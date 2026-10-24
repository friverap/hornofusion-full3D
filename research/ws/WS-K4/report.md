# WS-K4 — Columna del residuo de la sub-relajación de T en el audit

Pieza (b) de la «opción 3» aprobada por el usuario el 24-oct-2026: «la columna
en el audit como pieza aparte para que esto no vuelva a quedar escondido».
Pieza (a), alpha_T 0.85 en B1, quedó refutada en C-100 y no forma parte de este
cambio.

## Proceso

1. En WS-K3, el juez C-092 (d26k/e1) se refutó por energía. Eso llevó a medir
   una fuga preexistente de unos −60 J/paso en el líquido del régimen denso de
   B1 {C-094}.
2. Los bancos C-095..C-098 localizaron la causa: con alpha_T = 1.0 la fuga baja
   de −58.1 a −3.8 J/paso {C-096}. La auditoría dirigida propuso el mecanismo
   cualitativo en el código {C-097}:
   - `relax_field(liq%T, p_lT, cfg%alpha_T, m)` (src/mod_multiphase.f90:562) deja un
     Tk = αT·T* + (1−αT)·Tpre que no cumple la ecuación discreta;
   - el hook de energía evalúa los términos sobre ese Tk (src/mod_energy_3d.f90:495);
   - la identidad de check_audit supone residuo cero (tests/integration/check_audit.py:127-260);
   - eeq(1,1), el absorbido del líquido, nunca se escribía (antes de este diff
     audit_accumulate solo acumulaba eeq(2,1); src/mod_audit.f90:730).

   La forma cuantitativa de C-097 (descomposición lineal en (1−αT), con el
   −3.8 J/paso de αT = 1 atribuido al TDMA) quedó refutada en {C-098}: la fuga
   no es monótona en (1−αT). El mecanismo cuantitativo sigue abierto; la columna
   lo mide directamente sin suponer esa descomposición.
3. Cambio de este workstream, solo diagnóstico, sin efecto numérico:
   - `src/mod_audit.f90`:
     - función pura `eq_residual(q) = eeq(q,1) − (eeq(q,2)+eeq(q,3)+eeq(q,4)+eeq(q,5) − eeq(q,6) + eeq(q,7))`;
     - tres columnas anexadas al final del CSV: `E_abs_liq_hook` (eeq(1,1)), `E_relax_liq` y `E_relax_gas`, acumuladas en `audit_accumulate` antes de anular eeq.
   - `tests/integration/check_audit.py`: línea `INFO energy_relax` con los residuos y `gap − residuos`. **No** entran a la identidad del balance, a propósito: si entraran, el balance cerraría por construcción y escondería la pérdida.
   - `tests/unit/test_relax_residual.f90`: tres casos de `eq_residual`. Con el enunciado cerrado da 0; con absorbido menor da −60; con la convección de signo invertido (término 5, de −10 a +10: +20) y la pared de 3 a 13 (término 6: −10), los términos suman 110 y el residuo es 100 − 110 = −10. El gas sigue en 0.
   - Glosario (`scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md`), con tipo «D» de diagnóstico.
   - Regla `.claude/rules/transporte-energia.md`: bullet sobre el residuo de la sub-relajación.

## Resultado

Predicción pre-registrada antes de medir: {C-101}. Veredicto: soportada {C-102}.

Banco base0 (restart dense_340_n15 paso 341500 → 341720, 15 ranks,
alpha_T 0.7) con el binario `campaigns/bin/eaf3d_relaxcol_opt` (este diff,
`make opt`):

- El residuo acumulado explica el hueco del líquido {C-102}:
  - sum E_relax_liq = −1.0883e4 J frente al hueco del líquido de −1.1717e4 J;
  - la diferencia es de 7.1 %, dentro del 15 % pre-registrado, con el mismo signo.

  > [fuente: campaigns/b1/bench_relaxcol/audit.csv | python3 scripts/diag/energy_gap.py campaigns/b1/bench_relaxcol]
- Lo que sostiene la atribución a la relajación es el contraste de dispersiones
  por paso, no la correlación sola {C-103}:
  - hueco del líquido, std por paso: 181 J con alpha_T 0.7 (base0), 0.25 J con 1.0 (aT1), 105 J con 0.85 (aT085);
  - remanente hueco − E_relax_liq en bench_relaxcol: −833 J en total, mediana −3.74 J/paso, std 0.23 J, constante y del mismo valor que el hueco de aT1 (−3.8 J/paso, std 0.25 J) {C-096}{C-103}.

  > [fuente: campaigns/b1/bench_{base0,eg_aT1,eg_aT085,relaxcol}/audit.csv | energy_gap.gaps(), std con ddof=1]
- Correlación de Pearson paso a paso de 0.99999918 entre E_relax_liq y el hueco del líquido {C-102}. Por sí sola discrimina poco: columna y hueco comparten los mismos términos de fuente del hook (eeq(1,2..7)).
  > [fuente: campaigns/b1/bench_relaxcol/audit.csv | energy_gap.gaps() frente a la columna E_relax_liq]
