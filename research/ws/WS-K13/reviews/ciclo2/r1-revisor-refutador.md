# WS-K13: revisión del refutador (panel de cierre, ronda 1)

Revisión de solo lectura. Python solo se usó para leer `research/ledger.jsonl` y para llamar en memoria a `validate` y `current_state` con eventos sintéticos que no se escribieron. No corrí make, mpirun ni tests. No leí las revisiones de los otros revisores de este ciclo.

## 1. Conclusiones del reporte: hipótesis alternativa y dato que las separa

**C1. El estado vigente sigue la cadena de enmiendas; solo cambian {C-169} y {C-194}.**
- **Alternativa:** que el cambio altere de forma silenciosa otras raíces.
- **Dato:** comparar `current_state` de HEAD con el staged evento por evento.
- **Resultado:** lo comparé. Solo cambian C-169 (enmendada → refutada) y C-194 (enmendada → soportada). `open` da 0 abiertas de 64, 46 refutadas o fallidas y 10 cerradas sin decidir, como dice el reporte. **Se sostiene.**

**C2. M1/E1/R1 resueltos: con un veredicto en la cadena ya no se acepta una enmienda ni un `sin_decidir` sobre P.**
- **Alternativa:** que la protección dependa de que P se lea «cerrada», y que una nota posterior la reabra.
- **Dato:** en memoria, una nota y después un `sin_decidir`.
- **Resultado:** está en los datos y **refuta** la conclusión (objeción R2). La enmienda sí queda bloqueada, porque `juzgada` es transitiva. El `sin_decidir` no, porque mira solo `current_state`.

**C3. R2 resuelto (opción a): las refutadas y fallidas son permanentes.**
- **Alternativa:** que la regla cubra un camino que nadie usa y deje abiertos los caminos reales.
- **Dato:** cuántos eventos del historial tienen ref a una raíz que ya estaba refutada; probar otros caminos en memoria.
- **Resultado:**
  - En el historial hay 0 eventos con ref directa a una raíz ya refutada.
  - Las retomas reales citan el veredicto: C-226 sobre C-225, C-254 sobre C-249, C-263 y C-264 sobre C-256. Ese camino sigue permitido.
  - En memoria también pasan una nota seguida de una hija, un resultado `soportada` y un segundo veredicto `soportada`.
  - **Refuta la conclusión** (objeción R1).

**C4. L1 resuelto (`open` filtra por el estado vigente).**
- **Alternativa:** que la salida no cambie porque el caso nunca ocurre en los datos reales.
- **Dato:** `open` de HEAD frente al staged.
- **Resultado:** la salida es idéntica, así que el arreglo solo está probado con tests sintéticos. Es aceptable para una herramienta. Pero la objeción R2 muestra otra forma de meter en esa lista una predicción refutada (C-169).

**C5. L5 resuelto (`scripts/research` entra en la compuerta).**
- **Alternativa:** que el defecto se haya movido al hook.
- **Dato:** sha256 del staged con y sin `.claude`.
- **Resultado:** 351c1e5f… sin `.claude` (coincide con status.json) frente a bb175577… con `.claude`. El cambio del hook de este workstream no queda atado al panel (objeción R4).

**C6. `check` exige `cierre` y los tres «aprueba» a un workstream `fallido`.**
- Leí el código (`ledger.py:277-285`); `check` pasa sobre los 309 eventos. No veo una alternativa material.

## 2. Repeticiones de fracasos registrados

- **R1 repite R2 de la ronda 1.** Una refutada sale de las permanentes, ahora por la vía de una nota, de un resultado o de un veredicto nuevo.
- **R2 es B1 de la ronda 1 al revés.** B1 era una nota que juzgaba una enmienda; aquí una nota sobre la predicción le quita el juicio. El arreglo se aplicó solo a `estado_enmienda`.
- **R4 es L5 de WS-K12 con otro archivo** (`guard_cierre.sh`).
- **Física:** el workstream no toca `src/` ni el simulador. No repite nada de «Lo que NO funcionó» de `.claude/rules/acople-pv.md` ni de los `docs/PLAN_*.md`.

## 3. Objeciones

**R1 (bloqueante). La permanencia de las refutadas se puede saltar.**
Pruebas en memoria sobre el registro real:
- (a) Un resultado `propuesta` con ref C-199 (fallida) se acepta; C-199 pasa a `propuesta` y la hija ref C-199 también se acepta.
- (b) Un resultado `soportada` con ref C-199 se acepta.
- (c) Un veredicto `soportada` sobre C-011 (raíz refutada) se acepta.
- (d) Una predicción con ref al resultado que refuta (C-200, C-286) se acepta.

*Resolución:* `validate` rechaza todo evento con ref a una raíz refutada o fallida cuyo estado no sea refutada ni fallida, y todo veredicto sobre una predicción que ya tiene un veredicto de cierre. Hay que decidir de forma explícita qué pasa con la ref a un veredicto refutado. Los dos rechazos son compatibles con el historial: hoy hay 0 eventos así y 0 predicciones con más de un veredicto. Falta un test por cada camino y que `check` siga OK.

**R2 (bloqueante). Un `sin_decidir` entra sobre una predicción juzgada si antes hay una nota.**
Secuencia: nota `propuesta` con ref C-169 → C-169 queda en `propuesta` (aunque `juzgada` = True) → `sin_decidir` con ref C-169 aceptado → C-169 aparece en «cerradas sin decidir». Con C-011 pasa lo mismo.

*Resolución:* la regla de `sin_decidir` rechaza también si la cadena de la predicción tiene un veredicto de cierre (soportada, refutada o fallida, sin contar `en_disputa`). Comprobé que ningún `sin_decidir` del historial cae en ese caso: C-126, C-130, C-135, C-144 y C-212 vienen de veredictos `en_disputa`. Falta un test.

**R3 (no bloqueante). La sección «Incertidumbre» se queda corta.**
- Son 31 los eventos no raíz cuyo estado vigente no coincide con el suyo, no 2.
- Entre ellos está C-173 (el veredicto que refuta C-169), que se lee `soportada`.
- También C-093 y C-266 (refutada → propuesta) y C-249 y C-256 (refutada → pre-registrada).

*Resolución:* dar el conteo y el comando, o que `current_state` de un veredicto devuelva su propio estado.

**R4 (no bloqueante). El hook queda fuera de `diff_sha`.**
El cambio de `.claude/hooks/guard_cierre.sh` de este workstream no está atado a la aprobación del panel.

*Resolución:* añadir `.claude/hooks` a `GATED` y recalcular `diff_sha`, o justificar la exclusión por algo más que «el panel no lo pidió».

## Verificado por mí

- `ledger.py check`: OK con 309 eventos y 13 workstreams.
- El diff de `current_state` entre HEAD y el staged es solo C-169 y C-194.
- `open`: 0 de 64 abiertas, 46 refutadas o fallidas, 10 cerradas sin decidir (mismos ids que el reporte).
- El `diff_sha` de status.json es igual al sha256 del staged de src, tests y scripts/research.
- No hay predicciones ni hipótesis no raíz abiertas en el registro real.

VEREDICTO: rechaza