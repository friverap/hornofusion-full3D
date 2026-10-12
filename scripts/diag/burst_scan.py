"""Escaneo de rafagas en una serie densa de snapshots: para cada snapshot,
celdas con |p| > PTH y gas > GTH, con su estado y el cambio de estado
respecto del snapshot anterior (cruces de umbral de alpha_g, alpha_l,
hueco de poro). Indices impresos 1-based (i,j,k) como Fortran."""
import sys, glob, h5py, numpy as np
d = sys.argv[1]; PTH = float(sys.argv[2]) if len(sys.argv) > 2 else 1e5
GTH = 200.0
AFC, APG, ALC = 1e-2, 1.5e-2, 0.3
files = sorted(glob.glob(f'{d}/eaf3d_*.h5'))
prev = None
def load(fn):
    f = h5py.File(fn, 'r'); g = f['fields']
    t = float(f['metadata'].attrs['time'][0]) if 'metadata' in f else float('nan')
    D = {k: g[k][...] for k in ('pressure','alpha_liquid','alpha_gas','alpha_solid',
         'velocity_r_gas','velocity_th_gas','velocity_z_gas','velocity_z_liquid','velocity_r_liquid','velocity_th_liquid')}
    f.close(); return t, D
def cap(as_, asl=0.0):
    c = 1 - as_ - asl
    return np.where(as_ >= 1e-2, c - APG, c)
for fn in files:
    t, D = load(fn)
    p = D['pressure']; al = D['alpha_liquid']; ag = D['alpha_gas']; as_ = D['alpha_solid']
    ug = np.sqrt(D['velocity_r_gas']**2 + D['velocity_th_gas']**2 + D['velocity_z_gas']**2)
    room = cap(as_) - al
    big = np.abs(p) > PTH; fast = ug > GTH
    nb, nf = big.sum(), fast.sum()
    line = f"{fn.split('/')[-1]} t={t:.3f} |p|>{PTH:.0e}: {nb:3d}  gas>{GTH:.0f}: {nf:3d}  pmax={np.abs(p).max():.2e} gmax={ug.max():.0f}"
    if prev is not None:
        alp, agp, asp = prev['alpha_liquid'], prev['alpha_gas'], prev['alpha_solid']
        # cruces de umbral en todo el dominio
        gcross = ((agp >= AFC) & (ag < AFC)).sum(); gcross_up = ((agp < AFC) & (ag >= AFC)).sum()
        lcont = ((alp < ALC) & (al >= ALC) & (as_ < 1e-2)).sum()
        sat = ((cap(asp) - alp > 1e-4) & (room <= 1e-4) & (as_ >= 1e-2)).sum()
        line += f"  | cruces: ag<1e-2 {gcross} ag>=1e-2 {gcross_up} liq->cont {lcont} poro->sat {sat}"
    print(line)
    idx = np.argwhere(big | fast)
    # ordenar por |p|
    idx = sorted(idx.tolist(), key=lambda x: -abs(p[tuple(x)]))[:6]
    for (k, j, i) in idx:
        s = f"    ({i+1},{j+1},{k+1}) p={p[k,j,i]:+.2e} al={al[k,j,i]:.3f} ag={ag[k,j,i]:.4f} as={as_[k,j,i]:.3f} room={room[k,j,i]:+.4f} ug={ug[k,j,i]:.0f} uz_l={D['velocity_z_liquid'][k,j,i]:+.2f}"
        if k+1 < p.shape[0]:
            s += f" | T: al={al[k+1,j,i]:.3f} ag={ag[k+1,j,i]:.4f} p={p[k+1,j,i]:+.1e} uz_l={D['velocity_z_liquid'][k+1,j,i]:+.2f}"
        if k > 0:
            s += f" | B: al={al[k-1,j,i]:.3f} ag={ag[k-1,j,i]:.4f} as={as_[k-1,j,i]:.3f} p={p[k-1,j,i]:+.1e}"
        if prev is not None:
            s += f" | prev: al={alp[k,j,i]:.3f} ag={agp[k,j,i]:.4f} p={prev['pressure'][k,j,i]:+.1e}"
        print(s)
    prev = D
