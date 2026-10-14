#!/usr/bin/env python3
"""Balances globales desde audit.csv (generado por mod_audit.f90, C0.2).

Chequeos (ids para xfail, prefijo 'audit:'):
  energy_balance : |dE_total - E_iny| <= etol (S_ext + S_gas) + htol S_int
                   dE_total = (E_liq+E_sol+E_slag) final - inicial + E_gas_abs
                   E_iny    = fuentes externas (arco, radiacion, quimica,
                              paredes, ECS, adiciones, escoria, ...) menos lo
                              que se lleva el recorte de alpha
                   S_ext    = sum |fuentes externas por paso|
                   S_int    = sum |traspasos entre fases condensadas|:
                              fusion, congelacion, interfase solido/liquido,
                              cierre residual (tolerancia htol)
                   S_gas    = sum |E_iph_gas| + |E_gas_abs| (tolerancia etol:
                              el libro del gas tiene cuadratura O(dT^2))
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
    # (auditoria 4, A4-4) identidad POR PASO desde el paso 2: el htol
    # acumulado existe para tragar el paso 1 (fusion instantanea con 5
    # outers: bath_fill 3.9e6 J, bed_flood 9.6e6) y despues admitia errores
    # del tamano del arco (melt_forced 95 %). Medido fuera del paso 1:
    # gap/S_int <= 1.6e-6 (bath_freeze), 4e-7 (bed_drain), 7e-8 (melt)
    ap.add_argument("--htol-step", type=float, default=5e-5)
    # libro del gas POR PASO: medido 4.7 % (bath_fill) y 6.5 % (slag_chem_flow)
    # de S_gas en pasos sueltos (acumulado 1 %); piso absoluto 1e-8 del
    # inventario total (noflow: 22 J sobre 1e10)
    ap.add_argument("--etol-step", type=float, default=0.1)
    # (A4-6) cota al defecto convectivo del gas fuera del venteo:
    # |E_conv_gas - E_out_conv| <= ctol_gas x S_gas
    # (A4-6) masa que la EOS reescribe sobre el presupuesto de masa del gas:
    # medido 13 % (cold, arc_melt, bath_freeze) a 42 % (bath_fill 36, bed_drain
    # 38, slag_chem_flow 42) en los bancos de dos fluidos; 79 % en bed_flood
    # (xfail). Es una propiedad del modelo low-Mach (gas fuera del acople por
    # F2.13/F2.31/fsat, COMP_SRC_CAP, lazo externo); el gate acota regresiones
    # (>= 50 %) y el juez es B1 (N-M4 abierto)
    ap.add_argument("--mgtol", type=float, default=0.5)
    # (A4-5) cierre radiativo: |sum rad fases + E_rad_wall| <= rtol_rad x sum|rad|
    ap.add_argument("--rtol-rad", type=float, default=0.05)
    # fraccion minima del arco ABSORBIDO que recibe el liquido (casos de
    # baño plano; auditoria 2, N-A2: con reparto por volumen era 0.069)
    ap.add_argument("--min-liq-arc", type=float, default=None)
    # etol SOLO sobre el libro del gas (auditoria 3, A3-6): medido 1.0 % de
    # S_gas en las corridas frias (lazo externo sin converger; 4e-6 en
    # outer_conv), 2x de margen. Antes etol x (S_ext + S_gas) permitia
    # errores del tamano del arco (melt_forced 101 %, cold_bucket2 5.5x).
    ap.add_argument("--etol", type=float, default=0.02)
    # fuentes EXTERNAS (arco, radiacion, quimica, carga, ECS): hooks exactos
    ap.add_argument("--xtol", type=float, default=1e-9)
    ap.add_argument("--arctol", type=float, default=1e-3)
    # masa: medido 1e-11..2.5e-8 (auditoria 3, M3-6; antes 5e-3 dejaba pasar
    # ~330 kg en melt_forced)
    ap.add_argument("--mtol", type=float, default=3e-6)
    # recorte de alpha (M3-5): fraccion maxima del fundido que puede perderse
    # por el clip auditado (medido 0 en dos fluidos; 3.5e-3 en la mezcla, xfail)
    ap.add_argument("--ctol", type=float, default=1e-6)
    # centinelas (M3-9): P_HYDRO_CAP y U_GAS_MAX nunca se tocan en regimen sano
    ap.add_argument("--p-cap", type=float, default=2.0e6)
    ap.add_argument("--u-gas-cap", type=float, default=300.0)
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
    if "E_gas_abs" in last and any(r["E_gas_abs"] != 0.0 for r in steps):
        # E_gas_abs es diferencia de estado por paso (T - T_old): ya
        # incluye el retiro de la interfase (poke a gas%T dentro del paso)
        dE_gas = sum(r["E_gas_abs"] for r in steps)
    else:
        # sin ecuacion de energia del gas (solve_flow = false: noflow_energy)
        # el gas solo recibe pokes de la interfase: inventario de estado
        # (auditoria 3, A3-6: el gap era exactamente E_iph_gas)
        dE_gas = last["E_gas"] - first["E_gas"]
    dE = total_E(last) - total_E(first) + dE_gas
    EXT_POS = ("E_src_liq_arc", "E_src_liq_rad", "E_src_liq_chem",
               "E_src_gas_arc", "E_src_gas_rad", "E_src_gas_chem",
               "E_arc_direct_sol", "E_slag_intercept", "E_rad_sol",
               "E_conv_defect", "E_chem_sol", "E_ecs_in", "E_flux_in",
               "E_charge_in", "E_slag_ox", "E_rad_foam", "E_slag_tclip",
               "E_mix_init")
    EXT_NEG = ("E_wall_conv", "E_slag_red", "E_alpha_clip")
    # traspasos entre fases CONDENSADAS (inventarios de estado exactos): htol
    # (A4-4) sin E_iph_liq: es -E_iph_sol (misma transferencia contada dos
    # veces inflaba S_int)
    INTERNAL = ("E_melt_from_solid", "E_resolid", "E_iph_sol",
                "E_resid_closed")
    # terminos del GAS: su libro (E_gas_abs, forma T con rho(p,T)) tiene error
    # de cuadratura O(dT^2) conocido (~1 % en encendidos) -> etol, como las
    # fuentes externas (auditoria 2, N-A1: el intercambio gas-liquido nuevo)
    GAS = ("E_iph_gas", "E_gas_abs")

    # Defecto convectivo: solo el del GAS si hay columnas por fase (auditoria
    # 2, N-A7). La energia del LIQUIDO usa los flujos exactos del transporte
    # de alpha con el transitorio alpha^n (continuidad restada): su inventario
    # cierra SIN defecto (+-400 J/paso en bed_drain) y el 'defecto' del hook
    # es el transporte de masa ya contado en el inventario; sumarlo creaba un
    # gap de 1e7-1e8 J en los bancos de lecho. El gas (alpha^{n+1}) si lo lleva.
    per_phase = "E_conv_gas" in last

    def ext(r):
        v = (sum(r.get(k, 0.0) for k in EXT_POS)
             - sum(r.get(k, 0.0) for k in EXT_NEG))
        if per_phase:
            v += r.get("E_conv_gas", 0.0) - r.get("E_conv_defect", 0.0)
        return v

    E_in = sum(ext(r) for r in steps)
    # (E_out_conv es DIAGNÓSTICO: la energía convectada a las celdas
    # outlet queda en su T — el déficit convectivo del hook ya incluye
    # esas caras; restarla doble-contaba: gap medido == E_out_conv.)
    S_ext = sum(abs(r.get(k, 0.0)) for r in steps for k in EXT_POS + EXT_NEG
                if not (per_phase and k == "E_conv_defect"))
    if per_phase:
        S_ext += sum(abs(r.get("E_conv_gas", 0.0)) for r in steps)
    S_int = sum(abs(r.get(k, 0.0)) for r in steps for k in INTERNAL)
    S_gas = sum(abs(r.get(k, 0.0)) for r in steps for k in GAS)
    gap = dE - E_in
    allowed = args.etol * S_gas + args.xtol * S_ext + args.htol * S_int
    energy_on = True
    if args.config:
        v = read_config(args.config).get("solve_energy", True)
        energy_on = not (str(v).strip().lower() in ("false", ".false.", "f", "0"))
    if not energy_on:
        print("  PASS  energy_balance  (solve_energy = false: no aplica)")
    else:
        # -- identidad por paso desde el paso 2 (A4-4) --------------------
        worst, wk = 0.0, 0
        for k in range(1, len(steps)):
            a, b = steps[k - 1], steps[k]
            if "E_gas_abs" in b and any(r["E_gas_abs"] != 0.0 for r in steps):
                dEg = b["E_gas_abs"]
            else:
                dEg = b["E_gas"] - a["E_gas"]
            gk = total_E(b) - total_E(a) + dEg - ext(b)
            sx = sum(abs(b.get(c, 0.0)) for c in EXT_POS + EXT_NEG
                     if not (per_phase and c == "E_conv_defect"))
            if per_phase:
                sx += abs(b.get("E_conv_gas", 0.0))
            sg = sum(abs(b.get(c, 0.0)) for c in GAS)
            si = sum(abs(b.get(c, 0.0)) for c in INTERNAL)
            alw = args.etol_step * sg + args.xtol * sx + args.htol_step * si
            etot = abs(total_E(b)) + abs(b.get("E_gas", 0.0))
            r = abs(gk) / max(alw, 1.0, 1e-8 * etot)
            if r > worst:
                worst, wk = r, int(b["step"])
        chk.report("energy_balance_step", worst <= 1.0,
                   f"peor paso {wk}: gap/permitido = {worst:.3e} "
                   f"(etol_step {args.etol_step} x S_gas + xtol {args.xtol} x S_ext + "
                   f"htol_step {args.htol_step} x S_int, piso 1e-8 E_tot; por paso desde el 2)")
        ratio = abs(gap) / max(allowed, 1.0)
        chk.report("energy_balance", abs(gap) <= max(allowed, 1.0),
                   f"dE={dE:.4e} J, E_iny={E_in:.4e} J, gap={gap:.3e} J, "
                   f"permitido={allowed:.3e} J (etol {args.etol} x S_gas "
                   f"{S_gas:.3e} + xtol {args.xtol} x S_ext {S_ext:.3e} + htol "
                   f"{args.htol} x S_int {S_int:.3e}), "
                   f"gap/permitido={ratio:.3e}")

    # -- mass_gas (A4-6): libro de MASA del gas ------------------------------
    # d m_gas = -venteo + volfix + reacciones + (lo que la EOS reescribe).
    # El ultimo termino es la no conservacion del modelo low-Mach (la densidad
    # la fija rho(p,T) y la fuente de compresibilidad del Poisson solo la
    # sigue hasta COMP_SRC_CAP / convergencia): se mide como residuo y se acota.
    # E_conv_gas - E_out_conv es, en forma T, cp T x ese residuo: el 'defecto
    # convectivo' del gas no es numerico, es la entalpia de la masa reescrita.
    flow_on = True
    if args.config:
        v = read_config(args.config).get("solve_flow", True)
        flow_on = not (str(v).strip().lower() in ("false", ".false.", "f", "0"))
    if "m_gas_out" in last and not flow_on:
        print("  PASS  mass_gas  (solve_flow = false: sin EOS ni Poisson, no aplica)")
    elif "m_gas_out" in last:
        dm_g = last["m_gas"] - first["m_gas"]
        m_out = sum(r["m_gas_out"] for r in steps)
        m_fix = sum(r.get("m_gas_volfix", 0.0) for r in steps)
        m_rxn = sum(r.get("m_gas_rxn", 0.0) for r in steps)
        resid = dm_g - (-m_out + m_fix + m_rxn)
        den_g = max(abs(dm_g), abs(m_out), abs(m_fix), abs(m_rxn), 1e-2 * abs(first["m_gas"]))
        chk.report("mass_gas", abs(resid) <= args.mgtol * den_g,
                   f"dm_gas={dm_g:.4e} vs -venteo+volfix+reacciones="
                   f"{-m_out + m_fix + m_rxn:.4e} kg (venteo {m_out:.3e}, volfix {m_fix:.3e}, "
                   f"rxn {m_rxn:.3e}); EOS reescribe {resid:.3e} kg = {abs(resid) / den_g:.3e} rel (max {args.mgtol})")
        if per_phase and energy_on:
            cg = sum(r.get("E_conv_gas", 0.0) for r in steps)
            oc = sum(r.get("E_out_conv", 0.0) for r in steps)
            print(f"  INFO  conv_gas  E_conv_gas - venteo = {cg - oc:.3e} J; / (cp 1200 x masa EOS {resid:.3e} kg) = "
                  f"{(cg - oc) / max(1200.0 * abs(resid), 1e-30):.1f} K equivalentes")
    # -- rad_closure (A4-5) --------------------------------------------------
    if energy_on:
        RAD = ("E_src_liq_rad", "E_src_gas_rad", "E_rad_sol", "E_rad_foam", "E_rad_wall")
        rsum = sum(r.get(c, 0.0) for r in steps for c in RAD)
        rabs = sum(abs(r.get(c, 0.0)) for r in steps for c in RAD)
        if rabs > 1.0:
            chk.report("rad_closure", abs(rsum) <= args.rtol_rad * rabs,
                       f"sum rad fases + pared = {rsum:.3e} J sobre {rabs:.3e} (max {args.rtol_rad})")

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

    if args.min_liq_arc is not None:
        L = sum(r.get("E_src_liq_arc", 0.0) for r in steps)
        G = sum(r.get("E_src_gas_arc", 0.0) for r in steps)
        S = sum(r.get("E_arc_direct_sol", 0.0) for r in steps)
        share = L / max(L + G + S, 1e-30)
        chk.report("arc_liquid_share", share >= args.min_liq_arc,
                   f"liquido {share:.3f} del arco absorbido (min {args.min_liq_arc}; "
                   f"liq {L:.3e}, gas {G:.3e}, solido {S:.3e} J)")

    # -- mass_liq ------------------------------------------------------------
    dm_l = last["m_liq"] - first["m_liq"]
    m_melt = sum(r["m_melted"] for r in steps)
    m_res = sum(r["m_resolid"] for r in steps)
    m_clip = sum(r["m_alpha_clip"] for r in steps)
    m_fey = sum(r.get("m_fe_yield", 0.0) for r in steps)
    m_fer = sum(r.get("m_fe_return", 0.0) for r in steps)
    expected = m_melt - m_res - m_clip - m_fey + m_fer
    # (M3-5) el clip no infla la escala
    denom = max(abs(m_melt) + abs(m_res), abs(dm_l))
    if denom < 1.0:
        print("  PASS  mass_liq  (sin fusión: no aplica)")
    else:
        err = abs(dm_l - expected) / denom
        chk.report("mass_liq", err <= args.mtol,
                   f"dm_liq={dm_l:.4e} vs fundido-resolid-clip="
                   f"{expected:.4e} kg (fundido={m_melt:.3e}, "
                   f"resolid={m_res:.3e}, clip={m_clip:.3e}), "
                   f"err rel={err:.3e}")
        # -- alpha_clip (M3-5): el recorte auditado tiene cota ----------------
        chk.report("alpha_clip", abs(m_clip) <= args.ctol * max(abs(m_melt), 1.0),
                   f"clip auditado {m_clip:.3e} kg sobre fundido {m_melt:.3e} kg "
                   f"(max {args.ctol} relativo)")

    # -- mass_sol (M3-6): inventario del solido ---------------------------
    # dm_sol = cargas + ECS - fundido + resolid - C oxidado (m_resid_closed es
    # subconjunto de m_melted)
    if "m_sol" in last:
        dm_s = last["m_sol"] - first["m_sol"]
        m_chg = sum(r.get("m_charge_in", 0.0) for r in steps)
        m_ecs = sum(r.get("m_ecs_in", 0.0) for r in steps)
        m_cox = sum(r.get("m_C_oxid", 0.0) for r in steps)
        exp_s = m_chg + m_ecs - m_melt + m_res - m_cox
        den_s = max(abs(m_chg) + abs(m_ecs) + abs(m_melt) + abs(m_res) + abs(m_cox), abs(dm_s))
        if den_s < 1.0:
            print("  PASS  mass_sol  (sin cambios del solido: no aplica)")
        else:
            err_s = abs(dm_s - exp_s) / den_s
            chk.report("mass_sol", err_s <= args.mtol,
                       f"dm_sol={dm_s:.4e} vs cargas+ECS-fundido+resolid-Cox="
                       f"{exp_s:.4e} kg, err rel={err_s:.3e}")

    # -- centinelas (M3-9): nunca se tocan en regimen sano -------------------
    if "p_max" in last and "u_gas_max" in last:
        pm = max(r["p_max"] for r in steps)
        um = max(r["u_gas_max"] for r in steps)
        chk.report("sentinel_p", pm < 0.99 * args.p_cap,
                   f"p_max {pm:.3e} Pa (P_HYDRO_CAP {args.p_cap:.1e})")
        chk.report("sentinel_gas", um < 0.999 * args.u_gas_cap,
                   f"u_gas_max {um:.1f} m/s (U_GAS_MAX {args.u_gas_cap:.0f})")

    chk.exit()


if __name__ == "__main__":
    main()
