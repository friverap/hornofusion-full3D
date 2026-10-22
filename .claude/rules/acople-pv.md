---
paths:
  - "src/mod_pressure_3d.f90"
  - "src/mod_momentum_3d.f90"
  - "src/mod_multiphase.f90"
  - "src/mod_mixture_3d.f90"
  - "src/mod_drag_ergun.f90"
  - "src/mod_workspace.f90"
  - "src/mod_face_flux.f90"
  - "src/mod_boundary_3d.f90"
  - "src/mod_constants.f90"
  - "src/mod_turbulence_3d.f90"
  - "src/mod_convergence_3d.f90"
  - "input/**"
  - "campaigns/**"
---

# Acople presion-velocidad, momento, multifase, lecho y gas (Bug 15-21, F2.x, Planes C-G)

Convenciones vigentes movidas TEXTUALMENTE desde CLAUDE.md (reestructuracion
harness, 16-oct-2026). Cada una existe por un fallo medido: no simplificar una
guarda sin leer su causa.

- **ALPHA_FLOW_CUTOFF (1e-2)**: umbral hidrodinámico — fases por debajo no
  participan del acople momentum–presión. ALPHA_CUTOFF (1e-6) sigue para
  energía/especies/fusión. **El líquido bajo el umbral NO tiene velocidad
  nula en el transporte de α (sep-2026, Bug 14)**: se mueve con el gas más
  la velocidad terminal de sedimentación `settling_velocity(d_droplet)`
  (deslizamiento algebraico, Manninen 1996). Poner su velocidad a 0 dejaba
  3.6 t de niebla suspendida en B1 v11. `d_droplet = 0` recupera el
  comportamiento antiguo sólo para comparar.
- **ALPHA_LIQ_CONT (0.3, Bug 15)**: fuera del lecho el líquido es fase
  CONTINUA (momento propio + Poisson) sólo con α_l ≥ 0.3; por debajo es
  dispersa: drift-flux y FUERA del Poisson (`liq_continuous`,
  `ws_liq_cont`). Una fase dispersa nunca impone restricciones de volumen
  al acople P-V: gotas a 20 m/s en el Poisson exigían MPa, el gas vecino
  saltaba a km/s y p saturaba en `P_HYDRO_CAP` en todo el horno (B1 v11
  415 s / v12 450 s — los "cave-ins" eran esto). El audit tiene `p_max`,
  `u_gas_max`, `u_liq_max`: un blow-up P-V conserva masa y energía, sólo
  esas columnas lo delatan. El disperso lleva drift CON relajación de
  partícula (τ_p = u_t/g, desde `liq_old`) y arrastre físico
  `K = α_l Δρ g/u_t`: el ajuste instantáneo dejaba al gas sin la inercia
  de la niebla (melt_forced 300 kPa); en el lecho percola a √(2 g d_p)
  sin montar en el gas; al volverse continua, la celda hereda la
  velocidad de las vecinas continuas (`reset_new_continuous`). El gas
  usa SU Ergun (`drag_gas`, ρ_g/μ_g/|v_g|): con el del líquido (ρ_l=7500,
  |v_l|) el gas quedaba congelado donde el disperso percolaba y el Poisson
  perdía sus caminos (B1 v13, 5.5 s). El k-ε sólo actúa en líquido
  continuo (producción, convección, μ_t).
- **Presión**: CG precondicionado (`cg_3d_mpi`); la matriz debe mantenerse
  simétrica (coeficientes de cara + Dirichlet plegados). No volver a SOR ω=1.5.
  **Una celda sin fase continua no tiene presión de fluido (Bug 16)**: su
  `pp` es 0 y su `p` quedaría congelada para siempre, así que es PARED para
  todo gradiente de presión (`pgrad` + máscara `ws_pv_active`, tanto en
  momento como en el Rhie-Chow del Poisson) y recibe el Neumann de sus
  vecinas tras cada corrección. Nunca leer `sh%p` de una celda sin fluido.
- **Velocidad de una fase dispersa (Bug 17)**: es el ESTADO ESTACIONARIO de
  la ecuación de momento que se le sustituye — arrastre del gas en el
  freeboard (`settling_velocity`), arrastre de Ergun en el lecho
  (`percolation_velocity`; ~0.1 m/s con ε = 0.5 tras A6). Nunca una estimación aparte: √(2 g d_p)
  daba 700× de más y drenaba el primer fundido de la zona caliente.
