# Columnas de `audit.csv`

Generado por `scripts/make_audit_glossary.py` desde el encabezado de `src/mod_audit.f90` (no editar a mano; regenerar tras añadir una columna). Una fila por paso (`audit_freq`), más la fila 0 del estado inicial. Tipo: I = inventario instantáneo; S = integral de fuente por intervalo (hooks del solver); C = contador acumulativo (`audit_add`), acumula desde la fila anterior; D = diagnóstico. Las identidades que los relacionan viven en `tests/integration/check_audit.py`.

| Columna | Tipo | Definición |
|---|---|---|
| `step` | -- | Time-step index at the row |
| `time` | -- | Simulated time [s] |
| `dt` | -- | Time step of the written step [s] |
| `m_liq` | I | Liquid inventory `\sum \alpha_l\rho_l V` [kg] |
| `m_gas` | I | Gas inventory `\sum \alpha_g\rho_g(T) V` [kg] |
| `m_sol` | I | Solid inventory `\sum m_s` [kg] |
| `m_slag` | I | Slag inventory `\sum m_{sl}` [kg] |
| `E_liq` | I | Liquid energy `\sum \alpha_l\rho_l(c_{p,l}T+C_0)V` [J] (solid-consistent datum) |
| `E_gas` | I | Gas log-form energy inventory [J] (diagnostic; the balance uses E_gas_abs) |
| `E_sol` | I | Solid enthalpy `\sum E_s` [J] |
| `E_slag` | I | Slag enthalpy `\sum E_{sl}` [J] |
| `P_arc` | D | Instantaneous total arc power `\sum_e I^2R` [W] |
| `E_src_liq_arc` | S | Arc+MC source absorbed by the liquid equation [J] (exact in-solver hook) |
| `E_src_liq_rad` | S | Net DO radiation to the liquid [J] (Newton linearisation at the assembled iterate) |
| `E_src_liq_chem` | S | Post-combustion heat to the liquid [J] |
| `E_src_gas_arc` | S | Arc+MC source absorbed by the gas equation [J] |
| `E_src_gas_rad` | S | Net DO radiation to the gas [J] |
| `E_src_gas_chem` | S | Post-combustion heat to the gas [J] |
| `E_arc_direct_sol` | C | Direct arc footprint deposited into solid enthalpy [J] |
| `E_arc_discarded` | C | Arc energy discarded by caps [J] (sentinel; 0 by design since C1.6) |
| `E_mc_deposit` | C | Monte Carlo ray energy deposited into S_arc [J] |
| `m_melted` | C | Melted solid mass [kg] |
| `m_resolid` | C | Re-solidified liquid mass [kg] |
| `E_melt_from_solid` | C | Enthalpy removed from the solid by melting `\sum \dot m  e_s(T_s) dt` [J] |
| `m_alpha_clip` | C | Net mass removed by the volume-constraint clip of `\alpha_l` [kg] (the only mass error of the explicit transport) |
| `E_slag_intercept` | C | Arc energy intercepted by the slag cover [J] |
| `E_rad_sol` | C | DO radiation deposited into solid enthalpy [J] |
| `E_rad_wall` | C | Net radiative loss to black walls [J] |
| `E_conv_defect` | S | Global conservation defect of the bounded convection operator [J] (exact assembled-coefficient statement; enters the balance identity) |
| `E_wall_conv` | S | Robin wall loss `\sum h_w A \alpha (T-T_w) dt` [J] |
| `E_chem_sol` | C | Primary carbon-oxidation heat to the solid [J] |
| `E_mc_lost` | C | Monte Carlo ray energy escaped through ports/walls [J] (closes the arc budget) |
| `E_out_conv` | S | Net convective enthalpy into the outlet sink cells [J] (diagnostic; included in the defect) |
| `E_gas_abs` | S | Heat absorbed by the gas over the step [J]: `\sum \alpha_g\rho_g c_p (T_{end,SIMPLE}-T_{old}) V` (what the gas equation did) plus the exact log-form heat of the interphase and slag pokes (the gas dE of the balance; audit 5, B5-3) |
| `E_mass_liq` | S | Melting/freezing mass-source terms of the liquid energy equation [J] (diagnostic) |
| `m_ecs_in` | C | Solid mass charged by the continuous feeder (ECS) [kg] |
| `E_ecs_in` | C | Enthalpy charged by the continuous feeder `\sum dm  e_s(T_{charge})` [J] |
| `m_flux_in` | C | Lime/dololime/injected-carbon mass added to the slag [kg] |
| `E_flux_in` | C | Sensible enthalpy of slag additions (enter at ambient temperature) [J] |
| `m_fe_yield` | C | Iron oxidised out of the bath into slag FeO (yield loss) [kg] |
| `m_fe_return` | C | Iron returned to the bath by FeO+C reduction [kg] |
| `E_slag_ox` | C | Energy gained by slag + bath in Fe+1/2O`_2``\to`FeO: exothermic heat plus the datum difference between phases (FeO at the slag datum, Fe out at the steel datum) [J] (audit 19) |
| `E_slag_red` | C | Energy leaving slag + bath in FeO+C`\to`Fe+CO: endothermic heat plus the datum difference (reactants at the slag datum, Fe in at the steel datum, CO enthalpy) [J] (audit 19) |
| `E_rad_foam` | C | DO radiation absorbed by the foam/slag layer [J] |
| `E_iph_sol` | C | Interphase heat gained by the solid over the interval, as applied to `E_s` [J] |
| `E_iph_gas` | C | Interphase heat removed from the gas (with the regularised denominator of the `T` update) [J] |
| `E_iph_liq` | C | Interphase heat removed from the liquid (idem) [J] |
| `m_resid_closed` | C | Residual solid handed to the liquid by the vanishing-phase closure (`0<\alpha_s\le10^{-4}`) [kg]; subset of m_melted |
| `E_resid_closed` | C | Enthalpy handed with that residual [J]; subset of E_melt_from_solid |
| `m_spill` | C | Liquid mass moved upward by the conservative spill of volume-constraint excess, counted PER HOP [kg]: a relay chain of `L` cells adds `L` times the mass, so it is an upper bound of the mass moved (informative; no mass error; audit 9, B9-5) |
| `vol_dalpha_outer` | D | Liquid volume moved between the incoming outer iterate and the transported fraction, last outer iteration [m`^3`] (lag of `\alpha` in the pressure equation) |
| `vol_lim` | D | Liquid inflow blocked by the pore-capacity limiter, last outer iteration [m`^3`] |
| `vol_unlinked` | D | Liquid volume crossing faces not linked in the pressure equation (dispersed/drift), last outer iteration [m`^3`] |
| `p_max` | D | Maximum `\|p\|` over active cells at the written step [Pa] (blow-up sentinel: the cap is `2\times10^6`) |
| `u_gas_max` | D | Maximum gas speed over cells with `\alpha_g\ge10^{-2}` [m s`^{-1}`] |
| `u_liq_max` | D | Maximum liquid speed over cells with `\alpha_l\ge10^{-2}` [m s`^{-1}`] (cap 20) |
| `m_charge_in` | C | Scrap mass charged by baskets after start-up [kg] |
| `E_charge_in` | C | Enthalpy charged with that scrap [J] |
| `m_C_oxid` | C | Carbon oxidised to CO; leaves the steel inventory [kg] |
| `m_dil_O2` | C | O`_2` displaced by the dilution of reaction mass entering the gas (`-Y_k S_{gas}`, EOS-fixed density) [kg] |
| `m_dil_CO` | C | CO displaced by that dilution [kg] |
| `m_dil_CO2` | C | CO`_2` displaced by that dilution [kg] |
| `m_gas_volfix` | C | Gas mass created (+) or destroyed (-) when `\alpha_g=1-\sum\alpha` is re-imposed without the two-fluid `\alpha` transport [kg] |
| `E_slag_tclip` | C | Enthalpy injected by the slag floor `T_{sl}\ge300` K and, with condensed slag, by the thermal equilibration of slag traces (`\alpha_{sl}<10^{-6}`) with the bath [J] |
| `E_mix_init` | C | Heat the liquid receives from the gas in the start-up equilibration of the mixture model [J] |
| `E_resolid` | C | Enthalpy handed to the solid by freezing (`dm e_{entry}`) [J] |
| `E_alpha_clip` | C | Enthalpy removed with the audited `\alpha` clip [J] |
| `E_conv_liq` | D | Convective defect of the bounded liquid energy statement [J] |
| `E_conv_gas` | D | Convective defect of the bounded gas energy statement [J]; the only one that enters the identity |
| `E_abs_gas_hook` | D | Heat absorbed by the gas equation according to its own hook [J] (diagnostic against E_gas_abs) |
| `E_slag_gas` | C | Heat the slag receives from the gas of its cell [J] (transfer between state inventories; diagnostic) |
| `E_slag_liq` | C | Heat the slag receives from the bath (own cell or the one below) [J] (diagnostic) |
| `m_gas_out` | C | Net gas mass entering the outlet cells (electrode holes) with the conservative gas fluxes [kg]: the export |
| `m_gas_rxn` | C | Gas mass created by the reactions (`S_{CO}+S_{CO_2}+S_{O_2}`) [kg] |
| `E_gas_volfix` | C | Enthalpy carried by the gas mass the volume constraint creates or destroys (`m_{gas,volfix} c_p T`) [J]; exact external term |
| `m_vf_O2` | C | O`_2` mass leaving with the gas destroyed by the volume constraint, slag buoyancy, bucket charge or ECS [kg] (created gas carries no species) |
| `m_vf_CO` | C | CO mass leaving with the destroyed gas [kg] |
| `m_vf_CO2` | C | CO`_2` mass leaving with the destroyed gas [kg] |
| `m_gas_ccdrop` | C | Gas mass whose compressibility volume demand the step discards (`\rho_g` x overflow of the carry bound, carry of cells that leave the coupling, lose their gas or are sealed) [kg]; named part of the EOS residual of mass_gas (audit 6, M6-1/M6-2) |
| `m_slag_clip` | C | Condensed slag mass removed by the bounding of the volume-fraction transport (slag share of the final clip, `\alpha_{sl}\le\alpha_c`) [kg] (Plan H, P6) |
| `E_slag_clip` | C | Slag enthalpy leaving with m_slag_clip [J] |
| `E_slag_sol` | C | Heat from the slag to the scrap by contact in the bed (condensed slag in the pores; internal between inventories, diagnostic) [J] |
| `m_steel_deficit` | C | Steel mass created by the freezing deficit of the condensed transport (freezing sink larger than the cell steel; audit 19, M19-C2) [kg] |
| `E_steel_deficit` | C | Enthalpy of m_steel_deficit [J] |
| `E_abs_liq_hook` | D | Heat absorbed by the liquid equation according to its own hook, last outer iteration [J] (WS-K3) |
| `E_relax_liq` | D | Residual of the liquid discrete energy statement on the standing field Tk (T under-relaxation + incomplete inner solve; per-phase split valid only in two-fluid mode, not with mixture_model): absorbed - (arc + rad + chem + conv - wall + mass) of the hook [J]; energy the inventory gains/loses with no physical term, NOT in the identity (WS-K3/WS-K4, C-096..C-103) |
| `E_relax_gas` | D | Same residual for the gas equation [J] (WS-K3) |
| `m_gas_err_free` | D | Per-cell gas mass balance error d(alpha rho V) - dt sum F_g - rxn - volfix of the cell (melt/charge/ECS/slag displacement, WS-K6) summed over free-gas cells (no liquid, slag nor solid at the start AND end of the step); 0 when ws_Fg is not valid (mixture model), see m_gas_cells_skip [kg] (WS-K5) |
| `m_gas_err_multi` | D | Same per-cell error (cell volfix subtracted, WS-K6) over multiphase cells (liquid, slag or solid present): mass created/destroyed where the complement alpha_g = 1 - sum acts (hypothesis C-110: the complement without gas flux, N-M4; alternative: unlinked faces ws_Fg_lk = 0) [kg] (WS-K5) |
| `m_gas_err_abs` | D | Sum of \|per-cell gas mass error\| over non-outlet cells [kg] (WS-K5) |
| `m_gas_err_out` | D | Same per-cell error over the outlet cells (roof electrode cells, the sink); closure EOS - (free + multi + out) = vent to round-off [kg] (WS-K5/WS-K6) |
| `m_gas_cells_skip` | D | Steps without per-cell gas balance (ws_Fg not valid: mixture model or no multiphase) [-] (WS-K5) |
| `m_gas_vf_cells` | D | Gas volfix registered per cell by the AUD_GAS_VOLFIX routes (audit_volfix_cell); check mass_gas_vf_cells requires it to equal m_gas_volfix [kg] (WS-K6) |
| `m_gas_comp` | D | Gas mass created/destroyed by the complement alpha_g = 1 - sum after the liquid transport (3 sites in mod_continuity, audit_comp_cell): sum rho_g V d(alpha_g) [kg] (WS-K7) |
| `m_gas_eos` | D | Gas mass rewritten by the EOS in update_properties (audit_eos_cell): sum alpha_g V d(rho_g) [kg]; check mass_gas_rewrites: dm_gas = comp + eos + volfix (WS-K7) |
| `m_gas_err_liq` | D | Over multiphase cells with gas at the start or end of the step (alpha_g > 0; 0 elsewhere): rho_g (V_pois_in - V_eff_in), the liquid volume the Poisson balanced (ws_Fc on linked faces + the E2 source that the LAST Poisson actually added to Su, ws_pc_unl_used; C-144) minus the volume the transport moved (ws_Fr/Fth/Fz, all faces): the per-cell error predicted by hypothesis C-110 [kg]. It is the RESTRICTION of m_gas_err_liq_all to the cells with gas at the start or end; the split lk + unl is of m_gas_err_liq_all, NOT of this column. Not valid with slag: with condensed slag (Plan H) it is not evaluated (counted in m_gas_liq_skip); with slag on the legacy path (slag_in_volume = false) it IS evaluated but V_eff is the steel flux while the complement subtracts the slag, and check_audit prints n/a (WS-K7) |
| `m_gas_err_abs_multi` | D | Sum of \|per-cell gas mass error\| over multiphase cells only [kg] (WS-K7) |
| `m_gas_err_rem_abs` | D | Sum of \|e - err_liq\| over ALL multiphase cells, on steps with valid liquid-side terms (err_liq = 0 outside the gas set, so the set matches m_gas_err_abs_multi): a residual by subtraction e - err_liq; 1 - rem/abs is NOT a mechanism attribution (it mixes scale and correlation) [kg] (WS-K7) |
| `m_gas_liq_skip` | D | Steps without the liquid-side terms of the per-cell audit (ws_Fc or ws_Fr not valid: implicit alpha fallback; or condensed slag on, where ws_Fr is the steel flux and the complement follows the condensed transport). Slag on the legacy path is NOT skipped here (check_audit flags it as n/a from m_slag). check_audit evaluates the m_gas_err_liq family only on rows with 0 here, and prints n/a when there are none [-] (WS-K7) |
| `m_gas_vpois_abs` | D | Sum \|rho_g V_pois_in\| over multiphase cells with gas: size of the liquid volume the Poisson balanced, in gas mass units [kg] (WS-K7, sanity of m_gas_err_liq) |
| `m_gas_veff_abs` | D | Sum \|rho_g V_eff_in\| over multiphase cells with gas: size of the liquid volume the transport moved, in gas mass units [kg] (WS-K7) |
| `m_gas_err_abs_nogas` | D | Sum of \|e\| over the multiphase cells with no gas at the start nor the end of the step, i.e. outside the m_gas_err_liq set (m_gas_err_liq_all does cover them); accumulated whether or not the liquid-side terms are valid [kg] (WS-K7, C-124) |
| `m_gas_comp_abs` | D | Sum of \|dm\| over every call of audit_comp_cell (each complement site, each outer iteration): gas mass created plus destroyed by alpha_g = 1 - sum within the step, without the intra-step cancellation hidden by m_gas_comp [kg] (WS-K7, C-133) |
| `m_gas_eos_abs` | D | Sum of \|dm\| over every call of audit_eos_cell (each update_properties): gas mass rewritten plus un-rewritten by the EOS within the step [kg] (WS-K7, C-133) |
| `m_gas_err_liq_all` | D | err_liq = rho_g (V_pois_in - V_eff_in) summed over ALL multiphase cells, no gas filter (original definition of C-121), on steps with valid liquid-side terms; m_gas_err_liq_all = m_gas_err_liq_lk + m_gas_err_liq_unl by construction [kg] (WS-K7) |
| `m_gas_err_rem_abs_all` | D | Sum of \|e - err_liq\| over ALL multiphase cells with err_liq evaluated everywhere (original C-121 definition): residual by subtraction, not a mechanism attribution [kg] (WS-K7) |
| `m_gas_comp_abs_nogas` | D | m_gas_comp_abs restricted to the multiphase cells with no gas at the start nor the end of the step: > 0 means gas appeared and was destroyed within the step [kg] (WS-K7, C-133) |
| `m_gas_err_abs_nolink` | D | Sum of \|e\| over the multiphase cells with no linked face (liquid nor gas) in the last Poisson: there the E2 source is discarded (Su = 0) and err_liq = -rho_g V_eff_in by construction [kg] (WS-K7, C-132) |
| `m_gas_cells_nolink` | D | Number of multiphase cells with no linked face in the last Poisson, summed over the steps of the row [-] (WS-K7, C-132: 0 means that class is empty) |
| `m_gas_e2_nolink` | D | Sum \|rho_g dt ws_pc_unl\| over the multiphase cells with no linked face: approximately the E2 the Poisson discards there (it reads the E2 of transport N; the last Poisson saw that of transport N-1) [kg] (WS-K7, C-132) |
| `m_gas_err_liq_lk` | D | Part of m_gas_err_liq_all on LINKED faces, computed per cell as the err_liq of m_gas_err_liq_all minus the err_liq_unl of the same cell (the split is an identity by construction): rho_g dt sum_linked (ws_Fc - F/rho_l) up to second order, i.e. limiter, donor alpha vs a_f and face/cell density mismatch between the Poisson plan and the real transport [kg]. Spill is included only with pc_spill_source = false (with it on, spill enters unl_vol too and cancels). Only with pc_drift_source = true: with it off the split is not made and the unlinked inflow of ws_Fr also falls here (WS-K7, C-144) |
| `m_gas_err_liq_unl` | D | Part of m_gas_err_liq_all on UNLINKED faces: rho_g dt (E2 accepted by the last Poisson - E2 of the last transport): the lag of the E2 source between Poisson and transport. It tends to 0 with outer convergence ONLY where the Poisson accepted E2; where it discarded it (inactive, sealed or outlet cell) or accepted none (e.g. single outer iteration) it is -rho_g dt unl(N) at any convergence [kg] (WS-K7, C-144) |
| `m_gas_err_liq_unl_abs` | D | Sum of \|per-cell m_gas_err_liq_unl\| over all multiphase cells: size of the E2 lag [kg] (WS-K7, C-144) |
| `m_gas_vpois_abs_nogas` | D | Sum \|rho_g V_pois_in\| over the multiphase cells with no gas at the start nor the end of the step [kg] (WS-K7, C-144, R1) |
| `m_gas_veff_abs_nogas` | D | Sum \|rho_g V_eff_in\| over the same no-gas cells. These cells are full at both ends of the step and V_eff is NET, so it is ~0 by construction and not informative; whether a cell is blind (nothing in or out) or pass-through (out = in) is not measured [kg] (WS-K7, C-144, C-147/C-148) |
| `m_gas_rej_nogas` | D | Over the no-gas multiphase cells: rho_g (1 - ws_lim_step) dt sum_faces max(linked inflow ws_Fc, 0): ESTIMATE of the linked liquid inflow the Poisson planned that the limiter did not admit, in gas-mass units [kg]; ws_lim_step is the admitted fraction of the TOTAL transport inflow, applied here to the linked Poisson inflow (exact where ws_lim_step = 0 or 1) (WS-K7, C-144, R1) |
| `m_gas_e2_skip` | D | Steps with pc_drift_source on but no valid accepted-E2 array (ws_pc_unl_used) from this step's last Poisson [-]. It is 0 BY CONSTRUCTION while the per-cell branch runs: that branch requires ws_Fg_valid, which the same Poisson call sets after validating ws_pc_unl_used for this step; not an independent check (WS-K7, C-144, C-162) |
