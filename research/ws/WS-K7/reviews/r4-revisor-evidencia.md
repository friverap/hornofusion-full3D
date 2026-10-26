# Revisión de evidencia — WS-K7, ronda 1 (revisión ciega)

Alcance: cada número de `research/ws/WS-K7/report.md` recalculado desde `campaigns/b1/k7*/audit.csv` con python propio (csv, statistics), `check_audit.py` en modo lectura sobre los 10 bancos y sobre `tests/out/**` (78 bancos), logs de tests, configs, run.log, mtimes y código. Veredicto {C-145} comparado literalmente con el criterio de {C-144}. No se leyó `reviews/`.

## 1. Tabla afirmación / reporte / recalculado

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| **C-144 → C-145, inciso por celda (k7v5_mo20)** | 0.319 (sin decidir) | 5.2108e-3/1.6356e-2 = **0.3186**; mediana 0.3171, rango 0.3023–0.3814 | ok |
| **C-144 → C-145, inciso del neto** | 1.571 (> 0.3) | \|−8.5549e-4 − 4.8809e-4\|/8.5549e-4 = **1.5705** | ok |
| Veredicto literal según criterio C-144 | sin decidir | 0.3 < 0.3186 < 0.7 y neto > 0.3 → **SIN DECIDIR** | ok |
| k7v5_base por celda / neto / filtro | 0.404 / 1.320 / 0.626 | 0.4038 (0.4010, 0.377–0.457) / 1.3196 / 0.6263 | ok |
| k7v5_mo20 con filtro (C-126) | 0.565 | 0.5651 | ok |
| err_liq_all = lk + unl (mo20) | +4.881e-4 = +4.977e-4 + (−9.58e-6) | 4.8809e-4 = 4.9768e-4 + (−9.583e-6); split resto 1.19e-20 | ok |
| err_liq_all = lk + unl (base) | +5.022e-4 = +5.021e-4 + 1.64e-7 | 5.0224e-4 = 5.0207e-4 + 1.643e-7; resto 2.37e-20 | ok |
| Σ\|unl\|/Σ\|e\| | 2.16e-5/1.636e-2 = 0.0013; base 8.73e-6 → 0.0005 | 2.158e-5 → 0.00132; 8.734e-6 → 0.00048 | ok |
| Expectativa (i) C-144: Σ\|unl\| ≤ 0.2 Σ\|err_liq_all\| | cumplida | 0.044 ≤ 0.2 | ok |
| Nogas: Σ\|ρV_pois\|, Σ\|ρV_eff\|, cociente | 4.078e-3, 1.1e-16, 0.000 (base 4.086e-3) | 4.0782e-3, 1.09e-16, 2.7e-14 (base 4.0862e-3, 1.07e-16) | ok |
| rej_nogas / Σ\|e\| nogas | 7.655e-3/4.816e-3 = 1.59; base 1.59 | 7.6547e-3 → 1.589; base 7.7054e-3 → 1.595 | ok |
| m_spill; vol_lim | 1.3e-12 kg; 0.249 m³ | 1.270e-12; 0.2489 | ok |
| mass_gas_rewrites k7v5 (tol 1e-11) | −6.15e-14 / −7.08e-14 PASS | −6.148e-14 / −7.080e-14; tol 1e-11×0.8445 | ok |
| liq_skip, e2_skip; 14 columnas bit a bit con k7v4 | 0, 0; sí | 0, 0; 14/14 bit a bit (solo cambian err_liq, _all, rem, rem_all, vpois) | ok |
| corr k7v5 | +0.233, +0.970, 0/59; base −0.428, +0.993, 0/59 | idéntico | ok |
| **k7v5_mo20_1k** totales | 0.333 / 0.590 / 1.49; unl 9.1e-4 = 0.3 %; neto −6.0e-4, lk +8.8e-3; veff/vpois 2e-14; rej 1.53; resto −5.4e-14 (Σ\|dm\| 14.4); split 6.5e-19; u_gas 209 | 0.333 / 0.590 / 1.488; 9.15e-4 = 0.32 %; −5.99e-4; 8.81e-3; 2.4e-14; 1.528; −5.41e-14 (14.41); 6.51e-19; 209.0 FAIL regime_gas | ok |
| Tabla por tramos de 200 (5 filas × 9 col.) | — | todas las celdas coinciden al redondeo mostrado | ok |
| 59 primeras filas 1k = k7v5_mo20 salvo la última | sí | 280000–280058 idénticas; 280059 dt 9.9999971e-4 vs 1e-3 | ok |
| **k7_mo20 / k7_base** (12 cantidades de la tabla) | −8.555e-4, −2.956e-3, +2.101e-3, 1.636e-2, 9.257e-3, 4.816e-3 (29 %), 8.80e-3/2.28e-3, 0.566, 2.456; base −1.571e-3, −2.916e-3, 1.345e-3, 1.814e-2, 1.136e-2, 4.832e-3 (27 %), 8.80e-3/2.26e-3, 0.626, 0.856 | −8.5549e-4, −2.9563e-3, 2.1008e-3, 1.6356e-2, 9.2565e-3, 4.8164e-3 (29.4 %), 8.799e-3/2.275e-3, 0.5660, 2.4557; base −1.5715e-3, −2.9161e-3, 1.3446e-3, 1.8140e-2, 1.1358e-2, 4.8322e-3 (26.6 %), 8.802e-3/2.259e-3, 0.6261, 0.8556 | ok |
| k7_* reproducidas con k7v3/k7v4 | \|dif\|/\|val\| ≤ 2.4e-16; 5 columnas bit a bit | 1.7e-16…2.4e-16; p_max/m_gas/E_liq/E_gas/u_gas_max bit a bit (también con sonda_gc_*) | ok |
| Por paso k7_mo20: rem/abs mediana, rango; V_pois/V_eff | 0.574, 0.539–0.612; 3.87 (3.91, 3.87, 3.29–4.53; base 3.90) | 0.5740, 0.5391–0.6120; 3.867 (3.910, 3.871, 3.286–4.533; base 3.896) | ok |
| Correlaciones k7_mo20/base | −0.016/0.540; 0.976; −0.853/−0.890; corr(e,vol_lim) −0.06/−0.55; resto/err_liq −0.707 sd 0.081 (−0.95..−0.46), corr −0.850; base −0.46 sd 0.10 (−0.70..−0.27), −0.39 | todos idénticos | ok |
| m_gas_comp neto; e media/sd/signos; m_alpha_clip; m_melted; e_out | +4.1e-5; −1.45e-5, 3.4e-6, 59/59; 1.3e-12 (max 4.7e-14); 2.04; +9.24e-4 | 4.088e-5; −1.450e-5, 3.38e-6, 59/59; 1.349e-12 (4.70e-14); 2.038; 9.244e-4 | ok |
| **k7v3** (C-130/C-131) | +4.977e-4/+5.021e-4; nogas +3.454e-3/+3.418e-3; 7.85e-4/7.96e-4 (84 %); 5.225e-3/7.322e-3; 0.319 (0.318, 0.304–0.381)/0.404; 1.582/1.319; 2.271e-3/2.256e-3; 0.4324 (7.32e-3)/0.4284 (7.25e-3) | 4.9768e-4/5.0207e-4; 3.4540e-3/3.4182e-3; 7.847e-4/7.963e-4 (83.7 %); 5.2248e-3/7.3221e-3; 0.3194 (0.3176, 0.3039–0.3813)/0.4036; 1.5817/1.3195; 2.2714e-3/2.2562e-3; 0.43241 (7.322e-3)/0.42836 (7.251e-3) | ok |
| 26.4× y 26.5×; 7.8e3×; 127× | sí | 0.4324/1.636e-2 = 26.4; 7.322e-3/2.767e-4 = 26.5; 0.4324/5.521e-5 = 7831; 0.4324/3.418e-3 = 126.5 | ok |
| Cotas por subconjunto (C-142) | e_nogas ∈ [2.67e-3, 4.24e-3], 0.29, ≥ 71 %; e_gas ∈ [−5.09e-3, −3.53e-3], [0.16, 0.42] | [2.669e-3, 4.239e-3], 0.294, 0.706; [−5.094e-3, −3.525e-3], [0.161, 0.420] | ok |
| sd(err_liq_all)/sd(e); fórmula | 7.9e-7/3.35e-6 = 0.24; 0.9717 | 0.236 (psd 7.9e-7 / 3.35e-6); fórmula 0.9717 = corr medida 0.972 | ok |
| corr k7v3 | 0.229/0.972/0; base −0.429/0.993/0; vol_lim +0.517/+0.708 | idéntico | ok |
| **k7v4** (C-135/C-139) | 3.125e-3 (1.38×)/2.428e-3 (1.08×); nogas 1.908e-6 (4.0e-4)/1.334e-6 (2.8e-4); 0.841 (1.95×, 1.42e-2)/0.829 (1.93×, 1.40e-2); 51×; nolink 0/0/0; −6.15e-14/−7.08e-14 | 3.1246e-3 (1.376)/2.4279e-3 (1.076); 1.908e-6/1.334e-6; 0.84134 (1.946, 1.424e-2)/0.82864 (1.934, 1.404e-2); 51.4; 0/0/0; idéntico; 13 columnas bit a bit con k7v3; audit_r1.csv idéntico | ok |
| **k7v4_long** | −3.23e-14; Σ\|dm\| 78.35; tol vieja 3.3e-10 (0.3243, 52.9, piso 1.5e-12); nolink 51 845, 7.47e-3 = 0.36 % de 2.048, E2 1.1e-14; 0.504/0.712; −0.234/0.999/726; 0.235 (nogas 4.2e-4); 78.1 = 38×; e/paso −2.96e-5…−5.46e-5; 53 % ≥ 0.7 | −3.228e-14; 78.350; 3.258e-10 (0.3243, 52.9, 1.53e-12); 51845, 7.467e-3 = 0.36 % de 2.0483, 1.13e-14; 0.5037/0.7125; −0.234/0.9992/726; 0.2353 (4.18e-4); 78.11 = 38.1×; −2.959e-5, −3.238e-5, −4.016e-5, −4.238e-5, −5.261e-5, −5.460e-5; 2907/5499 = 52.9 % | ok |
| Tabla por tramos de 500 (11 filas × 6 col.) | — | todas coinciden | ok |
| corr(Σ\|e\|_nogas, vol_lim) 1–4500 / 1–2000 / 1–500 / 4501–5499; cociente 2.0e-2 | 0.97/0.94/0.88/0.34 | 0.971/0.938/0.877/0.339; cociente 1.97e-2…2.14e-2 por tramos | ok |
| En 59 pasos vol_lim ±1 % y corr 0.22–0.35 | sí | ±1.2 %; +0.221 (mo20) / +0.350 (base) | ok |
| Fila 280059 base ↔ long | dt 9.9999971e-4 vs 1e-3; err −2.61196e-5 vs −2.61190e-5; 1–58 idénticas | idéntico (76 de 110 columnas difieren en 280059) | ok |
| k7v4_long check_audit | FAIL energy 2.42×, mass_gas 0.547, u_gas 300, regime_p 5.02e5 | 2.418, 0.5471, 300.0, 5.017e5 | ok |
| k7_base no pasa check_audit | gap −4.688e3 / 2.090e3 = 2.243; u_gas 215; mo20 0.050, 163.5 | idéntico | ok |
| Tests | unit/quick/full OK, golden v131, 0 FAIL; 78 bancos rewrites 0 FAIL max 4.0e-12; split 66; cierre 66 ≤ 4.0e-12 | logs: `UNIT TESTS: OK`, `TESTS (quick): OK`, `TESTS (full): OK`, metrics_v131, tol 1e-11 en el log; barrido tests/out: 78 evaluados, 0 FAIL, max 3.97e-12; split 66/0; cierre 66, max 3.985e-12 | ok |
| CG no convergido | ≥ 1001 de 1180 (84.8 %); base ≥ 1 y < 1001 | run.log mo20: avisos en casos 1 y 1001 (res 5.9e-2, 3.2e-2); base 1 aviso | ok |
| Binarios/mtimes | k7v5 13:06:13 tras src 13:04:15; k7v4 10:51:19 tras 10:50:51; k7col 20:38:11 > k7_mo20/audit.csv 20:02:17 | idéntico; C-144 13:01:46 < src < bin < csv < logs 13:23–13:37 < C-145 13:38:13 | ok |
| Comparación justa | mismo reinicio, 15 ranks, configs iguales salvo clave | 10 bancos desde judge_otp_280/eaf3d_00280000.h5, 15 ranks (1×5×3); diff config = output_dir (+ max_outer 20/5, t_final, output_freq); solve_slag false; n_pc_max = 1 por defecto | ok |
| Numérica idéntica k7v5 («solo un array que lee el audit») | sí | ws_pc_unl_used escrito solo en mod_pressure_3d (:213/:653/:672/:749), leído solo en mod_audit (:1078/:1085); invariantes bit a bit | ok |
| Tiempos 34 min / 13.5 min | — | 2039.8 s / 811.7 s | ok |
| status.json diff_sha; plan; ledger check | — | f8f42df3… = sha256(`git diff --cached -- src tests`); plan existe (12:55); `ledger OK (145 eventos)` | ok |
| «lk reproduce exactamente err_liq_all de k7v4» | exactamente | igual a 1.1e-15 relativo, no bit a bit (dentro del redondeo mostrado) | ok (nota) |
| Líneas de código citadas (mod_pressure_3d, mod_audit, check_audit) | :209, :649, :663-667, :767, :1220, :1243, :1730-1734; :872-888, :998, :1015, :1039-1040; :398-417 | desfasadas: :210, :652, :671-672, :784, :1237, :1260, :1747-1751; :899-915, :1036, :1053, :1078; :419-437 | **objeción E1** |

