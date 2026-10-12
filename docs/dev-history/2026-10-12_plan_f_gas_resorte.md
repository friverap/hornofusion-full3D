# Plan F — diagnóstico denso en B1 y "bolsa de gas = resorte" (12-oct-2026)

Contexto: Plan D y Plan E (E1, E1b) cerrados negativos en el juez B1. Decisión
del usuario (12-oct): último esfuerzo, de raíz; si no funciona, cierre del
proyecto. Protocolo: medir en B1 antes de tocar nada (el banco no predice B1).

## 1. Series densas (snapshots cada 20 pasos) y sonda `[PROBE-pmax]`

Nueva línea de la sonda global (`mod_probe`, dentro de la ventana
`probe_step_*`): celda del |p| máximo de cada subetapa con su estado
(α_l/α_g/α_s, velocidades, vecinas B/T/E). Escáner de series densas:
`scripts/diag/burst_scan.py` (celdas con |p| > umbral y gas > 200 por snapshot,
con cruces de umbral entre snapshots).

- `base_dense325`: base (binario del juez `judge_largo_F231`, 4-oct), reinicio
  a 325 s, 41 snapshots hasta 326.6 s, 12 ranks.
- `e1b_dense315`: E1+E1b+D2.4 (binario 10-oct), reinicio a 315 s hasta 317.2 s.
- `base_dense325p`: base con el binario ACTUAL (12-oct), mismo reinicio, sonda
  de fila `[PROBE-P]` en la bolsa (6,30,1).

### Dónde están las ráfagas de la base (325.0–326.6 s)

428 celdas-snapshot con |p| > 100 kPa: **k = 1: 175, k = 2: 237**, k = 3: 13,
k = 4: 3. Tipos: lecho denso (α_s ≥ 0.85) 230, bolsas de gas (α_s ≈ 0.64,
α_g ≈ 0.36, α_l < 0.01) 50, baño 3. Los 164 celdas-snapshot con gas > 200
m/s están en k = 5 (153), sobre el baño bajo el arco, con gotas a −19…−36
m/s: chorro del arco con niebla, no el piso.

Anatomía (celda (6,30,1), bolsa del piso): α_s 0.635, α_g 0.365, α_l 0,
T_gas 450–585 K, T_s 445 K (fría). Encima (6,30,2): α_s 0.90, α_g 0.072 →
0.015, α_l 0.033 → 0.081 en 0.8 s (le entra líquido del poro saturado
(6,30,3): α_l 0.149 = cap, α_g 0.015 = piso). p(6,30,1) ≡ p(6,30,2) en cada
snapshot: 5 → 42 → 6 → 113 → 6 → 6 → 229 → 234 → 331 → 302 → 207 → 24 → 6
kPa; gas de la bolsa 24–115 m/s durante la ráfaga, 1–3 m/s fuera. Succión
simétrica en (1–3, 11–13, 1): −275 … −535 kPa mientras α_l crece 0.01 →
0.04. En E1b la primera celda del |p| máximo es (2,4,1), otra bolsa, a −50
kPa con p = 0 en su vecina radial (celda sin fluido); 4010 líneas de sonda
con |p| > 100 kPa: 3789 en k = 1, 221 en k = 2, 3583 en bolsas.

Lectura: la bolsa atrapada bajo el lecho inundado no percola hasta el
freeboard → F2.16 la saca del acople → pared Neumann (`pp = 0`, `p` = media
de vecinas). El líquido que el poro saturado le vierte o le drena cambia el
volumen de la fila vecina y la única compresibilidad que queda es la
acústica del líquido: ±MPa. Físicamente la bolsa es un resorte (p V^γ).
Hilfer (1998) dice que la subfase desconectada no propaga gradientes, no
que carezca de presión: F2.13/F2.16/F2.31 confundieron inmovilidad con
rigidez.

### La sonda de fila en la bolsa con el binario actual: otra trayectoria

`base_dense325p` (binario del 12-oct, sin claves): la bolsa (6,30,1) queda
ACTIVA (`act_g` = T) todo el tramo, p sube suave 5.6 → 11.7 kPa en 1.6 s
(Su_comp +1.8e-4 m³/s de expansión frente a caras que ventean 1.1e-4; pp
+2…+8 Pa por outer), sin ráfagas. Audit: p > 100 kPa en 0 % de los pasos en
7 de 9 ventanas de 0.2 s (21 % y 33 % en dos ráfagas de 218 y 370 kPa),
frente a 24–100 % en todas las ventanas con el binario del 4-oct.

**Hallazgo crítico**: todas las referencias "base" (`judge_largo_F231` bin
4-oct, `flood_n5/6/7` 6-oct, `dt_*` 5-oct, `v35_322` 4-oct) se corrieron con
binarios ANTERIORES a los dos fixes de halos basura: `ab5e95a` (7-oct,
`intent(out)` de la malla: topología basura esporádica) y `bf57c68` (9-oct,
Bug 22: halos físicos de `liq%alpha` con basura del heap, corridas no
reproducibles). Los jueces de Plan D/E compararon candidatos con binarios
nuevos contra una base contaminada. Nueva referencia: `judge_base_n12`
(binario actual, sin claves, 300 → 325 s), en cola tras `judge_f_n12`.

## 2. Clave `pc_gas_spring` (ver `docs/PLAN_F_gas_resorte.md`)

