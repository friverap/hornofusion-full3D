#!/usr/bin/env python3
"""Balances globales desde audit.csv (generado por mod_audit.f90, C0.2).

Chequeos (ids para xfail, prefijo 'audit:'):
  energy_balance : |dE_total - E_iny| <= etol * S_ext + htol * S_int
                   dE_total = (E_liq+E_sol+E_slag) final - inicial + E_gas_abs
                   E_iny    = fuentes externas (arco, radiacion, quimica,
                              paredes, ECS, adiciones, escoria, ...) menos lo
                              que se lleva el recorte de alpha
                   S_ext    = sum |fuentes externas por paso|
                   S_int    = sum |transferencias internas|: fusion
                              (E_melt_from_solid), congelacion (E_resolid),
                              interfase (E_iph_*), cierre residual
                   (auditoria 2, N-C3: antes la escala era
                   max(|dE|, |E_in|, sum|E_melt|) y en casos con fusion el
                   traspaso, 1e10-1e11 J, dejaba pasar errores de 1e8-1e9 J,
                   mayores que toda la energia del arco)
                   Con --config de solve_energy = false: no aplica.
  arc_budget     : E_arc_recibida / sum(P_arc*dt) = 1 ± tol (default 1e-3)
                   Objetivo post-C1.6/C1.7; hoy la sobre-inyección del MC y
                   el doble conteo por fase lo desvían.
  mass_liq       : |dm_liq - (m_melted - m_resolid - m_alpha_clip)| <= 0.5 %
                   (se omite con PASS informativo si no hubo fusión)

Uso: check_audit.py RUNDIR [--config CFG] [--xfail a,b] [--etol 0.01]
                      [--htol 1e-4] [--arctol 1e-3]
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg, read_config, safe_float


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--xfail", default="")
    ap.add_argument("--config", default=None)
    ap.add_argument("--htol", type=float, default=1e-4)
    ap.add_argument("--etol", type=float, default=0.01)
    ap.add_argument("--arctol", type=float, default=1e-3)
    ap.add_argument("--mtol", type=float, default=0.005)
    args = ap.parse_args()

    path = os.path.join(args.rundir, "audit.csv")
    if not os.path.exists(path):
        sys.exit(f"ERROR: no existe {path}")

    with open(path) as f:
        rows = [{k: safe_float(v) for k, v in r.items()}
                for r in csv.DictReader(f)]
    if len(rows) < 2:
        sys.exit("ERROR: audit.csv sin pasos (solo estado inicial)")

    first, last = rows[0], rows[-1]
    steps = rows[1:]
    chk = Checker(parse_xfail_arg(args.xfail))
    print(f"[audit] {args.rundir} ({len(steps)} pasos)")

    def total_E(r):
        return r["E_liq"] + r["E_sol"] + r["E_slag"]

    # -- energy_balance ------------------------------------------------------
    # dE del GAS: integral por paso del calor absorbido por su ecuación
    # (E_gas_abs; la forma T con rho(T) no tiene inventario de estado
    # consistente cuando la masa advecta). Fallback al inventario log si
    # la columna no existe (audits viejos).
    if "E_gas_abs" in last:
        # E_gas_abs es diferencia de estado por paso (T - T_old): ya
        # incluye el retiro de la interfase (poke a gas%T dentro del paso)
        dE_gas = sum(r["E_gas_abs"] for r in steps)
    else:
        dE_gas = last["E_gas"] - first["E_gas"]
    dE = total_E(last) - total_E(first) + dE_gas
    EXT_POS = ("E_src_liq_arc", "E_src_liq_rad", "E_src_liq_chem",
               "E_src_gas_arc", "E_src_gas_rad", "E_src_gas_chem",
               "E_arc_direct_sol", "E_slag_intercept", "E_rad_sol",
               "E_conv_defect", "E_chem_sol", "E_ecs_in", "E_flux_in",
               "E_charge_in", "E_slag_ox", "E_rad_foam", "E_slag_tclip",
               "E_mix_init")
    EXT_NEG = ("E_wall_conv", "E_slag_red", "E_alpha_clip")
    INTERNAL = ("E_melt_from_solid", "E_resolid", "E_iph_sol", "E_iph_gas",
                "E_iph_liq", "E_resid_closed")

    def ext(r):
        return (sum(r.get(k, 0.0) for k in EXT_POS)
                - sum(r.get(k, 0.0) for k in EXT_NEG))

    E_in = sum(ext(r) for r in steps)
    # (E_out_conv es DIAGNÓSTICO: la energía convectada a las celdas
    # outlet queda en su T — el déficit convectivo del hook ya incluye
    # esas caras; restarla doble-contaba: gap medido == E_out_conv.)
    S_ext = sum(abs(r.get(k, 0.0)) for r in steps for k in EXT_POS + EXT_NEG)
    S_int = sum(abs(r.get(k, 0.0)) for r in steps for k in INTERNAL)
    gap = dE - E_in
    allowed = args.etol * S_ext + args.htol * S_int
    energy_on = True
    if args.config:
        v = read_config(args.config).get("solve_energy", True)
        energy_on = not (str(v).strip().lower() in ("false", ".false.", "f", "0"))
    if not energy_on:
        print("  PASS  energy_balance  (solve_energy = false: no aplica)")
    else:
        ratio = abs(gap) / max(allowed, 1.0)
        chk.report("energy_balance", abs(gap) <= max(allowed, 1.0),
                   f"dE={dE:.4e} J, E_iny={E_in:.4e} J, gap={gap:.3e} J, "
                   f"permitido={allowed:.3e} J (etol {args.etol} x S_ext "
                   f"{S_ext:.3e} + htol {args.htol} x S_int {S_int:.3e}), "
                   f"gap/permitido={ratio:.3e}")

    # -- arc_budget ----------------------------------------------------------
    # E_mc_lost: beams que escapan por techo/paredes — pérdida física
    # CONTABILIZADA (el presupuesto exige saber a dónde va cada J)
    E_arc_in = sum(r["E_src_liq_arc"] + r["E_src_gas_arc"] +
                   r["E_arc_direct_sol"] + r.get("E_slag_intercept", 0.0) +
                   r.get("E_mc_lost", 0.0)
                   for r in steps)
    # Integración por Δt ENTRE filas: con audit_freq>1 el dt de la fila
    # solo cubre el último paso y subcuenta la energía disponible ~freq×
    # (los acumuladores del numerador sí se vuelcan completos por escritura)
    E_arc_avail = steps[0]["P_arc"] * steps[0]["dt"] + sum(
        steps[i]["P_arc"] * (steps[i]["time"] - steps[i - 1]["time"])
        for i in range(1, len(steps)))
    # LIMITACIÓN CONOCIDA (pendiente 2026-09): las identidades de este
    # checker están calibradas para audit_freq=1 (los gates del harness).
    # Con freq>1 la cuadratura de P_arc introduce ~4% sistemático y el
    # balance de energía mezcla columnas de distinta semántica de volcado
    # — los resultados son INFORMATIVOS, no gate.
    freq_gt1 = len(steps) > 1 and \
        (steps[1]["time"] - steps[0]["time"]) > 1.5 * steps[1]["dt"]
    if freq_gt1:
        print("  [WARN] audit_freq>1 detectado: energy_balance y "
              "arc_budget son INFORMATIVOS (identidades calibradas "
              "a freq=1)")
    if not energy_on:
        # sin energia nadie consume S_arc: el presupuesto no aplica
        print("  PASS  arc_budget  (solve_energy = false: no aplica)")
    elif E_arc_avail > 1.0:
        ratio = E_arc_in / E_arc_avail
        disc = sum(r["E_arc_discarded"] for r in steps)
        chk.report("arc_budget", abs(ratio - 1.0) <= args.arctol,
                   f"recibida/P_arc·dt = {ratio:.4f} (descartada "
                   f"{disc:.3e} J, tol {args.arctol})")
    else:
        print("  PASS  arc_budget  (sin potencia de arco: no aplica)")

    # -- mass_liq ------------------------------------------------------------
    dm_l = last["m_liq"] - first["m_liq"]
    m_melt = sum(r["m_melted"] for r in steps)
    m_res = sum(r["m_resolid"] for r in steps)
    m_clip = sum(r["m_alpha_clip"] for r in steps)
    m_fey = sum(r.get("m_fe_yield", 0.0) for r in steps)
    m_fer = sum(r.get("m_fe_return", 0.0) for r in steps)
    expected = m_melt - m_res - m_clip - m_fey + m_fer
    denom = max(abs(m_melt) + abs(m_res) + abs(m_clip), abs(dm_l))
    if denom < 1.0:
        print("  PASS  mass_liq  (sin fusión: no aplica)")
    else:
        err = abs(dm_l - expected) / denom
        chk.report("mass_liq", err <= args.mtol,
                   f"dm_liq={dm_l:.4e} vs fundido-resolid-clip="
                   f"{expected:.4e} kg (fundido={m_melt:.3e}, "
                   f"resolid={m_res:.3e}, clip={m_clip:.3e}), "
                   f"err rel={err:.3e}")

    chk.exit()


if __name__ == "__main__":
    main()
