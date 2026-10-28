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
  barrido; 3 fijos recortaron 2.6 t en B1 v9 — con tope `N_LIM_MAX` = 256
  barridos: si se agota, el exceso que deja el punto fijo no convergido lo
  mueve el derrame (`m_spill`), ver M9-6 abajo), aplicado por igual en las
  dos celdas de la cara
  → el fundido que no cabe se ACUMULA encima en vez de recortarse (B1 v8
  perdía 4.4 t en 427 s por el clip). Los flujos efectivos promediados
  (Plan J-B, `pc_transport_f28` ON: una cara continuo|continuo que el
  Poisson dejó sin enlazar por F2.8 lleva G = 0 en r, θ y z; el hueco
  de poro que lo decide está congelado en α^n)
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
  **WS-K5 (C-106..C-110, 24-oct-2026)**: en B1 el residuo es una deriva
  continua (~−5e-5 kg/paso): ~60 % lazo externo truncado (max_outer 5 nunca
  converge; vive en gas libre y lecho) y un piso ~1/3 de la EOS TOTAL en
  300 pasos que no baja con más externas ni con alpha_T y vive en celdas
  multifase (en las ventanas de K7 e_multi SÍ depende de las externas: ver
  WS-K7; errores +5e-3/−6e-3 kg
  en 59 pasos que se compensan; el neto ≈ −la entrada por el outlet).
  HIPÓTESIS (C-110): el complemento α_g = 1 − Σ crea gas donde el líquido
  se retira y lo destruye donde entra, sin flujo de gas. Resultado de WS-K7
  (C-168): SIN DECIDIR por celda; en las celdas sin gas la masa es flujo de
  gas exportado por el Poisson, no creación por el complemento; la
  alternativa «caras no enlazadas (ws_Fg_lk = 0)» es NULA (C-120); ver el
  párrafo de WS-K7. Hecho medido: el inventario nunca recibe el
  flujo del outlet, solo cambia por la EOS y el complemento. Columnas
  diagnósticas `m_gas_err_free`, `m_gas_err_multi`, `m_gas_err_abs`,
  `m_gas_err_out`, `m_gas_cells_skip` (balance POR CELDA con escoria en la
  clase y clase de inicio Y fin de paso; cierre al redondeo; **WS-K6**: e RESTA el volfix de cada celda, que las
  6 rutas de `AUD_GAS_VOLFIX` registran con `audit_volfix_cell` (columna
  `m_gas_vf_cells`; check `mass_gas_vf_cells` exige que iguale a
  `m_gas_volfix`: una ruta NUEVA de volfix sin `audit_volfix_cell` lo hace
  fallar); el cierre queda EOS − celdas = venteo; fuera de mass_gas;
  **WS-K7 (C-120..C-168)**: la «alternativa» de transporte por caras
  `ws_Fg_lk = 0` es NULA (ws_Fg vale 0 ahí: se anula en cada Poisson y solo
  se escribe con lk = 1). El inventario del gas solo cambia por TRES rutas,
  identidad exacta `mass_gas_rewrites`: Δm_gas = `m_gas_comp` (complemento
  α_g = 1 − Σ en los 3 sitios de mod_continuity, `audit_comp_cell`) +
  `m_gas_eos` (`update_properties`, `audit_eos_cell`) + volfix; resto
  ≤ 4e-12 kg en 78 bancos y −3e-14 en 5499 pasos de B1, con tolerancia
  1e-11·(Σ|comp| + Σ|eos| por llamada + Σ|volfix| por paso) + 1e-14·max
  m_gas + 1e-12 (`m_gas_comp_abs`/`m_gas_eos_abs` son Σ|dm| POR LLAMADA);
  toda reescritura nueva de α_g o ρ_g lleva su gancho o el check falla. La
  hipótesis C-110 (complemento sin flujo de gas que lo lleve) se mide por
  celda multifase como err_liq = ρ_g (V_pois,in − V_eff,in), con V_pois =
  ws_Fc enlazado + la E2 que el ÚLTIMO Poisson sumó a `Su`
  (`ws_pc_unl_used`; `ws_pc_unl` lo reescribe el transporte posterior) y
  V_eff = ws_Fr/Fth/Fz/ρ_l. `m_gas_err_liq_all` lo suma en TODAS las
  multifase (C-121) y `m_gas_err_liq` solo en las que tienen gas al inicio
  o al final (C-126; en k7v5_mo20 −2.97e-3 kg frente a +4.88e-4 de _all).
  Reparto por celda, identidad por construcción: `m_gas_err_liq_lk` :=
  err_liq − `m_gas_err_liq_unl`, con unl = ρ_g dt (E2 aceptada − E2 del
  transporte N) (desfase; −ρ_g dt unl(N) donde el Poisson no aceptó E2; 0
  sin E2 aceptada válida, y entonces todo cae en lk). Como `unl_vol` es la
  parte no enlazada de los mismos `Fw..Ft` de ws_Fr, lk se lee como el
  desajuste en caras enlazadas (limitador, α dador/a_f, ρ̄ de cara/ρ de
  celda; derrame solo con pc_spill_source = false). En 280 s el desfase
  pesa ≤ 0.2 % de Σ|err_liq_all| y 2 % del neto. 1 − Σ|e − err_liq|/Σ|e|
  (`m_gas_err_rem_abs`) es un residuo por resta que mezcla escala y
  correlación: NO es atribución de mecanismo. Veredicto (k7v5_mo20: 280 s,
  20 externas, 59 pasos tras reinicio; el único banco de K7 que pasa
  check_audit): SIN DECIDIR por celda con todas las definiciones del
  conjunto (rem/abs 0.319 sin filtro, 0.57 con filtro) y el inciso del NETO
  falla (1.57). El 0.319 es media de 0.384 (celdas con gas) y 0.163 (sin
  gas, identidad de fila): no es evidencia a favor de H. El inciso por
  celda es FRÁGIL frente al CG en ambas direcciones: en los bancos de test
  con el CG convergido rem_all/abs va de 0.134 a 1.007 (5 de 8 en la banda
  de refutación) y esos bancos no predicen B1; el «sin decidir» global
  (falla el neto) solo protege contra «soportada» (C-163). En ventanas largas
  rem/abs deriva hacia la refutación, en bancos que NO pasan check_audit:
  0.314 → 0.349 en 1 s con 20 externas (k7v5_mo20_1k, FAIL regime_gas 209);
  0.43 → 0.53 en 5.5 s con 5 (k7v4_long, máximo 0.57, no monótono,
  centinela de u_gas desde el paso 4340). e_multi DEPENDE de las externas
  en K7 (×1.84 en 59 pasos; 43 % en 999); la independencia de C-109 es de
  la EOS total en 300 pasos. Sobre el piso NETO el WS NO concluye:
  corr(e − err_liq_all, e) = 0.97 la fuerza el cociente de amplitudes
  (C-140), y la exportación de gas de las celdas sin gas (e_nogas entre
  +2.7e-3 y +4.2e-3 kg en 59 pasos) se CANCELA POR CONSTRUCCIÓN en e_multi:
  ws_Fg es conservativo y sus vecinas con gas son multifase (1213 de 1214
  caras en 280059; la dirección no está medida), así que el neto vive en
  Δm_multi y en el flujo de gas por la FRONTERA del conjunto multifase, que
  ninguna columna mide (C-150). Celdas con α_g = 0 al inicio y al final
  (29 % de Σ|e|): baño lleno (α_l ≥ 0.995) en las capas 2–4 desde el fondo
  (índice h5 k = 1–3), el 94–97 % sobre poro seco de la solera (en act_g,
  C-153); 406–488 celdas con α_g = 0 al final del paso en 5 snapshots
  (research/ws/WS-K7/scripts/nogas_vecinas.py). Ahí e ≈ −dt ΣF_g
  (complemento y EOS ≈ 0) y la fila del Poisson da Σ|ρ_g V_pois| =
  0.83–0.85 de Σ|e|: el Poisson planea una entrada NETA de líquido que el
  transporte no realiza (V_eff neto ≈ 0 por construcción en celda llena) y
  exporta el gas correspondiente por la α de cara MEDIA del gas (F2.24) con
  la celda en act_g por alcance. La identidad de fila vale en TODA fila del
  Poisson y no distingue mecanismo: quién conduce (la demanda del líquido,
  como en la válvula ficticia de Plan E, o el flujo fantasma del gas por
  F2.21 + F2.24, con u_z del líquido p10 −0.28 / p90 +0.76 m/s ahí, que
  refuta la premisa de F2.21) NO está medido; Plan E queda solo como
  antecedente y su población es otra, en parte POR DEFINICIÓN: las celdas
  de la válvula son poro saturado con α_g = ALPHA_PORE_GAS = 0.015 > 0 y
  nunca entran en esta clase; si la válvula actúa, cae en el subconjunto
  con gas (71 % de Σ|e|), donde K7 no la buscó (C-165; poro saturado: 7–19 %
  de las caras de estas celdas). Tampoco están medidos: si la
  celda es ciega o de paso; por qué caras y en qué dirección sale el gas
  (una reconstrucción aproximada sugiere entrada por arriba y salida
  lateral, C-153); ni su tamaño frente a vol_lim (`m_gas_rej_nogas` es un
  estimador bruto que no se interpreta). La insensibilidad a las externas
  (Σ|e|_nogas 4.82e-3 kg con 20 y 4.83e-3 con 5) es solo compatible con que
  no sea lazo truncado y no separa el residuo del CG; la identidad de fila
  acota CG + ρ de cara/celda + E2 en ≤ 16–18 % en B1. Con el CG convergido
  se cumple al ≤ 3 % en los bancos de test con claves por defecto, donde el
  término pesa 0–4 % de Σ|e| (29 % en B1) y no contienen la población de
  B1 (0 % de sus celdas sin gas sobre poro seco, C-164), y al 10 % en bed_flood_n4
  (claves de Plan D/E no por defecto) (C-158/C-162): existe con el CG
  convergido pero ahí es marginal; su peso en B1 no está separado del CG
  truncado ni del régimen. Esos ws_Fg ≠ 0 de celdas con α_g = 0 los
  reutilizan la energía y el momento del gas (mod_energy_3d,
  mod_momentum_3d: flujos de masa del Poisson), en tensión con «una celda
  sin fase no intercambia energía de esa fase»; no medido (C-162). NO es vía
  a E1b sin revalidación (C-089); la α del dador para el gas en el Poisson
  o sacar del alcance al baño del piso chocan con F2.17–F2.21 y F2.24
  (acople-pv.md). Complemento neto: |comp_multi del signo del piso| ≤
  (Σ|comp| por llamada − comp neto)/2; con 5 externas al menos el 32–61 %
  de e_multi por bloque de 1000 pasos no es complemento neto, compatible
  con el lazo truncado de 5 externas y con el régimen de centinela; con 20
  externas la cota no restringe (C-152). En bancos SIN líquido
  (cold_10step*, cold_bucket2_n4, outer_conv_n8) hay error multifase con
  complemento 0, un transitorio de arranque en frío (outer_conv_n8: ~1e-3
  kg/paso que decae y cambia de signo en el paso 10; 3e-4–3.5e-3 de |EOS|)
  cuyo origen no está separado (residuo del lazo externo con tol_cont 1e-2
  u otro, C-155); no es H. `check_audit` (INFO `mass_gas_cells_liq`):
  «1 − rem/abs = 0.000» con Σ|e| multifase en los bancos sin líquido; «n/a»
  sin filas con err_liq evaluado (escoria condensada, fallback implícito),
  con escoria por el camino legado (slag_in_volume = false: el audit evalúa
  err_liq pero V_eff es solo acero y el complemento resta la escoria) o con
  Σ|e| multifase = 0; «no medido» para err_liq_all, sin cara enlazada,
  Σ|e| sin gas y Σ|dm| por llamada cuando faltan en CSV antiguos. Las
  celdas con 0 < α_g < ALPHA_FLOW_CUTOFF SÍ tienen complemento y EOS (sin
  umbral); fuera de act_g su F_g es 0; en act_g por alcance (F2.21: celdas
  fuera del lecho junto a gas percolante; no depende de su α_g PROPIA)
  PUEDEN exportar F_g ≠ 0 por la α de cara media, como las celdas sin gas;
  su F_g no está medido (C-157/C-161). Siguiente pieza: `su_cc` frente a
  `m_gas_eos` por celda y por conjunto (un desajuste su_cc–EOS explicaría
  como máximo el 71 % de Σ|e|: en las celdas sin gas eos = su_cc = 0),
  comp/eos por conjunto y flujo de gas por la frontera del conjunto
  multifase (hecho en WS-K8);
  **WS-K8 (C-169..C-197)**: el Poisson exporta la demanda de compresibilidad
  que sumó a `Su` (`ws_su_cc_used`), su término advectivo (`ws_gadv_used`) y
  el almacenamiento de la fila (`ws_store_gas` real, `ws_store_art`
  artificial: compliance, piso D2.4 y acústico del líquido). Plan del Poisson
  por celda = err_liq_all + err_cc + err_art, con err_cc = eos + ρ_g dt
  (su_cc − gadv − store_gas) − rx (gadv se resta porque `ws_Fg` ya lleva la
  densidad del dador) y err_art = −ρ_g dt store_art. `su_cc` NO es «demanda
  térmica + gadv»: es clamp(fsat·(−src + gadv) + acarreo/dt + S_rx/ρ_g), y
  el plan usa ESA `su_cc` (`ws_su_cc_used` = lo sumado a `Su`). Como la fila
  la realiza en flujos, `su_cc` aparece igual en fl + ρ_g V_pois que en cc y
  se cancela en rem2: fsat, el acarreo y el tope solo sobreviven en rem2
  dentro de (ρ_final − ρ_iterado)/ρ·su_cc, de orden (Δρ/ρ)·Σ|cc|, que NO es
  despreciable en el gas libre (Σ|cc| = 4070 Σ|e|: basta Δρ/ρ ≈ 2e-4 para
  dar todo rem2_libre, C-190); como tales pertenecen a err_cc frente a la
  EOS; en el gas libre fsat = 1 (`fsat_cell` < 1 exige α_s ≥ ALPHA_BED =
  1e-2, y la clase libre α_s < 1e-2 al inicio y al final; excursiones
  intra-paso no contadas) (C-188, corrige C-181). En el residuo rem2
  = e − plan la EOS y rx se CANCELAN (err_cc contiene la EOS): rem2 mide el
  cierre de la fila del Poisson en masa y que el complemento siga al líquido
  realizado, NO contrasta la EOS (C-178/C-180); la parte de store_gas que la
  EOS no realiza (sh%p avanza alpha_p·pp; ws_Fg usa el pp completo) cae en
  err_cc, no en rem2. Por la misma cancelación, corr(e_multi, plan) por paso
  (0.93) NO es evidencia: reexpresa que la sd del neto de rem2 es pequeña
  frente a la de e (C-181). Reparto por conjunto: e = comp + eos − flujo
  entrante − rx (`m_gas_{comp,eos,flux,rx}_{multi,free}`;
  `mass_gas_class_split` es `mass_gas_rewrites` por clase, tautológico en el
  flujo; el cierre no tautológico es `mass_gas_flux_closure`: flux_multi +
  flux_free + m_gas_out = 0 por paso; desde WS-K9 `m_gas_out` se acumula
  con flujo de dos fluidos aunque `solve_energy` = false, banco
  `cold_flow_noenergy`). En la ventana de 280 s el CG NO
  converge con 20 ni con 200 iteraciones (residuo reducido ~2e-5 con 200);
  con 1000 sí. Con 20 externas y el CG convergido (k8_cg1000): el inciso por
  celda de C-110 no cambia (0.3156 frente a 0.3186; C-174); rem2/abs = 0.197
  en el multifase es un cierre de la fila al ~5.5 % de su plan (Σ|cc| =
  3.6×Σ|e|); en el gas libre rem2/Σ|cc| = 2e-4 con CG 200 y 1000, así que
  el 0.863 no es residuo del CG (C-173, refutada por la letra); que sea un
  piso de conversión volumen→masa y no un término que le falte al plan es
  HIPÓTESIS. Candidatos que sobreviven a la cancelación: (ρ_final −
  ρ_iterado)·dt·(su_cc + E2 + líquido neto − store) y `gadv` de ensamblaje
  frente al corregido, con las caras que `gas_adv` excluye por la guardia
  ALPHA_CUTOFF (C-188). El almacenamiento
  artificial es despreciable (~5e-8 kg frente a Σ|e| 1.6e-2). El NETO
  multifase es un desfase casi constante del residuo del plan (D, negativo
  en todos los pasos). Barrido de `max_outer` con CG 1000 desde
  judge_otp_280 (k8s_mo{5,10,20,40,80}, C-182 SOPORTADA en C-184): D en el
  paso 1 vale −4.18e-5, −2.31e-5, −2.105e-5, −2.078e-5 y −2.085e-5 kg con
  5/10/20/40/80 externas. Desde 20 externas D es una MESETA estructural que
  no depende del CG ni de iterar más el lazo externo. Con 5 externas D es
  mayor: 1.99 veces la meseta en el paso 1 y 1.76 de media con CG 1000, y
  1.71 y 1.51 con CG 20, la config de B1 (k8_base). No es aditivo (con 5
  externas converger el CG sube |D1| un 16 %) y sale de bancos que C-182 no
  usaba para decidir, y los dos bancos de 5 externas fallan
  `energy_balance` y `regime_gas` (u_gas 215 m/s) (C-187, corrige C-183). Salvedad: el lazo externo no declara convergencia en ningún paso
  de ningún banco (residuos estancados entre 20 y 80 externas), así que la
  meseta es la del iterado estancado (con 41 externas converge en 2 de 59
  pasos, y ahí D = −2.18e-5 y −2.16e-5, dentro de la meseta: evidencia
  parcial, C-193; nunca en los demás). La meseta de D es sobre todo la de
  e_multi (el plan neto por paso es ~+7.2e-6 en todos los bancos), y e_multi
  + e_free en la meseta (~−1.44e-5 kg/paso) es del orden del piso de
  C-109: el barrido NO distingue un sesgo de la fila de un error real de
  masa del gas que el plan no ve (C-193). Con dt 0.5 ms (k8s_dt05) D por paso cae a
  0.38 (C-196, «tasa» por la letra). Que e_multi por paso se quedara en 0.93
  (C-197) era un ARTEFACTO: el primer paso de k8s_dt05 es el
  transitorio del acotado de dt del reinicio (66 % del error); sin el, e
  0.5 ms / 1 ms = 0.32 con todos los pasos y 0.35 (IC90 0.33-0.40) en los
  pasos con p_max < 100 kPa: no se decide si baja mas que linealmente
  (C-223) y el plan no cambia de signo (C-206). No es enganche de fase: con 21 y 41 externas
  D1 queda a 3 % y 0.03 % de 20 y 40 (C-189 SOPORTADA en C-191); D no sigue
  al residuo paso a paso y su extrapolación a res_cont → 0 cae en la meseta
  (C-192, lectura). Coherente con el piso de la EOS de C-107/C-109. El origen de la meseta NO está medido
  (candidatos: el corchete del complemento frente a V_eff o el de la
  conversión volumen→masa de la fila, con los candidatos de arriba). Con 5
  externas el CG convergido baja
  el error del gas libre de 9.2e-3 a 3.6e-3 kg (C-186). Que el flujo neto que entra al multifase iguale en 59 pasos
  la entrada por las celdas de salida es coincidencia de sumas (corr por
  paso 0.09; en 999 pasos el cociente va de +1.39 a −143 por tramos):
  RETIRADO como origen. Con 20 externas el error del gas libre es residuo
  del CG (11× mayor con CG 20). Siguiente: partir rem2 en sus dos
  corchetes ([comp + ρ_g V_eff] y [fl + ρ_g V_pois + cc + err_art]) por
  clase y paso en los bancos de 5 y de 20 externas del barrido,
  a pre-registrar (columnas nuevas en `src/`).
  **WS-K10 (C-202..C-235; WS-K11 C-222..C-278)**: descomposicion EXACTA por celda y clase del
  residuo D = e − err_liq − err_cc − err_art, con la fila del ultimo Poisson
  tras el CG: D = A + Br1 + Br2 + Bgr + Bgq + Bx (`m_gas_pa_*`,
  `m_gas_brho_it_*`, `m_gas_brho_end_*`, `m_gas_bg_rho_*`, `m_gas_bg_q_*`,
  `m_gas_bx_*`; el Poisson exporta `ws_Fgv_*`, `ws_rho_g_used` y
  `ws_pc_res` solo con `audit_freq > 0`; `main_3d` copia la rho previa a la
  EOS final, `ws_rho_g_pre`, y marca el gancho de la EOS). Checks exactos a
  redondeo con tolerancia 1e-13 de una escala BRUTA: `mass_gas_row_volume`
  (fila en volumen), `mass_gas_decomp` (masa) y `mass_gas_eos_end` (valida el
  reparto Br1/Br2, que el cierre en masa no ve porque telescopa); con CSV de
  la primera version (sin `m_gas_dec_scale_*`) el checker usa la tolerancia
  de entonces (C-221); «n/a» con escoria condensada o las dos claves
  `pc_fs_*` (Plan D: caras de superficie libre fuera de la identidad). Los
  cierres y Bx van en `ROUNDOFF_COLS` de `compare_audit.py`.
  OJO: el snapshot judge_otp_280/eaf3d_00280000.h5 lo escribio judge_fh_275
  (20-oct) con `pc_transport_f28` y `pc_outlet_total_pressure` APAGADAS.
  WS-K11 (0.25 ms, una trayectoria por brazo; C-239, C-245, C-248, C-249,
  C-255..C-257, C-265, C-266, C-268..C-278): en los primeros 60 ms tras
  reiniciar con 0.25 ms, ENCENDER f28 sobre un estado escrito sin ella es
  NECESARIO y NO suficiente para la firma (>= 1 paso con celdas multifase
  sin cara enlazada, `m_gas_cells_nolink`, y >= 20 pasos con p_max >= 100
  kPa en 60 ms). La firma NO es exclusiva de ese reinicio: a 1 ms, 4.67 s
  despues de reiniciar con el cambio de f28 (judge_otp_280/eaf3d_00280000.h5),
  k7v4_long la da desde el paso 284669 (284.670 s; C-272), junto a la
  parada de B1 de 284.3 s
  (146 pasos con nolink; ninguno antes). Solo comparte el indicador
  nolink > 0, con otro patron (C-275): k7v4_long tiene un bloque fijo de
  360 celdas (144 de 146 pasos) que entra 0.33 s DESPUES de que empiece
  el episodio por u_gas; los reinicios, 1-16 celdas que fluctuan desde el
  paso 2. Hipotesis de trabajo: no es el mismo conjunto de celdas; los
  datos no apoyan que el cambio con 0.25 ms dispare antes el mecanismo de
  las paradas de B1, pero tampoco lo refutan: k7v4_long usa CG 20 y 5
  externas (>= 27001 resoluciones de CG sin converger de ~27500, frente a
  0 avisos con CG 1000) y un binario del 25-oct (C-277). Lo separaria comparar clase y lugar de las celdas nolink con
  PROBE-P; el mecanismo esta abierto.
  - Pares de UNA clave (solo f28) con firma: fh 280 s (A/F), 285 s (M/I) y
    295 s (O/J; 285 y 295 s hasta P_HYDRO_CAP). En fh 290 s la firma se
    midio encendiendo LAS DOS claves (N/B): f28 sola en 290 s no se probo.
    El estado de 280.06 s escrito por el binario actual (G) da la firma sin
    acotar dt (el binario escritor no es la causa), pero no tiene control
    sin cambio. En fh 300 s encender f28 NO da la firma (P). Todos los
    estados con cambio salen de UNA trayectoria (judge_fh_275): no es una
    tasa (C-271).
  - Ningun reinicio sin cambio la da en 60 ms con 0.25 ms: controles fh
    280-295 s con las claves apagadas (15-20 kPa) y jb/otp con sus claves.
    Entre los brazos con f28 encendida (15 de 20, con k11_dt025_tgfix),
    «sin cambio» y «f28 establecida >= 5 s» van siempre juntos. HIPOTESIS
    no probada y sin escala: lo que cuenta es la edad del cambio (k7v4_long
    da la firma 4.67 s despues del cambio). El final con nolink de F NO
    la hace plausible: su casi gemelo tgfix termina sin nolink (C-273); B,
    sin gemelo, acaba con nolink (C-277). Lo
    decidiria una propiedad del estado medida o los snapshots de
    judge_e1w280_n15 (report.md, Incertidumbre); no corrido.
  - `pc_outlet_total_pressure`: no necesaria en fh 280 s (F, C-249), no
    suficiente en fh 280 s (H, C-257) ni en jb 280 s (E, C-248). Actua en
    las aberturas con electrodo con gas: objetivo p0 - 1/2 rho u_in^2, con
    u_in > 0 solo si hay reflujo; sin reflujo relaja hacia la columna de
    gas p0. En los pasos 0-10 cambia u_gas_max y p_max en <= 1e-8 relativo
    y m_gas en ~3e-7 (atribuirlo al reflujo no esta medido).
  - Duracion: con 0.25 ms la persistencia >= 100 kPa NO es general. Ocupa
    los 60 ms en F (120/235 pasos), B (235/235) y J (219/239); G cae a 0
    tras el primer cuarto (27, 0, 0, 0), I baja a 6 en el segundo (59, 6,
    22, 55). k11_dt025_tgfix, casi gemelo de F (coincide hasta 280026),
    tiene nolink solo en 280002-280023 y medias de p_max por cuartos que
    bajan de 138 a 84 kPa (103/235 pasos >= 100 kPa; C-273): F, tgfix y G
    se leen como dispersion entre trayectorias, y el regime_p de 591.6 kPa
    de k10b_dt025 depende de la trayectoria. Si decae despues de 60 ms, sin
    decidir (C-250).
  - U_GAS_MAX sola no identifica el cambio: jb 295 s con sus mismas claves
    da 300.0 m/s en 1 paso (295002; 3 pasos >= 200 m/s) al acotar dt de 1 a
    0.25 ms y se apaga, sin nolink (C-256, C-259, sin diagnosticar). Con
    0.25 ms, los brazos jb/otp con f28 establecida alternan (C 76-80 kPa,
    K 66-71, L 31-42, Q 34-52); los fh con las claves apagadas (A, H, M, N,
    O) quedan planos en 14-18 kPa; f28 y linaje van juntos (no hay brazo jb
    con f28 apagada), asi que no se separa si ese nivel lo pone f28 o el
    estado. Solo se probo un sentido del cambio (encender f28 sobre fh);
    apagarla sobre un estado escrito con ella no se ha corrido.
  - Con 1 ms el pico se asienta en 13-31 pasos, y no en un estado tranquilo
    sino en un ciclo de 2 pasos (23/43 y 28/49 kPa); con f28 ese regimen
    alto y alternante (por media de p_max y |dp|) dura los 15-20 s medidos
    (C-241), pero por CONTEO no explica las paradas de B1: con filas de nivel centinela
    (u >= 299 m/s o p >= 300 kPa, cada 5 pasos, 280-295 s) el linaje sin
    claves da 15, el de solo f28 1 y judge_otp_280 26, y el evento de
    284.3 s aparece tambien sin f28 (C-251). f28 se adopto con un reinicio
    que la encendia en 280 s; la evidencia de mas largo plazo sin cambio de
    clave (jb 1 frente a fh 15 filas) no la contradice ni la apoya (una
    trayectoria por linaje, C-260). La adopcion de f28 (2f0529b, centinela
    2.6 % -> 0 %) NO esta contaminada por el pico de reinicio (sus filas de
    nivel centinela estan en 281461-281502), pero M20-2 (0398a99, acople-pv
    «no repetir») se decidio sobre el transitorio del cambio de f28 en
    280003-280029. Fuera de esos pasos m202_280 da 66.1 kPa y 1 fila,
    en el borde de la dispersion de sus hermanos (48.3-62.6 kPa, 0 filas,
    scrfh_b hasta 287.7 m/s), y el commit cita ademas B1 255-258 s neutro:
    ese dato ni apoya ni refuta M20-2; decidirlo pide un juez estadistico
    de m202 frente a m203 (C-270, C-276).
  - Con las claves ya establecidas (judge_otp_280/eaf3d_00290000.h5) hubo
    con 0.25 ms picos aislados de hasta 450 kPa (paso 290093) sin nolink,
    sin diagnosticar y no repetidos desde 300 s (C-245). Tambien siguen sin
    diagnosticar U_GAS_MAX en L (C-261) y P_HYDRO_CAP en I y J (C-277).
    El primer paso tras acotar dt se excluye
    siempre (C-230).
  Para comparar config o dt, reiniciar de un snapshot escrito con las MISMAS
  claves y con f28 establecida >= 5 s (minimo probado). Los bancos de
  WS-K5 a WS-K8 y WS-K10 que reinician de judge_otp_280/eaf3d_00280000.h5
  llevan el cambio de f28 y sus ventanas incluyen el asentamiento del pico.
  Los de 1599 filas con f28 encendida (C-270) reinician de
  judge_fh_275/eaf3d_00280000.h5, de campos primarios identicos, y tambien
  llevan el cambio (lista en
  research/ws/WS-K11/report.md, C-251); cuanto cambia eso sus conclusiones
  no esta evaluado.
  DESDE 290 s, con 20 externas, CG 1000, ventana 290.00-290.06 s y UNA
  trayectoria por dt (1 / 0.5 / 0.25 ms): r(e) = -4.93e-2 / -4.33e-2 /
  -4.11e-2 kg/s. C-231 SOPORTADA por la letra (C-232: 0.877, predicho
  0.888), pero con poca potencia: la rama de refutacion era inalcanzable
  con los extremos ya vistos, y el criterio (b) no distinguia una pieza por
  paso de su ausencia; la forma de los tres puntos refuta una pieza por paso
  constante en err_liq_lk (C-234, C-235). Lectura: el error se comporta
  mayormente como una tasa (c/r(1 ms) ~0.8, no pre-registrado). EN ESTA
  CONTABILIDAD Bgq es la tasa dominante (-5.8e-2 a -5.1e-2 kg/s, 1.2 e);
  puede ser la diferencia de dos terminos grandes no exportados. Con la
  config de B1 (solo 1 ms): store_gas multifase x77 y gas libre -2.2e-5
  kg/paso (C-233); su dependencia con dt NO esta medida.
  COMPARAR dt DESDE UN REINICIO ESTA CONFUNDIDO: el primer paso acota el dt
  del snapshot (transitorio; con 0.5 ms pone el 66 % del error, C-206) y la
  presion tarda mas en asentarse (pasos con p_max >= 100 kPa: 0 %, 9 % y
  51 % con 1 / 0.5 / 0.25 ms; max 592 kPa con 0.25 ms; C-216/C-219), y
  con 0.25 ms la CENTINELA U_GAS_MAX salta a los 3 pasos del reinicio (300
  m/s, 461 kPa; C-222): es el transitorio del cambio de claves (C-227). Con
  estos bancos NO se separa tasa de truncamiento (C-212 sin decidir, C-213;
  se retiraron las lecturas de C-214 «46 % fijo + dt^1.6» y de C-215 «dos
  tasas»; err_liq + A CRECE por unidad de tiempo al bajar dt, C-217). Lo
  medido, EN ESTA CONTABILIDAD de gadv y rho_f (no unica): en 280 s, con
  cada dt, la pieza de mayor media es Bgq
  (advectivo de ensamblaje frente al de los caudales corregidos, con las
  caras de la guardia ALPHA_CUTOFF de `gas_adv`), y la densidad posterior al
  ultimo Poisson pesa < 2 % de e en neto (Br2 y Bgr se cancelan). C-202
  (H10: «esta en Br») SIN DECIDIR por la letra (C-204, C-208). Antes de
  pre-registrar el reparto de Bgq: exportar las magnitudes brutas de sus dos
  terminos (dt Σ ρ_it gadv_used y dt Σ_caras (ρ_dador − ρ_it) q_out); un
  banco con la config de B1 en 340-345 s, donde el gas libre pesa 0.66 del
  multifase (k10_base); snapshots ASENTADOS y con las mismas claves si se
  compara dt; y
  ojo con repetir M6-1 (advectivo con T_g rancia en celdas sin gas) y M7-5
  (caudal fantasma de `ws_qin_cap`): Bgq apenas cambia con el regimen de
  presion y err_cc si (C-216).
  INFO `mass_gas_cells` con la tasa por s y por kg de gas, que no depende
  del largo de la ventana: el cociente de mass_gas sí, y en ventanas largas
  de B1 tiende a ~1).
