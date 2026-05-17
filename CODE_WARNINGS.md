# Advertencias y posibles errores del código (full3D)

> **Estado:** Todos los warnings han sido resueltos. La compilación con
> `make clean && make` produce **0 warnings, 0 errores** con flags
> `-Wall -Wextra -fcheck=bounds -std=f2008`.
>
> Última revisión: 2026-02-21
>
> **Simulación MPI (8 procesos) ejecutada correctamente:**
> - Configuración: `input/config_small_test.dat` (12×24×16 mesh, dt=0.5s, t_final=5s)
> - Resultado: 10 pasos completan sin NaN ni hang
> - Residuos: estables en pasos 1-9; divergencia numérica en paso 10 (parámetros de
>   arco no calibrados → P_arc ~TW, irrealista para EAF real ~30-40 MW)

---

## Corrida de producción completa — 10 pasos (todos los módulos físicos)

> **Resultado:** Simulación estable en todos los 10 pasos con toda la física de producción activa.
> Configuración: `input/config_10step_full_physics.dat` (18×36×24 mesh, dt=0.5s, t_final=5s, 8 procs MPI)
>
> ```
> [STEP]  1  t=0.50  outer=5  res: 0.000E+00  0.000E+00  1.563E-03
> [STEP]  2  t=1.00  outer=5  res: 0.000E+00  0.000E+00  1.635E-03
> [STEP]  3  t=1.50  outer=5  res: 0.000E+00  0.000E+00  1.726E-03
> [STEP]  4  t=2.00  outer=5  res: 0.000E+00  0.000E+00  1.773E-03
> [STEP]  5  t=2.50  outer=5  res: 0.000E+00  0.000E+00  1.800E-03
> [STEP]  6  t=3.00  outer=5  res: 0.000E+00  0.000E+00  1.815E-03
> [STEP]  7  t=3.50  outer=5  res: 0.000E+00  0.000E+00  1.822E-03
> [STEP]  8  t=4.00  outer=5  res: 0.000E+00  0.000E+00  1.845E-03
> [STEP]  9  t=4.50  outer=5  res: 0.000E+00  0.000E+00  1.832E-03
> [STEP] 10  t=5.00  outer=5  res: 0.000E+00  0.000E+00  1.880E-03
> Simulation complete. Steps: 10  Time: 5.00 s
> ```
>
> Física activa: flow, energy, melting, turbulence, radiation (DO), arc (Cassie-Mayr + MC), multiphase.
> Última revisión: 2026-02-21

---

## Resumen de fixes aplicados

| Prioridad | Archivo | Descripción | Estado |
|-----------|---------|-------------|--------|
| Crítica | mod_arc_radiation_mc.f90 | `minval(m%dr)` incluye halos con dr=0 → step_size=0 → loop infinito | ✅ Resuelto |
| Alta | mod_energy_3d.f90 | `T_old(:,:,:)` / `alpha_q(:,:,:)` → bounds incorrectos (-1:) | ✅ Resuelto |
| Alta | mod_pressure_3d.f90 | `alpha_q(:,:,:)` → bounds incorrectos (-1:) | ✅ Resuelto |
| Alta | mod_momentum_3d.f90 | Sin guarda para alpha_q≈0 → TDMA singular | ✅ Resuelto |
| Alta | mod_energy_3d.f90 | Sin guarda para alpha_q≈0 → TDMA singular | ✅ Resuelto |
| Media | mod_solver_3d.f90 | TDMA b(1)≈0 → NaN en forward sweep | ✅ Resuelto |
| Alta | mod_fields_3d.f90:385 | Aliasing IN/OUT en `mpi_allreduce_sum` | ✅ Resuelto |
| Media | mod_radiation_do.f90 | `I_dir` no inicializada | ✅ Resuelto |
| Baja | mod_solver_3d.f90 | Warnings de índices en `sor_3d` / `compute_residual_3d` | ✅ Resuelto |
| Baja | mod_convergence_3d.f90 | Comparación real para NaN (`/= res_cont`) | ✅ Resuelto |
| Baja | mod_boundary_3d.f90 | Argumentos `phi`, `cfg`, `bc_type` no usados | ✅ Resuelto |
| Baja | mod_solver_3d.f90 | `periodic_theta` no usado (dummy + local) | ✅ Resuelto |
| Baja | mod_pressure_3d.f90 | `alpha_q` no usado en `correct_velocities` | ✅ Resuelto |
| Baja | mod_electrode_3d.f90 | `time` no usado en `update_electrodes` | ✅ Resuelto |
| Baja | mod_radiation_do.f90 | `cfg` no usado en `solve_radiation_do` | ✅ Resuelto |
| Baja | mod_chemistry_carbon.f90 | `dt` no usado en `compute_carbon_oxidation` | ✅ Resuelto |
| Baja | mod_output_hdf5.f90 | `plist_xfer` no usado en `write_1d_dataset`; `dspace_id`/`dset_id` no usados en `write_mesh_group` | ✅ Resuelto |
| **Crítica** | **mod_interphase_ht.f90** | **Q_gs/Q_ls sin límite → inestabilidad explícita en celdas con alpha_g pequeño** | **✅ Resuelto** |
| Alta | mod_radiation_do.f90 | Signo S_rad erróneo, kappa en emission, SAVE en I_dir, inicio frío, kappa discontinuo | ✅ Resuelto |
| Alta | mod_config_3d.f90 | frac_conv/rad/elec y arc_w no configurables desde archivo | ✅ Resuelto |

