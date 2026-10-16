!===============================================================================
! test_arc_surface.f90 - Superficie del bano bajo el arco con malla FINA
! (auditoria 6, M6-5; auditoria 7, M7-1). Malla FINA en z (80 capas con el
! stretch por defecto, dz ~0.058 m en la capa de la pelicula):
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
    use mod_melting_3d, only: solid_enthalpy
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
    real(dp) :: P, e_k, e_film, e_tot, wvo, wba, wsc, gw, r2, sig, xe, ye, x, y, dzk
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

    ! --- caso 2 (M7-1): CRATER a medio fundir. La capa K+1 tiene chatarra
    ! alpha_s 0.15 (sin liquido) sobre el bano: ES la superficie (la chatarra
    ! se mide por su fraccion del volumen de la capa, no por espesor: con el
    ! espesor equivalente M6-5 exigia alpha_s >= 0.24 en esta malla y la
    ! potencia caia al bano de debajo). Nada debe llegar a la capa del bano.
    asg = 0.0_dp; alg = 0.0_dp
    alg(:,:,1:K) = 1.0_dp
    asg(:,:,K+1) = 0.15_dp
    where (mesh%cell_type_global == 0) alg = 0.0_dp
    where (mesh%cell_type_global == 0) asg = 0.0_dp
    sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp
    do kk = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                sol%alpha_s(i,j,kk) = asg(i,j,kk)
                sol%m_s(i,j,kk) = asg(i,j,kk) * cfg%rho_steel * mesh%vol(i,j,kk)
                sol%T_s(i,j,kk) = 1500.0_dp
                sol%E_s(i,j,kk) = sol%m_s(i,j,kk) * solid_enthalpy(1500.0_dp, cfg)
            end do
        end do
    end do
    e_film = sum(sol%E_s)
    sh%S_arc = 0.0_dp
    call distribute_arc_heat(elec, sh, sol, mesh, cfg, asg, 1, alg)
    ! el solido recibe JOULES del paso (arc_deposit: Q = P V dt); S_arc en W/m3
    e_k = 0.0_dp; e_tot = (sum(sol%E_s) - e_film) / cfg%dt
    do kk = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                e_tot = e_tot + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
                if (kk <= K) e_k = e_k + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
            end do
        end do
    end do
    print '(A,ES11.3,A,ES11.3)', '   crater: potencia en el bano ', e_k, '  total ', e_tot
    if (e_k /= 0.0_dp) call fail('crater: el arco salta la chatarra y calienta el bano (W)', e_k)
    ! tolerancia: 1e-12 de P mas el redondeo de restar el inventario de E_s
    if (abs(e_tot - P) > 1.0e-12_dp * P + 1.0e-15_dp * e_film / cfg%dt) &
        call fail('crater: presupuesto del arco (rel)', (e_tot - P) / P)

    ! --- casos 3-5 (auditoria 8, M8-1): QUIEN es la superficie. Discriminante:
    ! con superficie de CHATARRA, P_conv (y P_elec) van a la columna
    ! kg_scrap..kg_tip y las capas por encima de K+1 reciben; con superficie
    ! de BANO todo va a la capa K+1.
    ! 3: pelicula (alpha_l 0.31 en 1/3) bajo su umbral de espesor + chatarra
    !    suelta (alpha_s 0.06 en 2/3): el bano NO pasa su umbral propio ->
    !    CHATARRA (la comparacion cruda wsc >= wba la daba por bano: M8-1)
    call layer_case(3, 0.31_dp, 0.06_dp, .true., .true.)
    ! 4: bano con chatarra SUMERGIDA (alpha_l 0.75, alpha_s 0.20 en todas):
    !    el bano pasa su umbral y pesa mas -> BANO (M3-3; guarda de M9-3)
    call layer_case(4, 0.75_dp, 0.20_dp, .false., .false.)
    ! 5: lecho INUNDADO (alpha_s 0.55, alpha_l 0.43 en todas): los dos pasan
    !    su umbral y la chatarra pesa mas -> CHATARRA (M4-8)
    call layer_case(5, 0.43_dp, 0.55_dp, .false., .true.)
    ! 6: SOLO la chatarra pasa su umbral (pelicula 0.31 en 1/3 bajo su umbral,
    !    chatarra 0.09 en 2/3: wsc ~0.06 >= 0.05) aunque el bano crudo pese
    !    mas -> CHATARRA (rama normalizada, como el 3, con la chatarra sobre
    !    su umbral)
    call layer_case(6, 0.31_dp, 0.09_dp, .true., .true.)
    ! 7: NINGUNO pasa su umbral y la chatarra es una TRAZA: pelicula gruesa
    !    (alpha_l 0.32 en 3 de cada 4 celdas: casi en su umbral) y chatarra
    !    0.10 en 1 de cada 6: la capa es superficie (suma 1.33) y la
    !    normalizada da 0.34 frente a 0.99 -> BANO
    !    (auditoria dirigida de M8-1: con 'chatarra si el bano no pasa' una
    !    traza decidia la superficie)
    call layer_case(7, 0.32_dp, 0.10_dp, .false., .false., 6)
    ! 8 (limite de una capa, auditorias 11-13): CHARCO de 0.3 dz sobre un lecho
    !    COMPACTADO inundado (phi 0.95 en la capa K): K+1 tiene alpha_s 0.665 y
    !    alpha_l 0.335, que la regla de una capa daba por CHATARRA (0.665 >=
    !    0.335); mirando la capa de abajo el charco implicito es 0.3 dz >=
    !    ARC_SURF_H -> BANO
    call layer_case(8, 0.335_dp, 0.665_dp, .false., .false., phib=0.95_dp)
    ! 9: lecho inundado A RAS (alpha_s 0.6 en K+1 sobre el mismo lecho 0.6 en
    !    K): charco implicito 0 -> CHATARRA (como el 5)
    call layer_case(9, 0.40_dp, 0.60_dp, .false., .true., phib=0.60_dp)
    ! 10 (dirigida del modelo, M2): lecho SUELTO inundado a ras (0.6) sobre un
    !    lecho MAS denso pero no compactado (0.8): la regla del charco no actua
    !    (phi_abajo < 0.9) -> CHATARRA (M4-8)
    call layer_case(10, 0.40_dp, 0.60_dp, .false., .true., phib=0.80_dp)

    if (ok) then
        print '(A)', ' PASS test_arc_surface (pelicula no es superficie; crater, pelicula sobre chatarra y lecho inundado son chatarra; bano con chatarra sumergida es bano)'
    else
        print '(A)', ' FAIL test_arc_surface'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
