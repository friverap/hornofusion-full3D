## WS-K13, ciclo 5, ronda 1: revisor-refutador

**Alcance.** Solo lectura. Leí:
- `report.md`, `research/README.md` y `status.json`;
- el `ledger.py` y el `guard_cierre.sh` staged;
- los tests de `tests/research/`;
- la salida de `ledger.py open/check/show`;
- mi propia revisión del ciclo 4.

Las pruebas de `validate` y `current_state` las hice en memoria, con eventos sintéticos añadidos a una copia de la lista; no escribí en `ledger.jsonl`. No leí las revisiones de los otros revisores. No ejecuté las suites de tests: los conteos 36/36, 22 y 6 quedan sin verificar por mí.

`acople-pv.md` y los `PLAN_*` no aplican, porque no hay nada staged en `src/`.

### 1. Conclusiones, alternativas y dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿En los datos? |
|---|---|---|---|
| Un veredicto conserva su estado (con HEAD había 24 distintos del suyo; ahora 0) | Se ocultan reversiones legítimas | Leer qué hacen los eventos que los citan | **Sí, descartada** (ciclo 4): son acotaciones (C-147, C-178). |
| `check` pasa con 309 eventos | Las reglas solo se ajustaron al historial | Casos adversos | **Sí:** salen los huecos O2, O3, O5 y O6. Ninguno viola el historial, pero el contrato documentado no se cumple. |
| `open` da la misma salida que con HEAD y L1 queda resuelto | L1 no se ejerce con los datos reales; el test sintético solo cubre una hipótesis | Retomar una predicción cerrada `sin_decidir` | **Sí:** el doble listado persiste en las predicciones (O3). |
| L5 resuelto: la herramienta queda atada al panel | Solo a partir del commit siguiente; en este, nada la ata | Un sha256 del cambio de herramienta del ciclo 5 en el reporte | **No está:** solo hay sha de los ciclos 3 y 4. `diff_sha` 85191384 = `git diff --cached -- src tests`, que solo contiene `tests/research` (O1). |
| M1/R3, M3 y R4: la compuerta la decide la herramienta ya aprobada | El hook que corre es el del disco | `settings.json` | **Sí:** se ejecuta `${CLAUDE_PROJECT_DIR}/.claude/hooks/guard_cierre.sh` (O4). |
| Solo cambian de estado C-169 y C-194 | — | — | Coherente con C-171 → C-173 y C-195 → C-196. |

### 2. Repeticiones de fracasos registrados

- **O1 repite L5 de WS-K12.** Allí el `diff_sha` fue el de un diff vacío y el cambio de `ledger.py` quedó sin atar. Aquí el `diff_sha` solo cubre `tests/research`, y la mitigación que se afirma (sha256 y parches del ciclo 5 en el reporte) no existe.
- **R1 y R2 de mi revisión del ciclo 4: resueltos.** Lo verifiqué en memoria:
  - resultado soportada sobre C-121: rechazado;
  - predicción → resultado soportada: rechazado;
  - nota sobre C-110: rechazada;
  - veredicto sobre C-122: rechazado.
- **R3 y R4: resueltos por el código.** `tool = HEAD`; si no, el índice; y solo después el disco.
- No hay repeticiones numéricas (Plan D2.2, n_pc_max, reglas D/E/F/G): no hay cambios en `src/`.

### 3. Objeciones

**O1 (bloqueante). El ciclo 5 no queda atado a la aprobación.**
- El reporte afirma que `ledger.py`, el hook, el README y `CLAUDE.md` quedan atados «por los parches y los sha256 de este reporte» (`report.md:171-172`, `:216-217`).
- No hay sha256 ni parche del ciclo 5. Nada impide cambiar `ledger.py` después de aprobar, y la compuerta de HEAD no lo ve.
- **Resolución:** registrar en el reporte, con su comando, el sha256 del cambio de herramienta, y guardar `ledger_ciclo5.patch` y `hook_ciclo5.patch`. Mis mediciones:
  - `bbfe87de…` para `git diff --cached HEAD -- scripts/research/ledger.py .claude/hooks/guard_cierre.sh | shasum -a 256`;
  - `571806d2…` para el diff staged de todo `GATED`.

**O2 (no bloqueante). La precisión «a su cierre» se rechaza.**
- El README, el reporte y el propio mensaje de error de `validate` dicen que una precisión va con `--ref` «a su veredicto o a su cierre».
- Una nota con `--ref` a C-296 o C-304 se rechaza: el cierre está `sin_decidir` y aplica la regla de `:132`. Los cierres `fallida` (C-289, C-306, C-307) son absorbentes.
- C-110 y C-168 no tienen ningún camino con `--ref` para una precisión.
- **Resolución:** un test con una nota sobre un cierre `sin_decidir`, y después ajustar el código o el texto.

**O3 (no bloqueante). L1 sigue para las predicciones.**
- Una predicción hija colgada de C-123 o de C-296 se acepta, pero C-121 sigue en «cerradas sin decidir» y la hija aparece en «NO raíz abiertas».
- C-296 pasa a «pre-registrada».
- El README dice «vuelve a abiertas y sale de esa lista».
- **Resolución:** un test con una predicción retomada vía su veredicto o su cierre, y la regla documentada.

**O4 (no bloqueante). El hook del disco decide su propio commit.**
- Un `guard_cierre.sh` permisivo, en el disco o staged, decide su propio commit. Es la misma clase de fallo que M1/R3.
- **Resolución:** declararlo en «Incertidumbre», o ejecutar el hook de HEAD.

**O5 (no bloqueante). Las enmiendas de hipótesis o resultados esquivan la regla absorbente.**
- Si se refuta la enmienda de una hipótesis, la hipótesis se queda «enmendada»: sigue abierta y luego acepta un resultado soportada.
- En el registro real no hay ningún caso.
- **Resolución:** rechazar las enmiendas cuya raíz no sea una predicción, con un test.

**O6 (no bloqueante). Una nota cambia el estado de una predicción `en_disputa`.**
- Una nota con `--ref` directo a una predicción que tiene un veredicto `en_disputa` le cambia el estado vigente a «propuesta».
- **Resolución:** un test que exija que el estado siga en `en_disputa`, o declararlo como deliberado.

### Verificado por mí
- `diff_sha` 85191384 = `git diff --cached -- src tests`, que solo contiene `tests/research`.
- El reporte no trae ningún sha256 ni parche del ciclo 5.
- `ledger.py check`: OK con 309 eventos. `open`: 0 abiertas de 64 y 10 cerradas sin decidir.
- R1 y R2 del ciclo 4 están cerrados (en memoria).
- O2, O3, O5 y O6 se reproducen en memoria.
- C-049 es un veredicto, así que la precisión pendiente de O8 de WS-K12 sigue siendo posible.
- No hay enmiendas fuera de predicciones en el registro real.

VEREDICTO: rechaza