Gas siempre activo (`act_g = cell ∧ (α_g > 0 ∨ act_l)`), sin F2.16/F2.31/E1b;
caras líquido|líquido abiertas (E1); `liq_cap` = hueco físico (sin piso
`ALPHA_PORE_GAS`; `pc_keep_pore_floor` lo conserva para diagnóstico).
`make test-quick` OK con default (bit a bit).

## 3. Banco `bed_flood` variante base (12 s, n4, % de pasos)

| corrida | claves | p>20k | p>100k | g>200 | l>10 | cent | p_max |
|---|---|---|---|---|---|---|---|
| e_base_n4 | — | 42.3 | 8.1 | 12.5 | 9.4 | 4.7 | 999 kPa |
| e1_n4 | E1 | 53.9 | 1.4 | 3.1 | 0.0 | 0.8 | 291 kPa |
| e1bfc_n4 | E1+E1b+D2.4 | 99.2 | 2.0 | 2.8 | 1.9 | 0.7 | 158 kPa |
| f_n4 | spring | 100.0 | 11.2 | 21.1 | 0.8 | 8.6 | 918 kPa |
| f_a_n4 | spring + piso de poro | 53.8 | 7.5 | 7.0 | 0.0 | 2.0 | 396 kPa |
| **f_b_n4** | **spring + `alpha_g_comp_min` 0.01** | 99.2 | **0.0** | **0.9** | 0.0 | 0.6 | **72 kPa** |
| f_c_n4 | spring + piso + comp_min | 53.8 | 6.9 | 6.2 | 0.0 | 1.7 | 277 kPa |

`f_n4p` (f_n4 con sonda y snapshots cada 0.2 s): las ráfagas de `f_n4` son
oscilaciones ±100–145 kPa de signo alternante en celdas de baño sobre el
lecho que llegan a α_g = 0 exacto al quitar el piso ((3,16,4): α_l 1.000,
α_g 0; gas que entra desde arriba a 42–73 m/s y vuelve a salir): fila rígida
(solo acústica del líquido) con la presión relajada y la velocidad no (Plan
E §2.3). La compliancia residual (D2.4) la amortigua y además deja que el
gas entre y salga del baño sin conmutar la rigidez de la fila. El piso de
poro (f_a/f_c) no sustituye a la compliancia: conserva la válvula ficticia.
"p > 20 kPa 99 %" en f_b es la hidrostática del lecho saturado que ahora
carga su peso (como E1b).

## 4. Screening B1: NEGATIVO

`judge_f_n12` = `judge_e1_n12` sin E1 + `pc_gas_spring` + `alpha_g_comp_min
0.01`, 300 → 325 s, 12 ranks, 11:47–13:53. `regime2.py` (% de pasos):

| ventana | p>100k | g>200 | cent_pg | l≥20 | pmax | gmax |
|---|---|---|---|---|---|---|
| 300–305 | 21.9 | 50.8 | 0.4 | 0.0 | 1.93e5 | 300 |
| 305–310 | 100.0 | 100.0 | 1.6 | 0.0 | 1.12e5 | 300 |
| 310–315 | 100.0 | 100.0 | 0.5 | 13.0 | 3.99e5 | 300 |
| 315–320 | 100.0 | 100.0 | 13.5 | 4.2 | 2.50e5 | 300 |
| 320–325 | 100.0 | 100.0 | 46.5 | 89.4 | 1.85e6 | 300 |

Base vieja 320–325: 4.2 / 1.8 / 0.7; E1: 27.6 / 6.3 / 0.8. Mediana de
`p_max` por segundo: 54 kPa (300) → 105 (304) → 200 (316) → 240 (325),
rampa lineal; gas > 200 pasa de 2 % (300–301) a 51.6 % (302–303) y 100 %
desde 303 s. `pexcess.py`: +96 / +187 / +936 kPa (310 / 320 / 325 s), lecho.

Clasificación de celdas por snapshot (|p| > 100 kPa: total / poro seco con
α_g = 0.015 exacto, α_s > 0.98, sin líquido; gas > 200: total / en baño
α_l > 0.3 / en lecho / freeboard):

| t | |p|>100k | poro seco | gas>200 | baño | lecho | freeboard |
|---|---|---|---|---|---|---|
| 305 | 1 | 1 | 2 | 2 | 0 | 0 |
| 310 | 5 | 5 | 11 | 9 | 0 | 2 |
| 315 | 35 | 34 | 13 | 13 | 0 | 0 |
| 320 | 47 | 44 | 20 | 15 | 0 | 4 |
| 325 | 113 | 89 | 50 | 11 | 0 | 37 |

Celda rampa (8,56,2): p 0 → 65 → 79 → 185 → 203 → 238 kPa (300 → 325 s),
T_g 1213 → 1240 K, α_g 0.015 fijo, u_g = 0, S_arc = 0; la de arriba (k = 3)
α_g 0.015 → 0.010 → 0.000, α_s → 1.000. Mecanismo, conclusión y veredicto en
`docs/PLAN_F_gas_resorte.md` §5. Plan F cerrado NEGATIVO; el proyecto se
cierra por decisión del usuario.

## 5. Referencia limpia `judge_base_n12` (13:53–16:2x)

300–320 s limpia (0 / 0 / 0 / 2.4 % de pasos > 100 kPa por ventana de 5 s),
ráfaga aislada en 318–319 s (165 kPa), `P_HYDRO_CAP` a 320.49 s y en la cota
el 99–100 % de los pasos desde 321 s (320–325: 92.4 / 92.3 / 91.1). Tabla y
lectura en `docs/PLAN_F_gas_resorte.md` §6. Cierre: el muro de ~320 s es del
modelo, no del binario contaminado.
