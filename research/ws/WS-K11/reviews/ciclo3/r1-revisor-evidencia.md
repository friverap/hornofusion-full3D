# WS-K11, ronda 1: revisión de evidencia

**Rechazo el cierre por una sola objeción bloqueante (O1).** Todas las cifras del reporte que recalculé coinciden con los datos, y los veredictos de H22 y H23 respetan al pie de la letra el criterio pre-registrado. Lo que falla es una conclusión del titular, repetida en firme en la regla staged, que no está probada. Corregirla es solo cambiar la redacción.

## Qué hice

Todo en solo lectura.

- **Scripts del reporte:** `h22.py --todos`, `h15.py`, `h17.py`, `h19.py`, `duracion.py`, `pares.py`, `medir_centinela.py` y `check_audit.py` por brazo.
- **Comandos en línea:** los de las notas de procedencia, más mis propios cálculos con python y h5py sobre `audit.csv` y los snapshots.
- **Fechas y configs:** fechas de commits frente al nacimiento de cada `run.log`, `diff` de configs entre brazos pareados y `ledger.py show` / `check`.

## Tabla

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| H22: firma de M / N / O | sin firma (15 / 18 / 20 kPa; 92.3 / 68.9 / 61.2 m/s) | igual | ok |
| H22: veredicto frente al criterio de C-263 | SOPORTADA | ninguno con firma, cero AVISO → SOPORTADA | ok |
| H23: P (fh 300 s, f28 encendida) | sin firma: 0 nolink, 0 pasos ≥ 100 kPa, 96 kPa, 130.0 m/s | igual | ok |
| H23: Q (jb 300 s) | sin firma: 95 kPa, 89.9 m/s | igual | ok |
| H23: veredicto frente al criterio de C-264 («SOPORTADA si P tiene la firma y Q no; REFUTADA en otro caso») | REFUTADA | P sin firma → REFUTADA | ok |
| Pre-registro antes de correr | commit `8b2d95b` | 10:42:49; M arranca 10:42:55, Q a las 11:15:45; `h22.py` sin cambios | ok |
| Configs y binario de H22/H23 | config de A, F o C con otro reinicio | `diff`: solo cambian restart_file y t_final; `eaf3d_k10b_opt`, 15 ranks | ok (ver O3) |
| P: media de p_max por cuartos | 43.8 → 26.4 kPa; alterna 86/54 kPa | 43.8, 35.4, 33.5, 26.4; 86.0/54.0 | ok |
| Firma de los 14 brazos previos (`--todos`) | tabla de los pasos 12 y 13 | igual | ok |
| Pasos ≥ 100 kPa por cuartos | F 31,21,32,36; B 58,59,59,59; J 57,49,60,53; G 27,0,0,0; I 59,6,22,55 | igual | ok |
| Tabla de separación (paso 12) | nolink, pasos ≥ 100 kPa, nolink con p < 100 kPa, max p sin nolink, max p | igual en las 14 filas (F: 105/120/34/380/592; G: 35/27/8/91/895; I: 57/142/1/634/2000; J: 72/219/2/2000/2000) | ok |
| Pasos con u ≥ 200 o p ≥ 300 | G 11, F 8, B 18, I 101, J 187; L 3, s290 2 | igual | ok |
| Pasos con u ≥ 299 o p ≥ 300 | 7, 6, 9, 73, 120; 2, 2 | igual | ok |
| Tabla del paso 12 (pasos 2-10, ventana, último evento) | G 216.3/361, 895 (280263), paso 27; I 2000; J 997 y 2000 (295114); L 300.0/237 | igual | ok |
| Paso 9: nolink | k10b_dt025 105/235 en 280002-23, 280135-41 y 280161-236 (2 celdas en 280002, máx 6), 71 de 120; B 235/235 con 4-9 celdas | igual | ok |
| Pasos 11 y 12: FAIL y `[CG] AVISO` de los brazos | según tablas | igual (21 bancos); cero AVISO | ok |
| `pares.py` (E/C, F/k10b_dt025) | 7.9e-9 / 1.5e-9; 1.1e-9 / 3.5e-10; m_gas ~2.5e-7; 12 % | 7.9e-9, 1.5e-9, 1.1e-9, 3.5e-10; m_gas 2.6e-7 y 2.5e-7; 1.2e-1 | ok |
| Medias por cuartos (Resultado) | B 244.3 → 137.6 (−44 %); k10b_dt025 con \|Δp\| de 73.4 a 30.6; C 76-80; D 37.8 → 28.2; A 14.5 | igual | ok |
| Serie de C | 28.0 → 116.5 (280004); 99.2, 90.7, 86.5; ~87/75 kPa | igual | ok |
| Asentamiento a 1 ms | otp 24 y 17 pasos; mo20 31 y 13; ciclos 23/43 y 28/49 kPa | igual | ok |
| Jueces 275-295 s (media de p_max / \|Δp\|) | tabla de 16 filas; 38.3/18.4 y 38.1/21.9; 3.7 | igual | ok |
| Filas de nivel centinela de B1, 280-295 s | fh 15, jb 1, otp 26 | igual | ok |
| Resultado desde 290 s | 71.6/79; 80.1/71; 124/55; 450.0 (290093; 128.6), 344.3 (290074); 591.6 (280161; 113.2) | igual | ok |
| k11_base_s290 | 107 m/s, 27 kPa, 1 AVISO, FAIL de energy_balance | igual | ok |
| Pasos 1 y 6: centinela a 280 s | 198.6/281, 300.0/461, 200.8/199; 99.6 kPa y 163.5 m/s a 1 ms; 191.4 kPa a 0.5 ms | igual | ok |
| 0.5 ms por cuartos | 8, 1, 2, 0 de 29, 29, 29, 30 | igual | ok |
| comp_carry; EOS; Tg_end | 0; 4.4e-16 en 68232 celdas; 17.7 % y p99 0.2 % | igual | ok |
| eosend por unidad de tiempo | 2.922 / 2.882 / 2.865 kg/s | igual | ok |
| Tabla a 1 ms (paso 7) | 71.9/14.8 … 215.0/83.5; < 5e-6 | igual; 4.8e-6 | ok |
| Arranque entre binarios | 2.2e-12 y 5.2e-13 | igual | ok |
| Snapshots de 275 s idénticos | \|Δ\| = 0 en α, p, T_gas y /restart | 0 en los 17 datasets de /restart | ok |
| Divergencia a 280 s | 0.77, 0.64; −0.09/14.8 y −12.8/28.0 kPa | igual | ok |
| otp frente a fh a 280 s | 8 de 56 datasets distintos, S_arc 3.1e8 | igual | ok |
| H12: coincidencia «a 3 cifras» | 3 cifras | p_max en 280001: 69.37 frente a 69.06 kPa | objeción O4 |
| Arranques posteriores a sus pre-registros (H12-H21) | commits citados | todos anteriores a su `run.log` | ok |
| «lo que cuenta es la edad del cambio» | conclusión del titular | ningún dato la separa; C-268 dice «no probado» | objeción O1 |
| Muestra de construcción | 13 y 14 brazos | 14 en `h22.py` | objeción O2 |

