#!/usr/bin/env python3
"""WS-K10: compara celda a celda las columnas COMUNES de dos juegos de
audit.csv (antes y despues de anadir columnas de diagnostico).

Uso: python3 research/ws/WS-K10/scripts/cmp_comunes.py BASE_DIR NUEVO_DIR
     (cada uno con subcarpetas <caso>/audit.csv)
     python3 research/ws/WS-K10/scripts/cmp_comunes.py --par A/audit.csv B/audit.csv
"""
import csv
import os
import sys


def comparar(a, b):
    ra = list(csv.DictReader(open(a)))
    rb = list(csv.DictReader(open(b)))
    cols = [c for c in ra[0] if c in rb[0]]
    dif = sorted({c for x, y in zip(ra, rb) for c in cols if x[c] != y[c]})
    return len(ra), len(rb), len(cols), len(rb[0]) - len(cols), dif


if sys.argv[1] == "--par":
    na, nb, nc, nn, dif = comparar(sys.argv[2], sys.argv[3])
    print(f"{na}/{nb} filas, {nc} columnas comunes, {nn} nuevas; distintas: {dif}")
    sys.exit(0)
base, new = sys.argv[1], sys.argv[2]
iguales, distintos, faltan = 0, [], []
for caso in sorted(os.listdir(base)):
    b = f"{new}/{caso}/audit.csv"
    if not os.path.exists(b):
        faltan.append(caso)
        continue
    na, nb, nc, nn, dif = comparar(f"{base}/{caso}/audit.csv", b)
    if na == nb and not dif:
        iguales += 1
    else:
        distintos.append((caso, na, nb, dif))
print(f"{iguales} identicos en las columnas comunes; {len(distintos)} distintos; faltan {faltan}")
for c, na, nb, dif in distintos:
    print(f"  {c}: filas {na}/{nb}, columnas distintas {dif}")