- **Acople P-V del gas ACTIVO (low-Mach, cierre 2026)**: el gas participa del
  Poisson de mezcla con fuente de compresibilidad acotada (`COMP_SRC_CAP`) y
  compliance diagonal simétrica (sin ancla big-coefficient — rompía la
  simetría 120°). **COMPRESIÓN FÍSICA (auditoría M25, oct-2026)**: EOS única
  `gas_eos` = ρ(P0 + p, T) (nunca reescribir `1.2·300/T` a mano); la fuente
  temporal va contra ρ(P0 + pⁿ, T_ref) (`ws_p_n`) y la diagonal
  `α/(P0 + p)·V/dt` es su linealización de Newton (antes era
  seudo-compresibilidad). **T_ref = `sh%Tg_end`, la T del gas al FINAL del
  SIMPLE anterior (auditoría 3, A3-3; estado del reinicio), NO `gas_old%T`**:
  entre ambas están la interfase gas–sólido y el intercambio gas–líquido,
  que calientan el gas después del Poisson; medida contra `gas_old%T` esa
  expansión no pasaba por ningún Poisson (la EOS reescribía la masa del gas
  sin fuente de volumen: el mecanismo de F2.13, que Plan G ya corregía con
  `Tg_end`). Consecuencia: un gas FRÍO sobre un baño caliente ya no es un
  estado de reposo (se calienta y expande: 10 m/s sobre la superficie en
  bath_test; el banco arranca ahora en equilibrio térmico, `T_ambient` =
  `heel_T`); bath_freeze tiene un transitorio de arranque de 138 kPa en
  0.02–0.12 s (gas a 300 K atrapado en el baño a 1630 K) y bed_flood (xfail)
  toca `U_GAS_MAX` a 1.17 s (xfail con causa). Sin `Tg_end` (arranque,
  snapshot viejo) se usa `gas_old%T`. **El gas de PISO de un poro SATURADO
  no pide volumen al calentarse**: `ALPHA_PORE_GAS` es un canal hidráulico
  (F2.7), no un inventario termodinámico; su demanda térmica+advectiva se
  pesa con `fsat = min(1, hueco/ALPHA_PORE_GAS)` (continuo; las fuentes de
  masa de las reacciones no se pesan) **también en el test de venteo de
  F2.31 (auditoría 4, A4-2)**: sin eso el gas de piso salía de `act_g` por
  una demanda que no plantea y F2.29 sellaba la fila (E1b, negativo en B1,
  por la puerta de atrás). **Una sola definición, `fsat_cell` (B4-9)**: la
  saturación exige LÍQUIDO (rampa α_l 0 → APG; un lecho seco compactado no
  está saturado y demanda entero), vale 1 sin piso de poro
  (`pore_floor_on` falso: resorte de Plan F, mezcla). El acarreo `ws_cc` NO
  se vuelve a pesar (M5-3: es el resto de una demanda YA pesada; B4-9 lo
  pesaba dos veces). `Tg_end = gas%T` al
  final del paso en TODAS las ramas salvo la mezcla (la rama sin flujo
  arrastraba el del snapshot de origen). Con el área de película de A3-2 el
  piso se calentaba 5× en un paso y bombeaba el 7.5 % del volumen de cada
  poro a través del baño (bath_freeze 138 kPa, freeboard a 20 m/s y caótico:
  n1/n4 3e-8 → 0.14; con el peso continuo 1e-6). La fila sigue activa (la
  válvula de Plan E no se cierra): solo no bombea. El modelo de MEZCLA sigue low-Mach ρ(P0, T): con la
  compresión su baño en reposo es inestable (medido). **El exceso que recorta `COMP_SRC_CAP` se ACARREA** al paso
  siguiente (`ws_cc`, estado del reinicio; M26): un solo tope sobre la demanda
  total (térmica + advectiva + reacciones). **Bug 19 CERRADO (27-sep-2026)**: el modelo sostiene la
  formación del baño. B1 v32 (malla media, 120 s desde t=0, con arco,
  fusión, colapso y química): cero episodios, p_max 5.35 kPa en toda la
  corrida — y ocurre en el transitorio de encendido —, gas 168 m/s,
  líquido 0.84 m/s, clip 0. La cadena que lo cierra: F1 (flujos
  conservativos + superficie libre), F2 (Poisson de VOLUMEN + PEA),
  F2.7/F2.8 (water packing), Bug 21 (unidades de Ergun), F2.13 (gas de
  poro solo), F2.14 (goteo en el lecho), F2.15 (cizalla AIAD + Ergun
  efectivo). NUNCA volver a la forma de masa de la mezcla.
  `P_HYDRO_CAP` (2e6 Pa), `U_GAS_MAX` (300 m/s) y `U_LIQ_MAX` (20 m/s)
  son **CENTINELAS**, no cotas operativas: no se activan en régimen sano
  y su activación es la señal de que el acople volvió a romperse — si una
  se dispara, diagnosticar, nunca subirla. `p_max`/`u_gas_max`/`u_liq_max`
  del audit son las únicas columnas donde un blow-up P-V es visible (la
  masa y la energía siguen conservándose).
- **Flujos del transporte de α_l (Plan C F1)**: el líquido CONTINUO se
  transporta con los flujos CONSERVATIVOS que exporta el Poisson
  (`ws_Fc_*`, `F = F* + a_nb Δpp`), no con reconstrucciones de velocidades
  de centro (no son solenoidales aunque p converja). Caras mixtas
  continuo|disperso: regla del dador (nunca la media). La celda con
  líquido sobre una celda de baño es CONTINUA (regla de superficie libre,
  `liquid_continuity_mask`); usar siempre `ws_liq_cont`, no
  `liq_continuous` elemental. El gas ve `p + ws_pcorr_g` sobre el baño.
- **Poisson de VOLUMEN (Plan C F2, rama planc-f2-volumen)**: la ecuación
  de presión es Σ_q continuidad_q/ρ_q (GCBA; OpenFOAM), coeficientes
  `α_f (αV/aP)_f A/δ`, fuente `−Σ α_f u_f A`. NUNCA volver a la forma de
  masa de la mezcla `(αρ)_f u_f A`: al formarse el baño pedía gas de igual
  MASA y saturaba `P_HYDRO_CAP` (Bug 19). Corrector y Rhie–Chow con
  `d = αV/aP` (consistente con `−α∇p` del predictor). PEA del arrastre
  tras los solves de momento sobre las soluciones SIN relajar (nunca tras
  la corrección ni sobre campos relajados). El gas no carga el peso del
  líquido CONTINUO en las caras verticales (`gas_pgrad_z`); el disperso
  conserva el gradiente de mezcla (`test_dispersed_liquid` caso 4).
- **Residuales del lazo externo (Bug 20)**: momento ANTES del TDMA con el
  iterado entrante; continuidad = Σ|Su|/Σ|F*| (desbalance de masa), NUNCA
  el residual del CG. Con los antiguos el lazo salía en 1 iteración.
- **Ergun EFECTIVO del lecho se DESVANECE con el líquido de la celda (F2.28,
  oct-2026)**: `compute_ergun_drag(on_bed=.true.)` multiplica el Ergun del
  lecho de abajo por `1 − α_l`. El charco parcial de F2.15 (α_l ~ 0.3)
  conserva el 70 % del freno; la celda EMPACADA (α_l → 1) nada, porque no
  puede percolar a ninguna parte y su sumidero es la presión. Sin esto, la
  celda llena sobre lecho tenía `aP` de momento 1.3e5 en las tres direcciones
  (25× su inercia), coeficientes de Poisson de 1e-7, y era el "numerical dead
  end for the liquid" del **water packing** (TRACE §2, RELAP5 §3.4.6): el
  chorro empujaba la superficie dentro de ella, 35–52 kPa, y la corrección
  salía por la única cara blanda, la del gas (+90..+117 m/s). 204 de 206
  celdas del baño descansan sobre lecho: la regla rigidizaba TODA su base.
  **Nunca sola**: F2.28 sin F2.29 dispara la presión (21 % de pasos > 20 kPa).
- **Fila de presión ACTIVA pero SELLADA = pared (F2.29, oct-2026)**: una
  celda con fase continua cuyos seis coeficientes de cara suman cero (poro
  del lecho EMPACADO de líquido: el limitador de hueco F2.8 cierra toda cara
  hacia él, sin gas, sin salida) se marca `sealed`, su fila es trivial y
  recibe el Neumann de Bug 16 (excluyendo vecinas selladas). Es Bug 16 en el
  caso que se le escapó: su `pp` salía 0 cada paso y su `p` quedaba
  CONGELADA (−17.7 kPa idéntica 2.5 s; la vecina se empacó en −122 kPa y el
  gas de encima tocó 300 m/s). La pared se decide por el ESTADO hidráulico,
  no por la presencia de fase. **`p_max` del audit es max|p|**: mirar siempre
  también el mínimo del campo.