## Objeciones

1. **O1 (bloqueante).** El titular y la regla afirman una conclusión que nadie ha probado.
   - **Dónde:** `research/ws/WS-K11/report.md:17-20` concluye «así que lo que cuenta es la edad del cambio, no quién escribió el estado». La regla staged `.claude/rules/transporte-energia.md` (bullet «Ningun reinicio sin cambio la da») lo dice en firme: «un snapshot escrito poco despues del cambio la arrastraria […] Cuenta la EDAD del cambio».
   - **Por qué falla:** C-268 lo marca «(no probado)» y el reporte, en `report.md:708-714`, también.
   - **Por qué los datos no lo separan:** en los 19 brazos, todos los estados sin cambio llevan f28 ≥ 5 s y todos los estados con cambio tienen edad 0. Por tanto, «edad del cambio» y «estado escrito con o sin f28» van siempre juntos.
   - **Lo que hay de verdad:** recalculé las últimas 20 filas. B tiene nolink 4 y p_max de 109-150 kPa; F tiene nolink 1→4 y 104-156 kPa. Eso es una predicción, no una conclusión.
   - **Para levantarla:** redactarlo como hipótesis abierta en el reporte y en la regla, o reiniciar 60 ms desde `campaigns/b1/k11_b_dt025_fh290_on/eaf3d_00290236.h5` con su config y con una predicción pre-registrada.

2. **O2 (no bloqueante).** El tamaño de la muestra de construcción no es coherente.
   - `report.md:96-97` y `report.md:408` dicen 13 brazos.
   - `report.md:26`, `report.md:440` y `report.md:696`, el criterio de C-263/C-264 y `h22.py` (PREVIOS) cuentan 14.
   - **Para levantarla:** unificar la cifra, o explicar que 13 cuenta `k10b_dt025` y F como un solo estado.

3. **O3 (no bloqueante).** La ventana no es exactamente la pre-registrada.
   - C-263 dice «t_final +0.06 s».
   - `campaigns/b1/k11_{m,n,o}_*/config.dat` tienen t_final 285.061, 290.061 y 295.061, que dan 239 filas frente a 235.
   - El veredicto no cambia, porque las cuentas son 0.
   - **Para levantarla:** declararlo en el paso 13.

4. **O4 (no bloqueante).** La coincidencia de H12 no llega a 3 cifras en el primer paso.
   - En el paso 280001, `campaigns/b1/k11_dt025_tgfix/audit.csv` da p_max 69.37 kPa y `campaigns/b1/k10b_dt025/audit.csv` da 69.06 kPa (0.45 %).
   - **Para levantarla:** precisar «a 2-3 cifras», o empezar la comparación en 280002.

## Cosas que no puedo verificar y que el reporte ya declara

- Qué binario escribió `judge_fh_275` y cuál usó `scrfh_b`: los logs no lo registran y el reporte dice «probablemente».
- Que el control R4 del refutador descarta los poros sobrellenados: el cálculo es suyo y no está repetido en el reporte.

Ninguna de las dos sostiene el titular.

## Juicio sobre la comparación

- **H23 se comparó en condiciones justas:**
  - mismo binario y mismos 15 ranks;
  - misma config que F y que C, salvo el reinicio;
  - mismo acotado de dt;
  - mismo instante de 300 s en los dos linajes.
- **Su veredicto REFUTADA cumple el criterio literal.**
- **La conclusión «no suficiente» descansa en una sola trayectoria (P)** en un régimen caótico. El reporte lo declara, y el criterio era por trayectoria.
- **La afirmación de «necesario en los estados probados»** se apoya en:
  - H22, fuera de la muestra de construcción;
  - Q;
  - los brazos de construcción.

  Está bien acotada.

VEREDICTO: rechaza