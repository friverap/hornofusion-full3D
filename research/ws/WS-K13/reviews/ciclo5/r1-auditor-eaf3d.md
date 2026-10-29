**Veredicto: RECHAZA.** Quedan dos hallazgos MEDIO sin resolver.

Revisé el diff staged en solo lectura: no ejecuté tests, el hook ni `make`. Los escenarios del registro los reproduje llamando a `validate` y `current_state` sobre eventos en memoria, con el `ledger.py` staged y el de HEAD (este último cargado con `exec` desde `git show`, sin escribir archivos). Los defectos del hook los confirmé leyendo el código y la documentación de git (`man git-diff`, `man git-config`).

## Hallazgos

### MEDIO

**M1. Si la herramienta se renombra a una ruta no vigilada, la compuerta se apaga**
- **Dónde:** `.claude/hooks/guard_cierre.sh:161-166` y `:159`.
- **Defecto:**
  - `git diff --cached --name-only` aplica la detección de renombres: `diff.renames` vale `true` por defecto y no está configurado en el repo.
  - Según `man git-diff`, en un renombre solo muestra el nombre del «post-image tree», es decir, la ruta nueva.
- **Escenario de fallo:**
  1. Se hace `git mv scripts/research/ledger.py tools/ledger.py` y se commitea solo eso (`git commit -m x`).
  2. El hook ve solo `tools/ledger.py`, obtiene `gated=[]` y deja pasar el commit.
  3. En los commits siguientes, HEAD, el índice y el disco ya no tienen `scripts/research/ledger.py`. El hook llega a `:159 continue  # otro repo` y la compuerta queda apagada para siempre.
- **Por qué importa:** contradice lo que el reporte da por resuelto en M3. `test_borrar_la_herramienta_no_apaga_la_compuerta` solo prueba `git rm` combinado con `src/`.
- **Arreglo:**
  - Usar `--no-renames` en `:161`, o `--name-status` tomando las dos rutas.
  - Añadir un test en el que el único cambio staged sea `git mv … tools/ledger.py` y se espere deny.
  - El mismo arreglo cierra la variante previa: mover `src/x.f90` a `docs/` sin pasar la compuerta.

**M2. El commit de arranque no queda atado a esta aprobación como afirma el reporte**
- **Dónde:** `report.md:166-173` y `:215-218`.
- **Defecto:**
  - El reporte dice que ledger.py, el hook y la documentación quedan atados «por los parches y los sha256 de este reporte».
  - En el ciclo 5 no hay ni parche ni sha256. Los parches y los `diff_sha` guardados son de los ciclos 1 a 4, que fueron rechazados.
  - El `diff_sha` de `status.json` (85191384…, que verifiqué igual a `git diff --cached -- src tests`) solo cubre `tests/research`.
- **Escenario de fallo:**
  1. El panel aprueba.
  2. Antes del commit se modifica el `ledger.py` o el hook staged.
  3. La compuerta de HEAD sigue calculando el mismo sha sobre `src` y `tests` y deja pasar el commit.
  4. Después nadie puede comprobar que lo commiteado sea lo que se revisó. Es la misma situación de L5, repetida en el commit de arranque.
- **Arreglo:**
  - Registrar en el reporte y en `diff_sha_ciclos.txt` el sha del ciclo 5 sobre todas las rutas vigiladas (`GATED`): `571806d2d8fae89f7003a6b7d44e0e6c831c87624f8bbf2f60b3a28cedc404cc`.
  - Añadir los sha por archivo: hook `ec435cfb…`, ledger `f638597a…`.
  - Que el procedimiento de arranque del README lo verifique justo antes del commit.
  - No hay circularidad: el reporte no está en `GATED`.

### BAJO

**B1. El texto ofrece una precisión «a su cierre» que el código rechaza**
- **Dónde:** `ledger.py:130-131` (mensaje) y `README.md:50`.
- **Defecto:** en una predicción cerrada como sin_decidir, la nota sobre su cierre la rechaza `:132`. Lo reproduje: `resultado propuesta --ref C-296` da «C-296 esta cerrada sin_decidir: solo la retoma una PREDICCION nueva». Solo pasa con `--ref C-123`, el veredicto en_disputa.
- **Arreglo:** corregir el texto, o aceptar notas `propuesta` sobre un cierre cuya ref sea una predicción.

