---
name: workstream
description: Cierra un workstream del harness co-investigador de EAF3D por el panel de revisión (Workflow guardado 'workstream': auditor-eaf3d + revisor-evidencia + revisor-refutador, unanimidad, máx. 3 rondas) y la compuerta de commit (test-quick + diff_sha). Invocarla es el opt-in del usuario para lanzar ese Workflow.
argument-hint: "<WS> [max_rounds]"
---

Panel de cierre del workstream `$ARGUMENTS`.

1. Prerrequisitos (si falta algo, para y dilo):
   - `research/ws/<WS>/status.json` existe (`ledger.py ws-init`).
   - `research/ws/<WS>/report.md` escrito según `research/README.md`: proceso,
     afirmaciones `{C-nnn}` del registro, nota de procedencia (ruta | comando)
     tras cada número, sección «Incertidumbre».
   - Si el cambio es numérico: predicción pre-registrada (`/preregistro`) con
     veredicto registrado.
   - Sin simulación en curso que vaya a cambiar los datos citados.
2. Stagea EXACTAMENTE los archivos del workstream (`git add <rutas>`, nunca
   `-a`) y fija el diff revisado:
   `python3 scripts/research/ledger.py ws-set <WS> estado=en_revision diff_sha=auto`.
3. Lanza `Workflow({name: 'workstream', args: {ws: '<WS>', max_rounds: N}})`
   (N por defecto 3). No dupliques el trabajo de los revisores mientras corre.
4. Resultado:
   - `aprobado`: corre `make test-quick` SIN tocar el staged (si hay una
     simulación activa el hook lo bloquea: espera). Si pasa,
     `ledger.py ws-set <WS> test_quick=ok` y commitea con `git commit -m`
     (la compuerta `guard_cierre.sh` verifica el mismo diff).
   - `escala_al_coordinador`: lo que pide código, un experimento o una
     decisión del usuario lo haces tú (o lo preguntas); luego relanza desde 2.
   - `sin_terminar`: reporta al usuario las objeciones vivas tal cual, con
     las rutas de `reviews/`; no las resumas a favor del cambio.
5. Cualquier cambio del staged tras la revisión invalida la aprobación
   (diff_sha): se vuelve a 2.
