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
  slag_bed_volfix  (con --volfix-max) |m_gas_volfix| acumulado [kg] <= techo
                   (gas que la recolocacion de la escoria crea o destruye)
  slag_bed_jumps   (con --max-jumps) columnas cuyo SOPORTE de la escoria (acero
                   saturado mas alto, la regla de slag_buoyancy) salta >= 2
                   celdas entre snapshots consecutivos <= --max-jumps (vigila la
                   oscilacion de la escoria con creacion/destruccion de gas)
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
    ap.add_argument("--max-jumps", type=int, default=None)
    ap.add_argument("--volfix-max", type=float, default=None)
    # (auditoria 18, A18-2) reposo: cotas de u_liq_max / u_gas_max del audit
    ap.add_argument("--umax-liq", type=float, default=None)
    ap.add_argument("--umax-gas", type=float, default=None)
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[slag_bed] {a.rundir}")
    snaps = sorted(glob.glob(os.path.join(a.rundir, "eaf3d_*.h5")))
    n_bad = 0; worst = 0.0; Tsl = 0.0; Tref = 0.0
    n_jump = 0; ks_prev = None
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
        if als is not None:
            cap = np.maximum(np.where(als >= 1e-2, 1.0 - als - 0.015, 1.0 - als), 0.0)
            sat = al >= np.minimum(0.3, np.maximum(0.01, 0.5 * cap))
            idx = np.arange(nz)[:, None, None]
            ks = np.where(sat.any(axis=0), np.max(np.where(sat, idx, -1), axis=0), -1)
            if ks_prev is not None:
                n_jump += int((np.abs(ks - ks_prev) >= 2).sum())
            ks_prev = ks
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
    if a.max_jumps is not None:
        chk.report("slag_bed_jumps", n_jump <= a.max_jumps,
                   f"{n_jump} saltos del soporte >= 2 celdas entre snapshots (max {a.max_jumps})")
    rows = list(csv.DictReader(open(os.path.join(a.rundir, "audit.csv"))))
    if a.volfix_max is not None and "m_gas_volfix" in rows[0]:
        vf = sum(abs(float(r["m_gas_volfix"])) for r in rows[1:])
        chk.report("slag_bed_volfix", vf <= a.volfix_max,
                   f"|m_gas_volfix| acumulado {vf:.3e} kg (techo {a.volfix_max:.1e})")
    if a.umax_liq is not None:
        ul = max(float(r["u_liq_max"]) for r in rows[1:])
        chk.report("slag_rest_uliq", ul <= a.umax_liq,
                   f"u_liq_max {ul:.3e} m/s (max {a.umax_liq:.1e})")
    if a.umax_gas is not None:
        ug = max(float(r["u_gas_max"]) for r in rows[1:])
        chk.report("slag_rest_ugas", ug <= a.umax_gas,
                   f"u_gas_max {ug:.3e} m/s (max {a.umax_gas:.1e})")
    m0 = float(rows[0]["m_slag"]); m1 = float(rows[-1]["m_slag"])
    # (Plan H, P6) la escoria condensada recortada (auditada) sale del balance
    sclip = sum(float(r.get("m_slag_clip", 0.0) or 0.0) for r in rows[1:])
    chk.report("slag_bed_mass", abs(m1 - m0 + sclip) <= a.mtol * max(abs(m0), 1.0),
               f"m_slag {m0:.6f} -> {m1:.6f} kg, clip {sclip:.3e} kg (rel {abs(m1 - m0 + sclip) / max(abs(m0), 1.0):.2e})")
    chk.exit()


if __name__ == "__main__":
    main()
