# Plan D — acople implícito α–p: bitácora

Plan: `docs/PLAN_D_acople_implicito_alpha_p.md`. Antecedentes: `2026-09-29_colapso_al_perforar_el_lecho.md`.

## D0 — banco `bed_flood` (7-oct-2026): REPRODUCE el régimen de B1 en 8 s

Config `tests/integration/configs/bed_flood.dat` + receta
`input/recipe_bed_flood_flat.dat` (clave nueva `charge_recipe_file`, 072c696).
Malla 12×24×16, piso PLANO (`H_bowl = 0`), 3 niveles de chatarra densa
(α_s 0.85) inundados por un heel de 50 t (poro al límite, α_g = 0.015), 4
niveles de chatarra suelta (0.5) a 1805 K que el arco funde (~2 t/s) y drena
hacia el lecho. 4 ranks, dt 2 ms, 12 s ≈ 10 min de pared.

Variantes descartadas: T_initial 1815 (funde los 390 t en 0.6 s), 1700 (nada
funde en 3 s), cubo de líquido puro bajo el lecho (H_bowl 0.6: el fallo
aparece pero más tarde y más suave, u_l en cota desde 10 s).

Resultado (variante D): p_max 289 kPa a 7.92–8.02 s (ferrostática ~10 kPa),
gas en U_GAS_MAX, 681 kPa a 8.02 s, 999 kPa a 11.95 s; centinelas en 4.7 % de
los pasos de 12 s. La celda del pico (k=4, j=2, i=3) tiene α_l 0.991,
α_s 0.009, α_g 0.000: LLENA de líquido, sobre el lecho inundado (k=1–3,
α_l 0.135, α_g 0.015). Es el water packing de B1 a 320 s, en miniatura.
Masa exacta (clip 7e-10 kg).

## D1 — instrumentación de los tres desfases (7-oct-2026)

Columnas nuevas del audit (m³ de líquido por paso, última iteración externa):
`vol_dalpha_outer` (Σ|α_l tras el transporte − α_l del iterado entrante|·V),
`vol_lim` (entrada bloqueada por el limitador de hueco), `vol_unlinked`
(flujo por caras que el Poisson no enlazó: disperso/drift). Glosario
regenerado. Correlación con p_max: `scratchpad/cand/d1_corr.py`. Resultado:
pendiente.

### Sonda `[PROBE-P]` en la celda del pico (k=4, j=2, i=3; pasos 3945–4015)

Antes del pico (pasos 3955–3966, α_l 0.94→0.95, α_g 0.016→0.015):
- outer 1: `Su_liq = +0.225 m³/s` (líquido entrando por la cara superior),
  pp ≈ +1.3e4; outers 2–5: `Su_liq = 0.000` exacto y pp negativa (−2e3..−1e4).
  La cara inferior al poro lleno (k=3, hueco 0) ya la cierra F2.8; en outers
  2–5 el flujo de líquido pedido es cero y manda el gas.
En el pico (pasos 3998–4004): α_g → 0.0000 (el gas se fue), Su_comp = 0,
`aP` cae de 1e-5 a 4e-7 (sin caras de gas ni acústico: solo caras de
líquido con d = αV/aP_u ~ 4e-7 por la inercia ρ u Δx/Δt), y `Su_liq` sigue
en +0.15..0.25 m³/s. pp = Su/aP ≈ ±3e5 Pa por outer, con signo alternante;
p_in sube de 27 kPa a 378 kPa en 3 pasos. Es la entrada que el limitador
BLOQUEARÁ en el transporte (α_l solo crece 5e-4/paso) pero que el Poisson
pide cada iteración: lag 2 del plan, literal. La celda NO es del lecho
(α_s 0.009 < 0.01): `ws_liq_room = 1` para el Poisson (F2.8 no la cierra)
mientras el limitador del transporte sí la ve llena (liq_cap − α_l = 8e-4).
Esa inconsistencia binaria/continua es lo que D2.2 generaliza:
`ws_lim_step` (fracción de la entrada que cupo, agregada por paso) escala
coeficiente y Q* de cada cara de líquido hacia la celda receptora, para
TODAS las celdas, en las iteraciones externas siguientes del mismo paso
(sin estado entre pasos: el reinicio no cambia). Clave `pc_limiter_faces`.

