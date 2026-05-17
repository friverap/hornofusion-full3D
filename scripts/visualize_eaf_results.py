#!/usr/bin/env python3
"""
visualize_eaf_results.py - EAF simulation results visualization

Reads HDF5 snapshots written by mod_output_hdf5.f90 and generates:
  eaf_fields_step01.png  — 2×3 r-z field panels at t_initial
  eaf_fields_step10.png  — 2×3 r-z field panels at t_final
  eaf_comparison.png     — 2×2 side-by-side comparison (α_s, T_gas)
  eaf_3d_alpha.png       — PyVista 3D solid-fraction iso-surface (if available)

Usage:
  python visualize_eaf_results.py [--h5-dir output] [--step-init 1] [--step-final 10]

HDF5 layout written by mod_output_hdf5.f90:
  /mesh/r      (nr,)    — radial cell centers
  /mesh/theta  (nth,)   — azimuthal cell centers [rad]
  /mesh/z      (nz,)    — axial cell centers
  /fields/T_solid       — (nz, nth, nr) in file  [Fortran→C order flip by HDF5]
  /fields/alpha_solid   — likewise for all fields
  /fields/T_liquid, alpha_liquid, T_gas, alpha_gas
  /fields/pressure, tke, epsilon
  /fields/velocity_{r,th,z}_{liquid,gas}
  /metadata attrs: time [s], step [int], nprocs
"""

import argparse
import sys
from pathlib import Path

import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')          # headless rendering
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

# ── EAF geometry (must match input config) ───────────────────────────────────
R_SHELL = 3.80
H_TOTAL = 4.50
H_BOWL  = 0.60
R_BOWL  = 2.50
R_PCD   = 0.85   # electrode pitch circle RADIUS [m]
R_ELEC  = 0.30   # electrode radius [m]

# Electrode azimuthal angles (0°, 120°, 240°)
ELEC_ANGLES = [0.0, 2 * np.pi / 3, 4 * np.pi / 3]


# ── Geometry helpers ─────────────────────────────────────────────────────────

def bowl_z(r):
    """Bowl floor z-coordinate (parabolic profile)."""
    return np.where(r <= R_BOWL, H_BOWL * (r / R_BOWL) ** 2, H_BOWL)


def active_mask(r, z):
    """
    Boolean mask (nr, nz): True where cell is above the bowl floor
    (same logic as mark_cell_types in mod_mesh_3d.f90).
    """
    R2d, Z2d = np.meshgrid(r, z, indexing='ij')
    return Z2d >= bowl_z(R2d)


# ── HDF5 I/O ─────────────────────────────────────────────────────────────────

def load_h5(filepath):
    """
    Load one HDF5 snapshot.

    Returns dict with:
      r, theta, z  — 1-D coordinate arrays
      time, step   — scalar metadata
      All field datasets transposed to shape (nr, nth, nz).

    Fortran HDF5 writes dims as (nr, nth, nz) in Fortran order,
    which h5py reads as (nz, nth, nr) in C order.  We transpose
    back with .T so all arrays are consistently (nr, nth, nz).
    """
    data = {}
    filepath = Path(filepath)
    if not filepath.exists():
        raise FileNotFoundError(filepath)

    with h5py.File(filepath, 'r') as f:
        # Mesh coordinates (already 1-D, no transpose needed)
        data['r']     = f['mesh/r'][:]
        data['theta'] = f['mesh/theta'][:]
        data['z']     = f['mesh/z'][:]

        # Fields: stored as (nz, nth, nr) → transpose to (nr, nth, nz)
        for name in f['fields']:
            data[name] = f['fields'][name][:].T   # (nz,nth,nr) → (nr,nth,nz)

        # Metadata (Fortran HDF5 writes attrs as 1-element arrays)
        data['time'] = float(np.asarray(f['metadata'].attrs['time']).flat[0])
        data['step'] = int(np.asarray(f['metadata'].attrs['step']).flat[0])

    return data


# ── Averaging helpers ─────────────────────────────────────────────────────────

def theta_avg(arr3d):
    """Average over the θ axis (axis=1) → (nr, nz)."""
    return arr3d.mean(axis=1)


def theta_slice(arr3d, j=0):
    """Extract slice at azimuthal index j → (nr, nz)."""
    return arr3d[:, j, :]


# ── Geometry overlay for r-z plots ───────────────────────────────────────────

