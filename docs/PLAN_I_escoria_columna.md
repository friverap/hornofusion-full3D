# Plan I — Oxidación por columna y chatarra que atraviesa la escoria (17-oct-2026)

Decisiones del usuario (17-oct-2026, tras la auditoría 19): (1) estencil de
oxidación POR COLUMNA; (2) la chatarra del ECS, de la cesta 2 y del colapso
ATRAVIESA la escoria condensada; (3) implementar ahora en la rama `plan-i` y
probar cuando termine B1 (corridas solo secuenciales; B1 desde el 17-oct 05:08).

## I1 — Oxidación por columna (solo `slag_condensed_on`)

Problema: con la capa condensada compactada, el estencil celda-a-celda (O2 en
la celda de escoria y baño en la de abajo) solo actúa donde una celda parcial
de escoria toca el baño; la capa resuelta aísla el metal del O2
(`slag_chem_flow` 2.7 → 0.99 kg; `activity` con umbral 0.5 kg).

Modelo final (tras las dirigidas I1 e I1-b), `slag_oxidation_column`. En cada
columna (i,j), sobre el tramo de escoria RESUELTA (α_sl ≥ ALPHA_FLOW_CUTOFF:
una traza de upwind bajo la interfaz no cuenta) más bajo, con kb su celda
inferior y kt la superior:
- O2 = remanente del paso del gas de kt MÁS el de kt+1, cada uno solo si la
  celda tiene gas (α_g ≥ ALPHA_CUTOFF, la guardia del solver de especies);
  el sumidero se reparte en proporción (la segunda parte es el resto);
- Fe del acero de kb hasta su cota (F_MAX_FE) y el resto del baño de kb−1
  hasta la suya (sumas, nunca una fuente elegida por umbral: la tasa saltaba
  ~90-100 veces); FeO, calor y O2 se rehacen desde el Fe repartido;
- r_FeO = η_feo · O2 (misma cinética que E2.3), cota térmica sobre la
  escoria de kb, que recibe el FeO (masa y energía con el dato coherente de
  la auditoría 19). Auditoría: AUD_FE_YIELD y AUD_SLAG_OX_E repartidas entre
  los dueños de las celdas (take_fe por fuente).
- Patrón invariante MPI: máscara de escoria resuelta con halos, MIN global 2D
  de kb y kt (el tope más bajo es el del tramo de kb), valores de las celdas
  elegidas en planos 2D con un solo dueño y suma global exacta, mismo
  cálculo en todos los ranks, escritura de celdas propias.
- Sustituye al estencil local solo con la escoria condensada (en legado no
  cambia). Corre antes de congelar el hueco de la reducción (BAJO-5,
  documentado). Columnas con escoria solo en trazas no oxidan; queda un salto
  residual (~1.5×) en α_sl(kb) ≈ 0.01 con gas frío.

Test unitario `test_slag_ox_column`: 5 casos (capa compactada; celda parcial
con cociente exacto frente al legado; interfaz con acero; traza bajo la
interfaz; acero en traza que agota la cota de kb), con Fe, O y energía
contra el audit.

## I2 — La chatarra atraviesa la escoria condensada

Problema: el ECS fija la superficie con α_l ≥ ALPHA_LIQ_CONT (acero) y su
capacidad solo desplaza gas; el colapso trata una celda llena de escoria como
"vacío" pero no puede meter chatarra en ella; la cesta 2 se apoya sobre baño +
escoria. La chatarra (ρ ≫ ρ_sl) queda flotando sobre la capa y aislada del
baño.

Modelo final (tras las dirigidas I2, I2-b y la auditoría general): con la
escoria condensada la chatarra que cae sobre escoria ocupa las celdas de
escoria hasta apoyarse en el acero o el lecho; el volumen desplazado lo sube
el reordenamiento de inicio de paso (`slag_condensed_sort`, extensión sobre
el gas, auditado como volfix), conservando masa, E_sl y m_X.
- ECS: capacidad por celda min(vfrac − α_s, α_g + α_sl), con un presupuesto
  de volumen por columna igual al gas libre desde la base menos el piso de
  poro (allreduce 2D decrementado por nivel): nunca sobrellena; lo que no
  cabe queda pendiente. La superficie ya es el tope del acero.
- Cesta 2: cota de carga = tope del ACERO (máximo GLOBAL de la cima del
  lecho y del tope del acero, como antes: si queda chatarra alta en alguna
  columna la cesta va sobre ella en todas); dentro de la escoria la chatarra
  dispersa (α_s ≤ ALPHA_SCRAP_SURF) no es lecho, como en el colapso.
- Presupuesto del ECS: volumen LIBRE real (1 − α_s − α_l − α_sl − poro, con
  signo) desde la base: ve el solape de una cesta 2 del mismo paso.
- Colapso: hueco 1 − α_l (la escoria no es soporte ni ocupa el hueco).
- Sort: si una columna no cabe ni hasta el techo (estado de error), compacta
  con las capacidades escaladas por el sobrellenado, avisa `[SLAG] AVISO`
  (el harness falla) y el exceso entra al SIMPLE; bit a bit igual cuando cabe.

