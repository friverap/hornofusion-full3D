#!/usr/bin/env python3
"""
plot_insights.py – EAF 3D Simulator: insight plots from production run.

Usage:
    python3 postprocess/plot_insights.py [output_dir] [plots_dir]
Defaults:
    output_dir = output_prod/
    plots_dir  = plots/

Produces (all saved as PNG):
  01_scrap_evolution.png     – alpha_solid + T_solid vs time
  02_arc_power.png           – S_arc spatial mean vs time
  03_co_chemistry.png        – Y_CO / Y_CO2 max vs time + chemistry heat
  04_spatial_Tsolid.png      – T_solid r-z cross-section (last snapshot)
  05_spatial_YCO.png         – Y_CO + Y_CO2 r-z cross-section (last snapshot)
  06_spatial_Sarc.png        – S_arc + S_chem r-z cross-section (last snapshot)
  07_rtheta_Tsolid.png       – T_solid r-theta view (last snapshot, mid-z)
  08_electrode_heatmap.png   – S_arc at electrode level (r-theta, last snapshot)
"""
import sys, os, glob
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import h5py

# ── paths ──────────────────────────────────────────────────────────────────
OUTPUT_DIR = sys.argv[1] if len(sys.argv) > 1 else 'output_prod'
PLOTS_DIR  = sys.argv[2] if len(sys.argv) > 2 else 'plots'
os.makedirs(PLOTS_DIR, exist_ok=True)

files = sorted(glob.glob(os.path.join(OUTPUT_DIR, 'eaf3d_*.h5')))
if not files:
    sys.exit(f'No HDF5 files in {OUTPUT_DIR}')
print(f'Found {len(files)} snapshots in {OUTPUT_DIR}')

# ── style ──────────────────────────────────────────────────────────────────
plt.rcParams.update({
    'font.size': 11, 'axes.titlesize': 13, 'axes.labelsize': 12,
    'figure.dpi': 150, 'savefig.dpi': 150,
    'lines.linewidth': 2.0, 'axes.grid': True, 'grid.alpha': 0.3,
})

# ── constants ──────────────────────────────────────────────────────────────
N_ELEC  = 3
R_PCD   = 0.85      # m  (pitch-circle radius)
R_ELEC  = 0.30      # m  (electrode radius)
T_MELT  = 1811.0    # K  (iron melting point)
T_CHEM  = 800.0     # K  (Maahs onset temperature)

# ═══════════════════════════════════════════════════════════════════════════
# 1. Gather time-series
# ═══════════════════════════════════════════════════════════════════════════
print('Collecting time-series ...')
ts, T_s_max, T_s_mean, T_g_mean_clamped = [], [], [], []
alpha_s_mean, Y_CO_max, Y_CO_mean = [], [], []
Y_CO2_max, Y_CO2_mean_gas = [], []
S_arc_mean, S_arc_max = [], []
S_chem_mean = []

for fp in files:
    with h5py.File(fp, 'r') as f:
        t  = float(f['metadata'].attrs['time'][0])
        Ts = f['fields']['T_solid'][:]
        Tg = f['fields']['T_gas'][:]
        ag = f['fields']['alpha_gas'][:]
        als= f['fields']['alpha_solid'][:]
        Yc = f['fields']['Y_CO'][:]
        Y2 = f['fields']['Y_CO2'][:]
        Sa = f['fields']['S_arc'][:]
        Sc = f['fields']['S_chem'][:]

    mask_g = ag > 0.1
    mask_s = als > 0.01    # only real scrap cells (alpha_s > 1%)
    ts.append(t)
    # Mask AND clip: T_solid in cells that experienced thermal runaway can be
    # unphysically large (>1e6 K) or negative (E_s drained below 0 by interphase HT
    # on nearly-empty cells). Physical range is 200 – T_liquidus (1809 K).
    if mask_s.any():
        Ts_phys = Ts[mask_s]
        Ts_phys = Ts_phys[(Ts_phys > 200.0) & (Ts_phys < 1850.0)]
        T_s_max.append(Ts_phys.max() if len(Ts_phys) > 0 else 300.0)
        T_s_mean.append(Ts_phys.mean() if len(Ts_phys) > 0 else 300.0)
    else:
        T_s_max.append(300.0)
        T_s_mean.append(300.0)
    # clamp unrealistic gas T to 1e5 K for mean
    Tg_c = np.clip(Tg, 0, 1e5)
    T_g_mean_clamped.append(Tg_c[mask_g].mean() if mask_g.any() else 0.0)
    alpha_s_mean.append(als.mean())
    Y_CO_max.append(Yc.max())
    Y_CO_mean.append(Yc[mask_g].mean() if mask_g.any() else 0.0)
    Y_CO2_max.append(Y2.max())
    Y_CO2_mean_gas.append(Y2[mask_g].mean() if mask_g.any() else 0.0)
    S_arc_mean.append(Sa.mean())
    S_arc_max.append(Sa.max())
    S_chem_mean.append(Sc.mean())

