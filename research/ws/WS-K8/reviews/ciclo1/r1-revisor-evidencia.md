# WS-K8, ronda 1: revisión de evidencia

**Revisión ciega.** No leí research/ws/WS-K8/reviews/. Fuentes: `research/README.md`, `research/ws/WS-K8/report.md`, C-168 a C-176, C-125 y C-163 (`ledger.py show`), los `campaigns/b1/k8_*/{audit.csv,run.log,config.dat}`, los logs de `research/ws/WS-K8/logs/` y `tests/out/**/audit.csv`. Todo fue de solo lectura: `python3` con csv, `check_audit.py` (que no escribe archivos), `grep`, `sed -n`, `git show`, `cmp` y `stat`.

## 1. Tabla de verificación

| Afirmación | Valor del reporte | Valor recalculado | Estado |
|---|---|---|---|
| [CG] AVISO en cg1000 / cg200 / mo20 / base | 0 / 2 / 2 / 1 | 0 / 2 / 2 / 1 | ok |
| Σ\|e\| del gas libre (cg1000 / cg200 / mo20 / base) | 9.20e-5 / 8.99e-5 / 1.03e-3 / 9.20e-3 | 9.198e-5 / 8.991e-5 / 1.027e-3 / 9.203e-3 | ok |
| Cociente rem2/abs del gas libre | 0.863 / 0.847 / 1.004 / 0.918 | 0.8628 / 0.8468 / 1.0040 / 0.9182 | ok |
| Σ\|e\| del multifase | 1.632e-2 / 1.632e-2 / 1.636e-2 / 1.814e-2 | 1.6316e-2 / 1.6316e-2 / 1.6356e-2 / 1.8140e-2 | ok |
| Cociente rem2/abs del multifase | 0.197 / 0.197 / 0.203 / 0.339 | 0.1970 / 0.1966 / 0.2028 / 0.3391 | ok |
| Neto e frente al neto del plan (cg1000) | −8.55e-4 / +4.25e-4 (1.50) | −8.5500e-4 / +4.2494e-4 (1.4970) | ok |
| Neto e frente al plan (cg200 / mo20 / base) | −8.58e-4/4.25e-4; −8.55e-4/4.23e-4; −1.57e-3/3.65e-4 | −8.577e-4/4.246e-4; −8.555e-4/4.233e-4; −1.5715e-3/3.650e-4 | ok |
| C-110: rem_all/abs_multi y neto | 0.3156; 1.571 / 0.3155; 1.569 / 0.3186; 1.571 / 0.4038; 1.320 | 0.3156; 1.5707 / 0.3155; 1.5690 / 0.3186; 1.5705 / 0.4038; 1.3196 | ok |
| Σ\|err_art\| / Σ\|e\| | 3e-6 / 3e-6 / 5e-6 / 5e-5 | 2.96e-6 / 2.87e-6 / 5.15e-6 / 4.76e-5 (sobre el interior total; ver O5) | ok |
| Σ\|err_art\| (cg1000) | ≈ 5e-8 | 4.862e-8 | ok |
| class_split (resto) y rewrites (resto) | −1.6e-17 PASS; 1.8e-14 PASS (mo20 −6.2e-14) | −1.58e-17; 1.77e-14; −6.15e-14 | ok |
| Reparto del neto multifase (cg1000): comp, eos, flux, rx | +4.06e-5, +1.288e-4, +1.019e-3, +5.4e-6 | 4.0613e-5, 1.2876e-4, 1.0190e-3, 5.367e-6 | ok |
| Cierre del flujo por paso | ≤ 9.1e-19 | 9.08e-19 (base 1.19e-18, mo20 8.67e-19) | ok |
| Σ m_gas_out y fracciones | −9.708e-4; 95.3 % / 93.3 % / 115.7 % | −9.7082e-4; 0.9527 / 0.9331 / 1.1570 | ok |
| Flujo neto del gas libre y comp+eos | −4.8e-5; +1.7e-4 | −4.818e-5; +1.694e-4 | ok |
| Peso del multifase y del libre en Σ\|e\| | 99.4 % / 0.56 % | 99.44 % / 0.56 % | ok |
| Gas libre de CG 20 a CG convergido: «baja 11 veces» | 11× | 1.027e-3 / 9.198e-5 = 11.2 (con 20 externas) | ok el número; **«en B1», objeción O1** |
| k8_base: gas libre «100 veces mayor»; FAIL | 100×; energy 2.24, regime 215 m/s | 100.06×; 2.243; 215.0 | ok |
| CG 200: residuo reducido ~2e-5, ≥ 1001 casos | ~2e-5 | 2.017e-5 / 1.368e-5; aviso en el caso 1001 | ok |
| CG 20: «≥ 85 % sin converger» | ≥ 85 % | Solo se puede afirmar ≥ 1001 casos; el total de Poisson no consta | **objeción O2** |
| Bit a bit k8_mo20 frente a k7v5_mo20 | idéntico; m_gas_err_* ≤ 1.1e-19 (≤ 4e-12 relativo) | idéntico en las 6 columnas y en todas las comunes salvo 7 m_gas_err_*: 1.08e-19 / 3.97e-12 | ok |
| r2 idénticos; binarios difieren en 270 bytes | 137 columnas × 60 filas; 270 | idénticos byte a byte; `cmp -l` da 270 | ok |
| Barrido de tests/out | 78 / 66 / 66, 0 FAIL; 4.0e-12, 8.5e-15, 3.7e-14 | 78 / 66 / 66, 0 FAIL; 3.97e-12, 8.49e-15, 3.73e-14 (arc_melt_slag_heel_n1) | ok |
| Tests unit / quick / full OK, golden v131 | OK | OK en los tres logs; `metrics_v131.json`; 0 « FAIL » | ok |
| Pruebas de humo: libre 0.77-1.00; multifase 0.73-0.76; bed_bath 0.11 | igual | 0.766 / 0.946 / 1.000; 0.732 / 0.760; 0.108 | ok |
| alpha_p = 0.7 en `mod_pressure_3d.f90:898`; SMALL en `mod_solver_3d.f90:245` | igual | confirmado; el aviso exige n_iter >= max_iter | ok |
| Entrada al multifase en 42/59 pasos (C-173) | 42 | 42 | ok |
| «±5e-3 que se compensa por celda» | ±5e-3 | sin procedencia en K8 | **objeción O4** |