- **Gas que no puede ventear queda FUERA del acople (F2.31, oct-2026)**: una
  celda `act_g` cuya conductancia de gas en el Poisson (`α_f d_f A/δ`) no
  evacúa su demanda de compresibilidad con menos de `P_VENT` (5 kPa) sale del
  acople (Hilfer 1998 medido con la conductancia, no con la movilidad de
  F2.16). Si su fila se queda sin caras, F2.29 la vuelve pared. **La
  conductancia y la cota de la demanda del test se evalúan a `DT_MOB_REF`
  (auditoría 11, M11-1pv; con min(dt, DT_MOB_REF) desde la auditoría 13: con
  dt < 2 ms el desplazamiento lo volvía más laxo que el Poisson)**, como la
  movilidad de F2.16: el transitorio del
  momento por celda (`ws_trg`, `ws_trl`) y, en las celdas PEA, el aP
  equivalente recalculado con la fórmula de `pea2` y los transitorios de ambas
  fases a 2 ms (`pea_ref`; aP previos, KV y α guardados en
  `partial_elimination`). Con el dt de la corrida la conductancia crecía ∝ dt
  (5× a 10 ms, 250× a dt de producción) y el juicio dependía del integrador.
  Con dt = 2 ms es idéntico bit a bit. El acarreo `ws_cc/dt` se juzga
  escalado por min(1, dt_ref/dt) (auditoría 12, M12-1: existe por la cota
  estrecha de la FUENTE y a dt grande hacía parpadear la celda paso a paso;
  puede subestimar el acarreo de reacciones: el error ya no es solo hacia
  excluir de más). **Histéresis dentro del paso (M12-E1) solo con dt ≥ 2
  DT_MOB_REF**: excluida una vez, excluida el resto del paso (el juicio
  desplazado parpadeaba entre iteraciones externas: bath_fill a 10 ms, energía
  por paso 0.94 → 0.26 de lo permitido); en el régimen de B1 (~1–3 ms) no se
  aplica: sacaría del acople todo el paso a celdas excluidas en un iterado
  intermedio, el mecanismo del muro, y no hay juez de B1 disponible.
- **FUERZA VERTICAL BALANCEADA POR CARAS (13-oct-2026, `liq_balanced_force`,
  default on)**: líquido continuo y gas ven la presión REDUCIDA de la mezcla,
  media de caras de `(p_N − p_P)/δz + W_f` (`liq_weight_f`/`cell_w`), con W_f
  el peso de la mezcla continua por volumen de FLUIDO; ninguna fase lleva peso
  de celda, y el Rhie–Chow usa la misma forma. Mató el modo par–impar del baño
  (F1b): `bath_test` ferrostática 2e-11, corriente 9e-11 m/s. La causa era la
  celda LLENA bajo la superficie (central de un p con quiebre frente a peso
  uniforme), no la de superficie. Nunca volver a `−α∇p − αρg` con gradiente
  central para el líquido. Choi (1999) se midió NEGATIVO (rama `choi-intento`).
  **En el LECHO (α_s ≥ 1e-2, `ws_bed`) cada fase recupera su flotación
  relativa POR CARAS** (auditoría 2 N-C1; auditoría 3 A3-1/M3-1): a cada
  cara del gradiente reducido se suma `B_f = bed_f (w_q,f − W_f)`
  (`bed_rel_f` en momento, `bed_rel_fp` en el Poisson: MISMA expresión en
  la cara y en el gradiente de celda, así el Rhie–Chow la cancela exacto;
  nunca como fuerza de celda). El resultado es la forma clásica
  `−α ∇p − α ρ_q g` para ambas fases. Sin ella el líquido del lecho quedaba
  COLGADO (N-C1); y con solo el líquido clásico el gas libre fijaba
  `∂p/∂z = −W̄` (mezcla) y el empuje de drenaje quedaba × α_g/ε (A3-1,
  `bed_drain` 0.18 → 0.22 m, tasa 0.40 → 0.52 m/s). **El gas la lleva solo
  donde es la fase continua del poro** (`ws_bed_gas`: percola, está en
  `ws_pv_active`, α_g ≥ cutoff y peso lineal 0 → 1 entre `ALPHA_PORE_GAS`
  y 2× el piso; mascara de cara = MÍNIMO de las dos celdas). Las dos
  trampas medidas: el gas RESIDUAL del poro saturado (0.015 > cutoff a
  propósito, F2.7) con la forma clásica es una bomba de α_g(ρ_l − ρ_g)g que
  quita a la presión de poro el peso del líquido (bath_freeze: 31 → 16 kPa
  en la capa saturada, gas a 113 m/s); y con la MEDIA de celdas en la cara
  el gas libre sobre un poro saturado o una costra recibía ¼ ρ_l g (201
  m/s). El gas atrapado conserva el gradiente reducido (F2.3).
  Banco `bed_drain` (`check_drain`: caída ≥ 0.19 m y tasa ≥ 0.42 m/s;
  medido 0.207 m / 0.451 m/s tras A4-1) y `test_bed_buoyancy` (5 casos).
  **Máscaras de cara de la flotación (auditoría 4, A4-1)**: el GAS usa el
  mínimo de las dos celdas de `ws_bed_gas` (rampa de saturación 0 → 1 entre
  1× y 2× `ALPHA_PORE_GAS`, × gas del acople); el LÍQUIDO usa `ws_bedl_f`,
  la rampa de saturación (`ws_bed_liq`, SIN la condición de percolación: con
  gas atrapado sigue drenando clásico) de la celda RECEPTORA: del mínimo de
  las dos rampas en reposo al valor de la receptora con `tanh(u_f/U_BEDL)`,
  U_BEDL = 1 mm/s (SUAVE: un interruptor en el signo de u_f rompía la
  simetría 120° por el redondeo, T_gas 3.7e-5), fija por iteración externa
  para momento y Poisson. Antes el líquido usaba la media de `ws_bed`: en el poro
  saturado el líquido era clásico y el gas reducido, condiciones de reposo
  incompatibles → fuerza neta α_l α_g Δρ g/ε y el gas de piso subiendo 30×
  más rápido (la bomba de A3-1 con el motor en el líquido; `bed_bath_rest`
  0.29 m/s en un lecho inundado en reposo, bath_freeze 840 celdas con u_l
  −0.24 m/s). Con la rampa de la celda de origen o el mínimo, la cara
  saturado|seco se comportaba como superficie libre y el poro saturado no
  drenaba por Darcy (bed_drain 0.42 m/s, colgado). Con la receptora: drena
  hacia abajo si hay hueco y no empuja contra una columna sellada. El coste:
  en la cara saturado|seco el líquido drena con el colchón de presión de la
  forma reducida (0.515 → 0.451 m/s); el remanente de `bed_bath_rest` (0.07
  m/s) es la velocidad fantasma de la celda sellada de F2.29 (abierto, sin
  id propio; B5-23: no es B4-4, que es el intervalo del audit).
  **`ws_bed` es la MISMA máscara dura (α_s ≥ 1e-2) que `liq_continuous`, a
  propósito** (M3-2):
  la rampa 0 → 1 entre 1e-2 y 2e-2 se probó y llevó bath_freeze n1/n4 de
  1e-6 a 3e-3 (sensibilidad en el transitorio de la costra) y frenó
  bed_drain (0.52 → 0.50 m/s); la flotación relativa debe acompañar a la
  pertenencia del líquido al Poisson, que es un interruptor. **BURBUJAS en el baño (A3-5; auditoría 4,
  A4-8: `ws_bub` + máscara de cara `ws_bub_f`)**: celda de BAÑO (α_l ≥ 0.3,
  sin lecho) con gas que PUEDE deslizar (α_g ≥ cutoff, peso 0 → 1 hasta 2×:
  con gas evanescente, atado al líquido, la flotación del líquido no tiene
  contraparte y bath_test perdía el reposo a 0.13 m/s) y con baño encima.
  La cara (k | k+1) lleva la burbuja de k solo si k+1 es baño INTERIOR
  (líquido continuo con líquido continuo encima): el frente avanza hacia
  baño sin gas (con el mínimo de celdas una burbuja aislada no subía
  nunca) y NUNCA hacia la celda de superficie (el gas de la superficie
  leería el salto de presión del baño: el chorro de F2.3). Y fuera del
  lecho el gas móvil es fluido del acople aunque no tenga camino al
  freeboard (`gas_percolation_mask`): Hilfer es un criterio de medio poroso;
  la bolsa aislada quedaba pared y sin flotación para siempre. Común a las
  dos fases (Σα_q B_q = 0). bath_test sigue exacto; bath_fill: 288–576
  celdas burbuja; bed_flood 7.1 → 0 % de pasos > 200 m/s. **El arrastre de
  la burbuja es el físico (B4-25)**: en las celdas `ws_bub` el cierre
  `α_l α_g ρ_mez/TAU_LG` (deslizamiento fijo g τ ≈ 0.1 m/s) cede con el
  peso de `ws_bub` a `K = α_g α_l Δρ g/U_BUBBLE` (B5-10: la flotación que el
  gas ve es la RELATIVA, con α_l), `U_BUBBLE` = 0.23 m/s (Clift);
  la celda de superficie conserva `TAU_LG`. bath_fill 77.5 kPa / 61 m/s.
  **El peso propio de una fase en la cara es la media PONDERADA por su α
  (`own_weight_face`, B4-10)**: la T/ρ de la celda sin la fase son rancias
  (Boussinesq ×1.18 en el borde del lecho seco); momento y Poisson usan la
  misma función (la cancelación del Rhie–Chow lo exige). **`ALPHA_BED`
  (1e-2) es la única definición del umbral de lecho (B4-26)**; mismo valor
  que `ALPHA_FLOW_CUTOFF` a propósito.
