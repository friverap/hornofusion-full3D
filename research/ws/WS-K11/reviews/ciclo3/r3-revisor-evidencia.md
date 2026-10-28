## Revisión de evidencia: WS-K11, ronda 1 (revisor-evidencia)

**Veredicto: apruebo.** Recalculé desde los datos casi todas las cifras del reporte. Coinciden al redondeo mostrado, salvo cinco imprecisiones menores (O1, O2, O5, O6) que no cambian ninguna conclusión, y dos afirmaciones que no pude comprobar (O3, O4). Las seis objeciones son **no bloqueantes**. Cada veredicto de las nueve predicciones respeta la letra de su criterio pre-registrado.

Archivos revisados: `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K11/report.md`, `research/ledger.jsonl` (C-222..C-274), `campaigns/b1/*/audit.csv`, `config.dat`, `run.log` y los `.h5` citados.

**Cómo verifiqué (solo lectura):**
- Re-ejecuté los scripts del workstream: `h15.py` (A/B y C/D), `h17.py`, `h19.py`, `h22.py --todos`, `duracion.py`, `pares.py` y `medir_centinela.py`, además de `check_audit.py` en los 23 bancos y `ledger.py check` (OK, 274 eventos).
- Reproduje con python propio, sobre `audit.csv` y `.h5` existentes, todas las tablas y cifras sueltas.
- No corrí ningún binario ni `make`, y no escribí archivos fuera del scratchpad.

