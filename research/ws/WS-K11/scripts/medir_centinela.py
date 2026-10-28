#!/usr/bin/env python3
"""Medida pre-registrada de H12 (WS-K11): u_gas_max y p_max por paso en
280001-280010 y fraccion de pasos con p_max >= 100 kPa en toda la ventana;
'[CG] AVISO' del run.log.

Uso: python3 research/ws/WS-K11/scripts/medir_centinela.py [--inicio PASO] DIR_REF DIR_PRUEBA
(--inicio: paso del snapshot de reinicio; por defecto 280000)
"""
import csv
import sys

args = sys.argv[1:]
P0 = 280000
if args and args[0] == "--inicio":
    P0 = int(args[1])
    args = args[2:]
for d in args:
    r = [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > P0]
    print(f"== {d}")
    for x in r[:10]:
        print(f"  {x['step']}: u_gas_max {float(x['u_gas_max']):6.1f} m/s, p_max {float(x['p_max'])/1e3:6.0f} kPa")
    w = [x for x in r if P0 + 2 <= int(x["step"]) <= P0 + 10]
    um = max(float(x["u_gas_max"]) for x in w)
    pm = max(float(x["p_max"]) for x in w)
    alto = sum(float(x["p_max"]) >= 1e5 for x in r[1:])
    print(f"  pasos {P0+2}-{P0+10}: max u_gas_max {um:.1f} m/s, max p_max {pm/1e3:.0f} kPa; "
          f"ventana (sin el paso 1): p_max >= 100 kPa en {alto}/{len(r)-1}")
    log = open(f"{d}/run.log", errors="replace").read()
    print(f"  [CG] AVISO en run.log: {log.count('[CG] AVISO')}")
    if d == args[-1]:
        print("  veredicto por la letra (H12 con 280000, H13 con 290000):", "SOPORTADA" if (um < 200 and pm < 3e5) else
              ("REFUTADA" if um >= 300 else "SIN DECIDIR"))
