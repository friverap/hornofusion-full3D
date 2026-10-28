## Revisión de evidencia: WS-K11, ronda 1

**Veredicto: aprueba.** Los veredictos de las 11 predicciones respetan su criterio pre-registrado, y cada pre-registro es anterior al arranque de sus brazos. Las cifras se reproducen desde los datos dentro del redondeo mostrado, salvo un detalle de paso/tiempo (O1). Quedan siete objeciones no bloqueantes.

Todo se hizo en solo lectura: los scripts del WS (h15, h17, h19, h22, medir_centinela, duracion, pares), `check_audit.py` (sin escrituras), lecturas propias con csv/h5py, `git log/show` y `stat`. No se ejecutó `snap_tgfix.py`, que escribe. No leí las revisiones de los otros revisores.

### 1. Veredictos frente a su criterio

| Pred. | Criterio (registro) | Medido | Veredicto reporte | ok |
|---|---|---|---|---|
| H12 C-224 | refuta si u = 300 en 280002-010 | 300.0 m/s (280003), 0 AVISO | REFUTADA | ok |
| H13 C-226 | sopor. si u < 200 y p < 300 en 290002-010 | 71.6 m/s / 78.7 kPa, 0 AVISO | SOPORTADA | ok |
| H15 C-238 | A sin pico y B con pico | A 69.4/15; B 300.0/342 | SOPORTADA | ok |
| H16 C-244 | C sin pico | 51.2/117 | SOPORTADA | ok |
| H17 C-246 | E con pico | 51.2/117 (sin pico) | REFUTADA | ok |
| H18 C-247 | F sin pico | 300.0/461 (pico) | REFUTADA | ok |
| H19 C-252 | G con pico en 280238-246 | 216.3/361 | SOPORTADA | ok |
| H20 C-253 | I, J con pico; K, L sin pico | L 300.0 (pico) | REFUTADA | ok |
| H21 C-254 | H sin pico | 69.4/15 | SOPORTADA | ok |
| H22 C-263 | M, N, O sin firma | 0 nolink y 0 pasos ≥ 100 kPa | SOPORTADA | ok |
| H23 C-264 | P con firma y Q sin ella | P sin firma | REFUTADA | ok |

Comprobaciones de procedimiento:
- **Orden temporal:** commit de pre-registro → arranque del run.log. 096b1ba 23:44:28 → tgfix 23:44:32; d4c07b7 23:49:56 → s290 23:51:11; 424a70d 01:20:50 → A 01:20:55; aa93539 01:44:37 → C 01:44:42; 650d712 09:24:52 → E 09:24:57; 2c03398 09:52:00 → G 09:52:06; 8b2d95b 10:42:49 → M 10:42:55.
- **Enmiendas:** ninguna para WS-K11.
- **Binario y ranks:** `campaigns/bin/eaf3d_k10b_opt` (sha256 5409bbe9…, el del criterio) y 15 ranks constan en el run.log de todos los brazos.
- **Configs:** cada brazo difiere de su referencia solo en la clave probada, restart_file y t_final. N/B difiere en dos claves, y el reporte lo declara.

