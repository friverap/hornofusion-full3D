#!/usr/bin/env python3
"""Conservación de masa en la fusión (guardián de los fixes 3.2/3.3).

Compara el primer y el último snapshot de una corrida melt_forced:
  dm_liquido = SUM(alpha_liquid * rho_steel * vol) debe igualar
  -dm_solido = -SUM(mass_solid) con tolerancia relativa (default 0.5 %).

Pre-C1.1 el líquido gana ~max_outer veces lo que pierde el sólido
(la fuente mdot se aplica una vez por iteración externa) -> FAIL esperado.

Uso: check_melt.py RUNDIR --config CFG [--rtol 0.005]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import cell_volumes, load_snapshot, read_config, snapshots


def masses(path, rho_steel):
    fields, mesh, meta = load_snapshot(path)
    vol = cell_volumes(mesh)
    m_liq = float(np.sum(fields["alpha_liquid"] * rho_steel * vol))
    m_sol = float(np.sum(fields["mass_solid"]))
    return m_liq, m_sol, int(meta.get("step", -1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--config", required=True)
    ap.add_argument("--rtol", type=float, default=0.005)
    args = ap.parse_args()

    cfg = read_config(args.config)
    rho = float(cfg["rho_steel"])
    files = snapshots(args.rundir)
    ml0, ms0, s0 = masses(files[0], rho)
    ml1, ms1, s1 = masses(files[-1], rho)

    dm_l, dm_s = ml1 - ml0, ms1 - ms0
    print(f"[melt] {args.rundir} (steps {s0}->{s1})")
    print(f"  m_solido: {ms0:.6e} -> {ms1:.6e} kg (dm_s = {dm_s:+.6e})")
    print(f"  m_liquido: {ml0:.6e} -> {ml1:.6e} kg (dm_l = {dm_l:+.6e})")

    if dm_s >= 0.0 or abs(dm_s) < 1.0:
        print("  FAIL  melt_mass  test inconcluyente: no hubo fusión "
              f"(dm_s = {dm_s:+.3e} kg) — revisar melt_forced.dat")
        sys.exit(1)

    err = abs(dm_l + dm_s) / abs(dm_s)
    ratio = dm_l / (-dm_s)
    ok = err <= args.rtol
    tag = "PASS " if ok else "FAIL "
    print(f"  {tag} melt_mass  dm_l/(-dm_s) = {ratio:.4f} "
          f"(err rel = {err:.3e}, tol = {args.rtol})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
