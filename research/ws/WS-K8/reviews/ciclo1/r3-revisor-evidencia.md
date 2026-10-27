# WS-K8: revisión del revisor de evidencia (ronda 1 del panel actual)

Esta revisión es ciega y de solo lectura: no leí `reviews/`. Recalculé cada número del reporte desde `campaigns/b1/*/audit.csv`, `run.log` y `tests/out`, con los comandos de las notas de procedencia, `barrido_outer.py` y `check_audit.py`.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| [CG] AVISO cg1000/cg200/mo20/base | 0/2/2/1 | 0/2/2/1 | ok |
| Σ\|e\| libre (4 corridas) | 9.20e-5/8.99e-5/1.03e-3/9.20e-3 | 9.198e-5/8.991e-5/1.027e-3/9.203e-3 | ok |
| rem2/abs libre | 0.863/0.847/1.004/0.918 | 0.8628/0.8468/1.0040/0.9182 | ok |
| Σ\|e\| multifase; rem2/abs | 1.632e-2…1.814e-2; 0.197/0.197/0.203/0.339 | igual | ok |
| Neto e / neto plan (cociente) | −8.55e-4/+4.25e-4 (1.50), etc. | −8.550e-4/+4.249e-4 (1.497), etc. | ok |
| Desfase media ± sd, cg1000/cg200/base | −2.169/−2.173/−3.28e-5 | −2.1694/−2.1734/−3.282e-5 | ok |
| Desfase k8_mo20 | **−2.168e-5** ± 0.10e-5 | **−2.1675e-5** (redondea a −2.167e-5) | objeción O2 |
| sd/\|media\| | 0.060/0.059/0.047/0.136 | 0.0603/0.0593/0.0470/0.1359 | ok |
| D en el paso 1 | −2.105/−2.105/−2.110/−3.602e-5 | igual | ok |
| C-110 rem_all/abs; neto | 0.3156;1.571 / 0.3155;1.569 / 0.3186;1.571 / 0.4038;1.320 | igual | ok |
| Σ\|err_art\|/Σ\|e\|; Σ\|err_art\| | 3.0e-6…4.8e-5; 4.9e-8 | 2.96e-6/2.87e-6/5.15e-6/4.76e-5; 4.86e-8 | ok |
| class_split / rewrites (restos) | −1.6e-17; 1.8e-14; −6.2e-14 | −1.58e-17; 1.77e-14; −6.15e-14 | ok |
| Veredicto C-169/C-171 | REFUTADA | 0.8628 ≥ 0.7 → REFUTADA; prerrequisitos cumplidos | ok |
| Veredicto C-170/C-172 | SIN DECIDIR | 0.3156 ∈ (0.3, 0.7) | ok |
| Bit a bit k8_mo20 frente a k7v5_mo20 | idéntico; ≤ 1.1e-19 (relativo ≤ 4e-12) | 6 columnas idénticas; 1.08e-19; 3.97e-12 | ok |
| Enmiendas antes del banco que decide | 13:59:32 frente a 13:59:38 | commit 4aa8363 13:59:32; run.log 13:59:38 | ok |
| e_multi por paso; m_gas_out | −1.449e-5 ± 0.341e-5 (59/59); −1.645e-5 ± 6.39e-5 (25 entra / 34 sale) | igual | ok |
| corr e·out / flux·(−out) / e·(−flux) | 0.09/0.23/0.10 | 0.091/0.231/0.099 | ok |
| sd flux_multi; sd comp+eos | 3.26e-5; 3.24e-5 | 3.258e-5; 3.242e-5 | ok |
| «Σflux_multi = 95.3 % de −Σm_gas_out» (93.3; 115.7) | 95.3 % | Σflux/(−Σout) = 1.050/1.072/0.864 (95.3 % es el cociente inverso) | objeción O4 |
| Tramos de 200 pasos de k7v5_mo20_1k, Σe | **−3.05e-3**, −3.52, −3.38, −3.35, −3.55e-3 | **−3.0447e-3**, −3.517, −3.375, −3.354, −3.551e-3 | objeción O3 |
| Tramos de 200 pasos, Σout | −2.19e-3, +2.5e-5, −1.76e-3, +4.3e-4, −5.33e-3 | igual | ok |
| C-110 por tramos (20 y 200 pasos) | 0.320/0.314/0.313; 0.323/0.317/0.316; 0.314→0.349 | igual | ok |
| Σ\|cc\| multi, ratio; rem2_multi; % | 5.82e-2, 3.6; 3.21e-3; 5.5 % | 5.822e-2, 3.57; 3.214e-3; 5.52 % | ok |
| Σ\|cc\| libre; ratio; rem2/cc libre | 0.374; 4070; 2.0e-4/2.1e-4 | 0.3744; 4070; 2.03e-4/2.12e-4 | ok |
| Σ\|e\| libre de mo20 a cg1000; paso 1 | 11×; 9.8e-6 frente a 7.5e-7 | 11.2×; 9.78e-6/7.46e-7 | ok |
| Reparto comp/eos/flujo/rx; cierre por paso | +4.06e-5/+1.288e-4/1.019e-3/5.4e-6; ≤ 9.1e-19 | igual; 9.08e-19 | ok |
| sd eos_multi; sd e; corrAB; sd rem2 neto | 3.24e-5; 3.41e-6; 0.9992; 1.31e-6 | igual | ok |
| Gas libre como fracción de Σ\|e\| | 0.56 % | 0.561 % | ok |
| k7v5_mo20_1k «misma trayectoria» que k8_mo20 | misma | idéntica salvo la fila 280059 (dt recortado a t_final) | objeción O5 |
| Pruebas de humo (0.77–1.00; 0.73–0.76; 0.11) | sin fuente | 0.766/0.946/1.000; 0.732/0.760; 0.108 | objeción O6 |
| Pre-registro C-182 antes de correr | commit 34be842 | 15:17:52 frente a la primera corrida a las 15:18:02; script sin cambios | ok |
| Configs del barrido = k8_cg1000 salvo N | sí | diff: solo max_outer, monitor_freq y output_dir | ok |
| D1 del barrido (5…80) | −4.179/−2.308/−2.105/−2.078/−2.085e-5 | −4.1794/−2.3084/−2.1053/−2.0777/−2.0845e-5 | ok |
| Media D ± sd del barrido | −3.82±0.30 … −2.23±0.10 | −3.816±0.296 … −2.226±0.105 | ok |
| Externas = max_outer; res_u/res_cont | 59/59; 7.1e-3/6.4e-4 … 1.9e-4/5.2e-5 | igual | ok |
| Barrido: Σ\|e\| y cocientes de libre, multifase y C-110 | tabla de las líneas 293-295 | igual en todas las celdas | ok |
| Veredicto C-184 (cocientes) | 0.013; 0.0033; 0.011; 0.037; 0.99 | 0.0131; 0.0033; 0.0107; 0.0371; 0.990 | ok, SOPORTADA por la letra |
| P1 / P2 | 0 AVISO; 0 columnas distintas | igual | ok |
| CG con 5 externas: D1 se mueve un 16 %; con 20 externas, 0.2 % | 16 %; 0.2 % | 16.0 %; 0.24 % | ok |
| Gas libre con 5 externas: ~60 % del CG; ~40× de 5 a 20 | 60 %; 40× | 60.6 %; 39.4× | ok |
| «Con 5 externas, config de B1, vale el doble; en B1 la mitad es truncamiento» | 2×, la mitad | k8s_mo5 (CG 1000): D1 1.99×, Dm 1.76×; config de B1 (k8_base, CG 20): D1 1.71×, Dm 1.51× | **objeción O1 (bloqueante)** |
| FAIL de k8s_mo5 y k8_base (energy_balance, regime_gas) | 214.9 / 215 m/s; 2.24 | 2.226 y 214.9 (mo5); 2.243 y 215.0 (base) | ok |
| Barrido de tests/out | 78 y 66 bancos, 0 FAIL; 4.0e-12, 8.5e-15, 3.7e-14 | igual (3.97e-12; 8.49e-15 en bed_drain_n12; 3.73e-14) | ok |
| test-unit, test-quick y test-full | OK, v131 | logs OK, 0 FAIL, metrics_v131 | ok |
| Binarios: 270 bytes; identidad de _r2 | sí | 270 bytes; 0 columnas distintas | ok |

