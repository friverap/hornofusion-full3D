---
name: estado
description: Divulgación progresiva del harness co-investigador — resumen de una pantalla de la pregunta, metas, workstreams y afirmaciones (abiertas, en disputa, refutadas) leído del registro research/, no de memoria. Úsala cuando el usuario pregunte cómo va algo o cuántos hallazgos están resueltos.
argument-hint: "[WS]"
---

Estado del harness (`$ARGUMENTS` = un workstream para ver su detalle).

1. Fuente única: `research/QUESTION.md`, `python3 scripts/research/ledger.py open`,
   `ledger.py check` y `research/ws/*/status.json` (y `report.md` del WS pedido).
   No reportes nada que no esté ahí; si algo no está registrado, di «no
   registrado» en vez de reconstruirlo de memoria.
2. Formato para el usuario (en su idioma, sin jerga innecesaria):
   - Pregunta y metas, una línea cada una.
   - Tabla de workstreams: meta, estado (abierto / en revisión / aprobado /
     sin terminar / fallido), ronda, quién aprueba y quién no.
   - Afirmaciones: cuántas abiertas, en disputa, soportadas y refutadas; las
     en disputa y las predicciones pendientes de veredicto, listadas.
   - Distingue SIEMPRE aplicado ≠ verificado ≠ cerrado (commit con compuerta).
3. Si `ledger.py check` falla, dilo primero.
4. Con `[WS]`: el resumen del reporte, sus afirmaciones con estado y las
   objeciones vivas de la última ronda (`reviews/`), con rutas.
