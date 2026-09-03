#!/usr/bin/env python3
"""
plot_geometry_3d.py — Render 3D ilustrativo de la carga dentro del horno.

Toma un snapshot HDF5 real y dibuja la isosuperficie del lecho de chatarra
(alpha_solid) coloreada por su temperatura, con los tres electrodos y el
contorno de la coraza. Pensado para el README (docs/img/).

Uso:
    python3 postprocess/plot_geometry_3d.py [snapshot.h5] [salida.png]

Por defecto usa el último snapshot de campaigns/s5/base y escribe
docs/img/borein_3d.png.
"""
import glob
import os
import sys

import h5py
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import cm
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from skimage.measure import marching_cubes

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# geometría (input/config_*.dat)
R_SHELL, H_TOTAL = 3.80, 4.50
R_PCD, R_ELEC = 0.85, 0.30
ELEC_TH = np.deg2rad([0.0, 120.0, 240.0])

snap = sys.argv[1] if len(sys.argv) > 1 else sorted(
    glob.glob(os.path.join(REPO, "campaigns/s5/base/eaf3d_*.h5")))[-1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    REPO, "docs", "img", "borein_3d.png")

with h5py.File(snap) as f:
    alpha_s = f["fields/alpha_solid"][:]      # (nz, nth, nr)
    T_s = f["fields/T_solid"][:]
    r = f["mesh/r"][:]
    th = f["mesh/theta"][:]
    z = f["mesh/z"][:]
    t_sim = float(f["metadata"].attrs["time"][0])

# corte de cuña hacia la cámara (ilustrativo: muestra el interior del lecho)
WEDGE = (np.deg2rad(275.0), np.deg2rad(335.0))
alpha_s = alpha_s.copy()
alpha_s[:, (th >= WEDGE[0]) & (th <= WEDGE[1]), :] = 0.0

# cierre periódico en theta (para que la superficie no quede abierta)
alpha_p = np.concatenate([alpha_s, alpha_s[:, :1, :]], axis=1)
T_p = np.concatenate([T_s, T_s[:, :1, :]], axis=1)
th_p = np.concatenate([th, [th[0] + 2.0 * np.pi]])

verts, faces, _, _ = marching_cubes(alpha_p, level=0.3)

# índices continuos (iz, ith, ir) -> coordenadas físicas -> cartesianas
zc = np.interp(verts[:, 0], np.arange(len(z)), z)
tc = np.interp(verts[:, 1], np.arange(len(th_p)), th_p)
rc = np.interp(verts[:, 2], np.arange(len(r)), r)
x, y = rc * np.cos(tc), rc * np.sin(tc)
xyz = np.column_stack([x, y, zc])

# temperatura muestreada en el voxel más cercano al centroide de cada cara
idx = np.rint(verts).astype(int)
idx[:, 0] = idx[:, 0].clip(0, T_p.shape[0] - 1)
idx[:, 1] = idx[:, 1].clip(0, T_p.shape[1] - 1)
idx[:, 2] = idx[:, 2].clip(0, T_p.shape[2] - 1)
T_vert = T_p[idx[:, 0], idx[:, 1], idx[:, 2]]
T_face = T_vert[faces].mean(axis=1)

norm = plt.Normalize(300.0, max(1810.0, T_face.max()))
colors = cm.inferno(norm(T_face))

fig = plt.figure(figsize=(7.5, 6.5))
ax = fig.add_subplot(111, projection="3d")
mesh = Poly3DCollection(xyz[faces], facecolors=colors,
                        edgecolor="none", alpha=0.95)
ax.add_collection3d(mesh)

# electrodos (cilindros de grafito) hasta justo encima del lecho
tt = np.linspace(0, 2 * np.pi, 40)
zz = np.linspace(2.3, H_TOTAL, 2)
TT, ZZ = np.meshgrid(tt, zz)
for th_e in ELEC_TH:
    xe = R_PCD * np.cos(th_e) + R_ELEC * np.cos(TT)
    ye = R_PCD * np.sin(th_e) + R_ELEC * np.sin(TT)
    ax.plot_surface(xe, ye, ZZ, color="#7a1f1f", alpha=0.9,
                    linewidth=0, shade=True)

# contorno de la coraza (aros arriba/abajo + generatrices)
for zs in (0.0, H_TOTAL):
    ax.plot(R_SHELL * np.cos(tt), R_SHELL * np.sin(tt), zs,
            color="k", lw=1.0, alpha=0.6)
for th_w in np.linspace(0, 2 * np.pi, 12, endpoint=False):
    ax.plot([R_SHELL * np.cos(th_w)] * 2, [R_SHELL * np.sin(th_w)] * 2,
            [0, H_TOTAL], color="k", lw=0.4, alpha=0.25)

m = cm.ScalarMappable(norm=norm, cmap="inferno")
m.set_array([])
cb = fig.colorbar(m, ax=ax, shrink=0.6, pad=0.08)
cb.set_label(r"$T_{\rm solid}$  [K]")

ax.set_xlim(-R_SHELL, R_SHELL)
ax.set_ylim(-R_SHELL, R_SHELL)
ax.set_zlim(0, H_TOTAL)
ax.set_box_aspect((1, 1, H_TOTAL / (2 * R_SHELL)))
ax.set_xlabel("x [m]")
ax.set_ylabel("y [m]")
ax.set_zlabel("z [m]")
ax.set_title(f"Lecho de chatarra (isosuperficie "
             r"$\alpha_s$=0.3) — bore-in, "
             f"t = {t_sim:.0f} s")
ax.view_init(elev=28, azim=-55)

os.makedirs(os.path.dirname(out), exist_ok=True)
fig.tight_layout()
fig.savefig(out, dpi=150, bbox_inches="tight")
print(f"escrito {out}")
