!===============================================================================
! test_bed_buoyancy.f90 - Flotacion relativa en el LECHO con la fuerza
! balanceada (auditoria 2 N-C1; auditoria 3 A3-1/M3-1, oct-2026).
! Con liq_balanced_force ninguna fase lleva peso de celda (presion reducida con
! el peso de la mezcla continua en las caras). En el lecho cada fase recupera
! POR CARAS la forma clasica -alpha grad p - alpha rho_q g (bed_rel_f); el gas
! solo donde es fluido del acople (ws_bed_gas).
!   1. Columna de LECHO uniforme (alpha_s 0.5, alpha_l 0.05, alpha_g 0.45) con
!      gas que percola, p hidrostatica de la mezcla continua: la velocidad
!      vertical de AMBAS fases tras un solve de momento con la forma balanceada
!      es IGUAL (1e-10 relativo) a la de la forma clasica, y el liquido gotea
!      respecto del gas.
!   2. Misma columna SIN chatarra (alpha_l 0.4 continuo, fuera del lecho):
!      la forma balanceada NO lleva flotacion relativa (interfase grande): el
!      liquido no se separa del gas por gravedad en un paso.
!   3. Lecho con gas ATRAPADO (ws_bed_gas = 0): NINGUNA fase lleva flotacion
!      relativa (A4-1: misma mascara de cara para ambas); en la hidrostatica
!      de la mezcla ninguna se mueve. Es el poro saturado de bath_freeze y de
!      bed_bath_rest (antes el liquido seguia clasico: 0.29 m/s en reposo).
!   4. Lecho con gas libre y p = hidrostatica del GAS (estado de lecho de
!      goteo): ambas fases clasicas; el gas queda en reposo y el liquido
!      drena con TODO su peso (hasta A3-1 el empuje quedaba x alpha_g/eps).
!   6. Cara LECHO | FREEBOARD (M4-19): columna de lecho con la mascara de cara
!      del liquido nula en la cara superior (ws_bedl_f = 0 en k = 7|8): la
!      celda 7 solo lleva la flotacion de su cara inferior, asi que su empuje
!      es ~la mitad del interior (ratio u_l(7)/u_l(4) en 0.4..0.65).
!   5. BURBUJAS (A3-5): columna de bano sin chatarra con alpha_g 0.2 y
!      ws_bub = 1 en toda la columna: ambas fases clasicas (1e-10), el gas
!      SUBE y el liquido baja. (Que la celda de superficie no es burbuja lo
!      fija la mascara de mod_multiphase y lo vigila bath_test: punto fijo.)
!===============================================================================
program test_bed_buoyancy
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_momentum_3d, only: solve_momentum_3d
    use mod_drag_ergun, only: compute_ergun_drag
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid, &
                             ws_Fg_valid, ws_bed, ws_bed_gas, ws_bed_liq, ws_bedl_f, ws_bub, ws_bub_f, ws_bed_valid, &
                             ws_bedg_f, gas_face_mask
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas, liq_old, gas_old
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: Kz(:,:,:), dl(:,:,:), dg(:,:,:)
    real(dp), allocatable :: ul_bal(:,:,:), ug_bal(:,:,:), ul_cls(:,:,:), ug_cls(:,:,:)
    real(dp) :: r1, r2, r3, err_l, err_g, sc, scg
    integer  :: ic, jc, kc
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 8
    cfg%dt = 0.002_dp
    cfg%solve_multiphase = .true.; cfg%solve_flow = .true.
    cfg%stretch_z = 1.0_dp; cfg%stretch_r = 1.0_dp
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call phase_allocate(liq_old, mesh); call phase_allocate(gas_old, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    call ensure_workspace(mesh)
    allocate(Kz, dl, dg, ul_bal, ug_bal, ul_cls, ug_cls, mold=liq%ur)
    Kz = 0.0_dp
    ok = .true.
    ic = 3; jc = 4; kc = 4
    liq%T = cfg%T_ref_boussinesq; gas%T = 1500.0_dp
    gas%rho = gas_eos(cfg%rho_gas, gas%T, 0.0_dp)

    ! ---- caso 1: lecho uniforme, gas que percola ----
    call setup(0.5_dp, 0.05_dp, .true., .false.)
    call run_both()
    call cmp_classic('caso 1')
    if (.not. (ul_bal(ic,jc,kc) < 0.0_dp .and. ul_bal(ic,jc,kc) < ug_bal(ic,jc,kc))) then
        print '(A,2ES11.3)', '   FAIL caso 1: el liquido no gotea respecto del gas: u_l, u_g = ', &
            ul_bal(ic,jc,kc), ug_bal(ic,jc,kc)
        ok = .false.
    end if

    ! ---- caso 2: sin chatarra (interfase grande): sin flotacion relativa ----
    call setup(0.0_dp, 0.4_dp, .false., .false.)
    call run_both()
    if (abs(ul_bal(ic,jc,kc) - ug_bal(ic,jc,kc)) > 1.0e-10_dp * max(abs(ul_cls(ic,jc,kc)), 1.0e-12_dp)) then
        print '(A,2ES11.3)', '   FAIL caso 2: fuera del lecho la forma balanceada separo las fases: ', &
            ul_bal(ic,jc,kc), ug_bal(ic,jc,kc)
        ok = .false.
    end if

    ! ---- caso 3: lecho con gas ATRAPADO: liquido clasico, gas sin flotacion ----
    call setup(0.5_dp, 0.05_dp, .false., .false.)
    call run_both()
    sc = maxval(abs(ul_cls(1:6,1:8,2:7)))
    if (maxval(abs(ul_bal(1:6,1:8,2:7))) > 1.0e-10_dp * sc) then
        print '(A,ES11.3)', '   FAIL caso 3: el liquido del poro saturado recibio flotacion: u_l = ', &
            maxval(abs(ul_bal(1:6,1:8,2:7)))
        ok = .false.
    end if
    if (maxval(abs(ug_bal(1:6,1:8,2:7))) > 1.0e-10_dp * sc) then
        print '(A,ES11.3)', '   FAIL caso 3: el gas atrapado recibio flotacion: u_g = ', &
            maxval(abs(ug_bal(1:6,1:8,2:7)))
        ok = .false.
    end if

    ! ---- caso 4: lecho de goteo, p = hidrostatica del GAS ----
    call setup(0.5_dp, 0.05_dp, .true., .true.)
    call run_both()
    call cmp_classic('caso 4')
    sc = maxval(abs(ul_cls(1:6,1:8,2:7)))
    if (maxval(abs(ug_bal(1:6,1:8,2:7))) > 1.0e-10_dp * sc) then
        print '(A,ES11.3)', '   FAIL caso 4: el gas no queda en reposo en su hidrostatica: u_g = ', &
            maxval(abs(ug_bal(1:6,1:8,2:7)))
        ok = .false.
    end if
    ! el liquido drena con TODO su peso: la columna de caso 1 (p de la
    ! mezcla) lo frenaba por alpha_g/eps; aqui la velocidad debe ser mayor
    if (.not. (ul_bal(ic,jc,kc) < 0.0_dp)) then
        print '(A,ES11.3)', '   FAIL caso 4: el liquido no drena: u_l = ', ul_bal(ic,jc,kc)
        ok = .false.
    end if

    ! ---- caso 5: burbujas en el bano ----
    call setup(0.0_dp, 0.8_dp, .false., .false.)
    ws_bub = 0.0_dp; ws_bub_f = 0.0_dp
    ws_bub(1:6,1:8,1:8) = 1.0_dp; ws_bub_f(1:6,1:8,0:8) = 1.0_dp
    ws_bedl_f = 1.0_dp
    call run_both()
    call cmp_classic_k('caso 5', 2, 7)
    if (.not. (ug_bal(ic,jc,kc) > 0.0_dp .and. ul_bal(ic,jc,kc) < ug_bal(ic,jc,kc))) then
        print '(A,2ES11.3)', '   FAIL caso 5: las burbujas no suben respecto del liquido: u_l, u_g = ', &
            ul_bal(ic,jc,kc), ug_bal(ic,jc,kc)
        ok = .false.
    end if
    ws_bub = 0.0_dp; ws_bub_f = 0.0_dp; ws_bedl_f = 0.0_dp

    ! ---- caso 6: cara lecho | freeboard ----
    call setup(0.5_dp, 0.05_dp, .true., .false.)
    ws_bedl_f(:,:,7) = 0.0_dp
    call run_both()
    if (.not. (ul_bal(ic,jc,7) / ul_bal(ic,jc,4) > 0.4_dp .and. ul_bal(ic,jc,7) / ul_bal(ic,jc,4) < 0.65_dp)) then
        print '(A,2ES11.3)', '   FAIL caso 6: la celda bajo la cara sin flotacion no lleva ~la mitad: u(7), u(4) = ', &
            ul_bal(ic,jc,7), ul_bal(ic,jc,4)
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_bed_buoyancy'
    else
        print '(A)', ' FAIL test_bed_buoyancy'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine setup(as, al, gas_free, p_gas)
        real(dp), intent(in) :: as, al
        logical, intent(in)  :: gas_free, p_gas
        integer :: k
        real(dp) :: w
        sol%alpha_s = as; slag%alpha_sl = 0.0_dp; sol%mdot = 0.0_dp
        liq%alpha = al; gas%alpha = 1.0_dp - as - al
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
        ! p hidrostatica de la mezcla continua por volumen de fluido
        w = GRAVITY * (al * liq%rho(1,1,1) + gas%alpha(1,1,1) * gas%rho(1,1,1)) / (al + gas%alpha(1,1,1))
        if (p_gas) w = GRAVITY * gas%rho(1,1,1)
        do k = -1, mesh%nz + 2
            sh%p(:,:,k) = w * (mesh%zf(mesh%nz) - mesh%z(k))
        end do
        liq_old%ur = 0.0_dp; liq_old%uth = 0.0_dp; liq_old%uz = 0.0_dp
        gas_old%ur = 0.0_dp; gas_old%uth = 0.0_dp; gas_old%uz = 0.0_dp
        liq_old%alpha = liq%alpha; gas_old%alpha = gas%alpha
        liq_old%T = liq%T; gas_old%T = gas%T
        liq_old%rho = liq%rho; gas_old%rho = gas%rho
        ws_Fg_valid = .false.
        ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
        ws_bed = merge(1.0_dp, 0.0_dp, sol%alpha_s >= 1.0e-2_dp .and. mesh%cell_type /= 0)
        ! gas_free = poro no saturado con gas del acople; si no, poro
        ! SATURADO (rampa 0 para ambas fases, A4-1)
        ws_bed_liq = merge(ws_bed, 0.0_dp, gas_free)
        ws_bed_gas = ws_bed_liq
        ws_bedl_f = ws_bed_liq      ! columna uniforme en reposo: minimo = rampa
        ws_bed_valid = .true.
    end subroutine setup

    subroutine cmp_classic_k(tag, k1, k2)
        character(len=*), intent(in) :: tag
        integer, intent(in) :: k1, k2
        sc  = maxval(abs(ul_cls(1:6,1:8,k1:k2)))
        scg = max(maxval(abs(ug_cls(1:6,1:8,k1:k2))), sc)
        err_l = maxval(abs(ul_bal(1:6,1:8,k1:k2) - ul_cls(1:6,1:8,k1:k2))) / max(sc, SMALL)
        err_g = maxval(abs(ug_bal(1:6,1:8,k1:k2) - ug_cls(1:6,1:8,k1:k2))) / max(scg, SMALL)
        if (err_l > 1.0e-10_dp) then
            print '(A,A,A,ES11.3)', '   FAIL ', tag, ': liquido con la forma balanceada /= clasica (burbujas): ', err_l
            ok = .false.
        end if
        if (err_g > 1.0e-10_dp) then
            print '(A,A,A,ES11.3)', '   FAIL ', tag, ': gas con la forma balanceada /= clasica (burbujas): ', err_g
            ok = .false.
        end if
    end subroutine cmp_classic_k

    subroutine cmp_classic(tag)
        ! (nota A4-1: 'gas_free' en setup = poro no saturado; el caso con gas
        ! ATRAPADO pero poro no saturado -ws_bed_liq 1, ws_bed_gas 0- lo
        ! cubre bed_drain, donde el liquido drena clasico bajo gas atrapado)
        character(len=*), intent(in) :: tag
        sc  = maxval(abs(ul_cls(1:6,1:8,2:7)))
        scg = max(maxval(abs(ug_cls(1:6,1:8,2:7))), sc)
        err_l = maxval(abs(ul_bal(1:6,1:8,2:7) - ul_cls(1:6,1:8,2:7))) / max(sc, SMALL)
        err_g = maxval(abs(ug_bal(1:6,1:8,2:7) - ug_cls(1:6,1:8,2:7))) / max(scg, SMALL)
        if (err_l > 1.0e-10_dp) then
            print '(A,A,A,ES11.3)', '   FAIL ', tag, ': liquido con la forma balanceada /= clasica en el lecho: ', err_l
            ok = .false.
        end if
        if (err_g > 1.0e-10_dp) then
            print '(A,A,A,ES11.3)', '   FAIL ', tag, ': gas con la forma balanceada /= clasica en el lecho: ', err_g
            ok = .false.
        end if
    end subroutine cmp_classic

    subroutine run_both()
        integer :: ia, ja, ka
        ! mascara de CARA del gas por defecto (la que arma mod_multiphase sin
        ! pc_bed_gas_pocket; auditoria 6): max(min de las dos celdas, burbuja)
        ws_bedg_f = 0.0_dp
        do ka = lbound(ws_bedg_f,3), ubound(ws_bedg_f,3) - 1
            do ja = lbound(ws_bedg_f,2), ubound(ws_bedg_f,2)
                do ia = lbound(ws_bedg_f,1), ubound(ws_bedg_f,1)
                    ws_bedg_f(ia,ja,ka) = gas_face_mask(ws_bed_gas(ia,ja,ka), ws_bed_gas(ia,ja,ka+1), ws_bub_f(ia,ja,ka))
                end do
            end do
        end do
        ! forma balanceada (+ flotacion del lecho por caras)
        cfg%liq_balanced_force = .true.; cfg%pc_fs_liquid_gradient = .false.
        call one(ul_bal, ug_bal, .false.)
        ! forma clasica -alpha grad p - alpha rho_q g para AMBAS fases (la del
        ! liquido del camino Plan D; el gas sin fuerza balanceada lleva F2.3,
        ! que resta el peso del liquido continuo: para que sea clasico puro
        ! se le quita la mascara de liquido continuo solo en su solve)
        cfg%liq_balanced_force = .false.
        call one(ul_cls, ug_cls, .true.)
        cfg%liq_balanced_force = .true.
    end subroutine run_both

    subroutine one(ul, ug, classic)
        real(dp), intent(out) :: ul(-1:,-1:,-1:), ug(-1:,-1:,-1:)
        logical, intent(in)   :: classic
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
        call compute_ergun_drag(liq, sol, mesh, cfg, dl)
        call compute_ergun_drag(gas, sol, mesh, cfg, dg)
        call solve_momentum_3d(liq, liq_old, gas, Kz, sh, mesh, cfg, liq%alpha, dl, .false., r1, r2, r3)
        if (classic) ws_liq_cont = .false.
        call solve_momentum_3d(gas, gas_old, liq, Kz, sh, mesh, cfg, gas%alpha, dg, .true., r1, r2, r3)
        if (classic) ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s)
        ul = liq%uz; ug = gas%uz
    end subroutine one

end program test_bed_buoyancy
