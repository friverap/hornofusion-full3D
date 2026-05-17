# Patrón de Modificación para Módulos de Física - MPI Parallelization

## Objetivo
Convertir todos los módulos de física para que trabajen con dominios locales en modo paralelo MPI, manteniendo compatibilidad con modo serial.

## Patrón General

### 1. Añadir imports necesarios
```fortran
use mod_parallel_utils  ! Para get_loop_bounds, should_print, etc.
use mod_mpi_topology    ! Si se requieren reducciones globales
```

### 2. Reemplazar loops fijos por loops con rangos dinámicos

**ANTES (código serial):**
```fortran
do k = 1, m%nz
    do j = 1, m%ntheta
        do i = 1, m%nr
            ! Operación
        end do
    end do
end do
```

**DESPUÉS (código MPI-aware):**
```fortran
integer :: istart, iend, jstart, jend, kstart, kend

call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

do k = kstart, kend
    do j = jstart, jend
        do i = istart, iend
            ! Operación (SIN CAMBIOS en la lógica)
        end do
    end do
end do
```

### 3. Manejar accesos a vecinos (stencil)

Para accesos tipo `phi(i-1,j,k)`, `phi(i,j+1,k)`, etc., los halos ya contienen los datos correctos **SI** se llamó a `exchange_halos` antes.

**Patrón seguro:**
1. Antes de computar coeficientes que usan vecinos: exchange halos
2. Computar coeficientes (acceso a i±1, j±1, k±1 es seguro)
3. Resolver sistema
4. Después de resolver: exchange halos del resultado

### 4. Reemplazar llamadas a solucionadores

**ANTES:**
```fortran
call tdma_3d(aW, aE, aS, aN, aB, aT, aP, Su, phi, &
             m%nr, m%ntheta, m%nz, n_sweep, .true.)
```

**DESPUÉS:**
```fortran
call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, phi, m, n_sweep)
```

**ANTES:**
```fortran
call sor_3d(aW, aE, aS, aN, aB, aT, aP, Su, phi, &
            m%nr, m%ntheta, m%nz, omega, max_iter, tol, res, n_iter, .true.)
```

**DESPUÉS:**
```fortran
call sor_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, phi, m, &
                omega, max_iter, tol, res, n_iter)
```

### 5. Residuales globales

**ANTES:**
```fortran
res = compute_residual_3d(aW, aE, aS, aN, aB, aT, aP, Su, phi, &
                          m%nr, m%ntheta, m%nz, .true.)
```

**DESPUÉS:**
```fortran
res = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, phi, m)
```

### 6. Sumas globales (masa, energía, etc.)

**ANTES:**
```fortran
total_mass = sum(rho(:,:,:) * vol(:,:,:))
```

**DESPUÉS:**
```fortran
use mod_mpi_topology

real(dp) :: total_mass_local, total_mass_global

total_mass_local = sum(rho(istart:iend, jstart:jend, kstart:kend) &
                       * vol(istart:iend, jstart:jend, kstart:kend))

if (m%is_parallel) then
    call mpi_allreduce_sum(total_mass_local, total_mass_global, m%topo)
    total_mass = total_mass_global
else
    total_mass = total_mass_local
end if
```

### 7. Print statements

**ANTES:**
```fortran
print *, ' [MODULE] Some info'
```

**DESPUÉS:**
```fortran
if (should_print(m)) then
    print *, ' [MODULE] Some info'
end if
```

### 8. Allocate coefficients arrays

Los arrays de coeficientes (aW, aE, aP, Su, etc.) deben tener las mismas dimensiones que los campos, incluyendo halos:

**ANTES:**
```fortran
allocate(aP(m%nr, m%ntheta, m%nz))
```

**DESPUÉS:**
```fortran
! Use same bounds as field arrays
allocate(aP, mold=phi)  ! Más simple y seguro
! O explícitamente:
! allocate(aP(lbound(phi,1):ubound(phi,1), &
!              lbound(phi,2):ubound(phi,2), &
!              lbound(phi,3):ubound(phi,3)))
```

## Orden de Modificación Sugerido