def add_geometry_overlay(ax, r, z):
    """Add bowl floor, vessel walls, and electrode markers to an r-z axes."""
    r_line = np.linspace(0, R_SHELL, 300)
    # Bowl floor
    ax.plot(r_line, bowl_z(r_line), 'k-', lw=1.6, zorder=10)
    # Shell wall and roof
    ax.plot([R_SHELL, R_SHELL], [0, H_TOTAL], 'k-', lw=2.0, zorder=10)
    ax.plot([0, R_SHELL], [H_TOTAL, H_TOTAL], 'k-', lw=1.6, zorder=10)

    # Electrode footprints in r-z plane
    # Show as vertical shaded bands where r ≈ R_PCD ± R_ELEC
    for angle in ELEC_ANGLES:
        er = R_PCD * np.cos(angle)
        if er > R_ELEC:           # only electrodes with positive r projection
            ax.axvspan(er - R_ELEC, er + R_ELEC,
                       ymin=(H_TOTAL * 0.30) / (ax.get_ylim()[1] or H_TOTAL),
                       ymax=0.98,
                       color='#8B0000', alpha=0.18, zorder=9,
                       label='_nolegend_')

    ax.set_xlim(0, R_SHELL + 0.05)
    ax.set_ylim(0, H_TOTAL + 0.05)
    ax.set_xlabel('r  [m]', fontsize=9)
    ax.set_ylabel('z  [m]', fontsize=9)


# ── Single-step field plot ────────────────────────────────────────────────────

# Fields to display and their visualization properties
FIELD_SPECS = [
    # (h5_key,           display_title,                  cmap,        unit)
    ('alpha_solid',  r'Solid fraction  $\alpha_s$',   'plasma_r',  ''),
    ('T_solid',      r'Solid temperature  $T_s$',      'hot',       'K'),
    ('T_gas',        r'Gas temperature  $T_g$',        'coolwarm',  'K'),
    ('alpha_gas',    r'Gas fraction  $\alpha_g$',      'Blues',     ''),
    ('tke',          r'Turbulent kinetic energy',       'inferno',   r'm² s⁻²'),
    ('pressure',     r'Pressure  $p$',                  'viridis',   'Pa'),
]


def plot_rz_fields(data, title_prefix, output_path):
    """
    2 × 3 grid of r-z cross-section (θ-averaged) field maps.
    """
    r = data['r']
    z = data['z']
    mask = active_mask(r, z)    # (nr, nz) True = inside domain

    R2d, Z2d = np.meshgrid(r, z, indexing='ij')

    fig, axes = plt.subplots(2, 3, figsize=(15, 9))
    fig.suptitle(f"{title_prefix}   —   step {data['step']},   t = {data['time']:.2f} s",
                 fontsize=14, fontweight='bold')

    for ax, (key, title, cmap, unit) in zip(axes.flat, FIELD_SPECS):
        if key not in data:
            ax.set_visible(False)
            continue

        field_rz = theta_avg(data[key])          # (nr, nz)
        field_rz = np.where(mask, field_rz, np.nan)

        vmin = np.nanmin(field_rz)
        vmax = np.nanmax(field_rz)
        if not np.isfinite(vmin) or vmax == vmin:
            vmin = 0.0; vmax = 1.0

        im = ax.pcolormesh(R2d, Z2d, field_rz,
                           cmap=cmap, vmin=vmin, vmax=vmax, shading='nearest')

        add_geometry_overlay(ax, r, z)

        cb = plt.colorbar(im, ax=ax, shrink=0.88, pad=0.02)
        cb.set_label(unit, fontsize=8)
        cb.ax.tick_params(labelsize=7)

        ax.set_title(title, fontsize=10)
        ax.tick_params(labelsize=8)

        # Value range annotation
        ax.text(0.98, 0.02, f'[{vmin:.3g}, {vmax:.3g}]',
                transform=ax.transAxes, ha='right', va='bottom',
                fontsize=7, color='white',
                bbox=dict(boxstyle='round,pad=0.2', fc='black', alpha=0.45))

    plt.tight_layout(rect=[0, 0, 1, 0.96])
    output_path = Path(output_path)
    plt.savefig(str(output_path), dpi=150, bbox_inches='tight')
    plt.close()
    print(f'  Saved: {output_path}')


