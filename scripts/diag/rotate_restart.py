#!/usr/bin/env python3
"""Gira un snapshot de reinicio N celdas en theta (prueba de la costura, WS-K3).

Todos los campos 3D [k,j,i] de /fields, /restart y /mesh/cell_type se
desplazan +N en j (componentes r/theta/z son cilindricas: el giro las deja
igual). Los atributos por electrodo se permutan con el giro de los
electrodos: con N = nth/3 el material del electrodo e queda bajo el e+1.
Uso: rotate_restart.py ENTRADA.h5 SALIDA.h5 N
"""
import shutil, sys
import numpy as np, h5py

src, dst, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
shutil.copyfile(src, dst)
with h5py.File(dst, 'r+') as h:
    nth = h['mesh/theta'].shape[0]
    assert (3 * n) % nth == 0, 'el giro debe ser multiplo de 120 grados'
    shift_e = 3 * n // nth
    for g in ('fields', 'restart'):
        for k, ds in h[g].items():
            assert ds.ndim == 3 and ds.shape[1] == nth, (g, k, ds.shape)
            ds[...] = np.roll(ds[()], n, axis=1)
    ct = h['mesh/cell_type']; ct[...] = np.roll(ct[()], n, axis=1)
    for k, v in list(h['restart'].attrs.items()):
        if k.startswith('elec_'):
            h['restart'].attrs[k] = np.roll(v, shift_e)