### D1, correlación en el banco (`scratchpad/cand/d1_D`, 12 s, 6001 pasos)

Spearman de cada desfase del paso n con p_max del paso n+1:
`vol_lim` +0.94, `vol_unlinked` +0.93, `vol_dalpha_outer` +0.64.
Mediana en pasos sanos vs de pico (p > 100 kPa, 485 de 6001):
vol_lim 2.1e-3 → 2.1e-2 m³ (×10); vol_unlinked 2.4e-3 → 1.6e-2 (×7);
vol_dalpha 4e-5 → 1.5e-4 (×4, y 100× más pequeño en valor absoluto).
Lectura: el lag 1 (α rezagada en los coeficientes) es menor; los lags 2
(limitador fuera del Poisson) y 3 (flujo por caras no enlazadas: el goteo
disperso de la chatarra suelta que funde) son del mismo tamaño y crecen
juntos con el fundido acumulado. El volumen que el limitador bloquea es casi
igual al que llega por caras que el Poisson no enlaza: la celda muerta se
llena sobre todo por GOTEO que la ecuación de presión nunca vio. D2.2 (caras
con limitador) ataca el lag 2; D2.3 (drift como fuente conocida) el lag 3.

## D2.2 — caras del limitador en el Poisson (7-oct-2026): sola, EMPEORA

`ws_lim_step` (fracción de la entrada que cupo, agregada por paso) escala
coeficiente y Q* de cada cara de líquido hacia la receptora, en los outers
siguientes del mismo paso. Banco (`d2_D` vs `d1_D`): p>100 kPa 15.2 % (base
8.1 %), centinelas 11.2 % (4.7 %), pico 473 kPa a 11.4 s; idéntico hasta
7.2 s. Cerrar la cara en el Poisson sin que el momento lo sepa mueve el
problema a la celda donante.

### El mecanismo que faltaba (sonda `[PROBE-MOM]` + snapshots)

La celda de baño llena sobre el poro lleno cae a −1.3…−1.6 m/s durante 50+
pasos con `presion/grav = 0.6–0.77`: NO está en equilibrio hidrostático.
Snapshot a 8 s (23 celdas llenas sobre lecho): p(k) − p(k+1) = 25.8 kPa
(ρ g Δz = 20.7, hidrostático) pero p(k−1) − p(k) = −5.8 kPa: el poro lleno
de ABAJO tiene MENOS presión que la celda de baño. Sus caras de líquido
están cerradas (F2.8), su fila es sólo el gas de poro (o el Neumann de
F2.29), y su p no es la continuación hidrostática de la columna; el
gradiente CENTRADO del momento del baño la lee igual →
(p(k+1) − p(k−1))/2Δz ≈ ½ ρ g → el baño cae a g/2 contra una cara cerrada
→ la entrada que el limitador bloquea y la presión que la frena en un paso
(ρ u Δx/Δt ~ MPa). Es Bug 16 en una variante: la celda SÍ tiene fase
continua, pero está hidráulicamente sellada para el líquido.

## D2.2b — celda sellada para el líquido = pared de su gradiente (7-oct)

`ws_pv_liq`: falsa donde el líquido es activo y la suma de sus coeficientes
de cara de líquido en el último Poisson del paso es cero (`lcoef`). Usos:
(1) gradiente de presión del LÍQUIDO en el momento (`pv_ok`) y en el
Rhie–Chow del Poisson (`pv_cell` con `grad_is_gas`): diferencia unilateral
desde el lado con fluido; (2) el líquido de la celda sellada no se mueve.
Sólo dentro del paso (`ws_pv_liq_id`): sin estado en el reinicio. Clave
`pc_liq_sealed_wall`. Juez: `d2b_D` (con caras D2.2) y `d2b_nofaces_D`
(sin ellas) vs `d1_D`. Resultado: pendiente.

NOTA (7-oct): los primeros `d2b_D`/`d2b_nofaces_D` se lanzaron desde su
propio directorio y `charge_recipe_file`/`electrode_profile.dat` (rutas
relativas) cayeron al DEFAULT en silencio: corrieron otro caso (lecho 0.5,
P_arc 7.5e7). Invalidados. Guardia nueva: una receta nombrada que no abre es
error. Los bancos se lanzan SIEMPRE desde la raíz del repo.

