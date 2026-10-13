#!/usr/bin/env python3
"""Drenaje del lecho (auditoria 2, N-C1): el centroide vertical del liquido
debe bajar al menos --min-drop m entre el primer snapshot con liquido y el
ultimo. Con la fuerza balanceada sin la flotacion relativa del lecho el
liquido quedaba colgado (0.02 m en 0.6 s frente a 0.23 m).

Uso: check_drain.py RUNDIR [--min-drop 0.1] [--xfail ids]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, cell_volumes, load_snapshot, parse_xfail_arg, snapshots


def zcm(path):
    f, mesh, _ = load_snapshot(path)
    v = cell_volumes(mesh)
    z = mesh["z"][:, None, None]
    m = f["alpha_liquid"] * v
    return float(m.sum()), float((m * z).sum() / max(m.sum(), 1e-30))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--min-drop", type=float, default=0.1)
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[drain] {a.rundir}")
    snaps = snapshots(a.rundir)
    first = None
    for s in snaps:
        m, z = zcm(s)
        if m > 1e-6:
            first = (s, z)
            break
    if first is None:
        chk.report("bed_drain", False, "sin liquido en ningun snapshot")
        chk.exit()
    _, z1 = zcm(snaps[-1])
    drop = first[1] - z1
    chk.report("bed_drain", drop >= a.min_drop,
               f"centroide del liquido {first[1]:.4f} -> {z1:.4f} m "
               f"(baja {drop:.4f} m, minimo {a.min_drop})")
    chk.exit()


if __name__ == "__main__":
    main()
