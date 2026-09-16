!===============================================================================
! test_residual_closure.f90 - Cierre del solido residual (sep-2026)
!
! Motivo: B1 reventaba en el paso 235829 por un solido de microgramos
! (m_s > SMALL=1e-30) cuya T_s = f(E_s/m_s) explotaba. compute_melting
! debe cerrar toda celda con 0 < m_s <= rho_s*V*ALPHA_SOLID_RESID
! entregando masa y entalpia al liquido por el camino mdot/T_src.
!
! Casos (malla pequena, singleton MPI):
!   1. remanente FRIO (600 K) bajo el umbral -> celda vacia, mdot*dt = m0,
!      T_src = liquid_entry_T(e): el liquido recibe EXACTAMENTE E0
!      (mdot*dt*(cp_l*T_src + C0) == E0 a 1e-12 relativo)
!   2. remanente CALIENTE (1900 K > T_liq) -> fusion + cierre en el mismo
!      paso; T_src == 1900 K (para e >= e_s(T_liq) ambas T coinciden)
!   3. celda con masa fisica (1000 m_min, 600 K) -> intacta
!   4. celda que RE-SOLIDIFICA (T_l < T_sol) con remanente bajo el umbral
!      -> NO se cierra en este paso (mdot < 0; el latente lo contabiliza
!      el solver de energia con el signo de mdot)
!   5. celda vacia con liquido -> T_s esclavizada a T_l
!===============================================================================
program test_residual_closure
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_melting_3d
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), parameter :: DT = 0.01_dp
    real(dp) :: m_min, m0, e0, e_liq_in, err, C0
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 6

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh)
    call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)

    ok = .true.
    C0 = liquid_datum_offset(cfg)

    ! Estado comun: sin solido, liquido a 1800 K en la fila j=4, k=3
    sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%alpha_s = 0.0_dp
    sol%m_C = 0.0_dp; sol%T_s = 300.0_dp
    liq%alpha(:,4,3) = 0.5_dp
    liq%T(:,4,3)     = 1800.0_dp

    ! Caso 1: remanente frio bajo el umbral
    call put_solid(2, 0.5_dp, 600.0_dp)
    ! Caso 2: remanente caliente bajo el umbral
    call put_solid(3, 0.5_dp, 1900.0_dp)
    ! Caso 3: masa fisica
    call put_solid(4, 1000.0_dp, 600.0_dp)
    ! Caso 4: re-solidificacion con remanente bajo el umbral
    call put_solid(5, 0.5_dp, 600.0_dp)
    liq%T(5,4,3) = 1000.0_dp

    call compute_melting(sol, liq, mesh, cfg, DT)

    ! --- caso 1 ---
    m_min = solid_residual_mass(mesh%vol(2,4,3), cfg)
    m0 = 0.5_dp * m_min
    e0 = m0 * solid_enthalpy(600.0_dp, cfg)
    if (sol%m_s(2,4,3) /= 0.0_dp .or. sol%E_s(2,4,3) /= 0.0_dp .or. &
        sol%alpha_s(2,4,3) /= 0.0_dp) then
        print '(A)', '   FAIL caso 1: la celda residual fria no quedo vacia'
        ok = .false.
    end if
    err = abs(sol%mdot(2,4,3) * DT - m0) / m0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 1: mdot*dt /= m0, err = ', err
        ok = .false.
    end if
    e_liq_in = sol%mdot(2,4,3) * DT * (cfg%cp_l * sol%T_s(2,4,3) + C0)
    err = abs(e_liq_in - e0) / e0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 1: energia entregada /= E0, err = ', err
        ok = .false.
    end if

    ! --- caso 2 ---
    m_min = solid_residual_mass(mesh%vol(3,4,3), cfg)
    m0 = 0.5_dp * m_min
    if (sol%m_s(3,4,3) /= 0.0_dp) then
        print '(A)', '   FAIL caso 2: la celda residual caliente no quedo vacia'
        ok = .false.
    end if
    err = abs(sol%mdot(3,4,3) * DT - m0) / m0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 2: mdot*dt /= m0 (fusion+cierre), err = ', err
        ok = .false.
    end if
    if (abs(sol%T_s(3,4,3) - 1900.0_dp) > 1.0e-9_dp) then
        print '(A,F12.4)', '   FAIL caso 2: T_src /= 1900 K: ', sol%T_s(3,4,3)
        ok = .false.
    end if

    ! --- caso 3 ---
    m_min = solid_residual_mass(mesh%vol(4,4,3), cfg)
    if (abs(sol%m_s(4,4,3) - 1000.0_dp * m_min) > 1.0e-12_dp * m_min .or. &
        sol%mdot(4,4,3) /= 0.0_dp) then
        print '(A)', '   FAIL caso 3: la celda con masa fisica fue tocada'
        ok = .false.
    end if
    if (abs(sol%T_s(4,4,3) - 600.0_dp) > 1.0e-9_dp) then
        print '(A,F12.4)', '   FAIL caso 3: T_s /= 600 K: ', sol%T_s(4,4,3)
        ok = .false.
    end if

    ! --- caso 4 ---
    if (.not. (sol%mdot(5,4,3) < 0.0_dp .and. sol%m_s(5,4,3) > 0.0_dp)) then
        print '(A)', '   FAIL caso 4: celda re-solidificando fue cerrada'
        ok = .false.
    end if

    ! --- caso 5 ---
    if (abs(sol%T_s(1,4,3) - 1800.0_dp) > 1.0e-9_dp) then
        print '(A,F12.4)', '   FAIL caso 5: T_s de celda vacia no esclavizada: ', &
            sol%T_s(1,4,3)
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_residual_closure'
    else
        print '(A)', ' FAIL test_residual_closure'
        stop 1
    end if

    call mpi_finalize_topology(mesh%topo)

contains

    subroutine put_solid(i, frac_of_min, T)
        integer, intent(in)  :: i
        real(dp), intent(in) :: frac_of_min, T
        real(dp) :: mm
        mm = frac_of_min * solid_residual_mass(mesh%vol(i,4,3), cfg)
        sol%m_s(i,4,3)     = mm
        sol%E_s(i,4,3)     = mm * solid_enthalpy(T, cfg)
        sol%alpha_s(i,4,3) = mm / (cfg%rho_steel * mesh%vol(i,4,3))
        sol%T_s(i,4,3)     = T
    end subroutine put_solid

end program test_residual_closure
