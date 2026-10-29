# WS-K1, ronda 1: revisor de evidencia

Revisé research/ws/WS-K1/report.md contra research/ledger.jsonl (`ledger.py show`/`open`/`check`) y recalculé cada número desde los archivos de campaigns/b1. No ejecuté corridas ni binarios. Usé `cell_series.py`, `plank_conv.py` y `submerged_bed.py` después de comprobar que solo leen; también `regime2.py`, h5py/csv y `git show`/`log`/`apply --check`. No leí las revisiones de los otros revisores.

## Pre-registro y comparación justa

- **C-011 (H1).** El criterio sale del plan en c298555 (22-oct 16:48). k1_342 se corrió después: config.dat 16:52, primer snapshot 16:53.
- **C-025 (H1b).** Registrada a las 17:32. k1b_342 se corrió después (config 17:58). No tiene enmiendas.
- **C-035 y C-036.** Registradas a las 18:12:16. k1pa_342 y k1pb_342 se corrieron después (config 18:12:40).
- **Brazos de 342 s.** La base diag_p342b y k1, k1b, k1pa y k1pb comparten reinicio (diag_p342a/eaf3d_00342450.h5), t_final 342.56, 12 procesos MPI, sonda 10,60,2 y output_freq 1. Los diff de config.dat solo difieren en pc_alpha_implicit, pc_ai_tol y la ventana de la sonda.
- **Veredictos.**
  - C-012: con la letra de C-011 falla la convergencia (0 %) y falla |p| < 20 kPa.
  - C-028: con la letra de C-025 fallan (b) 70.57 > 3 y (c) 5.4 > 3.2 %. Las lecturas post hoc del reporte están marcadas «sin valor de veredicto». No reinterpreta ningún criterio para aprobar.
- **Muestra.** Son 111 pasos y el margen de (c) es pequeño. El reporte lo declara y lo cuantifica: sin los dos pasos del artefacto de reinicio quedan 4/109 frente a 3.49 permitidos, así que (c) sigue fallando.

## Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| k1_342: convergencia | 0 % | 205/205 sin converger | ok |
| k1_342: \|p\| ≥ 20 kPa en 342518–342560 | sí | 342518 = 20966.9 y todos los siguientes ≥ 39.4 kPa | ok |
| k1_342: p_max sonda | 69967.7 en 342539; 69.1 kPa = 342540 | 69967.7 en 342539; 69103.1 en 342540 | ok |
| osc2 base / k1 (342500–560) | 51.8 kPa / 342 Pa | 51835.2 / 342.3 | ok |
| Columna sobre la sonda (C-013) | ~6 kPa | ≈ 6.2 kPa (h5py, k1_342 paso 342539) | ok |
| k1b (a) osc2 | 885.7 | 885.7 | ok |
| k1b (b) grad_hid_max | 70.57 | 70.57 | ok |
| k1b (c) cent_pg / p>100k | 2.7 / 5.4 % (base 2.7 / 6.3) | 2.7 / 5.4 (2.7 / 6.3) | ok |
| k1b (d) sin converger | 0.9 % | 5/550 = 0.9 % | ok |
| k1b (e) vol_lim | 2.46e-3 | 2.4596e-3 | ok |
| Pasos con p_max > 1e5 (base / k1b, k1pb / k1, k1pa) | 7 / 6 / 2 con los pasos listados | idénticos | ok |
| 342450 / 342451 / 342452 | 9.52e4 / 8.045e5 frente a 8.030e5 / 1.6401–1.6404e5 | 9.522e4 / 8.0451e5 y 8.0298e5 / 164006–164035 | ok |
| Permitidos en (c) | 3.55; 3.49 | 3.552; 3.488 | ok |
| Sin 451–452: k1b | 4/109 (3.7 %) | 3.67 % | ok |
| k1b 342510–533: osc2 / ag_min | 6874 / 0.01500 | 6874.3 / 0.01500 | ok |
| Base 342510–533 | 23362 | 23362.5 (cociente 3.40) | ok |
| Pico de k1b | 410 kPa en 342534 | 409994.6 en 342534 | ok |
| dense_340_n14, max\|p\| en (1,59,9) | 74.5, 94.0, 42.6, 108.0, 42.9, 636.0; 342530 en otra celda (48.8) | idénticos; reinicio desde judge_otp_280/340000 | ok |
| P-a: osc2 / ag_min | 209.5 / 0.01834 | 209.5 / 0.01834 | ok |
| P-b: osc2 | 6876 | 6876.0; 549/550 sin converger | ok |
| C-030: celdas de lecho sumergidas | 242 / 45 / 73 | 242 / 45 / 73 | ok |
| C-033: k1b tras el pico | 27–36 kPa | 27.4–36.5 kPa | ok |
| cent_pg de k1_340 | 0.5 / 1.1 / 0.7 | 0.5 / 1.1 / 0.7 | ok |
| cent_pg de k1pa n12 / n14 / n15 | 0.4/0.3/0.1; 0.2/0.2/0.3; 0.1/0.2/12.8 | idénticos; pmax de n15 = 2.00e6 | ok |
| cent_pg de la base, 344–345.5 s | 6.7–9.5 | 6.7 / 7.2 / 9.5 | ok |
| «solo k1_340 llega a 346 s» (nota de procedencia) | sí | f231_340 y npc3_340 también llegan | objeción O2 |
| Holgura de v1 | ~0.4 % | sin cita; ag_min 0.01834 frente a 0.0150 da 0.33 puntos | objeción O3 |
| Variación de vol_lim | −0.8 % | −0.853 % | objeción O1 |
| vol_unlinked | 2.057e-3 en todos | 2.057e-3 | ok |
| Afirmaciones raíz de WS-K1 | 16: refutada 4, fallida 9, soportada 3 | idéntico; `ledger check` OK | ok |
| C-065..C-073 | fallida, motivo «usuario aprobó 2026-10-23» | idéntico | ok |
| Archivos de src con pc_alpha_implicit | 0 | 0 | ok |
| Commits en src desde 1bc9832 | 7, con hashes | 7, mismos hashes; tocan mod_pressure_3d y mod_continuity; todos declaran «sin cambio numérico» | ok |
| `git apply --check` | falla en mod_pressure_3d.f90:733 | falla en ese punto | ok |
| Diferencias de config P-a / P-b | solo pc_ai_tol | solo pc_ai_tol (y output_dir) | ok |
| Conteos PROBE (k1, k1b, k1pa, k1pb) | 1650/550/5940 frente a 410/205/2214; AI 3211 y 2971; pmax 1056 y 571; 37 frente a 34 caras | idénticos | ok |
| Líneas citadas de plan, reevaluación y reglas | plan 72–73, reev. 82–85, research.md 15–18, acople-pv 266–274, 536–546, 560–566, 611–617 | el contenido coincide | ok |
| Entrada «Plan K CERRADO» y §6 del plan | existen con ese contenido | existen | ok |

