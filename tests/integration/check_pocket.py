#!/usr/bin/env python3
"""check_pocket.py RUNDIR [--xfail ids] [--prefix P] (auditorias 6-8, M4-12)

Bolsa de gas bajo una capa saturada del lecho (pocket_rise y su variante a
dt = 10 ms, pocket_rise_dt10): el gas debe subir a contracorriente sin
quedar retenido, sin sobrepresion en la bolsa y sin venteo fantasma.
  pocket_onset    alpha_g de la capa saturada (8) >= 0.05 en t = 0.15 s
                  (medido 0.079 con 5 ms, 0.083 con 10 ms)
  pocket_rise     alpha_g de la capa 8 sube >= 0.2 al final y la bolsa
                  (capa 7) pierde gas (medido +0.260 / -0.202; con la
                  movilidad al dt de la corrida y 10 ms, +0.000: M8-2)
  pocket_excess   exceso p - p_hidrostatica(estratificacion vigente) en las
                  capas de la BOLSA (6-7) <= 2 kPa en todo snapshot
                  (auditoria 9, M9-1: el maximo de todo el dominio caia en el
                  freeboard y no veia la bolsa). Sana 0.00; tapada +11.8 kPa
  pocket_retain   la bolsa ni RETIENE presion ni SUCCIONA: para t >= 0.10 s,
                  |p de la bolsa - p media de la capa 9| <= 1 kPa en toda
                  celda de las capas 6-7 (auditoria 9, M9-1: el exceso sobre
                  la hidrostatica tiene 13-20 kPa de holgura en cuanto la capa
                  saturada drena y no veia una retencion parcial). La capa 9
                  es lecho suelto (alpha_s 0.215) con el gas conectado al
                  freeboard. Sana: -6..+12 Pa; tapada +31.8 kPa. Presupone el
                  arrastre ACTUAL del gas a contracorriente por la capa
                  saturada (la medida es 4-12 Pa): un cierre de permeabilidad
                  relativa mas realista podria dar ~1 kPa fisico y haria
                  fallar el banco en voz alta (falsa alarma, no falso pase)
  pocket_rest     exceso en el RESTO del dominio <= 2 kPa (medido 0.20 /
                  0.29; tapada 2.25)
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
# (auditoria 9, B9-11) el reinicio toma el dt del SNAPSHOT: se comprueba el
# dt real de la corrida (columna dt del audit)
ap.add_argument("--dt", type=float, default=None)   # default: el del config.dat de la corrida
# (auditoria 9, M9-2) cota de REGRESION del cierre de masa del gas para la
# variante con el lazo externo truncado (pocket_rise_o5): el 20 % es xfail
# con causa y esta cota atrapa un empeoramiento
ap.add_argument("--vent-bound", type=float, default=None)
# inicio de la ventana de pocket_retain (en la variante truncada a 0.10 s aun
# se mide el RETRASO del drenaje: 0.61 kPa, que cae a la mitad cada 10 ms)
ap.add_argument("--retain-from", type=float, default=0.10)
a = ap.parse_args()
chk = Checker(parse_xfail_arg(a.xfail))
P = a.prefix
cfgd = {}
cfgp = os.path.join(a.rundir, "config.dat")
if os.path.exists(cfgp):
    for line in open(cfgp):
        line = line.split("#")[0]
        if "=" in line:
            kk, vv = line.split("=", 1); cfgd[kk.strip()] = vv.strip()
if a.dt is None and "dt" in cfgd:
    a.dt = float(cfgd["dt"])
rows = []; pk_max = -1e30; pk_where = None; rest_max = -1e30; ret_max = -1e30; ret_min = 1e30; ret_where = None
for fn in sorted(glob.glob(os.path.join(a.rundir, "eaf3d_*.h5"))):
    with h5py.File(fn) as f:
        F = f["fields"]; ct = f["mesh/cell_type"][()]; z = f["mesh/z"][()]
        ag = F["alpha_gas"][()]; al = F["alpha_liquid"][()]
        Tl = F["T_liquid"][()]; Tg = F["T_gas"][()]; p = F["pressure"][()]
        t = float(np.ravel(f["metadata"].attrs.get("time", 0.0))[0])
        ex = p - hydrostatic(ct, z, al, ag, Tl, gas_eos(Tg, p))
        act = ct != 0
        pk = np.zeros_like(act); pk[5:7] = True      # capas 6-7: la bolsa
        if ex[act & pk].max() > pk_max:
            pk_max = ex[act & pk].max(); pk_where = t
        rest_max = max(rest_max, ex[act & ~pk].max())
        if t >= a.retain_from - 1e-9:
            p9 = p[8][act[8]].mean()
            ret = p[5:7][act[5:7]].max() - p9
            ret_min = min(ret_min, p[5:7][act[5:7]].min() - p9)
            if ret > ret_max:
                ret_max = ret; ret_where = t
        rows.append((t, [float(ag[k][ct[k] != 0].mean()) for k in (6, 7)]))
print(f"[{P}] {a.rundir} ({len(rows)} snapshots)")
t015 = min(rows, key=lambda r: abs(r[0] - 0.15))
chk.report(f"{P}_onset", t015[1][1] >= 0.05,
           f"alpha_g capa 8 en t = {t015[0]:.3f} s: {t015[1][1]:.3f} (min 0.05)")
rise = rows[-1][1][1] - rows[0][1][1]; drop = rows[0][1][0] - rows[-1][1][0]
chk.report(f"{P}_rise", rise >= 0.2 and drop > 0.0,
           f"capa 8: +{rise:.3f} de gas (min 0.2); bolsa (capa 7): -{drop:.3f}")
chk.report(f"{P}_excess", pk_max <= 2.0e3,
           f"exceso sobre la hidrostatica en la bolsa (capas 6-7): max {pk_max/1e3:.2f} kPa "
           f"en t = {pk_where:.3f} s (max 2 kPa)")
if ret_where is None:
    chk.report(f"{P}_retain", False, f"sin snapshots con t >= {a.retain_from:g} s")
else:
    chk.report(f"{P}_retain", ret_max <= 1.0e3 and ret_min >= -1.0e3,
               f"bolsa frente a la capa 9 (t >= {a.retain_from:g} s): max {ret_max/1e3:+.3f} kPa en t = {ret_where:.3f} s, "
               f"min {ret_min/1e3:+.3f} kPa (cota +-1 kPa)")
if "t_final" in cfgd:
    tf = float(cfgd["t_final"])
    chk.report(f"{P}_complete", abs(rows[-1][0] - tf) <= 1e-6 * max(tf, 1.0),
               f"ultimo snapshot en t = {rows[-1][0]:.4f} s (t_final {tf:g})")
chk.report(f"{P}_rest", rest_max <= 2.0e3,
           f"exceso sobre la hidrostatica fuera de la bolsa: max {rest_max/1e3:.2f} kPa (max 2 kPa)")
au = list(csv.DictReader(open(os.path.join(a.rundir, "audit.csv"))))
vent = sum(float(r["m_gas_out"]) for r in au[1:])
dm = float(au[-1]["m_gas"]) - float(au[0]["m_gas"])
ug = max(float(r["u_gas_max"]) for r in au[1:])
if a.dt is not None:
    dts = [float(r["dt"]) for r in au[1:]]
    chk.report(f"{P}_dt", all(abs(x - a.dt) <= 1e-9 * a.dt for x in dts),
               f"dt de la corrida {min(dts):.4g}..{max(dts):.4g} s (esperado {a.dt:g})")
chk.report(f"{P}_vent", abs(dm + vent) <= 0.2 * max(vent, abs(dm)),
           f"venteo {vent:.3f} kg, dm_gas {dm:.3f} kg: gas creado por la EOS {dm + vent:.3f} kg "
           f"({abs(dm + vent) / max(vent, abs(dm), 1e-30):.1%}, max 20 %)")
if a.vent_bound is not None:
    chk.report(f"{P}_vent_bound", abs(dm + vent) <= a.vent_bound * max(vent, abs(dm)),
               f"gas creado por la EOS {abs(dm + vent) / max(vent, abs(dm), 1e-30):.1%} "
               f"(cota de regresion {a.vent_bound:.0%})")
chk.report(f"{P}_gas", ug <= 75.0, f"u_gas_max del audit {ug:.1f} m/s (max 75)")
chk.exit()
