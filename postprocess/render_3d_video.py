#!/usr/bin/env python3
"""
render_3d_video.py – 3D isosurface animation of the EAF 3D simulator.

Produces:
  plots/3d_temperature_isosurfaces.mp4

Each frame shows:
  • T_solid isosurfaces at 400 K, 700 K, 1000 K, 1300 K
    with increasing opacity (0.15 → 0.35 → 0.55 → 0.75)
  • r-z cross-section at θ=0 (electrode 1 plane) coloured by T_solid
  • Electrode current field lines in the cross-section plane (analytical J×B model)
  • Electrode tube markers (wire-frame cylinders)
  • Title with simulation time

Usage:
    python3 postprocess/render_3d_video.py [output_dir] [plots_dir]
"""
import sys, os, glob, subprocess, tempfile, shutil
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.gridspec import GridSpec
from matplotlib.patches import FancyArrowPatch
from mpl_toolkits.mplot3d import Axes3D
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from skimage.measure import marching_cubes
from scipy.ndimage import gaussian_filter

# ── paths ──────────────────────────────────────────────────────────────────
OUTPUT_DIR = sys.argv[1] if len(sys.argv) > 1 else 'output_prod'
PLOTS_DIR  = sys.argv[2] if len(sys.argv) > 2 else 'plots'
os.makedirs(PLOTS_DIR, exist_ok=True)

files = sorted(glob.glob(os.path.join(OUTPUT_DIR, 'eaf3d_*.h5')))
if not files:
    sys.exit(f'No HDF5 files in {OUTPUT_DIR}')
print(f'{len(files)} snapshots → building video frames ...')

# ── physical constants ──────────────────────────────────────────────────────
N_ELEC  = 3
R_PCD   = 0.85    # m   pitch-circle radius
R_ELEC  = 0.30    # m   electrode radius
SIG_J   = 3.0 * R_ELEC          # Gaussian σ for J_z distribution
I_TOTAL = 55e3                    # A  nominal arc current per electrode
MU0     = 4e-7 * np.pi           # H/m

# ── isosurface levels and visual properties ────────────────────────────────
ISO_LEVELS  = [400.0, 700.0, 1000.0, 1300.0]   # K
ISO_COLORS  = ['#4cc9f0', '#90be6d', '#f9c74f', '#f3722c']
ISO_ALPHAS  = [0.12,      0.25,      0.45,      0.70]

# ── video parameters ───────────────────────────────────────────────────────
VIDEO_DURATION = 7.0    # seconds — FPS is derived from n_frames / duration
AZIM_START     = 30.0   # degrees — initial camera azimuth
AZIM_END       = 65.0   # degrees — final camera azimuth
FFMPEG  = shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'

# ═══════════════════════════════════════════════════════════════════════════
# Load mesh from first file (constant across all snapshots)
# ═══════════════════════════════════════════════════════════════════════════
import h5py
with h5py.File(files[0], 'r') as f:
    r_vec  = f['mesh']['r'][:]
    th_vec = f['mesh']['theta'][:]
    z_vec  = f['mesh']['z'][:]

nr  = len(r_vec)
nth = len(th_vec)
nz  = len(z_vec)
print(f'Mesh: nr={nr}, nth={nth}, nz={nz}')

# Build 3-D Cartesian coordinate arrays for the full cylindrical grid
# (downsampled to keep marching_cubes tractable: skip every 2nd cell)
r_ds  = r_vec[::2];  nr_d  = len(r_ds)
th_ds = th_vec[::2]; nth_d = len(th_ds)
z_ds  = z_vec[::2];  nz_d  = len(z_ds)

# Precompute Cartesian coords for downsampled grid
# Shape of grids below: (nz_d, nth_d, nr_d)
TH3, Z3, R3 = np.meshgrid(th_ds, z_ds, r_ds, indexing='ij')
# transpose so array[iz, ith, ir]
TH3 = TH3.transpose(1, 0, 2)
Z3  = Z3.transpose(1, 0, 2)
R3  = R3.transpose(1, 0, 2)
X3  = R3 * np.cos(TH3)    # (nz_d, nth_d, nr_d)
Y3  = R3 * np.sin(TH3)
# Z3 is already correct

