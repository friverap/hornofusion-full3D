# WS-K14, ronda 1: auditor-eaf3d

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO en el diff staged. Hay 5 hallazgos BAJO y una nota de verificación; ninguno bloquea.

Alcance revisado: `git diff --cached` completo, que toca `scripts/research/ledger.py`, `.claude/settings.json`, la cabecera de `.claude/hooks/guard_cierre.sh`, `tests/research/*`, `research/README.md`, `CLAUDE.md`, `.claude/skills/workstream/SKILL.md` y los eventos C-314..C-320 del registro. También revisé `/Users/frariv/Horno/.claude/settings.json`, que está fuera del repo. No leí `reviews/` (revisión ciega).

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B1. El precheck del workflow no exige veredicto firme**
- Dónde: `/Users/frariv/Horno/hornofusion-full3D/.claude/workflows/workstream.js:94`.
- Defecto: el punto 4 solo pide «prediccion del registro con criterio».
- Escenario: un WS numérico con veredicto `en_disputa` pasa el precheck y hace hasta 3 rondas de panel. La compuerta lo cierra recién al hacer commit (`ledger.py:414`). No hay agujero en la compuerta, pero se gasta el panel.
- Arreglo: añadir «y su veredicto es soportada o refutada». Es una ruta GATED, así que puede ir en un WS posterior.

**B2. La skill `/preregistro` no avisa que `en_disputa` es terminal para la compuerta**
- Dónde: `/Users/frariv/Horno/hornofusion-full3D/.claude/skills/preregistro/SKILL.md:21-24`.
- Defecto: sigue ofreciendo `en_disputa` sin advertir el efecto en un WS numérico.
- Escenario: después de `en_disputa`, `validate` rechaza un segundo veredicto (`ledger.py:116`: «un segundo juicio va en una prediccion nueva»). El cambio numérico ya no se puede commitear con esa predicción, y ni la skill ni el README dicen cuál es la salida.
- Arreglo: una línea con la salida: predicción nueva, juzgada en firme, y `ws-set prediccion=`.

**B3. El test no comprueba que los dos matchers lleven el guard**
- Dónde: `/Users/frariv/Horno/hornofusion-full3D/tests/research/test_guard_cierre.py:160-161`.
- Defecto: `cmds` es un set sobre todos los grupos PreToolUse, y `len==1` no distingue entre «los dos matchers tienen el guard» y «solo uno lo tiene».
- Escenario: si se quita el guard del grupo `Edit|Write|MultiEdit|NotebookEdit`, el caso `Write` → deny sigue pasando, porque ejecuta la cadena tomada del grupo Bash.
- Arreglo: comprobar el comando matcher por matcher.

**B4. Redacción imprecisa en el README**
- Dónde: `/Users/frariv/Horno/hornofusion-full3D/research/README.md:141`.
- Defecto: dice que «`prediccion` acepta cualquier id».
- Lo que hace el código: un id de hipótesis o de resultado no pasa, porque `veredictos` queda vacío y la compuerta responde «sin prediccion pre-registrada juzgada». Solo pasa un id cuya cadena tenga veredicto, es decir, una predicción o una enmienda.
- El hueco real (C-319b) es otro: acepta cualquier predicción juzgada en firme, aunque sea de otro WS.
- Arreglo: cambiar la redacción en ese sentido.

**B5. Contrato implícito del hook sin documentar**
- Dónde: comando de `.claude/settings.json` (y su copia en la raíz).
- Defecto: el hook de HEAD corre con `bash -c "$s"`, así que `$0` vale `bash` y no hay `BASH_SOURCE`.
- Escenario: un hook futuro que se ubique con `$(dirname "$0")` fallaría sin JSON, y Claude Code PERMITIRÍA la herramienta. El hook actual no usa `$0`, así que hoy no hay fallo.
- Arreglo: un comentario en la cabecera. Opcional: usar `git cat-file blob HEAD:$f` en vez de `git show`, para no depender de textconv. Hoy no hay `.gitattributes` ni textconv configurado, así que esto no es un defecto.

