# Auditoría estricta de EAF3D (12-oct-2026)

Revisión de solo lectura de todo `src/` (seis bloques en paralelo), con
verificación propia de los hallazgos críticos. Estados: **C** = confirmado
leyendo el código, **S** = sospecha (convención o magnitud por verificar).
Rutas relativas a `src/`.

## CRÍTICOS

| # | Hallazgo | Dónde | Estado |
|---|---|---|---|
| C1 | El respaldo "sin chatarra" del arco normaliza `P_rad` sobre 2 capas (`kg_scrap..kg_tip`) y lo deposita sobre 7 (`kg_tip±3`): ~3.5× la potencia radiativa directa, ~+50 MW espurios en baño plano. No lo ejercita ningún test ni B1 (<320 s). | `mod_arc_cassie_mayr.f90:219-234, 279-300` | C |
| C2 | Longitud de arco en cm usada como m (`ARC_LENGTH_GRAD = 11.5 V/cm`, `ARC_LENGTH_MIN` en m): 500 V dan 40 "m" contra un objetivo de 0.20 m. El regulador no tiene realimentación (l_a no depende de z_tip): tras el bore-in la punta baja siempre hasta `H_bowl + 0.05`. En B1 a 300 s el bore-in aún no terminó (punta a 1.4 m, `arc_length = 40`), así que es latente. `K_REGULATION` es por paso (depende de dt). | `mod_constants.f90:266-267`, `mod_arc_cassie_mayr.f90:73-74`, `mod_electrode_3d.f90:74-79` | C |

## ALTOS

### Conservación y orden de operaciones
| # | Hallazgo | Dónde | Estado |
|---|---|---|---|
| A1 | La química de escoria cambia `liq%alpha` después de copiar `liq_old%alpha`; el transporte de α rehace el paso desde `liq_old` y descarta el cambio. Oxidación: crea Fe; reducción: lo destruye. El audit (`m_fe_yield/return`) reporta transferencias que no ocurren. Afecta la configuración de producción. | `main_3d.f90:262, 333`; `mod_slag_chemistry.f90:121, 172`; `mod_continuity.f90:240` | C |
| A2 | Especies sub-relajadas contra el paso temporal (`Y = 0.5 Y* + 0.5 Yⁿ`, una vez por paso): la química consume todo el O₂ del paso pero el solver aplica la mitad del sumidero → se oxida ~2× el O₂ existente, 2× calor químico. Viola la convención de relajación. | `mod_species_transport.f90:145`; `main_3d.f90:342-347` | C |
| A3 | El colapso sobrescribe `sol%T_s`, que es la T de entrada del fundido del mismo paso: el fundido entra a la T de la mezcla con la chatarra que cae (pérdida de energía no auditada, re-solidificación espuria). | `mod_scrap_collapse.f90:110-127`; `mod_energy_3d.f90:272-274` | C |
| A4 | El colapso no tiene tope de empaquetamiento: conserva masa, no volumen aparente; con la malla estirada compacta α_s hasta ~0.9 o 1 (`min(1.0)`), desacopla m_s de α_s y permite Σα > 1 (destino con líquido < 0.3 o escoria). **Ligado al lecho ultra-denso (762 celdas α_s > 0.9) donde falla B1.** | `mod_scrap_collapse.f90:72-108`; `mod_solid_phase.f90:68-70` | C |
| A5 | La carga del cubo 2 sobrescribe celdas sin mirar líquido, escoria ni sólido residual; no audita ni intercambia halos. | `mod_fields_3d.f90:646-660`; `main_3d.f90:268-275` | C |

