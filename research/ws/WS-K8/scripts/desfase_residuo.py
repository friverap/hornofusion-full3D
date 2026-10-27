#!/usr/bin/env python3
"""Lectura (no veredicto) de WS-K8: relacion entre el desfase D por paso y los
residuos del lazo externo ([STEP], monitor_freq = 1), y extrapolacion lineal de
D1 (paso 280001) frente a res_cont del paso 1 a res_cont -> 0.

Uso: python3 research/ws/WS-K8/scripts/desfase_residuo.py DIR [DIR ...]
"""
import re
import statistics as st
import sys

sys.path.insert(0, "research/ws/WS-K8/scripts")
from barrido_outer import desfase, filas, log  # noqa: E402

p1 = []
for d in sys.argv[1:]:
    r = filas(d)
    D = desfase(r)
    _, pasos, mo = log(d)
    paso = {p[0]: p for p in pasos}
    pares = [(Dk, paso[int(x["step"])]) for Dk, x in zip(D, r) if int(x["step"]) in paso]
    Dv = [a for a, _ in pares]
    ru = [p[2] for _, p in pares]
    rc = [p[3] for _, p in pares]
    print(f"{d} (max_outer {mo}): n {len(pares)}  corr(D, res_u) {st.correlation(Dv, ru):+.3f}"
          f"  corr(D, res_cont) {st.correlation(Dv, rc):+.3f}  medias res_u {st.mean(ru):.3e} res_cont {st.mean(rc):.3e}")
    p1.append((pares[0][1][3], D[0], mo))
if len(p1) >= 2:
    x = [a for a, _, _ in p1]
    y = [b for _, b, _ in p1]
    sl, ic = st.linear_regression(x, y)
    print("D1 frente a res_cont del paso 1:", ", ".join(f"N={m}: ({a:.3e}, {b:.4e})" for a, b, m in p1))
    print(f"ajuste lineal: D1 = {ic:.4e} + {sl:.4e} * res_cont  ->  D1(res_cont = 0) = {ic:.4e} kg")
