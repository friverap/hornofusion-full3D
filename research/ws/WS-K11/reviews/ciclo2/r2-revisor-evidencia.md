# WS-K11, ronda 1: revisión de evidencia

Revisión ciega: no leí `research/ws/WS-K11/reviews/`. Todo fue de solo lectura: los scripts del WS (`h15.py`, `h17.py`, `h19.py`, `duracion.py`, `pares.py`, `medir_centinela.py`, que comprobé que no escriben), `tests/integration/check_audit.py` (sin escrituras), `python3` con csv/h5py, `git log/show`, `stat`, `diff` y `ledger.py show/check` (`ledger OK, 258 eventos`).

## 1. Tabla de verificación

| Afirmación (línea) | Reporte | Recalculado | Estado |
|---|---|---|---|
| k10b_dt025 en 280002-280004 (95-99) | 198.6/281, 300.0/461, 200.8/199 | 198.6/281.1, 300.0/460.8, 200.8/199.1 | ok |
| FAIL de k10b_dt025; regime_p en 280161 (101-103) | sentinel_gas, regime_p 591.6 kPa, regime_gas; 0 AVISO | igual; 5.916e5 en 280161; 0 | ok |
| comp_carry (106) | 0 | 0.0 | ok |
| \|Δρ/ρ\|; celdas; Tg_end (110-113) | ≤ 4.4e-16; 68232; 17.7 %, p99 0.2 % | 4.44e-16; 68232; 0.1769; 0.00217 | ok |
| H12 tgfix (120-122) | igual a 3 cifras, centinela en 280003; REFUTADA | 300.0/461 en 280003, serie 1-5 idéntica; criterio «u alcanza 300» → REFUTADA | ok |
| EOS final por unidad de tiempo (126) | 2.922 / 2.882 / 2.865 kg/s | 2.9221 / 2.8824 / 2.8650 | ok |
| diff de configs fh/otp; fechas 2f0529b, 8f568fc; run.log otp (130-135) | f28 + outlet; 10:13:58, 02:56:49; 02:57:32 | idénticos | ok |
| Pico por dt (136-138) | 99.6 kPa (280003), 163.5 m/s (280002); 191.4; 461/300 | 99.63 kPa; 163.5; 191.41; 460.8/300.0 | ok |
| Tabla a 1 ms (144-149) | 71.9/14.8 … 215.0/83.5 | idéntica | ok |
| m203/m21f1 frente a otp (157-159) | < 5e-6 | 4.83e-6 | ok |
| scrfh_b: diff solo f28; run.log y binario 21:29:42; posterior a 3c4bf52 | — | diff solo f28; ambos 21:29:42; 3c4bf52 a las 21:06:08 | ok |
| CG AVISO en scrfh_base, scrfh_b, m203, otp (160) | hay | 8, 8, 8, 328 | ok |
| H15 A/B (190-191) | A 69.4/15, 0,0,0,0; B 300.0/342, 365 (290020), 58/59/59/59 | idéntico; FAIL B: sentinel_gas, regime_gas; 0 AVISO | ok; SOPORTADA según el criterio de C-238 |
| Cuartos de k10b_dt025 (210, 389-390) | 31, 21, 32, 36 (120/235); también con 58/58/58/61 | idéntico en las dos particiones | ok |
| Tabla nolink (221-230) | 105/235 (71 de 120); B 235/235 (4-9); resto 0 | idéntico; tramos 280002-023, 135-141, 161-236; mínimo 1 y máximo 6; F en los mismos pasos | ok |
| Asentamiento a 1 ms (245-248) | otp p 24, u 17; mo20 p 31, u 13; 23/43 y 28/49 kPa | 280024/280017; 280031/280013; 23.2/43.3; 27.6/49.0 | ok |
| H16 C/D (262-263) | C 51.2/117, 117 (280004), 1,0,0,0; D 77.0/56, 0 | idéntico; 0 AVISO, sin FAIL | ok; SOPORTADA según C-244 |
| Serie de C (271-273) | 28.0 → 116.5; 99.2, 90.7, 86.5; ~87/~75 | idéntico; pares 83-87 (media 85.0), impares ~73 | ok (redondeo «~») |
| D alterna 30/54 kPa (278-279) | desde el paso 2 | 30/51-56 al inicio, 23/31 al final | objeción O5 |
| H17/H18 E/F (301-302) | E 51.2/117, 1,0,0,0, 0 nolink; F 300.0/461, 592 (280161), 31/21/32/36, 105 | idéntico; FAIL F: sentinel_gas, regime_p, regime_gas; 0 AVISO | ok; las dos REFUTADAS según C-246 y C-247 |
| pares.py (310-317) | ≤ 7.9e-9 / 1.5e-9; ≤ 1.1e-9 / 3.5e-10; m_gas ~2.5e-7; u hasta 12 % | 7.9e-9 / 1.5e-9; 1.1e-9 / 3.5e-10; 2.6e-7 / 2.5e-7; 1.2e-1 | ok |
| Tabla H19-H21 (342-347) | G 216.3/361, 895 (280263), 27,0,0,0, 35, 9/7, 27; H 69.4/15; I 300/2000 (285009), 59/6/22/55, 57, 99/55, 232; J 300/997, 2000 (295114), 57/49/60/53, 72, 187/74, 226; K 155.3/128, 5,0,0,0; L 300.0/237, 1,0,0,0, 3/0, 4 | idéntico (h19.py y duracion.py); FAIL idénticos; 0 AVISO en los seis | ok |
| Veredictos H19, H20, H21 (351-353) | SOPORTADA, REFUTADA (por L), SOPORTADA | coinciden literalmente con C-252, C-253 y C-254 | ok |
| L: 300.0, 299.8, 245.3 y después ≤ 113 (359-360) | — | 300.0, 299.8, 245.3; 113.3 | ok |
| L «toca 300 m/s durante 3 pasos» / «300 m/s en 295002-295004» (16, 45, 583) | 3 pasos a 300 | 1 paso en 300.0, 2 en ≥ 299, 3 en ≥ 200 | objeción O2 |
| jb a 1 ms en 295 s (360-361) | ~160/110 m/s, 44/22 kPa | 166-134 / 107-117 m/s; 43-46 / 21-24 kPa | ok |
| p_max de 0.37-2 MPa con cambio de f28 (11, 364) | 0.37-2 MPa {C-256} | B 365, F 592, G 895, I y J 2000 kPa (correcto); C-256 dice 0.9-2 MPa | objeción O3 |
| Tabla de Resultado (377-380) | s290 71.6/79, 450.0 (290093; 128.6), 344.3 (290074), 5/235, regime_p 4.500e5 PASS; dt05 80.1/71, 70.6 (290004), 0/117; mo20 124/55, 70.0 (290011; 121.5), 0/58; k10b 591.6 (280161; 113.2), 120/235 | idéntico | ok |
| u > 200 m/s en k10b (390-392); 0.5 ms 8,1,2,0 de 29,29,29,30 | — | 280007 229.1, 280011 282.8, 280041 252.8, 280137 229.4; [8,1,2,0], [29,29,29,30] | ok |
| Medias por cuartos y paso 0 (402-407) | B 244.3…137.6 / 34.2…24.3, 15.6; k10b; C; s290; D; A | idénticos; F = k10b salvo 106.7 frente a 106.8; E = C | ok |
| Tabla por segundos de los jueces (483-498) | 16 filas × 3 | idéntica | ok |
| 38.3/18.4 frente a 38.1/21.9; 3.7 kPa en 290.0-290.1 | — | 38.3/18.4; 38.1/21.9; 24.5/3.7 | ok |
| Filas de nivel centinela 280-295 s (514-519) | fh 15, jb 1 (288.68), otp 26; fh 300 m/s en 281.47-281.50, 304/578 kPa en 284.37/284.39 | idéntico | ok |
| Bancos afectados (443-455) | lista K5-K10 + judge_e1w280_n14/n15, diag_g284a | `grep restart_file`: los mismos, todos con las dos claves y primera fila 280000 (60/119/300/1000/4330/5500 filas) | ok |
| k11_base_s290 (462-466) | 107 m/s, 27 kPa, FAIL energy_balance, 1 AVISO con res 4.198e-2 | 106.9; 27.07; FAIL solo energy_balance; 1; 4.198E-02 | ok |
| Estados fh/jb en 275 s idénticos; configs difieren solo en f28; mismo restart (559-562) | Δ = 0 | Δ = 0 en α, p, T_gas y /restart (17 datasets); diff solo f28; los dos desde judge_rampbelow | ok |
| Divergencia en 280 s (563-564) | Δα_s 0.77, Δα_g 0.64; p −0.09…14.8 / −12.8…28.0 kPa | 0.772, 0.644; −90 Pa…14.79 kPa / −12.77…28.05 kPa | ok |
| 8 de 56 datasets distintos; S_arc hasta 3.1e8 (612-615) | — | 8/56, los mismos 8; S_arc 3.14e8 | ok |
| El binario que lee no influye (619-621) | 2.2e-12; 5.2e-13 | 2.22e-12; 5.21e-13 | ok |
| Oscilación de mo20_s290 y otp (641-643) | ~122/~77; 106.9/90.5, 23.5/27.0 | 122-124/76-80; 106.9/90.5, 23.5/27.0 | ok |
| Paradas de B1; última fila de otp (648-649) | 284.3, 294.1, 342.5 (C-001); 345.5 s | C-001 coincide; 345.528 s | ok |
| Referencias de código | mod_constants 594-599, mod_multiphase 473-477, mod_pressure_3d 598-601 / 1001-1010 / 2000-2012, mod_audit 1318-1335, mod_config_3d:110 | contenido coincide con lo descrito | ok |

