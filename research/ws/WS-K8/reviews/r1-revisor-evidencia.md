# WS-K8, ciclo 2, ronda 1: revisión de evidencia

Revisión de solo lectura. No ejecuté ningún binario, `make` ni `mpirun`. Lo que hice:
- Recalculé cada cifra desde `campaigns/b1/*/audit.csv` y `run.log` con python3, con `research/ws/WS-K8/scripts/barrido_outer.py` y `desfase_residuo.py` (con `-B`, sin escribir) y con `tests/integration/check_audit.py`.
- Comprobé la cronología con `git show` y `stat`, las citas con `sed -n` y la integridad del registro con `ledger.py check`, que da OK con 192 eventos.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| [CG] AVISO cg1000/cg200/mo20/base | 0/2/2/1 | 0/2/2/1 | ok |
| Gas libre Σ\|e\| | 9.20e-5 / 8.99e-5 / 1.03e-3 / 9.20e-3 | 9.198e-5 / 8.991e-5 / 1.027e-3 / 9.203e-3 | ok |
| Gas libre rem2/abs | 0.863 / 0.847 / 1.004 / 0.918 | 0.8628 / 0.8468 / 1.004 / 0.9182 | ok |
| Multifase Σ\|e\|; rem2/abs | 1.632e-2…1.814e-2; 0.197/0.197/0.203/0.339 | igual | ok |
| Neto e / plan (cg1000) | −8.55e-4 / +4.25e-4 (1.50) | −8.550e-4 / +4.249e-4; 1.497 | ok |
| Desfase medio ± sd | −2.169/−2.173/−2.167/−3.28 e-5 ± 0.13/0.13/0.10/0.45 | −2.169/−2.173/−2.167/−3.282 ± 0.131/0.129/0.102/0.446 | ok |
| sd/\|media\| | 0.060/0.059/0.047/0.136 | 0.0603/0.0593/0.0470/0.1359 | ok |
| D en paso 1 | −2.105/−2.105/−2.110/−3.602 e-5 | −2.1053/−2.1053/−2.1103/−3.6017 | ok |
| C-110 rem_all/abs; neto | 0.3156;1.571 / 0.3155;1.569 / 0.3186;1.571 / 0.4038;1.320 | igual | ok |
| Σ\|err_art\|/Σ\|e\| | 3.0e-6/2.9e-6/5.2e-6/4.8e-5 | 2.96e-6/2.87e-6/5.15e-6/4.76e-5 | ok |
| class_split / rewrites (restos) | −1.6e-17; 1.8e-14; −6.2e-14 | −1.58e-17; 1.77e-14; −6.15e-14 | ok |
| skip liq/cc | 0 | 0 en los 4 | ok |
| **C-173 frente a C-171**: libre ≥ 0.7 → REFUTADA | 0.863 | 0.8628 ≥ 0.7 | ok (literal) |
| **C-174 frente a C-172**: 0.3 < x < 0.7 → SIN DECIDIR | 0.3156; 1.571 | igual | ok (literal) |
| Enmiendas C-171/C-172 antes del banco decisivo | 4aa8363 13:59:32; k8_cg1000 13:59:38 | commit 13:59:32; run.log creado 13:59:38 | ok (antes del veredicto y con motivo; relaja solo prerrequisitos, lo que el reporte declara) |
| Bit a bit k8_mo20 frente a k7v5_mo20 | física idéntica; err ≤ 1.1e-19 (rel ≤ 4e-12) | 117 columnas comunes: solo difieren 7 m_gas_err_*, máx 1.08e-19, rel 3.97e-12; HDF5 final: 56 datasets idénticos | ok |
| Reparto neto multifase | comp 4.06e-5, eos 1.288e-4, flujo 1.019e-3, rx 5.4e-6; cierre ≤ 9.1e-19 | 4.0613e-5, 1.2876e-4, 1.0190e-3, 5.367e-6; 9.08e-19 | ok |
| e_multi; m_gas_out por paso | −1.449e-5 ± 0.341e-5 (59/59); −1.645e-5 ± 6.39e-5 (entra 25, sale 34) | igual | ok |
| corr 0.09 / 0.23 / 0.10; sd 3.26e-5 / 3.24e-5 | | 0.091 / 0.231 / 0.099; 3.26e-5 / 3.24e-5 | ok |
| 95.3/93.3/115.7 %; 1.050/1.072/0.864 | | 0.9527/0.9331/1.157; 1.0496/1.0717/0.8643 | ok |
| Tramos de k7v5_mo20_1k: Σe y Σout | −3.04…−3.55e-3; −2.19e-3…−5.33e-3 | igual | ok |
| C-110 por tramos (1k) | 0.314 → 0.349 | 0.314…0.349 | ok |
| Tramos de 20 pasos con CG 1000 / CG 20 | 0.320/0.314/0.313 y 0.323/0.317/0.316 | igual | ok |
| Σ\|cc\| multi; 3.6×; 5.5 % | 5.82e-2 | 5.822e-2; 3.57; 0.0552 | ok |
| Σ\|cc\| libre; 4070×; rem2/cc | 0.374; 2.0e-4 (CG 200) / 2.1e-4 (CG 1000) | 0.3744; 4070; 2.03e-4 / 2.12e-4 | ok |
| rem2_libre | 7.94e-5 | 7.936e-5 | ok |
| sd eos 3.24e-5, sd e 3.41e-6, corr(A,B) 0.9992, sd D 1.31e-6 | | igual | ok |
| Gas libre en paso 1 (mo20 / cg1000) | 9.8e-6 / 7.5e-7 | 9.78e-6 / 7.46e-7 | ok |
| Paso 1 libre k8_base / k8s_mo5 | 1.71e-4 / 5.80e-5 | 1.71e-4 / 5.80e-5 | ok (sin comando: O1) |
| **Barrido de C-182**: D1 por N = 5/10/20/40/80 | −4.179/−2.308/−2.105/−2.078/−2.085 e-5 | −4.1794/−2.3084/−2.1053/−2.0777/−2.0845 | ok |
| Media D ± sd | −3.82±0.30 … −2.23±0.10 | igual | ok |
| Externas = max_outer | 59/59 en los 5 | 59/59 | ok |
| res_u / res_cont medios | 7.1e-3/6.4e-4 … 1.9e-4/5.2e-5 | igual | ok |
| Libre y multifase por N; C-110 por N | tabla | igual en las 15 celdas | ok |
| **C-184 frente a C-182** (≤ 0.10 en D1; ≤ 0.15 en Dm) | 0.013, 0.0033; 0.011, 0.037; refutación 0.99 | 0.0131, 0.0033; 0.0106, 0.0371; 0.990 | ok (literal) |
| P1 (cero AVISO) y P2 (identidad k8s_mo20 = k8_cg1000) | cumplidos | 0 AVISO; 60 filas, 137 columnas, ninguna distinta | ok |
| Pre-registro C-182 antes de correr | 34be842 | commit 15:17:52; primera corrida 15:18:02; barrido_outer.py sin cambios desde 34be842 | ok |
| **C-191 frente a C-189** (N = 21 y 41) | 0.030, 0.0003; 0.022, 0.022 | 0.0296, 0.0003; 0.0224, 0.0225; 0 AVISO | ok (literal); d0fc6d9 a las 16:08:00, corrida a las 16:08:11 |
| k8s_mo41: pasos convergidos | 2 (280022 con 33, 280058 con 32) | igual; en los demás bancos ninguno | ok (sin comando: O1) |
| Correlación de D con residuos (N = 10…80) | −0.33…+0.30; −0.13…+0.21 | −0.326…+0.298; −0.134…+0.206 | ok (O2) |
| Extrapolación | −2.065e-5 (−2.000e-5 con N = 5) | −2.0651e-5 / −2.0004e-5 | ok |
| Exceso con 5 externas (C-187) | 1.99/1.76; 1.71/1.51; 50/43/42/34 %; +16 %; 60 %; ~40× | 1.985/1.759; 1.711/1.513; 49.6/43.1/41.5/33.9 %; 1.160; 0.606; 39.4 | ok |
| FAIL en k8s_mo5 / k8_base | energía 2.23 / 2.24; u_gas 214.9 / 215.0 | 2.226 / 2.243; 214.9 / 215.0 | ok |
| Identidades de masa del gas en k8s_* (7 bancos) | PASS | PASS | ok |
| Barrido de tests/out | 78 / 66 / 66 bancos, 0 FAIL; 4.0e-12; 8.5e-15; 3.7e-14 (arc_melt_slag_heel_n1) | igual (3.97e-12; 8.49e-15; 3.73e-14) | ok |
| Logs de tests | unit, quick y full OK; golden v131; 0 FAIL | igual; el sha del diff de src/ (78797d1c) es el mismo que el actual | ok |
| Binarios: 270 bytes; _r2 idénticos | | cmp: 270; k8_cg1000/k8_mo20 frente a _r2: ninguna columna distinta | ok (O4) |
| Pruebas de humo | 0.77–1.00; 0.73–0.76; 0.11 | 0.766/0.946/1.000; 0.732/0.760; 0.108 | ok (O3, atribución) |
| Configs: base frente a mo20 solo max_outer; B1 con 5 externas y CG 20; alpha_p y alpha_T 0.7; alpha_g_comp_min ausente | | `diff` y `grep` lo confirman; restart en judge_otp_280 y 15 ranks en todas | ok |
| Citas de código: 866-871, :898, 1019-1028, 1061, 1102-1103, 1106, config:94, solver:245, 271-279, ALPHA_BED | | coinciden; 625-632 está desplazada una línea | ok (O5) |

