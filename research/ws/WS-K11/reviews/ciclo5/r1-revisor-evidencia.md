# Revisión de evidencia: WS-K11, ronda 1

Revisión ciega: no leí `research/ws/WS-K11/reviews/`. Todo fue de solo lectura: `h22.py`, `h15.py`, `h17.py`, `h19.py`, `pares.py`, `duracion.py`, `nolink.py`, `medir_centinela.py`, `centinela.py`, `check_audit.py`, `python3` con csv/h5py, `git log/show`, `stat` y `ledger.py show/check`. `ledger.py check` sale OK (278 eventos).

## Predicción juzgada: C-264 (H23)

- **Criterio de C-264, literal:** SOPORTADA si P tiene la firma y Q no; REFUTADA en otro caso; FALLIDA si hay `[CG] AVISO`. La firma es nolink ≥ 1 Y ≥ 20 pasos con p_max ≥ 100 kPa, contando filas con step > P0+1.
- **`h22.py --todos` recalculado:**
  - P: nolink 0, 0 pasos ≥ 100 kPa, máximo 96 kPa, 130.0 m/s, AVISO 0. Sin firma.
  - Q: nolink 0, 0 pasos, 95 kPa, 89.9 m/s, AVISO 0. Sin firma.
  - Resultado: **H23: REFUTADA**. Coincide con C-266 y con el reporte.
- **H22 (C-263):** M, N y O dan 0/0, con 15, 18 y 20 kPa. **SOPORTADA**, como dice el reporte.
- **Pre-registro anterior a la corrida:**
  - Commit `8b2d95b`: 10:42:49.
  - run.log de M: 10:42:55; de P: 11:09:32; de Q: 11:15:45.
  - Lo mismo en todos los pre-registros: 096b1ba, d4c07b7, 424a70d, aa93539, 650d712 y 2c03398 son anteriores a sus brazos.
  - No hay enmienda de C-263 ni de C-264.
- **Comparación justa:**
  - `diff` F→P: solo cambian restart_file y t_final. `diff` C→Q: igual.
  - M/I, A/F y O/J difieren solo en f28. N/B difiere en dos claves, como el reporte declara.
  - P y Q: 15 ranks; arrancan en el paso 299999 de linajes con dt de 1 ms normal, sin paso truncado.
  - El binario no se puede verificar (E4).

