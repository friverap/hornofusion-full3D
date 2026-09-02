#!/usr/bin/env python3
"""Balances globales desde audit.csv (generado por mod_audit.f90, C0.2).

Chequeos (ids para xfail, prefijo 'audit:'):
  energy_balance : |dE_total - E_inyectada| / escala <= tol (default 1 %)
                   dE_total = (E_liq+E_gas+E_sol+E_slag) final - inicial
                   E_iny    = sum(E_src_liq_* + E_src_gas_* + E_arc_direct_sol)
                   (transferencias internas — fusión, interfase, escoria —
                   cancelan en el total SI la contabilidad es conservativa)
  arc_budget     : E_arc_recibida / sum(P_arc*dt) = 1 ± tol (default 1e-3)
                   Objetivo post-C1.6/C1.7; hoy la sobre-inyección del MC y
                   el doble conteo por fase lo desvían.
  mass_liq       : |dm_liq - (m_melted - m_resolid - m_alpha_clip)| <= 0.5 %
                   (se omite con PASS informativo si no hubo fusión)

Uso: check_audit.py RUNDIR [--xfail a,b] [--etol 0.01] [--arctol 1e-3]
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eafutil import Checker, parse_xfail_arg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--xfail", default="")
    ap.add_argument("--etol", type=float, default=0.01)
    ap.add_argument("--arctol", type=float, default=1e-3)
    ap.add_argument("--mtol", type=float, default=0.005)
    args = ap.parse_args()

    path = os.path.join(args.rundir, "audit.csv")
    if not os.path.exists(path):
        sys.exit(f"ERROR: no existe {path}")

    with open(path) as f:
        rows = [{k: float(v) for k, v in r.items()}
                for r in csv.DictReader(f)]
    if len(rows) < 2:
        sys.exit("ERROR: audit.csv sin pasos (solo estado inicial)")

    first, last = rows[0], rows[-1]
    steps = rows[1:]
    chk = Checker(parse_xfail_arg(args.xfail))
    print(f"[audit] {args.rundir} ({len(steps)} pasos)")

    def total_E(r):
        return r["E_liq"] + r["E_gas"] + r["E_sol"] + r["E_slag"]

    # -- energy_balance ------------------------------------------------------
    dE = total_E(last) - total_E(first)
    E_in = sum(r["E_src_liq_arc"] + r["E_src_liq_rad"] + r["E_src_liq_chem"] +
               r["E_src_gas_arc"] + r["E_src_gas_rad"] + r["E_src_gas_chem"] +
               r["E_arc_direct_sol"] + r.get("E_slag_intercept", 0.0)
               for r in steps)
    scale = max(abs(dE), abs(E_in), 1.0)
    err = abs(dE - E_in) / scale
    chk.report("energy_balance", err <= args.etol,
               f"dE={dE:.4e} J, E_iny={E_in:.4e} J, err rel={err:.3e} "
               f"(tol {args.etol})")

    # -- arc_budget ----------------------------------------------------------
    E_arc_in = sum(r["E_src_liq_arc"] + r["E_src_gas_arc"] +
                   r["E_arc_direct_sol"] + r.get("E_slag_intercept", 0.0)
                   for r in steps)
    E_arc_avail = sum(r["P_arc"] * r["dt"] for r in steps)
    if E_arc_avail > 1.0:
        ratio = E_arc_in / E_arc_avail
        disc = sum(r["E_arc_discarded"] for r in steps)
        chk.report("arc_budget", abs(ratio - 1.0) <= args.arctol,
                   f"recibida/P_arc·dt = {ratio:.4f} (descartada "
                   f"{disc:.3e} J, tol {args.arctol})")
    else:
        print("  PASS  arc_budget  (sin potencia de arco: no aplica)")

    # -- mass_liq ------------------------------------------------------------
    dm_l = last["m_liq"] - first["m_liq"]
    m_melt = sum(r["m_melted"] for r in steps)
    m_res = sum(r["m_resolid"] for r in steps)
    m_clip = sum(r["m_alpha_clip"] for r in steps)
    expected = m_melt - m_res - m_clip
    denom = max(abs(m_melt) + abs(m_res) + abs(m_clip), abs(dm_l))
    if denom < 1.0:
        print("  PASS  mass_liq  (sin fusión: no aplica)")
    else:
        err = abs(dm_l - expected) / denom
        chk.report("mass_liq", err <= args.mtol,
                   f"dm_liq={dm_l:.4e} vs fundido-resolid-clip="
                   f"{expected:.4e} kg (fundido={m_melt:.3e}, "
                   f"resolid={m_res:.3e}, clip={m_clip:.3e}), "
                   f"err rel={err:.3e}")

    chk.exit()


if __name__ == "__main__":
    main()
