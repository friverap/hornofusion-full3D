# Revisión de evidencia: WS-K12, ronda 1

**Resultado: rechazo.** Recalculé todas las cifras del reporte desde los datos y coinciden. Rechazo por dos problemas de regla de cierre, no de números.

Fuentes leídas:
- Reporte: `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K12/report.md`
- Registro: `research/ledger.jsonl`, 278 eventos; `ledger.py check` da OK.
- Diff staged de `scripts/research/ledger.py` y de `research/README.md`.

Método: todo en solo lectura. Los 30 eventos propuestos los validé en memoria con `ledger.validate`, sin escribir en el registro. Los `--cmd` los extraje con zsh y los ejecuté; todos son de lectura.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| Afirmaciones abiertas | 18 de 64 | 18 de 64 | ok |
| No raíz fuera de CERRADOS | 101 (11 entran, 90 fuera) | 101; 61+1+3+20+3+2 = 90 | ok |
| Resultados «propuesta» con refuta_si o criterio | 0 de 61 | 0 de 61 | ok |
| C-078, n14 | 31 / 19 (61.3 %); control 453/4919 (9.2 %) | igual | ok |
| C-081, n15 | 26 / 18 (69.2 %); celdas 22/2/1/1 | igual | ok |
| C-084, estado girado | 21 / 17 (81.0 %); (1,19,9) 18 y (1,20,9) 3 | igual | ok |
| 12 primeros eventos de n14 sin precursor (341.83–343.06 s) | sí | sí (c077.out) | ok |
| Cuota del gas en 341706 | 0.908 | 0.221/0.2433 = 0.908 | ok |
| Cuota del líquido en 341705 | 0.785 | 0.0126/0.01605 = 0.785 | ok |
| aP de 341705 cae 68x; pp | 68x; pp 3.37e5 | 68.3x; 3.369e5 | ok |
| Sonda C-058, 2.ª externa | E con cx=1 en it 2-6, N en it 1-6, T en 0, SALTADA | igual (run.log:558-576) | ok, pero ver O1 |
| Pasos truncados que suben p_max | 22 / 19; dt 1.19e-9 a 1.27e-9 | 22 / 19; 1.186e-9 a 1.270e-9 | ok |
| Penúltima → última de diag_k15a, dense_340_n15, judge_e1_n14, judge_d26k_n14 | 3.84e4→2.46e5; 5.75e4→2.04e5; 2.75e4→1.47e5; 1.86e4→2.00e5 | igual | ok |
| Errata de C-044 | 2.62e4 en el paso 345148 | 2.618e4 | ok |
| Control de reinicio (validez de C-087) | 220/220 | 220/220 | ok |
| B4: audit p_max = max\|p\| del campo | 395/395 snapshots, 0 diferencias | 181+181+12+12+7+2, 0 | ok |
| diag_k15d en 345250 y 345280 | 9.27e4 / −5.865e5; 2.564e5 / −3.279e5 | igual | ok |
| Audit de diag_k15d en 345277 / 345280 / 345283 | 3.491e5 / 3.279e5 / 3.082e5 | igual | ok |
| C-198, antes del arreglo | FAIL 3.41e-06; m_gas_out 0 | igual | ok |
| C-198, con el arreglo | PASS 1.69e-21; −7.1206e-6 kg | igual | ok |
| Columnas m_gas_bx en tests/out | columnas 149-150; 0 en 2b65e11, 1 en 1de144e | igual | ok |
| C-199 en el golden | 60 PASS; v132 = v131 + cold_flow_noenergy_n4 | igual | ok, pero ver O2 |
| B5 | 0.384/0.163; 0.491/0.165; 0.380→0.426 | igual | ok |
| B5, k7v4_long | «0.521 → 0.682» | …0.663, 0.682, **0.639** | O4 |
| B5, comprobación aritmética | (5.211e-3 − 7.85e-4)/(1.6356e-2 − 4.816e-3) = 0.384 | 0.3836 | ok |
| Pico de C-015 | −8.045e5 en (2,51,8), líquido puro; máximo con signo 3.19e4 | igual | ok |
| Caída del pico tras el reinicio | 164 → 85 kPa | 164.0 → 84.8 kPa | ok |
| Corridas continuas en 342.451-342.530 s | 91 / 81 / 131 kPa | 91.4 / 81.2 / 130.6 kPa | ok |
| diag_p342a frente a judge_otp_280 | solo difieren 340000 y 342450 | igual | ok (O7) |
| Plan K fuera de src | pc_alpha_implicit ausente; existe plan_k_v2.patch | igual | ok |
| k7_mo20 (E2) | 59 pasos; 0.5660; 2.456 | igual | ok |
| k8_cg1000 (E6) | 0.3156; 1.571 | igual | ok |
| k7v3 y k7v4 (E3, E4) | 0.319; 1.582; corr +0.229; 59/59 | igual | ok |
| k7v5 (E5) | 0.319; 1.571 | 0.3186; 1.5705 | ok |
| Cota de C-121 | ≥ 0.565; 2.21e-3 | 0.5647; 2.213e-3 | ok |
| C-202 (E7) | Br/e −0.683 / −0.135; Br(0.5)/Br(1) 0.184 | igual (piezas.py) | ok |
| Br + Bgr | −1.69e-7 (0.012 e); −1.8e-8 (~0.001 e) | −1.695e-7 (0.0117 e); −1.80e-8 (0.0013 e) | ok |
| check_audit 1de144e sobre k10_* | PASS; restos 2.91e-14 / 5.81e-14 / 2.91e-14; tolerancias 1.43e-11 / 1.46e-11 / 1.41e-11 | igual | ok |
| C-212 (E8) | 0.812 | 0.812 (tasa.py) | ok |
| k11_dt025_s290 (F1) | 344 kPa en 290074; 450 kPa en 290093 | 344.3 / 450.0 kPa | ok |
| k11_l_dt025_jb295 (F2) | 300 m/s en 295002 | 300.0 m/s | ok |
| P1 (C-093) | 2.001e5→1.240e5; 1.474e5→1.455e5; n15 no truncados | igual | ok |
| Validador sin_decidir | rechaza id inexistente, veredicto, enmienda, ya cerrada y sin ref; rechaza repetir | igual (en memoria) | ok |
| Simulación de los eventos | 30 aceptados; 0 abiertas de 64; los cmd terminan con código 0 | igual (en memoria y con zsh) | ok (O8) |
| Líneas de ledger.py | :32, :33, :114-122, :158-164, :207-209; HEAD :28 y :144-150 | igual | ok |
| Citas de A6 | PLAN_D §7 «peor en picos y gas»; acople-pv.md «7x en 320-325 s» | presentes (:201, :460) | ok |

