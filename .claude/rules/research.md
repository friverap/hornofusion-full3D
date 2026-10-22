---
paths:
  - "research/**"
  - "scripts/research/**"
  - ".claude/workflows/**"
---

# Harness co-investigador: reglas al tocar `research/`

- `research/ledger.jsonl` solo con `python3 scripts/research/ledger.py add`
  (el hook `guard_cierre.sh` bloquea Edit/Write y redirecciones). Una
  corrección es un evento nuevo con `--ref`; nunca se borra un fracaso.
- Criterio de una predicción: numérico, con ventana, base (ruta de la corrida
  de referencia), tolerancia y comando de medida, escrito y commiteado ANTES
  de lanzar la corrida. Pensar la escala física antes (lección de H1 del
  Plan K: «|p| < 20 kPa» ignoraba la hidrostática de ~70 kPa del fondo).
- Comparaciones justas: mismo reinicio, misma ventana, mismo código salvo la
  clave probada; ventanas de ~30 pasos que empiezan con el ciclo en marcha
  son señal temprana, no veredicto.
- Un workstream no se da por cerrado en el chat: cerrado = `status.json`
  `aprobado` + `test_quick` del mismo diff + commit que pasó la compuerta.
- Los revisores del panel son de solo lectura; el redactor del workflow solo
  edita `report.md` y añade eventos. Código, experimentos y enmiendas los
  hace el coordinador (la sesión principal).
