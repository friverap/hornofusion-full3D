#!/usr/bin/env python3
"""Medida pre-registrada de H14 (WS-K10, ciclo 2): r = media por paso / dt de
e_multi sin el paso 290001, desde el snapshot de 290 s; err_liq_lk por paso
del banco de 0.5 ms; y las piezas por unidad de tiempo (lectura).

Uso: python3 research/ws/WS-K10/scripts/h14.py DIR_1MS DIR_05MS DIR_025MS
"""
import csv
import statistics as st
import sys

P = {"e": ("m_gas_err_multi",), "Bgq": ("m_gas_bg_q_multi",), "err_cc": ("m_gas_err_cc_multi",),
     "err_liq": ("m_gas_err_liq_all",), "err_liq_lk": ("m_gas_err_liq_lk",), "A": ("m_gas_pa_multi",),
     "Br+Bgr": ("m_gas_brho_it_multi", "m_gas_brho_end_multi", "m_gas_bg_rho_multi")}
M = {}
for d in sys.argv[1:4]:
    r = [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > 290000][1:]
    dt = st.mean(float(x["dt"]) for x in r)
    M[d] = ({k: st.mean(sum(float(x[c]) for c in cols) for x in r) for k, cols in P.items()}, dt, len(r))
    pm = max(r, key=lambda x: float(x["p_max"]))
    print(f"{d}: n {len(r)}, dt {dt:.2e}, max p_max {float(pm['p_max'])/1e3:.0f} kPa (paso {pm['step']}), "
          f"pasos con p_max >= 100 kPa {sum(float(x['p_max']) >= 1e5 for x in r)}")
d1, d05, d025 = sys.argv[1:4]
print("por unidad de tiempo [kg/s] (1 / 0.5 / 0.25 ms) y cocientes con 1 ms:")
for k in P:
    v = [M[d][0][k] / M[d][1] for d in (d1, d05, d025)]
    print(f"  {k:10s} {v[0]:+.4e} {v[1]:+.4e} {v[2]:+.4e}   0.5/1 {v[1]/v[0]:.3f}  0.25/1 {v[2]/v[0]:.3f}")
q = (M[d05][0]["e"] / M[d05][1]) / (M[d1][0]["e"] / M[d1][1])
lk = M[d05][0]["err_liq_lk"]
print(f"(a) r(0.5)/r(1) de e = {q:.3f}: " + ("SOPORTADA" if 0.85 <= q <= 1.00 else ("REFUTADA" if q <= 0.70 else "SIN DECIDIR")))
print(f"(b) err_liq_lk por paso con 0.5 ms = {lk:.3e} kg: " + ("SOPORTADA" if 5.88e-6 <= lk <= 7.96e-6 else "REFUTADA"))
