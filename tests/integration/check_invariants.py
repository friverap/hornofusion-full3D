#!/usr/bin/env python3
"""Invariantes de acotación/positividad sobre todos los snapshots de una corrida.

Uso: check_invariants.py RUNDIR --config CFG [--xfail id1,id2,...]

Chequeos (ids para xfail):
  nan            : todos los campos finitos (NUNCA debe ir en xfail)
  alpha_bounds   : -tol <= alpha_{liquid,gas,solid,slag} <= 1+tol
  sum_alpha      : suma de alphas ~ 0 (celda inactiva) o ~ 1 (activa)
  T_liquid_bound : 250 <= T_liquid <= 4000 K
  T_solid_bound  : 250 <= T_solid <= 4000 K
  T_gas_bound    : 100 <= T_gas; <= 4000 K fuera de la columna de arco,
                   <= 25000 K dentro (r_loc < 2*sigma_r)
  Y_bounds       : Y en [0,1], Y_CO + Y_CO2 <= 1+tol
  turb_positive  : tke >= 0, epsilon >= 0
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import (Checker, arc_column_mask, load_snapshot, parse_xfail_arg,
                     read_config, snapshots)

TOL = 1e-12


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--config", required=True)
    ap.add_argument("--xfail", default="")
    args = ap.parse_args()

    cfg = read_config(args.config)
    chk = Checker(parse_xfail_arg(args.xfail))
    print(f"[invariants] {args.rundir}")

    worst = {}

    def track(key, value, detail):
        if key not in worst or value > worst[key][0]:
            worst[key] = (value, detail)

    arc_mask = None
    files = snapshots(args.rundir)
    for path in files:
        fields, mesh, meta = load_snapshot(path)
        step = int(meta.get("step", -1))
        if arc_mask is None:
            arc_mask = arc_column_mask(mesh, cfg)

        for name, arr in fields.items():
            n_bad = int(np.size(arr) - np.isfinite(arr).sum())
            track("nan", n_bad, f"{name} step {step}: {n_bad} no-finitos")

        alphas = [fields[k] for k in
                  ("alpha_liquid", "alpha_gas", "alpha_solid", "alpha_slag")]
        a_min = min(float(np.nanmin(a)) for a in alphas)
        a_max = max(float(np.nanmax(a)) for a in alphas)
        track("alpha_bounds", max(-a_min, a_max - 1.0),
              f"step {step}: min={a_min:.3e} max={a_max:.6f}")

        s = sum(alphas)
        dist = np.minimum(np.abs(s), np.abs(s - 1.0))
        track("sum_alpha", float(np.nanmax(dist)),
              f"step {step}: max|sum_alpha - {{0,1}}| = {np.nanmax(dist):.3e}")

        for fname, cid, lo, hi in (("T_liquid", "T_liquid_bound", 250., 4000.),
                                   ("T_solid", "T_solid_bound", 250., 4000.)):
            arr = fields[fname]
            viol = max(float(lo - np.nanmin(arr)), float(np.nanmax(arr) - hi))
            track(cid, viol, f"step {step}: [{np.nanmin(arr):.1f}, "
                             f"{np.nanmax(arr):.1f}] K")

        tg = fields["T_gas"]
        out_max = float(np.nanmax(np.where(arc_mask, -np.inf, tg)))
        in_max = float(np.nanmax(np.where(arc_mask, tg, -np.inf)))
        viol = max(100.0 - float(np.nanmin(tg)), out_max - 4000.0,
                   in_max - 25000.0)
        track("T_gas_bound", viol,
              f"step {step}: min={np.nanmin(tg):.1f} fuera_arco_max="
              f"{out_max:.1f} arco_max={in_max:.1f} K")

        yco, yco2 = fields["Y_CO"], fields["Y_CO2"]
        yo2 = fields.get("Y_O2", np.zeros_like(yco))
        viol = max(-float(np.nanmin(yco)), -float(np.nanmin(yco2)),
                   -float(np.nanmin(yo2)),
                   float(np.nanmax(yco)) - 1.0, float(np.nanmax(yco2)) - 1.0,
                   float(np.nanmax(yo2)) - 1.0,
                   float(np.nanmax(yco + yco2 + yo2)) - 1.0)
        track("Y_bounds", viol, f"step {step}")

        viol = max(-float(np.nanmin(fields["tke"])),
                   -float(np.nanmin(fields["epsilon"])))
        track("turb_positive", viol, f"step {step}")

    print(f"  ({len(files)} snapshots)")
    order = ["nan", "alpha_bounds", "sum_alpha", "T_liquid_bound",
             "T_solid_bound", "T_gas_bound", "Y_bounds", "turb_positive"]
    for cid in order:
        val, detail = worst[cid]
        chk.report(cid, val <= TOL if cid == "nan" else val <= TOL, detail)
    chk.exit()


if __name__ == "__main__":
    main()
