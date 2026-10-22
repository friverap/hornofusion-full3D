#!/usr/bin/env python3
"""Convergencia del conjunto activo del Plan K desde las lineas [PROBE-AI].

Uso: plank_conv.py run.log [--tol 1e-6]
Un solve empieza en 'it 1'. Convergido si su ultima linea tiene
(caras_fijas 0 y cambios 0) o (it > 1, cambios 0 y ds < tol), que son las
salidas de alpha_implicit_active_set; si no, llego al tope (pc_ai_max_it).
"""
import argparse, re
ap = argparse.ArgumentParser(); ap.add_argument("log"); ap.add_argument("--tol", type=float, default=1e-6)
a = ap.parse_args()
pat = re.compile(r'\[PROBE-AI\] paso\s+(\d+) it\s+(\d+) caras_fijas\s+(\d+) cambios\s+(\d+) ds\s+(\S+)')
solves, cur = [], None
for line in open(a.log, errors="replace"):
    m = pat.search(line)
    if not m:
        continue
    st, it, nf, ch, ds = int(m[1]), int(m[2]), int(m[3]), int(m[4]), float(m[5])
    if it == 1:
        if cur: solves.append(cur)
        cur = []
    if cur is not None:
        cur.append((st, it, nf, ch, ds))
if cur: solves.append(cur)
def conv(s):
    st, it, nf, ch, ds = s[-1]
    return (nf == 0 and ch == 0) or (it > 1 and ch == 0 and ds < a.tol)
nc = sum(not conv(s) for s in solves)
its = [s[-1][1] for s in solves]
print("solves=%d sin_converger=%d (%.1f %%) it_medio=%.2f caras_fijas_max=%d"
      % (len(solves), nc, 100.0 * nc / max(len(solves), 1), sum(its) / max(len(its), 1),
         max((x[2] for s in solves for x in s), default=0)))
