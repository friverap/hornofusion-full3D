!===============================================================================
! test_ecs_feed.f90 - Unit test del cargador continuo (E1.2)
!
! Malla pequeña en MPI singleton. N pasos de caudal fijo:
!   - conservación: Sum(m_s) - m_0 == Sum(mdot*dt) a 1e-12 relativo
!     (incluida m_ecs_pending si la banda se llena)
!   - acotamiento: alpha_s <= ecs_vfrac + eps y alpha_s + alpha_g <= 1 + eps
!   - la energía cargada = masa * e_s(T_charge) exacta
!   - el depósito respeta la banda (celdas fuera intactas)
! Parte 2 (Plan I, I2): baño con una capa CONDENSADA de escoria llena de 5
! celdas (más que ECS_MAX_LEVELS): sin la escoria en la capacidad toda la
! carga queda pendiente (legado); con ella la chatarra ATRAVIESA la capa, se
! apoya en el tope del acero y el reordenamiento sube la escoria desplazada
! (masa y energía de la escoria exactas, Sigma alpha <= 1, nada pendiente).
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
    use mod_slag_3d, only: slag_condensed_sort
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp) :: m0, m1, e0, e1, fed, dm_expected, err
    real(dp), parameter :: MDOT = 40.0_dp, DT = 0.5_dp
    integer :: n, i, j, k, kmin_ecs
    real(dp) :: msl0, esl0, over
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
        call ecs_feed(sol, gas, liq, mesh, cfg, MDOT, DT)
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

    ! ---- parte 2: capa condensada gruesa (Plan I, I2) ----
    cfg%solve_slag = .true.; cfg%slag_in_volume = .true.
    cfg%solve_flow = .true.; cfg%solve_multiphase = .true.; cfg%mixture_model = .false.
    ! legado (sin la escoria): las 4 celdas sobre el acero no tienen gas
    call setup_slag_bed()
    do n = 1, 5
        call ecs_feed(sol, gas, liq, mesh, cfg, MDOT, DT)
    end do
    if (.not. m_ecs_pending > 0.0_dp) then
        print '(A)', '   FAIL parte 2: sin la escoria la carga deberia quedar pendiente (caso no ejercido)'
        ok = .false.
    end if
    ! condensada: atraviesa la capa
    call setup_slag_bed()
    m0 = sum(sol%m_s(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    msl0 = sum(slag%m_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    esl0 = sum(slag%E_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    do n = 1, 20
        call ecs_feed(sol, gas, liq, mesh, cfg, MDOT, DT, sh, slag)
        call slag_condensed_sort(slag, liq, gas, sol, mesh, cfg, sh)
    end do
    m1 = sum(sol%m_s(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    if (m_ecs_pending > 0.0_dp .or. abs((m1 - m0) - 20.0_dp * MDOT * DT) > 1.0e-12_dp * 20.0_dp * MDOT * DT) then
        print '(A,2ES12.4)', '   FAIL parte 2: carga no colocada entera (pendiente, error): ', &
            m_ecs_pending, (m1 - m0) - 20.0_dp * MDOT * DT
        ok = .false.
    end if
    if (abs(sum(slag%m_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz)) - msl0) > 1.0e-12_dp * msl0 .or. &
        abs(sum(slag%E_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz)) - esl0) > 1.0e-12_dp * esl0) then
        print '(A)', '   FAIL parte 2: masa/energia de la escoria no conservadas'
        ok = .false.
    end if
    over = 0.0_dp; kmin_ecs = mesh%nz + 1
    do k = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                over = max(over, sol%alpha_s(i,j,k) + liq%alpha(i,j,k) + slag%alpha_sl(i,j,k) - 1.0_dp)
                if (sol%layer_id(i,j,k) == ID_ECS) kmin_ecs = min(kmin_ecs, k)
            end do
        end do
    end do
    if (over > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL parte 2: Sigma alpha > 1 tras el reordenamiento: ', over
        ok = .false.
    end if
    if (kmin_ecs /= 4) then
        print '(A,I4)', '   FAIL parte 2: la chatarra no se apoya en el tope del acero (k=4); base en k = ', kmin_ecs
        ok = .false.
    end if
    print '(A,I3,A,ES10.3)', '   parte 2 (escoria condensada): base de la chatarra k =', kmin_ecs, &
        '  sobrellenado ', over

    if (ok) then
        print '(A,F10.1,A)', ' PASS test_ecs_feed (', fed, ' kg cargados)'
    else
        print '(A)', ' FAIL test_ecs_feed'
        stop 1
    end if

contains

    ! baño lleno en k = 1..3, escoria condensada llena en k = 4..8, gas encima
    subroutine setup_slag_bed()
        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%m_C = 0.0_dp
        sol%layer_id = 0
        liq%alpha = 0.0_dp; liq%alpha(:,:,-1:3) = 1.0_dp; liq%T = 1850.0_dp
        slag%alpha_sl = 0.0_dp; slag%m_X = 0.0_dp
        slag%alpha_sl(:,:,4:8) = 1.0_dp
        where (mesh%cell_type == 0)
            slag%alpha_sl = 0.0_dp; liq%alpha = 0.0_dp
        end where
        slag%m_sl = slag%alpha_sl * cfg%rho_slag * mesh%vol
        slag%m_X(:,:,:,SL_CAO) = 0.5_dp * slag%m_sl
        slag%T_sl = 1850.0_dp
        slag%E_sl = slag%m_sl * cfg%cp_slag * 1850.0_dp
        gas%alpha = max(0.0_dp, 1.0_dp - liq%alpha - slag%alpha_sl)
        where (mesh%cell_type == 0) gas%alpha = 0.0_dp
        m_ecs_pending = 0.0_dp
    end subroutine setup_slag_bed

end program test_ecs_feed
