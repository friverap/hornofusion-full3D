# Revisión de evidencia: WS-K1, ronda 1

Revisión ciega: no leí research/ws/WS-K1/reviews/. Todo se hizo en solo lectura (python3, h5py y csv sobre archivos existentes, `cell_series.py`, `regime2.py`, `plank_conv.py`, `submerged_bed.py`, `ledger.py show/open/check`, `git show/log`). El hunk del parche lo comprobé emulando la aplicación en python sobre `git show HEAD:src/...`.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| k1_342: \|p\| sonda ≥ 20 kPa en 342518-342560 | sí | 342518 = 20 966.9 Pa; ninguno por debajo después | ok |
| k1_342: p_max sonda | 69 967.7 Pa en 342539 | 69 967.7 en 342539 | ok |
| El 69.1 kPa de C-012 es el paso 342540 | 69.1 | 69 103.1 | ok |
| osc2 base → k1 (342500-342560) | 51.8 kPa → 342 Pa | 51 835.2 → 342.3 | ok |
| Columna encima de la sonda ≈ 6 kPa | ~6 kPa {C-013} | sale del registro; p(342500) = 5.85 kPa, coherente | ok (registro) |
| H1b (b) grad_hid_max | 70.6 | 70.57 | ok |
| H1b (c) p>100k base / k1b (regime2) | 6.3 / 5.4 %, n = 111 | 6.3 / 5.4, n = 111 | ok |
| Conteo p_max > 1e5: base / k1b | 7 / 6 (pasos listados) | 7 / 6, mismos pasos | ok |
| Sin 342451/452 | k1b 4/109 (3.7 %), 3.49 permitidos; base 5/109 | 4/109 = 3.67 %; 0.032·109 = 3.488; base 5 | ok |
| 3.2 % de 111 | 3.55 | 3.552 | ok |
| 342451/452 «iguales en todos los brazos» | iguales | NO: 8.0451e5 frente a 8.0298e5; 1.64008e5 frente a 1.6400-1.6404e5 | objeción O3 |
| Pico de k1b | 410 kPa en 342.534 s | 409 994.6 en 342534 | ok |
| k1b, métrica C-036 (342510-342533) | 6874 Pa / 0.01500 | 6874.3 / 0.01500 | ok |
| (d) k1b sin converger, tol 1e-3 | 0.9 % | 5/550 = 0.9 % | ok |
| k1b tras el pico | 27-36 kPa | 27.4-36.5 kPa (342538-342560) | ok |
| P-a osc2 / ag_min | 209.5 / 0.01834 | 209.5 / 0.01834 | ok |
| P-b osc2 | 6876 | 6876.0 / 0.01500 | ok |
| P-a cambia factor y unl_on | dos cambios | pa_sin_A2.patch: `fac` = 1 y `unl_on = .false.` | ok |
| Celdas de lecho sumergidas (C-030) | 242 / 45 / 73 | 242 / 45 / 73 | ok |
| C-041, 344-345.5 s, cent_pg | K 0.1/0.3/12.8; base 6.7-9.5; centinela 2.00e6 | 0.1/0.3/12.8; 6.7/7.2/9.5; 2.00e6 | ok |
| «k1_340 mejor 340-346 s registrado» | afirmado | k1pa_340_n12 es mejor en cent_pg: 0.4/0.3/0.1 frente a 0.5/1.1/0.7 | objeción O5 |
| Raíces WS-K1 | 16: 4 refutadas, 9 fallidas, 3 soportadas | idéntico; `ledger check` OK | ok |
| src sin Plan K | 0 archivos | 0 (disco y HEAD) | ok |
| Commits en src desde 1bc9832 | 7 (hashes listados) | 7, mismos hashes; tocan mod_pressure_3d y mod_continuity | ok |
| Mensajes de commit «bit a bit / golden» | citados | leídos con `git show`, coinciden | ok (no reverificado numéricamente, declarado) |
| plan_k_v2.patch falla en mod_pressure_3d.f90:733 | falla | el hunk -733 no casa en HEAD; sí en 1bc9832 | ok |
| Config. de P-a y P-b solo difieren en pc_ai_tol | sí | sí (y output_dir); mismo reinicio y t_final | ok |
| Binario de cada corrida | no verificable | no verificable (no hay id en run.log ni en campaigns/bin) | objeción O7 (declarada) |
| Citas de documentos | PLAN_K 72-73, reevaluacion 82-85, research.md 15-18 | coinciden | ok |
| acople-pv.md VIGENCIA | 266-273 | 266-274 | objeción O6 |
| «Plan K CERRADO» tras «H0», y §6 de PLAN_K | sí | líneas 618 / 611; §6 en la línea 86 | ok |
| `ledger.py open`: solo las 5 últimas refutadas | sí | sí, ninguna de Plan K | ok |

