# Plan F — El gas es siempre fluido del acople: bolsa atrapada = resorte (12-oct-2026)

Último intento sobre el régimen de lecho inundado de B1 (decisión del usuario,
12-oct: "arreglar de raíz; si no funciona, cerrar el proyecto"). Sustituye los
interruptores de actividad del gas por un acople continuo y se juzga en B1 con
el juez estadístico, nunca en el banco.

## 1. Diagnóstico medido en B1 (no en el banco)

Serie densa de la base desde el snapshot de 325 s (`scratchpad/cand/
base_dense325`, 41 snapshots cada 40 ms hasta 326.6 s, 12 ranks) y de
E1+E1b+D2.4 desde 315 s (`e1b_dense315`, sonda `[PROBE-pmax]` por paso):

- **Las ráfagas de presión de la base viven en el PISO del horno, no en el
  baño.** 428 celdas-snapshot con |p| > 100 kPa: 175 en k = 1, 237 en k = 2,
  13 en k = 3, 3 en k = 4. Por tipo: 230 en lecho denso (α_s ≥ 0.85), 50 en
  bolsas de gas (α_s ≈ 0.64, α_g ≈ 0.36, sin líquido), 3 en baño.
- **Anatomía de una bolsa** (celda (6,30,1), k = 1): α_s 0.635, α_g 0.365,
  α_l 0, T_gas 450–585 K (fría: no es el poro calentándose de F2.13). Encima,
  (6,30,2): α_s 0.90, α_g 0.07 → 0.015 y α_l 0.03 → 0.08 en 0.8 s (le entra
  líquido del poro saturado de arriba, (6,30,3): α_l 0.149 = cap, α_g 0.015
  = piso). La presión de (6,30,1) y (6,30,2) es IDÉNTICA en cada snapshot y
  salta 5 → 42 → 6 → 113 → 6 → 229 → 234 → 331 → 302 → 207 → 24 → 6 kPa:
  ráfagas de uno o dos snapshots, con el gas de la bolsa a 24–115 m/s
  durante la ráfaga y 1–3 m/s fuera de ella.
- **Succión simétrica**: las bolsas (1–3, 11–13, 1) bajan a −275 … −535 kPa
  mientras su α_l crece 0.01 → 0.04 (el poro de encima les drena líquido);
  en E1b la primera celda de |p| máximo es (2,4,1), otra bolsa (α_g 0.365),
  a −50 kPa con p = 0 en su vecina radial (celda sin fluido).
- Los 164 celdas-snapshot con gas > 200 m/s están en k = 5 (153) sobre el
  baño bajo el arco, con gotas a −19 … −36 m/s: es el chorro del arco con
  niebla, no el piso. Queda fuera de este plan (métrica: presión).

Lectura: la bolsa de gas atrapada bajo el lecho inundado está FUERA del
acople (F2.16: no percola hasta el freeboard → `act_g = .false.` → pared
Neumann, `pp = 0`). El líquido que el poro saturado le vierte (o le drena)
cambia el volumen de la fila vecina y la única compresibilidad que queda es
la acústica del líquido (`α_l V/(ρ c² Δt)`, c = 4000 m/s): ±MPa por
cualquier desbalance. Físicamente una bolsa atrapada es un RESORTE
(`p V^γ`): se comprime al recibir líquido y se descomprime al drenarlo, y
su presión es tan de fluido como la del freeboard. Hilfer (1998) dice que
la subfase desconectada no PROPAGA gradientes, no que carezca de presión:
F2.13/F2.16/F2.31 confundieron inmovilidad con rigidez. Es la raíz común de
todo lo que se ha visto desde F2.13: el gas de poro "válvula ficticia"
(E1), el water packing al cerrarla (E1b), los MPa de B1 v30/v33.

## 2. Diseño (`pc_gas_spring`, una sola clave)

Con la clave activa:

1. **Actividad del gas continua**: `act_g = (cell_type ≠ 0) ∧ (α_g > 0 ∨ act_l)`.
   Sin umbral hidrodinámico en la actividad (los coeficientes `α_f d_f A/δ` y
   la compresibilidad `α_g V/(P0 Δt)` ya escalan con α), sin percolación
   (F2.16), sin criterio de venteo (F2.31), sin E1b. El canal residual F2.21
   (gas donde aún no lo hay pero puede llegar) se generaliza a toda celda con
   líquido continuo: el gas de una bolsa puede burbujear hacia el baño
   desplazando líquido hacia abajo (contracorriente de un lecho de goteo).
2. **Caras líquido|líquido siempre abiertas** (E1): el poro saturado es un
   medio poroso incompresible transmisivo, `div(α_l u_l) = 0`.
3. **Sin piso de gas de poro** en la capacidad del líquido (`liq_cap` = hueco
   físico `1 − α_s − α_sl`): el piso F2.7 existía para que "la celda nunca
   quedara sellada"; con 1 y 2 ninguna fila con fluido se sella, y el piso
   era la válvula ficticia (el limitador rechaza líquido mientras `α_g = 1 − Σ`
   repone el gas que el Poisson sacó).
4. Lo que NO cambia: limitador de hueco y derrame (guardas conservativas,
   auditadas), fase evanescente F2.20 (velocidad atada, `aP` físico), Ergun
   del gas, morfología F2.22, compresibilidad acotada (`COMP_SRC_CAP`),
   compliancia residual opcional (`alpha_g_comp_min`, se evalúa aparte).

Bit a bit con la clave apagada (goldens v37 intactos).

## 3. Gates

- G0: `make test-quick` con default (bit-idéntico).
- G1: banco `f_n4` (= `e_base_n4` + clave, 12 s, n4): sin centinela, p_max
  comparable al mejor de D+E. Solo filtra blow-ups: el banco NO predice B1.
- G2: screening B1 `judge_f_n12` (300 → 325 s, 12 ranks, ~2.4 h) con
  `regime2.py`: p > 100 kPa, gas > 200, centinela p/gas en 320–325 s frente a
  base 4.2 / 1.8 / 0.7 y E1 27.6 / 6.3 / 0.8; exceso hidrostático en
  snapshots (`pexcess.py`). Hay que mirar también el nivel: la bolsa como
  resorte tiene que dar p ≈ hidrostática + compresión, no ±MPa.
- G3: juez de tres trayectorias (n12/14/15, hasta 345 s) si G2 es acotado.
- G4: consolidar (default, golden vN, paper §b1limit, CLAUDE.md, memoria) o
  cerrar el proyecto. Sin término medio.

## 4. Riesgos

- Celdas de baño puro con caras de gas hacia todas sus vecinas con gas: es lo
  que F2.17–F2.19 rompieron y F2.20/F2.21 arreglaron (velocidad atada,
  canal geométrico). Ahora el canal es global. Gate: `bath_test` /
  `bath_fill` / `bath_freeze` en test-full.
- Presión rancia en celdas que pasan de pared a fluido al reiniciar: su `p`
  es la media Neumann que tenían (no un valor congelado de MPa). Vigilar en
  el primer medio segundo del screening.
- La bolsa que se calienta (F2.13) ahora empuja líquido hacia arriba por las
  caras abiertas (Darcy): volumen pequeño, presión acotada. Si no, se verá
  como p lineal en el tiempo en el piso.
