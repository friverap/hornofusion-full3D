#!/usr/bin/env python3
"""Química conservativa (C3.3): balances elementales de O y C.

Sobre una corrida SIN flujo (chem_test): entre el primer y último snapshot,
  O: O_gas + O desplazado por dilucion se conserva
  C: la masa que pierde el solido = carbono oxidado (m_C_oxid del audit)
     = C_gas + C desplazado
  con O_gas = sum(alpha_g*rho_g*[Y_O2 + Y_CO*16/28 + Y_CO2*32/44]*V),
  C_gas = sum(alpha*rho*[Y_CO*12/28 + Y_CO2*12/44]*V). La densidad del gas
  la fija la EOS: la masa que la reaccion aporta al gas (el carbono) desplaza
  mezcla (termino -Y_k S_gas, auditoria M14; columnas m_dil_* del audit).
Tolerancia holgada (default 5%): rho_gas(T) introduce deriva de inventario
al calentarse el gas (agujero EOS documentado).

(auditoria 5, M5-5) --slag: identidades con la quimica de la escoria y el gas
destruido. El gas que crea la restriccion de volumen o la flotacion de la
escoria no trae especies (Y diluida) y el destruido se las lleva (columnas
m_vf_*). Con FeO formado (m_fe_yield, consume O2 del gas) y reducido
(m_fe_return, devuelve CO al gas):
  O_1 + O_dil + O_vf - O_0 = (16/55.85) (m_fe_return - m_fe_yield)
  C_1 + C_dil + C_vf - C_0 = m_C_oxid + (12/55.85) m_fe_return
Solo vale sin flujo (solve_flow = false): con la EOS reescribiendo masa del
gas (N-M4) el inventario elemental no es una identidad.

Uso: check_chem.py RUNDIR --config CFG [--rtol 1e-7] [--slag]
"""
import argparse, csv, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import cell_volumes, load_snapshot, read_config, snapshots, cfg_bool


RHO_REF = 1.2      # cfg%rho_gas por defecto
T_REF = 300.0      # T_RHO_GAS_REF del codigo (fija; no T_ambient)


P0 = 101325.0       # P0_THERMO del codigo; la presion del snapshot es manometrica


def rho_gas(T, p):
    # la MISMA EOS que gas_eos (mod_constants, M25): rho(P0 + p, T)
    return (RHO_REF * T_REF / np.maximum(T, 100.0)
            * np.maximum(P0 + p, 0.05 * P0) / P0)