### 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| k10b_dt025, pasos 280002-280004 (u / p) | 198.6/281, 300.0/461, 200.8/199 | 198.6/281.1, 300.0/460.8, 200.8/199.1 | ok |
| máximo de regime_p de k10b_dt025 | 591.6 kPa en 280161 (113.2 m/s) | igual | ok |
| u_gas > 200 m/s en k10b_dt025 | 280007 229.1, 280011 282.8, 280041 252.8, 280137 229.4 | igual | ok |
| pasos ≥ 100 kPa por cuartos, k10b_dt025 | 31, 21, 32, 36 (120/235); 0.5 ms 8, 1, 2, 0 | igual, con los dos cortes de cuartos | ok |
| tramos nolink de k10b_dt025 | 280002-023, 280135-141, 280161-236; 2 celdas en 280002, máx 6; 71/120 | igual | ok |
| comp_carry del snapshot de 280 s | 0 | 0.0 | ok |
| \|Δρ/ρ\| frente a la EOS / salto de Tg_end | ≤ 4.4e-16 en 68232 celdas / 17.7 %, p99 0.2 % | 4.44e-16, 68232 / 17.69 %, p99 0.217 % | ok |
| H12 (tgfix frente a k10b_dt025) | 0.45 % en 280001; ≤ 3.4e-4 en 280002-280005; > 1 % desde 280027 | 0.448 %; 3.44e-4; 280027 | ok (ver O2) |
| masa reescrita por la EOS final, por unidad de tiempo | 2.922 / 2.882 / 2.865 kg/s | 2.9221 / 2.8824 / 2.8650 | ok |
| commits y logs | 2f0529b 21-oct 10:13:58; 8f568fc 22-oct 02:56:49; run.log de otp 02:57:32 | igual | ok |
| pico a 1 ms y 0.5 ms | 99.6 kPa (280003), 163.5 m/s (280002); 191.4 kPa | igual | ok |
| tabla a 1 ms (scrfh_base, scrfh_b, m203, otp) | 71.9/14.8 … 215.0/83.5; < 5e-6 | igual; 4.83e-6 | ok |
| reinicio frente a continuación | ≤ 2.2e-12 y 5.2e-13 | 2.22e-12 y 5.21e-13 | ok |
| H15: A / B | 69.4/15 / 300.0/342, 365 en 290020; 58, 59, 59, 59 | igual | ok |
| H16: C / D | 51.2/117 (280004) / 77.0/56 (300002) | igual | ok |
| serie de C | 28.0 → 116.5; 99.2, 90.7, 86.5; ~87/~75 | igual | ok |
| H17/H18, pasos 0-10 (rel.) | 7.9e-9 / 1.5e-9; 1.1e-9 / 3.5e-10; m_gas ~2.5e-7; E/C hasta 12 % | igual (2.6e-7 y 2.5e-7; 1.2e-1) | ok |
| H19-H21 (G, H, I, J, K, L) | tabla del paso 12 | `h19.py` y `duracion.py` dan lo mismo | ok |
| uniones de eventos | ≥ 200/300: G 11, F 8, B 18, I 101, J 187, L 3, s290 2; ≥ 299/300: 7, 6, 9, 73, 120, 2, 2 | igual | ok |
| cruce nolink/p | F 34 y 380 kPa; G 8 y 91; I 1 y 634; J 2 y 2000; B 0 | igual | ok |
| L, pasos 295002-295004 | 300.0, 299.8, 245.3; después ≤ 113 m/s | igual (113.3) | ok |
| H22/H23 (M, N, O, P, Q) | 15/18/20/96/95 kPa; 92.3/68.9/61.2/130.0/89.9 m/s; 0 nolink | igual | ok |
| ventanas reales | t_final +0.061 (M, N, O), 299999 → 300.06 (P, Q); 239 filas | igual | ok |
| tgfix por cuartos | nolink 22, 0, 0, 0; ≥ 100 kPa 31, 27, 26, 19; medias 138.0 … 83.9; \|Δp\| 73.7 … 17.8; últimas 20 filas 42-104 | igual | ok |
| tablas de medias por cuartos (B, k10b, C, s290, D, A, K, L, Q, H, M, N, O) | Resultado | igual en todas las celdas | ok |
| bancos de 290 s | s290 71.6/79/450 (290093, 128.6); dt05 80.1/71/70.6; mo20 124/55/70.0; 55/71/79 | igual | ok |
| asentamiento a 1 ms | otp 24/17, mo20 31/13; 23/43 y 28/49 kPa | igual | ok |
| tabla por segundos de los tres jueces (C-241/242) | las 16 filas | igual en todas | ok |
| filas de nivel centinela en 280-295 s | fh 15, jb 1 (288.68), otp 26 | igual | ok |
| e2 / jb | 28 filas en 282-287 s; 1 fila (277.506) | igual | ok |
| k7v4_long, nolink | 146 pasos, 284669-285379, máx 360; ninguno antes ni en 280001-031 | igual | ok |
| k7v4_long, 60 pasos desde 284669 | 59 / 45 / 30 / 153 kPa | 59 / 45 / 30 / 152.7 | ok |
| k7v4_long, filas de nivel centinela | primera en el paso 284340 (284.341 s); 86 de 96 con nolink | igual | ok |
| bancos desde fh 280 s | 215.0 en seis, 189.8 y 136.7; 0-1 frente a 9; scrfh_base 42 filas, 2.63 % | igual | ok |
| M20-2 | 156 frente a 94 (280003); 4 de 5 filas en 280003-029, la quinta en 280033; 66.1 frente a 51.3 y 1 frente a 0 | igual | ok |
| tiempos de las 42 filas de scrfh_base | 281.461-281.502 s | 281.462-281.503 s | objeción O1 |
| snapshots: estados de 275 s / 280 s | 275 s idénticos; \|Δα_s\| 0.77, \|Δα_g\| 0.64; p −0.09..14.8 y −12.8..28.0 kPa | igual | ok |
| e2 frente a fh en 280 s | 0.34 / 2.2 kPa | 0.342 / 2226 Pa | ok |
| archivos de 280 s de otp y fh | 8 de 56 datasets distintos; S_arc hasta 3.1e8 | igual | ok |
| comp_carry (15 estados) | lista de C-271/C-274 | igual | ok |
| Tg_end y Σliq_cont_prev | p99 0.20-0.23 %, máximo 6.8-44.8 %, Σ 1708-1755 | omite A (1707) y rampbelow (p99 0.555 %, Σ 1620) | objeción O5 |
| bancos de 255 s | 50.2/53.8/52.8 y 14.6/14.6/18.5 | igual | ok |
| k11_base_s290 | 107 m/s, 27 kPa, 1 AVISO (4.198e-2), FAIL energy_balance | igual | ok |
| FAIL y [CG] AVISO de los 23 bancos | según el reporte | igual; 0 AVISO en todos los k11_* salvo base_s290 | ok |
| binario de k7v4_long | eaf3d_k7v4_opt | su run.log no lo registra | objeción O3 |
| poros sobrellenados descartados por R4 | sin fuente | no verificable | objeción O4 |

