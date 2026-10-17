---
paths:
  - "src/mod_arc_*.f90"
  - "src/mod_slag_*.f90"
  - "src/mod_foam.f90"
  - "src/mod_electrode_3d.f90"
  - "src/mod_lorentz_3d.f90"
  - "src/mod_chemistry_carbon.f90"
  - "src/mod_species_transport.f90"
  - "tests/integration/check_slag*.py"
  - "tests/integration/check_chem.py"
---

# Arco electrico, escoria (legado y condensada, Plan H), quimica y especies

Convenciones vigentes movidas TEXTUALMENTE desde CLAUDE.md (reestructuracion
harness, 16-oct-2026). Cada una existe por un fallo medido: no simplificar una
guarda sin leer su causa.

Nota (Plan H, P9): con `slag_in_volume = true` (default) la escoria es fase
CONDENSADA del Poisson y del momento y flota por `slag_condensed_sort`; los
textos que describen la cesion en el derrame y la recolocacion por
`slag_buoyancy` cada paso valen para el camino legado (`slag_in_volume = false`);
`slag_buoyancy` solo corre en t = 0. Ver `docs/PLAN_H_escoria_condensada.md`.

- **Depósito MC del arco repartido por ABSORCIÓN (F2.30, oct-2026)**: en una
  celda con chatarra el beam deposita en cada fase en proporción a κ_q·α_q
  (`KAPPA_SOLID_ABS`, `KAPPA_GAS_ABS`, los de la DO; Fluent P-1/DO, MFiX TFM,
  Cai & Modest 2014), nunca todo al gas: el gas de poro (1.5 % del volumen)
  llegaba a 54 000 K. La parte del sólido va a `E_s` (auditada
  `AUD_ARC_DIRECT`, cota 2 K/paso; el exceso vuelve a `S_arc`).
