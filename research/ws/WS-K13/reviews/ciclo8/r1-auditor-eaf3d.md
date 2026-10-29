## Revisión: auditor-eaf3d, WS-K13 ciclo 8, ronda 1

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Quedan dos erratas BAJO del reporte y un contrafactual que no verifiqué; ninguno bloquea.

**Alcance.** Revisé el diff staged de:
- `scripts/research/ledger.py`
- `.claude/hooks/guard_cierre.sh`
- `tests/research/*` y `tests/run_tests.sh`
- `research/README.md` y `CLAUDE.md`

Lo contrasté con `research/ws/WS-K13/report.md`. Trabajé en modo de solo lectura:
- importé `ledger.py` con `python3 -B` (sin escribir `.pyc`);
- reconstruí en memoria la herramienta de HEAD y la del ciclo 7;
- corrí escenarios de `validate` y `current_state` sobre listas sintéticas.

No ejecuté la suite de tests, porque escribe repos temporales.

### Hallazgos

#### ALTO
Ninguno.

#### MEDIO
Ninguno.

#### BAJO (no bloqueantes)

- **B1. Citas de línea desfasadas** (errata, `report.md`, «Cambios»).
  - **Defecto.** El encabezado dice «líneas del `ledger.py` staged del ciclo 7», pero lo que se revisa es el ciclo 8. El arreglo de B1 añade la línea `:213`, y todo lo posterior queda desplazado +1:
    - `raiz_enmienda` está en `:222-227` (se cita `:221-226`);
    - en `open`, «hija juzgada» está en `:288-290`, las NO raíz abiertas en `:292-295`, «cerradas sin decidir» en `:301-305` y la clave `cierre` en `:308`;
    - `check` está en `:328-335`.
  - **Lo que está bien.** Las citas anteriores a `:213` (`:103-163`, `:120`, `:199-219`) y las de `GATED`, `juzgada` y `gate_errors` son correctas.
  - **Arreglo.** Poner «ciclo 8» en el encabezado y actualizar esas citas.
- **B2. El ciclo 7 falta en la reproducción por sha** (errata).
  - **Defecto.** El reporte habla de «los ciclos 1 a 6» y de reproducir «los ciclos 3 a 6». Pero `diff_sha_ciclos.txt` ya trae el ciclo 7, y `cat hook_ciclo7.patch ledger_ciclo7.patch tests_ciclo7.patch | shasum -a 256` da `f1b8e6ba…`, su `diff_sha_gated` (verificado).
  - **Arreglo.** Extender el texto a los ciclos 1 a 7 y añadir el ciclo 7 a la fuente.
- **N1. Contrafactual sin verificar.** No verifiqué «con HEAD fallan 28 y pasan 14».
  - **Lo que sí verifiqué.** En memoria, los dos tests que separan el ciclo 7 del 8 (ver abajo). Además, `tests_research.txt` dice «Ran 42, OK» y el staged tiene exactamente 42 `def test_`.
  - **Arreglo.** Que alguien con permiso de ejecutar repita el comando de la fuente y adjunte la salida.

### Lo verificado como correcto

**Shas del staged**
- `git diff --cached -- src tests | shasum -a 256` da `e10f7514…`, igual al `diff_sha` de `status.json`.
- El sha sobre todas las rutas de `GATED` da `221d17b0…`, igual al `diff_sha_gated`.
- No hay cambios sin stage en los archivos vigilados.

**Parches por ciclo.** Concatenados, reproducen 302baba4 (ciclo 3), d86e3085 (4), 571806d2 (5), b0cd7c65 (6) y f1b8e6ba (7).

**Del ciclo 7 al 8.** El diff entre el staged y `ledger_ciclo7.patch` solo contiene `:120` (M1) y `:212-214` (B1), más el desplazamiento de los hunks.

**M1 del ciclo 7 (arreglado)**
- Escenario: P, luego E1 `--ref P --criterio c2`, luego E2 `--ref E1` sin criterio.
- Con el staged se rechaza; con el ciclo 7 reconstruido se aceptaba.
- En `test_cadena_de_enmiendas_juzgada`, el caso negativo solo difiere del positivo en `--criterio`, así que falla por la razón correcta.
- En el registro real no hay enmiendas de enmiendas ni enmiendas sin criterio.

**B1 del ciclo 7 (arreglado)**
- Escenario: P, luego una enmienda, luego una nota `--ref P`.
- Con el staged, `current_state(P)` da `enmendada`; con el ciclo 7 daba `propuesta`.
- El salto solo aplica a hijas y notas (`resultado` propuesta) sobre una PREDICCIÓN. `sin_decidir --ref P` sigue cerrando, y una nota sobre P ya juzgada sigue rechazada (`:151`).
- El registro real tiene 0 notas sobre predicciones, así que el cambio no altera ningún estado vigente.

**B2 del ciclo 7 (arreglado).** Hay `addCleanup(shutil.rmtree, self.d, True)` en ambos `setUp`.

**Registro real**
- `validate` del staged revalida los 309 eventos sin ningún error.
- Veredictos con estado vigente distinto del suyo: 24 con HEAD y 0 con el staged.
- Solo cambian C-169 (enmendada → refutada) y C-194 (enmendada → soportada).
- La salida de `cmd_open` es idéntica con HEAD y con el staged.

**Escenarios en memoria**
- La cadena es lineal: el veredicto sobre un eslabón ya enmendado se rechaza.
- Una nota sobre P o sobre su última enmienda tras un `en_disputa` se rechaza.
- `sin_decidir` sobre una enmienda se rechaza.
- Una predicción cerrada no admite una hija colgada de su enmienda.
- Una hipótesis puede colgarse de un veredicto `en_disputa`.

**Hook**
- La herramienta se toma de HEAD; si HEAD no la tiene, del índice (`git show :LP`); si tampoco, del disco.
- Lee las rutas con `--no-renames -z`, y su lista de prefijos coincide con `GATED`.
- Ejecuta la herramienta desde un archivo temporal con `RESEARCH_ROOT=top`.
- Si la herramienta de HEAD falla, la compuerta deniega.

**`run_tests.sh`.** `run_script research` cuenta el fallo con `note_fail`, y `script:research` no está en `xfail.list`.

**Commit de arranque.** Es coherente: el `gate` de HEAD comparará contra `e10f7514`, y el README documenta que `test_quick` se fija con el `ledger.py` de HEAD.

**Límites declarados.** No los vuelvo a objetar:
- el hook que se certifica a sí mismo;
- el escape con el `ledger.py` del disco;
- B4 (un `resultado` sobre un veredicto);
- las aprobaciones con el sha del diff vacío;
- la compuerta numérica con `en_disputa`.

`settings.local.json` lo ignora el gitignore global, así que entra en el mismo límite del disco.

### Orden sugerido de corrección
1. B1: actualizar las citas de línea al ciclo 8.
2. B2: añadir el ciclo 7 a la reproducción por sha.
3. N1: adjuntar la salida del contrafactual con HEAD (opcional).
