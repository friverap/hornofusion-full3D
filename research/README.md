# research/ — workspace del harness co-investigador

Réplica para EAF3D del diseño de *AI co-mathematician* (Zheng et al., DeepMind
2026, arXiv 2605.06651): un coordinador (la sesión principal) con el usuario,
workstreams por meta, un *working paper* por workstream, un panel de revisores
que debe aprobar por unanimidad y un registro permanente de lo que funcionó y
de lo que NO. Añadido propio: **pre-registro** de predicciones con criterio
numérico congelado.

## Archivos

| Ruta | Qué es |
|---|---|
| `QUESTION.md` | Pregunta de investigación y metas G1..Gn aprobadas por el usuario (`/pregunta`) |
| `ledger.jsonl` | Registro append-only de afirmaciones. **Solo** se escribe con `scripts/research/ledger.py add` |
| `ws/<WS>/status.json` | Estado del workstream y su compuerta de cierre (`ledger.py ws-init / ws-set`) |
| `ws/<WS>/report.md` | Working paper del workstream |
| `ws/<WS>/reviews/r<N>-<revisor>.md` | Revisión de la ronda N |

## Afirmaciones (`ledger.jsonl`)

Tipos: `hipotesis`, `prediccion` (lleva `criterio`, nace `pre-registrada`),
`resultado`, `veredicto` (juzga una predicción o su enmienda), `enmienda`
(cambia el criterio de una predicción AÚN NO juzgada; exige `motivo`).

Estados: `propuesta`, `pre-registrada`, `soportada` (exige rutas que existan y
comando de reproducción), `refutada`, `en_disputa`, `fallida`, `enmendada`,
`sin_decidir` (cierre de una afirmación cuyo criterio dio la banda intermedia,
o de un resultado que solo registra ese «sin decidir» de otra predicción: no
soportada ni refutada; solo como `resultado` con `ref` a una afirmación aún no
cerrada; WS-K12).

Reglas (las verifica `ledger.py check`):
- Nada se borra ni se edita: una corrección es un evento nuevo con `ref`.
- Un criterio se escribe ANTES de correr el experimento. Si después resulta
  mal planteado se registra una `enmienda` con motivo (visible) o una
  predicción nueva; nunca se reinterpreta el resultado en el texto.
- Las refutadas y fallidas son permanentes: antes de proponer un cambio se
  consulta `ledger.py open` (sección de refutadas) y `.claude/rules/acople-pv.md`.
  Son ABSORBENTES (`validate`, WS-K13): ningún evento posterior cita con
  `--ref` una hipótesis, predicción o resultado cuyo estado vigente sea
  refutada o fallida, ni a sus enmiendas (ni nota, ni hija, ni otro juicio, ni
  `sin_decidir`). Quien la retome registra una afirmación NUEVA sin `--ref`, o
  con `--ref` a su VEREDICTO (práctica del registro: C-226 → C-225, C-263 →
  C-256); `open` lista esas hijas no raíz mientras sigan abiertas.
- Una PREDICCIÓN se juzga solo con un VEREDICTO: un `resultado` sobre ella o
  su enmienda es una nota (propuesta) o un cierre `sin_decidir`. Una predicción
  CERRADA (veredicto de cierre en su cadena, o estado vigente cerrado, incluido
  `sin_decidir`) es DEFINITIVA: nada la cita ni a sus enmiendas, tampoco otro
  veredicto. Una predicción con veredicto (aunque sea `en_disputa`) ya no admite
  notas directas: la nota va con `--ref` al veredicto (como C-308 → C-093).
- Un CIERRE (`resultado` refutada, fallida o `sin_decidir` con `--ref`) es el
  sitio de las precisiones y retomas: admite una nota (`resultado` propuesta)
  o una predicción/hipótesis hija, nada más, y no reabre lo que cierra. Así se
  precisa o retoma una predicción definitiva, o una afirmación refutada,
  fallida o `sin_decidir` (C-110 vía C-304).
- Una hipótesis o resultado cerrado `sin_decidir` admite además una
  PREDICCIÓN hija directa (la retoma), que la reabre; no admite notas
  directas (van al cierre).
- Las enmiendas solo cambian el criterio de una PREDICCIÓN.
- Una hipótesis nace `propuesta` (como una predicción nace `pre-registrada`), y
  ni una hija (predicción o hipótesis) ni una nota (`resultado` propuesta)
  cambian el estado vigente de una PREDICCIÓN: a la predicción solo la juzga
  su veredicto (WS-K13). Una enmienda encadenada también trae el criterio
  NUEVO. Una hipótesis o resultado
  soportado sí admite eventos posteriores: una hija o una nota lo reabre, y un
  resultado puede refutarlo (C-031 → C-013).
- Las cerradas `sin_decidir` las lista `ledger.py open` («cerradas sin
  decidir») y su motivo se lee con `ledger.py show C-nnn`. La pregunta que
  dejaron abierta solo se retoma con una predicción NUEVA. Si la afirmación es
  una hipótesis o un resultado, la retoma la cita y la reabre (sale de esa
  lista); si es una PREDICCIÓN (definitiva), la retoma cita su cierre o su
  veredicto, la predicción sigue en la lista y la hija sale en «NO raíz
  abiertas» de `open`.
- Enmiendas y veredictos (WS-K13): la cadena de enmiendas es LINEAL; una
  enmienda o un veredicto van sobre la ÚLTIMA enmienda (el criterio vigente),
  nunca sobre un eslabón ya enmendado. Una predicción tiene a lo sumo UN
  veredicto en toda su cadena: un segundo juicio es una predicción nueva. Una
  afirmación ya juzgada o cerrada no admite enmiendas. `sin_decidir` solo
  cierra una afirmación no cerrada cuya cadena no tenga veredicto de cierre
  (soportada, refutada o fallida); tras un veredicto `en_disputa` sí cabe.
