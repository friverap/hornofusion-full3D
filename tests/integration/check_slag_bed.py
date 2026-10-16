#!/usr/bin/env python3
"""Escoria sobre un lecho que funde (banco arc_melt_slag, oct-2026).
  slag_bed_order   en NINGUN snapshot hay acero (alpha_l > --al-min) encima
                   de la celda de escoria mas alta (alpha_sl > --asl-min) de
                   su columna: la escoria CEDE al acero (A11-2), nunca lo
                   deja encima (M9-4)
  slag_bed_T       T_sl max <= max(T_l, T_s) max + --dT (sin salida termica la
                   escoria se sobrecalentaba miles de K bajo el arco: A13-1;
                   medido 1626 K frente a 1808 K del bano)
  slag_bed_mass    la masa de escoria se conserva (audit m_slag, rel --mtol)
Uso: check_slag_bed.py RUNDIR [--xfail ids]
"""
import argparse, csv, glob, os, sys
import h5py
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--al-min", type=float, default=1e-3)
    ap.add_argument("--asl-min", type=float, default=0.1)
    ap.add_argument("--dT", type=float, default=300.0)
    ap.add_argument("--mtol", type=float, default=1e-12)
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[slag_bed] {a.rundir}")
    snaps = sorted(glob.glob(os.path.join(a.rundir, "eaf3d_*.h5")))
    n_bad = 0; worst = 0.0; Tsl = 0.0; Tref = 0.0
    for f in snaps:
        with h5py.File(f, "r") as h:
            fl = h["fields"]
            al = fl["alpha_liquid"][:]; asl = fl["alpha_slag"][:]
            Ts_l = fl["T_liquid"][:]; Ts_s = fl["T_solid"][:]; T_sl = fl["T_slag"][:]
            als = fl["alpha_solid"][:] if "alpha_solid" in fl else None
        nz = al.shape[0]
        for j in range(al.shape[1]):
            for i in range(al.shape[2]):
                ks = np.nonzero(asl[:, j, i] > a.asl_min)[0]
                if ks.size == 0:
                    continue
                above = al[ks.max() + 1:, j, i]
                if above.size and above.max() > a.al_min:
                    n_bad += 1; worst = max(worst, float(above.max()))
        m = asl > 1e-3
        if m.any():
            Tsl = max(Tsl, float(T_sl[m].max()))
        ml = al > 1e-3
        tl = float(Ts_l[ml].max()) if ml.any() else 0.0
        ts = float(Ts_s[als > 1e-3].max()) if als is not None and (als > 1e-3).any() else float(Ts_s.max())
        Tref = max(Tref, tl, ts)
    chk.report("slag_bed_order", n_bad == 0,
               f"{n_bad} columnas-snapshot con acero encima de la escoria (max alpha_l {worst:.3e}; {len(snaps)} snapshots)")
    chk.report("slag_bed_T", Tsl <= Tref + a.dT,
               f"T_sl max {Tsl:.0f} K frente a max(T_l, T_s) {Tref:.0f} K + {a.dT:.0f}")
    rows = list(csv.DictReader(open(os.path.join(a.rundir, "audit.csv"))))
    m0 = float(rows[0]["m_slag"]); m1 = float(rows[-1]["m_slag"])
    chk.report("slag_bed_mass", abs(m1 - m0) <= a.mtol * max(abs(m0), 1.0),
               f"m_slag {m0:.6f} -> {m1:.6f} kg (rel {abs(m1 - m0) / max(abs(m0), 1.0):.2e})")
    chk.exit()


if __name__ == "__main__":
    main()