ts = np.array(ts) / 60.0   # convert to minutes
ts_lbl = 'Time [min]'

# ═══════════════════════════════════════════════════════════════════════════
# Plot 1 – Scrap evolution
# ═══════════════════════════════════════════════════════════════════════════
fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
ax1, ax2 = axes

ax1.plot(ts, T_s_max, color='#e63946', label='T_solid max')
ax1.plot(ts, T_s_mean, color='#f4a261', label='T_solid mean (scrap cells)')
ax1.axhline(T_MELT, ls='--', color='gray', lw=1.2, label=f'T_melt = {T_MELT:.0f} K')
ax1.axhline(T_CHEM, ls=':', color='steelblue', lw=1.2, label=f'T_chem = {T_CHEM:.0f} K')
ax1.set_ylabel('Temperature [K]')
ax1.set_title('Scrap Heating Progress')
ax1.legend(fontsize=9)

ax2.plot(ts, np.array(alpha_s_mean) * 100.0, color='#2a9d8f', label='alpha_solid (domain avg)')
ax2.set_ylabel('Volume fraction [%]')
ax2.set_xlabel(ts_lbl)
ax2.set_title('Solid (scrap) volume fraction evolution')
ax2.legend(fontsize=9)

fig.tight_layout()
out = os.path.join(PLOTS_DIR, '01_scrap_evolution.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ═══════════════════════════════════════════════════════════════════════════
# Plot 2 – Arc power
# ═══════════════════════════════════════════════════════════════════════════
S_arc_mean_MW = np.array(S_arc_mean) * 1e-6    # W/m³ domain avg × volume ≈ relative
S_arc_max_GW  = np.array(S_arc_max)  * 1e-9

fig, ax = plt.subplots(figsize=(10, 4))
ax.semilogy(ts, S_arc_mean_MW, color='#e76f51', label='S_arc domain mean [MW/m³]')
ax2b = ax.twinx()
ax2b.semilogy(ts, S_arc_max_GW, color='#264653', ls='--', label='S_arc max [GW/m³]', alpha=0.7)
ax.set_xlabel(ts_lbl)
ax.set_ylabel('Mean arc heat source [MW/m³]', color='#e76f51')
ax2b.set_ylabel('Max arc heat source [GW/m³]', color='#264653')
ax.set_title('Arc Heat Source (S_arc) – Cassie-Mayr + MC radiation')
lines1, labels1 = ax.get_legend_handles_labels()
lines2, labels2 = ax2b.get_legend_handles_labels()
ax.legend(lines1 + lines2, labels1 + labels2, fontsize=9, loc='upper left')
fig.tight_layout()
out = os.path.join(PLOTS_DIR, '02_arc_power.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ═══════════════════════════════════════════════════════════════════════════
# Plot 3 – CO/CO2 chemistry
# ═══════════════════════════════════════════════════════════════════════════
fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
ax1, ax2 = axes

ax1.plot(ts, Y_CO_max,      color='#e63946',  label='Y_CO max')
ax1.plot(ts, Y_CO_mean,     color='#e63946', ls='--', alpha=0.6, label='Y_CO mean (gas region)')
ax1.plot(ts, Y_CO2_max,     color='#457b9d',  label='Y_CO₂ max')
ax1.plot(ts, Y_CO2_mean_gas,color='#457b9d', ls='--', alpha=0.6, label='Y_CO₂ mean (gas region)')
ax1.set_ylabel('Mass fraction [-]')
ax1.set_title('Gas Species: CO and CO₂ Mass Fractions')
ax1.legend(fontsize=9)

Sc_MW = np.array(S_chem_mean) * 1e-6
ax2.semilogy(ts, np.clip(Sc_MW, 1e-3, None), color='#2a9d8f', label='S_chem domain mean [MW/m³]')
ax2.set_ylabel('Chemistry heat [MW/m³]')
ax2.set_xlabel(ts_lbl)
ax2.set_title('Chemical Heat Release (C→CO→CO₂)')
ax2.legend(fontsize=9)

fig.tight_layout()
out = os.path.join(PLOTS_DIR, '03_co_chemistry.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ═══════════════════════════════════════════════════════════════════════════
# 2. Spatial plots – last snapshot
# ═══════════════════════════════════════════════════════════════════════════
print('Loading last snapshot for spatial plots ...')
with h5py.File(files[-1], 'r') as f:
    t_last = float(f['metadata'].attrs['time'][0])
    r_vec  = f['mesh']['r'][:]
    th_vec = f['mesh']['theta'][:]
    z_vec  = f['mesh']['z'][:]
    T_solid_3d = f['fields']['T_solid'][:]        # (nz, nth, nr)
    alpha_s_3d = f['fields']['alpha_solid'][:]
    alpha_g_3d = f['fields']['alpha_gas'][:]
    Y_CO_3d    = f['fields']['Y_CO'][:]
    Y_CO2_3d   = f['fields']['Y_CO2'][:]
    S_arc_3d   = f['fields']['S_arc'][:]
    S_chem_3d  = f['fields']['S_chem'][:]
    F_lor_r_3d = f['fields']['F_lorentz_r'][:]
    F_lor_t_3d = f['fields']['F_lorentz_th'][:]

nr, nz, nth = len(r_vec), len(z_vec), len(th_vec)
t_last_min = t_last / 60.0
print(f'  t = {t_last:.1f} s ({t_last_min:.1f} min), mesh = {nr}×{nth}×{nz}')

# ── r-z cross-section: average over theta ──
def rz_avg(field3d):
    """Average over theta dim (axis=1).  field3d shape = (nz, nth, nr)."""
    return field3d.mean(axis=1)   # -> (nz, nr)

def rz_theta0(field3d):
    """Slice at theta index 0."""
    return field3d[:, 0, :]  # -> (nz, nr)

def rz_theta_elec(field3d, elec_idx=0):
    """Closest theta index to electrode elec_idx."""
    theta_e = 2 * np.pi * elec_idx / N_ELEC
    idx = np.argmin(np.abs(th_vec - theta_e))
    return field3d[:, idx, :]

# Use theta-averaged for cleaner pictures
T_s_rz   = rz_avg(T_solid_3d)
alp_s_rz = rz_avg(alpha_s_3d)
Y_CO_rz  = rz_avg(Y_CO_3d)
Y_CO2_rz = rz_avg(Y_CO2_3d)
S_arc_rz = rz_avg(S_arc_3d)
S_chem_rz= rz_avg(S_chem_3d)

R2D, Z2D = np.meshgrid(r_vec, z_vec)   # (nz, nr)

# ─── helper for r-z panel ──────────────────────────────────────────────────
def rz_panel(ax, data, label, cmap='viridis', logscale=False, vmin=None, vmax=None):
    plot_data = np.log10(np.clip(data, 1e-20, None)) if logscale else data
    im = ax.pcolormesh(R2D, Z2D, plot_data, cmap=cmap, vmin=vmin, vmax=vmax,
                       shading='auto')
    ax.set_xlabel('r [m]')
    ax.set_ylabel('z [m]')
    cbar = plt.colorbar(im, ax=ax, pad=0.02)
    cbar.set_label(label)
    return im

# ─── Plot 4: T_solid + alpha_solid ─────────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 6))
ax1, ax2 = axes

rz_panel(ax1, T_s_rz, 'T_solid [K]', cmap='inferno',
         vmin=T_s_rz[alp_s_rz > 0.01].min() if (alp_s_rz > 0.01).any() else 300,
         vmax=min(T_s_rz.max(), 1600))
ax1.set_title('Scrap Temperature (θ-avg)')
# Contour at melting point
cs = ax1.contour(R2D, Z2D, T_s_rz, levels=[T_MELT], colors='cyan', linewidths=1.5)
ax1.clabel(cs, fmt='T_melt', fontsize=8)

rz_panel(ax2, alp_s_rz * 100, 'α_solid [%]', cmap='Oranges', vmin=0, vmax=65)
ax2.set_title('Solid Volume Fraction (θ-avg)')

for ax in axes:
    ax.set_aspect('auto')

fig.suptitle(f't = {t_last_min:.1f} min', fontsize=13)
fig.tight_layout()
out = os.path.join(PLOTS_DIR, '04_spatial_Tsolid.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ─── Plot 5: Y_CO + Y_CO2 ──────────────────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 6))

rz_panel(axes[0], Y_CO_rz, 'Y_CO [-]', cmap='YlOrRd', vmin=0, vmax=1)
axes[0].set_title('CO mass fraction (θ-avg)')

# Overlay alpha_solid contour
axes[0].contour(R2D, Z2D, alp_s_rz, levels=[0.05], colors='blue',
                linewidths=1.0, linestyles='--')

rz_panel(axes[1], Y_CO2_rz, 'Y_CO₂ [-]', cmap='Blues', vmin=0)
axes[1].set_title('CO₂ mass fraction (θ-avg)')

fig.suptitle(f'Gas Species  t = {t_last_min:.1f} min', fontsize=13)
fig.tight_layout()
out = os.path.join(PLOTS_DIR, '05_spatial_YCO.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ─── Plot 6: S_arc + S_chem ────────────────────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(14, 6))

Sa_safe = np.clip(S_arc_rz, 1e4, None)
rz_panel(axes[0], Sa_safe, 'log₁₀(S_arc) [W/m³]', cmap='hot', logscale=True)
axes[0].set_title('Arc Heat Source (θ-avg, log scale)')

Sc_safe = np.clip(S_chem_rz, 1e4, None)
rz_panel(axes[1], Sc_safe, 'log₁₀(S_chem) [W/m³]', cmap='plasma', logscale=True)
axes[1].set_title('Chemistry Heat Release (θ-avg, log scale)')

fig.suptitle(f'Heat Sources  t = {t_last_min:.1f} min', fontsize=13)
fig.tight_layout()
out = os.path.join(PLOTS_DIR, '06_spatial_Sarc.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ═══════════════════════════════════════════════════════════════════════════
# Plot 7 – r-theta view (polar), T_solid at mid-z
# ═══════════════════════════════════════════════════════════════════════════
k_mid = nz // 2
T_s_polar  = T_solid_3d[k_mid, :, :]   # (nth, nr)
alp_s_polar= alpha_s_3d[k_mid, :, :]

TH2D, R_pol = np.meshgrid(th_vec, r_vec, indexing='ij')  # (nth, nr)
X_pol = R_pol * np.cos(TH2D)
Y_pol = R_pol * np.sin(TH2D)

fig, ax = plt.subplots(figsize=(9, 8))
im = ax.pcolormesh(X_pol, Y_pol, T_s_polar, cmap='inferno',
                   vmin=300, vmax=min(T_s_polar.max(), 1600), shading='auto')
plt.colorbar(im, ax=ax, label='T_solid [K]')

# Alpha-solid contour
ax.contour(X_pol, Y_pol, alp_s_polar, levels=[0.05, 0.3], colors=['cyan', 'lime'],
           linewidths=1.2)

# Electrode circles
theta_e = [2 * np.pi * e / N_ELEC for e in range(N_ELEC)]
for te in theta_e:
    xe, ye = R_PCD * np.cos(te), R_PCD * np.sin(te)
    circ = plt.Circle((xe, ye), R_ELEC, color='white', fill=False, lw=2, ls='--')
    ax.add_patch(circ)
    ax.plot(xe, ye, 'w+', ms=10, mew=2)
    ax.annotate(f'E{theta_e.index(te)+1}', (xe, ye), color='white', fontsize=9,
                ha='center', va='bottom')

# Furnace wall
wall_th = np.linspace(0, 2 * np.pi, 300)
R_shell = r_vec[-1]
ax.plot(R_shell * np.cos(wall_th), R_shell * np.sin(wall_th), 'k-', lw=2)

ax.set_xlim(-R_shell * 1.05, R_shell * 1.05)
ax.set_ylim(-R_shell * 1.05, R_shell * 1.05)
ax.set_aspect('equal')
ax.set_xlabel('x [m]')
ax.set_ylabel('y [m]')
ax.set_title(f'T_solid – top view (z ≈ {z_vec[k_mid]:.2f} m, t = {t_last_min:.1f} min)')
fig.tight_layout()
out = os.path.join(PLOTS_DIR, '07_rtheta_Tsolid.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ═══════════════════════════════════════════════════════════════════════════
# Plot 8 – S_arc at electrode-tip level (r-theta, log scale)
# ═══════════════════════════════════════════════════════════════════════════
# Find z-index where S_arc is largest (electrode tips)
k_arc = int(S_arc_3d.mean(axis=(1, 2)).argmax())
S_arc_polar = S_arc_3d[k_arc, :, :]

fig, ax = plt.subplots(figsize=(9, 8))
Sa_plot = np.log10(np.clip(S_arc_polar, 1e5, None))
im = ax.pcolormesh(X_pol, Y_pol, Sa_plot, cmap='hot', shading='auto')
plt.colorbar(im, ax=ax, label='log₁₀(S_arc) [W/m³]')

for te in theta_e:
    xe, ye = R_PCD * np.cos(te), R_PCD * np.sin(te)
    circ = plt.Circle((xe, ye), R_ELEC, color='cyan', fill=False, lw=2)
    ax.add_patch(circ)
    ax.plot(xe, ye, 'c+', ms=10, mew=2)

ax.plot(R_shell * np.cos(wall_th), R_shell * np.sin(wall_th), 'w-', lw=2)
ax.set_xlim(-R_shell * 1.05, R_shell * 1.05)
ax.set_ylim(-R_shell * 1.05, R_shell * 1.05)
ax.set_aspect('equal')
ax.set_xlabel('x [m]')
ax.set_ylabel('y [m]')
ax.set_title(f'S_arc – electrode level (z ≈ {z_vec[k_arc]:.2f} m, t = {t_last_min:.1f} min)')
fig.tight_layout()
out = os.path.join(PLOTS_DIR, '08_electrode_heatmap.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

# ═══════════════════════════════════════════════════════════════════════════
# Plot 9 – Lorentz force r-z (theta-averaged magnitude)
# ═══════════════════════════════════════════════════════════════════════════
F_mag_rz = np.sqrt(rz_avg(F_lor_r_3d)**2 + rz_avg(F_lor_t_3d)**2)
fig, ax = plt.subplots(figsize=(8, 6))
F_safe = np.log10(np.clip(F_mag_rz, 1e-3, None))
im = ax.pcolormesh(R2D, Z2D, F_safe, cmap='magma', shading='auto')
plt.colorbar(im, ax=ax, label='log₁₀|F_Lorentz| [N/m³]')
ax.contour(R2D, Z2D, alp_s_rz, levels=[0.05], colors='cyan', linewidths=1, linestyles='--')
ax.set_xlabel('r [m]')
ax.set_ylabel('z [m]')
ax.set_title(f'Lorentz Force Magnitude (θ-avg, t = {t_last_min:.1f} min)')
fig.tight_layout()
out = os.path.join(PLOTS_DIR, '09_lorentz_force.png')
fig.savefig(out, bbox_inches='tight')
plt.close(fig)
print(f'  Saved {out}')

print(f'\nAll plots saved to {PLOTS_DIR}/')
