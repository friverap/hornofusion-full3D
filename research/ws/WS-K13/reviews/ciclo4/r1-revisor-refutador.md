# WS-K13, ciclo 4, ronda 1: revisor-refutador

Alcance: solo lectura. Leí `report.md`, `research/README.md`, el diff staged (`ledger.py`, `guard_cierre.sh`, `CLAUDE.md`, tests), `ledger.py open/show` y el registro real. Las pruebas de `validate` y `current_state` las hice en memoria con eventos sintéticos añadidos a una copia de la lista: no escribí en `ledger.jsonl`. No leí `reviews/` (revisión ciega). WS-K13 es de herramienta, no hay nada staged en `src/` y `acople-pv.md` no aplica (no tiene lecciones del harness).

## 1. Conclusiones, alternativas y dato que las separa

| Conclusión del reporte | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| Un veredicto conserva su estado (de 24 a 0 veredictos con estado vigente distinto del propio) | Algunos de esos 24 eran reversiones legítimas que la regla nueva ahora oculta | Leer los eventos que citan esos veredictos con un estado distinto | **Sí; queda descartada.** Son acotaciones o correcciones de texto: C-178 dice «veredicto REFUTADA intacto», C-147 dice «el veredicto formal no cambia», C-119 corrige un inciso. Ninguno revierte un veredicto. |
| C-169 pasa a refutada y C-194 a soportada; ningún otro estado cambia | — | — | Coherente con C-171→C-173 y C-195→C-196. |
| `check` pasa sobre los 309 eventos con las reglas nuevas | Las reglas solo se ajustaron al historial; consistencia no es completitud | Casos adversos que no están en el historial | **Sí, y la refutan en parte:** ver R1 y R2. |
| Se cerró el segundo juicio por resultado (R1/B1 del ciclo 3) | Solo se cerró la rama «veredicto de cierre» | Resultado soportada sobre una predicción en_disputa + sin_decidir, o sobre una sin veredicto | **Sí, sigue abierto:** validate devuelve [] sobre el registro real y C-121 pasa de sin_decidir a soportada. Predicción → resultado soportada → veredicto refutada: los dos se aceptan. |
| `open` no cambia y L1 queda arreglado | La salida no cambia porque ningún caso real ejerce L1 (la evidencia es solo el test sintético) | — | Aceptable para L1. Pero ahora cualquier nota saca a una afirmación de «cerradas sin decidir» (R2). |
| L5/B3: la herramienta queda atada al panel y la compuerta la decide el ledger.py staged | El ledger.py staged se juzga a sí mismo; además, con un borrado en stage, decide el del disco | Test con un ledger.py permisivo STAGED; test con `git rm --cached` | No está en los tests. Por el código, ambos dan allow (R3, R4). |

## 2. Repeticiones de fracasos registrados

- **R1 repite R1/B1 del ciclo 3** («segundo juicio hecho con un resultado»; lo tomo de la descripción del propio reporte). El fallo sigue entrando por la rama en_disputa → sin_decidir, que es como están cerradas 8 de las 10 «cerradas sin decidir» reales, y por la rama sin veredicto.
- No hay repeticiones numéricas (Plan D2.2, n_pc_max, reglas D/E/F/G): no hay cambios en `src/`.

## 3. Objeciones

**R1 (bloqueante).** El segundo juicio por resultado no está cerrado.
- **Caso (a):** una predicción con veredicto en_disputa y cerrada sin_decidir (C-121, C-126, C-130, C-135, C-144, C-170, C-202, C-212) acepta un `resultado` soportada. Comprobado en memoria: C-121 pasa de sin_decidir a soportada.
- **Caso (b):** predicción → resultado soportada → veredicto refutada. Se aceptan los dos, así que hay dos juicios.
- **Contradice** al README («a lo sumo UN veredicto… un segundo juicio es una predicción nueva») y al reporte, que da este punto por cerrado.
- **Resolución:** tests (1) y (2) que exijan RECHAZADO, y `check` en OK sobre los 309 eventos. Mi barrido indica que pasaría: los únicos resultados con estado de cierre sobre predicciones son C-296..C-303, todos sin_decidir. La otra salida es declararlo como permitido y justificarlo.

**R2 (no bloqueante).** Una nota (resultado propuesta) reabre una cerrada sin_decidir: C-110 pasa a propuesta y sale de la lista. El README dice que solo una predicción NUEVA la retoma.
- **Resolución:** un test que exija rechazo, o corregir el README.

**R3 (no bloqueante).** Un ledger.py staged con `gate_errors` devolviendo [] abre su propia compuerta (guard_cierre.sh:164-175). Lo deduzco del código, no lo ejecuté. La afirmación de L5 es más fuerte de lo que el mecanismo da, y el riesgo no aparece en «Incertidumbre».
- **Resolución:** el test del permisivo en stage. Si da allow, declararlo, o evaluar con el ledger.py de HEAD.

**R4 (no bloqueante).** Con `git rm --cached scripts/research/ledger.py`, el hook usa el ledger.py del disco (:166-167). Esto contradice el enunciado de B3.
- **Resolución:** un test con borrado en stage y ledger.py del disco permisivo que debe dar deny.

## Verificado por mí

- Los 24 veredictos con estado vigente distinto en HEAD son acotaciones, no reversiones.
- `ledger.py open`: 0 abiertas de 64; 10 cerradas sin decidir (C-121, C-126, C-130, C-135, C-144, C-170, C-202, C-212, C-110, C-168).
- Los casos A, B y C, probados en memoria con `validate` y `current_state` sobre el registro real.
- No hay cambios staged en `src/`.

VEREDICTO: rechaza