# ── Two-step comparison plot ──────────────────────────────────────────────────

COMPARE_SPECS = [
    ('alpha_solid',  r'Solid fraction  $\alpha_s$',    'plasma_r', ''),
    ('T_gas',        r'Gas temperature  $T_g$  [K]',   'coolwarm', 'K'),
]


def plot_comparison(d0, d1, output_path):
    """
    2 × 2 figure: rows = fields, columns = initial / final.
    Shared color scale per row.
    """
    fig, axes = plt.subplots(2, 2, figsize=(13, 9))
    fig.suptitle(
        f"EAF Simulation — "
        f"t = {d0['time']:.2f} s  vs  t = {d1['time']:.2f} s",
        fontsize=14, fontweight='bold')

    col_labels = [
        f"Initial  (step {d0['step']},  t = {d0['time']:.2f} s)",
        f"Final   (step {d1['step']},  t = {d1['time']:.2f} s)",
    ]

    for row, (key, title, cmap, unit) in enumerate(COMPARE_SPECS):
        datasets = [d0, d1]

        # Compute shared color limits across both time steps
        rz_fields = []
        for data in datasets:
            r, z = data['r'], data['z']
            mask = active_mask(r, z)
            field = theta_avg(data[key]) if key in data else None
            rz_fields.append(np.where(mask, field, np.nan) if field is not None else None)

        vmin = min(np.nanmin(f) for f in rz_fields if f is not None)
        vmax = max(np.nanmax(f) for f in rz_fields if f is not None)
        if not np.isfinite(vmin) or vmax == vmin:
            vmin = 0.0; vmax = 1.0

        for col, (data, field_rz) in enumerate(zip(datasets, rz_fields)):
            ax = axes[row, col]
            r, z = data['r'], data['z']
            R2d, Z2d = np.meshgrid(r, z, indexing='ij')

            if field_rz is not None:
                im = ax.pcolormesh(R2d, Z2d, field_rz,
                                   cmap=cmap, vmin=vmin, vmax=vmax,
                                   shading='nearest')
                cb = plt.colorbar(im, ax=ax, shrink=0.90, pad=0.02)
                cb.set_label(unit, fontsize=8)
                cb.ax.tick_params(labelsize=7)

            add_geometry_overlay(ax, r, z)

            if row == 0:
                ax.set_title(col_labels[col], fontsize=10)
            ax.set_ylabel(title if col == 0 else '', fontsize=9)
            ax.tick_params(labelsize=8)

            if field_rz is not None:
                ax.text(0.98, 0.02, f'[{vmin:.3g}, {vmax:.3g}]',
                        transform=ax.transAxes, ha='right', va='bottom',
                        fontsize=7, color='white',
                        bbox=dict(boxstyle='round,pad=0.2', fc='black', alpha=0.45))

    plt.tight_layout(rect=[0, 0, 1, 0.96])
    output_path = Path(output_path)
    plt.savefig(str(output_path), dpi=150, bbox_inches='tight')
    plt.close()
    print(f'  Saved: {output_path}')


# ── PyVista 3-D solid-fraction view ──────────────────────────────────────────

