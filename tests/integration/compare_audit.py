#!/usr/bin/env python3
"""compare_audit.py DIR_A DIR_B --from-step N [--rtol 1e-12]

Compara audit.csv de un REINICIO (DIR_A) con el de la corrida continua
(DIR_B) en las filas con step > N (la fila N del reinicio es su estado
inicial, sin fuentes). Todas las columnas son por intervalo o inventarios
instantaneos, asi que deben coincidir bit a bit con el mismo numero de
ranks (auditoria 4, B4-19: el gate del reinicio solo miraba el snapshot).
Error por columna relativo al mayor |valor| de esa columna en DIR_B; con
--decomp, m_gas_ccdrop (redondeo puro) se mide contra 1e-15 del inventario de
gas (auditoria 7, M7-2). (auditoria 5, B5-21) Filas
duplicadas y columnas de un solo lado son FAIL; en la fila N se comparan los
inventarios instantaneos (el estado de arranque del reinicio).
"""
import argparse
import csv
import math
import os
import sys


# inventarios instantaneos: en la fila N (estado inicial del reinicio) deben
# coincidir con la continua aunque las columnas de fuente sean 0 (B5-21)
INVENTORY = ("time", "m_liq", "m_gas", "m_sol", "m_slag",
             "E_liq", "E_gas", "E_sol", "E_slag")


def load(path):
    with open(path) as f:
        rows = list(csv.DictReader(f))
    out = {}
    for r in rows:
        st = int(float(r["step"]))
        if st in out:
            # (B5-21) una fila repetida (freno de NaN, B5-29) no es ruido
            print(f"FAIL: paso {st} duplicado en {path}")
            sys.exit(1)
        out[st] = r
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir_a")
    ap.add_argument("dir_b")
    ap.add_argument("--from-step", type=int, required=True)
    ap.add_argument("--rtol", type=float, default=1e-12)
    ap.add_argument("--decomp", action="store_true",
                    help="reinicio con otro numero de ranks (piso de redondeo en m_gas_ccdrop)")
    args = ap.parse_args()
    pa, pb = (os.path.join(d, "audit.csv") for d in (args.dir_a, args.dir_b))
    for p in (pa, pb):
        if not os.path.exists(p):
            print(f"FAIL: no existe {p}")
            sys.exit(1)
    A, B = load(pa), load(pb)
    steps = sorted(s for s in A if s > args.from_step)
    if not steps or any(s not in B for s in steps):
        print(f"FAIL: pasos del reinicio {steps[:3]}... no estan todos en la continua")
        sys.exit(1)
    # (bajo B6-10) y al reves: un audit de reinicio TRUNCADO (le faltan pasos
    # finales de la continua) o sin la fila N del arranque no es un reinicio
    # bit a bit aunque lo que tenga coincida
    missing = sorted(s for s in B if s > args.from_step and s not in A)
    if missing:
        print(f"FAIL: al audit del reinicio le faltan pasos de la continua: {missing[:5]}")
        sys.exit(1)
    if args.from_step not in A or args.from_step not in B:
        print(f"FAIL: falta la fila del paso de arranque {args.from_step} (fila 0 del reinicio)")
        sys.exit(1)
    # (B5-21) las dos cabeceras deben ser la MISMA: una columna de un solo
    # lado es un binario distinto o un audit truncado, no algo que ignorar
    ca, cb = list(A[steps[0]].keys()), list(B[steps[0]].keys())
    if ca != cb:
        print(f"FAIL: columnas distintas: solo en A {sorted(set(ca) - set(cb))}, "
              f"solo en B {sorted(set(cb) - set(ca))}")
        sys.exit(1)
    cols = ca
    # (auditoria 7, M7-2) tolerancia ABSOLUTA solo para las columnas de
    # REDONDEO PURO (m_gas_ccdrop vale ~1e-18 kg en los bancos sin escoria;
    # con el transitorio de arranque del gas frio sobre un talon caliente es
    # ~1 kg y NO es redondeo: su techo lo vigila check_audit ccdrop_bounded) y solo con --decomp (reinicio con otro numero de
    # ranks): 1e-15 del inventario de gas. Con el mismo numero de ranks el
    # reinicio es BIT A BIT (el piso de la auditoria 6 se aplicaba a toda
    # columna m_*/E_* y aflojaba m_spill, m_vf_*, m_gas_volfix a 1e-3)
    # (Plan H, P8) el clip de escoria condensada es del mismo tipo (~1e-33 kg
    # con signo segun la descomposicion): piso con el inventario de escoria
    ROUNDOFF_COLS = {"m_gas_ccdrop": "m_gas", "m_slag_clip": "m_slag", "E_slag_clip": "E_slag"}
    def inv_floor(c):
        if not (args.decomp and c in ROUNDOFF_COLS):
            return 0.0
        inv = ROUNDOFF_COLS[c]
        v = [abs(float(B[s][inv])) for s in steps if inv in B[s]]
        return 1e-15 * max(v) if v else 0.0
    worst, worst_id = 0.0, "-"
    # fila N: inventarios del estado de arranque frente a la continua
    cmp_rows = [(args.from_step, INVENTORY)] if args.from_step in A and args.from_step in B else []
    cmp_rows += [(s, cols) for s in steps]
    for c in cols:
        scale = max((abs(float(B[s][c])) for s in steps), default=0.0)
        # tolerancia absoluta equivalente: 1e-15 del inventario de la unidad
        # (redondeo); se expresa como escala para que err <= rtol la cubra
        scale = max(scale, inv_floor(c) / args.rtol)
        for s, cset in cmp_rows:
            if c not in cset:
                continue
            a, b = float(A[s][c]), float(B[s][c])
            if not (math.isfinite(a) and math.isfinite(b)):
                err = float("inf")
            elif scale > 0.0:
                err = abs(a - b) / scale
            else:
                # columna nula en la continua: cualquier valor distinto de
                # 0 en el reinicio es un fallo (antes escala 1e-300 -> inf,
                # o 0/0 silencioso)
                err = 0.0 if a == b else float("inf")
            if err > worst:
                worst, worst_id = err, f"{c}@{s}"
    ok = worst <= args.rtol
    print(f"[audit-restart] {os.path.basename(args.dir_a)} vs "
          f"{os.path.basename(args.dir_b)} ({len(steps)} filas, {len(cols)} columnas)")
    print(f"  {'PASS' if ok else 'FAIL'}  peor columna: {worst_id} ({worst:.3e}, tol {args.rtol})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