## 2. Objeciones

**O1 (bloqueante). A1 / C-057 lee el criterio de C-058 de dos maneras.**
- El criterio de C-058 tiene dos cláusulas sobre «sus caras de entrada T, E, N»:
  - soporte: ninguna queda candidata (cx=0);
  - refutación: alguna de esas caras queda fijada.
- Para declarar incumplido el soporte, el reporte lee T, E, N por su nombre: E y N tienen cx=1.
- Para decir que la refutación «no se observó», las lee por el sentido del caudal: E y N son salidas.
- Si se leen por nombre, la refutación SÍ se observó:
  - `campaigns/b1/diag_c058/run.log:561-576` da cx_E=1 en las it 2-6 y cx_N=1 en las it 1-6;
  - el parche fija las candidatas en el CG siguiente (`research/ws/WS-K1/patches/v2_completo_sobre_HEAD.patch:269`, `fx_r = cx_r`), así que C-061 es literal.
- Si se leen por el sentido del caudal, ninguna cara de entrada queda candidata y se cumple el soporte.
- Solo la lectura mixta da «no concluyente».
- Además:
  - «La sonda solo registra candidatas, no la fijación» contradice la cita del propio reporte a :269.
  - El salto por act_g está en `:201`, no en `:220-227`.
- **Para levantarla:** usar una sola lectura. Si es por nombre: la refutación de C-058 se cumplió, y la no propagación a C-057 se justifica porque C-058 enumeró caras por nombre y el refuta_si de C-057 habla de caras de entrada por caudal (otra afirmación). Retirar «la cláusula de refutación no se observó» y corregir la cita.

**O2 (bloqueante). B2, B3 y B5 no cumplen la regla declarada para el grupo B.**
- La regla dice que solo se cierra por relectura cuando el comando «decide su enunciado literal».
- B2 / C-199: el registro (C-200) dice que su afirmación central, 60 audit.csv idénticos celda a celda, NO se sostiene. Dejar C-199 en `soportada` contradice el registro.
- B3 / C-044:
  - el inciso «contamina reinicios» queda sin decidir;
  - su cifra está mal: `diag_k15a/audit.csv:345149` da 3.837e4, no 2.7e4.
- B5 / C-154: el comando no decide la interpretación.
- Es asimétrico con el grupo A, donde una prueba parcial da «fallida (no concluyente)».
- **Para levantarla:** declarar en la regla la variante «soportada SOLO en <partes verificadas>», con su condición y el porqué de la diferencia con A. O bien cerrar esas tres como fallida (no concluyente) y dejar las cifras como lectura.

**O3 (no bloqueante). Texto viejo en `report.md:500-503`.** Dice que siguen pendientes la validación de la ref de un `sin_decidir` y que `open` las muestre. El diff staged ya lo hace (`ledger.py:114-122` y `:207-209`). Solo queda pendiente la limitación de `current_state`.

**O4 (no bloqueante). Deriva de k7v4_long en B5.** La serie recalculada es [0.521, 0.56, 0.581, 0.531, 0.532, 0.618, 0.634, 0.637, 0.663, 0.682, 0.639]. No es monótona y termina en 0.639. Escribir «de 0.521 hasta un máximo de 0.682 (último tramo 0.639)».

**O5 (no bloqueante). Etiqueta de E1 / C-121.** «Por la letra» solo vale para la medida defectuosa (0.270, retirada en C-124). Con la cota corregida (≥ 0.565) el resultado puede ser sin decidir o refutada. Escribir «no decidible con este instrumento».

**O6 (no bloqueante). E11 / C-168 no encaja del todo en la definición.** El README define `sin_decidir` para un resultado que «solo registra» un sin decidir. C-168 contiene además afirmaciones propias (incisos 2 a 6). Ajustar la definición o decir en E11 que esos incisos no se juzgan.

**O7 (no bloqueante). Fila del reinicio de diag_p342a.** No difiere solo en «acumuladores de energía». La fila 340000 difiere en 43 columnas, también de masa y volumen (m_melted, m_gas_out, vol_lim…).

**O8 (no bloqueante). Fuente de la simulación.** La fuente cita `scratchpad/simk12/sim.py`, que está en el scratchpad de otra sesión y no es una ruta estable. La reproduje en memoria con el mismo resultado, pero conviene citar un comando reproducible.

## 3. Comparaciones y alcance

- Todo comparado en la misma ventana y con el mismo binario: picos de C-015, control de C-087, golden de C-199 y bandas de k10.
- El reporte declara la debilidad de la muestra en C-015/C-044: un solo caso y un control en otra ventana.
- No hay cambios en `src/` ni en `tests/`.

VEREDICTO: rechaza