# Plan E — acople α–p implícito / lecho saturado: bitácora

Plan: `docs/PLAN_E_acople_implicito_lecho_saturado.md`. Antecedente: Plan D
(`2026-10-07_plan_d_acople_implicito.md`), cerrado negativo el 10-oct.

## Banco `bed_flood` variante D (12 s, n4, dt 2 ms; % de pasos)

Columnas: p>20k / p>100k / gas>200 / liq>10 / centinela | p_max | medianas
`vol_lim`, `vol_unlinked` [m³]. Binario `d293b92` + claves de Plan E.
**El p>20k del banco NO es patología desde ~6 s**: el baño crece 2 t/s y a
10 s la carga hidrostática del lecho es ~50 kPa uniformes con u ≈ 0 (snapshot
`extremes.py`); la métrica útil del banco es el EXCESO sobre la hidrostática
de la columna (`pexcess.py`) y los picos > 100 kPa.

| variante | p>20k | p>100k | g>200 | l>10 | cent. | p_max | vol_lim | vol_unl |
|---|---|---|---|---|---|---|---|---|
| base (defaults d293b92) | 42.3 | 8.1 | 12.5 | 9.4 | 4.7 | 1.0 MPa | 2.2e-3 | 2.4e-3 |
| **E1** `pc_sat_open` | 53.9 | **1.4** | **3.1** | **0.0** | **0.8** | 291 kPa | 2.3e-3 | 5.9e-5 |
| E1 + E2 (goteo + derrame como fuente) | 52.6 | 5.7 | 5.5 | 0.0 | 2.8 | 2.0 MPa (cap) | 2.3e-3 (máx 0.66) | 5.3e-5 |
| E2 solo (con derrame) | 33.4* | 5.2* | 11.5* | 8.2* | 2.9* | 702 kPa | 1.9e-3 | 2.2e-3 |
| E1 + E2 solo caras no enlazadas (`e12ns_n4`) | 53.9 | 1.5 | 3.4 | 0.0 | 0.7 | 284 kPa | 2.3e-3 | 5.8e-5 |
| E1 + E2 (con derrame) + lazo `n_pc_max = 3` | 52.6 | 5.5 | 5.7 | 0.0 | 2.7 | 2.0 MPa (cap) | 2.3e-3 (máx 0.63) | 6.7e-5 |

(* a 10.4 s)

Exceso sobre la hidrostática de columna [kPa] (max / min, snapshots):

| t | base activas | base lecho | E1 activas | E1 lecho |
|---|---|---|---|---|
| 6 s | +2 / −22 | +2 / −22 | +5 / −19 | +5 / −19 |
| 8 s | +260 / −27 | +16 / −27 | +41 / −15 | +37 / −15 |
| 10 s | +23 / −34 | +1 / −34 | +20 / −12 | +20 / −12 |
| 12 s | +23 / −34 | +22 / −34 | +16 / −7 | +16 / −7 |

### E1 — poro saturado = celda incompresible transmisiva (10-oct)

`face_open` ya no cierra las caras líquido|líquido hacia una celda del lecho
con el poro lleno (cierre F2.8, v22/sep-2026). La celda saturada queda con
sus caras abiertas y su fila sin almacenamiento: div(α_l u_l) = 0. La
presión se propaga por el lecho inundado y el baño de encima deja de caer
contra un piso Neumann (D2.2). Es la pieza con más efecto de todo Plan D+E
en el banco: el líquido no toca nunca 10 m/s, los picos > 100 kPa bajan 6×,
la centinela 6×, y `vol_unlinked` (flujo por caras que el Poisson no enlaza)
cae 40× porque ahora enlaza las caras del lecho. Test unitario
`test_poisson_bath` caso 5 (hidrostática a través de un lecho saturado,
1e-9) — en reposo F2.8 no actúa, así que el caso guarda la continuación
hidrostática, no discrimina la clave.

### E2 — goteo no enlazado como fuente del Poisson (10-oct): con derrame, PEOR

