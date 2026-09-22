!===============================================================================
! test_settling.f90 - Sedimentacion del liquido disperso (sep-2026, opcion A)
!
! Motivo: en B1 v11 un tercio del "liquido" (3.6 t) era niebla a exactamente
! alpha_l = ALPHA_FLOW_CUTOFF suspendida en el freeboard: bajo el umbral la
! velocidad del liquido era 0 y la gravedad no actuaba. Ahora el liquido
! disperso se transporta con la velocidad del gas mas la terminal de
! sedimentacion (deslizamiento algebraico, Manninen et al. 1996).
!
! Casos (singleton MPI, gas en reposo):
!   1. settling_velocity: regimen de Newton (Re > 1000) reproduce
!      sqrt(4 g d drho / (3*0.44*rho_g)) a 1e-12; d=0 -> 0.
!   2. Niebla alpha_l = 0.005 en la capa k = nz-1 sobre celdas vacias: tras
!      N pasos toda la masa esta en k = 1 (fondo), masa EXACTA a 1e-12,
!      y el centro de masa baja a ~u_t (dentro del 30 %, discretizacion
!      donor-cell) mientras cae.
!   3. Con d_droplet = 0 la niebla no se mueve (regresion del
!      comportamiento anterior, para comparar corridas).
!===============================================================================
program test_settling
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_continuity, only: solve_volume_fraction
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: a_old(:,:,:)
    real(dp) :: m0, m1, err, u_t, u_ref, zc0, zc1, v_meas
    integer  :: nr, nth, nz, n, nsteps, i, j, k, kb
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 12
    cfg%dt = 0.002_dp

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    allocate(a_old, mold=liq%alpha)
    ok = .true.

    ! ---- caso 1: velocidad terminal ----
    ! mu bajo para caer en regimen de Newton (Re > 1000)
    u_t = settling_velocity(2.0e-3_dp, 7500.0_dp, 0.3_dp, 1.0e-5_dp)
    u_ref = sqrt(4.0_dp * GRAVITY * 2.0e-3_dp * (7500.0_dp - 0.3_dp) / (3.0_dp * 0.44_dp * 0.3_dp))
    if (0.3_dp * u_t * 2.0e-3_dp / 1.0e-5_dp < 1000.0_dp) then
        print '(A)', '   FAIL caso 1: el caso de prueba no esta en regimen de Newton'
        ok = .false.
    else if (abs(u_t - u_ref) > 1.0e-12_dp * u_ref) then
        print '(A,2F10.4)', '   FAIL caso 1: u_t /= Newton: ', u_t, u_ref
        ok = .false.
    end if
    if (abs(settling_velocity(0.0_dp, 7500.0_dp, 0.3_dp, 5.0e-5_dp)) > 0.0_dp) then
        print '(A)', '   FAIL caso 1: d=0 debe dar u_t=0'
        ok = .false.
    end if

    ! ---- caso 2: la niebla cae y se acumula en el fondo ----
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
    gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
    sol%mdot = 0.0_dp; sol%alpha_s = 0.0_dp; slag%alpha_sl = 0.0_dp
    liq%alpha = 0.0_dp
    liq%alpha(:, :, nz-1) = 0.005_dp
    m0 = liquid_mass()
    zc0 = zcm()
    u_t = settling_velocity(cfg%d_droplet, liq%rho(3,4,3), gas%rho(3,4,3), gas%mu(3,4,3))
    nsteps = 10
    do n = 1, nsteps
        a_old = liq%alpha
        call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    end do
    zc1 = zcm()
    v_meas = (zc0 - zc1) / (nsteps * cfg%dt)
    if (abs(v_meas - u_t) > 0.3_dp * u_t) then
        print '(A,2F10.4)', '   FAIL caso 2: velocidad de caida medida /= u_t: ', v_meas, u_t
        ok = .false.
    end if
    ! seguir hasta que todo este en el fondo (altura ~4.5 m a ~35 m/s: < 0.2 s)
    do n = 1, 400
        a_old = liq%alpha
        call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    end do
    m1 = liquid_mass()
    err = abs(m1 - m0) / m0
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL caso 2: masa no conservada al sedimentar, err = ', err
        ok = .false.
    end if
    ! todo debe estar en la celda mas baja ACTIVA de cada columna (la cuba
    ! tiene fondo escalonado: cell_type = 0 en las esquinas r > R_bowl)
    err = 0.0_dp
    do j = 1, nth
        do i = 1, nr
            kb = 0
            do k = 1, nz
                if (mesh%cell_type(i,j,k) /= 0) then
                    kb = k; exit
                end if
            end do
            if (kb > 0 .and. kb < nz) err = err + sum(liq%alpha(i,j,kb+1:nz))
        end do
    end do
    ! cola exponencial del donor-cell (frente a media velocidad): 1e-8 abs
    if (err > 1.0e-8_dp) then
        print '(A,ES10.3)', '   FAIL caso 2: queda liquido por encima del fondo: ', err
        ok = .false.
    end if

    ! ---- caso 3: d_droplet = 0 -> la niebla no se mueve ----
    cfg%d_droplet = 0.0_dp
    liq%alpha = 0.0_dp
    liq%alpha(:, :, nz-1) = 0.005_dp
    a_old = liq%alpha
    call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, a_old, mesh, cfg)
    if (maxval(abs(liq%alpha(1:nr,1:nth,1:nz) - a_old(1:nr,1:nth,1:nz))) > 1.0e-15_dp) then
        print '(A)', '   FAIL caso 3: con d_droplet=0 la niebla se movio'
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_settling'
    else
        print '(A)', ' FAIL test_settling'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains
    function liquid_mass() result(mt)
        real(dp) :: mt
        mt = sum(liq%alpha(1:nr,1:nth,1:nz) * liq%rho(1:nr,1:nth,1:nz) * mesh%vol(1:nr,1:nth,1:nz))
    end function liquid_mass
    function zcm() result(zc)
        real(dp) :: zc, mt
        integer :: k
        zc = 0.0_dp; mt = 0.0_dp
        do k = 1, nz
            zc = zc + mesh%z(k) * sum(liq%alpha(1:nr,1:nth,k) * mesh%vol(1:nr,1:nth,k))
            mt = mt + sum(liq%alpha(1:nr,1:nth,k) * mesh%vol(1:nr,1:nth,k))
        end do
        zc = zc / max(mt, SMALL)
    end function zcm
end program test_settling