- **Lo que NO funcionó en la ventana 280–370 s (oct-2026)**: la salvaguarda de
  water packing de RELAP5 §3.4.6 / TRACE cap. 2 (F2.32, archivada en
  dev-history) casi no se activa — la succión del piso del lecho no es water
  packing clásico. No reintentarla sin un mecanismo nuevo que la justifique.
- **Juez ESTADÍSTICO para regímenes marginales (oct-2026)**: pasados los
  ~280 s la dinámica es CAÓTICA (un reinicio desde el mismo snapshot es
  idéntico a 1e-9 en el primer paso y desplaza el mismo evento 0.2 s). Las
  centinelas son umbrales duros sobre un campo caótico: el "tiempo hasta la
  primera centinela" de UNA trayectoria es ruido (medido: cinco candidatos,
  cinco instantes distintos, ninguno más suave que la base). Comparar
  candidatos con varias trayectorias (12/14/15 ranks perturban el redondeo
  del MC sin tocar la física) y criterio de RÉGIMEN ACOTADO (% de pasos con
  |p| > 20 kPa, gas > 200, líquido > 10, alguna centinela), media ±
  desviación. Patrón en `scratchpad/cand/stat/` (`run_all.sh`,
  `criterio.py`). Las sondas de celda `[PROBE-MOM]`/`[PROBE-P]`
  (`probe_cell_i/j/k` + `probe_step_*`, docs/CONFIGURATION.md) localizan el
  mecanismo antes de tocar nada.
- **Flujos convectivos del LÍQUIDO en momento: DONOR-CELL (F2.24, sep-2026)**.
  `face_mass_fluxes_noalpha` × α del lado upwind, igual que la energía del
  líquido; conductancias difusivas con α de cara ARMÓNICA (`aface`). Con la
  interpolación SIMÉTRICA de α, una vecina VACÍA "entrega" ½·α_P·ρ·u de
  caudal fantasma, así que el coeficiente de esa cara vale
  `aT = D + ½ α_P ρ |u_P| A` — **crece con la propia velocidad** — y
  multiplica la velocidad de la celda vacía, que lleva la sedimentación del
  disperso (−49.7 m/s = `U_SETTLE_MAX` para gotas de 2 mm en gas a 2000 K).
  Eso es una REALIMENTACIÓN POSITIVA de `C/aP ~ 0.18` por iteración: e-folding
  de 50 ms, y la superficie del baño llegaba a `U_LIQ_MAX` en 0.24 s en cuanto
  el arco perforaba el lecho (v33: colapso desde 205.5 s, las tres centinelas
  en la cota el 100 % de los pasos desde 260 s). Es el MISMO defecto que ya se
  corrigió en la energía del líquido; allí era un sumidero, aquí una
  inestabilidad. Con donor-cell una vecina sin fase no entrega NADA y da igual
  qué velocidad lleve — por eso es robusto. **El GAS usa desde el 13-oct-2026
  los flujos de masa CONSERVATIVOS de su Poisson** (`ws_Fg_*`, auditoría M24,
  transitorio (αρ)ⁿ): antes era la forma simétrica, cuyo caudal fantasma
  ½αρu FRENABA el modo par–impar del baño en la celda de gas sobre la
  superficie; con la fuerza balanceada (sin modo) el flujo conservativo es
  estable. Nunca integrar uno sin el otro. Medido
  con la sonda de balance de momento por celda (`probe_cell_i/j/k` +
  `probe_step_*`, en `mod_momentum_3d`): `a_nb` crece 400× mientras `aP` no se
  mueve. Juez 200–230 s: ninguna centinela.
