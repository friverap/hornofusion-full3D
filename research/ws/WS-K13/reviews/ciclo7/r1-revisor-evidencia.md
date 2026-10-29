# WS-K13, ciclo 7, ronda 1: revisor-evidencia

Solo hice lecturas. No corrí `make`, `mpirun` ni el simulador.

- **Herramienta en copias temporales.** Puse tres versiones del ledger.py y del hook en el scratchpad de la sesión: la staged, la de HEAD y la del ciclo 6 (HEAD + `*_ciclo6.patch`). Con `TMPDIR` en el scratchpad.
- **Tests.** Corrí los tests de `tests/research`. Son unittest de la herramienta y solo escriben en repos git temporales.
- **Registro.** Lo leí con `RESEARCH_ROOT` apuntando al repo, sin escribir. `research/ledger.jsonl` no tiene cambios ni en el staged ni en el disco.

**Alcance.** El WS no cambia nada numérico (`status.json`: `numerico=false`, `prediccion=null`) y el registro no tiene eventos de WS-K13. Por eso no hay criterio pre-registrado que juzgar: el paso 3 del cierre no aplica. Lo que reviso es si cada número sale de los datos.

## 1. Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| sha de los parches del ciclo 3 (hook+ledger+tests) | 302baba4… | 302baba47975… = ciclo3 en `diff_sha_ciclos.txt` | ok |
| sha de los parches del ciclo 4 | d86e3085… | d86e308531ff… = ciclo4 | ok |
| sha de los parches del ciclo 5 (todas las rutas de GATED) | 571806d2… | 571806d2d8fa… = ciclo5 | ok |
| (extra) sha de los parches del ciclo 6 | — | b0cd7c6585fc… = `diff_sha_gated` del ciclo 6 | ok |
| `diff_sha_gated` = diff staged de todas las rutas de GATED | f1b8e6ba… (status.json) | f1b8e6ba1f42… | ok |
| `diff_sha` = diff staged de src y tests (fórmula de HEAD: `staged_sha` en HEAD:ledger.py:237-240) | e9e5211c… | e9e5211c92e5… | ok |
| Disco = índice en las rutas de GATED | — | `git status`: solo «M » staged, nada sin stage | ok |
| Veredictos con estado vigente distinto del suyo (HEAD → staged) | 24 → 0 | 24 → 0 (ciclo 6: 0) | ok |
| Estados de las hipótesis; hijas de predicciones | {propuesta: 10}; [] | Counter({'propuesta': 10}); [] | ok |
| `sin_decidir`: 8 tras `en_disputa` y 2 sin veredicto; ejemplo C-170 | 8 / 2 | 8 (C-121, C-126, C-130, C-135, C-144, C-170, C-202, C-212) / 2 (C-110, C-168) | ok |
| Estados que cambian (sin contar veredictos) | C-169 enmendada→refutada; C-194 enmendada→soportada | igual. Entre el ciclo 6 y el staged: ninguno | ok |
| `open` de HEAD frente al staged | diff vacío | diff vacío | ok |
| `check` sobre el registro real | OK, 309 eventos, 13 WS | `ledger OK (309 eventos, 13 workstreams)` | ok |
| Tiempo de `check` | 0.3 s | 0.068 s | objeción E2 (no bloquea) |
| Suite staged | 41/41 OK | Ran 41, OK | ok |
| Herramienta de HEAD + tests staged | 27 fallan, 14 pasan | FAILED (failures=27) de 41 | ok |
| Herramienta del ciclo 6 + tests staged | 2 fallan: `test_hija_no_juzga_a_una_prediccion`, `test_ruta_no_ascii_deny` | exactamente esos 2 | ok |
| `tests_research.txt` | Ran 41, OK; versionado | 41 nombres = 41 `def test_` staged; 41 «ok»; 0 FAIL; `git check-ignore` rc=1 (no lo ignora) | ok |
| N1 del ciclo 6: HEAD + tests del ciclo 6 | 25 de 39 | FAILED (failures=25), Ran 39 | ok |
| N1 del ciclo 6: herramienta del ciclo 5 + tests del ciclo 6 | 3 | FAILED (failures=3) | ok |
| Escenario A con la herramienta del ciclo 6 | sin error; cs(P)=refutada; veredicto rechazado «permanente» | igual. Staged: rechazado «una hipotesis nace 'propuesta'» | ok |
| Escenario B con la herramienta del ciclo 6 | aceptada; cs(P)=soportada; `sin_decidir` rechazado | igual. Staged: rechazada; cs(P)=en_disputa | ok |
| Escenario B1 con la herramienta del ciclo 6 | cs(P)=pre-registrada | igual. Staged: en_disputa | ok |
| Escenario B4 (declarado límite) | aceptado | aceptado también en el staged; cs(V)=soportada | ok |
| WS-K11 y WS-K12 aprobados con el sha de un diff vacío | e3b0c442… | los dos status.json: aprobado, e3b0c44298fc… | ok |
| Bug L1 en HEAD | lista con el estado propio y repetida | HEAD:ledger.py:207-209 confirma las dos cosas | ok |
| Citas de WS-K12 (L1, L5 y L6 en r2-auditor:3; O8 en r2-evidencia:49; R3 en r2-refutador:48; 61e4d25:report.md:604) | — | existen y dicen lo citado | ok |
| Ids citados (C-169/171/173, C-194/195/196, C-110/304, C-296, C-124/128, C-031/013, C-226/225, C-263/256, C-308/093) | tipos y refs | coinciden con `ledger.jsonl` | ok |
| `make test-quick` corre `tests/research` | sí | `tests/run_tests.sh` staged: `run_script "research" $PY -m unittest discover -s tests/research -q`; `run_script` y `PY` están definidos. No lo ejecuté | ok por lectura |
| Referencias de línea de ledger.py en «Cambios» | :197-214, … | son las del ciclo 6; en el staged están desplazadas 2-4 líneas | objeción E1 (no bloquea) |
| Columna «Revisiones» de la tabla de ciclos | — | no verificable por la revisión ciega | objeción E3 (no bloquea) |

