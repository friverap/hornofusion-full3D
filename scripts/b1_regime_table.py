#!/usr/bin/env python3
"""Tabla de REGIMEN ACOTADO de la ventana 300-345 s de B1 (paper, Sec.
Benchmarks): por trayectoria, % de pasos con |p| > 20 kPa, |u_g| > 200 m/s,
|u_l| > 10 m/s (incluye liquido disperso) y con alguna centinela de presion o
gas activa (P_HYDRO_CAP, U_GAS_MAX), en dos ventanas: 310-320 s (inicio del colapso) y 320-345 s.
Genera paper/tables/b1_regime.tex. Uso: python3 scripts/b1_regime_table.py
"""
import csv
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAND = os.path.join(REPO, "scratchpad", "cand")
OUT = os.path.join(REPO, "paper", "tables", "b1_regime.tex")

P_CAP, UG_CAP, UL_CAP = 2.0e6, 300.0, 20.0
WINDOWS = [(310.0, 320.0), (320.0, 345.0)]

# (etiqueta LaTeX, ruta del audit, grupo)
RUNS = [
    (r"v35 heat, $\dt=2$~ms (baseline)",
     os.path.join(REPO, "campaigns", "b1_v35_f229_5040s", "audit.csv")),
    (r"+ absorption split, vent criterion",
     os.path.join(CAND, "judge_largo_F231", "audit.csv")),
    (r"+ water-packing safeguard",
     os.path.join(CAND, "judge_largo_F232", "audit.csv")),
    (r"$\dt=1$~ms (a)", os.path.join(CAND, "dt_1ms", "audit.csv")),
    (r"$\dt=1$~ms (b)", os.path.join(CAND, "dt_adapt", "audit.csv")),
    (r"$\dt=0.5$~ms", os.path.join(CAND, "dt_05ms", "audit.csv")),
    (r"pore-saturation regime (a)", os.path.join(CAND, "sat_n5", "audit.csv")),
    (r"pore-saturation regime", os.path.join(CAND, "sat_n6", "audit.csv")),
    (r"pore-saturation regime (c)", os.path.join(CAND, "sat_n7", "audit.csv")),
    (r"immobile flooded scrap (a)", os.path.join(CAND, "flood_n5", "audit.csv")),
    (r"immobile flooded scrap (b)", os.path.join(CAND, "flood_n6", "audit.csv")),
    (r"immobile flooded scrap (c)", os.path.join(CAND, "flood_n7", "audit.csv")),
    (r"sealed-wall + free-surface grad. + compliance (a)", os.path.join(CAND, "judge_d2_n12", "audit.csv")),
    (r"sealed-wall + free-surface grad. + compliance (b)", os.path.join(CAND, "judge_d2_n14", "audit.csv")),
    (r"sealed-wall + free-surface grad. + compliance (c)", os.path.join(CAND, "judge_d2_n15", "audit.csv")),
    (r"+ free-surface face, consistent corrector, kinematic rule (a)", os.path.join(CAND, "judge_d26_n12", "audit.csv")),
    (r"transmissive saturated pore (Plan E E1) (a)", os.path.join(CAND, "judge_e1_n12", "audit.csv")),
]


def window_stats(rows, t0, t1):
    s = [r for r in rows if t0 <= float(r["time"]) < t1]
    # ventana incompleta (corrida detenida antes de t1): se marca
    if not s or float(rows[-1]["time"]) < t1 - 0.5:
        return None
    n = len(s)

    def pct(k, v):
        return 100.0 * sum(float(r[k]) > v for r in s) / n

    # Centinelas de PRESION y GAS. La columna u_liq_max del audit incluye el
    # liquido DISPERSO (alpha_l >= 1e-2), que lleva la velocidad terminal de
    # gota (hasta U_SETTLE_MAX ~ 50 m/s en gas caliente) y al que la cota
    # U_LIQ_MAX no se aplica (solo capa liquido continuo): u_liq_max >= 20 NO
    # es una centinela activa (corregido 10-oct-2026).
    sent = 100.0 * sum(float(r["p_max"]) >= P_CAP or
                       float(r["u_gas_max"]) >= UG_CAP for r in s) / n
    return (pct("p_max", 2.0e4), pct("u_gas_max", 200.0),
            pct("u_liq_max", 10.0), sent)


def main():
    lines = ["% Generado por scripts/b1_regime_table.py -- no editar",
             r"\begin{tabular}{lrrrrrrrr}", r"\hline",
             r" & \multicolumn{4}{c}{310--320 s} & \multicolumn{4}{c}{320--345 s} \\",
             r"Variant & $p$ & $u_g$ & $u_l$ & sent. & $p$ & $u_g$ & $u_l$ & sent. \\",
             r"\hline"]
    for label, path in RUNS:
        if not os.path.exists(path):
            print(f"[b1_regime] falta {path}", file=sys.stderr)
            continue
        rows = list(csv.DictReader(open(path), skipinitialspace=True))
        cells = []
        for t0, t1 in WINDOWS:
            st = window_stats(rows, t0, t1)
            cells += ["--"] * 4 if st is None else [f"{x:.0f}" for x in st]
        if all(c == "--" for c in cells):
            continue   # detenida antes de completar ventana alguna
        lines.append(label + " & " + " & ".join(cells) + r" \\")
    lines += [r"\hline", r"\end{tabular}"]
    with open(OUT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"[b1_regime] escrito {OUT}")


if __name__ == "__main__":
    main()
