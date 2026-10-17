!===============================================================================
! test_slag_reduction.f90 - Reduccion FeO + C -> Fe + CO de la escoria
! (auditoria 6, M6-3/M6-4). Singleton MPI, sin O2 (solo reduccion).
!   1. Escoria sobre una celda casi llena (hueco 0.005) y bano lleno debajo:
!      la solicitud de Fe supera el hueco, que queda EXACTAMENTE lleno. El CO
!      no puede ir a esa celda (ya no tiene gas: el solver de especies lo
!      descartaria, M6-3) y sube a la de encima. Conservacion de Fe y de CO a
!      1e-12, Sigma alpha <= 1.
!   2. Dos celdas de escoria APILADAS sobre bano lleno: cada una llena primero
!      su propio hueco y solo el sobrante baja; la de abajo queda llena y su
!      CO sube, ninguna celda pasa de su hueco (M6-4), conservacion a 1e-12.
!   3. (auditoria general Plan I, fisica MEDIO-1) escoria CONDENSADA con
!      chatarra sumergida: celda 5 con escoria 0.5 + chatarra 0.485 + gas de
!      poro 0.015 (>= ALPHA_FLOW_CUTOFF) bajo escoria llena (6) y gas (7+):
!      el gas de poro esta aislado (el sort lo compactaria con su CO); todo el
!      CO de las celdas 5 y 6 sube al gas libre (k >= 7), conservado.
!===============================================================================
program test_slag_reduction
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_slag_chemistry, only: compute_slag_chemistry
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, liq_old, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), parameter :: MW_FE = 0.05585_dp, MW_FEO = 0.07185_dp, MW_CO = 0.028_dp
    logical :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 10
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(liq_old, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    ok = .true.
    cfg%dt = 1000.0_dp

    ! --- caso 1: escoria sobre celda casi llena -------------------------------
    call setup()
    call put_slag(5, 0.6_dp, 0.3995_dp)
    call run_case('caso 1', 5)

    ! --- caso 2: escoria apilada ----------------------------------------------
    call setup()
    call put_slag(5, 0.6_dp, 0.395_dp)
    call put_slag(6, 0.6_dp, 0.0_dp)
    call run_case('caso 2', 6)

    ! --- caso 3: chatarra sumergida en escoria condensada ---------------------
    cfg%solve_slag = .true.
    if (.not. slag_condensed_on(cfg)) call fail('caso 3: la escoria condensada no esta activa', 0.0_dp)
    call setup()
    call put_slag(5, 0.5_dp, 0.0_dp)
    call put_slag(6, 1.0_dp, 0.0_dp)
    sol%alpha_s(:,:,5) = 0.485_dp
    gas%alpha(:,:,5) = 0.015_dp
    call run_case('caso 3', 6)
    if (sum(sh%S_CO_src(1:6,1:8,1:6)) /= 0.0_dp) &
        call fail('caso 3: CO en el gas aislado bajo la escoria (kg/m3/s)', sum(sh%S_CO_src(1:6,1:8,1:6)))
    cfg%solve_slag = .false.

    if (ok) then
        print '(A)', ' PASS test_slag_reduction (CO solo donde queda gas, Sigma alpha <= 1, Fe y CO conservados)'
    else
        print '(A)', ' FAIL test_slag_reduction'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine setup()
        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp
        liq%alpha = 0.0_dp; liq%alpha(:,:,-1:4) = 1.0_dp; liq%T = 1850.0_dp
        slag%m_sl = 0.0_dp; slag%alpha_sl = 0.0_dp; slag%E_sl = 0.0_dp
        slag%m_X = 0.0_dp; slag%T_sl = 0.0_dp; slag%alpha_foam = 0.0_dp
        sh%Y_O2 = 0.0_dp; sh%Y_CO = 0.0_dp; sh%Y_CO2 = 0.0_dp
        sh%S_O2_src = 0.0_dp; sh%S_CO_src = 0.0_dp; sh%S_CO2_src = 0.0_dp
        gas%alpha = 1.0_dp - liq%alpha
    end subroutine setup

    subroutine put_slag(kk, asl, al)
        integer, intent(in)  :: kk
        real(dp), intent(in) :: asl, al
        integer :: ii, jj
        do jj = 1, mesh%ntheta
            do ii = 1, mesh%nr
                slag%alpha_sl(ii,jj,kk) = asl
                slag%m_sl(ii,jj,kk) = cfg%rho_slag * asl * mesh%vol(ii,jj,kk)
                slag%m_X(ii,jj,kk,SL_FEO) = 0.40_dp * slag%m_sl(ii,jj,kk)
                slag%m_X(ii,jj,kk,SL_C)   = 0.10_dp * slag%m_sl(ii,jj,kk)
                slag%m_X(ii,jj,kk,SL_CAO) = 0.30_dp * slag%m_sl(ii,jj,kk)
                slag%m_X(ii,jj,kk,SL_SIO2) = 0.15_dp * slag%m_sl(ii,jj,kk)
                slag%T_sl(ii,jj,kk) = 1900.0_dp
                slag%E_sl(ii,jj,kk) = slag%m_sl(ii,jj,kk) * cfg%cp_slag * 1900.0_dp
                liq%alpha(ii,jj,kk) = al
                gas%alpha(ii,jj,kk) = 1.0_dp - asl - al
            end do
        end do
    end subroutine put_slag

    subroutine run_case(tag, ktop)
        character(len=*), intent(in) :: tag
        integer, intent(in) :: ktop
        real(dp) :: feo0, fe0, feo1, fe1, dfe, dco, co_src, gap, worst_sum, co_nogas
        integer :: ii, jj, kk
        liq_old%alpha = liq%alpha; liq_old%T = liq%T
        feo0 = sum(slag%m_X(1:6,1:8,1:10,SL_FEO))
        fe0 = mass_liq()
        call compute_slag_chemistry(slag, liq, liq_old, gas, sol, sh, mesh, cfg)
        feo1 = sum(slag%m_X(1:6,1:8,1:10,SL_FEO))
        fe1 = mass_liq()
        dfe = (feo0 - feo1) * MW_FE / MW_FEO
        dco = (feo0 - feo1) * MW_CO / MW_FEO
        if (.not. dfe > 0.0_dp) call fail(tag // ': no hubo reduccion', dfe)
        ! tolerancia: redondeo de la suma del inventario (~1e-14 de fe1)
        if (abs((fe1 - fe0) - dfe) > 1.0e-12_dp * dfe + 1.0e-14_dp * fe1) &
            call fail(tag // ': Fe no conservado (rel)', ((fe1 - fe0) - dfe) / dfe)
        co_src = 0.0_dp; worst_sum = 0.0_dp; co_nogas = 0.0_dp
        do kk = 1, 10
            do jj = 1, 8
                do ii = 1, 6
                    co_src = co_src + sh%S_CO_src(ii,jj,kk) * mesh%vol(ii,jj,kk) * cfg%dt
                    gap = 1.0_dp - sol%alpha_s(ii,jj,kk) - slag%alpha_sl(ii,jj,kk) - liq%alpha(ii,jj,kk)
                    worst_sum = max(worst_sum, -gap)
                    if (sh%S_CO_src(ii,jj,kk) > 0.0_dp .and. gap < ALPHA_CUTOFF) &
                        co_nogas = co_nogas + sh%S_CO_src(ii,jj,kk) * mesh%vol(ii,jj,kk) * cfg%dt
                end do
            end do
        end do
        if (abs(co_src - dco) > 1.0e-12_dp * dco) call fail(tag // ': CO no conservado (rel)', (co_src - dco) / dco)
        if (worst_sum > 1.0e-12_dp) call fail(tag // ': Sigma alpha > 1 en', worst_sum)
        if (co_nogas > 0.0_dp) call fail(tag // ': CO en celdas sin gas (kg)', co_nogas)
        ! la celda de escoria inferior (k = 5) debe quedar llena: el caso
        ! ejerce de verdad el limite del hueco
        gap = 1.0_dp - slag%alpha_sl(3,4,5) - liq%alpha(3,4,5)
        if (gap > 1.0e-9_dp .and. ktop == 5) call fail(tag // ': el hueco no se lleno (no ejerce M6-3)', gap)
        print '(3A,ES11.3,A,ES10.3)', '   ', tag, ': Fe reducido ', dfe, ' kg, hueco final k=5 ', gap
    end subroutine run_case

    function mass_liq() result(mm)
        real(dp) :: mm
        mm = sum(liq%alpha(1:6,1:8,1:10) * liq%rho(1:6,1:8,1:10) * mesh%vol(1:6,1:8,1:10))
    end function mass_liq

    subroutine fail(msg, v)
        character(len=*), intent(in) :: msg
        real(dp), intent(in) :: v
        print '(3A,ES12.4)', '   FAIL ', msg, ': ', v
        ok = .false.
    end subroutine fail
end program test_slag_reduction
