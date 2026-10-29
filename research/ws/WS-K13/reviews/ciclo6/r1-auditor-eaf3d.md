# WS-K13, ciclo 6, ronda 1: revisión del auditor-eaf3d

**Veredicto: RECHAZA.** Queda abierto un hallazgo MEDIO (M1). Los BAJO no bloquean.

Alcance: el diff staged (`git diff --cached`) contra `research/ws/WS-K13/report.md`. No toca `src/`, así que no aplican las comprobaciones numéricas ni MPI. No leí las revisiones de otros revisores.

## Hallazgos

### MEDIO

**M1. Una hipótesis hija puede juzgar una predicción sin veredicto.**
- **Dónde:** `scripts/research/ledger.py:145-150`, junto con `current_state` en `:209-211`.
- **Defecto:**
  - La regla «un resultado sobre una predicción solo es una nota o un cierre `sin_decidir`» mira solo `t == "resultado"`.
  - Una `hipotesis` puede nacer con cualquier estado.
  - `current_state` toma el estado de cualquier evento que cite la predicción con `--ref`.
- **Escenarios** (comprobados en memoria con `validate` y `current_state` del staged):
  - **A.** P pre-registrada, luego `add --tipo hipotesis --ref P --estado refutada`. Resultado:
    - el evento se acepta;
    - `current_state(P)` da `refutada` (permanente);
    - el veredicto legítimo posterior se rechaza («esta refutada (permanente)»).
  - **B.** P con un veredicto `en_disputa`, luego `hipotesis --estado soportada --ref P` con evidencia. Resultado:
    - el evento se acepta;
    - P queda `soportada`, cerrada sin segundo veredicto;
    - el `sin_decidir` posterior se rechaza porque P ya está cerrada.
- **Por qué importa:** es la misma clase de defecto que el ciclo 3 cerró solo para `resultado` («el segundo juicio por `resultado`»). Contradice el punto 2 del reporte y la regla del README «Una PREDICCIÓN se juzga solo con un VEREDICTO».
- **Arreglo:**
  - En `validate`, que una hipótesis nazca `propuesta`, igual que la predicción nace `pre-registrada`. Las 10 hipótesis del registro son `propuesta`, así que `check` sigue verde.
  - Otra vía: extender `:145` a `t in ("resultado", "hipotesis")`.
  - Opcional: que `current_state` de una PREDICCIÓN ignore a sus hijas `prediccion` e `hipotesis`.
  - Añadir un test con los escenarios A y B.

### BAJO

**B1. Una hija directa oculta un veredicto `en_disputa`** (`current_state`, `:209-211`).
- **Escenario:** P, luego V `en_disputa`, luego una hija P2 con `--ref P`. `current_state(P)` da `pre-registrada`, y `open` presenta como no juzgada una predicción que sí lo está.
- **Registro real:** no ocurre. Las 8 `en_disputa` solo tienen hijas `enmienda` o `sin_decidir`.
- **Arreglo:** el mismo arreglo opcional de M1.

**B2. Las aprobaciones de WS-K11 y WS-K12 abren la compuerta con un diff vacío.**
- **Estado:** los `status.json` de WS-K11 y WS-K12 están `aprobado` con `diff_sha = test_quick_sha = e3b0c442…`, el sha del diff vacío. Abren la compuerta siempre que `staged_sha` salga vacío.
- **Escenario (i), commit de arranque:** decide la gate de HEAD, que solo mira `src` y `tests`. Si el staged no tocara `src/` ni `tests/`, la compuerta pasaría por WS-K11 sin exigir WS-K13.
  - Hoy no ocurre: el staged incluye tests y da `e648…`, así que queda atado a WS-K13.
- **Escenario (ii), después del commit:** el hook usa `startswith(".claude/settings.json")` y `GATED` usa un pathspec exacto. Un `.claude/settings.json.bak` dispara la compuerta con un diff vacío y la abre.
- **Arreglo:**
  - Que `gate_errors` rechace el sha del diff vacío.
  - Que el hook derive sus prefijos de `GATED`, en vez de mantener dos listas a mano.

**B3. El escape puede perderse en silencio** (`.claude/hooks/guard_cierre.sh:181`).
- **Defecto:** el registro del escape usa el `ledger.py` del DISCO, con `capture_output` y sin revisar el código de salida.
- **Escenario:** un escape autorizado de un `git rm` de la herramienta. El `add` falla en silencio y el escape no queda en el registro.
- **Arreglo:** usar el `tool` (HEAD o índice) también para el `add`, o avisar si falla.

