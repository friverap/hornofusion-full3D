## Revisión de evidencia: WS-K14, ronda 1

**Veredicto: el panel puede cerrarlo.** Recalculé todos los números del reporte y todos coinciden con los datos. Quedan tres erratas menores que no bloquean.

WS-K14 no es numérico: no hay predicción con criterio pre-registrado que juzgar. Lo comprobé en `research/ws/WS-K14/status.json` (`numerico=false`, `prediccion=null`) y en el diff, que no toca `src/`. `ledger.py check` da «ledger OK (320 eventos, 14 workstreams)».

### Cómo lo comprobé

Todo fue de solo lectura sobre el repo. Lo que necesitaba escribir (tests y repo temporal) fue al scratchpad (`TMPDIR`):

- La suite `tests/research` usa directorios temporales.
- El control del `settings.json` viejo lo reproduje sin tocar `.claude/settings.json`: subclaseé el test para que lea `git show HEAD:.claude/settings.json`.
- El hook de HEAD lo probé con payloads que no llevan escape.

### 1. Tabla

| Afirmación | Reporte | Recalculado | Resultado |
|---|---|---|---|
| Suite `tests/research` | 45 OK; `test_gate_exige_veredicto_firme` ok; `test_settings_*` ok | 45 OK; los tres ok | ok |
| `FIRMES` y mensaje de `gate_errors` | `("soportada","refutada")`; «…veredicto 'en_disputa' (se exige soportada o refutada)» | Igual en el diff (`ledger.py:38`, 408-416) | ok |
| El test cubre 4 estados directos y además la enmienda (`en_disputa`/`refutada`) | sí | sí, según el diff de `tests/research/test_ledger.py` | ok |
| Control con el `settings.json` de HEAD | FALLA, `'allow' != 'deny'` | Reproducido: con el viejo FAIL (`'allow' != 'deny'`), con el nuevo OK | ok |
| `test_settings_sin_hook_en_HEAD…` también pasa con el viejo | sí | sí: ok con el viejo | ok |
| HEAD | 4850a0b | 4850a0b | ok |
| Entradas `PreToolUse` cambiadas | 2 | 2 (`settings.json:23` y `:36`); `guard_corridas` y `estado_sesion` siguen leyéndose del disco | ok |
| Sin hook en HEAD ni en el disco | rc 126, sin JSON | rc=126, sin JSON (repo vacío en el scratchpad) | ok (ver E3 sobre «126/127») |
| Transcripts | 3 en `-Users-frariv-Horno`, 0 en `-…-hornofusion-full3D` | 3 y 0 | ok |
| `settings.json` de la raíz (C-320) | `d=${CLAUDE_PROJECT_DIR}/hornofusion-full3D`; rama `exec bash -c`; deny; rc 0 | Igual: 1 `exec bash -c` en la traza, deny, rc 0 | ok |
| Workstreams numéricos (C-316) | 7; solo WS-K7 no pasaría | 7: K1 C-028 refutada, K2 C-041 refutada, K4 C-102 soportada, K5 C-112 soportada, K6 C-118 refutada, K7 C-145 en_disputa, K8 C-184 soportada. C-300 cierra C-144 `sin_decidir` | ok |
| WS-K4 cita C-101 (de WS-K3) | sí | C-101: `ws=WS-K3`, tipo prediccion | ok |
| WS-K10 tocó `src/` con `numerico=false` (1de144e) | sí | `src/mod_pressure_3d.f90`, más main/audit/workspace; prediccion C-202 | ok |
| C-318 (a): el hook de HEAD con el staged actual | commit deny; cherry-pick, revert, am, merge, rebase, commit-tree+update-ref allow | commit deny; los otros 6: allow, sin salida, rc 0 | ok |
| C-318 (b): ramas con el hook | 6 ramas, solo `pore-ramp` | 6 ramas, solo `pore-ramp` | ok |
| `fallida` = «prerrequisito» / «no concluyente» | C-043, C-076 | Son los únicos 2 veredictos `fallida` del registro, y dicen exactamente eso | ok |
| Decisión del usuario (C-317) | pregunta y opción citadas; 13:50:30Z / 13:58:11Z | El texto coincide literalmente: 13:50:30.049Z y 13:58:11.949Z | ok (ver E1) |
| Orígenes en WS-K13 | `report.md:240-251`; `ciclo4/r1-auditor-eaf3d.md:51` (B2); 98ae108; R1 del refutador en el ciclo 7; O4/B4 en el ciclo 5 | Todo existe en esas rutas y líneas | ok |
| `GATED` y `staged_sha` sin cambios; `diff_sha` | se mantiene | GATED igual en HEAD; sha256 del staged = `1e21790a…aaf` = `status.json:diff_sha` | ok (falta la nota, E2) |
| Documentación | README punto 3 y «Límite»; 1 línea de CLAUDE.md; SKILL; comentario del hook | Coincide con el diff staged | ok |

### Comparación justa y criterio

- **Sin criterio que juzgar.** No hay predicción pre-registrada, porque el WS no es numérico.
- **`fallida` como no firme.** La opción que eligió el usuario dice «solo pasa … si su predicción quedó soportada o refutada». Excluir `fallida` se sigue de esa letra, y el reporte lo declara como lectura propia en «Incertidumbre».
- **El control es justo.** Mismo test y mismo hook en HEAD y en el disco; solo cambia el comando de `settings.json`.

### 2. Objeciones (ninguna bloquea)

1. **E1.** `report.md` (fuente de C-317) dice «líneas 2226/2227». Son índices 0-based. Contadas desde 1 son las líneas 2227/2228. Se levanta indicando que son índices 0-based, o corrigiendo los números.
2. **E2.** En `report.md` («Arranque del commit»), la frase «diff_sha=auto da el mismo valor» no tiene nota de procedencia. Recalculado vale `1e21790a…aaf` = `status.json:diff_sha`. Se levanta añadiendo la nota con su comando.
3. **E3.** En `report.md` (Incertidumbre) aparece «rc 126/127», pero solo 126 está medido. Se levanta dejando 126, o añadiendo el caso que da 127 con su comando.

VEREDICTO: aprueba