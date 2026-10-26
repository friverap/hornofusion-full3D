# WS-K7: revisión de evidencia (ronda 1 del lanzamiento actual)

Revisión ciega: no leí `reviews/`. Solo hice lecturas. Recalculé todo con python/csv/h5py sobre los `audit.csv` y los `.h5` que ya existen, y con `check_audit.py` (que solo lee).

**Resumen:** el veredicto formal está bien. C-145 da «sin decidir» y coincide **literalmente** con el criterio de C-144: rem_all/abs = 0.3186, entre 0.3 y 0.7; neto = 1.5705 > 0.3. Todos los prerrequisitos de C-144 se cumplen y la comparación es justa. Aun así **rechazo** por una objeción bloqueante (E1): el reporte usa una comparación que él mismo declara inválida para descartar el residuo del CG.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| **C-144 → C-145** k7v5_mo20 rem_all/abs_multi | 0.319 | 5.2108e-3/1.63557e-2 = 0.3186 | ok |
| C-144 neto \|e_multi − err_liq_all\|/\|e_multi\| | 1.571 | 1.5705 | ok |
| Veredicto según la letra del criterio | sin decidir | 0.3 < 0.3186 < 0.7 y neto > 0.3 → sin decidir | ok |
| Enmienda de C-144 | ninguna | ninguna; C-144 13:01:46 < binario 13:06:13 < corrida 13:07:00 < C-145 13:38:13 | ok |
| rem_all/abs por paso: mediana y rango | 0.317; 0.302–0.381 | 0.3171; 0.3023–0.3814 | ok |
| k7v5_base: 0.404 (0.401, 0.377–0.457); neto 1.320 | — | 0.4038 (0.4010, 0.3774–0.4567); 1.3196 | ok |
| Con filtro: 0.565 / 0.626 | — | 0.5651 / 0.6263 | ok |
| err_liq_all = lk + unl (mo20) | 4.881e-4 = 4.977e-4 − 9.58e-6 | 4.8809e-4 = 4.9768e-4 − 9.583e-6; resto del split 1.19e-20 | ok |
| Σ\|unl\|/Σ\|e\| | 0.0013 (mo20), 0.0005 (base) | 2.158e-5/1.636e-2 = 0.00132; 8.73e-6/1.814e-2 = 0.00048 | ok |
| «err_liq … 99.9 % en caras enlazadas» | 99.9 % | denominador Σ\|e\|; respecto a err_liq: ≥ 99.8 % por celda, 98 % del neto | **E2** |
| Sin gas: Σ\|ρV_pois\|, Σ\|ρV_eff\| | 4.078e-3; 1.1e-16 | 4.0782e-3; 1.087e-16 | ok |
| rej/Σ\|e\| sin gas | 1.59 / 1.59 | 1.589 / 1.595 | ok |
| m_spill; vol_lim | 1.3e-12; 0.249 | 1.27e-12; 0.24892 | ok |
| liq_skip, e2_skip (los 3 bancos k7v5) | 0, 0 | 0, 0 | ok |
| Columnas bit a bit k7v5 ↔ k7v4 | solo cambian las 5 que dependen de E2 | de 110 columnas comunes difieren exactamente err_liq, rem_abs, vpois_abs, err_liq_all, rem_abs_all | ok |
| mass_gas_rewrites (mo20/base/1k) | −6.15e-14 / −7.08e-14 / −5.41e-14 | idéntico, PASS | ok |
| Barrido de tests/out | 78 PASS, máx 4.0e-12; split 66 PASS; cierre ≤ 4.0e-12 en 66 | 78/78 PASS, máx 3.97e-12; 66 PASS; 66, máx 3.98e-12 | ok |
| Logs de tests | test-unit/quick/full OK, v131, 0 FAIL | `TESTS (full): OK`, metrics_v131; los 6 «FAIL» del log son todos XFAIL | ok |
| diff_sha de status.json | — | coincide con `git diff --cached -- src tests`; árbol = staged | ok |
| Mismo reinicio, 15 ranks, configs | — | todos desde judge_otp_280/eaf3d_00280000.h5 (mtime 22-oct); base solo difiere en max_outer | ok |
| 1k: 0.333; filtro 0.590; neto 1.49 | — | 0.3333; 0.5895; 1.4878 | ok |
| 1k por tramos de 200 (5 filas × 9 columnas) | tabla | coinciden; salvo V_eff/V_pois del tramo 401–600: 2.4e-14 frente a 2.35e-14 | ok / **E6** |
| 1k: rej/nogas por paso (mediana, rango); corr con el paso; en diferencias | 1.52, 1.21–1.79; 0.10/0.91; 0.91 | 1.521, 1.214–1.789; 0.100/0.909; 0.911 | ok |
| 1k: vpois/nogas por tramo; corr en diferencias | 0.847…0.829; 0.98 | 0.847/0.835/0.834/0.830/0.829; 0.984 | ok |
| Σ\|e\|_nogas/vol_lim en los 4 bancos | 1.94/1.94/1.98/2.04e-2 | 1.935/1.941/1.982/2.039e-2 | ok (ver E1) |
| k7v4_long: corr nogas–vol_lim; tendencias; en diferencias; por tramos | 0.97; 0.965/0.992; 0.46; 0.94…0.40 | 0.971; 0.965/0.992; 0.464; 0.94/0.72/0.18/0.48/0.57/0.39/0.23/0.21/0.40 | ok |
| Subconjunto con gas: 1.154e-2 frente a 1.331e-2 (+15 %); rem/abs 0.38/0.49 | — | 1.1539e-2/1.3308e-2 (+15.3 %); 0.384/0.491 | ok |
| ρ_g medio; masa reconstruida = m_gas; 6 % | 0.304; 52.97 = m_gas; 6 % | 0.3043; 52.974 frente a m_gas 52.937; 6.4 % | ok / **E5** |
| 406 celdas multifase con α_g = 0 en 280059, todas de baño | 406 | 406; α_l ∈ [0.995, 1], α_s ≤ 0.005 | ok |
| Tabla k7_*: e_multi, err_liq, resto, abs, rem, nogas, vpois/veff, 0.566, 2.456, base | todas | todas coinciden (p. ej. 2.4557, 0.5660, 0.6261, 0.8556) | ok |
| vp/ve: 3.87 (mediana 3.91, rango 3.29–4.53; base 3.90) | — | 3.873 (3.910, 3.286–4.533; 3.896) | ok |
| k7 ↔ k7v3: \|dif\|/\|val\| | ≤ 2.4e-16 | 2.42e-16; p_max/m_gas/E/u_gas bit a bit | ok |
| sonda_gc ↔ k7v5: 5 columnas bit a bit | sí | sí (m_gas_volfix difiere en el último ulp; no está declarada) | ok |
| Tabla k7v3 (err_liq_all, nogas, 84 %, rem_all, 0.319/0.404, 1.582/1.319, comp_abs, eos_abs y medianas) | todas | todas coinciden | ok |
| Tabla k7v4 (nolink 0; 1.38/1.08; 4.0e-4/2.8e-4; 1.95/1.93; correlaciones) | todas | todas coinciden | ok |
| audit_r1 ↔ audit (k7v4_mo20) | 13 columnas idénticas | 108 columnas comunes, 0 diferencias | ok |
| corr(all,e) 0.229, corr(e − a, e) 0.972, 0/59; filtro −0.016 / 0.540 | — | idéntico | ok |
| sd 7.9e-7 / 3.35e-6, r = 0.236; fórmula → 0.9717 | — | pstdev 7.91e-7/3.351e-6; fórmula 0.9718 | ok |
| Cotas por subconjunto: [2.67, 4.24]e-3, ≥ 71 %, [0.81, 1.29], e_gas, [0.16, 0.42] | — | 2.669–4.239e-3; 0.706; 0.815–1.294; −5.095…−3.525e-3; 0.161–0.420 | ok |
| e_out 9.24e-4; corr −0.09/0.00/−0.004 | — | 9.244e-4; −0.087/0.002/−0.0041 | ok |
| «e_out cambia de signo por tercios» | sí | tercios de e_out +0.0696/+0.0951/+0.0690 kg | **E3** |
| Resto/err_liq (−0.707, sd 0.081, …); corr con vpois y vol_lim; corr(e, vol_lim) | — | coinciden (−0.707, 0.081, −0.95..−0.46, −0.850; 0.976, −0.853/−0.890; +0.517/+0.708; −0.06/−0.55) | ok |
| eos_abs: 26.4×, 26.5×, 51×, 8e3×, 127× | — | 26.44, 26.46, 51.4/51.5, 7832, 126.5 | ok |
| k7v4_long por tramos de 500 (11 filas × 6); 0.504/0.712; 53 %; e/paso por tramos; ×1.85 | — | coinciden | ok |
| k7v4_long: nolink 51 845, 7.47e-3 (0.36 %), E2 1.1e-14; comp/eos; 38× | — | coinciden | ok |
| k7v4_long: tolerancia vieja 3.26e-10 | — | 3.258e-10 | ok |
| k7v4_long: «tolerancia 7.8e-8»; lista de FAIL | — | check vigente: 7.8e-10; falta FAIL energy_balance_step 1.878 | **E4** |
| Fila 280059: base ↔ larga (dt, err_multi) | 9.9999971e-4 / 1e-3; −2.61196 / −2.61190e-5 | idéntico; solo difiere la fila 59 (76 columnas) | ok |
| CG: res 3.2e-2, ≥ 1001 casos; k7_base 1 aviso; n_pc_max = 1 (:111) | — | idéntico | ok |
| k7_base FAIL energy 2.243 y regime_gas 215; mo20 0.050 / 163.5 | — | idéntico | ok |
| Tercios de la ventana corta 0.323/0.318/0.318; p_max pasos 2–3 frente a mediana | 1.0e5 / 4.2e4 | k7v4: igual; k7v5: 0.323/0.317/0.316; 9.5e4–9.96e4 / 4.22e4 | ok |
| Duraciones y ranks (34 min, 13.5 min, 15) | — | 11:08:47→11:42:54; 13:07:19→13:20:52; 15 | ok |
| Líneas de src citadas en el diff staged (:249) | — | `sed`/`grep` coinciden todas; check_audit.py:434 | ok |
| Cifras históricas (67 bancos, 64 evaluaciones, 10:50:51, Proceso 7) | — | no reproducibles con los archivos actuales | **E7** |

