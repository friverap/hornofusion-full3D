#!/usr/bin/env python3
"""
eaf_geometry_simple.py - EAF furnace geometry visualization (matplotlib, no pyvista)

Generates:
  output/viz/eaf_geometry.png  — r-z cross-section + top-view r-θ diagram
"""

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from pathlib import Path

# EAF geometry — must match input/config_10step_full_physics.dat
R_SHELL = 3.80   # m  furnace inner radius
H_TOTAL = 4.50   # m  total height
H_BOWL  = 0.60   # m  bowl depth
R_BOWL  = 2.50   # m  bowl radius at shell floor
R_PCD   = 0.85   # m  electrode pitch circle RADIUS
R_ELEC  = 0.30   # m  electrode radius


def bowl_z(r):
    """Parabolic bowl floor: z_floor(r)"""
    return np.where(r <= R_BOWL, H_BOWL * (r / R_BOWL) ** 2, H_BOWL)


def draw_rz_cross_section(ax):
    """r-z plane cross-section of the EAF furnace."""
    r_full = np.linspace(0, R_SHELL, 500)

    # ── Refractory bowl ─────────────────────────────────────────────────────
    z_fl = bowl_z(r_full)
    ax.fill_between(r_full, 0, z_fl, color='#8B7355', alpha=0.85, label='Refractory bowl')
    ax.plot(r_full, z_fl, 'k-', lw=1.8)

    # ── Scrap charge bed ────────────────────────────────────────────────────
    z_scrap_top = H_BOWL + 1.80   # approximate scrap surface height
    ax.fill_between(r_full, z_fl, np.minimum(z_scrap_top, H_TOTAL),
                    color='#B0B0B0', alpha=0.55, label='Scrap charge')

    # ── Vessel walls & roof ─────────────────────────────────────────────────
    ax.plot([R_SHELL, R_SHELL], [0, H_TOTAL], 'k-', lw=2.5)
    ax.plot([0, R_SHELL], [H_TOTAL, H_TOTAL], 'k-', lw=2.5, label='Vessel')
    ax.plot([0, R_SHELL], [0, 0], 'k-', lw=1.5)

    # ── Electrodes (appear at r = R_PCD in the r-z plane) ───────────────────
    elec_z_bot = z_scrap_top - 0.10   # tip just above scrap
    elec_z_top = H_TOTAL * 0.95
    rect = patches.Rectangle(
        (R_PCD - R_ELEC, elec_z_bot), 2 * R_ELEC, elec_z_top - elec_z_bot,
        linewidth=1.5, edgecolor='#5C0000', facecolor='#8B0000', alpha=0.88,
        zorder=5, label='Electrode')
    ax.add_patch(rect)

    # Arc flash below tip
    n = 40
    arc_r = np.linspace(R_PCD - R_ELEC * 0.6, R_PCD + R_ELEC * 0.6, n)
    arc_z = elec_z_bot - 0.12 * np.abs(np.sin(np.pi * np.arange(n) / (n - 1)))
    ax.fill_between(arc_r, elec_z_bot, arc_z, color='yellow', alpha=0.85, zorder=6)

    # ── Symmetry axis ────────────────────────────────────────────────────────
    ax.axvline(0, color='gray', lw=0.9, ls='--', alpha=0.6)

    # ── Annotations ─────────────────────────────────────────────────────────
    ax.annotate('Electrode\n(graphite)', xy=(R_PCD + R_ELEC, (elec_z_top + elec_z_bot) / 2),
                xytext=(R_PCD + 0.55, (elec_z_top + elec_z_bot) / 2),
                arrowprops=dict(arrowstyle='->', color='#8B0000'),
                color='#8B0000', fontsize=8, va='center')
    ax.annotate('Arc', xy=(R_PCD, elec_z_bot - 0.08),
                xytext=(R_PCD + 0.55, elec_z_bot - 0.45),
                arrowprops=dict(arrowstyle='->', color='goldenrod'),
                color='goldenrod', fontsize=8)
    ax.text(0.06, H_BOWL * 0.5, 'Axis\n(sym.)', color='gray', fontsize=7.5, ha='left')
    ax.text(R_SHELL - 0.06, H_TOTAL * 0.5, 'Shell\nwall', color='k',
            fontsize=8, ha='right', va='center')
    ax.text(R_BOWL * 0.45, H_BOWL * 0.5, 'Bowl', color='#5C3B1A', fontsize=8, ha='center')

    # ── Dimension arrows ─────────────────────────────────────────────────────
    ax.annotate('', xy=(R_SHELL, -0.15), xytext=(0, -0.15),
                arrowprops=dict(arrowstyle='<->', color='#333333', lw=1.2))
    ax.text(R_SHELL / 2, -0.22, f'R_shell = {R_SHELL} m',
            ha='center', va='top', fontsize=8, color='#333333')
    ax.annotate('', xy=(R_SHELL + 0.18, H_TOTAL), xytext=(R_SHELL + 0.18, 0),
                arrowprops=dict(arrowstyle='<->', color='#333333', lw=1.2))
    ax.text(R_SHELL + 0.22, H_TOTAL / 2, f'H = {H_TOTAL} m',
            ha='left', va='center', fontsize=8, color='#333333', rotation=90)

    ax.set_xlim(-0.15, R_SHELL + 0.55)
    ax.set_ylim(-0.35, H_TOTAL + 0.3)
    ax.set_xlabel('r  [m]', fontsize=11)
    ax.set_ylabel('z  [m]', fontsize=11)
    ax.set_title('r-z Cross-Section  (θ = 0°)', fontsize=11)
    ax.set_aspect('equal')
    ax.legend(loc='upper right', fontsize=8, framealpha=0.85)
    ax.grid(True, alpha=0.2)


