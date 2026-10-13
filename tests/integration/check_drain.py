#!/usr/bin/env python3
"""Drenaje del lecho (auditoria 2 N-C1; auditoria 3 A3-1):
  bed_drain      el centroide vertical del liquido baja al menos --min-drop m
                 entre el primer snapshot con liquido y el ultimo. Sin la
                 flotacion relativa del lecho el liquido quedaba colgado
                 (0.02 m en 0.6 s); con el gas del lecho sin su flotacion
                 (dp/dz = -W de la mezcla, empuje x alpha_g/eps) 0.18 m; con
                 ambas fases clasicas en el lecho 0.22 m.
  bed_drain_rate la velocidad vertical media (ponderada por masa) del liquido
                 en los snapshots con t >= --t-rate es <= -(--min-speed) m/s:
                 medido 0.52-0.62 m/s (A3-1) frente a 0.40-0.44 antes.

Uso: check_drain.py RUNDIR [--min-drop 0.2] [--min-speed 0.48] [--xfail ids]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, cell_volumes, load_snapshot, parse_xfail_arg, snapshots


def zcm(path):
    f, mesh, meta = load_snapshot(path)
    v = cell_volumes(mesh)
    z = mesh["z"][:, None, None]
    m = f["alpha_liquid"] * v
    ms = max(m.sum(), 1e-30)
    uz = float((f["velocity_z_liquid"] * m).sum() / ms)
    return float(m.sum()), float((m * z).sum() / ms), uz, float(meta.get("time", -1.0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--min-drop", type=float, default=0.2)
    ap.add_argument("--min-speed", type=float, default=0.48)
    ap.add_argument("--t-rate", type=float, default=0.15)
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[drain] {a.rundir}")
    snaps = snapshots(a.rundir)
    first = None
    speeds = []
    for s in snaps:
        m, z, uz, t = zcm(s)
        if m > 1e-6 and first is None:
            first = (s, z)
        if m > 1e-6 and t >= a.t_rate:
            speeds.append(-uz)
    if first is None:
        chk.report("bed_drain", False, "sin liquido en ningun snapshot")
        chk.exit()
    _, z1, _, _ = zcm(snaps[-1])
    drop = first[1] - z1
    chk.report("bed_drain", drop >= a.min_drop,
               f"centroide del liquido {first[1]:.4f} -> {z1:.4f} m "
               f"(baja {drop:.4f} m, minimo {a.min_drop})")
    vmin = min(speeds) if speeds else 0.0
    chk.report("bed_drain_rate", bool(speeds) and vmin >= a.min_speed,
               f"velocidad media de drenaje minima {vmin:.3f} m/s en {len(speeds)} snapshots "
               f"(t >= {a.t_rate}; minimo {a.min_speed})")
    chk.exit()


if __name__ == "__main__":
    main()
