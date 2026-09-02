# Tests de regresión — EAF3D

## Uso

```bash
make test-quick        # gate por commit (~1 min): corrida fría -n 8 + invariantes + métricas
make test-full         # gate por etapa (~5-10 min): unit tests + matriz {configs}×{-n 1,4,6,8}
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
  rtol 1e-12). Entre distintos nº de ranks el resultado NO es bitwise
  (interfaces TDMA retardadas, SOR): tolerancia 1e-3 (post C1.2) → 1e-6
  (post Etapa 2), endureciendo solo vía más iteraciones internas del config.

## Estructura

| Ruta | Qué es |
|---|---|
| `unit/*.f90` | Unit tests de kernels (TDMA, métricas de malla, cp_eff, parser, Ergun) |
| `integration/configs/*.dat` | Corridas cortas: `cold_10step` (regresión fría), `melt_forced` (fusión desde el paso 1, T_init=1815 K), `symmetry_3elec` (simetría 120°), `noflow_energy` (balance térmico sin flujo) |
| `integration/check_invariants.py` | NaN, 0≤α≤1, Σα∈{0,1}, cotas de T e Y, k/ε≥0 |
| `integration/check_melt.py` | Conservación de masa en fusión: Δm_liq = −Δm_sol |
| `integration/compare_decomposition.py` | Invarianza al nº de ranks MPI |
| `integration/check_symmetry.py` | Invarianza a rotación de 120° |
| `integration/check_audit.py` | Balances de `audit.csv` (existe desde C0.2) |
| `integration/metrics_snapshot.py` | Golden de métricas escalares |
| `xfail.list` | Fallos esperados pendientes de fix |

Los outputs van a `tests/out/` (ignorado por git); cada corrida guarda su
`config.dat` efectivo y su `run.log`. El runner falla si el log contiene
`[CONFIG] WARNING` (typo de clave).
