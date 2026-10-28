#!/usr/bin/env python3
"""Medida pre-registrada de H11 (WS-K10): r(dt) = media por paso de e_multi
(y de Bgq) / dt, sin el paso 280001 (transitorio del acotado de dt al
reiniciar), con sensibilidad a descartar 2 y 4 pasos; cocientes entre dt y
ajuste r = c + b dt^p con tres dt.

Uso: python3 research/ws/WS-K10/scripts/tasa.py DIR_1MS DIR_05MS DIR_025MS
"""
import csv
import math
import statistics as st
import sys


def r(d, col, salto):
    f = [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > 280000][salto:]
    dt = st.mean(float(x["dt"]) for x in f)
    return st.mean(float(x[col]) for x in f) / dt, dt, len(f)


GRUPOS = {"Bgq + err_cc": ("m_gas_bg_q_multi", "m_gas_err_cc_multi"),
          "err_liq + A": ("m_gas_err_liq_all", "m_gas_pa_multi"),
          "Br + Bgr": ("m_gas_brho_it_multi", "m_gas_brho_end_multi", "m_gas_bg_rho_multi")}
args = sys.argv[1:]
if args and args[0] == "--grupos":
    for nombre, cols in GRUPOS.items():
        v = [sum(r(d, c, 1)[0] for c in cols) for d in args[1:4]]
        print(f"{nombre} por unidad de tiempo sin el paso 1 [lectura]: " + ", ".join(f"{x:+.4e}" for x in v)
              + f" kg/s; cocientes {v[1]/v[0]:.3f}, {v[2]/v[1]:.3f}")
    sys.exit(0)
dirs = args[0:3]
for col in ("m_gas_err_multi", "m_gas_bg_q_multi"):
    for salto in (1, 2, 4):
        v = [r(d, col, salto) for d in dirs]
        rr = [x[0] for x in v]
        dts = [x[1] for x in v]
        etiqueta = "DECIDE" if (salto == 1 and col == "m_gas_err_multi") else "lectura"
        print(f"{col} sin {salto} paso(s) [{etiqueta}]: r = " + ", ".join(f"{a:+.4e} (dt {b:.2e}, n {x[2]})" for a, b, x in zip(rr, dts, v))
              + f"; r(0.5)/r(1) = {rr[1]/rr[0]:.3f}, r(0.25)/r(0.5) = {rr[2]/rr[1]:.3f}")
        # ajuste c + b dt^p: p de la razon de diferencias (dt en progresion 2)
        d1, d2 = rr[0] - rr[1], rr[1] - rr[2]
        if d1 != 0 and d2 / d1 > 0:
            p = math.log(d1 / d2) / math.log(2.0)
            b = d1 / (dts[0] ** p - dts[1] ** p)
            c = rr[2] - b * dts[2] ** p
            print(f"    ajuste r = c + b dt^p: p = {p:.2f}, c = {c:+.3e} kg/s (parte independiente de dt), c / r(1 ms) = {c/rr[0]:.3f}")
        else:
            print("    ajuste r = c + b dt^p: no monotono, sin ajuste")
        if salto == 1 and col == "m_gas_err_multi":
            q = rr[2] / rr[1]
            print("    veredicto por la letra de H11:", "SOPORTADA (truncamiento)" if q <= 0.75 else
                  ("REFUTADA (tasa con piso)" if q >= 0.90 else "SIN DECIDIR"))
