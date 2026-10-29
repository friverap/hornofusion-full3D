# WS-K14: compuerta con veredicto firme y hook de cierre cargado desde HEAD

**Meta:** G3 (herramienta del harness). **Sin cambio numérico:** no toca
`src/` ni el simulador. Toca:

- `scripts/research/ledger.py` (`FIRMES`, `gate_errors`);
- `.claude/settings.json` (cómo se carga `guard_cierre.sh`);
- el comentario de cabecera de `.claude/hooks/guard_cierre.sh`;
- `tests/research/`;
- `research/README.md`, una línea de `CLAUDE.md` y `.claude/skills/workstream/SKILL.md`.

## Origen

Dos pendientes que WS-K13 (98ae108) dejó declarados en su «Incertidumbre»
(`research/ws/WS-K13/report.md:240-251`):

- **Compuerta numérica con un veredicto `en_disputa`** (B2 del ciclo 4,
  `research/ws/WS-K13/reviews/ciclo4/r1-auditor-eaf3d.md:51`). `gate_errors`
  aceptaba cualquier veredicto (`juzgada`). WS-K13 lo dejó fuera porque era
  una decisión de política. El usuario la tomó el 2026-10-29 {C-317}. A la
  pregunta «¿Incluyo también el cambio de política de la compuerta para
  predicciones con veredicto en_disputa?» eligió la opción «Exigir veredicto
  firme (Recomendado)», cuya descripción era: «Un cambio numérico solo pasa la
  compuerta si su predicción quedó soportada o refutada; en_disputa o
  sin_decidir la cierran.».

  > [fuente: ~/.claude/projects/-Users-frariv-Horno/1cff94cc-79f1-4419-a0f7-1f5efdb5b3bc.jsonl, líneas 2226 (AskUserQuestion, 13:50:30Z) y 2227 (respuesta, 13:58:11Z) | ver --cmd de C-317]
- **El hook se certifica a sí mismo** (O4/B4 del ciclo 5). Claude Code
  ejecutaba el `guard_cierre.sh` del DISCO, así que un hook debilitado (y
  staged) decidía su propio commit. `ledger.py` ya se tomaba de HEAD
  (WS-K13), pero el hook que lo invoca no.

## Cambios

1. **Veredicto firme** {C-314}. `FIRMES = ("soportada", "refutada")`. Si el
   workstream es numérico, `gate_errors` toma el veredicto de su predicción,
   directo o sobre su enmienda vigente (`veredictos`; hay a lo sumo uno, regla
   de WS-K13). Si ese veredicto no está en `FIRMES` da error: «la prediccion
   C-nnn tiene veredicto 'en_disputa' (se exige soportada o refutada)».
   - `en_disputa` no pasa, aunque después se cierre `sin_decidir`.
   - `fallida` no pasa. En el registro es «no concluyente» o «falló el
     prerrequisito» ({C-043}, {C-076}): no decide la predicción.
   - Una refutada sí pasa, como antes. Es la letra de la decisión del usuario,
     y el panel decide si un cambio con su predicción refutada se commitea.
   - El test cubre los cuatro estados con veredicto directo y, desde el ciclo
     2 (O1 de evidencia, B5 del auditor), el veredicto sobre la enmienda
     vigente: `en_disputa` cierra la compuerta y `refutada` la abre.

   > [fuente: scripts/research/ledger.py (FIRMES, gate_errors) | python3 -m unittest discover -s tests/research -v → research/ws/WS-K14/tests_research.txt: test_gate_exige_veredicto_firme ok, 45 tests OK]

