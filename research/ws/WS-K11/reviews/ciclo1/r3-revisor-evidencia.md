## Revisión de evidencia: WS-K11, ronda 1

Revisé `research/ws/WS-K11/report.md` contra el registro (C-222 a C-245) y los datos de `campaigns/b1/*`. Todo fue solo lectura. No leí las revisiones de los otros revisores.

**Resultado:** todas las cifras se reproducen y los veredictos de H12, H13, H15 y H16 coinciden con sus criterios pre-registrados. Rechazo por dos razones: el reporte se contradice sobre lo que H16 demuestra, y el titular afirma más de lo que prueba el brazo C.

### 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| k10b_dt025, pasos 280002-280004 (m/s / kPa) | 198.6/281, 300.0/461, 200.8/199 | 198.6/281.1, 300.0/460.8, 200.8/199.1 | ok |
| FAIL de check_audit en k10b_dt025 | sentinel_gas, regime_p (591.6 kPa en 280161), regime_gas | igual | ok |
| comp_carry | 0 | 0.0 | ok |
| \|Δρ/ρ\| frente a la EOS | ≤ 4.4e-16 en 68232 celdas | 4.44e-16 en 68232 | ok |
| Salto de Tg_end | 17.7 %, p99 0.2 % | \|T/Tg−1\| 0.177, p99 0.0022 (con \|Tg/T−1\| sale 0.150) | ok (O5) |
| eosend/dt con 1, 0.5 y 0.25 ms | 2.922, 2.882, 2.865 kg/s | 2.9221, 2.8824, 2.8650 | ok |
| H12: tgfix en 280003 | 300.0 m/s, 461 kPa; REFUTADA | igual; REFUTADA por la letra | ok |
| Picos con 1 ms y 0.5 ms | 99.6 kPa y 163.5 m/s; 191.4 kPa | 99.6 y 163.5; 191.4 | ok |
| Fechas de commits y run.log | 10:13:58; 02:56:49; run.log 43 s después | igual (02:57:32) | ok |
| Tabla de 1 ms (scrfh, m203, otp) | 71.9/14.8 … 215.0/83.5 | igual | ok |
| m203/m21f1 frente a otp | < 5e-6 | 4.83e-6 | ok |
| k10_base y k11_base_s290 frente a otp | 2.2e-12; 5.2e-13 | 2.22e-12; 5.21e-13 | ok |
| H13: s290, pasos 2-10 | 71.6 m/s / 79 kPa | igual | ok |
| H15 brazo A | 69.4 / 15; cuartos 0,0,0,0 | igual | ok |
| H15 brazo B | 300.0 / 342; ventana 365 (290020); cuartos 58,59,59,59 | igual; FAIL sentinel_gas y regime_gas | ok |
| [CG] AVISO en A, B, C, D | 0 | 0 | ok |
| Configs A y B frente a k10b_dt025 | solo claves o snapshot | diff confirma; binario k10b, 15 ranks | ok |
| Cuartos ≥ 100 kPa en k10b_dt025 | 31, 21, 32, 36 (120/235) | igual con las dos particiones | ok |
| u_gas_max > 200 m/s en k10b_dt025 | 280007, 280011, 280041, 280137 | igual (más 280003 y 280004) | ok |
| Cuartos ≥ 100 kPa en k10b_dt05 | 8, 1, 2, 0 | igual | ok |
| nolink en k10b_dt025 | 105/235, tres tramos, máx. 6, 71 de 120 | igual | ok |
| nolink en el brazo B | 235/235, 4-9 celdas | igual | ok |
| nolink en A, s290, dt05, mo20 | 0 | 0 (C y D también 0) | ok (O6) |
| Asentamiento a 1 ms | otp 24/17, mo20 31/13; ciclos 23/43 y 28/49 kPa | 24/17, 31/13; 23.2/43.3 y 27.6/49.0 | ok |
| Tabla de jueces 275-295 s | por segundo | idéntica | ok |
| Fila 275-280 de la tabla de jueces | 30.3/7.2 y 16.8/0.7 | igual, pero el comando citado no la produce | O4 |
| 280.0-280.1 s y \|Δp\| en 290.0-290.1 s | 38.3/18.4 frente a 38.1/21.9; 3.7 | igual, sin comando | O4 |
| Ventana de s290 | 450.0 (290093; 128.6); 344.3 (290074); 5/235 | igual | ok |
| Ventana de dt05 y mo20 | 70.6 (290004; 80.1); 70.0 (290011; 121.5) | igual | ok |
| k11_base_s290 | 107 m/s, 27 kPa, FAIL energy_balance, 1 AVISO (res 4.198e-2) | 106.9; 27.07; 2.153; 1; 4.198E-02 | ok |
| Alternancia de otp en 289998-290009 | 106.9/90.5 m/s; 23.5/27.0 kPa | igual | ok |
| Última fila de otp | 345.5 s | 345.53 s | ok |
| H16 brazo C | 51.2 / 117 (280004); cuartos 1,0,0,0; sin FAIL | igual; u máx. en la ventana 86.1 | ok |
| H16 brazo D | 77.0 / 56 (300002); 0,0,0,0 | igual | ok |
| Pre-registro antes de cada corrida | sí | 096b1ba < tgfix; d4c07b7 < s290; 424a70d < A; aa93539 < C | ok |
| H16 por la letra (C-244: sin pico si u < 200 y p < 300) | SOPORTADA | SOPORTADA | ok |

