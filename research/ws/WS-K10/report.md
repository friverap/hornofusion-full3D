# WS-K10 — Descomposición exacta del error de masa del gas por celda

Sigue a WS-K8. Con dt 0.5 ms frente a 1 ms, el error multifase por paso
parecía casi constante ({C-197}) y se leyó como la huella de una operación de
una vez por paso. Pregunta: ¿qué pieza del error se comporta por paso? Para
responderla se instrumenta una descomposición EXACTA, por celda y por clase,
del residuo del plan del Poisson. Es una pieza de diagnóstico, sin cambio
numérico: las columnas comunes de la suite y de los bancos de campaña son
idénticas antes y después {C-204}{C-209}.

**Resultado en una línea.**
- **Veredicto pre-registrado:** SIN DECIDIR por la letra {C-204}.
- **La premisa era un artefacto.** El paso del reinicio con dt acotado ponía
  el 66 % del error del banco de 0.5 ms. {C-206} corrige C-197.
- **Cociente entre dt, sin decidir y CONFUNDIDO.** Sin ese paso, desde 280
  s, e(0.5 ms)/e(1 ms) vale 0.32 con todos los pasos. Como lectura no
  pre-registrada, va de 0.31 a 0.375 según el umbral de p_max o la ventana
  física que se excluya {C-229}. No se decide si el error baja más que
  linealmente con dt {C-223}. Todas las cifras entre dt desde 280 s llevan el
  transitorio de cambio de claves {C-227}. Desde 290 s, con las claves ya
  activas, el cuadro es otro (lectura no pre-registrada, {C-230}): r(0.25
  ms)/r(1 ms) de e vale 0.833 (IC90 0.82-0.85), frente a 0.512 (0.45-0.62)
  desde 280 s, y los IC90 no se solapan. Que la caída de e con dt desde 280
  s venga de ese transitorio es una hipótesis alternativa que estos datos
  respaldan y que no está descartada.
- **El tercer dt** (0.25 ms, pre-registrado en {C-212}) quedó SIN DECIDIR por
  la letra {C-213}. Además dispara la centinela U_GAS_MAX: 300 m/s y 461 kPa
  a los 3 pasos del reinicio. No es una referencia limpia, y su cociente
  depende de esos pasos (0.812 a 0.896) {C-222}.
- **La causa de la centinela la aisló WS-K11** {C-227}. El snapshot de 280 s
  lo escribió una corrida con `pc_transport_f28` y
  `pc_outlet_total_pressure` apagadas, y todos los bancos de K8 y K10 las
  encienden al reiniciar. Con 0.25 ms desde el snapshot de 290 s, escrito ya
  con las claves activas, no hay centinela: en los pasos 290002-290010
  (ventana del criterio de C-226), como máximo 72 m/s y 79 kPa. En la
  ventana completa de ese banco hay picos de presión: p_max llega a 450 kPa
  y u_gas_max a 128.6 m/s en el paso 290093, y 5 de 235 pasos tienen p_max ≥
  100 kPa {C-227}{C-230}. 290 s no es una referencia libre de picos. Toda
  comparación entre dt de K8 y K10 desde 280 s lleva ese transitorio de
  cambio de claves.
- **Desde 280 s no se separa tasa de truncamiento.** Los dt no recorren el
  mismo régimen de presión {C-216}. Se retiraron las lecturas de C-214 y
  C-215 {C-216}{C-217}.
- **Desde 290 s, sin el transitorio, H14 queda SOPORTADA por la letra**
  {C-231}{C-232}, pre-registrada en el commit `798e2ad` con un banco nuevo
  de 0.5 ms. Vale SOLO para 20 externas, CG 1000, la ventana 290.00-290.06
  s y una trayectoria por dt. La config de B1 no está medida entre dt
  {C-234}.
  - (a) Por unidad de tiempo, el error con 0.5 ms vale 0.877 veces el de 1
    ms (IC90 0.860-0.894, bootstrap dentro de una trayectoria; banda [0.85,
    1.00]; la interpolación lineal
    predecía 0.888). El criterio tenía poca potencia: con r(0.25)/r(1) =
    0.833 ya visto, cualquier r(dt) monótona daba un cociente en [0.833,
    1.00], y la rama de refutación (≤ 0.70) era inalcanzable.
  - Lo que sostiene «mayormente tasa» es una lectura NO pre-registrada de
    la curvatura de los tres puntos: r(0.25)/r(0.5) = 0.949 (IC90
    0.925-0.972) frente a 0.877 (0.860-0.894), sin solape. El ajuste c +
    b·dt^p da c/r(1 ms) = 0.81 (IC90 0.73-0.84). La parte que depende de dt
    (12-19 %) no se atribuye a truncamiento, porque el régimen cambia con
    dt: p_max medio de 31, 35 y 45 kPa {C-234}.
  - (b) err_liq_lk da 6.996e-6 kg por paso, dentro de la banda. Pero la
    banda NO distinguía el modelo con pieza por paso (predicho 6.92e-6) del
    modelo sin ella: con k = 0 el valor cae en [6.83e-6, 7.12e-6], y su
    interpolación lineal, 7.02e-6, queda más cerca de lo medido. Los tres
    puntos son incompatibles con un k constante: el incremento de r de 0.5
    a 0.25 ms debería ser el doble del de 1 a 0.5 ms, y es 0.71 veces (IC90
    0.40-1.16). La hipótesis de k por paso sigue sin adoptar {C-234}.
  - EN ESTA CONTABILIDAD, Bgq es la tasa dominante: de −5.8e-2 a −5.1e-2
    kg/s, de 1.17 a 1.24 veces e. Puede ser una diferencia pequeña entre dos
    términos grandes que no se exportan (ver Incertidumbre).
- **Lo medido:**
  - la descomposición es exacta, con tres checks de cierre;
  - EN ESTA CONTABILIDAD de las piezas, Bgq es la de mayor media con cada dt,
    y la densidad posterior al último Poisson pesa menos del 2 % de e en
    neto. Las dos cosas se sostienen en las ventanas de 280 y 290 s (en 290
    s, Bgq 1.17 y 1.24 e; Br + Bgr 1.9 % de e con 1 ms, al borde) {C-230}.
    La contabilidad de gadv y ρ_f no es única; ver Incertidumbre.
  - Las MAGNITUDES y los pesos relativos /e dependen de la ventana: con 1 ms,
    e por paso vale −1.45e-5 kg en 280 s y −4.93e-5 en 290 s (×3.4, estable
    por quintos en las dos). Los pesos de la tabla de abajo valen solo para
    280.00-280.06 s; ver «Comparación desde 290 s».

## Proceso

1. **Identidad**, validada contra el código por un agente de diseño antes de
   implementar. Con la fila del último Poisson tras el CG, Σ_enlazadas
   (q_g,out + q_l,out) = su_cc + E2 − store_gas − store_art − r, por celda y
   de forma exacta:

   e = err_liq + err_cc + err_art + A + Br1 + Br2 + Bgr + Bgq + Bx

   - A = comp + ρ_f V_eff: el complemento frente al líquido realizado.
   - Br1 = (ρ_it − ρ_pre)·X y Br2 = (ρ_pre − ρ_f)·X, con X = V_pois + dt
     (su_cc − store_gas − store_art): el cambio de densidad después del
     último Poisson. Br1 viene de la EOS del mismo outer y Br2 de la EOS final
     del paso.
   - Bgr = dt (ρ_f − ρ_it) gadv_used y Bgq = dt (ρ_it gadv_used + Σ_caras
     (ρ_dador − ρ_it) q_out). Comparan el advectivo de ensamblaje con el de
     los caudales corregidos, incluidas las caras que `gas_adv` excluye por
     la guardia ALPHA_CUTOFF. Bgr también es densidad posterior al último
     Poisson.
   - Bx = −ρ_it dt r: el residuo de la fila tras el CG.

   ρ_it es la densidad con que el Poisson evaluó `ws_Fg`; ρ_pre, la previa a
   la EOS final; ρ_f, la final. La identidad es exacta con las claves por
   defecto. Con las dos claves `pc_fs_*` de Plan D hay caras de superficie
   libre fuera de ella, y no se evalúa.
2. **Instrumento.**
   - **Poisson** (`src/mod_workspace.f90`, `src/mod_pressure_3d.f90`):
     exporta el caudal volumétrico corregido del gas (`ws_Fgv_*`; ahora
     `ws_Fg` = gmass(`ws_Fgv`)), la densidad usada (`ws_rho_g_used`) y el
     residuo de la fila por celda (`ws_pc_res`, en el orden de `matvec`). La
     copia, los intercambios de halos y el residuo solo se hacen con
     `audit_freq > 0`.
   - **Paso** (`src/main_3d.f90`): copia `gas%rho` antes de la EOS final
     (`ws_rho_g_pre`) y marca el gancho de la EOS (`audit_mark_eos_pre`).
   - **Audit** (`src/mod_audit.f90`): 24 columnas nuevas frente a
     `k8s_mo20`. Son 7 del multifase (`pa`, `brho_it`, `brho_end`,
     `bg_rho`, `bg_q`, `bx` y `store`), 8 del gas libre (las mismas más
     `err_liq_free`) y 9 de control (`dec_abs` ×2, `rv_abs`, `rv_scale`,
     `dec_skip`, `dec_scale` ×2, `eosend_abs` y `eosend_scale`). `store` no es
     una pieza de e: es el dato ρ_f dt store_gas, cuya parte que la EOS no
     realiza cae en err_cc.
     err_liq del multifase usa la columna previa `m_gas_err_liq_all`. Ver `docs/AUDIT_COLUMNS.md`, columnas con (WS-K10).
   - **Checks** en `tests/integration/check_audit.py`, todos exactos a
     redondeo y con tolerancia de 1e-13 veces una escala BRUTA:
     - `mass_gas_row_volume`: la fila en volumen, sin densidades;
     - `mass_gas_decomp`: la descomposición en masa;
     - `mass_gas_eos_end`: α_g V (ρ_f − ρ_pre) frente al incremento del
       gancho de la EOS final. Valida el REPARTO Br1/Br2, que el cierre en
       masa no ve porque Br1 + Br2 telescopa.
   - **INFO** `mass_gas_cells_pieces`, con las piezas por paso.
   - `tests/integration/compare_audit.py`: los cierres y Bx entran en
     `ROUNDOFF_COLS`. Son restos de redondeo y ruido del CG, que cambian en
     sus últimos bits con otro número de ranks.
   - Revisión previa al panel {C-209}. Un auditor independiente encontró
     tolerancias que no escalaban con el caudal bruto, el reparto Br1/Br2 sin
     validar, el coste con el audit apagado y una cara con q = 0 que leía un
     halo. Todo se corrigió.