## 2. Objeciones

1. **E1 (bloqueante).** En `report.md:116`, inciso (c), dice «eso lo separa de un residuo del CG o del lazo truncado». Eso contradice `report.md:219` («El confusor del CG NO está acotado… no mide el efecto del residuo del CG») y `:220` («toda comparación 5↔20… no decide y no se generaliza»).
   - `campaigns/b1/k7v5_base` da FAIL energy_balance 2.243 y regime_gas 215.0.
   - El CG es idéntico en los dos bancos (max_iter 20, tol 1e-8) y en base no se conoce la fracción convergida (1 aviso).
   - El inciso (a) usa 4 bancos y 3 de ellos fallan check_audit (k7v5_base; k7v5_mo20_1k con regime_gas 209; k7v4_long con 6 FAIL).
   - Ambos datos sostienen la lectura de C-146, en estado «soportada».
   - Para levantarla: retirar «del residuo del CG»; dejar «lazo truncado» solo como compatible y declarar qué bancos fallan check_audit; registrarlo con `--ref C-146`. O medir el CG (max_iter mayor o recuento de no convergidos).
2. **E2.** En `report.md:95/:195` y en C-145, el «99.9 %» toma como denominador Σ|e| (0.13 %), no err_liq.
   - Recalculado: Σ|unl|/Σ|err_liq_all| ≤ 0.19 %, con Σ|err_liq_all| ≥ 1.636e-2 − 5.211e-3 = 1.115e-2.
   - unl/err_liq_all neto = −2.0 %.
   - Hay que reescribirlo con el denominador correcto.
