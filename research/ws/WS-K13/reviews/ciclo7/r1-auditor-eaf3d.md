## Revisión: auditor-eaf3d, WS-K13 ciclo 7, ronda 1

**Veredicto: RECHAZA.** Hay un hallazgo MEDIO bloqueante: una enmienda encadenada se acepta sin criterio.

Alcance: el diff staged de `scripts/research/ledger.py`, `.claude/hooks/guard_cierre.sh`, `tests/run_tests.sh`, `tests/research/*`, `research/README.md` y `CLAUDE.md`, contrastado con `research/ws/WS-K13/report.md`. Todo fue en modo de solo lectura: `ledger.py check`/`open` y escenarios de `validate`/`current_state` en memoria. No corrí la suite de tests.

### Hallazgos

#### MEDIO

**M1. Una enmienda encadenada se acepta sin criterio** (`scripts/research/ledger.py:120`, bloqueante)

- **Defecto.** La regla «la enmienda de una predicción trae el criterio NUEVO» mira `ref.tipo == 'prediccion'`. Desde WS-K13 la segunda enmienda tiene que ir sobre la última (`:104`), así que su `ref` es una enmienda y la regla no se aplica.
- **Escenario (reproducido con `validate` del staged):**
  1. P (criterio c0).
  2. E1 `--ref P` (criterio c1).
  3. E2 `--ref E1 --motivo m`, sin `--criterio`: pasa.
  4. Veredicto `--ref E2`: pasa.

  El veredicto juzga una cadena cuyo «criterio vigente» no existe, lo que rompe el pre-registro y contradice el README staged («Las enmiendas solo cambian el criterio de una PREDICCIÓN»; «…la ÚLTIMA enmienda (el criterio vigente)»).
- **El test lo fija.** `test_cadena_de_enmiendas_juzgada` (`tests/research/test_ledger.py:152`) registra e2 sin `--criterio` y espera éxito.
- **Arreglo.** Exigir el criterio cuando `raiz_enmienda(ref).tipo == 'prediccion'`, añadir `--criterio` a e2 en ese test y un caso negativo. El registro real no tiene enmiendas de enmiendas, así que `check` sigue pasando.

#### BAJO (no bloqueantes)

- **B1** (`ledger.py:214`; anterior a WS-K13). Una nota (`resultado` propuesta `--ref P`) sobre una predicción sin juzgar le pone el estado vigente `propuesta`; con P → E1 → nota se pierde `enmendada`. Por la misma regla, una hipótesis `sin_decidir` retomada directamente queda en `pre-registrada` para siempre. Es cosmético: no afecta a la compuerta. Arreglo: que una nota no cambie el estado de su ref, o declararlo.
- **B2** (`tests/run_tests.sh:291`). `test-quick` corre ahora `tests/research`, que crea unos 41 repos con `mkdtemp()` sin limpieza: se acumulan en `$TMPDIR` en cada commit. Arreglo: `addCleanup(shutil.rmtree, self.d, True)`.
- **B3** (errata del reporte). Las citas de líneas de `ledger.py` son las del ciclo 6, desplazadas entre 2 y 4 líneas en el staged:
  - `current_state` está en 199-218, no en 197-214.
  - `GATED` está en 342-343, no en 338-339.
  - `juzgada` se usa en `:407`, no en `:403`.

  Además, «ciclos 1 a 5» omite que `diff_sha_ciclos.txt` trae el ciclo 6, que también se reproduce (b0cd7c65…).

### Lo verificado como correcto

- **Shas del staged.**
  - `diff_sha` = e9e5211c…: es el sha de `git diff --cached -- src tests` (fórmula de HEAD).
  - `diff_sha_gated` = f1b8e6ba…: es el sha sobre todas las rutas de `GATED`.
  - No hay cambios sin stage.
- **Parches por ciclo.** Concatenados, reproducen 302baba4 (ciclo 3), d86e3085 (ciclo 4), 571806d2 (ciclo 5) y b0cd7c65 (ciclo 6).
- **Registro real.**
  - `ledger.py check`: OK con 309 eventos.
  - `open`: la salida es idéntica con HEAD y con el staged.
- **Conteos del reporte.**
  - Veredictos con estado vigente distinto del suyo: 24 con HEAD y 0 con el staged.
  - Solo cambian C-169 (enmendada → refutada) y C-194 (enmendada → soportada).
  - Las 10 hipótesis son `propuesta` y no hay hijas de predicciones.
  - De los `sin_decidir`, 8 llegan tras un `en_disputa` y 2 sin veredicto.
- **M1 y B1 del ciclo 6, arreglados.**
  - Una hipótesis refutada o soportada al nacer se rechaza (`validate:97`).
  - Con P en `en_disputa`, colgarle una hija predicción o hipótesis la deja en `en_disputa` (`:212`).
- **Escenarios en memoria.** Se comportan como dice el README:
  - un cierre `sin_decidir` impide un segundo `sin_decidir` y un veredicto posterior;
  - un cierre solo admite una nota o una retoma;
  - las refutadas son absorbentes incluso a través de una enmienda;
  - una predicción cerrada no admite notas.
- **Hook.**
  - Decide el `ledger.py` de HEAD; si no, el del índice; si no, el del disco.
  - Lee las rutas con `--no-renames -z` y su lista de rutas es la misma que `GATED`.
  - Lo cubren los tests de disco permisivo, índice permisivo, `git mv`, `git rm`, `rm --cached` y ruta no ASCII.
  - El `ledger.py` de HEAD corre desde un archivo temporal con `RESEARCH_ROOT=top`, y su `staged_sha` usa `cwd=root()`.
- **Tests y `run_tests.sh`.**
  - `run_script research` corre desde la raíz y cuenta el fallo.
  - Los tests aíslan el registro con `RESEARCH_ROOT` en un directorio temporal.
  - `tests_research.txt`: Ran 41, OK.
- **Commit de arranque.** Es coherente: el `gate` de HEAD comparará contra e9e5211c. El `test_quick_sha` debe fijarse con el `ledger.py` de HEAD, como documenta el README.
- **Límites declarados** (B2-B4 del ciclo 6, el escape y el hook que se certifica a sí mismo): los confirmé por lectura. No los vuelvo a objetar.

### Orden sugerido de corrección

1. M1: `ledger.py:120` más el test.
2. B2: limpieza de los directorios temporales en los tests.
3. B3: citas de líneas del reporte.
4. B1: decidir la regla o declararla.
