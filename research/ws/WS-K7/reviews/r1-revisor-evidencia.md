# Revisión de evidencia — WS-K7, ronda 1 (revisor-evidencia)

Alcance: `research/ws/WS-K7/report.md` contra `campaigns/b1/k7_{mo20,base}`, `campaigns/b1/k7v3_{mo20,base}`, `campaigns/b1/sonda_gc_*`, `research/ws/WS-K7/logs/*` y el registro (C-109, C-110, C-120..C-131). Solo lectura; sumas recalculadas con python/csv propio sobre las 59 filas `step > 280000`; `check_audit.py` ejecutado sobre los cuatro directorios. No leí `reviews/`.

## Comparación justa

- Mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`, run.log:26,37), misma ventana (280001–280059), 15 ranks en las cuatro corridas.
- `diff config.dat`: k7_mo20 vs k7_base solo `max_outer` (20/5) y `output_dir`; k7_* vs k7v3_* solo `output_dir`; vs `sonda_gc_*` solo `output_dir` y `probe_step_*`.
- Binario `campaigns/bin/eaf3d_k7col_opt`: mtime 20:38:11, posterior al pre-registro C-130 (20:37:16) y anterior a k7v3_mo20 (config 20:38:11, fin 20:38:51). El binario que produjo k7_mo20 (20:02) fue sobrescrito; las columnas de C-126 coinciden entre k7_mo20 y k7v3_mo20 salvo `m_gas_err_liq` y `m_gas_err_rem_abs` a 1.8e-16 relativo (orden de acumulación), dentro de todo redondeo mostrado.
- Bit a bit: `p_max, m_gas, E_liq, E_gas, u_gas_max` idénticos (0 discrepancias, 60 filas) entre k7_mo20/k7v3_mo20 y sonda_gc_mo20, y entre k7_base/k7v3_base y sonda_gc_base. `k7_*_v2/audit.csv` idénticos (`cmp`) a `k7_*/audit.csv`.
- Ventana: 59 pasos desde reinicio con el ciclo en marcha, un solo banco. Suficiente para el único veredicto que se emite («sin decidir», que no afirma nada más); el reporte ya lo acota.

## Tabla: afirmación / valor del reporte / recalculado / estado

| Afirmación (línea) | Reporte | Recalculado | |
|---|---|---|---|
| e_multi mo20 / base (50) | −8.555e-4 / −1.571e-3 | −8.5549e-4 / −1.5715e-3 | ok |
| err_liq mo20 / base (51) | −2.956e-3 / −2.916e-3 | −2.9563e-3 / −2.9161e-3 | ok |
| e − err_liq (52) | +2.101e-3 / +1.345e-3 | +2.1008e-3 / +1.3446e-3 | ok |
| Σ\|e\| multifase (53) | 1.636e-2 / 1.814e-2 | 1.6356e-2 / 1.8140e-2 | ok |
| Σ\|e − err_liq\| (54) | 9.257e-3 / 1.136e-2 | 9.2565e-3 / 1.1358e-2 | ok |
| nogas (55) | 4.816e-3 (29 %) / 4.832e-3 (27 %) | 4.8164e-3 (0.294) / 4.8322e-3 (0.266) | ok |
| Σ\|ρV_pois\|, Σ\|ρV_eff\| (56) | 8.80e-3, 2.28e-3 / 8.80e-3, 2.26e-3 | 8.799e-3, 2.275e-3 / 8.802e-3, 2.259e-3 | ok |
| rem/abs_multi (57) | 0.566 / 0.626 | 0.5660 / 0.6261 | ok |
| neto (58) | 2.456 / 0.856 | 2.4557 / 0.8556 | ok |
| liq_skip (59) | 0 / 0 | 0 / 0 | ok |
| por paso rem/abs (63) | mediana 0.574, 0.539–0.612 | 0.574, 0.539–0.612 | ok |
| corr(err_liq, e) (63,67) | −0.016 / 0.58 | −0.016 / 0.583 | ok |
| vp/ve (66) | 3.87; med 3.91, media 3.87, 3.29–4.53; base 3.90 | 3.867; 3.91, 3.87, 3.29–4.53; 3.896 | ok |
| corr(err_liq, vpois) / (err_liq, vol_lim) (66) | 0.976 / −0.85 (base −0.89) | 0.976 / −0.853 (−0.890) | ok |
| comp neto (66) | +4.1e-5 | +4.088e-5 | ok |
| factor e_multi 5↔20 ext. (67) | 1.84 | 1.837 | ok |
| corr(e, vol_lim) (67) | −0.06 → −0.55 | −0.060 / −0.550 | ok |
| mass_gas_rewrites k7 (68) | −6.2e-14 / −7.1e-14 | −6.15e-14 / −7.08e-14 | ok |
| test-full rewrites (68,70) | 67 PASS, max 4.0e-12; 64 evaluaciones ≤ 4.0e-12 | 67/67 PASS, 0 FAIL, max 3.97e-12; 64, max 3.985e-12 | ok |
| tests (70) | unit/quick/full OK, v131 | UNIT TESTS: OK; TESTS (quick): OK; TESTS (full): OK; metrics_v131 | ok |
| err_liq_all (77) | +4.977e-4 / +5.021e-4 | +4.9768e-4 / +5.0207e-4 | ok |
| err_liq nogas (78) | +3.454e-3 / +3.418e-3 | +3.4540e-3 / +3.4182e-3 | ok |
| Σ\|e − err_liq\| nogas, 84 % (79) | 7.85e-4 / 7.96e-4 | 7.847e-4 (0.837) / 7.963e-4 (0.835) | ok |
| rem_all (80) | 5.225e-3 / 7.322e-3 | 5.2248e-3 / 7.3221e-3 | ok |
| rem_all/abs (81) | 0.319; med 0.318, 0.304–0.381 / 0.404 | 0.3194; 0.318, 0.304–0.381 / 0.4036 | ok |
| neto sin filtro (82) | 1.582 / 1.319 | 1.5817 / 1.3195 | ok |
| Σ\|comp\|, Σ\|eos\| (83-84, 91) | 2.271e-3, 4.324e-1 / 2.256e-3, 4.284e-1; «200×»; «entre 7»; eos neto +5.5e-5 | 2.2714e-3, 4.3241e-1 / 2.2562e-3, 4.2836e-1; 190×; 7.2; +5.521e-5 | ok |
| k7_base check_audit (100) | FAIL energy gap −4.688e3, perm. 2.090e3, 2.243; u_gas 215.0; mo20 0.050, 163.5 | idéntico (4.993e-2) | ok, sin {C-nnn} (O2) |
| CG sin converger (99) | ≥ 1001 casos res 3.2e-2 / 1 | 1001 casos, 3.245E-02 / 1 caso | ok, sin {C-125} (O2) |
| «de 10 a 20 externas baja 16 %» (99) | 16 % | (5.33−4.46)/5.33 = 16.3 % (C-109) | ok |
| resto/err_liq (102) | −0.707 sd 0.081, −0.95..−0.46; corr −0.850; base −0.46 sd 0.10, −0.70..−0.27, corr −0.39 | −0.707, 0.081, −0.95..−0.46; −0.850; −0.462, 0.104, −0.70..−0.27; −0.393 | ok |
| m_alpha_clip (104) | 1.3e-12, max 4.7e-14; base 1.3e-12 | 1.35e-12, 4.70e-14; 1.34e-12 | ok |
| m_melted 2.04 kg; «~2e-6 kg» (102) | 2.04; ~2e-6 | 2.038; no reproducible (falta ρ_g); cota ≤ 3.7e-5 ≪ 2.1e-3 | parcial (O5) |
| C-128 cmd hoy (38) | ea−rem−vp−ve = −3.97e-3; rem−nogas 4.440e-3 | −3.975e-3; 4.4401e-3; (rem−nogas)/ea 0.271 | ok |
| Cifras de la primera corrida (38) | declaradas no reproducibles | confirmado: audit.csv mtime 20:02, binario sobrescrito 20:38, sin commit intermedio | ok (O4) |
| status.json (109) | prediccion C-121, test_quick null; cierre con C-126/C-127 | prediccion C-130, test_quick null, diff_sha coincide con `git diff --cached -- src tests` | objeción (O1) |
| `src/mod_audit.f90:981` (66) | :981 | :993 | objeción (O3) |

## Veredictos frente al criterio pre-registrado (literal)

- **C-126 → C-127.** Criterio: soportada si rem/abs ≤ 0.3 Y neto ≤ 0.3; refutada si rem/abs ≥ 0.7; entre ambos sin decidir. Medido 0.566 y 2.456 ⇒ sin decidir. Literal, sin reinterpretación. C-126 registrado 20:00:42, re-medida 20:02. P1–P4: rewrites PASS (resto −6.15e-14/−7.08e-14; 67 bancos, max 3.97e-12), liq_skip 0, bit a bit, tests OK. Cumplidos.
- **C-130 → C-131.** Criterio: mismo con `_all`. Medido 0.319 y 1.582 ⇒ sin decidir; 0.319 está en la banda predicha 0.25–0.35 y el reporte no lo convierte en «soportada». Literal. Pre-registro 20:37:16 < compilación 20:38:11 < corrida. P1–P4 cumplidos en k7v3_*.
- **C-121/C-122 → C-123** (en disputa, corregido por C-124/C-128): sus cifras no son reproducibles; el reporte lo declara y ningún número vigente proviene de esa corrida. La enmienda C-122 tiene motivo y es anterior al veredicto (18:59 < 19:37).
- `ledger.py check`: OK (131 eventos).

## Objeciones (ninguna bloqueante)

1. **O1 — `report.md:109` contradice `status.json`.** El reporte dice que status apunta a C-121 y que la compuerta se sostiene en {C-126}/{C-127}; `research/ws/WS-K7/status.json` apunta a `prediccion: C-130` (veredicto C-131). Levantar: reescribir esa viñeta con el estado real y nombrar una sola predicción de compuerta, consistente con status.json.
2. **O2 — afirmaciones sin `{C-nnn}`.** `report.md:99` y `:104` son el contenido de C-125 (soportada) pero no lo citan; `report.md:100` (k7_base FAIL energy_balance 2.243 y regime_gas 215.0 m/s, valores que reproduje) no tiene evento en el registro. Levantar: añadir {C-125}; registrar un `resultado` (ref C-127, rutas `campaigns/b1/k7_base`, cmd `check_audit.py`) y citarlo.
3. **O3 — `src/mod_audit.f90:981` → `:993`** (línea de `vp = vp + cfg%dt * ws_pc_unl`), desfasada tras las columnas de C-130.
4. **O4 — no verificable por revisión ciega:** C-128 cita `reviews/r1-auditor-eaf3d.md` como evidencia del primer instrumento; el código y el binario del primer instrumento no sobreviven. Lo que sí reproduje: rem − nogas = 4.4401e-3 (≈ 4.420e-3 de C-123) y (rem − nogas)/ea = 0.271. Ningún veredicto vigente depende de ello. Recomendación: un binario por versión de instrumento.
5. **O5 — `report.md:102` «~2e-6 kg»** no se deriva de audit.csv (falta ρ_g). Cota: 2.038 kg × 1.5e-5 m³/kg × ρ_g ≤ 1.2 ⇒ ≤ 3.7e-5 kg ≪ 2.1e-3: la conclusión se mantiene; sustituir la cifra por la cota con supuestos.

Observación sin objeción: la regla `transporte-energia.md:161-174` (mtime 20:03) lleva los números de C-127 como declara el reporte, pero no los de C-131 (0.32 sin filtro); propagarlo es del coordinador.

VEREDICTO: aprueba