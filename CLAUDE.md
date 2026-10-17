# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This file lives inside the git repo (`hornofusion-full3D/CLAUDE.md`, auditoría 5 B5-24; the parent `Horno/` only holds reference PDFs and a stub pointing here). All code lives in `hornofusion-full3D/` — **run every command from that directory**. Documentation and code comments are in Spanish; keep that convention.

**EAF3D** is a 3D multiphysics CFD simulator (Fortran 2008 + MPI + parallel HDF5) of scrap/HBI melting in a 130 t AC electric arc furnace, implementing Ugarte et al. (2024) *Materials* 17(21), 5139.

## Commands

```bash
# Build (from hornofusion-full3D/) → binary at bin/eaf3d_mpi
make              # -O2 + bounds check (development default)
make debug        # -O0 -g -fbacktrace (use for segfaults / out-of-range indices)
make opt          # -O3 -march=native (long production runs)
make clean

# Test suite (see tests/README.md; XFAILs esperados en tests/xfail.list)
make test-quick   # gate por commit (~1.5 min): corrida fría + bath_test + arc_melt + bed_bath_rest + invariantes + golden
make test-full    # gate por etapa (~5-10 min): unit + matriz MPI + simetría
make test-unit    # unit tests Fortran (tests/unit/*.f90: kernels, escoria condensada, config...; tope UNIT_TIMEOUT)
STAGE=vN make test-rebaseline   # regenerar golden tras un cambio numérico intencional

# Production run (mesh 60×120×84, 5040 s simulated)
mkdir -p output_prod2
make clean && make opt
mpirun -n 12 ./bin/eaf3d_mpi input/config_production_full.dat 2>&1 | tee run_production.log
tail -f output_prod2/monitor.log   # progress: step, time, solid mass, residuals

# Inspect output
h5ls -r output_prod2/eaf3d_00000200.h5

# Post-processing (Python 3, needs h5py/matplotlib; pyvista/skimage for some)
python3 postprocess/plot_insights.py [output_dir] [plots_dir]
python3 postprocess/render_3d_video.py [output_dir] [plots_dir]
python3 scripts/hdf5_to_vtk.py output/*.h5
```

Requirements (macOS): `brew install open-mpi hdf5-mpi`. The Makefile hardcodes Homebrew paths (`/opt/homebrew/include`, `/opt/homebrew/lib`).

**Choosing `-n`**: the domain decomposes in r × theta × z (`factorize_3d` picks the most cubic blocks); only `ntheta` must divide exactly, r/z remainders go to the last rank, and every local block needs ≥ 2 cells per direction (checked at startup, audit M32). Production mesh: 8 → 1×4×2, 12 → 2×3×2 (recommended on M4 Pro), 16 → 2×4×2, 24 → 2×4×3. See `docs/RUNNING.md` §3.


## Architecture

Detailed docs, read before non-trivial changes: `docs/ARCHITECTURE.md` (modules, types, MPI, resolved critical bugs), `docs/PHYSICS.md` (equations/models), `docs/CONFIGURATION.md` (all config keys), `docs/OUTPUT.md` (HDF5 format). `docs/dev-history/` is historical debugging context only.

- **~30 modules in `src/`, one concern each** (`mod_energy_3d`, `mod_arc_cassie_mayr`, …). `main_3d.f90` runs the time loop: arc (Cassie–Mayr → MC radiation → Lorentz) → DO radiation (S4, 24 direcciones) → carbon chemistry (O₂ finito) → especies O₂/CO/CO₂ → SIMPLE outer loop (Ergun drag, momentum, corrección de presión CG, energía, k-ε) → solid phase update → slag → dt por CFL → HDF5 output.
- **Adding a module requires editing the Makefile twice**: append to `SRCS` in topological order AND add its explicit `.o` dependency rule (module order matters; `.mod` files go to `obj/` via `-J`).
- **All 3D arrays carry 2-cell halos**: allocated `(-1:nr+2, -1:nth+2, -1:nz+2)`; physical indices are `1:n`. After updating any field needing cross-rank coherence, call the matching halo exchange (`phase_exchange_halos`, `solid_exchange_halos`, `slag_exchange_halos`, or `mpi_exchange_halos_3d` directly).
- **Critical GFortran rule**: a dummy argument declared `arr(:,:,:)` remaps the lower bound to 1, silently shifting all halo accesses by +2. Any dummy that touches halos MUST be declared `arr(-1:,-1:,-1:)`.
- **PHDF5 collectivity**: all HDF5 metadata operations (`h5dcreate_f`, `h5gcreate_f`, close calls) must be executed by ALL ranks or the program deadlocks in `h5fclose_f`; only `h5dwrite_f` may be rank-selective. Follow the pattern in `mod_output_hdf5.f90`.
- **FVM scalar equation pattern** (energy, species): coefficients aW/aE (r), aS/aN (θ), aB/aT (z), upwind convection, central diffusion, plus the minimum-phase guard `if (alpha_q < 1e-6) then aP=1; Su=phi_old; cycle` — without it TDMA divides by zero.
- **Only rank 0 prints** (use `should_print(mesh)`).
- Config files (`input/*.dat`) are `key = value`; unknown keys and keys without effect print a WARNING (rank 0) but do not stop the run — check the log for typos. Every physics module can be toggled via `solve_*` flags without recompiling; `solve_chemistry` REQUIRES `solve_species` (validated: without transport O₂ would be infinite).

## Reglas de trabajo