## Objeciones (ninguna bloqueante)

1. **O1. Variación de vol_lim.** Es −0.853 % (2.480737e-3 → 2.459573e-3), no −0.8 %. Escribir −0.85 % o −0.9 %.
2. **O2. Nota de procedencia «solo k1_340 llega a 346 s».** Es falsa tal como está escrita: `campaigns/b1/f231_340` y `npc3_340` terminan en t=346.00. La afirmación solo vale entre los brazos con pc_alpha_implicit=true. Hay que corregir la fuente o el texto.
3. **O3. «~0.4 % de holgura».** No cita nada; el dato viene de C-032 (y reevaluacion.md:76). Lo medido es ag_min 0.01834 frente a 0.0150, es decir, 0.33 puntos.
4. **O4. «k1pa ya pasó esa ventana».** Con la letra de C-025, k1pa fallaría (b): grad_hid_max = 10.52 > 3 (`cell_series.py campaigns/b1/k1pa_342 --cell 10,60,2 --steps 342500,342560`). Lo que pasó es P-a (C-037), además de p>100k 1.8 ≤ 3.2. Hay que precisarlo, también en acople-pv.md:654-655.
5. **O5. Binario de k1b_342 no verificable.** C-028 depende de que k1b_342 usara el binario post-auditoría, y run.log no lo identifica. El reporte solo explicita esa dependencia para C-037/C-038/C-039. Indicio a favor: k1pb reproduce a k1b (osc2 889.7 frente a 885.7, grad 70.57, p>100k 5.4). No cambia la conclusión «G1 no cumplida», pero conviene añadir una línea en Incertidumbre.
6. **O6. Cierre de C-064 sin citar.** Ese cierre en WS-K12 es C-294 y no está citado.

## Conclusión

Todos los números que sostienen los veredictos (C-012 y C-028) y el cierre se reproducen. Los veredictos siguen la letra de los criterios pre-registrados y no tienen enmiendas. La comparación usa el mismo reinicio, la misma ventana y los mismos ranks. Las objeciones son de precisión y de citas y no cambian la conclusión «G1 no cumplida; estado fallido».

VEREDICTO: aprueba