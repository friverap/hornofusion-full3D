## Revisión del refutador: WS-K14, ronda 1 (ciclo 2)

**Alcance.** WS-K14 cambia solo la herramienta (G3), no la numérica. Aquí no aplican bancos frente a B1 ni ventanas: el sitio que importa es la ruta real de commit en una sesión real. Todo fue de solo lectura: el diff staged, el hook (disco y HEAD), los dos settings.json más el de usuario, `ledger.py` (validate, current_state, veredictos, gate_errors, cmd_gate), los status.json, el registro, las ramas, `git replace -l` y las líneas 2226-2227 del transcript. Ejecuté python solo para leer el registro. No corrí tests. No leí revisiones de otros revisores; solo la mía del ciclo 1.

### 1. Conclusiones, alternativas y dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| C-314: un cambio numérico solo pasa con veredicto soportada o refutada | `vs[-1]` podría no ser el estado vigente: un veredicto firme seguido de un cierre sin_decidir pasaría | ¿El registro admite un segundo juicio tras un veredicto? | Sí, y lo descarta. `validate` rechaza un segundo veredicto en la cadena («ya tiene veredicto»), cualquier cita a una predicción con veredicto no en_disputa y un sin_decidir tras un veredicto firme. Por tanto `vs` tiene a lo sumo un elemento y coincide con current_state. La regla se sostiene en su letra |
| C-314 se aplica al cambio que importa | Se elude por status.json, por la predicción citada o por otro workstream con el mismo sha | `cmd_gate` sin workstream y la vinculación de status.json | Sí. `cmd_gate` pasa si CUALQUIER workstream pasa; status.json está fuera de diff_sha (C-319). Está declarado en parte (O3) |
| C-315: el hook que decide es el de HEAD | El test ejecuta /bin/sh y no Claude Code, y la configuración en vigor es la de la raíz | Prueba en vivo en una sesión nueva | No está en los datos. Es una emulación con un control discriminante: con el settings viejo, FAILED 'allow' != 'deny'. La prueba en vivo está declarada pero no registrada como pendiente (O1) |
| C-315: «un hook debilitado en el disco no decide su propio commit» | HEAD puede leerse distinto sin moverse | `git replace` | No declarado. Hoy no tiene efecto: `git replace -l` da 0 (O2) |
| C-316: solo WS-K7 no habría pasado | — | veredictos y current_state de los 14 status.json | Sí, coincide: K1, K2 y K6 refutada; K4, K5 y K8 soportada; K7 en_disputa → sin_decidir. Recuento acotado por C-319 |
| C-317: decisión del usuario | Que la opción no cubra `fallida` | Texto literal | Verificado en las líneas 2226-2227 (13:50:30Z y 13:58:11Z). `fallida` no aparece; su exclusión está declarada como interpretación |
| C-318: ramas sin hook | — | `git cat-file -e` por rama | Verificado: solo pore-ramp tiene el hook |
| C-320: rige ~/Horno/.claude/settings.json | Que las sesiones se lancen desde el repo | Transcripts por proyecto | Verificado: 3 .jsonl en -Users-frariv-Horno y 0 en el del repo; ese directorio solo guarda scripts de workflow. No hay settings.local.json, y el settings de usuario no tiene hooks. Los dos settings llevan el comando nuevo en ambas entradas |
| Arranque: el hook del disco equivale al de HEAD | — | Diff del disco contra HEAD | Verificado: solo cambian 3 líneas de comentario. WS-K14 no es numérico, así que ledger.py de HEAD (sin FIRMES) decide igual |

**¿Mueve el problema de sitio?** El vector «editar guard_cierre.sh en el disco» pasa a ser «cambiar lo que HEAD contiene o lo que `git show HEAD:` devuelve» y «editar settings.json, sobre todo el de la raíz». Ahora está declarado en C-318, C-319, C-320 y el «Límite» del README («barrera contra errores de proceso, no contra quien reescribe HEAD o el estado del workstream»), salvo `git replace` (O2) y la vía de otro workstream en `gate` sin argumento (O3). La energía por paso no aplica; el coste es un `git show` por llamada, sin medir y declarado.

### 2. Repeticiones de fracasos registrados

No hay afirmaciones refutadas, fallidas ni en disputa sobre el hook o la compuerta (busqué en el registro y en «Lo que NO funcionó» de acople-pv.md; los PLAN_* no lo tratan). La objeción repetida del panel (R1 del refutador de WS-K13, ciclo 7, y mi O1 del ciclo 1: HEAD avanza sin compuerta) ahora está declarada en C-318 y en el «Límite» del README. Mis O2-O5 del ciclo 1 quedan resueltas por C-320, C-319, la Incertidumbre y C-317.

### 3. Objeciones

- **O1 (no bloqueante).** La prueba en vivo de C-315 sigue pendiente y no figura en el registro (0 abiertas). Como el hook falla en abierto, un error en vivo pasaría desapercibido.
  - **Lo resuelve:** una predicción pre-registrada: en una sesión nueva desde ~/Horno, un Write sobre `research/ledger.jsonl` y un `git commit` de src/ sin workstream dan deny. Juzgarla después. Puede hacerse antes del commit: el settings de la raíz ya está cambiado y el hook de HEAD 4850a0b es equivalente.
- **O2 (no bloqueante).** `git replace` cambia el contenido «de HEAD» del hook y de ledger.py sin mover HEAD y sin el token `commit`.
  - **Lo resuelve:** usar `--no-replace-objects` en settings.json y en git_show() del hook, con un test de deny con un replace activo; o declararlo en el «Límite».
- **O3 (no bloqueante).** `gate` sin argumento acepta cualquier workstream con el mismo diff_sha. Un workstream no numérico, o una predicción nueva refutada al instante, abre la compuerta pese a un en_disputa.
  - **Lo resuelve:** un test con WS-A numérico en_disputa y WS-B no numérico con el mismo sha (OK hoy); luego, documentarlo o exigir que el commit nombre su workstream.

Ninguna objeción contradice las conclusiones en su letra. C-314 se sostiene por las reglas de `validate`, C-315 por un control discriminante, y C-316 a C-320 los verifiqué en los datos. Lo que no está verificado (la prueba en vivo) está declarado y, por la naturaleza del cambio, solo puede comprobarse en una sesión nueva.

VEREDICTO: aprueba