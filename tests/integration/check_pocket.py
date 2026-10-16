#!/usr/bin/env python3
"""check_pocket.py RUNDIR [--xfail ids] [--dt DT] (auditorias 6-8, M4-12)

Bolsa de gas bajo una capa saturada del lecho (pocket_rise): el gas debe subir
a contracorriente sin retencion. El estado hidrostatico NO es punto fijo: la
capa saturada drena por Darcy y su peso pasa al arrastre del lecho (la presion
del piso baja ~20 kPa, fisico); la bolsa se despresuriza y ventea por los
huecos de los electrodos. (El pico de u_gas del audit, ~45 m/s, NO es ese
venteo: es un modo par-impar del freeboard justo sobre el lecho, capa 10,
producido por el lazo externo truncado a 5 iteraciones; el caudal real que
sale de la bolsa es ~0.05 m/s superficial. Con 20 iteraciones desaparece.)
La presion de la bolsa se juzga DIRECTAMENTE frente a la capa
de encima conectada al gas (capa 9, lecho suelto alpha_s 0.215): retencion
r(t) = max p(capas 6-7) - p media(capa 9). (auditoria 8, M8-3: max|p| del
audit es siempre el piso y no veia la bolsa.)
  pocket_onset    alpha_g de la capa saturada (8) >= 0.05 en t = 0.15 s
                  (medido 0.069)
  pocket_rise     alpha_g de la capa 8 sube >= 0.2 al final y la bolsa
                  (capa 7) pierde gas (medido +0.254 / -0.200)
  pocket_mono     la bolsa solo se DESPRESURIZA: r(t) nunca sube mas de
                  0.5 kPa entre snapshots (medido: 20.0 -> 0.006 kPa, mayor
                  repunte +0.007). Atrapa un repunte
  pocket_gate     r <= 10 kPa antes de t = 0.09 s (medido 8.2 kPa en 0.07):
                  atrapa una MESETA o un retraso de >= ~25 ms (con release
                  sola pasaba un retraso de 30 ms)
  pocket_release  r(t) baja de 1 kPa y se queda ahi antes de t = 0.13 s
                  (medido 0.10 s): atrapa una despresurizacion retrasada
  pocket_retain   r(t) <= 1 kPa para t >= 0.13 s (medido <= 0.08 kPa) y
                  r(t) >= -1 kPa en TODA la corrida (medido -0.005): ni
                  retencion ni succion
  pocket_bounded  p_max del audit <= 1.05 x la inicial (piso; medido 0.999)
                  y u_gas_max del audit en TODA la corrida <= 60 m/s (medido
                  44.7: cota de REGRESION del artefacto del lazo truncado)
  pocket_complete el ultimo snapshot esta en t_final
  pocket_dt       el dt real de la corrida (columna dt del audit) es el
                  esperado: el reinicio toma el dt del SNAPSHOT
Requiere snapshots frecuentes (output_freq 2 en pocket_rise.dat).
"""
import argparse, csv, glob, os, sys
import numpy as np
import h5py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg

ap = argparse.ArgumentParser()
ap.add_argument("rundir")
ap.add_argument("--xfail", default="")
ap.add_argument("--dt", type=float, default=None)   # default: el del config.dat
a = ap.parse_args()
chk = Checker(parse_xfail_arg(a.xfail))

cfgd = {}
cfgp = os.path.join(a.rundir, "config.dat")
if os.path.exists(cfgp):
    for line in open(cfgp):
        line = line.split("#")[0]
        if "=" in line:
            kk, vv = line.split("=", 1); cfgd[kk.strip()] = vv.strip()
if a.dt is None and "dt" in cfgd:
    a.dt = float(cfgd["dt"])

rows = []
for fn in sorted(glob.glob(os.path.join(a.rundir, "eaf3d_*.h5"))):
    with h5py.File(fn) as f:
        ct = f["mesh/cell_type"][()] != 0
        ag = f["fields/alpha_gas"][()]; p = f["fields/pressure"][()]
        t = float(np.ravel(f["metadata"].attrs.get("time", 0.0))[0])
        r = p[5:7][ct[5:7]].max() - p[8][ct[8]].mean()
        rmin = p[5:7][ct[5:7]].min() - p[8][ct[8]].mean()
        rows.append((t, [float(ag[k][ct[k]].mean()) for k in (6, 7)], r, rmin))
