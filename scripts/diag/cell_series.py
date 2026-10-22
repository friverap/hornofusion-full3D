#!/usr/bin/env python3
"""Serie temporal de una celda desde los snapshots HDF5 de una corrida.

Uso: cell_series.py DIR --cell I,J,K [--steps S0,S1] [--quiet] [--rho 7000]
  I,J,K: indices FORTRAN globales (1-based, como probe_cell_i/j/k).
Imprime por snapshot: paso, p, alpha_g, alpha_l, alpha_s; y al final la
fraccion de ALTERNANCIA de dp (pasos donde el signo de p_n - p_{n-1}
cambia respecto del paso anterior) y la AMPLITUD del ciclo de 2 pasos,
osc2 = mediana |p_n - (p_{n-1} + p_{n+1})/2| (la alternancia sola no
distingue ruido de ciclo: el tramo tranquilo de B1 342.45-342.50 s ya da 0.6),
y grad_hid = max (p_k - p_{k+1}) / (rho g (z_{k+1} - z_k)): el salto de
presion con la celda de ARRIBA en unidades del gradiente hidrostatico del
liquido (1 = columna de liquido en reposo).
"""
import argparse, glob, os
import h5py, numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("dir")
ap.add_argument("--cell", required=True)
ap.add_argument("--steps")
ap.add_argument("--quiet", action="store_true")
ap.add_argument("--rho", type=float, default=7000.0,
                help="densidad del liquido para el gradiente hidrostatico de referencia [kg/m3]")
a = ap.parse_args()
i, j, k = (int(x) - 1 for x in a.cell.split(","))
s0, s1 = (int(x) for x in a.steps.split(",")) if a.steps else (0, 10**12)
rows = []
for fn in sorted(glob.glob(os.path.join(a.dir, "eaf3d_*.h5"))):
    st = int(os.path.basename(fn)[6:-3])
    if not s0 <= st <= s1:
        continue
    with h5py.File(fn, "r") as f:
        F = f["fields"]
        z = f["mesh/z"][()]
        g = (F["pressure"][k, j, i] - F["pressure"][k + 1, j, i]) / (a.rho * 9.81 * (z[k + 1] - z[k]))
        rows.append((st, F["pressure"][k, j, i], F["alpha_gas"][k, j, i],
                     F["alpha_liquid"][k, j, i], F["alpha_solid"][k, j, i], g))
if not a.quiet:
    for r in rows:
        print("%d p=%10.1f ag=%.5f al=%.5f as=%.5f grad_hid=%.2f" % r)
p = np.array([r[1] for r in rows])
if len(p) >= 3:
    d = np.sign(np.diff(p))
    alt = np.mean(d[1:] * d[:-1] < 0)
    osc2 = np.median(np.abs(p[1:-1] - 0.5 * (p[:-2] + p[2:])))
    gh = max(abs(r[5]) for r in rows)
    print("n=%d p_min=%.1f p_max=%.1f alternancia_dp=%.3f osc2=%.1f grad_hid_max=%.2f"
          % (len(p), p.min(), p.max(), alt, osc2, gh))
else:
    print("n=%d (insuficiente)" % len(p))