2. **Hook de HEAD** {C-315}. En `.claude/settings.json`, las dos entradas
   `PreToolUse` de `guard_cierre.sh` (Bash y Edit|Write|MultiEdit|NotebookEdit)
   pasan a ser:

   ```
   d="${CLAUDE_PROJECT_DIR}"; f=.claude/hooks/guard_cierre.sh;
   if s=$(git -C "$d" show "HEAD:$f" 2>/dev/null) && [ -n "$s" ]; then exec bash -c "$s"; fi;
   exec "$d/$f"
   ```

   - Se ejecuta el hook tal como está en HEAD. Eso equivale al hook aprobado
     solo si HEAD avanzó con un `git commit` vigilado; hay comandos que mueven
     HEAD sin pasar por la compuerta (ver «Incertidumbre», {C-318}). El JSON
     de la herramienta llega por stdin igual que antes, porque `bash -c`
     hereda stdin.
   - El archivo del disco solo se usa si HEAD no lo tiene (repo nuevo o rama
     sin el hook). Es el mismo orden de respaldo que `ledger.py` en WS-K13.
     Si tampoco está en el disco, `exec` falla (rc 126 con `/bin/sh` en un
     repo temporal vacío) y Claude Code PERMITE la herramienta ({C-318}).
   - `guard_corridas.sh` y `estado_sesion.sh` siguen cargándose del disco: no
     deciden commits.

   Prueba en un repo temporal (`test_settings_corre_el_hook_de_HEAD`): HEAD
   tiene el hook honesto, y en el disco (staged) queda reducido a `exit 0`. Se
   ejecuta el comando EXACTO de `settings.json` con `/bin/sh -c`:
   - `git commit` → deny;
   - `Write` sobre `research/ledger.jsonl` → deny;
   - `git status` → allow.

   **Control:** con el `settings.json` de HEAD (4850a0b), el mismo test FALLA
   (`'allow' != 'deny'`). El agujero existía y la prueba lo detecta.
   `test_settings_sin_hook_en_HEAD_usa_el_del_disco` cubre el respaldo, pero
   no distingue el comportamiento nuevo: pasaría igual con el `settings.json`
   viejo, que siempre usaba el del disco. No hay test del caso sin hook en HEAD
   ni en el disco.

   > [fuente: .claude/settings.json | python3 -m unittest discover -s tests/research -v → research/ws/WS-K14/tests_research.txt (test_settings_* ok)]
   > [fuente: research/ws/WS-K14/control_settings_HEAD_viejo.txt | git show HEAD:.claude/settings.json > .claude/settings.json; python3 -m unittest tests.research.test_guard_cierre.GuardCierreTest.test_settings_corre_el_hook_de_HEAD; restaurar → FAILED (failures=1), AssertionError: 'allow' != 'deny']

   **La configuración en vigor es la de la raíz** {C-320}. Las sesiones se
   lanzan desde `~/Horno` (3 transcripts en
   `~/.claude/projects/-Users-frariv-Horno`, 0 en
   `-Users-frariv-Horno-hornofusion-full3D`), así que rige
   `~/Horno/.claude/settings.json`, no el del repo. Se cambió igual: su
   comando es el del repo con `d=${CLAUDE_PROJECT_DIR}/hornofusion-full3D`.
   - Está fuera del repo: no queda versionado, no está en `GATED` y el hook no
     protege ese archivo frente a Edit/Write.
   - La suite no lo prueba: `settings_hook` solo lee `REPO/.claude/settings.json`.
   - Comprobación manual, no un test: su comando, ejecutado con `/bin/sh -x -c`
     y `CLAUDE_PROJECT_DIR=/Users/frariv/Horno`, toma la rama
     `exec bash -c` con el hook de HEAD, y un Write sobre
     `research/ledger.jsonl` da `deny`.

   > [fuente: ~/Horno/.claude/settings.json | ver --cmd de C-320 → permissionDecision "deny", rc 0]

