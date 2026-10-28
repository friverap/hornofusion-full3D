# Revisión WS-K11, ronda 1: revisor de evidencia

Alcance: `research/ws/WS-K11/report.md`, entradas C-222 a C-249 (`ledger.py show`). Todo en solo lectura: scripts `h15.py`, `h17.py`, `pares.py`, `medir_centinela.py`, `centinela.py` y `check_audit.py`, más python/h5py sobre archivos existentes. No ejecuté ninguna corrida. `ledger.py check`: OK (249 eventos).

**Veredicto: apruebo.** Todos los números que importan se reproducen y los cuatro veredictos coinciden con la letra del criterio. Quedan dos objeciones menores, no bloqueantes, que conviene corregir.

## Pre-registro y justicia de la comparación

| Predicción | Commit de pre-registro | Nacimiento del run.log | ¿Antes? |
|---|---|---|---|
| H15 C-238 | 424a70d 01:20:50 | A 01:20:55, B 01:25:09 | sí |
| H16 C-244 | aa93539 01:44:37 | C 01:44:42, D 01:48:56 | sí |
| H17/H18 C-246/C-247 | 650d712 09:24:52 | E 09:24:57, F 09:29:27 | sí |

- **Binario.** Todos los brazos y `k10b_dt025` registran `Ejecutable: campaigns/bin/eaf3d_k10b_opt`. El binario nació a las 22:37:45 del 27-oct y no se ha modificado desde entonces (birth = mtime), antes de todas las corridas. Su sha256 actual, `5409bbe9…`, coincide con el de C-246.
- **Rangos.** 15 rangos (1x5x3) en todos los brazos.
- **Configs (diff).** Cada par difiere solo en lo declarado:
  - E/C: solo `pc_outlet_total_pressure`.
  - F/A: solo `pc_transport_f28`.
  - F/k10b: solo `pc_outlet_total_pressure`.
  - A/k10b: las dos claves.
  - B y D frente a k10b: solo `restart_file` y `t_final`.
  - C frente a k10b: `restart_file` y la clave outlet.
- **Ventana.** Es la misma en todos: pasos 2-10 tras el reinicio para decidir y filas con step > P0+1 (235) para la lectura.
- **Determinismo.** Los gemelos coinciden en los pasos 0-10: F/k10b a 1.1e-9 y E/C a 7.9e-9. Esto confirma que solo cambia la clave probada.

## Veredictos frente al criterio literal

| Predicción | Criterio | Medido (recalculado) | Veredicto del reporte | ok |
|---|---|---|---|---|
| H15 C-238 | SOPORTADA si A sin pico y B con pico | A 69.4 m/s / 15 kPa; B 300.0 m/s / 342 kPa; 0 AVISO | SOPORTADA | ok |
| H16 C-244 | SOPORTADA si C sin pico | C 51.2 m/s / 117 kPa; 0 AVISO | SOPORTADA | ok |
| H17 C-246 | REFUTADA si E sin pico | E 51.2 m/s / 117 kPa; 0 AVISO | REFUTADA | ok |
| H18 C-247 | REFUTADA si F con pico | F 300.0 m/s / 461 kPa; 0 AVISO | REFUTADA | ok |
| H12 C-224 | REFUTADA si u = 300 en 280002-280010 | 300.0 en 280003; 0 AVISO | REFUTADA | ok |
| H13 C-226 | SOPORTADA si u < 200 y p < 300 | 71.6 m/s / 79 kPa; 0 AVISO | SOPORTADA | ok |

No hay enmiendas. El reporte no reinterpreta ningún criterio; distingue «por la letra» del alcance (C-240, C-236).

