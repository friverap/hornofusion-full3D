#!/usr/bin/env python3
"""WS-K11: copia el snapshot de reinicio y pone /restart/Tg_end = /fields/T_gas
(quita el salto de densidad entre el final del SIMPLE y el estado final que
hereda el primer Poisson tras el reinicio). Imprime el salto que se quita.

Uso: python3 research/ws/WS-K11/scripts/snap_tgfix.py ORIGEN.h5 DESTINO.h5
"""
import shutil
import sys

import h5py
import numpy as np

src, dst = sys.argv[1], sys.argv[2]
shutil.copyfile(src, dst)
with h5py.File(dst, "r+") as f:
    T = np.array(f["fields/T_gas"])
    tg = np.array(f["restart/Tg_end"])
    ag = np.array(f["fields/alpha_gas"])
    m = (ag > 1e-6) & (tg > 0)
    d = np.abs(T[m] / tg[m] - 1.0)
    print(f"celdas con gas y Tg_end > 0: {m.sum()}; |T/Tg_end - 1|: max {d.max():.3f}, p99 {np.quantile(d, 0.99):.3f}, mediana {np.median(d):.2e}")
    f["restart/Tg_end"][...] = T
print(f"escrito {dst}")
