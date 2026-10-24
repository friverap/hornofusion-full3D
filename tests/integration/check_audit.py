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
  alpha_clip_bounded : (solo con --clip-abs-max) |m_alpha_clip| <= techo
                   absoluto en kg; techo no enmascarado de un alpha_clip en
                   xfail (auditoria 15, M15-4)

Uso: check_audit.py RUNDIR [--config CFG] [--xfail a,b] [--etol 0.01]
                      [--htol 1e-4] [--arctol 1e-3]
"""
import argparse, math
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import cfg_bool, Checker, parse_xfail_arg, read_config, safe_float


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
    # medido (tests/out, 17-oct-2026) 0.6 % (slag_chem_flow) a 33 % (arc_slag
    # 0.327, melt_forced 0.324, bed_flood 0.235, arc_melt 0.13, bath_fill
    # 0.10) en los bancos de dos fluidos; pocket_rise 0.44. Es una propiedad
    # del modelo low-Mach (gas fuera del acople por F2.13/F2.31/fsat,
    # COMP_SRC_CAP, lazo externo); el gate acota regresiones (>= 50 %) y el
    # juez es B1 (N-M4 abierto). Unico xfail con causa: bath_fill_mix 0.57
    # (bed_flood y melt_forced salieron del xfail con N-M4, auditoria 6)
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
    # (M4-14) medido <= 1.5e-6 (1e-15 en frio)
    ap.add_argument("--arctol", type=float, default=1e-5)
    # (M4-14) E_mc_lost (beams que escapan) <= esta fraccion del arco: medido 0.12-0.25
    ap.add_argument("--mc-lost-max", type=float, default=0.4)
    # (M4-16) regimen acotado fuera de los bancos de bano: medido p <= 1.8e5 (bed_flood), gas <= 145 (bed_drain)
    ap.add_argument("--regime-p", type=float, default=5.0e5)
    ap.add_argument("--regime-gas", type=float, default=200.0)
    # masa: medido <= 3e-11 en toda la matriz (auditoria 4, B4-20; antes 3e-6,
    # y 5e-3 antes de M3-6 dejaba pasar ~330 kg en melt_forced)
    ap.add_argument("--mtol", type=float, default=1e-9)
    # (auditoria 5, M5-7) piso RELATIVO AL INVENTARIO: sin fusion (B4-22) la
    # identidad se mide contra 1 kg y dm_liq es el redondeo de la suma del
    # inventario (m_liq 2.7e5 kg: ulp 5.8e-11, medido 11-14 ulp = 8.1e-10 en
    # arc_noscrap_n1, 7.6e-10 en bath_test_n4, a 1.2x del gate). 1e-14 del
    # inventario = ~45 ulp; no afecta a los casos con fusion (mtol x fundido)
    ap.add_argument("--mtol-inv", type=float, default=1e-14)
    # recorte de alpha (M3-5): fraccion maxima del fundido que puede perderse
    # por el clip auditado (medido 0 en dos fluidos; 3.5e-3 en la mezcla, xfail)
    ap.add_argument("--ctol", type=float, default=1e-6)
    # (auditoria 15, M15-4) techo ABSOLUTO del clip [kg] para los casos cuyo
    # alpha_clip esta en xfail: el xfail tapa la cota estricta, este check no
    # (sin el, una regresion del derrame a toneladas seguia diciendo XFAIL)
    ap.add_argument("--clip-abs-max", type=float, default=None)
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
    # (auditoria 4, B4-24) el LIBRO del gas (E_gas_abs) existe cuando se
    # resuelve la energia del gas: solve_energy con flujo de dos fluidos (o
    # mezcla). Lo decide el config; sin --config, los datos (audits viejos).
    # (oct-2026) el redondeo de la SUMA del inventario crece como sqrt(N) eps
    # (caminata aleatoria sobre N celdas): con la malla fina de arc_slag
    # (18432 celdas) 1e-14 quedaba por debajo de su propio ruido (n1: 5e-9 kg
    # sobre 2.7e5, sin derrame ni clip, m_liq oscilando +-3e-9 por paso). La
    # tolerancia de redondeo es max(--mtol-inv, sqrt(N) eps).
    mtol_inv = args.mtol_inv
    if args.config:
        _c = read_config(args.config)
        try:
            _n = float(_c.get("nr", 18)) * float(_c.get("ntheta", 36)) * float(_c.get("nz", 24))
            mtol_inv = max(mtol_inv, math.sqrt(_n) * 2.22e-16)
        except (TypeError, ValueError):
            pass
    if args.config:
        cfgd = read_config(args.config)
        gas_book = (cfg_bool(cfgd, "solve_energy") and cfg_bool(cfgd, "solve_flow")
                    and cfg_bool(cfgd, "solve_multiphase"))
    else:
        gas_book = "E_gas_abs" in last and any(r["E_gas_abs"] != 0.0 for r in steps)
    if gas_book and "E_gas_abs" not in last:
        sys.exit("ERROR: el config resuelve la energia del gas pero el audit no trae E_gas_abs")
    if gas_book:
        # E_gas_abs es diferencia de estado por paso (T - T_old): ya
        # incluye el retiro de la interfase (poke a gas%T dentro del paso)
        dE_gas = sum(r["E_gas_abs"] for r in steps)
    else:
        # sin ecuacion de energia del gas (solve_flow = false: noflow_energy)
        # el gas solo recibe pokes de la interfase: inventario de estado
        # (auditoria 3, A3-6: el gap era exactamente E_iph_gas)
        dE_gas = last["E_gas"] - first["E_gas"]
    dE = total_E(last) - total_E(first) + dE_gas
    EXT_POS = ("E_steel_deficit", "E_src_liq_arc", "E_src_liq_rad", "E_src_liq_chem",
               "E_src_gas_arc", "E_src_gas_rad", "E_src_gas_chem",
               "E_arc_direct_sol", "E_slag_intercept", "E_rad_sol",
               "E_conv_defect", "E_chem_sol", "E_ecs_in", "E_flux_in",
               "E_charge_in", "E_slag_ox", "E_rad_foam", "E_slag_tclip",
               "E_mix_init")
    # (M4-13) E_gas_volfix = inv(alpha_nueva) - inv(alpha_vieja) del INVENTARIO
    # log del gas al reescribir alpha_g (volfix, flotacion de escoria): solo
    # entra cuando dE_gas es ese inventario (sin libro E_gas_abs). Con el libro
    # (alpha^{n+1}, T - T_old) el gas creado aparece a T_old sin calor absorbido
    # y la columna no pertenece a la identidad.
    gas_inv = not gas_book
    if gas_inv:
        EXT_POS = EXT_POS + ("E_gas_volfix",)
    # (Plan H, P6) E_slag_clip: energia de la escoria condensada recortada
    EXT_NEG = ("E_wall_conv", "E_slag_red", "E_alpha_clip", "E_slag_clip")
    # traspasos entre fases CONDENSADAS (inventarios de estado exactos): htol
    # (A4-4) sin E_iph_liq: es -E_iph_sol (misma transferencia contada dos
    # veces inflaba S_int)
    INTERNAL = ("E_melt_from_solid", "E_resolid", "E_iph_sol",
                "E_resid_closed")
    # terminos del GAS: su libro (E_gas_abs, forma T con rho(p,T)) tiene error
    # de cuadratura O(dT^2) conocido (~1 % en encendidos) -> etol, como las
    # fuentes externas (auditoria 2, N-A1: el intercambio gas-liquido nuevo)
    # E_slag_gas: poke a gas%T con capacidad alpha*rho(T)*cp (forma T) frente
    # al inventario log: error de cuadratura O(dT^2) tambien (M4-13)
    GAS = ("E_iph_gas", "E_gas_abs", "E_slag_gas")

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
    # (auditoria 18, A18-3) los AJUSTES no fisicos de la escoria (equilibrio
    # de trazas, recorte) entran a la identidad pero NO ensanchan la
    # tolerancia y tienen techo propio (abajo, slag_adjust_bounded)
    NO_SCALE = ("E_slag_tclip", "E_slag_clip")
    S_ext = sum(abs(r.get(k, 0.0)) for r in steps for k in EXT_POS + EXT_NEG
                if not (per_phase and k == "E_conv_defect") and k not in NO_SCALE)
    if per_phase:
        S_ext += sum(abs(r.get("E_conv_gas", 0.0)) for r in steps)
    S_int = sum(abs(r.get(k, 0.0)) for r in steps for k in INTERNAL)
    S_gas = sum(abs(r.get(k, 0.0)) for r in steps for k in GAS)
    gap = dE - E_in
    allowed = args.etol * S_gas + args.xtol * S_ext + args.htol * S_int
    energy_on = True
    if args.config:
        energy_on = cfg_bool(read_config(args.config), "solve_energy")
    if not energy_on and S_ext + S_int < 1.0:
        print("  PASS  energy_balance  (solve_energy = false y sin fuentes: no aplica)")
    else:
        # (M4-13) con solve_energy = false pero fuentes (quimica, escoria) la
        # identidad sigue valiendo sobre los INVENTARIOS de estado
        # -- identidad por paso desde el paso 2 (A4-4) --------------------
        worst, wk = 0.0, 0
        for k in range(1, len(steps)):
            a, b = steps[k - 1], steps[k]
            # (B5-17) el mismo libro del gas que la acumulada (lo decide el
            # config, B4-24; antes aqui lo decidian los datos)
            if gas_book:
                dEg = b["E_gas_abs"]
            else:
                dEg = b["E_gas"] - a["E_gas"]
            gk = total_E(b) - total_E(a) + dEg - ext(b)
            sx = sum(abs(b.get(c, 0.0)) for c in EXT_POS + EXT_NEG
                     if not (per_phase and c == "E_conv_defect") and c not in NO_SCALE)
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
        # (WS-K3, C-096..C-098) residuo del enunciado discreto que deja en pie
        # la sub-relajacion de T (alpha_T < 1): energia que el inventario
        # pierde o gana sin termino fisico. DIAGNOSTICO: no entra a la
        # identidad (la cerraria escondiendo la perdida), solo la atribuye.
        if "E_relax_liq" in last:
            rl = sum(r.get("E_relax_liq", 0.0) for r in steps)
            rg = sum(r.get("E_relax_gas", 0.0) for r in steps)
            print(f"  INFO  energy_relax  residuo del enunciado (sub-relajacion): liquido {rl:.3e} J, "
                  f"gas {rg:.3e} J; gap - residuos = {gap - rl - rg:.3e} J (gap {gap:.3e} J)")
    # (auditoria 18, A18-3) techo POR PASO de los ajustes no fisicos de la
    # escoria: |E_slag_tclip| + |E_slag_clip| de un paso <= 1e-4 del
    # inventario de la escoria (medido: arc_melt_slag 6e-6 en el peor paso,
    # trazas que se extienden por el lecho y toman la T local; arc_slag 10 s
    # ~1e-9). El caso de 5e11 J en un paso (paso 579, ~20 veces el inventario)
    # lo habria cerrado la identidad sin este techo
    if any("E_slag_tclip" in r for r in steps):
        esl = max(abs(r.get("E_slag", 0.0)) for r in rows)
        if esl > 0.0:
            worst_adj, ws = 0.0, 0
            for r in steps:
                a_ = abs(r.get("E_slag_tclip", 0.0)) + abs(r.get("E_slag_clip", 0.0))
                if a_ > worst_adj:
                    worst_adj, ws = a_, int(r.get("step", 0))
            chk.report("slag_adjust_bounded", worst_adj <= 1e-4 * esl,
                       f"peor paso {ws}: |E_slag_tclip| + |E_slag_clip| = {worst_adj:.3e} J "
                       f"sobre E_slag {esl:.3e} J (max 1e-4 por paso)")
        # (auditoria 19, M19-C3) y ACUMULADO frente a las fuentes externas del
        # tramo: el techo por inventario admitia mas que el arco de un paso
        # (2.2e6 J frente a 8e5). Medido: arc_melt_slag 2.2e-4 de S_ext, el
        # resto <= 1e-5; piso de 1 J para bancos sin fuentes (slag_rest)
        adj_cum = sum(abs(r.get("E_slag_tclip", 0.0)) + abs(r.get("E_slag_clip", 0.0)) for r in steps)
        chk.report("slag_adjust_cum", adj_cum <= 1e-2 * S_ext + 1.0,
                   f"|E_slag_tclip| + |E_slag_clip| acumulado {adj_cum:.3e} J sobre S_ext {S_ext:.3e} J "
                   f"(max 1e-2 S_ext + 1 J)")

    # -- mass_gas (A4-6): libro de MASA del gas ------------------------------
    # d m_gas = -venteo + volfix + reacciones + (lo que la EOS reescribe).
    # El ultimo termino es la no conservacion del modelo low-Mach (la densidad
    # la fija rho(p,T) y la fuente de compresibilidad del Poisson solo la
    # sigue hasta COMP_SRC_CAP / convergencia): se mide como residuo y se acota.
    # E_conv_gas - E_out_conv es, en forma T, cp T x ese residuo: el 'defecto
    # convectivo' del gas no es numerico, es la entalpia de la masa reescrita.
    flow_on = True
    if args.config:
        flow_on = cfg_bool(read_config(args.config), "solve_flow")
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
            cp_g = float(read_config(args.config).get("cp_gas", 1000.0)) if args.config else 1000.0   # (B6-8) default del codigo: CP_GAS = 1000
            print(f"  INFO  conv_gas  E_conv_gas - venteo = {cg - oc:.3e} J; / (cp {cp_g:.0f} x masa EOS {resid:.3e} kg) = "
                  f"{(cg - oc) / max(cp_g * abs(resid), 1e-30):.1f} K equivalentes")
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
    # (auditoria 5, B5-26) la primera fila cubre desde el estado inicial
    # (fila 0), no un solo dt: con audit_freq > 1 y la disposicion de B4-4
    # (todo snapshot cierra el intervalo) arc_budget daba 1.25
    E_arc_avail = steps[0]["P_arc"] * (steps[0]["time"] - first["time"]) + sum(
        steps[i]["P_arc"] * (steps[i]["time"] - steps[i - 1]["time"])
        for i in range(1, len(steps)))
    # LIMITACIÓN CONOCIDA (pendiente 2026-09): las identidades de este
    # checker están calibradas para audit_freq=1 (los gates del harness).
    # Con freq>1 la cuadratura de P_arc introduce ~4% sistemático y el
    # balance de energía mezcla columnas de distinta semántica de volcado
    # — los resultados son INFORMATIVOS, no gate.
    # (B5-26) lo decide el config si lo hay; si no, CUALQUIER par de filas
    # consecutivas separado mas de un paso (antes solo el primero, y con la
    # disposicion de B4-4 ese par puede ser de un solo paso)
    if args.config:
        freq_gt1 = int(float(read_config(args.config).get("audit_freq", 1))) > 1
    else:
        freq_gt1 = any((steps[i]["time"] - steps[i - 1]["time"]) > 1.5 * steps[i]["dt"]
                       for i in range(1, len(steps)))
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
                   f"recibida/P_arc·dt = {ratio:.7f} (descartada "
                   f"{disc:.3e} J, tol {args.arctol})")
        lost = sum(r.get("E_mc_lost", 0.0) for r in steps)
        chk.report("mc_lost_bound", lost <= args.mc_lost_max * E_arc_avail,
                   f"E_mc_lost {lost:.3e} J = {lost / E_arc_avail:.3f} del arco (max {args.mc_lost_max})")
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
    # (auditoria 19, M19-C2) acero creado por el deficit de congelacion del
    # condensado: columna propia, positiva, con techo propio (abajo)
    m_def = sum(r.get("m_steel_deficit", 0.0) for r in steps)
    expected = m_melt - m_res - m_clip - m_fey + m_fer + m_def
    # (M3-5) el clip no infla la escala
    # (auditoria 4, B4-22) SIEMPRE: con menos de 1 kg de movimiento la
    # identidad se mide contra 1 kg (absoluta); antes se saltaba y un
    # liquido que cambiaba 0.9 kg sin fusion no lo veia nadie
    denom = max(abs(m_melt) + abs(m_res), abs(dm_l), 1.0)
    err = abs(dm_l - expected) / denom
    # (M5-7) permitido = mtol x denom + mtol_inv x inventario (redondeo)
    inv_l = max(abs(first["m_liq"]), abs(last["m_liq"]))
    tol_l = args.mtol + mtol_inv * inv_l / denom
    chk.report("mass_liq", err <= tol_l,
               f"dm_liq={dm_l:.4e} vs fundido-resolid-clip="
               f"{expected:.4e} kg (fundido={m_melt:.3e}, "
               f"resolid={m_res:.3e}, clip={m_clip:.3e}), "
               f"err rel={err:.3e} (max {tol_l:.3e})")
    # -- alpha_clip (M3-5): el recorte auditado tiene cota --------------------
    # (auditoria 21, B21-C1) cota sobre la suma de |clip| por paso: el recorte
    # final mete clip NEGATIVO cuando a_pre < 0 (congelacion + salida) y con
    # la suma con signo un +X y un -X se cancelaban
    m_clip_abs = sum(abs(r["m_alpha_clip"]) for r in steps)
    chk.report("alpha_clip", m_clip_abs <= args.ctol * max(abs(m_melt), 1.0),
               f"sum|clip| auditado {m_clip_abs:.3e} kg (neto {m_clip:.3e}) sobre fundido "
               f"{m_melt:.3e} kg (max {args.ctol} relativo)")
    if args.clip_abs_max is not None:
        chk.report("alpha_clip_bounded", m_clip_abs <= args.clip_abs_max,
                   f"sum|clip| auditado {m_clip_abs:.3e} kg (techo {args.clip_abs_max:.1e} kg)")
    if any("m_steel_deficit" in r for r in steps):
        chk.report("steel_deficit_bounded", m_def <= args.ctol * max(abs(m_melt) + abs(m_res), 1.0),
                   f"acero creado por deficit de congelacion {m_def:.3e} kg (max {args.ctol} relativo)")

    # (auditoria 19, M19-1) techo del acarreo de compresibilidad DESCARTADO
    # (m_gas_ccdrop): sin el, una regresion que descarte toneladas de demanda
    # pasaba la matriz. Medido: <= 0.7 % del inventario de gas (transitorio de
    # arranque del gas a 300 K sobre el talon a 1850 K en los bancos de
    # escoria; ~0 en el resto)
    if any("m_gas_ccdrop" in r for r in steps):
        ccd = sum(abs(r.get("m_gas_ccdrop", 0.0)) for r in steps)
        mg = max(abs(r.get("m_gas", 0.0)) for r in rows)
        chk.report("ccdrop_bounded", ccd <= 2e-2 * max(mg, 1e-30) + 1e-12,
                   f"|m_gas_ccdrop| acumulado {ccd:.3e} kg sobre m_gas {mg:.3e} kg (max 2e-2)")

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
        # (B4-22) siempre, absoluta contra 1 kg si no hay movimiento
        err_s = abs(dm_s - exp_s) / max(den_s, 1.0)
        inv_s = max(abs(first["m_sol"]), abs(last["m_sol"]))
        tol_s = args.mtol + mtol_inv * inv_s / max(den_s, 1.0)
        chk.report("mass_sol", err_s <= tol_s,
                   f"dm_sol={dm_s:.4e} vs cargas+ECS-fundido+resolid-Cox="
                   f"{exp_s:.4e} kg, err rel={err_s:.3e} (max {tol_s:.3e})")

    # -- mass_slag (auditoria 21, M21-C1): inventario de la escoria ----------
    # dm_slag = FeO oxidado - FeO reducido - C consumido + adiciones - clip
    # (misma identidad que check_slag_chem slag_mass; ECS, cesta y sort no
    # cambian m_sl). Antes solo la verificaban los checkers de banco en
    # algunas corridas: ecs_slag_n12, arc_slag_n12, ... quedaban sin ella
    if "m_slag" in last and max(abs(first["m_slag"]), abs(last["m_slag"])) > 0.0:
        MW_FE, MW_FEO, MW_C = 0.05585, 0.07185, 0.012   # = mod_slag_chemistry
        dm_x = last["m_slag"] - first["m_slag"]
        feo_ox = sum(r.get("m_fe_yield", 0.0) for r in steps) * MW_FEO / MW_FE
        feo_red = sum(r.get("m_fe_return", 0.0) for r in steps) * MW_FEO / MW_FE
        flux_x = sum(r.get("m_flux_in", 0.0) for r in steps)
        sclip_x = sum(r.get("m_slag_clip", 0.0) for r in steps)
        exp_x = feo_ox - feo_red - feo_red * MW_C / MW_FEO + flux_x - sclip_x
        den_x = max(abs(feo_ox) + abs(feo_red) + abs(flux_x) + abs(sclip_x), abs(dm_x), 1.0)
        inv_x = max(abs(first["m_slag"]), abs(last["m_slag"]))
        tol_x = args.mtol + mtol_inv * inv_x / den_x
        err_x = abs(dm_x - exp_x) / den_x
        chk.report("mass_slag", err_x <= tol_x,
                   f"dm_slag={dm_x:.4e} vs FeO ox-red-C+adic-clip={exp_x:.4e} kg, "
                   f"err rel={err_x:.3e} (max {tol_x:.3e})")

    # -- centinelas (M3-9): nunca se tocan en regimen sano -------------------
    if "p_max" in last and "u_gas_max" in last:
        pm = max(r["p_max"] for r in steps)
        um = max(r["u_gas_max"] for r in steps)
        chk.report("sentinel_p", pm < 0.99 * args.p_cap,
                   f"p_max {pm:.3e} Pa (P_HYDRO_CAP {args.p_cap:.1e})")
        chk.report("sentinel_gas", um < 0.999 * args.u_gas_cap,
                   f"u_gas_max {um:.1f} m/s (U_GAS_MAX {args.u_gas_cap:.0f})")
        # (M4-16) regimen acotado: mucho antes de las centinelas
        chk.report("regime_p", pm <= args.regime_p, f"p_max {pm:.3e} Pa (max {args.regime_p:.1e})")
        chk.report("regime_gas", um <= args.regime_gas, f"u_gas_max {um:.1f} m/s (max {args.regime_gas:.0f})")

    chk.exit()


if __name__ == "__main__":
    main()