- **Morfología del acople gas-líquido: MEZCLA, nunca interruptor (F2.22)**.
  Dos logísticas de AIAD (Höhne–Vallée 2010 ecs. 6–9; `ALPHA_AIAD_LIM` = 0.3,
  `A_AIAD` = 50) entre LECHO (cizalla), INTERFASE RESUELTA (Štrubelj–Tiselj,
  `α_l α_g ρ_MEZCLA/TAU_LG`) y DISPERSA (gota). El interruptor duro sobre α_s
  saltaba una mediana de 1.5e8. **`TAU_LG` NO es una muleta**: es el cierre de
  interfase resuelta, y equilibra la flotación relativa
  `α_q (ρ_mez − ρ_q) g` de una celda mixta con 0.09 m/s de deslizamiento
  (medido en `bath_test` a t = 0). **La cizalla del lecho con K ~ 0.2 tampoco
  es un defecto**: es lo que deja VENTEAR al gas de poro; sin esa rama el gas
  de poro pasa de K/inercia 0.02 a 4.6 por paso y la presión sube lineal de
  4.5 a 63 kPa en 0.8 s.
- **Acople gas-líquido en el lecho (F2.15, sep-2026)**: en celdas con
  chatarra propia o que descansan sobre el lecho, el intercambio es la
  CIZALLA de superficie libre `C_FS_SHEAR ρ_g |Δu| |∇α_l|` (AIAD), NUNCA la
  relajación dispersa `α_l α_g ρ_l/TAU_LG` (K = 1.6e5: ataba un charco al
  chorro del arco en 14 ms, u_l/u_g = 0.99, y lo estrellaba a 20 m/s contra
  la celda en cap — 134 kPa en B1 v31). Fuera del lecho el charco libre
  CONSERVA el acople disperso: es lo único que frena al gas sobre un baño
  en reposo (con cizalla sola, bath_test se va a 143 m/s). Y el líquido
  lleva Ergun con α_s EFECTIVO `max(propio, de abajo)`
  (`compute_ergun_drag(..., on_bed=.true.)`): sin él, la celda de charco sin
  chatarra propia se queda sin ningún sumidero de momento y cae en caída
  libre hasta U_LIQ_MAX. Las dos piezas van juntas.
- **Líquido en contacto con el lecho (F2.14, sep-2026)**: una celda con
  chatarra propia (α_s > ALPHA_SOLID_RESID) o que descansa sobre una celda
  del lecho está en régimen de goteo: el drift del líquido disperso es
  `percolation_velocity` (α_s efectivo = max(propio, de abajo)), NUNCA la
  velocidad del gas. La celda recién fundida bajo el arco (α_s 0.003–0.01)
  llovía al lecho a la velocidad del jet (20 m/s): ráfagas de 25–84 kPa
  (B1 v30). Literatura: Austin–Nogami–Yagi 1997, TFM de lechos de goteo
  (arXiv 2409.10674): el líquido tiende a la velocidad del sólido cuando
  α_l → 0. Acotar solo el flujo de cara (F2.12-B) acumula y falla.
- **Gas atrapado = subfase DESCONECTADA (F2.16, sep-2026)**: el gas de una
  celda es fluido del acople P-V sólo si PERCOLA hasta el freeboard por
  celdas cuyo gas puede moverse (movilidad = transitorio/(transitorio +
  Ergun) > GAS_MOB_MIN; distribución bimodal medida). **El transitorio usa
  min(dt, `DT_MOB_REF`) con `DT_MOB_REF` = 2 ms (el dt de B1): nunca un paso
  MAYOR que el de calibración (auditoría 8, M8-2; con dt < 2 ms, el real,
  auditoría 13)**: con dt ≥ ~6.5 ms el gas de piso de una
  capa saturada (ε_g = 0.015) caía bajo el umbral (cifra de la movilidad
  medida en pocket_rise, 0.0130 a 5 ms, con mob = 1/(1 + Ergun·dt/(α_g ρ_g));
  a 2 ms queda ~0.032, margen ~3× sobre GAS_MOB_MIN: para el gas de piso el
  umbral SÍ es sensible, no aplica el «1e-2..1e-4 no es crítico») y la bolsa bajo el lecho
  inundado quedaba pared (pocket_rise a 10 ms: gas a 131 m/s). La
  clasificación es del estado, no del integrador (`test_gas_percolation`). Es criterio de CAMINO,
  no local: F2.13 lo probaba celda a celda y al declarar pared a las celdas
  del piso de poro encerraba a vecinas con movilidad propia (B1 v33: 1.4 MPa
  a t = 204 s). Hilfer, Phys. Rev. E 58 (1998) 2090: la subfase conectada es
  "the region inside of which an external applied pressure gradient can
  propagate"; las desconectadas son inmóviles y su presión no es
  diferenciable. `gas_percolation_mask` usa el patrón invariante (gather
  global + mismo barrido en todos los ranks) y nunca amuralla el dominio.
- **Fase EVANESCENTE (F2.20/F2.21, sep-2026)**: una fase por debajo de
  `ALPHA_FLOW_CUTOFF` NO se para. Su velocidad se ATA a la de la otra fase
  (`Su = aP·vel_other`) y su `aP` es FÍSICO
  (`max(α, ALPHA_PHASE_MIN)·ρ·V/Δt + (Ergun + K)·V`), nunca el ficticio 1.
  Es la *phase appearance and disappearance* de la termohidráulica nuclear:
  el modelo de dos fluidos pierde la hiperbolicidad en ese límite, y la
  literatura no para la fase — AUSM+ ata las velocidades con función suave
  bajo α_min = 1e-4, CATHARE/NEPTUNE acondicionan la fricción con
  fracciones residuales de 1e-5. El cero artificial hacía que el promedio de
  cara ½(0 + u_vecino) inyectara medio caudal por la superficie de un baño
  en reposo: cuatro intentos fallidos antes de encontrarlo (dev-history
  F2.17–F2.19). Además `ws_gas_reach` mete al gas en el Poisson donde aún no
  lo hay pero puede llegar (percolantes + una capa fuera del lecho), que es
  lo que deja a una celda de baño puro recibir gas al drenar; geométrico, no
  reactivo. Efecto colateral que confirma el diagnóstico: la deriva de α de
  un baño en reposo pasa de 1.1e-3 a 0.000 exacto y `bath_alpha_frozen` deja
  de ser xfail.
