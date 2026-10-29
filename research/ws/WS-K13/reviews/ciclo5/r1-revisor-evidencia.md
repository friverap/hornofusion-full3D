# WS-K13, ciclo 5, ronda 1: revisor-evidencia

**Alcance.** Revisé el reporte `research/ws/WS-K13/report.md`, el staged del índice (que coincide con el disco en ledger.py, el hook, tests/research, README y CLAUDE.md) y `research/ledger.jsonl` con 309 eventos. Por ser revisión ciega no leí `research/ws/WS-K13/reviews/`.

Todo fue en modo de solo lectura sobre el repo. Para comparar con HEAD extraje `git show HEAD:scripts/research/ledger.py` al scratchpad. Los tests de `tests/research` los corrí en copias dentro del scratchpad (staged, HEAD y HEAD con los parches del ciclo 4) y con TMPDIR en el scratchpad; usan repos git temporales y ninguno toca el repo ni lanza simulaciones.

El WS no hace cambios numéricos (`numerico=false`, sin predicción), así que no hay criterio pre-registrado que juzgar. Revisé las cifras y las citas.

## 1. Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| diff_sha = sha256(`git diff --cached -- src tests`) | = status.json | 85191384… = status.json | ok |
| Ese diff solo contiene tests/research | sí | test_guard_cierre.py, test_ledger.py | ok |
| sha de los parches del ciclo 3 | 302baba4… | 302baba4… | ok |
| sha de los parches del ciclo 4 | d86e3085… | d86e3085… | ok |
| Veredictos con estado vigente distinto del propio (HEAD / staged) | 24 / 0 | 24 / 0 | ok |
| Cambios de estado fuera de veredictos | C-169→refutada, C-194→soportada | idéntico | ok |
| sin_decidir tras un veredicto en_disputa / sin veredicto | 8 / 2 (C-110, C-168, resultados) | 8 / 2; C-110 y C-168 son `resultado` | ok |
| Resultados sobre una predicción | 8, todos sin_decidir | C-296..C-303, sin_decidir; 0 sobre una enmienda | ok |
| `check` | OK, 309 eventos, 13 WS, 0.3 s | OK, 309, 13, 0.22 s | ok (el tiempo depende de la máquina) |
| `open`: HEAD frente a staged | diff vacío | diff vacío | ok |
| Predicciones/hipótesis no raíz abiertas | ninguna | ninguna | ok |
| Tests con el diff | 36/36 | Ran 36, OK | ok |
| Tests con HEAD | fallan 22, pasan 14 | failures=22 | ok |
| Tests con el ciclo 4 | fallan 6 (lista) | failures=6, los mismos 6 | ok |
| Líneas citadas de ledger.py y del hook | :184-201, :102-111, … | coinciden | ok |
| diff_sha de WS-K12 | e3b0c442… | 61e4d25: e3b0c442… | ok |
| Citas de WS-K12 (L1/L5/L6 :3, O8 :49, R3 :48, P2 :604, tabla del ciclo 2) | — | presentes | ok |
| ledger.py, hook, README y CLAUDE.md del ciclo 5 «atados por los parches y los sha256 de este reporte» | sí | el reporte no tiene parche ni sha256 del ciclo 5 | **objeción** |

## 2. Objeciones

1. **E1 (bloqueante).** Afecta a `research/ws/WS-K13/report.md:166-174` y `:215-218`.
   - El reporte afirma que los cambios del ciclo 5 en ledger.py, el hook, el README y CLAUDE.md quedan atados «por los parches y los sha256 de este reporte».
   - No existe ningún `*_ciclo5.patch`, y el reporte no da ningún sha256 del ciclo 5. Solo están los de los ciclos 3 y 4, que son versiones anteriores, y el diff_sha 85191384…, que cubre solo tests/research.
   - Con eso no se puede comprobar que lo que se commitee sea lo que revisó este panel. Es el mismo hueco L5 que el WS dice cerrar.
   - Valores que calculé sobre el staged actual:
     - `git diff --cached HEAD -- scripts/research/ledger.py | shasum -a 256` = `f638597acd130e4ac7ddec95f7ff2c5f2b4095ae40b4f5fcef33c5215e5b6f84`
     - `git diff --cached HEAD -- .claude/hooks/guard_cierre.sh | shasum -a 256` = `ec435cfb49bfadaf59c78720577804aa612083b27d964a703eed96ee68881535`
   - Para levantarla: guardar `ledger_ciclo5.patch`, `hook_ciclo5.patch` y, si se declaran atados, los de README y CLAUDE.md, y poner sus sha256 en el reporte con nota de procedencia. La alternativa es quitar la frase y declarar que no quedan atados.
2. **E2 (no bloqueante).** En `report.md`, «Qué atendió cada ciclo», el ciclo 4 aparece como «(este ciclo)», pero el reporte es del ciclo 5. Se corrige quitando el paréntesis.
3. **E3 (no bloqueante).** El nombre `tests/research/test_guard_cierre.py:92 test_compuerta_la_decide_el_ledger_staged` dice lo contrario de lo que comprueba (que el ledger.py del disco no decida) y de la regla nueva (decide HEAD). Se corrige renombrándolo.

Todas las demás cifras y citas del reporte se reproducen exactamente.

VEREDICTO: rechaza