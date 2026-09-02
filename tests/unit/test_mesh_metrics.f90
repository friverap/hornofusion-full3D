!===============================================================================
! test_mesh_metrics.f90 - Unit test de métricas de malla (mod_mesh_3d)
!
! Con malla estirada (stretch != 1):
!   - Suma de volúmenes físicos = pi*(R_shell^2 - R_AXIS_MIN^2)*H_total (exacta
!     por telescopía de caras, independiente del estiramiento).
!   - dr, dz > 0 y áreas >= 0 en el rango físico.
! Corre en MPI singleton (mpi_init_topology con 1 proceso).
!===============================================================================
program test_mesh_metrics
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    real(dp) :: vsum, vexact, err
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 10; cfg%ntheta = 12; cfg%nz = 8
    cfg%stretch_r = 1.4_dp; cfg%stretch_z = 1.3_dp

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)

    ok = .true.

    vsum   = sum(mesh%vol(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    vexact = PI * (cfg%R_shell**2 - R_AXIS_MIN**2) * cfg%H_total
    err    = abs(vsum - vexact) / vexact
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL suma de volúmenes, err rel = ', err
        ok = .false.
    end if

    if (any(mesh%dr(1:mesh%nr) <= 0.0_dp)) then
        print '(A)', '   FAIL dr <= 0 en rango físico'
        ok = .false.
    end if
    if (any(mesh%dz(1:mesh%nz) <= 0.0_dp)) then
        print '(A)', '   FAIL dz <= 0 en rango físico'
        ok = .false.
    end if
    if (any(mesh%Ar(0:mesh%nr, 1:mesh%ntheta, 1:mesh%nz) < 0.0_dp) .or. &
        any(mesh%Ath(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz) < 0.0_dp) .or. &
        any(mesh%Az(1:mesh%nr, 1:mesh%ntheta, 0:mesh%nz) < 0.0_dp)) then
        print '(A)', '   FAIL área de cara negativa en rango físico'
        ok = .false.
    end if

    call mpi_finalize_topology(mesh%topo)

    if (ok) then
        print '(A)', ' PASS test_mesh_metrics'
    else
        print '(A)', ' FAIL test_mesh_metrics'
        stop 1
    end if
end program test_mesh_metrics