`ws_pc_unl` = volumen neto entrado por caras no enlazadas (y derrame) en el
último transporte del paso, `Su += ws_pc_unl`. Con el derrame incluido la
fuente realimenta al revés: la celda dadora (llena) "perdió" volumen y la
presión le mete más, el limitador lo bloquea (`vol_lim` máx 0.66 m³) y p
satura en `P_HYDRO_CAP`. El derrame es la corrección del limitador, no un
flujo físico que la presión deba compensar → clave aparte
`pc_spill_source` (false). Variante solo caras (`e12ns_n4`): igual que E1
(1.5/3.4/0.0/0.7): con E1 el flujo no enlazado ya es 40× menor y la fuente
no tiene sobre qué actuar → `pc_drift_source` default false (bit-idéntico a E1).

Lazo interno (`n_pc_max`, `tol_alpha_pc`; `n_pc_max = 1` bit-idéntico):
implementado en `multiphase_iteration`; `e12b_n4` (binario con lazo, 1 pasada) reproduce `e12_n4` columna a columna. Con 3 pasadas (`e12pc3_n4`, +60 % de tiempo de paso) el resultado es el de E1+E2: el lazo converge (`dalpha` mediana 6.5e-7 vs 1.8e-6) pero no cura la realimentación del derrame; se juzga de nuevo sin derrame.

### E1 en tres descomposiciones (n2 / n4 / n8; % de pasos, 12 s)

| | p>100k | gas>200 | liq>10 | centinela | p_max |
|---|---|---|---|---|---|
| base | 8.0 / 8.1 / 7.8 | 9.8 / 12.5 / 11.7 | 7.6 / 9.4 / 8.6 | 4.7 / 4.7 / 4.4 | 0.8 / 1.0 / 0.8 MPa |
| E1 | 1.4 / 1.4 / 1.4 | 3.2 / 3.1 / 3.3 | 0 / 0 / 0 | 0.6 / 0.8 / 0.7 | 329 / 291 / 284 kPa |

Mejora consistente en las tres trayectorias. Siguiente: `test-full` con
`pc_sat_open` default true, rebaseline v36, juez B1 (`judge_e1_n12/14/15`).

### test-full con E1 default (10-oct, 14:13–14:30)

Todos los gates pasan (unit, invariantes, reinicio bit a bit, n1 vs n4,
simetría, xfails sin cambio); solo mueve el golden en los tres casos con
poros saturados (`bath_fill`, `bath_freeze`, `bed_flood`) → rebaseline v36.
`bath_fill`: p_max 83 → 80 kPa. `bath_freeze`: p_max 122 → 92 kPa pero
u_gas_max 29 → 137 m/s (la re-solidificación crea lecho saturado al instante
y ahora es transmisivo; dentro del criterio, anotado para el juez).
`bed_flood` (3 s, config de test): `bath_pv_bounded` sigue xfail
(p_max 130 → 125 kPa, gas en cota).

## Juez B1 de E1 (10-oct, 14:20–16:20): NEGATIVO

`judge_e1_n12` (v35@300 s → 345 s, dt 2 ms, 12 ranks, `pc_sat_open = true`
sobre `9ade636`). Detenida a 321.8 s: la ventana 320–345 ya no podía bajar
del 5 % y la máquina hacía falta para diagnosticar. Ventanas de 5 s (% de
pasos; `judge_largo_F231` = base, `judge_d2_n12` = Plan D):

| ventana | base p>20k / l>10 / cent | D2 p>20k / l>10 / cent | **E1** p>20k / l>10 / cent | E1 p_max |
|---|---|---|---|---|
| 300–305 | 7.5 / 0.2 / 0.0 | 0.1 / 13.6 / 1.6 | 35.0 / 0.0 / 0.1 | 825 kPa |
| 305–310 | 3.1 / 9.6 / 0.0 | 4.6 / 9.2 / 0.1 | 25.3 / 0.0 / 0.0 | 166 kPa |
| 310–315 | 1.9 / 34.6 / 11.7 | 37.2 / 65.0 / 40.7 | 61.1 / 7.9 / 4.4 | 104 kPa |
| 315–320 | 32.3 / 56.9 / 33.8 | 76.5 / 99.4 / 42.9 | 67.2 / 39.1 / 0.5 | 198 kPa |
| 320–325 (884 pasos) | 61.6 / 57.2 / 7.2 | 71.5 / 99.2 / 94.7 | **100 / 100 / 66.4** | 291 kPa |

