# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This file lives inside the git repo (`hornofusion-full3D/CLAUDE.md`, auditoría 5 B5-24; the parent `Horno/` only holds reference PDFs and a stub pointing here). All code lives in `hornofusion-full3D/` — **run every command from that directory**. Documentation and code comments are in Spanish; keep that convention.

**EAF3D** is a 3D multiphysics CFD simulator (Fortran 2008 + MPI + parallel HDF5) of scrap/HBI melting in a 130 t AC electric arc furnace, implementing Ugarte et al. (2024) *Materials* 17(21), 5139.

## Commands

```bash
# Build (from hornofusion-full3D/) → binary at bin/eaf3d_mpi
make              # -O2 + bounds check (development default)
make debug        # -O0 -g -fbacktrace (use for segfaults / out-of-range indices)
make opt          # -O3 -march=native (long production runs)
make clean

# Test suite (see tests/README.md; XFAILs esperados en tests/xfail.list)
make test-quick   # gate por commit (~1.5 min): corrida fría + bath_test + arc_melt + bed_bath_rest + invariantes + golden
make test-full    # gate por etapa (~5-10 min): unit + matriz MPI + simetría
make test-unit    # unit tests Fortran (TDMA, malla, entalpía, flujos de cara)
STAGE=vN make test-rebaseline   # regenerar golden tras un cambio numérico intencional

# Production run (mesh 60×120×84, 5040 s simulated)
mkdir -p output_prod
make clean && make opt
mpirun -n 12 ./bin/eaf3d_mpi input/config_production_full.dat 2>&1 | tee run_production.log
tail -f output_prod/monitor.log   # progress: step, time, solid mass, residuals

# Inspect output
h5ls -r output_prod/eaf3d_00000200.h5

# Post-processing (Python 3, needs h5py/matplotlib; pyvista/skimage for some)
python3 postprocess/plot_insights.py [output_dir] [plots_dir]
python3 postprocess/render_3d_video.py [output_dir] [plots_dir]
python3 scripts/hdf5_to_vtk.py output/*.h5
```

Requirements (macOS): `brew install open-mpi hdf5-mpi`. The Makefile hardcodes Homebrew paths (`/opt/homebrew/include`, `/opt/homebrew/lib`).

**Choosing `-n`**: the domain decomposes in r × theta × z (`factorize_3d` picks the most cubic blocks); only `ntheta` must divide exactly, r/z remainders go to the last rank, and every local block needs ≥ 2 cells per direction (checked at startup, audit M32). Production mesh: 8 → 1×4×2, 12 → 2×3×2 (recommended on M4 Pro), 16 → 2×4×2, 24 → 2×4×3. See `docs/RUNNING.md` §3.


## Architecture

Detailed docs, read before non-trivial changes: `docs/ARCHITECTURE.md` (modules, types, MPI, resolved critical bugs), `docs/PHYSICS.md` (equations/models), `docs/CONFIGURATION.md` (all config keys), `docs/OUTPUT.md` (HDF5 format). `docs/dev-history/` is historical debugging context only.

- **~30 modules in `src/`, one concern each** (`mod_energy_3d`, `mod_arc_cassie_mayr`, …). `main_3d.f90` runs the time loop: arc (Cassie–Mayr → MC radiation → Lorentz) → DO radiation (S4, 24 direcciones) → carbon chemistry (O₂ finito) → especies O₂/CO/CO₂ → SIMPLE outer loop (Ergun drag, momentum, corrección de presión CG, energía, k-ε) → solid phase update → slag → dt por CFL → HDF5 output.
- **Adding a module requires editing the Makefile twice**: append to `SRCS` in topological order AND add its explicit `.o` dependency rule (module order matters; `.mod` files go to `obj/` via `-J`).
- **All 3D arrays carry 2-cell halos**: allocated `(-1:nr+2, -1:nth+2, -1:nz+2)`; physical indices are `1:n`. After updating any field needing cross-rank coherence, call the matching halo exchange (`phase_exchange_halos`, `solid_exchange_halos`, `slag_exchange_halos`, or `mpi_exchange_halos_3d` directly).
- **Critical GFortran rule**: a dummy argument declared `arr(:,:,:)` remaps the lower bound to 1, silently shifting all halo accesses by +2. Any dummy that touches halos MUST be declared `arr(-1:,-1:,-1:)`.
- **PHDF5 collectivity**: all HDF5 metadata operations (`h5dcreate_f`, `h5gcreate_f`, close calls) must be executed by ALL ranks or the program deadlocks in `h5fclose_f`; only `h5dwrite_f` may be rank-selective. Follow the pattern in `mod_output_hdf5.f90`.
- **FVM scalar equation pattern** (energy, species): coefficients aW/aE (r), aS/aN (θ), aB/aT (z), upwind convection, central diffusion, plus the minimum-phase guard `if (alpha_q < 1e-6) then aP=1; Su=phi_old; cycle` — without it TDMA divides by zero.
- **Only rank 0 prints** (use `should_print(mesh)`).
- Config files (`input/*.dat`) are `key = value`; unknown keys and keys without effect print a WARNING (rank 0) but do not stop the run — check the log for typos. Every physics module can be toggled via `solve_*` flags without recompiling; `solve_chemistry` REQUIRES `solve_species` (validated: without transport O₂ would be infinite).

