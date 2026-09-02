#!/usr/bin/env python3
"""Simetría azimutal de 120 grados: con carga uniforme, 3 electrodos
simétricos y MC apagado (n_beams=0), rotar la solución ntheta/3 celdas en
theta debe dejarla invariante.

Detecta la corrupción de métrica en la costura theta=0 (hallazgo 3.7) y
cualquier bug de indexación azimutal. La tolerancia por defecto (1e-6) se
calibrará al aterrizar C1.3: el barrido TDMA en theta con costura retardada
introduce una asimetría residual propia del solver que puede exigir aflojar
a ~1e-5; nunca más allá.

Uso: check_symmetry.py RUNDIR [--rtol 1e-6] [--floor 1e-10]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import load_snapshot, snapshots

# Campos vectoriales en theta rotan como escalares (la componente theta es
# la misma en la base local rotada); todos los campos se tratan igual.
THETA_AXIS = 1  # datasets h5py: (nz, nth, nr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--rtol", type=float, default=1e-6)
    ap.add_argument("--floor", type=float, default=1e-10)
    args = ap.parse_args()

    path = snapshots(args.rundir)[-1]
    fields, mesh, meta = load_snapshot(path)
    nth = len(mesh["theta"])
    if nth % 3 != 0:
        sys.exit(f"ERROR: ntheta={nth} no es múltiplo de 3")
    shift = nth // 3

    print(f"[symmetry] {args.rundir} (step {int(meta['step'])}, "
          f"rotación {shift}/{nth} celdas)")
    worst, worst_field = 0.0, ""
    for name in sorted(fields):
        a = fields[name]
        rot = np.roll(a, shift, axis=THETA_AXIS)
        scale = max(float(np.max(np.abs(a))), args.floor)
        err = float(np.max(np.abs(a - rot))) / scale
        flag = "   " if err <= args.rtol else "***"
        print(f"  {flag} {name:22s} err_rel_Linf = {err:.3e}")
        if err > worst:
            worst, worst_field = err, name
    ok = worst <= args.rtol
    print(f"  {'PASS' if ok else 'FAIL'}  peor campo: {worst_field} "
          f"({worst:.3e}, tol {args.rtol})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
