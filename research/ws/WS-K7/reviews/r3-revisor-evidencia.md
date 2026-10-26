# Revisión de evidencia — WS-K7 (panel de cierre, revisor-evidencia)

Alcance: `research/ws/WS-K7/report.md` (mtime 25-oct 12:19:56) contra `campaigns/b1/k7_{mo20,base}`, `k7v3_*`, `k7v4_*`, `k7v4_long`, `sonda_gc_*`, `judge_otp_280`, los logs de tests, el código citado y el registro (C-109…C-143). Solo lectura: `python3` (csv, h5py, statistics), `tests/integration/check_audit.py` (verificado que no escribe), `sed -n`, `grep`, `stat`, `ledger.py check|open|show`. No leí `reviews/`.

## 1. Tabla afirmación / reporte / recalculado

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| `ledger.py check` | — | OK, 143 eventos | ok |
| C-122 enmienda antes del veredicto, con motivo | sí | 18:59:40 < C-123 19:37:50; motivo (unidad, ámbito) | ok |
| C-135 pre-registrada antes de compilar | 10:45 | 10:45:07 < audit_r1 10:50:22 < binario 10:51:19 | ok |
| **k7_mo20** e_multi / err_liq / e−err | −8.555e-4 / −2.956e-3 / +2.101e-3 | −8.5549e-4 / −2.9563e-3 / +2.1008e-3 | ok |
| Σ\|e\| / rem / nogas (%) | 1.636e-2 / 9.257e-3 / 4.816e-3 (29 %) | 1.6356e-2 / 9.2565e-3 / 4.8164e-3 (29.4 %) | ok |
| Σ\|ρV_pois\|, Σ\|ρV_eff\|; cociente | 8.80e-3, 2.28e-3; 3.87 (med 3.91, 3.29–4.53) | 8.799e-3, 2.275e-3; 3.867 (3.91, media 3.87, 3.29–4.53) | ok |
| rem/abs (inciso por celda) | 0.566 (med 0.574, 0.539–0.612) | 0.5660 (0.574, 0.539–0.612) | ok |
| \|e−err\|/\|e\| (inciso neto) | 2.456 | 2.4557 | ok |
| **k7_base** (mismas filas) | −1.571e-3 / −2.916e-3 / 1.345e-3 / 1.814e-2 / 1.136e-2 / 4.832e-3 (27 %) / 0.626 / 0.856 | −1.5715e-3 / −2.9161e-3 / 1.3446e-3 / 1.8140e-2 / 1.1358e-2 / 4.8322e-3 (26.6 %) / 0.6261 / 0.8556 | ok |
| rem − nogas (conjunto con gas) | 4.440e-3 | 4.4401e-3 | ok |
| corr(err_liq,e); corr(e−err,e) mo20 / base | −0.016; 0.540 / 0.58; 0.517 | −0.016; 0.540 / 0.583; 0.517 | ok |
| corr(err_liq, vol_lim); corr(err_liq, vpois) | −0.853 (base −0.890); 0.976 | −0.853 (−0.890); 0.976 | ok |
| corr(e, vol_lim) mo20 → base | −0.06 → −0.55 | −0.060 → −0.550 | ok |
| resto/err_liq mo20 / base | −0.707 (sd 0.081, −0.95..−0.46), corr −0.850 / −0.46 (0.10, −0.70..−0.27), −0.39 | −0.707 (0.081, −0.95..−0.46), −0.850 / −0.462 (0.104, −0.70..−0.27), −0.393 | ok |
| comp neto; rx; volfix; m_alpha_clip | +4.1e-5; 5.4e-6; −1.3e-5; 1.3e-12 (max 4.7e-14) | 4.088e-5; 5.37e-6; −1.31e-5; 1.349e-12 (4.70e-14) | ok |
| e: media, sd, negativos | −1.45e-5, 3.4e-6, 59/59 | −1.450e-5, 3.378e-6, 59/59 | ok |
| **k7v3_mo20** err_liq_all / nogas / rem_nogas (84 %) | +4.977e-4 / +3.454e-3 / 7.85e-4 | +4.9768e-4 / +3.4540e-3 / 7.847e-4 (83.7 %) | ok |
| rem_all; 0.319 (med 0.318, 0.304–0.381); 1.582 | | 5.2248e-3; 0.3194 (0.318, 0.304–0.381); 1.5817 | ok |
| k7v3_base 0.404 (0.401, 0.377–0.456); 1.319; +5.021e-4; +3.418e-3; 7.96e-4 | | 0.4036 (0.401, 0.377–0.456); 1.3195; 5.0207e-4; 3.4182e-3; 7.963e-4 | ok |
| comp_abs; eos_abs (med) k7v3 | 2.271e-3; 0.4324 (7.32e-3) / 2.256e-3; 0.4284 (7.25e-3) | 2.2714e-3; 0.43241 (7.322e-3) / 2.2562e-3; 0.42836 (7.251e-3) | ok |
| 26.4× y 26.5×; 8e3×; 127× | | 26.44; 26.46; 7832; 126.5 | ok |
| corr(err_liq_all,e); corr(e−all,e); signo | 0.229; 0.972; 0/59 (base −0.429; 0.993; 0) | 0.2291; 0.9717; 0 (−0.4285; 0.9931; 0) | ok |
| corr(err_liq_all, vol_lim) | +0.517 (base +0.708) | 0.517 (0.708) | ok |
| sd(err_liq_all)/sd(e) = 7.9e-7/3.35e-6 = 0.24; fórmula 0.9717 | | 7.908e-7/3.350e-6 = 0.2361; 0.9717 | ok |
| e_nogas ∈ [2.67e-3, 4.24e-3]; cota 0.29; ≥ 71 %; err/e ∈ [0.81, 1.29] | | [2.669e-3, 4.239e-3]; 0.294; 0.706; [0.81, 1.29] | ok |
| e_gas ∈ [−5.09e-3, −3.53e-3]; [0.16, 0.42] (58–84 %) | | [−5.094e-3, −3.525e-3]; [0.161, 0.420] | ok |
| e_out; eos global k7v4_base; err_free | +9.24e-4; −1.31e-3; −9.9e-4 | 9.244e-4; −1.313e-3; −9.895e-4 | ok |
| **k7v4_mo20** comp_abs 3.125e-3 (1.38×); nogas 1.908e-6 (4.0e-4); eos_abs 0.841 (1.95×, med 1.42e-2); 51× | | 3.1246e-3 (1.376); 1.908e-6 (3.96e-4); 0.8413 (1.946; 1.424e-2); 51.4 | ok |
| k7v4_base 2.428e-3 (1.08); 1.334e-6 (2.8e-4); 0.829 (1.93; 1.40e-2) | | 2.4279e-3 (1.076); 1.334e-6 (2.76e-4); 0.8286 (1.934; 1.404e-2) | ok |
| nolink: celdas, Σ\|e\|, E2 | 0; 0; 0 | 0; 0; 0 (ambos) | ok |
| rewrites resto | −6.15e-14 / −7.08e-14 | −6.148e-14 / −7.080e-14 (dos formas) | ok |
| 13 columnas bit a bit k7v4 ↔ k7v3; audit_r1 | sí | 104/106 comunes idénticas (solo difieren comp_abs/eos_abs); audit_r1 108/108 | ok |
| k7_* reproducido por k7v3/k7v4: \|dif\|/\|val\| ≤ 2.4e-16; 5 columnas bit a bit | | 1.78e-16 (mo20), 2.42e-16 (base); 0 diferencias en p_max/m_gas/E_liq/E_gas/u_gas_max, 60 filas, también vs sonda_gc_* | ok |
| **k7v4_long** 5499 pasos, 15 ranks, 34 min | | 280001–285499; «Running on 15 MPI processes»; 11:08:47→11:42:54 | ok |
| resto −3.23e-14; Σ\|dm\| 78.35; tol 7.8e-8 | | −3.228e-14; 78.350; 7.84e-8 | ok |
| tol vieja 3.3e-10 (0.3243, 52.9); piso 1.5e-12 | | 3.26e-10 (0.32431, 52.945); 1.53e-12 | ok |
| nolink 51 845; 7.47e-3 (0.36 %); E2 1.1e-14 | | 51845; 7.467e-3 (0.365 %); 1.13e-14 | ok |
| 0.504 / 0.712; corr −0.234, 0.999, 726/5499 | | 0.5037 / 0.7125; −0.2342, 0.9992, 726 | ok |
| comp_abs 0.235 (nogas 4.2e-4); eos 78.1 = 38× | | 0.2353 (4.18e-4); 78.11 = 38.1× | ok |
| tramos −2.96/−3.24/−4.02/−4.24/−5.26/−5.46 e-5; ×1.85 | | −2.959/−3.238/−4.016/−4.238/−5.261/−5.460 e-5; 1.846 | ok |
| fila 280059 base ↔ long: dt 9.9999971e-4 vs 1e-3; err_multi −2.61196e-5 vs −2.61190e-5; 1–58 iguales | | dt idem; −2.6119639e-5 (base) vs −2.6119043e-5 (long); 59 filas iguales, 1 difiere | ok |
| check_audit long: energy 2.42×, mass_gas 0.547, u_gas 300, p 5.02e5 | | 2.418; 0.5471; 300.0; 5.017e5 | ok |
| k7_base FAIL energy (gap −4.688e3, perm 2.090e3, 2.243) y regime_gas 215.0; mo20 0.050, 163.5 | | idéntico | ok |
| Tests: unit/quick/full OK, golden v131; 67 PASS rewrites, max 4.0e-12; cierre ≤ 4.0e-12 en 64 | | logs: OK/OK/OK, metrics_v131; 67 PASS, 0 FAIL (6 XFAIL), max 3.97e-12; 64 evaluaciones, max 3.985e-12 | ok |
| Barrido tests/out: 78 bancos, 0 FAIL, max 4.0e-12; cierre 66 | | 78 audit.csv, 78 PASS, max 3.97e-12; 66, max 3.985e-12 | ok |
| Binario O9(a): 10:51:19 > fuentes 10:50:51; sin cambios después | | stat confirma; `find src tests -newer … -name '*.f90' -o '*.py'` vacío; eaf3d_k7col_opt 20:38:11 > k7_mo20/audit.csv 20:02:17 | ok |
| Mismo reinicio y misma config | judge_otp_280/eaf3d_00280000.h5 | 56 datasets HDF5 idénticos en k7_*, k7v4_*, long, sonda_gc_* (cmp solo difiere en cabecera); configs iguales salvo `max_outer` 20/5 y `t_final` 280.06/285.5 | ok |
| run.log: max_outer 20; CG ≥ 1001 casos (res 3.2e-2); base un aviso; n_pc_max ausente | | «max_outer= 20»; avisos en 1 y 1001 (3.245E-02); base solo el 1; `n_pc_max` no está en config.dat, default 1 (`mod_config_3d.f90:111`) | ok |
| 1001/1180 «≥ 85 %» | ≥ 85 % | 84.8 % | objeción O3 (redondeo) |
| Líneas de código citadas (mod_audit :872-888, :967-968, :998, :1005-1047, :1015, :1039-1040; pressure :209, :231-233, :649, :663-667, :767, :1186/1220/…/1388, :1232-1243, :1730-1734; continuity :497-504, :673/678, :808, :864, :1237, :1258-1267, :1687; properties :42; solver :272-278; check_audit :398-417; acople-pv :291) | | todas apuntan a lo que el reporte dice | ok |
| Glosario tex / AUDIT_COLUMNS: «every call», «only where the cell has a linked face» | corregidos | `audit_glossary.tex:107,114,115`; `AUDIT_COLUMNS.md:102,109-110` | ok |
| Estado de `transporte-energia.md` | dos versiones contradictorias en el reporte | «piso neto vive» solo como retirada (:168-169); «1.9 %» ausente; F2.21 sigue en :180 (no :173) | objeción O2 |
| status.json / reviews/ | «ronda: 1, aprueba»; «no ha escrito nada» | `ronda: 2`, `revisor-evidencia: rechaza`, actualizado 12:19:57; `reviews/r2-*.md` 12:18:06 (< 12:19:56 del reporte) | objeción O1 |

