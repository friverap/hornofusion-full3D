#!/usr/bin/env python3
"""compare_audit.py DIR_A DIR_B --from-step N [--rtol 1e-12]

Compara audit.csv de un REINICIO (DIR_A) con el de la corrida continua
(DIR_B) en las filas con step > N (la fila N del reinicio es su estado
inicial, sin fuentes). Todas las columnas son por intervalo o inventarios
instantaneos, asi que deben coincidir bit a bit con el mismo numero de
ranks (auditoria 4, B4-19: el gate del reinicio solo miraba el snapshot).
Error por columna relativo al mayor |valor| de esa columna en DIR_B; una
columna nula en DIR_B exige igualdad exacta. (auditoria 5, B5-21) Filas
duplicadas y columnas de un solo lado son FAIL; en la fila N se comparan los
inventarios instantaneos (el estado de arranque del reinicio).
"""
import argparse
import csv
import math
import os
import sys


# inventarios instantaneos: en la fila N (estado inicial del reinicio) deben
# coincidir con la continua aunque las columnas de fuente sean 0 (B5-21)
INVENTORY = ("time", "m_liq", "m_gas", "m_sol", "m_slag",
             "E_liq", "E_gas", "E_sol", "E_slag")


def load(path):
    with open(path) as f:
        rows = list(csv.DictReader(f))
    out = {}
    for r in rows:
        st = int(float(r["step"]))
        if st in out:
            # (B5-21) una fila repetida (freno de NaN, B5-29) no es ruido
            print(f"FAIL: paso {st} duplicado en {path}")
            sys.exit(1)
        out[st] = r
    return out


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
    # (B5-21) las dos cabeceras deben ser la MISMA: una columna de un solo
    # lado es un binario distinto o un audit truncado, no algo que ignorar
    ca, cb = list(A[steps[0]].keys()), list(B[steps[0]].keys())
    if ca != cb:
        print(f"FAIL: columnas distintas: solo en A {sorted(set(ca) - set(cb))}, "
              f"solo en B {sorted(set(cb) - set(ca))}")
        sys.exit(1)
    cols = ca
    worst, worst_id = 0.0, "-"
    # fila N: inventarios del estado de arranque frente a la continua
    cmp_rows = [(args.from_step, INVENTORY)] if args.from_step in A and args.from_step in B else []
    cmp_rows += [(s, cols) for s in steps]
    for c in cols:
        scale = max((abs(float(B[s][c])) for s in steps), default=0.0)
        for s, cset in cmp_rows:
            if c not in cset:
                continue
            a, b = float(A[s][c]), float(B[s][c])
            if not (math.isfinite(a) and math.isfinite(b)):
                err = float("inf")
            elif scale > 0.0:
                err = abs(a - b) / scale
            else:
                # columna nula en la continua: cualquier valor distinto de
                # 0 en el reinicio es un fallo (antes escala 1e-300 -> inf,
                # o 0/0 silencioso)
                err = 0.0 if a == b else float("inf")
            if err > worst:
                worst, worst_id = err, f"{c}@{s}"
    ok = worst <= args.rtol
    print(f"[audit-restart] {os.path.basename(args.dir_a)} vs "
          f"{os.path.basename(args.dir_b)} ({len(steps)} filas, {len(cols)} columnas)")
    print(f"  {'PASS' if ok else 'FAIL'}  peor columna: {worst_id} ({worst:.3e}, tol {args.rtol})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