contains
    ! capa K+1 con liquido al y chatarra as (film: al en 1/3 de las celdas y
    ! as en las otras 2/3; si no, ambos en todas); bano lleno en 1..K.
    ! want_scrap: superficie esperada (chatarra o bano)
    subroutine layer_case(icase, al, as, film, want_scrap, every, phib)
        integer, intent(in)  :: icase
        real(dp), intent(in) :: al, as
        logical, intent(in)  :: film, want_scrap
        ! (opcional) chatarra solo en 1 de cada 'every' celdas y liquido en 3
        ! de cada 4 (las de chatarra, sin liquido)
        integer, intent(in), optional :: every
        ! (opcional) la capa K es un LECHO inundado de fraccion phib (no bano)
        real(dp), intent(in), optional :: phib
        real(dp) :: e_up_, e_k_, e_tot_, e0
        integer  :: ii, jj, k3
        asg = 0.0_dp; alg = 0.0_dp
        alg(:,:,1:K) = 1.0_dp
        if (present(phib)) then
            asg(:,:,K) = phib; alg(:,:,K) = 1.0_dp - phib
        end if
        do jj = 1, mesh%nth_g
            do ii = 1, mesh%nr_g
                if (film) then
                    if (mod(ii + jj, 3) == 0) then
                        alg(ii,jj,K+1) = al
                    else
                        asg(ii,jj,K+1) = as
                    end if
                else if (present(every)) then
                    if (mod(ii + jj, 4) /= 0) alg(ii,jj,K+1) = al
                    if (mod(ii + jj, every) == 0) asg(ii,jj,K+1) = as
                else
                    alg(ii,jj,K+1) = al; asg(ii,jj,K+1) = as
                end if
            end do
        end do
        where (mesh%cell_type_global == 0) alg = 0.0_dp
        where (mesh%cell_type_global == 0) asg = 0.0_dp
        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%E_s = 0.0_dp
        do k3 = 1, mesh%nz
            do jj = 1, mesh%ntheta
                do ii = 1, mesh%nr
                    sol%alpha_s(ii,jj,k3) = asg(ii,jj,k3)
                    sol%m_s(ii,jj,k3) = asg(ii,jj,k3) * cfg%rho_steel * mesh%vol(ii,jj,k3)
                    sol%T_s(ii,jj,k3) = 1500.0_dp
                    sol%E_s(ii,jj,k3) = sol%m_s(ii,jj,k3) * solid_enthalpy(1500.0_dp, cfg)
                end do
            end do
        end do
        e0 = sum(sol%E_s)
        wvo = 0.0_dp; wba = 0.0_dp; wsc = 0.0_dp
        do jj = 1, mesh%nth_g
            do ii = 1, mesh%nr_g
                if (mesh%cell_type_global(ii,jj,K+1) == 0) cycle
                x = mesh%r_global(ii) * cos(mesh%theta_global(jj)); y = mesh%r_global(ii) * sin(mesh%theta_global(jj))
                r2 = ((x - xe)**2 + (y - ye)**2) / sig**2
                if (r2 >= 16.0_dp) cycle
                gw = exp(-r2) * mesh%vol_global(ii,jj,K+1)
                wvo = wvo + gw
                if (asg(ii,jj,K+1) > ALPHA_SCRAP_SURF) wsc = wsc + gw * asg(ii,jj,K+1)
                if (alg(ii,jj,K+1) >= ALPHA_LIQ_CONT) wba = wba + gw * alg(ii,jj,K+1)
            end do
        end do
        print '(A,I0,A,F7.4,A,F7.4,A,F7.4)', '   caso ', icase, ': wsc/wvo/0.05 = ', wsc / wvo / ARC_SURF_FRAC_S, &
            '  wba/wvo/frac_surf = ', wba / wvo / (ARC_SURF_H / dzk), '  suma = ', &
            wsc / wvo / ARC_SURF_FRAC_S + wba / wvo / (ARC_SURF_H / dzk)
        sh%S_arc = 0.0_dp
        call distribute_arc_heat(elec, sh, sol, mesh, cfg, asg, 1, alg)
        e_up_ = 0.0_dp; e_k_ = 0.0_dp; e_tot_ = (sum(sol%E_s) - e0) / cfg%dt
        do k3 = 1, mesh%nz
            do jj = 1, mesh%ntheta
                do ii = 1, mesh%nr
                    e_tot_ = e_tot_ + sh%S_arc(ii,jj,k3) * mesh%vol(ii,jj,k3)
                    if (k3 >= K + 2) e_up_ = e_up_ + sh%S_arc(ii,jj,k3) * mesh%vol(ii,jj,k3)
                    if (k3 <= K) e_k_ = e_k_ + sh%S_arc(ii,jj,k3) * mesh%vol(ii,jj,k3)
                end do
            end do
        end do
        print '(A,I0,A,ES11.3,A,ES11.3,A,L1)', '   caso ', icase, ': columna sobre K+1 ', e_up_, &
            '  bano enterrado ', e_k_, '  esperado chatarra=', want_scrap
        if (wsc / wvo / ARC_SURF_FRAC_S + wba / wvo / (ARC_SURF_H / dzk) < 1.0_dp) &
            call fail('el caso no hace superficie a la capa K+1 (mal construido)', 0.0_dp)
        if (want_scrap .and. e_up_ <= 0.0_dp) call fail('superficie de bano donde debia ser chatarra (W columna)', e_up_)
        if (.not. want_scrap .and. e_up_ /= 0.0_dp) call fail('superficie de chatarra donde debia ser bano (W columna)', e_up_)
        if (e_k_ /= 0.0_dp) call fail('potencia a la capa del bano enterrado (W)', e_k_)
        ! tolerancia: 1e-12 de P mas el redondeo de restar el inventario de E_s
        ! (suma de ~1e3 celdas: ~1e-13 relativo con la capa densa del caso 5)
        if (abs(e_tot_ - P) > 1.0e-12_dp * P + 1.0e-13_dp * e0 / cfg%dt) &
            call fail('presupuesto del arco (rel)', (e_tot_ - P) / P)
    end subroutine layer_case

    subroutine fail(msg, v)
        character(len=*), intent(in) :: msg
        real(dp), intent(in) :: v
        print '(3A,ES12.4)', '   FAIL ', msg, ': ', v
        ok = .false.
    end subroutine fail
end program test_arc_surface
