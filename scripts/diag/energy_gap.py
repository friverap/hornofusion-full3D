#!/usr/bin/env python3
"""Hueco de energia POR PASO y POR FASE desde audit.csv (WS-K3, C-094/C-095).
Misma identidad que tests/integration/check_audit.py (libro del gas con
E_gas_abs, columnas por fase): gap total = dE_cond + E_gas_abs - ext.
Subidentidades: solido (cierra exacta), gas (E_gas_abs = fuentes del gas +
E_conv_gas - E_iph_gas + E_slag_gas) y liquido = total - solido - gas.
Uso: energy_gap.py DIR [DIR...]   [--desde PASO]"""
import csv, sys
import numpy as np
EXT_POS = ("E_steel_deficit", "E_src_liq_arc", "E_src_liq_rad", "E_src_liq_chem", "E_src_gas_arc",
           "E_src_gas_rad", "E_src_gas_chem", "E_arc_direct_sol", "E_slag_intercept", "E_rad_sol",
           "E_conv_defect", "E_chem_sol", "E_ecs_in", "E_flux_in", "E_charge_in", "E_slag_ox",
           "E_rad_foam", "E_slag_tclip", "E_mix_init")
EXT_NEG = ("E_wall_conv", "E_slag_red", "E_alpha_clip", "E_slag_clip")

def fl(x):
    try: return float(x)
    except ValueError: return 0.0

def gaps(d, desde=0):
    R = [{k.strip(): fl(v) for k, v in r.items()} for r in csv.DictReader(open(f'{d}/audit.csv'))]
    R = [R[0]] + [r for r in R[1:] if r['step'] >= desde]
    A, B = R[:-1], R[1:]
    S = lambda c: np.array([b.get(c, 0.0) for b in B])
    ext = sum(S(k) for k in EXT_POS) - sum(S(k) for k in EXT_NEG) + S('E_conv_gas') - S('E_conv_defect')
    dcond = np.array([(b['E_liq'] + b['E_sol'] + b['E_slag']) - (a['E_liq'] + a['E_sol'] + a['E_slag']) for a, b in zip(A, B)])
    tot = dcond + S('E_gas_abs') - ext
    dsol = np.array([b['E_sol'] - a['E_sol'] for a, b in zip(A, B)])
    sol = dsol - (S('E_arc_direct_sol') + S('E_rad_sol') + S('E_chem_sol') + S('E_iph_sol')
                  - S('E_melt_from_solid') + S('E_resolid'))
    gas = S('E_gas_abs') - (S('E_src_gas_arc') + S('E_src_gas_rad') + S('E_src_gas_chem')
                            + S('E_conv_gas') - S('E_iph_gas') + S('E_slag_gas'))
    return S('step'), tot, sol, gas, tot - sol - gas

if __name__ == '__main__':
    a = sys.argv[1:]; desde = 0
    if '--desde' in a: i = a.index('--desde'); desde = int(a[i + 1]); del a[i:i + 2]
    for d in a:
        st, tot, sol, gas, liq = gaps(d, desde)
        print(f'{d}: {len(st)} pasos | total {tot.sum():.4e} (mediana {np.median(tot):.1f}/paso) | solido {sol.sum():.2e} '
              f'| gas {gas.sum():.3e} ({np.median(gas):.1f}) | liquido {liq.sum():.4e} (mediana {np.median(liq):.1f}/paso)')
