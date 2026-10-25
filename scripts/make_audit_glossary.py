#!/usr/bin/env python3
"""Genera la tabla LaTeX del glosario de columnas de audit.csv (P0.3).

Extrae el encabezado REAL del CSV desde mod_audit.f90 (fuente de verdad) y
lo cruza con el diccionario de definiciones de este script. Si aparece una
columna sin definición, FALLA: así el glosario no puede quedarse atrás del
código. Salidas: paper/tables/audit_glossary.tex (LaTeX, fuera del repo) y
docs/AUDIT_COLUMNS.md (Markdown, versionado; B5-22).
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
    "E_gas_abs": ("S", "Heat absorbed by the gas over the step [J]: "
                       "$\\sum \\alpha_g\\rho_g c_p (T_{end,SIMPLE}-T_{old}) V$ "
                       "(what the gas equation did) plus the exact log-form "
                       "heat of the interphase and slag pokes (the gas dE of "
                       "the balance; audit 5, B5-3)"),
    "E_mass_liq": ("S", "Melting/freezing mass-source terms of the liquid "
                        "energy equation [J] (diagnostic)"),
    "m_ecs_in": ("C", "Solid mass charged by the continuous feeder (ECS) "
                      "[kg]"),
    "E_ecs_in": ("C", "Enthalpy charged by the continuous feeder "
                      "$\\sum dm\\, e_s(T_{charge})$ [J]"),
    "m_flux_in": ("C", "Lime/dololime/injected-carbon mass added to the "
                       "slag [kg]"),
    "E_flux_in": ("C", "Sensible enthalpy of slag additions (enter at "
                       "ambient temperature) [J]"),
    "m_fe_yield": ("C", "Iron oxidised out of the bath into slag FeO "
                        "(yield loss) [kg]"),
    "m_fe_return": ("C", "Iron returned to the bath by FeO+C reduction "
                         "[kg]"),
    "E_slag_ox": ("C", "Energy gained by slag + bath in Fe+1/2O$_2$$\\to$FeO: exothermic "
                       "heat plus the datum difference between phases (FeO at the slag "
                       "datum, Fe out at the steel datum) [J] (audit 19)"),
    "E_slag_red": ("C", "Energy leaving slag + bath in FeO+C$\\to$Fe+CO: endothermic heat "
                        "plus the datum difference (reactants at the slag datum, Fe in at "
                        "the steel datum, CO enthalpy) [J] (audit 19)"),
    "E_rad_foam": ("C", "DO radiation absorbed by the foam/slag layer "
                        "[J]"),
    "E_iph_sol": ("C", "Interphase heat gained by the solid over the "
                       "interval, as applied to $E_s$ [J]"),
    "E_iph_gas": ("C", "Interphase heat removed from the gas (with the "
                       "regularised denominator of the $T$ update) [J]"),
    "E_iph_liq": ("C", "Interphase heat removed from the liquid (idem) "
                       "[J]"),
    "m_resid_closed": ("C", "Residual solid handed to the liquid by the "
                             "vanishing-phase closure ($0<\\alpha_s\\le10^{-4}$) "
                             "[kg]; subset of m\\_melted"),
    "E_resid_closed": ("C", "Enthalpy handed with that residual [J]; subset "
                             "of E\\_melt\\_from\\_solid"),
    "vol_dalpha_outer": ("D", "Liquid volume moved between the incoming outer "
                               "iterate and the transported fraction, last outer "
                               "iteration [m$^3$] (lag of $\\alpha$ in the pressure equation)"),
    "vol_lim": ("D", "Liquid inflow blocked by the pore-capacity limiter, last "
                     "outer iteration [m$^3$]"),
    "vol_unlinked": ("D", "Liquid volume crossing faces not linked in the pressure "
                          "equation (dispersed/drift), last outer iteration [m$^3$]"),
    "m_spill": ("C", "Liquid mass moved upward by the conservative spill of "
                     "volume-constraint excess, counted PER HOP [kg]: a relay "
                     "chain of $L$ cells adds $L$ times the mass, so it is an "
                     "upper bound of the mass moved (informative; no mass "
                     "error; audit 9, B9-5)"),
    "p_max": ("D", "Maximum $|p|$ over active cells at the written step [Pa] "
                   "(blow-up sentinel: the cap is $2\\times10^6$)"),
    "u_gas_max": ("D", "Maximum gas speed over cells with "
                       "$\\alpha_g\\ge10^{-2}$ [m\\,s$^{-1}$]"),
    "u_liq_max": ("D", "Maximum liquid speed over cells with "
                       "$\\alpha_l\\ge10^{-2}$ [m\\,s$^{-1}$] (cap 20)"),
    "m_charge_in": ("C", "Scrap mass charged by baskets after start-up [kg]"),
    "E_charge_in": ("C", "Enthalpy charged with that scrap [J]"),
    "m_C_oxid": ("C", "Carbon oxidised to CO; leaves the steel inventory [kg]"),
    "m_dil_O2": ("C", "O$_2$ displaced by the dilution of reaction mass entering "
                      "the gas ($-Y_k S_{gas}$, EOS-fixed density) [kg]"),
    "m_dil_CO": ("C", "CO displaced by that dilution [kg]"),
    "m_dil_CO2": ("C", "CO$_2$ displaced by that dilution [kg]"),
    "m_gas_volfix": ("C", "Gas mass created (+) or destroyed (-) when "
                          "$\\alpha_g=1-\\sum\\alpha$ is re-imposed without the "
                          "two-fluid $\\alpha$ transport [kg]"),
    "E_slag_tclip": ("C", "Enthalpy injected by the slag floor $T_{sl}\\ge300$ K and, with "
                          "condensed slag, by the thermal equilibration of slag traces "
                          "($\\alpha_{sl}<10^{-6}$) with the bath [J]"),
    "E_mix_init": ("C", "Heat the liquid receives from the gas in the start-up "
                        "equilibration of the mixture model [J]"),
    "E_resolid": ("C", "Enthalpy handed to the solid by freezing ($dm\\,e_{entry}$) [J]"),
    "E_alpha_clip": ("C", "Enthalpy removed with the audited $\\alpha$ clip [J]"),
    "E_conv_liq": ("D", "Convective defect of the bounded liquid energy statement [J]"),
    "E_conv_gas": ("D", "Convective defect of the bounded gas energy statement [J]; "
                        "the only one that enters the identity"),
    "E_abs_gas_hook": ("D", "Heat absorbed by the gas equation according to its own "
                            "hook [J] (diagnostic against E\\_gas\\_abs)"),
    "E_slag_gas": ("C", "Heat the slag receives from the gas of its cell [J] "
                        "(transfer between state inventories; diagnostic)"),
    "E_slag_liq": ("C", "Heat the slag receives from the bath (own cell or the "
                        "one below) [J] (diagnostic)"),
    "m_gas_out": ("C", "Net gas mass entering the outlet cells (electrode holes) "
                       "with the conservative gas fluxes [kg]: the export"),
    "m_gas_rxn": ("C", "Gas mass created by the reactions ($S_{CO}+S_{CO_2}+S_{O_2}$) "
                       "[kg]"),
    "E_gas_volfix": ("C", "Enthalpy carried by the gas mass the volume constraint creates "
                          "or destroys ($m_{gas,volfix}\\,c_p T$) [J]; exact external term"),
    "m_vf_O2": ("C", "O$_2$ mass leaving with the gas destroyed by the volume constraint, "
                     "slag buoyancy, bucket charge or ECS [kg] (created gas carries no species)"),
    "m_vf_CO": ("C", "CO mass leaving with the destroyed gas [kg]"),
    "m_vf_CO2": ("C", "CO$_2$ mass leaving with the destroyed gas [kg]"),
    "m_gas_ccdrop": ("C", "Gas mass whose compressibility volume demand the step discards "
                          "($\\rho_g$ x overflow of the carry bound, carry of cells that leave "
                          "the coupling, lose their gas or are sealed) [kg]; named part of the "
                          "EOS residual of mass\\_gas (audit 6, M6-1/M6-2)"),
    "m_slag_clip": ("C", "Condensed slag mass removed by the bounding of the volume-fraction "
                         "transport (slag share of the final clip, $\\alpha_{sl}\\le\\alpha_c$) "
                         "[kg] (Plan H, P6)"),
    "E_slag_clip": ("C", "Slag enthalpy leaving with m\\_slag\\_clip [J]"),
    "m_steel_deficit": ("C", "Steel mass created by the freezing deficit of the condensed transport "
                              "(freezing sink larger than the cell steel; audit 19, M19-C2) [kg]"),
    "E_steel_deficit": ("C", "Enthalpy of m\\_steel\\_deficit [J]"),
    "E_abs_liq_hook": ("D", "Heat absorbed by the liquid equation according to its own "
                       "hook, last outer iteration [J] (WS-K3)"),
    "E_relax_liq": ("D", "Residual of the liquid discrete energy statement on the standing field Tk "
                    "(T under-relaxation + incomplete inner solve; per-phase split valid only "
                    "in two-fluid mode, not with mixture_model): absorbed - (arc + rad + chem + conv - wall + mass) of the hook [J]; "
                    "energy the inventory gains/loses with no physical term, NOT in the identity (WS-K3/WS-K4, C-096..C-103)"),
    "E_relax_gas": ("D", "Same residual for the gas equation [J] (WS-K3)"),
    "m_gas_err_free": ("D", "Per-cell gas mass balance error d(alpha rho V) - dt sum F_g - rxn - volfix of the cell "
                       "(melt/charge/ECS/slag displacement, WS-K6) summed over "
                       "free-gas cells (no liquid, slag nor solid at the start AND end of the step); 0 when "
                       "ws_Fg is not valid (mixture model), see m_gas_cells_skip [kg] (WS-K5)"),
    "m_gas_err_multi": ("D", "Same per-cell error (cell volfix subtracted, WS-K6) over multiphase cells (liquid, slag or "
                        "solid present): mass "
                        "created/destroyed where the complement alpha_g = 1 - sum acts (hypothesis C-110: the complement "
                        "without gas flux, N-M4; alternative: unlinked faces ws_Fg_lk = 0) [kg] (WS-K5)"),
    "m_gas_err_abs": ("D", "Sum of |per-cell gas mass error| over non-outlet cells [kg] (WS-K5)"),
    "m_gas_err_out": ("D", "Same per-cell error over the outlet cells (roof electrode cells, the sink); closure "
                      "EOS - (free + multi + out) = vent to round-off [kg] (WS-K5/WS-K6)"),
    "m_gas_vf_cells": ("D", "Gas volfix registered per cell by the AUD_GAS_VOLFIX routes "
                       "(audit_volfix_cell); check mass_gas_vf_cells requires it to equal m_gas_volfix [kg] (WS-K6)"),
    "m_gas_cells_skip": ("D", "Steps without per-cell gas balance (ws_Fg not valid: mixture model or no "
                         "multiphase) [-] (WS-K5)"),
    "E_slag_sol": ("C", "Heat from the slag to the scrap by contact in the bed (condensed slag "
                        "in the pores; internal between inventories, diagnostic) [J]"),
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

# (auditoria 5, B5-22) el mismo glosario en Markdown DENTRO del repo (paper/
# esta en .gitignore): docs/AUDIT_COLUMNS.md, referenciado desde OUTPUT.md
OUT_MD = os.path.join(REPO, "docs", "AUDIT_COLUMNS.md")
with open(OUT_MD, "w") as f:
    f.write("# Columnas de `audit.csv`\n\n")
    f.write("Generado por `scripts/make_audit_glossary.py` desde el encabezado de "
            "`src/mod_audit.f90` (no editar a mano; regenerar tras añadir una "
            "columna). Una fila por paso (`audit_freq`), más la fila 0 del estado "
            "inicial. Tipo: I = inventario instantáneo; S = integral de fuente por "
            "intervalo (hooks del solver); C = contador acumulativo (`audit_add`), "
            "acumula desde la fila anterior; D = diagnóstico. Las identidades que "
            "los relacionan viven en `tests/integration/check_audit.py`.\n\n")
    f.write("| Columna | Tipo | Definición |\n|---|---|---|\n")
    for c in cols:
        typ, desc = DEFS[c]
        d = desc.replace("\\_", "_").replace("$", "`").replace("\\,", " ")
        d = d.replace("|", "\\|")   # (B6-21) una | sin escapar rompe la tabla
        f.write(f"| `{c}` | {typ} | {d} |\n")
print(f"escrito {OUT_MD}")
