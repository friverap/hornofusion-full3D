# WS-K10, ronda 1: revisor de evidencia

Esta revisión es ciega: no leí `reviews/`. Solo hice lecturas. Ejecuté `piezas.py`, `tasa.py`, `regimen.py`, `cmp_comunes.py`, `check_audit.py`, `ledger.py show|check` y los comandos `python3 -c` del reporte, y añadí algunos cálculos propios con python. No ejecuté `make`, `mpirun` ni binarios.

## 1. Afirmaciones y valores recalculados

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Br/e con 1 ms y 0.5 ms (veredicto de C-202, todos los pasos) | -0.683 / -0.135 | -0.683 / -0.135 | ok |
| Br(0.5)/Br(1) | 0.184 | 0.184 | ok |
| Veredicto de C-202 por la letra | SIN DECIDIR | SIN DECIDIR: no se cumple [0.5,1.5]; la condición \|Br\|<0.2\|e\| solo se da con 0.5 ms; 0.184 queda fuera de [0.35,0.65] | ok |
| Columnas comunes k8 frente a k10 | 137 idénticas | 137 idénticas, 20 nuevas, en los 3 pares | ok |
| row_volume / decomp | 2.2e-14 m3 / ≤ 2.1e-13 kg | 2.20e-14 / 2.13e-13 | ok |
| [CG] AVISO | 0 / 0 / 1 (base) | 0 / 0 / 1 | ok |
| dec_skip | 0 | 0 | ok |
| «`check_audit.py` actual da FAIL en k10_*» | FAIL | **PASS** (restos 2.91e-14 / 5.81e-14 / 2.91e-14, tolerancias 1.43e-11 / 1.46e-11 / 1.41e-11) | **objeción O1** |
| «1.4e-11 de C-204 no es reproducible» | no reproducible | se reproduce: 1.43e-11 | **objeción O1** |
| C-221: PASS k10_* | 2.9e-14 / 5.8e-14 / 2.9e-14 | igual | ok |
| k10b_*: tolerancias / eos_end | 8.9e-11 a 1.1e-9 / ≤ 2.3e-18 sobre 0.34 | 8.89e-11 a 1.09e-9 / 2.31e-18 sobre 0.340-0.346 | ok |
| Paso 280001 de k10_dt05: EOS / e / porcentaje | -7.97e-4 / -1.056e-3 / 66 % | -7.966e-4 / -1.0557e-3 / 66.4 % | ok |
| D sin el paso 1 (C-196) | 0.380 | 0.380 | ok |
| Tabla sin el paso 1: medias, /e, cocientes (10 filas) | ver reporte | todas reproducen al redondeo mostrado | ok |
| IC90 con bloques 10/20 (e, Bgq, err_liq, err_cc, A, Br2, Bgr) | 0.30-0.34, 0.38-0.40, 0.50-0.53, 0.35-1.14, 0.49-0.57, 0.18-0.19 ×2 | 0.301-0.341, 0.377-0.400, 0.503-0.532, 0.350-1.143, 0.488-0.574, 0.179-0.185, 0.179-0.187 | ok (ver O2) |
| IC90 de e con bloques 5/10 | 0.29-0.35 | 0.294-0.347 | ok |
| Error estándar de err_cc | ±3.5e-7 / ±1.2e-7 | 3.5e-7 / 1.2e-7 | ok |
| sd/\|m\| de Bgq; corr(Bgq,e); corr(err_cc,e) | 0.057/0.069; 0.07/-0.03; 0.89/0.99 | igual | ok |
| err_liq/\|Bgq\|; corr(Bgq,err_liq) | 0.37/0.49/0.22; +0.08/-0.48/-0.37 | igual | ok |
| sd/\|m\| de err_cc | 3.3 / 7.9 (10.2 con el paso) | 3.27 / 7.89 / 10.19 | ok |
| Br + Bgr con 1 ms | -1.69e-7, 0.012 e | -1.6946e-7, 0.0117 | ok |
| Parte fija del ajuste lineal con dos dt | ~0.38e-2, 26 % | 3.79e-3, 26.1 % | ok |
| k10_base y gas libre (sin el paso 1 / con todos) | ver reporte | todas reproducen | ok |
| Veredicto de C-212: r(1/0.5/0.25) | -1.4505e-2 / -9.145e-3 / -7.424e-3 | igual | ok |
| r(0.25)/r(0.5) | 0.812, SIN DECIDIR | 0.812, entre 0.75 y 0.90: SIN DECIDIR | ok |
| Prerrequisitos de C-212 | 0 AVISO; decomp 1.16e-13; eos_end 3.0e-18 | igual; dt 2.5e-4 en las 236 filas | ok |
| Tabla de tres dt y grupos | ver reporte | todo reproduce (tasa.py, tasa.py --grupos, comando de bootstrap) | ok |
| IC90 de r(0.25)/r(0.5) de e; p; c/r1; réplicas sin ajuste | 0.71-0.97; 0.88-4.05; 0.25-0.61; 72 | 0.713-0.973; 0.88-4.05; 0.25-0.61; 72 | ok en la reproducción; **sesgo de método (O2)** |
| Bgq + err_cc: 1268 réplicas sin ajuste; err_liq + A con bloques 5/10/20 | 1268; 1.075-1.146 | 1268; 1.075-1.146 | ok |
| Reparto del cambio de r(e) | +1.72e-3: 63 % / 36 % | +1.721e-3: 63.4 % / 35.7 % | ok |
| Br + Bgr / r(e) | 1.2 / 0.75 / 0.71 % | 1.17 / 0.75 / 0.71 % | ok |
| err_liq_lk: a, k, predicción, cuarto dt | 8.17e-3; 2.75e-7; 2.316e-6 frente a 2.349e-6 (1.4 %); ≈1.04e-2 | 8.166e-3; 2.75e-7; 2.3165e-6 frente a 2.3493e-6; 1.037e-2 | ok |
| Sensibilidad de c al descartar 2 o 4 pasos | -7.0e-3 / -7.2e-3 | -7.021e-3 / -7.247e-3 | ok |
| Régimen de presión (pasos, porcentajes, décimos, máximos, r(e), Bgq y err_cc por régimen, corr, vol_lim) | ver reporte | todo reproduce; el máximo con 1 ms es 99.63 kPa | ok (O6, menor) |
| C-219 y C-220: IC90 con regimen.py | 0.445-1.013 | 0.445-1.013 | ok |
| Bgq: ×1.68 entre k10_base y k10_mo20 | 1.68 | 1.685 | ok |
| Suite: 61 idénticos; 41 PASS / 27 INFO | según logs | copia base: 61 sha256 OK; 61 idénticos; 137 comunes, 24 nuevas; log 41/27 | ok (ver O3 y O5) |
| 24 columnas nuevas frente a k8s_mo20 | 24 | 24 (k10b_mo20) | ok |
| Referencias de código mod_pressure_3d.f90:893-905 y 1291-1495 | | concuerdan | ok |
| `ledger.py check` | | OK, 221 eventos | ok |

