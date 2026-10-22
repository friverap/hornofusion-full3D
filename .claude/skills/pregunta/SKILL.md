---
name: pregunta
description: Fase inicial del harness co-investigador (AI co-mathematician §3.1) — refina con el usuario la pregunta de investigación y las metas G1..Gn ANTES de trabajar, y las deja aprobadas en research/QUESTION.md. Úsala al empezar una línea de trabajo nueva o cuando el objetivo cambie.
argument-hint: "<tema o pregunta en borrador>"
---

Refinar la intención de `$ARGUMENTS` antes de gastar cómputo.

1. Lee `research/README.md`, `research/QUESTION.md` (si existe) y
   `python3 scripts/research/ledger.py open` (sobre todo las refutadas: no
   proponer metas que repitan un fracaso registrado sin decir en qué difieren).
2. Redacta: la PREGUNTA (una frase falsable: qué se mide, dónde, contra qué
   base), 2-5 METAS G1..Gn (cada una con su entregable y su criterio de
   terminado) y lo que queda FUERA de alcance.
3. Pregunta al usuario con AskUserQuestion lo que cambie el trabajo (alcance,
   criterio de éxito, prioridad entre metas). No asumas el criterio de éxito.
4. Con la aprobación, escribe `research/QUESTION.md` con fecha y «Aprobado
   por el usuario» (si ya existía, la versión anterior va a una sección
   «Historial», no se borra), crea un workstream por meta con
   `python3 scripts/research/ledger.py ws-init WS-<id> --meta G<n> [--numerico]`
   y commitea solo `research/`.
5. Las hipótesis que motivan las metas se registran con
   `ledger.py add --tipo hipotesis ...`; las predicciones con criterio van por
   `/preregistro`, antes de cada experimento.