## Tabla de verificación (muestra representativa; todo lo listado se recalculó)

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| 280002/3/4 u/p | 198.6/281, 300.0/461, 200.8/199 | igual | ok |
| FAIL k10b_dt025 | sentinel_gas, regime_p 591.6 kPa (280161), regime_gas | igual | ok |
| comp_carry 280 s | 0 | 0.0 | ok |
| \|Δρ/ρ\| EOS, celdas | 4.4e-16, 68232 | 4.44e-16, 68232 | ok |
| Tg_end máx / p99 | 17.7 % / 0.2 % | 17.69 % / 0.217 % | ok |
| H12 p 280001 | 69.37 frente a 69.06, 0.45 % | 69.373 / 69.064, 0.448 % | ok |
| H12 280002-5 | ≤ 3.4e-4 | 3.44e-4 | ok |
| EOS kg/s | 2.922, 2.882, 2.865 | 2.9221, 2.8824, 2.8650 | ok |
| 1 ms / 0.5 ms | 99.6 kPa, 163.5 m/s, 191.4 kPa | igual | ok |
| Tabla 1 ms (scrfh/m203/otp/k10_base) | 71.9/14.8 … 215.0/83.5 | igual | ok |
| m203/m21f1 frente a otp | < 5e-6 | 4.83e-6 | ok |
| Fechas 2f0529b, 8f568fc, run.log otp | 10:13:58, 02:56:49, 02:57:32 | igual | ok |
| H15 A/B | 69.4/15; 300.0/342; 365 (290020); 58,59,59,59 | igual | ok |
| Tabla nolink paso 9 (10 bancos) | 105/235 (71 de 120), 235/235, 0 … | igual; tramos 280002-023, 135-141, 161-236 | ok |
| Asentamiento 1 ms | p 24 / u 17 (otp); 31 / 13 (mo20); 23/43, 28/49 | igual | ok |
| H16 C/D | 51.2/117 (280004); 77.0/56; 99.2, 90.7, 86.5 | igual (máximo de u en la ventana 86.1, E6) | ok |
| H17/H18 pares | 7.9e-9, 1.5e-9, 1.1e-9, 3.5e-10, m_gas ~2.5e-7, 12 % | 7.9e-9, 1.5e-9, 1.1e-9, 3.5e-10, 2.5-2.6e-7, 0.12 | ok |
| Tabla H19-H21 (G-L) | 216.3/361, 895 (280263), 27,0,0,0 … L 3/0 en el paso 4 | igual (h19.py, duracion.py, FAIL) | ok |
| Umbral u ≥ 200 o p ≥ 300 | G 11, F 8, B 18, I 101, J 187; L 3, s290 2 | igual | ok |
| Nivel centinela B1 | G 7, F 6, B 9, I 73, J 120; L 2, s290 2 | igual | ok |
| Tabla de 14 brazos | nolink & p < 100: 34, 8, 0, 1, 2; máx. sin nolink 380, 91, 634, 2000 | igual | ok |
| L 295002-4 | 300.0, 299.8, 245.3; después ≤ 113 | igual (113.3) | ok |
| H22/H23 tabla M-Q | ver arriba | igual | ok |
| Ventana 239 filas, t_final | 285.061…300.06 | igual (242 líneas) | ok, pero E2 |
| tgfix | nolink 22,0,0,0; ≥ 100 kPa 31,27,26,19; 138.0…83.9; 73.7…17.8; 42-104 kPa; diverge en 280027; máx. 460.9 | igual | ok |
| k10b_dt025 últimas 20 filas | 104-156 kPa, nolink 1-4 | igual | ok |
| P primeros pasos, cuartos | 86/54; 43.8→26.4 | igual | ok |
| fh 299.9-300.0 u_gas | 56→112 | 55.7→112.2 | ok |
| Tabla Resultado (s290, dt05, mo20, k10b) | 450.0 (290093; 128.6), 344.3 (290074) … | igual | ok |
| u > 200 en k10b | 280007 229.1, 280011 282.8, 280041 252.8, 280137 229.4 | igual | ok |
| 0.5 ms por cuartos | 8,1,2,0 de 29,29,29,30 | igual | ok |
| Medias por cuartos (17 brazos) | B 244.3…137.6 … O 17.6…14.8 | igual | ok |
| Tabla de jueces por segundo (15+20+20 celdas) | 34.1/18.9 … 17.0/0.9 | igual | ok |
| Filas centinela 280-295 s | fh 15, jb 1 (288.68), otp 26; 304/578 kPa | igual | ok |
| e2 282-287 / jb 275-280 | 28 / 1 (277.506) | igual | ok |
| k7v4_long nolink | 146 pasos, 284669-285379, máx. 360, 12 tramos, 144/146 con 360 | igual (nolink.py) | ok |
| k7v4_long 60 pasos | 59, 45, 30, 153 kPa | 59, 45, 30, 152.7 | ok |
| k7v4_long primera centinela | 284340 (t 284.341), 300 m/s, sin nolink; 86/96 | igual | ok |
| k7v4_long 284341-284668 | 328 pasos, 35.9-85.3 kPa, 0 nolink | igual (7 con u ≥ 299) | ok |
| p ≥ 100 con nolink | 94/96, 27/27, 71/120, 56/142, 70/219 | igual | ok |
| CG sin converger k7v4_long | ≥ 27001 de ~27500 | 27001 acumulados; 5500 filas × 5 | ok |
| k7v4_long frente a otp | coincide en 280002, otra trayectoria antes de 281 s | idéntico hasta 280010; > 1 % desde 280118 | ok |
| Bancos de 1599 filas | 215.0 en seis, 189.8, 136.7; 0-1 y 9; 0.8-1.9 % | igual | ok |
| scrfh_base 42 filas, 2.63 % | 281.461-281.502 s | pasos 281461-281502; t 281.462-281.503 | **objeción E1** |
| M20-2 | 156/94; 4 de 5 en 280003-029, quinta en 280033; 66.1/51.3; 48.3-62.6; 287.7 | igual | ok |
| k11_base_s290 | 107 m/s, 27 kPa, 1 AVISO res 4.198e-2, FAIL energy_balance | igual | ok |
| 290-293 s y 290.0-290.1 | 24-28 / 3-7; 3.7 | 24.2-27.7 / 3.3-7.4; 3.7 | ok |
| Estados de 275 s fh/jb | idénticos | \|Δ\| = 0 en campos y /restart | ok |
| fh frente a jb a 280 s | Δα_s 0.77, Δα_g 0.64; p −0.09..14.8, −12.8..28.0 | igual | ok |
| e2 frente a fh a 280 s | 0.34, 2.2 kPa | 0.342, 2.23 kPa | ok |
| rampbelow 255 s | 50.2/53.8/52.8; 14.6/14.6/18.5; 50.6/14.4 | igual | ok |
| comp_carry (15 estados) | 0,0,0,1.5e-9(2),0; 2.26e-5(1); 8.1e-5(16); jb/otp/F/B … | igual | ok |
| Tg_end p99 / máximo | 0.20-0.23 %, 0.05 % A; 6.8-44.8 %, 44.5 % | igual | ok |
| Σ liq_cont_prev | 1620, 1707, 1708-1755 | igual | ok |
| Chatarra sumergida | 155-212; 43; jb 217, 130; otp 52 | igual; omite rampbelow = 316 | **objeción E3** |
| Datasets otp frente a fh a 280 s | 8 de 56; S_arc hasta 3.1e8 | 8 de 56; 3.14e8 | ok |
| Determinismo | 2.2e-12, 5.2e-13 | 2.22e-12, 5.21e-13 | ok |
| Alternancia otp 289998-290009 | 106.9/90.5; 23.5/27.0 | igual | ok |
| Fechas fh/jb/filmhyst | 13:24-16:38, 13:23:42, 14:02, 10:27 | igual | ok |
| Citas de código | mod_audit 1318-1335, pressure 1001-1027 y 2000-2012, config:110, acople-pv 566-568 | contenido coincide | ok |
| FAIL y `[CG] AVISO` de A-F, M-Q, s290 | según el reporte | igual | ok |