3. **Sin cambio numérico** {C-204}{C-209}.
   - `make test-unit` y `make test-full` OK, con el golden v132.
   - Los `audit.csv` de los 61 bancos de la suite son idénticos, en sus 137
     columnas comunes, a una copia previa que se tomó como del código de
     `934c2d4`. Esa procedencia NO es verificable: la copia está en el
     scratchpad de la sesión (efímero), sin binario ni log de la corrida que
     la generó. Lo que sí se verifica es que la copia coincide sha256 a
     sha256 con el manifiesto. Ver Incertidumbre.
   - Los tres checks pasan en 41 de las 68 evaluaciones de `check_audit`
     (53 corridas y 15 reinicios). En las otras 27 solo `mass_gas_decomp`
     informa «INFO n/a», por escoria condensada, fallback, `pc_fs_*` o falta
     de flujo de dos fluidos. En esas 27, `mass_gas_row_volume` y
     `mass_gas_eos_end` no se evalúan: no imprimen nada.
   - Conciliación con los 79 `audit.csv` de `tests/out` (61 corridas y 18
     reinicios). `test_full.txt` pasa `check_audit` por 77 directorios (61 y
     16). Los dos reinicios de reloj (`cold_10step_wallresume_n8` y
     `cold_10step_wallstop_n8`) solo pasan por `[audit-restart]`. En 9 de
     los 77, que tienen `solve_flow = false` (`chem_test_n4`, `ecs_test_*`
     ×3, `noflow_energy_n1`, `slag_chem_test_*` ×3 y el reinicio
     `ecs_test_n8_to_n8_s10`), el checker de entonces no imprimía ninguna
     línea `mass_gas_*`. Así, 77 − 9 = 68 evaluaciones: 53 corridas y 15
     reinicios. Con el checker actual, sobre los 79 (`checks_suite.txt`),
     salen 43 PASS (los 41 y los dos de reloj) y 36 «INFO n/a» (los 27 y
     los 9 sin flujo). Ver Incertidumbre, «Tests».
   > [fuente: conciliación: grep -oE '^\[audit\] tests/out/[^ ]+' research/ws/WS-K10/logs/test_full.txt | sort -u | wc -l (77); awk '/^\[audit\] tests\/out/{cur=$2} /mass_gas  \(solve_flow = false/{print cur}' research/ws/WS-K10/logs/test_full.txt (los 9); find tests/out -name audit.csv | wc -l (79)]
   > [fuente: research/ws/WS-K10/logs/test_unit.txt, test_full.txt, cmp_comunes.txt; base: copia en el scratchpad de la sesión, con el manifiesto sha256 de sus 61 audit.csv en research/ws/WS-K10/logs/base_audit_manifest.txt | python3 research/ws/WS-K10/scripts/cmp_comunes.py <copia> tests/out; grep -E 'mass_gas_decomp|mass_gas_row_volume|mass_gas_eos_end' research/ws/WS-K10/logs/test_full.txt | awk '{print $1,$2}' | sort | uniq -c]
4. **Pre-registro** {C-202}, en el commit `5999f40`, antes de correr.
   - **H10:** el error por paso de la meseta está en Br = Br1 + Br2.
   - **SOPORTADA** si Br/e_multi ∈ [0.5, 1.5] en los dos bancos y Br(0.5
     ms)/Br(1 ms) ∈ [0.75, 1.33].
   - **REFUTADA** si |Br| < 0.2 |e| en ambos bancos, o si el cociente cae en
     [0.35, 0.65].
   - **Enmienda {C-203}**, antes de correr: corrige el comando del
     prerrequisito de identidad.
   - Bgr, que también es densidad posterior al último Poisson, quedó fuera
     del Br pre-registrado {C-208}.
5. **Bancos** desde `judge_otp_280`, con 15 ranks y en serie:
   - `k10_mo20`: config de `k8s_mo20`, dt 1 ms;
   - `k10_dt05`: config de `k8s_dt05`, dt 0.5 ms;
   - `k10_base`: config de `k8_base`, la de B1 (5 externas, CG 20); es lectura.

   Los binarios:
   - `campaigns/bin/eaf3d_k10_opt` para el veredicto;
   - `campaigns/bin/eaf3d_k10b_opt`, el código tras la revisión previa, para
     `campaigns/b1/k10b_*`. Da las mismas piezas bit a bit {C-209}.
   > [fuente: research/ws/WS-K10/logs/opt_identidad.txt; los run.log registran la línea «Ejecutable:»]

## Resultado

- **Prerrequisitos** {C-204}, todos cumplidos:
  - las 137 columnas comunes son idénticas a las de `k8s_mo20`, `k8s_dt05` y `k8_base`;
  - `mass_gas_row_volume` deja un resto de 2.2e-14 m³;
  - `mass_gas_decomp` deja un resto ≤ 2.1e-13 kg;
  - cero `[CG] AVISO` en los dos bancos que deciden; `k10_base` tiene uno;
  - `m_gas_dec_skip` vale 0.

  El PASS de `mass_gas_decomp` en los `k10_*` se obtuvo con el checker de la
  hora del veredicto (tolerancia 1.4e-11 kg, {C-204}). El checker
  INTERMEDIO, entre {C-209} y {C-221}, daba FAIL en esos bancos: les faltaban
  las columnas `m_gas_dec_scale_*` y la escala valía 0. Con ese checker
  intermedio lo sostenían los `k10b_*`, cuyas columnas comunes con los `k10_*` son idénticas salvo
  `m_gas_rv_scale` {C-209}. Los restos son idénticos bit a bit: 2.91e-14 a
  2.13e-13 kg frente a tolerancias de 8.9e-11 a 1.1e-9 kg {C-218}. El
  checker de la hora del veredicto no está versionado (el último commit de
  `check_audit.py` era `79dc27b`). Con el checker de este diff la cifra SÍ
  se reproduce hoy {C-221}: los `k10_*` dan PASS con tolerancias de 1.41e-11
  a 1.46e-11 kg, y los `k10b_*` con tolerancias de 8.9e-11 a 1.1e-9 kg. La
  etiqueta es SIN DECIDIR, no fallida: el
  prerrequisito se cumple con el instrumento revisado, sobre las mismas
  piezas bit a bit, y el FAIL que daba el checker intermedio en los `k10_*`
  era de esquema (faltaban columnas), no de cierre {C-218}. Resuelto por el coordinador {C-221}: con
  un CSV sin `m_gas_dec_scale_*`, el `check_audit.py` de este diff aplica la
  tolerancia de la primera versión, y los `k10_*` dan PASS de forma
  reproducible con el código que se versiona en el commit de WS-K10 (restos de 2.9e-14, 5.8e-14 y 2.9e-14
  kg en el multifase).
  > [fuente: for n in k10_mo20 k10_dt05 k10_base; do python3 tests/integration/check_audit.py campaigns/b1/$n | grep -E 'mass_gas_decomp|mass_gas_row_volume|mass_gas_eos_end'; done]

  Con el binario revisado, `mass_gas_eos_end` cierra a ≤ 2.3e-18 kg sobre
  escalas de 0.34 {C-209}.
  > [fuente: python3 research/ws/WS-K10/scripts/cmp_comunes.py --par campaigns/b1/k8s_mo20/audit.csv campaigns/b1/k10_mo20/audit.csv (ídem dt05, y k8_base con k10_base); python3 tests/integration/check_audit.py campaigns/b1/k10b_<x> | grep -E 'mass_gas_decomp|mass_gas_row_volume|mass_gas_eos_end'; grep -c '\[CG\] AVISO' campaigns/b1/k10_<x>/run.log]
- **Veredicto de {C-202}: SIN DECIDIR por la letra** {C-204}{C-208}.
  - Br/e vale −0.683 con 1 ms y −0.135 con 0.5 ms, fuera de [0.5, 1.5]. No
    es soportada.
  - |Br| ≥ 0.2 |e| con 1 ms, y Br(0.5)/Br(1) = 0.184 queda fuera de [0.35,
    0.65]. No es refutada.
  - Lectura aparte, no veredicto: en ESTA contabilidad, Br + Bgr vale
    −1.69e-7 kg por paso, 0.012 e, con 1 ms; Br2 y Bgr se cancelan. La
    cancelación es algebraica: Br2 + Bgr = (ρ_pre − ρ_f)(X − dt gadv_used)
    − (ρ_it − ρ_pre) dt gadv_used: en la suma ponderada (no por celda) X ≈
    dt·gadv_used donde cambia ρ. Puede ser un efecto del peso con que se reparten las piezas (err_liq, err_cc y A
    también se evalúan con ρ_f), no una prueba de que la EOS final no importe
    {C-210}.
- **El paso del reinicio con dt acotado es un transitorio** {C-206}{C-211}.
  - En el paso 280001 de `k10_dt05`, igual que en `k8s_dt05`, el dt del
    snapshot (1e-3) se acota a 5e-4. La EOS reescribe −7.97e-4 kg y e_multi
    vale −1.056e-3 kg: el 66 % de la suma de e en 118 pasos.
  - Sin ese paso, el error por paso con 0.5 ms es 0.32 veces el de 1 ms con
    todos los pasos, no 0.93, y 0.35 en los pasos tranquilos: no se decide
    si baja más que linealmente {C-223}. Se retiran de C-197 «cantidad por
    paso» y «el plan cambia de signo».
  - C-196 no cambia: sin el paso 1, D sigue en 0.380. Con p_max < 100 kPa da
    0.377, y con t > 280.020 s, 0.372. D = e − err_liq − err_cc − err_art
    por paso; los mismos tres valores salen con los pares `k8s_*`, `k10_*`
    y `k10b_*`.
  - El artefacto del paso 1 NO depende del cambio de claves {C-230}:
    - en `k11_dt025_s290`, desde el snapshot de 290 s (claves ya activas),
      el paso 290001, con el dt acotado de 1e-3 a 2.5e-4, pone err_cc
      −1.731e-3 kg y e −1.735e-3 kg; con 1 ms (`k11_mo20_s290`, sin acotar)
      ese paso da e −5.06e-5;
    - en `k11_dt025_tgfix` (Tg_end del snapshot igualado a T_gas), err_cc
      del paso 280001 cambia de signo: de −1.586e-3 a +5.32e-4 kg. Los pasos
      siguientes cambian poco (paso 280002: err_cc 2.17e-5 frente a 2.07e-5;
      r(e) sin el paso 1, −7.23e-3 frente a −7.42e-3 kg/s). La referencia
      Tg_end heredada, venteada con el dt nuevo, participa en el paso 1. C-224
      se refutó {C-225} solo para la centinela de los pasos 2-3, no para
      este paso.
    - Por tanto, toda comparación entre dt excluye el primer paso tras
      acotar el dt, aunque el snapshot se haya escrito con las mismas claves.
  > [fuente: comandos de {C-206} y {C-208} en el registro (python3 scripts/research/ledger.py show C-206); python3 research/ws/WS-K10/scripts/piezas.py campaigns/b1/k10_mo20 campaigns/b1/k10_dt05; D, el comando de abajo; paso 1, comando de {C-230}]

  ```
  python3 -c "
  import csv,statistics as s
  F=lambda n:[x for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>280001]
  D=lambda x:float(x['m_gas_err_multi'])-float(x['m_gas_err_liq_all'])-float(x['m_gas_err_cc_multi'])-float(x['m_gas_err_art_multi'])
  for a,b in (('k8s_mo20','k8s_dt05'),('k10_mo20','k10_dt05'),('k10b_mo20','k10b_dt05')):
    A,Bb=F(a),F(b); q=lambda f:s.mean(D(x) for x in Bb if f(x))/s.mean(D(x) for x in A if f(x))
    print(a,b,'D 0.5/1: todos %.3f | p_max<100 kPa %.3f | t>280.020 %.3f'%(q(lambda x:1),q(lambda x:float(x['p_max'])<1e5),q(lambda x:float(x['time'])>280.020)))
  "
  ```
