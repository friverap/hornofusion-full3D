---
paths:
  - "src/mod_continuity.f90"
  - "src/mod_energy_3d.f90"
  - "src/mod_audit.f90"
  - "src/mod_interphase_ht.f90"
  - "src/mod_radiation_do.f90"
  - "src/mod_properties_3d.f90"
  - "src/mod_solver_3d.f90"
  - "tests/integration/check_audit.py"
---

# Transporte de alpha, energia, radiacion DO y auditoria de balances

Convenciones vigentes movidas TEXTUALMENTE desde CLAUDE.md (reestructuracion
harness, 16-oct-2026). Cada una existe por un fallo medido: no simplificar una
guarda sin leer su causa.

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
  una celda llena DE LÍQUIDO —sin escoria (α_sl < ALPHA_CUTOFF) y con α_l ≥
  ALPHA_FLOW_CUTOFF— no corta la cascada: recibe el exceso y lo cede en la
  pasada siguiente (relevo); una celda llena con ESCORIA o una COSTRA sólida
  NUNCA se atraviesa —el acero quedaría sobre la escoria—, auditoría 11 A11-2,
  traído de main d4800f8/10c8fd5; con escoria arriba DENTRO del lecho la
  cascada reserva el gas de poro con una rampa absoluta, fslag = min(1,
  α_sl/ALPHA_FLOW_CUTOFF): desde α_sl ≥ 1e-2 el tope es `liq_cap` (el poro de
  la escoria era un conducto y el acero la cruzaba), con traza ~ el hueco
  físico de F2.8 (auditorías 15–17). Lo que la cascada no sube bajo una interfaz
  de escoria NO va al clip: la escoria CEDE (oct-2026, A11-2): entra en la
  celda de escoria y `slag_buoyancy` sube la escoria al final del paso;
  banco `arc_melt_slag`) y solo lo que no cabe bajo el techo (o bajo una
  costra llena) va al clip auditado (`m_alpha_clip`,
  contabilizado POR PASO: la última iteración externa, no la suma de las
  5 — `audit_step_delta`). Nunca reintroducir un recorte silencioso de α:
  toda restricción de volumen se resuelve moviendo masa, no borrándola.
  Test: `test_alpha_limiter` (casos 1-12; con escoria: el exceso entra en su celda, casos 6/8/10/12). **Convergencia del limitador
  (auditoría 9, M9-6)**: el Jacobi del factor es MONÓTONO desde 1 (siempre
  sobreadmite) y en un baño LLENO al que el Poisson pide meter líquido (lecho
  que drena encima) converge geométricamente lento (1.4 %/barrido en la
  llamada más lenta medida, pocket_rise_dt10 paso 48, banco de la línea main; 7–12 % en otras) y agota
  `N_LIM_MAX`; el exceso que deja lo mueve el derrame (`m_spill`, auditado y
  conservativo; cuenta MASA POR SALTO, así que una cadena de relevo de L celdas suma L veces la masa: cota superior del error, no la masa movida): ESE es el error, no `dlim`. **Con escoria (A11-2, CERRADO oct-2026)**: la interfaz de escoria corta el relevo, pero el exceso que queda bajo ella ya no va al clip: la escoria CEDE (entra en su celda y `slag_buoyancy` la sube; arc_slag 10 s: clip 3.7 kg → 1.7e-9). El diagnóstico `[LIM]` estima la
  distancia al punto fijo (`dist_est` ≈ dlim r/(1−r)). Probado y NO adoptado:
  el hueco con signo (bath_freeze: derrame 10.4 → 2.1 t, pero volumen
  bloqueado +58 % y gas recreado 11.5 → 16.9 %: agranda el desfase α–p). No
  acelerar con extrapolación ni arranque en caliente: el mapa tiene familias
  de puntos fijos en lazos que conservan caudal. El origen es el desacople
  α–p (Plan D); magnitud en B1 sin medir.
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
  (bath_freeze 12 %), el lazo externo truncado y el gas fuera del acople. `E_conv_gas − E_out_conv` es, en
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
- **Radiación DO**: proyecciones de cara integradas exactas en cilíndricas
  (cierre a máquina); NO es invariante a rotaciones de 120° (efecto de rayos
  de la cuadratura S4) — el config de simetría corre con radiación off.
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
