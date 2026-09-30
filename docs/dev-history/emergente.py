#!/usr/bin/env python3
"""Caracteriza el fenomeno emergente de la ventana 200-211 s: sigue, snapshot a
snapshot, el estado de las celdas bajo los electrodos y el regimen de acople
gas-liquido que les toca (F2.15: cizalla si hay chatarra propia o debajo;
relajacion dispersa TAU_LG si no).
Uso: emergente.py DIR
"""
import sys, glob, os
import h5py, numpy as np

rho_l = 7500.0; TAU_LG = 0.01; C_FS = 0.5; mu_l = 6.0e-3; d_p = 0.10; G = 9.81

def main():
    d = sys.argv[1]
    fs = sorted(glob.glob(os.path.join(d, 'eaf3d_*.h5')))
    print('    t    | n_cap | n_TAU | as_eff bajo arco (j=0/20/40) | u_liq_max | p_max   en (i,j,k)   regimen')
    for fn in fs:
        with h5py.File(fn) as f:
            g = f['fields']
            t = float(np.asarray(f['metadata'].attrs['time']).ravel()[0])
            al = g['alpha_liquid'][...]; ag = g['alpha_gas'][...]
            as_ = g['alpha_solid'][...]; p = g['pressure'][...]
            Tg = g['T_gas'][...]
            ur = g['velocity_r_liquid'][...]; ut = g['velocity_th_liquid'][...]
            uz = g['velocity_z_liquid'][...]; wz = g['velocity_z_gas'][...]
        sp = np.sqrt(ur**2 + ut**2 + uz**2)
        liq = al >= 1e-2
        onb = np.zeros_like(al, bool)
        onb[1:] = (as_[1:] > 1e-4) | (as_[:-1] >= 1e-2)
        # continuo: fraccion propia o regla de superficie libre (celda de bano debajo)
        cont = al >= 0.3
        cont[1:] |= (al[1:] > 0) & (al[:-1] >= 0.3)
        cap = liq & cont & (sp >= 19.5)
        tau = liq & cont & ~onb
        asef = [max(as_[5, j, 12], as_[4, j, 12]) for j in (0, 20, 40)]
        k, j, i = np.unravel_index(p.argmax(), p.shape)
        reg = 'cizalla' if onb[k, j, i] else ('TAU_LG' if cont[k, j, i] else 'sin-liq')
        print('%8.3f | %5d | %5d | %.4f %.4f %.4f          | %9.2f | %8.4g (%2d,%2d,%2d) %s'
              % (t, cap.sum(), tau.sum(), asef[0], asef[1], asef[2],
                 sp[liq & cont].max() if (liq & cont).any() else 0.0,
                 p.max(), i, j, k, reg))

if __name__ == '__main__':
    main()