## Convenciones numéricas vigentes (roadmap 2026)

- **Flujos convectivos**: SIEMPRE vía `mod_face_flux` (interpolación simétrica a
  caras → telescopía exacta). Nunca reintroducir velocidades de centro de celda
  como flujo de cara, ni el factor `/r` en el flujo azimutal. **Energía del
  líquido (sep-2026)**: `face_mass_fluxes_noalpha` × α del lado upwind
  (donor-cell, el MISMO flujo que el transporte de α); la interpolación
  simétrica de α hacía que una celda vacía "entregara" ½·α_P·ρ·u de masa
  fantasma a su T rancia (300 K). Conductancias difusivas con α de cara
  ARMÓNICA (`aface`, simétrica → telescopa; nula hacia vecinas sin fase).
  Regla general: una celda sin fase no intercambia energía de esa fase con
  nadie. Test: `test_phase_appearance` casos 3-4.
- **aP de convección**: forma ACOTADA de Patankar (`aP = Σa_nb + transitorio`,
  SIN términos de flujo). La forma con `max()` de ambos signos era un sumidero
  artificial; la forma `+ΔF` conservativa pierde acotamiento con div≠0.
  **El transitorio del LÍQUIDO lleva α^n (`alpha_old`, sep-2026)**: es la
  forma exacta con la continuidad discreta restada — la masa nueva entra
  solo por `a_nb` de entrada y `mdot·cp·T_src`. Con α^{n+1} el fundido que
  llegaba a una celda vacía figuraba como masa a T_old=300 K, salía a
  (300+T_in)/2 y re-solidificaba (B1 v6: 10 kg de baño a los 442 s). **El
  sumidero de congelación `mdot<0` SÍ entra (auditoría 2, N-C2)**: con el
  transitorio αⁿ la forma exacta es Mⁿ(e′ − eⁿ) = dm(e′ − e_entry) →
  `aP −= |mdot|·cp`, `Su += |mdot|·(C0 − e_entry)`; la forma «se cancela»
  evaluaba el latente con T_old y perdía dm(e′ − eⁿ) por paso (bath_freeze
  −1.8e9 J). El gas conserva α^{n+1} (libro E_gas_abs). Test:
  `test_phase_appearance` (Bug 12 en ARCHITECTURE §10).
- **Sub-relajación**: en el lazo externo contra el iterado anterior
  (`relax_field`), nunca dentro de los solvers contra el paso temporal.
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
- **Cierre de fase evanescente (sep-2026)**: una celda con
  `0 < m_s ≤ ρ_s·V·ALPHA_SOLID_RESID` (1e-4) se CIERRA en `compute_melting`
  (masa+entalpía al líquido vía `mdot`/`T_src = liquid_entry_T(e)`, celda
  exactamente vacía). Nunca volver a la guardia `m_s > SMALL` como único
  criterio de existencia del sólido: T_s = E_s/m_s con microgramos fue el
  NaN de B1 (Bug 11 en ARCHITECTURE §10). Todo cierre nuevo de fase
  residual debe ser conservativo y auditado (`m_resid_closed`).
  **Solo remanentes que ya alcanzaron el solidus** (auditoría M10, oct-2026):
  un remanente FRÍO sigue siendo sólido — cerrarlo creaba líquido subenfriado
  que re-solidificaba y convertía en "líquido" la carga ECS de poca masa.
- **Fusión y congelación = REGLA DE LA PALANCA (auditoría M9, oct-2026)**:
  estados, no tasas por paso. Sólido con e > e_sol: f = (e−e_sol)/(e_lb−e_sol)
  sale como fundido a e_lb (T_liq), el resto queda en e_sol; líquido bajo el
  liquidus congela M(e_lb−e_l)/(e_lb−e_entry) a e_entry = min(e_sol, e_l)
  (`RESOLID_LIMITER` solo acota la fracción por paso, por positividad del
  transporte de α). La T de entrada del fundido la devuelve `compute_melting`
  en `ws_Tsrc`; NUNCA volver a usar `sol%T_s` como T_src.
- **Entalpía del sólido**: función única `solid_enthalpy`/`solid_T_from_enthalpy`
  (mod_melting_3d) para TODA conversión E↔T; el dato del líquido es
  `e_l = cp_l·T + C0`. No usar `E/(m·cp_s)` directo.
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
- **Frontera de BLOQUE ≠ frontera física**: toda condición de borde se
  escribe `(i > istart .or. .not. at_rmin)` (idem `iend`/`at_rmax`, z), nunca
  `i > 1`/`i < iend`: cinco sitios trataban el borde de cada bloque en r como
  pared (n12 2×3×2 difería 5e-2 de n1; oct-2026). `decomposition_cold_r`
  (n1 frente a n12) es la única comparación de la matriz que parte r.