### Resultado D2.2b (banco válido, n=4, 12 s; % de pasos)

| variante | p>100k | gas>200 | liq>10 | centinela |
|---|---|---|---|---|
| base (d1_D) | 8.1 | 12.5 | 9.4 | 4.7 |
| D2.2 caras del limitador | 15.2 | 23.9 | 7.2 | 11.2 |
| D2.2 + D2.2b pared sellada | 13.6 | 24.1 | 0.0 | 10.1 |
| **D2.2b sola (F2.8 binario)** | **4.9** | **5.7** | **0.0** | **2.0** |

La pared sellada para el líquido elimina las excursiones del líquido y
reduce a la mitad las de presión y gas; las caras escaladas del limitador
(D2.2) empeoran en toda combinación → `pc_limiter_faces` queda en false.
No es cura: 4.9 % de pasos > 100 kPa. Ablación en n=2/n=8 en curso
(`scratchpad/cand/abl_*`).

(El "pico a 1 s" de D2.2b fue un artefacto de lectura: `time[:6]` recortaba
"1.1076E+001"; verificado con `d2b_early` (0–1.3 s): nada. Los picos
restantes de D2.2b están a 7.9, 10.2 y 11.1 s, en la celda llena (k=4,
α_g = 0) con la cara superior ABIERTA hacia una celda de baño que cae a
−1.27 m/s: callejón sin salida no sellado. D2.2c: cierre BINARIO de las
caras hacia una celda con `ws_lim_step < pc_lim_dead` (0.5), para que quede
sellada y D2.2b la vuelva pared.)

### Ablación D2.2b en tres descomposiciones (n=2/4/8; % de pasos, 12 s)

| | p>100k | gas>200 | liq>10 | centinela |
|---|---|---|---|---|
| base n4 / n8 | 8.1 / 7.8 | 12.5 / 11.7 | 9.4 / 8.6 | 4.7 / 4.4 |
| pared sellada n2 / n4 / n8 | 3.8 / 4.9 / 4.4 | 4.9 / 5.7 / 5.4 | 0 / 0 / 0 | 1.7 / 2.0 / 2.0 |

Mejora consistente en las tres trayectorias (base n2 no es comparable: ver
nota). D2.2b se queda.

### Anomalía abierta: NaN NO determinista a n=2 (base, 7-oct)

`abl_base_n2` (pared OFF) murió en el paso 2 (liq%u no finito en la celda
local (1,1,1) del rank 1 = eje + costura θ + piso; +41 t de líquido por el
fallback implícito; p en la cota). La MISMA config relanzada dos veces (con
y sin sondas) corre limpia: lectura de memoria no inicializada (clase B1 v10,
halos de frontera física), dependiente del heap. Con la pared ON a n=2 no
apareció (una trayectoria). Un build con `-ffpe-trap -finit-real=snan
-fcheck=all` (copia en scratchpad/trap_tree) falla ya en la inicialización
de la malla a n=2 (tamaños locales basura) — probablemente interacción de
los flags con MPI, no concluyente. Instrumento correcto: añadir `bed_flood`
a `compare_decomposition` (n1 vs n2 vs n4) cuando D2 se estabilice; hasta
entonces, ninguna conclusión se apoya en una sola trayectoria a n=2.

### D2.2c (cierre binario, umbral 0.5) + pared: PEOR (n4 / n8)

p>100k 17.1 / 15.1 %, gas>200 23.5 / 22.7 %, liq>10 8.2 / 7.4 %, centinela
11.2 / 9.6 % (pared sola: 4.9 / 4.4, 5.7 / 5.4, 0 / 0, 2.0 / 2.0). Cerrar
caras de líquido en el Poisson — continuo o binario — es perjudicial en
toda combinación: la celda donante pasa a ser el callejón sin salida y la
columna se sella de abajo arriba. `pc_limiter_faces` queda en false.
Base fb06a44 a n=2 (worktree): 12 s sin NaN; liq>10 61.6 %, centinela 32.7 %
(una trayectoria; el NaN de `abl_base_n2` sigue sin reproducirse).
Siguiente experimento (barato, sólo config): ¿es un problema de CONVERGENCIA
del lazo externo? `max_outer` 5→15 y `alpha_p` 0.3→0.7 sobre la pared sola.
Si cura: D2.1 (correctores internos α↔p) es la inversión correcta.

