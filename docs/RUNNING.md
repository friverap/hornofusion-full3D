# Guía de Ejecución — EAF3D

Instrucciones completas para compilar, configurar y ejecutar el simulador.

---

## 1. Compilación

### Dependencias (macOS con Homebrew)

```bash
brew install open-mpi          # mpif90, mpirun
brew install hdf5-mpi          # libhdf5_fortran con soporte MPI
xcode-select --install         # GNU Make
```

### Targets de Make

```bash
make              # -O2, Wall, Wextra, bounds check (recomendado para desarrollo)
make opt          # -O3 -march=native (producción en CPU conocida)
make debug        # -O0 -g -fbacktrace (depuración con GDB/LLDB)
make clean        # elimina obj/ y bin/
```

El compilador es `mpif90` (GFortran + MPI wrappers). Flags actuales:

```makefile
FFLAGS = -O2 -std=f2008 -Wall -Wextra -fcheck=bounds -ffree-line-length-none
         -I/opt/homebrew/include
```

Binario de salida: `bin/eaf3d_mpi`

---

## 2. Sintaxis de ejecución

```bash
mpirun -n <NPROCS> ./bin/eaf3d_mpi <archivo_config.dat>
```

Si no se especifica archivo de config, se usan los valores por defecto de `mod_config_3d.f90`.

---

## 3. Elección del número de procesos MPI

El código descompone el dominio en **theta × z** (r no se descompone; todos los ranks tienen el rango r completo).

### Regla: ntheta y nz deben ser exactamente divisibles

```
Decomposición global: 1 × p_theta × p_z   (donde p_theta × p_z = NPROCS)
```

### Tabla de descomposiciones válidas para la malla de producción (60×120×84)

| NPROCS | Descomp. | ntheta/proc | nz/proc | Celdas/proc |
|--------|----------|-------------|---------|-------------|
| 8 | 1×4×2 | 30 | 42 | 75,600 |
| **12** | **2×3×2** | **40** | **42** | **50,400** |
| 16 | 1×4×4 | 30 | 21 | 37,800 |
| 24 | 1×6×4 | 20 | 21 | 25,200 |

> **Recomendado en M4 Pro (12 núcleos):** `mpirun -n 12`

### Para el test de regresión (18×36×24)

| NPROCS | Descomp. | Válido |
|--------|----------|--------|
| 8 | 1×4×2 | ✓ (ntheta/4=9, nz/2=12) |
| 4 | 1×4×1 | ✓ |
| 1 | 1×1×1 | ✓ |

---

## 4. Workflows completos

### A) Test de regresión (10 pasos, ~30 s de tiempo real)

Verifica que toda la física funciona correctamente en malla pequeña.

```bash
cd full3D
make clean && make

mpirun -n 8 ./bin/eaf3d_mpi input/config_small_test.dat

# Verificar salida
h5ls output/eaf3d_00000001.h5/fields
```

Resultado esperado (malla 12×24×16, t_final=5 s, max_outer=5):
```
 [STEP]        1  t=      0.50  outer=  5  res:   0.0000E+00  0.0000E+00  ~1.0E-02
 ...
 [STEP]       10  t=      5.00  outer=  5  res:   0.0000E+00  0.0000E+00  5.4518E-02
```

> `res_ur = 0` y `res_cont = 0` son normales cuando el flujo es laminar/estancado.
> `res_energy ~ 0.05` es aceptable para un arranque en frío con arco activo.

---

### B) Calibración bore-in (300 s simulados, ~60 pasos)

Valida el descenso de electrodos y la distribución de calor del arco.

```bash
mpirun -n 8 ./bin/eaf3d_mpi input/config_300s_borein.dat
```

El bore-in completa en t ≈ 200 s (electrodo desciende 2 m a 0.01 m/s).  
Verificar que `bore_in_done` pasa a `.true.` en los 3 electrodos.

---

### C) Corrida de producción completa (5040 s tap-to-tap)

```bash
# Asegurar directorio de salida
mkdir -p output_prod

# Compilar en modo optimizado (recomendado para runs largos)
make clean && make opt

# Lanzar (12 procs en M4 Pro, o 8 en MacBook de 8 núcleos)
mpirun -n 12 ./bin/eaf3d_mpi input/config_production_full.dat 2>&1 | tee run_production.log
```

El flag `2>&1 | tee` guarda stdout+stderr al mismo tiempo que muestra en pantalla.

**Progreso:** monitorear `output_prod/monitor.log` en tiempo real:

```bash
tail -f output_prod/monitor.log
```

Formato de cada línea del monitor:
```
# step  time[s]  m_s[kg]  res_cont  res_ur  res_energy  n_outer
      20     10.00  1.31E+05  1.2E-05  0.0E+00  2.1E-02    5
```

---

## 5. Estructura de directorios de salida

