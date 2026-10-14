!===============================================================================
! test_gas_liquid_ht.f90 - Intercambio de calor gas-liquido de dos fluidos
! (auditoria 2, N-A1; no existia: el gas a 300 K sobre acero a 1850 K quedaba a
! 300 K). compute_gas_liquid_heat, implicito exacto de dos nodos.
!   1. Celda de SUPERFICIE (liquido continuo 0.5 bajo gas): dt = 1 s ->
!      conservacion exacta (C_g dT_g + C_l dT_l = 0), el gas se calienta y
!      ninguna fase cruza a la otra.
!   2. dt = 1e6 s -> ambas a la media ponderada por capacidad.
!   3. Gotas dispersas (alpha_l 0.02, sin chatarra): conservacion y cotas, y
!      el intercambio es mayor que en la superficie a igual dt (area 6 alpha/d).
!   4. Sin liquido o sin gas: nada cambia.
!   5. LECHO (alpha_s 0.5, alpha_l 0.05): pelicula sobre la chatarra; G a MANO
!      (Ranz-Marshall con d_p, area 6 alpha_s/d_p por la fraccion mojada) y la
!      solucion exacta de dos nodos reproducen la T del gas a 1e-12 (A3-2:
!      antes una pelicula uniforme no intercambiaba nada).
!   6. Celda de SUPERFICIE con poco liquido (alpha_l 0.05 sobre una celda de
!      bano, continua por la regla de superficie libre): interfase resuelta,
!      no gotas: su intercambio es < 10 % del de las mismas gotas aisladas
!      (A3-2: con liq_continuous elemental recibia el area de gota, 60-600x).
!===============================================================================
program test_gas_liquid_ht
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_interphase_ht, only: compute_gas_liquid_heat, PR_GAS_MOL
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    integer, parameter :: I0 = 3, J0 = 4, K0 = 5
    real(dp) :: Cg, Cl, Tg0, Tl0, Tm, dTg_fs, dTg_d, dTg_s
    real(dp) :: dpp, kmol, Re, h, a_i, G, f, q, Tg_hand
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 10
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    ok = .true.
    sol%alpha_s = 0.0_dp
    Tg0 = 300.0_dp; Tl0 = 1850.0_dp

    ! --- caso 1: superficie libre, dt = 1 s ---
    call setup_fs(); cfg%dt = 1.0_dp
    call caps()
    call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg)
    call checks('caso 1')
    dTg_fs = gas%T(I0,J0,K0) - Tg0
    if (.not. dTg_fs > 0.0_dp) call fail('caso 1: el gas no se calento', dTg_fs)

    ! --- caso 2: dt enorme -> equilibrio ---
    call setup_fs(); cfg%dt = 1.0e6_dp
    call caps()
    call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg)
    Tm = (Cg * Tg0 + Cl * Tl0) / (Cg + Cl)
    if (abs(gas%T(I0,J0,K0) - Tm) > 1.0e-6_dp .or. abs(liq%T(I0,J0,K0) - Tm) > 1.0e-6_dp) &
        call fail('caso 2: no llega al equilibrio', gas%T(I0,J0,K0) - Tm)

    ! --- caso 3: gotas dispersas ---
    liq%alpha = 0.0_dp; liq%alpha(I0,J0,K0) = 0.02_dp
    gas%alpha = 1.0_dp - liq%alpha
    gas%T = Tg0; liq%T = Tl0; cfg%dt = 1.0_dp
    call caps()
    call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg)
    call checks('caso 3')
    dTg_d = gas%T(I0,J0,K0) - Tg0
    if (.not. dTg_d * Cg > dTg_fs * 1.0e-3_dp) call fail('caso 3: sin intercambio por gotas', dTg_d)

    ! --- caso 4: sin una de las fases ---
    liq%alpha = 0.0_dp; gas%alpha = 1.0_dp; gas%T = Tg0; liq%T = Tl0
    call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg)
    if (maxval(abs(gas%T(1:6,1:8,1:10) - Tg0)) > 0.0_dp) call fail('caso 4: cambio sin liquido', 1.0_dp)

    ! --- caso 5: lecho, pelicula sobre la chatarra; G a mano ---
    call ensure_workspace(mesh)
    liq%alpha = 0.0_dp; liq%alpha(I0,J0,K0) = 0.05_dp
    sol%alpha_s = 0.0_dp; sol%alpha_s(I0,J0,K0) = 0.5_dp
    gas%alpha = 1.0_dp - liq%alpha - sol%alpha_s
    gas%T = Tg0; liq%T = Tl0; cfg%dt = 1.0_dp
    ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
    call caps()
    dpp  = max(cfg%d_particle, 1.0e-3_dp)
    kmol = gas%mu(I0,J0,K0) * gas%cp(I0,J0,K0) / PR_GAS_MOL
    Re   = gas%rho(I0,J0,K0) * 1.0_dp * dpp / (gas%mu(I0,J0,K0) + SMALL)
    h    = kmol / dpp * (2.0_dp + 0.6_dp * sqrt(Re) * PR_GAS_MOL**(1.0_dp/3.0_dp))
    a_i  = 6.0_dp * 0.5_dp / dpp * min(1.0_dp, 0.05_dp / 0.5_dp)
    G    = h * a_i * mesh%vol(I0,J0,K0)
    f    = 1.0_dp - exp(-cfg%dt * G * (1.0_dp / Cg + 1.0_dp / Cl))
    q    = Cg * Cl / (Cg + Cl) * (Tg0 - Tl0) * f
    Tg_hand = Tg0 - q / Cg
    call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg)
    call checks('caso 5')
    if (abs(gas%T(I0,J0,K0) - Tg_hand) > 1.0e-12_dp * (Tl0 - Tg0)) &
        call fail('caso 5: T del gas /= G a mano (pelicula del lecho)', gas%T(I0,J0,K0) - Tg_hand)
    if (.not. (gas%T(I0,J0,K0) - Tg0 > 1.0_dp)) call fail('caso 5: la pelicula del lecho no intercambia', gas%T(I0,J0,K0) - Tg0)

    ! --- caso 6: superficie con poco liquido frente a las mismas gotas ---
    sol%alpha_s = 0.0_dp
    liq%alpha = 0.0_dp; liq%alpha(:,:,1:K0-1) = 1.0_dp; liq%alpha(I0,J0,K0) = 0.05_dp
    gas%alpha = 1.0_dp - liq%alpha
    gas%T = Tg0; liq%T = Tl0; cfg%dt = 1.0_dp
    ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s)
    ws_liq_cont(I0,J0,K0) = .true.    ! regla de superficie libre: sobre el bano
    call caps()
    call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg)
    call checks('caso 6')
    dTg_s = gas%T(I0,J0,K0) - Tg0
    liq%alpha = 0.0_dp; liq%alpha(I0,J0,K0) = 0.05_dp
    gas%alpha = 1.0_dp - liq%alpha
    gas%T = Tg0; liq%T = Tl0
    ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s)
    call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg)
    dTg_d = gas%T(I0,J0,K0) - Tg0
    if (.not. (dTg_s > 0.0_dp .and. dTg_s < 0.1_dp * dTg_d)) &
        call fail('caso 6: la celda de superficie intercambia como gotas (dT_s/dT_gotas)', dTg_s / max(dTg_d, SMALL))

    if (ok) then
        print '(A)', ' PASS test_gas_liquid_ht'
    else
        print '(A)', ' FAIL test_gas_liquid_ht'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine setup_fs()
        ! columna: liquido puro abajo, superficie en K0 (0.5), gas arriba
        liq%alpha = 0.0_dp
        liq%alpha(:,:,1:K0-1) = 1.0_dp
        liq%alpha(:,:,K0) = 0.5_dp
        gas%alpha = 1.0_dp - liq%alpha
        gas%T = Tg0; liq%T = Tl0
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 1.0_dp
        gas%rho = gas_eos(cfg%rho_gas, gas%T, 0.0_dp)
    end subroutine setup_fs

    subroutine caps()
        Cg = gas%alpha(I0,J0,K0) * gas%rho(I0,J0,K0) * gas%cp(I0,J0,K0) * mesh%vol(I0,J0,K0)
        Cl = liq%alpha(I0,J0,K0) * liq%rho(I0,J0,K0) * liq%cp(I0,J0,K0) * mesh%vol(I0,J0,K0)
    end subroutine caps

    subroutine checks(tag)
        character(len=*), intent(in) :: tag
        real(dp) :: dE
        dE = Cg * (gas%T(I0,J0,K0) - Tg0) + Cl * (liq%T(I0,J0,K0) - Tl0)
        if (abs(dE) > 1.0e-10_dp * Cg * (Tl0 - Tg0)) call fail(tag // ': conservacion', dE)
        if (gas%T(I0,J0,K0) > liq%T(I0,J0,K0) + 1.0e-9_dp) &
            call fail(tag // ': el gas cruzo al liquido', gas%T(I0,J0,K0) - liq%T(I0,J0,K0))
        if (gas%T(I0,J0,K0) < Tg0 - 1.0e-9_dp .or. liq%T(I0,J0,K0) > Tl0 + 1.0e-9_dp) &
            call fail(tag // ': fuera de cota', gas%T(I0,J0,K0))
    end subroutine checks

    subroutine fail(msg, v)
        character(len=*), intent(in) :: msg
        real(dp), intent(in) :: v
        print '(3A,ES12.4)', '   FAIL ', msg, ': ', v
        ok = .false.
    end subroutine fail
end program test_gas_liquid_ht
