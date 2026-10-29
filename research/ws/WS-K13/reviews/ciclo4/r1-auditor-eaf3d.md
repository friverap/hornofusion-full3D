# WS-K13, ciclo 4, ronda 1: auditor-eaf3d

**Veredicto: RECHAZA.** Hay tres hallazgos MEDIO sin resolver.

Revisé el diff staged en solo lectura. No ejecuté los tests ni el hook: crean repositorios temporales y escriben a disco. Los escenarios que cito los reproduje llamando a `validate` y `current_state` del `ledger.py` staged sobre eventos en memoria. Los defectos del hook los confirmé leyendo el código.

## Hallazgos

### MEDIO

**M1. `.claude/hooks/guard_cierre.sh:162-174`: la herramienta que se está revisando se aprueba a sí misma.**
- **Defecto.** El hook decide la compuerta con el `ledger.py` STAGED, y ese archivo es justo parte del cambio que la compuerta debe vigilar.
- **Escenario de fallo.**
  1. Se modifica `ledger.py` para que `gate_errors` devuelva `[]` (la misma modificación que usa `test_compuerta_la_decide_el_ledger_staged`).
  2. Se hace `git add` de ese archivo junto con un `src/a.f90`.
  3. Se corre `git commit -m x`.
  4. El hook ejecuta la versión staged, que responde «compuerta OK» con código 0; el hook sigue (`continue`) y el commit pasa sin panel.
- **Alcance.** El arreglo de B3 solo cierra la variante sin stage; con un `git add` el agujero es el mismo.
- **Arreglo.**
  - Ejecutar `git show HEAD:scripts/research/ledger.py`, o exigir que pasen HEAD y staged. El staged solo debe usarse si HEAD no tiene la herramienta.
  - Añadir un test con un `ledger.py` debilitado y staged que espere deny.
  - Documentar el costo: cuando cambie la fórmula de `staged_sha`, como en este mismo WS, el commit de arranque necesita el escape autorizado.

**M2. `scripts/research/ledger.py:110` y `:128-131`: una predicción cerrada sin veredicto de cierre se puede volver a juzgar.**
- **Escenario reproducido.** P pre-registrada → `resultado sin_decidir --ref P` → `veredicto soportada --ref P`.
  - `validate` acepta los tres eventos.
  - `current_state(P)` queda en `soportada` y `juzgada(P)` da True, así que un WS numérico con `prediccion=P` pasa la compuerta.
- **Por qué es un defecto.** El README staged dice que la pregunta sin_decidir «solo se retoma con una predicción NUEVA» y que «un segundo juicio es una predicción nueva».
- **Casos parecidos, también aceptados:**
  - `resultado soportada --ref P`, después `veredicto refutada --ref P`;
  - `veredicto en_disputa`, después `resultado soportada --ref P`: P queda soportada sin ningún veredicto de soporte.
- **Arreglo.** Si la base es una predicción con `current_state` en CERRADOS, rechazar el veredicto y el resultado con estado de cierre; solo se acepta una predicción nueva (la retoma).
- **Compatibilidad con el registro.** Comprobé que ningún evento real cita una predicción cerrada (los 23 casos que hay citan resultados o hipótesis soportadas), así que `check` seguiría pasando.

**M3. `.claude/hooks/guard_cierre.sh:151`: renombrar o borrar `ledger.py` desactiva la compuerta.**
- **Defecto.** `if not os.path.isfile(<disco>/scripts/research/ledger.py): continue  # otro repo`.
- **Escenario de fallo.** `git mv scripts/research/ledger.py scripts/research/registro.py` (o `git rm`), más un cambio en `src/`, y `git commit -m x`: el commit pasa sin compuerta. Desde ese momento todos los commits se saltan la misma línea.
- **Alcance.** Esto deja sin cumplir lo que el reporte da por resuelto en L5/R4: que `scripts/research/` está dentro de la compuerta.
- **Arreglo.**
  - Detectar el repo con `git cat-file -e HEAD:scripts/research/ledger.py`.
  - Si el staged borra o renombra la herramienta, aplicar la compuerta con la versión de HEAD.
  - Añadir un test con `git rm` más `src/` que espere deny.

### BAJO

**B1. `ledger.py:124-131` junto con `current_state`: un resultado con estado de cierre que cita una enmienda se acepta, pero no cuenta para la predicción.**
- **Escenario reproducido.** P → enmienda A → `resultado refutada --ref A` (aceptado: A queda refutada y P sigue «enmendada») → `veredicto soportada --ref A` (aceptado: P queda soportada).
- **Por qué es un defecto.** Si el resultado citara a P, P quedaría refutada y absorbente. Choca con la regla de que «citar una enmienda equivale a citar su predicción».
- **Arreglo.** Rechazar los resultados con `--ref` a una enmienda cuyo estado no sea `propuesta`. Ningún resultado real cita una enmienda.

**B2. `gate_errors:384` (previo a este WS, fuera de su alcance): `juzgada` acepta un solo veredicto `en_disputa`.**
- Un WS numérico abre la compuerta con su predicción en disputa.
- Queda a decisión del coordinador.

## Lo verificado como correcto

Todo lo siguiente lo rehíce en solo lectura.
- `ledger.py check`: «ledger OK (309 eventos, 13 workstreams)».
- `open` da la misma salida con HEAD que con el staged.
- Veredictos con estado vigente distinto del propio: 24 en HEAD y 0 en el staged.
- Fuera de los veredictos, con respecto a HEAD solo cambian C-169 (pasa a refutada) y C-194 (pasa a soportada).
- Eventos con `--ref` cuyo estado vigente difiere del propio: 53 (32 predicciones, 14 resultados, 5 enmiendas, 2 hipótesis).
- `staged_sha` = `d86e3085…`, igual a `diff_sha` de status.json. El disco es idéntico al staged.
- Reglas de `validate` correctas en los casos con veredicto:
  - cadena lineal (`:102`);
  - un solo veredicto (`:110`);
  - no se enmienda una afirmación juzgada o cerrada (`:121`);
  - refutadas absorbentes a través de la raíz (`:124-127`);
  - no hay `sin_decidir` tras un veredicto de cierre (`:141`).
- `current_state`: con el recorrido en orden, una nota anterior al veredicto ya no lo pisa, y un veredicto conserva su propio estado.
- `open`: la lista de cerradas sin decidir filtra por estado vigente y no repite refs (L1).
- `check` de `fallido`: exige la clave `cierre` y los tres «aprueba» en la ronda vigente.
- GATED coincide con los prefijos del hook. Que `tests/research` entre en `diff_sha` pero no bloquee está declarado en el reporte.
- `.claude/settings.local.json` fuera de la compuerta no es un defecto: está en el gitignore global.
- Las 8 predicciones sin_decidir del registro (C-296 a C-303) tuvieron antes un veredicto `en_disputa`.

## Orden sugerido de corrección (uno por uno)

1. **M1:** la compuerta la decide la herramienta de HEAD, con su test.
2. **M3:** la detección de «otro repo» no debe depender del disco, con su test de `git rm`.
3. **M2:** una predicción cerrada por resultado o por sin_decidir es definitiva, con un test de sin_decidir seguido de veredicto. Volver a correr `check` sobre el registro real.
4. **B1:** rechazar resultados con estado de cierre sobre enmiendas.
5. **B2:** decisión aparte del coordinador.
