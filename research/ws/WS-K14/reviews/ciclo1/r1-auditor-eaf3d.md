## Revisión WS-K14, ronda 1: auditor-eaf3d

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Quedan 5 observaciones BAJO, ninguna bloqueante.

Alcance: diff staged (`git diff --cached`) contra `research/ws/WS-K14/report.md`. El diff no toca `src/`, así que no aplican los criterios del simulador (conservación, halos MPI, snapshot ni `liq%alpha`). Todo lo revisado es herramienta del harness.

### Hallazgos

**ALTO:** ninguno.

**MEDIO:** ninguno.

**BAJO**

- **B1. Se puede forzar el uso del hook del disco moviendo HEAD.**
  - Archivos: `.claude/settings.json` (comando de guard_cierre) y `.claude/hooks/guard_cierre.sh:59`.
  - Escenario: `git reset --soft <sha anterior a 68cc32d>`, `git checkout --orphan x` o un HEAD desprendido. Ningún comando contiene «commit», así que el hook sale en la línea 59 sin intervenir. Después, `git show HEAD:...guard_cierre.sh` falla, se ejecuta el hook del disco (que puede estar debilitado) y el `git commit` siguiente pasa. Si HEAD apunta a un commit con una versión vieja del hook, decide esa versión.
  - Hay además rutas previas a este diff que el hook no intercepta: `git commit-tree` + `update-ref` (el token es `commit-tree`), `merge`, `cherry-pick`, `rebase`, `am` y `revert`. No están documentadas en ningún sitio: grep sin resultados en README, reportes, CLAUDE.md y docs.
  - Arreglo: documentarlo en el párrafo «Límite» del README y en la Incertidumbre del reporte (es una barrera contra errores, no contra quien reescribe HEAD). Opcional: denegar esos subcomandos cuando el staged toque rutas de GATED.

- **B2. `gate_errors` no comprueba qué evento es `status.prediccion`** (`scripts/research/ledger.py:409-416`, previo a este diff).
  - Escenario: el panel aprueba un WS numérico con su predicción en `en_disputa` y el gate deniega. Luego `ws-set WS prediccion=C-102` (soportada de WS-K4). `status.json` no está en GATED, así que `diff_sha` no cambia y la compuerta pasa.
  - Un error de tecleo honesto tampoco se detecta. C-314 dice «la predicción del workstream», pero el código no lo garantiza.
  - No se puede exigir igualdad estricta de ws: WS-K4 usa C-101, que es de WS-K3.
  - Arreglo: exigir que `raiz_enmienda(pid)` sea de tipo `prediccion` y avisar (o pedir un campo explícito) si el ws no coincide. Alternativa: acotar la redacción de C-314.

- **B3. El precheck no exige veredicto firme** (`.claude/workflows/workstream.js:94`, punto 4).
  - Pide solo «predicción con criterio», aunque SKILL.md ya pone el veredicto firme como prerrequisito.
  - Escenario: un WS numérico con veredicto `en_disputa` pasa por todo el panel y solo falla al hacer el commit.
  - Arreglo: añadir la condición al punto 4, en un WS posterior porque el archivo está en GATED.

- **B4. Contradicción de redacción** en «Arranque del commit» del reporte.
  - La viñeta 1 dice que decide el hook de HEAD. La viñeta 3, correctamente, dice que en esta sesión decide el hook del disco.
  - Verifiqué que el hook del disco es idéntico al staged (`M ` sin cambios en el árbol de trabajo) y que difiere de HEAD solo en el comentario. No hay efecto práctico.

- **B5. Falta un caso de prueba.** `test_gate_exige_veredicto_firme` no cubre un veredicto `en_disputa` sobre una enmienda. El riesgo es bajo porque `veredictos()` ya tiene pruebas de WS-K13.

### Verificado como correcto (no re-auditar)

