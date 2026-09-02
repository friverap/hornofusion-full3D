#!/usr/bin/env python3
"""Runner de campañas de simulación EAF3D (P0.2, roadmap del paper).

Lanza N corridas definidas como (config plantilla + overrides), una carpeta
por corrida, en serie (el binario ya usa todos los núcleos vía MPI). Al
final produce una tabla resumen CSV con métricas escalares de cada corrida
(inventarios finales del audit + extremos de campos del último snapshot).

Uso:
    python3 scripts/run_campaign.py campaign.json [--dry-run]

Formato de campaign.json:
{
  "template": "tests/integration/configs/cold_10step.dat",
  "outdir":   "campaigns/mi_campana",
  "nprocs":   8,
  "binary":   "bin/eaf3d_mpi",
  "runs": [
    {"name": "dt_base",  "overrides": {"dt": 0.02}},
    {"name": "dt_half",  "overrides": {"dt": 0.01, "t_final": 0.2}}
  ]
}

Los overrides se APPENDEAN al final del config (el parser toma la última
aparición de cada clave), así la plantilla queda intacta y el config
efectivo de cada corrida es auditable en su carpeta.
"""
import argparse
import csv
import glob
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(REPO, "tests", "integration"))
from eafutil import safe_float  # noqa: E402


def load_last_snapshot_stats(rundir):
    import h5py
    import numpy as np
    snaps = sorted(glob.glob(os.path.join(rundir, "eaf3d_*.h5")))
    if not snaps:
        return {}
    out = {}
    with h5py.File(snaps[-1]) as h:
        for f in ("T_gas", "T_solid", "T_liquid", "alpha_solid",
                  "alpha_liquid", "pressure"):
            if f"fields/{f}" in h:
                a = h[f"fields/{f}"][:]
                out[f"{f}_min"] = float(np.nanmin(a))
                out[f"{f}_max"] = float(np.nanmax(a))
    out["n_snapshots"] = len(snaps)
    return out


def load_audit_summary(rundir):
    path = os.path.join(rundir, "audit.csv")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        rows = [{k: safe_float(v) for k, v in r.items()}
                for r in csv.DictReader(f)]
    if len(rows) < 2:
        return {}
    first, last = rows[0], rows[-1]
    steps = rows[1:]
    out = {
        "t_final": last["time"], "n_steps": last["step"],
        "m_liq_final": last["m_liq"], "m_sol_final": last["m_sol"],
        "m_gas_final": last["m_gas"],
        "m_melted_total": sum(r.get("m_melted", 0.0) for r in steps),
        "E_arc_total": sum(0.5 * (a["P_arc"] + b["P_arc"]) *
                           (b["time"] - a["time"])
                           for a, b in zip(rows[:-1], rows[1:])),
    }
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("campaign", help="archivo JSON de la campana")
    ap.add_argument("--dry-run", action="store_true",
                    help="genera configs sin correr")
    args = ap.parse_args()

    spec = json.load(open(args.campaign))
    template = os.path.join(REPO, spec["template"])
    outdir = os.path.join(REPO, spec["outdir"])
    nprocs = spec.get("nprocs", 8)
    binary = os.path.join(REPO, spec.get("binary", "bin/eaf3d_mpi"))
    os.makedirs(outdir, exist_ok=True)

    base = open(template).read()
    results = []
    for run in spec["runs"]:
        rundir = os.path.join(outdir, run["name"])
        if os.path.exists(rundir):
            shutil.rmtree(rundir)
        os.makedirs(rundir)
        cfg_path = os.path.join(rundir, "config.dat")
        with open(cfg_path, "w") as f:
            f.write(base)
            f.write("\n# --- overrides de la campana ---\n")
            f.write(f"output_dir = {rundir}\n")
            for k, v in run.get("overrides", {}).items():
                f.write(f"{k} = {v}\n")
        print(f"[campaign] {run['name']}: config listo", flush=True)
        if args.dry_run:
            continue

        t0 = time.time()
        log = os.path.join(rundir, "run.log")
        with open(log, "w") as lf:
            rc = subprocess.run(
                ["mpirun", "-n", str(nprocs), binary, cfg_path],
                stdout=lf, stderr=subprocess.STDOUT, cwd=REPO).returncode
        wall = time.time() - t0
        row = {"name": run["name"], "exit": rc, "wall_s": round(wall, 1)}
        row.update(load_audit_summary(rundir))
        row.update(load_last_snapshot_stats(rundir))
        results.append(row)
        print(f"[campaign] {run['name']}: exit={rc} "
              f"wall={wall:.0f}s", flush=True)

    if results:
        keys = sorted({k for r in results for k in r},
                      key=lambda k: (k != "name", k))
        summary = os.path.join(outdir, "summary.csv")
        with open(summary, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=keys)
            w.writeheader()
            w.writerows(results)
        print(f"[campaign] resumen: {summary}")


if __name__ == "__main__":
    main()
