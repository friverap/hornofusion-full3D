# WS-K10, ronda 1: revisión de evidencia

**Resultado: rechazo el cierre por una objeción bloqueante (O1).** Los números se reproducen y el veredicto de C-202 (SIN DECIDIR) respeta la letra del criterio. El problema es que el reporte llama «tasa» a cocientes que la banda pre-registrada no acepta como tasa.

Todo se ejecutó en solo lectura, desde `/Users/frariv/Horno/hornofusion-full3D`. Comandos usados:
- `piezas.py`, con y sin `--sin-paso1`;
- `cmp_comunes.py --par`;
- `check_audit.py` sobre `campaigns/b1/k10*_*`;
- `grep` en los `run.log` y `shasum` de los binarios;
- un bootstrap por bloques propio para medir la incertidumbre de los cocientes.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Br/e (todos los pasos) 1 ms / 0.5 ms | −0.683 / −0.135 | −0.683 / −0.135 | ok |
| Br(0.5)/Br(1) | 0.184 | 0.184 | ok |
| Veredicto de C-202 por la letra | SIN DECIDIR | SIN DECIDIR (no es soportada: Br/e fuera de [0.5, 1.5]; no es refutada: \|Br\| ≥ 0.2\|e\| con 1 ms y 0.184 ∉ [0.35, 0.65]) | ok |
| `piezas.py` sin cambios en su medida desde el pre-registro (`5999f40`) | — | el diff solo añade `--sin-paso1`; con la opción por defecto el cálculo es idéntico | ok |
| Columnas comunes de k10 frente a k8s_mo20, k8s_dt05 y k8_base | 137, idénticas | 137, distintas: []; 60/119/60 filas | ok |
| `[CG] AVISO` | 0 / 0, y 1 en base | 0 / 0 / 1 | ok |
| `m_gas_dec_skip` | 0 | 0 en los tres | ok |
| `mass_gas_row_volume` | 2.2e-14 m³ | 2.20e-14 / 2.19e-14 / 2.21e-14 | ok |
| `mass_gas_decomp` | ≤ 2.1e-13 kg | máx. 2.13e-13 (gas libre, dt05) | ok (ver O4) |
| `mass_gas_eos_end` | ≤ 2.3e-18 sobre escalas de 0.34 | 1.94 / 2.31 / 1.89e-18 sobre 0.345 / 0.340 / 0.346 | ok (redondeo) |
| k10b frente a k10, «mismas piezas bit a bit» | — | 157 columnas comunes; solo cambia `m_gas_rv_scale` | ok |
| Columnas nuevas | 24 | 24 | ok |
| Binarios | k10_opt / k10b_opt | sha256 d5827e… / 5409bb… = `opt_identidad.txt`; diff staged de `src/` = 74a5e2… (k10b) | ok |
| Config y reinicio | config de K8, `judge_otp_280`, 15 ranks | configs idénticas salvo `output_dir`; mismo h5; 15 procesos | ok |
| Pre-registro antes de correr | — | C-202 21:57:27, C-203 21:57:37; audit.csv 21:59–22:04 | ok |
| Suite: 61 bancos idénticos | 61 | manifiesto sha256 OK; `cmp_comunes`: 61 idénticos | ok |
| Checks: 41/68, 53 corridas + 15 reinicios, 27 n/a | — | 41 PASS × 3, 27 INFO; 53 + 15 | ok |
| test-unit y test-full OK, golden v132 | — | OK; `metrics_v132.json` | ok |
| Paso 280001 de k10_dt05: EOS / e / % | −7.97e-4 / −1.056e-3 / 66 % | −7.966e-4 / −1.0557e-3 / 66.4 % | ok |
| e por paso sin paso1 (0.5/1) | 0.32 | 0.315 (IC90 0.295–0.346) | ok numérico; **O1** en la lectura |
| C-196: D sin paso1 | 0.380 | 0.3803 | ok |
| Br + Bgr con 1 ms | −1.69e-7, 0.012 e | −1.697e-7, 0.0117 e | ok |
| Tabla `--sin-paso1` (las 10 filas × 6 columnas) | ver reporte | todas coinciden al redondeo mostrado | ok |
| «escala como TASA»; «piezas grandes 0.18 a 0.56 = tasa» | — | e 0.315, Br2 0.182 y Bgr 0.183: fuera de la banda de tasa [0.35, 0.65] de C-202 | **O1** |
| err_cc «no distinto de cero», sd/\|media\| | 3.3 y 10.2 | 3.27 y 10.19 | ok numérico; **O3** en la inferencia |
| k10_base: store_gas multifase | +4.16e-5 frente a +3.2e-7 | con el comando citado: 4.154e-5 / 3.10e-7; con `--sin-paso1`: 4.156e-5 / 3.15e-7 | **O2** |
| k10_base: e_free, fracción, err_cc_free, store_free | −1.68e-5, 0.63, −1.62e-5, +6.76e-5 | todos los pasos: −1.677e-5, 0.630, −1.621e-5, 6.762e-5 | ok con el comando citado (O2: ventana mezclada) |
| e_free con 20 externas | +9.4e-8 | +9.36e-8 | ok |

