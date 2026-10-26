"""Ubicacion de las celdas multifase con alpha_g = 0 al final del paso ('nogas') y clase de sus vecinas con gas.

Uso: python3 research/ws/WS-K7/scripts/nogas_vecinas.py [--tol T] snapshot.h5 [...]
  Poro = alpha_s >= 1e-2 y |alpha_g - ALPHA_PORE_GAS| < T (ALPHA_PORE_GAS = 0.015; T por defecto 1e-6:
  la igualdad exacta pierde celdas por redondeo); poro seco si alpha_l < 1e-6, saturado si no.
  Poro casi saturado (sin tolerancia): alpha_s >= 1e-2, alpha_l >= 1e-6, alpha_g < 0.02.
  Arrays h5 (nz, ntheta, nr); z crece con k (k = 0 es el fondo); theta periodico.
"""
import argparse, h5py, numpy as np

ap = argparse.ArgumentParser()
ap.add_argument('--tol', type=float, default=1e-6)
ap.add_argument('snaps', nargs='+')
a = ap.parse_args()
DIRS = {(1, 0, 0): 'encima', (-1, 0, 0): 'debajo'}
for path in a.snaps:
    f = h5py.File(path, 'r'); F = lambda k: f['fields/' + k][...]
    ag, al, asl, as_ = F('alpha_gas'), F('alpha_liquid'), F('alpha_slag'), F('alpha_solid')
    ct = f['mesh/cell_type'][...]
    nz, nt, nr = ag.shape
    multi = (ct != 0) & (np.maximum(np.maximum(al, asl), as_) >= 1e-2)
    nog = multi & (ag == 0.0)
    pore = lambda k, j, i: as_[k, j, i] >= 1e-2 and abs(ag[k, j, i] - 0.015) < a.tol
    dry = lambda k, j, i: pore(k, j, i) and al[k, j, i] < 1e-6
    nearsat = lambda k, j, i: as_[k, j, i] >= 1e-2 and al[k, j, i] >= 1e-6 and ag[k, j, i] < 0.02
    sobre = sum(1 for k, j, i in np.argwhere(nog) if k > 0 and dry(k - 1, j, i))
    cls = dict.fromkeys(['poro seco', 'poro saturado', 'lecho con gas', 'bano con gas', 'otras'], 0)
    dirn = {'encima': 0, 'debajo': 0, 'lateral': 0}
    ns_all = ns_up = 0; to_multi = 0; tot = 0; up_cells = 0
    for k, j, i in np.argwhere(nog):
        if k + 1 < nz and ct[k + 1, j, i] != 0 and ag[k + 1, j, i] > 0: up_cells += 1
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            kk, jj, ii = k + d[0], (j + d[1]) % nt, i + d[2]
            if not (0 <= kk < nz and 0 <= ii < nr) or ct[kk, jj, ii] == 0 or ag[kk, jj, ii] <= 0: continue
            tot += 1
            c = ('poro seco' if dry(kk, jj, ii) else 'poro saturado' if pore(kk, jj, ii) else
                 'lecho con gas' if as_[kk, jj, ii] >= 1e-2 else 'bano con gas' if al[kk, jj, ii] >= 0.3 else 'otras')
            cls[c] += 1
            dn = DIRS.get(d, 'lateral'); dirn[dn] += 1
            if nearsat(kk, jj, ii):
                ns_all += 1
                if dn == 'encima': ns_up += 1
            if multi[kk, jj, ii]: to_multi += 1
    n = int(nog.sum())
    print(f"{'/'.join(path.split('/')[-2:])} tol {a.tol:g}: nogas {n}, k {sorted(set(np.argwhere(nog)[:, 0].tolist()))}, "
          f"bano (al>=0.3, as<1e-2) {int((nog & (al >= 0.3) & (as_ < 1e-2)).sum())}; sobre poro seco {sobre} ({100*sobre/n:.1f} %); "
          f"con vecina con gas ENCIMA {up_cells} ({100*up_cells/n:.1f} %)")
    print(f"   caras a vecinas con gas {tot}: " + ', '.join(f"{k} {v} ({100*v/tot:.1f} %)" for k, v in cls.items()))
    print(f"   por direccion: " + ', '.join(f"{k} {v}" for k, v in dirn.items()) +
          f"; poro casi saturado {ns_all} ({100*ns_all/tot:.1f} % de todas), encima {ns_up} ({100*ns_up/max(dirn['encima'],1):.1f} % de las de encima); "
          f"caras hacia celdas multifase {to_multi}/{tot}")