### 2. Objeciones

**O1 (bloqueante): el reporte se contradice sobre lo que H16 separa.**
- El titular (`report.md:83-89`) dice que H16 separa el cambio de claves de su sola presencia, y que la causa es el CAMBIO.
- El paso 9 «Alcance» (`report.md:220-221`) sigue diciendo que el titular habla de «encender las claves» y no de «el cambio de claves».
- La primera viñeta de Incertidumbre (`report.md:388-402`) dice «sin separar» y propone como pendientes los brazos C y D, que ya se corrieron (C-245).
- Para levantarla: reescribir esas dos secciones a la luz de C-245.

**O2 (bloqueante): el brazo C cambia tres cosas a la vez, no una.** Frente a `k10b_dt025`, `campaigns/b1/k11_c_dt025_jb280` cambia:
- la historia de f28;
- `pc_outlet_total_pressure` (`config.dat:115`: false en C, true en `k10b_dt025`);
- el linaje, el escritor y el estado del snapshot (judge_jb_275, que ya está a 30.3 kPa en 275-280 s; judge_fh_275 está a 16.8 kPa).

El veredicto de C-244 es correcto por la letra: el brazo C no tiene pico (51.2 m/s y 117 kPa). Pero el criterio solo prueba f28 con outlet apagada. El titular «la causa es el CAMBIO de claves sobre un estado escrito sin ellas» lo extiende a las dos claves, y el propio reporte admite (`report.md:443-447`) que a 0.25 ms el papel de outlet no está aislado.
- Para levantarla: acotar el titular a f28.
- Para resolverlo con datos haría falta una predicción nueva: 0.25 ms desde `judge_jb_275/eaf3d_00280000.h5` con f28 y outlet en true.

**O3 (no bloqueante): la viñeta sobre la regla de transporte está desfasada.** `report.md:474-488` cita las líneas 360-366, pero la regla ya cita C-245 (líneas 359-372). Siguen dos discrepancias reales:
- «~20-25 pasos» (línea 368), cuando con el criterio del paso 9 son 13-31 pasos;
- no aparece la huella nolink.

**O4 (no bloqueante): cifras sin comando que las produzca tal cual.**
- La fila 275-280 de la tabla de jueces: el comando citado imprime medias por segundo, no ese agregado.
- Las cifras de 280.0-280.1 s y de 290.0-290.1 s no tienen comando.

Todas las reproduje. Basta añadir al comando parámetros de ventana y cadencia.

**O5 (no bloqueante): faltan referencias y una definición.**
- El paso 6 no lleva {C-nnn}; las cifras están en C-226 y C-236.
- Hay que decir que el 17.7 % es \|T/Tg_end − 1\|.
- La procedencia apunta a un script que escribe un archivo; conviene dar un comando de solo lectura.

**O6 (no bloqueante): falta información sobre C y D.**
- La huella nolink de C y D (0/235 en ambos) no se informa.
- La viñeta «Una trayectoria por condición» no menciona que H16 se decide con una sola trayectoria (C llega a 117 kPa, el 39 % del umbral).

VEREDICTO: rechaza