3. **E3.** `report.md:224` (5) dice que e_out cambia de signo por tercios. En `campaigns/b1/k7v4_long/audit.csv` las sumas por tercio de e_out son +6.96e-2, +9.52e-2 y +6.90e-2 kg. Lo que cambia de signo es e_multi + e_out (+1.36e-2, +2.25e-2, −2.67e-2).
4. **E4.** En `report.md:171`, la «tolerancia 7.8e-8» sale hoy 7.8e-10 con `check_audit.py:434`. Hay que rotularla como del cuarto ciclo y añadir el FAIL energy_balance_step (1.878) que falta en la lista.
5. **E5.** En `report.md:116` dice que 52.97 kg «coincide con m_gas». El `m_gas` de `campaigns/b1/k7v5_mo20/audit.csv` en el paso 280059 es 52.937 kg (diferencia 0.07 %). Hay que declararlo como aproximado.
6. **E6.** En `report.md:203`, tramo 401–600, aparece 2.4e-14; recalculado da 2.35e-14. Es trivial.
7. **E7.** En `report.md:119/:121/:167`, las cifras históricas (67 bancos, 64 evaluaciones, tolerancia 1e-9, mtime 10:50:51) citan fuentes que ya no las reproducen (logs sustituidos, `src/mod_audit.f90` ahora con mtime 13:04:15). Hay que marcarlas como históricas, igual que se hizo con C-123.
8. **E8.** Hay viñetas sin `{C-nnn}`: `report.md:117, :166, :169, :195, :210, :220, :222, :228, :230`. Hay que añadir las ids.
9. **E9.** C-144 no está commiteada (HEAD 6579277 llega solo a C-121), en contra de `.claude/rules/research.md`. El orden se verificó solo con el ts automático de `ledger.py` y con `ledger.py check` OK. No es bloqueante porque el veredicto es «sin decidir».
10. **E10.** En `report.md:196`, «ws_lim_step = 0 ahí» y «rechazada íntegra» no están medidos: rej > 0 solo prueba s < 1 en alguna celda. Hay que declararlo como inferencia del código o añadir una columna.

Para levantar el rechazo hace falta resolver E1. E2–E10 son correcciones de texto y procedencia.

VEREDICTO: rechaza