### Convergencia del lazo externo: NO es la causa (7-oct)

Pared sola, n4: max_outer 5→15: p>100k 5.5 % (4.9), centinela 0.8 % (2.0);
alpha_p 0.3→0.7: 5.2 %, 2.9 %. Ruido de trayectoria; sin cura. D2.1
(correctores internos α↔p) no es la inversión prioritaria.

### Lectura del mecanismo restante (sonda d0_Dprobe, pasos 3997→3998)

Mientras la celda F (α_s 0.009, sobre el lecho) conserva 1.5–2.5 % de gas,
el término acústico α_g ρ_g V/(P0 Δt) le da COMPLIANCIA: parar la entrada
de 0.2 m³/s cuesta Δp ≈ P0·ΔV/(α_g V) ≈ 36 kPa/paso. En el paso en que
α_g → 0.0000 (gas expulsado), `Su_comp` = 0, `aP` cae de 1e-5 a 4e-7 y la
MISMA entrada cuesta Su/aP ≈ 3e5 Pa. Es, literal, la frase de RELAP5 §3.4.6:
"the discontinuous change in compressibility between a two-phase mixture of
small void fraction and a pure liquid phase". El lecho (α_s ≥ 0.01) no lo
sufre porque su líquido es inmóvil (Ergun) y su fila es pared; la celda de
baño sobre el lecho sí. Candidato D2.4: compliancia RESIDUAL en toda celda
con líquido activo — piso `alpha_g_comp_min` en el término acústico (sólo en
la diagonal; el volumen y la masa no cambian; el exceso lo mueve el
derrame, auditado). Es el `residualAlpha`/compresibilidad artificial de los
solvers incompresibles y la opción B-2 del Plan C. Default 0 (bit-idéntico).

## D2.4 — compliancia residual (7-oct): acota el pico, no la causa

`alpha_g_comp_min` 0 / 3e-3 / 1e-2 (pared sola, n4): p>100k 4.9 / 4.1 /
3.8 %; centinela 2.0 / 1.6 / 1.1 %. El pico de F pasa de 268 a 142 kPa
(cota de diseño ~P0·ΔV/(α_min V)), pero se repite cada ~0.1 s: el forzante
sigue.

### El forzante, medido (sondas `comp_probeT` k=5 y `comp_probeF` k=4)

T (celda de baño SUPERFICIAL: α_l 0.99, α_g 0.01, con gas encima y F
debajo) cae a −1.5 m/s de forma persistente con `presion/grav = 0.47–0.70`:
NO está en equilibrio hidrostático aunque F (24 kPa) y ella (8 kPa) sí lo
estén entre sí. Causa: el gradiente CENTRADO del momento del líquido en la
celda de superficie usa la presión del CENTRO de la celda de gas de arriba
(≈ 0) y la de la celda de abajo: (0 − 3/2 ρ g Δz)/(2Δz) = −¾ ρ g para una
columna hidrostática exacta. La celda superficial de todo baño siente ¾ g
(o menos con F parcialmente vacía) y cae; el líquido de la superficie
drena hacia la celda de abajo hasta que ésta se llena del todo, pierde su
gas y su compliancia, y revienta. El gas tiene su regla (`gas_pgrad_z`,
F2.3: no carga el peso del líquido); el líquido no tenía la suya. Es
también la "corriente fantasma" de `bath_rest` (0.17 m/s, xfail).
D2.5: en el gradiente de presión del LÍQUIDO (momento y Rhie–Chow), cuando
la vecina es fluido sin líquido continuo (superficie libre), su presión
actúa EN LA CARA (continuidad de presión en la interfase): la distancia
del gradiente es hasta la cara, no hasta el centro de la vecina. Para la
columna exacta da −ρ g a máquina.

## D2.5 — gradiente del líquido con superficie libre (7-oct): mejora, no cura

