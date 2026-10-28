#!/usr/bin/env python3
"""WS-K11: duracion de los eventos con el criterio de pico de H15 tras el
reinicio (sin el paso 1; no es el «nivel centinela de B1», u >= 299 m/s o
p >= 300 kPa): pasos con u_gas_max >= 200 m/s, pasos con p_max >= 300 kPa,
ultimo paso (contado desde P0) con alguno de los dos, y max u_gas_max desde
P0+5. P0 = primera fila de audit.csv. Solo lectura.

Uso: python3 research/ws/WS-K11/scripts/duracion.py DIR [DIR ...]
"""
import csv
import sys

for d in sys.argv[1:]:
    r = list(csv.DictReader(open(f"{d}/audit.csv")))
    p0 = int(r[0]["step"])
    r = [x for x in r if int(x["step"]) > p0 + 1]
    u = [int(x["step"]) for x in r if float(x["u_gas_max"]) >= 200]
    p = [int(x["step"]) for x in r if float(x["p_max"]) >= 3e5]
    ult = max(u + p) - p0 if u + p else "-"
    u5 = max(float(x["u_gas_max"]) for x in r if int(x["step"]) >= p0 + 5)
    print(f"{d}: u>=200 en {len(u)} pasos; p>=300 kPa en {len(p)}; ultimo paso con alguno: {ult}; "
          f"max u_gas_max desde P0+5: {u5:.1f} m/s")
