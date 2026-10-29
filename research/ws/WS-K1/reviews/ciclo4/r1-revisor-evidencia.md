## WS-K1, ronda 1: revisión de evidencia

**Resultado: rechazo el reporte por dos objeciones bloqueantes (O1 y O2).** Ninguna toca la conclusión central: G1 no se cumplió porque H1 y H1b están refutadas por la letra de sus criterios.

**Qué comprobé y cómo.** Solo lectura: `cell_series.py`, `regime2.py`, `plank_conv.py` y `submerged_bed.py`, h5py y csv sobre las corridas existentes, `ledger.py show/open/check`, `git show/log/rev-parse`, `git apply --check`, `cmp` y `sed`.

**Pre-registro.** Los criterios se fijaron antes de las corridas, sin enmiendas:
- **H1:** el criterio está en el commit c298555, de las 16:48 del 22-oct. k1_342 arrancó a las 16:52.
- **H1b:** C-025 se registró a las 17:32. k1b_342 arrancó a las 17:58.
- **P-a y P-b:** C-035 y C-036 se registraron a las 18:12:16. k1pa arrancó a las 18:12:40.
- **Enmiendas:** ni C-011 ni C-025 tienen enmiendas.

**Comparabilidad entre brazos.** Comprobada con `diff`:
- Todos los brazos parten del mismo reinicio (`diag_p342a/eaf3d_00342450.h5`) y llegan al mismo t_final 342.56.
- k1b, k1pa y k1pb comparten configuración; entre P-a y P-b solo cambia `pc_ai_tol`.
- La base `diag_p342b` difiere de k1b solo en las claves de Plan K y de sonda.

