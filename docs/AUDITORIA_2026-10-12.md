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

## Resolución (en curso, en orden de severidad)

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
| M8 | (este commit) | — | signo G_b = −β g (μ_t/Pr_t) ∂T/∂z. Sin efecto en la matriz: ningún caso combina k-ε con líquido (cobertura pendiente) |