**Justicia de la comparación:** los siete bancos parten del mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`) y miden la misma ventana de 59 ms. Cada predicción usa un solo binario, y el sha de `eaf3d_k10b_opt` coincide con el del diff actual de `src/` (74a5e2a4…). Entre `k10b_dt05` y `k10b_dt025` la config solo cambia en dt. Ambos pre-registros se commitearon antes de lanzar sus corridas: 5999f40 a las 21:57:42, antes de las 21:58:27; b03b22e a las 23:02:09, antes de las 23:02:21. La muestra es corta, una sola trayectoria y una ventana de 59 ms con el transitorio de presión al principio. El reporte lo reconoce, y los dos veredictos son SIN DECIDIR. Ninguna conclusión fuerte descansa sobre la muestra.

## 2. Objeciones

1. **O1 (bloqueante).** `research/ws/WS-K10/report.md:132-140` sostiene que «el `check_audit.py` actual da FAIL» en los k10_* y que «1.4e-11 de C-204 no es reproducible». Con el checker actual (modificado a las 23:24:00 por C-221) los tres dan **PASS**, con tolerancias de 1.43e-11, 1.46e-11 y 1.41e-11 kg, así que la cifra de C-204 sí se reproduce. El párrafo se contradice con su propia frase «Resuelto por el coordinador», y el punto afectado es el prerrequisito que separa «fallida» de «sin decidir». **Para levantarla:** pasar a pasado lo que describía el checker intermedio y dejar en presente solo lo que se reproduce hoy.
2. **O2 (no bloqueante).** El bootstrap de bloques móviles no envuelve los extremos, así que infrapondera el inicio de la ventana, donde está el transitorio. En `k10b_dt025` los primeros 40 pasos dan r = -5.13e-4 kg/s y el resto -8.84e-3. La media de las réplicas es -7.90e-3, frente a la muestral de -7.42e-3, y la mediana del cociente es 0.853 frente a 0.812. Con bloques circulares: e 0.25/0.5 da IC90 **0.655-0.961** (el reporte da 0.71-0.97), c/r(1 ms) **0.04-0.59** (0.25-0.61) y p **0.65-3.78** (0.88-4.05). Las conclusiones cualitativas se mantienen. **Para levantarla:** usar bootstrap circular o estacionario, o declarar el sesgo de borde en Incertidumbre.
3. **O3 (no bloqueante para el panel; sí para el cierre).** `logs/test_full.txt` (22:36:55) es anterior al último cambio de `tests/integration/check_audit.py` (23:24:00). El recuento 41/27 sale de otro checker y de otro diff_sha. Con el checker actual, sobre los 79 CSV que hay hoy en `tests/out`, salen 43 PASS, 36 INFO y 0 FAIL. **Para levantarla:** correr `make test-quick` (y `test-full`) sobre el diff final y archivar el log con su sha.
4. **O4 (no bloqueante).** El resumen (`report.md:15-16`) aplica a e, sin el paso 280001, la banda que C-202 fijó para Br, y no lo marca como lectura a posteriori. **Para levantarla:** etiquetarlo así en el resumen, como ya se hace en la línea 173.
5. **O5 (no bloqueante, ya reconocida).** La copia base en el scratchpad de esta sesión (`k10_base`) cuadra con las 61 sumas sha256 del manifiesto y `cmp_comunes.py` da 61 idénticos. Que salga de 934c2d4 sigue sin prueba. **Para levantarla:** archivarla, o archivar el sha del binario o el log de su corrida.
6. **O6 (menor).** `report.md:362` da «p_max máximo 100 kPa» con 1 ms en la misma tabla donde hay 0 pasos ≥ 100 kPa. El valor real es 99.63 kPa: conviene escribir 99.6 kPa.

Todos los números de las tablas y de las notas de procedencia se reproducen. Los dos veredictos (C-204 sobre C-202 y C-213 sobre C-212) se ajustan literalmente al criterio pre-registrado y no hay enmiendas a posteriori. El rechazo se debe solo a O1: el texto sostiene hoy dos afirmaciones sobre el prerrequisito del veredicto que el recálculo contradice.

VEREDICTO: rechaza