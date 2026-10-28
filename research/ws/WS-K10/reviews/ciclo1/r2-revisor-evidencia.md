## Revisión de evidencia de WS-K10, ronda 1

Rechazo el reporte. Todas las cifras se reproducen desde los datos y los dos veredictos por la letra son correctos. El problema está en la línea de resultado y en la lectura del tercer dt: afirman cosas que el bootstrap de esos mismos datos contradice o deja sin determinar (O1, bloqueante). Hay además 5 objeciones menores.

Las tres comprobaciones que dependían de archivos fuera del repo o de cálculos propios están hechas y se pueden reproducir:
- **Línea base de la suite:** está en el scratchpad de la sesión. Su sha256 coincide con `logs/base_audit_manifest.txt` y `cmp_comunes.py` da los 61 bancos idénticos (falta su procedencia, O4).
- **Bootstrap del tercer dt:** los intervalos de O1 los calculé yo.
- **Checker de la hora del veredicto:** no está versionado, así que el PASS de `mass_gas_decomp` en los `k10_*` no se puede reproducir (O2).

Lo hice todo en solo lectura, sin corridas ni compilación.

### 1. Tabla de verificación

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| Br/e con 1 ms y 0.5 ms, veredicto de C-202 | −0.683 / −0.135 | −0.683 / −0.135 | ok |
| Br(0.5)/Br(1) | 0.184 | 0.184 | ok |
| Etiqueta de C-202 por la letra | SIN DECIDIR | SIN DECIDIR | ok |
| Br + Bgr con 1 ms | −1.69e-7 (0.012 e) | −1.697e-7 (0.0117 e) | ok |
| Paso 280001 de k10_dt05: EOS multifase / e / fracción | −7.97e-4 / −1.056e-3 / 66 % | −7.966e-4 / −1.0557e-3 / 66.4 % | ok |
| D de C-196 sin el paso 1 | 0.380 | 0.380 | ok |
| Tabla sin el paso 1 (e, Bgq, err_liq, err_cc, A, Br2, Bgr, Br1, Bx, err_art, k10_base) | ver reporte | piezas.py `--sin-paso1` da todas las celdas iguales al redondeo mostrado | ok |
| IC90 de e(0.5)/e(1) | 0.315 (0.30-0.34) | 0.315 (0.301-0.341) | ok |
| IC90 de Bgq / err_liq / A / Br2 y Bgr / err_cc | 0.39 (0.38-0.40) / 0.52 (0.50-0.53) / 0.53 (0.49-0.57) / 0.18 / 0.56 (0.35-1.14) | 0.388 (0.377-0.400) / 0.518 (0.503-0.532) / 0.527 (0.488-0.574) / 0.182-0.183 / 0.560 (0.350-1.143) | ok |
| IC90 de e con bloques de 5/10 | 0.29-0.35 | 0.294-0.347 | ok |
| Error estándar de err_cc | ±3.5e-7 / ±1.2e-7 | 3.5e-7 / 1.2e-7 | ok |
| sd/\|media\| de Bgq; corr(Bgq,e); corr(err_cc,e) | 0.057/0.069; 0.07/−0.03; 0.89/0.99 | igual | ok |
| err_liq/\|Bgq\|; corr(Bgq,err_liq) | 0.37/0.49/0.22; +0.08/−0.48/−0.37 | igual | ok |
| sd/\|media\| de err_cc | 3.3 / 7.9 | 3.27 / 7.89 | ok |
| Parte lineal independiente de dt | ~0.38e-2 kg/s, 26 % | 3.785e-3, 26.1 % | ok |
| k10_base: Bx multifase / libre; store 5 frente a 20 externas | 4.27e-6 / 4.33e-6; 4.16e-5 frente a 3.2e-7 | 4.274e-6 / 4.332e-6; 4.1555e-5 frente a 3.150e-7 | ok |
| Gas libre en k10_base: e_free (fracción) / err_cc_free / store_free; e_free con 20 externas | −1.756e-5 (0.66) / −1.62e-5 / +6.75e-5; +9.5e-8 | −1.7562e-5 (0.660) / −1.6207e-5 / +6.7517e-5; +9.479e-8 | ok |
| Con todos los pasos | 4.15e-5, 3.1e-7, −1.68e-5 (0.63), −1.62e-5, +6.76e-5, +9.4e-8 | igual | ok |
| Columnas comunes k8 frente a k10 | 137 idénticas | 137 idénticas, 20 nuevas | ok |
| Columnas comunes k10 frente a k10b | idénticas salvo m_gas_rv_scale | 157 comunes, solo difiere m_gas_rv_scale | ok |
| Restos de row_volume / decomp | 2.2e-14 m³ / ≤ 2.1e-13 kg | 2.19-2.21e-14 / 2.91e-14 a 2.13e-13 | ok |
| Tolerancias de decomp con k10b | 8.9e-11 a 1.1e-9 | 8.89e-11 a 1.09e-9 | ok |
| PASS de decomp en k10_* con tolerancia 1.4e-11 | PASS | No verificable: el checker actual da FAIL (escala 0) y el de la hora del veredicto no está versionado | objeción O2 |
| eos_end con k10b | ≤ 2.3e-18 sobre 0.34 | 1.94 / 2.31 / 1.89e-18 sobre 0.345 / 0.340 / 0.346 | ok |
| [CG] AVISO | 0, 0, 1 en base; 0 en dt025 | igual | ok |
| m_gas_dec_skip | 0 | 0 | ok |
| Suite: 41 PASS / 27 n/a de 68 (53 + 15) | ver reporte | 41 PASS por check; 27 INFO solo en decomp | objeción O5 (menor) |
| 61 bancos idénticos a la base | sí | sha256 de la base igual al manifiesto; cmp_comunes da 61 idénticos | ok, con O4 |
| 24 columnas nuevas, "8 por clase + 8 de control" | 24 | 24, pero reparto 7 + 8 + 9 | objeción O3 |
| r(e) con 3 dt | −1.4505e-2 / −9.145e-3 / −7.424e-3 | igual | ok |
| r(Bgq) | −2.250e-2 / −1.746e-2 / −1.677e-2 | igual | ok |
| Grupos Bgq+err_cc / err_liq+A / Br+Bgr | ver tabla del reporte | igual | ok |
| r(0.25)/r(0.5) y etiqueta de C-212 | 0.812, SIN DECIDIR | 0.812, SIN DECIDIR por la letra | ok (IC90 en O6) |
| Ajuste c + b·dt^p (sin 1, 2 y 4 pasos) | p = 1.64, c = −6.61e-3 (46 %); −7.0e-3 y −7.2e-3 | igual | ok como cifra puntual; IC en O1 |
| "converge como dt^1.6", "≈ 46 %" | sin barra de error | p IC90 0.88-4.05; c/r1 IC90 0.25-0.61 | objeción O1 |
| "err_liq + A ... son tasas" (+11 %) | tasa | 1.114, IC90 1.07-1.15: crece al bajar dt, no es constante | objeción O1 |
| Comparación justa | — | mismo restart judge_otp_280, configs que solo cambian dt, misma ventana 280.001-280.060 s, binario según "Ejecutable:" | ok |

