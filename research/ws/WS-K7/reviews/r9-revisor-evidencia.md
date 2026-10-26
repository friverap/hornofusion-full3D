# Revisión de evidencia — WS-K7, ronda 1 (revisor-evidencia)

**Rechazo el reporte por dos objeciones bloqueantes.** El veredicto en sí es correcto: C-144 queda sin decidir, por la letra de su criterio. Todos los números que pesan en el veredicto salen de los datos.

Las dos objeciones bloqueantes son:
- **E1:** el reporte da por «cumplida» una expectativa pre-registrada que falló en una de sus tres cláusulas.
- **E2:** dos viñetas de Incertidumbre describen como presentes defectos que ya se corrigieron, y sus comandos ya no reproducen lo que dicen.

Trabajé solo en lectura: python3/h5py sobre archivos existentes, `check_audit.py`, `ledger.py show|check`, `git show`, `grep` y `sed`. No ejecuté corridas ni `make`.

Archivos:
- Reporte: `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K7/report.md`
- Registro: `/Users/frariv/Horno/hornofusion-full3D/research/ledger.jsonl`, con C-144 (predicción) y C-145 (veredicto); no hay enmienda de C-144
- Datos: `/Users/frariv/Horno/hornofusion-full3D/campaigns/b1/k7*`, `/Users/frariv/Horno/hornofusion-full3D/tests/out/**`

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Inciso por celda de C-144 en k7v5_mo20: rem_all/abs_multi | 5.211e-3/1.636e-2 = 0.319 | 5.2108e-3/1.6356e-2 = 0.31859 | ok |
| Por paso en k7v5_mo20: mediana; rango | 0.317; 0.302–0.381 | 0.3171; 0.3023–0.3814 | ok |
| Inciso del neto | 1.571 | 1.5705 | ok |
| **Veredicto frente al criterio literal** (≤ 0.3 y neto ≤ 0.3 → soportada; ≥ 0.7 → refutada; si no, sin decidir) | SIN DECIDIR | 0.3 < 0.319 < 0.7 → SIN DECIDIR | ok |
| k7v5_base: cociente; neto; por paso | 0.404; 1.320; 0.401 (0.377–0.457) | 0.4038; 1.3196; 0.4010 (0.3774–0.4567) | ok |
| k7v5_mo20_1k: cociente; con filtro; neto | 0.333; 0.590; 1.49 | 0.3333; 0.5895; 1.4878 | ok |
| err_liq_all = lk + unl en mo20; en base | +4.881e-4 = +4.977e-4 − 9.58e-6; +5.022e-4 = +5.021e-4 + 1.64e-7 | idénticos; residuo 1.19e-20 y 2.37e-20 | ok |
| lk reproduce exactamente el err_liq_all de k7v4 | «exactamente» | 4.9767606608e-4 en ambos; ≤ 1.4e-15 relativo por fila | ok |
| Σ\|unl\|/Σ\|e\|; cota sobre Σ\|err_liq_all\|; fracción del neto | 0.0013; ≤ 0.19 %; −2.0 % | 0.00132; 0.194 % (cota 1.1145e-2); −1.96 % | ok |
| mass_gas_rewrites en mo20, base y 1k | −6.15e-14, −7.08e-14, −5.41e-14 (Σ\|dm\| 14.4) | idénticos, PASS | ok |
| Barrido de tests/out: rewrites; cierre EOS | 78 bancos, 0 FAIL, ≤ 4.0e-12; 66 ≤ 4.0e-12 | 78, 0 FAIL, 3.97e-12; 66, 3.985e-12 | ok |
| liq_skip y e2_skip en k7v5_*; columnas invariantes frente a k7v4 | 0, 0; 105 de 110 idénticas | 0, 0; 105 de 110; difieren solo las 5 que dependen de E2 | ok |
| Tests y golden | OK, v131, 0 FAIL | logs de 20:15–20:29: UNIT, quick y full OK; metrics_v131; 0 FAIL | ok (ver E6) |
| Nogas en mo20: V_pois; V_eff; rej (múltiplos de Σ\|e\|_nogas y de V_pois) | 4.078e-3; 1.1e-16; 7.655e-3 = 1.59× = 1.88× | 4.0782e-3; 1.087e-16; 1.589×; 1.877× | ok |
| Cociente por subconjunto: con gas (peso); nogas; en base | 0.384 (70.6 %); 0.163; 0.491 y 0.165 | 0.3836 (70.55 %); 0.1629; 0.4906 y 0.1648 | ok |
| Tabla por tramos de 200 de 1k (45 valores) | ver report.md:333-337 | todos coinciden (p. ej. 0.314 → 0.349; rej 1.61 → 1.48) | ok |
| rej/nogas por paso en 1k: mediana; rango; correlaciones | 1.52; 1.21–1.79; corr 0.98 y 0.91 | 1.521; 1.214–1.789; 0.984 y 0.911 | ok |
| Σ\|e\|_nogas/vol_lim en mo20, base, 1k y long | 1.94e-2 ×2, 1.98e-2, 2.04e-2 | 1.935e-2, 1.941e-2, 1.982e-2, 2.039e-2 | ok |
| corr con vol_lim en long (pasos 1–4500): nivel; tendencias; primeras diferencias; tramos | 0.97; 0.965 y 0.992; 0.46; 0.94 … 0.40 | 0.971; 0.965 y 0.992; 0.464; idénticos | ok |
| Tabla k7_mo20 / k7_base (Resultado) | −8.555e-4 … 2.456 / 0.856 | todas las celdas coinciden | ok |
| Tablas k7v3 y k7v4 | 0.319, 1.582, 3.454e-3, 7.85e-4 … | coinciden (comp_abs 1.38 y 1.08, eos_abs 1.95 y 1.93, comp_abs_nogas 4.0e-4 y 2.8e-4) | ok |
| Correlaciones (k7v3/k7v4/k7v5) | +0.229/+0.972, −0.016/+0.540, +0.233/+0.970, −0.428/+0.993 | idénticas | ok |
| sd por paso; cociente; mínimo de la fórmula | 7.9e-7/3.35e-6; 0.236; 0.9717 | 7.908e-7/3.350e-6; 0.2361; √(1−r²) = 0.9717 | ok |
| Correlaciones con vol_lim (mo20 y base) | 0.976; −0.853 (−0.890); +0.517 (+0.708); −0.06 → −0.55 | idénticas | ok |
| k7v4_long: cocientes; nolink; Σ\|e\| | 0.504; 0.712; 51 845 celdas-paso; 7.47e-3 = 0.36 %; 2.048 | 0.504; 0.712; 51845; 7.467e-3; 2.048 | ok |
| k7v4_long: FAIL de check_audit; peor paso; cocientes | 6 FAIL; 284736 con 1.878; 2.42; 0.547; 300; 5.02e5 | idénticos | ok |
| k7v4_long: tolerancias; tramos de e/paso | 3.26e-10; 7.8e-10; ×1.85 | 3.258e-10; 7.85e-10; 5.46/2.96 = 1.845 | ok |
| Tabla de 500 pasos de long (66 valores); 53 % ≥ 0.7; subconjunto con gas | ver report.md:368-378; 0.521 → 0.682 | todo coincide | ok |
| Tercios de e_out; e_multi + e_out; correlaciones | +6.96e-2, +9.52e-2, +6.90e-2; +1.36e-2, +2.25e-2, −2.67e-2 | idénticos | ok |
| C-151/C-152: cotas; fracciones; inicio de centinelas | 48 %; 24 %; 31.8 %; 43.1 %; 1.91–2.44; 0.32 … 0.61; 0.43; pasos 4340 y 4669 | idénticos | ok |
| Composición en 5 snapshots (nogas_vecinas.py, tol 1e-6/1e-3/5e-3) | 407/406/412/488/482; 96.6 … 94.8 %; 1214 caras … | todo coincide; 88 = 391 − 303 | ok |
| rho_uz_nogas.py; tamaño | 0.30428; 52.9735; 0.2275 (0.1375–0.3410); 6.4 % y 8.5 % | idénticos; 6.36 % y 8.50 % | ok |
| C-157: celdas con 0 < α_g < 1e-2 | 85/95/90/91/89, k = 1–3, medianas 0.99 y 0.006 | idénticos | ok |
| C-158: identidad de fila en tests/out | 0.101, 0.019, 0.008 … ; 0.163/0.847 … | idénticos | ok |
| Bancos fríos: Σ\|e\| multifase; e_multi/\|EOS\|; Σ\|e\|/Σ\|eos\| | 1.331e-2, 1.196e-1, 8.771e-3; 3.0e-4, 3.9e-4, 3.5e-3; 3.1e-4, 3.0e-3, 2.1e-4 | idénticos | ok |
| Clasificación de tests/out; reparto trivial | 30/12/22+2; 34 de 66 | 30/12/22+2; 34 de 66 | ok |
| Identidad del binario; src sin cambios | sha 28a31905…; desde 16:57 | log presente; mtimes de src ≤ 16:57; staged = árbol | ok |
| **Expectativa (i) de C-144 «cumplida con holgura»** | cumplida | cláusula «en base mayor»: base 8.73e-6 < mo20 2.16e-5 → NO cumplida | **objeción E1** |
| **Incertidumbre, report.md:395 y :399 («en el diff staged quedan…»)** | defectos vigentes | grep vacío; checker imprime «no medido»; regla :185 corregida | **objeción E2** |
| «las cifras cambian en la cuarta cifra» (report.md:326) | 4.ª cifra | err_liq_all −1.93 % (2.ª cifra); rem_all y neto en la 3.ª | objeción E3 |
| «60–85 % del neto» (report.md:43 y :227) | 60–85 % | 58–84 % con gas; ≥ 71 % en nogas | objeción E4 |
| `check_audit.py:373-374` (rama «n/a» con Σ\|e\| = 0) | :373-374 | :385 | objeción E5 |
| «corr con el número de paso 0.10 frente a 0.91» | 0.10 | corr(rej, paso) 0.100; corr(rej/nogas, paso) −0.488 | objeción E8 |

