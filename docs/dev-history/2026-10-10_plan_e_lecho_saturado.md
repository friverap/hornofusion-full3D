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