### 2. Objeciones

**O1 (bloqueante).** La línea de resultado y las lecturas {C-214}{C-215} afirman cosas que los 3 puntos no sostienen. Lo calculé con bootstrap de bloques de 10/20/40 pasos sobre `campaigns/b1/k10b_{mo20,dt05,dt025}/audit.csv`, filas con step > 280001, 4000 réplicas y semilla 1:
- **Exponente.** `ajuste p` da IC90 de 0.88 a 4.05, así que "converge como dt^1.6" no está determinado.
- **Parte fija.** `c/r(1 ms)` da IC90 de 0.25 a 0.61, frente al "≈ 46 %" de la línea de resultado.
- **err_liq + A.** `k10b_dt025`, `r025/r05(err_liq+A)` = 1.114, IC90 de 1.07 a 1.15. Excluye 1: el grupo crece al bajar dt y no es una "tasa".
- **Coherencia.** Entre 0.5 y 0.25 ms, r(e) sube 1.72e-3 kg/s, y 1.09e-3 de ese cambio viene del crecimiento de err_liq + A. Las lecturas de C-214 (constante más una parte que converge) y de C-215 (dos tasas) no se reconcilian.

Para levantarla:
- Reescribir la línea de resultado y las viñetas de C-214 y C-215 como lectura, con estos IC90.
- Quitar "son tasas" para err_liq + A.
- Registrar la corrección en el ledger con ref a C-214 y C-215.
- Poner el comando del bootstrap en la nota de procedencia.

