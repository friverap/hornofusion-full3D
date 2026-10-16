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

### Targets de test (roadmap 2026; detalles en tests/README.md)

```bash
make test-quick   # gate por commit (~1.5 min): corrida fría -n 8 + bath_test + arc_melt + invariantes
                  # + balances de audit.csv + métricas vs golden
make test-full    # gate por etapa (~5-10 min): unit + matriz {configs}x{-n}
                  # + fusión + simetría 120° + química + convergencia externa
make test-unit    # unit tests Fortran (TDMA, malla, entalpía, flujos de cara,
                  # equilibrio DO, receta de carga)
STAGE=vN make test-rebaseline   # regenerar tests/golden/metrics_vN.json tras
                                # un cambio numérico INTENCIONAL y explicado
```

Los fallos esperados viven en `tests/xfail.list`, cada uno con su causa raíz;
se eliminan en el mismo commit que su fix.

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

El código descompone el dominio en **r × theta × z** (`factorize_3d` en
`mod_mpi_topology`): prueba todas las factorizaciones de NPROCS y elige la de
bloques más cúbicos. Reglas (auditoría M32, oct-2026):

- `ntheta` debe ser divisible exactamente por el número de procesos en theta
  (la costura periódica lo exige); la factorización solo considera esos.
- En r y z NO hace falta divisibilidad: el resto va al último rank de cada
  dirección.
- Cada bloque local necesita **al menos 2 celdas por dirección** (halos de dos
  capas). Si no, el programa aborta al arrancar con un mensaje.

### Descomposiciones reales para la malla de producción (60×120×84)

| NPROCS | r×θ×z | Bloque local (r, θ, z) | Celdas/proc |
|--------|-------|------------------------|-------------|
| 8 | 1×4×2 | 60, 30, 42 | 75,600 |
| **12** | **2×3×2** | **30, 40, 42** | **50,400** |
| 16 | 2×4×2 | 30, 30, 42 | 37,800 |
| 24 | 2×4×3 | 30, 30, 28 | 25,200 |

> **Recomendado en M4 Pro (12 núcleos):** `mpirun -n 12`

### Malla media (30×60×42)

| NPROCS | r×θ×z | Bloque local |
|--------|-------|--------------|
| 12 | 2×3×2 | 15, 20, 21 |
| 14 | 1×2×7 | 30, 30, 6 |
| 15 | 1×5×3 | 30, 12, 14 |
| 16 | 2×4×2 | 15, 15, 21 |

### Mallas de los tests (12×24×16)

| NPROCS | r×θ×z | Bloque local |
|--------|-------|--------------|
| 1 | 1×1×1 | 12, 24, 16 |
| 4 | 1×2×2 | 12, 12, 8 |
| 8 | 1×4×2 | 12, 6, 8 |

---

## 4. Workflows completos

### A) Test de regresión

```bash
make test-quick      # por commit (~minutos)
make test-full       # por lote: matriz completa, invariantes, golden
```

> (auditoría 15, M15-1) `config_small_test.dat` y los demás configs legados de
> `input/` usan pasos de 0.1–5 s: el régimen en que el modelo de dos fluidos
> se rompe (auditoría 12, M12-2). Ya no son la prueba de regresión.

---

### B) Calibración bore-in

`config_300s_borein.dat` es la PLANTILLA de las campañas: sola aborta (dt 5.0
mayor que el `dt_max` por defecto, 1.0). Lanzarla con el runner, que fija los
parámetros de paso (`campaigns/b1_ugarte.json`: dt 2 ms):

```bash
python3 scripts/run_campaign.py campaigns/b1_ugarte.json   # B1 completo (días); --dry-run solo genera el config
```

El bore-in completa en t ≈ 200 s (electrodo desciende 2 m a 0.01 m/s).
Verificar que `bore_in_done` pasa a `.true.` en los 3 electrodos.

---

### C) Corrida de producción completa (t_final 7200 s; tap-to-tap de referencia 5040 s)