## 2. Equidad de la comparación y pre-registro

- **Pre-registro.** Cada predicción está en su commit antes de arrancar su corrida: 096b1ba 23:44:28 → tgfix 23:44:32; d4c07b7 23:49:56 → s290/mo20 23:50-23:51; 424a70d 01:20:50 → A 01:20:55; aa93539 01:44:37 → C 01:44:42; 650d712 09:24:52 → E 09:24:57; 2c03398 09:52:00 → G 09:52:06. No hay enmiendas.
- **Mismo código y misma ventana.** Todos los brazos registran en su run.log `campaigns/bin/eaf3d_k10b_opt` y 15 ranks. El binario actual (sha256 5409bbe9…, mtime 27-oct 22:37) es anterior a todas las corridas; el log guarda la ruta, no el hash. Los `diff` de config confirman que cada par solo difiere en la clave declarada: A/k10b las dos claves; E/C solo outlet; F/A solo f28; F/k10b solo outlet; H/A solo outlet; G/A f28 + restart + t_final; I, J/F y K, L/C solo restart y t_final. Todos usan 0.06 s (235 o 239 filas).
- **Reinicio frente a continuación.** k11_base_s290 reproduce la continuación de judge_otp_280 a 5.2e-13 en 290001-290005, así que G no necesita un control propio para descartar un artefacto del reinicio.
- **Muestra.** Una trayectoria por brazo y ventanas de 60 ms. El reporte lo declara, y también que H16 descansa en 117 kPa, el 39 % del umbral. Es suficiente para los veredictos por la letra, no para la generalidad del titular (O1).

