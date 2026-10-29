# Revisión de evidencia de WS-K2, ronda 1 (revisor-evidencia)

Reporte revisado: `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K2/report.md`. Solo lectura: regime2.py, ledger.py show/open/check y python con csv/h5py sobre archivos existentes. No ejecuté corridas ni binarios.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| C-014: centinela 284.33–284.37 | 9.8 % -> 0 % | 9.8 -> 0.0 (gmax 300 -> 190) | ok |
| C-014: centinela 294.04–294.07, gas sigue en 300 | 6.7 % -> 0 %, 300 m/s | 6.7 -> 0.0, gmax 300 | ok |
| C-014: tamaño de muestra | 30–40 pasos | 41 y 30 filas | objeción menor (O8) |
| C-027: 340–342 k1_340 frente a base | 0.5 % > 0.3 % | 0.5 / 0.3 | ok; refutada, literal con C-026 |
| C-027: «mejoró mucho» en 342–346 | cualitativo | p>100k 10.3->1.6 y 23.4->11.2; cent_pg 2.5->1.1 y 6.5->2.6 | ok |
| C-041 (i) 344–345.5: media cent_pg K | 4.40 | 4.42 (0.133/0.333/12.8) | objeción (O2) |
| C-041 (i) 344–345.5: base/2 | 3.90 | 3.89 (6.667/7.2/9.467) | objeción (O2) |
| C-041 (iii): k1pa_340_n15 llega a la centinela | 2.00e6 en 345–345.5 | 2.00e6, primero en 345318 (345.319 s); cent_pg 38.0 % en 345–345.5 | ok |
| C-041 «2 de 3 K mejores que toda la base» | 0.1/0.3 frente a 6.7–9.5 | 0.13/0.33 frente a 6.67–9.47 | ok |
| Veredicto C-041 frente al criterio C-040 | refutada | falla (i) en 344–345.5 (4.42 > 3.89; max 12.8 > 9.47) y falla (iii) (2.0e6 >= 1e6); sin enmiendas | ok |
| Comparación justa en C-040 | 3+3 desde judge_otp_280/340000 | mismo restart, t_final 345.5, config igual salvo las claves de Plan K, ranks 12/14/15 | ok; el binario no es verificable (O9) |
| C-043: paso truncado | 1.25e-9 s | dt 1.2498e-9 en diag_k15a/345150 | ok |
| C-046: reproducción | refutada | diag_k15c 5151/5151 filas idénticas; diag_k15d >= 1e6 en 345318 | ok |
| C-048/C-049 «Plan K NECESARIO» + C-309 | sin restricción | diag_k15_k_off: max\|p\| = 2.000e6 en 345311; con signo 6.07e5 en 345318 | objeción (O1) |
| C-044: 19 de 22 | 19/22 | 22 corridas, 19 suben | ok |
| C-047 «audit = max\|p\|» | atribuido a C-047 | la afirmación es de C-288 | objeción menor (O5) |
| Tabla de estados | 22: 7/7/8 | 22: soportada 7, refutada 7, fallida 8; check OK | ok |
| «G1 no pasó» | sin id | C-025 refutada por C-028; WS-K1 en_revision | objeción (O3) |

## 2. Objeciones

1. **(BLOQUEANTE) O1.** `campaigns/b1/diag_k15_k_off`: max|p| = 2.000e6 en 345311 (audit p_max 2.0e6) y 1.851e6 en 345318. La cifra 6.07e5 de C-049 es el máximo con signo. El brazo sin Plan K arranca de `diag_k15d/eaf3d_00345310.h5`, un estado con Plan K, y llega al tope en el primer paso. El reporte afirma «Plan K es NECESARIO para el salto» sin la restricción a la celda (9,1,2) que fija C-309, y la sección Incertidumbre no lo recoge, aunque es lo que pregunta G2 sobre presiones no físicas.
   - **Para levantarla:** restringir la frase a la celda (9,1,2) y añadir la línea en Incertidumbre con {C-309}{C-294} y su comando.
2. **O2.** `k1pa_340_n*/audit.csv` y `base*/audit.csv` en 344–345.5: media K = 4.42 y base/2 = 3.89 (el reporte da 4.40 y 3.90 porque promedia valores redondeados). No cambia el veredicto.
   - **Para levantarla:** dar 4.42/3.89, o mostrar 1 decimal.
3. **O3.** «G1 no pasó (WS-K1)» va sin id.
   - **Para levantarla:** citar {C-025}/{C-028} y decir que WS-K1 sigue `en_revision`.
4. **O4.** «Plan K no adoptado» en el cierre va sin id; la fuente es C-279. Falta además motivar por qué 284.3/294.1 s quedan sin objeto y no pendientes.
5. **O5.** La afirmación «el p_max del audit es max|p|» es de {C-288}, no de C-047.
6. **O6.** En Incertidumbre, la frase sobre C-064 omite que C-294 registra pruebas de su generalización: C-075/C-076 (no concluyente) y C-077/C-078 (refutada en la letra).
7. **O7.** `base_340_n14` (paso 344641) y `base_340_n15` (paso 344797) también llegan a p_max = 2.0e6 en 344–345.5, antes que k1pa_340_n15 (345318). Conviene decirlo para no leer el estallido como algo propio de K.
8. **O8.** C-014: hay 41 y 30 filas, no «30–40».
9. **O9.** No verificable: el binario de cada brazo de C-040. No hay run.sh y run.log no lo registra.
   - **Para levantarla:** una ruta que lo demuestre, o declararlo en Incertidumbre.

## 3. Juicio

- **Lo que se sostiene:** el núcleo numérico del cierre se reproduce. C-040 queda refutada por la letra de su criterio pre-registrado: fallan (i) en 344–345.5 y (iii). C-026 queda refutada en 340–342. Los conteos del registro cuadran.
- **Por qué rechazo:** O1 es una omisión material de alcance y de justicia del control. Está registrada en el propio ledger (C-309) y el reporte la presenta de forma que induce a error sobre las presiones no físicas.
- **Qué falta para aprobar:** corregir O1. Las objeciones O2–O9 son correcciones menores.

VEREDICTO: rechaza