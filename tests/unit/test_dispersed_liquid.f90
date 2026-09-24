!===============================================================================
! test_dispersed_liquid.f90 - Liquido disperso fuera del acople P-V (Bug 15)
!
! Motivo: B1 v11/v12 — gotas que cruzaban ALPHA_FLOW_CUTOFF entraban al
! Poisson con 20 m/s y exigian correcciones de MPa; las puntas aceleraban
! el gas a km/s y a t~415 s p saturo en P_HYDRO_CAP en todo el horno
! (cave-in espurio). Ahora el liquido con alpha_l < ALPHA_LIQ_CONT fuera
! del lecho es fase dispersa: velocidad = gas + sedimentacion terminal,
! sin momento propio y sin entrar al Poisson.
!
! Casos (singleton MPI):
!   1. Predicado liq_continuous: 0.05 sin chatarra -> disperso; 0.5 sin
!      chatarra -> continuo; 0.05 con chatarra (alpha_s=0.3) -> continuo
!      (umbral ordinario); 0.005 con chatarra -> disperso.
!   2. Momento: gas uniforme uz=+3, ur=1; gota alpha_l=0.05 (sin chatarra)
!      con velocidad inicial 20 m/s -> tras solve_momentum_3d del liquido
!      su velocidad es la de drift RELAJADA desde liq_old con tau_p = u_t/g
!      hacia (1, 0, 3 - u_t) (exacta a 1e-9); una celda de bano (alpha_l=
!      0.6) NO queda en el valor drift (resuelve su momento).
!   3. Presion: bano en reposo (alpha_l=0.7 en k=1..2) + gota alpha_l=0.05
!      en k=3, pegada a la superficie del bano (cara enlazada).
!      (a) Con el fix, p tras UNA correccion es el mismo (1e-3 relativo;
!          el residuo es el momento del splash que la superficie continua
!          recibe por la cara compartida) con la gota a -20 m/s y en
!          reposo: su velocidad no entra al Poisson.
!      (b) Con la regla antigua (mascara invalida: alpha >= 0.01 entra),
!          la gota a -20 m/s multiplica p_max por > 10: es la punta de
!          rho_l*u^2 que rompio B1.
!   4. Acople gas-gota FISICO: gota dispersa alpha_l=0.005 a su drift (-u_t)
!      y K = a_l*(rho_l-rho_g)*g/u_t (arrastre = peso a velocidad terminal,
!      implicito): el cambio de velocidad del gas en un paso es
!      -K u_t dt/(a_g rho_g + K dt), a 1e-2. Con K = a_l a_g rho_l/TAU_LG
!      (0.01 s) el gas quedaba clavado en 0.1 ms; con K=0, libre bajo 100x
!      su masa.
!===============================================================================
program test_dispersed_liquid
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_momentum_3d, only: solve_momentum_3d
    use mod_pressure_3d, only: solve_pressure_correction
    use mod_continuity, only: compute_liquid_drift
    use mod_drag_ergun, only: compute_ergun_drag
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas, liq_old, gas_old
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: Kz(:,:,:), drag(:,:,:), p_ref(:,:,:)
    real(dp) :: u_t, r1, r2, r3, res, pscale
    integer  :: nr, nth, nz, ic, jc, kc
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 8
    cfg%dt = 0.002_dp
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
    allocate(Kz, mold=liq%ur); allocate(drag, mold=liq%ur); allocate(p_ref, mold=sh%p)
    Kz = 0.0_dp
    ok = .true.
    ic = 3; jc = 4; kc = 5

    ! ---- caso 1: predicado ----
    if (liq_continuous(0.05_dp, 0.0_dp))       call fail('0.05 sin chatarra deberia ser disperso')
    if (.not. liq_continuous(0.5_dp, 0.0_dp))  call fail('0.5 sin chatarra deberia ser continuo')
    if (.not. liq_continuous(0.05_dp, 0.3_dp)) call fail('0.05 con chatarra deberia ser continuo')
    if (liq_continuous(0.005_dp, 0.3_dp))      call fail('0.005 con chatarra deberia ser disperso')

    ! ---- caso 2: momento drift-flux ----
    sol%alpha_s = 0.0_dp; sol%mdot = 0.0_dp; slag%alpha_sl = 0.0_dp
    liq%alpha = 0.0_dp
    liq%alpha(ic,jc,kc) = 0.05_dp          ! gota
    liq%alpha(ic,jc,2)  = 0.6_dp           ! bano
    gas%alpha = 1.0_dp - liq%alpha
    gas%ur = 1.0_dp; gas%uth = 0.0_dp; gas%uz = 3.0_dp
    liq%ur = 20.0_dp; liq%uth = 0.0_dp; liq%uz = 20.0_dp
    call copy_old()
    ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
    call compute_liquid_drift(liq, gas, sol, mesh, cfg, liq_old)
    call compute_ergun_drag(liq, sol, mesh, cfg, drag)
    call solve_momentum_3d(liq, liq_old, gas, Kz, sh, mesh, cfg, liq%alpha, drag, .false., r1, r2, r3)
    u_t = settling_velocity(cfg%d_droplet, liq%rho(ic,jc,kc), gas%rho(ic,jc,kc), gas%mu(ic,jc,kc))
    call drift_velocity(1.0_dp, 0.0_dp, 3.0_dp, u_t, r1, r2, r3)   ! objetivo acotado
    ! relajacion de particula desde liq_old (20, 0, 20) con f = dt g / u_t
    pscale = min(1.0_dp, cfg%dt * GRAVITY / u_t)
    r1 = 20.0_dp + pscale * (r1 - 20.0_dp); r3 = 20.0_dp + pscale * (r3 - 20.0_dp)
    if (abs(liq%uz(ic,jc,kc) - r3) > 1.0e-9_dp .or. abs(liq%ur(ic,jc,kc) - r1) > 1.0e-9_dp) then
        print '(A,3F10.4)', '   FAIL caso 2: gota no en drift-flux: uz, ur, u_t = ', liq%uz(ic,jc,kc), liq%ur(ic,jc,kc), u_t
        ok = .false.
    end if
    if (abs(liq%uz(ic,jc,2) - r3) < 1.0e-6_dp) then
        print '(A)', '   FAIL caso 2: la celda de bano quedo en el valor drift (no resolvio su momento)'
        ok = .false.
    end if

    ! ---- caso 3a: p independiente de la velocidad de la gota (fix) ----
    call setup_bath(.true., 0.0_dp)
    call one_pv_iteration()
    p_ref = sh%p
    pscale = max(maxval(abs(p_ref(1:nr,1:nth,1:nz))), 1.0_dp)
    call setup_bath(.true., -20.0_dp)
    call one_pv_iteration()
    res = maxval(abs(sh%p(1:nr,1:nth,1:nz) - p_ref(1:nr,1:nth,1:nz))) / pscale
    ! tolerancia 1e-3: la superficie del bano (continua) recibe por la
    ! cara compartida el flujo convectivo de la gota (momento del splash,
    ! fisico); la regla antigua da dp/p ~ 80 (caso 3b)
    if (res > 1.0e-3_dp) then
        print '(A,ES10.3,A,ES10.3)', '   FAIL caso 3a: la velocidad de la gota altero p: dp/p = ', res, &
            '  (p max ', pscale, ')'
        ok = .false.
    end if

    ! ---- caso 3b: con la regla antigua la gota dispara la presion ----
    call setup_bath(.true., -20.0_dp)
    ws_liq_cont_valid = .false.            ! regla antigua: alpha >= 0.01 entra
    call one_pv_iteration()
    ws_liq_cont_valid = .true.
    res = maxval(abs(sh%p(1:nr,1:nth,1:nz))) / pscale
    print '(A,ES10.3,A,ES10.3)', '   info caso 3b: p_max regla antigua / p_max fix = ', res, &
        '   p_max antigua = ', maxval(abs(sh%p(1:nr,1:nth,1:nz)))
    ! Con el Poisson de MASA la regla antigua daba dp/p ~ 80 (la gota a 20 m/s
    ! exigia gas de igual masa). Con el Poisson de VOLUMEN (Plan C F2) la
    ! misma gota ya no dispara la presion: el control negativo deja de ser
    ! discriminante y queda como informacion; lo que se exige es que la
    ! regla antigua no sea PEOR que el fix por mas de 10x (acotado).
    if (res > 10.0_dp) then
        print '(A)', '   FAIL caso 3b: con Poisson de volumen la regla antigua no deberia disparar p'
        ok = .false.
    end if

    ! ---- caso 4: acople gas-gota fisico: K = a_l*drho*g/u_t, implicito ----
    sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp
    liq%alpha = 0.0_dp; liq%alpha(ic,jc,kc) = 0.005_dp
    gas%alpha = 1.0_dp - liq%alpha
    gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
    sh%p = 0.0_dp; sh%pp = 0.0_dp; sh%S_arc_mom = 0.0_dp
    u_t = settling_velocity(cfg%d_droplet, liq%rho(ic,jc,kc), gas%rho(ic,jc,kc), gas%mu(ic,jc,kc))
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp; liq%uz(ic,jc,kc) = -u_t
    call copy_old()
    ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
    call compute_liquid_drift(liq, gas, sol, mesh, cfg, liq_old)
    Kz = 0.0_dp
    Kz(ic,jc,kc) = liq%alpha(ic,jc,kc) * (liq%rho(ic,jc,kc) - gas%rho(ic,jc,kc)) * GRAVITY / u_t
    call compute_ergun_drag(gas, sol, mesh, cfg, drag)
    call solve_momentum_3d(gas, gas_old, liq, Kz, sh, mesh, cfg, gas%alpha, drag, .true., r1, r2, r3)
    ! forma implicita: du = K (u_l - u_g^old) dt / (a_g rho_g + K dt), con
    ! u_l - u_g^old = -u_t => K u_t = peso de las gotas. Se compara contra
    ! una celda de gas puro (misma gravedad propia del gas).
    res = gas%uz(ic,jc,kc) - gas%uz(ic,jc,kc+2)
    pscale = -Kz(ic,jc,kc) * u_t * cfg%dt / (gas%alpha(ic,jc,kc) * gas%rho(ic,jc,kc) + Kz(ic,jc,kc) * cfg%dt)
    if (abs(res - pscale) > 1.0e-2_dp * abs(pscale)) then
        print '(A,2ES12.4)', '   FAIL caso 4: du del gas /= arrastre implicito de las gotas: ', res, pscale
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_dispersed_liquid'
    else
        print '(A)', ' FAIL test_dispersed_liquid'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine fail(msg)
        character(len=*), intent(in) :: msg
        print '(A,A)', '   FAIL caso 1: ', msg
        ok = .false.
    end subroutine fail

    subroutine copy_old()
        liq_old%ur = liq%ur; liq_old%uth = liq%uth; liq_old%uz = liq%uz
        liq_old%alpha = liq%alpha; liq_old%T = liq%T
        gas_old%ur = gas%ur; gas_old%uth = gas%uth; gas_old%uz = gas%uz
        gas_old%alpha = gas%alpha; gas_old%T = gas%T
    end subroutine copy_old

    subroutine setup_bath(with_drop, uz_drop)
        logical, intent(in)  :: with_drop
        real(dp), intent(in) :: uz_drop
        sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp
        liq%alpha = 0.0_dp
        liq%alpha(:, :, 1:2) = 0.7_dp
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
        ! gota justo SOBRE la superficie del bano (k=3): cara enlazada con
        ! liquido continuo, como las salpicaduras de B1 (una gota aislada
        ! no tiene caras en el Poisson ni con la regla antigua)
        if (with_drop) then
            liq%alpha(ic,jc,3) = 0.05_dp
            liq%uz(ic,jc,3) = uz_drop
        end if
        gas%alpha = 1.0_dp - liq%alpha
        sh%p = 0.0_dp; sh%pp = 0.0_dp
        call copy_old()
        ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
        call compute_liquid_drift(liq, gas, sol, mesh, cfg, liq_old)
    end subroutine setup_bath

    subroutine one_pv_iteration()
        call compute_ergun_drag(liq, sol, mesh, cfg, drag)
        call solve_momentum_3d(liq, liq_old, gas, Kz, sh, mesh, cfg, liq%alpha, drag, .false., r1, r2, r3)
        call solve_momentum_3d(gas, gas_old, liq, Kz, sh, mesh, cfg, gas%alpha, drag, .true., r1, r2, r3)
        call solve_pressure_correction(liq, gas, gas_old%T, sh, mesh, cfg, res)
    end subroutine one_pv_iteration

end program test_dispersed_liquid