### Física
| # | Hallazgo | Dónde | Estado |
|---|---|---|---|
| A6 | Ergun (definido para velocidad SUPERFICIAL) aplicado a velocidad intersticial con presión ponderada por α: arrastre ×1/ε² (viscoso) y ×1/ε³ (inercial). ε=0.5: 4×/8×; ε=0.05: 400×/8000×. Afecta dos fluidos y mezcla (percolación, movilidad del gas de poro, F2.16/F2.31, F2.28). **Contribuye directamente a la impermeabilidad del piso de B1.** Forma correcta (Gidaspow): `ε²A + ε³B|u|`. | `mod_constants.f90:387-394`; `mod_drag_ergun.f90:96`; `mod_mixture_3d.f90:437-445` | C |
| A7 | Boussinesq referido a `T_ambient = 300 K`: a 1850 K el peso del acero queda ×0.81 (≈6100 kg/m³) mientras la inercia usa 7500. Hidrostática del baño 18 % baja (también en la inicialización y en G_b del k-ε); ramas dispersas usan ρ sin Boussinesq. | `mod_momentum_3d.f90:372-376`; `mod_pressure_3d.f90:676-682`; `mod_mixture_3d.f90` | C |
| A8 | La fuente de compresibilidad del gas solo tiene ∂ρ/∂t; falta `(α_g/ρ_g) u_g·∇ρ_g`. En un chorro estacionario calentado por el arco la expansión advectiva no se impone: el gas no conserva masa (dos fluidos y mezcla). | `mod_pressure_3d.f90:423-441`; `mod_mixture_3d.f90:914-924` | C (efecto S) |
| A9 | `S_arc` de convección (30 %), de electrodo (20 %) y el excedente del tope de 2 K van al gas o al líquido por fracción de volumen: en celdas del lecho el gas de poro se lleva todo (el sobrecalentamiento que F2.30 corrigió solo para el MC). | `mod_arc_cassie_mayr.f90:266-361`; `mod_energy_3d.f90:222-225` | C (magnitud S) |
| A10 | `bore_in_done` se activa al tocar la cima de la chatarra (el comentario dice "hasta el líquido") y nunca se reinicia con la 2.ª cesta. | `mod_electrode_3d.f90:61-69` | C |
| A11 | DO: líquido y escoria casi transparentes (κ = 0.3 1/m) y el tazón negro a 300 K: el baño radia en volumen hacia el refractario frío (~5 MW espurios estimados). | `mod_radiation_do.f90:99-140` | C (magnitud S) |
| A12 | h gas–sólido sobre 1373 K → 0 con gas quieto (sin piso Nu = 2) y discontinuo en 1373 K (×2.4–8.6): gas de poro estancado sin acople térmico. | `mod_interphase_ht.f90:71-77` | C |
| A13 | k-ε avanza un Δt por iteración externa (`tke_old = sh%tke` dentro del lazo): hasta `max_outer`× más rápido. Residuales de k-ε nunca calculados; `tol_turb` muerto y sin clave. | `mod_turbulence_3d.f90:77-78`; `main_3d.f90:375, 436` | C |

### Numérica y MPI
| # | Hallazgo | Dónde | Estado |
|---|---|---|---|
| A14 | Escoria dependiente de la descomposición en z: la flotación no cruza el tope del subdominio; el intercambio de calor y la química no actúan en la primera capa de cada rank; en la reducción el Fe se pierde en frontera de rank, en k = 1 o sobre pared. | `mod_slag_3d.f90:332, 442`; `mod_slag_chemistry.f90:91, 170` | C |
| A15 | Fila de relleno del eje (`aP_ur(1) = 1`) usada como coeficiente real en el Poisson y en F2.31: conductancia dimensionalmente incorrecta en la cara 1–2 en todo el eje. | `mod_boundary_3d.f90:127-136`; `mod_pressure_3d.f90:795` | C |
| A16 | Corrector por defecto con estencil central crudo: lee pp = 0 de celdas sin fluido o del tazón (no Neumann), inconsistente con predictor y Rhie-Chow. | `mod_pressure_3d.f90:1371-1396` | C |
| A17 | Máscaras de pared distintas entre el predictor (`ws_pv_active`) y el Poisson (`act_l/act_g` tras F2.21/F2.31/E1b): flujos de cara espurios junto a las celdas F2.31, justo en el piso del lecho. | `mod_momentum_3d.f90:484-494`; `mod_pressure_3d.f90:186-309, 719-725` | C |
| A18 | Mezcla: el intercambio gas–líquido se aplica después de la relajación: el punto fijo depende de α_T (transfiere q/α) y el audit registra q. | `mod_mixture_3d.f90:236-242, 1130-1140` | C |

## MEDIOS

