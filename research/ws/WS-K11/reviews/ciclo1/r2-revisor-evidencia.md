# Revisión r1, revisor de evidencia, WS-K11

Revisé `research/ws/WS-K11/report.md` frente a `research/ledger.jsonl` (C-222, C-224 a C-228, C-230, C-233, C-236 a C-239). Recalculé todo en modo solo lectura: `h15.py`, `medir_centinela.py`, `check_audit.py`, python/h5py sobre los audit.csv y los snapshots, `git log` y `stat`. No usé `snap_tgfix.py` porque escribe; calculé su misma métrica a mano. `ledger.py check` da OK.

## Comprobación del pre-registro y de que la comparación sea justa (H15)
- C-238 se registró a las 01:20:44 y entró en el commit `424a70d` a las 01:20:50, junto con `h15.py`. El run.log del brazo A nació a las 01:20:55 y el del brazo B a las 01:25:09. El pre-registro fue anterior a las corridas.
- No hay enmienda de C-238. C-239 lo juzga con el criterio literal: A sin pico (69.4 m/s, 15 kPa) y B con pico (300.0 m/s) en los pasos 2-10, lo que da SOPORTADA. Prerrequisito: 0 `[CG] AVISO` en los dos brazos. El veredicto se ajusta a la letra.
- Diferencias de config entre A y `k10b_dt025`: solo `pc_transport_f28` y `pc_outlet_total_pressure` (más output_dir). Entre B y `k10b_dt025`: solo restart_file y t_final.
- Los tres usan el binario `campaigns/bin/eaf3d_k10b_opt` (creado el 27-oct a las 22:37, antes de las tres corridas), con 15 procesos MPI, dt 0.25 ms y 20 externas.
- Una trayectoria por brazo, lo que el reporte declara. Para los pasos 2-10 basta, porque son deterministas.

