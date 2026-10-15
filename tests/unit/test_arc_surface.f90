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
    real(dp) :: P, e_k, e_film, e_tot, e_up, wvo, wba, wsc, gw, r2, sig, xe, ye, x, y, dzk
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
    if (sum(sol%E_s) - e_film <= 0.0_dp) call fail('crater: la chatarra de la superficie no recibe nada', 0.0_dp)
    ! tolerancia: 1e-12 de P mas el redondeo de restar el inventario de E_s
    if (abs(e_tot - P) > 1.0e-12_dp * P + 1.0e-15_dp * e_film / cfg%dt) &
        call fail('crater: presupuesto del arco (rel)', (e_tot - P) / P)

    ! --- caso 3 (auditoria 8, M8-1): capa MIXTA. La capa K+1 lleva la
    ! pelicula del caso 1 (alpha_l 0.31 en 1/3 de las celdas) y chatarra suelta
    ! (alpha_s 0.06 en las otras 2/3). Es superficie (wsc/0.05 + wba/frac_surf
    ! >= 1) y la decide la CHATARRA, que domina en su escala (~0.8 frente a
    ! wba/frac_surf ~0.43), aunque en fraccion cruda el bano pese mas
    ! (wba > wsc): la comparacion cruda la daba por bano y mandaba P_conv y
    ! P_elec a la pelicula. Con superficie de chatarra el bano de debajo esta
    ! enterrado: nada a la capa K.
    asg = 0.0_dp; alg = 0.0_dp
    alg(:,:,1:K) = 1.0_dp
    do j = 1, mesh%nth_g
        do i = 1, mesh%nr_g
            if (mod(i + j, 3) == 0) then
                alg(i,j,K+1) = 0.31_dp
            else
                asg(i,j,K+1) = 0.06_dp
            end if
        end do
    end do
    where (mesh%cell_type_global == 0) alg = 0.0_dp
    where (mesh%cell_type_global == 0) asg = 0.0_dp
    wvo = 0.0_dp; wba = 0.0_dp; wsc = 0.0_dp
    do j = 1, mesh%nth_g
        do i = 1, mesh%nr_g
            if (mesh%cell_type_global(i,j,K+1) == 0) cycle
            x = mesh%r_global(i) * cos(mesh%theta_global(j)); y = mesh%r_global(i) * sin(mesh%theta_global(j))
            r2 = ((x - xe)**2 + (y - ye)**2) / sig**2
            if (r2 >= 16.0_dp) cycle
            gw = exp(-r2) * mesh%vol_global(i,j,K+1)
            wvo = wvo + gw
            if (asg(i,j,K+1) > ALPHA_SCRAP_SURF) wsc = wsc + gw * asg(i,j,K+1)
            if (alg(i,j,K+1) >= ALPHA_LIQ_CONT) wba = wba + gw * alg(i,j,K+1)
        end do
    end do
    print '(A,F7.4,A,F7.4,A,F7.4)', '   mixta: wsc/wvo = ', wsc / wvo, '  wba/wvo = ', wba / wvo, &
          '  frac_surf = ', ARC_SURF_H / dzk
    if (.not. (wsc < wba .and. wsc / ARC_SURF_FRAC_S > wba / (ARC_SURF_H / dzk) .and. &
               wsc / ARC_SURF_FRAC_S + wba / (ARC_SURF_H / dzk) >= wvo)) &
        call fail('el caso no ejerce M8-1 (capa mixta fuera de la ventana)', wsc / wba)
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
    e_k = 0.0_dp; e_tot = (sum(sol%E_s) - e_film) / cfg%dt
    do kk = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                e_tot = e_tot + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
                if (kk <= K) e_k = e_k + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
            end do
        end do
    end do
    ! discriminante: con superficie de CHATARRA, P_conv (y P_elec con el) va a
    ! la columna kg_scrap..kg_tip, asi que las capas de ENCIMA reciben; con
    ! superficie de BANO todo va a la capa K+1 (la comparacion cruda: 0 W
    ! encima y 4.65e5 W al fluido de la pelicula)
    e_up = 0.0_dp
    do kk = K + 2, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                e_up = e_up + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
            end do
        end do
    end do
    print '(A,ES11.3)', '   mixta: P_conv a la columna sobre la superficie ', e_up
    if (e_up <= 0.0_dp) call fail('mixta: superficie de bano (nada a la columna del chorro)', e_up)
    print '(A,ES11.3,A,ES11.3,A,ES11.3)', '   mixta: potencia en el bano ', e_k, '  al solido ', &
          (sum(sol%E_s) - e_film) / cfg%dt, '  total ', e_tot
    if (e_k /= 0.0_dp) call fail('mixta: la capa se clasifico como bano (W a la capa K)', e_k)
    if (sum(sol%E_s) - e_film <= 0.0_dp) call fail('mixta: la chatarra de la superficie no recibe nada', 0.0_dp)
    if (abs(e_tot - P) > 1.0e-12_dp * P + 1.0e-15_dp * e_film / cfg%dt) &
        call fail('mixta: presupuesto del arco (rel)', (e_tot - P) / P)

    ! --- caso 4 (auditoria 9, M9-3): BANO con chatarra SUMERGIDA. La capa K+1
    ! lleva alpha_l 0.75 y alpha_s 0.20 en todas las celdas (desplome de
    ! chatarra en el bano). Los DOS materiales pasan su umbral propio: decide
    ! la fraccion cruda (bano 0.75 > chatarra 0.20), como antes de M8-1 y en
    ! cualquier malla. Con la comparacion normalizada de M8-1 (en esta malla
    ! 0.20/0.05 = 4.0 frente a 0.75/frac_surf ~3.1) salia CHATARRA y P_conv y
    ! P_elec iban a la columna de gas sobre el bano. Superficie de bano: nada
    ! por encima de K+1.
    asg = 0.0_dp; alg = 0.0_dp
    alg(:,:,1:K) = 1.0_dp
    alg(:,:,K+1) = 0.75_dp
    asg(:,:,K+1) = 0.20_dp
    where (mesh%cell_type_global == 0) alg = 0.0_dp
    where (mesh%cell_type_global == 0) asg = 0.0_dp
    if (.not. (0.20_dp / ARC_SURF_FRAC_S > 0.75_dp / (ARC_SURF_H / dzk) .and. &
               0.75_dp >= ARC_SURF_H / dzk)) &
        call fail('el caso no ejerce M9-3 (fuera de la ventana)', ARC_SURF_H / dzk)
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
    e_up = 0.0_dp; e_tot = (sum(sol%E_s) - e_film) / cfg%dt
    do kk = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                e_tot = e_tot + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
                if (kk >= K + 2) e_up = e_up + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
            end do
        end do
    end do
    print '(A,ES11.3)', '   sumergida: potencia a la columna sobre el bano ', e_up
    if (e_up /= 0.0_dp) call fail('sumergida: el bano se clasifico como chatarra (W sobre K+1)', e_up)
    if (abs(e_tot - P) > 1.0e-12_dp * P + 1.0e-15_dp * e_film / cfg%dt) &
        call fail('sumergida: presupuesto del arco (rel)', (e_tot - P) / P)

    ! --- caso 5 (auditoria 9, M9-3): SOLO la chatarra pasa su umbral. Pelicula
    ! del caso 1 (alpha_l 0.31 en 1/3: wba/wvo ~0.10, bajo frac_surf ~0.24) y
    ! chatarra alpha_s 0.09 en las otras 2/3 (wsc/wvo ~0.06 >= 0.05). En
    ! fraccion cruda el bano pesa mas, pero es una pelicula de menos de
    ! ARC_SURF_H: CHATARRA (P_conv a la columna, nada a la capa K).
    asg = 0.0_dp; alg = 0.0_dp
    alg(:,:,1:K) = 1.0_dp
    do j = 1, mesh%nth_g
        do i = 1, mesh%nr_g
            if (mod(i + j, 3) == 0) then
                alg(i,j,K+1) = 0.31_dp
            else
                asg(i,j,K+1) = 0.09_dp
            end if
        end do
    end do
    where (mesh%cell_type_global == 0) alg = 0.0_dp
    where (mesh%cell_type_global == 0) asg = 0.0_dp
    wvo = 0.0_dp; wba = 0.0_dp; wsc = 0.0_dp
    do j = 1, mesh%nth_g
        do i = 1, mesh%nr_g
            if (mesh%cell_type_global(i,j,K+1) == 0) cycle
            x = mesh%r_global(i) * cos(mesh%theta_global(j)); y = mesh%r_global(i) * sin(mesh%theta_global(j))
            r2 = ((x - xe)**2 + (y - ye)**2) / sig**2
            if (r2 >= 16.0_dp) cycle
            gw = exp(-r2) * mesh%vol_global(i,j,K+1)
            wvo = wvo + gw
            if (asg(i,j,K+1) > ALPHA_SCRAP_SURF) wsc = wsc + gw * asg(i,j,K+1)
            if (alg(i,j,K+1) >= ALPHA_LIQ_CONT) wba = wba + gw * alg(i,j,K+1)
        end do
    end do
    print '(A,F7.4,A,F7.4)', '   solo chatarra: wsc/wvo = ', wsc / wvo, '  wba/wvo = ', wba / wvo
    if (.not. (wsc >= ARC_SURF_FRAC_S * wvo .and. wba < (ARC_SURF_H / dzk) * wvo .and. wsc < wba)) &
        call fail('el caso no ejerce la rama solo-chatarra (fuera de la ventana)', wsc / wba)
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
    e_up = 0.0_dp; e_k = 0.0_dp; e_tot = (sum(sol%E_s) - e_film) / cfg%dt
    do kk = 1, mesh%nz
        do j = 1, mesh%ntheta
            do i = 1, mesh%nr
                e_tot = e_tot + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
                if (kk >= K + 2) e_up = e_up + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
                if (kk <= K) e_k = e_k + sh%S_arc(i,j,kk) * mesh%vol(i,j,kk)
            end do
        end do
    end do
    print '(A,ES11.3)', '   solo chatarra: P_conv a la columna ', e_up
    if (e_up <= 0.0_dp) call fail('solo chatarra: se clasifico como bano (nada a la columna)', e_up)
    if (e_k /= 0.0_dp) call fail('solo chatarra: potencia al bano enterrado (W)', e_k)
    if (abs(e_tot - P) > 1.0e-12_dp * P + 1.0e-15_dp * e_film / cfg%dt) &
        call fail('solo chatarra: presupuesto del arco (rel)', (e_tot - P) / P)

    if (ok) then
        print '(A)', ' PASS test_arc_surface (malla fina: pelicula delgada no es superficie; crater y capa mixta si; bano con chatarra sumergida es bano)'
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
