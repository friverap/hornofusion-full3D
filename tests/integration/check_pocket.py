#!/usr/bin/env python3
"""check_pocket.py RUNDIR [--xfail ids] [--prefix P] (auditorias 6-8, M4-12)

Bolsa de gas bajo una capa saturada del lecho (pocket_rise y su variante a
dt = 10 ms, pocket_rise_dt10): el gas debe subir a contracorriente sin
quedar retenido, sin sobrepresion en la bolsa y sin venteo fantasma.
  pocket_onset    alpha_g de la capa saturada (8) >= 0.05 en t = 0.15 s
                  (medido 0.069 con 5 ms)
  pocket_rise     alpha_g de la capa 8 sube >= 0.2 al final y la bolsa
                  (capa 7) pierde gas (medido +0.254 / -0.200; con la
                  movilidad al dt de la corrida y 10 ms, +0.000: M8-2)
  pocket_excess   p - p_hidrostatica(estratificacion vigente) <= 2 kPa en
                  TODO snapshot y celda (M8-3: max|p| siempre es el piso y no
                  veia la bolsa). El exceso NEGATIVO es fisico: la capa
                  saturada drena por Darcy y su peso pasa de la presion al
                  arrastre del lecho (informativo)
  pocket_vent     cierre de masa del gas: |dm_gas + venteo| <= 0.2 x
                  max(venteo, |dm_gas|)
                  (M8-3: con 5 iteraciones externas el desfase alpha-p
                  ventea 0.92 kg con 0.52 kg de perdida real -> la EOS crea
                  0.40 kg y el gas del techo llega a 45 m/s; con 20, 0.9 %;
                  12 % con 10 ms)
  pocket_gas      u_gas_max del audit en toda la corrida <= 75 m/s
                  (U_GAS_MAX/4; venteo de la despresurizacion por los huecos
                  de los electrodos: medido 30.6 con 5 ms y 49.4 con 10 ms;
                  la bolsa tapada de M8-2 da 95 y el desfase de M8-3 con
                  10 ms, 99)
"""
import argparse, csv, glob, os, sys
import numpy as np
import h5py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg
from make_pocket_init import hydrostatic, gas_eos

ap = argparse.ArgumentParser()
ap.add_argument("rundir")
ap.add_argument("--xfail", default="")
ap.add_argument("--prefix", default="pocket")
a = ap.parse_args()
chk = Checker(parse_xfail_arg(a.xfail))
P = a.prefix
rows = []; exc_max = -1e30; exc_min = 1e30; exc_where = None
for fn in sorted(glob.glob(os.path.join(a.rundir, "eaf3d_*.h5"))):
    with h5py.File(fn) as f:
        F = f["fields"]; ct = f["mesh/cell_type"][()]; z = f["mesh/z"][()]
        ag = F["alpha_gas"][()]; al = F["alpha_liquid"][()]
        Tl = F["T_liquid"][()]; Tg = F["T_gas"][()]; p = F["pressure"][()]
        t = float(np.ravel(f["metadata"].attrs.get("time", 0.0))[0])
        ex = (p - hydrostatic(ct, z, al, ag, Tl, gas_eos(Tg, p)))[ct != 0]
        if ex.max() > exc_max:
            exc_max = ex.max(); exc_where = t
        exc_min = min(exc_min, ex.min())
        rows.append((t, [float(ag[k][ct[k] != 0].mean()) for k in (6, 7)]))
print(f"[{P}] {a.rundir} ({len(rows)} snapshots)")
t015 = min(rows, key=lambda r: abs(r[0] - 0.15))
chk.report(f"{P}_onset", t015[1][1] >= 0.05,
           f"alpha_g capa 8 en t = {t015[0]:.3f} s: {t015[1][1]:.3f} (min 0.05)")
rise = rows[-1][1][1] - rows[0][1][1]; drop = rows[0][1][0] - rows[-1][1][0]
chk.report(f"{P}_rise", rise >= 0.2 and drop > 0.0,
           f"capa 8: +{rise:.3f} de gas (min 0.2); bolsa (capa 7): -{drop:.3f}")
chk.report(f"{P}_excess", exc_max <= 2.0e3,
           f"exceso sobre la hidrostatica: max {exc_max/1e3:.2f} kPa en t = {exc_where:.3f} s "
           f"(max 2 kPa); min {exc_min/1e3:.1f} kPa (drenaje, informativo)")
au = list(csv.DictReader(open(os.path.join(a.rundir, "audit.csv"))))
vent = sum(float(r["m_gas_out"]) for r in au[1:])
dm = float(au[-1]["m_gas"]) - float(au[0]["m_gas"])
ug = max(float(r["u_gas_max"]) for r in au[1:])
chk.report(f"{P}_vent", abs(dm + vent) <= 0.2 * max(vent, abs(dm)),
           f"venteo {vent:.3f} kg, dm_gas {dm:.3f} kg: gas creado por la EOS {dm + vent:.3f} kg "
           f"({abs(dm + vent) / max(vent, abs(dm), 1e-30):.1%}, max 20 %)")
chk.report(f"{P}_gas", ug <= 75.0, f"u_gas_max del audit {ug:.1f} m/s (max 75)")
chk.exit()
