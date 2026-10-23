#!/usr/bin/env python3
"""Celdas de LECHO (alpha_s >= ALPHA_BED) SUMERGIDAS en liquido por snapshot.

Uso: submerged_bed.py SNAP.h5 [SNAP.h5 ...] [--al 0.8] [--as-max 0.15]
Cuenta las celdas del lecho con alpha_l >= --al (sumergidas), las que tienen
chatarra escasa (alpha_s < --as-max) y las que tienen el gas en el piso de
poro (alpha_g < 1.6e-2, ALPHA_PORE_GAS = 1.5e-2): la poblacion donde el piso
de gas de poro es un residuo artificial (familia de B1 284/294/342 s).
"""
import argparse
import h5py, numpy as np
ap = argparse.ArgumentParser(); ap.add_argument("snaps", nargs="+")
ap.add_argument("--al", type=float, default=0.8); ap.add_argument("--as-max", dest="asmax", type=float, default=0.15)
a = ap.parse_args()
for fn in a.snaps:
    with h5py.File(fn, "r") as f:
        F = f["fields"]; s = F["alpha_solid"][()]; l = F["alpha_liquid"][()]; g = F["alpha_gas"][()]
    bed = s >= 1.0e-2; sub = bed & (l >= a.al)
    print("%s lecho=%d sumergidas=%d chatarra<%.2f=%d gas_en_piso=%d as_mediana=%s"
          % (fn, bed.sum(), sub.sum(), a.asmax, (sub & (s < a.asmax)).sum(), (sub & (g < 1.6e-2)).sum(),
             "%.3f" % np.median(s[sub]) if sub.any() else "-"))