### 2. Pre-registro y veredictos (comparados literalmente con el criterio)

- **Orden temporal.** Cada commit de pre-registro precede al arranque de sus corridas. Ejemplos: 8b2d95b a las 10:42:49 y el run.log de M a las 10:42:55; 2c03398 a las 09:52:00 y G a las 09:52:06. Lo mismo vale para H12-H18.
- **Veredictos.** H12 refutada, H13 soportada, H15 soportada, H16 soportada, H17 refutada, H18 refutada, H19 soportada, H20 refutada (por L), H21 soportada, H22 soportada y H23 refutada (P sin firma). Todos coinciden con la letra del criterio.
- **Ninguna enmienda ni reinterpretación.** La separación por «firma» posterior a C-256 está declarada como lectura NO pre-registrada.
- **Desviación de H22/H23.** El criterio dice t_final +0.06 y las configs usan +0.061. El reporte lo declara, y no altera el veredicto: M-Q dan 0 pasos con nolink y 0 con p ≥ 100 kPa en toda la ventana.
- **Comparaciones justas.** Comprobé con diff de config:
  - pares de una sola clave: A/F, M/I, O/J, A/H y C/E;
  - k10b_dt025/F difiere solo en la presión total y k10b_dt025/tgfix solo en el restart;
  - N/B cambia dos claves, como se declara;
  - todos los k11_* registran en su run.log `Ejecutable: campaigns/bin/eaf3d_k10b_opt` (sha256 5409bbe9…).
- **Muestra.** Son ventanas de 60-61 ms con una trayectoria por brazo, y H22 era de bajo riesgo. El reporte lo declara y limita el titular a «en los estados probados» y a los primeros 60 ms. No hay sobre-conclusión.

### 3. Objeciones (ninguna bloqueante)

1. **O1.** `report.md:705` da «281.461-281.502 s», que son pasos; los tiempos son 281.462-281.503 s (`campaigns/b1/scrfh_base/audit.csv`).
2. **O2.** `report.md:196-198` da 0.45 % en 280001, cifra correcta, pero cita {C-225}, que dice «idéntica a 3 cifras». Falta un evento que corrija C-225.
3. **O3.** El binario `eaf3d_k7v4_opt` de `k7v4_long` es una inferencia por fechas: el run.log no lo registra. La definición `lk_any` no cambia en git entre K7 y K10. Debe marcarse como «probable».
4. **O4.** `report.md:971-974`: el descarte de los poros sobrellenados por R4 no tiene id, ruta ni comando. Registrarlo o quitarlo.
5. **O5.** `report.md:950-952`: a los rangos de Tg_end y Σliq_cont_prev les faltan A 280.06 s (1707; p99 0.054 %) y rampbelow 255 s (1620; p99 0.555 %). La conclusión no cambia.
6. **O6.** Dos menores:
   - (a) «Ventanas de 1599 filas» se lee como si incluyera a judge_otp_280, que tiene 65527 filas.
   - (b) El tramo «285151-285168» son en realidad 285151-285166 y 285168.

Ninguna cambia un veredicto ni el titular. Se levantan con las correcciones de texto o de registro indicadas.

VEREDICTO: aprueba