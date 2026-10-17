---
name: gate-banco
description: Corre un banco de tests/integration/configs con overrides (p.ej. t_final, slag_in_volume) en el scratchpad y resume el gate (u_liq, vol_lim, u_gas, p por segundo; volfix; capa de escoria) con check_audit y check_slag_bed. Usala para validar un cambio de modelo en un regimen concreto antes de la matriz.
argument-hint: "<banco> [ranks] [clave=valor ...]"
---

Gate del banco `$0` con `$1` ranks (si no se da: 4) y los overrides que sigan en `$ARGUMENTS`.

1. Sin simulaciones en curso (las corridas son secuenciales).
2. Directorio `<scratch>/gate_$0_<etiqueta>`: copia
   `tests/integration/configs/$0.dat`, anade los overrides `clave = valor`
   y `output_dir`.
3. `mpirun -n <ranks> bin/eaf3d_mpi <dir>/config.dat > <dir>/run.log 2>&1`
   en segundo plano si dura mas de ~2 min (arma un Monitor que avise de
   cada 100 pasos y de ABORT/NaN/AVISO).
4. Resumen: `python3 scripts/diag/gate_summary.py <dir>`,
   `python3 tests/integration/check_audit.py <dir>` y, con escoria,
   `python3 tests/integration/check_slag_bed.py <dir>` con los argumentos
   del banco que use `tests/run_tests.sh`.
5. Ante un blow-up: protocolo del proyecto (parar, localizar el primer paso
   y celda que se desvia con snapshots por paso, diagnosticar la causa raiz
   antes de parchar).