## Tabla de cifras

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| k10b_dt025 280002/3/4 u, p | 198.6/281, 300.0/461, 200.8/199 | 198.6/281.1, 300.0/460.8, 200.8/199.1 | ok |
| FAIL k10b_dt025 | sentinel_gas, regime_p, regime_gas | igual | ok |
| regime_p 591.6 kPa en 280161 (u 113.2) | sí | 591.59 kPa, 113.23 m/s | ok |
| comp_carry | 0 | 0.0 | ok |
| \|Δρ/ρ\| EOS, celdas | ≤ 4.4e-16, 68232 | 4.44e-16, 68232 | ok |
| Tg_end max / p99 | 17.7 % / 0.2 % | 17.69 % / 0.217 % | ok |
| gas_eos en mod_constants.f90:594-599 | sí | 594-599 | ok |
| tgfix: serie 280001-280005 «a 3 cifras» | igual | p_max 280001: 69.37 frente a 69.06 kPa | objeción O2 |
| eosend kg/s 1/0.5/0.25 ms | 2.922, 2.882, 2.865 | 2.9221, 2.8824, 2.8650 | ok |
| Fechas 2f0529b / 8f568fc / run.log otp | 10:13:58 / 02:56:49 / 02:57:32 | igual | ok |
| Pico 1 ms y 0.5 ms | 99.6 kPa (280003), 163.5 m/s (280002), 191.4 kPa | igual | ok |
| Tabla a 1 ms (scrfh_base, scrfh_b, m203/m21f1, otp/k10_base) | 71.9/14.8, 71.7/14.8; 160.0/65.3, 189.8/62.0; 126.5/50.3, 215.0/83.5 | igual | ok |
| m203/m21f1 frente a otp, 280001-280011 | < 5e-6 | 4.83e-6 | ok |
| scrfh_b solo difiere en f28; run.log = bin cand_f28 21:29:42 | sí | igual | ok |
| [CG] AVISO en los 4 bancos de 1 ms | sí | 8, 8, 8, 328 | ok |
| H15 A: 2-10 / ventana / cuartos | 69.4/15; 15; 0,0,0,0 | igual | ok |
| H15 B: 2-10 / ventana / cuartos / FAIL | 300.0/342; 365 (290020); 58,59,59,59; sentinel_gas, regime_gas | igual | ok |
| Cuartos k10b_dt025 (h15 y 58/58/58/61) | 31,21,32,36 (120/235) | igual | ok |
| nolink k10b_dt025 | 105/235; tramos 280002-023, 135-141, 161-236; 2 en 280002, máx. 6; 71 de 120 | igual | ok |
| nolink B | 235/235, 4-9, hasta 290236; 235 de 235 | igual | ok |
| nolink A, s290, dt05, mo20, C, D, E | 0 | 0 en todos | ok |
| nolink F | 105, mismos pasos que k10b | 105, conjunto idéntico | ok |
| Asentado 1 ms: otp p/u, mo20 p/u | 24/17, 31/13 | 280024/280017, 280031/280013 | ok |
| Ciclo de 2 pasos | 23/43, 28/49 kPa | 23.2/43.3, 27.6/49.0 | ok |
| H16 C: 2-10 / ventana / cuartos | 51.2/117; 117 (280004); 1,0,0,0 | igual | ok |
| H16 D | 77.0/56; 56 (300002); 0,0,0,0 | igual | ok |
| C: 28.0 → 116.5; pares 99.2, 90.7, 86.5 | sí | igual | ok |
| D: alterna entre ~30 y 54 | sí | 29.7-30.0 / 51.3-56.0 | ok |
| H17 E | 51.2/117; 117 (280004); 1,0,0,0; 0/235 | igual (u ventana 86.2) | ok |
| H18 F | 300.0/461; 592 (280161); 31,21,32,36; 105/235; FAIL ×3 | igual | ok |
| pares: E/C u, p (0-10) | ≤ 7.9e-9, ≤ 1.5e-9 | 7.9e-9, 1.5e-9 | ok |
| pares: F/k10b u, p (0-10) | ≤ 1.1e-9, ≤ 3.5e-10 | 1.1e-9, 3.5e-10 | ok |
| m_gas (0-10) | ~2.5e-7 | 2.6e-7 (E/C), 2.5e-7 (F/k10b) | ok |
| u_gas E frente a C en la ventana | hasta 12 % | 1.2e-1 | ok |
| Líneas citadas mod_pressure_3d.f90:1001-1010, 2000-2012; mod_audit.f90:1318-1335 | sí | el contenido corresponde | ok |
| Resultado s290: 71.6, 79, 450.0 (290093; 128.6), 344.3 (290074), 5/235, regime_p 4.500e5 PASS | sí | igual | ok |
| Resultado dt05_s290: 80.1, 71, 70.6 (290004; 80.1), 0/117 | sí | igual | ok |
| Resultado mo20_s290: 124, 55, 70.0 (290011; 121.5), 0/58 | sí | igual | ok |
| u > 200 en 280007/011/041/137 | 229.1, 282.8, 252.8, 229.4 | igual | ok |
| dt05: cuartos | 8,1,2,0 (29,29,29,30) | igual | ok |
| k11_base_s290: u, p, FAIL, AVISO | 107, 27, energy_balance, 1 (res 4.198e-2) | 106.9, 27.1, igual, igual | ok |
| k10_base / base_s290 frente a otp | 2.2e-12, 5.2e-13 | 2.22e-12, 5.21e-13 | ok |
| Snapshots de 280 s otp/fh: datasets distintos | 8 de 56, S_arc hasta 3.1e8 | 8 de 56, S_arc 3.14e8 | ok |
| \|Δα_s\|, \|Δα_g\|; rango de p fh / jb | 0.77, 0.64; −0.09..14.8 / −12.8..28.0 kPa | 0.772, 0.644; −0.090..14.79 / −12.77..28.05 | ok |
| Tabla de jueces por segundo (15 filas × 3) y fila 275-280 | sí | idéntica fila a fila; 30.3/7.2, 16.8/0.7 | ok |
| otp 280.0-280.1 s (cada 5 / todas) y \|Δp\| 290.0-290.1 | 38.1/21.9, 38.3/18.4, 3.7 | igual | ok |
| otp 289998-290009 | 106.9/90.5 m/s; 23.5/27.0 kPa | 106.8/90.5; 23.6/27.0 | ok |
| Última fila de otp | 345.5 s | 345.528 s | ok |
| filmhyst_opt 13:23:42, 38 s antes; fh 13:24-16:38; jb 21-oct 10:27 | sí | igual | ok |
| fh auditado cada 5 pasos | sí | 279995, 280000, 280005… | ok |
| Paradas de B1 (C-001) | 284.3, 294.1, 342.5 | presentes en C-001 | ok |
| Contraste C, D, E, s290 | «tres linajes» | dos escritores (jb, otp), tres snapshots | objeción O1 |

