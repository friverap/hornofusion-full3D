#!/usr/bin/env python3
"""Genera la tabla LaTeX del glosario de columnas de audit.csv (P0.3).

Extrae el encabezado REAL del CSV desde mod_audit.f90 (fuente de verdad) y
lo cruza con el diccionario de definiciones de este script. Si aparece una
columna sin definición, FALLA: así el glosario no puede quedarse atrás del
código. Salida: paper/tables/audit_glossary.tex
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "src", "mod_audit.f90")
OUT = os.path.join(REPO, "paper", "tables", "audit_glossary.tex")

# tipo: I = inventario instantáneo; S = integral de fuente por intervalo
# (hooks in-solver); C = contador acumulativo (audit_add); D = diagnóstico
DEFS = {
    "step":  ("--", "Time-step index at the row"),
    "time":  ("--", "Simulated time [s]"),
    "dt":    ("--", "Time step of the written step [s]"),
    "m_liq": ("I", "Liquid inventory $\\sum \\alpha_l\\rho_l V$ [kg]"),
    "m_gas": ("I", "Gas inventory $\\sum \\alpha_g\\rho_g(T) V$ [kg]"),
    "m_sol": ("I", "Solid inventory $\\sum m_s$ [kg]"),
    "m_slag": ("I", "Slag inventory $\\sum m_{sl}$ [kg]"),
    "E_liq": ("I", "Liquid energy $\\sum \\alpha_l\\rho_l(c_{p,l}T+C_0)V$ "
                   "[J] (solid-consistent datum)"),
    "E_gas": ("I", "Gas log-form energy inventory [J] (diagnostic; the "
                   "balance uses E\\_gas\\_abs)"),
    "E_sol": ("I", "Solid enthalpy $\\sum E_s$ [J]"),
    "E_slag": ("I", "Slag enthalpy $\\sum E_{sl}$ [J]"),
    "P_arc": ("D", "Instantaneous total arc power $\\sum_e I^2R$ [W]"),
    "E_src_liq_arc": ("S", "Arc+MC source absorbed by the liquid equation "
                           "[J] (exact in-solver hook)"),
    "E_src_liq_rad": ("S", "Net DO radiation to the liquid [J] (Newton "
                           "linearisation at the assembled iterate)"),
    "E_src_liq_chem": ("S", "Post-combustion heat to the liquid [J]"),
    "E_src_gas_arc": ("S", "Arc+MC source absorbed by the gas equation [J]"),
    "E_src_gas_rad": ("S", "Net DO radiation to the gas [J]"),
    "E_src_gas_chem": ("S", "Post-combustion heat to the gas [J]"),
    "E_arc_direct_sol": ("C", "Direct arc footprint deposited into solid "
                              "enthalpy [J]"),
    "E_arc_discarded": ("C", "Arc energy discarded by caps [J] (sentinel; "
                             "0 by design since C1.6)"),
    "E_mc_deposit": ("C", "Monte Carlo ray energy deposited into S\\_arc "
                          "[J]"),
    "m_melted": ("C", "Melted solid mass [kg]"),
    "m_resolid": ("C", "Re-solidified liquid mass [kg]"),
    "E_melt_from_solid": ("C", "Enthalpy removed from the solid by melting "
                               "$\\sum \\dot m\\, e_s(T_s)\\,dt$ [J]"),
    "m_alpha_clip": ("C", "Net mass removed by the volume-constraint clip "
                          "of $\\alpha_l$ [kg] (the only mass error of the "
                          "explicit transport)"),
    "E_slag_intercept": ("C", "Arc energy intercepted by the slag cover "
                              "[J]"),
    "E_rad_sol": ("C", "DO radiation deposited into solid enthalpy [J]"),
    "E_rad_wall": ("C", "Net radiative loss to black walls [J]"),
    "E_conv_defect": ("S", "Global conservation defect of the bounded "
                           "convection operator [J] (exact assembled-"
                           "coefficient statement; enters the balance "
                           "identity)"),
    "E_wall_conv": ("S", "Robin wall loss $\\sum h_w A \\alpha (T-T_w) dt$ "
                         "[J]"),
    "E_chem_sol": ("C", "Primary carbon-oxidation heat to the solid [J]"),
    "E_mc_lost": ("C", "Monte Carlo ray energy escaped through ports/"
                       "walls [J] (closes the arc budget)"),
    "E_out_conv": ("S", "Net convective enthalpy into the outlet sink "
                        "cells [J] (diagnostic; included in the defect)"),
    "E_gas_abs": ("S", "Heat absorbed by the gas over the step "
                       "$\\sum \\alpha_g\\rho_g c_p \\Delta T\\, V$ [J] "
                       "(the gas dE of the balance; includes explicit "
                       "interphase removal)"),
    "E_mass_liq": ("S", "Melting/freezing mass-source terms of the liquid "
                        "energy equation [J] (diagnostic)"),
}

src = open(SRC).read()
m = re.search(r"write\(iu, '\(A\)'\) 'step,time,dt,' // &\n(.*?)\n\n",
              src, re.S)
if not m:
    sys.exit("ERROR: no encuentro el encabezado CSV en mod_audit.f90")
header = "step,time,dt," + "".join(
    re.findall(r"'([^']*)'", m.group(1)))
cols = [c for c in header.split(",") if c]

missing = [c for c in cols if c not in DEFS]
if missing:
    sys.exit(f"ERROR: columnas sin definicion en el glosario: {missing}\n"
             "Actualiza DEFS en scripts/make_audit_glossary.py")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write("%% Generado por scripts/make_audit_glossary.py — NO editar\n")
    f.write("%% a mano (se regenera desde el encabezado de mod_audit.f90)\n")
    f.write("\\begin{table*}\n  \\centering\n")
    f.write("  \\caption{Glossary of the conservation-audit stream "
            "(\\texttt{audit.csv}), one row per time step. Type: I = "
            "instantaneous inventory; S = per-interval source integral "
            "recorded by in-solver hooks; C = cumulative counter; D = "
            "diagnostic. Cumulative columns accumulate since the previous "
            "row.}\n")
    f.write("  \\label{tab:audit}\n  \\small\n")
    f.write("  \\begin{tabular}{llp{11cm}}\n    \\toprule\n")
    f.write("    Column & Type & Definition \\\\\n    \\midrule\n")
    for c in cols:
        typ, desc = DEFS[c]
        cname = c.replace("_", "\\_")
        f.write(f"    \\texttt{{{cname}}} & {typ} & {desc} \\\\\n")
    f.write("    \\bottomrule\n  \\end{tabular}\n\\end{table*}\n")
print(f"escrito {OUT} ({len(cols)} columnas)")
