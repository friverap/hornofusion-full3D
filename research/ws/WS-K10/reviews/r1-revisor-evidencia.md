## Revisión de evidencia: WS-K10, ronda 1

Revisión hecha en solo lectura. Repetí en python cada comando de procedencia sobre `campaigns/b1/*/audit.csv`, `research/ledger.jsonl` y `research/ws/WS-K10/logs/`. No compilé ni corrí nada.

### Validez de los pre-registros y de la comparación

| Predicción | Registro | Primera escritura del banco | Binario |
|---|---|---|---|
| C-202 | commit 5999f40, 21:57:42 | k10_mo20 a las 21:58:28 | k10_opt d5827e70 (21:58:21) |
| C-212 | commit b03b22e, 23:02:09 | k10b_dt025 a las 23:02:22 | k10b_opt 5409bbe9 (22:37:45, sin cambios después) |
| C-231 | commit 798e2ad, 00:16:51 | k11_dt05_s290 a las 00:16:58 | k10b_opt |

- `piezas.py` frente a la versión pre-registrada: solo se añadió `--sin-paso1`; la lógica del veredicto no cambió.
- `h14.py` no cambió desde 798e2ad.
- Los configs de k11_{mo20,dt05,dt025}_s290 solo difieren en dt y output_dir: mismo snapshot `eaf3d_00290000.h5`, mismo binario, mismas claves. Lo mismo vale para k10b_* desde 280 s.
- La fila `step=280000/290000` es la fila inicial con error 0. El filtro `step > p0+1` excluye esa fila y el paso de reinicio, así que salen 58, 117 y 235 pasos, como dice el reporte.
- `ledger.py check`: OK.

### Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| C-202: Br/e (1 ms; 0.5 ms) | −0.683; −0.135 | −0.683; −0.135 | ok |
| C-202: Br(0.5)/Br(1) | 0.184; SIN DECIDIR | 0.184; SIN DECIDIR (piezas.py) | ok |
| Prerrequisitos de C-204: columnas comunes | 137 idénticas | 137 idénticas en los 3 pares (cmp_comunes --par) | ok |
| Prerrequisitos de C-204: row_volume | 2.2e-14 m³ | 2.20e-14 | ok |
| Prerrequisitos de C-204: decomp | ≤2.1e-13 kg | 2.13e-13 | ok |
| Prerrequisitos de C-204: AVISO | 0/0/1 | 0/0/1 | ok |
| Prerrequisitos de C-204: dec_skip | 0 | 0 | ok |
| PASS de los k10_* con el checker actual | restos 2.9e-14, 5.8e-14, 2.9e-14; tol 1.41-1.46e-11 | 2.91e-14, 5.81e-14, 2.91e-14; 1.41-1.46e-11 | ok |
| k10b_*: tolerancias; eos_end | 8.9e-11 a 1.1e-9; ≤2.3e-18 | 8.89e-11 a 1.09e-9; 2.31e-18 | ok |
| Paso 280001 de k10_dt05: eos_multi; e; % de la suma | −7.97e-4; −1.056e-3; 66 % | −7.966e-4; −1.0557e-3; 66.4 % | ok |
| D de 0.5 frente a 1 ms (tres pares) | 0.380 / 0.377 / 0.372 | idéntico en los 3 pares | ok |
| Tabla de 280 s, medias de las 10 piezas × 3 bancos | p. ej. e −1.4505e-5 / −4.572e-6 / −2.661e-5 | todas coinciden (piezas.py --sin-paso1) | ok |
| IC90 por bloques de 10/20 | e 0.315 (0.30-0.34), Bgq 0.39, err_cc 0.56 (0.35-1.14)… | 0.315 (0.301-0.341), 0.388, 0.560 (0.350-1.143) | ok |
| IC90 por bloques de 5/10 | 0.29-0.35 | 0.294-0.347 | ok |
| Error estándar de err_cc | ±3.5e-7; ±1.2e-7 | 3.5e-7; 1.2e-7 | ok |
| sd/\|m\| y correlaciones | 0.057/0.069; 0.07/−0.03; 0.89/0.99; −0.48/−0.37/+0.08; 0.37/0.49/0.22 | idénticos | ok |
| k10_base: store, e_free, err_cc_free, store_free, Bx | 4.16e-5; −1.756e-5 (0.66); −1.62e-5; 6.75e-5; 4.27e-6/4.33e-6 | 4.1555e-5; −1.7562e-5 (0.660); −1.6207e-5; 6.7517e-5; 4.27e-6/4.33e-6 | ok |
| k10_base: quintos de store, Bgq y err_free | 4.0-4.3e-5; −3.7 a −3.85e-5; −1.5e-6 a −3.7e-5 | 4.01-4.33e-5; −3.68 a −3.85e-5; −1.54e-6 a −3.71e-5 | ok |
| Centinela de 0.25 ms (3 pasos) | 198.6/281, 300.0/461, 200.8/199 | idéntico (centinela.py) | ok |
| Cocientes al excluir pasos | 0.812/0.896/0.851/0.855 | idéntico | ok |
| Pasos tranquilos | 0.353 (0.334-0.397) | idéntico | ok |
| Sensibilidad al umbral de p_max | 0.375 a 0.314 | idéntico (sensibilidad.py) | ok |
| Sensibilidad a la ventana física | 0.318/0.306/0.306; 0.863/0.989/1.057 | idéntico (sensibilidad.py) | ok |
| C-212: r(e) | −1.4505e-2, −9.145e-3, −7.424e-3 | idéntico | ok |
| C-212: r(0.25)/r(0.5) y veredicto | 0.812; SIN DECIDIR | 0.812; SIN DECIDIR (tasa.py) | ok |
| Tabla de 3 dt, bootstrap móvil | p 1.64 (0.88-4.05), c/r1 0.46 (0.25-0.61), 72 y 1268 sin ajuste | idéntico | ok |
| Tabla de 3 dt, bootstrap circular | e 0.655-0.965, mediana 0.816 | idéntico | ok |
| Bloques no solapados (regimen.py) | 0.445-1.013 | idéntico | ok |
| Régimen de presión (pasos ≥100 kPa, décimos, máximos, r por régimen, corr, vol_lim) | tabla | idéntico | ok |
| Máximos por ventana (pasos 2-10 y ventana completa) | 100/163, 94/215, 191/188, 461/300, 55/124, 79/72; 450 kPa y 128.6 m/s en 290093; 5 de 235 | idéntico | ok |
| Paso 1 desde 290 s y tgfix | −1.731e-3/−1.735e-3; −5.06e-5; +5.32e-4; 2.17e-5/2.07e-5; −7.23e-3/−7.42e-3 | idéntico | ok |
| Tabla de 280 s frente a 290 s (11 piezas, /e e IC90) | p. ej. 0.512 (0.45-0.62) y 0.833 (0.82-0.85) | todas coinciden | ok |
| Quintos (280 s; 290 s) | −1.38 a −1.50e-5; −4.80 a −5.09e-5 | idéntico | ok |
| Ajuste lineal con dos puntos | ~78 %; 26 % | 77.7 %; 26 % | ok |
| H14 por unidad de tiempo (e, Bgq, err_liq, err_cc, A, Br+Bgr) | tabla | idéntico (h14.py) | ok |
| C-231 (a) | 0.877 ∈ [0.85, 1.00]: SOPORTADA | 0.877: SOPORTADA | ok |
| C-231 (b) | 6.996e-6 ∈ [5.88e-6, 7.96e-6]: SOPORTADA | 6.996e-6: SOPORTADA | ok |
| C-231: prerrequisitos | 0 AVISO, sin FAIL, 3 PASS, p_max máx. 71 kPa | 0; ninguna línea FAIL; 5.73e-14 y 2.30e-18; 70.6 kPa | ok |
| H14, bootstrap circular | 0.860-0.894; 0.949 (0.925-0.972); p 1.47 (0.81-2.43); c/r1 0.81 (0.73-0.84); 0 sin ajuste; incr. de lk 0.71 (0.40-1.16) | idéntico | ok |
| H14, bootstrap móvil | 0.862-0.891; 0.936-0.972; 0.77-0.84; 0.43-1.20 | idéntico | ok |
| k = 0 en el intervalo; interpolación lineal; k por par | [6.83e-6, 7.12e-6]; 7.02e-6; 3.4e-7/1.2e-7 | idéntico | ok |
| Interpolaciones lineal / dt² / dt^0.5 | 0.888/0.866/0.902 | 0.888/0.866/0.902 | ok |
| a y k (280 s y 290 s) | 8.17e-3/2.75e-7; 1.346e-2/1.93e-7 | idéntico | ok |
| Confusor de 290 s: p_max medio; u_gas_max medio | 30.8/35.2/45.1 kPa; 98.9/78.1/69.3 m/s | idéntico | ok |
| Confusor de 290 s: excluir t ≤ t0 | 0.961/0.969/0.984 | idéntico | ok |
| Confusor de 290 s: r por tramos de 12 ms | −3.9e-2 al inicio, luego −4.0 a −4.2e-2 | idéntico | ok |
| k11_base_s290 | e −6.77e-5; Bgq −7.92e-5; store 4.66e-5 frente a 6.1e-7 (×77); free −2.21e-5; Bx 2.4e-6/1.6e-6; gap/permitido 2.15; u_gas_max 106.9 m/s | idéntico | ok |
| Parte de r que depende de dt | 12-19 % | sin procedencia; 1 − c/r1 = 0.19 (IC 0.16-0.27) | objeción O1 |
| Suite: conteos | 79 = 61 + 18; 77 = 61 + 16; 9 sin flujo; 41/27; 43/36 | idéntico | ok |
| Suite: logs | test_full OK con v132 y diff_sha 660ee6ac | sha staged recalculado = 660ee6ac | ok |
| Suite: base de 61 idénticos | no verificable | copia hallada; manifiesto 61/61; cmp: 61 idénticos; procedencia de 934c2d4 sin verificar | objeción O2 |
| Párrafo «Tests (log anterior)» | 41/27 «del checker previo» | log sustituido, no verificable | objeción O3 |