## Objeciones (ninguna bloqueante)

- **E1** `report.md:739`: «281.461-281.502 s» son pasos; el tiempo real es 281.462-281.503 s (la misma confusión que corrigió C-272).
- **E2** `report.md:551-558`: C-264 fija t_final 300.06 literal. P y Q no se desvían del pre-registro; solo M, N y O.
- **E3** `report.md:997-1005` (C-278): «un solo negativo» omite rampbelow 255 s, con 316 celdas sumergidas, negativo que sí se usa para comp_carry. Va contra la lectura de cofactor.
- **E4** No verificable: el binario `eaf3d_k10b_opt` no consta en ningún run.log. Solo se verifica por fechas (binario del 27-oct 22:37, anterior a todas las corridas) y 15 ranks.
- **E5** `report.md:1024-1027`: el descarte de los poros sobrellenados (refutador R4) no tiene {C-nnn}, ruta ni comando.
- **E6** `report.md:103-106`: «51 m/s … como máximo» es de los pasos 2-10; el máximo de la ventana es 86.1 m/s.

## Juicio

- **Veredictos:** C-264 (H23) REFUTADA y C-263 (H22) SOPORTADA se reproducen literalmente con el comando del criterio. No hay enmiendas ni reinterpretaciones en prosa.
- **Titular:** «necesario, no suficiente, en los estados probados, 0.25 ms y 60 ms» se sigue de los veredictos y de los 20 brazos recalculados. El alcance está bien declarado: un solo linaje, una trayectoria por brazo, un solo sentido del cambio, H22 de bajo riesgo y firma definida tras ver la muestra.
- **Lecturas posteriores al veredicto:** C-268 a C-278 están marcadas como no pre-registradas y sus números se reproducen.
- **Bloqueos:** ninguno. Las seis objeciones son de precisión y de procedencia.

VEREDICTO: aprueba