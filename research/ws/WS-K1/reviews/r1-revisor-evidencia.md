## Revisión de evidencia: WS-K1, ronda 1

Revisión ciega: no leí `reviews/` de otros revisores. Todo fue solo lectura: `ledger.py show/check`, `regime2.py`, `cell_series.py`, `plank_conv.py`, `submerged_bed.py` (comprobé antes que no escriben), h5py y csv, `git show`, `grep` y `sed`.

### 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| H1: convergencia de k1_342 con tol 1e-6 / 1e-3 | 205/205 sin converger, 8 iteraciones / 0/205 | 205/205 (100 %), it_medio 8.00 / 0/205 | ok |
| H1: \|p\| sonda ≥ 20 kPa desde 342518 a 342560; máximo | máx 69 967.7 Pa en 342539; 69.1 kPa en 342540 | 342518 (342517 = 18 484); 69 967.7 en 342539; 69 103.1 en 342540 | ok |
| H1: osc2 de k1_342 frente a la base | 342 / 51.8 kPa | 342.3 / 51 835.2 | ok |
| C-011: criterio anterior a la corrida | texto de §4 del plan | c298555 16:48:17, antes de k1_342 (16:52); ledger a posteriori | ok (O3) |
| C-025 pre-registrada antes de k1b_342 | sí | 17:32:08 frente a la corrida a 17:58:19; sin enmiendas | ok |
| H1b (a): osc2 en 342500–342560 | 885.7 | 885.7 | ok |
| H1b (b): grad_hid_max | 70.57 | 70.57 | ok |
| H1b (c): p>100k / cent_pg | 5.4 % / 2.7 % (3/111 = 2.703 %) | 5.4 / 2.7 (3/111) | ok |
| H1b (d): sin converger con tol 1e-3 | 0.9 % | 5/550 = 0.9 % | ok |
| H1b (e): vol_lim medio | 2.46e-3 | 2.4596e-3 | ok |
| Fracción de \|d2p\| > 1000 en 342500–342560 (base / k1 / k1b / k1pa) | 85 / 22 / 47 / 22 % | 0.847 / 0.220 / 0.475 / 0.220 | ok |
| p75 / máx de \|d2p\| | 112k / 730 / 14 559 / 721; 333.8k / 3729 / 218 858 / 3728 | idénticos | ok |
| Tramo 342520–342537 (16 puntos) | base med 48.1k, p75 52.6k; k1b 40.7k, 55.2k | 48 142 / 52 619; 40 716 / 55 160 | ok |
| Tramo 342538–342560 (21 puntos) | k1b 14 %, base 100 % | 0.143 / 1.000 | ok |
| Primer \|d2p\| > 1/5/10/20 kPa | base 509/515/518/520; k1b 513/519/522/525 | idénticos | ok |
| Pico de p | 413.4 kPa en 342535; 410.0 en 342534 | 413 369 / 409 995 | ok |
| Recuento p_max > 1e5 (audit) | base 7, k1b y k1pb 6, k1 y k1pa 2 | idénticos, mismos pasos | ok |
| Sin los pasos del reinicio | 4/109 frente a 3.49 permitidos | 4/109; 3.488 | ok |
| p_max en 342450 / 342451 / 342452 | 9.52e4 / 8.045e5 y 8.030e5 / 1.6401e5–1.6404e5 | 9.522e4 / 8.0451e5 y 8.0298e5 / 164 006–164 035 | ok |
| k1b después del pico (23 pasos) | 27.4–36.5 kPa | 27 411.7 (342544) – 36 507.4 (342539) | ok |
| P-a y v1: osc2 / ag_min en 342510–342533 | 209.5 / 0.01834 | 209.5 / 0.01834 (k1 y k1pa) | ok |
| P-b: osc2 / ag_min; sin converger | 6876 / 0.01500; 99.8 % | 6876.0 / 0.01500; 549/550 | ok |
| k1b en 342510–342533 | 6874 / 0.01500 | 6874.3 / 0.01500 | ok |
| max\|Δp\| sonda k1−k1pa / k1b−k1pb | 17 / 96 Pa | 17.27 / 95.85 | ok |
| Primera divergencia > 100 Pa | 342506 en las dos parejas | 342506 / 342506 | ok |
| Firma de audit k1b/k1pb − k1_342 (342451–342460) | vol_lim −4.48e-7 (−3.8e-8 a −4.5e-6); vol_unl negativo desde 342453 | idénticos (−6.29e-8 en 342455, −1.45e-7 en 342458) | ok |
| Firma k1pa_342 − k1_342 | vol_lim +1.3e-9; vol_unl −2.3e-11 y luego positivo hasta +1.5e-8; \|Δp_max\| < 1.4 Pa | +1.35e-9; −2.29e-11 / +1.51e-8; 1.31 | ok |
| Firma n12 − k1_340 (340001–340010) | vol_lim +7.1e-9 a +3.8e-7; vol_unl +5.5e-10 a +2.5e-8, −4.1e-9 en 340007; Δp_max −862 en 340010 | idénticos | ok |
| n14/n15 − n12; base − judge | 3e-17 a 2e-14; ≤ 5.3e-15 en base_n15, 340010 | 2.9e-17 a 1.8e-14; 5.3e-15 en 340010 | ok |
| p_max de k1_342 y k1_340 en los 10 primeros pasos | 4.9e4–8.0e5 / 2.1e4–2.9e4 | 4.91e4–8.03e5 / 2.14e4–2.92e4 | ok |
| regime2 en 340–345.5 s, cent_pg (k1_340 / n12 / n14 / n15) | 0.5/1.1/0.7; 0.4/0.3/0.1; 0.2/0.2/0.3; 0.1/0.2/12.8 | idénticos | ok |
| regime2 p>100k, base y K, ventanas 340–345.5 y 344–345.3 | (ver reporte) | idénticos en las 28 celdas | ok |
| C-027: pmax de k1_340 | 4.51e5 | 4.505e5 (345520) | ok |
| dm_liq / dE_liq en [340, 345.3) | 392.4–392.6 frente a 398.6–400.6 kg; 4.523–4.524e8 frente a 4.561–4.573e8 | idénticos; suma con dm_sol = 0 | ok |
| Snapshots 345500: V_liq lecho / total / centroide z | 0.1540–0.1547 frente a 0.1575–0.1589; 1.0732 frente a 1.0741–1.0747; 0.2255–0.2257 frente a 0.2249–0.2250 | idénticos | ok |
| Celdas en el piso (umbrales 0.016 / 0.02 / 0.05) | base 117,132,150 / 121,133,155; K 133,143,162 / 130,145,165 / 142,155,169; k1_340 135/144/153 | idénticos | ok |
| dense_340_n14, celda (1,59,9) | 74.5 / 94.0 / 42.6 / 108.0 / 42.9 / 636.0 kPa; 48.8 kPa en otra celda en 342530 | idénticos | ok |
| Recuentos [PROBE-*] y «pp tras conjunto activo» | 205/41, 2214/41, 410/41; 550, 5940, 1650/110; AI 2971/3211; pmax 571/1056; 0/550/550/550 | idénticos | ok |
| [PROBE-AI] del paso 342451 | 37 caras (k1pa) frente a 34 (k1b) | 37 / 34 | ok |
| C-030 | 242 / 45 / 73 | 242 / 45 / 73 (submerged_bed.py) | ok |
| Estado de las afirmaciones de WS-K1 | 16: 4 refutadas, 9 fallidas, 3 soportadas | idéntico; `ledger.py check` OK | ok |
| Git y parches | e250687; 7 commits en src; apply falla en :733; index = blobs de 1bc9832; parches idénticos (cmp); numstat 35/49 y 17/18; 0 archivos con pc_alpha_implicit | idénticos | ok |
| Mensajes de commit («bit a bit», «error 0», etc.); 79dc27b toca mod_pressure_3d (32 líneas) | (ver reporte) | idénticos | ok |
| Topología | 12 ranks 2×3×2; mismo reinicio | k1_340, n12 y k1*_342: 12 (2×3×2); restart_file común | ok |
| Cita de WS-K2 a acople-pv.md:659–666 | «ya no coincide» (630) y «vuelve a ser válida» (644) | el índice tiene menos de 657 líneas; la guía está en la 648 | objeción O1 |

