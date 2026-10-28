**Rechazo el cierre de WS-K10 en esta ronda: una objeción bloqueante.** El resumen del reporte da para el banco de 0.25 ms desde 290 s un máximo de 72 m/s y 79 kPa sin decir en qué pasos se midió. En el banco completo la presión llega a 450 kPa (paso 290093), casi lo mismo que los 461 kPa que el reporte presenta como la anomalía.

Los dos veredictos pre-registrados (C-204 y C-213) cumplen la letra de sus criterios, y casi todos los demás números se reproducen.

# Revisión de evidencia — WS-K10, ronda 1 (revisor-evidencia)

Revisión ciega: no leí `research/ws/WS-K10/reviews/`. Todo se hizo en modo de solo lectura (python sobre los CSV y HDF5 existentes, los scripts del WS, `check_audit.py`, `ledger.py show/open/check`, `git show/log/diff`). No había ninguna simulación en curso.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Veredicto de C-202 (piezas.py, todos los pasos) | SIN DECIDIR; Br/e −0.683 / −0.135; Br(0.5)/Br(1) 0.184 | Igual; la letra del criterio da SIN DECIDIR | ok |
| Prerrequisito: columnas comunes con K8 | 137 idénticas | 137 idénticas en los 3 pares | ok |
| row_volume / decomp | 2.2e-14 m³; ≤ 2.1e-13 kg | 2.19-2.21e-14; máx. 2.13e-13 | ok |
| Tolerancias de decomp | k10_* 1.41-1.46e-11; k10b_* 8.9e-11 a 1.1e-9 | 1.41/1.43/1.46e-11; 8.89e-11 a 1.09e-9 | ok |
| `[CG] AVISO` / dec_skip | 0, 0 (base: 1) / 0 | Igual | ok |
| eos_end (k10b_*) | ≤ 2.3e-18 sobre 0.34 | 1.94 / 2.31 / 1.89e-18 sobre 0.345 / 0.340 / 0.346 | ok |
| k10b frente a k10: columnas comunes | 157, todas idénticas salvo rv_scale | Igual | ok |
| Columnas nuevas | 24 (7+8+9) | 24, con los nombres listados | ok |
| Paso 280001 de k10_dt05 | EOS −7.97e-4; e −1.056e-3; 66 % | −7.966e-4; −1.0557e-3; 0.664 | ok |
| e(0.5)/e(1) sin el paso 1 | 0.315 (IC90 0.30-0.34) | 0.315 (0.301-0.341) | ok |
| Tabla de piezas (10 filas × 6 columnas) | ver report.md:194-203 | Coincide al redondeo mostrado | ok |
| IC90 de e con bloques 5/10 | 0.29-0.35 | 0.294-0.346 | ok |
| Errores estándar de err_cc | ±3.5e-7 / ±1.2e-7 | 3.5e-7 / 1.2e-7 | ok |
| Correlaciones y sd/|media| | 0.057/0.069; 0.89/0.99; −0.48/−0.37/+0.08; 0.37/0.49/0.22 | Igual | ok |
| Br + Bgr con 1 ms | −1.69e-7 (0.012 e) | −1.6946e-7 (0.0117) | ok |
| Ajuste lineal de e/dt | ~0.38e-2 kg/s, 26 % | −3.785e-3, 0.261 | ok |
| D de C-196 sin el paso 1 / p_max < 100 kPa / t > 280.020 s | 0.380 / 0.377 / 0.372 | 0.380 / 0.377 / 0.372 | ok en el valor; sin comando (O2) |
| k10_base, gas libre | −1.756e-5 (0.66); err_cc −1.62e-5; store +6.75e-5; Bx 4.27e-6 / 4.33e-6 | Igual | ok en el valor; sin {C-nnn} (O3) |
| Ídem con todos los pasos | 4.15e-5, 3.1e-7, −1.68e-5 (0.63), −1.62e-5, 6.76e-5, 9.4e-8 | Igual | ok |
| Picos de 0.25 ms en 280002-280004 | 198.6/281/+7.98e-2; 300.0/461/+8.55e-2; 200.8/199/−1.04e-1 | Igual | ok |
| Cocientes según los pasos excluidos | 0.812/0.896/0.851/0.855; 0.967/1.006/0.983/0.988 | Igual | ok |
| FAIL de check_audit | dt025: sentinel, regime_p 592 kPa, regime_gas; base: energy_balance y regime_gas 215 m/s | Igual (también k8_base y k10b_base) | ok |
| Picos del reinicio por banco | 100/163; 94/215; 191/180; 461/300 | 99.6/163.5; 94.1/215.0; 191.4/179.8 (188.3 en 280009); 460.8/300.0 | ok, con O6 |
| 290 s con 0.25 ms | «como máximo 72 m/s y 79 kPa» | 71.6 / 78.7 solo en 290002-290010; en todo el banco **450 kPa y 128.6 m/s (paso 290093)**, 5/235 pasos ≥ 100 kPa | **objeción O1** |
| Pasos tranquilos | 0.353 (IC90 0.334-0.397); n 58/106/115; 0.844 | Igual | ok |
| Sensibilidad | umbral 0.375→0.314; ventana física 0.318/0.306/0.306; 0.27-0.84 | Igual | ok; sin {C-nnn} (O3) |
| Tabla de r con tres dt | r(e), r(Bgq), los grupos, err_liq_lk y sus IC90 | Igual, a 3 cifras | ok |
| Ajuste de tres puntos | p 1.64 (0.88-4.05); c/r1 0.46 (0.25-0.61); 72 y 1268 réplicas sin ajuste | Igual | ok |
| Variación de r(e) entre 0.5 y 0.25 ms | +1.72e-3: +1.09e-3 (63 %) / +6.2e-4 (36 %) | +1.721e-3: +1.090e-3 / +6.15e-4 | ok |
| Peso de Br+Bgr en r(e) | 1.2 / 0.75 / 0.71 % | 1.17 / 0.751 / 0.714 % | ok |
| err_liq_lk | a 8.17e-3; k 2.75e-7; 2.316e-6 frente a 2.349e-6 (1.4 %); 1.04e-2 | Igual | ok |
| Régimen de presión | pasos ≥ 100 kPa 0/11/120; ≥ 300 kPa 0/0/6; décimos; máx. 100/191/592; corr 0.15/0.32/0.52; vol_lim | Igual | ok |
| C-212: dt fijo, 236 filas, decomp 1.16e-13, eos_end 3.0e-18 | — | Igual (solo la última fila recortada) | ok |
| Recuentos de la suite | test_full 41 PASS / 27 n/a; checker actual 43 / 36 | 41/27 en el log; 43/36 recalculado sobre los 79 audit.csv | ok |
| Base de la suite (61 audit.csv de 934c2d4) | Manifiesto sha256 | La copia ya no existe | no verificable (O4) |
| Bgq de base frente a mo20 | ×1.68 | 1.684 | ok |
| Pre-registros antes de correr | 5999f40, b03b22e | Commits a las 21:57 y 23:02, antes de C-204 (22:05) y C-213 (23:06) | ok |

