#!/usr/bin/env python3
"""make_pocket_init.py SRC_SNAPSHOT DST (auditoria 6, M4-12).

Construye el estado inicial del banco pocket_rise a partir del snapshot del
paso 0 de bed_bath_rest (lecho frio con el poro inundado desde abajo): la
capa 8 (chatarra suelta) pasa a SATURADA (alpha_l = 1 - alpha_s - piso de
poro, a 1850 K) y las capas 6-7 quedan con gas (alpha_g 0.5). Es la bolsa de
gas bajo una capa saturada de M4-12, sin camino al freeboard.
"""
import shutil, sys
import h5py
src, dst = sys.argv[1], sys.argv[2]
shutil.copyfile(src, dst)
APG = 0.015
with h5py.File(dst, "r+") as f:
    F = f["fields"]; R = f["restart"]; ct = f["mesh/cell_type"][()]
    al = F["alpha_liquid"][()]; ag = F["alpha_gas"][()]; asl = F["alpha_solid"][()]
    Tl = F["T_liquid"][()]; lc = R["liq_cont_prev"][()]
    k = 7                       # capa 8 (indice 0)
    m = ct[k] != 0
    al[k][m] = 1.0 - asl[k][m] - APG
    ag[k][m] = APG
    Tl[k][m] = 1850.0
    lc[k][m] = 1
    F["alpha_liquid"][...] = al; F["alpha_gas"][...] = ag; F["T_liquid"][...] = Tl
    R["liq_cont_prev"][...] = lc
print(f"pocket_init escrito: {dst}")
