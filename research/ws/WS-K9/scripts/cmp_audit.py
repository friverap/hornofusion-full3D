#!/usr/bin/env python3
"""WS-K9: compara bit a bit (texto de cada celda) los audit.csv de una base
guardada antes del cambio con los de tests/out tras el cambio.

Uso: python3 research/ws/WS-K9/scripts/cmp_audit.py BASE_DIR tests/out
"""
import csv
import os
import sys

base, new = sys.argv[1], sys.argv[2]
iguales, distintos, faltan = 0, [], []
for caso in sorted(os.listdir(base)):
    a = f"{base}/{caso}/audit.csv"
    b = f"{new}/{caso}/audit.csv"
    if not os.path.exists(b):
        faltan.append(caso)
        continue
    ra = list(csv.reader(open(a)))
    rb = list(csv.reader(open(b)))
    if ra == rb:
        iguales += 1
        continue
    cols = ra[0]
    dif = sorted({cols[j] for x, y in zip(ra[1:], rb[1:]) for j, (p, q) in enumerate(zip(x, y)) if p != q})
    distintos.append((caso, len(ra), len(rb), dif))
print(f"{iguales} identicos; {len(distintos)} distintos; faltan {faltan}")
for c, na, nb, dif in distintos:
    print(f"  {c}: filas {na}/{nb}, columnas distintas {dif}")
