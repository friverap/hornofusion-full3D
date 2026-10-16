!===============================================================================
! test_charge_exact.f90 - charge_scrap termina y coloca la masa EXACTA de la
! receta (auditoria 15, A15-1).
!
! Cuando una capa se agotaba dentro de un nivel, charge_scrap hacia
! take = m/(rho vfrac); m = m - take*rho*vfrac: para algunos pares (m, rho
! vfrac) el residuo sale +1 ulp y se repite (factor ~1e-16 por vuelta) hasta un
! subnormal en el que take redondea a 0 y el do while no termina (cuelgue sin
! mensaje; ~3 % de las masas a rho 7500, vfrac 0.47). Caso (singleton): cesta 1
! de UNA capa de 1004.836 kg a vfrac 0.47 con rho_steel 7500, el par medido que
! colgaba. Exige que termine y que la masa colocada sea la de la receta.
!===============================================================================
program test_charge_exact
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_input_profiles, only: read_charge_recipe
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp) :: m_added
    integer  :: iu
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 16
    cfg%rho_steel = 7500.0_dp
    open(newunit=iu, file='test_charge_exact_tmp.dat', status='replace')
    write(iu,'(A)') '1  1004.836  0.47'
    close(iu)
    call read_charge_recipe(cfg, 'test_charge_exact_tmp.dat')
    open(newunit=iu, file='test_charge_exact_tmp.dat', status='old')
    close(iu, status='delete')

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    ok = .true.

    sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%m_C = 0.0_dp
    gas%alpha = 1.0_dp
    where (mesh%cell_type == 0) gas%alpha = 0.0_dp
    call charge_scrap(sol, gas, mesh, cfg, 1, sh)

    m_added = sum(sol%m_s(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz), &
                  mask=(mesh%cell_type(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz) == 1))
    print '(A,F12.6,A)', '   masa cargada ', m_added, ' kg (receta 1004.836)'
    if (abs(m_added - 1004.836_dp) > 1.0e-12_dp * 1004.836_dp) then
        print '(A)', '   FAIL la masa cargada no es la de la receta'
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_charge_exact (termina; masa de la receta exacta)'
    else
        print '(A)', ' FAIL test_charge_exact'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_charge_exact
