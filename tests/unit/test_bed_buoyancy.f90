!===============================================================================
! test_bed_buoyancy.f90 - Flotacion relativa en el LECHO con la fuerza
! balanceada (auditoria 2, N-C1, oct-2026).
! Con liq_balanced_force ninguna fase lleva peso de celda (presion reducida con
! el peso de la mezcla continua en las caras). En el lecho el liquido continuo
! (desde alpha_l 0.01) gotea a contracorriente del gas; sin flotacion relativa
! una columna uniforme quedaba en reposo con el liquido colgado.
!   1. Columna de LECHO uniforme (alpha_s 0.5, alpha_l 0.05, alpha_g 0.45), p
!      hidrostatica de la mezcla continua: la velocidad vertical del LIQUIDO
!      tras un solve de momento con la forma balanceada + flotacion del lecho
!      es IGUAL (1e-10 relativo) a la de la forma clasica -alpha grad p -
!      alpha rho g (la que usa el camino Plan D) y el liquido gotea respecto
!      del gas (el gas conserva el gradiente reducido de F2.3: con la forma
!      clasica veia la hidrostatica del poro y el anillo del eje divergia).
!   2. Misma columna SIN chatarra (alpha_l 0.4 continuo, fuera del lecho):
!      la forma balanceada NO lleva flotacion relativa (interfase grande): el
!      liquido no se separa del gas por gravedad en un paso.
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
                             ws_Fg_valid, ws_bed, ws_bed_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas, liq_old, gas_old
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: Kz(:,:,:), dl(:,:,:), dg(:,:,:)
    real(dp), allocatable :: ul_bal(:,:,:), ug_bal(:,:,:), ul_cls(:,:,:), ug_cls(:,:,:)
    real(dp) :: r1, r2, r3, err_l, sc
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

    ! ---- caso 1: lecho uniforme ----
    call setup(0.5_dp, 0.05_dp)
    call run_both()
    sc = maxval(abs(ul_cls(1:6,1:8,2:7)))
    err_l = maxval(abs(ul_bal(1:6,1:8,2:7) - ul_cls(1:6,1:8,2:7))) / max(sc, SMALL)
    if (err_l > 1.0e-10_dp) then
        print '(A,ES11.3)', '   FAIL caso 1: liquido con la forma balanceada /= clasica en el lecho: ', err_l
        ok = .false.
    end if
    if (.not. (ul_bal(ic,jc,kc) < 0.0_dp .and. ul_bal(ic,jc,kc) < ug_bal(ic,jc,kc))) then
        print '(A,2ES11.3)', '   FAIL caso 1: el liquido no gotea respecto del gas: u_l, u_g = ', &
            ul_bal(ic,jc,kc), ug_bal(ic,jc,kc)
        ok = .false.
    end if

    ! ---- caso 2: sin chatarra (interfase grande): sin flotacion relativa ----
    call setup(0.0_dp, 0.4_dp)
    call run_both()
    if (abs(ul_bal(ic,jc,kc) - ug_bal(ic,jc,kc)) > 1.0e-10_dp * max(abs(ul_cls(ic,jc,kc)), 1.0e-12_dp)) then
        print '(A,2ES11.3)', '   FAIL caso 2: fuera del lecho la forma balanceada separo las fases: ', &
            ul_bal(ic,jc,kc), ug_bal(ic,jc,kc)
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

    subroutine setup(as, al)
        real(dp), intent(in) :: as, al
        integer :: k
        real(dp) :: w
        sol%alpha_s = as; slag%alpha_sl = 0.0_dp; sol%mdot = 0.0_dp
        liq%alpha = al; gas%alpha = 1.0_dp - as - al
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
        ! p hidrostatica de la mezcla continua por volumen de fluido
        w = GRAVITY * (al * liq%rho(1,1,1) + gas%alpha(1,1,1) * gas%rho(1,1,1)) / (al + gas%alpha(1,1,1))
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
        ws_bed_valid = .true.
    end subroutine setup

    subroutine run_both()
        ! forma balanceada (+ flotacion del lecho)
        cfg%liq_balanced_force = .true.; cfg%pc_fs_liquid_gradient = .false.
        call one(ul_bal, ug_bal)
        ! forma clasica (la que usa el camino Plan D)
        cfg%liq_balanced_force = .false.
        call one(ul_cls, ug_cls)
        cfg%liq_balanced_force = .true.
    end subroutine run_both

    subroutine one(ul, ug)
        real(dp), intent(out) :: ul(-1:,-1:,-1:), ug(-1:,-1:,-1:)
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
        call compute_ergun_drag(liq, sol, mesh, cfg, dl)
        call compute_ergun_drag(gas, sol, mesh, cfg, dg)
        call solve_momentum_3d(liq, liq_old, gas, Kz, sh, mesh, cfg, liq%alpha, dl, .false., r1, r2, r3)
        call solve_momentum_3d(gas, gas_old, liq, Kz, sh, mesh, cfg, gas%alpha, dg, .true., r1, r2, r3)
        ul = liq%uz; ug = gas%uz
    end subroutine one

end program test_bed_buoyancy
