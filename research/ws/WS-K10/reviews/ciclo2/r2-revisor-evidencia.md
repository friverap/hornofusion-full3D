### Revisión r1: revisor de evidencia, WS-K10 (revisión ciega)

**Resultado: rechaza.** Todos los números del reporte que recalculé coinciden con los datos dentro del redondeo mostrado, y los tres veredictos siguen la letra de su criterio pre-registrado. Rechazo por dos problemas bloqueantes: el reporte se contradice con el registro tras C-231/C-232 (O1) y presenta H14 como una prueba más severa de lo que fue (O2).

Solo lectura: no ejecuté `make`, `mpirun` ni binarios. Usé el contexto, el reporte, `ledger.py show/check/open`, los scripts de `research/ws/WS-K10/scripts` (las versiones commiteadas en 5999f40 y b03b22e cuando son la medida pre-registrada), `check_audit.py`, `cmp_comunes.py` y python3 propio sobre los `audit.csv`. Los bootstraps propios los guardé en el scratchpad.

#### 1. Tabla de verificación

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| C-204: Br/e con 1 ms y con 0.5 ms; Br(0.5)/Br(1) | −0.683 / −0.135; 0.184 | −0.683 / −0.135; 0.184 (piezas.py de 5999f40) | ok |
| C-204: SIN DECIDIR por la letra | sin decidir | no cumple soportada (Br/e fuera de [0.5, 1.5]) ni refutada (\|Br\| ≥ 0.2\|e\| con 1 ms; 0.184 fuera de [0.35, 0.65]) | ok |
| Columnas comunes de k8s/k8 frente a k10 | 137 idénticas | 137, distintas: [] en los 3 pares | ok |
| row_volume / decomp (restos y tolerancias) | 2.2e-14 m3; ≤2.1e-13 kg; tolerancia 1.41-1.46e-11 | 2.20e-14; máximo 2.13e-13; 1.41e-11 a 1.46e-11 | ok |
| AVISO del CG / dec_skip | 0 y 0; k10_base 1 | 0 y 0; 1; dec_skip 0 | ok |
| k10b frente a k10 | iguales salvo rv_scale | 157 columnas comunes, distinta solo m_gas_rv_scale | ok |
| eos_end con el binario k10b | ≤2.3e-18 sobre ~0.34 | 1.94 / 2.31 / 1.89e-18 sobre 0.345 / 0.340 / 0.346 | ok |
| Paso 280001: EOS, e, peso en la suma | −7.97e-4; −1.056e-3; 66 % | −7.966e-4; −1.0557e-3; 66.4 % | ok |
| Cociente de D: todos / p<100 kPa / t>280.020 | 0.380 / 0.377 / 0.372 | lo mismo en los 3 pares | ok |
| Tabla sin el paso 1 (e, Bgq, err_liq, err_cc, A, Br2, Bgr, Br1, Bx, err_art; tres bancos) | ver :248-257 | todas las celdas coinciden; IC90 0.301-0.341, 0.377-0.400, 0.503-0.532, 0.350-1.143, 0.488-0.574, 0.179-0.185 | ok |
| IC90 de e con bloques 5/10 | 0.29-0.35 | 0.294-0.347 | ok |
| sd/\|m\|, correlaciones, err_liq/\|Bgq\| | 0.057/0.069; 0.07/−0.03; 0.89/0.99; 0.37/0.49/0.22 | idénticos | ok |
| err_cc ± error estándar | −1.08e-6 ± 3.5e-7; −6.0e-7 ± 1.2e-7 | igual | ok |
| k10_base: Bx, store, e_free, quintos | ver :321-334 | coinciden (quintos de store 4.01-4.33e-5; Bgq −3.68 a −3.85e-5; err_free −1.5e-6 a −3.7e-5) | ok |
| Centinela 280002-280004 y cocientes con los pasos excluidos | ver :341-353 | coinciden | ok |
| Máximos en los pasos 2-10 de cada banco | ver :365-372 | 99.6/163, 94/215, 191/188 (280009), 461/300, 55/124, 79/72 | ok |
| Ventana completa de 290 s con 0.25 ms | 450 kPa, 128.6 m/s (paso 290093), 5/235 | igual | ok |
| Pasos tranquilos 0.5/1 | 0.353 (0.334-0.397); 0.844 | igual (centinela.py) | ok |
| Sensibilidad (umbrales y ventanas) | 0.375-0.314; 0.318/0.306/0.306; 0.863/0.989/1.057 | igual | ok |
| C-213: r(e) de los 3 dt y r(0.25)/r(0.5) | −1.4505e-2, −9.145e-3, −7.424e-3; 0.812 → sin decidir | igual (tasa.py, el actual y el de b03b22e) | ok |
| Tabla del tercer dt e IC90 (bootstrap móvil) | ver :410-415 | todas coinciden; 72 y 1268 réplicas sin ajuste | ok |
| Bootstrap circular, mediana 0.855 y 0.816, IC90 de p y c | ver :424-431 | igual | ok |
| regimen.py (bloques de 10 ms) | 0.445-1.013 | igual | ok |
| Descomposición del +1.72e-3; Br+Bgr 1.2/0.75/0.71 % | 63 % / 36 % | 1.090e-3 (63 %), 6.15e-4 (36 %); igual | ok |
| a, k (280 s y 290 s), predicciones de 2.316e-6 y 6.92e-6 | ver :491-515 | igual | ok |
| Régimen de presión (pasos, décimos, r por régimen, corr, vol_lim) | ver :521-530 | igual | ok |
| Tabla de 280 s frente a 290 s (con IC90) | ver :572-582 | igual (0.135 se muestra como 0.14 y −1.265 como −1.27: redondeo) | ok |
| Ajuste lineal: 78 % / 26 % | ~78 % / 26 % | 77.7 % / 26.1 % | ok |
| Quintos de e en 280 s y en 290 s; ×3.4 | ver :612-613 | igual; 3.40 | ok |
| Paso 1 en 290 s y en tgfix | ver :213-220 | igual | ok |
| **C-232 (a)**: r(0.5)/r(1) | 0.877 → SOPORTADA | 0.877; dentro de [0.85, 1.00] | ok por la letra (ver O2 y O5) |
| **C-232 (b)**: err_liq_lk por paso | 6.996e-6 → SOPORTADA | 6.996e-6; dentro de [5.88e-6, 7.96e-6] | ok por la letra (ver O2) |
| Prerrequisitos de H14 | 0 AVISO, sin FAIL, p_max 71 kPa, checks PASS | igual (decomp 5.73e-14, eos_end 2.30e-18) | ok |
| Pre-registro antes de cada corrida | sí | k10_* 21:58:28 > commit 21:57:42; k10b_dt025 23:02:21 > 23:02:09; k11_dt05_s290 00:16:57 > 00:16:51 | ok |
| Comparación justa en H14 | mismo snapshot, binario, ventana | configs iguales salvo dt; binario k10b; t_final 290.06; sin el paso 290001 | ok |
| C-233 (config de B1 en 290 s) | −6.77e-5, ×77, −2.2e-5, FAIL energy_balance, regime_gas sin FAIL | igual (×76.8; 106.9 m/s) | ok, sin nota de fuente (O6) |
| Checks de la suite con el checker actual | 43 PASS / 36 n/a | 43 / 36 sobre las 79 audit.csv de tests/out | ok, conteo sin conciliar (O4) |
| 61 bancos de la suite idénticos a la base de 934c2d4 | sí | no verificable (base efímera) | objeción O3 |

