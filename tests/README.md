# Tests de regresión — EAF3D

## Uso

```bash
make test-quick        # gate por commit (~1.5 min): corrida fría -n 8 + bath_test + arc_melt (fusión bajo arco) + bed_bath_rest (lecho inundado en reposo, M5-8) + invariantes + métricas
make test-full         # gate por etapa (~5-10 min): unit tests + matriz {configs}×{-n 1,4,6,8,9,12} (los np exactos por banco en `run_tests.sh`)
make test-unit         # solo unit tests Fortran
STAGE=v1 make test-rebaseline   # regenera el golden de métricas (una vez por etapa)
```

## Principios

- **Los tests permanentes verifican invariantes** (balances, cotas, simetría,
  invarianza de descomposición MPI) y **nunca se re-baselinean**.
- Los valores numéricos concretos viven en `golden/metrics_v<etapa>.json`
  (solo escalares min/max/mean por campo del snapshot final — nunca campos
  completos) y se regeneran **una vez al cierre de cada etapa** del roadmap,
  con revisión manual del diff (el cambio debe ser explicable por el fix).
- **XFAIL** (`xfail.list`): fallos esperados hasta que aterrice su fix. La
  entrada se elimina en el mismo commit que el fix; un XPASS lo recuerda.
- Determinismo: mismo binario + mismo nº de ranks ⇒ misma salida (métricas a
  rtol 1e-12). Entre distintos nº de ranks el resultado NO es bitwise (el
  depósito del MC se reduce con MPI_SUM): las comparaciones de descomposición
  de la matriz van de 1e-12 (sin flujo: ecs_test, cold_10step) a 5e-4
  (bed_drain); con flujo y fases el nivel medido es 1e-8..1e-5. Cada
  tolerancia lleva en `run_tests.sh` lo medido (auditoría 20, M20-7).

## Estructura

| Ruta | Qué es |
|---|---|
| `unit/*.f90` | Unit tests de kernels y de cada arreglo (descubiertos por `make test-unit`: todo `unit/*.f90`). Entre los recientes: `test_dispersed_liquid` (caso 5: histéresis de la película), `test_transport_f28` (Plan J-B, caras r/θ/z), `test_pore_floor` (rampa del piso de poro), `test_drift_source` (E2), `test_slag_ox_column` (Plan I1), `test_slag_reduction`, `test_slag_contact` |
| `integration/configs/*.dat` | Corridas cortas: `cold_10step` (regresión fría), `melt_forced` (fusión desde el paso 1, T_init=1815 K), `symmetry_3elec` (simetría 120°), `noflow_energy` (balance térmico sin flujo), `bath_test` (charco de líquido puro en reposo, Bug 19) y `bath_fill` (charco + fusión forzada, Bug 19) |
| `integration/check_invariants.py` | NaN, 0≤α≤1, Σα∈{0,1}, cotas de T e Y, k/ε≥0 |
| `integration/check_melt.py` | Conservación de masa en fusión: Δm_liq = −Δm_sol |
| `integration/compare_decomposition.py` | Invarianza al nº de ranks MPI |
| `run_restart_case` (en `run_tests.sh`) | Reinicio desde snapshot (`restart_file`): reanuda `cold_10step` desde el paso 5 (n8→n8 en quick; n8→n4 y `melt_forced` paso 6 en full; además, entre otros, `bed_flood` paso 750 con película en la banda de histéresis, `ecs_slag` paso 30 y `cold_bucket2_slag` pasos 5 y 15, antes y después de la carga) y exige snapshot final BIT A BIT (`compare_decomposition` a 1e-12) contra la corrida continua con el mismo nº de ranks; con distinto nº aplica la tolerancia de descomposición (1e-10; medido 8.5e-13). Además (auditoría 4, B4-19) el tramo reanudado pasa invariantes y audit, y su `audit.csv` coincide bit a bit con el de la continua (`compare_audit.py`, filas `step > st`). Vive en `tests/out/restart/` (fuera del golden) |
| `integration/compare_audit.py` | `audit.csv` de un reinicio frente a la corrida continua, columna a columna |
| `integration/check_symmetry.py` | Invarianza a rotación de 120° |
| `integration/check_audit.py` | Balances de `audit.csv` (energía total y por paso, masas, arco, radiación, centinelas, techo de ajustes de escoria) |
| `oneflow_test` (full) | Rama legada de UNA fase (`solve_multiphase = false`) sobre el baño en reposo de `bath_test`, con `check_bath.py`; vigila que no empeore (masa, α congelada, centinelas); reposo y energía en xfail con causa (B5-4) |
| `pocket_rise` (full) | Bolsa de gas bajo una capa saturada del lecho (M4-12): reanuda desde un estado construido por `integration/make_pocket_init.py` sobre el paso 0 de `bed_bath_rest_n4` |
| `integration/check_pocket.py` | Criterio de `pocket_rise`: la capa saturada gana gas, la bolsa lo pierde y se despresuriza sin repuntes ni retención (presión de las capas 6–7 frente a la 9; M8-3) |
| `integration/check_slag_bed.py` | Capa de escoria: orden acero/escoria, T, masa (con `m_slag_clip` y su techo), volfix, saltos del soporte; con `--umax-liq/--umax-gas` el reposo de `slag_rest` |
| `integration/check_slag_chem.py` | Química de la escoria: Fe elemental, masa de escoria, actividad de oxidación y (`--min-return`) de reducción |
| bancos de escoria | `arc_slag`, `arc_melt_slag`, `arc_melt_slag_heel`, `slag_chem_flow`, `slag_chem_thick` (capa condensada gruesa), `slag_rest` (reposo con escoria condensada), `slag_chem_test` (sin flujo), `ecs_slag` (ECS que desplaza 60 t de escoria, `check_ecs.py --slag`) y `cold_bucket2_slag` (cesta 2 que atraviesa la escoria) |
| `check_drain.py` | `bed_drain`: el centroide del líquido baja ≥ 0.19 m, velocidad media 0.42..1.0 m/s, `bed_drain_outer` (máx. `vol_dalpha_outer` ≤ 2e-3 m³: el congelado del hueco de J-B) y `bed_drain_unlinked` (Σ\|`vol_unlinked`\| ≤ 1.0 m³: J-B) |
| `unit/test_condensed_*.f90` | Escoria condensada (Plan H): vista (ida y vuelta), transporte (bit a bit sin escoria, traslación, fallback, congelación) y reordenamiento (casos 1–7) |
| `../scripts/bitwise_check.sh` | Gate bit a bit del camino legado contra un binario de referencia (B1 corto y producción corta) |
| `../scripts/diag/gate_summary.py` | Resumen de un gate de banco (u_liq, vol_lim, u_gas, p por segundo; capa de escoria) |
| `integration/metrics_snapshot.py` | Golden de métricas escalares |
| `xfail.list` | Fallos esperados pendientes de fix |

Los outputs van a `tests/out/` (ignorado por git); cada corrida guarda su
`config.dat` efectivo y su `run.log`. El runner falla si el log contiene
`[CONFIG] WARNING` (typo de clave).