- **Lectura sin el paso de reinicio** {C-207}{C-210}, no pre-registrada.
  Medias por paso en el conjunto multifase, en kg. Todas las columnas,
  `k10_base` incluido, son SIN el paso 280001. El IC90 del cociente es por
  bootstrap de bloques (10 pasos con 1 ms, 20 con 0.5 ms). Ventana
  280.00-280.06 s, con el transitorio de cambio de claves {C-227}: las
  magnitudes y los pesos /e NO representan «la meseta»; en 290 s son otros
  (ver «Comparación desde 290 s»):

| pieza | 1 ms | 0.5 ms | 0.5 / 1 (IC90) | / e (1 ms) | / e (0.5 ms) | `k10_base` (lectura) |
|---|---|---|---|---|---|---|
| e | −1.4505e-5 | −4.572e-6 | 0.315 (0.30-0.34) | 1 | 1 | −2.661e-5 |
| **Bgq** | **−2.250e-5** | **−8.728e-6** | 0.39 (0.38-0.40) | **1.55** | **1.91** | −3.790e-5 |
| err_liq | +8.276e-6 | +4.285e-6 | 0.52 (0.50-0.53) | −0.57 | −0.94 | +8.52e-6 |
| err_cc | −1.077e-6 | −6.03e-7 | 0.56 (0.35-1.14) | 0.07 | 0.13 | −2.37e-6 |
| A | +9.63e-7 | +5.08e-7 | 0.53 (0.49-0.57) | −0.07 | −0.11 | +9.49e-7 |
| Br2 | +9.896e-6 | +1.800e-6 | 0.18 (0.18-0.19) | −0.68 | −0.39 | +9.97e-6 |
| Bgr | −1.0066e-5 | −1.837e-6 | 0.18 (0.18-0.19) | 0.69 | 0.40 | −1.004e-5 |
| Br1 | +2.8e-10 | +3.3e-9 | 11.6 | 0.00 | −0.001 | −1.8e-8 |
| Bx | −6.8e-14 | −8.7e-15 | 0.13 | 0.00 | 0.00 | +4.27e-6 |
| err_art | −4.0e-11 | −7.9e-12 | 0.20 | 0.00 | 0.00 | −2.0e-9 |

  > [fuente: medias, python3 research/ws/WS-K10/scripts/piezas.py --sin-paso1 campaigns/b1/k10_mo20 campaigns/b1/k10_dt05 campaigns/b1/k10_base (el veredicto, sin --sin-paso1). IC90 y error estándar: el comando de abajo (bloques móviles de 10/20 pasos, 4000 réplicas, semilla 1); con bloques de 5/10 el IC90 de e es 0.29-0.35]

  ```
  python3 -c "
  import csv,random,statistics as s
  F=lambda n,c:[float(x[c]) for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>280001]
  def B(v,L,g):
    o=[]
    while len(o)<len(v): i=g.randrange(len(v)-L+1); o+=v[i:i+L]
    return s.mean(o[:len(v)])
  g=random.Random(1)
  for c in 'err_multi bg_q_multi err_liq_all err_cc_multi pa_multi brho_end_multi bg_rho_multi'.split():
    a,b=F('k10_mo20','m_gas_'+c),F('k10_dt05','m_gas_'+c); m=sorted((B(a,10,g),B(b,20,g)) for _ in range(4000)); q=sorted(y/x for x,y in m)
    print(c,'%.3e se %.1e | %.3e se %.1e | q %.3f IC90 %.3f-%.3f'%(s.mean(a),s.stdev(x for x,_ in m),s.mean(b),s.stdev(y for _,y in m),s.mean(b)/s.mean(a),q[200],q[3800]))
  "
  ```

  - **Escalado con dt.** Las piezas grandes no escalan igual:
    - e da 0.315 por paso (IC90 0.30-0.34) con todos los pasos; en los pasos
      tranquilos, 0.353 (IC90 0.33-0.40), en el borde de la banda de tasa
      [0.35, 0.65] de C-202: no se decide si baja más que linealmente
      {C-223};
    - Bgq da 0.39 (exponente ~1.4), err_liq 0.52 y A 0.53: caen en la banda;
    - Br2 y Bgr dan 0.18 (exponente ~2.5): el mismo cociente con el que el
      veredicto juzgó que Br NO se comporta como tasa {C-204};
    - err_cc da 0.56 con IC90 0.35-1.14: no se determina.

    Con dos dt no se separa una tasa de un error de truncamiento temporal
    (splitting) que converge al bajar dt. Un ajuste lineal de e/dt en dt
    deja una parte independiente de dt de ~0.38e-2 kg/s, el 26 % del valor
    con 1 ms; con dos puntos ese ajuste no tiene grados de libertad. Ver
    Incertidumbre.
  - **Bgq domina la MEDIA de e con los dos dt** (1.55 y 1.91 veces e), pero
    NO su variación por paso. Bgq es un desplazamiento casi constante
    (sd/|media| 0.057 y 0.069) y su correlación por paso con e es 0.07 y
    −0.03. La variación de e la lleva err_cc (correlación con e 0.89 y
    0.99). err_liq compensa en parte la media de Bgq: err_liq/|Bgq| = 0.37 y
    0.49 (0.22 en `k10_base`), con correlación por paso −0.48 con 0.5 ms y
    −0.37 en `k10_base` (+0.08 con 1 ms). La talla de Bgq depende además de
    cómo se repartió gadv entre las piezas (ver Incertidumbre).
    > [fuente: el comando de abajo, sin el paso 280001]

    ```
    python3 -c "
    import csv,statistics as s
    F=lambda n,c:[float(x['m_gas_'+c]) for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>280001]
    for n in 'k10_mo20 k10_dt05 k10_base'.split():
      e,q,l,c=(F(n,k) for k in 'err_multi bg_q_multi err_liq_all err_cc_multi'.split())
      print(n,'sd/|m| Bgq %.3f err_cc %.2f; corr(Bgq,e) %.2f corr(err_cc,e) %.2f corr(Bgq,err_liq) %.2f; err_liq/|Bgq| %.2f'%(s.stdev(q)/abs(s.mean(q)),s.stdev(c)/abs(s.mean(c)),s.correlation(q,e),s.correlation(c,e),s.correlation(q,l),s.mean(l)/abs(s.mean(q))))
    "
    ```
  - **err_cc.** Se retira la lectura de C-205 de que err_cc «crece ×8.9 al
    bajar dt» y «compensa»: ese ×8.9 era el paso del reinicio. Se retira
    también, de C-207, que err_cc «no es distinto de cero»: sd/|media| (3.3
    y 7.9 sin el paso de reinicio) es dispersión por paso, no un contraste
    sobre la media. Con el error estándar por bootstrap de bloques, la media
    de err_cc es −1.08e-6 ± 3.5e-7 kg (1 ms) y −6.0e-7 ± 1.2e-7 kg (0.5 ms),
    distinta de cero en los dos bancos; es pequeña frente a e (0.07 y 0.13)
    {C-210}.
- **En la config de B1**, `k10_base`, solo como lectura y con la misma
  ventana que la tabla (sin el paso 280001) {C-229}. Estas lecturas son de
  280 s, con el transitorio de cambio de claves {C-227} y con FAIL de
  `energy_balance` y `regime_gas`. La misma config desde 290 s
  (`k11_base_s290`, solo 1 ms) está en la sección H14 {C-233}. Por quintos
  de la ventana, store_multi (4.0-4.3e-5) y Bgq (−3.7e-5 a −3.85e-5) son
  estables, pero err_free oscila de −1.5e-6 a −3.7e-5. El ×130 de store
  frente a 20 externas NO es propio de la ventana de 280 s: desde 290 s es
  ×77 {C-233}.
  - Bgq vale −3.79e-5 frente a e −2.66e-5;
  - el CG truncado deja Bx = +4.27e-6 en el multifase y +4.33e-6 en el gas
    libre;
  - ρ_f dt store_gas sube a +4.16e-5, frente a +3.2e-7 con 20 externas
    (`k10_mo20`). La causa no está medida;
  - el gas libre NO es pequeño ahí: e_free vale −1.756e-5 kg por paso, 0.66
    del multifase, con err_cc_free −1.62e-5 y store_free +6.75e-5.

  Con 20 externas, en cambio, e_free vale +9.5e-8 kg por paso, despreciable.
  > [fuente: {C-229}; python3 research/ws/WS-K10/scripts/piezas.py --sin-paso1 campaigns/b1/k10_mo20 campaigns/b1/k10_dt05 campaigns/b1/k10_base (filas «store» del multifase y tabla del gas libre); con todos los pasos los mismos números son 4.15e-5, 3.1e-7, −1.68e-5 (0.63), −1.62e-5, +6.76e-5 y +9.4e-8. Quintos: python3 -c "import csv,statistics as s; R=[x for x in csv.DictReader(open('campaigns/b1/k10_base/audit.csv')) if int(x['step'])>280001]; N=len(R); [print(c,[round(s.mean(float(x['m_gas_'+c]) for x in R[j*N//5:(j+1)*N//5]),9) for j in range(5)]) for c in ('store_multi','bg_q_multi','err_free')]"]