- **Operaciones de columna global (colapso) y de arco**: patrón invariante a la
  descomposición (gather global + escritura de celdas propias).
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
- **Colapso de chatarra**: una celda con α_l ≥ ALPHA_LIQ_CONT no es hueco.
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
- **Depósito MC del arco repartido por ABSORCIÓN (F2.30, oct-2026)**: en una
  celda con chatarra el beam deposita en cada fase en proporción a κ_q·α_q
  (`KAPPA_SOLID_ABS`, `KAPPA_GAS_ABS`, los de la DO; Fluent P-1/DO, MFiX TFM,
  Cai & Modest 2014), nunca todo al gas: el gas de poro (1.5 % del volumen)
  llegaba a 54 000 K. La parte del sólido va a `E_s` (auditada
  `AUD_ARC_DIRECT`, cota 2 K/paso; el exceso vuelve a `S_arc`).
- **Gas que no puede ventear queda FUERA del acople (F2.31, oct-2026)**: una
  celda `act_g` cuya conductancia de gas en el Poisson (`α_f d_f A/δ`) no
  evacúa su demanda de compresibilidad con menos de `P_VENT` (5 kPa) sale del
  acople (Hilfer 1998 medido con la conductancia, no con la movilidad de
  F2.16). Si su fila se queda sin caras, F2.29 la vuelve pared.
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
- **Auditoría 5 (14-oct-2026), lo que cambió de convención**: (A5-1) la
  superficie bajo el arco, chatarra O baño, se decide en UN solo barrido por
  contenido ponderado (`ksurf`; cada material en SU escala: el baño por
  ESPESOR equivalente `ARC_SURF_H` 0.014 m —M6-5: con fracción del volumen
  dependía de dz y en producción bastaban ~13 kg para recibir P_elec— y la
  chatarra por FRACCIÓN del volumen `ARC_SURF_FRAC_S` 5 % —M7-1: es un lecho;
  con espesor un cráter a medio fundir dejaba de ser superficie en
  producción—; la capa es superficie si las dos fracciones de umbral suman
  1; QUIÉN es la superficie (M8-1/M9-3): si solo un material pasa su umbral
  PROPIO, ese; si pasan los dos, la fracción cruda `wsc ≥ wba` (independiente
  de la malla: baño con chatarra sumergida = baño, M3-3; lecho inundado =
  chatarra, M4-8); si ninguno lo pasa solo, el más cercano a su umbral
  (`wsc/ARC_SURF_FRAC_S ≥ wba/frac_surf`: película fina sobre chatarra suelta
  = chatarra). La normalizada en todos los casos (M8-1) daba chatarra a un
  baño con chatarra sumergida en la malla fina);
  nunca volver a una
  búsqueda aparte del baño por celda. (M5-1) la DO guarda su reparto por fase
  (`sh%w_rad_l`, αⁿ) y la energía resta la emisión con ESE peso: con α^{n+1}
  se creaba energía en cada paso con fusión (melt_forced 1 %). (M5-2) el lazo
  de caras del intercambio gas–líquido va en dos barridos por paridad de la
  cara global con halos de T frescos (Gauss–Seidel + halo rancio no era
  conservativo en un corte de bloque en z; melt_forced n1/n7). (M5-3) el
  acarreo `ws_cc` NO se vuelve a pesar por `fsat` (es el resto de una demanda
  ya pesada). (M5-4/M5-5) toda reescritura de α_g —volfix, flotación de
  escoria, cesta, ECS— audita masa y energía del gas, el gas creado no trae
  especies y el destruido se las lleva (`m_vf_*`); `check_chem --slag` cierra
  O y C con escoria a 1e-11 usando la ρ_g del código (`/restart/rho_gas`).
  (M5-6) un hueco de energía por paso sistemático con `max_outer` bajo es la
  TRUNCACIÓN del lazo externo segregado, medible subiendo `max_outer` (×27 en
  slag_chem_flow al pasar de 2 a 10): diagnosticarlo así antes de buscar una
  fuga; slag_chem_flow corre con 10. (M5-7) las identidades de masa llevan
  piso relativo al inventario (`mtol_inv` 1e-14 ≈ 45 ulp). (M5-8)
  `bed_bath_rest` está en test-quick.
  **Bajos de la auditoría 5 (misma fecha)**: (B5-3) TODO intercambio de calor
  con el gas es en forma log con `gas_log_exchange` (mod_audit): el gas se
  relaja EXACTO con capacidad C_g/T hacia la T NUEVA del otro nodo y esa T
  cumple el balance (bisección monótona); la tasa es la física hA ΔT y el
  inventario decide ΔT — aplicar la fracción lineal en ln T daba 1.7× el
  calor a dt pequeño (lección del primer intento). El libro `E_gas_abs` se
  parte en la parte de la ECUACIÓN (estado lineal entre T_old y `Tg_end`) +
  pokes exactos; un libro lineal único con pokes log perdía O(dT²). (B5-25)
  el libro se acumula ANTES de `update_properties` (M4-3) y la FILA del
  audit se escribe DESPUÉS: describe el snapshot y la fila 0 del reinicio
  coincide exacta (`compare_audit` compara también los inventarios de la fila
  N). (B5-27/28/29) `adapt_timestep` parte del dt nominal; `last_step` se
  decide una vez con el dt del paso; el freno de NaN no repite la fila.
  (B5-7/9, corregido por M6-2) el acarreo `ws_cc` nunca se pierde sin rastro,
  pero vive SOLO dentro del acople: fuera de `act_g`, sin gas o en una fila
  sellada se DESCARTA con registro (`ws_cc_drop` → columna `m_gas_ccdrop`;
  conservarlo volvía pegajosa la exclusión de F2.31), el test de venteo juzga
  la demanda con signo (térmica + reacciones + acarreo), y las celdas outlet
  no plantean demanda ni acarrean. (M6-1) La cota `COMP_SRC_CAP` es el 20 %
  del gas que ATRAVIESA la celda en el paso (propio + entrante), no del
  propio: en un poro con caudal pasante la contracción del gas caliente que
  entra vale 1.2–1.6 × el gas propio por paso. (M7-5) El caudal entrante de
  la cota (`ws_qin_cap`) se CONGELA en la primera llamada del paso (la cota
  no depende del iterado `u*` de cada iteración externa) y solo cuenta caras
  con gas RESUELTO (α_g ≥ ALPHA_CUTOFF) en las dos celdas: nunca acumularlo
  antes de esa guardia ni con la α de cara simétrica (caudal fantasma ½α_P u
  A desde vecinas con gas evanescente de `ws_gas_reach`).
  (B5-1/2) el nodo líquido de la cara es continuo por `ws_liq_cont` y el área
  lleva la rampa (1 − fbed). (B5-4) la rama de UNA fase (flujo sin dos
  fluidos) es legada: `oneflow_test` la vigila con xfail con causa (corriente
  fantasma 0.2 m/s, ferrostática 2 %, energía creada) y la radiación está
  prohibida en ella. (B5-11) el clip sin flujo entra negativo. (B5-13) la
  escoria no ocupa el gas de poro. (M6-4, reemplaza a B5-14) la reducción de
  FeO va en DOS fases: solicitud por celda, huecos congelados con halos y
  reparto fijo —el Fe va PRIMERO a la propia celda de escoria hasta su hueco
  y el sobrante al baño de abajo hasta lo que le deja su escoria—; no hay
  pasada 3 (devolvía Fe sin cota: Σα > 1) y con prioridad al baño de abajo la
  escoria apilada reducía la mitad. (M6-3) el CO va al gas de la celda solo
  si le queda gas después del Fe. (B5-24) este archivo vive en el repo.