Tests unitarios: casos condensados de `test_charge_slag` (30 t), `test_ecs_feed`
(2 t con control legado pendiente; escoria hasta el techo: todo pendiente),
`test_scrap_collapse` y `test_condensed_sort` caso 8 (sobrellenado).

## Orden y estado

I1 → dirigidas (I1, I1-b) → I2 → dirigidas (I2, I2-b) → general (3
dimensiones) hechos en la rama `plan-i`. Mientras corre B1: compilados y
ENLAZADOS (simulador + los 41 unit tests, banderas de desarrollo -O2
-fcheck=bounds -Wall, en un arbol aparte, sin ejecutar nada); los avisos del
compilador en lo tocado son solo las comparaciones exactas intencionadas de
los tests bit a bit. Falta EJECUTAR (gates de abajo).

## Aceptados de la auditoría general (con causa)

- Σα > 1 transitorio entre la cesta 2/ECS y el sort de inicio de paso: el
  arco, el MC, la DO y la fusión ven el solape un paso (celdas algo más
  opacas); sin pérdida de masa ni energía. Llamar al sort justo tras la
  carga duplicaría sus gathers por paso con el ECS activo.
- Salto de kt cuando α_sl del tope cruza 0.01 (el O2 cae ~2× ese paso) y del
  piso de poro cuando α_s cruza ALPHA_BED dentro de la escoria (gas 0.015·V
  auditado como volfix): acotados; rampas solo si el juez estadístico de B6
  los señala.
- Solo en un horno SOBRELLENADO (estado de error que ya hace fallar el
  harness con `[SLAG] AVISO`): el exceso puede concentrarse en una celda con
  chatarra y el CO depositado en un techo sin gas lo descarta el solver de
  especies (queda en m_gas_rxn). El FeO de la oxidación por columna y el
  fundido pendiente que llegan tras el ECS solo pueden sobrellenar una
  columna con el presupuesto agotado (techo a ≤ 4 celdas).

## Gates tras B1 (en orden, uno por uno)

1. `make test-unit` (los 5 tests de arriba y el resto sin regresión).
   HECHO el 18-oct-2026 con B1 en curso (autorizado por el usuario: solo los
   unit tests, singleton, nice 19, binarios del árbol aparte): 41/41 PASS.
   Oxidación por columna: caso 2 = 3.09× el estencil local (O2 de la celda y
   de la de encima); test_condensed_sort caso 8 emite el aviso de
   sobrellenado esperado (x1.46). Repetirlo con `make test-unit` tras B1 (el
   binario de tests/bin).
1b. `make test-quick` antes de la verificación bit a bit.
2. `/verificacion-bitwise` de lo que debe quedar idéntico: `slag_chem_test`
   n1/n8/n9 (legado), `ecs_test` n1/n8/n12, `cold_bucket2_n4`,
   `arc_slag_legacy`; `arc_slag` y `slag_rest` solo cambiarían con
   sobrellenado (si cambian, diagnosticar).
   **Nota (auditoría 20, 21-oct):** el golden v128 (8b50511) YA incluye el
   cambio numérico de I1/I2 (v127 era anterior al Plan I), aunque su mensaje
   lo atribuye solo a E2/J-B; los gates 2 y 4–9 siguen sin ejecutar. El
   `--min-yield` del gate 3 se subió en 9b78456 (flow 4.1, thick 1.5 kg).
3. `slag_chem_flow_n4` y `slag_chem_thick_n1/n4`: medir el Fe oxidado y
   α_sl(kb); subir `--min-yield` claramente por encima de 0.99 kg (el
   condensado SIN I1), p.ej. 0.6 × lo medido; `fe_element`/`slag_mass` a
   1e-10 y `check_audit`.
4. Descomposición de I1 (general 2, M1; interfaz medida en v127: thick
   kb−1 = 18, kb = 19, kt = 20, kt+1 = 21; flow kb = kt = 3, kt+1 = 4): thick
   n1 frente a n7 (1x1x7, corta 18|19 = kb−1|kb) y n12 (1x2x6, corta 20|21 =
   kt|kt+1 y θ); flow n1 frente a n7 (corta 2|3) y n5 (corta 3|4); rtol
   1e-7. n4 y n9 cortan lejos de la interfaz (no prueban los planos 2D).
   Re-medir kb/kt con I1 antes de fijar los np.
   **HECHO (21-oct, HEAD f57e950):** kb/kt sin cambio con I1 (thick 19/20,
   flow 3/3, índices desde 1). thick n1 frente a n7 (1x1x7) 4.6e-8 y n12
   (1x2x6) 2.2e-8: PASA 1e-7. flow NO llega a 1e-7 con ninguna
   descomposición, tampoco la que corta lejos (n4 1x2x2: X_C 4.3e-6; n5,
   corte kt|kt+1: 4.7e-6; n7, corte kb−1|kb: S_chem 3.2e-5). El exceso de n7
   es el TDMA de especies con 2 barridos (`max_inner_mom = 2` del banco,
   halos entre barridos): con 30 barridos S_chem cae a 1.1e-7 e Y_CO de 5.4e-6
   a 3.2e-7; X_C ~5e-6 queda igual en todas (nivel del banco con flujo).
   `slag_oxidation_column` es invariante por construcción (un dueño por
   valor de plano, suma de ceros). Sin defecto del Plan I.