- **El banco de 0.25 ms dispara la centinela U_GAS_MAX** {C-222}. Tres
  pasos después del reinicio con dt acotado:

  | paso | u_gas_max [m/s] | p_max [kPa] | e/dt [kg/s] |
  |---|---|---|---|
  | 280002 | 198.6 | 281 | +7.98e-2 |
  | 280003 | **300.0** | **461** | +8.55e-2 |
  | 280004 | 200.8 | 199 | −1.04e-1 |

  `check_audit` da FAIL en `sentinel_gas`, `regime_p` (p_max 592 kPa) y
  `regime_gas`. El cociente pre-registrado depende de esos pasos:

  | pasos excluidos | r(0.25)/r(0.5) de e | de Bgq + err_cc |
  |---|---|---|
  | 280001 (criterio) | 0.812 | 0.967 |
  | 280001-280003 | 0.896 | 1.006 |
  | 280001-280004 | 0.851 | 0.983 |
  | 280001 y 280003 | 0.855 | 0.988 |

  - El veredicto {C-213} no cambia. `k10b_dt025` NO es una referencia
    limpia.
  - Fallos heredados: `k10_base`, `k10b_base` y `k8_base` dan FAIL en
    `energy_balance` y en `regime_gas`: 215 m/s en el paso 280002.
    `k10b_mo20` y `k10b_dt05` no tienen FAIL.
  - Causa, de WS-K11 {C-227}. El reinicio en 280 s enciende claves que no
    tenía la corrida que escribió el snapshot. El pico de 2 o 3 pasos existe
    con todos los dt y crece al bajar dt. Máximos en los pasos 2 a 10 tras
    el reinicio (la ventana de los criterios de C-224 y C-226):

    | banco | p_max | u_gas_max |
    |---|---|---|
    | 1 ms | 100 kPa | 163 m/s |
    | config de B1 | 94 kPa | 215 m/s |
    | 0.5 ms | 191 kPa | 188 m/s (paso 280009; 180 en el 280002) |
    | 0.25 ms | 461 kPa | 300 m/s |
    | 1 ms, desde 290 s | 55 kPa | 124 m/s |
    | 0.25 ms, desde 290 s | 79 kPa | 72 m/s |

    Desde el snapshot de 290 s, con 0.25 ms, no hay centinela en los pasos
    290002-290010. En la ventana completa de ese banco sí hay picos: p_max
    450 kPa y u_gas_max 128.6 m/s en el paso 290093, y 5 de 235 pasos con
    p_max ≥ 100 kPa (frente a 120 de 235 desde 280 s) {C-227}{C-230}. La
    observación de C-222 («bajar dt desde un snapshot asentado lleva a la
    centinela») queda sustituida por esta.
  > [fuente: python3 research/ws/WS-K10/scripts/centinela.py campaigns/b1/k10b_mo20 campaigns/b1/k10b_dt05 campaigns/b1/k10b_dt025; python3 tests/integration/check_audit.py campaigns/b1/k10b_dt025 | grep FAIL; ídem k10_base, k10b_mo20, k10b_dt05; máximos por ventana: python3 -c "import csv; [print(n,max(float(x['p_max']) for x in R)/1e3,max(float(x['u_gas_max']) for x in R)) for n,R in ((n,[x for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if 1<int(x['step'])%10000<=10]) for n in ('k10b_mo20','k10_base','k10b_dt05','k10b_dt025','k11_mo20_s290','k11_dt025_s290'))]"; ventana completa: ídem sin el filtro de paso]
- **Cociente entre dt en los pasos tranquilos** {C-223}. En los pasos con
  p_max < 100 kPa (58, 106 y 115 pasos), e por paso de 0.5 frente a 1 ms
  vale 0.353. El IC90 es de 0.334 a 0.397 con el script, o de 0.335 a 0.398
  en C-223, por el orden del generador aleatorio. Queda en el borde de la
  banda de tasa [0.35, 0.65]. Es una selección a posteriori sobre una
  variable correlacionada con e, así que es lectura, no pre-registrada.
  Sensibilidad, lectura no pre-registrada {C-229}:
  - con el umbral entre 60 y 150 kPa, el cociente va de 0.375 a 0.314;
  - excluyendo una ventana física inicial (t > 280.010, 280.020 o 280.030
    s), da 0.318, 0.306 y 0.306;
  - el cociente de 0.25 frente a 0.5 ms en los pasos tranquilos (0.844 en
    C-223) es inestable con el umbral (0.27 a 0.84) y no es interpretable;
    r(0.25)/r(0.5) de e con esas ventanas físicas da 0.863, 0.989 y 1.057.

  No se decide si el error baja más que linealmente. Todas estas cifras son
  de la ventana de 280 s y están confundidas con el transitorio de cambio de
  claves {C-227}.
  > [fuente: misma salida de centinela.py, última línea; python3 research/ws/WS-K10/scripts/sensibilidad.py campaigns/b1/k10b_mo20 campaigns/b1/k10b_dt05 campaigns/b1/k10b_dt025]
