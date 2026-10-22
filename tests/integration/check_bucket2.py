#!/usr/bin/env python3
"""Cesta 2 que ATRAVIESA la escoria condensada (Plan I, I2; auditoria 21,
B21-C2; gate 8 del PLAN_I, "base de la cesta").

  bucket2_through  entre el snapshot anterior a la carga (--pre) y el
                   posterior (--post), la chatarra aparece en celdas que
                   ANTES estaban llenas de escoria (alpha_sl >= --asl-min):
                   la cesta se apoya en el tope del ACERO y el sort sube la
                   escoria desplazada. Sin I2 la cesta se apoya sobre la
                   escoria y esas celdas no reciben chatarra.

Uso: check_bucket2.py RUNDIR --pre 5 --post 15 [--asl-min 0.5] [--das-min 0.01]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, load_snapshot, parse_xfail_arg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--pre", type=int, required=True)
    ap.add_argument("--post", type=int, required=True)
    ap.add_argument("--asl-min", type=float, default=0.5)
    ap.add_argument("--das-min", type=float, default=0.01)
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[bucket2] {a.rundir}")
    f0, _, _ = load_snapshot(os.path.join(a.rundir, f"eaf3d_{a.pre:08d}.h5"))
    f1, _, _ = load_snapshot(os.path.join(a.rundir, f"eaf3d_{a.post:08d}.h5"))
    asl0 = np.asarray(f0["alpha_slag"])
    das = np.asarray(f1["alpha_solid"]) - np.asarray(f0["alpha_solid"])
    slag_cells = asl0 >= a.asl_min
    n_slag = int(slag_cells.sum())
    n_thru = int((slag_cells & (das > a.das_min)).sum())
    chk.report("bucket2_through", n_slag > 0 and n_thru > 0,
               f"{n_thru} de {n_slag} celdas con escoria (alpha_sl >= {a.asl_min}) "
               f"antes de la carga reciben chatarra (d alpha_s > {a.das_min}); debe ser > 0")
    chk.exit()


if __name__ == "__main__":
    main()
