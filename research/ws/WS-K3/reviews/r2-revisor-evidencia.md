# WS-K3, ronda 2: revisión de evidencia

**Resultado: apruebo.** Recalculé todas las cifras del reporte (`research/ws/WS-K3/report.md`) a partir de los datos y las comparé con el criterio pre-registrado. El veredicto de C-092 (refutada por el inciso (d)) respeta la letra del criterio y la comparación con la base es justa. Las objeciones O1 y O2 de la ronda 1 quedaron resueltas. O3 sigue abierta y hay dos objeciones nuevas, O4 y O5; ninguna cambia la conclusión.

Todo se hizo en modo de solo lectura: `ledger.py show|check`, `check_audit.py`, `judge_metric.py`, `bench_metric.py` (comprobé antes que no escribe) y python con csv sobre los `audit.csv`.

## 1. Tabla de verificación

| Afirmación | Valor del reporte | Valor recalculado | Resultado |
|---|---|---|---|
| Afirmaciones raíz de WS-K3 por estado | 15: 7 / 4 / 3 / 1 | 15: 7 / 4 / 3 / 1, mismos ids | ok |
| C-078, precursor fantasma | 19/31 = 61.3 % | 19/31 = 61.3 % (`dense_340_n14/c077.out`) | ok |
| C-084, giro de 120 grados | 21/21 | 21/21: (1,19,9) 18 y (1,20,9) 3 | ok |
| C-085, primer pico | paso 341705 | `c086.out`: pico en 341705; la regla eligió 341706 | ok |
| C-091, el banco lo pasan d26k, e1 y combo | pasan | d26k 3.64e4 / 2.12e5 / 1; e1 2.31e4 / 6.34e4 / 0; combo 2.17e4 / 6.21e4 / 0; base0 3.706e5 / 3.706e5 / 17 | ok |
| C-093 (d), sentinel_gas en FAIL en las 4 | FAIL | FAIL en las 4 (u_gas_max 300.0) | ok |
| Pasos con u_gas >= 300 (n15/n14) | d26k 23/77, e1 2/1 | 23/77 y 2/1 con umbral 299.999 | ok |
| energy_balance gap/permitido (n15/n14) | d26k 2.32/2.31 (con errata 2.334), e1 1.79/1.84 | d26k 2.321/2.334, e1 1.793/1.839 | ok (nota en O2) |
| Base energy_balance | 1.717 | 1.717 / 1.717 | ok |
| Base, pasos con u_gas >= 300 | 201/131 | **200/131** (umbral 299.999); 201 solo con 299.9 | objeción O4 |
| C-308, picos sin la fila truncada | 2.001e5 y 1.474e5 son el paso truncado | 1.240e5 y 1.455e5 sin esa fila; n15 sin cambio | ok |
| C-096, C-098, C-100, C-102 (incisos citados) | localiza; refutada (2); refutada (c); soportada | coincide con el registro | ok |
| C-105 a C-110, C-304 | refutadas; C-110 sin_decidir | coincide | ok |
| WS-K4..K13 con meta G3 y estado aprobado; K4-K8 numéricos | sí | sí (`status.json`) | ok |
| `git log 1bc9832..HEAD -- src` | 7 commits | 7 | ok |
| `src/` no contiene el Plan K | sí (cita C-065) | grep pc_alpha_implicit src = 0 | ok, sin comando (O3) |
| Nunca se corrieron bancos, MPI ni bitwise con el Plan K | sí | sin eventos de K1, K2 ni K3 en el registro | ok, sin comando (O3) |
| QUESTION.md sin cambios desde el 22-oct | sí | solo fecc672 (2026-10-22) | ok, sin comando (O3) |
| No existe `judge_combo*` y no hay descarte registrado | sí | sí | ok |
| Corridas de E1 en `campaigns/b1` | 340–345.5, 280–285.5 y «dos del 20-oct en 275–300 s» | más bench_e1 y 7 directorios del 20-oct; ninguno cubre 320–325 s | objeción O5 |

**Comparación justa.** Las bases (`dense_340_n14` y `dense_340_n15`) y los cuatro jueces arrancan del mismo reinicio (`judge_otp_280/eaf3d_00340000.h5`) y llegan al mismo `t_final` de 345.5 s. Sus `config.dat` difieren solo en `output_dir` y en la clave probada.

**Criterio de C-092 aplicado a la letra.** El inciso (d) exige sentinel_gas en PASS y energy_balance <= 1.717; los dos fallan en las 4 corridas, así que refutada es correcto. El reporte no reinterpreta el criterio: las mejoras frente a la base las presenta como observación (C-094 y C-284).

## 2. Objeciones (ninguna bloqueante)

1. **O1 (ronda 1): resuelta.** El reporte ya nombra sentinel_gas.
2. **O2 (ronda 1): resuelta.** El reporte remite a C-284 por la errata. Queda una nota de forma: sería más limpio escribir «2.32/2.33» que mostrar 2.31 y corregirlo entre paréntesis. Dato: `campaigns/b1/judge_d26k_n14:energy_balance gap/permitido=2.334`.
3. **O3 (ronda 1): se mantiene.** Las afirmaciones (a) `src/` sin Plan K, (b) bancos, MPI y bitwise nunca corridos y (c) QUESTION.md sin cambios desde el 22-oct siguen sin comando de procedencia. Las verifiqué y son ciertas. Para levantarla basta añadir tres notas de fuente:
   - `grep -rn pc_alpha_implicit src` (0 coincidencias)
   - `grep -iE 'bed_bath_rest|pocket_rise|bath_freeze|bitwise' research/ledger.jsonl` (solo WS-K5, K7 y K8)
   - `git log -- research/QUESTION.md` (fecc672, 2026-10-22)
4. **O4 (nueva).** `campaigns/b1/dense_340_n15/audit.csv`: hay 200 pasos con u_gas_max >= 299.999 en 340001-345500, no 201. El propio C-284 registra «base 200/131». Para levantarla: escribir 200/131 (201 en C-093) con el comando y el umbral.
5. **O5 (nueva).** La lista de corridas de E1 está incompleta. Con `pc_sat_open = true` están además `campaigns/b1/bench_e1` (341.5–341.72 s) y siete directorios del 20-oct, no dos: `judge_fhe1_275` (275–300), `scrfh_e1` y `scrfh_e1b` (280–281.6), `scr2908_E1` y `scr2908_E12` (290.8–291), y `scr291_E1` y `scr291_E1b` (290.9–290.95). La conclusión de fondo se mantiene: ninguna corrida cubre 320–325 s. Para levantarla: corregir la lista o reducirla a esa afirmación, con la fuente `grep -l 'pc_sat_open *= *true' campaigns/b1/*/config.dat`.

## 3. Juicio

Las cifras de las que depende la conclusión se reproducen desde los datos:
- el conteo del registro;
- las métricas del banco y de los jueces;
- los FAIL del inciso (d);
- los estados de K4-K13 y los commits de `src/`.

El cierre como `fallido` («G3 sin objeto») es coherente con la sección «Estados de un workstream» de `research/README.md` y con C-065. O3, O4 y O5 son erratas o faltas de procedencia que no cambian el veredicto de ninguna predicción ni el estado propuesto.

VEREDICTO: aprueba