| # | Hallazgo | Dónde | Estado |
|---|---|---|---|
| M1 | Reinicio no bit a bit: `alpha_foam` no se lee (la DO del primer paso ve espuma 0). | `mod_restart.f90`; `mod_radiation_do.f90:104` | C |
| M2 | Reinicio no bit a bit: `ws_liq_cont_prev` no persiste (tras reiniciar no se detectan transiciones disperso→continuo, el mecanismo de MPa de Bug 15). | `mod_multiphase.f90:110, 482` | C |
| M3 | Reinicio: `m_ecs_pending` (save) no persiste. | `mod_ecs_feed.f90:47` | C |
| M4 | Reiniciar en el mismo `output_dir` trunca el snapshot de origen (fuentes en cero) y reemplaza `audit.csv`. | `main_3d.f90:231`; `mod_audit.f90:140` | C |
| M5 | Hook de auditoría de energía sobre la T sin relajar y con halos del TDMA sin intercambiar: identidad dependiente de la descomposición y de pasos no convergidos. | `mod_energy_3d.f90:316-323`; `mod_solver_3d.f90:359-366` | C |
| M6 | Interfase: el tope `min(Q, C_f ΔT/dt, C_s ΔT/dt)` rebasa el equilibrio; Q_gs y Q_ls recortados por separado pueden llevar T_s por encima de ambos fluidos. | `mod_interphase_ht.f90:87-110` | C |
| M7 | Área del sólido contada dos veces (gas y líquido usan `6α_s/d` completo). | `mod_interphase_ht.f90:62, 82, 98` | C |
| M8 | Flotación del k-ε con signo invertido (estratificación estable produce turbulencia). | `mod_turbulence_3d.f90:132-133` | C |
| M9 | Fusión y re-solidificación como fracción por paso: tasas ∝ 1/Δt; denominador sin sentido físico. Histéresis de 209 K (funde ≥ T_liq, congela < T_sol). | `mod_melting_3d.f90:165-203` | C |
| M10 | El cierre residual de un sólido frío crea líquido subenfriado (300 K → 587 K) que re-solidifica: vaivén; con ECS puede convertir la carga en "líquido". | `mod_melting_3d.f90:231-247` | C |
| M11 | Lorentz: signo invertido (debe ser pinch hacia el eje), fuerza irrotacional (no agita), aplicada también al gas (doble conteo) y a la niebla del freeboard. | `mod_lorentz_3d.f90:96-111`; `mod_momentum_3d.f90:310-336` | C |
| M12 | MC del arco: impacto en líquido por sustituto geométrico (z < H_bowl + 0.5), sin atenuación del gas ni de la espuma, emisión puntual sin sombra. | `mod_arc_radiation_mc.f90:107-176` | C |
| M13 | Tope de depósito `DT_RAD_MAX = 2 K/paso`: depende de dt; el exceso va al gas de poro. | `mod_arc_cassie_mayr.f90:135, 260`; `mod_arc_radiation_mc.f90:74` | C |
| M14 | Fuentes de especies fuera de la continuidad del gas; ΣY puede superar 1 (aire → CO: 1.17); masas de especies sin auditar. | `mod_species_transport.f90`; `mod_properties_3d.f90:37` | C |
| M15 | Carbono oxidado no se resta de `m_s` ni `E_s` (contado dos veces, hasta ~650 kg). | `mod_chemistry_carbon.f90:106-107` | C |
| M16 | Difusión de especies no telescopa (α·ρ·D de la celda P, no de cara) y la celda sin gas entrega Y rancia. | `mod_species_transport.f90:79-115` | C |
| M17 | La escoria nunca desciende: queda suspendida en el freeboard tras fundirse la chatarra, intercepta el arco y bloquea capacidad. | `mod_slag_3d.f90:87, 332-338` | C |
| M18 | La escoria puede entrar en celdas llenas de chatarra (`avail_above` ignora α_s) → Σα > 1. `alpha_sl` no se actualiza cuando cambia `m_sl`. | `mod_slag_3d.f90:343-344, 286` | C |
| M19 | Fe reducido entra al baño a la T rancia de la celda y sin tope de volumen; datums de entalpía distintos entre líquido (C0) y escoria (0 K). | `mod_slag_chemistry.f90:119-177` | C |
| M20 | Intercambio escoria–fluido explícito inestable con masas de escoria pequeñas. `alpha_foam` rancia en celdas sin escoria (absorbe radiación que nadie recibe). | `mod_slag_3d.f90:443-466`; `mod_slag_chemistry.f90:84, 212` | C/S |
| M21 | Química activa sin transporte de especies: O₂ infinito (~690 MW/m³); la combinación no se valida. | `mod_chemistry_carbon.f90`; `mod_config_3d.f90` | C |
| M22 | `sealed` no se intercambia en halos: el Neumann de F2.29 depende de la descomposición. | `mod_pressure_3d.f90:472, 735` | C |
| M23 | Paredes en deslizamiento libre (no hay esfuerzo de pared) aunque la CC dice "no-slip". | `mod_boundary_3d.f90:142-156` | C |
| M24 | Convección de momento con flujos reconstruidos de centro (no los conservativos del Poisson) y aP acotado sin ΔF: fuente ficticia de momento. | `mod_momentum_3d.f90:275-391` | C |
| M25 | Término acústico y `PP_COMPLIANCE` solo en la diagonal de pp, sin `(p^k − pⁿ)`: es seudo-compresibilidad, no compresión física (también en la mezcla y en `pc_gas_spring`). | `mod_pressure_3d.f90:484-517`; `mod_mixture_3d.f90:917` | C |
| M26 | El exceso recortado por `COMP_SRC_CAP` se pierde (el comentario dice que se re-emite). | `mod_pressure_3d.f90:416-436` | C |
| M27 | Faltan los términos viscosos cilíndricos del laplaciano vectorial (u_r/r², ∂u_θ/∂θ). | `mod_momentum_3d.f90:303-378` | C |
| M28 | Superficie libre por defecto con gradiente central a través de la celda de gas (corriente fantasma documentada en el propio código). | `mod_momentum_3d.f90:363-366` | C |
| M29 | Ergun del gas con ε = 1 − α_s, sin el líquido del poro (sin permeabilidad relativa). | `mod_drag_ergun.f90:62` | S |
| M30 | Transitorio de momento con αᵏ (no la forma α^n de la energía). PEA solo en momento, no en los coeficientes del Poisson. | `mod_momentum_3d.f90:193`; `mod_multiphase.f90:513` | S |
| M31 | El eje es una pared en r = 0.02 m (sin flujo a través del eje). | `mod_mesh_3d.f90:77, 246` | C (diseño) |
| M32 | Descomposición real 2×3×2 para 12 ranks (r SÍ se descompone), contra CLAUDE.md y RUNNING.md; sin validar tamaño local ≥ 2 ni divisibilidad en z. | `mod_mpi_topology.f90:157-232` | C |
| M33 | `monitor.log` nunca se escribe (`write_monitor_line` sin llamar) aunque la documentación lo usa. | `mod_output_hdf5.f90:533`; `main_3d.f90:520` | C |
| M34 | Reinicio heredado: `allocate(xdiag, mold=...)` sin inicializar y copiado entero (patrón Bug 22). | `mod_restart.f90:188-197` | C |
| M35 | Mezcla: velocidad normal a pared y piso nunca corregida (solo debería saltarse el eje). | `mod_mixture_3d.f90:983-990` | C |
| M36 | Mezcla: flujos de energía del gas no son el complemento de Q (no conservativos). | `mod_mixture_3d.f90:238`; `mod_energy_3d.f90:165` | C |
| M37 | Mezcla: deslizamiento con W de centro de la celda de arriba, no Godunov de Buckley–Leverett (estrato saturado sobre seco no drena). | `mod_continuity.f90:635` | S |
| M38 | ECS ignora el baño al definir la superficie: con baño > 4 celdas en la banda, todo queda pendiente. | `mod_ecs_feed.f90:78-91` | S |
| M39 | `K_GAS = 0.5` (Pr ≈ 0.1, ~5× la del N₂) y h líquido–sólido Nu = 6 constante (~1.8 kW/m²K frente a 5–20 de la literatura). | `mod_constants.f90:41`; `mod_interphase_ht.f90:94` | S |