- **Tercer dt: tasa o truncamiento** {C-212}{C-213}{C-214}{C-215}{C-216}{C-217}{C-222}.
  Pre-registrado en {C-212}, commit `b03b22e`, antes de correr.
  `campaigns/b1/k10b_dt025` usa la config de `k10b_dt05` con dt fijo de
  0.25 ms, 236 pasos. Se cumplen los prerrequisitos: cero `[CG] AVISO` y los
  tres checks en PASS (decomp 1.16e-13 kg en el multifase, eos_end 3.0e-18
  kg). r es la media de la pieza por paso entre dt, sin el paso 280001. El
  IC90 de los cocientes es por bootstrap de bloques móviles (10, 20 y 40
  pasos, 4000 réplicas, semilla 1):

  | pieza | 1 ms | 0.5 ms | 0.25 ms | 0.5 / 1 (IC90) | 0.25 / 0.5 (IC90) |
  |---|---|---|---|---|---|
  | r(e) [kg/s] | −1.4505e-2 | −9.145e-3 | −7.424e-3 | 0.630 (0.60-0.68) | 0.812 (0.71-0.97) |
  | r(Bgq) | −2.250e-2 | −1.746e-2 | −1.677e-2 | 0.776 (0.75-0.80) | 0.961 (0.94-0.98) |
  | r(Bgq + err_cc) | −2.358e-2 | −1.866e-2 | −1.805e-2 | 0.792 (0.76-0.83) | 0.967 (0.91-1.04) |
  | r(err_liq + A) | +9.24e-3 | +9.59e-3 | +1.068e-2 | 1.038 (1.00-1.07) | 1.114 (1.07-1.15) |
  | r(err_liq_lk) | +8.44e-3 | +8.72e-3 | +9.40e-3 | 1.033 (1.01-1.05) | 1.078 (1.05-1.11) |
  | r(Br + Bgr) | −1.69e-4 | −6.9e-5 | −5.3e-5 | | |

  > [fuente: medias, python3 research/ws/WS-K10/scripts/tasa.py campaigns/b1/k10b_mo20 campaigns/b1/k10b_dt05 campaigns/b1/k10b_dt025; ídem con --grupos; python3 tests/integration/check_audit.py campaigns/b1/k10b_dt025 | grep -E 'mass_gas_decomp|mass_gas_row_volume|mass_gas_eos_end'; grep -c '\[CG\] AVISO' campaigns/b1/k10b_dt025/run.log. IC90 de los cocientes y del ajuste: el comando de abajo; con bloques de 5/10/20 (el mismo comando con `L=[5,10,20]`) los IC90 cambian en la segunda cifra (err_liq + A 0.25/0.5: 1.075-1.146; otra implementación del mismo método da 1.073-1.145, por el orden del generador)]

  **Sesgo de borde del bootstrap móvil.** El inicio de bloque uniforme en
  [0, n−L] da menos peso a los primeros y últimos L−1 pasos. En
  `k10b_dt025` ahí están los pasos de la centinela (280002-280004): la
  mediana bootstrap de r(0.25)/r(0.5) de e sale 0.855 frente al valor
  puntual 0.812. Con bootstrap CIRCULAR de bloques (10/20/40, 4000 réplicas,
  semilla 1), los IC90 de 0.25/0.5 son: e 0.655-0.965 (mediana 0.816), Bgq
  0.931-0.989, Bgq + err_cc 0.898-1.034, err_liq + A 1.066-1.166 y
  err_liq_lk 1.036-1.120; los de 0.5/1 casi no cambian (e 0.588-0.673). Con
  bloques no solapados de 10 ms ({C-219}, `regimen.py`), el de e es
  0.445-1.013. Las conclusiones no cambian: el IC90 de e cruza 0.75 y 0.90,
  el de Bgq excluye 1 y el de err_liq + A también. Con el circular, el
  ajuste de tres puntos queda aún menos determinado: IC90 de p de 0.65 a
  3.78 y de c/r(1 ms) de 0.04 a 0.59. Los IC90 de las demás
  tablas con bootstrap móvil (incluida la de 290 s) llevan el mismo sesgo de
  borde.
  > [fuente: el comando de abajo con `B` sustituido por el circular: `def B(v,l,g):` / `o=[];n=len(v)` / `while len(o)<n: i=g.randrange(n); o+=[v[(i+j)%n] for j in range(l)]` / `return s.mean(o[:n])`]

  ```
  python3 -c "
  import csv,math,random,statistics as s
  N='k10b_mo20 k10b_dt05 k10b_dt025'.split(); T=[1e-3,5e-4,2.5e-4]; L=[10,20,40]
  R={n:[x for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>280001] for n in N}
  def B(v,l,g):
    o=[]
    while len(o)<len(v): i=g.randrange(len(v)-l+1); o+=v[i:i+l]
    return s.mean(o[:len(v)])
  def fit(r):
    a,b=r[0]-r[1],r[1]-r[2]
    if a==0 or b/a<=0: return None
    p=math.log(a/b)/math.log(2); k=a/(T[0]**p-T[1]**p); return p,(r[2]-k*T[2]**p)/r[0]
  g=random.Random(1); q=lambda a,f:sorted(a)[int(f*len(a))]
  for nom,cs in [('e','err_multi'),('Bgq','bg_q_multi'),('Bgq+err_cc','bg_q_multi err_cc_multi'),('err_liq+A','err_liq_all pa_multi'),('err_liq_lk','err_liq_lk')]:
    v=[[sum(float(x['m_gas_'+c]) for c in cs.split()) for x in R[n]] for n in N]
    r=[s.mean(a)/t for a,t in zip(v,T)]; Q1=[];Q2=[];P=[];C=[]
    for _ in range(4000):
      b=[B(a,l,g)/t for a,l,t in zip(v,L,T)]; Q1.append(b[1]/b[0]); Q2.append(b[2]/b[1]); f=fit(b)
      if f: P.append(f[0]); C.append(f[1])
    f=fit(r); print(nom,' '.join('%.4e'%x for x in r),'| r05/r1 %.3f (%.3f-%.3f) | r025/r05 %.3f (%.3f-%.3f)'%(r[1]/r[0],q(Q1,.05),q(Q1,.95),r[2]/r[1],q(Q2,.05),q(Q2,.95)),'| p %.2f (%.2f-%.2f) c/r1 %.2f (%.2f-%.2f), %d sin ajuste'%(f[0],q(P,.05),q(P,.95),f[1],q(C,.05),q(C,.95),4000-len(P)) if f else '')
  "
  ```

  - **Veredicto de {C-212}: SIN DECIDIR por la letra** {C-213}.
    r(0.25)/r(0.5) = 0.812 queda entre 0.75 (soportada) y 0.90 (refutada).
    Su IC90 (0.71-0.97) cruza los DOS umbrales: con esta muestra el banco
    no habría podido decidir en ningún sentido {C-216}.
  - **El ajuste r = c + b dt^p no determina nada** {C-216}. El valor
    puntual es p = 1.64 y c/r(1 ms) = 0.46, pero el IC90 de p va de 0.88 a
    4.05 (72 de 4000 réplicas no dan un ajuste monótono y se excluyen) y el
    de c/r(1 ms), de 0.25 a 0.61. La sensibilidad a descartar 2 o 4 pasos
    (c −7.0e-3 y −7.2e-3) no sustituye esa barra. **Se retira** de C-214
    que el error sea «una mezcla de un ≈ 46 % que no depende de dt y una
    parte que converge como dt^1.6». Se retira también que Bgq «se comporta
    como tasa con piso»: cae ×0.776 de 1 a 0.5 ms y ×0.961 de 0.5 a 0.25 ms,
    con un IC90 (0.94-0.98) que excluye 1, y su lectura está sujeta al
    confusor de presión de abajo.
  - **Por grupos** {C-217}. Bgq se agrupa con err_cc porque el reparto de
    gadv entre los dos no es único.
    - Bgq + err_cc da 0.967 de 0.5 a 0.25 ms, con IC90 de 0.91 a 1.04: no
      se distingue de una tasa ni de una parte que aún converge. En 1268 de
      4000 réplicas el ajuste de tres puntos no es monótono.
    - err_liq + A NO es una tasa: CRECE por unidad de tiempo al bajar dt, y
      cada vez más, ×1.038 y ×1.114; el segundo IC90 (1.07-1.15) excluye 1.
      **Se retira** de C-215 que los dos grupos «son tasas de signo
      contrario».
    - Entre 0.5 y 0.25 ms, r(e) cambia en +1.72e-3 kg/s: +1.09e-3 (63 %)
      viene del CRECIMIENTO de err_liq + A y +6.2e-4 (36 %) de Bgq +
      err_cc. Lectura, sujeta al confusor de régimen: no parece una parte
      truncada que decae. Las lecturas de C-214 y
      C-215 no se reconcilian entre sí, y ninguna se sostiene.
    - La densidad posterior al último Poisson, Br + Bgr, pesa el 1.2 %, el
      0.75 % y el 0.71 % de r(e).
  - **Hipótesis, no adoptada: una pieza por paso en err_liq_lk** {C-217}{C-234}.
    La media por paso de err_liq_lk se ajusta a a dt + k, con a = 8.17e-3
    kg/s y k = +2.75e-7 kg por paso, usando 1 y 0.5 ms. El ajuste predice
    2.316e-6 kg por paso con 0.25 ms, frente a 2.349e-6 medido (1.4 %).
    - Difiere de la «operación por paso» de C-197, retirada por {C-206}:
      aquella era e entero y venía del paso de reinicio; esta es una pieza,
      err_liq_lk, medida sin el paso 280001.
    - Está confundida con el régimen de presión (abajo), igual que el resto.
    - vol_lim por paso escala con dt (4.22e-3, 2.10e-3 y 1.05e-3 m³): el
      volumen bloqueado por el limitador es una tasa. Si k existe, no está en
      ese volumen; puede estar en el recorte, el derrame u otra parte de
      err_liq_lk, que incluye también el α dador frente a a_f y el desajuste
      de densidad entre cara y celda. Partirlo exige columnas nuevas.
    - Un cuarto dt (0.125 ms, donde el modelo predice err_liq_lk/dt ≈
      1.04e-2 kg/s) y esa partición quedan para un pre-registro del
      coordinador.
    - En 290 s, con dos puntos (1 y 0.25 ms, sin el paso 290001), el mismo
      ajuste da a = 1.346e-2 kg/s y k = +1.93e-7 kg por paso {C-230}. Su
      predicción para 0.5 ms, 6.92e-6 kg por paso, se pre-registró en C-231
      (b) y quedó SOPORTADA por la letra con 6.996e-6 {C-232}. Ese resultado
      NO apoya la hipótesis {C-234}:
      - la banda [5.88e-6, 7.96e-6] contenía todo el intervalo del modelo
        sin pieza por paso (k = 0 con r monótona entre los extremos ya
        vistos: [6.83e-6, 7.12e-6]), y la interpolación lineal sin k
        (7.02e-6) queda más cerca de lo medido que el modelo con k;
      - los tres puntos son incompatibles con un k constante. Ese modelo da
        r = a + k/dt, así que el incremento de r de 0.5 a 0.25 ms sería el
        doble del de 1 a 0.5 ms. Medido es 0.71 veces (IC90 0.40-1.16,
        bootstrap circular de bloques 10/20/40), y el k de cada par baja de
        3.4e-7 kg (1 y 0.5 ms) a 1.2e-7 kg (0.5 y 0.25 ms).

      La hipótesis sigue sin adoptar. Un test de k exige un dt fuera del
      intervalo ya visto (p. ej. 0.125 ms) con una banda que excluya k = 0:
      pre-registro del coordinador.

    > [fuente: a y k salen de la fila r(err_liq_lk) de la tabla, como r·dt por paso con 1 y 0.5 ms: a = (8.441e-6 − 4.358e-6)/5e-4, k = 4.358e-6 − a·5e-4; en 290 s, de la fila err_liq_lk de la tabla «Comparación desde 290 s»: a = (1.3654e-5 − 3.5583e-6)/7.5e-4, k = 3.5583e-6 − a·2.5e-4; banda de k = 0, cociente de incrementos y k por par en 290 s: el comando de la sección H14; vol_lim, del comando del régimen de presión de abajo]
  - **Los tres dt no recorren el mismo régimen de presión** {C-216}. Sin el
    paso 280001:

    | | 1 ms | 0.5 ms | 0.25 ms |
    |---|---|---|---|
    | pasos | 58 | 117 | 235 |
    | p_max ≥ 100 kPa | 0 (0 %) | 11 (9 %) | 120 (51 %) |
    | p_max ≥ 300 kPa | 0 | 0 | 6 (3 %) |
    | p_max medio por décimo de ventana [kPa] | 83 53 37 34 33 39 39 39 39 38 | 114 68 62 59 45 55 63 48 41 49 | 175 112 112 102 103 127 123 102 98 126 |
    | p_max máximo | 100 kPa (paso 280003) | 191 kPa (280003) | 592 kPa (280161) |
    | r(e), p_max < 100 kPa [kg/s] | −1.451e-2 | −1.023e-2 | −1.727e-2 |
    | r(e), p_max ≥ 100 kPa | — | +1.28e-3 | +2.01e-3 |
    | r(Bgq), < 100 / ≥ 100 | −2.250e-2 / — | −1.729e-2 / −1.903e-2 | −1.662e-2 / −1.691e-2 |
    | r(err_cc), < 100 / ≥ 100 | −1.08e-3 / — | −2.31e-3 / +9.39e-3 | −1.07e-2 / +7.73e-3 |
    | corr(e, p_max) por paso | 0.15 | 0.32 | 0.52 |

    > [fuente: el comando de abajo, filas step > 280001]

    ```
    python3 -c "
    import csv,statistics as s
    for n,t in (('k10b_mo20',1e-3),('k10b_dt05',5e-4),('k10b_dt025',2.5e-4)):
      R=[x for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>280001]; N=len(R)
      p=[float(x['p_max']) for x in R]; m=lambda c,I:s.mean(float(R[i]['m_gas_'+c]) for i in I)/t if I else float('nan')
      lo=[i for i in range(N) if p[i]<1e5]; hi=[i for i in range(N) if p[i]>=1e5]; k=max(range(N),key=lambda i:p[i])
      print(n,'n %d, >=100 kPa %d, >=300 kPa %d | p_max por decimo [kPa]:'%(N,len(hi),sum(v>=3e5 for v in p)),' '.join('%.0f'%(s.mean(p[j*N//10:(j+1)*N//10])/1e3) for j in range(10)),
       '| max %.0f kPa (paso %s) | r(e) <100 %.3e >=100 %.3e | Bgq %.3e %.3e | err_cc %.3e %.3e | corr(e,p_max) %.2f | vol_lim %.2e'%(p[k]/1e3,R[k]['step'],m('err_multi',lo),m('err_multi',hi),m('bg_q_multi',lo),m('bg_q_multi',hi),m('err_cc_multi',lo),m('err_cc_multi',hi),s.correlation([float(x['m_gas_err_multi']) for x in R],p),s.mean(float(x['vol_lim']) for x in R)))
    "
    ```

    - El primer décimo tiene la presión más alta con los tres dt: el
      transitorio del reinicio dura más de un paso en presión, y descartar 2
      o 4 pasos no lo cubre.
    - No es solo el primer décimo: con 0.25 ms la media por décimo se queda
      en 98-127 kPa toda la ventana, y el máximo (592 kPa, paso 280161) cae
      tarde. Desde 290 s, con las claves ya activas, el banco de 0.25 ms
      tiene p_max ≥ 100 kPa solo en 5 de 235 pasos {C-227}: el régimen alto
      de toda la ventana de 280 s acompaña al transitorio de cambio de claves.
    - En los pasos con p_max ≥ 100 kPa, e cambia de signo. Con p_max < 100
      kPa, r(e) NO es monótono en dt (−1.45e-2, −1.02e-2 y −1.73e-2 kg/s).
    - Bgq apenas cambia con el régimen; lo que cambia de signo es err_cc.
    - Por tanto los cocientes entre dt mezclan el truncamiento con un cambio
      de estado. Un veredicto limpio pide snapshots asentados con cada dt y
      la ventana medida después del asentamiento: es un pre-registro del
      coordinador.
