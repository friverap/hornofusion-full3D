#!/usr/bin/env python3
"""WS-K10, panel ronda 2: confusor del regimen de presion entre dt y barras
de error por bootstrap de bloques de los cocientes por unidad de tiempo.
Sin el paso 280001 (transitorio del acotado de dt).

Uso: python3 research/ws/WS-K10/scripts/regimen.py DIR_1MS DIR_05MS DIR_025MS
"""
import csv
import random
import statistics as st
import sys

G = {"e": ("m_gas_err_multi",), "Bgq + err_cc": ("m_gas_bg_q_multi", "m_gas_err_cc_multi"),
     "err_liq + A": ("m_gas_err_liq_all", "m_gas_pa_multi")}


def filas(d):
    return [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > 280000][1:]


dirs = sys.argv[1:4]
R = [filas(d) for d in dirs]
dts = [st.mean(float(x["dt"]) for x in r) for r in R]
print("== regimen de presion por banco (sin el paso 1)")
for d, r in zip(dirs, R):
    p = [float(x["p_max"]) for x in r]
    n = len(r)
    dec = [st.mean(p[i * n // 10:(i + 1) * n // 10]) / 1e3 for i in range(10)]
    print(f"{d}: n {n}, p_max >= 100 kPa en {sum(v >= 1e5 for v in p)}, >= 300 kPa en {sum(v >= 3e5 for v in p)}, "
          f"max {max(p)/1e3:.0f} kPa; media por decimo [kPa] " + " ".join(f"{v:.0f}" for v in dec))
    e = [float(x["m_gas_err_multi"]) for x in r]
    dt = dts[dirs.index(d)]
    lo = [a for a, v in zip(e, p) if v < 1e5]
    hi = [a for a, v in zip(e, p) if v >= 1e5]
    print(f"    e/dt con p_max < 100 kPa: {st.mean(lo)/dt:+.3e} kg/s (n {len(lo)})"
          + (f"; con p_max >= 100 kPa: {st.mean(hi)/dt:+.3e} (n {len(hi)})" if hi else "")
          + f"; corr(e, p_max) {st.correlation(e, p):+.2f}")
print("== bootstrap de bloques (10/20/40 pasos para 1/0.5/0.25 ms: 10 ms de ventana), 4000 replicas, semilla 1; IC90")
rng = random.Random(1)
blk = [10, 20, 40]


def boot(serie, b):
    nb = len(serie) // b
    bloques = [serie[i * b:(i + 1) * b] for i in range(nb)]
    out = []
    for _ in range(4000):
        m = []
        for _ in range(nb):
            m.extend(rng.choice(bloques))
        out.append(st.mean(m))
    return out


for nombre, cols in G.items():
    s = [[sum(float(x[c]) for c in cols) / dt for x in r] for r, dt in zip(R, dts)]
    bs = [boot(v, b) for v, b in zip(s, blk)]
    for i, j in ((1, 0), (2, 1)):
        q = sorted(a / b for a, b in zip(bs[i], bs[j]))
        print(f"{nombre}: r({['1', '0.5', '0.25'][i]})/r({['1', '0.5', '0.25'][j]}) = "
              f"{st.mean(s[i])/st.mean(s[j]):.3f}, IC90 {q[200]:.3f}-{q[3799]:.3f}")