- **`gate_errors`**
  - `vs[-1]` es el único veredicto posible: `validate` impide un segundo veredicto (`juzgada` sobre la raíz) y un veredicto sobre una predicción ya enmendada (`tiene_enmienda`).
  - En el registro real ninguna predicción tiene más de un veredicto (lo comprobé con python sobre `ledger.jsonl`).
  - Reemplazar `juzgada()` por `veredictos()` conserva el mismo criterio (`juzgada = bool(veredictos)`) y no pierde ninguna comprobación.
  - El mensaje de «sin predicción juzgada» sigue igual.
- **El test nuevo pasa por la razón correcta.** Comprueba el texto `veredicto '<estado>'` en los dos casos que deniegan. En el caso `en_disputa` + `sin_decidir`, el mensaje confirma que `veredictos()` no incluye el resultado de cierre.
- **C-316.** Hay 7 WS numéricos: K1 C-028 refutada, K2 C-041 refutada, K4 C-102 soportada, K5 C-112 soportada, K6 C-118 refutada, K7 C-145 en_disputa y K8 C-184 soportada. `current_state(C-144) = sin_decidir` (cierre C-300). Solo WS-K7 habría sido denegado.
- **`diff_sha`.** El sha256 de `git diff --cached -- <GATED>` es `bc23549026e3…398d`, igual al de `status.json`.
- **GATED y `staged_sha`** no cambian en el diff de `ledger.py`. La afirmación del arranque (que `diff_sha=auto` coincide entre el disco y HEAD) es correcta.
- **Comando nuevo de `settings.json`**
  - POSIX, con comillas correctas.
  - `git show` no consume stdin, y `bash -c` lo hereda, así que el JSON llega al `cat > "$tmp"` del hook.
  - El hook no usa `$0` ni `BASH_SOURCE`.
  - La sustitución `$(...)` quita el `\n` final, y el heredoc queda terminado en `PY` sin salto de línea. El único `bash` del sistema es `/bin/bash` 3.2, y con él el test deniega mediante el JSON que imprime el Python del heredoc, así que el heredoc se ejecuta bien.
  - Las dos entradas (Bash y Edit|Write|…) son idénticas.
- **`test_settings_corre_el_hook_de_HEAD`**
  - Lee el `settings.json` real del repo.
  - Discrimina: el `Write` sobre `ledger.jsonl` daría allow con el `exit 0` del disco.
  - El control con el `settings.json` de HEAD (4850a0b) falla `'allow' != 'deny'` (`control_settings_HEAD_viejo.txt`).
  - El test de respaldo también discrimina: si el `exec` fallara, la salida vacía daría allow.
- **`settings.json` de la raíz** (`~/Horno/.claude/settings.json`, fuera del repo; leído). Tiene el mismo comando con `d="${CLAUDE_PROJECT_DIR}/hornofusion-full3D"`. Es correcto, porque `~/Horno` no es un repo git.
- **`tests_research.txt`.** 45 tests OK, incluidos `test_gate_exige_veredicto_firme` y los dos `test_settings_*`.
- **Documentación.** README (punto 3 y párrafo Límite), CLAUDE.md, SKILL.md y la cabecera del hook (solo comentario) son coherentes con el código.

### Orden sugerido de corrección (uno por uno)

1. B4 y B1 (documentación): corregir la redacción del reporte y añadir el límite de mover HEAD y de los commits creados sin `git commit` al README y a la Incertidumbre. Se puede hacer en este mismo WS.
2. B2: comprobar en `gate_errors` el tipo de `status.prediccion`, en un WS de herramienta posterior.
3. B3: añadir la condición del veredicto firme al precheck de `workstream.js`.
4. B5: añadir el caso del veredicto sobre una enmienda al test.

Rutas: `/Users/frariv/Horno/hornofusion-full3D/scripts/research/ledger.py`, `/Users/frariv/Horno/hornofusion-full3D/.claude/settings.json`, `/Users/frariv/Horno/hornofusion-full3D/.claude/hooks/guard_cierre.sh`, `/Users/frariv/Horno/hornofusion-full3D/.claude/workflows/workstream.js`, `/Users/frariv/Horno/hornofusion-full3D/tests/research/test_guard_cierre.py`, `/Users/frariv/Horno/hornofusion-full3D/tests/research/test_ledger.py`, `/Users/frariv/Horno/.claude/settings.json`.