### 2. Cifras del reporte

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| k10b_dt025, 280002-004 | 198.6/281, 300.0/461, 200.8/199 | igual | ok |
| comp_carry 280 s | 0 | 0.0 | ok |
| \|Δρ/ρ\| EOS, celdas | ≤ 4.4e-16, 68232 | 4.44e-16, 68232 | ok |
| Tg_end máx / p99 | 17.7 % / 0.2 % | 17.69 % / 0.217 % | ok |
| H12, paso 280001 | 0.45 % (69.37/69.06) | 0.448 % | ok (O2) |
| H12, pasos 280002-005 | ≤ 3.4e-4 | 3.44e-4 | ok |
| EOS-end kg/s | 2.922 / 2.882 / 2.865 | 2.9221 / 2.8824 / 2.8650 | ok |
| Pico a 1 ms / 0.5 ms | 99.6 kPa, 163.5 m/s / 191.4 kPa | 99.63, 163.47 / 191.41 | ok |
| Tabla a 1 ms (scrfh, m203, otp) | 71.9/14.8 … 215.0/83.5 | igual | ok |
| m203 frente a otp, 280001-011 | < 5e-6 | 4.8e-6 | ok |
| Pasos ≥ 100 kPa por cuartos, k10b | 31, 21, 32, 36 | igual (con los dos cortes) | ok |
| Tramos nolink, k10b | 280002-023, 135-141, 161-236; máx. 6 | igual | ok |
| nolink frente a p ≥ 100 kPa | 105/71/120; B 235/235 | igual | ok |
| Asentamiento a 1 ms | 24/17; 31/13; 23/43, 28/49 kPa | 24/17; 31/13; 23.2/43.3, 27.6/49.0 | ok |
| Tablas de C, D, E, F, G, H, I, J, K, L | h15, h17, h19 | igual | ok |
| Umbral 1 (u ≥ 200 o p ≥ 300 kPa) | G 11, F 8, B 18, I 101, J 187, L 3, s290 2 | igual | ok |
| Umbral 2 (u ≥ 299 o p ≥ 300 kPa) | G 7, F 6, B 9, I 73, J 120, L 2, s290 2 | igual | ok |
| Tabla de 14 brazos (nolink, p < 100, máx. sin nolink) | 34 / 380, 8 / 91, 1 / 634, 2 / 2000 | igual | ok |
| M, N, O, P, Q | 15/18/20/96/95 kPa; 92.3/68.9/61.2/130.0/89.9 m/s | igual | ok |
| Medias por cuartos (B, k10b, C, s290, D, A, P) | 244.3 … 14.4; P 43.8 → 26.4 | igual | ok |
| Tabla de Resultado (s290, dt05, mo20, k10b) | 450.0 (290093; 128.6) … 591.6 (280161; 113.2) | igual | ok |
| Tabla por segundos de los 3 jueces | 34.1/18.9 … 17.0/0.9 | igual, todas las celdas | ok |
| Filas de nivel centinela, 280-295 s | fh 15, jb 1, otp 26 | igual | ok |
| k7v4_long nolink | 146 pasos, 284.669-285.380 s, 360 celdas | 146, pasos 284669-285379 = t 284.670-285.380 s, 360 | **O1** |
| k7v4_long, ventana de 60 pasos | 59 / 45 / 30 / 153 kPa | 59 / 45 / 30 / 152.7 | ok |
| Bancos de C-270 | 215.0 ×6, 189.8, 136.7; 0-1 y 9; 42 filas, 2.63 % | igual | ok |
| M20-2 | 156 frente a 94; 4 de 5; 66.1 frente a 51.3; 1 frente a 0 | igual | ok |
| comp_carry, Tg_end p99 | 0…1.46e-9 (2), 2.26e-5 (1), 8.06e-5 (16); 0.20-0.23 % | igual | ok |
| Σ liq_cont_prev | 1708-1755 | 1707-1755 (fh y A), rampbelow 1620 | **O3** |
| Divergencia fh/jb y fh/e2 | 0.77 / 0.64; −0.09…14.8 y −12.8…28.0 kPa; 0.34 / 2.2 kPa | igual | ok |
| fh 280 frente a otp 280 | 8 de 56 datasets, S_arc 3.1e8 | igual | ok |
| Reinicio desde rampbelow 255 s | 50.2/53.8/52.8; 14.6/14.6/18.5 | igual | ok |
| k10_base y k11_base_s290 frente a otp | 2.2e-12 / 5.2e-13; 107 m/s y 27 kPa; 1 AVISO | igual | ok |
| FAIL de check_audit y [CG] AVISO (23 bancos) | según tablas | igual | ok |
| Fechas (commits, run.log, binarios) | 43 s; 21:29:42; 13:23:42; 10:27 | igual | ok |

### 3. Objeciones (ninguna bloqueante)

- **O1.** k7v4_long: en `campaigns/b1/k7v4_long/audit.csv` el paso 284669 tiene t = 284.670 s. El reporte y la regla staged dan 284.669 s (paso tomado como tiempo). {C-269} da el paso «284341» para lo que es el paso 284340 (t = 284.341 s).
- **O2.** La cifra de H12 en 280001 (0.45 %) contradice el «idéntica a 3 cifras» de {C-225}, y ningún evento lo corrige. Hace falta un evento `--ref C-225`.
- **O3.** Σ liq_cont_prev: falta el comando, y el rango citado omite a A (1707) y a rampbelow (1620).
- **O4.** Sin id ni comando: la oscilación de judge_otp_280 en 289998-290009 y la subida de judge_fh_275 de 56 a 112 m/s en 299.9-300 s. Las cifras son correctas.
- **O5.** No verificable: el binario de k7v4_long; el run.log no lo registra.
- **O6.** I-O se corrieron con t_final +0.061 s frente a los +0.06 s pre-registrados, sin enmienda. Está declarado y no altera ningún veredicto.
- **O7.** Tres frases imprecisas. H no es un control con «las claves apagadas» (lleva la presión total encendida). Los «19 brazos» omiten a k11_dt025_tgfix (con cambio de f28 y firma: 22 nolink, 103 pasos ≥ 100 kPa), lo que no rompe la implicación. Las «1599 filas» no valen para judge_otp_280, que tiene 65527.

### 4. Equidad y alcance

- Los pares de una clave (A/F, C/E, A/H, M/I, O/J) comparten snapshot, binario, ranks, ventana y config salvo la clave.
- G no tiene control sin cambio, y en 290 s la comparación es de dos claves. El reporte declara las dos cosas.
- Una trayectoria por brazo, 60-61 ms y todos los estados con cambio de un solo linaje (judge_fh_275). El titular se limita a «en los estados probados, en los primeros 60 ms con 0.25 ms», y la hipótesis de la edad del cambio figura como no probada. El alcance que se reclama coincide con la muestra.

VEREDICTO: aprueba
