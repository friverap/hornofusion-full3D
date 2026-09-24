!===============================================================================
! mod_momentum_3d.f90 - 3D momentum equations in cylindrical coordinates
!
! Solves for u_r, u_theta, u_z with:
!   - First-order upwind convection
!   - Central differencing diffusion
!   - Implicit Euler time integration
!   - Cylindrical extra terms:
!       r-mom:     -rho*u_theta^2/r (centrifugal)
!       theta-mom: +rho*u_r*u_theta/r (Coriolis)
!   - Source terms: gravity, drag (Ergun), arc impingement
!
! Returns aP coefficients for Rhie-Chow pressure correction.
!
! MPI-aware: Uses local loops and halo exchanges
!===============================================================================
module mod_momentum_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    use mod_face_flux
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Solve all three momentum components for a single phase
    !---------------------------------------------------------------------------
    subroutine solve_momentum_3d(ph, ph_old, ph_other, Kexch, sh, m, cfg, &
                                  alpha_q, drag_coef, is_gas, &
                                  res_ur, res_uth, res_uz)
        type(phase_t), intent(inout) :: ph
        type(phase_t), intent(in)    :: ph_old
        ! Otra fase fluida + coeficiente de intercambio de momentum K [kg/(m3 s)]
        ! (C2.4): aP += K*vol, Su += K*u_otra*vol — implícito y simétrico.
        type(phase_t), intent(in)    :: ph_other
        real(dp), intent(in)         :: Kexch(-1:,-1:,-1:)
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        ! Coeficiente de Ergun (>=0), tratado IMPLÍCITO: aP += coef*vol (C1.4)
        real(dp), intent(in)         :: drag_coef(-1:,-1:,-1:)
        ! Identidad de fase: el gas NO recibe Boussinesq (su rho(T) de gas
        ! ideal ya aporta la flotabilidad; sumarle beta del acero la
        ! duplicaba — hallazgo 3.13)
        logical, intent(in)          :: is_gas
        real(dp), intent(out)        :: res_ur, res_uth, res_uz

        ! Solve each component
        call solve_momentum_component(ph%ur, ph_old%ur, ph_other%ur, Kexch, &
                                       ph, ph_other, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'ur', res_ur)

        call solve_momentum_component(ph%uth, ph_old%uth, ph_other%uth, Kexch, &
                                       ph, ph_other, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'uth', res_uth)

        call solve_momentum_component(ph%uz, ph_old%uz, ph_other%uz, Kexch, &
                                       ph, ph_other, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'uz', res_uz)

    end subroutine solve_momentum_3d

    !---------------------------------------------------------------------------
    ! Single momentum component solver (MPI-aware)
    !---------------------------------------------------------------------------
    subroutine solve_momentum_component(vel, vel_old, vel_other, Kexch, &
                                         ph, ph_other, sh, m, cfg, &
                                         alpha_q, drag_coef, is_gas, comp, residual)
        use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid, &
            ws_pcorr_g, ws_pcorr_valid, &
            ws_ud_r, ws_ud_th, ws_ud_z, ws_pv_active, ws_pv_valid, &
            aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su
        real(dp), intent(inout)      :: vel(-1:,-1:,-1:)
        real(dp), intent(in)         :: vel_old(-1:,-1:,-1:)
        real(dp), intent(in)         :: vel_other(-1:,-1:,-1:)
        real(dp), intent(in)         :: Kexch(-1:,-1:,-1:)
        type(phase_t), intent(inout) :: ph
        type(phase_t), intent(in)    :: ph_other
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        real(dp), intent(in)         :: drag_coef(-1:,-1:,-1:)
        logical, intent(in)          :: is_gas
        character(len=*), intent(in) :: comp
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: mu_f, vol, alpha_f, rho_vol_dt
        real(dp) :: dp_dr, dp_dth, dp_dz, src_extra, aP_extra
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax, ok_bot, ok_top
        ! Presion que ve ESTA fase: la del Poisson, y para el gas ademas la
        ! correccion de superficie libre (ws_pcorr_g, mod_workspace)
        real(dp), allocatable :: pf(:,:,:)

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        ! Allocate coefficient arrays (with same dimensions as fields)
        call ensure_workspace(m)
        allocate(pf, mold=sh%p)
        pf = sh%p   ! (F2.3: la superficie libre se trata en gas_pgrad_z, no en p)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        ! Loop over local cells only
        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    vol = m%vol(i,j,k)
                    alpha_f = max(alpha_q(i,j,k), SMALL)

                    ! Fase por debajo del umbral hidrodinámico: velocidad 0
                    ! (C2.2, ALPHA_FLOW_CUTOFF; antes vel=vel_old con umbral
                    ! 1e-6 dejaba celdas casi vacías con aP diminuto en el
                    ! acople de presión)
                    ! LIQUIDO DISPERSO (Bug 15): sin momento propio; se mueve
                    ! con el gas mas la sedimentacion terminal (drift-flux,
                    ! Manninen 1996). Cubre tambien alpha < ALPHA_FLOW_CUTOFF.
                    if (.not. is_gas .and. ws_liq_cont_valid) then
                        if (.not. ws_liq_cont(i,j,k)) then
                            aP(i,j,k) = 1.0_dp
                            if (alpha_q(i,j,k) <= 0.0_dp) then
                                Su(i,j,k) = 0.0_dp
                            else
                                select case (comp)
                                case ('ur');  Su(i,j,k) = ws_ud_r(i,j,k)
                                case ('uth'); Su(i,j,k) = ws_ud_th(i,j,k)
                                case default; Su(i,j,k) = ws_ud_z(i,j,k)
                                end select
                            end if
                            cycle
                        end if
                    end if
                    if (alpha_q(i,j,k) < ALPHA_FLOW_CUTOFF) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = 0.0_dp
                        cycle
                    end if

                    rho_vol_dt = alpha_f * ph%rho(i,j,k) * vol / cfg%dt

                    ! Diffusion coefficients (viscous)
                    Dw = 0.0_dp; De = 0.0_dp; Ds = 0.0_dp; Dn = 0.0_dp
                    Db = 0.0_dp; Dt = 0.0_dp
                    ! West
                    if (m%cell_type(i-1,j,k) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i-1,j,k))
                            Dw = alpha_f * mu_f * m%Ar(i-1,j,k) / (0.5_dp*(m%dr(i)+m%dr(i-1)))
                        end if
                    ! East
                    if (m%cell_type(i+1,j,k) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i+1,j,k))
                            De = alpha_f * mu_f * m%Ar(i,j,k) / (0.5_dp*(m%dr(i)+m%dr(i+1)))
                        end if
                    ! South (theta-)
                    mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,jm,k))
                    Ds = alpha_f * mu_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jm)))
                    ! North (theta+)
                    mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,jp,k))
                    Dn = alpha_f * mu_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jp)))
                    ! Bottom
                    if (m%cell_type(i,j,k-1) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,j,k-1))
                            Db = alpha_f * mu_f * m%Az(i,j,k-1) / (0.5_dp*(m%dz(k)+m%dz(k-1)))
                        end if
                    ! Top
                    if (m%cell_type(i,j,k+1) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,j,k+1))
                            Dt = alpha_f * mu_f * m%Az(i,j,k) / (0.5_dp*(m%dz(k)+m%dz(k+1)))
                        end if

                    ! Flujos convectivos de cara únicos (C2.2)
                    call face_mass_fluxes(alpha_q, ph%rho, ph%ur, ph%uth, &
                        ph%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)

                    ! Upwind coefficients
                    aW(i,j,k) = Dw + max( Fw, 0.0_dp)
                    aE(i,j,k) = De + max(-Fe, 0.0_dp)
                    aS(i,j,k) = Ds + max( Fs, 0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn, 0.0_dp)
                    aB(i,j,k) = Db + max( Fb, 0.0_dp)
                    aT(i,j,k) = Dt + max(-Ft, 0.0_dp)

                    ! Pressure gradient and extra cylindrical sources
                    dp_dr = 0.0_dp; dp_dth = 0.0_dp; dp_dz = 0.0_dp
                    src_extra = 0.0_dp
                    aP_extra = 0.0_dp

                    select case (comp)
                    case ('ur')
                        dp_dr = pgrad(pf(i-1,j,k), pf(i,j,k), pf(i+1,j,k), &
                                      m%r(i-1), m%r(i), m%r(i+1), &
                                      i > 1    .and. pv_ok(i-1,j,k), &
                                      i < iend .and. pv_ok(i+1,j,k))
                        ! Centrifugal: +rho*u_th^2/r  +  Lorentz r-stirring
                        src_extra = alpha_f * ph%rho(i,j,k) * ph%uth(i,j,k)**2 / m%r(i) &
                                  + sh%F_lorentz_r(i,j,k)
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dr + src_extra) * vol

                    case ('uth')
                        ! theta desenrollada en halos: la diferencia es
                        ! correcta también en la costura (el parche
                        ! merge(jp<jm) anterior nunca se activaba: comparaba
                        ! ÍNDICES, y jp=j+1 > jm=j-1 siempre)
                        dp_dth = pgrad(pf(i,jm,k), pf(i,j,k), pf(i,jp,k), &
                                       m%r(i) * m%theta(jm), m%r(i) * m%theta(j), &
                                       m%r(i) * m%theta(jp), &
                                       pv_ok(i,jm,k), pv_ok(i,jp,k))
                        ! Coriolis -rho*ur*uth/r, LINEAL en uth: linearización
                        ! de Patankar — implícito (aP_extra) cuando el
                        ! coeficiente es positivo. Explícito cerraba el lazo de
                        ! realimentación con el término centrífugo
                        ! (uth^2/r -> ur -> ur*uth/r) y las velocidades
                        ! divergían (medido |u| -> 1e14).
                        aP_extra = alpha_f * ph%rho(i,j,k) * &
                                   max(ph%ur(i,j,k), 0.0_dp) / m%r(i) * vol
                        src_extra = -alpha_f * ph%rho(i,j,k) * &
                                    min(ph%ur(i,j,k), 0.0_dp) * ph%uth(i,j,k) / m%r(i) &
                                  + sh%F_lorentz_th(i,j,k)
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dth + src_extra) * vol

                    case ('uz')
                        ! Central salvo en frontera FÍSICA; en interfaces de
                        ! rank el halo de p es válido (hallazgo 3.6)
                        ok_bot = (k > kstart .or. .not. at_zmin) .and. pv_ok(i,j,k-1)
                        ok_top = (k < kend   .or. .not. at_zmax) .and. pv_ok(i,j,k+1)
                        if (is_gas) then
                            ! El GAS no carga el peso del liquido (F2.3): en
                            ! las caras verticales su gradiente es
                            ! (p_N - p_P)/dz + (alpha_l rho_l)_f g_eff. Con
                            ! una sola p por celda, la p de una celda con
                            ! liquido esta sobre la linea hidrostatica de
                            ! la MEZCLA; el gas de al lado leia ese salto
                            ! como fuerza (chorro fantasma de 25 m/s sobre
                            ! un bano en reposo, bath_test). Es la flotacion
                            ! de la fase ligera en la mezcla, fisica para
                            ! burbujas pero espuria en una interfase grande
                            ! (AIAD/LIM la suprimen con arrastre); aqui se
                            ! quita del gradiente. Media de las caras que
                            ! existen, como pgrad.
                            dp_dz = gas_pgrad_z(i, j, k, ok_bot, ok_top)
                        else
                            dp_dz = pgrad(pf(i,j,k-1), pf(i,j,k), pf(i,j,k+1), &
                                          m%z(k-1), m%z(k), m%z(k+1), ok_bot, ok_top)
                        end if
                        ! Gravity + arc impingement; Boussinesq SOLO líquido
                        ! (rho constante): el gas ya tiene flotabilidad vía
                        ! rho(T) de gas ideal (hallazgo 3.13)
                        src_extra = -alpha_f * ph%rho(i,j,k) * GRAVITY &
                                  + sh%S_arc_mom(i,j,k)
                        if (.not. is_gas) then
                            src_extra = src_extra &
                                  + alpha_f * ph%rho(i,j,k) * cfg%beta_expansion &
                                    * GRAVITY * (ph%T(i,j,k) - cfg%T_ambient)
                        end if
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dz + src_extra) * vol
                    end select

                    ! Central coefficient (drag de Ergun IMPLÍCITO: coef*vol —
                    ! incondicionalmente estable, mismo punto fijo que la
                    ! versión explícita divergente; hallazgo 3.11)
                    ! Intercambio de momentum entre fases (C2.4), implícito
                    Su(i,j,k) = Su(i,j,k) + Kexch(i,j,k) * vel_other(i,j,k) * vol

                    ! Forma ACOTADA de Patankar (sin dF; ver mod_energy)
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_vol_dt &
                               + drag_coef(i,j,k) * vol + aP_extra &
                               + Kexch(i,j,k) * vol
                end do
            end do
        end do

        ! Boundary conditions
        call apply_momentum_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, comp)

        ! Residual del ITERADO ENTRANTE (misma semantica que la energia,
        ! Plan C F1): mide si la velocidad que queda en pie satisface su
        ! ecuacion de momento. Se calculaba con el campo recien resuelto
        ! (post-TDMA): ~1e-17 siempre, y con res_cont = residual del CG
        ! (<= 1e-5 por construccion) el lazo externo declaraba convergencia
        ! en UNA iteracion en todo regimen de flujo — el acople P-V nunca se
        ! iteraba (bath_test: outer=1 en todos los pasos).
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, vel, m)

        ! Solve with MPI-aware TDMA
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, vel, m, cfg%max_inner_mom)

        ! (C2.1: la sub-relajación se hace en el LAZO EXTERNO contra el
        ! iterado anterior — ver multiphase_iteration/relax_field. Relajar
        ! aquí contra vel_old del paso temporal sesgaba el punto fijo.)

        ! Store aP for Rhie-Chow
        select case (comp)
        case ('ur');  ph%aP_ur = aP
        case ('uth'); ph%aP_uth = aP
        case ('uz');  ph%aP_uz = aP
        end select



        deallocate(pf)

    contains

        ! La celda tiene presion de fluido definida? (Bug 16)
        pure logical function pv_ok(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            if (ws_pv_valid) then
                pv_ok = ws_pv_active(ii,jj,kk)
            else
                pv_ok = (m%cell_type(ii,jj,kk) /= 0)
            end if
        end function pv_ok

        ! Peso del liquido por unidad de volumen en la cara entre (k-1,k)
        ! (media de celdas, con Boussinesq del liquido)
        pure function liq_weight_f(ii, jj, ka, kb) result(w)
            integer, intent(in) :: ii, jj, ka, kb
            real(dp) :: w
            ! Solo el liquido CONTINUO (bano, pelicula: interfase grande,
            ! morfologia AIAD): el disperso (niebla) SI carga al gas via
            ! el arrastre de las gotas, con la flotacion de la mezcla que lo
            ! compensa (test_dispersed_liquid caso 4).
            w = 0.5_dp * GRAVITY * ( &
                merge(1.0_dp, 0.0_dp, cont_ok(ii,jj,ka)) * &
                ph_other%alpha(ii,jj,ka) * ph_other%rho(ii,jj,ka) * &
                    (1.0_dp - cfg%beta_expansion * (ph_other%T(ii,jj,ka) - cfg%T_ambient)) + &
                merge(1.0_dp, 0.0_dp, cont_ok(ii,jj,kb)) * &
                ph_other%alpha(ii,jj,kb) * ph_other%rho(ii,jj,kb) * &
                    (1.0_dp - cfg%beta_expansion * (ph_other%T(ii,jj,kb) - cfg%T_ambient)))
        end function liq_weight_f

        pure logical function cont_ok(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            if (ws_liq_cont_valid) then
                cont_ok = ws_liq_cont(ii,jj,kk)
            else
                cont_ok = (ph_other%alpha(ii,jj,kk) >= ALPHA_LIQ_CONT)
            end if
        end function cont_ok

        ! Gradiente vertical que ve el gas: caras con el peso del liquido
        ! restado (ver arriba); media de las caras existentes
        pure function gas_pgrad_z(ii, jj, kk, okm, okp) result(g)
            integer, intent(in) :: ii, jj, kk
            logical, intent(in) :: okm, okp
            real(dp) :: g, gb, gt
            gb = 0.0_dp; gt = 0.0_dp
            if (okm) gb = (pf(ii,jj,kk) - pf(ii,jj,kk-1)) / (m%z(kk) - m%z(kk-1)) &
                          + liq_weight_f(ii, jj, kk-1, kk)
            if (okp) gt = (pf(ii,jj,kk+1) - pf(ii,jj,kk)) / (m%z(kk+1) - m%z(kk)) &
                          + liq_weight_f(ii, jj, kk, kk+1)
            if (okm .and. okp) then
                g = 0.5_dp * (gb + gt)
            else if (okp) then
                g = gt
            else if (okm) then
                g = gb
            else
                g = 0.0_dp
            end if
        end function gas_pgrad_z

    end subroutine solve_momentum_component

end module mod_momentum_3d