#### 2. Objeciones

**O1 (bloqueante): el reporte se contradice con el registro.**
- `report.md:510-513` dice que la predicción de err_liq_lk «no está pre-registrada» y que es tarea del coordinador; ya es C-231 (b) y se juzgó en C-232.
- `:622-625` y `:680-685` piden «una corrida NUEVA de 0.5 ms desde eaf3d_00290000.h5» como pendiente; ya existe: `campaigns/b1/k11_dt05_s290`.
- `:666-667` describe la muestra de 290 s como «lectura no pre-registrada con dos dt».
- `:686-689` dice «ninguna de las dos lecturas está medida», frente a C-232 soportada «mayormente TASA» (resumen, `:44-50`).
- `:490` deja la hipótesis de k «no adoptada» sin decir qué cambia con C-232 (b).

Para levantarla: poner al día esas secciones conforme a C-231/C-232 y separar lo soportado de lo abierto.

**O2 (bloqueante): C-231 tuvo poco poder y el reporte no lo dice.**
- **(b):** con k=0 y una tasa monótona entre `k11_mo20_s290:r(err_liq_lk)=1.3654e-2` y `k11_dt025_s290:r(err_liq_lk)=1.4233e-2`, err_liq_lk por paso con 0.5 ms cae en [6.83e-6, 7.12e-6], dentro de la banda. La interpolación lineal de la tasa da 7.02e-6, más cerca del valor medido (`k11_dt05_s290:6.996e-6`) que el 6.92e-6 del modelo con k. El reporte lo cita como «predicho 6.92e-6» (`:49` y `:649`).
- **(a):** con `r(0.25)/r(1)=0.833` ya visto, cualquier r monótona da un cociente en [0.833, 1]: lineal 0.888, dt^2 0.867, dt^0.5 0.902. La refutación (≤0.70) era inalcanzable.
- El veredicto sigue la letra del criterio, pero la conclusión «mayormente tasa» descansa en el 0.833, que no estaba pre-registrado.

Para levantarla: declarar ambas limitaciones en el resultado y en Incertidumbre. Un test de k necesita un dt fuera del intervalo ya visto (p. ej. 0.125 ms) y una banda que excluya k=0.

**O3 (no bloqueante): la base de la suite no es verificable.** `research/ws/WS-K10/logs/cmp_comunes.txt` dice «61 idénticos», pero la base es una copia efímera. Sí verifiqué de forma independiente la identidad k8s→k10→k10b en las campañas. Para levantarla: archivar la base o regenerarla desde 934c2d4 con el sha del binario.

**O4 (no bloqueante): logs sin atar al diff y conteo sin conciliar.**
- `logs/test_full.txt` no registra el sha del diff.
- `logs/checks_suite.txt` no registra el comando que lo generó.
- 68 evaluaciones (53+15) frente a 79 audit.csv en tests/out (61+18), sin explicar.

Para levantarla: volver a correr test-full con el sha guardado y conciliar los conteos.

**O5 (no bloqueante): falta el IC90 de H14.** Mi bootstrap da 0.862-0.891 con bloques móviles 10/20 y 0.860-0.894 con el circular. Queda dentro de la banda, pero es una sola trayectoria por dt en 60 ms, y CLAUDE.md pide un juez estadístico por encima de 280 s. Para levantarla: añadir el IC90 y esa salvedad.

**O6 (no bloqueante): k11_base_s290 sin nota de fuente.** `report.md:655-662` no lleva nota de fuente y no menciona su «[CG] AVISO» (1). Para levantarla: añadir el comando de C-233.

#### 3. Observaciones sin objeción
- Los tres veredictos (C-204, C-213, C-232) aplican literalmente su criterio. Las enmiendas (C-203) son anteriores a las corridas y llevan motivo.
- Las comparaciones entre dt usan el mismo snapshot, el mismo binario y la misma ventana. Se excluye el primer paso tras acotar el dt, como fija cada criterio.

VEREDICTO: rechaza