**Corrección de métrica (10-oct, tarde)**: la columna `cent` de arriba (y la
de `scripts/b1_regime_table.py` hasta hoy) contaba `u_liq_max ≥ 20`, pero
`mod_audit` toma `u_liq_max` de toda celda con α_l ≥ 1e-2 — incluido el
líquido DISPERSO, que lleva la velocidad terminal de gota (hasta
`U_SETTLE_MAX` ≈ 50 m/s) y al que `U_LIQ_MAX` no se aplica. Eso no es una
centinela. Con centinelas de p y gas solamente (`regime2.py`): 320–325 s
(1123 pasos) E1 p>100k **27.6 %** (base 4.2), gas>200 6.3 (1.8), centinela
p/gas 0.8 (0.7), l≥20 62.5 (6.5: gotas). En 310–320 s NINGUNA variante tiene
centinelas de p/gas (todas 0.0–0.1 %) y E1 no se distingue de la base
(p>100k 0.0/0.2 %, gas>200 7.0/0.4 %). El veredicto negativo se sostiene
por p>100k en 320–325 s; el "66 % de centinela" y el "100 % > 20 kPa"
eran gotas e hidrostática.

Lectura honesta:

- **Lo que E1 sí hace en B1**: nada medible en 300–320 s con la métrica
  corregida (ver arriba); el baño deja de caer contra el piso Neumann, pero
  eso no cambia el régimen.
- **Lo que no hace**: el nivel de presión del lecho sube desde el primer
  segundo (p>20k 35 % en 300–305 frente a 7.5 %) y en 320–325 s los picos
  > 100 kPa son 7× los de la base (27.6 % frente a 4.2 % de pasos).
- **Transitorio de reinicio**: el snapshot v35 trae las celdas saturadas
  SELLADAS (F2.29, p = media de vecinas); al abrirlas E1 en el primer paso,
  p_max 825 kPa, gas 300 m/s, que decae a 20 kPa en 40 ms (~20 pasos). Es
  un artefacto del juez (no existe trayectoria E1 desde t = 0), pero no
  explica el régimen de 305–320 s.
- **Snapshots** (`pexcess.py`, exceso sobre la hidrostática de columna,
  p_hyd máx 10–11 kPa porque el baño es de 3.3 t): 310 s E1 +7/−8 kPa
  (base 300 s +5/−10; D2 310 s +2/−11) — en los instantes de snapshot el
  campo E1 es tan tranquilo o más; 320 s E1 **+44 kPa** en el lecho
  (D2 +21). La celda (k,j,i) = (3,60,8): lecho α_s 0.835, α_l 0.150,
  α_g 0.015 (gas residual de poro, pared por F2.13) → hueco 0.015, con
  p = 50.8 kPa; debajo (k = 2) lecho seco α_s 0.985 con la misma p
  (Neumann); encima (k = 4) baño α_l = 1 a 10.9 kPa con u_l = (−1.32,
  +0.61, −0.33) m/s: 40 kPa de salto en una celda, el baño empujando hacia
  abajo 0.33 m/s contra un poro casi lleno sin salida (horizontal: lecho
  con d_f ~ 1e-7). Es el riesgo "bolsa" de PLAN_E §5: la fila incompresible
  con caras abiertas cobra en presión toda la entrada que el limitador va a
  rechazar — F2.8 cerraba esa cara (y el baño caía), E1 la abre (y el baño
  se estrella). Son las dos caras del mismo desfase: la presión no sabe lo
  que el limitador hará.
- Limitador: `[LIM]` it_max 12–18 en 305–313 s; **61–62 a 320.75–321.5 s**
  (base: nunca > 20 en la ventana).

Decisión: `pc_sat_open` vuelve a default `false` (lo activa solo
`bed_flood.dat`, como las claves de Plan D); golden v37 (bath_fill y
bath_freeze vuelven a sus valores v35; bed_flood no cambia). Diagnóstico
con sonda desde `judge_e1_n12/eaf3d_00160000.h5` (320 s), celda (8,60,3),
pasos 160001–160120: `scratchpad/cand/e1_diag320/`.