## 2. Veredictos frente al criterio pre-registrado

- **C-169, enmendada por C-171 (criterio sobre k8_cg1000).** La regla dice REFUTADA si alguno de los dos cocientes es ≥ 0.7. El del gas libre vale 0.8628, así que la predicción queda **REFUTADA**, y C-173 lo aplica por la letra. Los prerrequisitos se cumplen todos:
  - cero avisos del CG;
  - skips en 0;
  - class_split y rewrites PASS en k8_* y en tests/out;
  - columnas físicas bit a bit con k7v5_mo20 y m_gas_err_* a ≤ 4e-12 de diferencia relativa (el límite es 1e-10);
  - tests OK con v131.

  La «lectura acotada» no cambia el veredicto.
- **C-170, enmendada por C-172.** El cociente 0.3156 está en la banda intermedia (> 0.3 y < 0.7), así que el resultado es **SIN DECIDIR**, como dice C-174 (estado en_disputa).
- **Enmiendas.** Se registraron antes del banco que decide (4aa8363 a las 13:59:32; k8_cg1000 empieza a las 13:59:38) y antes de cualquier veredicto (14:17), y tienen motivo. El paso a k8_cg1000 ya estaba previsto en C-169. Ver O7.
- **Comparación justa.**
  - Las cuatro configs son idénticas salvo `max_inner_pres` y `max_outer`.
  - Mismo `restart_file` (judge_otp_280/eaf3d_00280000.h5), mismos 59 pasos (280001-280059), 15 ranks y el mismo binario de banco (13:56:02, posterior al pre-registro de las 13:55:24).
  - El binario actual da resultados idénticos (r2).
  - 59 pasos tras el reinicio es una muestra corta, y el reporte lo acota a «esta ventana».

## 3. Objeciones

1. **O1 (bloqueante).** Afirmación afectada: `report.md`, «El residuo del CG sí explica el error del gas libre en B1», y la frase de Incertidumbre «B1 corre con 20 iteraciones…».
   - B1 corre con `max_outer = 5` (`campaigns/b1/judge_otp_280/config.dat:max_outer=5`).
   - La comparación que sostiene la frase usa 20 externas: `k8_mo20:Σ|e|_libre=1.027e-3` frente a `k8_cg1000:9.198e-5`.
   - Con la configuración de B1, `k8_base:Σ|e|_libre=9.203e-3`, y no existe ninguna corrida con 5 externas y el CG convergido.
   - C-125 ya había limitado K7 a 20 externas y excluido B1, y la viñeta no lleva {C-nnn}.

   **Para levantarla:** acotar el texto a «280 s, 20 externas» y citar {C-173}/{C-176}, o correr un banco k8_base con CG 1000 pre-registrado.
2. **O2.** `k8_mo20/run.log`: solo permite afirmar «≥ 1001 casos». El «≥ 85 %» no se puede verificar con K8; con 1180 Poisson saldría 84.8 %. **Para levantarla:** citar {C-125} o escribir «≥ 1001 Poisson».
3. **O3.** Hay viñetas sin {C-nnn}: la tabla de Resultado, «Almacenamiento artificial… despreciable» y Tests. Además, la procedencia de la tabla no es un comando literal. **Para levantarla:** añadir {C-173}/{C-176} y el comando python3 literal.
4. **O4.** El «±5e-3 que se compensa por celda» no tiene procedencia. **Para levantarla:** indicar la columna y la corrida (p. ej. `k8_cg1000:m_gas_err_rem_abs_all=5.150e-3`) o citar {C-110}.
5. **O5.** El denominador de «Σ|err_art| / Σ|e|» es ambiguo: `k8_base` da 4.76e-5 sobre el interior total y 7.2e-5 sobre el multifase. **Para levantarla:** escribir el denominador.
6. **O6.** «Cero avisos implica CG convergido» no cubre la salida silenciosa por SMALL (`src/mod_solver_3d.f90:245`). Se cumple el prerrequisito literal y el reporte lo declara. **Para levantarla:** registrar el residuo final o n_iter de cada Poisson.
7. **O7 (nota).** C-171 relajó el prerrequisito bit a bit después de ver la diferencia de ~1e-19 en k8_mo20. Es válida (anterior al banco que decide y al veredicto, con motivo) y no cambia ningún resultado.

Archivos clave:
- /Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K8/report.md
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/k8_cg1000/audit.csv
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/k8_base/audit.csv
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/judge_otp_280/config.dat

VEREDICTO: rechaza