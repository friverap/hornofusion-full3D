#!/usr/bin/env python3
"""check_pocket.py RUNDIR [--xfail ids] (auditoria 6, M4-12)

Bolsa de gas bajo una capa saturada del lecho (pocket_rise, opcion
pc_bed_gas_pocket): el gas debe subir a contracorriente SIN retencion.
  pocket_onset   alpha_g de la capa saturada (8) >= 0.05 en t = 0.15 s
                 (medido 0.082; sin la opcion 0.015: la capa queda retenida
                 0.25-0.3 s, la «tapa» de M4-12)
  pocket_rise    alpha_g de la capa 8 sube >= 0.2 al final (medido 0.30 en
                 0.5 s) y la bolsa (capa 7) pierde gas
  pocket_bounded p_max <= 1.1 x la inicial (medido 1.06; sin la opcion 1.22) y
                 |u_g| de los snapshots <= 35 m/s (medido 28.6; sin la opcion 42.2)
"""
import argparse, glob, os, sys
import numpy as np
import h5py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg

ap = argparse.ArgumentParser()
ap.add_argument("rundir")
ap.add_argument("--xfail", default="")
a = ap.parse_args()
chk = Checker(parse_xfail_arg(a.xfail))
rows = []
for fn in sorted(glob.glob(os.path.join(a.rundir, "eaf3d_*.h5"))):
    with h5py.File(fn) as f:
        ct = f["mesh/cell_type"][()]; ag = f["fields/alpha_gas"][()]
        t = float(np.ravel(f["metadata"].attrs.get("time", 0.0))[0])
        p = np.abs(f["fields/pressure"][()]).max(); ug = np.abs(f["fields/velocity_z_gas"][()]).max()
        rows.append((t, [float(ag[k][ct[k] != 0].mean()) for k in (6, 7)], p, ug))
print(f"[pocket] {a.rundir} ({len(rows)} snapshots)")
t015 = min(rows, key=lambda r: abs(r[0] - 0.15))
chk.report("pocket_onset", t015[1][1] >= 0.05,
           f"alpha_g capa 8 en t = {t015[0]:.3f} s: {t015[1][1]:.3f} (min 0.05; sin la opcion 0.015)")
rise = rows[-1][1][1] - rows[0][1][1]; drop = rows[0][1][0] - rows[-1][1][0]
chk.report("pocket_rise", rise >= 0.2 and drop > 0.0,
           f"capa 8: +{rise:.3f} de gas (min 0.2); bolsa (capa 7): -{drop:.3f}")
p0 = rows[0][2]; pm = max(r[2] for r in rows); um = max(r[3] for r in rows)
chk.report("pocket_bounded", pm <= 1.1 * p0 and um <= 35.0,
           f"p_max {pm/1e3:.1f} kPa (inicial {p0/1e3:.1f}, factor 1.1), |u_g| max {um:.2f} m/s (max 35)")
chk.exit()
