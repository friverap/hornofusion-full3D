!===============================================================================
! test_arc_surface.f90 - Superficie del bano bajo el arco con malla FINA
! (auditoria 6, M6-5). Malla de produccion en z (80 capas, dz 0.056 m):
! bano lleno hasta la capa K y encima una PELICULA (alpha_l 0.31 en ~1/3 de
! las celdas) cuyo material ponderado supera el 5 % del volumen de su capa
! (criterio viejo: seria la superficie y recibiria P_elec, ~13-20 kg) pero
! no el espesor equivalente ARC_SURF_H. Toda la potencia del arco (sin MC:
! P_rad, P_conv, P_elec) debe ir a la capa K, nada a la pelicula, y el
! presupuesto cierra a 1e-12.
!===============================================================================
program test_arc_surface
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_arc_cassie_mayr, only: distribute_arc_heat
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    type(electrode_t) :: elec(1)
    real(dp), allocatable :: asg(:,:,:), alg(:,:,:)
    integer, parameter :: K = 20
    real(dp) :: P, e_k, e_film, e_tot, wvo, wba, gw, r2, sig, xe, ye, x, y, dzk
    integer :: i, j, kk
    logical :: ok

    call config_set_defaults(cfg)
    cfg%nr = 12; cfg%ntheta = 24; cfg%nz = 80
    cfg%n_beams = 0
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp
    ok = .true.

    allocate(asg(mesh%nr_g, mesh%nth_g, mesh%nz_g), alg(mesh%nr_g, mesh%nth_g, mesh%nz_g))
    asg = 0.0_dp; alg = 0.0_dp
    alg(:,:,1:K) = 1.0_dp
    do j = 1, mesh%nth_g
        do i = 1, mesh%nr_g
            if (mod(i + j, 3) == 0) alg(i,j,K+1) = 0.31_dp
        end do
    end do
    where (mesh%cell_type_global == 0) alg = 0.0_dp

    elec(1)%theta_pos = 0.0_dp
    elec(1)%z_tip = mesh%zf_global(K + 6)
    elec(1)%arc_length = 0.2_dp
    elec(1)%bore_in_done = .true.
    P = 1.0e6_dp
    elec(1)%arc_power = P

    ! el caso ejerce M6-5: pelicula > 5 % del volumen ponderado de su capa y
    ! < ARC_SURF_H de espesor equivalente
    sig = 1.5_dp * cfg%R_elec
    xe = cfg%R_pcd; ye = 0.0_dp
    wvo = 0.0_dp; wba = 0.0_dp
    do j = 1, mesh%nth_g
        do i = 1, mesh%nr_g
            if (mesh%cell_type_global(i,j,K+1) == 0) cycle
            x = mesh%r_global(i) * cos(mesh%theta_global(j)); y = mesh%r_global(i) * sin(mesh%theta_global(j))
            r2 = ((x - xe)**2 + (y - ye)**2) / sig**2
            if (r2 >= 16.0_dp) cycle
            gw = exp(-r2) * mesh%vol_global(i,j,K+1)
            wvo = wvo + gw
            if (alg(i,j,K+1) >= ALPHA_LIQ_CONT) wba = wba + gw * alg(i,j,K+1)
        end do
    end do
    dzk = mesh%zf_global(K+1) - mesh%zf_global(K)
    print '(A,F7.4,A,F7.4,A,F7.4)', '   pelicula: wba/wvo = ', wba / wvo, '  (criterio viejo 0.05, nuevo ', &
          ARC_SURF_H / dzk, ')'
    if (.not. (wba / wvo > 0.05_dp .and. wba / wvo < ARC_SURF_H / dzk)) &
        call fail('el caso no ejerce M6-5 (wba/wvo fuera de la ventana)', wba / wvo)

    sh%S_arc = 0.0_dp
    call distribute_arc_heat(elec, sh, sol, mesh, cfg, asg, 1, alg)

    e_k = 0.0_dp; e_film = 0.0_dp; e_tot = 0.0_dp
    do kk = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                e_tot = e_tot + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
                if (kk == K) e_k = e_k + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
                if (kk == K + 1) e_film = e_film + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
            end do
        end do
    end do
    e_tot = e_tot + sum(sol%E_s)
    print '(A,ES11.3,A,ES11.3,A,ES11.3)', '   potencia: capa K ', e_k, '  pelicula ', e_film, '  total ', e_tot
    if (e_film /= 0.0_dp) call fail('potencia del arco en la pelicula (W)', e_film)
    if (abs(e_k - P) > 1.0e-12_dp * P) call fail('la capa K no recibe todo el arco (rel)', (e_k - P) / P)
    if (abs(e_tot - P) > 1.0e-12_dp * P) call fail('presupuesto del arco (rel)', (e_tot - P) / P)

    if (ok) then
        print '(A)', ' PASS test_arc_surface (malla fina: una pelicula delgada no es la superficie del arco)'
    else
        print '(A)', ' FAIL test_arc_surface'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
contains
    subroutine fail(msg, v)
        character(len=*), intent(in) :: msg
        real(dp), intent(in) :: v
        print '(3A,ES12.4)', '   FAIL ', msg, ': ', v
        ok = .false.
    end subroutine fail
end program test_arc_surface