- Un commit por pieza; cada commit pasa `make test-quick`; `make test-full`
  por etapa. Trailer de coautoria en los commits.
- Cambio numerico INTENCIONAL: `STAGE=vN make test-rebaseline` y commit del
  golden con la explicacion (skill `/rebaseline`). Los invariantes nunca se
  re-baselinean; xfails solo con causa raiz en `tests/xfail.list`.
- Corridas SOLO secuenciales y nunca tocar `bin/` con una simulacion en
  curso: lo impone el hook `.claude/hooks/guard_corridas.sh`.
- Las centinelas (`P_HYDRO_CAP`, `U_GAS_MAX`, `U_LIQ_MAX`) nunca se suben: si
  una se dispara, diagnosticar.
- Hallazgos de auditoria uno por uno, con test y auditoria dirigida tras cada
  arreglo (skill `/auditoria-dirigida`, subagente `auditor-eaf3d`). Cambios
  que solo deben actuar con una clave nueva: `/verificacion-bitwise`. Gate de
  un banco con overrides: `/gate-banco`.
- Toda ruta nueva de masa/energia se AUDITA (columna + identidad en
  `tests/integration/check_audit.py` en el mismo commit); todo estado que
  persiste entre pasos entra al snapshot de reinicio en el mismo commit.
- Documentacion y comentarios en espanol.

## Convenciones numericas (indice)

El detalle de cada convencion, con su causa medida, esta en `.claude/rules/`
(se carga solo al leer/editar con las herramientas de archivo los modulos de
su tema). **Antes de modificar un modulo, lee la regla de su tema** —
obligatorio si editas por Bash o scripts, que no la cargan:

| Tema | Archivo | Modulos |
|---|---|---|
| Acople P-V, momento, multifase, lecho, gas; Planes C-G y lo que NO funciono | `.claude/rules/acople-pv.md` | pressure, momentum, multiphase, mixture, drag, workspace, face_flux, turbulence, convergence |
| Transporte de alpha, energia, DO, audit de balances | `.claude/rules/transporte-energia.md` | continuity, energy, audit, interphase_ht, radiation_do |
| Arco, escoria (Plan H condensada / legado), quimica | `.claude/rules/arco-escoria-quimica.md` | arc_*, slag_*, foam, electrode, chemistry, species |
| Solido, fusion/congelacion, colapso, cestas, ECS | `.claude/rules/solido-fusion-carga.md` | melting, solid_phase, scrap_collapse, ecs_feed, fields |
| MPI, halos, reinicio, memoria, harness, tipos/config, tests | `.claude/rules/mpi-reinicio-memoria.md` | restart, output_hdf5, mpi_topology, mesh, main, types, config, `tests/**`, Makefile |

Reglas criticas (una linea; detalle en el archivo del tema):
- Flujos convectivos SIEMPRE via `mod_face_flux`; liquido donor-cell (energia y
  momento), conductancias con alpha de cara ARMONICA.
- aP de Patankar ACOTADO; transitorio del liquido con alpha^n; sub-relajacion
  solo en el lazo externo.
- Poisson de VOLUMEN (nunca la forma de masa de la mezcla); fuerza vertical
  balanceada por caras; residuales con el iterado ENTRANTE (Bug 20).
- `ALPHA_FLOW_CUTOFF` 1e-2 (hidrodinamica), `ALPHA_CUTOFF` 1e-6 (energia),
  `ALPHA_LIQ_CONT` 0.3 (liquido continuo); fase evanescente ATADA, nunca u = 0.
- Celda sin fase continua = pared para todo gradiente de presion (Bug 16) y
  fila sellada = pared (F2.29).
- Fusion/congelacion por regla de la palanca; entalpia del solido solo con
  `solid_enthalpy`; cierre de fase residual conservativo y auditado.
- Transporte de alpha explicito con limitador de hueco y derrame auditados;
  nunca un recorte silencioso de alpha.
- Escoria CONDENSADA por defecto (Plan H, `slag_in_volume`): vista alpha_c en
  `multiphase_iteration`, extensivas con `slq_adv`, flotacion por
  `slag_condensed_sort`.
- Frontera de BLOQUE != frontera fisica; operaciones de columna con gather
  global + escritura de celdas propias.
- Halos: dummies `(-1:,-1:,-1:)`; nunca copiar entero un array `mold` escrito
  solo en celdas propias (Bug 22); `intent(inout)` para tipos derivados con
  estado; `make debug` debe arrancar.
- Energia del gas = inventario logaritmico (`gas_log_exchange`); toda
  reescritura de alpha_g audita masa y energia del gas.
- Regimen marginal (B1 > 280 s): juez ESTADISTICO con varias trayectorias,
  nunca una sola corrida.

## Orden del paso

- **Orden del paso**: fusión+colapso ANTES del lazo SIMPLE
  (update_solid_premelt); interfase DESPUÉS de los solves de energía
  (update_solid_postenergy) — moverla antes duplica el calor.

## Hard-won fixes — do not regress

`docs/ARCHITECTURE.md` §10 lists 10 resolved critical bugs with root causes (halo lower-bound offsets, PHDF5 deadlock, arc power `abs(V*I)` instead of `I²R`, residual-norm denominator anchoring, melting energy accounting, interphase heat-transfer clamp, MC radiation step size excluding halo `dr`). Before "simplifying" a guard, clamp, or seemingly redundant term in those areas, check that list — most exist to prevent a specific NaN, deadlock, or divergence.
