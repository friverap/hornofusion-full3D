!===============================================================================
! test_alpha_limiter.f90 - Limitador de hueco del transporte de alpha (sep-2026)
!
! Motivo: B1 v8 perdía 4.4 t de acero en 427 s por el clip de acotamiento:
! el líquido drenaba a celdas del lecho ya llenas (alpha_s+alpha_l=1) y el
! exceso se recortaba. El limitador escala la ENTRADA de cada celda a su
! hueco libre (+ lo que sale), con el mismo flujo efectivo en las dos celdas
! de la cara: conservativo por construcción.
!
! Casos (singleton MPI, sin mdot):
!   1. Fondo sólido (alpha_s=1), celda llena encima (alpha_s=0.6,
!      alpha_l=0.4) y líquido arriba (alpha_l=0.5) con velocidad hacia
!      abajo: la llena no puede drenar ni recibir, la de arriba conserva
!      su líquido, masa total EXACTA (sin clip), flujo efectivo nulo.
!   2. Columna uniforme alpha_l=0.5 con flujo vertical: el limitador no
!      actúa (entrada = salida), la masa se conserva a 1e-12 y el flujo
!      efectivo acumulado por cara es el donor-cell crudo.
!   3. Columna casi llena (alpha_l=0.99 en k=2..nz) sobre fondo sólido con
!      flujo hacia abajo fuerte: el "no cabe" debe propagarse por toda la
!      columna (convergencia del limitador, no 3 barridos fijos): masa
!      exacta y ningún sobrellenado.
!===============================================================================
program test_alpha_limiter
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_continuity, only: solve_volume_fraction
    use mod_workspace, only: ws_Fz, ws_flux_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: a_old(:,:,:)
    real(dp) :: m0, m1, err, over, F_expected
    integer  :: nr, nth, nz
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
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    allocate(a_old, mold=liq%alpha)
    ok = .true.

    ! ---- caso 1: celda llena debajo ----
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = -0.5_dp
    sol%mdot = 0.0_dp; sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp
    liq%alpha = 0.0_dp
    sol%alpha_s(3,4,1) = 1.0_dp
    sol%alpha_s(3,4,2) = 0.6_dp; liq%alpha(3,4,2) = 0.4_dp
    liq%alpha(3,4,3) = 0.5_dp
    a_old = liq%alpha
    m0 = liquid_mass()
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    m1 = liquid_mass()
    err = abs(m1 - m0) / m0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 1: masa liquida no conservada, err = ', err
        ok = .false.
    end if
    over = maxval(liq%alpha(1:nr,1:nth,1:nz) + sol%alpha_s(1:nr,1:nth,1:nz)) - 1.0_dp
    if (over > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 1: sobrellenado alpha_s+alpha_l-1 = ', over
        ok = .false.
    end if
    if (abs(liq%alpha(3,4,3) - 0.5_dp) > 1.0e-12_dp .or. &
        abs(liq%alpha(3,4,2) - 0.4_dp) > 1.0e-12_dp) then
        print '(A,2F10.6)', '   FAIL caso 1: el liquido no se quedo encima: ', &
            liq%alpha(3,4,3), liq%alpha(3,4,2)
        ok = .false.
    end if
    if (.not. ws_flux_valid) then
        print '(A)', '   FAIL caso 1: ws_flux_valid no quedo activo'
        ok = .false.
    end if
    if (abs(ws_Fz(3,4,2)) > 1.0e-14_dp) then
        print '(A,ES10.3)', '   FAIL caso 1: flujo efectivo hacia la celda llena /= 0: ', &
            ws_Fz(3,4,2)
        ok = .false.
    end if

    ! ---- caso 2: columna uniforme, el limitador no actúa ----
    sol%alpha_s = 0.0_dp
    liq%alpha = 0.0_dp
    liq%alpha(3,4,1:nz) = 0.5_dp
    a_old = liq%alpha
    m0 = liquid_mass()
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    m1 = liquid_mass()
    err = abs(m1 - m0) / m0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 2: masa no conservada, err = ', err
        ok = .false.
    end if
    ! cara tope de (3,4,3): flujo donor-cell crudo = rho*uz*A*alpha_upwind
    ! (uz<0 => upwind es la celda de arriba, alpha=0.5); el limitador de
    ! la receptora (3,4,3) debe ser 1 (entrada = salida)
    F_expected = 0.5_dp * liq%rho(3,4,3) * (-0.5_dp) * mesh%Az(3,4,3)
    err = abs(ws_Fz(3,4,3) - F_expected) / abs(F_expected)
    if (err > 1.0e-9_dp) then
        print '(A,2ES12.4)', '   FAIL caso 2: flujo efectivo /= donor crudo: ', &
            ws_Fz(3,4,3), F_expected
        ok = .false.
    end if

    ! ---- caso 3: columna casi llena, el limitador debe converger ----
    sol%alpha_s = 0.0_dp; liq%alpha = 0.0_dp
    sol%alpha_s(3,4,1) = 1.0_dp
    liq%alpha(3,4,2:nz) = 0.99_dp
    liq%uz = -2.0_dp
    a_old = liq%alpha
    m0 = liquid_mass()
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    m1 = liquid_mass()
    err = abs(m1 - m0) / m0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 3: columna llena perdio masa (clip), err = ', err
        ok = .false.
    end if
    over = maxval(liq%alpha(1:nr,1:nth,1:nz) + sol%alpha_s(1:nr,1:nth,1:nz)) - 1.0_dp
    if (over > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 3: sobrellenado = ', over
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_alpha_limiter'
    else
        print '(A)', ' FAIL test_alpha_limiter'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    function liquid_mass() result(mt)
        real(dp) :: mt
        mt = sum(liq%alpha(1:nr,1:nth,1:nz) * liq%rho(1:nr,1:nth,1:nz) * &
                 mesh%vol(1:nr,1:nth,1:nz))
    end function liquid_mass

end program test_alpha_limiter
