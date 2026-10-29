## Revisión de evidencia de WS-K13, ciclo 4, ronda 1

Revisé `research/ws/WS-K13/report.md` contra el diff staged. El `diff_sha` vigente es `d86e3085…`. Lo recalculé con `git diff --cached -- <GATED> | shasum -a 256` y coincide con `research/ws/WS-K13/status.json`. No hay cambios sin stage en las rutas de la compuerta.

**Qué se juzga.** Es un cambio de herramienta sin efecto numérico (`numerico=false`, `prediccion=null`) y no registra eventos de WS-K13 en el registro. Por eso no hay criterio pre-registrado que juzgar: lo que reviso es que cada número salga de los datos.

**Cómo verifiqué.**
- Los tests los corrí en copias aisladas dentro del scratchpad, con `TMPDIR` también en el scratchpad, en tres configuraciones: ledger y hook staged; ledger y hook de HEAD; HEAD más los parches del ciclo 3. Ninguna corrida escribió en el repo: después de revisar, el registro sigue con 309 líneas y el `diff_sha` no cambió.
- De las revisiones previas solo leí la línea del veredicto, para respetar la revisión ciega.

### Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Veredictos con estado vigente distinto del propio: HEAD / staged | 24 / 0 | 24 / 0 (C-049 … C-266) | ok |
| Tests con el diff | 30 de 30 OK | Ran 30, OK | ok |
| Fallos con ledger y hook de HEAD | 16: todos los nuevos o ampliados menos `test_nota_sobre_enmienda_no_la_juzga` | 16. Hay 16 tests nuevos más `test_gate` ampliado; falla todo salvo ese test | ok |
| Fallos con los parches del ciclo 3 | 4 (los citados) | 4: `juicio_por_enmienda…`, `sin_decidir_no_tras…`, `compuerta_la_decide…`, `hook_y_workflow_deny` | ok |
| Ampliaciones respecto de los tests del ciclo 3 | nota y segundo juicio; `agents/` y `settings.json` | confirmado con un diff contra HEAD + `tests_ciclo3.patch` | ok |
| `ledger.py check` | OK, 309 eventos, 13 workstreams | idéntico | ok |
| Estados que cambian fuera de los veredictos | C-169 y C-194 | C-169 (enmendada → refutada), C-194 (enmendada → soportada) | ok |
| Eventos con ref cuyo estado vigente difiere del propio | 53 = 32 pred + 14 res + 5 enm + 2 hip; 0 veredictos | idéntico; C-035 pasa de pre-registrada a soportada | ok |
| Salida de `open` HEAD vs staged | diff vacío; 0 de 64; 10 cerradas sin decidir; 0 hijas no raíz | diff vacío, rc=0; mismos valores | ok |
| `sin_decidir` puestos después de un `en_disputa` | 8 de 10 | 8 (C-121, C-126, C-130, C-135, C-144, C-170, C-202, C-212); C-110 y C-168 sin veredicto | ok, sin fuente (O1) |
| Coste de `check` | < 1 s | 0.26 s | ok, sin fuente (O2) |
| Cadenas C-169→C-171→C-173 y C-194→C-195→C-196 | según texto | confirmadas en el registro | ok |
| Ejemplos de precisión o retoma: C-308→C-093, C-226→C-225, C-263/C-264→C-256, C-031→C-013 | según texto | refs confirmadas; C-093, C-225 y C-256 son veredictos | ok |
| `diff_sha` de WS-K12 = diff vacío | e3b0c442… | `61e4d25:status.json` = e3b0c442… | ok |
| Citas a WS-K12: `r2-auditor:3`, `r2-evidencia:49`, `r2-refutador:48`, `61e4d25:report.md:604`, tabla «Ciclo 2, ronda 1» | según texto | todas existen y dicen lo citado (la tabla está en la línea 741) | ok |
| Parches del ciclo 3 frente al `diff_sha` del ciclo 3 | tabla de ciclos | hook+ledger+tests concatenados = 302baba4…, coincide | ok (O3) |
| Ciclos 1 a 3: los tres revisores rechazan | sí | 9 de 9 rechazan | ok |
| Rangos de líneas en ledger.py y en el hook | varios | todos coinciden, salvo `:100-111`, que debe ser `:101-111` | O5 |
| E1–E6 corregidas | sí | no verificable sin leer las revisiones previas | O4 |

### Objeciones (ninguna bloqueante)

1. **O1**, `report.md` (Cambios, punto 5), «8 de los 10»: el número es correcto pero no tiene nota de procedencia. Para levantarla, añadir el comando.
2. **O2**, `report.md` (Incertidumbre), «check < 1 s»: no tiene comando. El valor medido es 0.26 s. Para levantarla, añadir `time python3 scripts/research/ledger.py check`.
3. **O3**, la nota `shasum -a 256 research/ws/WS-K13/*.patch` no muestra los hashes. Lo comprobable es que los tres parches del ciclo 3 concatenados reproducen 302baba4…; conviene citarlo así. Los ciclos 1 y 2 no se pueden reproducir porque no se guardaron sus parches de tests.
4. **O4**, «E1–E6 corregidas»: no lo pude verificar porque la revisión ciega no me deja leer las revisiones previas. Para levantarla basta un mapa E→línea.
5. **O5**, `report.md`, regla 2 «`:100-111`»: debe decir `scripts/research/ledger.py:101-111`.

Todos los números del reporte se reproducen exactamente desde el registro, el código staged, HEAD y los parches. No hay predicción ni criterio pre-registrado que juzgar, porque el cambio no es numérico. Las comparaciones se hicieron con el mismo registro de 309 eventos y los mismos tests, y solo cambia el código que se prueba.

VEREDICTO: aprueba