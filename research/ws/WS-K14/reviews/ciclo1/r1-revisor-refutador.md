## Revisión del refutador: WS-K14, ronda 1

**Alcance.** WS-K14 es solo de herramienta (meta G3) y no cambia la numérica. Las preguntas sobre bancos frente a B1 o ventanas cortas no aplican. Aquí el sitio que importa es la ruta real de commit en las sesiones reales. Todo lo hice en solo lectura: diffs staged, el hook, los dos settings.json, ledger.py, los status.json, el registro, las ramas de git y las revisiones de WS-K13. No ejecuté tests.

### 1. Conclusiones, alternativas y el dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| C-314: un cambio numérico solo pasa con veredicto firme | La regla depende de dos campos de status.json que nada ata: `numerico` es autodeclarado y `prediccion` acepta cualquier id. status.json no está en GATED ni en diff_sha | Si gate_errors comprueba el ws y el tipo de `prediccion`, y si un cambio de `numerico` después de la aprobación cambia el sha | Sí, y en contra. gate_errors no comprueba ni ws ni tipo, y ws-set acepta cualquier valor. WS-K4 ya usa C-101, que es de WS-K3. WS-K10 tocó src/ (1de144e) con numerico=false y C-202 en_disputa (O3) |
| C-315: el hook que corre es el de HEAD, «ya aprobado» | HEAD se mueve sin compuerta, así que «HEAD = aprobado» es falso. El agujero solo se traslada de editar el archivo a mover HEAD | Que el hook cubra los comandos que crean o mueven commits, y que el hook exista en las ramas | Sí, y en contra. El hook sale si el comando no contiene «commit» y solo vigila el token exacto `commit`, así que commit-tree, merge, rebase, reset y update-ref pasan sin compuerta. 5 de las 6 ramas locales no tienen el hook; en ellas se usa el del disco o, si falta, se permite la herramienta (O1, O4) |
| C-315 medido en el sitio correcto | El test ejecuta el settings.json del repo, pero las sesiones reales se lanzan desde ~/Horno y usan el settings.json de la raíz, sin versionar | ¿Qué directorio de proyecto usan las sesiones? | Sí: 3 transcripts en -Users-frariv-Horno y 0 en el del repo. Por lectura, el comando de la raíz es el mismo con `d` sufijado. El mecanismo está activo pero sin probar, y el archivo no tiene protección (O2) |
| C-316: solo WS-K7 no habría pasado | Cierto en su letra. Pero solo cuenta los workstreams autodeclarados numéricos: WS-K10 cambió src/ con una predicción en_disputa | numerico de WS-K10 + `git show --stat 1de144e` | Sí. WS-K10 se declaró de diagnóstico con columnas idénticas (C-204, C-209); es legítimo, pero muestra que la regla depende de la etiqueta |
| El arranque no requiere procedimiento especial | — | Diff de staged_sha y de GATED | Sí: no cambian, y el hook del disco equivale al de HEAD salvo el comentario |

**¿Mueve el problema de sitio?** Sí, en parte. El vector deja de ser «editar guard_cierre.sh en el disco» y pasa a ser «mover HEAD con comandos que no son `git commit`» (commit-tree + update-ref, merge, cherry-pick) o «editar el settings.json de la raíz», que está en vigor y ningún hook protege. El reporte declara este último a medias y no menciona el primero.

### 2. Repeticiones de fracasos registrados

No hay afirmaciones refutadas, fallidas ni en disputa sobre el hook o la compuerta (`ledger.py open` y búsqueda en el registro). Lo que sí se repite es una **objeción del panel que nunca se resolvió**: R1 del refutador de WS-K13, ciclo 7 (`research/ws/WS-K13/reviews/ciclo7/r1-revisor-refutador.md:31`). Decía que merge, cherry-pick, revert, rebase y am mueven HEAD sin compuerta, lo que debilita la premisa de que HEAD es la herramienta aprobada. Se pedía un test o declararlo en el README. No se hizo ninguna de las dos cosas: el grep en el README y en los reportes de WS-K13 y WS-K14 no da coincidencias. WS-K14 hace que el hook también dependa de esa premisa.

### 3. Objeciones

- **O1 (bloqueante).** HEAD no es «ya aprobado».
  - El hook sale en cuanto el comando no contiene «commit» (merge, rebase, reset, update-ref, switch) y solo vigila el token exacto `commit`, así que `git commit-tree` + `git update-ref` y cherry-pick/revert/am tampoco pasan la compuerta.
  - main, choi-intento, plan-i, planc-f2-volumen y estado-auditoria-8 no tienen `.claude/hooks/guard_cierre.sh`. En ellas se usa el hook del disco o, si checkout lo borró, `exec` falla y la herramienta se permite.
  - **Lo resuelve:** declararlo en «Incertidumbre» y en el «Límite» del README (comandos, ramas sin el hook, paso a permitir cuando falta el archivo), o un test de deny con commit-tree + update-ref o cherry-pick sobre rutas GATED. Hoy ese test fallaría.
- **O2 (no bloqueante).** La configuración en vigor es `~/Horno/.claude/settings.json` (3 de 3 transcripts son de ~/Horno).
  - No está versionada, el test no la cubre y Edit/Write sobre ella no se deniega.
  - **Lo resuelve:** decirlo explícitamente en el reporte y en el README; probar el comando con `d=${CLAUDE_PROJECT_DIR}/hornofusion-full3D`; hacer la verificación en vivo desde una sesión lanzada en ~/Horno.
- **O3 (no bloqueante).** La regla del veredicto firme se puede saltar desde status.json (autodeclaración y id libre).
  - **Lo resuelve:** que gate_errors exija que `prediccion` sea de tipo predicción y del mismo ws, con un test de predicción ajena soportada; o declararlo, junto con que `numerico` es autodeclarado y status.json queda fuera de diff_sha.
- **O4 (no bloqueante).** `test_settings_sin_hook_en_HEAD_usa_el_del_disco` pasaría también con el settings viejo. Falta el caso sin hook en HEAD ni en el disco (exit 127, la herramienta se permite).
  - **Lo resuelve:** un test que documente ese caso, o un respaldo que deniegue.
- **O5 (no bloqueante).** La decisión del usuario solo se cita en el reporte.
  - **Lo resuelve:** citar la pregunta y la respuesta literales o registrarlas como evento.

**Lo que sí verifiqué que se sostiene:** la letra de C-314 (gate_errors y FIRMES), el control de C-315 (FAILED con el settings viejo, así que el test detecta el cambio), C-316 por lectura de los status.json, y la equivalencia entre el hook del disco y el de HEAD para el arranque.

El rechazo es solo por O1, que es documental y barato de resolver. Es una objeción ya planteada por el panel, nunca declarada, y contradice la premisa central de este WS.

VEREDICTO: rechaza