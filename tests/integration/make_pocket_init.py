#!/usr/bin/env python3
"""make_pocket_init.py SRC_SNAPSHOT DST (auditoria 6, M4-12).

Construye el estado inicial del banco pocket_rise a partir del snapshot del
paso 0 de bed_bath_rest (lecho frio con el poro inundado desde abajo): la
capa 8 (chatarra suelta) pasa a SATURADA (alpha_l = 1 - alpha_s - piso de
poro, a 1850 K); las capas 6-7 conservan el gas que ya tienen en ese
snapshot (alpha_g 0.5). Es la bolsa de gas bajo una capa saturada de M4-12,
sin camino al freeboard. La presion es la HIDROSTATICA de la nueva
estratificacion y rho_gas la de la EOS con esa presion (auditoria 7, M7-3).
"""
import shutil, sys
import numpy as np
import h5py
src, dst = sys.argv[1], sys.argv[2]
shutil.copyfile(src, dst)
# constantes del codigo (mod_constants: ALPHA_PORE_GAS, T_LIQUIDUS,
# BETA_EXPANSION, GRAVITY; rho_steel default de mod_config_3d)
APG = 0.015
RHO_L, BETA, T_REF, G = 7500.0, 1.2e-4, 1809.0, 9.81
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
    # (auditoria 7, M7-3) presion HIDROSTATICA de la nueva estratificacion, la
    # misma integral que mod_fields_3d::initialize_hydrostatic_pressure (fuerza
    # balanceada: peso de la mezcla por volumen de FLUIDO, entre centros con
    # el peso de cara): sin esto el estado heredaba la p del snapshot de origen
    # y el arranque soltaba una rafaga (gas 79.6 m/s en el paso 1) y la EOS
    # reescribia 0.16 kg de gas
    rg = R["rho_gas"][()]
    z = f["mesh/z"][()]
    Ht = float(np.ravel(f["metadata"].attrs.get("H_total", 4.5))[0]) if "H_total" in f["metadata"].attrs else 4.5
    zf_top = np.concatenate([(z[1:] + z[:-1]) / 2.0, [Ht]])
    rf = al * RHO_L * (1.0 - BETA * (Tl - T_REF)) + ag * rg
    eps = al + ag
    rf = np.where(eps > 1e-12, rf / np.where(eps > 1e-12, eps, 1.0), 0.0)
    p = np.zeros_like(al)
    nz = al.shape[0]
    for jj in range(al.shape[1]):
        for ii in range(al.shape[2]):
            ph = 0.0; kprev = -1
            for kk in range(nz - 1, -1, -1):
                if ct[kk, jj, ii] == 0:
                    continue
                if kprev < 0:
                    ph = rf[kk, jj, ii] * G * (zf_top[kk] - z[kk])
                else:
                    ph += 0.5 * (rf[kprev, jj, ii] + rf[kk, jj, ii]) * G * (z[kprev] - z[kk])
                p[kk, jj, ii] = ph; kprev = kk
    F["pressure"][...] = p
    # densidad del gas coherente con la presion nueva: la MISMA EOS que
    # mod_constants::gas_eos (rho_ref 1.2 a 300 K, P0 101325); si no, la EOS
    # la corregia de golpe en el paso 1 (0.54 kg de gas «reescrito»)
    Tg = F["T_gas"][()]
    rg_new = 1.2 * 300.0 / np.maximum(Tg, 100.0) * np.maximum(101325.0 + p, 0.05 * 101325.0) / 101325.0
    R["rho_gas"][...] = np.where(ct != 0, rg_new, R["rho_gas"][()])
print(f"pocket_init escrito: {dst}")