## 2. Objeciones (ninguna bloqueante)

1. **O1, notas de procedencia sin comando.** Afecta a:
   - `report.md:261`: el error del gas libre en el paso 1 de k8_base y k8s_mo5, 1.71e-4 y 5.80e-5;
   - `:280-283`: la identidad de k7v5_mo20_1k con k8_mo20 y el dt de la fila 280059, 9.9999971e-4;
   - `:376`: los pasos 280022 y 280058 de k8s_mo41;
   - `:164`: las horas.

   Recalculé las cuatro y coinciden. Para levantarla, hay que añadir los comandos a las notas.
2. **O2, `report.md:356`.** «D no sigue al residuo» omite N = 5 (`k8s_mo5`: corr +0.387 / +0.461). La extrapolación la dominan N = 5 y 10, porque res_cont del paso 1 solo baja de 1.27e-5 a 6.5e-6 entre 20 y 80 externas. Para levantarla, hay que citar las correlaciones con N = 5 y lo que pesa cada punto en el ajuste.
3. **O3, `report.md:129-131`.** El 1.00 del gas libre es de `bed_bath_rest_n4`, no de arc_melt_n4 ni de cold_10step_n8, que dan 0.766 y 0.946. Además, tests/out es la salida del binario final. Para levantarla, hay que dar los valores por banco.
4. **O4.** Los artefactos no dicen qué binario usó cada corrida (run.log no lo registra). Lo mitiga la identidad k8s_mo20 = k8_cg1000 = k8_cg1000_r2. Para levantarla, hay que registrar el binario por corrida.
5. **O5.** Algunas citas están desplazadas. `src/mod_pressure_3d.f90:625-632` debería ser 624-631. La condición de inicio de la clase libre está en `src/mod_audit.f90:1089`, no en :981. «fsat ≡ 1» no excluye excursiones de α_s dentro del paso, porque `ws_bed` se evalúa en `multiphase_iteration`. No afecta a ninguna cifra ni a ningún veredicto (C-188).