## Objeciones

1. **O1 (no bloqueante).** Afecta a `report.md`, sección Incertidumbre:
   - **Recuento:** el reporte dice «tres linajes». Recalculado: los restart_file de C y E son `judge_jb_275/eaf3d_00280000.h5`, y los de D y s290 son `judge_otp_280/eaf3d_00300000.h5` y `…00290000.h5`. Son dos escritores y tres snapshots.
   - **Contradicción:** la frase «no hay un estado de linaje fh con f28 ya establecida» choca con que los snapshots de 290 s y 300 s de otp descienden del estado fh de 280 s con f28 encendida 10 y 20 s.
   - **Inferencia sin medida:** «poco probable que el estado por sí solo explique…» es una inferencia en prosa.
   - **Para levantarla:** corregir el recuento, tratar los snapshots de otp (o justificar su exclusión) y marcar la frase como lectura.
2. **O2 (no bloqueante).** Afecta a `report.md`, paso 4. En el paso 280001, p_max de `campaigns/b1/k11_dt025_tgfix/audit.csv` es 69373 Pa y el de `campaigns/b1/k10b_dt025/audit.csv` es 69064 Pa (0.45 %). Por tanto «280001-280005 a 3 cifras» es falso para ese paso; sí se cumple en 280002-280005. No altera el veredicto de H12.
   - **Para levantarla:** acotar la frase a 280002-280005, o mencionar la diferencia del paso 1.

## Notas sin objeción

Los veredictos se apoyan en una trayectoria por brazo y en ventanas de 60 ms. El reporte lo declara (Incertidumbre, C-237). La conclusión «encender f28 sobre un estado escrito sin ella» está definida operativamente y su confusión con el estado fh está declarada.

VEREDICTO: aprueba