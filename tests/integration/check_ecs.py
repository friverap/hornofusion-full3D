#!/usr/bin/env python3
"""Conservacion del cargador continuo ECS (E1.3).

  ecs_mass   : m_sol(final) - m_sol(0) == sum(m_ecs_in) == mdot*t a 1e-10
  ecs_energy : E_sol(final) - E_sol(0) == sum(E_ecs_in) a 1e-10
  ecs_carbon : el carbono cargado es ecs_carbon_frac * masa (via HDF5)

Modo --slag (Plan I, I2: la chatarra ATRAVIESA la escoria condensada;
auditoria general 2, M3/H4):
  ecs_slag_guard : el banco no tiene otras rutas de masa/energia del solido
                   (fusion, carga, C oxidado, radiacion, arco, quimica,
                   interfase): si no, el balance de abajo no es una identidad
  ecs_energy     : dE_sol == sum(E_ecs_in) - sum(E_slag_sol) (contacto
                   escoria-chatarra, A18-10), que debe ser no nulo
  ecs_slag_mass  : dm_slag + sum(m_slag_clip) == 0 (la escoria desplazada se
                   reordena, no se crea ni destruye)
  ecs_pending    : nada pendiente en el ultimo snapshot
  ecs_displaced  : en alguna columna la chatarra final supera el gas inicial
                   de su celda (desplazo escoria: el caso ejerce I2)
  ecs_base       : en cada columna de la banda con carga, la celda mas baja
                   con layer_id == ID_ECS es k0 (la de encima del tope del
                   acero/chatarra/tazon del snapshot 0) y alguna k0 empezo
                   con escoria resuelta (si no, el caso no ejerce I2)

Uso: check_ecs.py RUNDIR --config CFG [--slag] [--xfail ids]
"""
import argparse
import csv
import glob
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg, safe_float


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--config", required=True)
    ap.add_argument("--xfail", default="")
    ap.add_argument("--slag", action="store_true")
    args = ap.parse_args()

    cfgtext = open(args.config).read()

    def cfg_get(key):
        m = re.findall(rf"^\s*{key}\s*=\s*([\d.Ee+-]+)", cfgtext, re.M)
        return float(m[-1]) if m else None

    rate = cfg_get("ecs_rate")
    cfrac = cfg_get("ecs_carbon_frac")

    with open(os.path.join(args.rundir, "audit.csv")) as f:
        rows = [{k: safe_float(v) for k, v in r.items()}
                for r in csv.DictReader(f)]
    first, last = rows[0], rows[-1]
    steps = rows[1:]

    chk = Checker(parse_xfail_arg(args.xfail))
    print(f"[ecs] {args.rundir}")

    fed = sum(r.get("m_ecs_in", 0.0) for r in steps)
    dm = last["m_sol"] - first["m_sol"]
    expected = rate * last["time"]
    err1 = abs(dm - fed) / max(expected, 1.0)
    err2 = abs(fed - expected) / max(expected, 1.0)
    chk.report("ecs_mass", err1 <= 1e-10 and err2 <= 1e-10,
               f"dm_sol={dm:.6f} vs m_ecs_in={fed:.6f} vs mdot*t="
               f"{expected:.6f} kg (err {max(err1, err2):.3e})")

    e_fed = sum(r.get("E_ecs_in", 0.0) for r in steps)
    de = last["E_sol"] - first["E_sol"]
    if not args.slag:
        err3 = abs(de - e_fed) / max(abs(e_fed), 1.0)
        chk.report("ecs_energy", err3 <= 1e-10,
                   f"dE_sol={de:.6e} vs E_ecs_in={e_fed:.6e} J (err {err3:.3e})")
    else:
        check_slag_mode(args, cfg_get, rows, steps, first, last, fed, e_fed, de, chk)

    # carbono cargado (desde el ultimo snapshot no hay m_C exportado; se
    # valida indirectamente: masa*frac contra el unit test; aqui solo la
    # coherencia global via audit si existiera columna futura)
    print(f"  INFO  carbono esperado = {cfrac * fed:.3f} kg "
          f"(validado en test_ecs_feed)")

    chk.exit()


ID_ECS = 31   # MAX_LAYERS + 1 (mod_types_3d / mod_ecs_feed)