`pgrad_fs` en momento y Rhie–Chow (clave `pc_fs_liquid_gradient`).
test-full: unit OK; `bath_hydrostatic` pasa a XPASS (0.6 %, antes 1.05 %);
`bath_rest` 0.175 → 0.116 m/s (sigue xfail); goldens se mueven (esperado).
Banco (% pasos): pared sola 4.9/5.7/0.0/2.0 → +D2.5 n4 3.8/5.3/0.1/2.1,
n8 2.8/4.1/0.0/1.3, +compliancia 1e-2 2.5/3.3/0.0/0.9 (p>100k/gas>200/
liq>10/centinela). Los picos siguen en la misma columna (F k=4 llena sin
gas; T encima cae a −2.0 m/s a 8 s). Pendiente: sonda de T con D2.5
(`fs_probeT`) para ver si `presion/grav` subió a ~1.
REGRESIÓN detectada en test-full: reinicio cold_10step n8→n4 difiere 10 %
en velocidad del gas (n8→n8 bit a bit; el líquido idéntico). Bisección por
claves en `scratchpad/cand/bisect_restart`.

## BUG LATENTE encontrado: `mesh_generate_parallel(m)` con `intent(out)` (7-oct)

Persiguiendo el no-determinismo (NaN a n=2; reinicio cold_10step n8→n4 con
10 % de diferencia en el gas en UNA corrida y 1e-13 en las siguientes;
`MallocPreScribble` no lo reproduce): una copia del árbol compilada a -O0
falla SIEMPRE en la inicialización de la malla (allocate con tamaños
basura), también con el árbol base `fb06a44`. Un print antes del allocate:
`rank ***, coords basura, iloc ******, np 1 0 5`. Causa: `mesh%topo` se
llena en `mpi_init_topology` y después `mesh_generate_parallel(m, cfg)`
declara `m` como `intent(out)`: el dummy queda INDEFINIDO al entrar (y
gfortran desasigna/reinicia componentes). A -O2 la topología sobrevivía
por casualidad; en condiciones distintas de pila/heap (otros trabajos en
la máquina) deja basura parcial → halos basura esporádicos. Es la familia
de B1 v10 ("basura en halos de frontera física") vista desde la raíz.
Fix: `intent(inout)`. Verificación: -O0 arranca y corre; reinicio n8→n4 y
n=2 repetidos.

## D5 — JUEZ B1 con D2.2b + D2.4 (1e-2) + D2.5 (8-oct-2026): NO cruza

v35@300 → 345 s, tres trayectorias SECUENCIALES (12/14/15 ranks), dt 2 ms,
especies off. % de pasos (p>20k / p>100k / gas>200 / liq>10 / centinela):

| ventana | D2 n12 | D2 n14 | D2 n15 | ref 2 ms (F231) |
|---|---|---|---|---|
| 300–310 | 2.3/0/0.3/11.4/0.9 | 1.4/0/0/13.1/0.8 | 1.5/0/0/12.5/0.9 | 5.3/0/0/4.9/0 |
| 310–320 | 56.9/2.7/0.1/82.2/41.8 | 37.7/0.1/0/76.7/50.2 | 53.1/3.6/0/70.9/48.6 | 17.1/0.2/0.1/45.7/22.7 |
| 320–345 | 63.2/6.3/13.9/88.4/54.1 | 82.0/6.0/7.8/95.2/66.3 | 74.6/10.3/31.7/93.8/70.3 | 78.4/25.0/15.6/85.7/46.4 |

