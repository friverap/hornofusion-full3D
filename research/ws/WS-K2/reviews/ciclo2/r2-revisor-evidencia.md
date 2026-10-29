El veredicto se sostiene. C-041 refuta C-040 a la letra de su criterio pre-registrado, sin enmiendas: fallan el inciso (i) en 344–345.5 s y el inciso (iii). Todas las cifras de C-310, C-311 y C-312 se reproducen. Quedan 8 objeciones, todas no bloqueantes. Cuatro vienen de la ronda 1 y siguen sin corregir en el texto (O1–O4), una no se puede verificar con lo que hay en disco (O5) y tres son nuevas (O6–O8).

# Revisión de evidencia de WS-K2, ronda 2 (revisor-evidencia)

**Qué se revisó:** `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K2/report.md`, en su versión del working tree (01:18).

**Cómo se revisó:** solo lectura. Usé `regime2.py`, `ledger.py show/check` y python con csv/h5py sobre archivos que ya existían. No corrí nada.

**Revisión ciega:** no leí las revisiones de los otros revisores.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| C-014, 284.33–284.37 s: cent_pg y filas | 9.8 → 0 %, 41 filas | 9.8 → 0.0, n = 41 | ok |
| C-014, 294.04–294.07 s: cent_pg, gas y filas | 6.7 → 0 %, gas 300 m/s, 30 filas | 6.7 → 0.0, gmax 300, n = 30 | ok |
| C-027, 340–342 s: cent_pg de k1_340 frente a la base | 0.5 > 0.3 | 0.5 / 0.3 | ok |
| C-041 (i), 344–345.5 s: media de K | 4.42 (0.133/0.333/12.8) | 4.42 (0.1333/0.3333/12.8) | ok |
| C-041 (i), 344–345.5 s: mitad de la base | 3.89 (6.667/7.2/9.467) | 3.89 | ok |
| C-041 (i) 342–344 s, (ii) y (iv) | cumplen | 0.23 ≤ 0.77; 0.23 ≤ 0.57 | ok |
| Veredicto C-041 frente al criterio de C-040 | refutada | falla (i) en 344–345.5 s y falla (iii); sin enmiendas | ok |
| Tabla de estados | 22: 7/7/8 | 22: 7 soportadas, 7 refutadas, 8 fallidas; ids iguales | ok |
| C-312, cent_pg en 344–345.318 s | K 0.15/0.08/0.76; base 7.21/7.89/10.24 | igual | ok |
| C-312, cent_pg en 345.318–345.5 s | K 0.0/2.2/100.0; base 2.7/2.2/3.8 | igual | ok |
| C-312, medias de vol_lim y vol_unlinked | K 2.524–2.530e-3 y 2.097–2.104e-3; base 2.541–2.548e-3 y 2.071–2.086e-3 | igual | ok |
| C-312, sumas de m_spill y m_alpha_clip | K 2.3–7.1e-11 y 5.1–8.3e-11; base 1.05–1.22e-10 y 5.6–7.8e-11 | igual | ok |
| Pasos ≥ 1e6 en judge_otp_280 | 1, máx. 1.056e6 en 345266 | igual | ok |
| base_340_n14 | 4 pasos ≥ 1e6; tope «desde 344641» | 4; 1 paso en el tope (344641) | objeción O3 (incompleto) |
| base_340_n15 | 19 pasos ≥ 1e6; tope «desde 344797 (racha 2)» | 19; 3 pasos en el tope, racha en el tope 1; la racha ≥ 1e6 es 2 | objeción O3 |
| k1pa_340_n12 / _n14 | 0 pasos; máx. 3.30e5 en 340026 | igual | ok |
| k1pa_340_n15 | 183 seguidos (345318–345500); 122 en el tope | igual; incluye el paso truncado 345500 | objeción O4 (menor) |
| diag_k15_k_off, 345310–345320 | 10 pasos seguidos desde 345311; 2 en el tope; 90.9 % | igual | ok |
| diag_k15_k_on, 345310–345320 | 3 pasos desde 345318; 1 en el tope; 27.3 % | igual | ok |
| C-309: max\|p\| y celda | 2.000e6 en 345311–345312; 1.851e6 en 345318; celda (1,56,7-8) | igual con h5py; el máximo con signo es 6.072e5 | ok |
| C-043: paso truncado | 1.25e-9 s | 1.2498e-9 s | ok |
| C-044: 19 de 22 corridas | sin id | 22 corridas y 19 suben; la cifra es de C-287 | objeción O6 |
| C-076 y C-078 | 2 eventos; 19/31 = 61.3 %; control 9.2 % | igual en el registro | ok |
| C-093 | 2.32/2.31 frente a 1.717 | igual en el registro | ok |
| «PEOR en picos» | sin ruta | está en acople-pv.md:449 | objeción O7 |
| Avisos [PLAN-K] a los 25000 solves | 104/143/114 (0.42–0.57 %) | igual | ok |
| «unknown key» en los run.log de K | no aparece | 0, 0, 0 | ok |
| Audit de base_340_n1x idéntico al de dense_340_n1x; binario e5d331e | sí | cmp idéntico; run.sh lanza e5d331e | ok, pero 2 de 3 brazos base (O8) |
| Audit de K frente a la base | difieren «desde la primera fila» | primera diferencia en la línea 3 (paso 340001) | objeción O1 |
| Diff de config.dat entre K y la base | output_dir, restart, t_final, output_freq y claves de K | solo output_dir, pc_alpha_implicit y pc_ai_tol | objeción O2 |
| acople-pv.md, líneas 631–632 | frase a matizar | confirmado | ok |
| WS-K1 | en_revision | en_revision | ok |
| ledger.py check | — | OK (312 eventos) | ok |

