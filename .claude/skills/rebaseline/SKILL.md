---
name: rebaseline
description: Protocolo de rebaseline del golden de metricas de EAF3D tras un cambio numerico INTENCIONAL (nueva etapa vN). Usala solo cuando el cambio de resultados esta explicado y verificado; nunca para tapar una regresion.
argument-hint: "<vN>"
---

Rebaseline a la etapa `$ARGUMENTS`.

1. Justifica el cambio numerico: que commit lo produce, en que bancos, y por
   que es intencional (con datos del banco o del gate). Los invariantes nunca
   se re-baselinean.
2. Sin simulaciones en curso (`pgrep -fl eaf3d`).
3. `STAGE=$ARGUMENTS make test-rebaseline` en segundo plano (~10 min). El
   harness solo escribe `tests/golden/metrics_$ARGUMENTS.json` si toda la
   matriz pasa: si hay FAIL, diagnostica (no edites el golden a mano).
4. Commit del golden junto con la explicacion (que bancos cambian y por que)
   y nota en el plan/auditoria correspondiente.
