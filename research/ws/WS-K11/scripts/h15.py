#!/usr/bin/env python3
"""Medida pre-registrada de H15 (WS-K11): pico de los pasos 2-10 tras el
reinicio en dos brazos de control, y lectura de toda la ventana (maximo con su
paso y pasos con p_max >= 100 kPa por cuartos).

Uso: python3 research/ws/WS-K11/scripts/h15.py DIR_A PASO0_A DIR_B PASO0_B
"""
import csv
import sys


def medir(d, p0):
    r = [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > p0]
    w = [x for x in r if p0 + 2 <= int(x["step"]) <= p0 + 10]
    um = max(float(x["u_gas_max"]) for x in w)
    pm = max(float(x["p_max"]) for x in w)
    mx = max(r[1:], key=lambda x: float(x["p_max"]))
    n = len(r) - 1
    q = [sum(float(x["p_max"]) >= 1e5 for x in r[1:][i * n // 4:(i + 1) * n // 4]) for i in range(4)]
    print(f"== {d}: pasos {p0+2}-{p0+10}: max u_gas_max {um:.1f} m/s, max p_max {pm/1e3:.0f} kPa; ventana: "
          f"max p_max {float(mx['p_max'])/1e3:.0f} kPa en {mx['step']}, max u_gas_max "
          f"{max(float(x['u_gas_max']) for x in r[1:]):.1f} m/s; pasos >= 100 kPa por cuartos {q}")
    log = open(f"{d}/run.log", errors="replace").read()
    print(f"   [CG] AVISO: {log.count('[CG] AVISO')}")
    pico = um >= 200 or pm >= 3e5
    limpio = um < 200 and pm < 3e5
    return pico, limpio


args = sys.argv[1:]
picoA, limpioA = medir(args[0], int(args[1]))
picoB, limpioB = medir(args[2], int(args[3]))
if limpioA and picoB:
    v = "SOPORTADA (la causa es el cambio de claves)"
elif picoA and limpioB:
    v = "REFUTADA (la causa es el estado/codigo del snapshot de 280 s, no las claves)"
else:
    v = "SIN DECIDIR"
print(f"brazo A: {'pico' if picoA else 'sin pico'}; brazo B: {'pico' if picoB else 'sin pico'} -> H15 {v}")