5. Reinicio con escoria en el tramo con oxidación: `slag_chem_flow` 4→4 (ya
   existe) y 4→7 (rtol 1e-10); thick con `output_freq` 15 y 4→12.
6. Banco nuevo `ecs_slag` (config ya en tests/integration/configs, 60 t de
   escoria con k0 llena y 20 kg/paso; cifras estimadas: medir el paso 0): n1/n9/n12 (nz 16: n12 corta r, n9 corta z
   en la escoria), `decomposition_ecs_slag` rtol 1e-9 al principio (con flujo
   la invarianza medida es 1e-10..1e-13) y luego ~10× lo medido; reinicio
   9→9 y 9→12; `check_slag_bed`; `--clip-abs-max 3e-4` en el audit.
7. `check_ecs.py ecs_slag_n9 --slag` (HECHO el script, probado en seco):
   guarda de otras rutas del sólido, dE_sol = E_ecs_in − E_slag_sol (no
   nulo), masa de escoria con el clip, nada pendiente, base = k0 con escoria
   resuelta. Si con `solve_energy` actúa la interfase (E_iph_sol ≠ 0), la
   guarda lo dirá: entonces sumar esa columna a la identidad.
8. Banco `cold_bucket2_slag` (config ya creada; 60 t de escoria, k6 llena;
   sin fusión): la cesta 2 atraviesa una capa sin gas y el sort sube la
   escoria en el paso de carga. n1/n9, `check_slag_bed`, base de la cesta,
   `decomposition_bucket2_slag` rtol 1e-7, reinicios 9→9 cruzando la carga
   (paso 5) y después (15). El colapso que atraviesa la escoria solo lo
   cubre el caso 3 de `test_scrap_collapse` (en 0.2 s nada funde lo bastante;
   un banco de integración exigiría una fusión larga): hueco conocido.
   **HECHO gates 5-8 (21-oct, golden v129):** `ecs_slag` n1/n9/n12 y
   `cold_bucket2_slag` n1/n9 en la matriz. check_ecs --slag n9: masa del ECS
   err 5.7e-16, energía 1.7e-16 (E_slag_sol −6.6e5 J, no nulo), escoria
   dm + clip 1.5e-11 kg de 6e4, nada pendiente, 16 columnas con base k0 y 16
   con desplazamiento (I2 ejercido). check_slag_bed: orden y masa en ambos
   (clip 8.6e-14 y 2.4e-11 kg). Descomposición: velocidades 1.4e-6 (ecs n9),
   6.0e-6 (n12), 1.9e-6 (cesta n9); α_sl 1.3e-9; rtol 2e-5/6e-5/2e-5 (~10×).
   Reinicios ecs 9→9 (paso 30) y cesta 9→9 (5 y 15): BIT A BIT (0.0). Los
   reinicios con distinto nº de ranks (ecs 9→12, flow 4→7) dan lo mismo que
   la corrida continua con esa descomposición: el snapshot está completo.
   thick con `output_freq` 15, reinicio desde el paso 15: 4→4 bit a bit,
   4→12 2.2e-8 (T_sl, rtol 1e-7). Gates 1-10 hechos; queda el 11 (juez
   estadístico con escoria antes de usar el Plan I en campaña).
   **Gate 2 HECHO (21-oct):** 788287c frente a 15816f4 (punta de plan-i), rtol
   0: slag_chem_test n1/n8/n9, ecs_test n1/n8/n12, cold_bucket2 n4,
   arc_slag_legacy n4, arc_slag n4 y slag_rest n4 idénticos.
   Notas: en la franja de redondeo del sort (vtol) la última celda puede
   quedar con Σα − 1 ≤ 1e-10·V_col/V_k2; los allreduce de bud/dvb del ECS son
   sumas parciales por rank (no bit a bit entre descomposiciones cuando el
   presupuesto limita; cabe en el rtol 1e-9 de `decomposition_ecs_slag`).
9. `arc_melt_slag_n4` y `arc_melt_slag_heel_n1/n4`: solo ven trazas de
   escoria (α_sl ≤ 0.015); probable bit a bit; `decomposition_slagbed`.
10. `make test-full` y `STAGE=v128 make test-rebaseline` (cambian seguro
    `slag_chem_flow_n4`, `slag_chem_thick_n1/n4`; probable
    `arc_melt_slag*`; nuevos `ecs_slag_*`, `cold_bucket2_slag_n4`).
11. Juez estadístico con escoria (tipo B6, varias trayectorias) para los
    saltos aceptados (kt, piso de poro) antes de usar el Plan I en campaña.