- **Comparación desde 290 s** {C-230}. LECTURA NO PRE-REGISTRADA, hecha
  después de ver los datos. `k11_mo20_s290` (config de `k10b_mo20`, 1 ms) y
  `k11_dt025_s290` (config de `k10b_dt025`, 0.25 ms) corrieron con el
  binario `k10b`, 15 ranks, desde `judge_otp_280/eaf3d_00290000.h5`,
  escrito ya con las dos claves activas {C-226}{C-227}. Cero `[CG] AVISO` y
  sin FAIL de `check_audit`. Sin el paso 290001 (58 y 235 pasos), frente a
  los mismos dt desde 280 s (`k10b_mo20`, `k10b_dt025`). Bootstrap de
  bloques móviles de 10 y 40 pasos, 4000 réplicas, semilla 1:

  | pieza | / e, 1 ms, 280 s | / e, 1 ms, 290 s | / e, 0.25 ms, 280 s | / e, 0.25 ms, 290 s | r(0.25)/r(1), 280 s (IC90) | r(0.25)/r(1), 290 s (IC90) |
  |---|---|---|---|---|---|---|
  | e [kg/paso] | −1.4505e-5 | −4.934e-5 | −1.856e-6 | −1.027e-5 | 0.512 (0.45-0.62) | 0.833 (0.82-0.85) |
  | Bgq | 1.55 | 1.17 | 2.26 | 1.24 | 0.745 (0.73-0.76) | 0.877 (0.86-0.89) |
  | err_liq | −0.57 | −0.28 | −1.27 | −0.34 | 1.135 (1.10-1.16) | 1.040 (1.03-1.05) |
  | err_cc | 0.07 | 0.10 | 0.17 | 0.13 | 1.19 (0.54-3.0) | 1.08 (1.03-1.29) |
  | A | −0.07 | −0.01 | −0.17 | −0.02 | 1.34 (1.21-1.41) | 1.36 (1.27-1.49) |
  | Br2 | −0.68 | −0.30 | −0.27 | −0.05 | 0.20 | 0.13 |
  | Bgr | 0.69 | 0.32 | 0.28 | 0.05 | 0.21 | 0.14 |
  | Br + Bgr | 0.012 | 0.019 | 0.007 | 0.004 | 0.31 (0.27-0.44) | 0.20 (0.19-0.21) |
  | Bgq + err_cc | 1.63 | 1.27 | 2.43 | 1.36 | 0.766 (0.73-0.82) | 0.893 (0.88-0.91) |
  | err_liq + A | −0.64 | −0.29 | −1.44 | −0.37 | 1.156 (1.12-1.19) | 1.055 (1.04-1.06) |
  | err_liq_lk | −0.58 | −0.28 | −1.27 | −0.35 | 1.113 (1.08-1.14) | 1.042 (1.03-1.05) |

  > [fuente: el comando de abajo; la fila e da las medias por paso en kg; las demás, la pieza / e del mismo banco]

  ```
  python3 -c "
  import csv,random,statistics as s
  P={'e':'err_multi','Bgq':'bg_q_multi','err_liq':'err_liq_all','err_cc':'err_cc_multi','A':'pa_multi','Br2':'brho_end_multi','Bgr':'bg_rho_multi','Br+Bgr':'brho_it_multi brho_end_multi bg_rho_multi','Bgq+err_cc':'bg_q_multi err_cc_multi','err_liq+A':'err_liq_all pa_multi','err_liq_lk':'err_liq_lk'}
  F=lambda n,p0:[x for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>p0+1]
  def B(v,L,g):
    o=[]
    while len(o)<len(v): i=g.randrange(len(v)-L+1); o+=v[i:i+L]
    return s.mean(o[:len(v)])
  for a,b,p0 in (('k10b_mo20','k10b_dt025',280000),('k11_mo20_s290','k11_dt025_s290',290000)):
    Ra,Rb=F(a,p0),F(b,p0); g=random.Random(1); V=lambda R,cs:[sum(float(x['m_gas_'+c]) for c in cs.split()) for x in R]; ea,eb=s.mean(V(Ra,'err_multi')),s.mean(V(Rb,'err_multi'))
    for k,cs in P.items():
      va,vb=V(Ra,cs),V(Rb,cs); ma,mb=s.mean(va),s.mean(vb); q=sorted((B(vb,40,g)/2.5e-4)/(B(va,10,g)/1e-3) for _ in range(4000))
      print(a,'%-10s 1ms %+.4e /e %+.3f | 0.25ms %+.4e /e %+.3f | r025/r1 %.3f IC90 %.3f-%.3f'%(k,ma,ma/ea,mb,mb/eb,4*mb/ma,q[200],q[3800]))
  "
  ```

  - **Las cifras entre dt desde 280 s están confundidas.** Los IC90 de
    r(0.25)/r(1) de e, Bgq y err_liq en 290 s no se solapan con los de 280
    s. Que la caída de e con dt desde 280 s la cause el transitorio de
    cambio de claves es una hipótesis alternativa que estos datos
    respaldan; no está descartada ni medida.
  - Un ajuste lineal r = c + b dt con estos dos puntos dejaría ~78 % de
    r(e, 1 ms) independiente de dt (26 % desde 280 s, con 1 y 0.5 ms). Con
    dos puntos no tiene grados de libertad: no separa tasa de truncamiento.
  - La magnitud es de estado, no del transitorio: con 1 ms, e por paso es
    ×3.4 mayor en 290 s que en 280 s, estable en los cinco quintos de cada
    ventana (−1.38e-5 a −1.50e-5 en 280 s; −4.80e-5 a −5.09e-5 en 290 s).
  - Se sostienen en las dos ventanas: Bgq es la pieza de mayor media, y Br
    + Bgr pesa menos del 2 % de e (1.9 % con 1 ms en 290 s, al borde).
    err_liq + A crece por unidad de tiempo al bajar dt en las dos (×1.156 y
    ×1.055).
  - Salvedades: dos dt y una trayectoria por dt; el binario no es el que
    corrió `judge_otp_280`, así que puede haber un transitorio pequeño de
    cambio de binario (salvedad de {C-226}); el banco de 0.25 ms tiene 5
    pasos con p_max ≥ 100 kPa, con 450 kPa en el paso 290093; y como estos
    datos ya se vieron, NO pueden pre-registrarse. La corrida nueva de 0.5
    ms desde `eaf3d_00290000.h5` se pre-registró en {C-231} y se juzgó en
    {C-232}: ver la sección H14. Con tres dt, el ajuste c + b·dt^p pasa
    exactamente por los tres puntos (sin grados de libertad); su barra de
    error sale del bootstrap (ver H14).
  > [fuente: quintos: python3 -c "import csv,statistics as s; [print(n,[round(s.mean(R[j*len(R)//5:(j+1)*len(R)//5]),8) for j in range(5)]) for n,R in ((n,[float(x['m_gas_err_multi']) for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>p+1]) for n,p in (('k10b_mo20',280000),('k11_mo20_s290',290000)))]"; check_audit y AVISO: comandos de {C-227}]

- **H14: comparación entre dt desde 290 s** {C-231}{C-232}{C-233}{C-234}.
  - Pre-registrada en {C-231}, commit `798e2ad`, antes de correr el banco
    nuevo `campaigns/b1/k11_dt05_s290`: config de `k10b_dt05` desde
    `judge_otp_280/eaf3d_00290000.h5`.
  - Alcance: 20 externas, CG 1000, ventana 290.00-290.06 s y una
    trayectoria por dt. No dice nada de la config de B1 (5 externas, CG 20)
    entre dt: ese banco no existe (ver «Config de B1» abajo y Sitio).
  - Los bancos de 1 y 0.25 ms desde 290 s (`k11_mo20_s290`,
    `k11_dt025_s290`) ya se habían visto, y no deciden.
  - Prerrequisitos cumplidos: cero `[CG] AVISO`; sin FAIL; p_max máximo de
    71 kPa; los tres checks en PASS.

  | por unidad de tiempo [kg/s] | 1 ms | 0.5 ms | 0.25 ms | 0.5 / 1 | 0.25 / 1 |
  |---|---|---|---|---|---|
  | e | −4.934e-2 | −4.328e-2 | −4.108e-2 | **0.877** | 0.833 |
  | Bgq | −5.793e-2 | −5.283e-2 | −5.081e-2 | 0.912 | 0.877 |
  | err_liq | +1.359e-2 | +1.391e-2 | +1.414e-2 | 1.023 | 1.040 |
  | err_cc | −4.76e-3 | −4.70e-3 | −5.14e-3 | 0.986 | 1.080 |
  | A | +6.7e-4 | +7.6e-4 | +9.1e-4 | 1.132 | 1.361 |
  | Br + Bgr | −9.1e-4 | −4.2e-4 | −1.8e-4 | 0.457 | 0.195 |

  > [fuente: python3 research/ws/WS-K10/scripts/h14.py campaigns/b1/k11_mo20_s290 campaigns/b1/k11_dt05_s290 campaigns/b1/k11_dt025_s290; python3 tests/integration/check_audit.py campaigns/b1/k11_dt05_s290]

  - **Veredicto (a): SOPORTADA por la letra.** r(0.5)/r(1) = 0.877 cae en
    [0.85, 1.00]. Su IC90 es 0.860-0.894 por bootstrap circular de bloques
    (10 y 20 pasos), o 0.862-0.891 con el móvil: dentro de la banda.
    - **Poca potencia.** Con r(0.25)/r(1) = 0.833 ya visto {C-230},
      cualquier r(dt) monótona entre 1 y 0.25 ms da r(0.5)/r(1) en [0.833,
      1.00]: lineal 0.888, dt² 0.866, dt^0.5 0.902.
    - La banda de soportada cubría casi todo ese rango. La rama de
      refutación (≤ 0.70) solo se alcanzaba con una r no monótona.
    - La corrida nueva confirma la interpolación. Lo que sostiene
      «mayormente tasa» es el 0.833, que no estaba pre-registrado, y la
      curvatura de abajo.
  - **Veredicto (b): SOPORTADA por la letra, sin poder frente a k = 0.**
    err_liq_lk por paso = 6.996e-6 kg cae en [5.88e-6, 7.96e-6].
    - El modelo sin pieza por paso (k = 0, r monótona entre r(1) =
      1.3654e-2 y r(0.25) = 1.4233e-2 kg/s) da [6.83e-6, 7.12e-6], dentro
      de la banda.
    - Su interpolación lineal (7.02e-6) está más cerca de lo medido que la
      del modelo con k (6.92e-6).
    - Los tres puntos contradicen un k constante: el cociente de
      incrementos vale 0.71 (IC90 0.40-1.16) frente a 2. Ver «Hipótesis, no
      adoptada» en «Tercer dt». La hipótesis de k sigue sin adoptar.
  - **Curvatura (lectura no pre-registrada)** {C-234}. r(0.25)/r(0.5) =
    0.949 (IC90 0.925-0.972) frente a r(0.5)/r(1) = 0.877 (0.860-0.894).
    - Los IC90 no se solapan: la caída por unidad de tiempo se frena al
      bajar dt, y una ley de potencia pura (c = 0) queda excluida.
    - El ajuste r = c + b·dt^p pasa exactamente por los tres puntos (sin
      grados de libertad). Da p = 1.47 (IC90 0.81-2.43) y c/r(1 ms) = 0.81
      (0.73-0.84), con barra por bootstrap. Las 4000 réplicas dan un ajuste
      monótono.
    - Es esto, y no el criterio (a), lo que sostiene «mayormente tasa» en
      esta ventana. c es una extrapolación dentro de ese modelo, no una
      medida. Se retira la frase anterior «con 3 dt no se cuantifica la
      parte que converge».
  - **Confusor de régimen, más débil que en 280 s** {C-234}.
    - Con 1, 0.5 y 0.25 ms, p_max medio vale 30.8, 35.2 y 45.1 kPa, y
      u_gas_max medio 98.9, 78.1 y 69.3 m/s.
    - El banco de 0.25 ms arranca con r(e) ≈ −3.9e-2 kg/s en los primeros
      12 ms, y después se queda entre −4.0e-2 y −4.2e-2.
    - Al excluir t ≤ 290.01, 290.02 y 290.03 s, r(0.25)/r(0.5) pasa de
      0.949 a 0.961, 0.969 y 0.984. r(0.5)/r(1) se queda en 0.874-0.880.
    - Por eso la parte de r que depende de dt (del 12 al 19 % de r(1 ms))
      no puede atribuirse a truncamiento: puede ser una relajación tras
      acotar el dt o un régimen distinto. La conclusión principal no cambia,
      porque esa parte es pequeña. Separarla exige snapshots asentados con
      cada dt: es un pre-registro del coordinador.
  - **Lectura.** En esta ventana y con esta config, el error de la meseta
    multifase es mayormente una tasa (c/r(1 ms) ≈ 0.8). EN ESTA
    CONTABILIDAD, la pieza de mayor media es Bgq. Que Bgq sea una tasa
    física y no un artefacto del reparto de gadv no está medido (ver
    Incertidumbre). err_liq + A crece levemente por unidad de tiempo al
    bajar dt, como en 280 s.
  > [fuente: el comando de abajo (bootstrap circular de bloques de 10/20/40 pasos, 4000 réplicas, semilla 1; filas step > 290001). Con bloques móviles: r(0.5)/r(1) 0.862-0.891, r(0.25)/r(0.5) 0.936-0.972, c/r(1 ms) 0.77-0.84, cociente de incrementos 0.43-1.20. El revisor-refutador obtuvo 0.39-1.18 para este último con otra implementación del mismo método]

  ```
  python3 -c "
  import csv,math,random,statistics as s
  N='k11_mo20_s290 k11_dt05_s290 k11_dt025_s290'.split(); T=[1e-3,5e-4,2.5e-4]; L=[10,20,40]
  R={n:[x for x in csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')) if int(x['step'])>290001] for n in N}
  V=lambda c:[[float(x['m_gas_'+c]) for x in R[n]] for n in N]
  def B(v,l,g):
    o=[];n=len(v)
    while len(o)<n: i=g.randrange(n); o+=[v[(i+j)%n] for j in range(l)]
    return s.mean(o[:n])
  def fit(r):
    a,b=r[0]-r[1],r[1]-r[2]
    if a==0 or b/a<=0: return None
    p=math.log(a/b)/math.log(2); k=a/(T[0]**p-T[1]**p); return p,(r[2]-k*T[2]**p)/r[0]
  q=lambda a,f:sorted(a)[int(f*len(a))]
  for c in ('err_multi','err_liq_lk'):
    v=V(c); r=[s.mean(a)/t for a,t in zip(v,T)]; g=random.Random(1); Q1=[];Q2=[];I=[];P=[];C=[]
    for _ in range(4000):
      b=[B(a,l,g)/t for a,l,t in zip(v,L,T)]; Q1.append(b[1]/b[0]); Q2.append(b[2]/b[1]); I.append((b[2]-b[1])/(b[1]-b[0])); f=fit(b)
      if f: P.append(f[0]); C.append(f[1])
    f=fit(r); print(c,'r05/r1 %.3f (%.3f-%.3f) r025/r05 %.3f (%.3f-%.3f) incr %.2f (%.2f-%.2f)'%(r[1]/r[0],q(Q1,.05),q(Q1,.95),r[2]/r[1],q(Q2,.05),q(Q2,.95),(r[2]-r[1])/(r[1]-r[0]),q(I,.05),q(I,.95)),'p %.2f (%.2f-%.2f) c/r1 %.2f (%.2f-%.2f) sin ajuste %d'%(f[0],q(P,.05),q(P,.95),f[1],q(C,.05),q(C,.95),4000-len(P)) if f else '')
  lk=[s.mean(a) for a in V('err_liq_lk')]; r=[m/t for m,t in zip(lk,T)]
  print('err_liq_lk por paso %.4e %.4e %.4e | k=0 monotono: [%.3e, %.3e] | lineal %.3e | k(1,0.5) %.2e k(0.5,0.25) %.2e'%(*lk,min(r[0],r[2])*5e-4,max(r[0],r[2])*5e-4,(r[0]+(r[2]-r[0])*2/3)*5e-4,2*lk[1]-lk[0],2*lk[2]-lk[1]))
  for n in N: print(n,'p_max medio %.1f kPa, u_gas_max medio %.1f m/s'%(s.mean(float(x['p_max']) for x in R[n])/1e3,s.mean(float(x['u_gas_max']) for x in R[n])))
  for t0 in (290.01,290.02,290.03):
    rr=[s.mean(float(x['m_gas_err_multi']) for x in R[n] if float(x['time'])>t0)/t for n,t in zip(N,T)]; print('t > %.2f s: r(0.5)/r(1) %.3f r(0.25)/r(0.5) %.3f'%(t0,rr[1]/rr[0],rr[2]/rr[1]))
  for n,t in zip(N,T): print(n,'r(e) por 12 ms',[round(s.mean(float(x['m_gas_err_multi']) for x in R[n] if 290+j*0.012<float(x['time'])<=290+(j+1)*0.012)/t,4) for j in range(5)])
  "
  ```
  - **Config de B1 desde 290 s** (`k11_base_s290`, lectura, solo 1 ms)
    {C-233}{C-234}:
    - frente a 20 externas, e_multi vale −6.77e-5 kg por paso contra
      −4.93e-5, y Bgq −7.92e-5 contra −5.79e-5;
    - ρ_f dt store_gas del multifase vale +4.66e-5 frente a +6.1e-7, ×77.
      El almacenamiento grande es propio de la config de B1, no de la
      ventana de 280 s;
    - el gas libre suma −2.21e-5 kg por paso: err_cc_free −1.89e-5,
      store_free +7.56e-5 y Bx_free +1.6e-6. El CG truncado deja además
      Bx_multi = +2.4e-6;
    - da FAIL en `energy_balance` (gap/permitido 2.15) y ya NO en
      `regime_gas` (u_gas_max 106.9 m/s): el 215 m/s de `k10_base` era el
      transitorio del cambio de claves;
    - su `run.log` tiene un `[CG] AVISO`; los tres bancos de 20 externas,
      ninguno;
    - ni H14 ni el reparto de las piezas con dt están medidos en esta
      config.
  > [fuente: el comando de {C-233} (python3 scripts/research/ledger.py show C-233), filas step > 290001; gas libre: el mismo comando con m_gas_err_cc_free, m_gas_store_free y m_gas_bx_free; python3 tests/integration/check_audit.py campaigns/b1/k11_base_s290 | grep -E 'FAIL|regime_gas'; grep -c '\[CG\] AVISO' campaigns/b1/k11_base_s290/run.log campaigns/b1/k11_mo20_s290/run.log campaigns/b1/k11_dt05_s290/run.log campaigns/b1/k11_dt025_s290/run.log]

