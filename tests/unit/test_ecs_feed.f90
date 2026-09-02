!===============================================================================
! test_ecs_feed.f90 - Unit test del cargador continuo (E1.2)
!
! Malla pequeña en MPI singleton. N pasos de caudal fijo:
!   - conservación: Sum(m_s) - m_0 == Sum(mdot*dt) a 1e-12 relativo
!     (incluida m_ecs_pending si la banda se llena)
!   - acotamiento: alpha_s <= ecs_vfrac + eps y alpha_s + alpha_g <= 1 + eps
!   - la energía cargada = masa * e_s(T_charge) exacta
!   - el depósito respeta la banda (celdas fuera intactas)
!===============================================================================
program test_ecs_feed
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_melting_3d, only: solid_enthalpy
    use mod_ecs_feed
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp) :: m0, m1, e0, e1, fed, dm_expected, err
    real(dp), parameter :: MDOT = 40.0_dp, DT = 0.5_dp
    integer :: n, i, j, k
    logical :: ok

    call config_set_defaults(cfg)
    cfg%nr = 8; cfg%ntheta = 12; cfg%nz = 10
    cfg%solve_ecs = .true.
    cfg%ecs_rate = MDOT
    cfg%ecs_theta_center = 0.5_dp * PI
    cfg%ecs_theta_width  = 0.5_dp
    cfg%ecs_r_inner      = 2.4_dp
    cfg%ecs_vfrac        = 0.6_dp
    cfg%ecs_T_charge     = 320.0_dp
    cfg%ecs_carbon_frac  = 0.01_dp

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh)
    call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)

    ok = .true.
    m0 = sum(sol%m_s(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    e0 = sum(sol%E_s(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))

    do n = 1, 20
        call ecs_feed(sol, gas, mesh, cfg, MDOT, DT)
    end do

    m1 = sum(sol%m_s(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    e1 = sum(sol%E_s(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    dm_expected = 20.0_dp * MDOT * DT
    fed = (m1 - m0) + m_ecs_pending

    err = abs(fed - dm_expected) / dm_expected
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL conservacion de masa, err = ', err
        ok = .false.
    end if

    err = abs((e1 - e0) - (m1 - m0) * solid_enthalpy(cfg%ecs_T_charge, cfg)) &
          / max(e1 - e0, 1.0_dp)
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL energia cargada, err = ', err
        ok = .false.
    end if

    do k = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                if (sol%alpha_s(i,j,k) > cfg%ecs_vfrac + 1.0e-12_dp) then
                    print '(A,3I4,F8.4)', '   FAIL alpha_s > vfrac en ', &
                        i, j, k, sol%alpha_s(i,j,k)
                    ok = .false.
                end if
                if (sol%alpha_s(i,j,k) + gas%alpha(i,j,k) > 1.0_dp + 1e-12_dp) then
                    print '(A,3I4)', '   FAIL suma alpha > 1 en ', i, j, k
                    ok = .false.
                end if
                ! fuera de la banda: sin deposito
                if ((mesh%r(i) < cfg%ecs_r_inner .or. &
                     abs(atan2(sin(mesh%theta(j) - cfg%ecs_theta_center), &
                               cos(mesh%theta(j) - cfg%ecs_theta_center))) &
                     > 0.5_dp * cfg%ecs_theta_width + 1e-9_dp) .and. &
                    sol%layer_id(i,j,k) == ID_ECS) then
                    print '(A,3I4)', '   FAIL deposito fuera de banda ', i, j, k
                    ok = .false.
                end if
            end do
        end do
    end do

    if (ok) then
        print '(A,F10.1,A)', ' PASS test_ecs_feed (', fed, ' kg cargados)'
    else
        print '(A)', ' FAIL test_ecs_feed'
        stop 1
    end if

end program test_ecs_feed
