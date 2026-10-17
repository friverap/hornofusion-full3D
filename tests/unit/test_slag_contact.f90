!===============================================================================
! test_slag_contact.f90 - Contacto termico de la escoria CONDENSADA con el gas
! (auditoria 19, regresion de 29fd409). Por columna:
! (1) escoria llena (celda 4, sin gas) bajo la celda TOPE de la escoria
!     (celda 5: escoria 0.6 + gas 0.4) y gas puro encima: la escoria enterrada
!     NO intercambia con el gas de la celda 5 (ya lo hace la escoria de la 5):
!     el gas de la 5 queda entre T_sl y su T inicial (sin sobrepaso) y la
!     energia total (escoria + inventario log del gas + acero) se conserva;
! (2) escoria llena (celda 4, sin gas) bajo gas PURO (celda 5): la escoria
!     tope intercambia por su cara superior (el gas se enfria, la escoria se
!     calienta) y la energia se conserva.
!===============================================================================
program test_slag_contact
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_audit, only: gas_inventory_cell
    use mod_slag_3d, only: update_slag
    implicit none
    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp) :: E0, E1, Tg5_0, Tsl_hot, Es4_0
    integer  :: i, j, nr, nth, nz
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 3; cfg%ntheta = 4; cfg%nz = 10; cfg%dt = 0.01_dp
    cfg%solve_slag = .true.; cfg%slag_in_volume = .true.
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    ok = .true.
    Tsl_hot = 1850.0_dp; Tg5_0 = 2600.0_dp

    ! ---- (1) escoria enterrada bajo la celda tope con gas ----
    call setup(0.6_dp)
    E0 = total_energy()
    Es4_0 = sum(slag%E_sl(1:nr,1:nth,4))
    call update_slag(slag, liq, gas, sol, mesh, cfg, cfg%dt, sh)
    E1 = total_energy()
    ! la escoria enterrada (todo a T_sl salvo el gas de la 5) no recibe calor
    if (abs(sum(slag%E_sl(1:nr,1:nth,4)) - Es4_0) > 1.0e-10_dp * Es4_0) then
        print '(A,ES12.4)', '   FAIL caso 1: la escoria enterrada intercambio con el gas de arriba: dE = ', &
            sum(slag%E_sl(1:nr,1:nth,4)) - Es4_0
        ok = .false.
    end if
    do j = 1, nth
        do i = 1, nr
            if (mesh%cell_type(i,j,5) == 0) cycle
            if (gas%T(i,j,5) < Tsl_hot - 1.0e-6_dp .or. gas%T(i,j,5) > Tg5_0 + 1.0e-6_dp) then
                print '(A,F10.3)', '   FAIL caso 1: T del gas fuera de [T_sl, T_g0] (sobrepaso): ', gas%T(i,j,5)
                ok = .false.; exit
            end if
        end do
        if (.not. ok) exit
    end do
    if (abs(E1 - E0) > 1.0e-9_dp * abs(E0)) then
        print '(A,2ES16.8)', '   FAIL caso 1: energia no conservada: ', E0, E1
        ok = .false.
    end if

    ! ---- (2) escoria tope bajo gas puro ----
    call setup(0.0_dp)
    E0 = total_energy()
    call update_slag(slag, liq, gas, sol, mesh, cfg, cfg%dt, sh)
    E1 = total_energy()
    do j = 1, nth
        do i = 1, nr
            if (mesh%cell_type(i,j,5) == 0) cycle
            if (.not. (gas%T(i,j,5) < Tg5_0 - 1.0e-3_dp)) then
                print '(A,F10.3)', '   FAIL caso 2: la escoria tope no intercambio con el gas de arriba: ', gas%T(i,j,5)
                ok = .false.; exit
            end if
        end do
        if (.not. ok) exit
    end do
    if (abs(E1 - E0) > 1.0e-9_dp * abs(E0)) then
        print '(A,2ES16.8)', '   FAIL caso 2: energia no conservada: ', E0, E1
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_slag_contact (escoria enterrada sin contacto con el gas; tope por su cara; energia exacta)'
    else
        print '(A)', ' FAIL test_slag_contact'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
contains
    ! columna: acero 1-3, escoria llena en 4, celda 5 con escoria asl5 + gas,
    ! gas puro encima; todo a T_sl salvo el gas de la 5 (caliente)
    subroutine setup(asl5)
        real(dp), intent(in) :: asl5
        integer :: ii, jj, kk
        liq%alpha = 0.0_dp; slag%alpha_sl = 0.0_dp; slag%m_sl = 0.0_dp; slag%E_sl = 0.0_dp
        slag%m_X = 0.0_dp; slag%alpha_foam = 0.0_dp; sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp
        do kk = 1, nz
            do jj = 1, nth
                do ii = 1, nr
                    if (mesh%cell_type(ii,jj,kk) == 0) cycle
                    if (kk <= 3) liq%alpha(ii,jj,kk) = 1.0_dp
                    if (kk == 4) slag%alpha_sl(ii,jj,kk) = 1.0_dp
                    if (kk == 5) slag%alpha_sl(ii,jj,kk) = asl5
                    slag%m_sl(ii,jj,kk) = slag%alpha_sl(ii,jj,kk) * cfg%rho_slag * mesh%vol(ii,jj,kk)
                    slag%E_sl(ii,jj,kk) = slag%m_sl(ii,jj,kk) * cfg%cp_slag * Tsl_hot
                    slag%T_sl(ii,jj,kk) = Tsl_hot
                    liq%T(ii,jj,kk) = Tsl_hot
                    gas%T(ii,jj,kk) = Tsl_hot
                    if (kk == 5) gas%T(ii,jj,kk) = Tg5_0
                end do
            end do
        end do
        gas%alpha = max(0.0_dp, 1.0_dp - liq%alpha - slag%alpha_sl)
        where (mesh%cell_type == 0) gas%alpha = 0.0_dp
        call mpi_exchange_halos_3d(liq%alpha, mesh%topo); call mpi_exchange_halos_3d(gas%alpha, mesh%topo)
        call mpi_exchange_halos_3d(gas%T, mesh%topo); call mpi_exchange_halos_3d(liq%T, mesh%topo)
        call slag_exchange_halos(slag, mesh)
    end subroutine setup

    real(dp) function total_energy() result(e)
        integer :: ii, jj, kk
        e = 0.0_dp
        do kk = 1, nz
            do jj = 1, nth
                do ii = 1, nr
                    if (mesh%cell_type(ii,jj,kk) == 0) cycle
                    e = e + slag%E_sl(ii,jj,kk) &
                          + liq%alpha(ii,jj,kk) * liq%rho(ii,jj,kk) * liq%cp(ii,jj,kk) * liq%T(ii,jj,kk) * mesh%vol(ii,jj,kk) &
                          + gas_inventory_cell(gas%alpha(ii,jj,kk), gas%T(ii,jj,kk), sh%p(ii,jj,kk), &
                                               gas%cp(ii,jj,kk), mesh%vol(ii,jj,kk), cfg)
                end do
            end do
        end do
    end function total_energy
end program test_slag_contact
