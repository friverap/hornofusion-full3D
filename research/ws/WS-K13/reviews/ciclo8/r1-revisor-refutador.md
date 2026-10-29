# WS-K13, ciclo 8, ronda 1: revisor-refutador

Lo hice solo leyendo. Usé python únicamente para leer el registro y simular eventos en memoria; no escribí nada en `ledger.jsonl`. No leí las revisiones de los otros revisores.

## 1. Conclusiones, hipótesis alternativa y dato que las separa

**C1. `current_state` sigue las enmiendas juzgadas. Solo cambian C-169 y C-194; los 24 veredictos conservan su estado.**
- **Hipótesis alternativa:** el cambio vuelve a poner etiqueta a afirmaciones cuya lectura de fondo quedó matizada. C-194 dice «D es una TASA» y ahora sale `soportada`, mientras que C-197 concluye que el error es POR PASO; el nuevo estado podría ocultar esa precisión.
- **Dato que las separa:** si C-197 sigue visible junto a C-194. Está en los datos: `ledger.py show C-194` lista C-195, C-196 y C-197. El veredicto C-196 es «soportada por la letra», como manda la regla. Además, C-169 y C-194 no son raíz, así que no salen en `open`.
- **Comprobación:** reproduje el conteo frente a HEAD: `[('C-169','enmendada','refutada'), ('C-194','enmendada','soportada')]` y 24 veredictos. Los 24 son una consecuencia directa de que ahora un veredicto devuelve su propio estado; no prueban nada por sí solos, pero tampoco tienen efecto en `open`.
- **Resultado:** la alternativa se descarta.

**C2. L1: «cerradas sin decidir» se calcula por el estado vigente.**
- **Hipótesis alternativa:** el síntoma sigue apareciendo por la vía de retoma que cita el propio reporte (`report.md:167-168`, «C-110 vía C-304»).
- **Dato que las separa:** simulé en memoria una predicción C-900 que retoma C-110 por cada vía.
  - Por el cierre C-304: se acepta y C-110 sigue en «cerradas sin decidir», mientras C-900 sale como abierta.
  - Directa sobre C-110: se acepta, C-110 sale de esa lista pero queda `pre-registrada`, y la misma retoma cuenta en «abiertas» y en «NO raíz abiertas».
- **Resultado:** L1 queda arreglado tal como lo formuló el panel (ningún id sale en las dos listas a la vez). Lo que queda es una ambigüedad del README (`:56` frente a `:58` y `:71-72`). Ver R1.

**C3. L5: GATED y el hook cubren la herramienta y el panel.**
- **Hipótesis alternativa:** la compuerta sigue sin atar el propio cambio.
- **Dato que las separa:** para este commit la compuerta es la de HEAD, que solo mira `src` y `tests`. Verifiqué que `diff_sha_gated` (221d17b0…) y `diff_sha` (e10f7514…) se reproducen con el diff staged. Para los commits siguientes, GATED y el hook usan las mismas rutas.
- **Resultado:** la alternativa se cumple solo para este commit, y está declarado. Ver R2.

**C4. «`open` da la misma salida que con HEAD».**
- **Hipótesis alternativa:** que la salida coincida porque el código nuevo de `open` (hijas NO raíz, aviso de «hija juzgada», clave `cierre`) nunca se ejecuta con el registro real.
- **Comprobación:** el diff sale vacío. No hay raíces abiertas, todas las predicciones e hipótesis hijas están cerradas y ningún workstream tiene `cierre`. Así que el registro real no prueba esas ramas; solo las prueban los tests (`test_open_sin_decidir_por_estado_vigente` y `test_open_avisa_madre_con_hija_juzgada`).
- **Resultado:** la afirmación es correcta y no dice más de lo que demuestra.

**C5. Cadena lineal, un solo veredicto y `sin_decidir` solo tras `en_disputa`.**
- **Hipótesis alternativa:** cerrar `sin_decidir` sobre una enmienda podría saltarse la regla de que una predicción cerrada es definitiva.
- **Dato que las separa:** lo probé en memoria. `validate` rechaza `sin_decidir` sobre una enmienda, y también rechaza un segundo veredicto sobre una cadena con veredicto `en_disputa`. En el registro, los 10 cierres citan la raíz (C-301 → C-170 y C-302 → C-202, aunque ambas tienen enmienda).
- **Resultado:** la alternativa se descarta.

**C6. Tests: 42 de 42.**
- `tests_research.txt` (staged) dice «Ran 42 … OK» y los 42 tests existen.
- No volví a correr los conteos de 28 y 2 fallos con HEAD y con los parches del ciclo 7, porque soy solo lectura. Eso le toca al revisor de evidencia.

## 2. Repeticiones de fracasos registrados

No hay. Es una meta G3 de herramienta y no cambia la numérica. «Lo que NO funcionó» de `.claude/rules/acople-pv.md` y `docs/PLAN_*.md` tratan del acople numérico (D2.2, n_pc_max, reglas de clasificación, etc.), y ninguno toca el registro. Tampoco reaparece ningún diseño de herramienta ya refutado: el límite de `current_state` que WS-K12 declaró se resuelve aquí, no se repite.

## 3. Objeciones

- **R1 (no bloqueante).** Hay dos vías válidas para retomar un resultado o una hipótesis cerrados `sin_decidir`, y `open` no queda igual con cada una.
  - **Por el cierre (C-110 vía C-304):** C-110 sigue en «cerradas sin decidir» aunque su pregunta está abierta.
  - **Directa:** C-110 sale de esa lista, pero queda `pre-registrada` (un estado de predicción puesto a un resultado) y la retoma cuenta dos veces entre las abiertas.
  - **Resolución:** que el README fije una sola vía para hipótesis y resultados `sin_decidir`, o que diga explícitamente que la vía por el cierre no los reabre, y añadir un test que fije la salida de `open` en ambas vías. El dato ya está: la simulación en memoria descrita arriba.
- **R2 (no bloqueante).** El commit de arranque de WS-K13 no queda atado por la compuerta (está declarado).
  - **Resolución:** anotar que después del commit se puede comprobar con `git diff HEAD~1 HEAD -- <rutas GATED> | shasum -a 256`, que debe dar 221d17b0….

Ninguna conclusión del reporte resulta falsa con los datos que existen. Las dos objeciones son de documentación y de verificación posterior, no de corrección.

VEREDICTO: aprueba