## Incertidumbre

- **Muestra mínima.**
  - En 280 s, una ventana con un reinicio y una trayectoria por config.
  - En 290 s, tres dt: dos ya vistos {C-230} y uno pre-registrado
    {C-231}{C-232}. Hay una trayectoria por dt en 60 ms.
  - B1 por encima de 280 s exige un juez estadístico con varias
    trayectorias. Los IC90 de este reporte son de bootstrap de bloques
    dentro de UNA trayectoria: no recogen la varianza entre trayectorias ni
    entre ventanas.
  - Generalizar H14 a «el error de la meseta» exige otra ventana u otras
    trayectorias. Las magnitudes y los pesos /e cambian entre las dos
    ventanas.
- **El transitorio del primer paso** al acotar el dt del reinicio afecta a
  cualquier comparación entre dt desde `judge_otp_280`. Las lecturas se dan
  sin ese paso, y el veredicto se juzgó con él, como fijó el criterio
  ({C-202}, todas las filas). Una comparación limpia de dt exigiría un
  snapshot con el dt nuevo, o descartar en el pre-registro una ventana
  física de al menos 20 ms; aun así el régimen difiere. Y, por {C-227}, un
  snapshot escrito con las MISMAS claves: desde 280 s todo banco lleva el
  transitorio del cambio de claves. El paso 1 tras acotar el dt existe
  también con un snapshot de las mismas claves (290001 de `k11_dt025_s290`)
  y la referencia Tg_end heredada participa en él ({C-230}, `k11_dt025_tgfix`):
  toda comparación entre dt excluye ese paso. Los bancos de 1 y 0.25 ms
  desde 290 s ya se habían leído {C-230}. La corrida nueva de 0.5 ms desde
  `eaf3d_00290000.h5` se pre-registró en {C-231} y se juzgó en {C-232}.
  Otra ventana (p. ej. un snapshot de 300 s escrito con las mismas claves)
  o la config de B1 entre dt exigen corridas nuevas: son del coordinador.
- **Tasa o truncamiento.** Desde 280 s, sin separar. Desde 290 s, mayormente
  tasa, pero solo en una ventana.
  - Desde 290 s (20 externas, CG 1000, 290.00-290.06 s, una trayectoria por
    dt), H14 queda soportada por la letra {C-232}. La curvatura de los tres
    puntos da c/r(1 ms) = 0.81 (IC90 0.73-0.84) {C-234}: mayormente tasa.
  - El criterio (a) tenía poca potencia: con el 0.833 ya visto, su rama de
    refutación era inalcanzable con una r monótona. El criterio (b) no tenía
    poder frente a k = 0 {C-234}.
  - Sigue abierto si la parte que depende de dt (12-19 %) es truncamiento o
    cambio de régimen: p_max medio de 31, 35 y 45 kPa.
  - Sigue abierto si vale fuera de esa ventana, con otras trayectorias o en
    la config de B1.
  - Sigue abierto si existe k por paso en err_liq_lk. En 290 s los tres
    puntos contradicen un k constante.
  - Desde 280 s no se distingue si e es una tasa (un sesgo de flujo que no
    depende de dt) o un error de truncamiento temporal que converge al
    bajar dt; ninguna de las dos lecturas está medida ahí:
  - El tercer dt (0.25 ms, {C-212}) quedó SIN DECIDIR por la letra {C-213}.
    El cociente pre-registrado, 0.812, tiene IC90 de 0.71 a 0.97 por
    bootstrap de bloques móviles (0.655-0.965 con bootstrap circular, que
    no infrapondera los pasos de la centinela en el borde) y cruza los dos
    umbrales (0.75 y 0.90): con esta muestra no podía decidir {C-216}.
  - **Confusor de ventana:** todos los cocientes entre dt de este reporte
    salvo los de la sección «Comparación desde 290 s» son de 280 s y están
    confundidos con el transitorio de cambio de claves {C-227}. Desde 290 s,
    r(0.25)/r(1) de e vale 0.833 (IC90 0.82-0.85) frente a 0.512 (0.45-0.62)
    desde 280 s {C-230}.
  - El ajuste de tres puntos no determina el exponente (IC90 de p de 0.88 a
    4.05) ni la parte fija (c/r(1 ms) de 0.25 a 0.61). Se retiraron las
    lecturas de C-214 y C-215 {C-216}{C-217}.
  - **Confusor:** con otro dt cambia la trayectoria. Los pasos con p_max ≥
    100 kPa son el 0 %, el 9 % y el 51 %, y en ellos err_cc y e cambian de
    signo; con p_max < 100 kPa r(e) no es monótono en dt {C-216}. El
    cociente entre dt no es el de una pieza aislada. Separar tasa y
    truncamiento exige snapshots asentados con cada dt y la ventana medida
    tras el asentamiento.
  - err_liq + A crece por unidad de tiempo al bajar dt {C-217}; la
    hipótesis de una pieza por paso en err_liq_lk no está adoptada (C-231
    (b) no tenía poder frente a k = 0, {C-234}).
