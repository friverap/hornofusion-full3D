!===============================================================================
! test_pore_floor.f90 - Piso de gas de poro en RAMPA por debajo de ALPHA_BED
! (6314031; auditoria 20, A20-2/B20-C1: la rampa no tenia test)
!
! Motivo: con el interruptor en ALPHA_BED una celda que fundia de 0.0101 a
! 0.0099 liberaba el 1.5 % de hueco en un paso (rafagas de B1 a 241 s); la
! rampa POR ENCIMA de ALPHA_BED (4547861) sellaba el lecho (2 MPa).
!
! Casos:
!   1. pore_floor: 0 hasta ALPHA_BED/2, lineal hasta ALPHA_PORE_GAS en
!      ALPHA_BED, constante encima (nunca por encima de ALPHA_BED la rampa).
!   2. liq_cap = 1 - as - asl - pore_floor(as), acotado a >= 0.
!   3. Derrame en la banda: una celda con alpha_s = 0.75 ALPHA_BED llena hasta
!      1 - alpha_s queda en su liq_cap (el exceso sube a la de arriba) y la
!      masa se conserva.
!===============================================================================
program test_pore_floor
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_continuity, only: solve_volume_fraction
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: a_old(:,:,:)
    real(dp) :: as, m0, m1
    logical  :: ok

    ok = .true.

    ! ---- caso 1: forma de la rampa ----
    if (pore_floor(0.4_dp * ALPHA_BED) /= 0.0_dp) call fail('caso 1: piso /= 0 bajo ALPHA_BED/2')
    if (pore_floor(0.5_dp * ALPHA_BED) /= 0.0_dp) call fail('caso 1: piso /= 0 en ALPHA_BED/2')
    if (abs(pore_floor(0.75_dp * ALPHA_BED) - 0.5_dp * ALPHA_PORE_GAS) > 1.0e-15_dp) &
        call fail('caso 1: piso /= ALPHA_PORE_GAS/2 a mitad de la rampa')
    if (abs(pore_floor(ALPHA_BED) - ALPHA_PORE_GAS) > 1.0e-15_dp) &
        call fail('caso 1: piso /= ALPHA_PORE_GAS en ALPHA_BED')
    if (pore_floor(1.5_dp * ALPHA_BED) /= ALPHA_PORE_GAS .or. pore_floor(0.6_dp) /= ALPHA_PORE_GAS) &
        call fail('caso 1: piso /= ALPHA_PORE_GAS en el lecho')

    ! ---- caso 2: liq_cap ----
    as = 0.75_dp * ALPHA_BED
    if (abs(liq_cap(as, 0.0_dp) - (1.0_dp - as - 0.5_dp * ALPHA_PORE_GAS)) > 1.0e-15_dp) &
        call fail('caso 2: liq_cap en la banda no resta el piso de la rampa')
    if (liq_cap(0.995_dp, 0.0_dp) /= 0.0_dp) call fail('caso 2: liq_cap negativo')

    ! ---- caso 3: derrame en la banda ----
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
    allocate(a_old, mold=liq%alpha)
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
    sol%mdot = 0.0_dp; sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp
    liq%alpha = 0.0_dp
    sol%alpha_s(3,4,1) = 1.0_dp
    sol%alpha_s(3,4,2) = as; liq%alpha(3,4,2) = 1.0_dp - as
    a_old = liq%alpha
    m0 = liquid_mass()
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    m1 = liquid_mass()
    if (abs(m1 - m0) > 1.0e-12_dp * m0) call fail('caso 3: masa no conservada')
    if (liq%alpha(3,4,2) > liq_cap(as, 0.0_dp) + 1.0e-12_dp) &
        call fail('caso 3: la celda de la banda quedo sobre su liq_cap')
    if (liq%alpha(3,4,3) <= 0.0_dp) call fail('caso 3: el exceso no subio a la celda de arriba')
    call mpi_finalize_topology(mesh%topo)

    if (ok) then
        print '(A)', 'test_pore_floor: OK'
    else
        print '(A)', 'test_pore_floor: FAIL'
        stop 1
    end if

contains

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

end program test_pore_floor
