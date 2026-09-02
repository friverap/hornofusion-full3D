!===============================================================================
! mod_radiation_do.f90 - Radiación por Ordenadas Discretas (S4, 24 direcciones)
!
! C3.4: reescritura como FVM CONSERVATIVO por dirección (la versión anterior
! solo propagaba intensidad a lo largo del índice radial y un limitador
! S_RAD_LIMIT=1e4 W/m3 la neutralizaba — la escala física es 4*k*sigma*T^4
! ~ 7e5 W/m3 a 1800 K).
!
! RTE por dirección cartesiana fija s:  div(s I) + kappa I = kappa B
! FVM sobre las celdas cilíndricas con PROYECCIONES DE CARA INTEGRADAS
! EXACTAS (cierran el poliedro a precisión de máquina, sin términos de
! redistribución angular):
!   cara radial   (r_f, th_s..th_n): c = r_f dz [sx(sin th_n - sin th_s)
!                                               + sy(cos th_s - cos th_n)]
!   cara azimutal (th_f):            c = (-sx sin th_f + sy cos th_f) dr dz
!   cara axial:                      c = sz * Az
! Upwind: salidas (c>0) a aP, entradas a a_nb; el sistema por dirección se
! resuelve con tdma_3d_mpi (acople MPI vía halos, sin costuras de rank).
!
! Emisión de MEZCLA: B = [kf*(wl*B(T_l)+wg*B(T_g)) + ks*B(T_s)]/kappa_mix
! con kf = KAPPA_GAS*(1-alpha_s), ks = KAPPA_SOLID*alpha_s.
!
! Acople:
!  - FLUIDOS: sh%kappa_f y sh%G_rad para linearización IMPLÍCITA en energía
!    (Su += w*kf*G*V ; aP += w*kf*4*sigma*T_old^3*V) — estable sin limitador.
!  - SÓLIDO: depósito directo kappa_s*(G - 4 sigma T_s^4)*V*dt con
!    actualización puntual linearizada (incondicional).
!  - PAREDES negras a cfg%T_wall: entrada = |c|*B_wall, salida absorbida.
!    Es el sumidero radiativo físico del horno (paneles refrigerados).
!===============================================================================
module mod_radiation_do
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_solver_3d, only: tdma_3d_mpi
    use mod_melting_3d, only: solid_T_from_enthalpy, effective_cp
    use mod_audit, only: audit_add, AUD_RAD_SOL, AUD_RAD_WALL
    implicit none

    integer, parameter :: N_DIRECTIONS = 24
    real(dp), parameter :: KAPPA_GAS = 0.3_dp    ! 1/m (gas absorption coefficient)
    real(dp), parameter :: KAPPA_SOLID = 10.0_dp ! 1/m (solid region)
    integer, parameter :: N_SWEEPS_RTE = 2       ! sweeps TDMA por dirección