**B2. La frase «vuelve a abiertas y sale de esa lista» es falsa para las predicciones**
- **Dónde:** `README.md:58-59`.
- **Defecto:** falla en 8 de los 10 sin_decidir del registro, que son predicciones (C-121, C-126, C-130, C-135, C-144, C-170, C-202, C-212).
  - `prediccion --ref C-121` se rechaza en `:128`.
  - `prediccion --ref C-296` se acepta, pero C-121 sigue con estado vigente sin_decidir y en «cerradas sin decidir». Lo reproduje.
- **Arreglo:** limitar la frase a hipótesis y resultados.

**B3. Una nota sobre la predicción tapa su estado en_disputa**
- **Dónde:** `current_state:196-200`.
- **Defecto:** con P → veredicto en_disputa → `resultado propuesta --ref P`, P queda en «propuesta». Si la nota cita la enmienda, P conserva en_disputa. La asimetría solo afecta lo que muestran `open` y `show`.
- **Alcance:** en el registro real no hay ninguna predicción cuyo estado vigente difiera de su veredicto (salvo sin_decidir); lo verifiqué.

**B4. El hook puede debilitarse a sí mismo**
- **Defecto:** se ejecuta el `guard_cierre.sh` del disco. Un hook debilitado, en stage junto con un cambio de `src/`, se aprueba solo; es la misma clase que M1/R3 del ciclo 4. Además, la sección 3 no bloquea un Edit sobre `.claude/hooks/`.
- **Arreglo:** declararlo en «Incertidumbre», o hacer que `settings.json` ejecute la versión de HEAD y bloquear Edit sobre hooks y settings.

**B5. Tests no reproducidos y fuera de test-quick**
- No pude correr los 36 tests (los crean repos temporales y este rol es de solo lectura). Sí confirmé que son 23 + 13 = 36.
- `make test-quick` (`tests/run_tests.sh`) no corre `tests/research`, así que el `test_quick=ok` que exige la compuerta no los cubre.

## Lo verificado como correcto
- **diff_sha:** `diff_sha` = `git diff --cached -- src tests` = 85191384…. El disco es idéntico al índice.
- **Parches de los ciclos 3 y 4:** concatenados reproducen 302baba4… y d86e3085….
- **Registro real:** se revalidaron los 309 eventos con el `validate` staged, sin errores.
- **Veredictos con estado vigente distinto del propio:** 24 con HEAD y 0 con el staged.
- **Estados que cambian fuera de los veredictos:** solo C-169 (pasa de enmendada a refutada) y C-194 (de enmendada a soportada).
- **`open`:** la salida es idéntica con HEAD y con el staged.
- **Los 10 sin_decidir:** 8 son predicciones con un veredicto en_disputa previo; C-110 y C-168 son resultados sin veredicto.
- **M2 del ciclo 4 resuelto:** `veredicto --ref P` sobre una P sin_decidir y sin veredicto se rechaza en `:128`.
- **R2 del ciclo 4 resuelto:** una nota o una hipótesis sobre una hipótesis sin_decidir se rechaza; una predicción se acepta.
- **B1 del ciclo 4 resuelto:** un resultado de cierre sobre una enmienda se rechaza en `:134`.
- **Precisión pendiente O8:** `resultado propuesta --ref C-049` se acepta.
- **Hook:** decide con el `ledger.py` de HEAD, después el del índice y por último el del disco (`:156-158`). Se ejecuta desde un archivo temporal con `RESEARCH_ROOT=top`, y `root()` no depende de `__file__`.
- **Rutas vigiladas:** `GATED` coincide con los prefijos del hook.
- **Tests del hook:** `test_ledger_permisivo_staged_no_decide`, `test_borrar…` y `test_quitarla_del_indice…` distinguen el comportamiento nuevo del anterior, es decir, pasan por la razón correcta.
- **`check` de `fallido`:** exige la clave `cierre` y los tres «aprueba» de la ronda vigente.

## Orden sugerido de corrección (uno por uno)
1. **M1:** `--no-renames` en el hook, con su test de `git mv` hacia fuera.
2. **M2:** sha del ciclo 5 sobre `GATED` en el reporte, en `diff_sha_ciclos.txt` y en el procedimiento de arranque.
3. **B1 y B2:** corregir el texto del README y del mensaje de `:130`.
4. **B4:** declararlo o arreglarlo.
5. **B3:** arreglarlo o declararlo.
6. **B5:** adjuntar la corrida de `tests/research`.