- **Identidad de energía POR PASO (A4-4)**: además de la acumulada, cada paso
  desde el 2 cumple |gap| ≤ 0.1·S_gas + 1e-9·S_ext + 5e-5·S_int (piso
  1e-8·E_tot): el htol acumulado existe para el paso 1 (fusión instantánea
  con 5 outers) y después admitía errores del tamaño del arco. S_int sin
  `E_iph_liq` (= −E_iph_sol, contado dos veces).
- **Auditoría de energía**: hooks exactos en solve_energy_3d
  (energy_audit_hook, linearización de Newton en T_it del ensamblado); el
  balance se escala contra el throughput bruto. arc_budget cierra a 1.0000
  con `E_mc_lost` (beams que escapan).
- **Residuo de la SUB-RELAJACIÓN de T (WS-K3/WS-K4, C-095..C-103, 24-oct-2026)**:
  el campo que queda en pie es el relajado `Tk = αT T* + (1−αT) Tpre`, que no
  cumple el enunciado discreto; el hook evalúa cada término exacto en Tk y la
  identidad supone residuo 0. Con `alpha_T` 0.7 en B1 el líquido pierde
  ~−60 J/paso (280–345 s: energy_balance 1.7–2.3× lo permitido); banco de 220
  pasos: neto 0.85 → −2.1, 1.0 → −3.8, 0.7 con max_outer 10 → −89. NO es
  lineal en (1−αT) (C-097 refutada en C-098). Con 0.85 se cierra el NETO, no
  cada paso: std por paso 105 J frente a 0.25 J con 1.0 (C-103); de ahí el
  FAIL de energy_balance_step en el juez C-100. El remanente de ~−3.7 J/paso
  queda FUERA de E_relax_liq (bench_relaxcol: gap − columna −833 J, std 0.23 J;
  C-102/C-103), así que NO es residuo del TDMA (R(Tk) lineal: caería dentro);
  sin atribuir (candidatos: celdas con alpha < ALPHA_CUTOFF o guarda). Columnas
  diagnósticas (WS-K4) `E_relax_liq`/`E_relax_gas` (y `E_abs_liq_hook`; reparto por fase solo en
  dos fluidos, no con mixture_model): fuera de la identidad a
  propósito (la cerrarían escondiendo la pérdida); `check_audit` las
  reporta como INFO `energy_relax`. Hueco por fase: `scripts/diag/energy_gap.py`.
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
