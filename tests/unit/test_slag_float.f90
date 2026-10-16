!===============================================================================
! test_slag_float.f90 - La escoria FLOTA SOBRE EL BANO aunque haya chatarra
! encima (oct-2026, dirigida del modelo de escoria M4).
!
! slag_buoyancy apoyaba la escoria en la celda mas alta con bano O lecho: con
! la cesta 2 cargada sobre bano con escoria la subia de golpe a la cima de la
! carga nueva (metros). La escoria es liquida: flota sobre el bano y se
! infiltra en los poros de la chatarra a ese nivel; solo sin bano se apoya en
! la cima del lecho.
! Caso (singleton): bano lleno en z < 1.1 m, 3 t de escoria y un lecho SECO
! (alpha_s 0.5) desde la cima del bano hasta 2.5 m. Exige: masa de escoria
! exacta, toda la escoria por debajo de z_bano + 0.5 m (sin escoria en la
! cima del lecho) y sum alpha <= 1.
! Caso 2: sin bano (lecho seco solo): la escoria se apoya en la cima del lecho.
!===============================================================================
program test_slag_float
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_slag_3d, only: slag_buoyancy
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp) :: m0, m1, z_hi, z_bath, z_bed, over
    integer  :: i, j, k, nr, nth, nz
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 32
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    ok = .true.

    ! ---- caso 1: bano + lecho seco encima; la escoria entra arriba del todo
    z_bath = 0.0_dp; z_bed = 0.0_dp
    liq%alpha = 0.0_dp; sol%alpha_s = 0.0_dp; slag%m_sl = 0.0_dp; slag%E_sl = 0.0_dp
    slag%m_X = 0.0_dp; slag%alpha_sl = 0.0_dp
    do k = 1, nz
        if (mesh%z(k) < 1.1_dp) then
            liq%alpha(:,:,k) = 1.0_dp; z_bath = mesh%zf(k)
        else if (mesh%z(k) < 2.5_dp) then
            sol%alpha_s(:,:,k) = 0.5_dp; z_bed = mesh%zf(k)
        end if
    end do
    call put_slag_on_top(3000.0_dp)
    call run_and_check(1, z_bath + 0.5_dp)

    ! ---- caso 2: sin bano: la escoria se apoya en la cima del lecho
    liq%alpha = 0.0_dp
    call put_slag_on_top(3000.0_dp)
    call slag_buoyancy(slag, liq, gas, sol, mesh, cfg, sh)
    z_hi = -1.0_dp
    do k = 1, nz
        if (any(slag%m_sl(1:nr,1:nth,k) > 0.0_dp .and. mesh%cell_type(1:nr,1:nth,k) /= 0)) &
            z_hi = max(z_hi, mesh%zf(k))
    end do
    if (z_hi < z_bed) then
        print '(A,2F8.3)', '   FAIL caso 2: sin bano la escoria no se apoya en la cima del lecho: ', z_hi, z_bed
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_slag_float (la escoria flota sobre el bano dentro de los poros; sin bano, sobre el lecho)'
    else
        print '(A)', ' FAIL test_slag_float'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains

    ! toda la escoria en la celda activa mas alta de cada columna (la
    ! posicion de partida no importa: slag_buoyancy rehace la columna)
    subroutine put_slag_on_top(mtot)
        real(dp), intent(in) :: mtot
        real(dp) :: vtop
        integer :: kt
        slag%m_sl = 0.0_dp; slag%E_sl = 0.0_dp; slag%alpha_sl = 0.0_dp
        vtop = 0.0_dp
        do j = 1, nth
            do i = 1, nr
                do kt = nz, 1, -1
                    if (mesh%cell_type(i,j,kt) /= 0) exit
                end do
                if (kt >= 1) vtop = vtop + mesh%vol(i,j,kt)
            end do
        end do
        do j = 1, nth
            do i = 1, nr
                do kt = nz, 1, -1
                    if (mesh%cell_type(i,j,kt) /= 0) exit
                end do
                if (kt < 1) cycle
                slag%m_sl(i,j,kt) = mtot * mesh%vol(i,j,kt) / vtop
                slag%E_sl(i,j,kt) = slag%m_sl(i,j,kt) * cfg%cp_slag * 1800.0_dp
                slag%alpha_sl(i,j,kt) = slag%m_sl(i,j,kt) / (cfg%rho_slag * mesh%vol(i,j,kt))
            end do
        end do
        gas%alpha = max(0.0_dp, 1.0_dp - liq%alpha - sol%alpha_s - slag%alpha_sl)
        where (mesh%cell_type == 0) gas%alpha = 0.0_dp
    end subroutine put_slag_on_top

    subroutine run_and_check(icase, z_max)
        integer, intent(in)  :: icase
        real(dp), intent(in) :: z_max
        m0 = sum(slag%m_sl(1:nr,1:nth,1:nz))
        call slag_buoyancy(slag, liq, gas, sol, mesh, cfg, sh)
        m1 = sum(slag%m_sl(1:nr,1:nth,1:nz))
        z_hi = -1.0_dp; over = 0.0_dp
        do k = 1, nz
            do j = 1, nth
                do i = 1, nr
                    if (mesh%cell_type(i,j,k) == 0) cycle
                    if (slag%m_sl(i,j,k) > 0.0_dp) z_hi = max(z_hi, mesh%zf(k))
                    over = max(over, sol%alpha_s(i,j,k) + liq%alpha(i,j,k) + slag%alpha_sl(i,j,k) - 1.0_dp)
                end do
            end do
        end do
        print '(A,I0,A,F8.3,A,F8.3,A,ES10.3)', '   caso ', icase, ': escoria hasta z = ', z_hi, &
            ' m (max ', z_max, ')  sobrellenado ', over
        if (abs(m1 - m0) > 1.0e-12_dp * m0) then
            print '(A,ES10.3)', '   FAIL masa de escoria no conservada: ', (m1 - m0) / m0
            ok = .false.
        end if
        if (z_hi > z_max) then
            print '(A)', '   FAIL la escoria subio sobre la chatarra en vez de flotar sobre el bano'
            ok = .false.
        end if
        if (over > 1.0e-12_dp) then
            print '(A)', '   FAIL sum alpha > 1'
            ok = .false.
        end if
    end subroutine run_and_check

end program test_slag_float