## 2. Objeciones

1. **E1 (no bloquea).** Referencias de línea que no son las del diff revisado.
   - `research/ws/WS-K13/report.md`, sección «Cambios»: las líneas citadas son de la versión del ciclo 6, no del staged.
   - Ejemplos del staged: `current_state` está en `scripts/research/ledger.py:199-218` (el reporte dice 197-214), `GATED` en `:342-343` (dice 338-339) y el uso de `juzgada` en `gate_errors` en `:407` (dice 403).
   - Además, el código nuevo de este ciclo no lleva referencia: `:97-98` (la hipótesis nace `propuesta`) y `:212-213` (una hija no juzga a una predicción).
   - Para levantarla: recalcular las líneas con `git show :scripts/research/ledger.py | cat -n` y citar las del ciclo 7.
2. **E2 (no bloquea).** `report.md`, «Evidencia», nota de `check`: el reporte dice 0.3 s y yo medí 0.068 s. Para levantarla: poner el valor medido o «< 0.3 s».
3. **E3 (no bloquea).** No verifiqué la columna «Revisiones» de la tabla de ciclos porque la revisión es ciega. Para levantarla: que alguien no ciego la compare con la línea VEREDICTO de cada archivo en `research/ws/WS-K13/reviews/ciclo{1..6}/`.

**Comparación justa.**
- Los tres conteos de la suite usan los MISMOS tests staged y solo cambian la herramienta (HEAD, ciclo 6 o staged).
- Los conteos de N1 usan los tests del ciclo 6 con las herramientas de HEAD y del ciclo 5.
- Los estados del registro se calculan sobre el mismo `ledger.jsonl` (309 eventos, igual a HEAD) con cada versión del módulo.

Todos los números del reporte, salvo el tiempo de `check`, coinciden exactamente con lo recalculado. No hay criterio pre-registrado que reinterpretar.

VEREDICTO: aprueba