**Nota de verificación (no es un defecto).** No ejecuté la suite porque la regla es solo lectura. La cubre el `test_quick=ok` que exige la compuerta: `tests/run_tests.sh:291` corre `tests/research` dentro de `make test-quick`.

## 2. Verificado como correcto

**`gate_errors` y `FIRMES`** (`ledger.py:40, 409-416`)
- `veredictos` cubre el veredicto directo y el puesto sobre la enmienda vigente.
- `validate` garantiza como mucho un veredicto por cadena (`ledger.py:116`; las enmiendas van sobre la punta). `ledger.py check` da OK con 320 eventos, y ninguna predicción del registro tiene más de un veredicto. Por eso `vs[-1]` es seguro.
- Sin `pid`, o con un pid inexistente, el error es el mismo que antes.

**Alcance histórico (C-316)**
- Los 7 WS numéricos y sus pares predicción → veredicto: K1 C-025→C-028 refutada, K2 C-040→C-041 refutada, K4 C-101→C-102 soportada, K5 C-111→C-112 soportada, K6 C-117→C-118 refutada, K7 C-144→C-145 en_disputa (estado vigente sin_decidir), K8 C-182→C-184 soportada.
- Solo WS-K7 no pasaría la regla nueva, como dice el reporte.

**Test de veredicto firme** (`test_gate_exige_veredicto_firme`)
- Los casos negativos comprueban el mensaje `veredicto '<est>'`, así que fallan por la razón correcta.
- Los casos positivos pasan con el mismo montaje (diff_sha, test_quick, revisores), así que el negativo de la enmienda se atribuye solo al estado del veredicto.

**Comando de `settings.json`**
- `$(...)` no consume stdin, y `exec bash -c` hereda el JSON.
- El respaldo va al disco solo si HEAD no tiene el hook.
- Las comillas aguantan espacios en la ruta.
- Las dos entradas del repo son idénticas.
- `~/Horno/.claude/settings.json` tiene el mismo comando con `d=${CLAUDE_PROJECT_DIR}/hornofusion-full3D` en los dos matchers, y el `REPO0` del hook resuelve bien con `PROJ=~/Horno`.

**`test_settings_corre_el_hook_de_HEAD` discrimina y falla por la razón correcta**
- El staged toca `.claude/hooks/` (ruta GATED), y el gate usa el `ledger.py` del HEAD temporal, sin WS → deny.
- El `Write` sobre `ledger.jsonl` solo da deny si el hook de HEAD lee stdin.
- El control (`control_settings_HEAD_viejo.txt`) da `'allow' != 'deny'`.
- `test_settings_sin_hook_en_HEAD_usa_el_del_disco` no discrimina entre el comando viejo y el nuevo, y el reporte lo declara.

**Diff y log**
- `status.json` `diff_sha` = `1e21790a…` = sha256 de `git diff --cached` sobre las rutas GATED (lo recalculé).
- No hay cambios unstaged.
- El log tiene 45 «ok», igual a 17 + 28 `def test_`.

**Arranque del commit**
- `GATED` y `staged_sha` no cambian, así que `diff_sha=auto` da lo mismo con la herramienta de HEAD que con la del disco.
- WS-K14 tiene `numerico=false`, así que `FIRMES` no entra en juego en este commit.

**Configuración en vigor (C-320):** hay 3 transcripts en `-Users-frariv-Horno` y 0 en `-Users-frariv-Horno-hornofusion-full3D`.

**Límites declarados (C-318, C-319, C-320, `settings.json` en el disco):** coinciden con el código. Son anteriores al diff o no los empeora, así que no los cuento como hallazgos nuevos.

**Documentación:** `CLAUDE.md`, `workstream/SKILL.md` y la cabecera del hook son coherentes con el código.

## 3. Orden sugerido de corrección (uno por uno)
1. B3: test por matcher. Es lo único que protege el arreglo central frente a una regresión silenciosa.
2. B1: precheck del workflow.
3. B2: la skill `/preregistro` documenta la salida de `en_disputa`.
4. B4: redacción del README.
5. B5: comentario sobre `$0` en la cabecera del hook.