- **Gas residual de poro solo (F2.13, sep-2026)**: una celda del lecho sin
  líquido continuo y con α_g en el piso `ALPHA_PORE_GAS` (`pore_gas_only`)
  NO es fluido del acople P-V (fuera de `ws_pv_active` y `act_g`: pared,
  pp = 0, Neumann de p). Ese gas existe para la contabilidad de volumen
  (F2.7); si lleva presión, su compresibilidad integra p ≈ P0 (T/T0 − 1)
  al calentarse (B1 v30: 111 kPa lineales en el fondo bajo los arcos).
- **Ergun (Bug 21, sep-2026)**: `mod_constants::ergun_coefficients` es la
  ÚNICA definición (forma original de Ergun 1952: `A = 150 μ (1−ε)²/(d_p² ε³)`,
  `B = 1.75 ρ (1−ε)/(d_p ε³)`, coef = A + B|u|). Nunca reescribir el
  Forchheimer como `C_F ρ|u|/√K` con `C_F = 1.75/(d_p ε³)`: tiene unidades
  de 1/m y daba un lecho 500–800× más resistente (percolación de 3 mm/s,
  gas de poro sin salida → kPa–MPa en toda la familia Bug 18/19). Todo
  test de una correlación se contrasta con la fuente y un valor a mano.
  **Convención de velocidad (auditoría 12-oct-2026, A6)**: Ergun da la caída
  de presión por la velocidad SUPERFICIAL; el código usa velocidad
  INTERSTICIAL con presión pesada por la fracción, así que `ergun_coefficients`
  devuelve los coeficientes de Gidaspow `ε²A_E`, `ε³B_E` (antes A_E, B_E: lecho
  4×/8× más resistente con ε = 0.5 y 400×/8000× con ε = 0.05). Percolación con
  ε = 0.5, α_l = 0.01: ~0.11 m/s.
- **Residuales del lazo externo**: se computan con el ITERADO ENTRANTE
  (el campo que queda en pie), jamás con el recién resuelto post-TDMA
  (siempre ~0: declaraba convergencia en 1 outer y perdía (1−α_T) de las
  fuentes por paso — fue el hueco del balance de energía).
- **Régimen de PASO válido del modelo de dos fluidos (auditoría 12, M12-2)**:
  dt de unos pocos ms con CFL ≤ 1 (los parámetros de B1: dt_0 2 ms, dt_min
  1 ms, cfl_max 1). Con pasos fijos ≥ 50 ms, o con el antiguo dt_0 0.5 s /
  dt_min 10 ms de `config_production_full`, bath_test y bath_fill se rompen
  en los primeros pasos (presión en P_HYDRO_CAP, líquido a 14–31 m/s; también
  en el estado de la auditoría 8: es previo). `config_production_full` usa
  ahora los de B1 (`max_outer` 5) con `dt_max` 10 ms (mayor paso fijo validado con baño). OJO (auditoría 13): en los bancos el
  lazo externo no converge en `max_outer`, `adapt_timestep` parte el paso y lo
  deja en `dt_min` (1 ms); `bath_fill_adapt` cubre ESE régimen, no el
  crecimiento del paso ni el cruce de 4 ms de la histéresis de F2.31.
- **CFL azimutal**: `dth_len = max(r·dθ, dr)` — el anillo del eje no
  gobierna el dt (esquema implícito; escala advectiva ≥ ancho radial).
- **M4-12, gas bajo una capa saturada (auditorías 6-7)**: banco
  `pocket_rise` (bolsa de gas bajo la capa 8 saturada; estado construido por
  `make_pocket_init.py` con presión HIDROSTÁTICA de la nueva estratificación y
  `rho_gas` de la EOS). Con los defaults el gas sube a contracorriente desde
  el primer paso. El estado hidrostático NO es punto fijo (auditoría 8,
  M8-3): la capa saturada drena por Darcy y su peso pasa al arrastre del
  lecho (la presión del piso baja ~20 kPa, físico) y la bolsa se
  despresuriza y ventea por los huecos de los electrodos. El pico de gas del
  audit (45 m/s) NO es ese venteo: es un modo par-impar del freeboard sobre
  el lecho que produce el lazo externo truncado a 5 iteraciones (con 20
  desaparece); la cota de 60 m/s es de regresión. El juez mide la presión de
  la bolsa DIRECTAMENTE frente a la capa de encima conectada al gas
  (`max|p|` es siempre el piso): sin repuntes de más de 0.5 kPa; ENVOLVENTE
  de tiempos (bajo 15/10/5/2/1 kPa antes de 0.08/0.09/0.10/0.11/0.13 s;
  medido 0.06/0.07/0.08/0.09/0.10): una meseta por encima de 1 kPa de más de
  ~20–30 ms falla, y también un drenaje un 35 % más lento (si un cambio del
  modelo lo justifica, remedir); ≤ 1 kPa desde 0.13 s y ≥ −1 kPa siempre; dt
  real = esperado = el del config (el reinicio toma el del snapshot). La
  «retención de 0.25–0.3 s» medida en la auditoría 6 era el estado construido
  con la presión del snapshot de origen, NO el modelo; la opción
  `pc_bed_gas_pocket` que se añadió para quitarla se RETIRÓ (con el estado
  coherente soltaba 45 m/s en el paso 1). Lección: un estado construido a mano
  debe ser un punto de equilibrio del modelo (presión y EOS) antes de juzgar
  nada con él. El juez para la bolsa real de B1 sigue siendo B1.
- **Plan D (acople α–p por reglas locales) CERRADO NEGATIVO (10-oct-2026)**:
  las claves `pc_liq_sealed_wall`, `pc_fs_liquid_gradient`, `alpha_g_comp_min`,
  `pc_fs_liquid_face`, `pc_consistent_corrector`, `pc_liq_closed_dir` existen
  con default `false` y SOLO las activa el banco `tests/integration/configs/
  bed_flood.dat` (xfail `bath_pv_bounded` con causa). Bajan los picos del banco
  (>100 kPa 8 → 1 %) y no el nivel del poro inundado; en B1 ninguna cruza el
  juez (320–345 s: 63–82 % de pasos > 20 kPa; D2.6 65.7 % y PEOR en picos:
  la cara de superficie libre unilateral transmite la presión del poro
  empacado al gas en vez de dejar caer el charco con velocidad fantasma —
  el mismo water packing con la válvula en otro sitio). No reintentar reglas
  locales sobre α: lo que falta es converger transporte de α + limitador
  JUNTO con la presión dentro de la iteración externa (NEPTUNE_CFD, Liles &
  Reed). Lección de método: el banco de 4 celdas NO predice B1 — toda
  variante pasa por el juez estadístico antes de tocar defaults.
