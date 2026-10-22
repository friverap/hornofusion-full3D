!===============================================================================
! test_drift_source.f90 - Plan E E2 (pc_drift_source): fuente conocida del
! Poisson (auditoria 20, M20-6)
!
! El volumen de liquido que el transporte mete por caras que el Poisson NO
! enlaza (ws_pc_unl, m3/s) entra al Poisson como fuente: la presion debe
! evacuarlo por las caras ENLAZADAS en la misma iteracion. Bano en reposo de
! test_poisson_bath (todo liquido, p hidrostatica) y una fuente Q en una
! celda interior:
!   1. E2 ON : flujo neto conservativo SALIENTE de la celda = Q (1e-3 rel.)
!              y pp de la celda > 0 (la fuente empuja)
!   2. E2 OFF: la fuente no se ve (|pp|max ~ 0, flujo neto ~ 0)
!   3. E2 ON con ws_pc_unl de OTRO paso (ws_pc_unl_id viejo): inerte
!===============================================================================
program test_drift_source
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_momentum_3d, only: solve_momentum_3d
    use mod_pressure_3d, only: solve_pressure_correction
    use mod_drag_ergun, only: compute_ergun_drag
    use mod_probe, only: probe_set_step
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid, &
                             ws_pv_active, ws_pv_valid, ws_Fc_r, ws_Fc_th, ws_Fc_z, &
                             ws_pc_unl, ws_pc_unl_valid, ws_pc_unl_id
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas, liq_old, gas_old
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: Kz(:,:,:), drag(:,:,:), p_hyd(:,:,:)
    real(dp) :: r1, r2, r3, res, H, scale_p, ztop, g_eff, Q, qout, ppc, ppmax, qout1, ppc1
    integer  :: i, j, k, nr, nth, nz, i0, j0, k0
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 10
    cfg%dt = 0.01_dp
    cfg%solve_multiphase = .true.; cfg%solve_flow = .true.
    cfg%gas_in_poisson = .true.
    cfg%max_inner_pres = 2000          ! el balance de la fuente no debe depender de un CG truncado

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call phase_allocate(liq_old, mesh); call phase_allocate(gas_old, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    call ensure_workspace(mesh)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    allocate(Kz, mold=liq%ur); allocate(drag, mold=liq%ur); allocate(p_hyd, mold=sh%p)
    Kz = 0.0_dp
    ok = .true.

    ! Dominio TODO liquido, en reposo, p hidrostatica con referencia 0 en el
    ! centro del nivel superior (donde apply_pressure_bc ancla la salida)
    sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp; sol%mdot = 0.0_dp
    liq%alpha = 1.0_dp; gas%alpha = 0.0_dp
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
    gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
    liq%T = 1850.0_dp; sh%S_arc_mom = 0.0_dp
    ztop = mesh%z(nz)
    ! g efectiva con Boussinesq (el momento del liquido lo lleva):
    ! dp/dz = -rho g (1 - beta (T_l - T_ref))
    g_eff = GRAVITY * (1.0_dp - cfg%beta_expansion * (1850.0_dp - cfg%T_ref_boussinesq))
    do k = lbound(sh%p,3), ubound(sh%p,3)
        p_hyd(:,:,k) = liq%rho(1,1,1) * g_eff * (ztop - mesh%z(k))
    end do
    sh%p = p_hyd; sh%pp = 0.0_dp
    H = ztop - mesh%z(1)
    scale_p = liq%rho(1,1,1) * g_eff * H

    liq_old%ur = liq%ur; liq_old%uth = liq%uth; liq_old%uz = liq%uz
    liq_old%alpha = liq%alpha; liq_old%T = liq%T
    gas_old%ur = gas%ur; gas_old%uth = gas%uth; gas_old%uz = gas%uz
    gas_old%alpha = gas%alpha; gas_old%T = gas%T
    ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
    ws_pv_active = (ws_liq_cont .or. gas%alpha >= ALPHA_FLOW_CUTOFF) .and. (mesh%cell_type /= 0)
    ws_pv_valid = .true.

    i0 = nr / 2; j0 = nth / 2; k0 = nz / 2
    Q = 1.0e-4_dp * mesh%vol(i0,j0,k0) / cfg%dt

    ! 1. E2 ON
    call one_solve(.true., probe_id=1, unl_id=1)
    if (abs(qout - Q) > 1.0e-3_dp * Q .or. ppc <= 0.0_dp) then
        print '(A,ES12.4,A,ES12.4,A,ES11.3)', '   FAIL caso 1 (E2 on): salida neta ', qout, &
            ' frente a Q ', Q, '  pp celda ', ppc
        ok = .false.
    end if
    qout1 = qout; ppc1 = ppc
    ! 2. E2 OFF
    call one_solve(.false., probe_id=2, unl_id=2)
    if (abs(qout) > 1.0e-6_dp * Q .or. ppmax > 1.0e-9_dp * scale_p) then
        print '(A,ES12.4,A,ES11.3)', '   FAIL caso 2 (E2 off): salida neta ', qout, '  |pp|max ', ppmax
        ok = .false.
    end if
    ! 3. E2 ON, fuente de un paso anterior
    call one_solve(.true., probe_id=4, unl_id=3)
    if (abs(qout) > 1.0e-6_dp * Q .or. ppmax > 1.0e-9_dp * scale_p) then
        print '(A,ES12.4,A,ES11.3)', '   FAIL caso 3 (fuente de otro paso): salida neta ', qout, '  |pp|max ', ppmax
        ok = .false.
    end if

    print '(A,3ES12.4)', '   Q, salida neta (on), pp celda: ', Q, qout1, ppc1
    if (ok) then
        print '(A)', ' PASS test_drift_source'
    else
        print '(A)', ' FAIL test_drift_source'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine one_solve(on, probe_id, unl_id)
        logical, intent(in) :: on
        integer, intent(in) :: probe_id, unl_id
        integer :: ii, jj, kk
        cfg%pc_drift_source = on
        call probe_set_step(probe_id)
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        sh%p = p_hyd; sh%pp = 0.0_dp
        ws_pc_unl = 0.0_dp
        ws_pc_unl(i0,j0,k0) = Q
        ws_pc_unl_valid = .true.; ws_pc_unl_id = unl_id
        call compute_ergun_drag(liq, sol, mesh, cfg, drag)
        call solve_momentum_3d(liq, liq_old, gas, Kz, sh, mesh, cfg, liq%alpha, drag, .false., r1, r2, r3)
        call solve_pressure_correction(liq, gas, gas_old%T, sh, mesh, cfg, res)
        qout = ws_Fc_r(i0,j0,k0) - ws_Fc_r(i0-1,j0,k0) + ws_Fc_th(i0,j0,k0) - ws_Fc_th(i0,j0-1,k0) &
             + ws_Fc_z(i0,j0,k0) - ws_Fc_z(i0,j0,k0-1)
        ppc = sh%pp(i0,j0,k0)
        ppmax = 0.0_dp
        do kk = 1, nz
            do jj = 1, nth
                do ii = 1, nr
                    if (mesh%cell_type(ii,jj,kk) == 0) cycle
                    ppmax = max(ppmax, abs(sh%pp(ii,jj,kk)))
                end do
            end do
        end do
    end subroutine one_solve

end program test_drift_source
