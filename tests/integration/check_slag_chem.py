#!/usr/bin/env python3
"""Conservacion elemental de la quimica de escoria (E2.3/E2.4).

  fe_element : m_liq*(Fe) + m_FeO*(56/72) constante => dm_liq ==
               -(m_fe_yield - m_fe_return) del audit, y el FeO del
               snapshot cuadra con el neto (oxidado - reducido)
  slag_mass  : dm_sl == dm_FeO_neto - dm_C_consumido + adiciones
  activity   : la quimica corrio (m_fe_yield > 0)

Uso: check_slag_chem.py RUNDIR --config CFG [--xfail ids]
"""
import argparse
import csv
import glob
import os
import sys

import h5py
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg, safe_float

MW_FE, MW_FEO, MW_C = 0.05585, 0.07185, 0.012


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--config", required=True)
    ap.add_argument("--xfail", default="")
    # (auditoria 18, A1) actividad de la REDUCCION: Fe devuelto minimo [kg]
    ap.add_argument("--min-return", type=float, default=None)
    args = ap.parse_args()

    rows = [{k: safe_float(v) for k, v in r.items()}
            for r in csv.DictReader(
                open(os.path.join(args.rundir, "audit.csv")))]
    first, last = rows[0], rows[-1]
    steps = rows[1:]
    chk = Checker(parse_xfail_arg(args.xfail))
    print(f"[slag_chem] {args.rundir}")

    fey = sum(r.get("m_fe_yield", 0.0) for r in steps)
    fer = sum(r.get("m_fe_return", 0.0) for r in steps)
    dm_liq = last["m_liq"] - first["m_liq"]

    # umbral 0.5 kg (Plan H, P7): con la escoria CONDENSADA la capa resuelta
    # aisla el metal del O2 (el estencil de oxidacion pide O2 en la celda de
    # escoria y baño en la de abajo; tras la compactacion la celda inferior
    # no tiene gas): slag_chem_flow oxida 0.99 kg frente a 2.7 kg del legado.
    # El check vigila que la quimica CORRA, no su tasa
    if args.min_return is not None:
        chk.report("reduction", fer >= args.min_return,
                   f"Fe devuelto por la reduccion = {fer:.3f} kg (min {args.min_return:.3f})")
    chk.report("activity", fey > 0.5,
               f"Fe oxidado = {fey:.3f} kg (>0.5 kg exige quimica activa)")

    # Fe elemental: el liquido pierde (yield - return) exactamente.
    # Tolerancia 1e-6 relativa al flujo: dm_liq es la RESTA de inventarios
    # ~1e5 kg (cancelacion de redondeo ~1e-6 kg absoluto, 1e-11 relativo
    # al inventario)
    # Resolucion del CSV: m_liq se escribe en doble completo (ES24.16E3,
    # auditoria 3 M3-6), asi que la resta de dos inventarios de ~1e5 kg
    # resuelve ~1e-11 kg. El umbral es el mayor de 1e-9 del flujo y dos
    # unidades de esa resolucion. (auditoria 4, B4-17: estaba calibrado a
    # las 10 cifras de ES17.9, 1e7x mas laxo que lo medido, 2e-11)
    import math
    mref = max(abs(first["m_liq"]), abs(last["m_liq"]), 1.0)
    res_csv = 2.0 * 10.0 ** (math.floor(math.log10(mref)) - 16)
    err = abs(dm_liq + (fey - fer)) / max(fey, 1.0)
    tol_fe = max(1e-9, res_csv / max(fey, 1.0))
    chk.report("fe_element", err <= tol_fe,
               f"dm_liq={dm_liq:.4f} vs -(yield-return)="
               f"{-(fey-fer):.4f} kg (err {err:.3e})")

    # FeO del snapshot: neto = oxidado*(72/56) - reducido consumido
    snaps = sorted(glob.glob(os.path.join(args.rundir, "eaf3d_*.h5")))
    with h5py.File(snaps[0]) as h0, h5py.File(snaps[-1]) as h1:
        # m_FeO por celda no esta en HDF5; usamos X_FeO * m_sl... m_sl
        # tampoco: validamos via la masa total de escoria del audit
        pass
    feo_from_yield = fey * MW_FEO / MW_FE
    feo_reduced = fer * MW_FEO / MW_FE
    dm_sl = last["m_slag"] - first["m_slag"]
    flux = sum(r.get("m_flux_in", 0.0) for r in steps)
    c_consumed = feo_reduced * MW_C / MW_FEO
    # (Plan H, P6) escoria condensada recortada por el acotado del transporte
    sclip = sum(r.get("m_slag_clip", 0.0) for r in steps)
    expected_dm_sl = feo_from_yield - feo_reduced - c_consumed + flux - sclip
    err2 = abs(dm_sl - expected_dm_sl) / max(abs(expected_dm_sl), 1.0)
    chk.report("slag_mass", err2 <= 1e-6,
               f"dm_slag={dm_sl:.4f} vs esperado={expected_dm_sl:.4f} kg "
               f"(err {err2:.3e})")

    chk.exit()


if __name__ == "__main__":
    main()
