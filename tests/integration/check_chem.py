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

Uso: check_chem.py RUNDIR --config CFG [--rtol 0.05]
"""
import argparse, csv, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import cell_volumes, load_snapshot, read_config, snapshots


RHO_REF = 1.2      # cfg%rho_gas por defecto
T_REF = 300.0      # cfg%T_ambient (se sobreescribe con el config)


def rho_gas(T):
    # la MISMA EOS que mod_properties_3d: rho_gas*T_ambient/T (antes 1.2*300/T
    # fijo: con T_ambient = 900 K los inventarios salian 3x menores)
    return RHO_REF * T_REF / np.maximum(T, 100.0)


def elements(path):
    f, mesh, meta = load_snapshot(path)
    vol = cell_volumes(mesh)
    arho = f["alpha_gas"] * rho_gas(f["T_gas"])
    O = float(np.sum(arho * (f["Y_O2"] + f["Y_CO"] * 16 / 28 +
                             f["Y_CO2"] * 32 / 44) * vol))
    C = float(np.sum(arho * (f["Y_CO"] * 12 / 28 + f["Y_CO2"] * 12 / 44) * vol))
    return O, C, f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--config", required=True)
    ap.add_argument("--rtol", type=float, default=0.05)
    args = ap.parse_args()

    global RHO_REF, T_REF
    cfg = read_config(args.config)
    RHO_REF = float(cfg.get("rho_gas", 1.2))
    T_REF = float(cfg.get("T_ambient", 300.0))
    files = snapshots(args.rundir)
    O0, C0, f0 = elements(files[0])
    O1, C1, f1 = elements(files[-1])

    # columnas del audit (si existen): dilucion y carbono oxidado
    dil = {"m_dil_O2": 0.0, "m_dil_CO": 0.0, "m_dil_CO2": 0.0, "m_C_oxid": 0.0}
    apath = os.path.join(args.rundir, "audit.csv")
    have_audit = False
    if os.path.exists(apath):
        with open(apath) as fa:
            rows = list(csv.DictReader(fa))[1:]
        if rows and "m_dil_O2" in rows[0]:
            have_audit = True
            for r in rows:
                for kk in dil:
                    dil[kk] += float(r[kk])
    O_dil = dil["m_dil_O2"] + dil["m_dil_CO"] * 16 / 28 + dil["m_dil_CO2"] * 32 / 44
    C_dil = dil["m_dil_CO"] * 12 / 28 + dil["m_dil_CO2"] * 12 / 44

    print(f"[chem] {args.rundir}")
    ok = True

    errO = abs(O1 + O_dil - O0) / max(O0, 1e-12)
    print(f"  {'PASS' if errO <= args.rtol else 'FAIL'}  O_conservation  "
          f"O: {O0:.4e} -> {O1:.4e} + desplazado {O_dil:.4e} kg (err {errO:.3e})")
    ok = ok and errO <= args.rtol

    dC_gas = C1 - C0 + C_dil
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
    O2_0 = float(np.sum(f0["Y_O2"] * f0["alpha_gas"] * rho_gas(f0["T_gas"]) * vol0))
    O2_1 = float(np.sum(f1["Y_O2"] * f1["alpha_gas"] * rho_gas(f1["T_gas"]) * vol0))
    dO2 = O2_0 - O2_1 - dil["m_dil_O2"]   # O2 consumido por las reacciones
    # cota estequiométrica: 4/3 <= O2_consumido/C_gas <= 4/3 + 4/7·(CO2/(CO+CO2))
    ratio = dO2 / dC_gas * (12.0 / 16.0)  # mol O / mol C
    okr = 0.45 <= ratio <= 1.15  # entre CO puro (0.5) y CO2 puro (1.0) +tol
    print(f"  {'PASS' if okr else 'FAIL'}  estequiometria  mol O/mol C = "
          f"{ratio:.3f} (esperado 0.5-1.0; dC_gas={dC_gas:.3e} kg, "
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