# ── cross-section plane (theta=0, electrode 1) ────────────────────────────
idx_th0 = 0     # theta index for electrode 1 cross-section
R2D, Z2D = np.meshgrid(r_vec, z_vec)   # (nz, nr)

# ── electrode positions (Cartesian) ───────────────────────────────────────
th_elec = [2 * np.pi * e / N_ELEC for e in range(N_ELEC)]
x_elec  = [R_PCD * np.cos(t) for t in th_elec]
y_elec  = [R_PCD * np.sin(t) for t in th_elec]

# ── analytical current field lines ────────────────────────────────────────
# Physics: J_z(ρ) = -I/(2πσ²) · exp(-ρ²/2σ²), σ = SIG_J = 3·R_elec
# Current flows electrode tip → arc plasma → scrap surface (downward).
# Bath return circuit closes between the three electrodes through liquid steel.

def arc_fieldlines_3d(ax3d, xe, ye, z_tip, z_scrap, n_rings=5, n_azimuth=10):
    """
    3-D current field lines for one electrode:
    - n_rings concentric rings of lines, each ring at radius r_ring = ring * SIG_J/n_rings
    - n_azimuth lines per ring, equally spaced in angle
    - Line intensity (alpha, lw) weighted by Gaussian J profile
    - Path: quadratic Bezier from (xe, ye, z_tip) spreading outward to scrap level
    """
    t_param = np.linspace(0, 1, 50)
    # Central core line (bright yellow)
    ax3d.plot([xe, xe], [ye, ye], [z_tip, z_scrap],
              color='#ffee44', alpha=0.95, lw=2.5, zorder=10)
    ax3d.plot([xe], [ye], [z_tip], 'o', color='#fffaaa',
              ms=5, alpha=0.9, zorder=11)

    for ring in range(1, n_rings + 1):
        r_ring = ring * SIG_J / n_rings          # ring radius (0 < r ≤ SIG_J)
        intensity = np.exp(-r_ring**2 / (2 * SIG_J**2))
        if intensity < 0.05:
            continue
        color = plt.cm.plasma(0.25 + 0.65 * intensity)
        al    = float(0.85 * intensity)
        lw    = 2.2 * intensity

        for ai in range(n_azimuth):
            phi    = 2 * np.pi * ai / n_azimuth
            # End point at scrap level: displaced r_ring * 0.6 (field converges)
            dx_end = r_ring * 0.60 * np.cos(phi)
            dy_end = r_ring * 0.60 * np.sin(phi)

            # Skip lines that exit the furnace shell
            x_end = xe + dx_end
            y_end = ye + dy_end
            if np.sqrt(x_end**2 + y_end**2) > R_wall * 0.95:
                continue

            # Bezier control point: spreads out at mid-height
            xc = xe + r_ring * 1.1 * np.cos(phi)
            yc = ye + r_ring * 1.1 * np.sin(phi)
            zc = (z_tip + z_scrap) * 0.5

            # Quadratic Bezier: P(t) = (1-t)²·P0 + 2(1-t)t·Pc + t²·P1
            s  = t_param
            xp = (1 - s)**2 * xe   + 2*(1-s)*s * xc + s**2 * x_end
            yp = (1 - s)**2 * ye   + 2*(1-s)*s * yc + s**2 * y_end
            zp = (1 - s)**2 * z_tip + 2*(1-s)*s * zc + s**2 * z_scrap

            ax3d.plot(xp, yp, zp, color=color, alpha=al, lw=lw, zorder=5)


def bath_return_circuit(ax3d, x_elec, y_elec, z_bath):
    """
    Schematic 3-phase return current in the liquid bath:
    Draw dashed arcs connecting each electrode to the next at z_bath level.
    The path curves slightly inward (toward furnace center) simulating bath flow.
    """
    n  = len(x_elec)
    t  = np.linspace(0, 1, 60)
    for i in range(n):
        j = (i + 1) % n
        # Control point: midpoint pulled 30% toward center
        xc = (x_elec[i] + x_elec[j]) / 2 * 0.70
        yc = (y_elec[i] + y_elec[j]) / 2 * 0.70
        zc = z_bath - 0.12   # slight dip below bath surface

        s  = t
        xp = (1 - s)**2 * x_elec[i] + 2*(1-s)*s * xc + s**2 * x_elec[j]
        yp = (1 - s)**2 * y_elec[i] + 2*(1-s)*s * yc + s**2 * y_elec[j]
        zp = (1 - s)**2 * z_bath    + 2*(1-s)*s * zc + s**2 * z_bath

        ax3d.plot(xp, yp, zp, color='#00e5ff', alpha=0.55, lw=1.6,
                  ls='--', zorder=6)
        # Arrowhead at midpoint
        mid = len(t) // 2
        ax3d.quiver(xp[mid], yp[mid], zp[mid],
                    xp[mid+1]-xp[mid-1], yp[mid+1]-yp[mid-1], zp[mid+1]-zp[mid-1],
                    length=0.12, color='#00e5ff', alpha=0.7, arrow_length_ratio=0.7,
                    normalize=True)