3. **Alcance histórico** {C-316}. Hay 7 workstreams que se declararon
   numéricos en el registro, y solo WS-K7 no habría pasado la regla nueva (predicción {C-144}, veredicto
   {C-145} `en_disputa`, cerrada `sin_decidir`). La regla no es retroactiva:
   `gate` solo juzga el diff staged de un commit nuevo, y el `status.json` de
   WS-K7 no cambia.

   > [fuente: research/ws/*/status.json, research/ledger.jsonl | ver --cmd de C-316 en `ledger.py show C-316`]

   El recuento depende de dos datos que la compuerta no verifica {C-319}:
   - `numerico` lo autodeclara el workstream. WS-K10 tocó `src/` (1de144e,
     `mod_pressure_3d.f90`) con `numerico=false`, declarado como instrumento
     sin cambio numérico.
   - `prediccion` puede ser cualquier id: WS-K4 cita C-101, predicción de
     WS-K3.

   > [fuente: research/ws/WS-K4/status.json (numerico true, prediccion C-101), research/ws/WS-K10/status.json (numerico false, prediccion C-202) | ver --cmd de C-319]

4. **Documentación:**
   - `research/README.md`: punto 3 del cierre y el párrafo «Límite» del punto 4.
   - `CLAUDE.md`: una línea.
   - `workstream/SKILL.md`: prerrequisito «veredicto firme».
   - Cabecera de `guard_cierre.sh`: solo comentario.

## Arranque del commit

- Este commit lo decide el hook del disco (la sesión cargó el comando viejo,
  ver abajo), que es igual al de HEAD salvo el comentario de cabecera, con el
  `ledger.py` de HEAD. Como WS-K14 no es numérico, la regla nueva no entra en
  juego.
- `GATED` y `staged_sha` no cambian, así que `diff_sha=auto` da el mismo valor
  con la herramienta del disco que con la de HEAD. No hace falta el
  procedimiento de arranque de WS-K13.
- Claude Code toma los hooks de `settings.json` al iniciar la sesión. El
  comando nuevo rige desde la sesión siguiente; en esta sigue el viejo, que
  ejecuta el hook del disco (igual al de HEAD salvo el comentario de
  cabecera).

## Incertidumbre

- **HEAD se mueve sin la compuerta** {C-318}. Todo lo «de HEAD» (hook y
  `ledger.py`) presupone que HEAD solo avanza con un `git commit` vigilado, y
  eso no se cumple:
  - `guard_cierre.sh` solo vigila el subcomando exacto `commit`. Con el hook
    de HEAD y el staged actual, `git commit -m x` da deny, pero `git
    cherry-pick`, `git revert`, `git am`, `git merge`, `git rebase` y
    `git commit-tree` + `git update-ref` dan allow.
  - De las 6 ramas locales solo `pore-ramp` tiene el hook. En las otras cinco
    (`main`, `choi-intento`, `plan-i`, `planc-f2-volumen`,
    `estado-auditoria-8`) se usa el del disco, y si `checkout` lo borró no hay
    ninguno.
  - Sin hook en HEAD ni en el disco, `exec` falla (rc 126/127, sin JSON) y
    Claude Code permite la herramienta: solo bloquea un `deny` o un exit 2.
    Era igual con el `settings.json` viejo. No hay test de este caso.

  Lo planteó ya el refutador de WS-K13 (ciclo 7, R1) y no se había declarado.
  Desde el ciclo 2 de WS-K14 lo declara el README («Límite» del punto 4),
  junto con {C-319} y {C-320}. No se arregla aquí: cubrir esos comandos o
  atar `status.json` es otro cambio de la compuerta.
- **La regla del veredicto firme se salta desde `status.json`** {C-319}. Este
  archivo no está en `GATED` ni en `diff_sha`, así que `ws-set
  numerico=false` tras la aprobación no cambia `diff_sha`. Además,
  `gate_errors` no comprueba que `prediccion` sea de tipo `prediccion` ni del
  mismo workstream: basta citar una predicción soportada antigua.

- **`settings.json` en el disco.** Si alguien cambia `.claude/settings.json`
  en el disco para volver a cargar el hook del disco y reinicia la sesión, el
  hook vuelve a ser el del disco. Commitear ese cambio exige el panel, pero una
  sesión puede correr con él sin commitearlo. Lo mismo vale para el
  `settings.json` de la raíz, que no está versionado. Cerrarlo exigiría un
  control fuera del repo, como una política administrada de Claude Code.
- **No probado en vivo.** No se probó con Claude Code real ejecutando el hook
  desde `settings.json`: eso exige una sesión nueva, lanzada desde `~/Horno`
  porque la configuración en vigor es la de la raíz {C-320}. La prueba ejecuta la
  misma cadena con `/bin/sh -c` y `CLAUDE_PROJECT_DIR`, como lo hace Claude
  Code. Queda por confirmar en la primera sesión tras el commit, por ejemplo
  con un `git commit` de `src/` sin workstream, que debe ser denegado.
- **Coste.** Cada llamada a Bash, Edit o Write ejecuta un `git show` más. Es
  barato, pero no se midió.
- **Siguen como en WS-K13:**
  - B3: el escape registra con el `ledger.py` del disco.
  - B2 del ciclo 6: hay dos listas de rutas a mano (hook y `GATED`).
- **`fallida` como no firme** es una lectura de la decisión del usuario, que
  nombró soportada/refutada frente a en_disputa/sin_decidir. `fallida` no
  aparecía en la pregunta ni en sus opciones ({C-317}). Se excluye porque en el registro significa «no
  concluyente».