### 2. Juicio frente al criterio pre-registrado

- **C-025 (H1b).** Fallan (b) y (c) por la letra: grad_hid_max 70.57 > 3 y p>100k 5.4 % > 3.2 %. Además cent_pg = 3/111 = 2.703 % > 2.7, que el reporte señala bien como fallo literal que C-028 no aplicó. No hay enmiendas. El estado `refutada` coincide con el criterio. El reporte no reinterpreta el criterio: marca como «lectura sin valor de veredicto» todo lo que va más allá (ciclo por tramos, regla de aborto, lectura estructural).
- **C-011 (H1).** Refutada por convergencia (con la salvedad de la tolerancia de v1, declarada) y por |p| < 20 kPa. Es coherente con C-012.
- **G1.** No cumplida. El estado `fallido` es acorde con README («Estados de un workstream»).
- **Justicia de la comparación.** Todas las corridas parten del mismo reinicio (diag_p342a/342450), usan la misma ventana (342.45–342.56 s, 111 filas) y 12 ranks 2×3×2. El reporte declara las limitaciones de muestra: P-a/P-b en 24 pasos, 1 trayectoria contra 1, y los dos pasos contaminados por el reinicio.

### 3. Objeciones (ninguna bloqueante)

1. **O1. Contradicción interna sobre la cita de WS-K2** (`research/ws/WS-K1/report.md`:630–631 frente a :644–645). Por número de línea la cita sigue rota: `git show :.claude/rules/acople-pv.md | sed -n 657,667p` sale vacío y la guía está en la 648. Se levanta corrigiendo la frase de la línea 644.
2. **O2. Binario de k1b_342 no verificable** (`campaigns/b1/k1b_342/run.log`: sin hash ni commit; en `campaigns/bin` no hay k1b). C-025 exige «binario de src post-auditoria». El reporte lo declara en Incertidumbre. Se levanta con la prueba bit a bit que el reporte nombra (Experimentos 1). No bloquea un cierre `fallido` sin adopción de código.
3. **O3. C-011 se registró en el ledger a posteriori** (ts 17:31:51, después de k1_342). El criterio está en c298555:docs/PLAN_K_limitador_en_poisson.md:69–73, de las 16:48, antes de la corrida, así que es válido; conviene decirlo en el punto 1.

VEREDICTO: aprueba