- **Plan E E1 (`pc_sat_open`, poro saturado transmisivo) CERRADO NEGATIVO
  en B1 (10-oct-2026)**: default `false`, solo el banco `bed_flood.dat`. En el
  banco era la mejor pieza de D+E (picos > 100 kPa 8 → 1.4 %, líquido > 10 m/s
  → 0, consistente n2/n4/n8); en B1 no se distingue de la base en 300–320 s y
  en 320–325 s tiene 7× más picos > 100 kPa (27.6 % de pasos frente a 4.2).
  Segunda confirmación de la lección: ni la coincidencia en
  tres descomposiciones del banco predice B1. **Mecanismo medido con la
  sonda `[PROBE-P]` a 320 s**: el gas residual del poro saturado
  (`ALPHA_PORE_GAS` = 0.015 > `ALPHA_FLOW_CUTOFF`, puesto así en F2.7 para
  que "la celda nunca quede sellada") es una VÁLVULA FICTICIA: la fila pide
  7.5e-4 m³/s de líquido y lo compensa con gas de piso que sale a 2.4 m/s
  por el baño de encima; ni α_l ni α_g cambian en 120 pasos (el limitador
  rechaza el líquido, `α_g = 1 − Σ` repone el gas) y el baño de encima baja
  0.33 m/s "dentro" del poro cada paso. Es `vol_lim` (desfase 2 de Plan D)
  con mecanismo. Con la válvula cerrada (E1b `pc_sat_gas_off`, siempre con
  E1) el lecho saturado carga su peso (∇p = ρ_l g medido; la base está
  ~70 kPa POR DEBAJO de su hidrostática) y el desajuste α–p se cobra en el
  gas residual de las celdas de baño casi llenas (banco: 300 m/s en θ).
  **E1b + compliancia residual D2.4 también NEGATIVO en B1** (screening
  `judge_e1b_n12`, 320–325 s: p > 100 kPa el 63 % de los pasos, gas > 200
  el 100 %, `P_HYDRO_CAP` a 323 s; base 4 / 2 %), con el banco acotado
  (4 / 5 %): cerrar la válvula vuelve rígido TODO el piso del baño y el
  golpe de ariete de la celda que se llena (RELAP5 §3.4.6) sale a escala
  de horno en ráfagas de pocos pasos (los snapshots a 320/325 s están
  limpios). La válvula ficticia es lo que sostiene a la base hasta ~320 s.
  Tercera confirmación: el banco no predice B1.
- **Plan F (`pc_gas_spring`, bolsa de gas atrapada = RESORTE) CERRADO
  NEGATIVO en B1 (12-oct-2026)**: diagnóstico correcto (el 96 % de las
  celdas con |p| > 100 kPa de la base están en el PISO, k = 1–2, bolsas de
  gas bajo el lecho inundado que F2.16/F2.31 vuelven pared), banco el mejor
  de todos (p > 100 kPa 0 %, 72 kPa), pero en B1 (`judge_f_n12`, 300–325 s)
  p > 100 kPa y gas > 200 el 100 % de los pasos desde 305 s y 1.85 MPa a
  324 s. Mecanismo medido: "todo el gas es fluido del acople" mete las celdas
  de poro SECO (α_g = `ALPHA_PORE_GAS` exacto, sin vecinas con gas) y su fila
  sin conductancia integra cualquier defecto de volumen en presión (rampa
  lineal 5–7 kPa/s, 240 kPa a 325 s, sin calentamiento: es el B1 v30 de
  F2.13); el gas del baño (α_g 0.1) sale a 200+ m/s por la superficie. Las
  capas F2.13 / F2.16 / F2.31 existen cada una por un fallo medido y
  quitarlas juntas los expone todos. Cuarta confirmación: el banco no
  predice B1. **Las bases de referencia anteriores al 9-oct (judge_largo_F231,
  flood_n*) están contaminadas por Bug 22**; la referencia limpia es
  `judge_base_n12` (binario actual): LIMPIA hasta 318 s (0 % sobre 100 kPa
  en 300–315 s) y `P_HYDRO_CAP` a 320.49 s, en la cota el 92 % de los pasos
  de 320–325 s. El muro de ~320 s es del modelo, no del binario
  (`docs/PLAN_F_gas_resorte.md` §6).
- **Plan G (`mixture_model`, modelo de MEZCLA con deslizamiento y acople α–p
  implícito, `mod_mixture_3d`) — opt-in, juez B1 NEGATIVO (12-oct-2026)**:
  una velocidad volumétrica, Poisson de volumen con fuerzas de cara
  BALANCEADAS (el Boussinesq va en la densidad de cara), velocidad de celda
  RECONSTRUIDA de los flujos conservativos, α_l con flujo de mezcla +
  deslizamiento Godunov acotado; en el lecho Darcy bifásico (movilidades
  α²/K por fase, peso/inercia ponderados por movilidad, flujo fraccional de
  Buckley–Leverett evaluado con la α del sub-paso); intercambio gas–líquido de
  BURBUJAS (no existía en el código); fuente de compresibilidad contra
  `sh%Tg_end` (T del gas al final del SIMPLE anterior, persiste en el
  reinicio): medida contra T_old, la interfase sólido–gas partida después del
  SIMPLE bombeaba volumen cada paso (es el mecanismo de F2.13). Bancos: baño
  en reposo exacto (1e-15), `bath_fill` 62 kPa / gas 85 m/s (dos fluidos
  83 / 163). Juez B1 reanudado desde 300 s: 2 MPa en <0.3 s, ±0.7–1.5 MPa en
  el piso de chatarra COMPACTADA (762 celdas con α_s > 0.9 a 300 s; Ergun
  1e6× menos permeable que un lecho real): ninguna variante lo acota. Lección:
  el muro de ~320 s vive en el ESTADO del lecho (compactación del colapso +
  inundación), no en el método de acople. Gotas con velocidad propia dentro de
  la mezcla: probado y negativo (`MIX_DROPLETS`). `docs/PLAN_G_mezcla.md`.
- **Boussinesq del líquido referido a `T_ref_boussinesq` = T_liquidus
  (auditoría 12-oct-2026, A7)**, no a `T_ambient`: con 300 K el baño a 1850 K
  pesaba ×0.81 (≈6100 kg/m³) mientras la inercia usaba 7500. Afecta momento,
  `liq_weight_f`, inicialización hidrostática, mezcla y `check_bath.py`.
- **Métricas del régimen (corregidas 10-oct-2026)**: `u_liq_max` del audit
  incluye el líquido DISPERSO (α_l ≥ 1e-2, velocidad terminal de gota hasta
  `U_SETTLE_MAX` ≈ 50 m/s, sin cota): `u_liq_max ≥ 20` NO es centinela.
  Centinelas del juez = presión y gas. Y `|p| > 20 kPa` es HIDROSTÁTICA en
  cuanto el lecho saturado carga su peso (ρ_l g entero: 0.3 m de lecho
  inundado = 22 kPa): medir exceso sobre la hidrostática saturada
  (`scratchpad/cand/pexcess.py`), p > 100 kPa, gas > 200 y centinelas
  (`regime2.py`).

