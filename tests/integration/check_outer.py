#!/usr/bin/env python3
"""Convergencia real del lazo externo SIMPLE (guardián de C2.1 / 3.15).

Lee run.log y verifica que en el último paso el lazo externo convergió en
MENOS de max_outer iteraciones (outer < max). Antes de C2.1 el punto fijo
del lazo no satisfacía la ecuación discreta y siempre se agotaba max_outer.

Uso: check_outer.py RUNDIR --max-outer 30
"""
import argparse
import os
import re
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--max-outer", type=int, required=True)
    args = ap.parse_args()

    log = os.path.join(args.rundir, "run.log")
    outers = []
    pat = re.compile(r"\[STEP\]\s+(\d+)\s+t=\s*\S+\s+outer=\s*(\d+)")
    with open(log) as f:
        for line in f:
            mm = pat.search(line)
            if mm:
                outers.append((int(mm.group(1)), int(mm.group(2))))
    if not outers:
        sys.exit(f"ERROR: sin líneas [STEP] en {log}")

    # TODOS los pasos (auditoria 2, N-A6): 1 < outer < max. outer = 1 es la
    # firma de la regresion de Bug 20 (residuales con el campo recien
    # resuelto: el lazo se declara convergido sin iterar)
    bad = [(s, o) for s, o in outers if not (1 < o < args.max_outer)]
    ok = not bad
    tag = "PASS " if ok else "FAIL "
    print(f"[outer] {args.rundir}")
    lo = min(o for _, o in outers); hi = max(o for _, o in outers)
    print(f"  {tag} outer_convergence  {len(outers)} pasos, outer en [{lo}, {hi}] "
          f"(se exige 1 < outer < max_outer = {args.max_outer})"
          + (f"; fuera: {bad[:5]}" if bad else ""))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