contains

    subroutine solve_radiation_do(liq, gas, sol, sh, m, cfg)
        type(phase_t), intent(in)    :: liq, gas
        type(solid_t), intent(inout) :: sol
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer  :: i, j, k, d
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: aW(:,:,:), aE(:,:,:), aS(:,:,:), aN(:,:,:)
        real(dp), allocatable :: aB(:,:,:), aT(:,:,:), aP(:,:,:), Su(:,:,:)
        real(dp), allocatable :: Irad(:,:,:), Bmix(:,:,:), kmix(:,:,:)
        real(dp) :: sx, sy, sz, w_d
        real(dp) :: cw, ce, cs, cn, cb, ct
        real(dp) :: B_wall, wall_net, wall_net_step
        real(dp) :: ks_a, T_s, dE_rate, denom, dE
        real(dp) :: w_l, w_g, B_fluid

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        allocate(aW, mold=sh%G_rad); allocate(aE, mold=sh%G_rad)
        allocate(aS, mold=sh%G_rad); allocate(aN, mold=sh%G_rad)
        allocate(aB, mold=sh%G_rad); allocate(aT, mold=sh%G_rad)
        allocate(aP, mold=sh%G_rad); allocate(Su, mold=sh%G_rad)
        allocate(Irad, mold=sh%G_rad); allocate(Bmix, mold=sh%G_rad)
        allocate(kmix, mold=sh%G_rad)

        B_wall = STEFAN_BOLTZMANN * cfg%T_wall**4 / PI

        ! ── Emisión de mezcla y kappas (una vez por llamada) ───────────────
        Bmix = B_wall   ! halos/inactivas: valor de pared (guess inicial de I)
        kmix = 0.0_dp
        sh%kappa_f = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    sh%kappa_f(i,j,k) = KAPPA_GAS * &
                        max(0.0_dp, 1.0_dp - sol%alpha_s(i,j,k))
                    ks_a = KAPPA_SOLID * sol%alpha_s(i,j,k)
                    kmix(i,j,k) = sh%kappa_f(i,j,k) + ks_a

                    ! Reparto de la emisión fluida por fase (mismos pesos que
                    ! el reparto de fuentes en energía)
                    w_l = liq%alpha(i,j,k) / &
                          (liq%alpha(i,j,k) + gas%alpha(i,j,k) + SMALL)
                    w_g = 1.0_dp - w_l
                    B_fluid = STEFAN_BOLTZMANN / PI * &
                              (w_l * liq%T(i,j,k)**4 + w_g * gas%T(i,j,k)**4)
                    Bmix(i,j,k) = (sh%kappa_f(i,j,k) * B_fluid + &
                                   ks_a * STEFAN_BOLTZMANN / PI * &
                                   sol%T_s(i,j,k)**4) / max(kmix(i,j,k), SMALL)
                end do
            end do
        end do

        ! ── Barrido por dirección ──────────────────────────────────────────
        sh%G_rad = 0.0_dp
        wall_net = 0.0_dp

        do d = 1, N_DIRECTIONS
            call get_s4_direction(d, sx, sy, sz, w_d)

            aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
            aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) then
                            aP(i,j,k) = 1.0_dp
                            Su(i,j,k) = B_wall
                            cycle
                        end if

                        ! Proyecciones de cara integradas exactas (c>0: sale)
                        cw = -face_r(i-1, j, k)
                        ce =  face_r(i,   j, k)
                        cs = -face_th(i, j-1, k)
                        cn =  face_th(i, j,   k)
                        cb = -sz * m%Az(i,j,k-1)
                        ct =  sz * m%Az(i,j,k)

                        aP(i,j,k) = max(cw,0.0_dp) + max(ce,0.0_dp) + &
                                    max(cs,0.0_dp) + max(cn,0.0_dp) + &
                                    max(cb,0.0_dp) + max(ct,0.0_dp) + &
                                    kmix(i,j,k) * m%vol(i,j,k)
                        Su(i,j,k) = kmix(i,j,k) * Bmix(i,j,k) * m%vol(i,j,k)

                        ! Entradas: del vecino activo, o de PARED (B_wall)
                        if (m%cell_type(i-1,j,k) /= 0) then
                            aW(i,j,k) = max(-cw, 0.0_dp)
                        else
                            Su(i,j,k) = Su(i,j,k) + max(-cw,0.0_dp) * B_wall
                        end if
                        if (m%cell_type(i+1,j,k) /= 0) then
                            aE(i,j,k) = max(-ce, 0.0_dp)
                        else
                            Su(i,j,k) = Su(i,j,k) + max(-ce,0.0_dp) * B_wall
                        end if
                        if (m%cell_type(i,j-1,k) /= 0) then
                            aS(i,j,k) = max(-cs, 0.0_dp)
                        else
                            Su(i,j,k) = Su(i,j,k) + max(-cs,0.0_dp) * B_wall
                        end if
                        if (m%cell_type(i,j+1,k) /= 0) then
                            aN(i,j,k) = max(-cn, 0.0_dp)
                        else
                            Su(i,j,k) = Su(i,j,k) + max(-cn,0.0_dp) * B_wall
                        end if
                        if (m%cell_type(i,j,k-1) /= 0) then
                            aB(i,j,k) = max(-cb, 0.0_dp)
                        else
                            Su(i,j,k) = Su(i,j,k) + max(-cb,0.0_dp) * B_wall
                        end if
                        if (m%cell_type(i,j,k+1) /= 0) then
                            aT(i,j,k) = max(-ct, 0.0_dp)
                        else
                            Su(i,j,k) = Su(i,j,k) + max(-ct,0.0_dp) * B_wall
                        end if
                    end do
                end do
            end do

            ! Guess inicial cerca del equilibrio → converge en pocos sweeps
            Irad = Bmix
            call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, Irad, m, &
                             N_SWEEPS_RTE)

            ! Acumular G y el flujo neto a paredes (diagnóstico de auditoría)
            wall_net_step = 0.0_dp
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        sh%G_rad(i,j,k) = sh%G_rad(i,j,k) + w_d * Irad(i,j,k)

                        cw = -face_r(i-1, j, k)
                        ce =  face_r(i,   j, k)
                        cs = -face_th(i, j-1, k)
                        cn =  face_th(i, j,   k)
                        cb = -sz * m%Az(i,j,k-1)
                        ct =  sz * m%Az(i,j,k)
                        if (m%cell_type(i-1,j,k) == 0) wall_net_step = &
                            wall_net_step + max(cw,0.0_dp)*Irad(i,j,k) &
                                          - max(-cw,0.0_dp)*B_wall
                        if (m%cell_type(i+1,j,k) == 0) wall_net_step = &
                            wall_net_step + max(ce,0.0_dp)*Irad(i,j,k) &
                                          - max(-ce,0.0_dp)*B_wall
                        if (m%cell_type(i,j-1,k) == 0) wall_net_step = &
                            wall_net_step + max(cs,0.0_dp)*Irad(i,j,k) &
                                          - max(-cs,0.0_dp)*B_wall
                        if (m%cell_type(i,j+1,k) == 0) wall_net_step = &
                            wall_net_step + max(cn,0.0_dp)*Irad(i,j,k) &
                                          - max(-cn,0.0_dp)*B_wall
                        if (m%cell_type(i,j,k-1) == 0) wall_net_step = &
                            wall_net_step + max(cb,0.0_dp)*Irad(i,j,k) &
                                          - max(-cb,0.0_dp)*B_wall
                        if (m%cell_type(i,j,k+1) == 0) wall_net_step = &
                            wall_net_step + max(ct,0.0_dp)*Irad(i,j,k) &
                                          - max(-ct,0.0_dp)*B_wall
                    end do
                end do
            end do
            wall_net = wall_net + w_d * wall_net_step
        end do

        ! Pérdida radiativa neta a paredes acumulada este paso [J]
        call audit_add(AUD_RAD_WALL, wall_net * cfg%dt)

        ! ── Depósito directo al SÓLIDO (su parte de la absorción) ──────────
        ! Actualización puntual linearizada implícita: incondicionalmente
        ! estable (la emisión crece con T_s).
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (sol%m_s(i,j,k) <= SMALL) cycle
                    ks_a = KAPPA_SOLID * sol%alpha_s(i,j,k)
                    if (ks_a <= SMALL) cycle

                    ! Newton puntual sobre E:  f(E) = E - E0 - dt*V*ks*
                    ! (G - 4σT(E)^4) = 0.  3 iteraciones bastan (f' > 1).
                    block
                        real(dp) :: E0, E_new, fval, fprime
                        integer  :: it
                        E0 = sol%E_s(i,j,k)
                        E_new = E0
                        do it = 1, 3
                            T_s = solid_T_from_enthalpy( &
                                  E_new / sol%m_s(i,j,k), cfg)
                            fval = E_new - E0 - cfg%dt * ks_a * m%vol(i,j,k) * &
                                   (sh%G_rad(i,j,k) - &
                                    4.0_dp * STEFAN_BOLTZMANN * T_s**4)
                            fprime = 1.0_dp + cfg%dt * ks_a * m%vol(i,j,k) * &
                                     16.0_dp * STEFAN_BOLTZMANN * T_s**3 / &
                                     (sol%m_s(i,j,k) * effective_cp(T_s, cfg))
                            E_new = E_new - fval / fprime
                        end do
                        dE = E_new - E0
                        sol%E_s(i,j,k) = E_new
                        sol%T_s(i,j,k) = solid_T_from_enthalpy( &
                            E_new / sol%m_s(i,j,k), cfg)
                        call audit_add(AUD_RAD_SOL, dE)
                    end block
                end do
            end do
        end do

        ! ── Diagnóstico para salida HDF5 (fluido, evaluado a T actual) ─────
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    w_l = liq%alpha(i,j,k) / &
                          (liq%alpha(i,j,k) + gas%alpha(i,j,k) + SMALL)
                    w_g = 1.0_dp - w_l
                    sh%S_rad(i,j,k) = sh%kappa_f(i,j,k) * (sh%G_rad(i,j,k) - &
                        4.0_dp * STEFAN_BOLTZMANN * &
                        (w_l * liq%T(i,j,k)**4 + w_g * gas%T(i,j,k)**4))
                end do
            end do
        end do

        deallocate(aW, aE, aS, aN, aB, aT, aP, Su, Irad, Bmix, kmix)

    contains

        ! Proyección integrada exacta sobre la cara RADIAL en r_f(ii),
        ! theta en [thetaf(jj-1), thetaf(jj)], z en dz(kk):
        !   c = r_f dz [sx(sin th_n - sin th_s) + sy(cos th_s - cos th_n)]
        real(dp) function face_r(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            face_r = m%rf(ii) * m%dz(kk) * &
                (sx * (sin(m%thetaf(jj)) - sin(m%thetaf(jj-1))) + &
                 sy * (cos(m%thetaf(jj-1)) - cos(m%thetaf(jj))))
        end function face_r

        ! Proyección sobre la cara AZIMUTAL en thetaf(jj): s·theta_hat * A
        real(dp) function face_th(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            face_th = (-sx * sin(m%thetaf(jj)) + sy * cos(m%thetaf(jj))) * &
                      m%dr(ii) * m%dz(kk)
        end function face_th

    end subroutine solve_radiation_do

    !---------------------------------------------------------------------------
    ! S4 quadrature directions and weights (24 directions)
    ! Symmetric set for 3D: octant directions with positive/negative combos
    !---------------------------------------------------------------------------
    subroutine get_s4_direction(d, mu, eta, xi, w)
        integer, intent(in)   :: d
        real(dp), intent(out) :: mu, eta, xi, w

        real(dp), parameter :: a1 = 0.2958759_dp
        real(dp), parameter :: a2 = 0.9082483_dp
        real(dp), parameter :: w1 = 0.5235987755982988_dp  ! pi/6

        integer :: octant, local_d
        real(dp) :: s_mu, s_eta, s_xi

        ! 24 directions = 8 octants x 3 permutations
        octant  = (d - 1) / 3 + 1
        local_d = mod(d - 1, 3) + 1

        ! Signs for each octant
        s_mu  = merge(1.0_dp, -1.0_dp, mod(octant-1, 2) == 0)
        s_eta = merge(1.0_dp, -1.0_dp, mod((octant-1)/2, 2) == 0)
        s_xi  = merge(1.0_dp, -1.0_dp, mod((octant-1)/4, 2) == 0)

        select case (local_d)
        case (1)
            mu = s_mu * a2; eta = s_eta * a1; xi = s_xi * a1
        case (2)
            mu = s_mu * a1; eta = s_eta * a2; xi = s_xi * a1
        case (3)
            mu = s_mu * a1; eta = s_eta * a1; xi = s_xi * a2
        end select

        w = w1
    end subroutine get_s4_direction

end module mod_radiation_do
