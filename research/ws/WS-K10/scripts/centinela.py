#!/usr/bin/env python3
"""WS-K10 ciclo 2: (1) sensibilidad del cociente pre-registrado de C-212 a los
pasos del banco de 0.25 ms con la centinela U_GAS_MAX (280002-280004) y
(2) cociente por paso de e en los pasos tranquilos (p_max < 100 kPa) con IC90
por bootstrap de bloques de 10 ms (4000 replicas, semilla 1).

Uso: python3 research/ws/WS-K10/scripts/centinela.py DIR_1MS DIR_05MS DIR_025MS
"""
import csv
import random
import statistics as st
import sys


def filas(d):
    return [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > 280000]


def r(rows, dt, cols):
    return st.mean(sum(float(x[c]) for c in cols) for x in rows) / dt


a, b, c = (filas(d) for d in sys.argv[1:4])
E, G = ("m_gas_err_multi",), ("m_gas_bg_q_multi", "m_gas_err_cc_multi")
print("== banco de 0.25 ms, pasos 280001-280005: u_gas_max [m/s], p_max [kPa], e/dt [kg/s]")
for x in c[:5]:
    print(f"  {x['step']}: {float(x['u_gas_max']):.1f}, {float(x['p_max'])/1e3:.0f}, {float(x['m_gas_err_multi'])/2.5e-4:+.3e}")
for nombre, excl in (("sin 280001 (criterio)", {280001}), ("sin 280001-280003", {280001, 280002, 280003}),
                     ("sin 280001-280004", {280001, 280002, 280003, 280004}), ("sin 280001 ni 280003", {280001, 280003})):
    cc = [x for x in c if int(x["step"]) not in excl]
    print(f"{nombre}: r(0.25)/r(0.5) de e {r(cc, 2.5e-4, E)/r(b[1:], 5e-4, E):.3f}, "
          f"de Bgq + err_cc {r(cc, 2.5e-4, G)/r(b[1:], 5e-4, G):.3f}")
q = lambda rows: [float(x["m_gas_err_multi"]) for x in rows[1:] if float(x["p_max"]) < 1e5]
qa, qb, qc = q(a), q(b), q(c)
rng = random.Random(1)


def boot(v, blk):
    nb = len(v) // blk
    bl = [v[i * blk:(i + 1) * blk] for i in range(nb)]
    out = []
    for _ in range(4000):
        m = []
        for _ in range(nb):
            m.extend(rng.choice(bl))
        out.append(st.mean(m))
    return out


rr = sorted(x / y for x, y in zip(boot(qb, 20), boot(qa, 10)))
print(f"pasos tranquilos (p_max < 100 kPa; n {len(qa)}, {len(qb)}, {len(qc)}): e por paso 0.5/1 = "
      f"{st.mean(qb)/st.mean(qa):.3f} (IC90 {rr[200]:.3f}-{rr[3799]:.3f}), 0.25/0.5 = {st.mean(qc)/st.mean(qb):.3f}")