- **La contabilidad no es única.** err_cc RESTA ρ_f dt gadv_used y Bgr + Bgq
  lo SUMAN: la talla de Bgq depende de cómo se repartió gadv entre las
  piezas. No están exportadas las magnitudes brutas de los dos términos de
  Bgq (dt Σ ρ_it gadv_used y dt Σ_caras (ρ_dador − ρ_it) q_out); si son
  mucho mayores que Bgq, Bgq es una diferencia pequeña entre dos términos
  grandes. Tampoco hay columna de Bgq restringida a las celdas con
  err_liq ≠ 0, que diría si Bgq y err_liq son dos caras del mismo desajuste
  en las mismas caras.
  - Por eso «Bgq es la tasa dominante» (resumen y H14) vale solo EN ESTA
    CONTABILIDAD. Si Bgq es una diferencia pequeña entre dos términos
    grandes, «partir Bgq» se dirigiría a un artefacto de reparto.
  - Separarlo exige columnas nuevas: dt·Σ ρ_it·gadv_used y dt·Σ_caras
    (ρ_dador − ρ_it)·q_out por separado, y Bgq en las celdas con err_liq ≠ 0.
    Exige también un barrido de externas con CG convergido (20, 40 y 80)
    desde 290 s. Las dos cosas son del coordinador.
- **Bgq junta tres cosas, no dos:**
  - las caras de la guardia ALPHA_CUTOFF de `gas_adv`;
  - el desfase entre el caudal PREDICHO con que `gas_adv` ensambla
    (af·u_f·A, `src/mod_pressure_3d.f90:1291-1495`) y el corregido
    (Fg + ag·Δpp, `:893-905`), dt Σ_in (ρ_N − ρ_P)(q* − q). Es proporcional
    al pp del último outer, que no está linealizado en la fila;
  - las caras que cambian de sentido.

  Alternativa no descartada: la parte en pp es el residuo del lazo externo
  estancado, que no converge en ningún banco (C-184), y no algo estructural.
  Bgq vale −3.79e-5 en `k10_base` (5 externas) y −2.25e-5 en `k10_mo20`
  (20 externas), ×1.68, pero los dos bancos difieren también en el CG (20
  frente a 1000 iteraciones), así que esa diferencia no aísla las externas.
  Partirla exige columnas nuevas y un barrido de externas (20, 40, 80, como
  `k8s_mo40` y `k8s_mo80`); queda para un pre-registro del coordinador.
- **Riesgo de repetir un fracaso.** La guardia ALPHA_CUTOFF de `gas_adv`
  existe por M6-1 (el advectivo con T_g rancia en celdas sin gas daba −3.6e4
  veces su gas) y la de `ws_qin_cap` por M7-5 (caudal fantasma). Si la pieza
  resulta estar en las caras de la guardia, quitarla o relajarla repetiría
  esos fallos; linealizar gadv en pp dentro de la fila queda cerca de las
  lecciones de Plan D sobre el acople implícito. Cualquier arreglo debería
  fijar `slag_chem_flow` y `bath_fill` sin regresión como prerrequisito.
- **Sitio.**
  - Las lecturas entre dt son de 20 externas y CG 1000: en 280 s, una
    ventana de 59 ms; en 290 s (H14), 290.00-290.06 s. Hay una trayectoria
    por dt.
  - B1 corre con 5 externas y CG 20. Desde 290 s con esa config
    (`k11_base_s290`, solo 1 ms) {C-233}{C-234}, el gas libre suma −2.21e-5
    kg por paso: err_cc_free −1.89e-5, store_free +7.56e-5 y Bx_free
    +1.6e-6. A eso se suma Bx_multi = +2.4e-6.
  - store del multifase es ×77 el de 20 externas (×130 en 280 s): el
    almacenamiento grande es propio de la config de B1, no de la ventana.
    Esa misma config en 280 s (`k10_base`) lleva el cambio de claves y un
    FAIL de `regime_gas`; err_free oscila allí por quintos de −1.5e-6 a
    −3.7e-5 {C-229}.
  - Ni H14 ni el reparto de las piezas con dt están medidos en la config de
    B1. Extender la conclusión a B1 exige un banco nuevo pre-registrado:
    config de B1 con 0.5 ms desde `eaf3d_00290000.h5`, comparado con
    `k11_base_s290`, midiendo e_multi + e_free por unidad de tiempo. Hoy no
    existe.
  - No está medido el vínculo entre este error de masa y los ciclos α–p de
    342 s que paran B1. Antes de dirigir un arreglo al multifase haría falta
    además un banco con el binario `k10b` y la config de B1 en la ventana
    340-345 s.
  - Los dos bancos son del coordinador.
- **El peso de la densidad.** err_liq, err_cc y A se evalúan con ρ_f; con
  otra contabilidad (ρ_it por celda) el reparto entre Br2, Bgr y esas piezas
  cambiaría. No se ha reevaluado.
- **A no se partió.** Contiene la densidad rancia de cada llamada al
  complemento, la congelación, el recorte y el derrame del último
  transporte. Pesa −0.07 e.
- **La identidad no vale** con las dos claves `pc_fs_*` de Plan D, que solo
  usa `bed_flood`, ni con escoria condensada (`liq_ok` falso). Ahí los checks
  dan «n/a».
- **El lazo externo no converge en ningún banco** (WS-K8). La descomposición
  es la del iterado del último outer.
- **Procedencia de la base de la suite: NO verificable por un tercero.** La
  comparación de los 61 bancos se hizo contra una copia en el scratchpad de
  la sesión de trabajo de WS-K10, que es efímero y no es visible desde otra
  sesión (un revisor no la encontró). En esa sesión, en la ronda 1 del
  ciclo 2, la copia seguía coincidiendo sha256 a sha256 con
  `research/ws/WS-K10/logs/base_audit_manifest.txt` y `cmp_comunes.py`
  volvía a dar «61 idénticos». No hay binario ni log que la ate a
  `934c2d4`. Atenuantes verificados: golden v132 en PASS (rtol 1e-12) y las
  137 columnas comunes idénticas de `k8s_*`/`k8_base` frente a `k10_*`.
  Archivar la base o regenerarla desde `934c2d4` con log y sha del binario
  queda para el coordinador: el redactor solo edita este reporte.
- **Checker del veredicto C-204 no versionado.** Ver Resultado,
  prerrequisitos, {C-218} y {C-221}. Resuelto: el checker versionado con
  esta pieza reproduce el PASS de los `k10_*`.
- **Correcciones duplicadas.** {C-235}, del coordinador, repite parte de {C-234} (potencia de C-231 y k constante). {C-219} y {C-220}, del coordinador, duplican
  a {C-216} y {C-217}, del redactor. Usan un bootstrap independiente, con
  bloques de 10 ms: el IC90 de r(0.25)/r(0.5) de e sale de 0.445 a 1.013,
  más ancho que el de 0.71 a 0.97 de C-216. Las dos versiones dicen lo
  mismo: el cociente no decide.
  > [fuente: python3 research/ws/WS-K10/scripts/regimen.py campaigns/b1/k10b_mo20 campaigns/b1/k10b_dt05 campaigns/b1/k10b_dt025]
- **Copia en las reglas (hecha por el coordinador en la ronda 3).**
  En la ronda 3, `.claude/rules/transporte-energia.md` (entrada WS-K10)
  copiaba como hechos las lecturas retiradas de C-214 («~46 % que no depende
  de dt», «dt^1.6») y de C-215 (los dos grupos «son TASAS»). Decía además
  «Siguiente: partir Bgq» sin las condiciones de este reporte. Las
  condiciones que había que copiar allí antes de pre-registrar ese reparto:
  - que faltan las magnitudes brutas de los dos términos de Bgq;
  - que hace falta el banco con el binario `k10b` y la config de B1 en la
    ventana 340-345 s, donde el gas libre pesa 0.66 del multifase;
  - que Bgq apenas cambia con el régimen de presión (−1.66e-2 frente a
    −1.69e-2 kg/s con 0.25 ms) y que lo que se mueve es err_cc {C-216}.

  El coordinador reescribió la entrada WS-K10 de la regla con estas
  condiciones y retiró de ella las lecturas de C-214 y C-215.

  Pendiente tras la ronda 1 del ciclo 2, HECHO por el coordinador antes de
  la ronda 3 del ciclo 2 (la regla acota ahora H14 a 20 externas, CG 1000 y
  290.00-290.06 s, pone «en esta contabilidad», cita la poca potencia de
  C-231 con {C-234} y {C-235}, y dice «sin transitorio de claves; el primer
  paso tras acotar dt se excluye siempre»). Lo que decía la entrada WS-K10
  de la regla:
  - copia «el error de la meseta multifase es MAYORMENTE una TASA» sin
    acotar la config: 20 externas, CG 1000, 290.00-290.06 s y una
    trayectoria por dt;
  - dice «Bgq es la tasa dominante» sin «en esta contabilidad»;
  - cita «C-231 SOPORTADA» sin la poca potencia de (a) ni la falta de poder
    de (b) frente a k = 0 {C-234};
  - dice que desde `eaf3d_00290000.h5` «no hay transitorio». Debería decir:
    «sin transitorio de claves; el primer paso tras acotar dt se excluye
    siempre (C-230)».
- **Tests, repetidos por el coordinador antes de la ronda 3 del ciclo 2.**
  `make test-full` se volvió a correr el 28-oct a las 00:39 con el checker
  actual. La cabecera de `research/ws/WS-K10/logs/test_full.txt` registra el
  sha del diff staged de `src/` y `tests/` (660ee6ac…, el mismo de
  `status.json`), el del árbol de trabajo de `src/` (74a5e2a4…) y el del
  binario compilado. Resultado: `TESTS (full): OK`, y los tres checks dan 41
  PASS y 27 «n/a». Lo que sigue de este punto describe el log anterior, ya
  sustituido.
- **Tests (log anterior).** El `test_full.txt` de las 22:36 era anterior al
  último cambio de `tests/integration/check_audit.py` (23:24, {C-221}): su
  recuento de 41 PASS y 27 «n/a» es del checker previo. Con el checker
  actual, los tres checks pasan en los 43 bancos de `tests/out` donde
  aplican, y en 36 dan «n/a». `test_full.txt` tampoco registra el sha del
  diff de `src/` con que corrió, así que no se ata al diff actual
  (`status.json`: `diff_sha` 660ee6ac…). La última modificación de `src/`
  es anterior al log, y el sha del diff de `src/` coincide con el del
  binario `k10b` (`opt_identidad.txt`). Eso es compatible con el diff
  actual, pero no lo prueba. `checks_suite.txt` no registra el comando que
  lo generó; es el de la fuente de abajo. La diferencia entre las 68
  evaluaciones de `test_full.txt` y los 79 `audit.csv` se concilia en
  Proceso, punto 3: 2 reinicios de reloj que no pasan por `check_audit`, y
  9 bancos con `solve_flow = false` en los que el checker de entonces no
  imprimía nada. Repetir `make test-full` con el checker actual y guardar
  el sha del diff junto al log es del coordinador. `make test-quick` se
  corre sobre el diff aprobado antes del commit; hoy `status.json` tiene
  `test_quick` en null.
  > [fuente: research/ws/WS-K10/logs/checks_suite.txt, regenerable con: for d in $(find tests/out -name audit.csv -exec dirname {} \;); do python3 tests/integration/check_audit.py $d; done | grep -E 'mass_gas_(decomp|row_volume|eos_end)' | awk '{print $1,$2}' | sort | uniq -c]

