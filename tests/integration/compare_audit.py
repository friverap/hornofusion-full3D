#!/usr/bin/env python3
"""compare_audit.py DIR_A DIR_B --from-step N [--rtol 1e-12]

Compara audit.csv de un REINICIO (DIR_A) con el de la corrida continua
(DIR_B) en las filas con step > N (la fila N del reinicio es su estado
inicial, sin fuentes). Todas las columnas son por intervalo o inventarios
instantaneos, asi que deben coincidir bit a bit con el mismo numero de
ranks (auditoria 4, B4-19: el gate del reinicio solo miraba el snapshot).
Error por columna relativo al mayor |valor| de esa columna en DIR_B.
"""
import argparse
import csv
import math
import os
import sys


def load(path):
    with open(path) as f:
        rows = list(csv.DictReader(f))
    return {int(float(r["step"])): r for r in rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir_a")
    ap.add_argument("dir_b")
    ap.add_argument("--from-step", type=int, required=True)
    ap.add_argument("--rtol", type=float, default=1e-12)
    args = ap.parse_args()
    pa, pb = (os.path.join(d, "audit.csv") for d in (args.dir_a, args.dir_b))
    for p in (pa, pb):
        if not os.path.exists(p):
            print(f"FAIL: no existe {p}")
            sys.exit(1)
    A, B = load(pa), load(pb)
    steps = sorted(s for s in A if s > args.from_step)
    if not steps or any(s not in B for s in steps):
        print(f"FAIL: pasos del reinicio {steps[:3]}... no estan todos en la continua")
        sys.exit(1)
    cols = [c for c in A[steps[0]] if c in B[steps[0]]]
    worst, worst_id = 0.0, "-"
    for c in cols:
        scale = max((abs(float(B[s][c])) for s in steps), default=0.0)
        for s in steps:
            a, b = float(A[s][c]), float(B[s][c])
            if not (math.isfinite(a) and math.isfinite(b)):
                err = float("inf")
            else:
                err = abs(a - b) / max(scale, 1e-300)
            if err > worst:
                worst, worst_id = err, f"{c}@{s}"
    ok = worst <= args.rtol
    print(f"[audit-restart] {os.path.basename(args.dir_a)} vs "
          f"{os.path.basename(args.dir_b)} ({len(steps)} filas, {len(cols)} columnas)")
    print(f"  {'PASS' if ok else 'FAIL'}  peor columna: {worst_id} ({worst:.3e}, tol {args.rtol})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