### 1. Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| k1_342: \|p\| ≥ 20 kPa en 342518–342560 | sí | 20966.9 Pa (342518) … 39401.6 Pa (342560) | ok |
| k1_342: p_max de la sonda | 69967.7 Pa en 342539; 69.1 kPa en 342540 | 69967.7 / 69103.1 | ok |
| osc2 base / k1 (342500–560) | 51.8 kPa / 342 Pa | 51835.2 / 342.3 | ok |
| H1: convergencia | 0 % | 205/205 en el tope (tol 1e-6, it 8); 0 % sin converger con --tol 1e-3 | ok (O5) |
| C-025 (a) osc2 k1b | 885.7 ≤ 1000 | 885.7 | ok |
| C-025 (b) grad_hid_max | 70.57 > 3 | 70.57 | ok (FALLA) |
| C-025 (c) cent_pg / p>100k | 2.7 / 5.4 (> 3.2) | 2.7 / 5.4; base 2.7 / 6.3 | ok (FALLA) |
| C-025 (d) sin converger (tol 1e-3) | 0.9 % | 5/550 = 0.9 % | ok |
| C-025 (e) vol_lim medio | 2.46e-3 ≤ 2.605e-3 | 2.4596e-3; base 2.4807e-3 | ok |
| Veredicto de H1b frente al criterio | refutada | (b) y (c) fallan por la letra | ok |
| \|d2p\| > 1000 Pa (59 puntos interiores) | k1b 28 (47 %); k1 y k1pa 13 (22 %); base 50 (85 %) | 28 / 13 / 13 / 50 | ok |
| p75 / máximo de \|d2p\| | k1b 14.6 / 219 kPa; k1 0.73; k1pa 0.72 | 14559 / 218858; 730; 721 | ok |
| p>100k: pasos en la ventana | 6 de 111; 3.55 permitidos; base 7 | 6, 111, 3.552, 7 | ok |
| Pasos > 1e5 por brazo | base 7, k1b/k1pb 6, k1/k1pa 2 (con sus pasos) | idénticos | ok |
| 342451 / 342452 | 8.045e5 base, 8.030e5 resto / 1.6401–1.6404e5 | 804512, 802982–802984 / 164006–164035 | ok |
| Sin 342451–342452 | k1b 4/109 (3.7 %), 3.49 permitidos; base 5/109 | 4, 3.67 %, 3.488, 5 | ok |
| Paso 342450 | 9.52e4 | 95224.7 | ok |
| Ciclo k1b 342510–533 | osc2 6874, ag_min 0.01500 | 6874.3 / 0.01500 | ok |
| Base 342510–533; cociente | 23362; 3.4× | 23362.5; 3.40 | ok |
| Pico de k1b | 410 kPa en 342534 | 409994.6 | ok |
| Liso tras el pico {C-033} | 27–36 kPa | 27.41–36.51 kPa | objeción menor (O4) |
| dense_340_n14: celda (1,59,9) | 74.5, 94.0, 42.6, 108.0, 42.9, 636.0 kPa; 342530 en otra celda, 48.8 | 74459, 94031, 42646, 107963, 42878, 635970; 342530: 48838 en (1,19,7) | ok |
| dense_340_n14: reinicio | judge_otp_280/eaf3d_00340000.h5 | ídem; sin pc_alpha_implicit | ok |
| P-a: osc2 / ag_min | 209.5 / 0.01834 | 209.5 / 0.01834 | ok |
| P-b: osc2 / sin converger | 6876 / 99.8 % | 6876.0 / 549/550 | ok |
| k1pa: p>100k | 1.8 % | 1.8 | ok |
| P-a cambia dos cosas | factor 1 y `unl_on = .false.` | confirmado en pa_sin_A2.patch:8,18,23 | ok |
| C-030: celdas sumergidas | 242 / 45 / 73 | 242 / 45 / 73 | ok |
| cent_pg 340–345.5 (3 ventanas) | k1_340 0.5/1.1/0.7; n12 0.4/0.3/0.1; n14 0.2/0.2/0.3; n15 0.1/0.2/12.8; base 6.7–9.5 | idénticos | ok |
| k1pa_340_n15 (C-311) | 183 pasos seguidos ≥ 1 MPa; 122 en 2 MPa | 183 seguidos; 122 | ok |
| diag_k15_k_off | 1.551e5, luego 2.000e6 → 1.797e6; 10 filas ≥ 1e6 | 155132; 2.0e6 → 1796927; 10 | ok |
| vol_lim / vol_unlinked medios | 2.481e-3 frente a 2.460e-3 (−0.8 %); 2.057e-3 | 2.4807 frente a 2.4596–2.4600 (−0.83 %); 2.0568–2.0573 | ok |
| Afirmaciones raíz WS-K1 | 16: 4 refutadas, 9 fallidas, 3 soportadas | idéntico; `check` OK; 0 abiertas | ok |
| C-065 a C-073 | fallida, con su motivo | fallida, motivo literal | ok |
| C-064 cerrada sin verificar | sí | fallida por C-294 | ok |
| `src/` sin Plan K | 0 archivos | 0 en disco y 0 en HEAD | ok |
| Commits en `src/` desde 1bc9832 | 7 (lista) | 7, misma lista | ok |
| Mensajes de commit: numérica sin cambio | las 4 frases citadas | 79dc27b dice «sin cambio numérico en las columnas físicas» | objeción menor (O3) |
| Parches | índices 412cfd5/3c1948e/c01f606; v2_completo idéntico byte a byte; `apply` falla en :733 | confirmado | ok |
| Líneas citadas de plan, reglas y reevaluación | plan 72–73; acople-pv 266–274, 536–546, 560–566, 611–617, 622–624, 644–647; reevaluacion 82–85; research.md 15–18 | contenido coincide | ok |
| Recuentos de sonda en run.log | 1650/550/5940 frente a 410/205/2214 (k1) | totales ok, pero las ventanas de sonda difieren (41 frente a 110 pasos) | objeción (O2) |
| Brazo K del juez = v2 sin A2 | afirmado como hecho | no verificable en disco | objeción (O1) |

