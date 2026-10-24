#!/usr/bin/env python3
"""Metricas del banco del primer pico (WS-K3, C-090): max|p| del CAMPO por
snapshot desde los resumenes de phantom_scan (DIR/phantom/<paso>.npz).
Uso: bench_metric.py DIR [DIR...]   (pasos 341501-341720)"""
import glob, os, sys
import numpy as np
for d in sys.argv[1:]:
    P = {}
    for f in glob.glob(os.path.join(d, 'phantom', '*.npz')):
        s = int(os.path.basename(f)[:8])
        if 341501 <= s <= 341720: P[s] = float(np.load(f)['pmax'])
    if not P: print(f'{d}: sin resumenes'); continue
    pk = max(v for s, v in P.items() if s >= 341690) if any(s >= 341690 for s in P) else float('nan')
    print(f'{d}: pasos {len(P)} | max|p| 341690-720 {pk:.3e} | max|p| ventana {max(P.values()):.3e} '
          f'| pasos >1e5 {sum(v > 1e5 for v in P.values())} | ultimo paso {max(P)}')