## Oct-2026 (B1 241–285 s): rampa del piso de poro, película con histéresis, E2 y J-B

- **Rampa del piso de poro POR DEBAJO de ALPHA_BED (6314031)**: `pore_floor(as)`
  sube de 0 en ALPHA_BED/2 a `ALPHA_PORE_GAS` en ALPHA_BED, y `liq_cap` la
  resta (limitador y derrame). Causa: con el interruptor en ALPHA_BED una celda
  que fundía de 0.0101 a 0.0099 liberaba de golpe 0.015 de hueco: ráfagas de
  B1 a 241 s. La rampa POR ENCIMA (ALPHA_BED → 2 ALPHA_BED, 4547861) llevó el
  juez a 2 MPa: no usarla. El hueco de la banda (ALPHA_BED/2..ALPHA_BED) lo ve
  SOLO el limitador: `ws_liq_room`, `fsat_cell` y `ws_bed` siguen con el
  escalón en ALPHA_BED A PROPÓSITO. Llevarlo al Poisson (F2.8 cerrando caras
  hacia la banda) se probó y se RECHAZÓ (auditoría 20, A20-2, 4645f55): B1
  255–258 s 12–33 % de pasos en centinela frente a 0 %. El desfase
  limitador/Poisson en la banda se acepta (el derrame sube lo recortado).
- **Película de superficie con HISTÉRESIS (3c4bf52)**: una celda de película
  nueva entra con α_l ≥ 2·ALPHA_FLOW_CUTOFF y una que ya era continua se queda
  con ≥ ALPHA_FLOW_CUTOFF (`liquid_continuity_mask(..., prev)`, con
  `ws_liq_cont_prev`, que va en el snapshot). Causa: la película que alternaba
  continua/dispersa cada paso (juez E2 282.73 s, celda (1,36,3)) hacía saltar
  la conductancia de su fila (ráfagas de gas). Las llamadas del lazo pasan
  `ws_liq_cont_prev`; la mezcla (Plan G) no.
- **E2 `pc_drift_source` ON (a8a0df1)**: el volumen de líquido que entró por
  caras SIN enlace del Poisson en el último transporte del paso es fuente
  conocida del Poisson de la iteración siguiente (`ws_pc_unl`, drift-flux de
  Manninen). Juez B1 275–300 s: p_max 1.1 MPa → < 95 kPa. No actúa en el
  outer 1 de cada paso (su fuente es del transporte del paso; el residual del
  outer 1 es coherente con eso: B20-4, cerrado sin cambio).
- **J-B `pc_transport_f28` ON (2f0529b)**: una cara continuo|continuo que el
  Poisson dejó sin enlace (F2.8: receptora sin hueco) TAMPOCO transporta α
  (antes la rellenaba la velocidad de centro y el defecto se volvía un pozo de
  presión: B1 281 s, −82 kPa). El hueco de poro se CONGELA en α^n durante el
  paso: con el del iterado la cara cerraba, la receptora no se llenaba, reabría
  y se llenaba (ciclo entre outers; bed_drain energy_balance_step ×8.9). En la
  vista condensada `liq_old%alpha` ya es acero+escoria (no sumar `ws_sp_asl`).
  Que fsat/F2.31/fs_full vean también el hueco congelado es A PROPÓSITO:
  separarlos del de las caras (M20-2) se probó y empeoró el pozo de 281 s
  (0.5 % centinela, p_max 156 kPa frente a 0 % y 94 kPa); no repetir. La
  celda que se llena dentro del paso queda abierta hasta el siguiente; el
  enlace cambia entre correcciones en ~1 % de las caras, sin relación con las
  ráfagas (M20-3, medido sin acción).

## 22-oct-2026 (B1 258–345 s): presión total en las aberturas y F2.31 por paso

- **Aberturas del techo con presión total (`pc_outlet_total_pressure`, ON,
  8f568fc, golden v131)**: la ráfaga de gas de 258.5 s era reflujo sin freno
  por el agujero del electrodo 2. Quitada (gas 66 vs 300 m/s). Pendiente M3:
  el gas aspirado entra con la T y composición de la celda.
- **Juez largo `judge_otp_280` (280→345.5 s, detenido)**: el muro sigue. A
  342.5 s, celdas del FONDO (k = 1) del baño con chatarra residual sumergida
  (α_s 0.013–0.08 ≥ ALPHA_BED, α_g en el piso 0.015) ciclan en 2 pasos (α_g
  0.015 ↔ 0.02, p ±40–90 kPa) y escalan a 1.06 MPa a 345 s. Sonda en
  (10,60,2): F2.31 excluye el gas en el TERCER outer porque su demanda
  (ρ_g − ρ_eos(p^n))/ρ_g crece dentro del paso con el error de presión (src
  1.5e-5 → 2.3e-3 > cg·P_VENT 2.0e-3); la fila pierde la conductancia del gas
  (aP/12) y salta a 413 kPa.
- **F2.31 decidido una vez por paso (`pc_f231_step_freeze`) PROBADO Y NO
  ADOPTADO**: quita el pico de 342.535 s (413 → 101 kPa) y mejora 340–344 s,
  pero el ciclo de 2 pasos del piso sigue creciendo y a 344.83 s se traba en
  2 MPa (344–346 s: 34 % centinela frente a 6.7 %). Parche no versionado.
  Quinta regla local sobre la misma familia (D, E, F, G): confirma la lección
  de Plan D — el ciclo α–p del poro sumergido no se cura clasificando; hace
  falta converger transporte de α + limitador con la presión dentro de la
  iteración externa.
- `u_liq_max ≥ 20` del audit es líquido DISPERSO (ya documentado arriba):
  no reportarlo como centinela.
- **Corrector interno α↔p `n_pc_max = 3` (código existente, sin cambios)
  PROBADO EN B1 Y NO ADOPTADO**: empeora desde el primer segundo. 340–342 s:
  28.9 % centinela (base 0.3 %), p_max 1.5 MPa; 342–344 s 39.5 % (base 2.5 %);
  342.45–342.56 s 24.7 % (base 3.7 %). La variante con momento congelado
  (α re-transportada con flujos de una presión aún no convergida) amplifica
  el ciclo en vez de amortiguarlo. Converger α con p exige un acople
  implícito de verdad (α y p en el mismo sistema o con la linealización
  ∂α/∂p en la fila), no iterar el segregado.
