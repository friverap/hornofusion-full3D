!===============================================================================
! test_do_equilibrium.f90 - Verificación del DO real (C3.4, hallazgo 3.5)
!
! Recinto isotermo: todo el dominio (gas + sólido) y las paredes a la misma
! temperatura T0. En equilibrio radiativo, I = B en todas partes, G = 4*sigma*T0^4
! y el término fuente neto k*(G - 4*sigma*T0^4) debe anularse.
!
! Las proyecciones de cara integradas exactas cierran cada celda a precisión
! de máquina, así que el test exige |S_rad| < 1e-9 * 4*k*sigma*T0^4.
! El DO anterior (barrido solo radial + S_RAD_LIMIT) no podía pasar esto.
!===============================================================================
program test_do_equilibrium
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_radiation_do, only: solve_radiation_do
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(shared_t) :: sh
    real(dp), parameter :: T0 = 1500.0_dp
    real(dp) :: ref, worst
    integer  :: i, j, k, iq
    integer, parameter :: NQS(3) = [4, 6, 8]
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 10; cfg%ntheta = 12; cfg%nz = 8
    cfg%stretch_r = 1.3_dp; cfg%stretch_z = 1.2_dp
    cfg%T_wall = T0
    cfg%dt = 0.1_dp
    cfg%audit_freq = 0

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh)
    call shared_allocate(sh, mesh)

    ! Estado isotermo: gas puro a T0 (alpha_s = 0 -> sin depósito al sólido)
    liq%alpha = 0.0_dp; gas%alpha = 1.0_dp
    liq%T = T0; gas%T = T0
    sol%alpha_s = 0.0_dp; sol%T_s = T0; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp

    ! C4.2: el equilibrio isotermo debe cumplirse en las TRES cuadraturas
    ref = 4.0_dp * 0.3_dp * STEFAN_BOLTZMANN * T0**4   ! 4*kappa_gas*sigma*T0^4
    ok = .true.
    do iq = 1, 3
        cfg%do_quadrature = NQS(iq)
        call solve_radiation_do(liq, gas, sol, sh, mesh, cfg)
        worst = 0.0_dp
        do k = 1, mesh%nz
            do j = 1, mesh%ntheta
                do i = 1, mesh%nr
                    if (mesh%cell_type(i,j,k) == 0) cycle
                    worst = max(worst, abs(sh%S_rad(i,j,k)))
                end do
            end do
        end do
        if (worst / ref >= 1.0e-9_dp) then
            print '(A,I2,A,ES10.3)', '   FAIL S', NQS(iq), &
                '  |S_rad|/4kσT⁴ = ', worst/ref
            ok = .false.
        else
            print '(A,I2,A,ES10.3)', '   OK   S', NQS(iq), &
                '  |S_rad|/4kσT⁴ = ', worst/ref
        end if
    end do

    call mpi_finalize_topology(mesh%topo)

    if (ok) then
        print '(A)', ' PASS test_do_equilibrium (S4/S6/S8)'
    else
        print '(A)', ' FAIL test_do_equilibrium'
        stop 1
    end if
end program test_do_equilibrium