## 2. Objeciones

**E1 (no bloqueante) — procedencia por líneas desfasada.** `src/mod_pressure_3d.f90` y `src/mod_audit.f90` se editaron el 25-oct 13:04 (quinto ciclo) después de fijar los números de línea de las rondas 5-6 (C-141/C-142), y el reporte sigue diciendo «en el diff en revisión del 25-oct». En el diff staged actual: `ws_Fg_r = 0` está en :210 (no :209); `Su += ws_pc_unl` en :652 (no :649); `Su = 0` en inactivas/selladas en :671-672 (no :663-667); llamada al CG en :784 (no :767); `af = 0.5_dp*(aef(P)+aef(vecina))` en :1203/:1237/:1286/:1320/:1369/:1405 (no :1186/:1220/…); `Fg_r = af*u_f*A` en :1260 (no :1243); `link` en :1747-1751 (no :1730-1734); `audit_comp_cell`/`audit_eos_cell` en :899-905/:909-915 (no :872-888); identidad `ee` en :1036 (no :998); `case default` en :1045; `lk_any` en :1053 (no :1015); `vp += dt·ws_pc_unl_used` en :1078 (no :1039-1040); tolerancia por llamada en `check_audit.py:419-437` (no :398-417). `:231-233` son comentarios, no la definición de `act_g`. Verifiqué que cada construcción existe y dice lo que el reporte afirma (en particular la α de cara MEDIA en el ensamblaje y en `Fg_*`, base de R1/R6), por eso no bloquea. Para levantarla: actualizar las líneas al diff staged o citar por patrón `grep -n`, y anotar que las líneas de C-141/C-142 corresponden al diff del cuarto ciclo.