### Sonda a 320 s (E1, `e1_diag320`): la válvula ficticia del gas de piso

Reinicio desde `judge_e1_n12/eaf3d_00160000.h5` (320 s), 2 s, sonda en
(8,60,3), pasos 160001–160120 (`[PROBE-P]`/`[PROBE-MOM]`, `probe_p.py`):

- La fila de presión de la celda está TRANQUILA: pp −15…−140 Pa por outer,
  p baja de 50.8 a 27.5 kPa en 0.24 s. Pero `Su_liq = +7.5e-4 m³/s`
  (entrada de líquido predicha, ½ volumen de celda por segundo) compensada
  por `Su_gas = −7.2e-4 m³/s`: el gas de piso (α_g = 0.015 =
  `ALPHA_PORE_GAS`, `act_g = T` porque el piso está por ENCIMA de
  `ALPHA_FLOW_CUTOFF` — así se diseñó en F2.7 para que "la celda nunca
  quede sellada hidráulicamente") sale a 2.4 m/s hacia arriba por el baño
  (canal residual F2.21). α_l = 0.150 y α_g = 0.015 NO cambian en 120 pasos:
  el limitador rechaza el líquido (`vol_lim`), `α_g = 1 − Σ` repone el gas.
  Es una válvula ficticia de caudal permanente; el baño de encima (k = 4)
  lleva u_z = −0.33 m/s "hacia dentro" del poro cada paso y lo rechazado lo
  mueve el derrame. Momento del líquido en el poro: `presion` +67 contra
  Ergun·u 73 (u_z = +3.5 cm/s, flujo de Darcy hacia arriba).
- A 320.5 s el campo vuelve a estar tranquilo (|p| máx 23 kPa, gas 97 m/s);
  los picos del audit son ráfagas de pocos pasos.
- `u_liq_max` del audit incluye el líquido DISPERSO (gotas a velocidad
  terminal, hasta `U_SETTLE_MAX` ≈ 50 m/s en gas a 2000 K, físico); la cota
  `U_LIQ_MAX` sólo capa líquido continuo. "l>10" y la centinela de líquido
  del juez pueden ser gotas, no blow-up: el veredicto va por p y gas.

### E1b — gas residual del poro saturado FUERA del acople (`pc_sat_gas_off`)

`act_g = .false.` donde `ws_liq_room ≤ 1e-4` (sólo el lecho: fuera de él
`ws_liq_room = 1`). Banco n4 (`e1b_n4`), con E1:

| | p>20k | p>100k | g>200 | l>10 | cent. | p_max | vol_lim med |
|---|---|---|---|---|---|---|---|
| E1 | 53.9 | 1.4 | 3.1 | 0.0 | 0.8 | 291 kPa | 2.3e-3 |
| E1+E1b | 100 | 7.6 | 17.9 | 2.5 | 6.5 | 1.25 MPa | **1.6e-4** |

- **`vol_lim` cae 14×** (la entrada ficticia ya no se pide) y el lecho
  saturado queda en HIDROSTÁTICA CORRECTA: sonda (7,20,1) a 8 s,
  `presion` +399 vs `grav` −389 → ∇p = 75.8 kPa/m ≈ ρ_l g (73.6). Columna
  (7,20): p = 66.0 / 48.6 / 32.7 / 4.0 kPa (k = 1..4) = ρ_l g × profundidad
  bajo la superficie libre del poro. En E1 (y la base) la misma columna
  está en 10.1 / 6.8 / 3.3 / 0.9 kPa: **el lecho inundado del modelo base
  está ~70 kPa por DEBAJO de su hidrostática** porque la válvula se traga
  la caída. `pexcess.py` corregido (10-oct): la referencia pesa ρ_l g
  entero donde el líquido es continuo y llena su capacidad (poro saturado,
  baño), α_l ρ g en el resto; con la referencia antigua (α-ponderada) el
  "exceso" de +56 kPa de E1b era hidrostática y el de la base −70 kPa quedaba
  oculto. **El "p>20k" del banco y del juez es hidrostática en cuanto el
  lecho carga su peso**: el criterio útil es exceso sobre hidrostática
  (snapshots), p>100k, gas>200 y centinelas.
- **Lo que E1b destapa**: tormenta sostenida 7.5–11 s (p_max 0.7–1.25 MPa,
  50–75 % de pasos con centinela por bin). Snapshot 10 s: celdas de BAÑO
  casi llenas sobre el lecho saturado en el anillo del eje, (4,j,1) con
  α_l 0.95, α_g 0.04–0.07, p ±10 kPa entre vecinas azimutales y gas a
  ±300 m/s en θ con el líquido quieto (0.1 m/s); el lecho debajo en su
  hidrostática (72 kPa, u ≈ 0). Sin la válvula del poro, el único
  absorbente de volumen que queda en la capa de baño es el gas residual de
  esas celdas (4 %), y el desajuste α–p (lo que el limitador rechaza y el
  goteo no enlazado) se cobra ahí. Es exactamente el término de E2
  (`S_unl`/`S_store`) que en el banco "no tenía sobre qué actuar" con E1:
  ahora sí. Bancos en cadena: E1+E1b+E2 (`e1b2_n4`), +lazo 3 pasadas
  (`e1b2pc3_n4`), E1+E1b+lazo sin E2 (`e1bpc3_n4`).

### Bancos E1+E1b con E2 y lazo interno; la máscara que conmuta

| variante (n4, 12 s) | p>100k 6–12 s | gas>200 | cent. p/gas | p_max | vol_lim med |
|---|---|---|---|---|---|
| E1 | 2.7 | 5.1 | 1.5 | 291 kPa | 2.3e-3 |
| E1+E1b | 15.3 | 34.7 | 12.6 | 1.25 MPa | 1.6e-4 |
| E1+E1b+E2 | 15.2 | 32.8 | 12.3 | 892 kPa | 1.6e-4 |
| E1+E1b+E2+lazo 3 | 93.2 | 95.9 | 84.2 | 1.03 MPa | 5.8e-4 |
| E1+E1b+lazo 3 | 93.5 | 91.2 | 77.6 | 1.52 MPa | — |
| E1+E1b, máscara fija por paso (`e1bf`) | 12.3 | 20.9 | 8.7 | 1.41 MPa | 1.2e-4 |

- E2 no hace nada sobre E1b: `ws_pc_unl` mide la entrada no enlazada
  EFECTIVA (tras el limitador), que en un poro lleno es cero. El lazo
  interno con momento rezagado (`n_pc_max = 3`) es MUCHO peor sobre filas
  rígidas (exceso ±190 kPa en el lecho): cada pasada re-corrige la presión
  sin que el momento la vea. Descartado como está.
- **Sonda (1,16,4) a 10 s en `e1b`** (celda de BAÑO del anillo del eje con
  1.3 % de chatarra, α_l 0.95–0.99, α_g 0.00–0.025): `act` alterna TT/TF
  entre outers y pasos; pp por outer +1.3e4, +0.9e4, +4.3e4, +0.05e4,
  +3.8e4 (un paso), −1.1e4, +2.0e4, −1.3e4, +2.9e4, −1.2e4 (el siguiente);
  p de la celda −2 → 20 → 39 → 55 → 40 → … kPa paso a paso; `Su_liq`
  ±0.1–0.8 m³/s (mil volúmenes de celda por segundo). Su única cara blanda
  es la radial (aE 1.5e-4; aS/aN 4.9e-7, aT 7e-8, aB 6e-9 sobre el lecho
  rígido). Causa: la celda tiene α_s = 0.013 ≥ 1e-2, así que `liq_cap` le
  descuenta el piso de poro y `ws_liq_room` cruza 1e-4 y vuelve en outers
  consecutivos → el gas entra y sale del acople → la fila alterna
  blanda/rígida → SIMPLE no converge. Corrección: `ws_sat_goff` fijada en la
  primera iteración externa del paso (sin estado entre pasos: reinicio
  bit a bit intacto). Sonda repetida en `e1bf`: pp por outer 5.6e3, 0.7e3,
  2.6e3, 2.3e3, 2.2e3 (converge, mismo signo), p 17.6 → 28 kPa suave.
- Pero la tormenta 7.5–11 s sigue (`e1bf`: p_max 1.41 MPa, 35–80 pasos de
  cada 250 con p > 100 kPa): los snapshots a 8 y 10 s están LIMPIOS (|p|
  máx 70–93 kPa, hidrostática; gas 124–157 m/s), así que son ráfagas de
  pocos pasos cada ~4 pasos. Hipótesis: golpe de ariete al SATURARSE una
  celda entre un paso y el siguiente (blanda con entrada a u → rígida: parar
  u = 0.5 m/s en 2 ms cuesta ρ u Δx/Δt ≈ 200 kPa; la presión expulsa
  líquido por otra cara, la celda baja de cap, vuelve a blanda, repite). Es
  el water packing clásico (RELAP5 §3.4.6) que F2.32 "casi no veía" porque
  la válvula del gas de poro lo absorbía. Pruebas encoladas: snapshots
  cada 20 ms en 8–8.5 s para localizar las ráfagas; E1b + compliancia
  residual D2.4 (`alpha_g_comp_min = 0.01`) como amortiguador; `alpha_p`
  0.7 (el de B1; el banco llevaba 0.3) y 10 outers.

### Ráfagas localizadas (`e1bf_dense`, snapshots cada 20 ms en 8–8.5 s)

Pasos con p > 300 kPa: 4028–4031 (515–540 kPa), 4035 (…), ráfagas de 3–5
pasos. Snapshot 4030: celda (4,2,3) = BAÑO casi lleno sobre el lecho, α_l
0.988, α_s 0.007 (< 1e-2: NO es lecho, sin piso de poro, E1b no la toca),
α_g 0.0045 (< `ALPHA_FLOW_CUTOFF`: su gas está FUERA del acople), p = 540 kPa,
u_g (9.5, 74.5, −133) m/s; encima (k = 5) α_l 0.60 / α_g 0.40 a 129 kPa con
u_l = −0.84 m/s (vertiendo en ella). Snapshot 4040: (4,15,3) idéntica (α_l
0.983, α_g 0.0087, 312 kPa, k = 5 vierte a −0.90 m/s). Es el **golpe de
ariete de la celda que se LLENA** (RELAP5 §3.4.6: "discontinuous change in
compressibility" cuando el hueco se va; TRACE cap. 2): al cruzar α_g el
umbral 1e-2 hacia abajo su gas sale del acople de golpe, la fila queda
líquida pura e incompresible, el piso (lecho E1b) es rígido, y parar
0.84 m/s en 2 ms cuesta ρ u Δx/Δt ≈ 300 kPa. Las otras ráfagas (4100,
4251) son celdas de lecho saturadas en el anillo del eje con +77–160 kPa
sobre su vecina de arriba (también saturada), ∇p ≫ ρ g: mismo mecanismo
desde la cara de arriba.

Lectura: en el modelo base esto no se veía porque la válvula ficticia del
poro (F2.7 + gas de piso activo) absorbía la entrada; por eso F2.32
"casi nunca se activaba". Con E1b la rigidez es real y el water packing
clásico aparece donde la literatura dice: la celda que pierde su último
gas. Remedios de libro: (a) mitigación RELAP5/TRACE (detectar la celda que
se llena y resolver la cara de entrada desde el momento, no desde la
presión — F2.32 archivada, reescribible ahora que el fenómeno existe);
(b) compresibilidad residual en las filas de líquido (D2.4
`alpha_g_comp_min`, residualAlpha de OpenFOAM): el gas sigue en la
diagonal al cruzar el umbral y el golpe se reparte en varios pasos. Banco
`e1bfc_n4` = E1+E1b(fija)+`alpha_g_comp_min = 0.01` en curso.
Relajación y outers no son la causa: `alpha_p` 0.7 (el de B1) no cambia
nada (11.6/19.1/8.3); 10 outers mejora poco (10.0/13.9/6.0; 0–6 s limpio).