- **Lo que NO funcionó en la ventana 280–370 s (oct-2026)**: la salvaguarda de
  water packing de RELAP5 §3.4.6 / TRACE cap. 2 (F2.32, archivada en
  dev-history) casi no se activa — la succión del piso del lecho no es water
  packing clásico. No reintentarla sin un mecanismo nuevo que la justifique.
- **`intent(out)` en dummies de tipo derivado que llegan PARCIALMENTE
  inicializados = basura (bug latente hasta oct-2026)**: `mesh_generate_parallel`
  recibía `mesh` (con `mesh%topo` ya llena) como `intent(out)`; el dummy queda
  indefinido al entrar y a -O0 la topología era basura (a -O2 sobrevivía por
  casualidad → halos basura esporádicos, NaN a n=2, reinicios no
  reproducibles). Regla: `intent(inout)` para todo tipo derivado que ya traiga
  estado; y `make debug` (-O0) DEBE arrancar — si no arranca, hay un
  indefinido, no un "problema de flags".
- **Un array asignado con `mold` y escrito solo en celdas propias NUNCA se
  copia entero a un campo (Bug 22, oct-2026)**: `liq%alpha = a_new` con
  `a_new` de `mold` dejaba los halos FÍSICOS (eje, pared, piso, techo,
  esquinas) con basura del heap — nadie los escribe ni los intercambia — y
  todo lo elemental de array completo (`liq_continuous`, `ws_liq_room`,
  máscaras de superficie libre) la leía: corridas no reproducibles según la
  presión de memoria de la máquina (idénticas unas veces, 10 % de
  diferencia otras; reinicio no bit a bit). Regla: `allocate(x, mold=f);
  x = f` y luego escribir lo propio. Detector definitivo: `malloc` interpuesto
  que rellena con NaN señalizante + `-O0 -ffpe-trap=invalid`
  (`scripts/diag/snanfill.c`): la primera aritmética sobre basura aborta con
  traza; `MallocPreScribble=1` solo delata que existe. Antes de cerrar
  cualquier gate de reinicio/invarianza, repetir la corrida fría dos veces
  en serie y compararla a 1e-12.
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
- **Intercambio de CALOR gas–líquido con la misma morfología (auditoría 3,
  A3-2)**: en el lecho (α_s ≥ 1e-2) película sobre la chatarra (área
  6α_s/d_p × fracción mojada, Ranz–Marshall con d_p); fuera, el líquido
  CONTINUO (`ws_liq_cont`, incluida la celda de superficie con cualquier
  α_l) es interfase resuelta (|∇α_l|, placa L = dz) y el DISPERSO lleva la
  logística AIAD hacia gotas (6α_l/d). **Auditoría 4, A4-3**: la logística
  en α_l aplicada al continuo daba f_disp = 0.5 en α_l = 0.3 y la celda de
  superficie que cruza 0.3–0.45 al llenarse recibía área de gota (×1200 en
  el umbral; el gas de la capa salía a T_l en un paso, el síntoma que A3-2
  decía cerrar). `test_gas_liquid_ht` caso 7. Con `liq_continuous` elemental la celda
  de superficie con poco líquido recibía el área de gota (60–600× la de la
  superficie) y una película uniforme en el lecho (|∇α| = 0) no
  intercambiaba. `test_gas_liquid_ht` casos 5–6 (G a mano).
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
  el paso de REFERENCIA fijo `DT_MOB_REF` = 2 ms (el dt de B1 donde se
  calibró), nunca el dt de la corrida (auditoría 8, M8-2)**: el gas de piso de
  una capa saturada (ε_g = 0.015, la vía de F2.7) tiene movilidad ~0.025 con
  2 ms y 0.01 con 5 ms; con dt ≥ ~6.5 ms la capa cortaba el camino y una bolsa
  bajo el lecho inundado quedaba pared (`pocket_rise_dt10`: sin subir, gas a
  131 m/s). La clasificación es del estado, no del integrador. Es criterio de CAMINO,
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
- **Reinicio desde snapshot (`restart_file`, sep-2026)**: todo snapshot es
  un estado completo (`/fields` + `/restart` + `/metadata`) y el reinicio
  es BIT A BIT contra la corrida continua (test `restart_*`; desde B4-19
  también su `audit.csv`, `compare_audit.py`, más invariantes y audit del
  tramo). **Todo snapshot cierra el intervalo del audit (B4-4)**: con
  `audit_freq > 1` el snapshot y el último paso escriben su línea, así el
  reinicio (que arranca su audit de cero) no pierde nada. Reanudar con
  `t_final ≤ time` no reescribe el origen (B4-5). `/mesh/cell_type` va en
  el snapshot (B4-21: `sum_alpha` exige 1 en activas, 0 en inactivas).
  **Harness (B4-18/22/23)**: NaN en una comparación es FAIL; sin
  `audit.csv` con `audit_freq ≠ 0` es FAIL; el rebaseline no escribe el
  golden si la matriz tiene fallos; el libro del gas lo decide el config
  (B4-24). Todo estado
  nuevo que persista entre pasos (campo, escalar, `save`) debe entrar en
  `write_restart_group`/`restart_read` en el mismo commit — si no, el test
  de reinicio lo delata. Las propiedades (`rho_gas`, `mu_eff_liquid`) se
  guardan tal como quedan al final del paso: la corrida continua arranca
  con las de la última iteración externa, no con las de la T final.
