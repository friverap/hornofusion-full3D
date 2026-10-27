#!/usr/bin/env python3
"""Medida pre-registrada del barrido de max_outer (WS-K8, C-182).

Por banco: desfase neto multifase de rem2 por paso
    D_k = m_gas_err_multi - (m_gas_err_liq_all + m_gas_err_cc_multi + m_gas_err_art_multi)
en las filas step > 280000; D1 = fila del paso 280001 (mismo estado inicial
en todos los bancos). Del run.log: '[CG] AVISO' y, por paso, las iteraciones
externas usadas y los residuos (lineas [STEP], monitor_freq = 1).

Uso: python3 research/ws/WS-K8/scripts/barrido_outer.py DIR [DIR ...]
     python3 research/ws/WS-K8/scripts/barrido_outer.py --identidad DIR_A DIR_B
"""
import csv
import re
import statistics as st
import sys


def filas(d):
    return [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > 280000]


def desfase(r):
    f = lambda x, c: float(x[c])
    return [f(x, "m_gas_err_multi") - (f(x, "m_gas_err_liq_all") + f(x, "m_gas_err_cc_multi")
                                       + f(x, "m_gas_err_art_multi")) for x in r]


def log(d):
    txt = open(f"{d}/run.log", errors="replace").read()
    avisos = txt.count("[CG] AVISO")
    pasos = []
    for m in re.finditer(r"\[STEP\]\s+(\d+)\s+t=\s*\S+\s+outer=\s*(\d+)\s+res:\s+(\S+)\s+(\S+)\s+(\S+)", txt):
        pasos.append((int(m.group(1)), int(m.group(2)), float(m.group(3)), float(m.group(4)), float(m.group(5))))
    mo = int(re.search(r"max_outer=\s*(\d+)", txt).group(1))
    return avisos, pasos, mo


def resumen(d):
    r = filas(d)
    D = desfase(r)
    dts = [float(x["dt"]) for x in r]
    avisos, pasos, mo = log(d)
    print(f"== {d}  max_outer {mo}")
    print(f"  filas {len(r)}  dt min/max {min(dts):.4e}/{max(dts):.4e}  [CG] AVISO {avisos}")
    print(f"  D1 (paso {r[0]['step']}) = {D[0]:+.4e} kg")
    print(f"  media D = {st.mean(D):+.4e}  sd {st.stdev(D):.3e}  sd/|media| {st.stdev(D)/abs(st.mean(D)):.3f}"
          f"  negativos {sum(x < 0 for x in D)}/{len(D)}  media D/dt {st.mean([a/b for a, b in zip(D, dts)]):+.4e} kg/s")
    if pasos:
        p1 = pasos[0]
        no_conv = sum(1 for p in pasos if p[1] >= mo)
        print(f"  externas paso {p1[0]}: {p1[1]} (res u {p1[2]:.3e}, cont {p1[3]:.3e}, energia {p1[4]:.3e})")
        print(f"  pasos con externas = max_outer (no convergidos): {no_conv}/{len(pasos)};"
              f" externas media {st.mean(p[1] for p in pasos):.1f}")
    else:
        print("  sin lineas [STEP] (monitor_freq != 1)")
    return D[0], st.mean(D)


def identidad(a, b):
    ra = list(csv.DictReader(open(f"{a}/audit.csv")))
    rb = list(csv.DictReader(open(f"{b}/audit.csv")))
    cols = [c for c in ra[0] if c in rb[0]]
    dif = [c for c in cols if any(x[c] != y[c] for x, y in zip(ra, rb))]
    print(f"{a} frente a {b}: {len(ra)}/{len(rb)} filas, {len(cols)} columnas, distintas: {dif}")


if __name__ == "__main__":
    if sys.argv[1] == "--identidad":
        identidad(sys.argv[2], sys.argv[3])
    else:
        res = {d: resumen(d) for d in sys.argv[1:]}
