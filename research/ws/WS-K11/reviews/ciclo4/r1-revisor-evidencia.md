## Revisión de evidencia: WS-K11, ronda 1 (revisor-evidencia)

**Alcance.** Solo lectura. Recalculé los números con python3 (csv/h5py) sobre `campaigns/b1/*/audit.csv`, los snapshots `.h5` y las configs. Ejecuté `research/ws/WS-K11/scripts/h22.py --todos`, `medir_centinela.py`, `pares.py`, `nolink.py`, `tests/integration/check_audit.py` y `ledger.py show/check`. No miré las revisiones de otros revisores.

### Predicción del workstream: C-264 (H23), comparada con el criterio pre-registrado

- El criterio dice literalmente: «SOPORTADA si P tiene la firma y Q no; REFUTADA en otro caso». La firma es ≥ 1 paso nolink **y** ≥ 20 pasos con p_max ≥ 100 kPa, contando filas con step > P0+1.
- Al recalcular con `h22.py`: P (`k11_p_dt025_fh300_f28`, P0 = 299999, 239 filas) da nolink 0 y 0 pasos ≥ 100 kPa, así que no tiene la firma. Q tampoco la tiene (0/0). **Resultado: REFUTADA, igual que {C-266}.**
- El momento cuadra: el pre-registro se commiteó en `8b2d95b` a las 10:42:49 y la primera corrida (M) se creó a las 10:42:55. `h22.py` no ha cambiado desde ese commit y no hay ninguna enmienda.
- Las condiciones también: P es la config de F y Q la de C, cambiando solo restart y t_final; binario `eaf3d_k10b_opt`, 15 ranks y cero `[CG] AVISO`.
- C-263 (H22): M, N y O dan 0/0, así que queda **SOPORTADA, igual que {C-265}**.
- El reporte no reinterpreta el criterio. Lo que afirma de necesidad y suficiencia lo presenta como lectura con alcance, y declara que H22 era de bajo riesgo.

### Tabla de verificación

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| H23 P: nolink / ≥ 100 kPa / máx. p / máx. u | 0 / 0 / 96 kPa / 130.0 | 0 / 0 / 95.9 / 130.0 | ok |
| H23 Q | 0 / 0 / 95 / 89.9 | 0 / 0 / 95.0 / 89.9 | ok |
| H22 M, N, O | 15/18/20 kPa; 92.3/68.9/61.2 m/s | igual | ok |
| P: alternancia y media por cuartos | 86/54; 43.8 → 26.4 | 86.0/54.0; 43.8, 35.4, 33.5, 26.4 | ok |
| Ventana de M a Q | 61 ms, 239 filas | t_final +0.061; 239 | ok (E3) |
| H15 A / B (pasos 2-10, máximo, cuartos) | 69.4/15; 300/342, 365 (290020), 58-59-59-59 | igual | ok |
| H16 C / D | 51.2/117 (280004); 77.0/56 (300002) | igual | ok |
| H17/H18: E y F | 117; 300/461, 592 (280161), 31-21-32-36, nolink 105 | igual | ok |
| Pares C/E y k10b/F (pasos 0-10) | ≤ 7.9e-9 / 1.5e-9; 1.1e-9 / 3.5e-10; m_gas ~2.5e-7; 12 % | 7.9e-9 / 1.5e-9; 1.1e-9 / 3.5e-10; 2.6e-7 / 2.5e-7; 1.2e-1 | ok |
| G, I, J, K, L (tabla del paso 12) | 216.3/361, 895 (280263), 27-0-0-0, 35, 9/7 en el paso 27; I 99/55 en el 232; J 187/74 en el 226; L 3/0 en el 4 | igual | ok |
| Umbral 200/300: G, F, B, I, J, L, s290 | 11, 8, 18, 101, 187, 3, 2 | igual | ok |
| Nivel centinela | 7, 6, 9, 73, 120, 2, 2 | igual | ok |
| Tabla de la firma (14 brazos): nolink, ≥ 100, nolink con < 100, máx. sin nolink | F 105/120/34/380; G 35/27/8/91; B 235/235/0; I 57/142/1/634; J 72/219/2/2000 | igual | ok |
| Brazos de 0.25 ms: total / con f28 / sin cambio de f28 / con cambio y firma | 20 / 15 / 12 / todos menos P | 20 / 15 / 12 / 7 de 8 | ok |
| tgfix (C-273) | nolink 22-0-0-0; 31-27-26-19; 138.0/105.1/99.5/83.9; 73.7/50.3/38.1/17.8; 42-104; 460.9 | igual | ok |
| k10b_dt025: tramos nolink | 280002-023, 135-141, 161-236; 2 celdas en 280002; máx. 6 | igual | ok |
| Medias por cuartos B, k10b, C, s290, D, A, K, L, Q, H, M, N, O | (tablas de Resultado) | igual | ok |
| H12 | 69.37 frente a 69.06 (0.45 %); ≤ 3.4e-4; >1 % desde 280027 | 0.448 %; 3.44e-4; 280027 | ok |
| EOS final | 2.922 / 2.882 / 2.865 kg/s | igual | ok |
| Snapshot: Δρ y Tg_end | 4.4e-16 en 68232; 17.7 %, p99 0.2 % | 4.44e-16; 17.69 %, 0.217 % | ok |
| Pico a 1 ms y a 0.5 ms | 99.6 kPa, 163.5 m/s; 191.4 kPa | 99.63; 163.47; 191.41 | ok |
| Banco de 1 ms (paso 7) | 71.9/14.8 … 215.0/83.5; < 5e-6; [CG] AVISO | 4.8e-6; 8/8/8/328 | ok |
| Determinismo del reinicio | 2.2e-12; 5.2e-13 | 2.22e-12; 5.21e-13 | ok |
| Asentamiento a 1 ms (C-241) | otp 24/17; mo20 31/13; ciclos 23/43 y 28/49 | igual | ok |
| Banco s290 y otros | 450.0 (290093; 128.6), 344.3 (290074), 5/235; dt05 8-1-2-0 | igual | ok |
| k7v4_long (C-269, C-272, C-275) | 146 pasos, 284669-285379, 360 celdas en 144, 12 tramos, 59/45/30, 153, 329 pasos con 36-87, 86/96, 94/96 | igual (152.7; 35.9) | ok |
| Tamaño de los episodios nolink | F 6, G 11, I 16, J 13; B 4-9 | igual | ok |
| Régimen de los jueces 275-295 s | 45 celdas de la tabla | todas iguales | ok |
| Nivel centinela 280-295 s | 15 / 1 (288.68) / 26 | igual | ok |
| C-270/C-276 | 1599 filas; 215.0 en seis; 189.8; 136.7; 9 eventos; 66.1 frente a 48.3-62.6; 287.7 | igual | ok |
| C-274 | e2 28 filas; jb 1 (277.506) | igual | ok |
| comp_carry (C-271, C-274) | 0, 0, 0, 1.5e-9, 2.26e-5, 8.1e-5; jb/otp/F/B | igual | ok |
| Σliq_cont_prev | 1708-1755 | 1620-1755 en el conjunto citado | objeción E1 |
| Divergencia fh/jb en 280 s; identidad en 275 s | 0.77, 0.64; −0.09…14.8 y −12.8…28.0; Δ = 0 | igual | ok |
| fh frente a otp 280 | 8 de 56 datasets, solo diagnósticos | igual; /restart idéntico | ok |
| check_audit, FAIL de los 21 bancos | según las tablas | igual | ok |

