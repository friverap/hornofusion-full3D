export const meta = {
  name: 'workstream',
  description: 'Panel de cierre de un workstream EAF3D: 3 revisores (codigo, evidencia, refutador) hasta unanimidad, max 3 rondas',
  whenToUse: 'Desde la skill /workstream, con los cambios del workstream ya STAGED y el reporte escrito en research/ws/<WS>/report.md',
  phases: [
    { title: 'Precheck', detail: 'workstream, reporte, prediccion pre-registrada' },
    { title: 'Revision', detail: 'panel de 3 revisores en paralelo; ronda 1 ciega' },
    { title: 'Respuesta', detail: 'el redactor corrige el REPORTE o escala al coordinador' },
    { title: 'Cierre', detail: 'escribe revisiones y status.json' },
  ],
}

// args: { ws: 'WS-K1', max_rounds?: 3 }
// Replica el proceso de revision de AI co-mathematician (arXiv 2605.06651,
// §3.4 y §7): revisores persistentes, unanimidad, tope de rondas con escalada
// ("sin terminar"), y contra el falso consenso: ronda 1 ciega, veredictos con
// datos recalculados y un revisor de evidencia FRESCO (sin historial) en la
// ultima ronda. El workflow NO toca src/ ni lanza simulaciones: si una
// objecion exige codigo o un experimento, escala al coordinador.
const WS = args && args.ws
if (!WS) throw new Error('args.ws es obligatorio (p. ej. {ws: "WS-K1"})')
const MAX = (args && args.max_rounds) || 3
const DIR = `research/ws/${WS}`

const PRE = {
  type: 'object',
  properties: {
    ok: { type: 'boolean' },
    motivo: { type: 'string' },
    numerico: { type: 'boolean' },
    prediccion: { type: 'string' },
    resumen_reporte: { type: 'string' },
  },
  required: ['ok', 'motivo'],
}
const VERDICT = {
  type: 'object',
  properties: {
    veredicto: { type: 'string', enum: ['aprueba', 'rechaza'] },
    objeciones: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          texto: { type: 'string' },
          dato_que_la_resuelve: { type: 'string' },
          bloqueante: { type: 'boolean' },
        },
        required: ['id', 'texto', 'dato_que_la_resuelve', 'bloqueante'],
      },
    },
    verificado: { type: 'array', items: { type: 'string' } },
    revision_md: { type: 'string' },
  },
  required: ['veredicto', 'objeciones', 'revision_md'],
}
const RESP = {
  type: 'object',
  properties: {
    respuestas: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          revisor: { type: 'string' },
          id: { type: 'string' },
          accion: { type: 'string', enum: ['corregido_en_reporte', 'refutada_con_dato', 'requiere_coordinador'] },
          detalle: { type: 'string' },
        },
        required: ['revisor', 'id', 'accion', 'detalle'],
      },
    },
  },
  required: ['respuestas'],
}

const REVIEWERS = [
  { key: 'auditor-eaf3d', agentType: 'auditor-eaf3d',
    task: 'Revisa el CODIGO del diff staged (git diff --cached) contra el reporte: defectos reales con escenario de fallo. ' +
          'Un hallazgo ALTO o MEDIO sin resolver es objecion bloqueante.' },
  { key: 'revisor-evidencia', agentType: 'revisor-evidencia',
    task: 'Recalcula cada numero del reporte desde los datos y juzga contra el criterio PRE-REGISTRADO del registro.' },
  { key: 'revisor-refutador', agentType: 'revisor-refutador',
    task: 'Intenta refutar las conclusiones del reporte: alternativas, confusores, repeticion de fracasos registrados.' },
]

phase('Precheck')
const pre = await agent(
  `Precheck del workstream ${WS} del harness co-investigador (lee research/README.md). SOLO LECTURA.\n` +
  `1. ${DIR}/status.json existe y su estado es 'en_revision' (lo pone la skill /workstream al stagear). ` +
  `2. ${DIR}/report.md existe y cita afirmaciones {C-nnn} que existen en el registro (python3 scripts/research/ledger.py show C-nnn). ` +
  `3. 'python3 scripts/research/ledger.py check' pasa. ` +
  `4. Si status.numerico es true: status.prediccion apunta a una prediccion del registro con criterio. ` +
  `5. 'git diff --cached --stat' no esta vacio si el workstream toca codigo (si no toca codigo, dilo). ` +
  `Devuelve ok=false con el motivo exacto si algo falla; resumen_reporte = 5 lineas del reporte.`,
  { label: 'precheck', phase: 'Precheck', schema: PRE, effort: 'low' })
if (!pre || !pre.ok) {
  log(`Precheck fallido: ${pre ? pre.motivo : 'sin respuesta'}`)
  return { ws: WS, estado: 'bloqueado', motivo: pre ? pre.motivo : 'precheck sin respuesta' }
}

