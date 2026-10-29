## Revisión de evidencia, WS-K1, ronda 1

**Resultado: rechazo el reporte.** Una objeción bloquea, la O1. Todos los números que sostienen el veredicto se reproducen. El problema está en otro sitio: varios bloques del historial de ciclos describen el diff staged en un estado que ya no existe, y uno contradice al propio reporte.

Solo usé lectura: ledger.py show/open/check, regime2.py, plank_conv.py, cell_series.py, h5py/csv, git show/log/grep y git apply --check. No leí las revisiones de otros revisores.

### 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| H1, k1_342: solves sin converger (tol 1e-6 / 1e-3) | 205/205; 0/205 | 205/205 (it_medio 8.00); 0/205 | ok |
| k1_342: \|p\| ≥ 20 kPa en 342518-342560, máximo | sí; 69967.7 Pa en 342539; 69.1 kPa = paso 342540 | <20 kPa solo en 342500-517; 69967.7 (342539); 69103.1 (342540) | ok |
| osc2 de k1_342 frente a la base (342500-560) | 342 Pa / 51.8 kPa | 342.3 / 51835.2 | ok |
| C-025 (a) osc2 de k1b | 885.7 ≤ 1000 | 885.7 | ok |
| C-025 (b) grad_hid_max | 70.57 > 3 | 70.57 | ok |
| C-025 (c) p>100k y cent_pg | 5.4 % (6/111; se permiten 3.55); cent_pg 3/111 = 2.703 % | 6/111; 3/111; regime2 5.4 / 2.7 | ok |
| C-025 (d) sin converger | 0.9 % | 5/550 = 0.9 % | ok |
| C-025 (e) vol_lim medio | 2.46e-3 ≤ 2.605e-3 | 2.4596e-3 | ok |
| Veredicto de C-025 frente al criterio literal | refutada por (b) y (c) | (b) y (c) fallan; (c) falla también por cent_pg leído literalmente | ok |
| Pasos > 1e5 (base / k1b, k1pb / k1, k1pa) | 7 / 6 / 2, con la lista de pasos | 7 / 6 / 2, la misma lista | ok |
| 342451 y 342452 | 8.045e5 y 8.030e5; 1.6401e5-1.6404e5 | 804512 / 802982-802984; 164006-164035 | ok |
| Sin esos dos pasos | 4/109 frente a 3.49 permitidos; base 5/109 | 4/109; 5/109; 3.2 % × 109 = 3.49 | ok |
| \|d2p\| > 1000 Pa: fracción, p75 y máximo (base, k1, k1b, k1pa, k1pb) | 0.847/0.220/0.475/0.220/0.475; p75 112.0k/730/14559/721/14565; máx. 333.8k/3729/218858/3728/218864 | idénticos | ok |
| cell_series 342510-342533 | base 23362/0.01500; k1 y k1pa 209.5/0.01834; k1b 6874/0.01500; k1pb 6876 | 23362.5; 209.5/0.01834; 6874.3/0.01500; 6876.0 | ok |
| Amplitud de la base frente a k1b | 3.4× | 23362.5 / 6874.3 = 3.40 | ok |
| k1b liso en 342538-342560 | 27.4-36.5 kPa (mínimo en 342544, máximo en 342539) | 27411.7 (342544); 36507.4 (342539) | ok |
| dense_340_n14 en la celda (1,59,9) | 74.5, 94.0, 42.6, 108.0, 42.9, 636.0 kPa; 342530 en otra celda (48.8 kPa) | idénticos | ok |
| Firma del audit, k1b/k1pb/k1pa frente a k1_342 | vol_lim −4.48e-7 / +1.3e-9; rangos; vol_unlinked; Δp_max < 1.4 Pa y 1.8-57 Pa | idénticos | ok |
| Firma del audit, n12 frente a k1_340 | vol_lim +7.1e-9 (+7e-9 a +3.8e-7); vol_unlinked +5.5e-10 a +2.5e-8 (−4.1e-9 en 340007); Δp_max 70.8 y −862 Pa | idénticos | ok |
| Redondeo n14/n15 frente a n12; base frente a judge | 3e-17 a 2e-14; ≤ 5.3e-15 (base_340_n15, 340010) | 2.9e-17 a 1.78e-14; 5.30e-15 (340010) | ok |
| p_max de k1_342 / k1_340 en los primeros 10 pasos | 4.9e4-8.0e5 / 2.1e4-2.9e4 | 49066-802982 / 21413-29163 | ok |
| regime2 en 340-345.5 s (cent_pg) | k1_340 0.5/1.1/0.7; n12 0.4/0.3/0.1; n14 0.2/0.2/0.3; n15 0.1/0.2/12.8 | idénticos | ok |
| regime2 en 340-345.5 s (p>100k) | base 2.3/4.1/2.2, 10.3/9.8/7.2, 23.9/20.2/31.5; K 0.1×4, 1.6/1.4/1.6/2.4, 6.7/6.5/8.5/26.4; en 344-345.3: 25.1/20.8/35.2 frente a 6.4/6.6/9.0/15.1 | idénticos | ok |
| dm_liq y dE_liq en [340, 345.3) | 392.4-392.6 frente a 398.6-400.6 kg; dE 4.523-4.524e8 frente a 4.561-4.573e8 | 392.44-392.64 / 398.56-400.64; 4.5228-4.5241e8 / 4.5608-4.5733e8; dm_liq + dm_sol = 0 | ok |
| Snapshots 345500: V_liq en el lecho, total, centroide z, celdas en el piso | 0.1540-0.1547 frente a 0.1575-0.1589; 1.0732 frente a 1.0741-1.0747; 0.2255-0.2257 frente a 0.2249-0.2250; 117/121 … 162/165/169 | idénticos (k1_340 en 346000: 0.1541; 135/144/153) | ok |
| C-030 | 242/45/73 | submerged_bed: 242/45/73 | ok |
| Afirmaciones raíz de WS-K1 | 16: 4 refutadas, 9 fallidas, 3 soportadas | idéntico; ledger check OK | ok |
| Archivos de src con pc_alpha_implicit | 0 | 0 | ok |
| Commits en src desde 1bc9832 | 7, con sus mensajes; 79dc27b toca 32 líneas de mod_pressure_3d | idéntico | ok |
| git apply --check | falla en mod_pressure_3d.f90:733 | idéntico | ok |
| Índices de los parches = blobs de 1bc9832; v2_completo = plan_k_v2 | sí | 412cfd5/3c1948e/c01f606; cmp idénticos | ok |
| Recuentos [PROBE-*]; «pp tras conjunto activo»; caras fijas en 342451 | 0/550/550/550; 3211/1056 frente a 2971/571; 37 frente a 34 | idénticos | ok |
| §6 del plan staged, línea 101 (líneas 575-578, 627-632) | «sigue diciendo 'medida solo en k1pa_342'» | dice «medida en k1_342 (v1) y en k1pa_342» | **objeción (O1)** |
| git diff --cached --stat (nota de fuente, línea 608) | acople-pv 64, PLAN_K 12 | 75 y 35 | **objeción (O1)** |
| Menciones de D2.2/pc_limiter_faces en el índice (línea 608) | 9 | 2 | **objeción (O1)** |
| Qué cubre la entrada «Plan K CERRADO» (líneas 535-540, 590-605, 617-622) | regla de aborto §4, C-035-C-039, SALVEDAD 4/4, 47 frente a 85 %, firma del audit | no están: la entrada (acople-pv:618-645) solo recoge veredictos y lo abierto | **objeción (O1)** |
| Sección «Pendiente del coordinador» | citada 5 veces | no existe | **objeción (O1)** |

