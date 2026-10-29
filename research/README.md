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
- Las cerradas `sin_decidir` las lista `ledger.py open` («cerradas sin
  decidir») y su motivo se lee con `ledger.py show C-nnn`. La pregunta que
  dejaron abierta solo se retoma con una predicción NUEVA.

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
3. Si el cambio es numérico: predicción pre-registrada con veredicto.
4. El hook `guard_cierre.sh` bloquea `git commit` de `src/` o `tests/` si
   `ledger.py gate` no pasa para ese diff exacto.

## Reportar al usuario

El estado de los hallazgos o de un plan se reporta desde el registro
(`/estado`, `ledger.py open`), no de memoria: aplicado ≠ verificado ≠ cerrado.
