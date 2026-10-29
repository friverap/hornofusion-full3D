El reporte no puede aprobarse todavía: una cifra no se reproduce y no tiene fuente. Todo lo demás que comprobé cuadra con los datos. WS-K13 no hace cambios numéricos (`numerico=false`, `prediccion=null`), así que no hay ningún criterio pre-registrado que juzgar. Lo que revisé son las cifras y las citas.

## Cómo lo verifiqué

- Trabajé sobre el diff staged del ciclo 3. El árbol de trabajo coincide con el staged (`git diff` vacío).
- `staged_sha()` da `302baba4…`, igual al `diff_sha` de `research/ws/WS-K13/status.json`.
- Los tests corrieron en copias dentro del scratchpad, con TMPDIR también en el scratchpad. No se escribió nada en el repositorio.

## Tabla de verificación

| Afirmación | Valor del reporte | Valor recalculado | Estado |
|---|---|---|---|
| Tests con el diff staged | 28 de 28 OK | Ran 28, OK | ok |
| Tests con `ledger.py` y hook de HEAD | 14 fallos: los nuevos o ampliados menos `test_nota_sobre_enmienda_no_la_juzga` | 14 fallos; hay 14 tests nuevos más `test_gate` ampliado, menos el excluido | ok |
| Tests con los parches del ciclo 2 | 5 fallos, los citados | 5 fallos, los mismos 5 | ok |
| sha256 de `ledger_ciclo1.patch` / `ledger_ciclo2.patch` | 48b98e37… / 15ba4390… | 48b98e37… / 15ba4390… | ok |
| `juzgada` en los parches de los ciclos 1 y 2 | :176-179 / :198-205 | 176-179 / 198-205 | ok |
| diff_sha revisados en los ciclos 1 y 2 | 106ba79b… / 351c1e5f… | no verificable sin leer reviews/ | objeción E5 |
| Eventos con ref y estado vigente distinto del suyo | 53 (prediccion 32, resultado 14, enmienda 5, hipotesis 2; veredicto 0) | 53, el mismo Counter | ok (la prosa omite las enmiendas, E2) |
| «Antes, 31 eventos con ref» movidos por notas | 31 | 24, todos veredictos (igual con HEAD, ciclo 1 y ciclo 2) | **objeción E1** |
| Ahora ningún veredicto difiere de su estado | 0 | 0 | ok |
| Ejemplo C-035 | pre-registrada → soportada | pre-registrada → soportada | ok |
| Cambios de estado vigente respecto de HEAD, sin veredictos | solo C-169 y C-194 | C-169 enmendada→refutada; C-194 enmendada→soportada | ok |
| `validate` rechaza sin_decidir sobre C-169 y C-194 | rechaza | rechaza (C-169 por absorbente y cerrada; C-194 por cerrada) | ok |
| `ledger.py check` | OK, 309 eventos, 13 workstreams | OK, 309 eventos, 13 workstreams | ok |
| `open` igual que en HEAD | diff vacío; 0 abiertas de 64; 10 sin decidir | diff vacío; 0 de 64; 10 | ok |
| sin_decidir cerradas tras en_disputa | 8 de 10 | 8 (C-110 y C-168 sin veredicto) | ok |
| C-146 en Incertidumbre | soportada → propuesta | soportada → propuesta | ok |
| `check` tarda menos de 1 s | menos de 1 s | 0.22 s | ok |
| diff_sha de WS-K12 | e3b0c442… | e3b0c442… (`61e4d25:research/ws/WS-K12/status.json`) | ok |
| Citas de origen | `r2-auditor-eaf3d.md:3`, `r2-revisor-evidencia.md:49`, `r2-revisor-refutador.md:48`, `report.md:604` | coinciden en 61e4d25 | ok |
| Citas de línea en `ledger.py` | :173-188, :191-199, :100-111, :214-225, :377, :123-126, :261-279, :298-305, :313 | coinciden | ok |
| Citas :119-122 y :132-137 | :119-122 y :132-137 | las reglas están en :120-122 y :134-137 | objeción E3 (menor) |
| `GATED` y hook | cinco rutas; tests/golden y tests/research fuera del bloqueo | coincide (diff de `guard_cierre.sh` y `ledger.py:313`) | ok |
| Sin cambios en src/ | no toca src/ | `git diff --cached --name-only` no lista src/ | ok |

## Objeciones

1. **E1 (bloqueante).** `research/ws/WS-K13/report.md`, punto 1, dice «Antes, 31 eventos con ref…». El valor recalculado es 24, todos veredictos: C-049, C-093, C-102, C-112, C-118, C-123, C-127, C-131, C-139, C-145, C-173, C-184, C-196, C-204, C-213, C-225, C-227, C-232, C-239, C-245, C-249, C-256, C-265 y C-266. Sale igual con el código de HEAD, del ciclo 1 y del ciclo 2. Ninguna otra lectura que probé da 31: con ref y estado distinto son 77; si el último evento que lo cita es un resultado, 38 (16 veredictos). La cifra no tiene fuente. **Para levantarla:** poner 24 con su comando, o el comando que produce 31.
2. **E2 (no bloqueante).** Punto 1: la prosa atribuye los 53 eventos a predicciones, hipótesis y resultados, pero su propia fuente cuenta también 5 enmiendas. **Para levantarla:** mencionar las enmiendas.
3. **E3 (no bloqueante).** Las reglas están en `ledger.py:120-122` (el reporte cita :119-122) y en `ledger.py:134-137` (el reporte cita :132-137). **Para levantarla:** ajustar las citas.
4. **E4 (no bloqueante).** La regla de las refutadas absorbentes se puede saltar a través del veredicto. `validate({tipo: prediccion, ref: C-256, …})` devuelve `[]`, aunque C-256 es el veredicto refutado de C-253 y C-253 está refutada. El registro ya tiene C-263 y C-264 con ref C-256. Por la letra del reporte, «ni hija» es cierto, porque habla de citar la afirmación. Pero la promesa del README de que quien la retome lo haga «sin --ref» no queda forzada, y «Incertidumbre» no lo dice. **Para levantarla:** declararlo en «Incertidumbre» o restringirlo en `validate`.
5. **E5 (no bloqueante).** Los diff_sha de los ciclos 1 y 2 (106ba79b…, 351c1e5f…) no son verificables: solo constan en reviews/, que no leo por la revisión ciega. **Para levantarla:** una fuente fuera de reviews/.
6. **E6 (no bloqueante).** `research/ws/WS-K13/status.json` tiene `ronda: 0` y revisores con ronda 1 del ciclo 2. Eso choca con la frase «status.json guarda la ronda del ciclo vigente». **Para levantarla:** fijar la ronda del ciclo 3 o aclarar el texto.

## Notas

- Como el cambio no es numérico, no hay predicción ni veredicto que contrastar con un criterio pre-registrado.
- Las comprobaciones de las afirmaciones de cada ciclo, en el orden de la tabla, se apoyan en código del mismo staged, el mismo registro de 309 eventos y la misma copia de los tests.

VEREDICTO: rechaza