- **Auditoría 5 (14-oct-2026), lo que cambió de convención**: (A5-1) la
  superficie bajo el arco, chatarra O baño, se decide en UN solo barrido por
  contenido ponderado (`ksurf`; cada material en SU escala: el baño por
  ESPESOR equivalente `ARC_SURF_H` 0.014 m —M6-5: con fracción del volumen
  dependía de dz y en producción bastaban ~13 kg para recibir P_elec— y la
  chatarra por FRACCIÓN del volumen `ARC_SURF_FRAC_S` 5 % —M7-1: es un lecho;
  con espesor un cráter a medio fundir dejaba de ser superficie en
  producción—; la capa es superficie si las dos fracciones de umbral suman
  1). QUIÉN es la superficie (auditoría 8, M8-1): si el baño pasa su umbral
  propio, chatarra si Σwα_s ≥ Σwα_l y la chatarra pasa también el suyo (baño
  con chatarra sumergida = baño, M3-3; lecho inundado = chatarra si pesa más
  que el líquido, M4-8); si no, el material más cercano a su umbral (escala
  normalizada: película más fina que `ARC_SURF_H` sobre chatarra suelta =
  chatarra; traza de chatarra frente a película casi en su umbral = baño).
  Ni la cruda sola (película fina pasaba por baño) ni la normalizada sola (el
  baño con chatarra sumergida dependía de la malla). **LÍMITE DEL MODELO
  (auditorías 11-12, M11-1arc/M11-2arc/M12-2arc)**: con fracciones
  promediadas por capa, un charco h sobre un lecho inundado φ da en su capa
  α_s = φ(dz−h)/dz y α_l ≈ 1 − α_s, indistinguible de un lecho inundado a ras
  con φ' = α_s. La regla de los dos umbrales (fracción cruda) lo clasifica
  chatarra solo si α_s ≥ α_l, así que la ambigüedad existe solo con φ > 0.5 y
  para h ≤ dz(1 − 0.5/φ). Con φ de la receta (0.45–0.55) la banda queda bajo
  `ARC_SURF_H` en producción (4.5 mm) y en B1 (7–11.5 mm); pero con chatarra
  COMPACTADA (α_s > 0.9, 762 celdas en B1 a 300 s) la banda es 0.44 dz: 17–28
  mm en producción y 34–56 mm en B1, POR ENCIMA de `ARC_SURF_H`: ahí el error
  existe también en producción (auditoría 13). El filtro por celda α_l ≥ 0.3
  sube el umbral efectivo del baño a max(14 mm, 0.3 dz): 14–19 mm en
  producción, 23–38 mm en B1, 84 mm en los bancos. No intentar otra regla de UNA
  capa (tres intentos solo movieron la frontera). **Capa de abajo (oct-2026,
  b255fc1 + dirigida M2)**: si la capa de abajo es un lecho COMPACTADO
  (φ ≥ 0.9) inundado, la capa está saturada de líquido y el charco implícito
  h = dz(1 − α_s/φ_abajo) ≥ `ARC_SURF_H`, la superficie es el BAÑO (casos 8–10
  de `test_arc_surface`). LÍMITE que queda (no identificable por capas): un
  lecho más suelto inundado A RAS sobre uno compactado da las mismas
  fracciones y se clasifica como baño; con φ_abajo < 0.9 la regla no actúa.
  Su efecto en producción lo juzga el B1 nuevo. Nunca volver a una
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
- **Arco y ESCORIA: modelo térmico de la escoria (oct-2026; cierra M12-1arc
  / A13-1)**: (1) la escoria DENSA absorbe y emite en la DO
  (`KAPPA_SLAG_ABS` α_sl, a T_sl, mismo camino que la espuma; depósito en
  E_sl, `E_rad_foam`); (2) el acople escoria–baño va al reservorio de MAYOR
  capacidad (su celda o la de abajo; antes a la traza de líquido de su
  celda: 10–30 J/paso); (3) el arco abre CAVIDAD: `ksurf`/P_elec/P_conv usan
  solo α_l (metal bajo la escoria), pero los rayos del MC ven α_l + α_sl
  (apantallamiento) y `slag_intercept_arc` pasa a E_sl la parte de la escoria
  por su κ SOLO del depósito del MC (`S_arc_mc`, la diferencia de S_arc antes
  y después del MC): P_elec/P_conv no se interceptan aunque la celda sea
  mixta (antes la escoria se llevaba hasta el 30 % del arco; arc_slag 2 s:
  49 → 4.6 MJ interceptados). El P_rad DIRECTO (no MC) lo deposita el modelo
  en la superficie (baño/chatarra), no en la escoria. La escoria como superficie de TODO el arco se probó dos veces y
  NO es física (se lleva ~43 MW, +72 K/s en su celda). (4) La escoria CEDE al
  acero en el DERRAME del sobrellenado (A11-2; `slag_vs_steel`): el exceso
  bajo una interfaz de escoria entra en su celda (el recorte final no corta
  acero por la escoria) y `slag_buoyancy` la sube al final del paso. NO en el
  limitador ni en el Poisson: dejar entrar por advección el acero del baño en
  la capa de escoria BOMBEABA el gas (arc_slag: u_gas a la cota de 300 m/s en
  5 s; bisecado). (5) Soporte de la escoria (`slag_buoyancy`): el acero
  SATURADO MÁS ALTO de la columna (α_l ≥ min(0.3, max(0.01, liq_cap/2)):
  relativo en lechos densos); una bolsa de gas o un fondo seco no cortan la
  búsqueda (un barrido contiguo desde el fondo metía la escoria en la bolsa de
  pocket_rise); un charco encaramado SÍ la sostiene; la inversión acero sobre
  escoria se deshace cuando el fundido satura. Sin acero, la cima del lecho
  (la cesta cargada sobre baño ya no la arrastra, M4, salvo que una celda de
  la cesta llegue a saturarse de fundido). LÍMITE (dirigida de 00e249e, S): el
  fundido que llega DESDE ARRIBA no atraviesa la escoria por advección (el
  limitador la cuenta); se acumula hasta saturar y entonces la escoria se
  recoloca sobre él; un charco encaramado saturado también la sostiene.
  Medido en `arc_melt_slag_heel` (talón + lecho + escoria + fusión, 6 s): 0
  saltos del soporte, |volfix| 0.05 kg y una PELÍCULA de acero sobre la
  escoria de α_l ≤ 0.016 en hasta 94/288 columnas (auditoría 17, M17-I1: el
  «0 columnas» de 7b3224f salía de un gate que con α_sl ≤ 0.014 no evaluaba
  ninguna; `check_slag_bed --asl-min 1e-3 --al-min 0.05` en los bancos con
  chatarra). `test_slag_float` casos 1–6. Medido en arc_slag 10 s:
  T_sl máx siempre bajo T_l máx (la escoria sigue al baño), clip 3.7 kg →
  1.7e-9. Bancos `arc_slag` y `arc_melt_slag` (escoria sobre lecho que
  funde, `check_slag_bed.py`). `config_production_full` corre con
  `solve_slag false`: sin talón no hay escoria líquida al arrancar en frío, y
  sin escoria inicial no hay vía que la cree (la oxidación a FeO se acota por
  la escoria existente; las adiciones se descartan con aviso `[SLAG] AVISO`;
  dirigida de 147fad5). Para una colada con escoria: talón + `m_slag_init` > 0
  + `solve_slag true`. Antes: escoria inicial a 300 K sobre la chatarra fría (auditoría 17, M17-1: 3.3 t a 300 K sobre la
  chatarra fría se llevaba ~91 % del MC en la cima del lecho, régimen que ningún
  banco cubre); con talón (`heel_mass` > 0) la escoria inicial va a `heel_T`.
  B1 (Ugarte) sin escoria. `slag_buoyancy` recoloca con REMAPEO LAGRANGIANO
  (cada parcela conserva su entalpía y composición; antes la media de columna
  daba conductividad vertical infinita, M17-arc1): el transporte entre capas
  de escoria lo hace la DO (espesor óptico ~5 por celda; `k_slag` sin efecto).
  **M17-PV1 CERRADO con Plan H (16-oct-2026, `slag_in_volume`, default
  true; `docs/PLAN_H_escoria_condensada.md`)**: la escoria es fase CONDENSADA
  del Poisson y del momento. Dentro de `multiphase_iteration` `liq%alpha`/
  `liq%rho` son α_c = α_l + α_sl y ρ_c (`cond_view_enter/exit`; el acero vive
  en `ws_al_st`), con el peso `ws_wc` (Boussinesq del acero + ρ_sl g) vía
  `liq_w`. El condensado se transporta con `solve_volume_fraction` y la
  escoria viaja con él (`asl_adv`) con la composición ACTUAL del dador en
  cada sub-paso, derrame y recorte, y con ella sus extensivas E_sl y m_X
  (`slq_adv`; con los valores específicos de inicio de paso la escoria que
  cruzaba una celda vacía viajaba sin energía). Flotación =
  `slag_condensed_sort` (reordenamiento por columna neutro en volumen,
  compactación del gas SOLO bajo la interfaz de escoria resuelta, α_sl =
  m_sl/(ρ_sl V) para las fuentes de química/adiciones, que extienden el tramo
  sobre el gas; gas auditado como volfix). Trazas de escoria (α_sl <
  ALPHA_CUTOFF) en equilibrio térmico con el baño (`E_slag_tclip`, por paso):
  la masa de una celda que se vacía cancela a ~1e-110 kg y su E solo al
  redondeo — E/m absurda llevó 5e11 J a la vecina y el baño a −2 MPa. Clip de
  escoria aparte (`m_slag_clip`/`E_slag_clip`). Hidrostática inicial con el
  peso de la escoria. arc_slag 10 s: u_liq 0.087 m/s (legado 1.25), vol_lim
  2.9e-7, u_gas 6, p 95 kPa, energía 1.6e-3 del permitido. La capa condensada
  AISLABA el metal del O₂ en el estencil local de oxidación (slag_chem_flow
  0.99 kg frente a 2.7 kg): con el condensado la oxidación va POR COLUMNA
  (Plan I, I1, `slag_oxidation_column`): en el tramo de escoria RESUELTA
  (α_sl ≥ ALPHA_FLOW_CUTOFF: una traza de upwind bajo la interfaz no es kb)
  más bajo, O₂ del gas del tope kt MÁS el de kt+1 (cada uno si tiene gas), Fe
  del acero de kb hasta su cota y el resto del baño de kb−1 (sumas, nunca una
  fuente elegida por umbral: la tasa saltaba ~100 veces), FeO a la escoria de
  kb; mismas cotas; sustituye al estencil local (no contar dos veces el O₂).
  Una columna con escoria solo en trazas (< 0.01 en todas sus celdas) no
  oxida; queda un salto residual (~1.5×) en α_sl(kb) ≈ 0.01 con gas frío
  (pendiente medir α_sl de la interfaz en slag_chem_flow; si molesta, cota
  térmica sobre m_sl(kb) + m_sl(kb+1)). Test `test_slag_ox_column`. `slag_in_volume = false` recupera la capa
  legada (con el hueco fantasma de gas F2.21 descrito en el plan). Con el condensado la escoria
  ya tiene transporte LATERAL (antes solo columnas). Sin modelar: viscosidad
  propia de la escoria (P5b opcional).
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
  simetría 120°) es chatarra o baño según la regla de M8-1 (sección de la
  auditoría 5); el P_rad directo
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
- **MC del arco**: beams repartidos round-robin entre ranks; TODOS los ranks
  consumen la secuencia RNG completa (determinismo por paso). El depósito se
  reduce con MPI_SUM => no bitwise (~1e-13 en corridas regulares).
