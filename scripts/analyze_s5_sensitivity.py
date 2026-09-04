#!/usr/bin/env python3
"""Análisis S5: sensibilidad del bore-in (120 s) a las perillas del modelo.

Lee campaigns/s5/ (y campaigns/s5b/ si existe: re-corrida de dpart_* tras
el fix del parser de d_particle) y genera:
  - paper/tables/s5_sensitivity.tex (tabla booktabs para §6)
  - un resumen por stdout con los canales de energía al sólido

Métrica clave: Q_sol = ∫(E_arc_direct_sol + E_mc_deposit + E_rad_sol +
E_chem_sol) — todo el calor que llega al sólido; la masa fundida a 120 s
es una métrica de UMBRAL (no lineal) y se reporta junto a T_s,max.

Uso: analyze_s5_sensitivity.py
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

RUNS = [
    # (nombre, dir, etiqueta de la perilla)
    ("base",      "s5",  r"referencia"),
    ("beams_1e2", "s5",  r"$N_{\rm beams}=10^2$ (vs $10^3$)"),
    ("beams_1e4", "s5",  r"$N_{\rm beams}=10^4$"),
    ("dpart_low", "s5b", r"$d_p=0.025$ m (vs 0.10)"),
    ("dpart_high","s5b", r"$d_p=0.075$ m"),
    ("cfrac_2x",  "s5",  r"$w_{\rm C}=1\%$ (vs 0.5\%)"),
    ("frad_low",  "s5",  r"$f_{\rm rad}=0.4$, $f_{\rm conv}=0.4$"),
    ("frad_high", "s5",  r"$f_{\rm rad}=0.6$, $f_{\rm conv}=0.2$"),
]
Q_COLS = ["E_arc_direct_sol", "E_mc_deposit", "E_rad_sol", "E_chem_sol"]


def load(campaign, run):
    d = os.path.join(REPO, "campaigns", campaign, run)
    if not os.path.isfile(os.path.join(d, "audit.csv")):
        return None
    # solo corridas TERMINADAS: el runner escribe summary.csv al final de
    # la campaña; sin fila ahí, la corrida está en curso o incompleta
    spath0 = os.path.join(REPO, "campaigns", campaign, "summary.csv")
    if not os.path.isfile(spath0) or run not in {
            s["name"] for s in csv.DictReader(open(spath0))}:
        return None
    rows = list(csv.DictReader(open(os.path.join(d, "audit.csv"))))
    q_sol = sum(sum(float(r[c]) for c in Q_COLS) for r in rows)
    m_melt = sum(float(r["m_melted"]) for r in rows)
    t_end = float(rows[-1]["time"])
    # extremos desde el summary de la campaña
    summ = {}
    spath = os.path.join(REPO, "campaigns", campaign, "summary.csv")
    if os.path.isfile(spath):
        for s in csv.DictReader(open(spath)):
            if s["name"] == run:
                summ = s
    return {
        "q_sol_gj": q_sol / 1e9,
        "m_melt": m_melt,
        "t_end": t_end,
        "T_s_max": float(summ.get("T_solid_max", "nan")),
        "T_g_max": float(summ.get("T_gas_max", "nan")),
        "wall_s": float(summ.get("wall_s", "nan")),
    }


results = []
for run, camp, label in RUNS:
    r = load(camp, run)
    results.append((run, label, r))
    if r is None:
        print(f"{run:<11} PENDIENTE (campaña {camp} sin datos)")
    else:
        print(f"{run:<11} Q_sol={r['q_sol_gj']:7.2f} GJ  "
              f"m_melt={r['m_melt']:8.1f} kg  T_s,max={r['T_s_max']:7.1f} K  "
              f"T_g,max={r['T_g_max']:7.1f} K  wall={r['wall_s']:8.0f} s")

out = os.path.join(REPO, "paper", "tables", "s5_sensitivity.tex")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    f.write("% Generado por scripts/analyze_s5_sensitivity.py -- no editar\n")
    f.write("\\begin{tabular}{llrrrr}\n\\hline\n")
    f.write("Variante & Perilla & $Q_{\\rightarrow\\rm sol}$ [GJ] & "
            "$m_{\\rm fund}$ [kg] & $T_{s,\\max}$ [K] & "
            "$T_{g,\\max}$ [K] \\\\\n\\hline\n")
    for run, label, r in results:
        name = run.replace("_", "\\_")
        if r is None:
            f.write(f"{name} & {label} & \\multicolumn{{4}}{{c}}"
                    f"{{(re-corrida en curso)}} \\\\\n")
        else:
            f.write(f"{name} & {label} & {r['q_sol_gj']:.2f} & "
                    f"{r['m_melt']:.0f} & {r['T_s_max']:.0f} & "
                    f"{r['T_g_max']:.0f} \\\\\n")
    f.write("\\hline\n\\end{tabular}\n")
print(f"tabla: {out}")
