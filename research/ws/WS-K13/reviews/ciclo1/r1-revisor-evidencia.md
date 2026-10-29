# Revisión de evidencia: WS-K13, ronda 1

**Veredicto: rechazo.** Todas las cifras del reporte se reproducen. El rechazo se debe a un hueco en la regla que el propio WS introduce (E1, bloqueante): una predicción refutada todavía se puede reabrir.

## Alcance y método

- Solo lectura. No usé `make`, `mpirun` ni binarios.
- Los tests de `tests/research` corrieron con `TMPDIR` en el scratchpad. Escriben únicamente en directorios temporales.
- Para comparar con HEAD extraje `HEAD:ledger.py` con `git show` al scratchpad.
- WS-K13 no tiene cambio numérico ni predicción pre-registrada (`status.json`: `numerico: false`, `prediccion: null`). Por eso no hay criterio contra el que juzgar un veredicto y la revisión se centra en las afirmaciones del reporte y en el comportamiento del código.

## 1. Tabla

| Afirmación | Valor del reporte | Valor recalculado | Estado |
|---|---|---|---|
| Tests de `tests/research` con el diff | Ran 18, OK | Ran 18, OK | ok |
| Tests nuevos contra ledger.py y hook de HEAD | FAILED failures=5, los 5 citados | FAILED failures=5: herramienta_del_registro_deny, test_gate, avisa_madre, sin_decidir_por_estado_vigente, juzgada_por_su_enmienda | ok |
| `ledger.py check` | OK, 309 eventos, 13 WS | OK (309 eventos, 13 workstreams); `wc -l` = 309 | ok |
| Cambios de estado vigente HEAD→nuevo | solo C-169 y C-194 | C-169 enmendada→refutada; C-194 enmendada→soportada; ningún otro | ok |
| `validate` rechaza `sin_decidir` sobre C-169 y C-194 | «ya esta cerrada (refutada\|soportada)» | mismo mensaje en ambos | ok |
| `open`: abiertas | 0 de 64 | 0 de 64 | ok |
| `open`: cerradas sin decidir | 10 (C-121 … C-168) | 10, misma lista y orden | ok |
| `diff` de `open` HEAD vs nuevo | idéntico «salvo la línea del nuevo WS-K13» | diff vacío: la línea de WS-K13 sale en ambos | objeción E2 (no bloq.) |
| `diff_sha` de WS-K12 | e3b0c442… (diff vacío) | e3b0c44298fc… | ok |
| `diff_sha` de WS-K13 = staged | (status.json) 106ba79b… | `staged_sha()` = 106ba79b… | ok |
| Líneas citadas de ledger.py | :112, :158-173, :176-179, :216-219, :226-229, :232-233, :259 | coinciden | ok |
| `juzgada`: «veredicto directo o sobre una de sus enmiendas»; ya no admite otra enmienda | regla cerrada | falla con enmiendas encadenadas (ver E1) | **objeción E1 (bloq.)** |
| C-057, C-079, C-085, C-089 no concluyentes | no concluyentes | fallida (no concluyente) vía C-279, C-281, C-283, C-284 | ok |
| `check` < 1 s | < 1 s | 0.23 s (`open` 0.20 s) | ok |
| Origen: «tres hallazgos BAJO, todos de herramienta» | L1, L5, límite de current_state | Los BAJO del auditor fueron L1, L5 y L6 (L6 resuelto en 61e4d25); siguen pendientes O8 y R3 | objeción E3 (no bloq.) |

## 2. Objeciones

**E1 (bloqueante).** `scripts/research/ledger.py:176-179`: `juzgada()` revisa un solo nivel de enmiendas. En cambio:

- `current_state` (`:169-170`) recorre las enmiendas de forma recursiva;
- `validate` del veredicto (`:96-102`, bucle `while raiz.get("tipo") == "enmienda"`) acepta cadenas de enmiendas.

Lo reproduje en memoria, sin escribir en el registro, con la cadena P ← E1 ← E2 ← V(refutada):

- `current_state(P) = refutada`, pero `juzgada(P) = False`;
- una enmienda nueva sobre P se acepta (`[]`) y P vuelve a «enmendada»;
- después, un `resultado sin_decidir` sobre P también se acepta (`[]`).

Resultado: una predicción refutada se reabre y se cierra como «sin decidir». Esto contradice `research/README.md:44-46` («ya no admite otra enmienda ni `sin_decidir`») y el punto 2 de «Cambios».

En el registro real el hueco está latente: no hay enmiendas sobre enmiendas (C-122, C-171, C-172, C-195 y C-203 apuntan todas a una predicción). Aun así es la regla misma que este WS entrega.

Para levantarla hay dos opciones:
- que `juzgada()` recorra las enmiendas de forma transitiva (o se derive del estado vigente);
- o que `validate` rechace una enmienda cuya `ref` sea otra enmienda.

En ambos casos hace falta un test P←E1←E2←V que falle con el código actual.

**E2 (no bloqueante).** Reporte, «Evidencia», último punto. El comando `diff <(python3 HEAD:ledger.py open) <(python3 scripts/research/ledger.py open)` sale vacío, porque las dos versiones leen `research/ws/*` vía `git rev-parse` y ven la misma línea de WS-K13. Hay que escribir «idéntica (diff vacío)».

**E3 (no bloqueante).** La sección «Origen» atribuye al panel tres BAJO de herramienta, pero `research/ws/WS-K12/reviews/ciclo2/r2-auditor-eaf3d.md:3` lista L1, L5 y L6:

- L6 quedó resuelto en el commit 61e4d25 (la tabla «Ciclo 2, ronda 1» está en `report.md:741`).
- El límite de `current_state` viene del report de WS-K12, no de un BAJO del panel.

Además el panel dejó otros dos pendientes que el reporte no menciona:

- **O8**, no bloqueante: `r2-revisor-evidencia.md:49`. `61e4d25:research/ws/WS-K12/report.md:604` sigue diciendo «la misma lectura que B4 refuta».
- **R3**: `r2-revisor-refutador.md:48`. Es una corrida que separa material de z_tip.

El usuario pidió abordar «los pendientes que dejó el panel». Hay que corregir «Origen» y declarar O8 y R3 como fuera del alcance, con el motivo.

## Lo verificado sin objeción

- Los 5 tests nuevos o ampliados fallan con HEAD y pasan con el diff.
- `check` revalida cada evento contra los anteriores con el `current_state` nuevo, y ningún cierre histórico se invalida.
- GATED y el hook son coherentes:
  - `tests/research` entra en `diff_sha` pero queda fuera del bloqueo del hook;
  - un workstream `fallido` no pasa `gate`, porque `gate` exige `aprobado`;
  - `WS_ESTADOS` incluye `fallido`.

VEREDICTO: rechaza