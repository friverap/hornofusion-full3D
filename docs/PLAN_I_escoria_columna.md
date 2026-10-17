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

Modelo (O2 inyectado/arrastrado que atraviesa la capa): en cada columna (i,j)
- `kt` = celda TOPE de la escoria (α_sl ≥ ALPHA_CUTOFF más alta del tramo);
  O2 disponible = el remanente del paso en el gas de `kt` (si α_g(kt) ≥
  ALPHA_FLOW_CUTOFF) o de `kt+1` (gas libre encima);
- `kb` = celda de interfaz (la de escoria más baja); Fe del acero de `kb`
  (acero resuelto propio) o de `kb−1` (baño de abajo);
- r_FeO = η_feo · O2_rem (misma cinética que E2.3) con las MISMAS cotas: Fe
  extraíble (F_MAX_FE del acero de origen) y cota térmica sobre la capacidad
  de la escoria de `kb` (que recibe el FeO).
- FeO, su masa y su energía (dato coherente, auditoría 19) a la escoria de
  `kb`; Fe sale del acero de origen (fe_out, a su entalpía); O2 sale del gas
  de la celda de O2 (S_O2_src). Columnas y auditoría: las de E2.3
  (AUD_FE_YIELD, AUD_SLAG_OX_E).
- Patrón invariante MPI: gather global de α_l, α_sl, α_g, ρ_g, Y_O2,
  S_O2_src, m_sl, E_sl, T_l y cp; mismo barrido en todos los ranks; cada rank
  aplica a sus celdas propias.
- Modo legado y celdas donde el estencil local ya actúa: sin cambio (en
  condensado la oxidación por columna SUSTITUYE al estencil local para no
  contar dos veces el mismo O2).

Gates: `slag_chem_flow` y `slag_chem_thick` con `fe_element`/`slag_mass`
exactos (1e-10), energía cerrada, actividad de oxidación del orden del legado
(umbral de `activity` de vuelta a ~1 kg en `slag_chem_flow`), invarianza
n1/n4 (rtol 1e-7) y reinicio bit a bit; unit test de una columna (O2 arriba,
escoria compactada de 3 celdas, baño abajo) con conservación de Fe, O y
energía.

## I2 — La chatarra atraviesa la escoria condensada

Problema: el ECS fija la superficie con α_l ≥ ALPHA_LIQ_CONT (acero) y su
capacidad solo desplaza gas; el colapso trata una celda llena de escoria como
"vacío" pero no puede meter chatarra en ella; la cesta 2 se apoya sobre baño +
escoria. La chatarra (ρ ≫ ρ_sl) queda flotando sobre la capa y aislada del
baño.

Modelo: con la escoria condensada, la chatarra que cae sobre escoria se
coloca en las celdas de escoria (desplazando escoria, no solo gas) hasta
apoyarse en el baño o el lecho; el volumen de escoria desplazado lo sube el
reordenamiento (`slag_condensed_sort`, extensión del tramo sobre el gas;
gas auditado como volfix), de forma conservativa (masa, E_sl, m_X).
- ECS: capacidad por celda min(vfrac − α_s, α_g + α_sl); superficie = tope del
  ACERO (no del condensado).
- Cesta 2 (`charge_scrap` bucket > 1): cota de carga = tope del acero, no del
  baño + escoria (A11-1 queda para el acero: la chatarra no desplaza acero).
- Colapso: una celda de escoria condensada no es soporte (capacidad incluye
  α_sl).
- El sort de inicio de paso ya corre después del ECS, la cesta 2 y la
  prefusión (colapso): resuelve el solape escoria/chatarra antes del SIMPLE.
- Contacto escoria–chatarra (A18-10) y fusión bajo la escoria se ejercen.

Gates: banco nuevo `ecs_slag` (ECS sobre baño con capa condensada gruesa):
la chatarra termina bajo la escoria (ninguna celda con α_s sobre escoria
resuelta), masa/energía de escoria exactas, volfix acotado, sin Σα > 1;
`test_charge_slag` y `test_ecs_feed` extendidos; `cold_bucket2` con escoria;
matriz completa y rebaseline.

## Orden y estado

I1 → dirigida → I2 → dirigida → general. Código en la rama `plan-i`,
verificado solo por sintaxis (`mpif90 -fsyntax-only` en un árbol aparte,
sin enlazar ni ejecutar) mientras corre B1; gates al terminar B1.
