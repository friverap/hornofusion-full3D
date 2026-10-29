## Revisión de evidencia — WS-K1, panel de cierre, ronda 2 (revisor-evidencia)

Recalculé con datos en disco todos los números del reporte, incluidos los añadidos en esta versión (resumen, contraste k1b/k1pb, D2.2/D2.2c y pc_drift_source). No ejecuté ninguna corrida.

### Tabla

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| H1: convergencia k1_342 | 205/205 con tol 1e-6; 0/205 con 1e-3 | 205/205; 0/205 (plank_conv) | ok |
| H1: \|p\| máx. en la sonda | 69 967.7 Pa en 342539 | 69 967.7 en 342539 | ok |
| osc2 base → k1 | 51.8 kPa → 342 Pa | 51 835.2 → 342.3 | ok |
| H1b (a) osc2 | 885.7 | 885.7 | ok |
| H1b (b) grad_hid_max | 70.57 | 70.57 | ok |
| H1b (c) p>100k | 5.4 % (6/111) frente a 3.2 % (3.55) | 5.4 %; 6 pasos | ok |
| H1b (d) sin converger | 0.9 % | 5/550 = 0.9 % | ok |
| H1b (e) vol_lim | 2.46e-3 ≤ 2.605e-3 | 2.4596e-3 | ok |
| Veredicto C-028 frente al criterio C-025 | refutada | (b) y (c) fallan por la letra de C-025 | ok |
| \|d2p\|>1000: base/k1/k1b/k1pa | 85/22/47/22 % (50/13/28/13 de 59) | 0.847/0.220/0.475/0.220 | ok |
| p75 / máx. \|d2p\| | 112k/730/14559/721; 333.8k/3729/218858/3728 | 111 994/730/14 559/721; 333 796/3729/218 858/3728 | ok |
| k1b frente a k1pb (osc2, p75, máx.) | 885.7/889.7; 14559/14565; 218858/218864 | idénticos | ok |
| Pasos con \|p_max\|>1e5 | base 7, k1b/k1pb 6, k1/k1pa 2 | idénticos, con los mismos pasos | ok |
| 342450 / 342451 / 342452 | 9.52e4; 8.045e5 y 8.030e5; 1.6401–1.6404e5 | 95 224.7; 804 512 y 802 982–802 984; 164 006–164 035 | ok |
| Sensibilidad sin 342451-2 | 4/109 = 3.7 % frente a 3.49 | 3.67 % frente a 3.488 | ok |
| Ciclo k1b (C-036) | osc2 6874, ag_min 0.01500 | 6874.3; 0.01500 | ok |
| Cociente de amplitud | 3.4× (23362/6874) | 23 362.5/6874.3 = 3.40 | ok |
| P-a k1pa_342 | osc2 209.5, ag_min 0.01834, p>100k 1.8 | 209.5; 0.01834; 1.8 | ok |
| k1b tras el pico | 27.4–36.5 kPa (342538–342560) | 27 411.7 (342544) – 36 507.4 (342539) | ok |
| dense_340_n14 (1,59,9) | 74.5/94.0/42.6/108.0/42.9/636.0 kPa; 342530 48.8 en otra celda | idénticos; 342530 en (1,19,7) | ok; ver O4 |
| Juez 344–345.5 s | K 0.1/0.3/12.8; base 6.7–9.5 | n12 0.1, n14 0.3, n15 12.8; base 6.7/7.2/9.5 | ok |
| k1_340 frente a n12 | 0.5/1.1/0.7 frente a 0.4/0.3/0.1 | idénticos | ok |
| ≥1 MPa (C-310/C-311) | base 1/4/19; n15 183 (122 en 2e6) | 1/4/19; 183/122 | ok |
| diag_k15_k_off | 1.551e5, luego 2.0e6 → 1.797e6, 10 filas | 155 132 → 2.0e6 → 1 796 927; 10 | ok |
| vol_lim / vol_unlinked | 2.481e-3 frente a 2.460e-3; 2.057e-3 | 2.4807e-3 frente a 2.4596–2.4600e-3; 2.0568–2.0573e-3 | ok |
| pc_drift_source en las 5 config | true | true | ok; la conclusión sobre unl_on es imprecisa (O5) |
| PROBE-LIM / ws_pc_unl en run.log | 0 | 0 | ok |
| 'pp tras conjunto activo' | 0/550/550/550 | 0/550/550/550 | ok |
| Recuentos PROBE y caras 34/37 | según el reporte | idénticos | ok |
| D2.2 / D2.2c | 15.2/8.1, 11.2/4.7; 17.1/15.1 frente a 4.9/4.4 | idénticos (plan_d, líneas 112-123 y 159-166) | ok |
| Afirmaciones raíz | 16: 4 refutadas, 9 fallidas, 3 soportadas | idéntico | ok |
| Commits en src desde 1bc9832 | 7, con los extractos de sus mensajes | 7; extractos coinciden | ok |
| git apply --check | falla en mod_pressure_3d.f90:733 | idéntico | ok |
| index del parche = blobs de 1bc9832 | 412cfd5/3c1948e/c01f606 | idénticos; cmp: archivos idénticos | ok |
| «~0.4 % de holgura» en k1_340 | cita {C-027} | la cifra está en C-032 y se midió en k1_342 (0.01834) | objeción O3 |
| Diff del cierre añade C-312/C-313 | sí | ya están en HEAD e250687 | objeción O1 |