Criterio (320–345: p>20k < 5 %, cero centinelas): NO. Mejora p>100k (25 → 6–10 %)
y, en dos de tres, el gas; pero la centinela del LÍQUIDO empeora (liq>10
88–95 % vs 86 %) y la ventana 310–320 es PEOR que la referencia en presión y
líquido. Masa exacta (clip 3.5–4.9 kg, derrame 430–450 kg).
Dónde está el líquido rápido (snapshots n12, α_l ≥ 1e-2): (i) gotas
DISPERSAS (α_l 0.01–0.03) en la celda de gas sobre el baño, a −10…−20 m/s
(sedimentación en cota U_LIQ_MAX); (ii) a 330 s, 15 celdas de BAÑO (α_l 1.0,
k=4) sobre un poro lleno, cayendo a −10.8 m/s con p = 3.4 kPa (hidrostático
de media celda: 10.3 kPa): charco de UNA celda de profundidad sobre pared,
con gas encima — la ecuación de presión no establece el hidrostático dentro
de una celda aislada (Rhie–Chow con δ centro-a-centro vs gradiente D2.5 a la
cara: inconsistentes en la superficie libre) → cae a ~2/3 g → water packing.
La ganancia del banco (8.1 → 2.5 %) NO se transfiere a B1.
Decisión pendiente del usuario: parar aquí y consolidar, o un último intento
acotado (consistencia Rhie–Chow/gradiente en la superficie libre, tipo p_rgh).

## D2.6 — consistencia Rhie–Chow / gradiente de superficie libre (9-oct-2026)

Decisión del usuario: "ve por hacer consistente el Rhie–Chow con el gradiente
de superficie libre". Antes de tocar nada, los snapshots del juez (n12, 320 y
330 s) corrigen el diagnóstico de D5:

- **La cifra "hidrostático de media celda 10.3 kPa" era un error aritmético.**
  Con Δz = 0.089 m (z(4) = 0.286, z(5) = 0.375) el hidrostático de media
  celda es ½·7500·9.81·0.0447 = 3.29 kPa, y las celdas de baño de k=4
  (α_l = 1.000, α_g = 0) están a 2.7–3.6 kPa: **exactamente hidrostáticas**
  respecto al gas de encima (fijado por la cara del gas, cuyo Rhie–Chow lleva
  `liq_weight_f` = la misma condición que D2.5). No caen por el gradiente.
- Caen (−5 a −11 m/s, el gas evanescente atado a ellas) sin fuerza neta:
  **velocidad FANTASMA**. Sus dos caras verticales están cerradas para el
  líquido (poro lleno debajo: `face_open` lo cierra; gas encima: una cara
  líquido|gas nunca fue cara de líquido del Poisson). Ninguna cara la ve,
  ningún término la frena (Ergun se desvanece con 1−α_l = 0, K = 0 con el
  gas atado), el transitorio la conserva y la convección lateral la propaga
  a vecinas que sí tienen caras abiertas. Es exactamente la situación en que
  la malla escalonada diría "velocidad de cara cerrada = 0, la celda no
  tiene velocidad propia".
- Celdas de líquido puro **suspendidas sobre gas** (k=7 sobre gas en k=5–6,
  (7,26,5) y (7,7,5)) congeladas por D2.2b (todas sus caras de líquido
  cerradas porque el líquido continuo solo cruza caras líquido|líquido). El
  líquido continuo no podía subir por la superficie libre (solo por derrame,
  `vol_unlinked`, Spearman 0.93 en D1) ni volver a caer.
- Los máximos de |p| (20–54 kPa) están en el LECHO (k=2–3, poros sellados con
  p idéntica por pares: Neumann), no en el baño; |u_g| máx 120–146 m/s en el
  gas inmediatamente sobre el baño.

Tres piezas, cada una con clave (`docs/CONFIGURATION.md`):

1. **`pc_consistent_corrector`**: `correct_velocities` usa el MISMO operador de
   gradiente que el predictor (`pgrad_fs` con paredes unilaterales de Bug
   16/D2.2b, distancia a la cara en la superficie libre; el gas, media de las
   caras existentes en z como `gas_pgrad_z`). El estencil central crudo
   `(pp_N − pp_B)/(z_N − z_B)` no contiene `pp_P` (la celda de superficie no
   sentía su propio pp) y metía `pp = 0` de las paredes.
2. **`pc_fs_liquid_face`**: la cara líquido continuo | fluido sin líquido
   continuo es cara de líquido del Poisson, UNILATERAL desde la celda de
   líquido: `u_f = u_L + d_L [g_L − (p_N − p_L)/(±δ_cara)]` (con el gradiente
   unilateral de D2.5 el corchete es cero: la velocidad de la celda es la de
   su superficie), `a = α_L d_L A/δ_cara`, `Q = α_L u_f A`, solo donante
   (líquido→gas), cara superior solo con la celda LLENA (`fs_full`), hueco de
   la receptora y limitador como cualquier cara. Simétrica: el lado del gas
   (`fs_gas_side`) suma el mismo coeficiente a su fila. El flujo se exporta al
   transporte de α con la α_f que usó el Poisson (`ws_Fc_af_*`; con la media
   ½(α_L + 0) el caudal se doblaba).