- **Transporte de α_l**: explícito en forma de flujo (donor-cell) con
  sub-pasos CFL uniformes globales — conservación EXACTA (ratio 1.0000);
  fallback implícito acotado si CFL > sub-pasable (avisa por stdout).
  **Limitador de hueco (sep-2026)**: la entrada a cada celda se escala a
  `(1−α_s−α_sl−α_l)·ρV/dt_sub + salida − mdot` (factor `ws_lim`, barridos
  Jacobi con halos HASTA CONVERGENCIA — el "no cabe" avanza una celda por
  barrido; 3 fijos recortaron 2.6 t en B1 v9), aplicado por igual en las
  dos celdas de la cara
  → el fundido que no cabe se ACUMULA encima en vez de recortarse (B1 v8
  perdía 4.4 t en 427 s por el clip). Los flujos efectivos promediados
  quedan en `ws_Fr/ws_Fth/ws_Fz` (`ws_flux_valid`) y la energía del
  líquido los REUTILIZA: nunca recalcular flujos del líquido en la
  energía si el transporte de α ya los produjo. El exceso residual se
  DERRAMA hacia arriba (conservativo, columna `m_spill`, entra a `ws_Fz`;
  una celda LLENA no corta la cascada: recibe el exceso y lo cede en la
  pasada siguiente —auditoría 8: el fondo de un baño lleno recortaba con
  hueco encima—) y solo lo que no cabe bajo el techo va al clip auditado (`m_alpha_clip`,
  contabilizado POR PASO: la última iteración externa, no la suma de las
  5 — `audit_step_delta`). Nunca reintroducir un recorte silencioso de α:
  toda restricción de volumen se resuelve moviendo masa, no borrándola.
  Test: `test_alpha_limiter` (4 casos).