## 2. Veredictos contra los criterios pre-registrados (comparación literal)

- **C-121/C-122 → C-123**: «sin decidir» (ningún inciso cumplido, no refutada). Las cifras de C-123 son no reproducibles y así se declara {C-128}; el reporte no las usa.
- **C-126 → C-127**: criterio «≤ 0.3 Y neto ≤ 0.3 ⇒ soportada; ≥ 0.7 ⇒ refutada; entre ambos sin decidir». Medido 0.5660 y 2.4557 ⇒ **sin decidir**. Coincide.
- **C-130 → C-131**: medido 0.3194 y 1.5817 ⇒ **sin decidir**. Coincide. La predicción declarada (0.25–0.35) se cumple por la letra (0.319); el reporte no la convierte en «soportada».
- **C-135 → C-139**: medido 0.3194 y 1.5817 ⇒ **sin decidir**. Coincide. Prerrequisitos: rewrites PASS en k7v4_mo20/base/long y 78 bancos, liq_skip 0, columnas numéricas bit a bit con k7v3, tests OK golden v131: todos verificados.
  - Cláusula «se registra además el resultado sobre el piso NETO: H no lo explica si corr(err_liq_all, e) < 0.3». Medido 0.2291 < 0.3. El reporte lo registra «por la letra» y RETIRA su lectura de mecanismo (C-140, C-143). Comprobé el fundamento: C-134 (24-oct 21:11) ya contenía 0.229 sobre k7v3_mo20; C-135 (25-oct 10:45) fijó el umbral después; k7v4 reproduce las mismas columnas bit a bit (104/106 idénticas). La cláusula no era una predicción independiente en el sentido de `research/README.md`. La retirada está registrada como evento nuevo con `ref` y debilita (no refuerza) las conclusiones: no es una reinterpretación a favor de H. Acepto.
