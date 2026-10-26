"""rho_g medio del dominio, masa de gas reconstruida, rho_g y u_z del liquido en las celdas 'nogas' de un snapshot.

Uso: python3 research/ws/WS-K7/scripts/rho_uz_nogas.py campaigns/b1/k7v5_mo20/eaf3d_00280059.h5
  Volumenes de celda reconstruidos de mesh/r y mesh/z con caras en los puntos medios (extremos
  extrapolados, r >= 0) y dtheta = 2 pi / ntheta. nogas = cell_type != 0, max(al, asl, as) >= 1e-2, ag == 0.
"""
import sys, h5py, numpy as np
f = h5py.File(sys.argv[1], 'r'); F = lambda k: f['fields/' + k][...]
ag, al, asl, as_ = F('alpha_gas'), F('alpha_liquid'), F('alpha_slag'), F('alpha_solid')
rho = f['restart/rho_gas'][...]; ct = f['mesh/cell_type'][...]
r, th, z = f['mesh/r'][...], f['mesh/theta'][...], f['mesh/z'][...]
def edges(c):
    m = 0.5 * (c[1:] + c[:-1]); return np.concatenate([[c[0] - (m[0] - c[0])], m, [c[-1] + (c[-1] - m[-1])]])
re_, ze = edges(r), edges(z); re_[0] = max(re_[0], 0.0)
V = (0.5 * (re_[1:] ** 2 - re_[:-1] ** 2))[None, None, :] * (2 * np.pi / len(th)) * (ze[1:] - ze[:-1])[:, None, None]
act = ct != 0
mg = (ag * rho * V)[act].sum(); vg = (ag * V)[act].sum()
nog = act & (np.maximum(np.maximum(al, asl), as_) >= 1e-2) & (ag == 0.0)
uz = F('velocity_z_liquid')[nog]
print(f"masa de gas reconstruida {mg:.4f} kg; V_gas {vg:.2f} m3; rho_g medio {mg / vg:.5f} kg/m3")
print(f"nogas {int(nog.sum())}: rho_g mediana {np.median(rho[nog]):.4f} (rango {rho[nog].min():.4f}-{rho[nog].max():.4f}) kg/m3; "
      f"u_z liquido p10 {np.percentile(uz, 10):.3f}, mediana {np.median(uz):.4f}, p90 {np.percentile(uz, 90):.3f} m/s")
