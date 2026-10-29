# WS-K12, ciclo 2, ronda 2: revisor de evidencia

Esta revisión es solo de lectura. Ejecuté la simulación en memoria que trae el reporte (report.md:544-571, con `--run`) y repetí cada cifra con su comando o con un python propio sobre los archivos existentes. No leí las revisiones de los otros revisores de esta ronda.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Abiertas en `open` | 18 de 64 | 18 de 64 | ok |
| Barrido no raíz fuera de CERRADOS | 101 = 61+3+1+20+3+2+11 | 101; 64 resultados en propuesta (61 + C-146/162/181), 0 con criterio o refuta_si | ok |
| Simulación del cierre | 31 eventos aceptados, 0 abiertas de 64 | 31 ACEPTADOS (C-279..C-309), «abiertas 0 de 64», todos los --cmd con código 0 | ok |
| C-078 / C-081 / C-084 | 31/19 (61.3 %) 9.2 %; 26/18 (69.2 %) 9.4 %; 21/17 (81.0 %) 9.7 % | igual (tail de c077/c080/c083.out) | ok |
| A2: dos regímenes | 0/19 tempranos (12+4+3); después 19/19, 18/22, 17/18 | igual (eventos de c077/c080/c083) | ok |
| A4: celdas y alcance | (1,19,9) 18, (1,20,9) 3; z_tip [1.628,1.613,1.657] a [1.657,1.628,1.613]; rejilla 1x5x3; 13 snapshots | igual (`restart/elec_z_tip`, run.log «1 x 5 x 3», ntheta 60, 12 eaf3d + rot20) | ok |
| A5: Su l/g/c | 341706: -2.20e-2/-2.21e-1/-2.51e-4 (cuota 0.908); 341705: +1.26e-2/+2.18e-3/-1.27e-3 (0.785); externas 2-5 TF | igual (c086.out) | ok |
| A1: sonda | E candidata en it 2-6 y N en it 1-6 de la 2.ª externa; SALTADA; T nunca candidata (externas >= 2) | igual (diag_c058/run.log:560-576); parche :195/:201/:229/:269 | ok |
| A6: energía n15/n14 | d26k 2.321/2.334, e1 1.793/1.839, base 1.717 | igual; checker de 6127dd7 en memoria: idéntico | ok (O2 resuelta) |
| A6: u_gas >= 299.999 | d26k 23/77, e1 2/1, base 200/131 | igual (con >= 300 exacto: 22/71, 2/1, 182/119) | ok |
| A6: C-105 | 0.615 frente a 0.552; 0 frente a 100 | igual (ledger C-105) | ok |
| B1: logs WS-K9 | FAIL 3.41e-06, m_gas_out 0; PASS 1.69e-21, -7.1206e-6 | igual | ok (O6 resuelta) |
| B1: código | diff +9 / +11-2; gas_mass_on :812/:862 en 2b65e11, :884/:934 hoy; main_3d:149-150 | igual | ok |
| B1: tests/out | m_gas_bx_* en columnas 149-150; 0 en 2b65e11, 1 en 1de144e; .gitignore:20 | igual | ok |
| B2 | 60 PASS err rel 0; v132 = v131 + cold_flow_noenergy_n4 | `60`, `{'cold_flow_noenergy_n4'} []` | ok |
| B3: barrido | 22 corridas, 19 suben; dt 1.19e-9 a 1.27e-9; excepciones diag_c060, f231_340, k1pa | 22 19; dt 1.186e-9 a 1.270e-9; las mismas excepciones | ok |
| B3: errata C-044 | penúltima 3.84e4, 2.62e4 en 345148 | 3.837e4; 2.618e4 | ok |
| B3: C-043/C-046 | k15b 0/180, 2.98e5, 0; k15d 180/180, 3.81e4, 62; p417 220/220 | igual | ok |
| B4 | 395/395 con 0 diferencias; 5.865e5, 3.491e5, 3.279e5, 3.082e5 | igual; mod_audit:704, main_3d:836/:900, hdf5:230 | ok |
| B5 | 0.384/0.163, 0.491/0.165; 0.380 a 0.426; serie de 0.521 a 0.639 (máx. 0.682) | igual | ok (O4 resuelta) |
| Grupo C (C-015) | 805 kPa en 342451, (2,51,8), p = -8.045e5, máx. con signo 3.19e4, alpha_s = alpha_g = 0; 164 y 85 kPa; 91/81/131 kPa; 43 columnas | igual (-804512, 31894, 164008, 84832; 91.4/81.2/130.6 kPa; 43 columnas con m_*) | ok (O5 resuelta) |
| Evento 342535 n14 | 6.36e5 en (1,59,9) | igual | ok |
| E1: cotas de C-121 | [0.565, 0.635]; t = 1.144e-3; umbral 2.21e-3 | 0.5647, 0.6347; 1.1442e-3; 2.2125e-3 | ok (O1 resuelta) |
| E2 / E6 | 0.566 y 2.456; 0.3156 y 1.571 | 0.5660 y 2.4557; 0.3156 y 1.5707 | ok |
| E3-E5, E8 | 0.319/1.582; 0.319/1.571; 0.812 | coinciden con C-131/C-139/C-145/C-213 | ok |
| E7: check de hoy en k10_* | PASS; restos 2.91e-14/5.81e-14/2.91e-14; tolerancias 1.43e-11/1.46e-11/1.41e-11 | igual | ok |
| Herramienta | :28-32, :33, :114-122, :158-164, :207-209 | ESTADOS empieza en :27 (lo demás coincide); C-169 y C-194: `enmendada []` | ok (O3 resuelta; errata de línea sin efecto) |
| P1 | 2.001e5 a 1.240e5; 1.474e5 a 1.455e5; n15 sin cambio | igual | ok |
| P2 | 345311: 4.56e5 / -2.0e6 en (1,56,8), audit 2.0e6; 345318: 6.07e5 / 1.85e6; 345310: 1.55e5 | igual | ok en cifras; ver O8 |