- Estado vigente (`current_state`): se recorre el registro en orden y vale el
  último evento que la cita con `--ref` (una enmienda la deja «enmendada») o el
  último veredicto sobre una enmienda de su cadena, cada uno en SU posición.
  Una nota que cite una enmienda no la juzga. Un veredicto conserva su propio
  estado: las notas que lo precisan no lo cambian. El veredicto de una
  predicción HIJA no se propaga a la madre: la madre se cierra con un
  `resultado` propio (regla de WS-K12); `open` avisa «hija juzgada» junto a
  cada madre abierta cuya hija DIRECTA (predicción con `--ref` a la madre) está
  cerrada; las hijas colgadas de un resultado intermedio no se avisan.

## Working paper (`report.md`)

- Explica el PROCESO que llevó al resultado, no solo el resultado.
- Cada afirmación lleva su id: `... la presión ya no alterna {C-012}`.
- Nota de procedencia al margen tras cada número:
  `> [fuente: campaigns/b1/k1_342/audit.csv | python3 scripts/diag/regime2.py ... --w 342.45,342.56]`
- Enlaces internos a planes (`docs/PLAN_*.md`), auditorías y corridas.
- Sección final «Incertidumbre»: lo no verificado, lo en disputa y por qué.

## Cierre de un workstream

1. Los tres revisores (`auditor-eaf3d`, `revisor-evidencia`,
   `revisor-refutador`) aprueban en la MISMA ronda (máx. 3 rondas; la 3.ª con
   un revisor de evidencia fresco). Sin consenso → `sin_terminar` y aviso al
   usuario; el reporte queda.
2. `make test-quick` verde sobre el diff staged → `ws-set WS test_quick=ok diff_sha=auto`.
3. Si el cambio es numérico: predicción pre-registrada con veredicto FIRME
   (`soportada` o `refutada`, `FIRMES` en `ledger.py`); un veredicto
   `en_disputa` (aunque se cierre `sin_decidir`) o `fallida` no basta (WS-K14).
4. El hook `guard_cierre.sh` bloquea `git commit` de `src/`, `tests/`,
   `scripts/research/`, `.claude/hooks/`, `.claude/workflows/`,
   `.claude/agents/` o `.claude/settings.json` (la herramienta del registro,
   el panel y su conexión, WS-K13) si `ledger.py gate` no pasa para ese diff
   exacto; `diff_sha` cubre esas rutas (`GATED` en `ledger.py`). La compuerta
   la decide el `ledger.py` de HEAD (la herramienta ya aprobada), no el staged
   ni el del disco; el del índice solo si HEAD no lo tiene, y el del disco solo
   si tampoco el índice (repo nuevo). Borrar o renombrar la herramienta no
   apaga la compuerta (`git diff --cached --no-renames`). Consecuencia: el
   commit que cambia la propia compuerta (`staged_sha`, `GATED`,
   `gate_errors`) se juzga con la de HEAD, así que su `diff_sha` y su
   `test_quick` se fijan con el `ledger.py` de HEAD (`git show
   HEAD:scripts/research/ledger.py > $T; python3 $T ws-set ...`). Para atar
   el resto del cambio, `status.json` lleva además `diff_sha_gated` (sha256 de
   `git diff --cached -- <rutas de GATED>`), y justo antes del commit de
   arranque se comprueba a mano que el staged lo reproduce.
   El hook también es el de HEAD (WS-K14): `.claude/settings.json` lo carga
   con `git show HEAD:.claude/hooks/guard_cierre.sh` y solo usa el del disco
   si HEAD no lo tiene, así que un hook debilitado en el disco no decide su
   propio commit. Límite: Claude Code toma los hooks de `settings.json` al
   iniciar la sesión; un `settings.json` cambiado en el disco (sin commit) rige
   desde la sesión siguiente. Las sesiones que se lanzan desde `~/Horno` usan
   `~/Horno/.claude/settings.json`, fuera del repo y sin versionar (C-320).
   Límites de «HEAD = aprobado» (C-318): el hook solo vigila el subcomando
   `git commit`; `cherry-pick`, `revert`, `am`, `merge`, `rebase`, `reset` y
   `commit-tree` + `update-ref` mueven HEAD sin compuerta, y entonces el hook
   y el `ledger.py` «de HEAD» no son necesariamente los que aprobó un panel.
   Solo `pore-ramp` tiene el hook: en las demás ramas rige el del disco y, si
   no está ni en HEAD ni en el disco, la herramienta se PERMITE (el `exec`
   falla sin JSON). Tampoco ata `status.json` (C-319): no está en `GATED`,
   `numerico` lo declara el propio workstream y `prediccion` acepta cualquier
   id. Es una barrera contra errores de proceso, no contra quien reescribe
   HEAD o el estado del workstream.

Estados de un workstream (`status.json`): `abierto`, `en_revision`,
`aprobado` (el panel aprobó el reporte), `sin_terminar` (sin consenso en 3
rondas) y `fallido`: el panel aprobó por unanimidad un reporte de CIERRE que
concluye que la meta no se cumplió (refutada o sin objeto). Los veredictos de
los revisores quedan en `status.json` y la clave `cierre` dice el motivo en
una línea (`ledger.py open` la muestra). `ledger.py check` lo exige: un
`fallido` sin `cierre` o sin los tres «aprueba» en la ronda vigente es error.
Un workstream `fallido` no abre la compuerta de commit.

## Reportar al usuario

El estado de los hallazgos o de un plan se reporta desde el registro
(`/estado`, `ledger.py open`), no de memoria: aplicado ≠ verificado ≠ cerrado.
