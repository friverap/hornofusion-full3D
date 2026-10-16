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
!   4. Derrame: alpha_old sobrellena una celda (a_l=1 con a_s=0.2) con
!      hueco encima y velocidad nula -> el exceso 0.2 sube a la celda de
!      arriba (con la razón de volúmenes), masa exacta, sin clip, y
!      ws_Fz de la cara superior lleva la masa derramada (energía).
!   5-9. Celda LLENA sobre la sobrellena (auditorias 8-9): de liquido, el
!      exceso la atraviesa (5; encadenado por dos celdas, 9); de escoria,
!      de costra solida o la interfaz acero|escoria, nunca (6-8, M9-4).
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
    ! celda de lecho llena hasta su hueco de poro (F2.7: 1 - a_s - ALPHA_PORE_GAS)
    sol%alpha_s(3,4,2) = 0.6_dp; liq%alpha(3,4,2) = liq_cap(0.6_dp, 0.0_dp)
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
        abs(liq%alpha(3,4,2) - liq_cap(0.6_dp, 0.0_dp)) > 1.0e-12_dp) then
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

    ! ---- caso 4: derrame conservativo del exceso ----
    sol%alpha_s = 0.0_dp; liq%alpha = 0.0_dp; liq%uz = 0.0_dp
    sol%alpha_s(3,4,2) = 0.2_dp
    liq%alpha(3,4,2) = 1.0_dp          ! sobrellena: a_s + a_l = 1.2
    liq%alpha(3,4,3) = 0.1_dp
    a_old = liq%alpha
    m0 = liquid_mass()
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    m1 = liquid_mass()
    err = abs(m1 - m0) / m0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 4: el derrame no conservo la masa, err = ', err
        ok = .false.
    end if
    ! el exceso sobre el hueco de poro (F2.7) se derrama: 1 - liq_cap(0.2,0)
    if (abs(liq%alpha(3,4,2) - liq_cap(0.2_dp, 0.0_dp)) > 1.0e-12_dp) then
        print '(A,2F10.6)', '   FAIL caso 4: la celda sobrellena no quedo en su hueco de poro: ', &
            liq%alpha(3,4,2), liq_cap(0.2_dp, 0.0_dp)
        ok = .false.
    end if
    F_expected = 0.1_dp + (1.0_dp - liq_cap(0.2_dp, 0.0_dp)) * mesh%vol(3,4,2) / mesh%vol(3,4,3)
    if (abs(liq%alpha(3,4,3) - F_expected) > 1.0e-12_dp) then
        print '(A,2F10.6)', '   FAIL caso 4: la celda de arriba no recibio el exceso: ', &
            liq%alpha(3,4,3), F_expected
        ok = .false.
    end if
    F_expected = (1.0_dp - liq_cap(0.2_dp, 0.0_dp)) * liq%rho(3,4,2) * mesh%vol(3,4,2) / cfg%dt
    if (abs(ws_Fz(3,4,2) - F_expected) > 1.0e-9_dp * F_expected) then
        print '(A,2ES12.4)', '   FAIL caso 4: ws_Fz no lleva el derrame: ', ws_Fz(3,4,2), F_expected
        ok = .false.
    end if

    ! ---- casos 5-7 (auditorias 8-9): el derrame y una celda LLENA encima ----
    ! k=2 sobrellena (a_s 0.2, a_l 1.0) y k=3 llena por completo; k=4 vacia.
    ! 5: k=3 llena de LIQUIDO -> el exceso la atraviesa (relevo) y llega a k=4
    ! 6: k=3 llena de ESCORIA -> el acero NUNCA cruza la escoria (M9-4): k=3 y
    !    k=4 sin liquido; el exceso va al clip auditado, como antes
    ! 7: k=3 COSTRA solida (a_s = 1) -> tampoco la atraviesa
    call spill_case(5, 0.0_dp, 1.0_dp, 0.0_dp)
    call spill_case(6, 0.0_dp, 0.0_dp, 1.0_dp)
    call spill_case(7, 1.0_dp, 0.0_dp, 0.0_dp)
    ! 8: k=3 INTERFAZ llena mitad acero mitad escoria (la celda real de M9-4):
    !    la clausula de escoria la bloquea aunque tenga liquido
    call spill_case(8, 0.0_dp, 0.5_dp, 0.5_dp)
    ! 9: relevo ENCADENADO: k=3 y k=4 llenas de liquido, el exceso llega a k=5
    call spill_case(9, 0.0_dp, 1.0_dp, 0.0_dp)

    if (ok) then
        print '(A)', ' PASS test_alpha_limiter'
    else
        print '(A)', ' FAIL test_alpha_limiter'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine spill_case(icase, as3, al3, asl3)
        integer, intent(in)  :: icase
        real(dp), intent(in) :: as3, al3, asl3
        real(dp) :: exc, a4_exp
        sol%alpha_s = 0.0_dp; liq%alpha = 0.0_dp; liq%uz = 0.0_dp
        liq%ur = 0.0_dp; liq%uth = 0.0_dp
        slag%alpha_sl = 0.0_dp
        sol%alpha_s(3,4,2) = 0.2_dp
        liq%alpha(3,4,2) = 1.0_dp
        sol%alpha_s(3,4,3) = as3; liq%alpha(3,4,3) = al3; slag%alpha_sl(3,4,3) = asl3
        if (icase == 9) liq%alpha(3,4,4) = 1.0_dp
        a_old = liq%alpha
        m0 = liquid_mass()
        call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
        m1 = liquid_mass()
        exc = (1.0_dp - liq_cap(0.2_dp, 0.0_dp)) * mesh%vol(3,4,2)
        if (icase == 9) then
            a4_exp = exc / mesh%vol(3,4,5)
            if (abs(m1 - m0) > 1.0e-12_dp * m0) then
                print '(A,ES10.3)', '   FAIL caso 9: el relevo encadenado no conservo la masa, err = ', (m1 - m0) / m0
                ok = .false.
            end if
            if (abs(liq%alpha(3,4,3) - 1.0_dp) > 1.0e-12_dp .or. abs(liq%alpha(3,4,4) - 1.0_dp) > 1.0e-12_dp &
                .or. abs(liq%alpha(3,4,5) - a4_exp) > 1.0e-12_dp) then
                print '(A,4F10.6)', '   FAIL caso 9: el exceso no atraveso las dos celdas llenas: ', &
                    liq%alpha(3,4,3), liq%alpha(3,4,4), liq%alpha(3,4,5), a4_exp
                ok = .false.
            end if
        else if (icase == 5) then
            a4_exp = exc / mesh%vol(3,4,4)
            if (abs(m1 - m0) > 1.0e-12_dp * m0) then
                print '(A,ES10.3)', '   FAIL caso 5: el relevo no conservo la masa, err = ', (m1 - m0) / m0
                ok = .false.
            end if
            if (abs(liq%alpha(3,4,3) - 1.0_dp) > 1.0e-12_dp .or. abs(liq%alpha(3,4,4) - a4_exp) > 1.0e-12_dp) then
                print '(A,3F10.6)', '   FAIL caso 5: el exceso no atraveso la celda llena de liquido: ', &
                    liq%alpha(3,4,3), liq%alpha(3,4,4), a4_exp
                ok = .false.
            end if
        else
            if (liq%alpha(3,4,3) /= al3 .or. liq%alpha(3,4,4) /= 0.0_dp) then
                print '(A,I2,A,2ES12.4)', '   FAIL caso ', icase, &
                    ': el acero cruzo la celda llena (escoria/costra): a_l(k=3,4) = ', &
                    liq%alpha(3,4,3), liq%alpha(3,4,4)
                ok = .false.
            end if
            if (liq%alpha(3,4,2) > 1.0_dp - 0.2_dp + 1.0e-12_dp) then
                print '(A,I2,A,F10.6)', '   FAIL caso ', icase, ': k=2 sobre su hueco fisico: ', liq%alpha(3,4,2)
                ok = .false.
            end if
        end if
    end subroutine spill_case

    function liquid_mass() result(mt)
        real(dp) :: mt
        mt = sum(liq%alpha(1:nr,1:nth,1:nz) * liq%rho(1:nr,1:nth,1:nz) * &
                 mesh%vol(1:nr,1:nth,1:nz))
    end function liquid_mass

end program test_alpha_limiter
