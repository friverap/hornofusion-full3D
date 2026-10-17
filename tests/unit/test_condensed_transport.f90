!===============================================================================
! test_condensed_transport.f90 - Transporte condensado acero+escoria (Plan H, P2)
! (a) sin escoria, solve_condensed_fraction == solve_volume_fraction BIT A BIT
!     (alpha del acero, alpha del gas, flujos ws_Fr/Fth/Fz);
! (b) traslacion azimutal uniforme (periodica) de acero y escoria con
!     composicion variable: masa de acero, masa de escoria, E_sl y m_X
!     conservados a 1e-13, 0 <= alpha_sl <= alpha_c, sin recorte;
! (c) (auditoria P4 M3) CFL no sub-pasable -> fallback implicito: la escoria
!     queda en su celda acotada por alpha_c, sin flujo de escoria, y masa de
!     escoria + clip auditado = masa inicial;
! (d) (auditoria 18, A18-5) congelacion mayor que el acero de una celda con
!     escoria (acero 0.3, escoria 0.1, sumidero 0.4): la escoria se conserva
!     ENTERA (sin clip de escoria) y el acero queda en 0 (el deficit es clip
!     del liquido, no escoria recortada).
!===============================================================================
program test_condensed_transport
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_continuity, only: solve_volume_fraction, solve_condensed_fraction
    use mod_workspace, only: ws_Fr, ws_Fth, ws_Fz, ws_slag_clip_call, ensure_workspace, &
                             ws_Fsl_r, ws_Fsl_th, ws_Fsl_z
    implicit none
    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas, liq2, gas2
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: a_old(:,:,:), zero(:,:,:), Fr1(:,:,:), Fth1(:,:,:), Fz1(:,:,:)
    real(dp), allocatable :: asl0(:,:,:), ms0(:,:,:), es0(:,:,:), mx0(:,:,:,:)
    real(dp) :: mst0, mst1, msl0, msl1, E0, E1, X0, X1, worst
    integer  :: i, j, k, nr, nth, nz
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 4; cfg%ntheta = 12; cfg%nz = 6; cfg%dt = 0.01_dp
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call phase_allocate(liq2, mesh); call phase_allocate(gas2, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    call ensure_workspace(mesh)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    ok = .true.
    allocate(a_old, zero, Fr1, Fth1, Fz1, asl0, ms0, es0, mold=liq%alpha)
    allocate(mx0, mold=slag%m_X)
    zero = 0.0_dp

    ! ---- (a) sin escoria: bit a bit ----
    sol%alpha_s = 0.0_dp; sol%mdot = 0.0_dp; slag%alpha_sl = 0.0_dp
    slag%m_sl = 0.0_dp; slag%E_sl = 0.0_dp; slag%m_X = 0.0_dp
    liq%ur = 0.0_dp; liq%uth = 0.3_dp; liq%uz = -0.2_dp
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                liq%alpha(i,j,k) = 0.2_dp + 0.05_dp * mod(i + 2*j + k, 7)
            end do
        end do
    end do
    gas%alpha = 1.0_dp - liq%alpha
    a_old = liq%alpha
    liq2 = liq; gas2 = gas
    call solve_volume_fraction(liq, gas, sol, zero, a_old, mesh, cfg)
    Fr1 = ws_Fr; Fth1 = ws_Fth; Fz1 = ws_Fz
    call solve_condensed_fraction(liq2, gas2, sol, slag, zero, zero, slag%m_X, a_old, mesh, cfg)
    if (any(liq2%alpha(1:nr,1:nth,1:nz) /= liq%alpha(1:nr,1:nth,1:nz)) .or. &
        any(gas2%alpha(1:nr,1:nth,1:nz) /= gas%alpha(1:nr,1:nth,1:nz)) .or. &
        any(ws_Fr /= Fr1) .or. any(ws_Fth /= Fth1) .or. any(ws_Fz /= Fz1)) then
        print '(A)', '   FAIL caso a: sin escoria el transporte condensado no es bit a bit'
        ok = .false.
    end if

    ! ---- (b) traslacion azimutal con escoria ----
    liq%ur = 0.0_dp; liq%uth = 0.4_dp; liq%uz = 0.0_dp
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                a_old(i,j,k) = 0.3_dp + 0.04_dp * mod(i + j, 5)
                asl0(i,j,k) = 0.1_dp + 0.03_dp * mod(2*j + k, 4)
                ms0(i,j,k) = asl0(i,j,k) * cfg%rho_slag * mesh%vol(i,j,k)
                es0(i,j,k) = ms0(i,j,k) * cfg%cp_slag * (1700.0_dp + 10.0_dp * j)
                mx0(i,j,k,:) = ms0(i,j,k) * 0.1_dp * (1.0_dp + 0.01_dp * j)
            end do
        end do
    end do
    where (mesh%cell_type == 0)
        a_old = 0.0_dp; asl0 = 0.0_dp; ms0 = 0.0_dp; es0 = 0.0_dp
    end where
    do i = 1, size(mx0,4)
        where (mesh%cell_type == 0) mx0(:,:,:,i) = 0.0_dp
    end do
    ! los insumos llegan con halos intercambiados (como slag_pre y liq_old)
    call mpi_exchange_halos_3d(a_old, mesh%topo); call mpi_exchange_halos_3d(asl0, mesh%topo)
    call mpi_exchange_halos_3d(ms0, mesh%topo);   call mpi_exchange_halos_3d(es0, mesh%topo)
    do i = 1, size(mx0,4)
        Fr1 = mx0(:,:,:,i); call mpi_exchange_halos_3d(Fr1, mesh%topo); mx0(:,:,:,i) = Fr1
    end do
    liq%alpha = a_old; gas%alpha = 1.0_dp - a_old - asl0
    mst0 = sum(a_old(1:nr,1:nth,1:nz) * mesh%vol(1:nr,1:nth,1:nz))
    msl0 = sum(ms0(1:nr,1:nth,1:nz)); E0 = sum(es0(1:nr,1:nth,1:nz)); X0 = sum(mx0(1:nr,1:nth,1:nz,:))
    call solve_condensed_fraction(liq, gas, sol, slag, asl0, es0, mx0, a_old, mesh, cfg)
    mst1 = sum(liq%alpha(1:nr,1:nth,1:nz) * mesh%vol(1:nr,1:nth,1:nz))
    msl1 = sum(slag%m_sl(1:nr,1:nth,1:nz)); E1 = sum(slag%E_sl(1:nr,1:nth,1:nz))
    X1 = sum(slag%m_X(1:nr,1:nth,1:nz,:))
    worst = max(abs(mst1-mst0)/mst0, abs(msl1-msl0)/msl0, abs(E1-E0)/E0, abs(X1-X0)/X0)
    if (worst > 1.0e-13_dp) then
        print '(A,4ES11.3)', '   FAIL caso b: conservacion acero/escoria/E/X: ', &
            (mst1-mst0)/mst0, (msl1-msl0)/msl0, (E1-E0)/E0, (X1-X0)/X0
        ok = .false.
    end if
    if (any(slag%alpha_sl(1:nr,1:nth,1:nz) < 0.0_dp) .or. abs(ws_slag_clip_call) > 1.0e-12_dp * msl0) then
        print '(A,ES11.3)', '   FAIL caso b: escoria negativa o recortada: ', ws_slag_clip_call
        ok = .false.
    end if
    if (abs(sum(slag%alpha_sl(1:nr,1:nth,1:nz) * cfg%rho_slag * mesh%vol(1:nr,1:nth,1:nz)) - msl1) > 1.0e-12_dp * msl1) then
        print '(A)', '   FAIL caso b: alpha_sl incoherente con m_sl'
        ok = .false.
    end if

    ! principio del maximo: la escoria resuelta no sale del rango de T inicial
    ! (con valores especificos de inicio de paso y reescalado final, la que
    ! cruzaba una celda dentro del paso llegaba sin energia)
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                if (slag%alpha_sl(i,j,k) < 1.0e-6_dp) cycle
                if (slag%T_sl(i,j,k) < 1700.0_dp + 10.0_dp - 1.0e-9_dp .or. &
                    slag%T_sl(i,j,k) > 1700.0_dp + 10.0_dp * nth + 1.0e-9_dp) then
                    print '(A,3I4,ES14.6)', '   FAIL caso b: T_sl fuera del rango inicial en ', i, j, k, slag%T_sl(i,j,k)
                    ok = .false.
                end if
            end do
        end do
    end do

    ! ---- (c) fallback implicito ----
    liq%ur = 0.0_dp; liq%uth = 5.0e3_dp; liq%uz = 0.0_dp
    liq%alpha = a_old; gas%alpha = 1.0_dp - a_old - asl0
    ws_Fsl_r = 1.0_dp; ws_Fsl_th = 1.0_dp; ws_Fsl_z = 1.0_dp
    call solve_condensed_fraction(liq, gas, sol, slag, asl0, es0, mx0, a_old, mesh, cfg)
    msl1 = sum(slag%m_sl(1:nr,1:nth,1:nz))
    if (abs(msl1 + ws_slag_clip_call - msl0) > 1.0e-12_dp * msl0) then
        print '(A,2ES12.4)', '   FAIL caso c: masa de escoria + clip /= inicial: ', msl1 + ws_slag_clip_call - msl0, msl0
        ok = .false.
    end if
    if (any(slag%alpha_sl(1:nr,1:nth,1:nz) < 0.0_dp) .or. any(liq%alpha(1:nr,1:nth,1:nz) < 0.0_dp)) then
        print '(A)', '   FAIL caso c: fraccion negativa tras el fallback'; ok = .false.
    end if
    if (any(ws_Fsl_r /= 0.0_dp) .or. any(ws_Fsl_th /= 0.0_dp) .or. any(ws_Fsl_z /= 0.0_dp)) then
        print '(A)', '   FAIL caso c: flujo de escoria rancio tras el fallback'; ok = .false.
    end if

    ! ---- (d) congelacion mayor que el acero ----
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
    a_old = 0.0_dp; asl0 = 0.0_dp; es0 = 0.0_dp; mx0 = 0.0_dp
    i = 2; j = 3; k = 3
    a_old(i,j,k) = 0.3_dp; asl0(i,j,k) = 0.1_dp
    es0(i,j,k) = asl0(i,j,k) * cfg%rho_slag * mesh%vol(i,j,k) * cfg%cp_slag * 1800.0_dp
    sol%mdot = 0.0_dp
    sol%mdot(i,j,k) = -0.4_dp * cfg%rho_steel * mesh%vol(i,j,k) / cfg%dt
    liq%alpha = a_old; gas%alpha = 1.0_dp - a_old - asl0
    call solve_condensed_fraction(liq, gas, sol, slag, asl0, es0, mx0, a_old, mesh, cfg)
    sol%mdot = 0.0_dp
    if (abs(slag%alpha_sl(i,j,k) - 0.1_dp) > 1.0e-12_dp .or. liq%alpha(i,j,k) /= 0.0_dp .or. &
        abs(ws_slag_clip_call) > 1.0e-12_dp * cfg%rho_slag * mesh%vol(i,j,k)) then
        print '(A,3ES12.4)', '   FAIL caso d: la congelacion recorto escoria: ', slag%alpha_sl(i,j,k), &
            liq%alpha(i,j,k), ws_slag_clip_call
        ok = .false.
    end if

    if (ok) then
        print '(A,ES10.3,A)', ' PASS test_condensed_transport (sin escoria bit a bit; traslacion conserva a ', worst, ')'
    else
        print '(A)', ' FAIL test_condensed_transport'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_condensed_transport
