#!/usr/bin/env python3
"""Fusión PROGRESIVA bajo arco (auditoría 4, A4-7): chatarra a 1550 K (bajo el
solidus) con arco; la palanca funde a lo largo de muchos pasos, no en el
paso 1 (melt_forced, bath_fill y bed_flood funden >= 99.99 % en el paso 1).
  arcmelt_progressive  fracción de pasos con m_melted > 0 >= --frac (medido
                       0.62 desde la banda ±1 del 14-oct; 0.56 antes) y
                       ningún paso funde más de --maxstep del total
  arcmelt_mass         m_liq final >= --mliq kg (medido 36.8; 28 antes de
                       la banda ±1)
Uso: check_arcmelt.py RUNDIR [--xfail ids]
"""
import argparse, csv, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--frac", type=float, default=0.4)
    ap.add_argument("--maxstep", type=float, default=0.1)
    ap.add_argument("--mliq", type=float, default=10.0)
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[arcmelt] {a.rundir}")
    rows = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(open(os.path.join(a.rundir, "audit.csv")))][1:]
    mm = [r["m_melted"] for r in rows]; tot = sum(mm)
    frac = sum(1 for x in mm if x > 0) / len(mm)
    mx = max(mm) / tot if tot > 0 else 0.0
    chk.report("arcmelt_progressive", frac >= a.frac and mx <= a.maxstep,
               f"{frac:.2f} de los pasos funden (min {a.frac}); el mayor paso funde {mx:.3f} del total (max {a.maxstep})")
    chk.report("arcmelt_mass", rows[-1]["m_liq"] >= a.mliq, f"m_liq final {rows[-1]['m_liq']:.1f} kg (min {a.mliq})")
    chk.exit()


if __name__ == "__main__":
    main()