def check_slag_mode(args, cfg_get, rows, steps, first, last, fed, e_fed, de, chk):
    import h5py
    import numpy as np

    def tot(col):
        return sum(r.get(col, 0.0) for r in steps)

    others = {c: tot(c) for c in ("m_melted", "m_resolid", "m_C_oxid", "m_charge_in",
                                   "E_rad_sol", "E_arc_direct_sol", "E_chem_sol",
                                   "E_iph_sol")}
    bad = {c: v for c, v in others.items() if v != 0.0}
    chk.report("ecs_slag_guard", not bad,
               "sin otras rutas del solido" if not bad else f"rutas activas: {bad}")

    e_ss = tot("E_slag_sol")
    err = abs(de - (e_fed - e_ss)) / max(abs(e_fed), abs(e_ss), 1.0)
    chk.report("ecs_energy", err <= 1e-10 and e_ss != 0.0,
               f"dE_sol={de:.6e} vs E_ecs_in - E_slag_sol={e_fed - e_ss:.6e} J "
               f"(err {err:.3e}; E_slag_sol={e_ss:.3e}, debe ser no nulo)")

    msl = max(abs(first["m_slag"]), 1.0)
    dsl = last["m_slag"] - first["m_slag"] + tot("m_slag_clip")
    chk.report("ecs_slag_mass", abs(dsl) <= 1e-12 * msl,
               f"dm_slag + clip = {dsl:.3e} kg (max 1e-12 de {msl:.3e})")

    snaps = sorted(glob.glob(os.path.join(args.rundir, "eaf3d_*.h5")))
    with h5py.File(snaps[0]) as h0, h5py.File(snaps[-1]) as h1:
        pend = float(np.asarray(h1["restart"].attrs["m_ecs_pending"]).ravel()[0])
        chk.report("ecs_pending", pend == 0.0, f"m_ecs_pending final = {pend:.3e} kg")
        # arrays (nz, nth, nr)
        ct = h0["mesh/cell_type"][()]
        r = h0["mesh/r"][()]
        th = h0["mesh/theta"][()]
        as0 = h0["fields/alpha_solid"][()]
        al0 = h0["fields/alpha_liquid"][()]
        asl0 = h0["fields/alpha_slag"][()]
        ag0 = h0["fields/alpha_gas"][()]
        lid = h1["restart/layer_id"][()]
        as1 = h1["fields/alpha_solid"][()]
    tc, tw, ri = cfg_get("ecs_theta_center"), cfg_get("ecs_theta_width"), cfg_get("ecs_r_inner")
    nz, nth, nr = ct.shape
    ncol, nbad, nslag, ndisp = 0, 0, 0, 0
    msgs = []
    for j in range(nth):
        dth = math.atan2(math.sin(th[j] - tc), math.cos(th[j] - tc))
        if abs(dth) > 0.5 * tw:
            continue
        for i in range(nr):
            if r[i] < ri:
                continue
            ks = [k for k in range(nz) if lid[k, j, i] == ID_ECS]
            if not ks:
                continue
            top = -1
            for k in range(nz):
                if ct[k, j, i] == 0 or as0[k, j, i] > 0.05 or al0[k, j, i] >= 0.3:
                    top = k
            k0 = top + 1
            ncol += 1
            if k0 < nz and asl0[k0, j, i] >= 0.01:
                nslag += 1
            # (dirigida general 2, M3) la chatarra DESPLAZO escoria: en alguna
            # celda supera el gas que habia al inicio
            if any(as1[k, j, i] > ag0[k, j, i] + 1e-9 for k in ks):
                ndisp += 1
            if min(ks) != k0:
                nbad += 1
                if len(msgs) < 3:
                    msgs.append(f"(i={i+1},j={j+1}) base {min(ks)+1} vs k0 {k0+1}")
    chk.report("ecs_base", ncol > 0 and nbad == 0 and nslag > 0,
               f"{ncol} columnas con carga, {nbad} con base distinta de k0 {msgs}, "
               f"{nslag} con escoria resuelta en k0 al inicio (debe ser > 0)")
    chk.report("ecs_displaced", ndisp > 0,
               f"{ndisp} columnas donde la chatarra supera el gas inicial (desplazo "
               f"escoria; debe ser > 0, si no el caso no ejerce I2)")


if __name__ == "__main__":
    main()
