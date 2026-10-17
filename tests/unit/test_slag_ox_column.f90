!===============================================================================
! test_slag_ox_column.f90 - Oxidacion Fe + 1/2 O2 -> FeO POR COLUMNA con la
! escoria CONDENSADA (Plan I, I1). Singleton MPI, sin carbon en la escoria
! (solo oxidacion). Por caso, en todas las columnas:
!   1. Capa compactada de 3 celdas (4-6, sin gas) entre el baño (1-3) y gas
!      con O2 (7+): el O2 sale de la celda 7 (gas libre sobre el tope; la 6
!      no tiene gas y no aporta), el Fe
!      del baño de la celda 3 y el FeO va a la escoria de la celda 4 (antes la
!      capa aislaba el metal: no habia oxidacion).
!   2. Una celda parcial de escoria con gas propio (4: escoria 0.5 + gas 0.5)
!      sobre el baño: O2 de la propia celda 4 MAS el de la 5 (gas libre) y Fe
!      de la 3; el estencil local (modo legado) solo usa el O2 de la 4: la
!      columna oxida MAS que el legado.
!   3. Celda de interfaz con acero resuelto (4: acero 0.5 + escoria 0.5) bajo
!      escoria compactada (5) y gas (6+): Fe del acero de la celda 4, O2 de la 6.
!   4. (dirigida I1, MEDIO-4) el caso 1 con una TRAZA de escoria (1e-4) en la
!      celda de baño 3 (la que deja el upwind antes del reordenamiento): la
!      traza no es la interfaz; el FeO va a la escoria resuelta de la 4.
! En todos: Fe, O y energia conservados contra el audit (AUD_FE_YIELD,
! AUD_SLAG_OX_E) a 1e-12 mas el redondeo de las restas de inventario, y nada
! cambia fuera de las tres celdas elegidas.
!===============================================================================
program test_slag_ox_column
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_audit, only: audit_peek, AUD_FE_YIELD, AUD_SLAG_OX_E
    use mod_melting_3d, only: liquid_datum_offset
    use mod_slag_chemistry, only: compute_slag_chemistry
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, liq_old, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), parameter :: MW_FE = 0.05585_dp, MW_FEO = 0.07185_dp, MW_O2 = 0.032_dp
    integer :: nr, nth, nz
    real(dp) :: last_dfeo, dfeo_col
    logical :: ok

    call config_set_defaults(cfg)
    cfg%nr = 3; cfg%ntheta = 4; cfg%nz = 10; cfg%dt = 0.01_dp
    cfg%solve_slag = .true.; cfg%slag_in_volume = .true.
    cfg%solve_flow = .true.; cfg%solve_multiphase = .true.; cfg%mixture_model = .false.
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(liq_old, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    ok = .true.
    if (.not. slag_condensed_on(cfg)) then
        print '(A)', ' FAIL test_slag_ox_column: la escoria condensada no esta activa'
        stop 1
    end if

    ! --- caso 1: capa compactada de 3 celdas ----------------------------------
    call setup(3)
    call put_slag(4, 1.0_dp, 0.0_dp); call put_slag(5, 1.0_dp, 0.0_dp)
    call put_slag(6, 1.0_dp, 0.0_dp)
    call run_case('caso 1', 7, 7, 3, 4)
    ! --- caso 2: celda parcial con gas propio ---------------------------------
    call setup(3)
    call put_slag(4, 0.5_dp, 0.0_dp)
    call run_case('caso 2', 4, 5, 3, 4)
    dfeo_col = last_dfeo
    ! el mismo caso con el estencil LOCAL (modo legado): solo el O2 de la 4
    cfg%slag_in_volume = .false.
    call setup(3)
    call put_slag(4, 0.5_dp, 0.0_dp)
    call run_case('caso 2 legado', 4, 4, 3, 4)
    if (.not. dfeo_col > last_dfeo * (1.0_dp + 1.0e-6_dp)) &
        call fail('caso 2: la columna no suma el O2 de la celda de encima (kg)', dfeo_col - last_dfeo)
    cfg%slag_in_volume = .true.
    ! --- caso 3: interfaz con acero resuelto ----------------------------------
    call setup(3)
    call put_slag(4, 0.5_dp, 0.5_dp); call put_slag(5, 1.0_dp, 0.0_dp)
    call run_case('caso 3', 6, 6, 4, 4)

    ! --- caso 4: traza de escoria bajo la interfaz ----------------------------
    call setup(3)
    call put_slag(3, 1.0e-4_dp, 1.0_dp - 1.0e-4_dp)
    call put_slag(4, 1.0_dp, 0.0_dp); call put_slag(5, 1.0_dp, 0.0_dp)
    call put_slag(6, 1.0_dp, 0.0_dp)
    call run_case('caso 4', 7, 7, 3, 4)

    if (ok) then
        print '(A)', ' PASS test_slag_ox_column (O2 sobre la capa, Fe bajo la capa, Fe/O/energia exactos)'
    else
        print '(A)', ' FAIL test_slag_ox_column'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    ! baño lleno en 1..kbath, gas con O2 encima, todo a 1850 K
    subroutine setup(kbath)
        integer, intent(in) :: kbath
        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp
        liq%alpha = 0.0_dp; liq%alpha(:,:,-1:kbath) = 1.0_dp; liq%T = 1850.0_dp
        slag%m_sl = 0.0_dp; slag%alpha_sl = 0.0_dp; slag%E_sl = 0.0_dp
        slag%m_X = 0.0_dp; slag%T_sl = 0.0_dp; slag%alpha_foam = 0.0_dp
        sh%Y_O2 = 0.2_dp; sh%Y_CO = 0.0_dp; sh%Y_CO2 = 0.0_dp
        sh%S_O2_src = 0.0_dp; sh%S_CO_src = 0.0_dp; sh%S_CO2_src = 0.0_dp
        gas%alpha = 1.0_dp - liq%alpha
    end subroutine setup

    subroutine put_slag(kk, asl, al)
        integer, intent(in)  :: kk
        real(dp), intent(in) :: asl, al
        integer :: ii, jj
        do jj = 1, nth
            do ii = 1, nr
                slag%alpha_sl(ii,jj,kk) = asl
                slag%m_sl(ii,jj,kk) = cfg%rho_slag * asl * mesh%vol(ii,jj,kk)
                slag%m_X(ii,jj,kk,SL_FEO)  = 0.20_dp * slag%m_sl(ii,jj,kk)
                slag%m_X(ii,jj,kk,SL_CAO)  = 0.40_dp * slag%m_sl(ii,jj,kk)
                slag%m_X(ii,jj,kk,SL_SIO2) = 0.20_dp * slag%m_sl(ii,jj,kk)
                slag%T_sl(ii,jj,kk) = 1900.0_dp
                slag%E_sl(ii,jj,kk) = slag%m_sl(ii,jj,kk) * cfg%cp_slag * 1900.0_dp
                liq%alpha(ii,jj,kk) = al
                gas%alpha(ii,jj,kk) = max(0.0_dp, 1.0_dp - asl - al)
            end do
        end do
    end subroutine put_slag

    ! ko1..ko2: celdas del O2; ks: celda del Fe; kb: celda que recibe el FeO
    subroutine run_case(tag, ko1, ko2, ks, kb)
        character(len=*), intent(in) :: tag
        integer, intent(in) :: ko1, ko2, ks, kb
        real(dp), allocatable :: feo0(:,:,:), al0(:,:,:), esl0(:,:,:)
        real(dp) :: c0, dfeo, dfe, do2, de_sl, de_l, aud_fe0, aud_e0, aud_fe, aud_e, e_ref
        ! (dirigida I1, MEDIO-1) escalas del redondeo de las RESTAS de
        ! inventario: Delta alpha sobre alpha ~ 1 (ulp(1)/da ~ 1e-12 relativo,
        ! sistematico entre columnas) y Delta m_X sobre la masa de FeO previa
        real(dp) :: s_ml, s_hl, s_feo, tol
        integer :: ii, jj, kk
        c0 = liquid_datum_offset(cfg)
        liq_old%alpha = liq%alpha; liq_old%T = liq%T
        allocate(feo0(nr,nth,nz), al0(nr,nth,nz), esl0(nr,nth,nz))
        feo0 = slag%m_X(1:nr,1:nth,1:nz,SL_FEO); al0 = liq%alpha(1:nr,1:nth,1:nz)
        esl0 = slag%E_sl(1:nr,1:nth,1:nz)
        aud_fe0 = audit_peek(AUD_FE_YIELD); aud_e0 = audit_peek(AUD_SLAG_OX_E)
        call compute_slag_chemistry(slag, liq, liq_old, gas, sol, sh, mesh, cfg)
        aud_fe = audit_peek(AUD_FE_YIELD) - aud_fe0
        aud_e  = audit_peek(AUD_SLAG_OX_E) - aud_e0
        dfeo = 0.0_dp; dfe = 0.0_dp; do2 = 0.0_dp; de_sl = 0.0_dp; de_l = 0.0_dp; e_ref = 0.0_dp
        s_ml = 0.0_dp; s_hl = 0.0_dp; s_feo = 0.0_dp
        do kk = 1, nz
            do jj = 1, nth
                do ii = 1, nr
                    dfeo = dfeo + slag%m_X(ii,jj,kk,SL_FEO) - feo0(ii,jj,kk)
                    dfe = dfe + (al0(ii,jj,kk) - liq%alpha(ii,jj,kk)) * liq%rho(ii,jj,kk) * mesh%vol(ii,jj,kk)
                    do2 = do2 - sh%S_O2_src(ii,jj,kk) * mesh%vol(ii,jj,kk) * cfg%dt
                    de_sl = de_sl + slag%E_sl(ii,jj,kk) - esl0(ii,jj,kk)
                    de_l = de_l - (al0(ii,jj,kk) - liq%alpha(ii,jj,kk)) * liq%rho(ii,jj,kk) &
                         * mesh%vol(ii,jj,kk) * (liq%cp(ii,jj,kk) * liq%T(ii,jj,kk) + c0)
                    e_ref = e_ref + esl0(ii,jj,kk)
                    s_ml = s_ml + al0(ii,jj,kk) * liq%rho(ii,jj,kk) * mesh%vol(ii,jj,kk)
                    s_hl = s_hl + al0(ii,jj,kk) * liq%rho(ii,jj,kk) * mesh%vol(ii,jj,kk) &
                         * abs(liq%cp(ii,jj,kk) * liq%T(ii,jj,kk) + c0)
                    s_feo = s_feo + feo0(ii,jj,kk)
                    if (kk /= kb .and. slag%m_X(ii,jj,kk,SL_FEO) /= feo0(ii,jj,kk)) &
                        call fail(tag // ': FeO fuera de la celda kb en k', real(kk, dp))
                    if (kk /= ks .and. liq%alpha(ii,jj,kk) /= al0(ii,jj,kk)) &
                        call fail(tag // ': Fe sale de otra celda que ks en k', real(kk, dp))
                    if ((kk < ko1 .or. kk > ko2) .and. sh%S_O2_src(ii,jj,kk) /= 0.0_dp) &
                        call fail(tag // ': O2 sale de otra celda que ko1..ko2 en k', real(kk, dp))
                    if (liq_old%alpha(ii,jj,kk) /= liq%alpha(ii,jj,kk)) &
                        call fail(tag // ': ancla temporal del liquido sin el Fe en k', real(kk, dp))
                end do
            end do
        end do
        if (.not. dfeo > 0.0_dp) call fail(tag // ': no hubo oxidacion', dfeo)
        ! referencia exacta: el Fe auditado (suma directa de los dm_fe); cada
        ! inventario se compara con su tolerancia de redondeo de la resta
        tol = 1.0e-12_dp * aud_fe + 4.0_dp * epsilon(1.0_dp) * s_ml
        if (abs(dfe - aud_fe) > tol) call fail(tag // ': Fe del baño /= AUD_FE_YIELD (kg)', dfe - aud_fe)
        tol = 1.0e-12_dp * aud_fe + 4.0_dp * epsilon(1.0_dp) * s_feo
        if (abs(dfeo - aud_fe * MW_FEO / MW_FE) > tol) &
            call fail(tag // ': FeO formado /= Fe auditado (kg)', dfeo - aud_fe * MW_FEO / MW_FE)
        ! el sumidero de O2 parte de 0: sin resta de inventario
        if (abs(do2 - aud_fe * 0.5_dp * MW_O2 / MW_FE) > 1.0e-12_dp * do2) &
            call fail(tag // ': O no conservado (rel)', (do2 - aud_fe * 0.5_dp * MW_O2 / MW_FE) / do2)
        ! energia: lo que ganan escoria + baño es exactamente el termino de
        ! reaccion auditado (tolerancia: redondeo de E_sl y de la entalpia del baño)
        tol = 1.0e-12_dp * abs(aud_e) + 4.0_dp * epsilon(1.0_dp) * (e_ref + s_hl)
        if (abs(de_sl + de_l - aud_e) > tol) &
            call fail(tag // ': energia vs AUD_SLAG_OX_E (J)', de_sl + de_l - aud_e)
        print '(3A,ES11.3,A)', '   ', tag, ': FeO formado ', dfeo, ' kg'
        last_dfeo = dfeo
        deallocate(feo0, al0, esl0)
    end subroutine run_case

    subroutine fail(msg, v)
        character(len=*), intent(in) :: msg
        real(dp), intent(in) :: v
        print '(3A,ES12.4)', '   FAIL ', msg, ': ', v
        ok = .false.
    end subroutine fail
end program test_slag_ox_column
