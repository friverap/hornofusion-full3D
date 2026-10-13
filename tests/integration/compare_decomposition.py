#!/usr/bin/env python3
"""Invarianza a la descomposición MPI: compara el último snapshot de dos
corridas del MISMO config con distinto número de ranks.

Métrica por campo: max|a-b| / max(escala, floor), con la escala por FAMILIA
de campo: las componentes de velocidad de una fase se escalan con la máxima
de las tres (auditoria 2: una componente ~0 por simetría, p. ej. u_theta de un
baño simétrico de 5e-7 m/s, dominaba la métrica con ruido de 1e-9 m/s y
obligaba a una tolerancia laxa). El resto, con su propio máximo. Bitwise es inalcanzable
por diseño (TDMA con interfaces retardadas, SOR con recorrido distinto,
barridos fijos no convergidos); la tolerancia arranca en 1e-3 (post C1.2)
y se endurece a 1e-6 tras la Etapa 2 subiendo iteraciones internas en el
config de test, nunca aflojando la tolerancia.

Uso: compare_decomposition.py DIR_A DIR_B [--rtol 1e-3] [--floor 1e-10]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import load_snapshot, snapshots


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir_a")
    ap.add_argument("dir_b")
    ap.add_argument("--rtol", type=float, default=1e-3)
    ap.add_argument("--floor", type=float, default=1e-10)
    args = ap.parse_args()

    fa = snapshots(args.dir_a)[-1]
    fb = snapshots(args.dir_b)[-1]
    fields_a, _, meta_a = load_snapshot(fa)
    fields_b, _, meta_b = load_snapshot(fb)

    if int(meta_a["step"]) != int(meta_b["step"]):
        print(f"FAIL: pasos finales distintos ({meta_a['step']} vs "
              f"{meta_b['step']}) — el conteo de pasos debe ser idéntico")
        sys.exit(1)

    print(f"[decomposition] {os.path.basename(args.dir_a)} vs "
          f"{os.path.basename(args.dir_b)} (step {int(meta_a['step'])})")
    worst, worst_field = 0.0, ""

    def family_scale(name):
        # velocidades: la maxima de las tres componentes de la misma fase
        if name.startswith("velocity_"):
            phase = name.split("_")[-1]
            comps = [f"velocity_{c}_{phase}" for c in ("r", "th", "z")]
            return max(float(np.max(np.abs(fields_b[c]))) for c in comps if c in fields_b)
        return float(np.max(np.abs(fields_b[name])))

    for name in sorted(fields_a):
        a, b = fields_a[name], fields_b[name]
        scale = max(family_scale(name), args.floor)
        err = float(np.max(np.abs(a - b))) / scale
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