- **Residuales del lazo externo**: se computan con el ITERADO ENTRANTE
  (el campo que queda en pie), jamás con el recién resuelto post-TDMA
  (siempre ~0: declaraba convergencia en 1 outer y perdía (1−α_T) de las
  fuentes por paso — fue el hueco del balance de energía).
- **Emisión radiativa CONSISTENTE con la DO (auditoría 4, A4-5)**: la
  energía (fluido y sólido) resta la emisión κ·4σT_old⁴ que la DO transportó
  (se llamó con T_old), con la pendiente de Newton 16σT_it³ implícita y su
  fuente 16σT_it³·T_it, que se anula al converger. Antes el nivel era
  12σT_it⁴ (emisión a T_it al converger): 4κσ(T_it⁴ − T_old⁴) de energía
  creada o destruida por paso, 1.2–2.5 % del arco (41 % de lo radiado en
  cold_10step). Ahora `rad_closure` (Σ fases + sólido + pared, tolerancia 5 %)
  cierra a 3.6 % en frío y 0.1 % con baño; el 1 % de melt_forced era el
  reparto por fase con α^{n+1} (M5-1, cerrado: +51 J). Re-resolver la DO por
  iteración externa NO ayuda: la pared se contabiliza por llamada.
- **Libro de MASA del gas (auditoría 4, A4-6)**: columnas `m_gas_out`
  (venteo neto a las celdas outlet con los flujos conservativos `ws_Fg`) y
  `m_gas_rxn`; identidad `mass_gas`: Δm_gas = −venteo + volfix + reacciones +
  (lo que la EOS reescribe). **N-M4, auditoría 6**: medido con una sonda de
  balance por celda, casi todo el residuo era el gas FANTASMA del volfix de
  la fusión antes del SIMPLE (el volumen que deja el sólido es del líquido
  pendiente `mdot`, que el transporte añade en el SIMPLE; el volfix lo
  rellenaba con gas registrado como creado y el transporte lo destruía por
  complemento sin registro). `enforce_volume_constraint(pending_melt)` lo
  reserva al líquido (solo al FUNDIR: con el pendiente de la congelación
  bath_freeze pasaba de 97 a 202 kPa). Y la cota `COMP_SRC_CAP` sobre el gas
  propio recortaba la contracción del gas que atraviesa los poros (M6-1).
  Residuo ahora: bed_drain 1.8 %, cold 3.5 %, bath_fill 10 %, arc_melt 13 %,
  bed_flood 23 %, melt_forced 32 %; lo que queda es la congelación
  (bath_freeze 12 %), el lazo externo truncado y el gas fuera del acople.
  **Auditoría 8 (M8-3), medido**: el lazo externo TRUNCADO es la parte
  dominante fuera de la congelación. Con 20 iteraciones en vez de 5,
  melt_forced baja de 32 a 3.5 % y pocket_rise de 44 a 0.9 %; bath_freeze
  apenas cambia (12 → 11.5 %). El desfase α–p de 5 iteraciones VENTEA gas
  que la EOS vuelve a crear (pocket_rise: 0.92 kg de venteo con 0.52 de
  pérdida real), y crece con el dt (10 ms: 1.50 kg, gas 99 m/s por los huecos
  de los electrodos). B1 corre con `max_outer` = 5: decisión abierta. `E_conv_gas − E_out_conv` es, en
  forma T, la entalpía de esa masa: el «defecto convectivo» del gas no es
  numérico. Gate `mgtol` 0.5 (regresiones); el juez es B1 (N-M4 abierto).
- **Identidad de energía POR PASO (A4-4)**: además de la acumulada, cada paso
  desde el 2 cumple |gap| ≤ 0.1·S_gas + 1e-9·S_ext + 5e-5·S_int (piso
  1e-8·E_tot): el htol acumulado existe para el paso 1 (fusión instantánea
  con 5 outers) y después admitía errores del tamaño del arco. S_int sin
  `E_iph_liq` (= −E_iph_sol, contado dos veces).
- **Auditoría de energía**: hooks exactos en solve_energy_3d
  (energy_audit_hook, linearización de Newton en T_it del ensamblado); el
  balance se escala contra el throughput bruto. arc_budget cierra a 1.0000
  con `E_mc_lost` (beams que escapan).
- **Orden del paso**: fusión+colapso ANTES del lazo SIMPLE
  (update_solid_premelt); interfase DESPUÉS de los solves de energía
  (update_solid_postenergy) — moverla antes duplica el calor.