def plot_3d_pyvista(data, output_path, title=''):
    """
    3-D structured-grid visualisation of solid fraction with PyVista.
    Renders an iso-surface at alpha_s = 0.3 coloured by T_solid.
    Falls back silently if PyVista is unavailable.
    """
    try:
        import pyvista as pv
    except ImportError:
        print('  PyVista not available — skipping 3-D plot.')
        return

    r     = data['r']       # (nr,)
    theta = data['theta']   # (nth,)
    z     = data['z']       # (nz,)

    # Build Cartesian coordinates  shape (nr, nth, nz) each
    R3, TH3, Z3 = np.meshgrid(r, theta, z, indexing='ij')
    X = R3 * np.cos(TH3)
    Y = R3 * np.sin(TH3)

    # PyVista StructuredGrid expects (nr, nth, nz) — correct order
    grid = pv.StructuredGrid(X, Y, Z3)

    alpha_s = data.get('alpha_solid')
    T_s     = data.get('T_solid')
    if alpha_s is not None:
        grid['alpha_solid'] = alpha_s.flatten(order='F')
    if T_s is not None:
        grid['T_solid'] = T_s.flatten(order='F')

    pl = pv.Plotter(off_screen=True, window_size=(1200, 900))
    pl.background_color = 'white'

    # Iso-surface of solid fraction
    if alpha_s is not None and alpha_s.max() > 0.1:
        iso_val = min(0.30, alpha_s.max() * 0.5)
        try:
            iso = grid.contour([iso_val], scalars='alpha_solid')
            if iso.n_points > 0:
                scalar = 'T_solid' if T_s is not None else 'alpha_solid'
                pl.add_mesh(iso, scalars=scalar, cmap='hot', opacity=0.85,
                            show_scalar_bar=True,
                            scalar_bar_args={'title': scalar.replace('_', ' '),
                                             'vertical': True})
        except Exception:
            pl.add_mesh(grid.outline(), color='gray')
    else:
        pl.add_mesh(grid.outline(), color='gray')

    # Vessel outline cylinder
    cyl = pv.Cylinder(center=(0, 0, H_TOTAL / 2), direction=(0, 0, 1),
                      radius=R_SHELL, height=H_TOTAL, resolution=60)
    pl.add_mesh(cyl, color='lightgray', opacity=0.12, style='wireframe')

    # Electrodes
    for angle in ELEC_ANGLES:
        xe = R_PCD * np.cos(angle)
        ye = R_PCD * np.sin(angle)
        elec = pv.Cylinder(center=(xe, ye, H_TOTAL * 0.625),
                           direction=(0, 0, 1),
                           radius=R_ELEC, height=H_TOTAL * 0.65, resolution=20)
        pl.add_mesh(elec, color='darkred', opacity=0.88)

    t_str = f"t = {data['time']:.2f} s  (step {data['step']})"
    pl.add_text(f'{title}\n{t_str}', position='upper_left',
                font_size=11, color='black')

    pl.camera.position = (9, 7, 7)
    pl.camera.focal_point = (0, 0, H_TOTAL / 2)
    pl.camera.up = (0, 0, 1)

    output_path = Path(output_path)
    pl.screenshot(str(output_path))
    pl.close()
    print(f'  Saved: {output_path}')


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description='Visualize EAF HDF5 simulation results')
    ap.add_argument('--h5-dir',     default='output',
                    help='Directory containing eaf3d_XXXXXXXX.h5 files')
    ap.add_argument('--output-dir', default='output/viz',
                    help='Output directory for PNG images')
    ap.add_argument('--step-init',  type=int, default=1,
                    help='Step number for "initial" snapshot (default: 1)')
    ap.add_argument('--step-final', type=int, default=10,
                    help='Step number for "final"   snapshot (default: 10)')
    ap.add_argument('--no-3d', action='store_true',
                    help='Skip PyVista 3-D renders')
    args = ap.parse_args()

    h5_dir  = Path(args.h5_dir)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    f_init  = h5_dir / f'eaf3d_{args.step_init:08d}.h5'
    f_final = h5_dir / f'eaf3d_{args.step_final:08d}.h5'

    print('EAF Results Visualizer')
    print('=' * 50)

    print(f'Loading  initial: {f_init}')
    d_init  = load_h5(f_init)
    print(f'         t = {d_init["time"]:.2f} s,  '
          f'mesh = {len(d_init["r"])} × {len(d_init["theta"])} × {len(d_init["z"])}')

    print(f'Loading  final  : {f_final}')
    d_final = load_h5(f_final)
    print(f'         t = {d_final["time"]:.2f} s')

    print('\nGenerating plots...')

    tag_i = f'step{args.step_init:02d}'
    tag_f = f'step{args.step_final:02d}'

    # 2×3 field panels
    plot_rz_fields(d_init,  'EAF — Initial State',
                   out_dir / f'eaf_fields_{tag_i}.png')
    plot_rz_fields(d_final, 'EAF — Final State',
                   out_dir / f'eaf_fields_{tag_f}.png')

    # 2×2 comparison
    plot_comparison(d_init, d_final,
                    out_dir / 'eaf_comparison.png')

    # 3-D PyVista renders
    if not args.no_3d:
        plot_3d_pyvista(d_init,  out_dir / f'eaf_3d_{tag_i}.png',
                        title='EAF — Initial State')
        plot_3d_pyvista(d_final, out_dir / f'eaf_3d_{tag_f}.png',
                        title='EAF — Final State')

    print(f'\nAll plots saved to: {out_dir.resolve()}')


if __name__ == '__main__':
    main()