**Justicia de la comparación.** Todas las corridas k1* y la base diag_p342b arrancan de `diag_p342a/eaf3d_00342450.h5` con t_final 342.56, la misma descomposición MPI y la misma config.dat, salvo la clave probada y la sonda. Cada pre-registro es anterior a su corrida (archivos de las corridas frente a `ts`): c298555 16:48 < k1_342 16:52; C-025 17:32 < k1b 17:58; C-035/036 18:12:16 < k1pa/pb 18:12:40. La muestra es corta: 111 pasos en total y 24 en la métrica de ciclo. Dato adicional: el cent_pg de 2.7 % del inciso (c) son exactamente los pasos 342451-342453 (u_gas = 300), es decir, el mismo artefacto del reinicio.

## 2. Objeciones

1. **O1 (bloqueante).** `research/ws/WS-K1/report.md`, punto 4: «La refutación descansa en (c) y en el retorno del ciclo, no en (b)». Reinterpreta en prosa el criterio de C-025: descarta (b) sin ningún evento registrado y añade como base algo que no es un inciso del criterio. El inciso de ciclo que sí está pre-registrado, (a), **cumple**: `campaigns/b1/k1b_342: osc2(342500-342560) = 885.7 Pa ≤ 1000`, y el reporte no lo dice. Según la letra, H1b queda refutada por (b) 70.57 > 3 y por (c) 5.4 > 3.2. Para levantarla: redactar según la letra (b y c fallan; a, d y e cumplen). El argumento de que (b) está mal planteado va en una nota con `--ref C-028` o se rotula como «lectura fuera del criterio, sin valor de veredicto».
2. **O2.** Punto 4 y R2: «Por la letra se disparó» la regla de aborto. Esa regla no tiene umbral numérico y está en la viñeta de H1. El PRESENTE de k1b es circular: k1b (6874 Pa/0.01500) forma parte de la calibración de C-036. Para levantarla: cambiar a «a juicio del coordinador», declarar la calibración y aplicar lo mismo en `.claude/rules/acople-pv.md:621-624` y en `docs/PLAN_K_limitador_en_poisson.md:94-95`.
3. **O3.** Punto 4: «iguales en todos los brazos, {C-290}» es falso. `diag_p342b/audit.csv:342451 = 8.0451e5` frente a `k1b_342/audit.csv:342451 = 8.0298e5`, y C-290 no habla de los brazos k1*. Para levantarla: escribir «presentes (> 1e5) en todos los brazos».
4. **O4.** Nota de procedencia del punto 4: la ventana «342.45<t<=342.56» da 110 filas; regime2 usa `t0 <= t < t1` (111 filas). Las cifras no cambian. Para levantarla: corregir la ventana en la nota.
5. **O5.** Incertidumbre: «k1_340 es el mejor 340-346 s registrado» no tiene procedencia, y `k1pa_340_n12` tiene menor cent_pg en 340-345.5 (0.4/0.3/0.1 frente a 0.5/1.1/0.7). Para levantarla: matizar o añadir el comando que lo respalde.
6. **O6.** `.claude/rules/acople-pv.md`: el párrafo VIGENCIA ocupa 266-274, no 266-273.
7. **O7 (no verificable, ya declarada).** Qué binario usó cada corrida k1*_342 (C-036 exige `eaf3d_k1b_opt`), y la invariancia numérica de los 7 commits. De esto dependen C-037/C-038/C-039. La salvedad debe seguir en el reporte.

La conclusión de cierre (G1 no cumplida; `fallido`) sí se sostiene por la letra: C-012 refuta H1 (convergencia 0 % y \|p\| 69 kPa > 20) y C-028 refuta H1b (incisos b y c). O1 bloquea porque el reporte cambia en prosa la base de esa refutación; no bloquea por el resultado.

VEREDICTO: rechaza