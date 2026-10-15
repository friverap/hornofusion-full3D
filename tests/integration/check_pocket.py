#!/usr/bin/env python3
"""check_pocket.py RUNDIR [--xfail ids] (auditoria 6-7, M4-12)

Bolsa de gas bajo una capa saturada del lecho (pocket_rise, defaults): el gas
debe subir a contracorriente SIN retencion y SIN rafaga.
  pocket_onset   alpha_g de la capa saturada (8) >= 0.05 en t = 0.15 s
                 (medido 0.069)
  pocket_rise    alpha_g de la capa 8 sube >= 0.2 al final (medido +0.254)
                 y la bolsa (capa 7) pierde gas
  pocket_start   u_gas_max del AUDIT en los 5 primeros pasos <= 10 m/s
                 (medido 2.2-7.9; con la opcion retirada pc_bed_gas_pocket
                 45.5; con la presion no hidrostatica del estado viejo 79.6)
  pocket_bounded p_max del audit <= 1.05 x la inicial (medido 0.999) y
                 u_gas_max del audit <= 60 m/s (medido 44.7)
(auditoria 7, M7-3: los picos se leen del audit POR PASO; los snapshots,
cada 10 pasos, no veian la rafaga del arranque.)
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
           f"alpha_g capa 8 en t = {t015[0]:.3f} s: {t015[1][1]:.3f} (min 0.05)")
rise = rows[-1][1][1] - rows[0][1][1]; drop = rows[0][1][0] - rows[-1][1][0]
chk.report("pocket_rise", rise >= 0.2 and drop > 0.0,
           f"capa 8: +{rise:.3f} de gas (min 0.2); bolsa (capa 7): -{drop:.3f}")
import csv
au = list(csv.DictReader(open(os.path.join(a.rundir, "audit.csv"))))
p0 = float(au[0]["p_max"])
ug = [float(r["u_gas_max"]) for r in au[1:]]
pm = max(float(r["p_max"]) for r in au[1:])
chk.report("pocket_start", max(ug[:5]) <= 10.0,
           f"u_gas_max del audit en los pasos 1-5: {max(ug[:5]):.1f} m/s (max 10)")
chk.report("pocket_bounded", pm <= 1.05 * p0 and max(ug) <= 60.0,
           f"p_max del audit {pm/1e3:.1f} kPa (inicial {p0/1e3:.1f}, factor 1.05), "
           f"u_gas_max del audit {max(ug):.1f} m/s (max 60)")
chk.exit()