def elements(path):
    f, mesh, meta = load_snapshot(path)
    vol = cell_volumes(mesh)
    # (auditoria 5, M5-5) la densidad con la que el CODIGO lleva las especies
    # (/restart/rho_gas): sin flujo ni energia (slag_chem_test) rho_g queda en
    # su valor inicial aunque la escoria caliente el gas, y la EOS evaluada
    # con la T del snapshot restaba 0.9 kg de O (5.6 %) que nunca salieron
    import h5py
    with h5py.File(path, "r") as h:
        if "restart" in h and "rho_gas" in h["restart"]:
            rho = h["restart"]["rho_gas"][:]
        else:
            rho = rho_gas(f["T_gas"], f["pressure"])
    arho = f["alpha_gas"] * rho
    f["_rho_gas"] = rho
    O = float(np.sum(arho * (f["Y_O2"] + f["Y_CO"] * 16 / 28 +
                             f["Y_CO2"] * 32 / 44) * vol))
    C = float(np.sum(arho * (f["Y_CO"] * 12 / 28 + f["Y_CO2"] * 12 / 44) * vol))
    return O, C, f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--config", required=True)
    # medido O 1.2e-12, C 1.7e-10 (auditoria 2, N-A6: antes 5 %)
    ap.add_argument("--rtol", type=float, default=1e-7)
    ap.add_argument("--slag", action="store_true",
                    help="incluir la quimica de la escoria (FeO) y el gas destruido")
    args = ap.parse_args()

    global RHO_REF
    cfg = read_config(args.config)
    RHO_REF = float(cfg.get("rho_gas", 1.2))
    # (bajo B6-11) --slag solo vale SIN flujo (docstring): con flujo la EOS
    # reescribe la masa del gas y el inventario elemental no es identidad
    if args.slag and cfg_bool(cfg, "solve_flow", default=True):
        print("FAIL: check_chem --slag solo vale con solve_flow = false (con flujo la EOS reescribe el gas)")
        sys.exit(1)
    files = snapshots(args.rundir)
    O0, C0, f0 = elements(files[0])
    O1, C1, f1 = elements(files[-1])

    # columnas del audit (si existen): dilucion y carbono oxidado
    dil = {"m_dil_O2": 0.0, "m_dil_CO": 0.0, "m_dil_CO2": 0.0, "m_C_oxid": 0.0,
           "m_vf_O2": 0.0, "m_vf_CO": 0.0, "m_vf_CO2": 0.0,
           "m_fe_yield": 0.0, "m_fe_return": 0.0}
    apath = os.path.join(args.rundir, "audit.csv")
    have_audit = False
    if os.path.exists(apath):
        with open(apath) as fa:
            rows = list(csv.DictReader(fa))[1:]
        if rows and "m_dil_O2" in rows[0]:
            have_audit = True
            for r in rows:
                for kk in dil:
                    dil[kk] += float(r.get(kk, 0.0))
    O_dil = dil["m_dil_O2"] + dil["m_dil_CO"] * 16 / 28 + dil["m_dil_CO2"] * 32 / 44
    C_dil = dil["m_dil_CO"] * 12 / 28 + dil["m_dil_CO2"] * 12 / 44
    # (M5-5) especies que salieron con el gas destruido (volfix, escoria,
    # cesta, ECS): mismo signo que la dilucion (salen del inventario)
    O_dil += dil["m_vf_O2"] + dil["m_vf_CO"] * 16 / 28 + dil["m_vf_CO2"] * 32 / 44
    C_dil += dil["m_vf_CO"] * 12 / 28 + dil["m_vf_CO2"] * 12 / 44
    # quimica de la escoria (MW del codigo: Fe 55.85, O 16, C 12)
    O_slag = C_slag = 0.0
    if args.slag:
        O_slag = (dil["m_fe_return"] - dil["m_fe_yield"]) * 16.0 / 55.85
        C_slag = dil["m_fe_return"] * 12.0 / 55.85

    print(f"[chem] {args.rundir}" + (" (con escoria)" if args.slag else ""))
    ok = True

    errO = abs(O1 + O_dil - O0 - O_slag) / max(O0, 1e-12)
    print(f"  {'PASS' if errO <= args.rtol else 'FAIL'}  O_conservation  "
          f"O: {O0:.4e} -> {O1:.4e} + desplazado {O_dil:.4e} kg"
          + (f" (FeO: {O_slag:+.4e})" if args.slag else "")
          + f" (err {errO:.3e})")
    ok = ok and errO <= args.rtol

    dC_gas = C1 - C0 + C_dil
    if args.slag:
        # el C que entra al gas: carbono del acero oxidado + el de la escoria
        # que reduce FeO (CO); m_C_oxid puede ser 0 (sin chatarra)
        C_src = dil["m_C_oxid"] + C_slag
        errCg = abs(dC_gas - C_src) / max(C_src, 1e-12)
        okCg = errCg <= args.rtol
        print(f"  {'PASS' if okCg else 'FAIL'}  C_conservation  C en gas + desplazado "
              f"{dC_gas:.4e} vs oxidado {dil['m_C_oxid']:.4e} + reduccion FeO "
              f"{C_slag:.4e} kg (err {errCg:.3e})")
        ok = ok and okCg
        if dil["m_fe_yield"] <= 1e-6 or dil["m_fe_return"] <= 1e-6:
            print("  FAIL  reaccion_activa  sin oxidacion o sin reduccion de FeO: "
                  "test inconcluyente")
            sys.exit(1)
        sY = float(np.max(f1["Y_O2"] + f1["Y_CO"] + f1["Y_CO2"]))
        okY = sY <= 1.0 + 1e-9
        print(f"  {'PASS' if okY else 'FAIL'}  suma_Y  max(Y_O2+Y_CO+Y_CO2) = {sY:.6f}")
        ok = ok and okY
        sys.exit(0 if ok else 1)
    if have_audit:
        # M15: el carbono oxidado SALE del acero. La masa de solido perdida
        # (sin fusion en chem_test) debe ser exactamente m_C_oxid; y el C que
        # aparece en el gas (mas el desplazado por dilucion) es ese mismo C.
        ms0 = float(np.sum(f0["mass_solid"])); ms1 = float(np.sum(f1["mass_solid"]))
        errC = abs((ms0 - ms1) - dil["m_C_oxid"]) / max(dil["m_C_oxid"], 1e-12)
        okC = errC <= 1e-9 and dil["m_C_oxid"] > 0.0
        print(f"  {'PASS' if okC else 'FAIL'}  C_sale_del_solido  dm_solido "
              f"{ms0 - ms1:.6e} vs m_C_oxid {dil['m_C_oxid']:.6e} kg (err {errC:.3e})")
        ok = ok and okC
        errCg = abs(dC_gas - dil["m_C_oxid"]) / max(dil["m_C_oxid"], 1e-12)
        okCg = errCg <= args.rtol
        print(f"  {'PASS' if okCg else 'FAIL'}  C_conservation  C en gas + desplazado "
              f"{dC_gas:.4e} vs oxidado {dil['m_C_oxid']:.4e} kg (err {errCg:.3e})")
        ok = ok and okCg
    if dC_gas < 1e-6:
        print("  FAIL  reaccion_activa  no se produjo CO/CO2 "
              "(dC_gas ~ 0): test inconcluyente")
        sys.exit(1)
    # C consumido del inventario: mass_solid no incluye m_C por separado;
    # usar el O consumido para inferir estequiometría global:
    # O_consumido = 4/3*C_a_CO + 4/7*CO_a_CO2... chequeo directo:
    # el C en gas debe ser consistente con el O2 desaparecido:
    vol0 = cell_volumes(load_snapshot(files[0])[1])
    O2_0 = float(np.sum(f0["Y_O2"] * f0["alpha_gas"] * f0["_rho_gas"] * vol0))
    O2_1 = float(np.sum(f1["Y_O2"] * f1["alpha_gas"] * f1["_rho_gas"] * vol0))
    dO2 = O2_0 - O2_1 - dil["m_dil_O2"]   # O2 consumido por las reacciones
    # cota estequiométrica: 4/3 <= O2_consumido/C_gas <= 4/3 + 4/7·(CO2/(CO+CO2))
    ratio = dO2 / dC_gas * (12.0 / 16.0)  # mol O / mol C
    # mol O / mol C: CO puro = 1, CO2 puro = 2 (auditoria 2, N-A6: la ventana
    # 0.45-1.15 suponia 0.5-1.0 -> aceptaba un deficit de O del 50 % y
    # rechazaba una corrida correcta con mas de ~15 % de CO2)
    okr = 1.0 - 1e-3 <= ratio <= 2.0 + 1e-3
    print(f"  {'PASS' if okr else 'FAIL'}  estequiometria  mol O/mol C = "
          f"{ratio:.4f} (esperado 1 (CO) - 2 (CO2); dC_gas={dC_gas:.3e} kg, "
          f"dO2={dO2:.3e} kg)")
    ok = ok and okr

    # M14: con el termino de dilucion la suma de especies nunca supera 1
    sY = float(np.max(f1["Y_O2"] + f1["Y_CO"] + f1["Y_CO2"]))
    okY = sY <= 1.0 + 1e-9
    print(f"  {'PASS' if okY else 'FAIL'}  suma_Y  max(Y_O2+Y_CO+Y_CO2) = {sY:.6f}")
    ok = ok and okY

    ts = f1["T_solid"]
    okT = np.isfinite(ts).all() and np.nanmax(ts) < 4000
    print(f"  {'PASS' if okT else 'FAIL'}  T_solid_acotada  max = "
          f"{np.nanmax(ts):.0f} K (el calor de Maahs limitado por O2)")
    ok = ok and okT

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
