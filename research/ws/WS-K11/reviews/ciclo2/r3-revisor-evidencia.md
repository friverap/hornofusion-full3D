# WS-K11, ronda 1: revisión de evidencia

Revisión ciega: no se leyó `research/ws/WS-K11/reviews/`. Solo lectura. Usé `ledger.py show|check`, `git show/log/diff --cached`, los scripts del WS de solo lectura (`h15.py`, `h17.py`, `h19.py`, `h22.py`, `pares.py`, `duracion.py`, `medir_centinela.py`; no ejecuté `snap_tgfix.py`, que escribe) y `check_audit.py`, comprobando antes que no escribe. El resto lo recalculé con mi propio python sobre `audit.csv` y los h5.

## Pre-registro y comparación justa

- C-263 (H22) y C-264 (H23) están en el commit `8b2d95b` (2026-10-28 10:42:49). Las corridas M a Q nacen después: el run.log de M es de 10:42:55 y el último audit.csv de Q termina a las 11:20:58. `h22.py` no cambió desde `8b2d95b`. No hay enmiendas. Los veredictos C-265 y C-266 son de las 11:21:34. `ledger.py check` da OK.
- Configs: M, N y O solo difieren de A en restart_file y t_final (+0.061 s; el criterio dice +0.06, sin efecto). P difiere de F y Q de C solo en restart_file y t_final. Los pares de una clave son M/I y O/J (solo f28). N/B difiere en dos claves (ver O3). Todos usan `campaigns/bin/eaf3d_k10b_opt` según el run.log. P y Q reinician de `eaf3d_00299999.h5`, el volcado final de t_final = 300.0, con los mismos 56 datasets y 17 de `/restart` que el de 295 s.
- Una trayectoria por brazo y ventanas de 235 a 239 pasos. El reporte lo declara. P no se queda corto de margen frente al umbral: 0 pasos ≥ 100 kPa contra 20 exigidos.

## Tabla

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| H22: firma de M/N/O (nolink; pasos ≥ 100 kPa; max p; max u) | 0;0;15;92.3 / 0;0;18;68.9 / 0;0;20;61.2 → SOPORTADA | idéntico, `h22.py` → SOPORTADA | ok |
| H23: firma de P / Q | 0;0;96;130.0 / 0;0;95;89.9 → REFUTADA | idéntico → REFUTADA (P sin firma) | ok, coincide con el criterio literal |
| Firma de los 14 brazos previos (`h22.py --todos`) | tabla del paso 12 | idéntica (nolink 105/35/235/57/72; ≥ 100 kPa 120/27/235/142/219; sin cambio 0-5) | ok |
| Cruce nolink/p (34, 8, 0, 1, 2; 380, 91, 634, 2000 kPa) | paso 12 | idéntico | ok |
| P: alternancia 86/54 kPa; cuartos 43.8 → 26.4 kPa | paso 13 | 86.0/54.0; [43.8, 35.4, 33.5, 26.4] | ok |
| fh a 1 ms: 56 → 112 m/s en 299.9-300.0 s | paso 13 | 55.7 → 112.2 | valor ok, sin fuente (O4) |
| H15: A 69.4/15, B 300.0/342, 365 (290020), cuartos 58/59/59/59 | paso 9 | idéntico | ok |
| H16: C 51.2/117 (280004), D 77.0/56 (300002) | paso 10 | idéntico | ok |
| H17/H18: E 51.2/117, F 300.0/461, 592 (280161), 31/21/32/36 | paso 11 | idéntico | ok |
| Pares: 7.9e-9, 1.5e-9, 1.1e-9, 3.5e-10; m_gas ~2.5e-7; 12 % | paso 11 | 7.9e-9, 1.5e-9, 1.1e-9, 3.5e-10; 2.6e-7 y 2.5e-7; 1.2e-1 | ok |
| H19-H21: G 216.3/361/895, I 2000, J 997/2000, K 155.3/128, L 300.0/237, H 69.4/15; cuartos, nolink, u ≥ 200/p ≥ 300, último paso | paso 12 | idéntico | ok |
| Unión de umbrales: G 11, F 8, B 18, I 101, J 187, L 3, s290 2 / 7, 6, 9, 73, 120, 2, 2 | paso 12 | idéntico | valor ok, sin comando (O5) |
| L: 300.0, 299.8, 245.3 m/s; luego ≤ 113 m/s | líneas 49-50 y 386 | 300.0, 299.8, 245.3; 113.3 | ok |
| L «toca 300 m/s 3 pasos» | línea 21 | 1 paso en 300 m/s; 3 pasos ≥ 200 m/s | **objeción O1** |
| k10b_dt025 en 280002-280004 | 198.6/281, 300.0/461, 200.8/199 | idéntico | ok |
| FAIL de check_audit en 21 brazos | varios | idénticos (A, C, D, E, H, K, M-Q, s290, dt05, mo20 sin FAIL) | ok |
| comp_carry; \|Δρ/ρ\| en 68232 celdas; Tg_end 17.7 % y p99 0.2 % | 0; 4.4e-16; 17.7 %; 0.2 % | 0.0; 4.44e-16; 0.1769; 0.00217 | ok |
| EOS-final 2.922 / 2.882 / 2.865 kg/s | paso 5 | 2.9221 / 2.8824 / 2.8650 | ok |
| Fechas de 2f0529b, 8f568fc y run.log de otp | 21-oct 10:13:58; 22-oct 02:56:49; 02:57:32 | idénticas | ok |
| Pico a 1 ms / 0.5 ms | 99.6 kPa (280003), 163.5 m/s (280002); 191.4 kPa | idéntico | ok |
| Tabla 1 ms del paso 7 y rel < 5e-6 | paso 7 | idéntica; 4.8e-6 | ok |
| Asentamiento a 1 ms: 24/17, 31/13; ciclo 23/43 y 28/49 kPa | paso 9 | 280024/280017, 280031/280013; 23.2/43.3 y 27.6/49.0 | ok |
| Nolink de k10b: 280002-023, 135-141, 161-236; 2 celdas en 280002, máx. 6; 71 de 120; B 4-9 | paso 9 | idéntico; F en los mismos pasos | ok |
| Medias por cuartos (B, k10b, C, s290, D, A) y p en el paso 0 | Resultado | idénticas; B −44 % (244.3 → 137.6) | ok |
| Tabla de Resultado: s290 450.0 (290093) y 344.3 (290074); dt05 70.6; mo20 70.0; k10b 591.6 (280161); 5/235, 0/117, 0/58, 120/235 | Resultado | idéntica | ok |
| Régimen de los jueces 275-295 s (tabla de 15 filas × 3) y filas especiales | C-241 | idéntico, incluidos 30.3/7.2, 16.8/0.7, 38.1/21.9, 38.3/18.4 y 3.7 kPa | ok |
| Nivel centinela de B1 en 280-295 s: fh 15, jb 1, otp 26; 304 y 578 kPa | C-251 | idéntico | ok |
| Snapshots de 275 s idénticos; a 280 s Δα_s 0.77 y Δα_g 0.64; rangos de p | Incertidumbre | 0 en todo, incluidos los 17 datasets de /restart; 0.772, 0.644; −0.09/14.8 y −12.8/28.0 kPa | ok |
| 8 de 56 datasets distintos, S_arc hasta 3.1e8 | Incertidumbre | 8/56, 3.14e8 | valor ok, sin comando (O6) |
| Lectura independiente del binario: 2.2e-12 y 5.2e-13 | Incertidumbre | 2.22e-12 y 5.21e-13 | valor ok, sin comando (O6) |
| Alternancias: otp 106.9/90.5 m/s y 23.5/27.0 kPa; mo20_s290 ~122/~77; jb 295 s ~160/110 y 44/22 | Incertidumbre y paso 12 | idénticas | ok |
| Lista de bancos que reinician de otp 280 s y sus pasos (60, 119, 300, 1000, 4330, 5500) | Resultado | idéntica | ok |
| C-nnn citados | 41 ids | todos existen; veredictos posteriores a sus predicciones | ok |
| Regla staged, frase «(jb 1 frente a fh 15) la apoya» | «queda corregida en este diff» | contradice C-260 y la línea 629 del reporte | **objeción O2** |