def electrode_current_arrows(ax, z_tip, z_scrap, n_lines=7):
    """
    Draw schematic current field lines for electrode 1 in the r-z plane.
    Lines diverge from electrode tip to scrap surface (Gaussian spread).
    """
    sigmas = np.linspace(0.0, SIG_J * 1.5, n_lines)
    colors = plt.cm.plasma(np.linspace(0.3, 0.9, n_lines))
    # For each sigma offset, draw a line from (R_PCD + σ, z_tip) to scrap level
    for sigma, c in zip(sigmas, colors):
        for sign in ([-1, 1] if sigma > 0 else [0]):
            r_start = R_PCD + sign * sigma
            if r_start < 0 or r_start > r_vec[-1]:
                continue
            # Line slightly curved (quadratic arc)
            z_line = np.linspace(z_tip, z_scrap, 30)
            r_line = np.linspace(r_start, R_PCD + sign * sigma * 0.3, 30)
            alpha  = np.exp(-sigma**2 / (2 * SIG_J**2))
            ax.plot(r_line, z_line, color=c, alpha=float(alpha) * 0.8,
                    lw=1.5 * (1 - sigma / (SIG_J * 2)))
    # Central strong line
    ax.annotate('', xy=(R_PCD, z_scrap), xytext=(R_PCD, z_tip),
                arrowprops=dict(arrowstyle='->', color='yellow', lw=2.5))

# ═══════════════════════════════════════════════════════════════════════════
# Helper: build isosurface mesh in Cartesian from cylindrical volume
# ═══════════════════════════════════════════════════════════════════════════
def build_isosurface(field_cyl, level, spacing=(1, 1, 1)):
    """
    field_cyl: (nz, nth, nr) cylindrical data (downsampled)
    Returns list of Poly3DCollection ready to add to ax3d.
    """
    # Apply light smoothing to reduce marching-cubes noise
    smooth = gaussian_filter(field_cyl, sigma=1.0)
    if smooth.max() <= level:
        return None
    if smooth.min() >= level:
        return None
    verts_idx, faces, _, _ = marching_cubes(smooth, level=level, spacing=spacing)
    # verts_idx is in (iz, ith, ir) index space — convert to real cylindrical
    iz_f  = verts_idx[:, 0].clip(0, nz_d - 1).astype(int)
    ith_f = verts_idx[:, 1].clip(0, nth_d - 1).astype(int)
    ir_f  = verts_idx[:, 2].clip(0, nr_d - 1).astype(int)
    # Interpolate real coords
    z_v  = z_ds [iz_f]
    th_v = th_ds[ith_f]
    r_v  = r_ds [ir_f]
    x_v  = r_v * np.cos(th_v)
    y_v  = r_v * np.sin(th_v)
    verts_cart = np.column_stack([x_v, y_v, z_v])
    # Build face vertex arrays
    mesh_verts = verts_cart[faces]
    return mesh_verts

# ═══════════════════════════════════════════════════════════════════════════
# Electrode tube wireframe helper
# ═══════════════════════════════════════════════════════════════════════════
def draw_electrode_tube(ax3d, x_e, y_e, z_tip, z_top=4.5, n_phi=16):
    phi = np.linspace(0, 2 * np.pi, n_phi)
    for ph1, ph2 in zip(phi[:-1], phi[1:]):
        for z1, z2 in zip([z_tip, z_top * 0.6], [z_top * 0.6, z_top]):
            dx1 = R_ELEC * np.cos(ph1); dy1 = R_ELEC * np.sin(ph1)
            dx2 = R_ELEC * np.cos(ph2); dy2 = R_ELEC * np.sin(ph2)
            xs = [x_e + dx1, x_e + dx2, x_e + dx2, x_e + dx1]
            ys = [y_e + dy1, y_e + dy2, y_e + dy2, y_e + dy1]
            zs = [z1, z1, z2, z2]
            poly = Poly3DCollection([list(zip(xs, ys, zs))],
                                    alpha=0.20, facecolor='silver', edgecolor='gray',
                                    linewidth=0.3)
            ax3d.add_collection3d(poly)