**Comparaciones justas.** Los tres bancos k7v5 parten del mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`) con 15 ranks y el mismo binario. Las configs de mo20 y base solo difieren en `max_outer`; `alpha_T` vale 0.7 en ambas, solo cambia de línea. La ventana de 59 pasos empieza con transitorio (p_max 9.55e4–9.96e4 en los pasos 2–3 frente a una mediana de 4.22e4). Esto está declarado y el veredicto es «sin decidir», así que no se extrae ninguna conclusión positiva de una muestra corta.

## 2. Objeciones

1. **E1 (bloqueante).** `research/ws/WS-K7/report.md:326` y C-145 dicen «(i) cumplida». La expectativa (i) de C-144 tiene tres cláusulas:
   - en k7v5_mo20, |Σ unl| ≤ 0.2 Σ|err_liq_all|: se cumple;
   - en k7v5_mo20, Σ|unl| ≤ 0.3 Σ|e|: se cumple;
   - «en k7v5_base mayor»: **no se cumple**. En `campaigns/b1/k7v5_base/audit.csv`, Σ m_gas_err_liq_unl_abs = 8.734e-6, menor que 2.158e-5 en mo20.

   El criterio de C-144 pide reportar las expectativas «como cumplidas o no». Llamar «cumplida» a una expectativa con una cláusula fallida es reinterpretarla, aunque el fallo se mencione después en la misma frase.
   - Para levantarla: escribir «(i) cumplida en sus dos cotas de mo20; NO cumplida en ‹en base mayor›» y registrar la corrección de C-145 con `--ref C-145`.

2. **E2 (bloqueante).** `report.md:395` y `:399` afirman en presente que el diff staged conserva frases retiradas en la regla, en el glosario y en el checker. Sus comandos de procedencia dan hoy otra cosa:
   - `grep -n 'residual de esa\|sin líquido en movimiento\|10–13.5\|≥ 48 %' .claude/rules/transporte-energia.md` sale vacío, y la versión staged es igual al árbol de trabajo (`git show :…`);
   - `check_audit.py tests/out/cold_10step_n4` imprime «1 - sum|e - err_liq|/sum|e| = 0.000», no «H explica 0.000»;
   - `grep 'Reduced form'` sale vacío en `scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md` y `paper/tables/audit_glossary.tex`;
   - `check_audit.py campaigns/b1/k7_mo20` imprime «no medido», no ceros;
   - `.claude/rules/transporte-energia.md:185` ya dice «e_multi DEPENDE de las externas».

   Esas correcciones vienen de C-156, C-160 y C-161, y el preámbulo del propio reporte las da por hechas, así que el reporte se contradice.
   - Para levantarla: añadir la nota «Resuelto en la ronda 13/15/16» con la salida actual de cada comando, y dejar en presente solo lo que siga abierto (p. ej. el párrafo WS-K5 de la regla, :133-137).

3. **E3.** `report.md:326`, «cambian en la cuarta cifra»: es falso. err_liq_all pasa de 4.977e-4 a 4.881e-4 (−1.9 %), rem_all de 5.225e-3 a 5.211e-3 y el neto de 1.582 a 1.571 (comparando `campaigns/b1/k7v4_mo20` con `k7v5_mo20`). Basta con citar los cambios relativos.

4. **E4.** `report.md:43` y `:227` dicen «60–85 %», pero la cota medida en :358 es 58–84 % con gas y ≥ 71 % en las nogas. Hay que citar esas cotas.

5. **E5.** `report.md:100`, `:395` y `:399` remiten a `tests/integration/check_audit.py:373-374` para la rama «n/a» con Σ|e| = 0; hoy esa rama está en `:385`. También han cambiado `:358-362`, `:374-383` y `:391-393,424`. Hay que actualizar las líneas.

6. **E6.** C-145 tiene ts 13:38:13 y cita tests de «13:22-13:40», un intervalo que termina después del veredicto; esos logs ya no existen. El prerrequisito sí se cumple con los logs actuales de `research/ws/WS-K7/logs/` (20:15–20:29), sobre el mismo `src/` y un binario idéntico. Hay que declarar en Incertidumbre que esos son los logs que lo acreditan.

7. **E7.** C-144 no estaba commiteado antes de la corrida: HEAD 6579277 solo llega a C-121. La desviación está declarada en `report.md:387` y los umbrales son los del C-121 commiteado. Queda para el coordinador; no es bloqueante.

8. **E8.** En `report.md:248`, «corr con el número de paso 0.10» tiene un sujeto ambiguo. Medido en `campaigns/b1/k7v5_mo20_1k/audit.csv`: corr(rej, paso) = 0.100, pero corr(rej/Σ|e|_nogas, paso) = −0.488. Hay que nombrar la serie.

Las objeciones E3–E8 no son bloqueantes. Al levantar E1 y E2, el reporte queda en condiciones de aprobarse por evidencia: el veredicto «sin decidir» y todas las cifras que lo sostienen se reproducen.

VEREDICTO: rechaza
