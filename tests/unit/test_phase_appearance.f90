!===============================================================================
! test_phase_appearance.f90 - Forma exacta de Patankar en la energía (sep-2026)
!
! Motivo: B1 v6 no formaba baño (10 kg de líquido a los 442 s con 9646 kg
! fundidos): el transitorio de la energía usaba alpha^{n+1}, así que el
! fundido que llegaba a una celda vacía figuraba como masa preexistente a
! T_old (300 K inicial) y salía a (300+T_in)/2 -> re-solidificaba. Además
! el sumidero de re-solidificación añadía aP += |mdot|*cp sin contraparte
! en Su (enfriamiento espurio).
!
! Casos (malla pequeña, singleton MPI, sin flujo ni fuentes volumétricas):
!   1. Aparición de fase: alpha_old=0, alpha_new=mdot*dt/(rho*V), T_old=300,
!      T_src=1900, vecinos a 1900 -> T = 1900 EXACTO (antes: 1100).
!   2. Sumidero sin latente (T_old=1300 < 1334 K => e_l <= e_s(T_sol)):
!      campo uniforme, mdot<0 en una celda -> T = 1300 EXACTO en todas
!      (antes: la celda del sumidero se enfriaba).
!   3. Losa líquida a 1700 K rodeada de celdas vacías con T rancia 300 K,
!      sin flujo -> la losa NO se enfría (conductancia con alpha de cara
!      armónica; antes alpha_P sola conducía al vacío).
!   4. Idem con velocidad vertical uniforme -> tampoco (flujo donor-cell:
!      la vecina vacía no entrega masa; antes ½·alpha_P·rho·u a 300 K).
!===============================================================================
program test_phase_appearance
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_energy_3d, only: solve_energy_3d
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: T_old(:,:,:), a_old(:,:,:), zero3(:,:,:)
    real(dp) :: res, vol, err
    integer  :: i, j, k, nbad
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 6
    cfg%dt = 0.01_dp
    cfg%h_wall = 0.0_dp

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh)
    call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)

    allocate(T_old, a_old, zero3, mold=liq%T)
    zero3 = 0.0_dp
    ok = .true.

    ! Estado sin flujo ni fuentes
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
    sh%S_arc = 0.0_dp; sh%S_chem = 0.0_dp; sh%kappa_f = 0.0_dp; sh%G_rad = 0.0_dp
    sol%mdot = 0.0_dp

    ! ---- caso 1: aparición de fase ----
    liq%alpha = 0.0_dp; a_old = 0.0_dp
    T_old = 300.0_dp; liq%T = 1900.0_dp; sol%T_s = 1900.0_dp
    vol = mesh%vol(3,4,3)
    liq%alpha(3,4,3) = 0.01_dp
    sol%mdot(3,4,3)  = 0.01_dp * liq%rho(3,4,3) * vol / cfg%dt
    call solve_energy_3d(liq, T_old, sh, mesh, cfg, liq%alpha, zero3, a_old, &
                         sol%mdot, sol%T_s, .false., res)
    ! tolerancia: el TDMA por barridos converge a ~1e-7 relativo (el
    ! esquema anterior daba 1100 K)
    err = abs(liq%T(3,4,3) - 1900.0_dp)
    if (err > 1.0e-2_dp) then
        print '(A,F12.5)', '   FAIL caso 1: fase nueva no entra a T_src: T = ', &
            liq%T(3,4,3)
        ok = .false.
    end if

    ! ---- caso 2: sumidero sin latente ----
    liq%alpha = 0.5_dp; a_old = 0.5_dp
    T_old = 1300.0_dp; liq%T = 1300.0_dp; sol%T_s = 1300.0_dp
    sol%mdot = 0.0_dp
    sol%mdot(4,4,3) = -0.1_dp * liq%rho(4,4,3) * mesh%vol(4,4,3) / cfg%dt
    call solve_energy_3d(liq, T_old, sh, mesh, cfg, liq%alpha, zero3, a_old, &
                         sol%mdot, sol%T_s, .false., res)
    nbad = 0
    do k = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                if (abs(liq%T(i,j,k) - 1300.0_dp) > 1.0e-2_dp) nbad = nbad + 1
            end do
        end do
    end do
    if (nbad > 0) then
        print '(A,I0,A,F12.5)', '   FAIL caso 2: ', nbad, &
            ' celdas se apartan de 1300 K; sumidero T = ', liq%T(4,4,3)
        ok = .false.
    end if

    ! ---- caso 3: sin difusión hacia vecinas vacías ----
    ! losa líquida k=3 a 1700 K; el resto vacío con T rancia 300 K
    liq%alpha = 0.0_dp; a_old = 0.0_dp; sol%mdot = 0.0_dp
    liq%alpha(:,:,3) = 0.5_dp; a_old(:,:,3) = 0.5_dp
    T_old = 300.0_dp; T_old(:,:,3) = 1700.0_dp; liq%T = T_old
    call solve_energy_3d(liq, T_old, sh, mesh, cfg, liq%alpha, zero3, a_old, &
                         sol%mdot, sol%T_s, .false., res)
    nbad = 0
    do j = 1, mesh%ntheta
        do i = 1, mesh%nr
            if (mesh%cell_type(i,j,3) == 0) cycle
            if (abs(liq%T(i,j,3) - 1700.0_dp) > 1.0e-2_dp) nbad = nbad + 1
        end do
    end do
    if (nbad > 0) then
        print '(A,I0,A,F12.5)', '   FAIL caso 3: ', nbad, &
            ' celdas de la losa se enfriaron por difusion a vecinas vacias; T = ', &
            liq%T(3,4,3)
        ok = .false.
    end if

    ! ---- caso 4: sin masa fantasma por convección desde vecina vacía ----
    ! misma losa, velocidad vertical uniforme: la cara inferior de la losa
    ! da a una celda vacía; con interpolación simétrica de alpha entraba
    ! ½·alpha_P·rho·u de "líquido" a 300 K
    liq%uz = 0.05_dp
    liq%T = T_old
    call solve_energy_3d(liq, T_old, sh, mesh, cfg, liq%alpha, zero3, a_old, &
                         sol%mdot, sol%T_s, .false., res)
    nbad = 0
    do j = 1, mesh%ntheta
        do i = 1, mesh%nr
            if (mesh%cell_type(i,j,3) == 0) cycle
            if (abs(liq%T(i,j,3) - 1700.0_dp) > 1.0e-2_dp) nbad = nbad + 1
        end do
    end do
    if (nbad > 0) then
        print '(A,I0,A,F12.5)', '   FAIL caso 4: ', nbad, &
            ' celdas de la losa recibieron masa fantasma fria; T = ', liq%T(3,4,3)
        ok = .false.
    end if
    liq%uz = 0.0_dp

    if (ok) then
        print '(A)', ' PASS test_phase_appearance'
    else
        print '(A)', ' FAIL test_phase_appearance'
        stop 1
    end if

    call mpi_finalize_topology(mesh%topo)
end program test_phase_appearance
