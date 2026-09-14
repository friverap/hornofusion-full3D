!===============================================================================
! test_nan_guard.f90 - El freno de NaN (sep-2026)
!
! Motivo: B1 reventaba en t=471.66 y la corrida seguia 176k pasos
! escribiendo NaN (dos dias de CPU con estado corrupto). El freno debe
! detener la corrida en el paso en que el estado deja de ser finito.
!
! Casos:
!   1. Campos limpios y residuales finitos  -> NO dispara
!   2. NaN en una celda propia de liq%uz    -> dispara
!   3. Inf en sol%T_s                       -> dispara
!   4. Residual NaN con campos limpios      -> dispara (el residual basta)
!   5. NaN SOLO en el halo                  -> NO dispara en este rank
!      (la celda propia vive en el rank vecino y alla se detecta; barrer
!       halos daria abortos duplicados y falsos en bordes fisicos)
!===============================================================================
program test_nan_guard
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_convergence_3d, only: nan_guard_triggered
    use ieee_arithmetic, only: ieee_value, ieee_quiet_nan, ieee_positive_inf
    implicit none

    type(config_t)      :: cfg
    type(mesh_t)        :: mesh
    type(phase_t)       :: liq, gas
    type(solid_t)       :: sol
    type(slag_t)        :: slag
    type(shared_t)      :: sh
    type(convergence_t) :: conv
    real(dp) :: nan_val, inf_val, saved
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 6

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh)
    call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)

    nan_val = ieee_value(1.0_dp, ieee_quiet_nan)
    inf_val = ieee_value(1.0_dp, ieee_positive_inf)
    conv%res_cont = 1.0e-6_dp; conv%res_ur = 1.0e-6_dp
    conv%res_uth = 1.0e-6_dp;  conv%res_uz = 1.0e-6_dp
    conv%res_energy = 1.0e-6_dp
    conv%res_tke = 1.0e-6_dp;  conv%res_eps = 1.0e-6_dp
    ok = .true.

    ! 1) estado sano
    if (nan_guard_triggered(conv, liq, gas, sol, sh, mesh, 1, 0.0_dp)) then
        print '(A)', '   FAIL falso positivo con estado sano'
        ok = .false.
    end if

    ! 2) NaN en una celda propia
    saved = liq%uz(3,4,3)
    liq%uz(3,4,3) = nan_val
    if (.not. nan_guard_triggered(conv, liq, gas, sol, sh, mesh, 2, 1.0_dp)) then
        print '(A)', '   FAIL no detecto NaN en liq%uz'
        ok = .false.
    end if
    liq%uz(3,4,3) = saved

    ! 3) Inf en el solido
    saved = sol%T_s(2,2,2)
    sol%T_s(2,2,2) = inf_val
    if (.not. nan_guard_triggered(conv, liq, gas, sol, sh, mesh, 3, 2.0_dp)) then
        print '(A)', '   FAIL no detecto Inf en sol%T_s'
        ok = .false.
    end if
    sol%T_s(2,2,2) = saved

    ! 4) residual no finito con campos limpios
    conv%res_cont = nan_val
    if (.not. nan_guard_triggered(conv, liq, gas, sol, sh, mesh, 4, 3.0_dp)) then
        print '(A)', '   FAIL no detecto residual NaN'
        ok = .false.
    end if
    conv%res_cont = 1.0e-6_dp

    ! 5) NaN solo en el halo: no es de este rank
    liq%uz(-1,4,3) = nan_val
    if (nan_guard_triggered(conv, liq, gas, sol, sh, mesh, 5, 4.0_dp)) then
        print '(A)', '   FAIL disparo por un NaN que vive en el halo'
        ok = .false.
    end if
    liq%uz(-1,4,3) = 0.0_dp

    if (ok) then
        print '(A)', ' PASS test_nan_guard'
    else
        print '(A)', ' FAIL test_nan_guard'
        stop 1
    end if

    call mpi_finalize_topology(mesh%topo)
end program test_nan_guard
