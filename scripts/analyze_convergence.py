#!/usr/bin/env python3
"""Análisis de autoconvergencia C2 (temporal) y C3 (iterativa) del paper.

C2: orden observado p = log2(||f_2h - f_h|| / ||f_h - f_{h/2}||) sobre los
    campos del snapshot final (mismo t_final, dt/2 anidado).
C3: error del balance de energía (check_audit) vs tolerancia del lazo.

Uso: analyze_convergence.py campaigns/f2
"""
import csv
import glob
import os
import sys

import h5py
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(REPO, "tests", "integration"))
from eafutil import safe_float  # noqa: E402

base = sys.argv[1] if len(sys.argv) > 1 else "campaigns/f2"


def last_snap(run):
    files = sorted(glob.glob(os.path.join(base, run, "eaf3d_*.h5")))
    return files[-1]


def field(run, name):
    with h5py.File(last_snap(run)) as h:
        return h[f"fields/{name}"][:]


print("== C2: orden temporal observado (dt=0.02 / 0.01 / 0.005, t=0.16 s)")
print(f"{'campo':14s} {'||e_2h||':>12s} {'||e_h||':>12s} {'orden p':>8s}")
for f in ("T_gas", "T_solid", "velocity_z_gas", "pressure"):
    f20 = field("c2_dt20", f)
    f10 = field("c2_dt10", f)
    f05 = field("c2_dt05", f)
    e1 = np.sqrt(np.nanmean((f20 - f10) ** 2))
    e2 = np.sqrt(np.nanmean((f10 - f05) ** 2))
    p = np.log2(e1 / e2) if e2 > 0 else float("nan")
    print(f"{f:14s} {e1:12.4e} {e2:12.4e} {p:8.2f}")

print()
print("== C3: balance de energía vs tolerancia del lazo externo")
print(f"{'tol':>8s} {'err balance':>12s} {'outers(último)':>15s}")
for n in range(3, 10):
    run = f"c3_tol{n}"
    audit = os.path.join(base, run, "audit.csv")
    if not os.path.exists(audit):
        continue
    rows = [{k: safe_float(v) for k, v in r.items()}
            for r in csv.DictReader(open(audit))]
    first, last = rows[0], rows[-1]
    steps = rows[1:]

    def S(c):
        return sum(r.get(c, 0.0) for r in steps)

    dE = (last["E_liq"] - first["E_liq"] + last["E_sol"] - first["E_sol"] +
          last["E_slag"] - first["E_slag"] + S("E_gas_abs"))
    E_in = (S("E_src_liq_arc") + S("E_src_liq_rad") + S("E_src_liq_chem") +
            S("E_src_gas_arc") + S("E_src_gas_rad") + S("E_src_gas_chem") +
            S("E_arc_direct_sol") + S("E_slag_intercept") + S("E_rad_sol") +
            S("E_conv_defect") - S("E_wall_conv") + S("E_chem_sol") +
            S("E_ecs_in"))
    gross = sum(abs(r.get("E_melt_from_solid", 0.0)) for r in steps)
    scale = max(abs(dE), abs(E_in), gross, 1.0)
    err = abs(dE - E_in) / scale
    # outers del último paso (del log)
    outers = "?"
    log = os.path.join(base, run, "run.log")
    if os.path.exists(log):
        for line in reversed(open(log).readlines()):
            if "[STEP]" in line and "outer=" in line:
                outers = line.split("outer=")[1].split()[0]
                break
    print(f"1e-{n:<5d} {err:12.4e} {outers:>15s}")