## 2. Criterios pre-registrados

- **Grupo E.** C-121/C-122, C-126, C-130, C-135, C-144, C-170/C-172, C-202/C-203 y C-212 tienen en su criterio la banda intermedia «sin decidir». Los valores medidos caen en esa banda, así que el cierre `sin_decidir` respeta la letra. Ningún veredicto se reetiqueta.
- **A2 (C-074 refutada en la letra de C-077).** C-077 exige >= 70 %. Medido: 61.3 %. La discrepancia con el `refuta_si` propio de C-074 está escrita en el evento.
- **A4 (C-082 soportada en la letra de C-083).** 21/21 eventos fuera de la costura. El alcance (material más z_tip) está declarado.
- **A1, A3, A5 y A6 (no concluyentes).** La hija probó otra afirmación: otras caras, otra variable, otro paso u otro banco. No se propaga ningún veredicto.

## 3. Objeciones

1. **O1 a O7 de la ronda 1: resueltas.** El detalle está arriba. En O1, la resta de conjuntos es legítima: el conjunto de C-123 (alpha_g >= 1e-2) está contenido en el de C-126 (alpha_g > 0), con la misma fórmula de err_liq y m_gas_liq_skip = 0. La dependencia de cifras no reproducibles (C-128) está declarada, y la etiqueta no depende de ella.
2. **O8 (no bloqueante): P2 y la letra de C-048.** El criterio de C-048 dice «max de p del campo < 1e6», no «p_max». Por esa letra, C-049 se sostiene (6.07e5 < 1e6). Con max|p| (2.0e6, 1.85e6) se rebasaría la cláusula. P2 llama al 6.07e5 «la misma lectura que B4 refuta en C-047» y no dice si el veredicto se sostiene.
   - Ruta: `research/ws/WS-K12/report.md:604`. Dato: `diag_k15_k_off` en 345318: max p 6.07e5, max|p| 1.85e6.
   - Para levantarla: añadir que C-049 se sostiene por su letra y que la precisión no cambia el veredicto, y sustituir «la misma lectura que B4 refuta» por «el máximo con signo que C-047 tomaba por max|p|».

Errata menor, que no es objeción: `ESTADOS` empieza en `scripts/research/ledger.py:27`, no en la :28.

VEREDICTO: aprueba