## Objeciones

1. **O1 (bloqueante).** `report.md:21` dice que acotar dt en jb 295 s «toca 300 m/s 3 pasos». En `campaigns/b1/k11_l_dt025_jb295/audit.csv` u_gas_max vale 300.0, 299.8 y 245.3 m/s: un solo paso en U_GAS_MAX y tres ≥ 200 m/s. Contradice C-259(3) y la línea 50 del reporte. La regla staged repite el error. Para levantarla: corregir las dos frases según C-259(3).
2. **O2 (bloqueante).** La regla staged `.claude/rules/transporte-energia.md` publica que la evidencia de jb 1 frente a fh 15 filas «la apoya». C-260 retiró esa palabra y el reporte (líneas 627-629) dice «tampoco la apoya». El reporte afirma que la regla queda corregida en este diff. Para levantarla: cambiar la frase y volver a hacer stage.
3. **O3 (no bloqueante).** El titular (líneas 13-16) presenta los controles como de una sola clave en 290 s. Pero `k11_b_dt025_fh290_on/config.dat` frente a `k11_n_dt025_fh290_off/config.dat` difieren en dos claves. Para levantarla: decirlo en el titular o correr un brazo de 290 s con solo f28.
4. **O4 (no bloqueante).** Falta la fuente de «56 a 112 m/s en 299.9-300.0 s» (línea 449). El valor recalculado es 55.7 → 112.2.
5. **O5 (no bloqueante).** Falta el comando de los recuentos de unión de las líneas 375-376. `duracion.py` no los imprime. Los valores se reproducen.
6. **O6 (no bloqueante).** Faltan los comandos de «8 de 56 datasets / S_arc 3.1e8» y de «2.2e-12 y 5.2e-13» (Incertidumbre). Ni el reporte ni C-236 los traen. Los valores se reproducen.

El fondo se sostiene. H22 SOPORTADA y H23 REFUTADA coinciden literalmente con sus criterios pre-registrados, y la comparación es justa (mismo binario, configs de una clave salvo N/B). Todas las demás cifras se reproducen. El rechazo se debe a dos afirmaciones del titular y del diff de la regla que contradicen datos y correcciones registradas (C-259, C-260).

VEREDICTO: rechaza