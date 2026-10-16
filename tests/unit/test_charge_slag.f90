!===============================================================================
! test_charge_slag.f90 - La carga de la cesta 2 NO sobrellena celdas con bano
! o escoria (auditoria 11, A11-1).
!
! charge_scrap colocaba la chatarra de la cesta 2 sobre la cima del LECHO (o
! H_bowl) aunque hubiera bano encima, restando solo gas y confiando en que el
! derrame del transporte de alpha subiera el liquido desplazado. Bajo una capa
! de escoria llena el derrame no pasa y el exceso iba al clip auditado
! (replica de produccion: 12 t en el paso de carga). Ahora la cesta 2 se
! coloca sobre la cima del bano y la escoria (contenido no gas y no solido
! >= ALPHA_LIQ_CONT): la chatarra solo desplaza gas.
!
! Caso (singleton): bano lleno hasta z ~1.1 m (por encima de H_bowl 0.6 m),
! una capa de escoria encima (alpha_sl 0.6), sin chatarra; cesta 2 de 3 t a
! vfrac 0.5. Exige: ninguna celda con alpha_s + liquido + escoria > 1, masa
! cargada exacta, y toda la chatarra por encima de la escoria.
!===============================================================================
program test_charge_slag
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
    real(dp), allocatable :: al(:,:,:), asl(:,:,:)
    real(dp) :: over, m_added, z_slag_top, z_scrap_low
    integer  :: i, j, k, nr, nth, nz, iu, ks
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 32
    open(newunit=iu, file='test_charge_slag_tmp.dat', status='replace')
    write(iu,'(A)') '1  1000.0  0.50'
    write(iu,'(A)') '2  3000.0  0.50'
    close(iu)
    call read_charge_recipe(cfg, 'test_charge_slag_tmp.dat')
    open(newunit=iu, file='test_charge_slag_tmp.dat', status='old')
    close(iu, status='delete')

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    ok = .true.

    allocate(al, asl, mold=gas%alpha)
    al = 0.0_dp; asl = 0.0_dp
    ks = 0
    do k = 1, nz
        if (mesh%z(k) < 1.1_dp) then
            al(:,:,k) = 1.0_dp
            ks = k
        end if
    end do
    asl(:,:,ks + 1) = 0.6_dp
    z_slag_top = mesh%zf(ks + 1)
    sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%m_C = 0.0_dp
    gas%alpha = 1.0_dp - al - asl
    where (mesh%cell_type == 0)
        al = 0.0_dp; asl = 0.0_dp; gas%alpha = 0.0_dp
    end where

    call charge_scrap(sol, gas, mesh, cfg, 2, sh)

    over = 0.0_dp; m_added = 0.0_dp; z_scrap_low = huge(1.0_dp)
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                over = max(over, sol%alpha_s(i,j,k) + al(i,j,k) + asl(i,j,k) - 1.0_dp)
                m_added = m_added + sol%m_s(i,j,k)
                if (sol%m_s(i,j,k) > 0.0_dp) z_scrap_low = min(z_scrap_low, mesh%zf(k-1))
            end do
        end do
    end do
    print '(A,ES10.3,A,F9.3,A,F6.3,A,F6.3)', '   sobrellenado max ', over, '  masa cargada ', m_added, &
        ' kg  base de la chatarra ', z_scrap_low, ' m  cima de la escoria ', z_slag_top
    if (over > 1.0e-12_dp) then
        print '(A)', '   FAIL la carga sobrellena celdas con bano/escoria (A11-1)'
        ok = .false.
    end if
    if (abs(m_added - 3000.0_dp) > 1.0e-9_dp * 3000.0_dp) then
        print '(A)', '   FAIL la masa cargada no es la de la receta'
        ok = .false.
    end if
    if (z_scrap_low < z_slag_top - 1.0e-12_dp) then
        print '(A)', '   FAIL chatarra por debajo de la cima de la escoria'
        ok = .false.
    end if
    ! caso 2: un lecho de la cesta 1 por ENCIMA del bano (capas ks+2..ks+4,
    ! alpha_s 0.5): manda la cima del solido, la cesta 2 va sobre el lecho
    sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%m_C = 0.0_dp
    do k = ks + 2, ks + 4
        sol%alpha_s(:,:,k) = 0.5_dp
        sol%m_s(:,:,k) = 0.5_dp * cfg%rho_steel * mesh%vol(:,:,k)
        sol%E_s(:,:,k) = sol%m_s(:,:,k) * 1.0e5_dp
    end do
    gas%alpha = 1.0_dp - al - asl - sol%alpha_s
    where (mesh%cell_type == 0)
        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; gas%alpha = 0.0_dp
    end where
    m_added = sum(sol%m_s(1:nr,1:nth,1:nz))
    call charge_scrap(sol, gas, mesh, cfg, 2, sh)
    z_scrap_low = huge(1.0_dp); over = 0.0_dp
    do k = ks + 5, nz
        do j = 1, nth
            do i = 1, nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                if (sol%m_s(i,j,k) > 0.0_dp) z_scrap_low = min(z_scrap_low, mesh%zf(k-1))
            end do
        end do
    end do
    m_added = sum(sol%m_s(1:nr,1:nth,1:nz)) - m_added
    print '(A,F9.3,A,F6.3,A,F6.3)', '   lecho sobre el bano: masa cargada ', m_added, ' kg  base de la carga ', &
        z_scrap_low, ' m  cima del lecho ', mesh%zf(ks + 4)
    if (abs(m_added - 3000.0_dp) > 1.0e-9_dp * 3000.0_dp .or. z_scrap_low < mesh%zf(ks + 4) - 1.0e-12_dp) then
        print '(A)', '   FAIL con lecho de la cesta 1 sobre el bano, la carga no va sobre el lecho'
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_charge_slag (la cesta 2 se apoya sobre bano y escoria; solo desplaza gas)'
    else
        print '(A)', ' FAIL test_charge_slag'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_charge_slag