**O2 (no bloqueante).** `campaigns/b1/k10_{mo20,dt05,base}`: `check_audit.py` da `mass_gas_decomp` en FAIL, porque sin `m_gas_dec_scale_*` la tolerancia es 1e-13 × 0. El checker de la hora del veredicto (tolerancia 1.4e-11) no está versionado: el último commit de `check_audit.py` es 79dc27b. Los restos sí son idénticos (2.91e-14, 5.81e-14 y 2.13e-13 kg), y k10b_* pasa con el checker actual. Para levantarla, conservar en `logs/` el checker o la salida de la hora del veredicto. Otra opción es registrar con ref a C-204 que el prerrequisito se sostiene con k10b_* (C-209) y por qué la etiqueta sigue siendo SIN DECIDIR y no fallida.

**O3 (no bloqueante).** El paso 2 del Proceso dice "8 piezas por clase y 8 de control". El reparto real de las 24 columnas es:
- 7 de multifase: pa, brho_it, brho_end, bg_rho, bg_q, bx y store;
- 8 de gas libre: las mismas más err_liq_free;
- 9 de control: dec_abs ×2, rv_abs, rv_scale, dec_skip, dec_scale ×2, eosend_abs y eosend_scale.

Además, store no es una pieza de la identidad.

**O4 (no bloqueante).** La base de la suite vive en el scratchpad de la sesión, que es efímero: `/private/tmp/claude-502/-Users-frariv-Horno/68c200c2-efa4-46c5-a9ff-3c767a24d56a/scratchpad/k10_base`. Su sha256 coincide con el manifiesto y la comparación da 61 bancos idénticos. Lo que no se puede verificar es que salga del código de 934c2d4: falta el binario o el log. Conviene archivar la base o su procedencia.

**O5 (no bloqueante).** `logs/test_full.txt`: solo `mass_gas_decomp` imprime "INFO n/a" (27 veces). En esas 27 evaluaciones, row_volume y eos_end no imprimen nada. El texto debería decirlo así.

**O6 (no bloqueante).** El IC90 de r(0.25)/r(0.5) para e va de 0.71 a 0.97 y cruza los dos umbrales de C-212 (0.75 y 0.90). El veredicto SIN DECIDIR es correcto por la letra, pero con esta muestra el banco tampoco habría podido decidir. Conviene decirlo en Incertidumbre.

### Comprobado sin objeción

- Los veredictos de C-202/C-203 y de C-212 se aplicaron literalmente. Las enmiendas son anteriores a las corridas: C-203 en el commit 5999f40 y C-212 en b03b22e.
- Los bancos que se comparan arrancan del mismo reinicio (`judge_otp_280`).
- Sus `config.dat` solo difieren en dt y en `output_dir`.
- Cubren la misma ventana, de 280.001 a 280.060 s.
- Cada uno usa el binario que dice su línea "Ejecutable:", y k10 frente a k10b dan las mismas piezas bit a bit.
- El banco de 1 ms tiene dt adaptativo con dt_min = 1e-3, pero en todas las filas dt vale 1e-3, salvo el recorte final.
- La identidad algebraica de Br2 + Bgr es correcta.
- Las referencias `src/mod_pressure_3d.f90:893-905` y `1291-1495` corresponden a lo que describe el reporte.

VEREDICTO: rechaza