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
- Cesta 2: cota de carga = tope del ACERO.
- Colapso: hueco 1 − α_l (la escoria no es soporte ni ocupa el hueco).
- Sort: si una columna no cabe ni hasta el techo (estado de error), compacta
  con las capacidades escaladas por el sobrellenado, avisa `[SLAG] AVISO`
  (el harness falla) y el exceso entra al SIMPLE; bit a bit igual cuando cabe.

Tests unitarios: casos condensados de `test_charge_slag` (30 t), `test_ecs_feed`
(10 t con control legado pendiente; escoria hasta el techo: todo pendiente),
`test_scrap_collapse` y `test_condensed_sort` caso 8 (sobrellenado).

## Orden y estado

I1 → dirigidas (I1, I1-b) → I2 → dirigidas (I2, I2-b) → general (3
dimensiones) hechos en la rama `plan-i`, verificados SOLO por sintaxis
(`mpif90 -fsyntax-only`, sin enlazar ni ejecutar) mientras corre B1.

## Gates tras B1 (en orden, uno por uno)

1. `make test-unit` (los 5 tests de arriba y el resto sin regresión).
2. `/verificacion-bitwise` de lo que debe quedar idéntico: `slag_chem_test`
   n1/n8/n9 (legado), `ecs_test` n1/n8/n12, `cold_bucket2_n4`,
   `arc_slag_legacy`; `arc_slag` y `slag_rest` solo cambiarían con
   sobrellenado (si cambian, diagnosticar).
3. `slag_chem_flow_n4` y `slag_chem_thick_n1/n4`: medir el Fe oxidado y
   α_sl(kb); subir `--min-yield` claramente por encima de 0.99 kg (el
   condensado SIN I1), p.ej. 0.6 × lo medido; `fe_element`/`slag_mass` a
   1e-10 y `check_audit`.
4. Descomposición de I1: `slag_chem_flow` n1 con `decomposition_slagflow`
   y `slag_chem_thick` con un np cuyo corte en z caiga en la interfaz medida
   (n7, n12 o n9 según kb), rtol 1e-7 (n4 corta lejos de la interfaz).
5. Reinicio con escoria en el tramo con oxidación (`slag_chem_flow` 4→4 ya
   existe; añadir uno con np distinto).
6. Banco nuevo `ecs_slag` (baño con capa condensada gruesa, `solve_ecs`):
   n1/n8/n12 con `decomposition_ecs_slag` a 1e-12, reinicio, invariantes.
7. `check_ecs.py --slag` (H4): masa con las columnas de fusión, energía por
   la identidad de `check_audit`, masa/energía de escoria, `m_ecs_pending`
   = 0, base de `layer_id == ID_ECS` = tope del acero + 1 en la banda.
8. Banco `cold_bucket2_slag` (cesta 2 de toneladas sobre capa condensada).
9. `arc_melt_slag_n4` y `arc_melt_slag_heel_n1/n4`: el colapso que atraviesa
   la escoria cambia volfix/jumps; si superan su techo, diagnosticar (nunca
   subirlo sin causa); `decomposition_slagbed`.
10. `make test-full` y `STAGE=v128 make test-rebaseline` (cambian seguro
    `slag_chem_flow_n4`, `slag_chem_thick_n1/n4`; probable
    `arc_melt_slag*`; nuevos `ecs_slag_*`, `cold_bucket2_slag_n4`).