## 2. Comparación justa

- **Mismo punto de partida:** los seis brazos de C-040 arrancan de `judge_otp_280/eaf3d_00340000.h5` y tienen el mismo t_final, 345.5 s.
- **Mismas claves:** el config de K solo difiere de la base en las claves probadas.
- **Base correcta:** es la que fija C-040.
- **Ventana del desglose:** el corte en 345.318 s de C-312 es a posteriori, porque coincide con el evento. El reporte lo usa solo para explicar el veredicto, no para cambiarlo, y eso es correcto.
- **Brazos diag_k15_k_*:** son 11 filas cada uno y no son controles limpios. El reporte lo declara.

## 3. Objeciones (ninguna bloqueante)

**De la ronda 1, siguen sin corregir:**

1. **O1.** `report.md` (Binarios): «difieren desde la primera fila» es falso. La primera diferencia está en el paso 340001, línea 3 del archivo, en n14 y en n15.
   - **Para levantarla:** escribir «desde el paso 340001».
2. **O2.** El diff real de `base_340_n14` (y de n15) frente a `k1pa_340_n14` (y n15) solo da output_dir, pc_alpha_implicit y pc_ai_tol. restart_file, t_final y output_freq son idénticos.
   - **Para levantarla:** corregir la lista.
3. **O3.** `base_340_n15`: tiene 3 pasos en el tope y su racha en el tope es 1. La racha de 2 es la de los pasos ≥ 1e6. A `base_340_n14` le falta decir que en el tope hay 1 paso.
   - **Para levantarla:** corregir las dos celdas de la tabla.
4. **O4.** `k1pa_340_n15`: los 183 y los 122 pasos incluyen la fila 345500, que es el paso truncado (dt 1.258e-9 s, C-287). Sin ella quedan 182 y 121.
   - **Para levantarla:** añadir una nota en la tabla.
5. **O5.** No verificable: no hay prueba en disco del contenido de `eaf3d_k1pa_opt`. El reporte lo declara como prueba parcial.
   - **Para levantarla:** no se puede con los datos actuales. Basta con que siga en «Incertidumbre».

**Nuevas:**

6. **O6.** «19 de 22 corridas» no lleva id. La cifra es de C-287.
   - **Para levantarla:** añadir {C-287}.
7. **O7.** «PEOR en picos» no tiene ruta en su nota de fuente. El texto está en `.claude/rules/acople-pv.md:449`.
   - **Para levantarla:** añadir esa ruta a la nota.
8. **O8.** La verificación indirecta de los binarios base cubre `base_340_n14` y `base_340_n15`, pero no `judge_otp_280`. Esa corrida no tiene run.sh ni script que la lance, y su run.log no registra el binario.
   - **Para levantarla:** escribir «2 de los 3 brazos base» y atribuir el binario de judge_otp_280 a lo que afirma C-040.

## 4. Juicio

- **Por qué apruebo:** todos los números que sostienen el cierre se reproducen dentro del redondeo mostrado. El veredicto de C-040 se juzga a la letra. Las precisiones C-310, C-311 y C-312 cuadran y no reinterpretan el criterio: el reporte deja sin decidir la causalidad del Plan K.
- **Por qué no bloquean las objeciones:** son erratas de texto y de procedencia, y no cambian el veredicto ni el estado propuesto (`fallido`).

VEREDICTO: aprueba