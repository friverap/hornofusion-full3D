#!/usr/bin/env python3
"""Vigilante de corridas largas EAF3D (sep-2026, tras B1 v6-v10).

Lee audit.csv (+ run.log) de una corrida en marcha y comprueba invariantes
FÍSICOS que los gates del harness no ven en corridas cortas. Cada fallo
de B1 se habría detectado en los primeros minutos con estas reglas:

  v6/v7 churn        : re-solidificado/fundido ~1 con baño ~0 tras minutos
  v8 clip            : m_sol+m_liq cae (clip acumulado > tolerancia)
  v9 limitador       : clip por fila grande (drenaje recortado)
  v10 basura         : líquido sin fusión; masa total SUBE; T_l > 3000 K

Uso: python3 scripts/watch_run.py <dir_corrida> [--ref otro/audit.csv]
Salida: una línea de estado + líneas ALERT/WARN; exit 2 si hay ALERT,
1 si solo WARN, 0 si todo bien.
"""
import argparse
import csv
import glob
import os
import re
import subprocess
import sys
import time

C0 = (400.0 - 696.4) * 1809.0 + 247000.0   # dato e_l = cp_l*T + C0 (mod_melting_3d)
CP_L, CP_S = 696.4, 400.0


def num(v):
    v = v.strip()
    try:
        return float(v)
    except ValueError:      # exponente de 3 dígitos sin 'E' (CSV antiguos)
        return float(re.sub(r'(\d)([+-]\d{3})$', r'\1E\2', v))