```
output_prod/
├── monitor.log                   Línea por paso: tiempo, masa sólida, residuales
├── eaf3d_00000200.h5            Snapshot t=100 s
├── eaf3d_00000400.h5            Snapshot t=200 s
...
└── eaf3d_00010080.h5            Snapshot t=5040 s (final)
```

Cada archivo HDF5 contiene:
- `/mesh/r`, `/mesh/theta`, `/mesh/z` — coordenadas 1D
- `/fields/<nombre>` — campos 3D (nr × nth × nz)
- `/metadata/time`, `/metadata/step`, `/metadata/nprocs`

Ver [`docs/OUTPUT.md`](OUTPUT.md) para la lista completa de campos.

---

## 6. Habilitar/deshabilitar módulos individuales

Cualquier módulo puede desactivarse desde el config sin recompilar:

```ini
solve_flow       = false   # desactiva momentum + presión
solve_energy     = false   # desactiva ecuación de energía
solve_melting    = false   # desactiva fusión/solidificación
solve_turb       = false   # desactiva k-ε
solve_radiation  = false   # desactiva DO radiation
solve_chemistry  = false   # desactiva C→CO + CO→CO₂
solve_arc        = false   # desactiva Cassie-Mayr, MC, Lorentz
solve_multiphase = false   # SIMPLE mono-fase (solo líquido)
solve_slag       = false   # desactiva capa de escoria
solve_species    = false   # desactiva transporte CO/CO₂
```

> **Nota:** `solve_species = true` requiere `solve_chemistry = true` para que las fuentes `S_CO_src` y `S_CO2_src` sean no nulas. Si `solve_chemistry = false`, el transporte funciona pero Y_CO = Y_CO₂ = 0 siempre.

---

## 7. Checkeo de la salida HDF5

```bash
# Listar campos en el primer snapshot
h5ls -r output_prod/eaf3d_00000200.h5

# Ver metadatos (tiempo, pasos, procs)
h5dump -g /metadata output_prod/eaf3d_00000200.h5

# Verificar dimensiones de un campo
h5ls output_prod/eaf3d_00000200.h5/fields/T_gas
# → Dataset {84, 120, 60}  (nz × nth × nr)
```

---

## 8. Errores comunes y soluciones

### "Cannot open electrode profile"
```
[INPUT] Cannot open electrode profile: input/electrode_profile.dat
```
El código usa valores por defecto (500 V, 50 kA). No es un error fatal.  
Solución: verificar que se ejecuta desde `full3D/` como directorio de trabajo.

### HDF5 deadlock (programa cuelga en `h5fclose_f`)
Causa: `h5dcreate_f` o `h5gcreate_f` llamado solo por rank 0.  
Todas las operaciones de metadatos HDF5 deben ser **colectivas** (todos los ranks).  
Ver `mod_output_hdf5.f90` para el patrón correcto.

### NaN en energía (res_energy → inf)
Causas comunes:
1. `alpha_q < 1e-6` sin guard → diagonal TDMA ≈ 0 (resuelto con guard en `solve_energy_3d`)
2. Q de interfase demasiado grande → overshooting de temperatura (resuelto con clamp en `mod_interphase_ht.f90`)
3. step_size = 0 en MC radiation (resuelto con `minval(dr(1:nr))`)

### Bucle infinito en MC radiation
Causa: `step_size = minval(m%dr)` incluye halos donde `dr(-1) = 0`.  
Solución ya aplicada: `step_size = minval(m%dr(1:m%nr)) * 0.5 + fallback`

### Segfault por índices fuera de rango
Compilar con `make debug` (activa `-fcheck=bounds -fbacktrace`) para obtener el stack trace.

---

## 9. Variables de entorno útiles

```bash
# Limitar threads OpenMP si hay conflicto con MPI
export OMP_NUM_THREADS=1

# Para Open-MPI en macOS: suprimir warnings de fork
export OMPI_MCA_mpi_warn_on_fork=0

# Verbose de MPI para depurar comunicaciones
export OMPI_MCA_verbose=1
```

---

## 10. Ejecución en cluster (SLURM)

```bash
#!/bin/bash
#SBATCH --job-name=eaf3d_prod
#SBATCH --ntasks=48
#SBATCH --cpus-per-task=1
#SBATCH --time=48:00:00
#SBATCH --mem=96G

module load gcc/12 openmpi/4 hdf5-parallel/1.14

cd $SLURM_SUBMIT_DIR
mkdir -p output_prod

srun ./bin/eaf3d_mpi input/config_production_full.dat 2>&1 | tee run_production.log
```

Para 48 procs en la malla 60×120×84: descomposición 1×6×8 (ntheta/6=20, nz/8=~10.5 — NO exacto).  
Usar en cambio 1×8×6 (ntheta/8=15, nz/6=14 — EXACTO). Total: 48 procs ✓.