**B4. Un resultado refutada o fallida puede colgar de un VEREDICTO.**
- **Escenario** (comprobado): P soportada por V, luego `resultado --estado refutada --ref V`. Resultado:
  - el evento se acepta;
  - no cambia ningún estado vigente;
  - `open` no lo muestra;
  - el código lo trata como un «cierre».
- **Contexto:** los resultados `soportada` o `en_disputa` sobre veredictos son práctica histórica de precisión (C-119, C-178, C-147). Un `refutada` o `fallida` no tiene precedente.
- **Arreglo:** restringir esos dos estados en un resultado cuya ref sea un veredicto, o listarlos en `open`.

**B5. Rutas entrecomilladas fuera de la compuerta** (`guard_cierre.sh:162-167`).
- **Defecto:** `--name-only` combinado con `.split()` no ve las rutas que git entrecomilla. `core.quotePath` está activo por defecto.
- **Escenario:** un commit con solo `src/módulo.f90` no dispara la compuerta.
- **Contexto:** es anterior a este WS y hoy latente (no hay rutas no ASCII versionadas), pero ahora alcanza más rutas.
- **Arreglo:** usar `-z` y separar por `\0`.

**B6. Erratas del reporte.**
- `tests_research.log` está ignorado por `.gitignore:28` (`*.log`): existe en disco pero no entrará en el commit.
- El ciclo 5 también se reproduce: los tres parches concatenados dan `571806…`, el sha de `GATED`. El reporte dice que solo se reproducen los ciclos 3 y 4.

### No verificado

**N1.** No reproduje los conteos contrafactuales del reporte (25 fallos con la herramienta de HEAD, 3 con los parches del ciclo 5): exigen ejecutar la suite y la regla de solo lectura me lo impide. Solo leí el log: 39 OK, generado después de la última edición del código.

## Verificado como correcto

- **Shas del staged.**
  - `diff_sha` de `src` y `tests` = `e648eeff…`, igual al de `status.json`.
  - `diff_sha_gated` de las rutas de `GATED` = `b0cd7c65…`, igual al de `status.json`.
  - El disco coincide con el índice en todas las rutas de `GATED`.
- **Parches de ciclos:** los de los ciclos 3 y 4 reproducen `302baba4…` y `d86e3085…`.
- **Afirmaciones del reporte**, comprobadas en memoria contra el `ledger.py` de HEAD:
  - veredictos con estado vigente distinto del suyo: 24 con HEAD, 0 con el staged;
  - fuera de los veredictos, solo cambian C-169 (enmendada → refutada) y C-194 (enmendada → soportada);
  - `validate` da 0 errores sobre los 309 eventos;
  - la salida de `open` es idéntica a la de HEAD.
- **Referencias de línea** del reporte: correctas (`:197-214`, `:217-222`, `:229-235`, `:244-246`, `:282-303`, `:323-330`, `:338-339` y hook `:151-177`).
- **Reglas de `validate`**, probadas con eventos sintéticos:
  - cadena de enmiendas lineal;
  - un solo veredicto por cadena;
  - enmienda solo de predicciones;
  - refutadas absorbentes, también a través de enmiendas;
  - cierre restringido a nota o retoma;
  - `sin_decidir` tras `en_disputa` sí, tras un veredicto de cierre no;
  - nota a una predicción juzgada, rechazada.
- **`current_state`:** cada juicio cuenta en su posición y un veredicto conserva su propio estado.
- **Hook:**
  - orden HEAD → índice → disco, con el archivo temporal borrado en `finally`;
  - `--no-renames` (M1 del ciclo 5).
  - Los tests discriminan: con el `ledger.py` permisivo en disco o en el índice, con la herramienta renombrada, borrada o quitada del índice. Cada uno fallaría con la lógica anterior.
- **`run_tests.sh quick`:** corre `tests/research` desde la raíz con el manejo de XFAIL.
- **`check`:** exige `cierre` y los tres «aprueba» para un `fallido`.

## Orden sugerido de corrección (uno por uno)

1. M1, con B1 en el mismo arreglo: estado de nacimiento de la hipótesis y estado vigente de la predicción. Más el test.
2. B2: rechazar el sha del diff vacío y derivar los prefijos del hook de `GATED`.
3. B3: el escape usa la misma herramienta que la compuerta.
4. B4: los resultados refutada o fallida sobre un veredicto.
5. B5: `-z` en el hook.
6. B6: las erratas y el log versionable.
