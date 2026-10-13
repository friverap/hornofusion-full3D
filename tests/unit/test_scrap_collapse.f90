!===============================================================================
! test_scrap_collapse.f90 - Colapso de chatarra (auditoria 12-oct-2026, A4)
!
! El colapso conservaba la masa pero no el volumen aparente: la celda destino
! quedaba con alpha_s = m/(rho V_dest) y un min(1.0) silencioso. Con la malla
! estirada en z una capa de 0.55 llegaba a ~0.9 o a 1 (B1 a 300 s: 762 celdas
! con alpha_s > 0.9). Casos (singleton MPI, malla estirada stretch_z = 1.5):
!   1. Columna con las capas k = 3..6 a alpha_s = 0.55 y hueco en k = 1..2:
!      la chatarra cae; masa, energia y carbono EXACTOS; ninguna celda supera
!      0.55; alpha_s = m/(rho V) en todas las celdas.
!   2. Igual, con liquido alpha_l = 0.6 en el destino (k = 1): el solido que
!      entra no supera el hueco libre (alpha_s + alpha_l <= 1).
!===============================================================================
program test_scrap_collapse
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_melting_3d, only: solid_enthalpy
    use mod_scrap_collapse, only: apply_scrap_collapse
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp) :: M0, E0, C0, M1, E1, C1, amax, err_a, over
    integer  :: nr, nth, nz, i, j, k, icase
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 12
    cfg%stretch_z = 1.5_dp
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh)
    call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    ok = .true.

    do icase = 1, 2
        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%m_C = 0.0_dp
        sol%layer_id = 0; liq%alpha = 0.0_dp; slag%alpha_sl = 0.0_dp
        do k = 1, nz
            do j = 1, nth
                do i = 1, nr
                    if (mesh%cell_type(i,j,k) == 0) cycle
                    if (k >= 3 .and. k <= 6) then
                        sol%alpha_s(i,j,k) = 0.55_dp
                        sol%m_s(i,j,k) = 0.55_dp * cfg%rho_steel * mesh%vol(i,j,k)
                        sol%T_s(i,j,k) = 300.0_dp + 10.0_dp * k
                        sol%E_s(i,j,k) = sol%m_s(i,j,k) * solid_enthalpy(sol%T_s(i,j,k), cfg)
                        sol%m_C(i,j,k) = 0.005_dp * sol%m_s(i,j,k)
                        sol%layer_id(i,j,k) = 1
                    end if
                    if (icase == 2 .and. k == 1) liq%alpha(i,j,k) = 0.6_dp
                end do
            end do
        end do
        M0 = sum(sol%m_s(1:nr,1:nth,1:nz)); E0 = sum(sol%E_s(1:nr,1:nth,1:nz))
        C0 = sum(sol%m_C(1:nr,1:nth,1:nz))

        call apply_scrap_collapse(sol, liq, slag, mesh, cfg)

        M1 = sum(sol%m_s(1:nr,1:nth,1:nz)); E1 = sum(sol%E_s(1:nr,1:nth,1:nz))
        C1 = sum(sol%m_C(1:nr,1:nth,1:nz))
        amax = maxval(sol%alpha_s(1:nr,1:nth,1:nz))
        err_a = 0.0_dp; over = 0.0_dp
        do k = 1, nz
            do j = 1, nth
                do i = 1, nr
                    if (mesh%cell_type(i,j,k) == 0) cycle
                    err_a = max(err_a, abs(sol%alpha_s(i,j,k) - sol%m_s(i,j,k) / &
                                (cfg%rho_steel * mesh%vol(i,j,k))))
                    over = max(over, sol%alpha_s(i,j,k) + liq%alpha(i,j,k) - 1.0_dp)
                end do
            end do
        end do
        if (abs(M1 - M0) > 1.0e-12_dp * M0 .or. abs(E1 - E0) > 1.0e-12_dp * abs(E0) .or. &
            abs(C1 - C0) > 1.0e-12_dp * C0) then
            print '(A,I2,A,3ES11.3)', '   FAIL caso', icase, ': conservacion (dM,dE,dC rel) = ', &
                (M1-M0)/M0, (E1-E0)/E0, (C1-C0)/C0
            ok = .false.
        end if
        if (amax > 0.55_dp + 1.0e-12_dp) then
            print '(A,I2,A,F8.4)', '   FAIL caso', icase, ': compactacion, max alpha_s = ', amax
            ok = .false.
        end if
        if (err_a > 1.0e-12_dp) then
            print '(A,I2,A,ES10.3)', '   FAIL caso', icase, ': alpha_s /= m/(rho V), err = ', err_a
            ok = .false.
        end if
        if (over > 1.0e-12_dp) then
            print '(A,I2,A,ES10.3)', '   FAIL caso', icase, ': alpha_s + alpha_l - 1 = ', over
            ok = .false.
        end if
        if (sum(sol%m_s(1:nr,1:nth,1:2)) <= 0.0_dp) then
            print '(A,I2,A)', '   FAIL caso', icase, ': la chatarra no cayo al hueco'
            ok = .false.
        end if
    end do

    if (ok) then
        print '(A)', ' PASS test_scrap_collapse (masa/energia/C exactos, sin compactacion, sin sobrellenado)'
    else
        stop 1
    end if
end program test_scrap_collapse
