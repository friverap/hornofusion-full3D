#!/usr/bin/env python3
"""Banco del acople P-V en regimen de bano (Plan C, F0; Bug 19).

Sobre bath_test (charco de liquido puro en reposo):
  bath_hydrostatic : en las celdas puras del ultimo snapshot, la presion
                     media por nivel sigue rho_l g (z_top - z) a 1 % de la
                     ferrostatica total del charco
  bath_rest        : max |u_l| en celdas puras <= 1e-2 m/s al final
  bath_alpha_frozen: max |alpha_l(fin) - alpha_l(0)| en celdas puras <= 1e-9
  bath_mass        : |m_liq(fin) - m_liq(0)| / m_liq(0) <= 1e-10 (audit)
  bath_pv_bounded  : max p_max <= 3x ferrostatica y max u_gas_max < 100 m/s
                     en TODO el audit (no solo al final)
Con --fill (bath_fill: charco que crece por fusion): solo bath_pv_bounded
(con u_gas_max < 300, la cota que no debe tocarse), bath_mass_steel
(m_sol + m_liq exacta) y bath_melt_handoff (dm_liq = fundido - resolid - clip).

Uso: check_bath.py RUNDIR --config CFG [--fill] [--xfail ids]
"""
import argparse
import csv
import glob
import os
import sys

import h5py
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg, safe_float

RHO_L, G = 7500.0, 9.81
BETA, T_AMB = 1.2e-4, 300.0   # Boussinesq del liquido (mod_constants): g_eff = g (1 - beta (T_l - T_amb))


def load(fn):
    f = h5py.File(fn, "r")
    g = f["fields"]
    d = {k: g[k][...] for k in ("alpha_liquid", "alpha_gas", "alpha_solid", "pressure",
                                "velocity_r_liquid", "velocity_th_liquid", "velocity_z_liquid")}
    d["z"] = f["mesh/z"][...]
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--config", required=True)
    ap.add_argument("--fill", action="store_true")
    ap.add_argument("--xfail", default="")
    a = ap.parse_args()
    chk = Checker(parse_xfail_arg(a.xfail))
    print(f"[bath] {a.rundir}" + (" (fill)" if a.fill else ""))

    snaps = sorted(glob.glob(os.path.join(a.rundir, "eaf3d_*.h5")))
    first, last = load(snaps[0]), load(snaps[-1])
    with open(os.path.join(a.rundir, "audit.csv")) as f:
        rows = [{k: safe_float(v) for k, v in r.items()} for r in csv.DictReader(f)]

    act = (last["alpha_liquid"] + last["alpha_gas"] + last["alpha_solid"]) > 0.5
    pure0 = act & (first["alpha_liquid"] > 0.999)
    z = last["z"]
    # profundidad del charco: desde el fondo activo hasta la superficie
    # (nivel mas alto con liquido > 0.5 en el ultimo snapshot)
    liq_k = np.nonzero((last["alpha_liquid"] > 0.5).any(axis=(1, 2)))[0]
    k_bot, k_top = liq_k.min(), liq_k.max()
    H = z[k_top] - z[k_bot] + 0.5 * (z[1] - z[0])
    # el momento del liquido lleva Boussinesq: la ferrostatica de un charco
    # caliente es rho g (1 - beta (T_l - T_amb)) h, no rho g h
    with h5py.File(snaps[-1], "r") as f:
        Tl_all = f["fields/T_liquid"][...]
    T_l = float(np.median(Tl_all[pure0])) if pure0.any() else T_AMB
    g_eff = G * (1.0 - BETA * (T_l - T_AMB))
    p_ferro = RHO_L * g_eff * H

    if not a.fill:
        # --- ferrostatica por niveles (celdas puras) ---
        p = last["pressure"]
        lev = [k for k in range(p.shape[0]) if pure0[k].any()]
        pm = {k: float(p[k][pure0[k]].mean()) for k in lev}
        kt = max(lev)
        err = max(abs((pm[k] - pm[kt]) - RHO_L * g_eff * (z[kt] - z[k])) for k in lev) / p_ferro
        chk.report("bath_hydrostatic", err <= 1.0e-2,
                   f"err {err:.3e} de rho g H = {p_ferro:.3e} Pa "
                   f"(p fondo-tope medida {pm[min(lev)] - pm[kt]:.3e}, "
                   f"esperada {RHO_L * g_eff * (z[kt] - z[min(lev)]):.3e}, g_eff/g {g_eff / G:.3f})")
        # --- reposo ---
        u = np.sqrt(last["velocity_r_liquid"]**2 + last["velocity_th_liquid"]**2
                    + last["velocity_z_liquid"]**2)
        umax = float(u[pure0].max())
        chk.report("bath_rest", umax <= 1.0e-2, f"max |u_l| en celdas puras = {umax:.3e} m/s")
        # --- alpha congelada ---
        da = float(abs(last["alpha_liquid"] - first["alpha_liquid"])[pure0].max())
        chk.report("bath_alpha_frozen", da <= 1.0e-9, f"max |d alpha_l| en celdas puras = {da:.3e}")
        # --- masa ---
        m0, m1 = rows[0]["m_liq"], rows[-1]["m_liq"]
        chk.report("bath_mass", abs(m1 - m0) / m0 <= 1.0e-10,
                   f"m_liq {m0:.3f} -> {m1:.3f} kg (err {abs(m1 - m0) / m0:.3e})")
        pmax = max(r["p_max"] for r in rows)
        ugmax = max(r["u_gas_max"] for r in rows)
        chk.report("bath_pv_bounded", pmax <= 3.0 * p_ferro and ugmax < 100.0,
                   f"p_max {pmax:.3e} Pa (3x ferro = {3 * p_ferro:.3e}), u_gas_max {ugmax:.1f} m/s")
    else:
        pmax = max(r["p_max"] for r in rows)
        ugmax = max(r["u_gas_max"] for r in rows)
        chk.report("bath_pv_bounded", pmax <= 3.0 * p_ferro and ugmax < 300.0,
                   f"p_max {pmax:.3e} Pa (3x ferro = {3 * p_ferro:.3e}), u_gas_max {ugmax:.1f} m/s")
        s0 = rows[0]["m_sol"] + rows[0]["m_liq"]
        s1 = rows[-1]["m_sol"] + rows[-1]["m_liq"]
        chk.report("bath_mass_steel", abs(s1 - s0) / s0 <= 1.0e-9,
                   f"acero {s0:.2f} -> {s1:.2f} kg (err {abs(s1 - s0) / s0:.3e})")
        melt = sum(r["m_melted"] for r in rows[1:])
        res = sum(r["m_resolid"] for r in rows[1:])
        clip = sum(r["m_alpha_clip"] for r in rows[1:])
        dm = rows[-1]["m_liq"] - rows[0]["m_liq"]
        exp = melt - res - clip
        err = abs(dm - exp) / max(abs(melt), 1.0)
        chk.report("bath_melt_handoff", err <= 1.0e-8,  # redondeo de la reduccion MPI (n4: 1.0e-9)
                   f"dm_liq {dm:.3f} vs fundido-resolid-clip {exp:.3f} kg (err {err:.3e})")
    chk.exit()


if __name__ == "__main__":
    main()