- **CFL azimutal**: `dth_len = max(r·dθ, dr)` — el anillo del eje no
  gobierna el dt (esquema implícito; escala advectiva ≥ ancho radial).
- **Coeficientes de ensamblado**: los 8 arrays (aW..aT, aP, Su) viven en
  `mod_workspace` (persistentes, C4.1). Todo ensamblador nuevo debe cerarlos
  completos antes de usarlos — esa es la condición que hace seguro
  compartirlos. Vale también para los halos: el intercambio MPI NO escribe
  los halos de frontera física (eje, piso, techo, pared); si un array de
  trabajo se lee ahí, hay que cerarlo COMPLETO en cada llamada (B1 v10:
  basura en `ws_Mr(0,:,:)`/`ws_Mz(:,:,0)` creó 143 t de líquido).
- **Radiación DO**: proyecciones de cara integradas exactas en cilíndricas
  (cierre a máquina); NO es invariante a rotaciones de 120° (efecto de rayos
  de la cuadratura S4) — el config de simetría corre con radiación off.
- **Química**: O₂ transportado y finito (horno sellado — sin ingreso de aire
  modelado); ambas cinéticas limitadas por el suministro local de O₂ del paso;
  carbono como inventario `sol%m_C` (`carbon_frac`, default 0.5 %).
  **El carbono oxidado SALE del acero** (`m_s`, `E_s`; columna `m_C_oxid`,
  auditoría M15) y su entalpía pasa al gas. **Especies con dilución**
  (M14): la masa del gas la fija la EOS, así que la masa que aportan las
  reacciones entra al Poisson como fuente de volumen S_gas/ρ_g y en las
  especies como −Y_k·S_gas (columnas `m_dil_*`); ΣY ≤ 1 por construcción.
  Difusión de especies con conductancia de CARA armónica (M16). **Sin
  transporte de α de dos fluidos (`solve_flow` o `solve_multiphase` off)
  nadie repone el gas que la química desplaza (auditoría 3, A3-7)**: tras la
  química se llama `enforce_volume_constraint(..., sh)` (α_g = complemento,
  masa en `m_gas_volfix`) y el gas CREADO no trae especies (Y diluida por
  α_old/α_new: la masa de O/C se conserva, check_chem 5e-13; sin la dilución
  el relleno del poro creaba O y C de la nada). El Fe que la escoria devuelve
  al baño nunca pasa del hueco de ninguna celda (A3-7: slag_chem_test tenía
  α_l = 1.000104); el reparto vigente es el de M6-4 (propia celda primero, el
  sobrante abajo; ver la sección de la auditoría 5).
  `check_invariants` corre en TODA la matriz.
- **P_elec del arco va al BAÑO, nunca a trazas de líquido (auditoría 3,
  A3-4)**: tras el bore-in, solo celdas con α_l ≥ `ALPHA_LIQ_CONT` de la capa
  más alta con baño bajo la punta (`kg_bath`), peso α_l V; sin baño en la
  columna, por volumen con reparto por absorción. Con `any_liq` a 1e-6 una
  gota en la columna recibía los ~5.5 MW del electrodo (symmetry_3elec: el
  «líquido» absorbía 0.145 del arco por trazas; ahora 0.026).
- **Superficie del arco por CONTENIDO ponderado y P_elec a esa misma
  superficie (auditoría 4, M4-7/M4-8)**: la primera capa bajo la punta con
  material ponderado por la gaussiana sobre el umbral (hoy por material, ver
  la sección de la auditoría 5: M6-5/M7-1) (hasta 4σ: un corte duro a 2σ
  dejaba la pertenencia de las celdas del borde al redondeo y rompía la
  simetría 120°) es chatarra o baño según la regla de tres regímenes de
  M8-1/M9-3 (ver la sección de la auditoría 5); el P_rad directo
  pesa la chatarra EXPUESTA (rampa 1 → 0 entre α_l 0.2 y 0.4); P_elec va a
  la capa del baño (gaussiana, α_l V) solo cuando la superficie es baño y si
  no se deposita con P_conv (antes buscaba baño en 2 R_elec saltando la
  chatarra: 0.2 P_arc a una capa enterrada). **El lazo externo no es
  contractivo en el régimen de superficie de baño bajo el arco**: con 60
  outers y tolerancias inalcanzables el iterado se aleja de la simetría
  (1.7e-9 tras 5 outers → 8.5e-4 tras 60 en un paso); `symmetry_3elec` corre
  con el lazo de producción (5) y queda como hallazgo de modelo (B3-14).
  **Banda del P_rad directo = superficie y capa de ENCIMA, nunca k−1
  (14-oct)**: con la superficie por contenido la capa elegida es el piso del
  cráter y k−1 es chatarra enterrada que no ve fotones (arc_melt 27.8 → 8.4 kg
  con la banda ±1; 36.8 kg sin ella). La fracción no expuesta de una celda
  (rampa) va a su propio fluido (charco), no a las vecinas. Lección: `arc_melt`
  es el único banco del régimen de B1 y entonces solo corría en `test-full`
  — tres commits pasaron `test-quick` con la regresión dentro; desde fc15c60
  está en `test-quick`, y desde la auditoría 5 (M5-8) también
  `bed_bath_rest`, el único banco que vigila la bomba de A4-1.
