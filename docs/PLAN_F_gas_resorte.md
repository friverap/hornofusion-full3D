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

## 5. Veredicto G2: NEGATIVO (12-oct-2026, `judge_f_n12`, 300 → 325 s, 12 ranks)

| corrida (320–325 s) | p > 100 kPa | gas > 200 | centinela p/gas | p_max |
|---|---|---|---|---|
| base vieja `judge_largo_F231` (binario 4-oct) | 4.2 | 1.8 | 0.7 | 331 kPa |
| E1 `judge_e1_n12` | 27.6 | 6.3 | 0.8 | 317 kPa |
| **F `judge_f_n12`** (resorte + `alpha_g_comp_min` 0.01) | **100.0** | **100.0** | **46.5** | **1.85 MPa** |

Evolución de F por ventanas de 5 s (p > 100 kPa / gas > 200): 300–305
21.9 / 50.8; desde 305 s **100 / 100** en todas. Mediana de `p_max` del
audit: 54 kPa (300 s) → 105 (304) → 200 (316) → 240 kPa (325), lineal.
Exceso sobre la hidrostática saturada (`pexcess.py`): +96 kPa (310 s),
+187 kPa (320 s), +936 kPa (325 s), siempre en el lecho. Sin NaN ni avisos.

**Mecanismo medido en los snapshots (`scripts/diag/burst_scan.py` +
clasificación por tipo de celda):**

1. **Rampa lineal en celdas de poro SECO.** El 89–100 % de las celdas con
   |p| > 100 kPa de cada snapshot (1/1, 5/5, 34/35, 44/47, 89/113) tienen
   α_g = 0.015 exacto (`ALPHA_PORE_GAS`), α_s = 0.985, sin líquido, u_g = 0,
   k = 2–3, bajo los tres electrodos (j ≈ 1–3, 19, 36, 55–57). Su presión sube
   5–7 kPa/s desde 302 s: (8,56,2) 0 → 65 → 79 → 185 → 203 → 238 kPa entre 300
   y 325 s con T_g 1213 → 1240 K (no es calentamiento isocórico: 27 K darían
   2 kPa). La vecina de arriba pierde su gas (α_g 0.015 → 0.010 → 0.000,
   α_s → 1.000). Son EXACTAMENTE las celdas que F2.13 saca del acople
   (`pore_gas_only`, B1 v30: "111 kPa lineales en el fondo bajo los arcos")
   y que `pc_gas_spring` mete (`act_g = α_g > 0`): sin conductancia hacia
   ninguna vecina (todas sin gas) su fila solo tiene la diagonal acústica y
   cualquier defecto de volumen se integra en presión.
2. **Gas > 200 m/s el 100 % de los pasos desde 303 s, en el BAÑO.** Las celdas
   rápidas son de baño (α_l ≈ 0.9, α_g 0.08–0.10) sobre el lecho y con
   freeboard encima (2/2, 9/11, 13/13, 15/20; 0 en el lecho): el gas dentro
   del baño es ahora fluido del acople y sale a 206–243 m/s por la
   superficie. Es el "resorte solo oscila" del banco; la compliancia 0.01 lo
   amortiguó en 4 celdas y no en B1.
3. **Ráfaga final 324–325 s (1.85 MPa).** Snapshot 325 s: (5,60,3) 959 kPa con
   α_l 0.17, α_g 0, α_s 0.83, Σα = 1.015, líquido puro encima y sólido 1.0
   debajo: celda del lecho que se satura sin gas ni margen, el golpe de
   ariete de E1b.

**Conclusión.** La bolsa como resorte es correcta para las bolsas con gas
real, pero "todo el gas es fluido del acople" revive de golpe los tres fallos
que motivaron F2.13 (poro seco), F2.16/F2.31 (gas sin camino) y el venteo
del gas del baño. Cada una de esas capas existe por un fallo medido y
quitarlas juntas los vuelve a exponer todos. No se probó una variante
reducida (resorte solo en bolsas con α_g ≥ `ALPHA_FLOW_CUTOFF` y F2.13
vigente para el poro seco); queda anotada, no ejecutada. Por decisión del
usuario (último esfuerzo), el Plan F se cierra NEGATIVO. `pc_gas_spring`
y `pc_keep_pore_floor` quedan con default `false` y ningún config las activa.

La referencia nueva con el binario actual (`judge_base_n12`) se termina de
correr solo para dejar documentado el nivel real de la base (los jueces de
Plan D/E se compararon contra bases contaminadas por Bug 22).

## 6. Referencia limpia `judge_base_n12` (binario actual, sin claves, 300 → 325 s)

| ventana | p > 100 kPa | gas > 200 | centinela p/gas | l ≥ 20 | p_max | g_max |
|---|---|---|---|---|---|---|
| 300–305 | 0.0 | 0.0 | 0.0 | 0.0 | 34 kPa | 145 |
| 305–310 | 0.0 | 0.0 | 0.0 | 0.7 | 50 kPa | 162 |
| 310–315 | 0.0 | 0.0 | 0.0 | 17.6 | 99 kPa | 191 |
| 315–320 | 2.4 | 0.1 | 0.0 | 0.0 | 165 kPa | 210 |
| 320–325 | 92.4 | 92.3 | 91.1 | 90.0 | 2.00 MPa | 300 |

Por segundo: 318–319 s una ráfaga (12 % de pasos > 100 kPa, 165 kPa), 319–320
limpio, y a **320.49 s** `P_HYDRO_CAP` (2 MPa) por primera vez; desde 321 s
en la cota el 99–100 % de los pasos. Snapshot 325 s: (5,10,3) −2 MPa con
α_l 0.22, α_g 0, α_s 0.78, Σα = 1.015, líquido puro encima a −20 m/s
(`U_LIQ_MAX`) y poro con 9 % de gas debajo a +240 kPa: la celda del lecho
que se satura sin gas es la misma anatomía que la ráfaga final de F.
Exceso hidrostático: +1.3 / +6.9 kPa a 310 / 320 s; ±1–2 MPa a 325 s.
Sin NaN ni avisos. `make test-quick` OK tras la cadena.

**Lectura.** Con el binario actual la base es LIMPIA hasta 318 s (la vieja
tenía 0.4 % en 315–320 y 4.2 % en 320–325) y colapsa de golpe a 320.5 s,
MÁS fuerte que la vieja (92 % en la cota frente a 4.2 % sobre 100 kPa). La
contaminación por Bug 22 cambiaba el ruido de 300–320 s, no el muro de
~320 s: el colapso del lecho inundado es un fallo del modelo con el binario
limpio. Plan F frente a la referencia limpia: 100 / 100 % en 305–320 s
contra 0 / 0 %; en 320–325 s ambos en centinela. El veredicto NEGATIVO de
§5 se mantiene y se refuerza. Los jueces de Plan D/E no se repiten: contra
una base con el 92 % de pasos en la cota en 320–325 s ningún candidato de
D/E (63–100 % sobre 100 kPa) cambiaría de veredicto.
