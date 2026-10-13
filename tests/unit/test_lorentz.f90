!===============================================================================
! test_lorentz.f90 - Fuerza de Lorentz del baño (auditoria 12-oct-2026, M11)
!
! Fuente puntual de corriente (Shercliff 1970, Sozou 1971). Un electrodo,
! baño continuo en todo el dominio salvo una celda con niebla:
!   1. bajo el pie del arco la fuerza apunta HACIA el eje del electrodo y
!      HACIA ABAJO (antes: hacia afuera, signo invertido)
!   2. valor analitico F = J B en una celda
!   3. cero sobre el pie del arco y en liquido disperso (alpha_l < 0.3)
!   4. rotacional no nulo: a la misma distancia al eje, la fuerza horizontal
!      cambia con la profundidad (antes era independiente de z: un gradiente)
!===============================================================================
program test_lorentz
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_lorentz_3d, only: compute_lorentz_force
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    type(electrode_t) :: elec(1)
    real(dp), parameter :: I_EL = 50.0e3_dp
    integer  :: i, j, k, ka, kb, kfog, ic
    real(dp) :: z_att, xi, eta, rl, dz, rho2, cth, Fref, Frad, Fh1, Fh2, xe, ye
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 12; cfg%ntheta = 24; cfg%nz = 16
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    ok = .true.

    elec(1)%theta_pos = mesh%theta(1)
    z_att = mesh%zf(mesh%nz / 2)
    elec(1)%arc_length = 0.2_dp
    elec(1)%z_tip = z_att + elec(1)%arc_length
    liq%alpha = 1.0_dp
    kfog = 2
    liq%alpha(:, :, kfog) = 0.1_dp       ! niebla: sin fuerza
    call compute_lorentz_force(elec, liq%alpha, sh, mesh, cfg, I_EL, 1)

    xe = cfg%R_pcd * cos(elec(1)%theta_pos); ye = cfg%R_pcd * sin(elec(1)%theta_pos)
    ! celda de prueba: mismo theta que el electrodo, radio mayor que R_pcd
    j = 1
    ic = 0
    do i = 1, mesh%nr
        if (mesh%r(i) > cfg%R_pcd + 0.2_dp) then; ic = i; exit; end if
    end do
    ka = mesh%nz / 2 - 2; kb = 4
    if (ic == 0 .or. mesh%cell_type(ic,j,ka) == 0 .or. mesh%cell_type(ic,j,kb) == 0) then
        print '(A)', '   FAIL configuracion: celda de prueba fuera del dominio'
        stop 1
    end if

    ! 1. direccion: radio mayor que el electrodo -> F_r < 0 (hacia el eje del
    !    electrodo), F_z < 0
    if (.not. (sh%F_lorentz_r(ic,j,ka) < 0.0_dp .and. sh%F_lorentz_z(ic,j,ka) < 0.0_dp)) then
        print '(A,2ES12.4)', '   FAIL caso 1: F_r, F_z = ', sh%F_lorentz_r(ic,j,ka), sh%F_lorentz_z(ic,j,ka)
        ok = .false.
    end if

    ! 2. valor analitico (componente horizontal)
    xi = mesh%r(ic) * cos(mesh%theta(j)) - xe; eta = mesh%r(ic) * sin(mesh%theta(j)) - ye
    rl = sqrt(xi**2 + eta**2); dz = z_att - mesh%z(ka)
    rho2 = rl**2 + dz**2 + cfg%R_elec**2; cth = dz / sqrt(rho2)
    Fref = I_EL / (TWO_PI * rho2) * MU_0 * I_EL * (1.0_dp - cth) / (TWO_PI * rl) * cth
    Frad = sqrt(sh%F_lorentz_r(ic,j,ka)**2 + sh%F_lorentz_th(ic,j,ka)**2)
    if (abs(Frad - Fref) > 1.0e-10_dp * Fref) then
        print '(A,2ES14.6)', '   FAIL caso 2: |F_h| vs analitico = ', Frad, Fref
        ok = .false.
    end if

    ! 3. cero sobre el pie del arco y en la niebla
    do k = 1, mesh%nz
        if (mesh%z(k) < z_att .and. k /= kfog) cycle
        if (maxval(abs(sh%F_lorentz_r(1:mesh%nr,1:mesh%ntheta,k))) > 0.0_dp .or. &
            maxval(abs(sh%F_lorentz_z(1:mesh%nr,1:mesh%ntheta,k))) > 0.0_dp) then
            print '(A,I3)', '   FAIL caso 3: fuerza no nula en k = ', k
            ok = .false.
        end if
    end do

    ! 4. rotacional: |F_h| cambia con la profundidad a r_loc fijo
    Fh1 = abs(sh%F_lorentz_r(ic,j,ka)); Fh2 = abs(sh%F_lorentz_r(ic,j,kb))
    if (abs(Fh1 - Fh2) < 1.0e-3_dp * max(Fh1, Fh2)) then
        print '(A,2ES12.4)', '   FAIL caso 4: fuerza horizontal independiente de z: ', Fh1, Fh2
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_lorentz (pinch hacia el eje y abajo, analitico, solo baño, rotacional)'
    else
        stop 1
    end if
end program test_lorentz
