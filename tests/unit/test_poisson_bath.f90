!===============================================================================
! test_poisson_bath.f90 - Punto fijo ferrostatico del acople P-V (Plan C, F0)
!
! Motivo: Bug 19. El acople presion-velocidad debe ADMITIR un bano en
! reposo: dominio lleno de liquido puro (alpha_l = 1), u = 0 y
! p = rho_l g_eff (z_top - z) exacta, con g_eff = g (1 - beta (T_l - T_amb))
! porque el momento del liquido lleva Boussinesq. Con p lineal, dp/dz central y unilateral valen -rho_l g
! exactamente y cancelan la gravedad del momento; la velocidad de cara de
! Rhie-Chow es 0 y la divergencia tambien => UNA iteracion momento+presion
! debe dejar pp ~ 0 y u ~ 0 (a redondeo relativo a rho g H y a rho g dt).
! Cualquier termino nuevo del Poisson (transitorio de densidad, F2) debe
! preservar este punto fijo: en reposo la composicion no cambia.
!
! Casos (singleton MPI, malla pequena, gas inactivo en todo el dominio):
!   1. |pp|max <= 1e-9 * rho g H
!   2. |u_l|max <= 1e-9 * g dt   (aceleracion residual nula)
!   3. p tras la correccion sigue siendo hidrostatica a 1e-9 relativo
!===============================================================================
program test_poisson_bath
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_momentum_3d, only: solve_momentum_3d
    use mod_pressure_3d, only: solve_pressure_correction
    use mod_drag_ergun, only: compute_ergun_drag
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid, &
                             ws_pv_active, ws_pv_valid, ws_Fc_r, ws_Fc_th, ws_Fc_z, &
                             ws_Fc_lk_z, ws_Fc_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas, liq_old, gas_old
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: Kz(:,:,:), drag(:,:,:), p_hyd(:,:,:)
    real(dp) :: r1, r2, r3, res, H, scale_p, ppmax, umax, perr, ztop, g_eff
    real(dp) :: fmax, scale_f
    integer  :: nlk
    integer  :: i, j, k, nr, nth, nz
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 10
    cfg%dt = 0.01_dp
    cfg%solve_multiphase = .true.; cfg%solve_flow = .true.
    cfg%gas_in_poisson = .true.

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
    ! dp/dz = -rho g (1 - beta (T_l - T_amb))
    g_eff = GRAVITY * (1.0_dp - cfg%beta_expansion * (1850.0_dp - cfg%T_ambient))
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

    call compute_ergun_drag(liq, sol, mesh, cfg, drag)
    call solve_momentum_3d(liq, liq_old, gas, Kz, sh, mesh, cfg, liq%alpha, drag, .false., r1, r2, r3)
    call solve_pressure_correction(liq, gas, gas_old%T, sh, mesh, cfg, res)

    ppmax = 0.0_dp; umax = 0.0_dp; perr = 0.0_dp
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                ppmax = max(ppmax, abs(sh%pp(i,j,k)))
                umax  = max(umax, sqrt(liq%ur(i,j,k)**2 + liq%uth(i,j,k)**2 + liq%uz(i,j,k)**2))
                perr  = max(perr, abs(sh%p(i,j,k) - p_hyd(i,j,k)))
            end do
        end do
    end do
    if (ppmax > 1.0e-9_dp * scale_p) then
        print '(A,ES10.3,A,ES10.3)', '   FAIL caso 1: |pp|max = ', ppmax, ' frente a rho g H = ', scale_p
        ok = .false.
    end if
    if (umax > 1.0e-9_dp * GRAVITY * cfg%dt) then
        print '(A,ES10.3,A,ES10.3)', '   FAIL caso 2: |u_l|max = ', umax, ' frente a g dt = ', GRAVITY * cfg%dt
        ok = .false.
    end if
    if (perr > 1.0e-9_dp * scale_p) then
        print '(A,ES10.3)', '   FAIL caso 3: p se aparto de la hidrostatica: ', perr
        ok = .false.
    end if
    ! Caso 4 (Plan C F1): los flujos CONSERVATIVOS exportados por el Poisson
    ! son ~0 en reposo y TODAS las caras internas del bano estan enlazadas
    ! (escala: masa que moveria g dt por la cara mayor)
    fmax = 0.0_dp; nlk = 0
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                fmax = max(fmax, abs(ws_Fc_r(i,j,k)), abs(ws_Fc_th(i,j,k)), abs(ws_Fc_z(i,j,k)))
                if (k < nz .and. ws_Fc_lk_z(i,j,k) == 1) nlk = nlk + 1
            end do
        end do
    end do
    ! flujos VOLUMETRICOS (m3/s): escala g dt A
    scale_f = GRAVITY * cfg%dt * maxval(mesh%Az(1:nr,1:nth,1:nz))
    if (.not. ws_Fc_valid .or. fmax > 1.0e-9_dp * scale_f) then
        print '(A,ES10.3,A,ES10.3)', '   FAIL caso 4: |F_c|max = ', fmax, ' frente a g dt A = ', scale_f
        ok = .false.
    end if
    if (nlk /= count(mesh%cell_type(1:nr,1:nth,1:nz-1) /= 0 .and. mesh%cell_type(1:nr,1:nth,2:nz) /= 0)) then
        print '(A,I0)', '   FAIL caso 4: caras verticales del bano sin enlazar; enlazadas = ', nlk
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_poisson_bath'
    else
        print '(A)', ' FAIL test_poisson_bath'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_poisson_bath