Nota (sin objeción): «reproduce exactamente» para lk(k7v5) ↔ err_liq_all(k7v4) es igualdad a 1.1e-15 relativo, no bit a bit; el valor mostrado (+4.977e-4) coincide.

## 3. Juicio sobre el veredicto y la muestra

- {C-145} coincide LITERALMENTE con el criterio pre-registrado de {C-144}: 0.3186 ∈ (0.3, 0.7) y neto 1.5705 > 0.3 → «sin decidir», registrado como `en_disputa`. No hay enmienda posterior ni reinterpretación en prosa que apruebe nada: las lecturas de mecanismo (válvula de Plan E en nogas, desfase E2 despreciable) corresponden a las expectativas (i)-(iii) declaradas en C-144 antes de correr, con sus umbrales (≤ 0.3, ≥ 0.5, ≥ 0.7) y se reportan «cumplidas», no deciden H.
- Prerrequisitos de C-144 cumplidos en su totalidad (ver tabla). El pre-registro (13:01) precede a la última edición de `src/` (13:04), al binario (13:06), a las corridas (13:07–13:20), a los tests (13:23–13:37) y al veredicto (13:38).
- Muestra: 59 pasos tras reinicio con transitorio (p_max 1e5 en los pasos 2-3); el reporte lo declara y el banco de 1000 pasos con 20 externas (primeras 59 filas idénticas al banco corto) mantiene el cociente en 0.314–0.349 por tramos, dentro de la banda «sin decidir» con la que se cierra; la ventana corta no cambia el veredicto.
- Las cifras de la primera corrida (C-123/C-124) siguen no reproducibles, como declara {C-128}; ninguna cifra del reporte depende de ellas (todas las de k7_* se reproducen con k7v3/k7v4 a ≤ 2.4e-16).

VEREDICTO: aprueba
