#!/usr/bin/env python3
"""Medida pre-registrada de H17/H18 (WS-K11): cada brazo cambia UNA clave
sobre el estado de 280 s respecto de su escritor. Misma definicion de pico que
h15.py: en los pasos 280002-280010, max u_gas_max >= 200 m/s o max p_max >=
300 kPa. Lectura de toda la ventana como en h15.py.

H17 (brazo E) predice pico; H18 (brazo F) predice que no lo hay.

Uso: python3 research/ws/WS-K11/scripts/h17.py DIR_E DIR_F
"""
import csv
import sys

P0 = 280000


def medir(d):
    r = [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > P0]
    w = [x for x in r if P0 + 2 <= int(x["step"]) <= P0 + 10]
    um = max(float(x["u_gas_max"]) for x in w)
    pm = max(float(x["p_max"]) for x in w)
    mx = max(r[1:], key=lambda x: float(x["p_max"]))
    n = len(r) - 1
    q = [sum(float(x["p_max"]) >= 1e5 for x in r[1:][i * n // 4:(i + 1) * n // 4]) for i in range(4)]
    print(f"== {d}: pasos {P0+2}-{P0+10}: max u_gas_max {um:.1f} m/s, max p_max {pm/1e3:.0f} kPa; ventana: "
          f"max p_max {float(mx['p_max'])/1e3:.0f} kPa en {mx['step']}, max u_gas_max "
          f"{max(float(x['u_gas_max']) for x in r[1:]):.1f} m/s; n {n}; pasos >= 100 kPa por cuartos {q}")
    avisos = open(f"{d}/run.log", errors="replace").read().count("[CG] AVISO")
    print(f"   [CG] AVISO: {avisos}")
    return um >= 200 or pm >= 3e5, avisos


# H17 predice pico al cambiar solo la presion total; H18 predice que cambiar
# solo f28 NO da pico.
for h, d, clave, predice_pico in (("H17", sys.argv[1], "pc_outlet_total_pressure", True),
                                  ("H18", sys.argv[2], "pc_transport_f28", False)):
    pico, avisos = medir(d)
    if avisos:
        v = "FALLIDA (prerrequisito: [CG] AVISO en el brazo)"
    else:
        v = "SOPORTADA" if pico == predice_pico else "REFUTADA"
    print(f"{h}: cambiar solo {clave}: {'pico' if pico else 'sin pico'} -> {v}")
