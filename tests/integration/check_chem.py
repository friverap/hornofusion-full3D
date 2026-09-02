#!/usr/bin/env python3
"""Química conservativa (C3.3): balances elementales de O y C.

Sobre una corrida SIN flujo (chem_test): entre el primer y último snapshot,
  O: sum(alpha_g*rho_g*[Y_O2 + Y_CO*16/28 + Y_CO2*32/44]*V) se conserva
  C: el carbono aparecido en el gas = carbono consumido del inventario m_C
     (aprox: C_gas = sum(alpha*rho*[Y_CO*12/28 + Y_CO2*12/44]*V))
Tolerancia holgada (default 5%): rho_gas(T) introduce deriva de inventario
al calentarse el gas (agujero EOS documentado).

Uso: check_chem.py RUNDIR --config CFG [--rtol 0.05]
"""
import argparse, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import cell_volumes, load_snapshot, read_config, snapshots


def elements(path):
    f, mesh, meta = load_snapshot(path)
    vol = cell_volumes(mesh)
    arho = f["alpha_gas"] * 1.2 * 300.0 / np.maximum(f["T_gas"], 100.0)
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

    files = snapshots(args.rundir)
    O0, C0, f0 = elements(files[0])
    O1, C1, f1 = elements(files[-1])

    print(f"[chem] {args.rundir}")
    ok = True

    errO = abs(O1 - O0) / max(O0, 1e-12)
    print(f"  {'PASS' if errO <= args.rtol else 'FAIL'}  O_conservation  "
          f"O: {O0:.4e} -> {O1:.4e} kg (err {errO:.3e})")
    ok = ok and errO <= args.rtol

    dC_gas = C1 - C0
    if dC_gas < 1e-6:
        print("  FAIL  reaccion_activa  no se produjo CO/CO2 "
              "(dC_gas ~ 0): test inconcluyente")
        sys.exit(1)
    # C consumido del inventario: mass_solid no incluye m_C por separado;
    # usar el O consumido para inferir estequiometría global:
    # O_consumido = 4/3*C_a_CO + 4/7*CO_a_CO2... chequeo directo:
    # el C en gas debe ser consistente con el O2 desaparecido:
    dO2 = float(np.sum((f0["Y_O2"] - f1["Y_O2"]) *
                       f0["alpha_gas"] * 1.2 * 300 /
                       np.maximum(f0["T_gas"], 100) *
                       cell_volumes(load_snapshot(files[0])[1])))
    # cota estequiométrica: 4/3 <= O2_consumido/C_gas <= 4/3 + 4/7·(CO2/(CO+CO2))
    ratio = dO2 / dC_gas * (12.0 / 16.0)  # mol O / mol C
    okr = 0.45 <= ratio <= 1.15  # entre CO puro (0.5) y CO2 puro (1.0) +tol
    print(f"  {'PASS' if okr else 'FAIL'}  estequiometria  mol O/mol C = "
          f"{ratio:.3f} (esperado 0.5-1.0; dC_gas={dC_gas:.3e} kg, "
          f"dO2={dO2:.3e} kg)")
    ok = ok and okr

    ts = f1["T_solid"]
    okT = np.isfinite(ts).all() and np.nanmax(ts) < 4000
    print(f"  {'PASS' if okT else 'FAIL'}  T_solid_acotada  max = "
          f"{np.nanmax(ts):.0f} K (el calor de Maahs limitado por O2)")
    ok = ok and okT

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