## 2. Objeciones

1. **O1 (bloqueante).** Afecta a `report.md:41-42`, `:307-311` y `:340`. El reporte dice «vale el doble (−4.18e-5) … en B1 la mitad es truncamiento».
   - El −4.18e-5 viene de `k8s_mo5`, que corre con CG 1000. B1 corre con `max_inner_pres` = 20 (`campaigns/b1/judge_otp_280/config.dat:49`).
   - En la configuración de B1 (`campaigns/b1/k8_base`):
     - D1 = −3.602e-5, que es 1.71× la meseta de −2.105e-5;
     - Dm = −3.282e-5, que es 1.51× la meseta de −2.169e-5;
     - el exceso es del 41 % y del 34 %, no la mitad.
   - Incluso con CG 1000, Dm sale 1.76× la meseta; solo D1 da 1.99×.
   - El reparto aditivo «mitad truncamiento, mitad estructural» no está probado, y viene de N = 5, que C-182 declaró «se reporta, no decide» (C-183 sigue en estado `propuesta`).
   - **Para levantarla:** dar los cocientes reales separando CG 1000 y CG 20, retirar «en B1 la mitad» o calificarlo como lectura no pre-registrada, y corregir lo mismo en `.claude/rules/transporte-energia.md:299-301`.
2. **O2.** `report.md:161` y `:245` dan −2.168e-5 para el desfase de k8_mo20; lo recalculado es −2.1675e-5, es decir, −2.167e-5.
3. **O3.** `report.md:237` da −3.05e-3 para el primer tramo; lo recalculado es −3.0447e-3, es decir, −3.04e-3.
4. **O4.** `report.md:233` invierte el cociente. Las cifras 95.3, 93.3 y 115.7 % son −Σm_gas_out / Σflux_multi. El cociente que el texto nombra vale 1.050, 1.072 y 0.864.
5. **O5.** `report.md:236` dice «misma trayectoria». En `k8_mo20` la fila 280059 difiere de `k7v5_mo20_1k` en 82 columnas: el último dt es 9.99999711e-4, recortado a t_final. El efecto es despreciable, pero hay que precisarlo.
6. **O6.** `report.md:93-96` y `:411-412` no tienen fuente. Los valores son reproducibles en `tests/out/{arc_melt_n4,cold_10step_n8,bed_bath_rest_n4}` (0.766/0.946/1.000; 0.732/0.760; 0.108). Basta añadir la nota de procedencia.
7. **O7.** El alcance de C-184 es un solo estado de reinicio, una sola trayectoria por N y 59 pasos. Hay que acotarlo en la sección Incertidumbre, porque la regla del régimen marginal B1 > 280 s exige un juez estadístico.
8. **O8.** No es verificable directamente que el barrido usara `campaigns/bin/eaf3d_k8b_opt`, porque el run.log no lo registra. Solo hay evidencia indirecta: `k8s_mo20` es idéntico a `k8_cg1000` y a `k8_cg1000_r2`.

## 3. Juicio contra los criterios

- **C-169/C-171 (REFUTADA)** y **C-170/C-172 (SIN DECIDIR)** coinciden literalmente con el criterio enmendado. Las enmiendas son anteriores al banco que decide y tienen motivo; el reporte declara con transparencia la relajación del bit a bit.
- **C-182 (SOPORTADA)** cumple la letra del criterio. Es una comparación justa: mismo reinicio, mismo binario, misma config salvo N; P1 y P2 se cumplen y el pre-registro es anterior a las corridas. La salvedad del lazo estancado está declarada.
- El rechazo se debe a O1: el reporte extrae de bancos que no deciden (N = 5 con CG 1000) una conclusión cuantitativa sobre B1 («la mitad es truncamiento») que no coincide con lo que da la configuración de B1 (CG 20), y la repite en el resumen y en la conclusión.

VEREDICTO: rechaza
