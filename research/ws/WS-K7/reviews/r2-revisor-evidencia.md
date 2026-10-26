# Revisión de evidencia — WS-K7, ronda 2 (revisor-evidencia)

Modo solo lectura: `python3` (csv/statistics) sobre los `audit.csv` existentes, `tests/integration/check_audit.py` (solo abre en lectura, `:113`), `grep`/`sed -n`, `stat`, `ledger.py show|check`. No leí `research/ws/WS-K7/reviews/` de otros revisores.

## Estado de mis objeciones de la ronda 1

| id | estado | comprobación |
|---|---|---|
| O1 (200×) | resuelta | `k7v3_mo20`: 4.3241e-1/1.6356e-2 = 26.4; medianas 7.322e-3/2.767e-4 = 26.5; 7.83e3× |Σ eos| 5.52e-5; 126.5× Σ_pasos|eos| 3.418e-3. El «3.8 %» ya no aparece. |
| O2 (1.1e-12) | resuelta | `k7v4_long` 5499 filas: 1e-9×0.3243 + 1e-14×52.9 + 1e-12 = 3.258e-10; piso 1.53e-12. Cmd del reporte reproduce 5499, 0.3243, 52.9, 3.26e-10. |
| O3 (líneas mod_audit) | resuelta | `:967-968`, `:998`, `case default :1007`, `lk_any :1015`, `:1039-1040` coinciden; `:872-887` debería ser `:872-888` (trivial, O8). |
| O4 (binario k7_*) | resuelta | mtimes declarados y correctos; k7_* ↔ k7v3_*/k7v4_* reproducen err_liq/rem_abs a ≤ 2.42e-16 y 5 columnas bit a bit. |
| O5 (umbral 0.3 post hoc) | resuelta | Frase presente en Resultado (viñeta {C-139}) e Incertidumbre (3); C-134 21:11 < C-135 10:45 verificado en el registro. |
| O6 (comp_abs_nogas > 0) | resuelta | Redacción nueva coincide con C-135 (iii); 1.908e-6/4.816e-3 = 3.96e-4. |

## Tabla: afirmación / valor del reporte / recalculado / estado

