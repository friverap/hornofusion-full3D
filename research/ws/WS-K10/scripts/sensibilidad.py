#!/usr/bin/env python3
"""WS-K10 ciclo 2 (revision previa): sensibilidad de los cocientes entre dt
(1) al umbral de p_max que define los pasos 'tranquilos' y (2) a excluir una
VENTANA FISICA inicial (t > t0) en vez de un numero de pasos. Lectura, no
decide nada.

Uso: python3 research/ws/WS-K10/scripts/sensibilidad.py DIR_1MS DIR_05MS DIR_025MS
"""
import csv
import statistics as st
import sys


def filas(d):
    return [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > 280000]


a, b, c = (filas(d) for d in sys.argv[1:4])
E, G = ("m_gas_err_multi",), ("m_gas_bg_q_multi", "m_gas_err_cc_multi")
v = lambda rows, cols: [sum(float(x[k]) for k in cols) for x in rows]
print("== umbral de p_max (pasos tranquilos, sin el paso 280001): e por paso 0.5/1 y 0.25/0.5")
for thr in (60e3, 80e3, 100e3, 120e3, 150e3):
    q = lambda rows: [y for y, x in zip(v(rows[1:], E), rows[1:]) if float(x["p_max"]) < thr]
    qa, qb, qc = q(a), q(b), q(c)
    print(f"  p_max < {thr/1e3:.0f} kPa (n {len(qa)}, {len(qb)}, {len(qc)}): {st.mean(qb)/st.mean(qa):.3f}, "
          f"{st.mean(qc)/st.mean(qb):.3f}")
print("== ventana fisica t > t0 (mismas t en los tres bancos): r = media por paso / dt")
for t0 in (280.002, 280.010, 280.020, 280.030):
    w = lambda rows: [x for x in rows if float(x["time"]) > t0]
    wa, wb, wc = w(a), w(b), w(c)
    r = lambda rows, dt, cols: st.mean(v(rows, cols)) / dt
    print(f"  t > {t0:.3f} s (n {len(wa)}, {len(wb)}, {len(wc)}): e por paso 0.5/1 {st.mean(v(wb,E))/st.mean(v(wa,E)):.3f}; "
          f"r(0.25)/r(0.5) de e {r(wc,2.5e-4,E)/r(wb,5e-4,E):.3f}, de Bgq + err_cc {r(wc,2.5e-4,G)/r(wb,5e-4,G):.3f}")