## BAJOS (resumen)

- Desborde de arreglos con perfiles de más de 10 000 puntos o capas (`mod_input_profiles.f90:60, 103, 216`).
- Perfil de electrodos ausente → 500 V / 50 kA silencioso e impreso por todos los ranks.
- Arco repartido a la escoria por fracción de volumen (contra F2.30).
- Cinética de Maahs nunca limitante; P_O₂ con 101 325 Pa fijos.
- `S_chem` calienta también al líquido (el comentario dice "al gas").
- Cassie–Mayr: código muerto y dimensionalmente incorrecto (R no se usa).
- Semilla del RNG del MC desborda int32 desde ~271 000 pasos.
- Eje como pared negra en la DO, pero el MC lo cruza.
- DO sin aviso de no convergencia; CG sin aviso al agotar iteraciones.
- Umbrales de "chatarra" incoherentes (0.01 / 0.05 / 0.1) y κ duplicadas.
- AC sin desfase entre electrodos (aceptable si se documenta).
- `fs_shear` y `Kexch` leen halos físicos y celdas del tazón.
- Errores de re-solidificación y de cierre residual pequeños no auditados.
- `enforce_volume_constraint` crea o destruye gas sin auditar.
- ρ_g discontinua en `T_MIN_GAS` y referida a `T_ambient`.
- k-ε sin tratamiento de pared ni tope de μ_t.
- Recortes `T_sl ≥ 300` sin ajustar E_sl.
- Freno de NaN sin `gas%uth`, k, ε, Y, escoria; `check_convergence` da por convergido un residual NaN.
- El lazo temporal rebasa `t_final`; `should_print` lee `is_parallel` sin definir; prints desde todos los ranks.
- Mezcla:
  - topes de velocidad tras `phase_velocities` rompen la identidad de mezcla;
  - predicado local antes de llamadas colectivas (`all(Tg_end<0)`);
  - equilibrio de arranque sin auditar;
  - halos rancios de `vth` en el primer outer;
  - `mass_o` mezcla instantes;
  - CFL de mezcla no garantiza monotonía si ffrac > s;
  - derrame corre 128 pasadas en vano;
  - media aritmética de D en caras lecho/libre;
  - código muerto de `MIX_DROPLETS`, `dispc`, `with_g = .false.`.
- Configuración:
  - claves sin efecto (`emissivity`, `k_s`, `k_slag`, `R_outlet`, `T_liq_hbi`, `ecs_mode`, `ecs_k_power`, `ecs_total_mass`);
  - faltan validaciones (stretch = 0, geometría, dt en rango).
- Documentación desalineada:
  - PHYSICS.md §6–9, §11, §15;
  - cabeceras de `mod_pressure_3d`, `mod_drag_ergun`, `mod_solver_3d`;
  - CLAUDE.md (r no descompuesto, claves desconocidas silenciosas, percolación "~2 mm/s").
- Código muerto: SOR, TDMA serial, `ws_pcorr_g`, constantes sin uso, `compute_ergun_drag` redundante en `main`.

## Verificado sin defecto (resumen)