1. **mod_convergence_3d.f90**: Ajustar reducciones globales (ya tiene lógica de residuales)
2. **mod_momentum_3d.f90**: Ecuaciones de momento, usa tdma_3d
3. **mod_pressure_3d.f90**: Ecuación de presión, usa sor_3d
4. **mod_energy_3d.f90**: Ecuación de energía, usa tdma_3d
5. **mod_turbulence_3d.f90**: k-epsilon, usa tdma_3d
6. **mod_continuity.f90**: Corrección continuidad
7. **mod_melting_3d.f90**: Melting model
8. **mod_scrap_collapse.f90**: Vertical collapse (requiere comunicación en z)
9. **mod_arc_cassie_mayr.f90**: Arc heat distribution
10. **mod_radiation_do.f90**: Discrete ordinates (complejo, muchas direcciones)
11. **mod_chemistry_carbon.f90**: Carbon reactions
12. **mod_multiphase.f90**: Orquestador (llama a otros módulos, agrega exchanges)

## Ejemplo Completo: mod_momentum_3d.f90

```fortran
subroutine solve_momentum_r(liq, gas, sol, sh, m, cfg, alpha_u)
    use mod_parallel_utils
    
    ! ... declaraciones ...
    integer :: istart, iend, jstart, jend, kstart, kend
    
    call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
    
    ! Allocate coefficient arrays with halos
    allocate(aW, mold=liq%ur)
    allocate(aE, mold=liq%ur)
    ! ... etc
    
    ! Exchange halos before computing coefficients
    call phase_exchange_halos(liq, m)
    call phase_exchange_halos(gas, m)
    call solid_exchange_halos(sol, m)
    call shared_exchange_halos(sh, m)
    
    ! Compute coefficients (loops con istart:iend, etc.)
    do k = kstart, kend
        do j = jstart, jend
            do i = istart, iend
                ! Calcular aW(i,j,k), aE(i,j,k), etc.
                ! Acceso a vecinos es seguro: liq%ur(i-1,j,k), etc.
            end do
        end do
    end do
    
    ! Solve
    call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, liq%ur, m, n_sweep=3)
    
    ! Exchange halos after solve
    call phase_exchange_halos(liq, m)
    
    ! Compute residual
    res_ur = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, liq%ur, m)
    
    deallocate(aW, aE, aS, aN, aB, aT, aP, Su)
end subroutine solve_momentum_r
```

## Notas Importantes

1. **Periodicidad en theta**: Ya está manejada en `mpi_exchange_halos_3d`, no requiere código especial en módulos de física.

2. **Boundary conditions**: Los halos en fronteras físicas (r=0, r=R_shell, z=0, z=H) contienen valores boundary apropiados después del exchange (implementado en mod_boundary_3d).

3. **Orden de operaciones**:
   - Exchange halos → Compute coef → Solve → Exchange halos → Continue

4. **Performance**: Minimize exchanges. Si múltiples campos se usan juntos, exchange todos antes de empezar cómputos.

5. **Debugging**: Use `should_print(m)` para imprimir solo desde rank 0, evita output duplicado.

## Checklist por Módulo

Para cada módulo físico:
- [ ] Añadir `use mod_parallel_utils`
- [ ] Reemplazar loops 1:nr por istart:iend (usar get_loop_bounds)
- [ ] Cambiar tdma_3d → tdma_3d_mpi
- [ ] Cambiar sor_3d → sor_3d_mpi
- [ ] Cambiar compute_residual_3d → compute_residual_3d_mpi
- [ ] Allocar arrays de coeficientes con halos
- [ ] Agregar halo exchanges antes/después de solves
- [ ] Convertir sumas/max globales a versiones con Allreduce
- [ ] Proteger prints con should_print(m)
- [ ] Compilar y verificar

## Testing

Después de modificar cada módulo:
1. Compilar: `make clean && make debug`
2. Test serial (1 proceso): Debe dar resultados idénticos a versión anterior
3. Test paralelo (4 procesos): `mpirun -np 4 bin/eaf3d_mpi`
4. Verificar conservación de masa/energía
5. Verificar que residuales convergen igual que en serial
