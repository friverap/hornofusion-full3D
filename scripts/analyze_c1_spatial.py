#!/usr/bin/env python3
"""C1: autoconvergencia ESPACIAL (3 mallas, refinamiento r=2, dt congelado).

Orden observado y GCI de Roache (1994):
    p   = ln(|f_c - f_m| / |f_m - f_f|) / ln(2)
    GCI_fino = 1.25 |f_m - f_f| / f_f / (2^p - 1)

Observables:
  - globales (limpios): masa fundida acumulada, E_sol y E_liq finales
    (del audit.csv, que integra toda la corrida)
  - campos (aproximados): L2 de T_s y alpha_s del último snapshot,
    restringiendo malla media (2^3) y fina (4^3) a la gruesa por promedio
    ponderado por volumen (pesos r*Δr*Δz por celda; las mallas comparten
    ley de stretch => la restricción por bloques es consistente a O(h))

Uso: analyze_c1_spatial.py [campaigns/c1]
"""
import csv
import glob
import math
import os
import sys

import h5py
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "campaigns/c1")

RUNS = ["c1_coarse", "c1_medium", "c1_fine"]


def audit_globals(run):
    path = os.path.join(BASE, run, "audit.csv")
    rows = [{k: float(v) for k, v in r.items()}
            for r in csv.DictReader(open(path))]
    last = rows[-1]
    if last["time"] < 29.5:
        return None
    return {
        "m_melted": sum(r["m_melted"] for r in rows),
        "E_sol": last["E_sol"],
        "E_liq": last["E_liq"],
    }


def load_last(run):
    snaps = sorted(glob.glob(os.path.join(BASE, run, "eaf3d_*.h5")))
    with h5py.File(snaps[-1]) as h:
        T = h["fields/T_solid"][:]        # (nz, nth, nr)
        a = h["fields/alpha_solid"][:]
        r = h["mesh/r"][:]
        z = h["mesh/z"][:]
    # pesos de volumen ~ r*Δr*Δz (Δθ uniforme se cancela en el promedio)
    dr = np.gradient(r)
    dz = np.gradient(z)
    w = dz[:, None, None] * np.ones_like(T[0:1, :, 0:1]) * (r * dr)[None, None, :]
    return T, a, np.broadcast_to(w, T.shape).copy()


def restrict(f, w, factor):
    """Promedio por bloques factor^3 ponderado por w (index-space)."""
    nz, nth, nr = f.shape
    s = (nz // factor, factor, nth // factor, factor, nr // factor, factor)
    fw = (f * w).reshape(s).sum(axis=(1, 3, 5))
    ww = w.reshape(s).sum(axis=(1, 3, 5))
    return fw / ww, ww


def order_gci(fc, fm, ff, name, rel=None):
    e_cm, e_mf = abs(fc - fm), abs(fm - ff)
    if e_mf < 1e-30:
        print(f"  {name:<22} diferencias nulas")
        return None
    p = math.log(e_cm / e_mf) / math.log(2.0)
    scale = abs(ff) if rel is None else rel
    gci = 1.25 * e_mf / max(scale, 1e-30) / (2.0 ** p - 1.0)
    print(f"  {name:<22} f=({fc:.6g}, {fm:.6g}, {ff:.6g})  "
          f"p={p:5.2f}  GCI_fino={100*gci:6.3f}%")
    return p


gs = {run: audit_globals(run) for run in RUNS}
if any(v is None for v in gs.values()):
    missing = [r for r in RUNS if gs[r] is None]
    print(f"PENDIENTE: faltan corridas completas: {missing}")
    sys.exit(0)

print("== C1: orden observado y GCI (globales del audit)")
orders = {}
for key in ("m_melted", "E_sol", "E_liq"):
    orders[key] = order_gci(gs["c1_coarse"][key], gs["c1_medium"][key],
                            gs["c1_fine"][key], key)

print("== C1: campos del último snapshot (L2 vs malla gruesa, restricción")
print("   por bloques ponderada por volumen)")
Tc, ac, wc = load_last("c1_coarse")
Tm, am, wm = load_last("c1_medium")
Tf, af, wf = load_last("c1_fine")
for name, (fc, fm, ff, wmm, wff) in {
        "T_s [K]": (Tc, Tm, Tf, wm, wf),
        "alpha_s": (ac, am, af, wm, wf)}.items():
    fm_r, wr = restrict(fm, wmm, 2)
    ff_r, _ = restrict(ff, wff, 4)
    l2 = lambda d: float(np.sqrt(np.sum(wc * d * d) / np.sum(wc)))
    e_cm, e_mf = l2(fc - fm_r), l2(fm_r - ff_r)
    p = math.log(e_cm / e_mf) / math.log(2.0)
    print(f"  L2({name:<9}) e(c,m)={e_cm:.4g}  e(m,f)={e_mf:.4g}  p={p:5.2f}")
    orders[f"L2_{name.split()[0]}"] = p