def draw_top_view(ax):
    """r-θ top-down view of the EAF at mid-height."""
    theta_c = np.linspace(0, 2 * np.pi, 500)

    # Shell
    ax.fill(R_SHELL * np.cos(theta_c), R_SHELL * np.sin(theta_c),
            color='#D0D0D0', alpha=0.35)
    ax.plot(R_SHELL * np.cos(theta_c), R_SHELL * np.sin(theta_c),
            'k-', lw=2.5, label=f'Shell  (R = {R_SHELL} m)')

    # Scrap bed
    ax.fill(0.97 * R_SHELL * np.cos(theta_c), 0.97 * R_SHELL * np.sin(theta_c),
            color='#A0A0A0', alpha=0.45, label='Scrap charge')

    # Electrode pitch circle
    ax.plot(R_PCD * np.cos(theta_c), R_PCD * np.sin(theta_c),
            'r--', lw=0.9, alpha=0.6, label=f'PCD  (R = {R_PCD} m)')

    # Electrodes at 0°, 120°, 240°
    for k, angle in enumerate([0, 2 * np.pi / 3, 4 * np.pi / 3]):
        xe = R_PCD * np.cos(angle)
        ye = R_PCD * np.sin(angle)
        elec = plt.Circle((xe, ye), R_ELEC,
                          facecolor='#8B0000', edgecolor='#3C0000',
                          linewidth=1.2, alpha=0.90, zorder=6)
        ax.add_patch(elec)
        label_r = R_PCD + R_ELEC + 0.20
        ax.text(label_r * np.cos(angle), label_r * np.sin(angle),
                f'E{k + 1}\n({np.degrees(angle):.0f}°)',
                ha='center', va='center', fontsize=8, color='#8B0000')

    # Axis cross
    ax.axhline(0, color='gray', lw=0.7, ls='--', alpha=0.5)
    ax.axvline(0, color='gray', lw=0.7, ls='--', alpha=0.5)
    ax.plot(0, 0, 'k+', ms=6)

    ax.set_xlim(-(R_SHELL + 0.5), R_SHELL + 0.5)
    ax.set_ylim(-(R_SHELL + 0.5), R_SHELL + 0.5)
    ax.set_aspect('equal')
    ax.set_xlabel('x  [m]', fontsize=11)
    ax.set_ylabel('y  [m]', fontsize=11)
    ax.set_title('Top View  (r-θ plane)', fontsize=11)
    ax.legend(loc='upper right', fontsize=8, framealpha=0.85)
    ax.grid(True, alpha=0.25)


def main():
    out_dir = Path('output/viz')
    out_dir.mkdir(parents=True, exist_ok=True)

    fig, axes = plt.subplots(1, 2, figsize=(14, 7))
    fig.suptitle('130-ton AC EAF — Furnace Geometry', fontsize=14, fontweight='bold')

    draw_rz_cross_section(axes[0])
    draw_top_view(axes[1])

    plt.tight_layout()
    out_file = out_dir / 'eaf_geometry.png'
    plt.savefig(str(out_file), dpi=150, bbox_inches='tight')
    plt.close()
    print(f'Saved: {out_file}')


if __name__ == '__main__':
    main()
