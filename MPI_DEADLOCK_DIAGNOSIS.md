# 🔒 MPI DEADLOCK DIAGNOSIS

## 🐛 PROBLEMA IDENTIFICADO

**MPI Deadlock** en simulador 3D EAF con múltiples procesos:

- ✅ **1 proceso**: Funciona perfectamente (10 steps, 60s)  
- ❌ **2+ procesos**: Se cuelga en infinite loop (100% CPU cada proceso)  

## 📍 LOCALIZACIÓN DEL BUG

### Evidencia
1. **Serial (np=1)**: Completa 10 time steps sin problema
2. **Parallel (np=2)**: Se cuelga después del primer paso temporal
3. **Parallel (np=4)**: Se cuelga antes del primer paso (en HDF5 output)

### Log Analysis
```
[1 proceso] - FUNCIONA:
 [STEP]        1  t=      1.00  res:   3.0300-314  2.1997-314  3.0300-314
 [STEP]        2  t=      2.00  res:   3.0300-314  2.1997-314  3.0300-314
 ...
 [STEP]       10  t=     10.00  res:   3.0300-314  2.1997-314  3.0300-314
 Simulation complete. Steps:       10  Time:      10.00 s

[2 procesos] - SE CUELGA:
 [STEP]        1  t=      1.00  res:   3.0439-314  2.8090-314  3.0439-314
 [HANGING... infinite loop]

[4 procesos] - SE CUELGA:
 [MAIN] Writing initial state...
 [CHARGE] Bucket 1 loaded, layers   1- 14
 [HANGING... infinite loop]
```

## 🕵️ ROOT CAUSE ANALYSIS

### Ubicación del Deadlock

El problema está en **MPI collective operations** que requieren sincronización de todos los procesos.

**Candidatos más probables:**

#### 1. **HDF5 Parallel I/O (write_hdf5_parallel)**
```fortran
! En mod_output_hdf5.f90 líneas 42-52:
call h5open_f(error)  ! ← Todos los procesos deben llamar esto
call h5pcreate_f(H5P_FILE_ACCESS_F, plist_id, error)
call h5pset_fapl_mpio_f(plist_id, m%topo%comm_cart, MPI_INFO_NULL, error) ! ← MPI collective
call h5fcreate_f(filename, H5F_ACC_TRUNC_F, file_id, error, access_prp=plist_id) ! ← MPI collective
```

#### 2. **MPI Global Reductions (en solvers)**
```fortran
! En módulos física, e.g., mod_momentum_3d.f90:
call mpi_allreduce(local_residual, global_residual, ...)  ! ← Deadlock posible
```

#### 3. **Halo Exchange (mpi_exchange_halos_3d)**
```fortran
! En mod_parallel_utils.f90:
call MPI_Isend(...) ! Non-blocking send
call MPI_Irecv(...) # Non-blocking receive  
call MPI_Waitall(...) ! ← Deadlock posible si sends/recvs desbalanceados
```

## 🔧 DEBUGGING STRATEGY

### Paso 1: Aislar el Módulo Problemático

**Deshabilitar módulos gradualmente:**

1. ✅ **Deshabilitado**: HDF5 inicial write → 4 procesos aún se cuelgan
2. 🔄 **Siguiente**: Deshabilitar HDF5 en time loop
3. 🔄 **Siguiente**: Deshabilitar global reductions
4. 🔄 **Siguiente**: Deshabilitar halo exchanges

### Paso 2: Instrumentar con Prints Debug

Agregar prints para localizar exactamente dónde se cuelga:

```fortran
if (should_print(mesh)) print *, '[DEBUG] Before HDF5 write'
call write_hdf5_parallel(...)
if (should_print(mesh)) print *, '[DEBUG] After HDF5 write'

if (should_print(mesh)) print *, '[DEBUG] Before halo exchange'  
call phase_exchange_halos(...)
if (should_print(mesh)) print *, '[DEBUG] After halo exchange'
```

### Paso 3: MPI Process Tracing

```bash
# Usar MPI debugging
mpirun --mca btl vader,self -np 2 --display-map --debug-devel ./bin/eaf3d_mpi ...
```

## 🚀 IMMEDIATE FIXES TO TRY

### Fix #1: Disable HDF5 in Time Loop

