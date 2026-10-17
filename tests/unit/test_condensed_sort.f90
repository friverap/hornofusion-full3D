!===============================================================================
! test_condensed_sort.f90 - Flotacion condensada (Plan H, P3): reordenamiento
! neutro en volumen de acero/escoria dentro de cada segmento condensado.
! (1) columna ordenada (bano, interfaz mixta, escoria): sin cambio BIT A BIT;
! (2) pelicula de acero SOBRE la escoria: el acero baja; alpha_c de cada celda
!     a 1e-15 (el gas no se toca), energia del acero y de la escoria y masa
!     de escoria a 1e-13, ningun acero encima de la escoria;
! (3) dos segmentos separados por una celda de gas: sin trasvase entre ellos.
!===============================================================================
program test_condensed_sort
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_slag_3d, only: slag_condensed_sort
    implicit none
    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: al0(:,:,:), as0(:,:,:), T0(:,:,:), E0(:,:,:)
    real(dp) :: est0, est1, esl0, esl1, msl0, msl1, err_c
    integer  :: i, j, k, nr, nth, nz
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 3; cfg%ntheta = 4; cfg%nz = 10
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    allocate(al0, as0, T0, E0, mold=liq%alpha)
    ok = .true.

    ! ---- (1) ordenada ----
    call setcol([1.0_dp,1.0_dp,1.0_dp,0.45_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp], &
                [0.0_dp,0.0_dp,0.0_dp,0.55_dp,1.0_dp,0.3_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp])
    al0 = liq%alpha; as0 = slag%alpha_sl; T0 = liq%T; E0 = slag%E_sl
    call slag_condensed_sort(slag, liq, gas, sol, mesh, cfg, sh)
    if (any(liq%alpha(1:nr,1:nth,1:nz) /= al0(1:nr,1:nth,1:nz)) .or. &
        any(slag%alpha_sl(1:nr,1:nth,1:nz) /= as0(1:nr,1:nth,1:nz)) .or. &
        any(liq%T(1:nr,1:nth,1:nz) /= T0(1:nr,1:nth,1:nz)) .or. any(slag%E_sl(1:nr,1:nth,1:nz) /= E0(1:nr,1:nth,1:nz))) then
        print '(A)', '   FAIL caso 1: una columna ordenada cambio'; ok = .false.
    end if

    ! ---- (2) pelicula de acero sobre la escoria ----
    call setcol([1.0_dp,1.0_dp,0.0_dp,0.3_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp], &
                [0.0_dp,0.0_dp,1.0_dp,0.2_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp])
    al0 = liq%alpha; as0 = slag%alpha_sl
    call totals(est0, esl0, msl0)
    call slag_condensed_sort(slag, liq, gas, sol, mesh, cfg, sh)
    call totals(est1, esl1, msl1)
    err_c = maxval(abs((liq%alpha(1:nr,1:nth,1:nz) + slag%alpha_sl(1:nr,1:nth,1:nz)) &
                       - (al0(1:nr,1:nth,1:nz) + as0(1:nr,1:nth,1:nz))))
    if (err_c > 1.0e-15_dp) then
        print '(A,ES10.3)', '   FAIL caso 2: alpha_c por celda cambio (el gas se toco): ', err_c; ok = .false.
    end if
    if (abs(est1-est0) > 1.0e-13_dp*est0 .or. abs(esl1-esl0) > 1.0e-13_dp*esl0 .or. abs(msl1-msl0) > 1.0e-13_dp*msl0) then
        print '(A,3ES10.3)', '   FAIL caso 2: energia/masa: ', (est1-est0)/est0, (esl1-esl0)/esl0, (msl1-msl0)/msl0
        ok = .false.
    end if
    do j = 1, nth
        do i = 1, nr
            if (mesh%cell_type(i,j,3) == 0) cycle
            if (liq%alpha(i,j,4) > 1.0e-14_dp .and. slag%alpha_sl(i,j,3) > 1.0e-14_dp) then
                print '(A,2F8.4)', '   FAIL caso 2: acero encima de la escoria tras ordenar: ', &
                    liq%alpha(i,j,4), slag%alpha_sl(i,j,3); ok = .false.; exit
            end if
        end do
        if (.not. ok) exit
    end do

    ! ---- (3) dos segmentos separados por gas ----
    call setcol([0.5_dp,0.5_dp,0.0_dp,0.0_dp,0.4_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp], &
                [0.0_dp,0.0_dp,0.0_dp,0.6_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp,0.0_dp])
    al0 = liq%alpha
    call slag_condensed_sort(slag, liq, gas, sol, mesh, cfg, sh)
    if (any(liq%alpha(1:nr,1:nth,1:2) /= al0(1:nr,1:nth,1:2))) then
        print '(A)', '   FAIL caso 3: el segmento de abajo cambio'; ok = .false.
    end if
    if (any(abs(liq%alpha(1:nr,1:nth,3)) > 0.0_dp)) then
        print '(A)', '   FAIL caso 3: trasvase a la celda de gas'; ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_condensed_sort (ordenada intacta; pelicula baja con alpha_c y energia exactas; segmentos aislados)'
    else
        print '(A)', ' FAIL test_condensed_sort'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
contains
    subroutine setcol(al, asl)
        real(dp), intent(in) :: al(10), asl(10)
        integer :: ii, jj, kk
        liq%alpha = 0.0_dp; slag%alpha_sl = 0.0_dp; slag%m_sl = 0.0_dp; slag%E_sl = 0.0_dp; slag%m_X = 0.0_dp
        do kk = 1, nz
            do jj = 1, nth
                do ii = 1, nr
                    if (mesh%cell_type(ii,jj,kk) == 0) cycle
                    liq%alpha(ii,jj,kk) = al(kk)
                    liq%T(ii,jj,kk) = 1800.0_dp + 10.0_dp * kk
                    slag%alpha_sl(ii,jj,kk) = asl(kk)
                    slag%m_sl(ii,jj,kk) = asl(kk) * cfg%rho_slag * mesh%vol(ii,jj,kk)
                    slag%E_sl(ii,jj,kk) = slag%m_sl(ii,jj,kk) * cfg%cp_slag * (1600.0_dp + 20.0_dp * kk)
                    slag%m_X(ii,jj,kk,:) = slag%m_sl(ii,jj,kk) * 0.1_dp
                end do
            end do
        end do
        gas%alpha = max(0.0_dp, 1.0_dp - liq%alpha - slag%alpha_sl)
    end subroutine setcol
    subroutine totals(est, esl, msl)
        real(dp), intent(out) :: est, esl, msl
        est = sum(liq%alpha(1:nr,1:nth,1:nz) * mesh%vol(1:nr,1:nth,1:nz) * liq%T(1:nr,1:nth,1:nz))
        esl = sum(slag%E_sl(1:nr,1:nth,1:nz)); msl = sum(slag%m_sl(1:nr,1:nth,1:nz))
    end subroutine totals
end program test_condensed_sort
