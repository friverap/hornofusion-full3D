# Revisión de evidencia: WS-K12, ronda 1 (tras la escalada)

Revisé `research/ws/WS-K12/report.md`, el registro (`ledger.py show/open/check`), el diff staged de `scripts/research/ledger.py` y `research/README.md`, y los datos de `campaigns/b1/`. No he leído las revisiones de otros revisores. Todo fue solo lectura: `python3` con csv/h5py/numpy, `grep` y `sed`, y los scripts de lectura `probe_p.py`, `judge_metric.py`, `piezas.py`, `tasa.py` y `check_audit.py` sobre salidas existentes.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Afirmaciones raíz abiertas | 18 de 64 | 18 de 64 | ok |
| Eventos no raíz con estado no cerrado | 101 | 101 | ok |
| Resultados «propuesta» excluidos (lista literal), con refuta_si o criterio | 61, 0 de 61 | 61, 0 de 61 | ok |
| Veredictos: 14 con estado propio cerrado y 6 en_disputa (listas) | 14 + 6 | 14 + 6, mismas listas | ok |
| Entran 11 no raíz (C-126…C-212, C-237, C-261, C-154, C-168) | 11 | 11 | ok |
| C-078: eventos, precursor, control (n14) | 31, 19 (61.3 %), 453/4919 (9.2 %) | 31, 19, 61.3 %, 453/4919, 9.2 % | ok |
| Los 12 primeros eventos de n14 sin precursor (341.83-343.06 s) | 12 | 341833…343062 «no»; desde 343307, PRECURSOR | ok |
| C-081: eventos, precursor, control, celdas | 26, 18 (69.2 %), 457/4837; 22/2/1/1 | idénticos | ok |
| C-081: eventos en el piso con 0.01 ≤ alpha_s ≤ 0.05 | 17/26 = 65.4 % | 17/26 = 0.6538 (ALPHA_BED = 1e-2) | ok |
| C-084: eventos, precursor, control, celdas | 21, 17 (81.0 %), 480/4948; 18/3 | idénticos | ok |
| C-087: paso P elegido por la regla | 341706 (mediana 1.56e4) | 341706; mediana 1.56e4, recalculada desde la 1.ª PROBE-P de cada paso en run.log | ok |
| Cuota del gas, 341706 o1 | 0.908 | 0.221/(0.022+0.221+0.000251) = 0.908 | ok |
| Cuota del líquido, 341705 o1; externas 2-5 | 0.785; 1.0 | 0.785; 1.0 (Su_gas = Su_comp = 0) | ok |
| C-088: aP cae 68x; pp en o2 | 68x; 3.37e5 | 2.56e-6/3.75e-8 = 68.3; +3.369e5 | ok |
| C-093: pico de d26k_n14 y e1_n14 con la fila truncada / sin ella | 2.001e5 → 1.240e5; 1.474e5 → 1.455e5 | 2.001e5/1.24e5; 1.474e5/1.455e5 (argmax = 345500) | ok |
| d26k_n15 y e1_n15 no están en la fila final | 2.011e5, 1.853e5 | argmax en 341143 y 344287 | ok |
| E1 7x en 320-325 s; D2.6 «peor en picos y gas» | citas | acople-pv.md:460; PLAN_D §7, l.201 | ok |
| C-044: corridas con dt final < 1e-6 / en cuántas sube p_max | 22 / 19 | 22 / 19 (bajan diag_c060, f231_340; k1pa_340_n15 se queda en 2e6) | ok |
| Rango de dt final | 1.19e-9 a 1.27e-9 | 1.19e-9 a 1.27e-9 | ok |
| diag_k15a, dense_340_n15, judge_e1_n14, judge_d26k_n14: penúltima → última fila | 3.84e4→2.46e5; 5.75e4→2.04e5; 2.75e4→1.47e5; 1.86e4→2.00e5 | idénticos | ok |
| Errata de C-044: 345148 | 2.62e4 | 2.618e4 | ok |
| main_3d.f90:335-340 (paso corto si el hueco > 1e-6·dt_step) | cita | confirmado | ok |
| Afirmación de C-044 «contamina reinicios», cerrada como soportada | soportada | no medida (el propio reporte lo dice) | **objeción O2** |
| C-047: snapshots con audit p_max = max\|p\| | 395/395, 0 diferencias | 181+181+12+12+7+2 = 395, 0 diferencias | ok |
| diag_k15d 345250: max, min, audit | 9.27e4, −5.865e5, 5.865e5 | 9.266e4, −5.865e5, 5.865e5 | ok |
| diag_k15d 345280: max, min, audit | 2.564e5, −3.279e5, 3.279e5 | idénticos | ok |
| Audit de C-047 en 345.28 s: «2.6e5» | no se comenta | el audit da 3.279e5 | objeción O7 |
| mod_audit.f90:704; main_3d.f90:836 y 900; mod_output_hdf5.f90:230 | citas | confirmadas | ok |
| C-198, antes del arreglo: FAIL, 3.41e-06, sum m_gas_out 0 | | idénticos (check.txt) | ok |
| C-198, con el arreglo: PASS, 1.69e-21, −7.1206e-6 | | idénticos (test_full.txt:2138-2175 y check_audit sobre tests/out) | ok |
| Binario previo «eaf3d_k8b_opt» | dato | no está en el log; solo en C-198 | objeción O8 |
| tests/out: «código de 2b65e11..1de144e~1» | | el audit.csv tiene m_gas_bx_*, columnas de 1de144e | **objeción O3** |
| .gitignore:20; mtimes 00:40 y 00:43; 1de144e es el único commit de src | | confirmados | ok |
| C-199: PASS con err rel 0; v132 = v131 + 1 | 60; cold_flow_noenergy_n4 | 60; {'cold_flow_noenergy_n4'}, 0 métricas comunes distintas | ok |
| C-015: reinicio, dt 1.19e-9, p 2.78e4 → 9.52e4 | | restart_file = diag_p342a/eaf3d_00342450.h5; 1.19e-9; 2.783e4 → 9.522e4 | ok |
| C-015: pico y celda | 805 kPa en (2,51,8), líquido puro | −8.045e5 en [k,j,i] (2,51,8); alpha_l = 1 | ok |
| C-015: caída en dos pasos | 164 y 85 kPa | 1.64e5 y 8.48e4 | ok |
| Corridas continuas en 342.451-342.530 s | 91 / 81 / 131 kPa | 91.4 / 81.2 / 130.6 kPa | ok |
| Comparación justa p342 frente a judge_otp_280 | no se dice | p342a = judge_otp_280 bit a bit (2450/2450 filas) | ok (a favor) |
| Evento 342535 de n14 | 6.36e5 en (1,59,9) | c077.out:11 | ok |
| Plan K fuera de src | grep vacío | vacío; el parche existe | ok |
| C-127 (k7_mo20) | 59, 0.5660, 2.456 | 59, 0.56595, 2.4557 | ok |
| C-131 / C-139 (k7v3 / k7v4) | 0.319, 1.582, corr +0.229 | 0.3194, 1.5817, 0.229 | ok |
| C-145 (k7v5) | 0.319, 1.571 | 0.3186, 1.5705 | ok |
| C-174 (k8_cg1000) | 0.3156, 1.571 | 0.31561, 1.5707 | ok |
| C-204 | Br/e −0.683 y −0.135; 0.184 | piezas.py: −0.683, −0.135, 0.184 | ok |
| C-213 | 0.812 | tasa.py: 0.812 | ok |
| C-154 (su propio comando) | «repite C-145» | 0.384/0.163; 0.491/0.165; [0.380…0.426]; [0.521…0.682] | objeción O9 |
| Bandas de C-121/C-122, C-126, C-130, C-135, C-144, C-172 y C-202/C-203, C-212 | sin decidir | sin decidir por la letra; enmiendas C-122/C-172/C-203 anteriores a su veredicto y con motivo | ok |
| C-057 → C-058 → C-061 | refutada | la cláusula «fijada» no se demuestra | **objeción O1** |
| C-074 → C-077 → C-078 | refutada en la letra | 61.3 % < 70 % con 31 eventos ≥ 3 | ok |
| C-082 → C-083 → C-084 | soportada | 21/21 en j 16..22 ≥ 70 % | ok |
| C-085 → C-086 → C-087 | refutada | cuota del gas 0.908 ≥ 0.6 | ok |
| C-079, C-089 | fallida (no concluyente) | coherente con la regla declarada | ok (ver O4, O11) |
| Validador: sin_decidir solo en resultado con ref; ESTADOS_VEREDICTO sin él | | confirmado leyendo el diff (validate, l.31-32 y 113-114) | ok |
| check OK con 278 eventos; ningún evento usa sin_decidir | | «ledger OK (278 eventos)»; 0 | ok |
| dense_rot_n15 conserva 13 snapshots | 13 | 13 *.h5 (12 eaf3d + rot20) | ok |