print(f"[pocket] {a.rundir} ({len(rows)} snapshots)")
if len(rows) < 2:
    chk.report("pocket_complete", False, "menos de dos snapshots")
    chk.exit()

t015 = min(rows, key=lambda q: abs(q[0] - 0.15))
chk.report("pocket_onset", t015[1][1] >= 0.05,
           f"alpha_g capa 8 en t = {t015[0]:.3f} s: {t015[1][1]:.3f} (min 0.05)")
rise = rows[-1][1][1] - rows[0][1][1]; drop = rows[0][1][0] - rows[-1][1][0]
chk.report("pocket_rise", rise >= 0.2 and drop > 0.0,
           f"capa 8: +{rise:.3f} de gas (min 0.2); bolsa (capa 7): -{drop:.3f}")

jumps = [(rows[i][0], rows[i][2] - rows[i - 1][2]) for i in range(1, len(rows))]
tj, dj = max(jumps, key=lambda q: q[1])
chk.report("pocket_mono", dj <= 0.5e3,
           f"mayor subida de la retencion entre snapshots: {dj/1e3:+.3f} kPa en t = {tj:.3f} s (max 0.5 kPa)")
t_rel = None
for i in range(len(rows)):
    if all(q[2] <= 1.0e3 for q in rows[i:]):
        t_rel = rows[i][0]; break
chk.report("pocket_release", t_rel is not None and t_rel <= 0.13 + 1e-9,
           f"la retencion queda bajo 1 kPa desde t = {t_rel if t_rel is not None else float('nan'):.3f} s (max 0.13 s)")
early = [q for q in rows if 0.0 < q[0] <= 0.09 + 1e-9]
t_gate = next((q[0] for q in early if q[2] <= 10.0e3), None)
chk.report("pocket_gate", t_gate is not None,
           f"la retencion baja de 10 kPa en t = {t_gate if t_gate is not None else float('nan'):.3f} s (max 0.09 s)")
late = [q for q in rows if q[0] >= 0.13 - 1e-9]
rmax = max(q[2] for q in late) if late else float("nan")
rlow = min(q[3] for q in rows[1:])
chk.report("pocket_retain", bool(late) and rmax <= 1.0e3 and rlow >= -1.0e3,
           f"bolsa frente a la capa 9: max {rmax/1e3:+.3f} kPa para t >= 0.13 s (max 1), "
           f"min {rlow/1e3:+.3f} kPa en toda la corrida (min -1)")

au = list(csv.DictReader(open(os.path.join(a.rundir, "audit.csv"))))
if len(au) < 2:
    chk.report("pocket_bounded", False, "audit.csv sin pasos")
    chk.exit()
p0 = float(au[0]["p_max"])
ug = [float(r["u_gas_max"]) for r in au[1:]]
pm = max(float(r["p_max"]) for r in au[1:])
chk.report("pocket_bounded", pm <= 1.05 * p0 and max(ug) <= 60.0,
           f"p_max del audit {pm/1e3:.1f} kPa (inicial {p0/1e3:.1f}, factor 1.05), "
           f"u_gas_max del audit {max(ug):.1f} m/s en toda la corrida (max 60)")
if "t_final" in cfgd:
    tf = float(cfgd["t_final"])
    chk.report("pocket_complete", abs(rows[-1][0] - tf) <= 1e-6 * max(tf, 1.0),
               f"ultimo snapshot en t = {rows[-1][0]:.4f} s (t_final {tf:g})")
if a.dt is not None:
    dts = [float(r["dt"]) for r in au[1:]]
    chk.report("pocket_dt", all(abs(x - a.dt) <= 1e-9 * a.dt for x in dts),
               f"dt de la corrida {min(dts):.4g}..{max(dts):.4g} s (esperado {a.dt:g})")
chk.exit()