**Equidad de la comparación.** Los brazos de 342 s comparten reinicio (`diag_p342a/eaf3d_00342450.h5`), t_final, 12 ranks (2×3×2) y config. Solo difieren `pc_ai_tol`, la ventana de sonda de k1_342 y la sonda ausente en la base, tal como dice el reporte. El veredicto de C-025 coincide literalmente con su criterio pre-registrado y no hay enmienda.

### 2. Objeciones

1. **O1 (bloqueante).** El historial de ciclos describe el diff staged en un estado que ya no existe.
   - `research/ws/WS-K1/report.md:575-578,627-632` afirma que `docs/PLAN_K_limitador_en_poisson.md:101` dice «medida solo en k1pa_342». El archivo dice «medida en k1_342 (v1) y en k1pa_342». El propio reporte lo reconoce en la línea 706.
   - `report.md:608` da «acople-pv 64, PLAN_K 12» y «9 en el índice». Lo recalculado da 75, 35 y 2.
   - `report.md:535-540,590-605,617-622` atribuye a la entrada «Plan K CERRADO» contenidos que el ciclo 9 retiró.
   - Cinco remisiones a «Pendiente del coordinador» apuntan a una sección inexistente.

   Para levantarla: pasar esos bloques a tiempo pasado (corregido en el ciclo N y retirado en el 9), eliminar las afirmaciones falsas, recalcular las cifras de la línea 608 sobre el diff final y redirigir «Pendiente del coordinador» a la sección «Experimentos que este reporte nombra y que no existen».
2. **O2 (no bloqueante).** `report.md:401-403` cita `dev-history/2026-10-07:424-425`. Esa línea habla de las mejoras de D2.2b, D2.4, D2.5 y D2.6, no del empeoramiento de D2.2. Aplicarla a D2.2 es una lectura del redactor y debería marcarse como tal.
3. **O3 (no bloqueante).** `report.md:98-103` llama «artefacto del reinicio» a los pasos 342451-342452 y cita C-290, que es fallida y declara sus lecturas «sin valor de veredicto». Conviene marcarlo así. No afecta al veredicto.
4. **O4 (no bloqueante, constancia).** El fallo de (c) depende de 6 frente a 3.55 pasos, en una sola trayectoria (k1pb_342 es casi idéntica) y en una ventana que arranca justo tras el reinicio. El reporte ya lo declara y limita la conclusión a la letra del criterio. No requiere cambios.

VEREDICTO: rechaza
