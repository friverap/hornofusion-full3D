# WS-K13, panel de cierre, ronda 1: auditor-eaf3d

**Veredicto: RECHAZA.** Queda un MEDIO (M1) sin resolver: rompe la regla 4 del reporte (refutadas absorbentes) según el orden en que se registren los eventos.

Revisé solo el código del diff staged (`scripts/research/ledger.py`, `.claude/hooks/guard_cierre.sh`, `tests/research/*`, README y CLAUDE.md). Todo en modo lectura: los escenarios los reproduje en memoria con `validate` y `current_state` del staged, y los tests corrieron en directorios temporales del scratchpad.

## Hallazgos

### MEDIO

**M1. `current_state` no respeta el orden temporal del veredicto de una enmienda** (`scripts/research/ledger.py:185-188`, `:191-199`)

- **Defecto.** El bucle de `current_state` recorre los eventos con `ref == P` en el orden del registro. Al encontrar la enmienda A llama a `estado_enmienda(A)`, que ya incluye el veredicto V aunque V sea POSTERIOR. Cualquier evento que cite P después de A pero antes de V sobrescribe el juicio.
- **Escenario reproducido.** Secuencia: P (pre-registrada), A (enmienda ref P), N (resultado propuesta ref P), V (veredicto **refutada** ref A).
  - Resultado: `current_state(P) = 'propuesta'` y `juzgada(P) = True`.
  - Después `validate` ACEPTA una predicción hija con ref P y un `resultado soportada` con ref P, y P queda en `soportada`.
  - `open` lista como abierta una predicción refutada.
  - Pasa lo mismo si el evento intermedio es una predicción hija: P queda «pre-registrada».
- **Contraste.** Sin enmienda (P, N, V) o con la nota después de V, el estado es correcto. Esto contradice el punto 4 del reporte y la frase del punto 2 «`juzgada` y `current_state` no pueden discrepar».
- **Registro real.** No hay daño. Las cinco predicciones juzgadas por enmienda (C-121, C-169, C-170, C-194 y C-202) no tienen eventos sobre P antes del veredicto. Pero la herramienta acepta la secuencia sin avisar.
- **Arreglo.** Recorrer `ev` una sola vez:
  - si `x.ref == eid`, aplicar `'enmendada'` (si x es una enmienda) o `x.estado`;
  - si x es un veredicto cuya ref está en la cadena de enmiendas de `eid` (la misma que arma `veredictos()`), aplicar `x.estado` en la posición de x.
  - Añadir un test con P, A, nota(P) y V(A, refutada): debe dar `refutada` y rechazar después una nota o una hija. Volver a correr `check` sobre los 309 eventos.

### BAJO

**B1. Se puede volver a juzgar con un `resultado` (`:110`, `:123-126`).** Tras P, V(soportada) y R(`resultado refutada` ref P) se acepta R, y P pasa a `refutada` aunque la cadena tenga un veredicto `soportada`. El propio `test_sin_decidir_no_tras_veredicto_de_cierre` deja `juzgada=True` con `current_state='propuesta'`. La frase del punto 2 del reporte es falsa tal como está escrita. Hay que corregirla y documentar el caso, o bien rechazar un `resultado` con estado en CERRADOS sobre una predicción juzgada.

**B2. Citas a la enmienda de una refutada (`:124`).** La regla absorbente solo mira refs de tipo afirmación. Tras P, A y V(A, refutada) se aceptan una predicción hija con ref A y un `resultado soportada` con ref A. No cambian el estado de P, pero quedan colgando de una refutada y `open` no las muestra. Arreglo: aplicar la regla sobre `raiz_enmienda(ref)` cuando ref es una enmienda.

**B3. El hook ejecuta el `ledger.py` del árbol de trabajo, no el staged** (`guard_cierre.sh`, llamada a `ledger.py gate`). Viene de antes de WS-K13. Ahora que `scripts/research` está en `diff_sha`, el ledger.py staged queda atado, pero la compuerta la decide el de disco. Se puede anotar en «Incertidumbre» o ejecutar `git show :scripts/research/ledger.py`.

## Verificado como correcto

- `diff_sha` de `status.json` = `staged_sha()` = sha256 del `git diff --cached` de las cinco rutas de GATED (302baba4…).
- Tests:
  - con el staged pasan 28/28;
  - con HEAD fallan los 14 que lista el reporte;
  - con los parches del ciclo 2 fallan exactamente los 5 citados.
- `ledger.py check` sobre el registro real da OK (309 eventos, 13 workstreams) con todas las reglas nuevas.
- Cambios de estado frente a HEAD fuera de veredictos: solo C-169 (enmendada → refutada) y C-194 (enmendada → soportada). El recuento de 53 (pred 32, res 14, enm 5, hip 2, ver 0) es exacto.
- `validate` rechaza `sin_decidir` sobre C-169 y C-194.
- `open` del staged es idéntico al de HEAD sobre el registro real.
- GATED (`:313`) y el filtro del hook usan las mismas cinco rutas. La exclusión de `tests/golden` y `tests/research` en el hook es la documentada.
- Cadena lineal: se rechazan la enmienda hermana, el veredicto sobre un eslabón ya enmendado y el segundo veredicto.
- `check` exige `cierre` y los tres «aprueba» en la ronda vigente para un workstream `fallido`.
- Las citas de línea del reporte corresponden al archivo staged.

## Orden sugerido de corrección

1. M1: `current_state` ordenado por el tiempo del juicio, más su test.
2. B2: regla absorbente a través de `raiz_enmienda`.
3. B1: corregir la frase del punto 2, o restringir el `resultado` cerrado sobre una predicción juzgada.
4. B3: anotarlo en «Incertidumbre».