```bash
# Asegurar directorio de salida
mkdir -p output_prod2

# Compilar en modo optimizado (recomendado para runs largos)
make clean && make opt

# Lanzar (12 procs en M4 Pro, o 8 en MacBook de 8 núcleos)
mpirun -n 12 ./bin/eaf3d_mpi input/config_production_full.dat 2>&1 | tee run_production.log
```

El flag `2>&1 | tee` guarda stdout+stderr al mismo tiempo que muestra en pantalla.

**Progreso:** monitorear `output_prod2/monitor.log` en tiempo real:

```bash
tail -f output_prod2/monitor.log
```

Formato de cada línea del monitor:
```
# step  time[s]  m_s[kg]  res_cont  res_ur  res_energy  n_outer
      20     10.00  1.31E+05  1.2E-05  0.0E+00  2.1E-02    5
```

### D) Reanudar una corrida desde un snapshot

```bash
# config idéntico al de la corrida original + dos claves:
cp campaigns/b1_v24_f28_120s/config.dat scratchpad/b1_restart.dat
cat >> scratchpad/b1_restart.dat <<EOF
output_dir   = /ruta/nueva/salida
restart_file = /Users/frariv/Horno/hornofusion-full3D/campaigns/b1_v24_f28_120s/eaf3d_00015000.h5
EOF
mpirun -n 12 ./bin/eaf3d_mpi scratchpad/b1_restart.dat
```

El estado completo (campos, sólido, escoria, electrodos, `dt`, paso y
tiempo) viene del snapshot; la carga, el remanente y la hidrostática inicial
no se repiten. `t_final` sigue siendo absoluto. El primer archivo escrito es
una copia del estado reanudado (mismo número de paso) y `audit.csv` arranca
en ese paso. Uso típico: iterar sobre un instante caro (el episodio de 34 s
de B1 está a ~3 h del arranque en la malla media; desde el snapshot de 30 s
son minutos). Detalles y reconstrucción de snapshots antiguos en
`docs/OUTPUT.md` §5b.

---

## 5. Estructura de directorios de salida

```
output_prod2/
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
h5ls -r output_prod2/eaf3d_00000200.h5

# Ver metadatos (tiempo, pasos, procs)
h5dump -g /metadata output_prod2/eaf3d_00000200.h5

# Verificar dimensiones de un campo
h5ls output_prod2/eaf3d_00000200.h5/fields/T_gas
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
#SBATCH --time=48:00:00   # SEGMENTO: la colada completa no cabe (ver abajo); reanudar con restart_file
#SBATCH --mem=96G

module load gcc/12 openmpi/4 hdf5-parallel/1.14

cd $SLURM_SUBMIT_DIR
mkdir -p output_prod2

srun ./bin/eaf3d_mpi input/config_production_full.dat 2>&1 | tee run_production.log
```

La descomposición NO se elige a mano: `factorize_3d` (`src/mod_mpi_topology.f90`)
prueba todas las factorizaciones de `nprocs` con `npth | ntheta` y se queda con
la de bloques más cúbicos.

> **Costo (auditoría 15, M15-5; ESTIMACIÓN, sin medir en esta malla).** En el
> régimen actual el paso queda en `dt_min` = 1 ms: ~7.2e6 pasos para 7200 s.
> Referencia del repo: B1 en malla media (30×60×42), 5040 s a ~2 ms, 14 ranks,
> ~8–10 días (`docs/PLAN_D_acople_implicito_alpha_p.md`, D6). La malla de
> producción tiene 8× celdas, el doble de pasos por segundo simulado y 1.4×
> el tiempo simulado: del orden de **180–225 días** a 14 ranks (8–10 d × 8 × 2 × 1.4); con 48 ranks,
> si el escalamiento fuera ideal, del orden de ~2 meses. Un job de 48 h es un
> SEGMENTO (~1–2 % de la colada): encadenar con `restart_file`. Antes de
> comprometer cómputo, medir el costo por paso con una corrida de ~100 pasos y
> validar el régimen con un B1 nuevo (bloqueado 2 de la auditoría 13).