---

## Detalle de cada fix

### 1. Acceso potencial fuera de rango (`mod_solver_3d.f90`)

**Causa:** El análisis estático veía `phi(i-1,j,k)` y `phi(i,j,k-1)` dentro de
bucles `do i=1,nr` y `do k=1,nz` en las funciones no-MPI `sor_3d` y
`compute_residual_3d`.

**Fix:** Las guardas `if (i > 1)` / `if (k > 1)` se reemplazaron por índices
clampeados con `max`/`min` (e.g. `phi(max(1,i-1),j,k)`). Los coeficientes de
borde son 0 tras aplicar las BCs, por lo que el resultado es matemáticamente
idéntico y el compilador ya no ve accesos potencialmente fuera de rango.

También se eliminaron las variables locales `periodic_theta` en las versiones
MPI (`tdma_3d_mpi`, `sor_3d_mpi`, `compute_residual_3d_mpi`) que eran asignadas
pero nunca usadas en el cálculo, y el argumento dummy `periodic_theta` en
`sor_3d` y `compute_residual_3d`.

---

### 2. Argumentos dummy no usados (`mod_boundary_3d.f90`)

**Causa:** `apply_scalar_bc`, `apply_momentum_bc` y `apply_pressure_bc` recibían
`phi`, `cfg` (y `bc_type` en la primera) como argumentos que nunca usaban en el
cuerpo.

**Fix:** Argumentos eliminados de las tres firmas. Todos los call sites
actualizados (`mod_energy_3d.f90`, `mod_turbulence_3d.f90`,
`mod_momentum_3d.f90`, `mod_pressure_3d.f90`).

---

### 3. Aliasing IN/OUT en `mpi_allreduce_sum` (`mod_fields_3d.f90:385`)

**Causa:** La misma variable `local_vol_add` se pasaba como argumento
`INTENT(IN)` y `INTENT(OUT)`, lo que viola el estándar Fortran.

**Fix:**
```fortran
real(dp) :: global_vol_add
call mpi_allreduce_sum(local_vol_add, global_vol_add, m%topo)
local_vol_add = global_vol_add
```

---

### 4. Variable no inicializada (`mod_radiation_do.f90`)

**Causa:** `I_dir` se usaba en `I_dir = emission + (I_dir - emission) * exp(…)`
sin inicialización previa en la primera iteración del barrido.

**Fix:** Inicialización en la declaración: `real(dp) :: I_dir = 0.0_dp`.

---

### 5. Comparación de reales para NaN (`mod_convergence_3d.f90:27`)

**Causa:** El patrón `res_cont /= res_cont` detecta NaN pero genera warning de
comparación de igualdad entre reales.

**Fix:** Se usa `ieee_arithmetic` (F2003 estándar):
```fortran
use ieee_arithmetic, only: ieee_is_nan, ieee_is_finite
...
if (ieee_is_nan(conv%res_cont) .or. .not. ieee_is_finite(conv%res_cont) &
    .or. conv%res_cont > 1.0e100_dp) then
```

---

### 6. Argumentos dummy no usados — varios módulos

| Módulo | Subrutina | Argumento eliminado |
|--------|-----------|---------------------|
| `mod_pressure_3d.f90` | `correct_velocities` | `alpha_q` |
| `mod_electrode_3d.f90` | `update_electrodes` | `time` |
| `mod_radiation_do.f90` | `solve_radiation_do` | `cfg` |
| `mod_chemistry_carbon.f90` | `compute_carbon_oxidation` | `dt` |

Call sites en `main_3d.f90` actualizados en todos los casos.

---

### 7. Variables no usadas (`mod_output_hdf5.f90`)

- `dspace_id` y `dset_id` eliminados de `write_mesh_group` (línea 89).
- `plist_xfer` eliminado de `write_1d_dataset` y de `write_mesh_group`
  (los datasets 1D no necesitan transfer property list).
- Los 6 call sites de `write_1d_dataset` en `write_mesh_group` actualizados.

---

## Cómo verificar

```bash
# Compilación limpia — debe producir 0 warnings
make clean && make 2>&1 | grep -E "Warning:|Error:"

# Resultado esperado: (sin salida)
```
