!===============================================================================
! test_interphase.f90 - Intercambio solido-fluido (auditoria 12-oct-2026, M6/M7)
!
! Antes cada flujo se recortaba por separado a min(Q, C_f dT/dt, C_s dT/dt)
! (rebasa el equilibrio) y gas y liquido usaban el area 6 alpha_s/d completa.
! Casos (singleton MPI, celdas con solido + liquido + gas):
!   1. dt = 1 s con poca masa de solido: T_s final dentro de [T_s, max fluido],
!      cada fluido queda del lado del solido sin cruzarlo, conservacion exacta.
!   2. dt = 1e6 s: los tres nodos tienden a la media ponderada por capacidad.
!   3. Area: con alpha_l = 0 el gas recibe el area completa; con gas y liquido
!      a partes iguales y T_l = T_g el flujo total no depende del reparto
!      (la suma de areas es 6 alpha_s/d, no el doble).
!===============================================================================
program test_interphase
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_melting_3d, only: solid_enthalpy
    use mod_interphase_ht, only: compute_interphase_heat
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    integer, parameter :: I0 = 3, J0 = 4, K0 = 5
    real(dp) :: V, Cg, Cl, E0, E1, Ts, Tl, Tg, Tmix, Q1, Q2
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
    V = mesh%vol(I0,J0,K0)

    ! --- caso 1: dt grande, poca masa de solido -------------------------------
    call setup(0.05_dp, 0.45_dp, 0.50_dp, 300.0_dp, 1700.0_dp, 2500.0_dp, 1.0_dp)
    E0 = energy()
    call compute_interphase_heat(liq, gas, sol, mesh, cfg)
    E1 = energy()
    Ts = sol%T_s(I0,J0,K0); Tl = liq%T(I0,J0,K0); Tg = gas%T(I0,J0,K0)
    if (Ts < 300.0_dp - 1.0e-9_dp .or. Ts > 2500.0_dp + 1.0e-9_dp) call fail('caso 1: T_s fuera de cota', Ts)
    if (Tg < Ts - 1.0e-9_dp) call fail('caso 1: el gas cruzo al solido', Tg - Ts)
    if (Tl < Ts - 1.0e-9_dp) call fail('caso 1: el liquido cruzo al solido', Tl - Ts)
    if (abs(E1 - E0) > 1.0e-10_dp * abs(E0)) call fail('caso 1: conservacion', (E1 - E0) / E0)

    ! --- caso 2: dt enorme -> equilibrio de los tres nodos ---------------------
    call setup(0.30_dp, 0.30_dp, 0.40_dp, 300.0_dp, 900.0_dp, 1200.0_dp, 1.0e6_dp)
    Cg = gas%alpha(I0,J0,K0) * gas%rho(I0,J0,K0) * gas%cp(I0,J0,K0) * V
    Cl = liq%alpha(I0,J0,K0) * liq%rho(I0,J0,K0) * liq%cp(I0,J0,K0) * V
    Tmix = (sol%m_s(I0,J0,K0) * cfg%cp_s * 300.0_dp + Cl * 900.0_dp + Cg * 1200.0_dp) / &
           (sol%m_s(I0,J0,K0) * cfg%cp_s + Cl + Cg)
    call compute_interphase_heat(liq, gas, sol, mesh, cfg)
    print '(A,4F12.4)', '   caso 2: T_mix, T_s, T_l, T_g = ', Tmix, sol%T_s(I0,J0,K0), liq%T(I0,J0,K0), gas%T(I0,J0,K0)
    if (abs(sol%T_s(I0,J0,K0) - Tmix) > 0.1_dp .or. abs(liq%T(I0,J0,K0) - Tmix) > 0.1_dp &
        .or. abs(gas%T(I0,J0,K0) - Tmix) > 0.1_dp) &
        call fail('caso 2: sin equilibrio, T_s - T_mix =', sol%T_s(I0,J0,K0) - Tmix)

    ! --- caso 3: area repartida ------------------------------------------------
    ! mismo fluido caliente (T_l = T_g, mismas propiedades): el calor al solido
    ! con 50/50 de poro debe ser el del promedio de los dos casos puros, nunca
    ! la suma (area doble)
    call setup(0.30_dp, 0.0_dp, 0.70_dp, 300.0_dp, 1000.0_dp, 1000.0_dp, 1.0e-6_dp)
    call clone_gas_props()
    call compute_interphase_heat(liq, gas, sol, mesh, cfg)
    Q1 = sol%E_s(I0,J0,K0)
    call setup(0.30_dp, 0.35_dp, 0.35_dp, 300.0_dp, 1000.0_dp, 1000.0_dp, 1.0e-6_dp)
    call clone_gas_props()
    E0 = sol%E_s(I0,J0,K0)
    call compute_interphase_heat(liq, gas, sol, mesh, cfg)
    Q2 = sol%E_s(I0,J0,K0) - E0
    Q1 = Q1 - E0
    if (abs(Q2 - Q1) > 1.0e-6_dp * abs(Q1)) call fail('caso 3: area doble, Q(50/50)/Q(gas) =', Q2 / Q1)

    if (ok) then
        print '(A)', ' PASS test_interphase (sin rebase del equilibrio, conservativo, area repartida)'
    else
        stop 1
    end if

contains

    subroutine setup(as, al, ag, Ts0, Tl0, Tg0, dt)
        real(dp), intent(in) :: as, al, ag, Ts0, Tl0, Tg0, dt
        cfg%dt = dt
        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp
        liq%alpha = 0.0_dp; gas%alpha = 1.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
        liq%rho = 7000.0_dp; liq%cp = 800.0_dp; liq%kth = 30.0_dp
        gas%rho = 0.2_dp; gas%cp = 1200.0_dp; gas%kth = 0.1_dp; gas%mu = 5.0e-5_dp
        sol%alpha_s(I0,J0,K0) = as
        sol%m_s(I0,J0,K0) = as * cfg%rho_steel * V
        sol%T_s(I0,J0,K0) = Ts0
        sol%E_s(I0,J0,K0) = sol%m_s(I0,J0,K0) * solid_enthalpy(Ts0, cfg)
        liq%alpha(I0,J0,K0) = al; gas%alpha(I0,J0,K0) = ag
        liq%T(I0,J0,K0) = Tl0; gas%T(I0,J0,K0) = Tg0
    end subroutine setup

    subroutine clone_gas_props()
        liq%rho = gas%rho; liq%cp = gas%cp; liq%kth = 2.0_dp * gas%kth / 6.0_dp
    end subroutine clone_gas_props

    function energy() result(e)
        real(dp) :: e
        e = sol%E_s(I0,J0,K0) &
          + liq%alpha(I0,J0,K0) * liq%rho(I0,J0,K0) * liq%cp(I0,J0,K0) * V * liq%T(I0,J0,K0) &
          + gas%alpha(I0,J0,K0) * gas%rho(I0,J0,K0) * gas%cp(I0,J0,K0) * V * gas%T(I0,J0,K0)
    end function energy

    subroutine fail(msg, v)
        character(len=*), intent(in) :: msg
        real(dp), intent(in) :: v
        print '(A,A,ES12.4)', '   FAIL ', msg, v
        ok = .false.
    end subroutine fail
end program test_interphase