const history = { 'auditor-eaf3d': [], 'revisor-evidencia': [], 'revisor-refutador': [] }
let round = 0, last = null, escalate = null
while (round < MAX) {
  round += 1
  phase('Revision')
  log(`Ronda ${round} de ${MAX}`)
  const fresh = round === MAX && MAX > 1
  const verdicts = await parallel(REVIEWERS.map(r => () => {
    const own = (fresh && r.key === 'revisor-evidencia') ? [] : history[r.key]
    const prev = own.length
      ? `\n\nTus rondas anteriores (eres el MISMO revisor; mantén tus objeciones salvo que el reporte o los datos las resuelvan):\n` +
        JSON.stringify(own, null, 1)
      : (round > 1 ? '\n\nEres un revisor FRESCO en la ultima ronda: no veas revisiones anteriores; juzga desde cero.' : '')
    return agent(
      `Panel de cierre, workstream ${WS}, ronda ${round}. ${r.task}\n` +
      `Reporte: ${DIR}/report.md. Registro: research/ledger.jsonl (ledger.py show/open). ` +
      `No leas ${DIR}/reviews/ de otros revisores (revision ciega). ` +
      `Prohibido aprobar por redaccion o confianza: lo no verificado es una objecion. ` +
      `revision_md = tu revision completa en markdown (se guardara en ${DIR}/reviews/r${round}-${r.key}.md).` + prev,
      { label: `r${round}:${r.key}${fresh && r.key === 'revisor-evidencia' ? ' (fresco)' : ''}`,
        phase: 'Revision', agentType: r.agentType, schema: VERDICT })
      .then(v => ({ key: r.key, v }))
  }))
  last = verdicts.filter(Boolean).filter(x => x.v)
  const missing = REVIEWERS.map(r => r.key).filter(k => !last.some(x => x.key === k))
  for (const x of last) history[x.key].push({ ronda: round, veredicto: x.v.veredicto, objeciones: x.v.objeciones })
  const approve = last.filter(x => x.v.veredicto === 'aprueba').map(x => x.key)
  log(`Ronda ${round}: aprueban ${approve.join(', ') || 'nadie'}${missing.length ? '; sin respuesta: ' + missing.join(', ') : ''}`)
  if (approve.length === REVIEWERS.length) break
  if (round === MAX) break

  phase('Respuesta')
  const objections = last.filter(x => x.v.veredicto === 'rechaza')
    .map(x => ({ revisor: x.key, objeciones: x.v.objeciones }))
  const resp = await agent(
    `Eres el redactor del workstream ${WS}. Responde a CADA objecion del panel (ronda ${round}):\n` +
    JSON.stringify(objections, null, 1) + '\n\n' +
    `Puedes editar SOLO ${DIR}/report.md y anadir eventos al registro con 'python3 scripts/research/ledger.py add' ` +
    `(nunca editar ledger.jsonl a mano; nunca tocar src/, tests/ ni lanzar make/mpirun/simulaciones). ` +
    `Para cada objecion: 'corregido_en_reporte' (corregiste o retiraste la afirmacion; una afirmacion que no puedes sostener se ` +
    `RETIRA o se marca en la seccion Incertidumbre, nunca se suaviza para complacer), 'refutada_con_dato' (cita ruta y valor que ` +
    `la refutan), o 'requiere_coordinador' (exige cambiar codigo, correr un experimento o decidir algo del usuario). ` +
    `No cambies criterios pre-registrados: eso solo lo hace el coordinador con una enmienda.`,
    { label: `respuesta r${round}`, phase: 'Respuesta', agentType: 'general-purpose', schema: RESP })
  const needs = resp ? resp.respuestas.filter(a => a.accion === 'requiere_coordinador') : []
  for (const r of REVIEWERS) {
    const mine = resp ? resp.respuestas.filter(a => a.revisor === r.key) : []
    if (history[r.key].length) history[r.key][history[r.key].length - 1].respuesta_del_redactor = mine
  }
  if (!resp || needs.length) {
    escalate = resp ? needs : [{ detalle: 'el redactor no respondio' }]
    log(`Escala al coordinador: ${escalate.length} objecion(es) exigen codigo, experimento o decision`)
    break
  }
}

phase('Cierre')
const allApprove = last && last.length === REVIEWERS.length && last.every(x => x.v.veredicto === 'aprueba')
const estado = allApprove ? 'aprobado' : (escalate ? 'en_revision' : 'sin_terminar')
const files = (last || []).map(x => ({ path: `${DIR}/reviews/r${round}-${x.key}.md`, md: x.v.revision_md }))
const setArgs = [`ronda=${round}`, `estado=${estado}`]
  .concat((last || []).map(x => `revisor.${x.key}=${x.v.veredicto}`))
await agent(
  `Escribano del workstream ${WS}. Haz EXACTAMENTE esto y nada mas:\n` +
  `1. Escribe estos archivos (crea ${DIR}/reviews/ si falta), contenido literal:\n` +
  JSON.stringify(files, null, 1) + '\n' +
  `2. Ejecuta: python3 scripts/research/ledger.py ws-set ${WS} ${setArgs.join(' ')}\n` +
  `3. Ejecuta: python3 scripts/research/ledger.py check\n` +
  `No edites ningun otro archivo. Devuelve la salida de los comandos.`,
  { label: 'escribano', phase: 'Cierre', agentType: 'general-purpose', effort: 'low' })

const objecionesVivas = (last || []).filter(x => x.v.veredicto === 'rechaza')
  .map(x => ({ revisor: x.key, objeciones: x.v.objeciones.filter(o => o.bloqueante) }))
return {
  ws: WS, estado, rondas: round,
  veredictos: (last || []).map(x => ({ revisor: x.key, veredicto: x.v.veredicto, n_objeciones: x.v.objeciones.length })),
  escala_al_coordinador: escalate,
  objeciones_vivas: objecionesVivas,
  siguiente: allApprove
    ? 'correr make test-quick sobre el MISMO staged y luego ledger.py ws-set ' + WS + ' test_quick=ok; la compuerta compara diff_sha'
    : 'el coordinador resuelve las objeciones (codigo/experimento/decision del usuario) y relanza /workstream',
}
