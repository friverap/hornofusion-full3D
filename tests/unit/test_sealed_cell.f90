!===============================================================================
! test_sealed_cell.f90 - Presion de celdas SIN fase continua (Bug 16, sep-2026)
!
! Motivo: B1 v14. Una celda con alpha_s = 1.0000 exacto queda fuera del
! Poisson (aP=1, Su=0 => pp=0), asi que su presion no vuelve a cambiar
! NUNCA: se congelo en 613 kPa a t=42 s y sostuvo un chorro de gas de
! 200 m/s tres celdas mas arriba el resto de la corrida (p_max identico a
! 5 cifras durante 20 s). Los vecinos la leen en dp/dx del momento.
!
! Casos (singleton MPI):
!   1. Celda sellada (alpha_s = 1) con presion rancia de 6e5 Pa rodeada de
!      gas: tras UNA correccion de presion su p es la media de las vecinas
!      con fluido (Neumann de pared), no 6e5.
!   2. Sin gradiente espurio: el campo de presion y la velocidad del gas
!      tras momento+presion son IDENTICOS (1e-9 relativo) partiendo con la
!      celda sellada a 6e5 o a 0. Antes, la rancia movia el gas.
!===============================================================================
program test_sealed_cell
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_momentum_3d, only: solve_momentum_3d
    use mod_pressure_3d, only: solve_pressure_correction
    use mod_drag_ergun, only: compute_ergun_drag
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid, &
                             ws_pv_active, ws_pv_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas, liq_old, gas_old
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: Kz(:,:,:), drag(:,:,:), p_ref(:,:,:), uz_ref(:,:,:)
    real(dp) :: r1, r2, r3, res, pscale, p_seal
    integer  :: nr, nth, nz, ic, jc, kc
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 8
    cfg%dt = 0.002_dp
    cfg%solve_multiphase = .true.; cfg%solve_flow = .true.
    cfg%gas_in_poisson = .true.

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call phase_allocate(liq_old, mesh); call phase_allocate(gas_old, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    call ensure_workspace(mesh)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    allocate(Kz, mold=liq%ur); allocate(drag, mold=liq%ur)
    allocate(p_ref, mold=sh%p); allocate(uz_ref, mold=gas%uz)
    Kz = 0.0_dp
    ok = .true.
    ic = 3; jc = 4; kc = 3

    ! ---- caso 1: la presion rancia se reemplaza por el Neumann de pared ----
    call setup(6.0e5_dp)
    call one_pv_iteration()
    p_seal = sh%p(ic,jc,kc)
    if (abs(p_seal) > 1.0e3_dp) then
        print '(A,ES12.4)', '   FAIL caso 1: la celda sellada conservo presion rancia: p = ', p_seal
        ok = .false.
    end if

    ! ---- caso 2: sin gradiente espurio sobre el gas ----
    call setup(0.0_dp)
    call one_pv_iteration()
    p_ref = sh%p; uz_ref = gas%uz
    pscale = max(maxval(abs(p_ref(1:nr,1:nth,1:nz))), 1.0_dp)
    call setup(6.0e5_dp)
    call one_pv_iteration()
    res = maxval(abs(sh%p(1:nr,1:nth,1:nz) - p_ref(1:nr,1:nth,1:nz))) / pscale
    if (res > 1.0e-9_dp) then
        print '(A,ES10.3)', '   FAIL caso 2: la presion rancia altero el campo p: dp/p = ', res
        ok = .false.
    end if
    res = maxval(abs(gas%uz(1:nr,1:nth,1:nz) - uz_ref(1:nr,1:nth,1:nz)))
    if (res > 1.0e-9_dp) then
        print '(A,ES10.3)', '   FAIL caso 2: la presion rancia movio el gas: du = ', res
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_sealed_cell'
    else
        print '(A)', ' FAIL test_sealed_cell'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine setup(p_stale)
        real(dp), intent(in) :: p_stale
        sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp; liq%alpha = 0.0_dp
        sol%alpha_s(ic,jc,kc) = 1.0_dp        ! celda SELLADA: sin gas ni liquido
        gas%alpha = 1.0_dp - sol%alpha_s - liq%alpha
        liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
        gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
        sh%p = 0.0_dp; sh%pp = 0.0_dp; sh%S_arc_mom = 0.0_dp
        sh%p(ic,jc,kc) = p_stale
        liq_old%ur = liq%ur; liq_old%uth = liq%uth; liq_old%uz = liq%uz
        liq_old%alpha = liq%alpha; liq_old%T = liq%T
        gas_old%ur = gas%ur; gas_old%uth = gas%uth; gas_old%uz = gas%uz
        gas_old%alpha = gas%alpha; gas_old%T = gas%T
        ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
        ws_pv_active = (ws_liq_cont .or. gas%alpha >= ALPHA_FLOW_CUTOFF) .and. (mesh%cell_type /= 0)
        ws_pv_valid = .true.
    end subroutine setup

    subroutine one_pv_iteration()
        call compute_ergun_drag(gas, sol, mesh, cfg, drag)
        call solve_momentum_3d(gas, gas_old, liq, Kz, sh, mesh, cfg, gas%alpha, &
                               drag, .true., r1, r2, r3)
        call solve_pressure_correction(liq, gas, gas_old%T, sh, mesh, cfg, res)
    end subroutine one_pv_iteration

end program test_sealed_cell