### 2. Objeciones

**O1 (bloqueante).** El punto 7 afirma como hecho que el brazo K del juez fue «v2 sin A2». La sección Incertidumbre lo repite en dos frases:
- «k1pa (v2 sin A2) es el brazo K de C-041»;
- «k1pa, que tenía holgura, falló el juez».

Nada de esto se puede verificar en disco:
- `campaigns/b1/k1pa_340_n1{2,4,5}/run.log` no nombra el ejecutable ni el commit, y no tiene líneas `[PROBE-*]`.
- `config.dat` solo trae `pc_alpha_implicit = true` y `pc_ai_tol = 1.0e-3`.
- En `campaigns/bin` no existe `eaf3d_k1pa_opt`.

Además, `.claude/rules/acople-pv.md:643-645` (la entrada que este mismo cierre añadió) dice «el binario no se identifica en los run.log, así que v2 con o sin A2 no se distingue». El reporte se contradice.

*Para levantarla:* redactarlo como «según C-040; binario no verificable (v2 con o sin A2)» y condicionar a eso «la holgura falló el juez».

**O2 (bloqueante).** Los recuentos de sonda se comparan entre ventanas distintas:
- `campaigns/b1/k1_342/config.dat` tiene `probe_step_from = 342500` y `probe_step_to = 342540` (41 pasos).
- k1b, k1pa y k1pb tienen 342450–342560 (110 pasos con sonda).

Normalizado por paso:

| Línea de sonda | k1_342 | k1b, k1pa, k1pb |
|---|---|---|
| PROBE-MOM | 205/41 = 5 | 550/110 = 5 |
| PROBE-loc | 2214/41 = 54 | 5940/110 = 54 |
| PROBE-P | 410/41 = 10 | 1650/110 = 15 |

k1 también tiene 5 outers por paso, así que «k1pa tiene la sonda de 5 outers de k1b y k1pb … frente a k1_342» es falso. La conclusión «k1pa no es v1» sí se sostiene, pero por PROBE-P: v2 escribe una línea extra, «pp tras conjunto activo». Además, «Las configuraciones sí coinciden» omite esta diferencia de ventana.

*Para levantarla:* usar recuentos por paso, apoyar la conclusión en esa línea extra y mencionar la diferencia de sonda de k1_342.

**O3 (no bloqueante).** El mensaje de 79dc27b no contiene ninguna de las cuatro frases citadas. Dice «sin cambio numérico en las columnas físicas», que es más débil, y ese commit toca `mod_pressure_3d.f90`. *Para levantarla:* citarlo literalmente.

**O4 (no bloqueante).** En `campaigns/b1/k1b_342`, pasos 342538–342560, el tramo va de 27411.7 a 36507.4 Pa. «27–36 kPa» no es el redondeo correcto. *Para levantarla:* escribir 27.4–36.5 kPa.

**O5 (no bloqueante).** «Convergencia 0 %» depende de la tolerancia:
- Con la tolerancia de la corrida, 1e-6 (`k1_342/config.dat` no fija `pc_ai_tol` y el default del parche es 1e-6), da 100 % sin converger. Los 205 solves llegan al tope de 8 iteraciones.
- Con `plank_conv.py --tol 1e-3`, da 0 % sin converger.

*Para levantarla:* indicar la tolerancia, como hace C-012. El veredicto de H1 no cambia, porque |p| ≥ 20 kPa también falla.

### 3. Lo que queda verificado

- Los veredictos de C-012 y C-028 coinciden literalmente con los criterios de C-011 y C-025.
- El reporte no reinterpreta ningún criterio para aprobar. El inciso (a) y la regla de aborto se presentan como lecturas sin valor de veredicto.
- La circularidad de la métrica de C-036 está bien señalada: 6874 Pa / 0.01500 figura en su lista de calibración.

VEREDICTO: rechaza