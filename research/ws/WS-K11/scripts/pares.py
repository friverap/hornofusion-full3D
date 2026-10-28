#!/usr/bin/env python3
"""WS-K11: diferencia relativa maxima entre dos bancos que solo difieren en
una clave (u_gas_max, p_max, m_gas), en los pasos 0-10 y en toda la ventana,
y pasos con celdas nolink de cada uno. Solo lectura.

Uso: python3 research/ws/WS-K11/scripts/pares.py DIR_1 DIR_2 [DIR_1 DIR_2 ...]
"""
import csv
import sys


def load(d):
    return {int(x["step"]): x for x in csv.DictReader(open(f"{d}/audit.csv"))}


a = sys.argv[1:]
for d1, d2 in zip(a[0::2], a[1::2]):
    A, B = load(d1), load(d2)
    s = sorted(set(A) & set(B))
    print(f"== {d1} frente a {d2}: {len(s)} pasos comunes")
    for c in ("u_gas_max", "p_max", "m_gas"):
        r = [abs(float(A[k][c]) - float(B[k][c])) / abs(float(A[k][c])) for k in s]
        print(f"   {c}: pasos 0-10 max rel {max(r[:11]):.1e}; ventana max rel {max(r):.1e}")
    for d, X in ((d1, A), (d2, B)):
        n = sum(float(x["m_gas_cells_nolink"]) > 0 for k, x in X.items() if k > s[0] + 1)
        print(f"   nolink {d}: {n} pasos")