| Afirmación (fuente) | Reporte | Recalculado | |
|---|---|---|---|
| k7_mo20: e_multi, err_liq, e−err | −8.555e-4, −2.956e-3, +2.101e-3 | −8.5549e-4, −2.9563e-3, +2.1008e-3 | ok |
| k7_mo20: Σ|e|, rem, nogas (%) | 1.636e-2, 9.257e-3, 4.816e-3 (29 %) | 1.6356e-2, 9.2565e-3, 4.8164e-3 (29.4 %) | ok |
| k7_mo20: vpois, veff; rem/abs; neto; liq_skip | 8.80e-3, 2.28e-3; 0.566; 2.456; 0 | 8.799e-3, 2.275e-3; 0.566; 2.456; 0 | ok |
| k7_base: e_multi, err_liq, Σ|e|, rem, nogas, rem/abs, neto | −1.571e-3, −2.916e-3, 1.814e-2, 1.136e-2, 4.832e-3 (27 %), 0.626, 0.856 | −1.5715e-3, −2.9161e-3, 1.8140e-2, 1.1358e-2, 4.8322e-3 (26.6 %), 0.626, 0.856 | ok |
| rem/abs por paso mediana, rango | 0.574, 0.539–0.612 | 0.574, 0.539–0.612 | ok |
| Σ|ρV_pois|/Σ|ρV_eff| sumas/mediana/media/rango; k7_base | 3.87/3.91/3.87/3.29–4.53; 3.90 | 3.87/3.91/3.87/3.29–4.53; 3.90 | ok |
| corr(err_liq,e) mo20/base; corr(e,vol_lim) | −0.016/0.58; −0.06/−0.55 | −0.016/0.583; −0.060/−0.550 | ok |
| corr(err_liq,vol_lim) con filtro; corr(err_liq,Σ|ρV_pois|) | −0.853 (base −0.890); 0.976 | −0.853 (−0.890); 0.976 | ok |
| resto/err_liq −0.707 (sd 0.081, −0.95..−0.46), corr −0.850; base −0.46, 0.10, −0.70..−0.27, −0.39 | | −0.707, 0.081, −0.95..−0.46, −0.850; −0.462, 0.104, −0.70..−0.27, −0.393 | ok |
| comp neto, eos neto, rxn, volfix, m_alpha_clip (máx/paso), k7_base clip | +4.1e-5, +5.5e-5, 5.4e-6, −1.3e-5, 1.3e-12 (4.7e-14), 1.3e-12 | 4.09e-5, 5.52e-5, 5.37e-6, −1.31e-5, 1.35e-12 (4.70e-14), 1.34e-12 | ok |
| m_melted 2.04 kg; m_slag = 0; e_out +9.24e-4 | | Σ 2.038; 0; 9.244e-4 | ok |
| k7v3: err_liq_all, nogas err_liq, Σ|e−err|_nogas (84 %), rem_all, rem_all/abs (mediana, rango), neto | +4.977e-4, +3.454e-3, 7.85e-4, 5.225e-3, 0.319 (0.318, 0.304–0.381), 1.582 | +4.9768e-4, +3.4540e-3, 7.847e-4 (84 %), 5.2248e-3, 0.319 (0.318, 0.304–0.381), 1.582 | ok |
| k7v3_base: idem | +5.021e-3, +3.418e-3, 7.96e-4, 7.322e-3, 0.404, 1.319 | +5.0207e-4, +3.4182e-3, 7.963e-4, 7.3221e-3, 0.404, 1.319 | ok |
| k7v3 comp_abs; eos_abs (mediana) | 2.271e-3/2.256e-3; 4.324e-1 (7.32e-3)/4.284e-1 (7.25e-3) | 2.2714e-3/2.2562e-3; 4.3241e-1 (7.322e-3)/4.2836e-1 (7.251e-3) | ok |
| eos_abs/Σ|e| = 26.4; medianas 26.5; 7.8e3× neto; 127× Σ_pasos|eos| 3.42e-3 | | 26.4; 26.5; 7.83e3; 126.5 (3.418e-3) | ok |
| corr(all,e), corr(e−all,e), mismo signo; filtro; base | 0.229, 0.972, 0/59; −0.016, 0.540; −0.429/0.993/0; 0.583/0.517 | idénticos | ok |
| corr(err_liq_all, vol_lim) +0.517 (base +0.708) | | +0.517 (+0.708) | ok |
| sd(all)/sd(e) = 7.9e-7/3.35e-6 = 0.24; media e −1.45e-5, sd 3.4e-6, 59/59 neg.; fórmula → 0.971, mínimo 0.972 | | 0.236 (7.91e-7/3.35e-6); −1.450e-5, 3.38e-6, 59/59; 0.9717 ambos | ok |
| e_nogas ∈ [2.67e-3, 4.24e-3]; e_gas ∈ [−5.09e-3, −3.53e-3]; |e_gas−err|/|e_gas| ∈ [0.16, 0.42] (58–84 %) | | [2.669e-3, 4.239e-3]; [−5.094e-3, −3.525e-3]; [0.16, 0.42] | ok |
| **|e − err_liq|/|e| ≤ 0.23 en nogas; err_liq_nogas explica ≥ 77 %** | 0.23; 77 % | **0.29 (7.847e-4/2.669e-3); ≥ 71 %**; 0.23/77 % salen con denominador err_liq_nogas 3.454e-3 | **objeción O7** |
| neto −8.55e-4 ≈ 20 % de la cancelación ±4e-3 | | 0.21 | ok |
| k7v4: rem_all/abs (mediana, rango); neto; nolink 0;0;0 | 0.319 (0.318, 0.304–0.381)/0.404 (0.401, 0.377–0.456); 1.582/1.319; 0 | idénticos; cells_nolink 0, Σ|e| 0, E2 0 en ambos | ok |
| comp_abs 3.125e-3/2.271e-3 = 1.38; base 2.428e-3/2.256e-3 = 1.08 | | 1.38; 1.08 | ok |
| comp_abs_nogas 1.908e-6/4.816e-3 = 4.0e-4; base 1.334e-6 → 2.8e-4 | | 3.96e-4; 2.76e-4 | ok |
| eos_abs 0.841/0.432 = 1.95 (mediana 1.42e-2); base 0.829/0.428 = 1.93 (1.40e-2); 51× Σ|e| y 51× medianas | | 1.95 (1.424e-2); 1.93 (1.404e-2); 51.4; 51.5 | ok |
| rewrites resto −6.15e-14 / −7.08e-14 PASS | | −6.148e-14 (tol 8.46e-10); −7.080e-14 (8.33e-10) | ok |
| 13 columnas bit a bit k7v4 ↔ k7v3 (60 renglones); audit_r1 idéntico salvo 2 columnas | | 14 columnas, 0 diferencias; audit_r1 solo le faltan m_gas_cells_nolink/m_gas_e2_nolink | ok |
| p_max, m_gas, E_liq, E_gas, u_gas_max bit a bit con sonda_gc_* (60) | | 0 diferencias en mo20 y base | ok |
| k7_* ↔ k7v3_*/k7v4_*: err_liq/rem_abs ≤ 2.4e-16; 5 columnas bit a bit | | 1.78e-16 (mo20), 2.42e-16 (base); 0 difs | ok |
| k7v4_base eos global −1.31e-3, err_free −9.9e-4 | | −1.313e-3, −9.895e-4 | ok |
| k7v4_long: 5499 pasos, 15 ranks, 34 min; resto −3.23e-14, Σ|dm| 78.35, tol 7.8e-8 | | 5499 (280001–285499); 15 MPI; 11:08:47→11:42:54; −3.228e-14; 78.35; 7.84e-8 | ok |
| tolerancia vieja 3.3e-10; piso 1.5e-12 | | 3.258e-10; 1.53e-12 | ok |
| nolink 51 845; Σ|e| 7.47e-3 = 0.36 % de 2.048; E2 1.1e-14; 0.504/0.712; corr −0.234/0.999/726; comp 0.235 (nogas 4.2e-4); eos 78.1 = 38× | | 51845; 7.467e-3 (0.36 %) de 2.048; 1.13e-14; 0.504/0.712; −0.234/+0.999/726; 0.235 (4.18e-4); 78.11 (38.1×) | ok |
| medias por tramos −2.96e-5 … −5.46e-5, ×1.85 | | −2.959e-5, −3.238e-5, −4.016e-5, −4.238e-5, −5.261e-5, −5.460e-5; 1.85 | ok |
| filas 280001–280058 iguales a k7v4_base; 280059 difiere; dt 9.9999971e-4 vs 1e-3; err_multi «−2.61190e-5 frente a −2.61196e-5» | | iguales; 76/110 columnas difieren; dt ok; **err_multi base −2.61196e-5, long −2.61190e-5 (orden invertido)** | O8 (trivial) |
| config k7v4_long = k7v4_base salvo t_final 285.5 (y output_freq); k7v3 = k7v4 = k7 salvo output_dir | | diff confirma | ok |
| k7_base FAIL energy_balance (gap −4.688e3, permitido 2.090e3, 2.243) y regime_gas 215.0; k7_mo20 0.050, 163.5 | | idénticos | ok |
| k7v4_long FAIL energy_balance 2.42×, mass_gas 0.547, u_gas 300, regime_p 5.02e5 | | 2.418; 0.5471; 300.0; 5.017e5 | ok |
| Tests OK (unit/quick/full, v131), 0 FAIL en test_full.txt | | OK los tres; 6 líneas FAIL son XFAIL | ok |
| mass_gas_rewrites 67 bancos PASS, máx 4.0e-12 (test_full.txt); barrido 78 bancos, 0 FAIL, máx 4.0e-12; cierre ≤ 4.0e-12 en 66 evaluaciones | | 67/67, 3.97e-12; barrido reproducido: 78, 0 FAIL, 3.97e-12; 66 evaluaciones, máx 3.985e-12 | ok |
| run.log k7_mo20: max_outer= 20; CG ≥ 1001 casos, res 3.2e-2; k7_base ≥ 1 y < 1001 | | `max_outer= 20`; avisos en 1 y 1001 casos, res 3.245e-2; k7_base un aviso (1 caso) | ok |
| mtimes: k7col_opt 20:38:11 > k7_mo20 20:02:17, k7_base 20:02:36; k7v3 20:38; k7v4 10:52; long 11:42; audit_r1 10:50:22; k7v4_opt 10:51:19 | | idénticos | ok |
| Registro: C-134 24-oct 21:11 (0.229) antes de C-135 25-oct 10:45; C-135 antes del binario; ledger check OK | | 21:11:39; 10:45:07; 10:51:19; «ledger OK (141 eventos)» | ok |
| Referencias de código y docs (ver O8) | | todas coinciden salvo `:872-887` → `:872-888` | ok/O8 |