- Estequiometría, masas molares y entalpías de reacción.
- Cuadraturas S4/S6/S8 y proyecciones exactas de la DO.
- Simetría de la matriz del Poisson y CG/TDMA MPI.
- Métricas cilíndricas y costura θ; colectividad PHDF5.
- Linearización de Newton de la radiación.
- Forma acotada con α^n del líquido y conversiones E↔T.
- Buckley–Leverett de la mezcla y simetría/unidades de su Poisson.
- Reinicio de la mezcla (`Tg_end`).

## Resolución (completada el 13-oct-2026, en orden de severidad)

Cada pieza es un commit que pasa `make test-quick`; los goldens se
rebaselinean solo cuando cambia la numérica (versión indicada).

| Hallazgo | Commit | Golden | Verificación |
|---|---|---|---|
| C1 | d8a645a | — | `arc_noscrap` (arco sin chatarra) |
| C2 | 8c64682 | — | regulador con l_a en m (1150 V/m) |
| A1 | 0a1f777 | — | `slag_chem_flow`, invarianza n1/n8 |
| A2 | a8e5b2e | — | especies sin relajación |
| A3 | 8713d98 | — | defecto latente (0 casos en 100 pasos de B1) |
| A4 | 52affbb | v38 | `test_scrap_collapse` (0.71 → ≤ 0.55) |
| A5 | e08f957 | v38 | `cold_bucket2`: error de energía 0.998 → 4e-5 |
| A6 | 1f6e3ee | v39 | `test_ergun` con valores a mano |
| A7 | 5309bf2 | v40 | `test_poisson_bath`, `check_bath.py` |
| A8 | fa3c2e9 | v41 | `bed_flood:bath_pv_bounded` sale de xfail |
| A9, M13 | 3799a70 | v42 | tope de estado en vez de 2 K/paso |
| A10 | 9b2eeab | v43 | `arc_noscrap` sale de xfail |
| A11 | 0a594e9 | v44 | equilibrio isotermo de la DO |
| A12 | 0a92029 | v45 | h_gs = max(Wakao, alta T) |
| A13 | b892a57 | — | k-ε con ancla temporal |
| A14, M17, M18, M20 | 070f90f | v46 | `decomposition_slag` 3e-14 |
| A15 | b49aa3f | v47 | aP del eje físico |
| A16 | 747ac36 | v48 | corrector con `pgrad` |
| A17 | f08257c | — | bit a bit |
| A18 | 25ad37b | — | orden de la energía de mezcla |
| M1–M4, M34 | 7f46baf | — | reinicios bit a bit; reanudar en el mismo directorio conserva el snapshot de origen y el audit previo (`audit_prev_<paso>.csv`) |
| M5 | 98e5e9f | — | hook sobre el campo relajado con halos frescos; balances: cold_10step 1.51 → 1.39 %, melt_forced 3.0e-6 → 1.6e-6, arc_noscrap 1.72 → 2.43 % (residuo del lazo externo, ahora visible) |
| M6, M7 | 88f652d | v49 | paso implícito exacto de tres nodos (gas, líquido, sólido) y área del sólido repartida por fracción de poro; `test_interphase` (sin rebase, conservativo, área no duplicada) |
| M8 | b021255 | — | signo G_b = −β g (μ_t/Pr_t) ∂T/∂z. Sin efecto en la matriz: ningún caso combina k-ε con líquido (cobertura pendiente) |
| M9, M10 | 60dba64 | v50 | regla de la palanca (fusión y congelación como estados); el remanente frío no se cierra; `test_residual_closure` casos 1, 6 y 7; melt_forced: balance 2e-5 → 1.3e-7 |
| M11 | cbf4e3f | v51 | fuente puntual de corriente (Shercliff 1970, Sozou 1971) anclada en la superficie del baño: pinch hacia el eje y hacia abajo, rotacional, solo líquido continuo y solo en la ecuación del líquido; `F_lorentz_z` nuevo; `test_lorentz`. Magnitud 10²–10³ N/m³ cerca del electrodo |
| M12 | 77fc75e | v52 | MC: impacto en el baño por α_l, atenuación Beer–Lambert del gas, emisión a lo largo de la columna del arco, sombra de los electrodos; arc_budget 1.0000 en todos los casos con flujo |
| M14, M15, M16 | 72bf1c4 | v53 | carbono oxidado sale de `m_s`/`E_s` (`m_C_oxid`); dilución −Y_k·S_gas en especies y fuente de volumen S_gas/ρ_g en el Poisson (`m_dil_*`); difusión de cara armónica y sin entrada desde celdas sin gas. `check_chem` usaba ρ = 1.2·300/T en vez de la EOS del código (3× en chem_test): ahora O 3e-12, C 9e-11, ΣY ≤ 1 |
| M19 | — | — | sin cambio de código: la T rancia la resolvió A1 (`add_fe` mezcla entalpías); el sobrellenado lo absorbe el derrame conservativo (slag_chem_flow: clip 0, derrame 2 g); los datums son neutros en el ciclo oxidación–reducción (el Fe sale y vuelve con e_l = cp_l T + C0) |
| M21, M22 | 8e6ac71 | v54 | `config_validate` exige `solve_species` con `solve_chemistry`; `sealed` intercambiado en halos; la astilla de redondeo de `init_heel` (α_l ~ 4e-18 con T = heel_T según la descomposición) se corta. bath_freeze n1 vs n4: α_l 9.7 % → 9e-6, presión 1.6 % → 9e-5, peor campo 2.7e-4; nuevo `decomposition_freeze` en la matriz |
| M23 | f435df7 | v55 | no deslizamiento: conductancia de media celda α μ A/(δ/2) en la diagonal de las componentes tangenciales junto a toda pared (tazón, coraza, piso, techo); el eje sigue como simetría. Solo el modelo de dos fluidos (la mezcla va con M35) |
| M24 (líquido), M30 (transitorio) | 0f4eb51 | v56 | momento del líquido continuo con los flujos conservativos del transporte de α y transitorio con α^n (forma exacta con la continuidad restada, como la energía); la masa fundida entra con u = 0. Flujos válidos dentro del paso (desde la 2.ª iteración externa): el reinicio sigue bit a bit. Nota: bed_flood p_max 164 → 247 kPa y gas 208 → 249 m/s a lo largo de M6, M9 y M12 (más fundido por la regla de la palanca; 0.53 de 3× ferrostática) |
| M24 (gas) | rama `m24-gas-intento` (ee0e96e) | — | IMPLEMENTADO Y MEDIDO NEGATIVO (13-oct-2026), no integrado. El Poisson exporta los flujos de masa conservativos del gas (Q* + a Δpp por la densidad del dador) y el momento del gas los usa con transitorio (αρ)ⁿ. Mejora `bath_fill` (gas 110 → 95 m/s) y `bed_flood` (226 → 196 m/s), pero rompe dos gates duros: `bath_test` (gas 24 → 52 m/s, `bath_alpha_frozen` 0 → 0.09) y `decomposition_bath` (n1/n4 0.8). Mecanismo (sonda `[PROBE-MOM]` en la celda de gas sobre la superficie libre): la presión dinámica del modo par–impar del líquido de la celda de abajo (xfail `bath_rest`) empuja al gas; la fuerza de presión sube de 0.4 a 18 N dentro del primer paso CON Y SIN M24. Con la interpolación simétrica lo frena el caudal fantasma ½αρu de la cara inferior (a_nb 0.39 frente a 0.015): es el mismo término de F2.24, aquí como amortiguador. Con el flujo conservativo (sin fantasma) el modo queda libre. Requisito para integrarlo: eliminar el modo par–impar del líquido en la superficie (corrección de Choi/Majumdar del Rhie–Chow, ARCHITECTURE F1b) o un tratamiento de fuerzas balanceadas del gas en la superficie libre |
| M25 | (este commit) | v68 | COMPRESIÓN FÍSICA del gas: EOS única `gas_eos` = ρ_ref (T_ref/T)(P0 + p)/P0 (piso 0.05 P0); la fuente de compresibilidad usa ρ(P0 + pⁿ, Tⁿ) (`ws_p_n`, copia de p al inicio del paso) y contiene (p^k − pⁿ); la diagonal α_g/(P0 + p) V/Δt es su linealización de Newton; la advectiva (A8) toma la densidad con presión. P_O₂ con la presión absoluta; inventario del gas del audit con (P0 + p)/P0; `check_chem` con la misma EOS. Medido: el lazo externo converge ANTES (cold_10step 22–23 iteraciones frente a 36–40) y con el lazo convergido el balance cierra a 2.5e-7 por paso (antes 4.9e-6); con max_outer = 5 el encendido queda en 1.01 % (xfail repuesto con esa causa); arc_noscrap 1.4–2.4 % → 0.16 % (xfail retirado); bed_flood p_max 223 → 179 kPa. El modelo de MEZCLA queda low-Mach (con la compresión física su baño en reposo crece ×10 por paso: el gas es el complemento sin masa propia) |
| M26 | f74a7e9 | v57 | demanda de volumen del gas (térmica + advectiva + reacciones) con UN tope y acarreo del exceso al paso siguiente (`ws_cc`, en el snapshot de reinicio). cold_10step: balance 1.25 % → 0.75 %, sale de xfail |
| M27 | 1eaab70 | v58 | laplaciano vectorial cilíndrico: −μu_r/r² y −μu_θ/r² implícitos, ∓(2μ/r²)∂u_{θ,r}/∂θ explícitos |
| M28 | — | — | PENDIENTE con causa: la alternativa local ya existe y se midió (D2.5, `pc_fs_liquid_gradient`: cara de superficie libre unilateral) y se cerró NEGATIVA en el juez B1 (Plan D, 10-oct-2026). Lo que falta es el acople implícito α–p (NEPTUNE_CFD, Liles & Reed), no otra regla local |
| M29 | fb68144 | v59 | Ergun del gas con el líquido retenido como obstáculo (ε_g = 1 − α_s − α_l en celdas del lecho; Sáez & Carbonell 1985, Attou et al. 1999). Efecto acotado en los bancos (bath_freeze p_max 69.9 → 67.7 kPa) |
| M30 (PEA en el Poisson) | e22653b | v60 | el PEA deja en `aP_*` el coeficiente equivalente α V/d con la respuesta acoplada d_l = V(α_l a_g + KVα_g)/det (Karema & Lo 1999): Poisson y corrector ven la respuesta de la mezcla cuando K es grande. bed_flood p_max 247 → 232 kPa |
| M31 | (este commit) | v67 | EJE REAL: `R_AXIS_MIN` = 0, la cara del eje tiene área nula y las celdas del primer anillo son cuñas que se tocan en el eje (exacto en volumen finito: ninguna masa atraviesa una línea; el flujo que cruza el eje pasa por las caras θ del anillo). Se retira el pasador sólido de 4 cm y la reflexión del MC en él (el trazado cartesiano cruza el eje). Los gradientes de centro del primer anillo siguen siendo unilaterales hacia el eje (sin halo diametral). Bancos acotados: bed_flood p_max 232 → 223 kPa, bath_rest 0.22 m/s (xfail), simetría 120° e invarianza MPI intactas |
| M32, M33 | a1c107f | — | validación al arrancar: cada bloque local ≥ 2 celdas por dirección (aborta con mensaje); RUNNING.md §3 y CLAUDE.md con la descomposición real r×θ×z; `monitor.log` se escribe cada `monitor_freq` (la rutina tenía además un formato roto que nunca se había ejecutado) |
| M35, M36, M37 | b720f73 | — | mezcla: velocidad de celda reconstruida también junto a coraza/piso/techo (solo el eje fuera); energía del gas con el complemento Q − Q_l del flujo de mezcla; deslizamiento del lecho con flujo de Godunov de Buckley–Leverett. Banco `bath_fill` en mezcla (n4, 0.5 s): p_max 220 → 136 kPa, gas 287 → 77 m/s; baño en reposo igual. La matriz no tiene casos de mezcla (bit a bit en dos fluidos) |
| M38 (+ hallazgo nuevo) | 77b2a32 | v61 | el tope del baño es superficie para la carga ECS. HALLAZGO NUEVO, más grave: `ecs_feed` suponía r sin descomponer (índice radial local = global); con 12 ranks (2×3×2) la carga NO se depositaba (0 de 300 kg en ecs_test). Índices globales; `decomposition_ecs_r` (n12 vs n1: 4e-16) en la matriz. CONFIGURATION.md corregido |
| M39 | 0c9fb6d | v62 | Wakao con conductividad MOLECULAR k = μ c_p/0.7 (antes cfg%k_gas = 0.5: Pr 0.1, h ~4× la literatura); líquido–sólido con Ranz–Marshall real Nu = 2 + 0.6 Re^½ Pr^⅓ y la velocidad del líquido (antes Nu = 6 fijo). `k_gas` queda como conductividad efectiva de la difusión del gas. Cambia la cinética de fusión: B1 debe re-juzgarse |
| B1, B2 (perfiles) | 68aca2f | — | lectores de perfil y receta sin desborde (se trunca con aviso al máximo); clave `electrode_profile_file` (default el archivo de siempre; `''` = constante `elec_V_const`/`elec_I_const`); archivo configurado que no abre = error fatal; mensajes solo de rank 0. Bit a bit |
| B3, B10 (arco a escoria, umbrales y κ) | ba68bb0 | — | `slag_intercept_arc` reparte por absorción (κ_sl α_sl + κ_foam α_foam frente a κ_l α_l + κ_g α_g; incluye la espuma); κ con una sola definición en `mod_constants` (la DO tenía copias); `ALPHA_SCRAP_SURF` = 0.05 único para la superficie de chatarra (electrodos, ECS, MC, depósito directo). Sin cambio en la matriz |
| B4–B8 (química, arco, RNG, eje en el MC) | 92e384c | v63 | `S_chem` (combustión CO → CO₂ en fase gas) solo al gas; P_O₂ con la masa molar de la mezcla real O₂/CO/CO₂/N₂ (la cinética de Maahs sigue limitada por el suministro de O₂: comportamiento documentado); EDO de Cassie–Mayr retirada (R muerta y P_rad·R incoherente), `arc_R` = V/I diagnóstico; semilla del MC en 64 bits mod 2³¹−1; reflexión especular del rayo en el pasador del eje (coherente con la pared re-irradiante de la DO) |
| B9, B18, B19 (avisos, NaN, lazo temporal) | f192ad7 | v64 | avisos acotados (primero y cada 1000) cuando la DO o el CG agotan iteraciones; el freno de NaN barre también u_θ del gas, k, ε, especies y escoria; `check_convergence` no da por convergido ningún residual no finito (antes solo miraba res_cont); el último paso termina exactamente en t_final (cold_10step corría 11 pasos por redondeo); `should_print` usa el rank de la topología (se llamaba antes de definir `is_parallel`) |
| B19 (prints por rank) | a779258 | — | MPI se inicializa antes de leer el config y los mensajes de lectura/validación salen solo de rank 0 (antes uno por rank); `mpi_init_topology` inicializa MPI solo si hace falta. Bit a bit |
| B12, B14, B15 (halos, volumen, EOS) | 18de789 | v65 | `fs_shear` con diferencias unilaterales junto a celdas inactivas y α_s de abajo solo si existe (antes leía halos físicos y el tazón); columna `m_gas_volfix` para el gas que crea/destruye la restricción de volumen; EOS del gas continua en `T_MIN_GAS` y referida a 300 K (`T_RHO_GAS_REF`), no a `T_ambient` (chem_test tenía aire de 1.2 kg/m³ a 900 K), y el campo inicial con la misma EOS. `check_slag_chem` con la tolerancia de la resolución del CSV. Los errores pequeños de cierre residual (masas < 1e-9 de m_min, energía < 1e-20 J) quedan documentados como despreciables |
| B16, B17 (k-ε de pared, piso de escoria) | cf69bf0 | — | función de pared de Launder–Spalding para ε en celdas de líquido continuo junto a pared y tope μ_t/μ ≤ 1e5; piso T_sl ≥ 300 K con E_sl coherente y energía auditada (`E_slag_tclip`, en la identidad del balance). Colateral: el formato de la fila del audit admitía 60 pares y la columna 38 partía la fila en dos líneas; ahora 100. Sin cambio en la matriz (no hay casos k-ε con líquido) |
| B20 (mezcla) | ef97106 | v66 | decisión global del equilibrio de arranque (antes predicado local antes de colectivas) y su energía auditada (`E_mix_init`); topes de fase que conservan el flujo de mezcla; halos de v tras `mixture_state`; `mass_o` con las densidades del paso anterior (y `*_old%rho` ahora se copia: la omisión rompía la mezcla, encontrada por bisección); CFL con ffrac/s; derrame sale sin progreso posible; μ de cara armónica; código muerto de gotas (`MIX_DROPLETS`, `dsp`, `Kd`, `fdw`, `ws_mFd`, `dispc`, `with_g`) retirado. `bath_mix` y `bath_fill_mix` en la matriz (bath_fill en mezcla: 178 kPa, gas 76 m/s; hidrostática 2e-15) |
| B11, B21, B22, B23 (config, docs, código muerto) | ef97106 | — | aviso por cada clave sin efecto (`k_s`, `emissivity`, `arc_w`, `k_slag`, `ecs_*`), `ecs_mode = 'coupled'` rechazado (no implementado); validación de estiramiento, geometría y dt (con paso adaptativo); PHYSICS.md §4, §6–16 reescritas al código actual y AC sin desfase documentada; cabeceras de `mod_pressure_3d`, `mod_drag_ergun`, `mod_solver_3d`; CLAUDE.md (avisos del config); retirados SOR (serie y MPI), TDMA 3D serie, residual serie, `ws_pcorr_g`, constantes sin uso y el Ergun redundante de `main`. Bit a bit |