## 2. Objeciones

**Bloqueantes**

1. **O1: A1 (C-057).**
   - Dato: `campaigns/b1/diag_c058/run.log:561-576`, 2.ª externa de 345318: cx E = 1 en it 2-6 y N = 1 en it 1-6.
   - El criterio de C-058 refuta solo si una cara queda **fijada**. La sonda muestra **candidatas**, y C-061 admite que no lo distingue.
   - Ni el soporte ni la refutación se cumplen por la letra. A1 trata la candidatura como fijación y no dice que el refuta_si de C-057 tampoco se cumplió.
   - Para levantarla: cerrar como fallida (no concluyente), según la regla del propio reporte, o aportar una sonda que registre fijación y signo del caudal.
2. **O2: B3 (C-044).**
   - La cláusula «contamina reinicios» no está medida: el propio reporte lo dice en «Incertidumbre» y en C1.
   - Para levantarla: «soportada SOLO en» la subida de p_max en el paso truncado (19/22) y la ruta de código; el reinicio queda como lectura. O bien correr el control desde un snapshot de paso completo.
3. **O3: B1 (C-198).**
   - Dato: `tests/out/cold_flow_noenergy_n4/audit.csv`, columnas 149-150: `m_gas_bx_multi` y `m_gas_bx_free`.
   - Esas columnas no están en `2b65e11:src/mod_audit.f90` y sí en `1de144e`. La frase «código de 2b65e11..1de144e~1» es falsa.
   - Para levantarla: quitar la mención a tests/out (los logs de WS-K9 bastan) o corregir la procedencia.

