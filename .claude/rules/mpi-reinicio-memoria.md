---
paths:
  - "src/mod_restart.f90"
  - "src/mod_output_hdf5.f90"
  - "src/mod_mpi_topology.f90"
  - "src/mod_parallel_utils.f90"
  - "src/mod_mesh_3d.f90"
  - "src/main_3d.f90"
  - "tests/**"
  - "scripts/**"
  - "Makefile"
  - "src/mod_types_3d.f90"
  - "src/mod_config_3d.f90"
  - "src/mod_probe.f90"
  - "src/mod_timers.f90"
---

# MPI, halos, reinicio desde snapshot, memoria sin inicializar, harness de tests

Convenciones vigentes movidas TEXTUALMENTE desde CLAUDE.md (reestructuracion
harness, 16-oct-2026). Cada una existe por un fallo medido: no simplificar una
guarda sin leer su causa.

- **Frontera de BLOQUE ≠ frontera física**: toda condición de borde se
  escribe `(i > istart .or. .not. at_rmin)` (idem `iend`/`at_rmax`, z), nunca
  `i > 1`/`i < iend`: cinco sitios trataban el borde de cada bloque en r como
  pared (n12 2×3×2 difería 5e-2 de n1; oct-2026). `decomposition_cold_r`
  (n1 frente a n12) es la única comparación de la matriz que parte r.
- **Operaciones de columna global (colapso) y de arco**: patrón invariante a la
  descomposición (gather global + escritura de celdas propias).
- **`intent(out)` en dummies de tipo derivado que llegan PARCIALMENTE
  inicializados = basura (bug latente hasta oct-2026)**: `mesh_generate_parallel`
  recibía `mesh` (con `mesh%topo` ya llena) como `intent(out)`; el dummy queda
  indefinido al entrar y a -O0 la topología era basura (a -O2 sobrevivía por
  casualidad → halos basura esporádicos, NaN a n=2, reinicios no
  reproducibles). Regla: `intent(inout)` para todo tipo derivado que ya traiga
  estado; y `make debug` (-O0) DEBE arrancar — si no arranca, hay un
  indefinido, no un "problema de flags".
- **Un array asignado con `mold` y escrito solo en celdas propias NUNCA se
  copia entero a un campo (Bug 22, oct-2026)**: `liq%alpha = a_new` con
  `a_new` de `mold` dejaba los halos FÍSICOS (eje, pared, piso, techo,
  esquinas) con basura del heap — nadie los escribe ni los intercambia — y
  todo lo elemental de array completo (`liq_continuous`, `ws_liq_room`,
  máscaras de superficie libre) la leía: corridas no reproducibles según la
  presión de memoria de la máquina (idénticas unas veces, 10 % de
  diferencia otras; reinicio no bit a bit). Regla: `allocate(x, mold=f);
  x = f` y luego escribir lo propio. Detector definitivo: `malloc` interpuesto
  que rellena con NaN señalizante + `-O0 -ffpe-trap=invalid`
  (`scripts/diag/snanfill.c`): la primera aritmética sobre basura aborta con
  traza; `MallocPreScribble=1` solo delata que existe. Antes de cerrar
  cualquier gate de reinicio/invarianza, repetir la corrida fría dos veces
  en serie y compararla a 1e-12.
- **Reinicio desde snapshot (`restart_file`, sep-2026)**: todo snapshot es
  un estado completo (`/fields` + `/restart` + `/metadata`) y el reinicio
  es BIT A BIT contra la corrida continua (test `restart_*`; desde B4-19
  también su `audit.csv`, `compare_audit.py`, más invariantes y audit del
  tramo). **Todo snapshot cierra el intervalo del audit (B4-4)**: con
  `audit_freq > 1` el snapshot y el último paso escriben su línea, así el
  reinicio (que arranca su audit de cero) no pierde nada. Reanudar con
  `t_final ≤ time` no reescribe el origen (B4-5). `/mesh/cell_type` va en
  el snapshot (B4-21: `sum_alpha` exige 1 en activas, 0 en inactivas).
  **Harness (B4-18/22/23)**: NaN en una comparación es FAIL; sin
  `audit.csv` con `audit_freq ≠ 0` es FAIL; el rebaseline no escribe el
  golden si la matriz tiene fallos; el libro del gas lo decide el config
  (B4-24). Todo estado
  nuevo que persista entre pasos (campo, escalar, `save`) debe entrar en
  `write_restart_group`/`restart_read` en el mismo commit — si no, el test
  de reinicio lo delata. Las propiedades (`rho_gas`, `mu_eff_liquid`) se
  guardan tal como quedan al final del paso: la corrida continua arranca
  con las de la última iteración externa, no con las de la T final.
- **Coeficientes de ensamblado**: los 8 arrays (aW..aT, aP, Su) viven en
  `mod_workspace` (persistentes, C4.1). Todo ensamblador nuevo debe cerarlos
  completos antes de usarlos — esa es la condición que hace seguro
  compartirlos. Vale también para los halos: el intercambio MPI NO escribe
  los halos de frontera física (eje, piso, techo, pared); si un array de
  trabajo se lee ahí, hay que cerarlo COMPLETO en cada llamada (B1 v10:
  basura en `ws_Mr(0,:,:)`/`ws_Mz(:,:,0)` creó 143 t de líquido).
