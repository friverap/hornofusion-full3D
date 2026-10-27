# Revisión de evidencia — WS-K8 (revisor-evidencia)

**Resultado:** apruebo. Todas las cifras de las que dependen los veredictos se reproducen desde los datos. Hay 8 objeciones y ninguna bloquea: una relación escrita al revés, dos redondeos, una cita equivocada, un matiz de trayectoria, dos puntos no verificables tal cual y uno de proceso (el nombre de archivo de esta revisión).

Material leído: `research/README.md`, el reporte `research/ws/WS-K8/report.md` y las entradas C-169 a C-180 del registro (más C-110, C-125, C-133, C-145, C-150, C-154, C-163 y C-168). No leí `reviews/`.

Cómo verifiqué: solo lectura. Usé python sobre los `audit.csv`, `check_audit.py`, `grep`, `sed`, `git log/show`, `cmp` y `strings`. Directorio de trabajo: `/Users/frariv/Horno/hornofusion-full3D`.

## 1. Tabla de verificación

Ventana usada para recalcular: las 59 filas con `step > 280000` de `campaigns/b1/k8_*/audit.csv`.

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Avisos `[CG] AVISO` (cg1000 / cg200 / mo20 / base) | 0 / 2 / 2 / 1 | 0 / 2 / 2 / 1 | ok |
| Σ\|e\| del gas libre | 9.20e-5 / 8.99e-5 / 1.03e-3 / 9.20e-3 | 9.198e-5 / 8.991e-5 / 1.027e-3 / 9.203e-3 | ok |
| rem2/abs del gas libre | 0.863 / 0.847 / 1.004 / 0.918 | 0.8628 / 0.8468 / 1.0040 / 0.9182 | ok |
| Σ\|e\| del multifase | 1.632e-2 / 1.632e-2 / 1.636e-2 / 1.814e-2 | ídem | ok |
| rem2/abs del multifase | 0.197 / 0.197 / 0.203 / 0.339 | 0.1970 / 0.1966 / 0.2028 / 0.3391 | ok |
| Neto e frente a neto del plan | −8.55e-4/+4.25e-4 (1.50); −8.58e-4/+4.25e-4; −8.55e-4/+4.23e-4; −1.57e-3/+3.65e-4 | −8.550e-4/+4.249e-4 (1.497); −8.577e-4/+4.246e-4; −8.555e-4/+4.233e-4; −1.571e-3/+3.650e-4 | ok |
| Desfase por paso (media ± sd, pasos negativos) | cg1000 −2.169e-5±0.13e-5; cg200 −2.173e-5; **mo20 −2.168e-5±0.10e-5**; base −3.28e-5±0.45e-5; 59/59 | −2.1694e-5±1.31e-6; −2.1734e-5; **−2.16749e-5±1.02e-6**; −3.282e-5±4.46e-6; 59/59 | mo20: **O2** |
| corr(e_multi, plan) | 0.93 / 0.93 / 0.96 / 0.68 | 0.930 / 0.933 / 0.955 / 0.677 | ok |
| C-110: rem_all/abs; neto | 0.3156; 1.571 / 0.3155; 1.569 / 0.3186; 1.571 / 0.4038; 1.320 | 0.31561; 1.5707 / 0.31553; 1.5690 / 0.31859; 1.5705 / 0.40384; 1.3196 | ok |
| Σ\|err_art\| / Σ\|e\| (multifase + libre) | 3.0e-6 / 2.9e-6 / 5.2e-6 / 4.8e-5 | 2.96e-6 / 2.87e-6 / 5.15e-6 / 4.76e-5 | ok |
| Σ\|err_art\| en k8_cg1000; Σ\|e\| | 4.9e-8; 1.64e-2 | 4.862e-8; 1.6408e-2 | ok |
| Resto de `mass_gas_class_split` (cg1000) | −1.6e-17 | −1.58e-17 | ok |
| Resto de `mass_gas_rewrites` (cg1000; mo20) | 1.8e-14; −6.2e-14 | 1.77e-14; −6.15e-14 | ok |
| Reparto por conjunto: comp / eos / flujo / rx | +4.06e-5 / +1.288e-4 / +1.019e-3 / +5.4e-6 | 4.0613e-5 / 1.2876e-4 / 1.0190e-3 / 5.367e-6 | ok |
| Máximo resto de `mass_gas_flux_closure` | ≤ 9.1e-19 | 9.08e-19 | ok |
| e_multi por paso | −1.449e-5 ± 0.341e-5, 59/59 | −1.4491e-5 ± 3.414e-6, 59 | ok |
| m_gas_out por paso; pasos que entran / salen | −1.645e-5 ± 6.39e-5; 25 / 34 | −1.6455e-5 ± 6.393e-5; 25 / 34 | ok |
| corr (e,out) / (flux,−out) / (e,−flux) | 0.09 / 0.23 / 0.10 | 0.091 / 0.231 / 0.099 | ok |
| sd de flux_multi; sd de comp+eos | 3.26e-5; 3.24e-5 | 3.258e-5; 3.242e-5 | ok |
| «Σ flux_multi = 95.3 % de −Σ m_gas_out» (93.3 / 115.7 %) | 95.3 / 93.3 / 115.7 % | Σflux/−Σout = 105.0 / 107.2 / 86.4 %; el inverso da 95.3 / 93.3 / 115.7 % | **O1** |
| k7v5_mo20_1k: Σ e_multi por tramos | **−3.05e-3**, −3.52, −3.38, −3.35, −3.55 | **−3.0447e-3**, −3.517, −3.375, −3.354, −3.551 | tramo 1: **O3** |
| k7v5_mo20_1k: Σ m_gas_out por tramos | −2.19e-3, +2.5e-5, −1.76e-3, +4.3e-4, −5.33e-3 | −2.192e-3, +2.46e-5, −1.764e-3, +4.31e-4, −5.330e-3 | ok |
| 0.314 → 0.349 en 1k {C-154} | 0.314 → 0.349 | 0.314 / 0.328 / 0.334 / 0.339 / 0.349 | cifra ok; cita mal: **O4** |
| Σ\|cc\|_multi; múltiplo de Σ\|e\|; rem2/Σ\|cc\| | 5.82e-2; 3.6; 5.5 % | 5.822e-2; 3.568; 5.52 % | ok |
| Σ\|cc\|_libre; múltiplo; rem2/Σ\|cc\| (cg200, cg1000) | 0.374; 4070; 2.0e-4, 2.1e-4 | 0.3744; 4070.2; 2.03e-4, 2.12e-4 | ok |
| Σ\|e\|_libre en el paso 1 (CG 20 frente a CG 1000) | 9.8e-6 / 7.5e-7 | 9.78e-6 / 7.46e-7 | ok |
| Tramos de 20 pasos (CG 1000; CG 20) | 0.320/0.314/0.313; 0.323/0.317/0.316 | 0.3196/0.3136/0.3134; 0.3227/0.3166/0.3162 | ok |
| Gas libre como fracción de Σ\|e\| del interior | 0.56 % | 0.561 % | ok |
| comp + eos (multifase) | +1.7e-4 | 1.694e-4 | ok |
| Pruebas de humo (libre; multifase; bed_bath) | 0.77–1.00; 0.73–0.76; 0.11 | tests/out final: 0.766 / 0.946 / 1.000; 0.732 / 0.760; 0.108 | ok, sin nota: **O6** |
| Bit a bit k8_mo20 frente a k7v5_mo20 | idénticas las 6 columnas físicas en 60 filas; err_* ≤ 1.1e-19, rel ≤ 4e-12 | 0 diferencias; 1.084e-19; 3.97e-12 | ok |
| Corridas `_r2` idénticas; binarios difieren en 270 bytes | 137 col × 60 filas; 270 B | `[]` en ambas; `cmp -l` da 270 (solo cadenas con número de línea) | ok |
| Barrido de tests/out | 78 / 66 bancos, 0 FAIL; 4.0e-12; 8.5e-15; 3.7e-14 | 78 / 66 / 66, 0 FAIL; 3.97e-12; 8.49e-15; 3.73e-14 | ok |
| test-unit / test-quick / test-full | OK, golden v131 | «UNIT TESTS: OK», «TESTS (quick): OK», «TESTS (full): OK», metrics_v131, 0 FAIL | ok |
| k8_base no pasa `check_audit` | FAIL energy_balance 2.24; regime_gas 215 | 2.243; 215.0 m/s | ok |
| Avisos de k8_mo20 en los casos 1 y 1001 | sí | `run.log`:45-46 | ok |
| Referencias de código | :1106; 866-871; :898; config:94; solver:245 y 271-279 | coinciden | ok |
| C-110: +5.1e-3 / −6.0e-3 | — | +5.11e-3 / (−2.78 − 3.20)e-3 = −5.98e-3 | ok |

