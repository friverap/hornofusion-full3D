!===============================================================================
! test_noflow_mass.f90 - Fusion/congelacion SIN transporte de alpha (auditoria
! 2, N-C4). En las ramas de una sola fase y solo energia el mdot no se aplicaba
! al liquido: bath_freeze sin flujo creaba 18 t de acero y 1.4e10 J por paso.
!   1. Congelacion 5 K bajo el liquidus: compute_melting + apply_mass_source_
!      noflow + solve_energy_3d -> masa de acero (liquido + solido) y energia
!      exactas; liquido en T_liquidus (palanca en un paso); sum alpha = 1.
!   2. Fusion de chatarra caliente en un charco: masa y energia exactas.
!===============================================================================
program test_noflow_mass
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_energy_3d, only: solve_energy_3d
    use mod_melting_3d, only: compute_melting, solid_enthalpy
    use mod_solid_phase, only: apply_mass_source_noflow
    use mod_workspace, only: ensure_workspace
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: T_old(:,:,:), a_old(:,:,:), zero3(:,:,:), Tsrc(:,:,:)
    real(dp) :: res, C0, M0, M1, E0, E1, scaleE, sumerr
    integer  :: i, j, k
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 6
    cfg%dt = 0.01_dp; cfg%h_wall = 0.0_dp
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    call ensure_workspace(mesh)
    allocate(T_old, a_old, zero3, Tsrc, mold=liq%T)
    zero3 = 0.0_dp; Tsrc = 0.0_dp
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
    sh%S_arc = 0.0_dp; sh%S_chem = 0.0_dp; sh%kappa_f = 0.0_dp; sh%G_rad = 0.0_dp
    C0 = (cfg%cp_s - cfg%cp_l) * cfg%T_liquidus + cfg%h_fusion
    ok = .true.

    ! ---- caso 1: congelacion ----
    liq%alpha = 0.5_dp; gas%alpha = 0.5_dp
    T_old = cfg%T_liquidus - 5.0_dp; liq%T = T_old
    sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%alpha_s = 0.0_dp; sol%mdot = 0.0_dp
    call totals(M0, E0)
    a_old = liq%alpha
    call compute_melting(sol, liq, mesh, cfg, cfg%dt, Tsrc)
    call apply_mass_source_noflow(liq, gas, sol, slag, mesh, cfg, cfg%dt)
    call solve_energy_3d(liq, T_old, sh, mesh, cfg, liq%alpha, zero3, a_old, &
                         sol%mdot, Tsrc, .false., res)
    call totals(M1, E1)
    scaleE = sum(sol%m_s) * cfg%h_fusion
    call check('caso 1 (congelacion)', M0, M1, E0, E1, scaleE)
    if (abs(liq%T(3,4,3) - cfg%T_liquidus) > 1.0e-6_dp) then
        print '(A,F14.8)', '   FAIL caso 1: liquido fuera de T_liquidus: ', liq%T(3,4,3)
        ok = .false.
    end if

    ! ---- caso 2: fusion de chatarra caliente en un charco ----
    liq%alpha = 0.3_dp
    sol%alpha_s = 0.2_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%mdot = 0.0_dp
    do k = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                sol%m_s(i,j,k) = 0.2_dp * cfg%rho_steel * mesh%vol(i,j,k)
                sol%E_s(i,j,k) = sol%m_s(i,j,k) * 0.5_dp * &
                    (solid_enthalpy(cfg%T_solidus, cfg) + solid_enthalpy(cfg%T_liquidus, cfg))
            end do
        end do
    end do
    gas%alpha = 1.0_dp - liq%alpha - sol%alpha_s
    T_old = cfg%T_liquidus + 20.0_dp; liq%T = T_old
    call totals(M0, E0)
    a_old = liq%alpha
    call compute_melting(sol, liq, mesh, cfg, cfg%dt, Tsrc)
    call apply_mass_source_noflow(liq, gas, sol, slag, mesh, cfg, cfg%dt)
    call solve_energy_3d(liq, T_old, sh, mesh, cfg, liq%alpha, zero3, a_old, &
                         sol%mdot, Tsrc, .false., res)
    call totals(M1, E1)
    scaleE = abs(E0) * 1.0e-3_dp
    call check('caso 2 (fusion)', M0, M1, E0, E1, scaleE)

    ! suma de fracciones = 1 en las celdas activas
    sumerr = 0.0_dp
    do k = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                sumerr = max(sumerr, abs(liq%alpha(i,j,k) + gas%alpha(i,j,k) &
                         + sol%alpha_s(i,j,k) + slag%alpha_sl(i,j,k) - 1.0_dp))
            end do
        end do
    end do
    if (sumerr > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL sum alpha /= 1: ', sumerr
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_noflow_mass'
    else
        print '(A)', ' FAIL test_noflow_mass'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    subroutine totals(Mt, Et)
        real(dp), intent(out) :: Mt, Et
        integer :: ii, jj, kk
        Mt = 0.0_dp; Et = 0.0_dp
        do kk = 1, mesh%nz
            do jj = 1, mesh%ntheta
                do ii = 1, mesh%nr
                    if (mesh%cell_type(ii,jj,kk) == 0) cycle
                    Mt = Mt + liq%alpha(ii,jj,kk) * liq%rho(ii,jj,kk) * mesh%vol(ii,jj,kk) &
                         + sol%m_s(ii,jj,kk)
                    Et = Et + liq%alpha(ii,jj,kk) * liq%rho(ii,jj,kk) * mesh%vol(ii,jj,kk) &
                         * (liq%cp(ii,jj,kk) * liq%T(ii,jj,kk) + C0) + sol%E_s(ii,jj,kk)
                end do
            end do
        end do
    end subroutine totals

    subroutine check(name, Ma, Mb, Ea, Eb, sE)
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: Ma, Mb, Ea, Eb, sE
        if (abs(Mb - Ma) > 1.0e-12_dp * Ma) then
            print '(3A,ES12.4,A,ES12.4)', '   FAIL ', name, ': masa de acero dM = ', Mb - Ma, ' de ', Ma
            ok = .false.
        end if
        if (abs(Eb - Ea) > 1.0e-9_dp * max(sE, 1.0_dp)) then
            print '(3A,ES12.4,A,ES12.4)', '   FAIL ', name, ': energia dE = ', Eb - Ea, ' escala ', sE
            ok = .false.
        end if
    end subroutine check

end program test_noflow_mass
