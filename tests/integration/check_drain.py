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
                 medido 0.52-0.62 m/s (A3-1; 0.50 con la rampa del lecho M3-2) frente a 0.40-0.44 antes.
  bed_drain_outer  max vol_dalpha_outer del audit <= --max-vdo m3 (auditoria 20,
                 M20-5): con Plan J-B el hueco de poro se congela en alpha^n;
                 sin el congelado la cara se cierra y reabre entre iteraciones
                 externas (medido: 2.5e-2 frente a 1.45e-4).
  bed_drain_unlinked  suma de |vol_unlinked| <= --max-unlinked m3 (M20-5): sin
                 J-B el transporte rellena caras que el Poisson cerro (medido:
                 5.0 frente a 0.12).

Uso: check_drain.py RUNDIR [--min-drop 0.19] [--min-speed 0.42] [--max-vdo 2e-3]
     [--max-unlinked 1.0] [--xfail ids]
"""
import argparse
import csv
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
    ap.add_argument("--min-drop", type=float, default=0.19)
    ap.add_argument("--min-speed", type=float, default=0.42)
    ap.add_argument("--t-rate", type=float, default=0.15)
    # (M4-17) cota superior: sin Ergun el liquido caeria libre (>> 1 m/s)
    ap.add_argument("--max-speed", type=float, default=1.0)
    ap.add_argument("--max-vdo", type=float, default=2.0e-3)
    ap.add_argument("--max-unlinked", type=float, default=1.0)
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
    vmax = max(speeds) if speeds else 0.0
    chk.report("bed_drain_rate", bool(speeds) and vmin >= a.min_speed and vmax <= a.max_speed,
               f"velocidad media de drenaje {vmin:.3f}..{vmax:.3f} m/s en {len(speeds)} snapshots "
               f"(t >= {a.t_rate}; minimo {a.min_speed}, maximo {a.max_speed})")
    with open(os.path.join(a.rundir, "audit.csv")) as fh:
        rows = list(csv.DictReader(fh, skipinitialspace=True))[1:]
    vdo = max(abs(float(r["vol_dalpha_outer"])) for r in rows)
    chk.report("bed_drain_outer", vdo <= a.max_vdo,
               f"max vol_dalpha_outer {vdo:.3e} m3 (maximo {a.max_vdo:.1e})")
    unl = sum(abs(float(r["vol_unlinked"])) for r in rows)
    chk.report("bed_drain_unlinked", unl <= a.max_unlinked,
               f"suma |vol_unlinked| {unl:.3e} m3 (maximo {a.max_unlinked:.1e})")
    chk.exit()


if __name__ == "__main__":
    main()