**No bloqueantes**

4. **O4: A3.** n15 tiene un evento en (1,58,8), celda que C-079 no lista. Afirmar que el refuta_si «no se cumple» es una interpretación; conviene reformular.
5. **O5: C2.** C-051 y C-064 se apoyan en el brazo sin Plan K (`diag_k15_k_off`), así que «Plan K v2 / no se adoptó» no las describe. Necesitan un texto propio.
6. **O6:** `report.md:313-314` cita `ledger.py:28` sin sin_decidir, pero el diff staged lo añade en la l.31. current_state está ahora en 150-156.
7. **O7: B4.** Falta la errata del audit de C-047 en 345.28 s: el audit da 3.279e5, no 2.6e5.
8. **O8: B1.** «eaf3d_k8b_opt» es una declaración de C-198, no un dato del log; hay que atribuírselo.
9. **O9: E10.** C-154 se reproduce hoy con su propio comando; «repite el sin decidir de C-145» no lo describe.
10. **O10: E7.** Conviene decir en el texto que el prerrequisito sobre k10_* no se reproduce con el checker versionado y que se sostiene con k10b_* (C-218).
11. **O11: A6.** Cerrar C-089 (regla de método del usuario) como fallida la pone en la lista de fracasos permanentes de `open`.

Todas las demás cifras del reporte se reproducen dentro del redondeo mostrado. El alcance (18 raíces, 101 → 11 eventos, 90 exclusiones) es exacto.

VEREDICTO: rechaza