### Pendientes con causa (no resueltos por decisión o por evidencia)

- **M24, parte del gas.** Implementado y medido negativo (rama
  `m24-gas-intento`): el flujo conservativo deja libre el modo de la celda de
  gas sobre la superficie libre que hoy frena el caudal fantasma de la
  interpolación simétrica. Depende de eliminar antes el modo par–impar del
  líquido (Choi/Majumdar) o de fuerzas balanceadas del gas en la superficie.
- **M28.** La alternativa local (cara de superficie libre unilateral, D2.5)
  ya se cerró negativa en el juez B1; lo que falta es el acople implícito α–p.

### Hallazgos nuevos durante la resolución

- `ecs_feed` suponía r sin descomponer: con 12 ranks no depositaba la carga
  (M38).
- `init_heel` dejaba una astilla de redondeo con T = heel_T según la
  descomposición (M22).
- `*_old%rho` nunca se copiaba al inicio del paso (lo destapó B20 en la mezcla).
- `gas%rho` inicial no seguía la EOS; `check_chem` usaba otra densidad.
- La fila del audit se partía al pasar de 60 pares de columnas.
- El lazo temporal daba un paso de más por redondeo (cold_10step corría 11).
- `monitor.log` tenía un formato roto que nunca se había ejecutado.

### Consecuencia para B1

Varias piezas cambian la física de forma apreciable (regla de la palanca M9,
Lorentz M11, MC M12, interfase M6/M7/M39, carbono M15, densidad del gas de
referencia, química al gas). El juez estadístico previo de B1 deja de ser
representativo: hay que volver a juzgar B1 desde el inicio con el código
actual antes de sacar conclusiones sobre el colapso de ~320 s.
