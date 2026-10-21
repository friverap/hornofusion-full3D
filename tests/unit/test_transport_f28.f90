!===============================================================================
! test_transport_f28.f90 - Plan J-B (oct-2026): el transporte de alpha respeta
! el cierre F2.8 del Poisson en las caras continuo|continuo
!
! Motivo: en una celda de poro saturada el Poisson cerraba sus caras de liquido
! (F2.8) pero el transporte la rellenaba por ellas con la reconstruccion de
! centro: la fila de presion pedia el volumen que el transporte no respetaba
! y el defecto se volvia un pozo de presion (B1 281 s, -82 kPa).
!
! Casos (singleton MPI, sin mdot; dos celdas continuas apiladas, flujo hacia
! abajo; ws_Fc_valid con todas las caras SIN enlace):
!   1. pc_transport_f28 = true: la cara continuo|continuo sin enlace no
!      transporta (alpha intacta, flujo efectivo 0, masa exacta).
!   2. pc_transport_f28 = false: la misma cara transporta (resto: velocidad
!      de centro) -> el comportamiento anterior.
!   3. Cara LATERAL continuo|disperso sin enlace: B no la toca (el goteo
!      disperso sigue con su donor-cell; lateral porque la regla de pelicula
!      solo es vertical).
!   4. Cara continuo|continuo ENLAZADA (lk = 1): B no la toca.
!   5. ws_Fc_valid = .false.: B inerte.
!===============================================================================
program test_transport_f28
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_continuity, only: solve_volume_fraction
    use mod_workspace, only: ensure_workspace, ws_Fr, ws_Fz, ws_Fc_z, ws_Fc_af_z, ws_Fc_valid, ws_Fc_lk_r, &
                             ws_Fc_lk_th, ws_Fc_lk_z, ws_liq_cont_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: a_old(:,:,:)
    real(dp) :: m0, m1, F_off
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 6
    cfg%dt = 0.05_dp

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh)
    call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    call ensure_workspace(mesh)
    allocate(a_old, mold=liq%alpha)
    ok = .true.

    ! ---- caso 1: B encendido, cara continuo|continuo sin enlace ----
    call setup(0.8_dp)
    cfg%pc_transport_f28 = .true.
    m0 = liquid_mass()
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    m1 = liquid_mass()
    if (abs(m1 - m0) > 1.0e-12_dp * m0) call fail('caso 1: masa no conservada')
    if (abs(liq%alpha(3,4,3) - 0.8_dp) > 1.0e-14_dp .or. &
        abs(liq%alpha(3,4,2) - 0.8_dp) > 1.0e-14_dp) &
        call fail('caso 1: la cara sin enlace transporto liquido')
    if (abs(ws_Fz(3,4,2)) > 0.0_dp) call fail('caso 1: flujo efectivo /= 0')

    ! ---- caso 2: B apagado, la misma cara transporta ----
    call setup(0.8_dp)
    cfg%pc_transport_f28 = .false.
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    if (ws_Fz(3,4,2) >= 0.0_dp) call fail('caso 2: sin B la cara no transporto hacia abajo')

    ! ---- caso 3: vecina lateral dispersa, B no cambia esa cara ----
    call setup(0.8_dp)
    liq%alpha(4,4,2) = 0.1_dp; a_old = liq%alpha
    liq%uz = 0.0_dp; liq%ur = -0.5_dp; gas%ur = -0.5_dp
    cfg%pc_transport_f28 = .false.
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    F_off = ws_Fr(3,4,2)
    call setup(0.8_dp)
    liq%alpha(4,4,2) = 0.1_dp; a_old = liq%alpha
    liq%uz = 0.0_dp; liq%ur = -0.5_dp; gas%ur = -0.5_dp
    cfg%pc_transport_f28 = .true.
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    if (F_off == 0.0_dp) call fail('caso 3: la cara continuo|disperso no transporta (caso mal puesto)')
    if (ws_Fr(3,4,2) /= F_off) call fail('caso 3: B cambio el goteo continuo|disperso')

    ! ---- caso 4: cara continuo|continuo enlazada ----
    call setup(0.8_dp)
    ws_Fc_lk_z(3,4,2) = 1
    ws_Fc_z = 0.0_dp; ws_Fc_af_z = 0.0_dp
    ws_Fc_z(3,4,2) = -1.0e-3_dp; ws_Fc_af_z(3,4,2) = 0.8_dp
    cfg%pc_transport_f28 = .true.
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    if (ws_Fz(3,4,2) >= 0.0_dp) call fail('caso 4: B corto una cara enlazada')

    ! ---- caso 5: sin flujos del Poisson, B inerte ----
    call setup(0.8_dp)
    ws_Fc_valid = .false.
    cfg%pc_transport_f28 = .true.
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    if (ws_Fz(3,4,2) >= 0.0_dp) call fail('caso 5: B actuo sin flujos del Poisson')

    call mpi_finalize_topology(mesh%topo)
    if (ok) then
        print '(A)', 'test_transport_f28: OK'
    else
        print '(A)', 'test_transport_f28: FAIL'
        stop 1
    end if

contains

    ! columna (3,4,1:2) llena de liquido y (3,4,3) con a_top, todo hacia abajo,
    ! Poisson "valido" sin ninguna cara enlazada
    subroutine setup(a_top)
        real(dp), intent(in) :: a_top
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = -0.5_dp; gas%ur = 0.0_dp
        sol%mdot = 0.0_dp; sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp
        liq%alpha = 0.0_dp
        liq%alpha(3,4,1) = 0.8_dp; liq%alpha(3,4,2) = 0.8_dp
        liq%alpha(3,4,3) = a_top
        a_old = liq%alpha
        ws_liq_cont_valid = .false.
        ws_Fc_valid = .true.
        ws_Fc_lk_r = 0; ws_Fc_lk_th = 0; ws_Fc_lk_z = 0
    end subroutine setup

    real(dp) function liquid_mass()
        liquid_mass = sum(liq%alpha(1:mesh%nr,1:mesh%ntheta,1:mesh%nz) * &
                          liq%rho(1:mesh%nr,1:mesh%ntheta,1:mesh%nz) * &
                          mesh%vol(1:mesh%nr,1:mesh%ntheta,1:mesh%nz))
    end function liquid_mass

    subroutine fail(msg)
        character(*), intent(in) :: msg
        print '(A,A)', '   FAIL ', msg
        ok = .false.
    end subroutine fail

end program test_transport_f28