## 2. Veredictos frente al criterio pre-registrado

- **C-169 enmendada por C-171 → REFUTADA.** Se lee literal en el criterio: «REFUTADA si alguno de los dos cocientes >= 0.7» y en k8_cg1000 el del gas libre vale 0.8628. Los incisos restantes (0.197 cumple; 1.497 falla) se informan sin reinterpretarlos.
- **C-170 enmendada por C-172 → SIN DECIDIR.** También literal: 0.3156 cae entre 0.3 y 0.7, y el neto vale 1.571.
- **Prerrequisitos.** Se cumplen todos:
  - 0 avisos del CG en k8_cg1000;
  - los checks PASS en k8_* y en tests/out;
  - columnas de salto (skip) a 0;
  - bit a bit dentro de la tolerancia;
  - tests OK con golden v131.
- **Validez de las enmiendas.** C-171 y C-172 tienen motivo. Se commitearon en `4aa8363` (13:59:32), antes de que arrancara k8_cg1000 (13:59:38) y antes de los veredictos (14:17). El pre-registro `8dcb6e5` (13:55:24) es anterior al binario (13:56:02). La relajación del bit a bit llegó después de ver que k8_mo20 lo incumplía por 1e-19; el reporte lo dice abiertamente, y k8_cg200 con el criterio original da el mismo veredicto. Según las reglas de `research/README.md`, son válidas.
- **Comparación justa.** Las configuraciones solo difieren en la clave probada (`max_inner_pres` o `max_outer`). Mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`), 15 ranks y misma ventana. La base del bit a bit es la correcta (`k7v5_mo20`).
- **Alcance.** 59 pasos y un solo banco que decide. El reporte acota bien esta limitación en «Incertidumbre»: 5 externas sin medir, deriva larga sin probar con CG 1000 y el hueco del criterio «0 avisos ⇒ convergido» (`mod_solver_3d.f90:245`).

## 3. Objeciones (ninguna bloqueante)

1. **O1 — relación invertida.** Ubicación: `report.md`, «Neto multifase», primer subapartado.
   - El reporte dice «Σ flux_multi equivalga al 95.3 % de −Σ m_gas_out».
   - Lo correcto: `campaigns/b1/k8_cg1000/audit.csv` da Σflux/−Σout = 1.050 (1.072 en k8_mo20, 0.864 en k8_base). Las cifras 95.3 / 93.3 / 115.7 % corresponden a −Σout/Σflux.
   - Cómo se levanta: escribir «−Σ m_gas_out equivale al 95.3 % de Σ flux_multi».
2. **O2 — redondeo.** `campaigns/b1/k8_mo20/audit.csv`: el desfase vale −2.16749e-5, es decir −2.167e-5, no −2.168e-5. Aparece en la tabla, en la prosa y en C-178. C-179 ya da −2.167e-5.
3. **O3 — redondeo.** `campaigns/b1/k7v5_mo20_1k/audit.csv`, tramo 280001–280200: Σ e_multi = −3.0447e-3, es decir −3.04e-3, no −3.05e-3.
4. **O4 — cita equivocada.** La cifra «0.314 → 0.349» está en C-145 y C-163. C-154 da 0.380 → 0.426, que es otra cantidad (el subconjunto con gas). Hay que citar {C-145}{C-163}.
5. **O5 — matiz de trayectoria.** «Misma trayectoria física» que k8_mo20 vale hasta 280058. En 280059 `p_max` vale 48955.6434 frente a 48955.6369, por el recorte del último dt a `t_final` = 280.06. Basta añadir el matiz.
6. **O6 — no verificable tal cual.** Las cifras de la prueba de humo previa al pre-registro no tienen log ni nota de procedencia. Sí se reproducen con `tests/out` del diff final mediante `check_audit.py tests/out/{arc_melt_n4,cold_10step_n8,bed_bath_rest_n4} | grep mass_gas_cells_cc`. Hay que añadir esa nota y aclarar que son los bancos del diff final.
7. **O7 — no verificable directamente.** `run.log` no registra el ejecutable. Que k8_cg200 y k8_base usaran `campaigns/bin/eaf3d_k8_opt` solo se deduce de las fechas. Solo k8_cg1000 y k8_mo20 se repitieron con `eaf3d_k8b_opt`, con resultado idéntico. La corrida que decide está cubierta. Conviene decirlo en «Incertidumbre».
8. **O8 — proceso.** El reporte dice «Ronda 2», pero `research/ws/WS-K8/status.json` sigue con `"ronda": 1` y ya tiene los veredictos de la ronda 1. Guardar esta revisión en `reviews/r1-revisor-evidencia.md` sobrescribiría la de la ronda 1. Para levantarla:
   - guardarla como `r2-revisor-evidencia.md`;
   - actualizar la ronda con `ledger.py ws-set`.

VEREDICTO: aprueba