def load(path):
    with open(path) as f:
        return [{k: num(v) for k, v in r.items()} for r in csv.DictReader(f)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--ref", help="audit.csv de referencia (misma config)")
    ap.add_argument("--stall-min", type=float, default=20.0,
                    help="minutos sin escribir audit => ALERT")
    a = ap.parse_args()

    alerts, warns = [], []
    A = lambda s: alerts.append(s)
    W = lambda s: warns.append(s)

    audit = os.path.join(a.rundir, "audit.csv")
    if not os.path.exists(audit):
        print(f"ALERT sin audit.csv en {a.rundir}")
        return 2
    rows = load(audit)
    if len(rows) < 2:
        print("WARN audit con <2 filas; nada que comprobar")
        return 1
    r0, r = rows[0], rows[-1]
    t = r["time"]

    # --- proceso vivo / estancado ---------------------------------------
    age_min = (time.time() - os.path.getmtime(audit)) / 60.0
    alive = subprocess.run(["pgrep", "-f", "bin/eaf3d_mpi"], capture_output=True).returncode == 0
    if not alive:
        A(f"no hay proceso eaf3d_mpi (audit escrito hace {age_min:.0f} min)")
    elif age_min > a.stall_min:
        A(f"audit sin actualizar hace {age_min:.0f} min con proceso vivo (estancado)")

    log = os.path.join(a.rundir, "run.log")
    if os.path.exists(log):
        with open(log, errors="replace") as f:
            tail = f.read()[-200000:]
        for pat in ("NaN-GUARD", "[ABORT]", "[ALPHA] AVISO"):
            if pat in tail:
                A(f"'{pat}' en run.log")

    # --- inventarios ------------------------------------------------------
    S = lambda c: sum(x[c] for x in rows[1:])
    m_liq, m_sol, m_gas = r["m_liq"], r["m_sol"], r["m_gas"]
    m0 = r0["m_sol"] + r0["m_liq"]
    m_in = S("m_ecs_in")
    steel = m_sol + m_liq
    d_steel = steel - m0 - m_in
    clip = S("m_alpha_clip")
    melt, resol = S("m_melted"), S("m_resolid")
    if d_steel > 1.0e-3 * m0:
        A(f"masa de acero CREADA: +{d_steel:.0f} kg ({d_steel/m0:.2%})")
    if -d_steel > 2.0e-3 * m0:
        A(f"masa de acero PERDIDA: {d_steel:.0f} kg ({-d_steel/m0:.2%}); clip acumulado {clip:.0f} kg")
    elif -d_steel > 5.0e-4 * m0:
        W(f"masa de acero baja {d_steel:.0f} kg; clip acumulado {clip:.0f} kg")
    if m_liq > melt + 1.0:
        A(f"líquido sin fusión: m_liq={m_liq:.1f} kg > fundido acumulado {melt:.1f} kg")
    if m_gas < 20.0 or m_gas > 500.0:
        W(f"masa de gas fuera de rango: {m_gas:.1f} kg")

    # --- temperaturas medias de inventario ----------------------------------
    T_l = ((r["E_liq"] / m_liq) - C0) / CP_L if m_liq > 1.0 else float("nan")
    T_s = r["E_sol"] / (m_sol * CP_S) if m_sol > 1.0 else float("nan")   # cota inferior (sin latente)
    if m_liq > 1.0:
        if T_l > 3000.0 or T_l < 1300.0:
            A(f"T_l media no física: {T_l:.0f} K")
        elif T_l < 1600.0:
            W(f"T_l media bajo el solidus: {T_l:.0f} K (líquido subenfriado)")
    if m_sol > 1.0 and (T_s > 2500.0 or T_s < 250.0):
        A(f"T_s media no física: {T_s:.0f} K")

    # --- tasas por fila (última ventana de 60 s) -------------------------------
    win = [x for x in rows if x["time"] >= t - 60.0]
    if len(win) > 2:
        mx_clip = max(x["m_alpha_clip"] for x in win)
        mx_melt = max(x["m_melted"] for x in win)
        if mx_clip > 20.0:
            A(f"clip por fila hasta {mx_clip:.1f} kg en los últimos 60 s (limitador no cierra)")
        if mx_melt > 100.0:
            A(f"fusión por fila hasta {mx_melt:.0f} kg (82 MW dan ~0.6 kg/fila)")
        dtw = min(x["dt"] for x in win)
        if dtw < 1.5e-3:
            W(f"dt cayó a {dtw:.2e} s")

    # --- acople P-V (Bug 15): p y velocidades maximas ------------------------
    # Se miran los MAXIMOS DE LA VENTANA, no la ultima fila: las excursiones
    # del acople duran decimas de segundo y se recuperan (B1 v15: 2 MPa y
    # 9.5 km/s entre t=34.6 y 37.7 s, invisibles en la fila final).
    if "p_max" in r:
        win_pv = [x for x in rows if x["time"] >= t - 300.0] or [r]
        pm = max(x["p_max"] for x in win_pv)
        ugm = max(x["u_gas_max"] for x in win_pv)
        ulm = max(x["u_liq_max"] for x in win_pv)
        n_pk = sum(1 for x in win_pv if x["p_max"] > 3.0e5)
        if n_pk:
            W(f"{n_pk} filas con p>3e5 en los últimos 300 s (pico {pm:.2e} Pa)")
        if pm >= 1.5e6:
            A(f"presión en la cota: p_max={pm:.3e} Pa (P_HYDRO_CAP 2e6) — acople P-V roto")
        # p_max identico entre filas = celda sellada (Bug 16). Se excluye el
        # valor EN LA COTA: ahi la igualdad la produce el clamp, no una celda
        # congelada (falso positivo en el regimen de Bug 19).
        if (1.0e4 < r["p_max"] < 0.99 * 2.0e6
                and any(abs(x["p_max"] - r["p_max"]) < 1e-9 * r["p_max"]
                        for x in rows[-200:-20] if x is not r)):
            A(f"p_max congelado en {r['p_max']:.4e} Pa (celda sellada, Bug 16)")
        elif pm > 3.0e5:
            W(f"p_max={pm:.3e} Pa (>3e5; hidrostática del baño ~1e5)")
        if ugm > 1000.0:
            A(f"gas hipersónico: |u_g|max={ugm:.0f} m/s")
        elif ugm > 300.0:
            W(f"|u_g|max={ugm:.0f} m/s (>300; low-Mach exige << 900)")
        # el liquido DISPERSO va a su velocidad de deriva (hasta
        # U_SETTLE_MAX = 50 m/s), asi que solo avisa por encima de eso
        if ulm >= 49.5:
            W(f"líquido en el cap de deriva: |u_l|max={ulm:.1f} m/s")

    # --- energía: nada por encima de lo inyectado -----------------------------
    P_int = sum(rows[i]["P_arc"] * (rows[i]["time"] - rows[i-1]["time"]) for i in range(1, len(rows)))
    E_tot = r["E_liq"] + r["E_sol"] + r["E_gas"] + r["E_slag"]
    E_tot0 = r0["E_liq"] + r0["E_sol"] + r0["E_gas"] + r0["E_slag"]
    if P_int > 0 and (E_tot - E_tot0) > 1.15 * P_int:
        A(f"energía creada: dE_inv={E_tot-E_tot0:.3e} J > 1.15·∫P_arc={P_int:.3e} J")

    # --- churn: fusión sin baño ---------------------------------------------------
    if t > 120.0 and melt > 500.0 and m_liq < 0.05 * melt:
        A(f"churn: fundido {melt:.0f} kg, re-solid {resol:.0f} kg, baño {m_liq:.0f} kg")

    # --- referencia ----------------------------------------------------------------
    ref_txt = ""
    if a.ref and os.path.exists(a.ref):
        ref = load(a.ref)
        rr = min(ref, key=lambda x: abs(x["time"] - t))
        if abs(rr["time"] - t) < 2.0:
            ref_txt = f" | ref m_liq={rr['m_liq']:.0f}"
            if rr["m_liq"] > 200 and abs(m_liq - rr["m_liq"]) > 0.5 * rr["m_liq"]:
                W(f"m_liq se aparta >50% de la referencia ({rr['m_liq']:.0f} kg)")

    ratio = resol / melt if melt > 0 else 0.0
    print(f"[watch {time.strftime('%H:%M')}] t={t:7.1f}s m_liq={m_liq:8.0f} m_sol={m_sol:6.0f} "
          f"acero Δ={d_steel:+7.0f} clipΣ={clip:7.1f} T_l~{T_l:5.0f}K resol/melt={ratio:.2f} "
          f"dt={r['dt']:.4f}{ref_txt}")
    for s in alerts:
        print("  ALERT", s)
    for s in warns:
        print("  WARN ", s)
    if not alerts and not warns:
        print("  OK    invariantes físicos en orden")
    return 2 if alerts else (1 if warns else 0)


if __name__ == "__main__":
    sys.exit(main())