## Veredictos frente al criterio pre-registrado

- **C-135 → C-139 «sin decidir»**: criterio literal «SOPORTADA si rem_all/abs ≤ 0.3 Y neto ≤ 0.3; REFUTADA si ≥ 0.7; entre 0.3 y 0.7 (o ≤ 0.3 con el neto fallando) SIN DECIDIR». Medido 0.319 y 1.582 → sin decidir. Coincide. Prerrequisitos: rewrites PASS en k7v4_mo20/base/long y en los 78 bancos; liq_skip 0; bit a bit con k7v3; tests OK. Cumplidos.
- **Inciso del piso neto** («H no lo explica si corr(err_liq_all, e) < 0.3»): 0.229 < 0.3. El reporte conserva el resultado por la letra y retira solo la lectura de mecanismo («vive en e − err_liq», que no estaba en el criterio) con motivo registrado (C-140, ref C-139). No aprueba H ni altera el veredicto; aceptable, con la salvedad de O9 (c).
- **C-126 → C-127** (0.566, 2.456) y **C-130 → C-131** (0.319, 1.582): «sin decidir» coincide con sus criterios; reproducidos.
- Expectativas (i)-(iii) de C-135: (i) no cumplida (clase vacía), (ii) cumplida (1.582 > 1, 0.229 < 0.3, 0/59), (iii) cumplida (1.38×, 1.95× ≤ 3; nogas 1.9e-6 > 0 y ≤ 0.5 Σ|comp|). Reportadas como tales.
- Comparación justa: mismo snapshot `judge_otp_280/eaf3d_00280000.h5`, mismas configs salvo `max_outer` (5/20) y `output_dir`, misma ventana 59 pasos; k7v4_long comparte config con k7v4_base salvo `t_final`. La ventana de 59 pasos no representa 280 s (deriva ×1.85 en 5.5 s) y el reporte lo declara.

