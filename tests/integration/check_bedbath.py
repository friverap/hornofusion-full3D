#!/usr/bin/env python3
"""Baño bajo lecho en REPOSO (auditoría 4, A4-7 / A4-1): heel que satura los
poros de un lecho frío, sin arco ni fusión. Criterios:
  bedbath_alpha_frozen  max |dalpha_l| entre el primer y el último snapshot
                        <= --dalpha (medido 4e-7; antes de A4-1 7e-6)
  bedbath_p_bounded     p_max del audit <= --pfac x p_max inicial
  bedbath_liq_rest      u_liq_max del audit con t >= --t0 <= --uliq m/s
                        (medido 0.069 — velocidad fantasma de la celda
                        sellada de F2.29, abierto sin id propio (B5-23: no es
                        B4-4); antes de A4-1 0.29: la bomba del poro saturado
                        con el motor en el líquido)
  bedbath_gas_rest      u_gas_max del audit con t >= --t0 <= --ugas m/s
                        (medido 0.2; antes 1.6)
Uso: check_bedbath.py RUNDIR [--xfail ids]
"""
import argparse, csv, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, load_snapshot, parse_xfail_arg, snapshots


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--dalpha", type=float, default=1e-5)
    ap.add_argument("--pfac", type=float, default=1.2)
    ap.add_argument("--uliq", type=float, default=0.1)
    ap.add_argument("--ugas", type=float, default=1.0)
    ap.add_argument("--t0", type=float, default=0.1)
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[bedbath] {a.rundir}")
    sn = snapshots(a.rundir)
    f0, _, _ = load_snapshot(sn[0]); f1, _, _ = load_snapshot(sn[-1])
    da = float(np.abs(f1["alpha_liquid"] - f0["alpha_liquid"]).max())
    chk.report("bedbath_alpha_frozen", da <= a.dalpha, f"max |d alpha_l| = {da:.3e} (max {a.dalpha})")
    rows = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(open(os.path.join(a.rundir, "audit.csv")))]
    p0 = rows[0]["p_max"]; pm = max(r["p_max"] for r in rows)
    chk.report("bedbath_p_bounded", pm <= a.pfac * p0, f"p_max {pm:.3e} Pa (inicial {p0:.3e}, factor {a.pfac})")
    late = [r for r in rows if r["time"] >= a.t0]
    ul = max(r["u_liq_max"] for r in late); ug = max(r["u_gas_max"] for r in late)
    chk.report("bedbath_liq_rest", ul <= a.uliq, f"u_liq_max (t >= {a.t0}) = {ul:.3f} m/s (max {a.uliq})")
    chk.report("bedbath_gas_rest", ug <= a.ugas, f"u_gas_max (t >= {a.t0}) = {ug:.3f} m/s (max {a.ugas})")
    chk.exit()


if __name__ == "__main__":
    main()
