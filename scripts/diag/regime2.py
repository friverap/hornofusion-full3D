#!/usr/bin/env python3
"""Regimen acotado v2 (10-oct): sin p>20k (hidrostatica cuando el lecho carga
su peso). Por ventana: % pasos p>100k, gas>200, centinela de p o gas
(P_HYDRO_CAP / U_GAS_MAX), u_liq_max>=U_LIQ_MAX aparte (OJO: u_liq_max del
audit incluye el liquido DISPERSO, no solo el continuo), p_max, gas_max.
Cada corrida es un directorio con audit.csv (ruta absoluta o relativa al cwd).
Uso: regime2.py dir1 dir2 ... [--w t0,t1,t0,t1,...]"""
import csv, os, sys
P, UG, UL = 2e6, 300., 20.
argv = sys.argv[1:]
skip = {i + 1 for i, a in enumerate(argv) if a == "--w"}
args = [a for i, a in enumerate(argv) if not a.startswith("--") and i not in skip]
W = [(300,305),(305,310),(310,315),(315,320),(320,325),(325,345)]
if "--w" in sys.argv:
    v = [float(x) for x in sys.argv[sys.argv.index("--w")+1].split(",")]; W = list(zip(v[::2], v[1::2]))
for r in args:
    p = os.path.join(r, "audit.csv")
    if not os.path.exists(p): print(r, "sin audit"); continue
    rows = list(csv.DictReader(open(p), skipinitialspace=True))
    print(f"== {r}  (t_fin {float(rows[-1]['time']):.2f})")
    print(f"   {'ventana':>9s} {'n':>5s} | {'p>100k':>6s} {'g>200':>6s} {'cent_pg':>7s} {'ul>=20':>6s} | {'pmax':>8s} {'gmax':>5s}")
    for t0, t1 in W:
        s = [x for x in rows if t0 <= float(x["time"]) < t1]
        if not s: continue
        n = len(s); f = lambda k: [float(x[k]) for x in s]
        pm, gm, lm = f("p_max"), f("u_gas_max"), f("u_liq_max")
        pc = lambda v, th: 100*sum(a > th for a in v)/n
        cpg = 100*sum(a >= P or b >= UG for a, b in zip(pm, gm))/n
        print(f"   {t0:4.0f}-{t1:4.0f} {n:5d} | {pc(pm,1e5):6.1f} {pc(gm,200):6.1f} {cpg:7.1f} {pc(lm,UL-1e-9):6.1f} | {max(pm):8.2e} {max(gm):5.0f}")