```fortran
! En main_3d.f90, around line 180-190:
! if (mod(step, cfg%output_freq) == 0) then
!     call write_hdf5_parallel(mesh, liq, gas, sol, sh, step, time, cfg%output_dir)
! end if

! Temporary debug version:
if (mod(step, cfg%output_freq) == 0 .and. mesh%topo%nprocs == 1) then
    call write_hdf5_parallel(mesh, liq, gas, sol, sh, step, time, cfg%output_dir)
else if (mesh%topo%nprocs > 1) then
    if (should_print(mesh)) then
        print '(A,I0,A)', ' [DEBUG] Skipping HDF5 write for ', mesh%topo%nprocs, ' processes'
    end if
end if
```

### Fix #2: Simplify MPI Topology for Testing

Test with simple 1D decomposition first:

```bash
# Force 1D decomposition (should be simpler)
# Edit mpi_init_topology to force npr=np, npth=1, npz=1
mpirun -np 4 ./bin/eaf3d_mpi input/config_test.dat  # 4×1×1 instead of 2×2×1
```

### Fix #3: Add MPI Barriers for Debugging

```fortran
! Add strategic MPI barriers to isolate deadlock location:
call mpi_barrier(m%topo%comm_cart, ierr)
if (should_print(mesh)) print *, '[DEBUG] Passed barrier 1'

call some_mpi_operation(...)

call mpi_barrier(m%topo%comm_cart, ierr)  
if (should_print(mesh)) print *, '[DEBUG] Passed barrier 2'
```

### Fix #4: Check MPI Communicator

Verify all processes use same communicator:

```fortran
! En mod_mpi_topology.f90, add debug prints:
print '(A,I0,A,I0)', '[MPI] Rank ', rank, ' using comm: ', comm_cart
```

## 📋 SYSTEMATIC TESTING PLAN

### Phase 1: Minimal MPI Test
```bash
# Test 1: Serial (baseline)
mpirun -np 1 ./bin/eaf3d_mpi input/config_test.dat  # ✅ WORKS

# Test 2: 2 processes, no physics
# (modify config_test.dat: all solve_* = false)
mpirun -np 2 ./bin/eaf3d_mpi input/config_minimal.dat

# Test 3: 2 processes, minimal physics  
# (enable only solve_flow = true)
```

### Phase 2: Module-by-Module
```bash
# Test each physics module individually with 2 processes:
# 1. solve_flow only
# 2. solve_energy only  
# 3. solve_flow + solve_energy
# etc.
```

### Phase 3: Process Scaling
```bash
# Once 2 processes work, scale up:
mpirun -np 2 → np 4 → np 8 → np 14
```

## 🎯 EXPECTED OUTCOMES

### Success Criteria:
1. **2 processes complete**: Simple time loop without hanging
2. **4 processes complete**: Basic physics enabled
3. **8 processes complete**: Full production config

### Performance Baseline:
- **Serial (1 proc)**: 60s for 10 steps (config_test)
- **Parallel (8 proc)**: Should be ~20-30s for same workload

## 📝 FILES TO MODIFY FOR DEBUG

### Quick Wins:
1. `src/main_3d.f90` - Add debug prints, disable HDF5 selectively
2. `input/config_minimal.dat` - Create minimal config (all physics off)
3. `src/mod_output_hdf5.f90` - Add debug prints around collective ops
4. `src/mod_mpi_topology.f90` - Add communicator debug info

### Strategic Fixes:
1. Review all `mpi_allreduce()` calls for correct arguments
2. Check `mpi_exchange_halos_3d()` for balanced send/recv
3. Verify HDF5 collective operations have proper error handling
4. Ensure all processes call collective operations consistently

---

## 🔄 CURRENT STATUS

- ✅ **Stack overflow fixed** (mod_radiation_do.f90)  
- ✅ **Compilation successful**  
- ✅ **1 process works perfectly**  
- ❌ **2+ processes deadlock** ← CURRENT FOCUS  
- 🔄 **Working on**: MPI collective operation debugging

---

## 📞 NEXT STEPS

1. **Create config_minimal.dat** (all physics disabled)
2. **Test 2 processes with minimal config**
3. **Add debug prints to isolate deadlock location**
4. **Fix identified MPI collective operation**
5. **Gradually re-enable physics modules**
6. **Scale to 4, 8, 14 processes**

**Goal**: Get `mpirun -np 8 ./bin/eaf3d_mpi input/config_production.dat` working without crashes or hangs.