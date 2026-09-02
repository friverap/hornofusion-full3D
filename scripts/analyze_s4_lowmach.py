#!/usr/bin/env python3
"""Análisis S4: cuantificar el agujero EOS que el acople low-Mach elimina.

Compara las corridas lowmach_on / lowmach_off (bore-in 60 s):
  - masa de gas: con acople debe DECRECER por venteo físico (flujo por
    puertos); sin acople "desaparece" sin flujo (el agujero EOS).
  - dónde se nota: m_gas(t) del audit + velocidad en puertos del último
    snapshot.
Genera la figura paper/figures/lowmach_gas_mass.pdf (m_gas vs t, ambas
corridas) y reporta los números para §6.

Uso: analyze_s4_lowmach.py [campaigns/s4]
"""
import csv
import glob
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(REPO, "tests", "integration"))
from eafutil import safe_float  # noqa: E402

base = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "campaigns/s4")


def series(run):
    rows = [{k: safe_float(v) for k, v in r.items()}
            for r in csv.DictReader(
                open(os.path.join(base, run, "audit.csv")))]
    t = np.array([r["time"] for r in rows])
    mg = np.array([r["m_gas"] for r in rows])
    return t, mg, rows


t_on, mg_on, rows_on = series("lowmach_on")
t_off, mg_off, rows_off = series("lowmach_off")

print("== S4: agujero EOS vs venteo físico (bore-in, 60 s)")
print(f"lowmach ON : m_gas {mg_on[0]:.1f} -> {mg_on[-1]:.1f} kg "
      f"({100*(mg_on[-1]/mg_on[0]-1):+.1f}%)")
print(f"lowmach OFF: m_gas {mg_off[0]:.1f} -> {mg_off[-1]:.1f} kg "
      f"({100*(mg_off[-1]/mg_off[0]-1):+.1f}%)")

# velocidad máxima de venteo en el último snapshot (roof) de cada corrida
import h5py
for run in ("lowmach_on", "lowmach_off"):
    snaps = sorted(glob.glob(os.path.join(base, run, "eaf3d_*.h5")))
    with h5py.File(snaps[-1]) as h:
        uz = h["fields/velocity_z_gas"][:]
        print(f"{run}: |uz_gas| techo max = {np.nanmax(np.abs(uz[-1])):.1f} "
              f"m/s (global {np.nanmax(np.abs(uz)):.1f})")

fig, ax = plt.subplots(figsize=(4.4, 3.0))
ax.plot(t_on, mg_on, "-", color="#1a5fb4", lw=1.6,
        label="low-Mach coupling on (physical venting)")
ax.plot(t_off, mg_off, "--", color="#c0392b", lw=1.6,
        label="coupling off (no venting: inventory frozen)")
ax.set_xlabel("simulated time [s]")
ax.set_ylabel("gas inventory [kg]")
ax.legend(fontsize=7.5, loc="best")
fig.tight_layout()
out = os.path.join(REPO, "paper", "figures", "lowmach_gas_mass.pdf")
fig.savefig(out, bbox_inches="tight")
print(f"figura: {out}")
