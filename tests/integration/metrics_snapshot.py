#!/usr/bin/env python3
"""Métricas golden: escalares (min/max/mean por campo) del snapshot final
de cada corrida bajo tests/out/. Nunca se guardan campos completos.

Modos:
  --mode check      compara las corridas presentes contra el golden más
                    reciente (tests/golden/metrics_v*.json, mayor versión).
                    Falla si difieren más de --rtol o si una corrida no
                    existe en el golden (sugiere rebaseline).
  --mode rebaseline escribe/actualiza el golden indicado por --stage
                    (default: el más reciente; crea metrics_v0.json si no
                    hay ninguno) fusionando las corridas presentes.

Determinismo esperado: mismo binario + mismo nprocs => misma salida
(RNG del MC con semilla fija, reducciones MPI de orden fijo), por eso el
rtol por defecto es 1e-12. Los valores cambian legítimamente solo cuando
un fix cambia la numérica: regenerar UNA vez al cierre de cada etapa.

Uso: metrics_snapshot.py OUTDIR --mode check|rebaseline [--rtol 1e-12]
     [--stage v1] [--golden-dir tests/golden]
"""
import argparse
import glob
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import load_snapshot


def collect_run(rundir):
    files = sorted(glob.glob(os.path.join(rundir, "eaf3d_*.h5")))
    if not files:
        return None
    fields, _, meta = load_snapshot(files[-1])
    entry = {
        "final_step": int(meta["step"]),
        "final_time": float(meta["time"]),
        "n_snapshots": len(files),
        "fields": {},
    }
    for name in sorted(fields):
        a = fields[name]
        entry["fields"][name] = {
            "min": float(np.min(a)),
            "max": float(np.max(a)),
            "mean": float(np.mean(a)),
        }
    return entry


def golden_files(golden_dir):
    files = glob.glob(os.path.join(golden_dir, "metrics_v*.json"))

    def version_key(p):
        m = re.search(r"metrics_v(\d+(?:\.\d+)*)\.json$", p)
        return [int(x) for x in m.group(1).split(".")] if m else [-1]

    return sorted(files, key=version_key)


def rel_diff(a, b):
    scale = max(abs(a), abs(b), 1e-300)
    return abs(a - b) / scale if scale > 1e-30 else abs(a - b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--mode", choices=["check", "rebaseline"], required=True)
    ap.add_argument("--rtol", type=float, default=1e-12)
    ap.add_argument("--stage", default=None,
                    help="sufijo del golden a escribir, ej. v1")
    ap.add_argument("--golden-dir", default=None)
    ap.add_argument("--only", default=None,
                    help="csv de nombres de corrida a considerar (modo quick)")
    args = ap.parse_args()
    only = set(s.strip() for s in args.only.split(",")) if args.only else None

    here = os.path.dirname(os.path.abspath(__file__))
    golden_dir = args.golden_dir or os.path.join(here, "..", "golden")
    os.makedirs(golden_dir, exist_ok=True)

    runs = {}
    for d in sorted(glob.glob(os.path.join(args.outdir, "*"))):
        if os.path.isdir(d):
            name = os.path.basename(d)
            if only is not None and name not in only:
                continue
            entry = collect_run(d)
            if entry:
                runs[name] = entry
    if not runs:
        sys.exit(f"ERROR: sin corridas con snapshots en {args.outdir}")

    existing = golden_files(golden_dir)

    if args.mode == "rebaseline":
        if args.stage:
            path = os.path.join(golden_dir, f"metrics_{args.stage}.json")
        elif existing:
            path = existing[-1]
        else:
            path = os.path.join(golden_dir, "metrics_v0.json")
        data = {"runs": {}}
        if os.path.exists(path):
            with open(path) as f:
                data = json.load(f)
        data["runs"].update(runs)
        with open(path, "w") as f:
            json.dump(data, f, indent=1, sort_keys=True)
        print(f"[metrics] golden actualizado: {path} "
              f"({', '.join(sorted(runs))})")
        return

    if not existing:
        sys.exit("FAIL: no existe ningún golden — ejecutar "
                 "'make test-rebaseline' primero")
    path = existing[-1]
    with open(path) as f:
        golden = json.load(f)["runs"]

    print(f"[metrics] comparando contra {os.path.basename(path)} "
          f"(rtol {args.rtol})")
    fail = False
    for run, entry in sorted(runs.items()):
        if run not in golden:
            print(f"  FAIL  {run}: no está en el golden "
                  "(¿falta 'make test-rebaseline'?)")
            fail = True
            continue
        g = golden[run]
        worst, worst_id = 0.0, ""
        for key in ("final_step", "n_snapshots"):
            if int(entry[key]) != int(g[key]):
                print(f"  FAIL  {run}: {key} = {entry[key]} vs "
                      f"golden {g[key]}")
                fail = True
        for fname, stats in entry["fields"].items():
            gstats = g["fields"].get(fname)
            if gstats is None:
                print(f"  FAIL  {run}: campo nuevo '{fname}' no está en "
                      "el golden")
                fail = True
                continue
        for fname, stats in entry["fields"].items():
            gstats = g["fields"].get(fname)
            if gstats is None:
                continue
            for stat in ("min", "max", "mean"):
                d = rel_diff(stats[stat], gstats[stat])
                if d > worst:
                    worst, worst_id = d, f"{fname}.{stat}"
        ok = worst <= args.rtol
        print(f"  {'PASS ' if ok else 'FAIL '} {run}: peor métrica "
              f"{worst_id or '-'} (err rel {worst:.3e})")
        fail = fail or not ok
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