- **M4-12, gas bajo una capa saturada (auditorías 6-7)**: banco
  `pocket_rise` (bolsa de gas bajo la capa 8 saturada; estado construido por
  `make_pocket_init.py` con presión HIDROSTÁTICA de la nueva estratificación y
  `rho_gas` de la EOS). Con los defaults el gas sube a contracorriente desde
  el primer paso. El estado hidrostático NO es punto fijo (auditoría 8,
  M8-3): la capa saturada drena por Darcy y su peso pasa al arrastre del
  lecho (la presión del piso baja ~20 kPa, físico) y la bolsa se
  despresuriza y ventea por los huecos de los electrodos (gas ~30 m/s). El
  banco corre con `max_outer` = 20 (con 5 el desfase α–p ventea gas
  fantasma: 45 m/s). El juez (auditoría 9, M9-1) mide la presión de la bolsa
  DIRECTAMENTE frente a la capa de encima conectada al gas (±1 kPa desde
  t = 0.10 s; sana −6..+12 Pa, tapada +31.8 kPa): ni `max|p|` (siempre el
  piso) ni el exceso sobre la hidrostática (cae al drenar y deja 13–20 kPa de
  holgura) veían una retención. Además, el cierre de masa del gas, el máximo
  del gas en TODA la corrida y el dt real de la corrida. La
  «retención de 0.25–0.3 s» medida en la auditoría 6 era el estado construido
  con la presión del snapshot de origen, NO el modelo; la opción
  `pc_bed_gas_pocket` que se añadió para quitarla se RETIRÓ (con el estado
  coherente soltaba 45 m/s en el paso 1). Lección: un estado construido a mano
  debe ser un punto de equilibrio del modelo (presión y EOS) antes de juzgar
  nada con él. El juez para la bolsa real de B1 sigue siendo B1.
- **Energía del gas = inventario LOGARÍTMICO, una sola definición (auditoría
  4, M4-13)**: la masa del gas la fija la EOS (ρ ∝ 1/T a p fija), así que su
  energía es `C_g ln(T/T_ref)` con `C_g = α ρ_ref T_ref cp V (P0+p)/P0`
  (`gas_inventory_cell`/`gas_heat_capacity_ref` en mod_audit; el audit, el
  volfix y la escoria la usan). Todo «poke» a `gas%T` con capacidad lineal
  `αρ(T)cpV` es solo de primer orden: con gas a 300 K tocando escoria a
  1800 K el poke de `slag_energy` perdía el 30 % de Q (slag_chem_test, paso
  1: 1.0e6 J sin columna). Regla: calor Q al gas a α fija ⇒
  `T = T·exp(Q/C_g)`, y el equilibrio de dos nodos se resuelve en la forma
  no lineal (sin sobrepaso). Toda reescritura de α_g (restricción de
  volumen, flotación de escoria) crea/destruye gas: masa Y energía de
  inventario auditadas (`m_gas_volfix`, `E_gas_volfix`); con `solve_energy =
  false` la identidad corre sobre los inventarios si hay fuentes.
- **Intercambio gas–líquido por SUPERFICIE RESUELTA = por CARAS (M4-10)**:
  con interfase nítida ninguna celda tiene las dos fases; la cara vertical
  k|k+1 con `|Δα_l|` acopla la celda de más α_l (nodo líquido) con la otra
  (gas), `h = k(2/dz + 0.664 √Re Pr^⅓/L)` con L = max(R_shell, dz) — la
  conducción `2k/dz` es lo que deja intercambiar a un gas en reposo (con
  L = R_shell solo, bath_test_cold no intercambiaba nada) y L largo quita la
  dependencia h ∝ dz^-½. Película del lecho y gotas con rampa `fbed` en
  α_s 1e-2..2e-2 (M4-9), nunca interruptor duro. Banco: `bath_test_cold`.
- **MC del arco**: beams repartidos round-robin entre ranks; TODOS los ranks
  consumen la secuencia RNG completa (determinismo por paso). El depósito se
  reduce con MPI_SUM => no bitwise (~1e-13 en corridas regulares).

## Hard-won fixes — do not regress

`docs/ARCHITECTURE.md` §10 lists 10 resolved critical bugs with root causes (halo lower-bound offsets, PHDF5 deadlock, arc power `abs(V*I)` instead of `I²R`, residual-norm denominator anchoring, melting energy accounting, interphase heat-transfer clamp, MC radiation step size excluding halo `dr`). Before "simplifying" a guard, clamp, or seemingly redundant term in those areas, check that list — most exist to prevent a specific NaN, deadlock, or divergence.
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