## Objeciones

1. **O7 (bloqueante).** `research/ws/WS-K7/report.md` (Resultado, párrafo «Lo que los datos sí acotan, por subconjuntos»; Incertidumbre (4); `research/ledger.jsonl` C-140 (4)): «|e − err_liq|/|e| ≤ 0.23 en nogas» y «err_liq_nogas +3.454e-3 explica ≥ 77 %». Con los propios límites del reporte (|e_nogas| ≥ 2.669e-3) la cota es 7.847e-4/2.669e-3 = **0.29** y la fracción explicada **≥ 71 %** (o err_liq/e ∈ [0.81, 1.29]). 0.23 y 77 % son 7.847e-4/3.454e-3: denominador err_liq_nogas, no |e| como dice la etiqueta. No cambia el titular «60–85 %» ni ningún veredicto, pero el número no sale de los datos tal como está escrito y ya está copiado en el registro. Para levantarla: corregir ambas cifras en Resultado e Incertidumbre con el cmd `python3 -c "import csv;r=[x for x in csv.DictReader(open('campaigns/b1/k7v3_mo20/audit.csv')) if int(x['step'])>280000];S=lambda c:sum(float(x[c]) for x in r);rn=S('m_gas_err_rem_abs_all')-(S('m_gas_err_rem_abs')-S('m_gas_err_abs_nogas'));en=S('m_gas_err_liq_all')-S('m_gas_err_liq');print(rn,en,rn/(en-rn),1-rn/(en-rn))"` → 7.847e-4, 3.454e-3, 0.294, 0.706; y un evento nuevo con `--ref C-140`.
2. **O8 (no bloqueante).** (a) R4 (a): los valores de `m_gas_err_multi` en la fila 280059 están en orden invertido respecto al orden base↔long que fija el `dt` (base −2.61196e-5, long −2.61190e-5). (b) `src/mod_audit.f90` «:872-887» → `:872-888` (`end subroutine audit_eos_cell` está en :888). El resto de referencias de código y docs coinciden.
3. **O9 (no bloqueante, no verificable).** (a) Correspondencia binario `eaf3d_k7v4_opt` ↔ diff staged no comprobable sin compilar; el binario de `audit_r1.csv` (10:50) tampoco se conserva; la compuerta `test_quick=ok diff_sha=auto` es quien lo cubre. (b) `research/ws/WS-K7/status.json` muestra «revisor-evidencia: aprueba, ronda 1», que no coincide con mi veredicto anterior (rechaza); el archivo lo escribe el Workflow y no está en el diff. (c) La retirada de la lectura de mecanismo del inciso de correlación se registra como `propuesta` (C-140); conforme a `research/README.md` lo que la cierra es la predicción nueva en ventana independiente (pendiente del coordinador), no más prosa.

Todo lo demás reproduce al redondeo mostrado; las seis objeciones de la ronda 1 están resueltas como declaró el redactor.

VEREDICTO: rechaza