### Juicio sobre la predicción y la comparación
- C-025 exige que se cumplan TODOS los incisos (a)-(e). Fallan (b) y (c), así que la refutación (C-028) sigue la letra del criterio. El reporte no presenta (a) como aprobado en ningún sentido favorable y deja la regla de aborto como lectura sin veredicto. Es correcto.
- La comparación es justa: todos los brazos parten del mismo reinicio, diag_p342a/eaf3d_00342450.h5, con la misma ventana y las mismas ranks. El reporte reconoce que ese reinicio está probablemente contaminado (C-290) y lo contrasta con la corrida continua dense_340_n14. También declara que los binarios no son verificables y que k1b/k1pb es una sola trayectoria.

### Objeciones (ninguna bloqueante)
1. **O1**: report.md:18-19, 52 y 348-349 atribuyen a este cierre C-312/C-313, la errata de research.md, la entrada «Plan K CERRADO» y el §6. Todo eso ya está en HEAD e250687 (`git log -1 -- .claude/rules/research.md` = e250687). El diff staged solo cambia 16 líneas de acople-pv.md y 6 del plan.
2. **O2**: report.md:87 presenta como hecho «artefacto del reinicio {C-290}», pero C-290 está «fallida» y dice «muy probablemente».
3. **O3**: report.md:222, «~0.4 %», cita C-027. Debería citar C-032 y la medición de k1_342 (ag_min 0.01834 en `campaigns/b1/k1_342`).
4. **O4**: report.md:103-109 no cita {C-077}/{C-078} para el binario de dense_340_n14 (eaf3d_head_e5d331e_opt, bit a bit) y omite 342525 (33.6 kPa en (1,59,9)).
5. **O5 (nueva)**: report.md:143-145. Que pc_drift_source sea true no basta para que unl_on esté activo: según plan_k_v2.patch:155 también exige ws_pc_unl_valid del transporte del mismo paso (1bc9832:src/mod_continuity.f90:277, 863-866), así que en el outer 1 no lo estaba.
6. **O6 (nueva)**: el acople-pv.md staged mantiene en la línea 644 el «no reintentar» que el propio reporte (líneas 243-247) califica de «más fuerte que los datos», y no incluye D2.2/D2.2c en las líneas 669-672. El reporte lo lista como pendiente (líneas 392-405), pero el commit de cierre llevaría ese texto sin corregir. Hace falta aplicar los pendientes antes del commit o declararlos diferidos.

Todos los números del reporte se reprodujeron dentro del redondeo mostrado, y el veredicto de la predicción respeta el criterio pre-registrado. Las objeciones son de atribución, procedencia y precisión, y ninguna cambia la conclusión «G1 no cumplida; estado fallido».

VEREDICTO: aprueba