## 2. Objeciones

**O1 (bloqueante).** El reporte usa «tasa» con otro sentido que el del criterio pre-registrado.
- `research/ws/WS-K10/report.md` («Resultado en una línea»; «Todas las piezas grandes escalan como una tasa: los cocientes entre dt van de 0.18 a 0.56»).
- C-202 define el comportamiento de tasa como un cociente en [0.35, 0.65]. Con esa banda, C-204 juzgó que Br, con 0.184, NO es tasa.
- Pero el reporte llama tasa a e: `piezas.py --sin-paso1` da 0.315, con IC90 por bootstrap de bloques de 0.295 a 0.346.
- Y también a Br2 (0.182) y a Bgr (0.183).
- La lectura contradice el veredicto que cita.
- Para levantarla: reescribir así: «e baja más que linealmente con dt (0.32); Bgq 0.39, err_liq 0.52 y A 0.53 caen en la banda de tasa; Br2 y Bgr dan 0.18». Si se quiere sostener «tasa», registrar una predicción nueva con esa definición. Añadir además un evento que precise el término en C-206 y C-207.

**O2.** El párrafo de k10_base mezcla ventanas.
- `campaigns/b1/k10_base`: store_gas multifase = 4.1544e-5 y k10_mo20 = 3.1031e-7 con el comando citado (sin `--sin-paso1`). El reporte pone 4.16e-5 y 3.2e-7, que son los valores de `--sin-paso1`.
- Los números del gas libre sí salen con todos los pasos. Con `--sin-paso1` serían e_free = −1.756e-5 y 0.66.
- Para levantarla: declarar la ventana de cada número o usar una sola.

**O3.** err_cc: la inferencia no está soportada.
- `campaigns/b1/k10_mo20`: sd/|media| = 3.27 es dispersión por paso. Con n = 59, |media|/EE ≈ 2.3, sin corregir la autocorrelación: no basta para decir «no distinto de cero».
- Sin paso1, sd/|media| sigue en 3.27 y 7.89, y el cociente de err_cc (0.56) tiene IC90 [0.29, 0.90].
- Por eso no puede entrar como pieza que «escala como tasa».
- Para levantarla: dar el EE o un IC por bloques y sacar err_cc de esa frase.

**O4.** El prerrequisito `mass_gas_decomp` sobre k10_* no se reproduce con el checker actual.
- `campaigns/b1/k10_mo20`, `k10_dt05` y `k10_base` dan FAIL, porque no tienen `m_gas_dec_scale_*` y la escala vale 0.
- El PASS de C-204 fue con el checker previo (tol 1.4e-11). Hoy lo sostienen k10b_*, con piezas idénticas. Los restos (≤ 2.13e-13) cumplen de sobra.
- Para levantarla: decirlo explícitamente en Prerrequisitos.

## 3. Comparación justa y muestra

- La comparación es justa:
  - el mismo binario para los dos bancos que deciden;
  - configs idénticas salvo dt;
  - el mismo snapshot `judge_otp_280` y 15 ranks;
  - la misma ventana física: 59 ms, con 58/59 pasos a 1 ms y 117/118 a 0.5 ms.
- El veredicto se juzgó con todas las filas, como manda C-202.
- El transitorio del reinicio está declarado. Hace que la premisa de escala de C-202 (−1.348e-5, tomada de C-197) sea un artefacto; el reporte lo reconoce.
- La muestra es de una trayectoria por config y 58–118 pasos. Basta para cocientes tan nítidos como los de Bgq, Br2 y Bgr (IC estrechos), pero no para err_cc (O3).

VEREDICTO: rechaza