- El remanente del líquido, mediana −3.7 J/paso, coincide con el de alpha_T 1.0: −3.8 J/paso {C-096} (−3.6 con max_outer 10 {C-098}) {C-102}.
- Gas: E_relax_gas = +1.079e3 J frente a un hueco del gas de +1.046e3 J {C-102}.
- Sin cambio numérico:
  - p_max es idéntico bit a bit con bench_base0 en los 221 renglones;
  - energy_balance da el mismo veredicto (FAIL, gap/permitido 1.456) y el mismo gap, −1.067e4 J {C-102}.

  > [fuente: campaigns/b1/bench_base0/audit.csv, campaigns/b1/bench_relaxcol/audit.csv | python3 tests/integration/check_audit.py DIR]

- `make test-unit` OK (`PASS unit:test_relax_residual`, `UNIT TESTS: OK`) y `make test-quick` OK (las 4 corridas contra metrics_v131.json, err rel 0.000e+00; `TESTS (quick): OK`), sin rebaseline. Ambos corrieron sobre el árbol final de la ronda 2, que incluye el comentario corregido de src/mod_audit.f90.
  > [fuente: research/ws/WS-K4/logs/test_unit.txt, research/ws/WS-K4/logs/test_quick.txt | make test-unit; make test-quick]

## Incertidumbre

- **Remanente fuera de la columna.** Quedan −866 J (unos −3.9 J/paso) de `gap − residuos` en el total del banco; en el líquido, −833 J (std por paso 0.23 J) {C-103}. Queda FUERA de E_relax_liq. Como eq_residual se evalúa sobre el Tk guardado, cualquier residuo del TDMA caería DENTRO de la columna, así que el remanente no es el TDMA (la atribución de C-097 está refutada {C-098}). Candidato sin verificar: términos que el hook no ve, p. ej. celdas con alpha < ALPHA_CUTOFF o celdas guarda (T = T_old). Para cerrarlo: separar el inventario dE_liq de esas celdas con los h5 del banco y compararlo con −3.7 J/paso.
- **alpha_T 0.85 no anula el residuo de cada paso.** En aT085 el hueco neto del líquido es −13 J, pero la std por paso es de 105 J (frente a 0.25 J con 1.0) {C-103}. Con 0.85 se cierra el balance acumulado, no el enunciado de cada paso; esto concuerda con el FAIL de energy_balance_step. Ni el comentario de src/mod_audit.f90 («banco: 0 con 0.85-1.0») ni la regla de `.claude/rules/transporte-energia.md` (que atribuye el −3.8 J/paso al «residuo del TDMA de 3 barridos») reflejan esto ni C-098/C-103. Corregirlos cambia archivos fuera del alcance del redactor y queda para el coordinador.
- La columna se verificó en un solo banco de 220 pasos, una trayectoria (n15) y alpha_T 0.7. No se ha probado con aT1 ni con aT085 usando el binario nuevo, ni en n14, ni en el régimen denso largo, donde el remanente podría crecer (C-094: −87 J/paso en 280-340 s frente a −58 en el banco). No se extrapola más allá de lo pre-registrado en C-101. Comprobación prevista: en la próxima corrida B1 con el binario nuevo, comparar sum E_relax_liq con el hueco del líquido de energy_gap.py y con el remanente por paso.
- Las columnas son acumuladores por paso escrito, como el resto de `acc`: se anulan tras cada `audit_write_step` (src/mod_audit.f90:517). El audit arranca de cero tras un reinicio (src/mod_restart.f90:34), así que no hay estado nuevo que persista entre pasos ni que deba entrar al snapshot.

## Respuesta a la ronda 1

- evidencia O1: logs de test-unit y test-quick guardados en `research/ws/WS-K4/logs/`; `test_quick=ok` se fija con ws-set sobre el diff staged final.
- evidencia O5 y refutador O2 (auditor K4-A1): el comentario de src/mod_audit.f90 ya no dice «0 con 0.85-1.0». Ahora da el neto de −2 a −4 J/paso y la std por paso de 105 J con 0.85 frente a 0.25 J con 1.0 {C-103}.
- refutador O1 (auditor K4-A2):
  - la regla ya no atribuye el −3.8 J/paso al TDMA; cita C-098 y anota que el remanente queda FUERA de la columna {C-102}{C-103};
  - el glosario dice ahora «standing field Tk (under-relaxation + incomplete inner solve)»;
  - separar dE_liq de las celdas con alpha < ALPHA_CUTOFF es un análisis nuevo y queda pendiente en «Incertidumbre». No bloquea la columna, que es diagnóstica.
- auditor K4-A3: el comentario, el glosario y la regla dicen que el reparto por fase solo vale en dos fluidos, no con mixture_model.