3. **`pc_liq_closed_dir`** (regla cinemática): componente del líquido continuo
   nula en la dirección sin ninguna cara de líquido abierta en el último
   Poisson del paso (`lcoef_r/th/z`, `ws_liq_f*`), tanto antes del Poisson
   (mod_multiphase) como en el corrector. Generaliza D2.2b por dirección.

`make test-unit` OK; `make test-quick`: invariantes OK, golden se mueve
(cold_10step: velocity_z_gas.min, corrector del gas con paredes unilaterales).

## Bug 22 — halos FÍSICOS de `liq%alpha` con basura del heap (9-oct-2026)

Detectado al pasar `make test-full` con D2.6: reinicio `cold_10step` n8→n8 NO
bit a bit (S_rad 3e-4), `bath_test` n1 vs n4 fuera de tolerancia (8e-3 …
0.46 entre repeticiones) y simetría 120° intermitente. Bisección por claves
sin patrón reproducible; dos corridas idénticas en SERIE (n=1) del caso frío
diferían un 10 % en la velocidad del gas unas veces y eran idénticas otras
(dependía de qué más corría en la máquina). Con `MallocPreScribble=1` tres
corridas son idénticas entre sí y distintas de la normal ⇒ lectura de heap
sin inicializar. Para localizarla: una `dylib` que interpone `malloc` y
rellena cada bloque con NaN SEÑALIZANTE (`0x7FF4000000000001`), más la
compilación `-O0 -ffpe-trap=invalid` (`scripts/diag/snanfill.c`,
README en `scripts/diag`): la primera aritmética sobre basura aborta con traza.
Resultado: en la SEGUNDA `liquid_continuity_mask` del paso, `liq%alpha` tiene
3584 halos con el patrón: toda la corona de halos físicos (eje, pared, piso,
techo y esquinas).

Causa: `solve_volume_fraction` hace `allocate(a_new, mold=liq%alpha)`,
escribe solo las celdas propias y luego `liq%alpha = a_new`; el intercambio
MPI y la periodicidad en θ reparan los otros halos, los físicos no los
escribe nadie. Está en HEAD desde Plan C F1 (`liq%alpha = a_new`). Qué
lee esos halos: todo lo elemental de array completo (`liq_continuous`,
`ws_liq_room`, `ws_liq_cont`) y, con D2.5/D2.6, las máscaras de superficie
libre y las caras unilaterales. Con páginas frescas del SO (ceros) el efecto
es nulo; con páginas recicladas (otros procesos en la máquina → otra
estrategia del asignador) entra basura O(1) por caminos de peso pequeño: 1e-10
en el paso 1, 10 % a los 10 pasos. Es la familia de B1 v10 y del
`intent(out)` de la malla.

Fix: `a_new = liq%alpha` tras el `allocate` (los halos conservan el valor
válido). Verificación: bajo el `malloc` de sNaN la corrida fría completa sin
trampa alguna (55 pasadas de máscara limpias).

### D2.6 en el banco (antes del fix de Bug 22; n4, % pasos p>20k / p>100k / gas>200 / liq>10 / centinela)

| variante | p>20k | p>100k | gas>200 | liq>10 | cent. |
|---|---|---|---|---|---|
| D2.5+comp (ref) | 42.4 | 2.5 | 3.3 | 0.0 | 0.9 |
| D2.6 completo | 41.8 | 1.1 | 3.8 | 0.0 | 0.5 |
| sin corrector consistente | 41.7 | 1.1 | 4.2 | 0.0 | 1.0 |
| sin regla cinemática | 42.4 | 2.4 | 2.6 | 0.0 | 0.2 |

