# WS-K13, ciclo 3: revisión del refutador (ronda 1)

Revisión de solo lectura. No corrí make, mpirun ni tests. Usé Python solo para leer `research/ledger.jsonl` y para llamar en memoria a `validate`, `current_state` y `juzgada` con eventos sintéticos, sin escribir nada. Leí solo mi revisión del ciclo 2 (mismo rol), no las de otros revisores.

## 1. Conclusiones del reporte: alternativa y dato que las separa

**C1. El estado vigente sigue las enmiendas juzgadas; solo cambian {C-169} y {C-194}; ningún veredicto se mueve por notas.**
- **Alternativa:** que la regla acierte en el registro real por el orden en que ocurrieron los eventos y falle con otro orden.
- **Dato:** la secuencia P, enmienda E, nota sobre P, veredicto soportada sobre E.
- **Qué encontré:**
  - En el registro real lo reproduje: solo cambian C-169 y C-194; hay 53 eventos con estado vigente distinto del propio y 0 veredictos entre ellos.
  - En memoria la conclusión falla: con esa secuencia, `current_state(P)` = propuesta aunque `juzgada(P)` = True, porque `estado_enmienda` se evalúa en la posición de E y no en la del veredicto. Ver R2.

**C2. Cadena lineal y un solo veredicto; «`juzgada` y `current_state` no pueden discrepar».**
- **Alternativa:** que el segundo juicio siga siendo posible con otro tipo de evento.
- **Dato:** en memoria sobre la C-048 real.
- **Qué encontré:** la conclusión es falsa. Una nota la reabre a propuesta. Después se rechazan el veredicto, el `sin_decidir` y la enmienda, pero un `resultado` refutada se acepta. Además, un resultado refutada sobre una predicción soportada la voltea sin nota previa. Ver R1.

**C3. Las refutadas y fallidas son absorbentes.**
- **Alternativa:** que la regla bloquee un camino que nadie usa y deje abierto el que sí se usa.
- **Dato:** el historial de retomas.
- **Qué encontré:**
  - Hay 0 eventos con ref directa a una refutada.
  - Las retomas reales cuelgan del VEREDICTO: C-226, C-254, C-261, C-263, C-264.
  - En memoria también se aceptan una nota y una hija sobre la ENMIENDA de una refutada.
  - El estado de la madre no se reabre, pero esas hijas son invisibles en `open`. Ver R3.

**C4. L1: `open` filtra por estado vigente.**
- **Alternativa:** que no se vea nada porque el caso no ocurre en los datos reales.
- **Dato:** la salida de `open` en HEAD frente al staged.
- **Qué encontré:** las dos salidas son idénticas, así que el arreglo solo queda probado con tests sintéticos. Para una herramienta es aceptable.

**C5. L5 y R4: el hook y el workflow quedan atados al panel.**
- **Alternativa:** que el defecto se mueva a otro archivo de `.claude`.
- **Dato:** qué rutas cubre `GATED`.
- **Qué encontré:** el `diff_sha` coincide (302baba4…). Pero `.claude/settings.json` (que conecta el hook) y `.claude/agents/` (los revisores) quedan fuera. Ver R4.

**C6. `check` y el estado `fallido`.**
- `check` da OK con 309 eventos. Leí el código y no veo una alternativa material.

## 2. Repeticiones de fracasos registrados

- **R1 repite R1(c)/M1 del ciclo 2 con otro nombre.** El segundo juicio ya no entra como `veredicto`, pero entra como `resultado` soportada o refutada.
- **R4 repite L5 de WS-K12 y R4 del ciclo 2 con otro archivo.** Ahora es `settings.json` y `agents/`.
- **Física:** el workstream no toca `src/`. Nada de «Lo que NO funcionó» en `.claude/rules/acople-pv.md` ni de los `docs/PLAN_*.md` aplica.

## 3. Objeciones

**R1 (bloqueante). Una predicción reabierta queda atrapada y su única salida es un segundo juicio.**
- **El problema:**
  - El README (líneas 44-45) y el test `test_ledger.py:215` permiten que una nota reabra una predicción con veredicto de cierre.
  - Una vez reabierta, `validate` rechaza veredicto, `sin_decidir` y enmienda. Solo acepta un `resultado` soportada o refutada, es decir, un juicio sin criterio pre-registrado.
  - Comprobado en memoria sobre C-048. Además, un resultado refutada sobre una soportada la voltea aunque no haya nota previa.
- **Resolución:** elegir una de dos opciones y escribir un test por camino. Es compatible con el historial (0 casos); `check` debe seguir OK.
  - (a) Rechazar la nota con ref directa a una predicción con veredicto de cierre (la precisión va sobre el veredicto, como C-308 y C-309).
  - (b) Que `current_state` de esa predicción devuelva su veredicto.
  - En los dos casos, rechazar además un `resultado` soportada, refutada o fallida con ref a una predicción o a su enmienda.

**R2 (bloqueante). `estado_enmienda` no respeta el orden temporal.**
- **El problema:** con P, E, nota sobre P y veredicto sobre E, la predicción queda en propuesta aunque esté juzgada.
- **Resolución:** un test con esa secuencia que espere soportada. Lo arregla la opción (b) de R1, o exigir que la nota sobre una predicción enmendada vaya sobre la punta de la cadena.

**R3 (no bloqueante). La retoma por veredicto o enmienda contradice el README y queda invisible en `open`.**
- **El problema:** el README pide retomar sin `--ref`, pero las retomas reales citan el veredicto (C-226, C-254, C-261, C-263, C-264). Como esas hijas no son raíces, `open` no las lista.
- **Resolución:** documentar la vía del veredicto o restringirla a un `resultado`, y que `open` liste las predicciones e hipótesis no raíz abiertas (hoy hay 0, así que la salida no cambia).

**R4 (no bloqueante). `settings.json` y `agents/` quedan fuera de `GATED`.**
- **El problema:** un commit que quite el hook de `settings.json`, o que cambie a los revisores, no pasa por la compuerta.
- **Resolución:** añadir esas dos rutas a `GATED` y al hook, y recalcular `diff_sha`; o declarar la exclusión con su motivo en «Incertidumbre».

## Verificado por mí

- `ledger.py check`: OK (309 eventos, 13 workstreams).
- `diff_sha`: el sha256 del staged de las cinco rutas es 302baba4…, igual que en `status.json`.
- `open`: la salida de HEAD y la del staged son idénticas.
- `current_state` de HEAD frente al staged: solo cambian C-169 y C-194; 53 eventos con estado vigente distinto del propio, 0 de ellos veredictos.
- Historial: 0 resultados de cierre sobre predicciones y 0 notas sobre predicciones juzgadas (fuera de los 8 `sin_decidir` tras `en_disputa`).
- Los escenarios en memoria de R1, R2 y R3, como se describen arriba.

VEREDICTO: rechaza