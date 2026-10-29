## Revisión de evidencia: WS-K13, ciclo 6, ronda 1

La revisión es ciega: no leí `research/ws/WS-K13/reviews/`. No hay predicción que juzgar, porque el cambio no es numérico (`status.json`: `numerico=false`, `prediccion=null`) y WS-K13 no tiene eventos en `research/ledger.jsonl`. Reproduje con python de solo lectura sobre el registro y con `git show`/`git diff --cached` todos los números y los sha del reporte (`/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K13/report.md`).

Hay un paso que no fue de solo lectura. Para repetir los tests corrí `unittest` en copias dentro del scratchpad (`TMPDIR` en el scratchpad, sin bytecode). No escribí en el repo ni lancé `make`, `mpirun` ni simulaciones. `git status` quedó igual que al empezar.

### Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| sha de los parches del ciclo 3 (hook+ledger+tests) | 302baba4… | 302baba47975… (= diff_sha_ciclos.txt) | ok |
| sha de los parches del ciclo 4 | d86e3085… | d86e308531ff… (= diff_sha_ciclos.txt) | ok |
| (extra) parches del ciclo 5 | gated 571806d2… | 571806d2d8fa… | ok |
| `diff_sha_gated` = diff staged sobre GATED | b0cd7c65… | b0cd7c6585fc… | ok |
| `diff_sha` = diff staged sobre src y tests (fórmula de HEAD) | e648eeff… | e648eeff5f58…; el `staged_sha` de HEAD usa solo `src`,`tests` (HEAD:ledger.py:237-240) | ok |
| Veredictos con estado vigente distinto del suyo: HEAD / nuevo | 24 / 0 | 24 / 0 | ok |
| `sin_decidir` tras un veredicto `en_disputa` | 8 de 10, p. ej. C-170 | 8 con ['en_disputa'] (C-296..C-303, incluido C-301→C-170); 2 con [] (C-304→C-110, C-305→C-168) | ok |
| Tests con la herramienta staged | 39/39 | Ran 39, OK | ok |
| Tests con la herramienta de HEAD | fallan 25, pasan 14 | FAILED (failures=25) de 39 | ok |
| Tests con los parches del ciclo 5 | fallan 3 (renombrar, cierre_admite_nota_y_retoma, enmienda_solo_de_predicciones) | los mismos 3 | ok |
| `check` | 309 eventos, 13 WS, 0.3 s | ledger OK (309 eventos, 13 workstreams), 0.23 s | ok |
| Estados distintos de HEAD (sin contar veredictos) | solo C-169 y C-194 | [('C-169','enmendada','refutada'), ('C-194','enmendada','soportada')] | ok |
| Diff de `open` HEAD/nuevo | vacío | vacío | ok |
| Cadenas citadas (C-169→C-171→C-173; C-194→C-195→C-196; C-110 vía C-304; C-031→C-013; C-226→C-225; C-263→C-256; C-308→C-093; C-124→C-128) | — | coinciden tipo, estado y ref en el registro | ok |
| Referencias de línea de ledger.py (197-214, 229-235, 102-111, 125-150, 217-222, 151-161, 244-246, 282-303, 323-330, 338-339, 403) y del hook (151-177) | — | coinciden con el staged (= disco) | ok |
| Punto 3: `:120-124` | — | el bloque es :114-124 | errata (O4) |
| Tabla de ciclos: veredictos por ciclo | — | no verificable por la revisión ciega | O2 |

### Objeciones (ninguna bloqueante)

1. **O1.** `research/ws/WS-K13/tests_research.log`: el contenido es «Ran 39 … OK», pero está ignorado por `.gitignore:28 *.log` y no queda en el commit. Para levantarla, forzar el stage del log o citar solo el comando reproducible.
2. **O2.** No pude verificar la columna «Revisiones» de la tabla de ciclos (rechazos y aprobación del ciclo 4) por la regla de revisión ciega. Es historia del proceso y no sostiene ninguna conclusión. Puede confirmarlo el coordinador.
3. **O3.** Las afirmaciones de herramienta no llevan `{C-nnn}`, porque WS-K13 no registró eventos. Como el WS no es numérico, no hay criterio pre-registrado que se pueda violar. Todas traen un comando y todas se reproducen. Hay dos salidas: registrar un resultado o aceptar esta práctica de forma explícita para los WS de herramienta.
4. **O4.** Errata: el punto 3 cita `ledger.py:120-124` y el bloque es `:114-124`. «0.3 s» medido da 0.23 s, dentro del redondeo.

### Comparación justa

- Las comparaciones HEAD frente a nuevo usan el mismo `ledger.jsonl` (309 eventos) y la misma suite de tests (`tests/research/test_*.py` staged). Solo cambia la herramienta (HEAD, HEAD+parches del ciclo 5, o staged).
- El disco coincide con el índice en `ledger.py` (`cmp`). No hay cambios sin stage en las rutas de GATED.

VEREDICTO: aprueba