### Objeciones (ninguna bloqueante)

1. **E1.** El rango de Σliq_cont_prev en `report.md:977` y C-271 («1708-1755») omite A (1707, `k11_a_dt025_s280_off/eaf3d_00280236.h5`) y rampbelow 255 s (1620). La conclusión «no separa» se mantiene. Para levantarla: corregir el rango.
2. **E2.** En `report.md:469-470` dice «G no acota». Pero `k11_g_dt025_a236_f28/config.dat` tiene dt_min = dt_max = 0.00025. Lo que falta en G es el salto de dt en el reinicio. Para levantarla: reformular la frase.
3. **E3.** M, N y O usan t_final +0.061 frente al «+0.06 s» de C-263, sin enmienda. El reporte lo declara, la desviación es conservadora y con 235 filas siguen dando 0/0. Para levantarla: añadir una nota de desviación o el conteo con 235 filas.
4. **E4.** judge_e2_275 tiene «salvo audit_freq» como diferencia, pero el valor es el mismo (5): la config efectiva es idéntica. Para levantarla: reformular la frase.
5. **E5.** El binario de k7v4_long no es verificable desde su run.log, porque no tiene la línea «Ejecutable». Para levantarla: citar WS-K7/C-135 como fuente.

### Comparación justa y muestra

- Las condiciones se cumplen: mismo binario y ranks, configs que solo difieren en la clave probada o en el restart, P0 explícito y ventanas de 235-239 pasos desde el reinicio, que no empiezan con el ciclo en marcha.
- El reporte reconoce sus límites: una trayectoria por brazo, un solo linaje con cambio y un solo sentido del cambio. Ninguna conclusión pre-registrada va más allá de lo que da su criterio.
- No reproduje por separado `h15.py`, `h17.py`, `h19.py`, `duracion.py` ni `WS-K10/centinela.py`, pero recalculé de forma independiente todas las cifras que imprimen.
- No verifiqué el cálculo R4 del refutador, que el propio reporte declara no repetido, ni las paradas de B1 de C-001, que solo se citan.

VEREDICTO: aprueba