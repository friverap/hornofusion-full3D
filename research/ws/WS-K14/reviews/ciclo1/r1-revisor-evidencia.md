# WS-K14, ronda 1: revisión de evidencia

**Alcance.** WS-K14 no es numérico (`numerico: false`, `prediccion: null` en `research/ws/WS-K14/status.json`), así que no hay criterio pre-registrado contra el cual juzgarlo. Lo que comprobé:

- que los resultados C-314, C-315 y C-316 se reproducen desde sus rutas y comandos;
- que las cifras y las citas del reporte son correctas;
- que el control (settings.json viejo) es una comparación justa: mismo repo temporal y misma entrada, y solo cambia el `settings.json`.

**Cómo lo verifiqué.**

- Re-ejecuté `python3 -m unittest discover -s tests/research`. Los tests escriben solo en repos temporales; no son corridas del simulador.
- Reproduje el control en un repo temporal propio, sin sobrescribir `.claude/settings.json` del proyecto.
- Lo demás fue lectura con `git diff --cached`, `ledger.py show/check` y python sobre `ledger.jsonl` y `status.json`.

## 1. Tabla

| Afirmación | Reporte | Recalculado | Resultado |
|---|---|---|---|
| Tests de `tests/research` {C-314, C-315} | 45 tests OK | Ran 45 tests, OK (28 en test_ledger + 17 en test_guard_cierre) | ok |
| `test_gate_exige_veredicto_firme` | ok | ok en `tests_research.txt` y en la re-ejecución | ok |
| `FIRMES` / mensaje de error {C-314} | `("soportada","refutada")`; «la prediccion C-nnn tiene veredicto 'en_disputa' (se exige soportada o refutada)» | `scripts/research/ledger.py:40` y `:411-416`, idénticos | ok |
| en_disputa y fallida no pasan; refutada y soportada sí | 4 casos | los 4 casos están en el test y pasan | ok (O1: falta el caso con enmienda) |
| `test_settings_corre_el_hook_de_HEAD` con settings nuevo {C-315} | commit deny, Write ledger deny, git status allow | deny / deny / allow (reproducido) | ok |
| Control con el settings.json de HEAD 4850a0b | FALLA, `'allow' != 'deny'` | allow / allow / allow (reproducido); `control_settings_HEAD_viejo.txt` dice FAILED (failures=1), `'allow' != 'deny'` | ok |
| Respaldo sin hook en HEAD | test ok | ok | ok |
| settings.json de la raíz, fuera del repo | cambiado, con `/hornofusion-full3D` | `~/Horno/.claude/settings.json` usa `d="${CLAUDE_PROJECT_DIR}/hornofusion-full3D"`; con CLAUDE_PROJECT_DIR = directorio padre, deniega el commit | ok |
| WS numéricos en el registro {C-316} | 7 | 7: K1, K2, K4, K5, K6, K7, K8 | ok |
| Solo WS-K7 falla la regla nueva {C-316} | C-144 / C-145 en_disputa, cerrada sin_decidir | gate_errors nuevo: solo WS-K7 da error; el cierre es C-300 (sin_decidir, ref C-144) | ok (O2) |
| Veredictos de K1, K2, K4, K5, K6, K8 | C-028 ref., C-041 ref., C-102 sop., C-112 sop., C-118 ref., C-184 sop. | iguales; uno por predicción | ok |
| `guard_cierre.sh` | solo cambia el comentario | el diff solo toca líneas `#` | ok |
| `GATED` y `staged_sha` sin cambios; `diff_sha=auto` | igual con la herramienta del disco y la de HEAD | ambas dan `bc23549026e3…398d` = `status.json` | ok |
| C-043 y C-076 como «fallida» | prerrequisito fallido / no concluyente | C-043: fallida por el prerrequisito; C-076: NO CONCLUYENTE | ok |
| Origen | WS-K13 `report.md:240-251`; `ciclo4/r1-auditor-eaf3d.md:51`; commit 98ae108 | las líneas contienen los dos pendientes y B2; el commit existe | ok |
| Integridad del registro | — | `ledger.py check`: OK (316 eventos, 14 workstreams) | ok |

## 2. Objeciones (ninguna bloqueante)

**O1. Falta probar el veredicto sobre una enmienda.**
- Dónde: `tests/research/test_ledger.py`, `test_gate_exige_veredicto_firme`, y `scripts/research/ledger.py:246` (`veredictos`).
- Qué pasa: el reporte dice «directo o sobre su enmienda vigente», pero el test solo prueba veredictos directos. El código, además, acepta un veredicto sobre cualquier eslabón de la cadena, no solo el vigente.
- Por qué no bloquea: es equivalente por la regla de WS-K13 (a lo sumo un veredicto por cadena; `check` da OK).
- Para levantarla: añadir el caso predicción → enmienda → veredicto (en_disputa cierra la compuerta, soportada la abre), o ajustar el texto.

**O2. El comando de C-316 no imprime la conclusión.**
- Dónde: `ledger.py show C-316`, campo `cmd`.
- Qué pasa: el comando lista el estado del veredicto por WS; «solo WS-K7» se deduce del listado.
- Lo confirmé aplicando `gate_errors(st, st['diff_sha'], ev)` a cada `status.json` numérico: solo WS-K7 da el error `la prediccion C-144 tiene veredicto 'en_disputa'`.
- Para levantarla (opcional): citar ese cálculo en la procedencia.

**O3. Sin prueba en vivo ni medida de coste.**
- El comando nuevo no se probó con Claude Code real, y el coste del `git show` extra no se midió. El reporte lo declara en «Incertidumbre».
- Reproduje la misma cadena con `/bin/sh -c` y `CLAUDE_PROJECT_DIR`, incluido el `settings.json` de la raíz, y obtuve los mismos resultados.
- Para levantarla: hacer la comprobación en vivo que el reporte propone para la primera sesión tras el commit.

## 3. Juicio

- Todas las cifras del reporte salen de los datos y se reproducen.
- Las tres afirmaciones (C-314, C-315, C-316) llevan rutas existentes y comando.
- El control es justo: mismo repo temporal, mismo hook de HEAD y misma entrada; solo cambia el `settings.json`. Además muestra el agujero, porque con el settings viejo también se permitía escribir en `ledger.jsonl`.
- No hay criterio pre-registrado que reinterpretar, porque el WS no es numérico.
- Las objeciones son de cobertura y redacción, no de evidencia.

VEREDICTO: aprueba
