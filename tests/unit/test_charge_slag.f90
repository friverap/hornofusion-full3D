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
!
! Caso 3 (Plan I, I2): con la escoria CONDENSADA (slag_in_volume) la cesta 2
! ATRAVIESA la capa: se apoya en el tope del ACERO bajo una capa gruesa de
! escoria llena (3 celdas) y el reordenamiento de inicio de paso
! (slag_condensed_sort) sube la escoria desplazada: masa y energia de la
! escoria exactas, Sigma alpha <= 1 y la base de la chatarra en el tope del
! acero (antes quedaba flotando sobre la escoria, aislada del baño).
!===============================================================================
program test_charge_slag
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_input_profiles, only: read_charge_recipe
    use mod_slag_3d, only: slag_condensed_sort
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: al(:,:,:), asl(:,:,:), ms0(:,:,:)
    real(dp) :: over, m_added, z_slag_top, z_scrap_low, msl0, esl0, z_slag_hi
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
    allocate(ms0, mold=sol%m_s); ms0 = sol%m_s
    call charge_scrap(sol, gas, mesh, cfg, 2, sh)
    ! (auditoria 12, A12-T2) la chatarra NUEVA se localiza en TODO el dominio
    ! (donde aumento m_s), no solo por encima del lecho: una carga dentro del
    ! lecho tambien debe fallar
    z_scrap_low = huge(1.0_dp); over = 0.0_dp; m_added = 0.0_dp
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                if (sol%m_s(i,j,k) > ms0(i,j,k) * (1.0_dp + 1.0e-12_dp) + 1.0e-12_dp) &
                    z_scrap_low = min(z_scrap_low, mesh%zf(k-1))
                m_added = m_added + sol%m_s(i,j,k) - ms0(i,j,k)
                over = max(over, sol%alpha_s(i,j,k) + al(i,j,k) + asl(i,j,k) - 1.0_dp)
            end do
        end do
    end do
    print '(A,F9.3,A,F6.3,A,F6.3,A,ES10.3)', '   lecho sobre el bano: masa cargada ', m_added, ' kg  base de la carga ', &
        z_scrap_low, ' m  cima del lecho ', mesh%zf(ks + 4), '  sobrellenado ', over
    if (abs(m_added - 3000.0_dp) > 1.0e-9_dp * 3000.0_dp .or. z_scrap_low < mesh%zf(ks + 4) - 1.0e-12_dp &
        .or. over > 1.0e-12_dp) then
        print '(A)', '   FAIL con lecho de la cesta 1 sobre el bano, la carga no va sobre el lecho'
        ok = .false.
    end if

    ! caso 3 (Plan I, I2): escoria condensada gruesa sobre el baño
    cfg%solve_slag = .true.; cfg%slag_in_volume = .true.
    cfg%solve_flow = .true.; cfg%solve_multiphase = .true.; cfg%mixture_model = .false.
    if (.not. slag_condensed_on(cfg)) then
        print '(A)', '   FAIL caso 3: la escoria condensada no esta activa'
        ok = .false.
    end if
    sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp; sol%m_C = 0.0_dp
    liq%alpha = al; liq%T = 1850.0_dp
    slag%alpha_sl = 0.0_dp; slag%m_sl = 0.0_dp; slag%E_sl = 0.0_dp; slag%m_X = 0.0_dp
    do k = ks + 1, ks + 3
        slag%alpha_sl(:,:,k) = 1.0_dp
    end do
    where (mesh%cell_type == 0) slag%alpha_sl = 0.0_dp
    slag%m_sl = slag%alpha_sl * cfg%rho_slag * mesh%vol
    slag%m_X(:,:,:,SL_CAO) = 0.5_dp * slag%m_sl
    slag%T_sl = 1850.0_dp
    slag%E_sl = slag%m_sl * cfg%cp_slag * 1850.0_dp
    gas%alpha = max(0.0_dp, 1.0_dp - liq%alpha - slag%alpha_sl)
    where (mesh%cell_type == 0) gas%alpha = 0.0_dp
    msl0 = sum(slag%m_sl(1:nr,1:nth,1:nz)); esl0 = sum(slag%E_sl(1:nr,1:nth,1:nz))
    call charge_scrap(sol, gas, mesh, cfg, 2, sh, slag)
    call slag_condensed_sort(slag, liq, gas, sol, mesh, cfg, sh)
    over = 0.0_dp; m_added = 0.0_dp; z_scrap_low = huge(1.0_dp); z_slag_hi = 0.0_dp
    do k = 1, nz
        do j = 1, nth
            do i = 1, nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                over = max(over, sol%alpha_s(i,j,k) + liq%alpha(i,j,k) + slag%alpha_sl(i,j,k) - 1.0_dp)
                m_added = m_added + sol%m_s(i,j,k)
                if (sol%m_s(i,j,k) > 0.0_dp) z_scrap_low = min(z_scrap_low, mesh%zf(k-1))
                if (slag%alpha_sl(i,j,k) >= ALPHA_CUTOFF) z_slag_hi = max(z_slag_hi, mesh%zf(k))
            end do
        end do
    end do
    print '(A,F9.3,A,F6.3,A,F6.3,A,F6.3,A,ES10.3)', '   escoria condensada: masa cargada ', m_added, &
        ' kg  base de la chatarra ', z_scrap_low, ' m  tope del acero ', mesh%zf(ks), &
        '  cima de la escoria ', z_slag_hi, '  sobrellenado ', over
    if (abs(m_added - 3000.0_dp) > 1.0e-9_dp * 3000.0_dp) then
        print '(A)', '   FAIL caso 3: la masa cargada no es la de la receta'
        ok = .false.
    end if
    if (abs(z_scrap_low - mesh%zf(ks)) > 1.0e-12_dp) then
        print '(A)', '   FAIL caso 3: la chatarra no se apoya en el tope del acero (no atraviesa la escoria)'
        ok = .false.
    end if
    if (.not. z_slag_hi > mesh%zf(ks + 3) + 1.0e-12_dp) then
        print '(A)', '   FAIL caso 3: la escoria desplazada no subio'
        ok = .false.
    end if
    if (over > 1.0e-12_dp) then
        print '(A)', '   FAIL caso 3: Sigma alpha > 1 tras el reordenamiento'
        ok = .false.
    end if
    if (abs(sum(slag%m_sl(1:nr,1:nth,1:nz)) - msl0) > 1.0e-12_dp * msl0 .or. &
        abs(sum(slag%E_sl(1:nr,1:nth,1:nz)) - esl0) > 1.0e-12_dp * esl0) then
        print '(A,2ES12.4)', '   FAIL caso 3: masa/energia de escoria no conservadas: ', &
            sum(slag%m_sl(1:nr,1:nth,1:nz)) - msl0, sum(slag%E_sl(1:nr,1:nth,1:nz)) - esl0
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_charge_slag (legado: sobre bano y escoria; condensada: atraviesa la escoria)'
    else
        print '(A)', ' FAIL test_charge_slag'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_charge_slag