## 3. Objeciones

1. **O1 (bloqueante).** `report.md:9-14` y `:579-582`. «Sin cambio de f28 no aparece ese régimen» en cinco estados es lo que probaba H20 (C-253), y H20 está REFUTADA (C-256). El separador «u 300 m/s + p 0.37-2 MPa + nolink» es posterior a L y el titular no lo marca como no pre-registrado. Con la propia métrica de nivel centinela (`report.md:514`), los brazos sin cambio también tienen eventos: `campaigns/b1/k11_dt025_s290/audit.csv:290093 = 450.0 kPa` (dentro de 0.37-2 MPa) y 290074 = 344 kPa; `campaigns/b1/k11_l_dt025_jb295/audit.csv:295002-295003 = 300.0/299.8 m/s`. F tiene 6 eventos. Lo único que separa es nolink > 0 (0 frente a 35-235 pasos). **Para levantarla:** marcarlo como lectura no pre-registrada en el titular, el Resultado y la Incertidumbre; definir el régimen por nolink; y, si se quiere como resultado, pre-registrar una predicción nueva con ese criterio en estados nuevos.
2. **O2.** `report.md:16, 45, 583`, «300 m/s durante 3 pasos». Los datos dan `k11_l_dt025_jb295/audit.csv:295002-295004 = 300.0, 299.8, 245.3 m/s`: 3 pasos ≥ 200 m/s y solo 1 en U_GAS_MAX. **Para levantarla:** corregir la redacción.
3. **O3.** `report.md:364`, «0.37-2 MPa» citando {C-256}, que dice «0.9-2 MPa» (falso para B, 365 kPa, y F, 592 kPa). **Para levantarla:** evento de corrección `--ref C-256`.
4. **O4.** «Nivel centinela» se usa con u ≥ 200 (`duracion.py`, `report.md:362`) y con u ≥ 299 (`report.md:514`). Con la segunda, B dura 33 pasos y no 86, y s290 y L tienen 2 eventos cada uno. **Para levantarla:** unificar o nombrar los dos umbrales.
5. **O5.** `report.md:278-279`, D «alterna 30/54 kPa». Eso vale solo al inicio; `k11_d_dt025_s300/audit.csv` da 23/31 kPa al final. **Para levantarla:** precisarlo.

Fuera de O1-O5, todos los números del reporte que recalculé coinciden con los datos dentro del redondeo mostrado, y los siete veredictos (H12, H13, H15-H21) aplican literalmente su criterio pre-registrado. Rechazo por O1: el titular presenta como resultado la generalidad que la predicción pre-registrada H20 no sostuvo, con un criterio posterior y sin decirlo.

VEREDICTO: rechaza