- Expectativas (i)-(iii) de C-135: (i) no cumplida (clase vacía), (ii) cumplida, (iii) cumplida (1.38×, 1.95× ≤ 3×; nogas 1.908e-6 > 0 y ≤ 0.5 Σ|comp|). Reportadas tal cual.

Comparación justa: mismo snapshot (56 datasets idénticos), mismo binario por serie, configs iguales salvo la clave probada. La muestra de 59 pasos con ciclo en marcha está declarada como no representativa (R4, deriva ×1.85 en k7v4_long; sin ventana larga a 20 externas): la conclusión del WS es «sin decidir» y no se extiende más allá del régimen medido.

## 3. Objeciones (ninguna bloqueante)

1. **O1 — status.json / reviews/ (Incertidumbre, O9 b).** `research/ws/WS-K7/status.json`: `ronda: 2`, `revisor-evidencia: rechaza (ronda 2)`, `actualizado 2026-10-25T12:19:57`; `research/ws/WS-K7/reviews/r2-{auditor-eaf3d,revisor-evidencia,revisor-refutador}.md` con mtime 12:18:06, anterior al guardado del reporte (12:19:56). El reporte afirma «ronda: 1 / aprueba» y «no ha escrito nada en status.json ni en reviews/». Falso en el estado actual. Levantar: reescribir el párrafo con el estado real o reducirlo a «este reporte no infiere nada de status.json». Comando: `cat research/ws/WS-K7/status.json; ls -laT research/ws/WS-K7/reviews/`.
2. **O2 — Estado de la regla, contradicción interna.** Incertidumbre dice a la vez «corregida por el coordinador tras la ronda 6 {C-143}» y «Desfasada de nuevo tras la ronda 5: aún dice ‘el piso neto vive…’, F2.21 (:173), ‘1.9 %’». `.claude/rules/transporte-energia.md`: «piso neto vive» solo como RETIRADA (:168-169); `grep -E '1\.9 ?%'` vacío; F2.21 sigue, pero en :180 (en :173 están las cotas ≥ 71 % / 58–84 %). También Resultado cita `:173` para F2.21. Levantar: dejar como único pendiente «F2.21 → F2.24 en :180» y quitar los otros dos desfases.
3. **O3 — «≥ 1001 (≥ 85 %)».** 1001/1180 = 84.8 %. Escribir «≥ 84.8 %» o «≈ 85 %». Fuente `campaigns/b1/k7_mo20/run.log`.

## 4. Verificado sin objeción

Todas las cifras de las tres tablas, de las viñetas de Resultado y de Incertidumbre se recalculan desde `campaigns/b1/k7*/audit.csv` dentro del redondeo mostrado (tabla arriba); los logs de tests y el barrido de `tests/out` dan exactamente 67/78 PASS, 64/66 evaluaciones de cierre y resto máximo 3.97e-12; los mtimes del binario, fuentes y CSV sostienen O4 y O9(a); las líneas de código y docs citadas apuntan a lo que el reporte dice; el registro está íntegro (`ledger.py check` OK) y cada corrección es un evento nuevo con `ref`.

VEREDICTO: aprueba