## 3. Juicio

- **Veredictos frente a los criterios pre-registrados.** Los cuatro veredictos coinciden literalmente con su criterio: C-173 frente a C-171, C-174 frente a C-172, C-184 frente a C-182 y C-191 frente a C-189.
- **Enmiendas.** C-171 y C-172 se registraron y commitearon antes del banco decisivo (13:59:32 frente a 13:59:38) y antes de cualquier veredicto, con motivo. Solo relajan el prerrequisito bit a bit (con una diferencia medida de 1e-19) y no tocan los umbrales. El reporte declara que se vio k8_mo20 antes.
- **Comparaciones justas.** Todas parten del mismo reinicio (judge_otp_280), con la misma ventana (280001–280059) y 15 ranks. Las configs difieren solo en la clave probada (y en monitor_freq, cuya neutralidad está comprobada por identidad). Los binarios son equivalentes: audit.csv idénticos.
- **Alcance de las conclusiones.** «Estructural» se acota bien. El lazo externo no converge y el reporte lo dice. La ventana de 59 pasos con una sola trayectoria por config se declara en Incertidumbre, y D1 parte del mismo estado en todos los bancos.
- **Cifras.** No encontré ninguna cifra que se aparte de su recálculo más allá del redondeo mostrado.

VEREDICTO: aprueba