La regla cinemática es la que baja los picos (>100 kPa 2.5 → 1.1 %); el
corrector consistente apenas cambia el banco; `vol_unlinked`/`vol_lim`
medianos bajan a la mitad. El p>20 kPa del banco (42 %) es el poro del
lecho inundado (k=1–3) y no lo toca ninguna pieza de superficie libre.
Primera versión del corrector corregía `u_r` en la celda del eje con el
`aP = 1` de relleno (d = αV/1): 20 m/s un paso sí y otro no desde 8.2 s; se
restauró el salto de las fronteras físicas como en el predictor.
Sin la ablación `noface` (la cadena murió con SIGKILL al relanzar y luego el
script de reintento esperaba una cadena mal escrita). Todos estos números
se repiten con el binario corregido (`d26f_n4`, `d26f_ref_n4`) antes del
juez B1 (`judge_d26_n12/14/15`, secuencial, ~3 h cada uno).

Con el binario corregido (Bug 22), banco n4: referencia D2.5+comp
`d26f_ref_n4` vs D2.6 completo `d26f_n4` → ver tabla siguiente (misma
tendencia: los picos >100 kPa y la centinela bajan, el nivel del poro no).

| corrida (binario corregido) | p>20k | p>100k | gas>200 | liq>10 | cent. |
|---|---|---|---|---|---|
| d26f_ref_n4 | 42.4 | 2.5 | 3.3 | 0.0 | 0.9 |
| d26f_n4 | 41.7 | 0.9 | 2.5 | 0.0 | 0.3 |

## D6 — JUEZ B1 con D2.6 (9-oct-2026, binario con Bug 22 corregido): NO cruza

v35@300 → 345 s, 12 ranks, dt 2 ms, especies off, claves D2.2b+D2.4+D2.5 +
`pc_fs_liquid_face`/`pc_consistent_corrector`/`pc_liq_closed_dir`. Duró 6 h 14 min
(no las ~3 h estimadas). % de pasos (p>20k / p>100k / gas>200 / liq>10 / centinela):

| ventana | D2.6 n12 | D2 n12 | ref 2 ms (F231) |
|---|---|---|---|
| 300–310 | 2.2/0/0/0/0 | 2.3/0/0.3/11.4/0.9 | 5.3/0/0/4.9/0 |
| 310–320 | 75.4/30.0/0.1/78.9/28.5 | 56.9/2.7/0.1/82.2/41.8 | 17.1/0.2/0.1/45.7/22.7 |
| 320–345 | 65.7/18.9/26.8/95.2/64.3 | 63.2/6.3/13.9/88.4/54.1 | 78.4/25.0/15.6/85.7/46.4 |

Criterio (320–345: p>20k < 5 %, cero centinelas): NO, y PEOR que D2 en todo
menos la ventana 300–310 (que es la más limpia de todas las variantes: ni un
paso con líquido > 10 m/s). Lo que el banco ganaba (p>100k 2.5 → 0.9 %) se
invierte en el horno: p>100k sube a 30 % en 310–320 (D2: 2.7 %) y a 19 % en
320–345; la centinela del gas se dispara el 78 % de los pasos en 330–335.
Lectura: la cara de superficie libre unilateral mete en el Poisson la caída
del charco de una celda — justo lo que faltaba en D5 — pero en el lecho
inundado esa cara es la ÚNICA salida blanda de un poro empacado y ahora
transmite la presión del poro al gas de encima (p>100k) en vez de dejar al
líquido caer con velocidad fantasma. Es el mismo mecanismo de water packing
con la válvula movida de sitio, no quitada.
La cadena se detuvo tras n12 (n14 llevaba 2 min): con una trayectoria en
65.7 % ninguna media de tres baja de 5 %, y 12 h más de máquina no cambian
la decisión. `scripts/b1_regime_table.py` lleva sólo la fila (a).
Conclusión de Plan D: D2.2b, D2.4, D2.5 y D2.6 son mejoras locales del banco
`bed_flood` que NO se transfieren a B1; el párrafo del paper (§b1limit) y
el trabajo futuro (acople α–p implícito tipo NEPTUNE) quedan como estaban,
con las dos filas nuevas en la tabla. Código en el árbol de trabajo
(sin commit): claves default `.true.`; decisión del usuario si se consolida
con default `.false.` (banco documentado) o se descarta.
