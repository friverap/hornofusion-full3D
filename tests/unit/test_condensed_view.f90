!===============================================================================
! test_condensed_view.f90 - Vista condensada acero+escoria (Plan H, P1).
! (1) entrar y salir de la vista restituye liq/liq_old BIT A BIT;
! (2) alpha_c w_c = alpha_l w_l(T_l) + alpha_sl rho_sl g a 1e-15 relativo, y
!     rho_c = (alpha_l rho_l + alpha_sl rho_sl)/alpha_c;
! (3) una celda SOLO de escoria no lee la T del acero (T basura 1e30): w_c =
!     rho_sl g exacto;
! (4) liq_w: con la vista apagada es liq_own_weight bit a bit; encendida, ws_wc.
!===============================================================================
program test_condensed_view
    use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_workspace
    implicit none
    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, liq_old
    real(dp), allocatable :: asl(:,:,:), asl0(:,:,:), a0(:,:,:), r0(:,:,:), ao0(:,:,:), ro0(:,:,:)
    real(dp) :: wl, lhs, rhs, err, w0
    integer  :: i, j, k
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 4; cfg%ntheta = 8; cfg%nz = 6
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(liq_old, mesh)
    call ensure_workspace(mesh)
    ok = .true.
    allocate(asl, asl0, a0, r0, ao0, ro0, mold=liq%alpha)
    ! campos con valores no triviales
    do k = lbound(liq%alpha,3), ubound(liq%alpha,3)
        do j = lbound(liq%alpha,2), ubound(liq%alpha,2)
            do i = lbound(liq%alpha,1), ubound(liq%alpha,1)
                liq%alpha(i,j,k) = mod(0.137_dp * (i + 2*j + 3*k), 0.7_dp)
                asl(i,j,k) = mod(0.091_dp * (3*i + j + k), 0.3_dp)
                liq%rho(i,j,k) = 7000.0_dp + i
                liq%T(i,j,k) = 1800.0_dp + 3.0_dp * k
                liq_old%alpha(i,j,k) = liq%alpha(i,j,k) * 0.9_dp
                liq_old%rho(i,j,k) = 7000.0_dp
                asl0(i,j,k) = asl(i,j,k) * 1.1_dp
            end do
        end do
    end do
    ! celda solo de escoria con T basura
    liq%alpha(2,3,3) = 0.0_dp; asl(2,3,3) = 0.6_dp; liq%T(2,3,3) = ieee_value(1.0_dp, ieee_quiet_nan)
    a0 = liq%alpha; r0 = liq%rho; ao0 = liq_old%alpha; ro0 = liq_old%rho

    ! (4) liq_w con la vista apagada
    w0 = liq_w(liq%rho(1,1,1), liq%T(1,1,1), cfg%beta_expansion, cfg%T_ref_boussinesq, 1, 1, 1)
    if (w0 /= liq_own_weight(liq%rho(1,1,1), liq%T(1,1,1), cfg%beta_expansion, cfg%T_ref_boussinesq)) then
        print '(A)', '   FAIL liq_w sin vista distinto de liq_own_weight'; ok = .false.
    end if

    call cond_view_enter(liq, liq_old, asl, asl0, cfg%rho_slag, cfg%beta_expansion, cfg%T_ref_boussinesq)
    err = 0.0_dp
    do k = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                if (liq%alpha(i,j,k) <= 0.0_dp) cycle
                if (i == 2 .and. j == 3 .and. k == 3) cycle
                wl = liq_own_weight(r0(i,j,k), liq%T(i,j,k), cfg%beta_expansion, cfg%T_ref_boussinesq)
                lhs = liq%alpha(i,j,k) * ws_wc(i,j,k)
                rhs = a0(i,j,k) * wl + asl(i,j,k) * cfg%rho_slag * GRAVITY
                err = max(err, abs(lhs - rhs) / abs(rhs))
                err = max(err, abs(liq%rho(i,j,k) * liq%alpha(i,j,k) - (a0(i,j,k) * r0(i,j,k) &
                          + asl(i,j,k) * cfg%rho_slag)) / (a0(i,j,k) * r0(i,j,k) + asl(i,j,k) * cfg%rho_slag))
            end do
        end do
    end do
    if (err > 1.0e-15_dp) then
        print '(A,ES10.3)', '   FAIL identidad del peso/densidad condensados, err = ', err; ok = .false.
    end if
    if (ws_wc(2,3,3) /= cfg%rho_slag * GRAVITY) then
        print '(A,ES12.4)', '   FAIL celda solo de escoria lee la T del acero: w_c = ', ws_wc(2,3,3); ok = .false.
    end if
    if (liq_w(liq%rho(2,3,3), liq%T(2,3,3), cfg%beta_expansion, cfg%T_ref_boussinesq, 2, 3, 3) /= ws_wc(2,3,3)) then
        print '(A)', '   FAIL liq_w con la vista no es ws_wc'; ok = .false.
    end if
    call cond_view_exit(liq, liq_old)
    if (any(liq%alpha /= a0) .or. any(liq%rho /= r0) .or. any(liq_old%alpha /= ao0) &
        .or. any(liq_old%rho /= ro0) .or. ws_cond_on) then
        print '(A)', '   FAIL la vista no se deshace bit a bit'; ok = .false.
    end if

    if (ok) then
        print '(A,ES10.3,A)', ' PASS test_condensed_view (ida y vuelta bit a bit; peso condensado err ', err, ')'
    else
        print '(A)', ' FAIL test_condensed_view'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_condensed_view
