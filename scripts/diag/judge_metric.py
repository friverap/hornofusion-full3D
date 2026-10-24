#!/usr/bin/env python3
"""Metricas del juez denso de B1 340-345.5 s (WS-K3, C-092): max|p| del CAMPO
por snapshot desde los resumenes de phantom_scan (DIR/phantom/<paso>.npz).
Uso: judge_metric.py DIR [DIR...]"""
import glob, os, sys
import numpy as np
GAP = 5
for d in sys.argv[1:]:
    P = {}
    for f in glob.glob(os.path.join(d, 'phantom', '*.npz')):
        P[int(os.path.basename(f)[:8])] = float(np.load(f)['pmax'])
    if not P: print(f'{d}: sin resumenes'); continue
    s = sorted(P); hi = [x for x in s if P[x] > 3e5]
    ev = [x for x in hi if not any(0 < x - y <= GAP for y in hi if y < x)]
    print(f'{d}: pasos {len(P)} ({s[0]}-{s[-1]}) | pico {max(P.values()):.3e} | pasos >1e5 {sum(v > 1e5 for v in P.values())} '
          f'| pasos >3e5 {len(hi)} | eventos >3e5 {len(ev)}')