# ═══════════════════════════════════════════════════════════════════════════
# Frame rendering
# ═══════════════════════════════════════════════════════════════════════════
FPS = len(files) / VIDEO_DURATION   # e.g. 37 frames / 10 s = 3.7 fps
AZIM_STEP = (AZIM_END - AZIM_START) / max(len(files) - 1, 1)
print(f'Video: {len(files)} frames  ·  {FPS:.2f} fps  ·  {VIDEO_DURATION:.0f} s  '
      f'·  azim {AZIM_START:.0f}°→{AZIM_END:.0f}°  (step {AZIM_STEP:.2f}°/frame)')

frame_dir = tempfile.mkdtemp(prefix='eaf3d_frames_')
print(f'Rendering frames to {frame_dir} ...')

R_wall = r_vec[-1]
Z_top  = z_vec[-1]

for fi, fp in enumerate(files):
    with h5py.File(fp, 'r') as f:
        t_s    = float(f['metadata'].attrs['time'][0])
        step_n = int(f['metadata'].attrs['step'][0])
        T_cyl  = f['fields']['T_solid'][:]       # (nz, nth, nr)
        als3d  = f['fields']['alpha_solid'][:]
        T_gas3d = f['fields']['T_gas'][:]
        alg3d   = f['fields']['alpha_gas'][:]

    t_min = t_s / 60.0

    # Downsample for marching cubes
    T_ds  = T_cyl[::2, ::2, ::2]     # (nz_d, nth_d, nr_d)
    # Mask: zero out cells with no solid (T_solid is meaningless there)
    alp_ds = als3d[::2, ::2, ::2]
    T_ds   = np.where(alp_ds > 0.02, T_ds, 0.0)

    # Find scrap surface z (highest k with solid present, theta-avg)
    alp_rz = als3d.mean(axis=1)   # (nz, nr)
    has_solid = alp_rz.max(axis=1) > 0.02   # (nz,)
    k_scrap = int(np.where(has_solid)[0].max()) if has_solid.any() else nz // 3
    z_scrap = z_vec[k_scrap]

    # Electrode tip z (80% of furnace height)
    z_tip = Z_top * 0.82

    # ── figure layout: 3D (left) | T_solid (top-right) | T_gas (bot-right) ─
    fig = plt.figure(figsize=(18, 9), facecolor='#0a0a0a')
    gs  = GridSpec(2, 2, figure=fig,
                   width_ratios=[1.15, 0.85], hspace=0.42, wspace=0.30)
    ax3   = fig.add_subplot(gs[:, 0], projection='3d', facecolor='#0d0d1a')
    ax_ts = fig.add_subplot(gs[0, 1], facecolor='#0d0d1a')   # T_solid
    ax_tg = fig.add_subplot(gs[1, 1], facecolor='#0d0d1a')   # T_gas

    # ── 3D isosurfaces ────────────────────────────────────────────────────
    for level, color, alpha in zip(ISO_LEVELS, ISO_COLORS, ISO_ALPHAS):
        mesh_v = build_isosurface(T_ds, level)
        if mesh_v is not None and len(mesh_v) > 0:
            coll = Poly3DCollection(mesh_v, alpha=alpha,
                                    facecolor=color, edgecolor='none')
            ax3.add_collection3d(coll)

    # Electrode tubes
    for xe, ye in zip(x_elec, y_elec):
        draw_electrode_tube(ax3, xe, ye, z_tip, Z_top)

    # ── 3-D arc current field lines ───────────────────────────────────────
    for xe, ye in zip(x_elec, y_elec):
        arc_fieldlines_3d(ax3, xe, ye, z_tip, z_scrap,
                          n_rings=5, n_azimuth=12)

    # ── Bath return circuit (electrode-to-electrode through liquid steel) ─
    bath_return_circuit(ax3, x_elec, y_elec, z_scrap - 0.05)

    # ── Furnace shell — more prominent wireframe ──────────────────────────
    phi_w  = np.linspace(0, 2 * np.pi, 128)
    SHELL_C = '#99aacc'
    # Horizontal rings: stronger at top/bottom rims, subtler in between
    for zfrac, al, lw in [(0.0,  0.60, 2.0),
                           (0.25, 0.28, 1.0),
                           (0.50, 0.35, 1.3),
                           (0.75, 0.28, 1.0),
                           (1.0,  0.60, 2.0)]:
        zl = zfrac * Z_top
        ax3.plot(R_wall * np.cos(phi_w), R_wall * np.sin(phi_w),
                 [zl] * 128, color=SHELL_C, alpha=al, lw=lw)
    # Vertical staves (16 lines, higher alpha)
    for ph in np.linspace(0, 2 * np.pi, 16, endpoint=False):
        ax3.plot([R_wall * np.cos(ph)] * 2, [R_wall * np.sin(ph)] * 2,
                 [0.0, Z_top], color=SHELL_C, alpha=0.28, lw=0.9)
    # Bottom disc (furnace floor)
    r_disc = np.linspace(0, R_wall, 8)
    for phi_d in np.linspace(0, 2 * np.pi, 12, endpoint=False):
        ax3.plot([0, R_wall * np.cos(phi_d)],
                 [0, R_wall * np.sin(phi_d)],
                 [0.0, 0.0], color=SHELL_C, alpha=0.18, lw=0.7)

    ax3.set_xlim(-R_wall, R_wall)
    ax3.set_ylim(-R_wall, R_wall)
    ax3.set_zlim(0, Z_top)
    ax3.set_xlabel('x [m]', color='white', labelpad=6, fontsize=9)
    ax3.set_ylabel('y [m]', color='white', labelpad=6, fontsize=9)
    ax3.set_zlabel('z [m]', color='white', labelpad=6, fontsize=9)
    ax3.tick_params(colors='gray', labelsize=7)
    ax3.xaxis.pane.fill = False; ax3.yaxis.pane.fill = False; ax3.zaxis.pane.fill = False
    ax3.xaxis.pane.set_edgecolor('#222'); ax3.yaxis.pane.set_edgecolor('#222')
    ax3.zaxis.pane.set_edgecolor('#222')
    ax3.view_init(elev=25, azim=AZIM_START + fi * AZIM_STEP)

    # Isosurface + field-line legend
    for level, color, alpha in zip(ISO_LEVELS, ISO_COLORS, ISO_ALPHAS):
        ax3.plot([], [], [], color=color, alpha=alpha,
                 lw=6, label=f'T = {level:.0f} K')
    ax3.plot([], [], [], color='#ffee44', lw=2.0, label='Arc current (J field)')
    ax3.plot([], [], [], color='#00e5ff', lw=1.5, ls='--', label='Bath return circuit')
    ax3.legend(loc='upper left', fontsize=8, framealpha=0.3,
               labelcolor='white', facecolor='black')

    # ── helper: style a dark 2-D axis ──────────────────────────────────────
    def style_ax(ax, xlabel, ylabel, title):
        ax.set_xlabel(xlabel, color='white', fontsize=8)
        ax.set_ylabel(ylabel, color='white', fontsize=8)
        ax.set_title(title, color='white', fontsize=9)
        ax.tick_params(colors='white', labelsize=7)
        for sp in ax.spines.values():
            sp.set_edgecolor('#444')

    def add_cbar(fig, im, ax, label):
        cb = fig.colorbar(im, ax=ax, pad=0.02, fraction=0.046)
        cb.set_label(label, color='white', fontsize=8)
        cb.ax.yaxis.set_tick_params(color='white', labelsize=7)
        plt.setp(cb.ax.yaxis.get_ticklabels(), color='white')

    # ── TOP-RIGHT: T_solid r-z cross-section ──────────────────────────────
    T_rz         = T_cyl[:, idx_th0, :]
    alp_rz_slice = als3d[:, idx_th0, :]

    T_plot      = np.where(alp_rz_slice > 0.02, T_rz, np.nan)
    T_plot_clip = np.clip(T_plot, 300, 1600)
    cmap_ts     = plt.cm.inferno.copy()
    cmap_ts.set_bad(color='#0d0d1a')

    im_ts = ax_ts.pcolormesh(R2D, Z2D, T_plot_clip, cmap=cmap_ts,
                              vmin=300, vmax=1600, shading='auto')
    try:
        ax_ts.contour(R2D, Z2D, alp_rz_slice,
                      levels=[0.05, 0.30], colors=['#00d4ff', '#7fff00'],
                      linewidths=[0.7, 1.0], alpha=0.85)
    except Exception:
        pass
    electrode_current_arrows(ax_ts, z_tip, z_scrap, n_lines=6)
    ax_ts.axvline(R_PCD, ls='--', color='silver', lw=1.0, alpha=0.5)
    ax_ts.annotate('E1', (R_PCD * 1.03, z_tip), color='silver', fontsize=7, va='center')
    add_cbar(fig, im_ts, ax_ts, 'T_solid [K]')
    style_ax(ax_ts, 'r [m]', 'z [m]', 'Scrap temperature  (θ = 0)')

    # ── BOTTOM-RIGHT: T_gas r-z cross-section ─────────────────────────────
    # Physical gas T: clip to [300, 5000] K; cells with no gas → NaN (dark bg)
    # Arc plasma column typically reaches 3 000–10 000 K — the 5 000 K cap
    # lets the colour scale show both the cold bulk gas and the hot plasma.
    Tg_rz       = T_gas3d[:, idx_th0, :]
    alg_rz      = alg3d[:, idx_th0, :]
    Tg_plot     = np.where(alg_rz > 0.05, Tg_rz, np.nan)
    Tg_plot     = np.clip(Tg_plot, 300, 5000)
    cmap_tg     = plt.cm.plasma.copy()
    cmap_tg.set_bad(color='#0d0d1a')

    im_tg = ax_tg.pcolormesh(R2D, Z2D, Tg_plot, cmap=cmap_tg,
                              vmin=300, vmax=5000, shading='auto')
    # Overlay scrap boundary so the observer can relate gas T to scrap position
    try:
        ax_tg.contour(R2D, Z2D, alp_rz_slice,
                      levels=[0.05], colors=['#00ff88'],
                      linewidths=[0.9], alpha=0.75)
    except Exception:
        pass
    ax_tg.axvline(R_PCD, ls='--', color='silver', lw=1.0, alpha=0.5)
    ax_tg.annotate('E1', (R_PCD * 1.03, Z_top * 0.82), color='silver',
                   fontsize=7, va='center')
    add_cbar(fig, im_tg, ax_tg, 'T_gas [K]')
    style_ax(ax_tg, 'r [m]', 'z [m]', 'Gas temperature  (θ = 0)')

    # Overall title
    fig.suptitle(
        f'EAF 3D Simulator  ·  t = {t_min:.1f} min  (step {step_n})',
        color='white', fontsize=13, y=1.00
    )

    frame_path = os.path.join(frame_dir, f'frame_{fi:04d}.png')
    fig.savefig(frame_path, dpi=110, bbox_inches='tight',
                facecolor=fig.get_facecolor())
    plt.close(fig)

    if fi % 5 == 0 or fi == len(files) - 1:
        print(f'  Frame {fi+1}/{len(files)}  t={t_min:.1f} min')

# ═══════════════════════════════════════════════════════════════════════════
# Encode video with ffmpeg
# ═══════════════════════════════════════════════════════════════════════════
out_mp4 = os.path.join(PLOTS_DIR, '3d_temperature_isosurfaces.mp4')
cmd = [
    FFMPEG, '-y',
    '-framerate', f'{len(files) * 10}/{int(VIDEO_DURATION * 10)}',
    '-i', os.path.join(frame_dir, 'frame_%04d.png'),
    '-c:v', 'libx264',
    '-preset', 'slow',
    '-crf', '18',
    '-pix_fmt', 'yuv420p',
    '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',  # ensure even dimensions
    out_mp4
]
print(f'\nEncoding video → {out_mp4}')
ret = subprocess.run(cmd, capture_output=True, text=True)
if ret.returncode != 0:
    print('ffmpeg error:\n', ret.stderr[-2000:])
else:
    size_mb = os.path.getsize(out_mp4) / 1e6
    print(f'  Video saved: {out_mp4}  ({size_mb:.1f} MB)')

shutil.rmtree(frame_dir, ignore_errors=True)
print('Done.')