### Veredictos frente a la letra del criterio

- **C-202 → SIN DECIDIR.** Coincide con la letra. Se juzgó con el paso 280001 incluido, como fija el criterio (`step > 280000`).
- **C-212 → SIN DECIDIR.** Coincide con la letra: 0.812 queda entre 0.75 y 0.90.
- **C-231 → SOPORTADA por la letra en (a) y (b).**
  - Coincide con la letra.
  - El reporte no reinterpreta el criterio. Declara que la rama de refutación de (a) era inalcanzable con una r monótona y que (b) no tenía poder frente a k = 0 {C-234}{C-235}.
  - Atribuye «mayormente tasa» a una lectura no pre-registrada.

No hay enmiendas posteriores a ningún veredicto. C-203 es anterior a la corrida y tiene motivo.

### Muestra

El reporte declara bien sus límites:
- una trayectoria por dt;
- 60 ms por ventana;
- IC90 calculados dentro de una sola trayectoria;
- dos ventanas cuyas magnitudes difieren ×3.4;
- el confusor de régimen: p_max medio de 31, 35 y 45 kPa;
- la config de B1 sin medir entre dt.

No encontré conclusiones que vayan más allá de esa muestra.

### Objeciones (ninguna bloquea)

1. **O1. «12-19 %» sin procedencia.** Está en `report.md`, H14 «Confusor de régimen» y resumen (a). Mezcla 1 − r(0.5)/r(1) = 0.123 con 1 − c/r(1 ms) = 0.19. El IC90 de c/r(1 ms), 0.73-0.84, implica una parte dependiente de dt del 16 al 27 %. Para levantarla: usar una sola definición con su IC y citar el comando de H14.
2. **O2. Base de la suite.**
   - La copia existe en `/private/tmp/claude-502/-Users-frariv-Horno/68c200c2-efa4-46c5-a9ff-3c767a24d56a/scratchpad/k10_base`. Coincide en 61 de 61 archivos con `research/ws/WS-K10/logs/base_audit_manifest.txt`, y `cmp_comunes.py` da 61 idénticos.
   - Sigue sin poder verificarse que venga de 934c2d4 (mtime 21:22:06, sin binario ni log).
   - Para levantarla: corregir la frase «no visible», citar la ruta y archivar la copia o regenerarla con log.
3. **O3. Log sustituido y atribución de los conteos.**
   - «Tests (log anterior)» describe un log que ya no existe; no puede verificarse.
   - La diferencia entre 41/27 y 43/36 se debe al modo de invocación (arnés frente a llamada directa), no a «el checker de entonces». En el log actual tampoco hay líneas `mass_gas_*` en los 9 bancos sin flujo.
   - Para levantarla: retirar o marcar ese párrafo y corregir la atribución.

VEREDICTO: aprueba