Verificaciones adicionales:
- **Snapshot de 280 s.** `judge_otp_280/eaf3d_00280000.h5` no es idéntico byte a byte al de `judge_fh_275`. Comparé el contenido con h5py: solo difieren 8 campos diagnósticos que se recalculan en cada paso (Lorentz, radiación, fuentes). El estado coincide, así que se sostiene la lectura de C-227.
- **Referencias de código.** Las líneas citadas de `mod_pressure_3d.f90` (gas_adv y el caudal corregido) corresponden a lo que dice el reporte.

## 2. Objeciones

1. **O1 (bloqueante).** `report.md:26-27` da «como máximo 72 m/s y 79 kPa» para 0.25 ms desde 290 s, sin indicar ventana.
   - Esas cifras valen solo para los pasos 290002-290010, la ventana de C-226.
   - En el banco completo (`campaigns/b1/k11_dt025_s290/audit.csv`), p_max llega a 450.0 kPa y u_gas_max a 128.6 m/s, ambos en el paso 290093. Además, 5 de 235 pasos tienen p_max ≥ 100 kPa.
   - Esos 450 kPa son casi los 461 kPa que el reporte presenta como la anomalía. Omitir la ventana favorece la lectura de que 290 s es una referencia limpia.
   - **Para levantarla:** acotar la cifra a 290002-290010, dar también el máximo de la ventana completa y ajustar la frase de Incertidumbre sobre la comparación desde 290 s.
2. **O2.** Faltan comandos.
   - `report.md:184-185`: D = 0.380 / 0.377 / 0.372. Los comandos citados no calculan D; los valores se reproducen con mi propio python.
   - `report.md:349`: IC90 1.075-1.146 con bloques 5/10/20, sin comando exacto. Con el mismo método obtengo 1.073-1.145.
   - **Para levantarla:** añadir esos comandos a las notas de procedencia.
3. **O3.** Afirmaciones sin `{C-nnn}`, aunque los números se reproducen.
   - `report.md:264-275`: el gas libre de k10_base es 0.66 del multifase. C-205 solo dice que es «pequeño» en los bancos de 20 externas.
   - `report.md:16-17` y `322-327`: la sensibilidad al umbral de p_max y a la ventana física.
   - **Para levantarla:** registrar un `resultado` con esas lecturas y citarlo.
4. **O4 (no verificable).** La base de los 61 audit.csv de la suite estaba en un scratchpad efímero y ya no existe; solo queda `research/ws/WS-K10/logs/base_audit_manifest.txt`.
   - Además, `test_full.txt` no registra el sha de src/ y es anterior al último cambio del checker.
   - Atenuantes verificados: el golden v132 pasa y las 137 columnas comunes de K8 frente a K10 son idénticas.
   - **Para levantarla:** archivar o regenerar la base con su log y el sha del binario, y registrar el sha del diff de src/ junto al log de test-full.
5. **O5.** El bootstrap de bloques móviles (`report.md:351-373`) da menos peso a los pasos de los bordes, que en `k10b_dt025` son justo los de la centinela.
   - La mediana bootstrap sale 0.855 frente al valor puntual 0.812.
   - Con bootstrap circular el IC90 es 0.655-0.965; con bloques no solapados, 0.445-1.013.
   - Las conclusiones no cambian: el intervalo sigue cruzando 0.75 y 0.90; Bgq queda en 0.931-0.989 y err_liq+A en 1.067-1.166.
   - **Para levantarla:** declarar el sesgo o usar bootstrap circular.
6. **O6.** `report.md:309`: los 180 m/s de 0.5 ms son del paso 280002. En 280002-280010 el máximo es 188.3 m/s (paso 280009).
   - **Para levantarla:** indicar la ventana de la tabla.

**Juicio contra el criterio pre-registrado:**
- **C-204:** aplica la letra de C-202 con su enmienda C-203 sin reinterpretarla, con el paso 280001 incluido, como fija el criterio. Las lecturas sin ese paso están marcadas como no pre-registradas.
- **C-213:** aplica la letra de C-212: 0.812 cae entre 0.75 y 0.90. Los prerrequisitos de C-212 no incluyen la centinela; el reporte lo declara y no lo usa para cambiar la etiqueta.
- **Comparación justa:** misma configuración salvo dt, mismo reinicio, misma t_final y mismo binario. El transitorio por el cambio de claves al reiniciar está declarado.

VEREDICTO: rechaza