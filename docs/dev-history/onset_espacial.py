#!/usr/bin/env python3
"""Estructura espacial del arranque: distingue una respuesta FORZADA bajo cada
arco (pocas celdas, en la huella del electrodo) de un tren de ondas de
Kelvin-Helmholtz de escala de malla (celdas alternadas a lo largo de theta).
Uso: onset_espacial.py DIR
"""
import sys, glob, os
import h5py, numpy as np

def main():
    d = sys.argv[1]
    for fn in sorted(glob.glob(os.path.join(d, 'eaf3d_*.h5'))):
        with h5py.File(fn) as f:
            g = f['fields']
            t = float(np.asarray(f['metadata'].attrs['time']).ravel()[0])
            al = g['alpha_liquid'][...]; as_ = g['alpha_solid'][...]
            uz = g['velocity_z_liquid'][...]; wz = g['velocity_z_gas'][...]
            ur = g['velocity_r_liquid'][...]; ut = g['velocity_th_liquid'][...]
        sp = np.sqrt(ur**2 + ut**2 + uz**2)
        cont = al >= 0.3
        cont[1:] |= (al[1:] > 0) & (al[:-1] >= 0.3)
        act = (al >= 1e-2) & cont
        if not act.any():
            continue
        v = np.where(act, sp, 0.0)
        if v.max() < 0.5:
            continue
        kk, jj, ii = np.where(v > 0.5 * v.max())
        # signo de uz en las celdas rapidas: alternancia => onda; mismo signo => forzado
        sg = np.sign(uz[kk, jj, ii])
        print('t=%8.3f  u_max=%6.2f  n(>50%%)=%3d  j={%s}  i={%s}  k={%s}  signo uz: %+d/%+d  u_gas_loc=%.0f'
              % (t, v.max(), len(kk),
                 ','.join(str(x) for x in sorted(set(jj.tolist()))[:12]),
                 ','.join(str(x) for x in sorted(set(ii.tolist()))[:8]),
                 ','.join(str(x) for x in sorted(set(kk.tolist()))[:6]),
                 int((sg > 0).sum()), int((sg < 0).sum()),
                 np.abs(wz[kk, jj, ii]).mean()))

if __name__ == '__main__':
    main()