## Tabla

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| k10b_dt025, pasos 280002-280004: u / p | 198.6/281, 300.0/461, 200.8/199 | igual | ok |
| FAIL de k10b_dt025 | sentinel_gas, regime_p 591.6 kPa (280161), regime_gas | igual; 591.59 kPa en el 280161 | ok |
| comp_carry | 0 | suma de |c| = 0.0 | ok |
| |Δρ/ρ| frente a la EOS, celdas con gas | ≤ 4.4e-16, 68232 | 4.44e-16, 68232 | ok |
| Tg_end frente a T_gas | 17.7 %, p99 0.2 % | |T/Tg_end-1| máx 0.177, p99 0.0022 | ok |
| H12 tgfix: serie 280001-280005 y centinela | igual a 3 cifras, 300 m/s en el 280003 | igual; FAIL sentinel_gas y regime_gas | ok |
| EOS final por unidad de tiempo | 2.92 / 2.88 / 2.87 kg/s | 2.922 / 2.882 / **2.865** | O3 (redondeo) |
| pico a 1 / 0.5 / 0.25 ms | 99.6 kPa y 163.5 m/s / 191.4 / 461 y 300 | 99.63 y 163.5 / 191.41 / 460.8 y 300 | ok |
| fechas de 2f0529b y 8f568fc | 21-oct 10:13 y 22-oct 02:56 | igual | ok |
| «arrancó ese mismo minuto» | – | run.log a las 02:57:32 (43 s después) | O4 |
| tabla del paso 7 (scrfh_base, scrfh_b, m203, judge_otp_280) | 71.9/14.8, 71.7/14.8; 160.0/65.3, 189.8/62.0; 126.5/50.3, 215.0/83.5 | igual | ok |
| m203/m21f1 frente a judge_otp_280, 280001-280011 | < 5e-6 | 4.83e-6 | ok |
| marcas de tiempo de scrfh_b y eaf3d_cand_f28_opt | 21:29:42 | igual (los dos) | ok |
| `[CG] AVISO` en los 4 bancos de 1 ms | > 0 | 8, 8, 8, 8, 328 y k10_base 1 | ok |
| H15 brazo A: pasos 2-10 y ventana | 69.4 / 15 kPa; 15 kPa; 0,0,0,0 | igual (máximo de p en el 280089) | ok |
| H15 brazo B | 300.0 / 342 kPa; 365 kPa en el 290020; 58,59,59,59 | igual | ok |
| FAIL de los brazos | A ninguno; B sentinel_gas, regime_gas | igual | ok |
| cuartos de k10b_dt025 (paso 9) | 31, 21, 32, **33** | 31, 21, 32, **36** (los dos repartos) | **O1** |
| «con 1 ms se asienta en 20-25 pasos» | sin fuente | compatible con k10b_mo20 y judge_otp_280 (periodo 2 hacia el paso 20-24) | O2 |
| Resultado: k11_dt025_s290 | 71.6 / 79; 450.0 en el 290093 (128.6); 344.3 en el 290074; 5/235 | igual | ok |
| Resultado: k11_dt05_s290 | 80.1 / 71; 70.6 en el 290004; 0/117 | igual | ok |
| Resultado: k11_mo20_s290 | 124 / 55; 70.0 en el 290011 (121.5); 0/58 | igual | ok |
| Resultado: k10b_dt025 | 300 / 461; 591.6 en el 280161 (113.2); 120/235 | igual | ok |
| regime_p de k11_dt025_s290 | PASS, 4.500e5 | igual | ok |
| cuartos de k10b_dt025 y pasos con u > 200 m/s | 31,21,32,36; 229.1, 282.8, 252.8, 229.4 | igual | ok |
| cuartos con 0.5 ms | 8,1,2,0 de 29,29,29,30 | igual | ok |
| identidades de masa de k11_dt025_s290 | pasan | row_volume, decomp y eos_end PASS | ok |
| k11_base_s290 | 107 m/s, 27 kPa, FAIL energy_balance, 1 AVISO con res 4.198e-2 | 106.9, 27.07 kPa, gap/permitido 2.153, 1 AVISO | ok |
| k10_base y k11_base_s290 frente a judge_otp_280 | 2.2e-12 y 5.2e-13 | 2.22e-12 y 5.21e-13 | ok |
| snapshots de 280 s: datasets que difieren | 8 de 56; S_arc hasta 3.1e8 | 8 de 56; S_arc 3.14e8 | ok |
| judge_fh_275: marcas de tiempo, binario y auditoría | 13:24-16:38; binario 13:23:42; audit cada 5 | igual (audit_freq = 5; pasos 280000, 280005) | ok |
| alternancia de judge_otp_280 en 289998-290009 | 106.9/90.5; 23.5/27.0 | igual | ok |
| alternancia de k11_mo20_s290 | ~122 / ~77 | 120-124 / 76-79 | ok |

## Objeciones
1. **O1 (bloqueante).** En `report.md`, paso 9, figura «31, 21, 32 y 33»; el valor recalculado es 31, 21, 32, **36**. El reporte se contradice con su propia sección Resultado, y el error está también en el veredicto registrado C-239. Para levantarla: corregir el reporte y registrar un evento con ref C-239, porque el registro es append-only.
2. **O2.** «con 1 ms se asienta en unos 20-25 pasos» no tiene fuente ni comando. Hay que añadir la ruta (`campaigns/b1/k10b_mo20/audit.csv`) y definir qué cuenta como «asentado».
3. **O3.** Para 0.25 ms la tasa es 2.865, que se redondea a 2.86, no a 2.87.
4. **O4.** «ese mismo minuto» es falso por 43 s. Además, 2f0529b y 8f568fc *introducen* las claves con valor ON; no cambian su valor por defecto.
5. **O5.** Fuera del reporte: `status.json` tiene prediccion = C-226, cuando el veredicto que sostiene el resultado es C-238/C-239.

Ni el veredicto por la letra de H15 ni el de H12 o H13 cambian. El resto de las cifras se reproduce. El rechazo se debe solo a O1: una cifra mal escrita en el reporte y en el veredicto registrado.

VEREDICTO: rechaza
