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
    use mod_probe, only: probe_active_now, probe_current_step
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Solve all three momentum components for a single phase
    !---------------------------------------------------------------------------
    subroutine solve_momentum_3d(ph, ph_old, ph_other, Kexch, sh, m, cfg, &
                                  alpha_q, drag_coef, is_gas, &
                                  res_ur, res_uth, res_uz, mdot_l)
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
        ! Fuente de masa de la fase [kg/s por celda] (M24): fusion para el
        ! liquido, gas de las reacciones para el gas; entra con velocidad nula
        real(dp), intent(in), optional :: mdot_l(-1:,-1:,-1:)
        real(dp), allocatable :: md(:,:,:)

        allocate(md, mold=alpha_q); md = 0.0_dp
        if (present(mdot_l)) md = max(mdot_l, 0.0_dp)

        ! Solve each component
        call solve_momentum_component(ph%ur, ph_old%ur, ph_other%ur, Kexch, &
                                       ph, ph_other, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'ur', res_ur, &
                                       ph_old%alpha, ph_old%rho, md)

        call solve_momentum_component(ph%uth, ph_old%uth, ph_other%uth, Kexch, &
                                       ph, ph_other, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'uth', res_uth, &
                                       ph_old%alpha, ph_old%rho, md)

        call solve_momentum_component(ph%uz, ph_old%uz, ph_other%uz, Kexch, &
                                       ph, ph_other, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'uz', res_uz, &
                                       ph_old%alpha, ph_old%rho, md)
        deallocate(md)

    end subroutine solve_momentum_3d

    !---------------------------------------------------------------------------
    ! Single momentum component solver (MPI-aware)
    !---------------------------------------------------------------------------
    subroutine solve_momentum_component(vel, vel_old, vel_other, Kexch, &
                                         ph, ph_other, sh, m, cfg, &
                                         alpha_q, drag_coef, is_gas, comp, residual, &
                                         alpha_old, rho_old, mdot_m)
        use mod_workspace, only: ensure_workspace, own_weight_face, ws_liq_cont, ws_liq_cont_valid, &
                                 liq_own_weight, liq_w, mix_cell_weight, liq_cont_fallback, bed_rel_face, &
            ws_Fr, ws_Fth, ws_Fz, ws_flux_valid, ws_trg, ws_trl, &
            ws_Fg_r, ws_Fg_th, ws_Fg_z, ws_Fg_valid, ws_bed, ws_bed_gas, ws_bed_liq, ws_bedl_f, ws_bub, ws_bub_f, ws_bed_valid, &
            ws_ud_r, ws_ud_th, ws_ud_z, ws_pv_active, ws_pv_valid, &
            ws_pv_liq, ws_pv_liq_valid, ws_pv_liq_id, &
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
        real(dp), intent(in)         :: alpha_old(-1:,-1:,-1:)
        real(dp), intent(in)         :: rho_old(-1:,-1:,-1:)
        real(dp), intent(in)         :: mdot_m(-1:,-1:,-1:)
        logical :: cons_l, cons_g, cons
        ! fuerza vertical balanceada por caras (liq_balanced_force)
        logical :: lbf_m

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: mu_f, vol, alpha_f, rho_vol_dt
        real(dp) :: dp_dr, dp_dth, dp_dz, src_extra, aP_extra
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax, ok_bot, ok_top
        ! Presion que ve ESTA fase: la del Poisson, y para el gas ademas la
        ! correccion de superficie libre del gas: gas_pgrad_z (F2.3)
        real(dp), allocatable :: pf(:,:,:)
        ! aP fisico del anillo del eje (A15)
        real(dp) :: aP_axis(lbound(vel,2):ubound(vel,2), lbound(vel,3):ubound(vel,3))
        ! Sonda de balance de momento de una celda (cfg%probe_cell_*)
        integer  :: pi_, pj_, pk_
        logical  :: probe_here, probe_own

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)
        lbf_m = cfg%liq_balanced_force .and. .not. cfg%pc_fs_liquid_gradient

        ! Allocate coefficient arrays (with same dimensions as fields)
        call ensure_workspace(m)
        ! (M11-1pv) transitorio de esta fase para F2.31: 0 donde no se ensambla
        if (is_gas) then
            ws_trg = 0.0_dp
        else
            ws_trl = 0.0_dp
        end if
        allocate(pf, mold=sh%p)
        pf = sh%p   ! (F2.3: la superficie libre se trata en gas_pgrad_z, no en p)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        ! Sonda de BALANCE: solo uz del liquido, dentro de la ventana de
        ! pasos y en el rank duenio de la celda pedida.
        probe_here = .false.; pi_ = 0; pj_ = 0; pk_ = 0
        if (cfg%probe_cell_k > 0 .and. comp == 'uz' .and. .not. is_gas) then
            if (probe_active_now(cfg)) then
                call global_to_local(m, cfg%probe_cell_i, cfg%probe_cell_j, &
                                     cfg%probe_cell_k, pi_, pj_, pk_, probe_own)
                probe_here = probe_own
            end if
        end if

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
                        ! FASE EVANESCENTE (F2.20). El modelo de dos fluidos
                        ! pierde la hiperbolicidad cuando una fase desaparece
                        ! (la minoritaria obedece una dinamica sin presion, su
                        ! jacobiano no es diagonalizable): es la "phase
                        ! appearance and disappearance" de la termohidraulica
                        ! nuclear. La literatura NO la para: AUSM+ para dos
                        ! fluidos (Paillere et al. 2003) ATA su velocidad a la
                        ! de la otra fase por debajo de alpha_min, y CATHARE /
                        ! NEPTUNE acondicionan los terminos de friccion para
                        ! dar "a proper mechanical model for the coupling of
                        ! the residual phases". Poner u = 0 era un cero
                        ! ARTIFICIAL: en la cara, el promedio con la velocidad
                        ! del vecino inyectaba medio caudal a traves de la
                        ! superficie de un bano en reposo (cuatro intentos
                        ! fallidos en docs/dev-history, F2.17-F2.19).
                        ! El liquido disperso ya seguia esta regla desde el
                        ! Bug 15 (su velocidad es el drift, no cero); esto se
                        ! la da tambien al gas.
                        aP(i,j,k) = max(alpha_q(i,j,k), ALPHA_PHASE_MIN) &
                                    * ph%rho(i,j,k) * vol / cfg%dt &
                                    + (drag_coef(i,j,k) + Kexch(i,j,k)) * vol
                        if (is_gas) then
                            ws_trg(i,j,k) = max(alpha_q(i,j,k), ALPHA_PHASE_MIN) * ph%rho(i,j,k) * vol / cfg%dt
                        else
                            ws_trl(i,j,k) = max(alpha_q(i,j,k), ALPHA_PHASE_MIN) * ph%rho(i,j,k) * vol / cfg%dt
                        end if
                        Su(i,j,k) = aP(i,j,k) * vel_other(i,j,k)
                        cycle
                    end if

                    ! Liquido CONTINUO con los flujos CONSERVATIVOS que
                    ! transportaron alpha (ws_Fr/Fth/Fz, los de la energia del
                    ! liquido) y transitorio con alpha^n: la forma exacta con la
                    ! continuidad discreta restada (auditoria M24/M30). Antes:
                    ! flujos reconstruidos de velocidades de centro y aP
                    ! acotado sin dF -> u_P * (desbalance de masa) era una
                    ! fuente ficticia de momento; y alpha^k en el transitorio
                    ! hacia figurar la masa recien llegada como si tuviera la
                    ! velocidad vieja. La masa fundida entra con u = 0
                    ! (aP += mdot). Flujos del iterado externo anterior.
                    ! GAS (auditoria M24, gas): la misma forma con los flujos
                    ! de MASA conservativos de su Poisson (ws_Fg_*, volumetrico
                    ! corregido por la densidad del dador) y transitorio con
                    ! (alpha rho)^n; la masa de las reacciones entra con u = 0.
                    ! Antes: interpolacion simetrica de alpha rho u de centro.
                    cons_l = (.not. is_gas) .and. ws_flux_valid
                    cons_g = is_gas .and. ws_Fg_valid
                    cons = cons_l .or. cons_g
                    if (cons) then
                        rho_vol_dt = max(alpha_old(i,j,k), ALPHA_PHASE_MIN) &
                                     * rho_old(i,j,k) * vol / cfg%dt
                    else
                        rho_vol_dt = alpha_f * ph%rho(i,j,k) * vol / cfg%dt
                    end if

                    ! Diffusion coefficients (viscous)
                    ! F2.24 (2026-09-29): la fraccion de fase de la CARA es la
                    ! media ARMONICA de las dos celdas (aface), no la de la
                    ! celda propia. Es la MISMA regla que ya rige en la
                    ! energia ("una celda sin fase no intercambia esa fase con
                    ! nadie", mod_energy_3d::aface): simetrica, telescopa, y
                    ! NULA hacia una vecina sin la fase.
                    !
                    ! Con alpha_P sola, una celda de bano (alpha_l = 0.58)
                    ! tenia conductancia viscosa PLENA hacia la celda de
                    ! arriba con alpha_l = 0, y esa celda vacia lleva la
                    ! velocidad de DRIFT del liquido disperso, que con gotas
                    ! de 2 mm en gas a 2000 K vale -49.7 m/s (U_SETTLE_MAX).
                    ! Medido con la sonda de momento en el arranque del
                    ! colapso (celda 13,1,6 de la malla media, 208.8-209.1 s):
                    ! a_nb crece de 2.4 a 959 mientras aP no se mueve, y la
                    ! superficie del bano es arrastrada de 0 a U_LIQ_MAX en
                    ! 0.24 s. Ninguna fuerza local lo explica (presion +18,
                    ! gravedad -66, arrastre del gas -4.7e3 frente a aP 5.6e3).
                    Dw = 0.0_dp; De = 0.0_dp; Ds = 0.0_dp; Dn = 0.0_dp
                    Db = 0.0_dp; Dt = 0.0_dp
                    ! West
                    if (m%cell_type(i-1,j,k) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i-1,j,k))
                            Dw = aface(alpha_q(i,j,k), alpha_q(i-1,j,k)) * mu_f &
                                 * m%Ar(i-1,j,k) / (0.5_dp*(m%dr(i)+m%dr(i-1)))
                        end if
                    ! East
                    if (m%cell_type(i+1,j,k) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i+1,j,k))
                            De = aface(alpha_q(i,j,k), alpha_q(i+1,j,k)) * mu_f &
                                 * m%Ar(i,j,k) / (0.5_dp*(m%dr(i)+m%dr(i+1)))
                        end if
                    ! South (theta-)
                    mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,jm,k))
                    Ds = aface(alpha_q(i,j,k), alpha_q(i,jm,k)) * mu_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jm)))
                    ! North (theta+)
                    mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,jp,k))
                    Dn = aface(alpha_q(i,j,k), alpha_q(i,jp,k)) * mu_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jp)))
                    ! Bottom
                    if (m%cell_type(i,j,k-1) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,j,k-1))
                            Db = aface(alpha_q(i,j,k), alpha_q(i,j,k-1)) * mu_f &
                                 * m%Az(i,j,k-1) / (0.5_dp*(m%dz(k)+m%dz(k-1)))
                        end if
                    ! Top
                    if (m%cell_type(i,j,k+1) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,j,k+1))
                            Dt = aface(alpha_q(i,j,k), alpha_q(i,j,k+1)) * mu_f &
                                 * m%Az(i,j,k) / (0.5_dp*(m%dz(k)+m%dz(k+1)))
                        end if

                    ! Flujos convectivos de cara (C2.2) con alpha DONOR-CELL
                    ! (F2.24, 2026-09-29). Es la misma correccion que ya lleva
                    ! la energia del liquido: la interpolacion SIMETRICA de
                    ! alpha hace que una celda VACIA "entregue" 1/2 alpha_P rho
                    ! u de caudal fantasma a traves de la cara, y ese
                    ! coeficiente multiplica la velocidad de la celda vacia.
                    !
                    ! En momento eso es una REALIMENTACION POSITIVA, no solo
                    ! una inconsistencia: el coeficiente de la cara superior
                    ! vale aT = D + (1/2) alpha_P rho |u_P| A, o sea que CRECE
                    ! con la propia velocidad, y multiplica la velocidad de
                    ! drift de la celda vacia (-49.7 m/s = U_SETTLE_MAX para
                    ! gotas de 2 mm en gas a 2000 K). El termino entra al
                    ! segundo miembro como C u_P con C = 49.7 (1/2) alpha_P
                    ! rho A ~ 1.2e3 frente a aP ~ 6.3e3: 18 % de ganancia por
                    ! iteracion. Medido con la sonda de momento en el arranque
                    ! del colapso (celda 13,1,6, 208.8-209.1 s): a_nb crece de
                    ! 2.4 a 959 mientras aP no se mueve, la velocidad media de
                    ! las vecinas es -24 m/s con la celda aun a -0.85, y la
                    ! superficie del bano llega a U_LIQ_MAX en 0.24 s con un
                    ! e-folding de 50 ms. Con donor-cell, una vecina sin fase
                    ! no entrega nada: F = 0.
                    ! Solo el LIQUIDO: es la fase cuyas celdas vacias llevan
                    ! una velocidad de DRIFT grande (-49.7 m/s). El gas usa
                    ! los flujos conservativos de su Poisson (cons_g, M24):
                    ! la forma simetrica anterior frenaba con su caudal
                    ! fantasma el modo par-impar que la fuerza balanceada
                    ! elimino; sin ella, el conservativo no es estable.
                    if (cons_l) then
                        Fw = ws_Fr(i-1,j,k);  Fe = ws_Fr(i,j,k)
                        Fs = ws_Fth(i,jm,k);  Fn = ws_Fth(i,j,k)
                        Fb = ws_Fz(i,j,k-1);  Ft = ws_Fz(i,j,k)
                    else if (cons_g) then
                        Fw = ws_Fg_r(i-1,j,k);  Fe = ws_Fg_r(i,j,k)
                        Fs = ws_Fg_th(i,jm,k);  Fn = ws_Fg_th(i,j,k)
                        Fb = ws_Fg_z(i,j,k-1);  Ft = ws_Fg_z(i,j,k)
                    else if (is_gas) then
                        call face_mass_fluxes(alpha_q, ph%rho, ph%ur, ph%uth, &
                            ph%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                    else
                        call face_mass_fluxes_noalpha(ph%rho, ph%ur, ph%uth, &
                            ph%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                        Fw = donor_a(Fw, alpha_q(i-1,j,k), alpha_q(i,j,k))
                        Fe = donor_a(Fe, alpha_q(i,j,k),   alpha_q(i+1,j,k))
                        Fs = donor_a(Fs, alpha_q(i,jm,k),  alpha_q(i,j,k))
                        Fn = donor_a(Fn, alpha_q(i,j,k),   alpha_q(i,jp,k))
                        Fb = donor_a(Fb, alpha_q(i,j,k-1), alpha_q(i,j,k))
                        Ft = donor_a(Ft, alpha_q(i,j,k),   alpha_q(i,j,k+1))
                    end if

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
                        dp_dr = pgrad_fs(pf(i-1,j,k), pf(i,j,k), pf(i+1,j,k), &
                                      m%r(i-1), m%r(i), m%r(i+1), &
                                      (i > istart .or. .not. at_rmin) .and. pv_ok(i-1,j,k), &
                                      (i < iend   .or. .not. at_rmax) .and. pv_ok(i+1,j,k), &
                                      fs_nb(i-1,j,k), fs_nb(i+1,j,k), m%rf(i-1), m%rf(i))
                        ! Centrifugal: +rho*u_th^2/r  +  Lorentz r-stirring
                        src_extra = alpha_f * ph%rho(i,j,k) * ph%uth(i,j,k)**2 / m%r(i)
                        ! Laplaciano VECTORIAL en cilindricas (auditoria M27):
                        ! mu [lap u_r - u_r/r^2 - (2/r^2) du_th/dth]; -u_r/r^2
                        ! implicito (diagonal), el acople con u_th explicito
                        aP_extra = aP_extra + max(alpha_q(i,j,k), 0.0_dp) * ph%mu_eff(i,j,k) &
                                   / m%r(i)**2 * vol
                        src_extra = src_extra - max(alpha_q(i,j,k), 0.0_dp) * ph%mu_eff(i,j,k) &
                                    * 2.0_dp / m%r(i)**2 * (ph%uth(i,jp,k) - ph%uth(i,jm,k)) &
                                    / (m%theta(jp) - m%theta(jm))
                        ! Lorentz SOLO en el liquido (auditoria M11: se sumaba
                        ! tambien al gas -> fuerza contada dos veces)
                        if (.not. is_gas) src_extra = src_extra + sh%F_lorentz_r(i,j,k)
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dr + src_extra) * vol

                    case ('uth')
                        ! theta desenrollada en halos: la diferencia es
                        ! correcta también en la costura (el parche
                        ! merge(jp<jm) anterior nunca se activaba: comparaba
                        ! ÍNDICES, y jp=j+1 > jm=j-1 siempre)
                        dp_dth = pgrad_fs(pf(i,jm,k), pf(i,j,k), pf(i,jp,k), &
                                       m%r(i) * m%theta(jm), m%r(i) * m%theta(j), &
                                       m%r(i) * m%theta(jp), &
                                       pv_ok(i,jm,k), pv_ok(i,jp,k), &
                                       fs_nb(i,jm,k), fs_nb(i,jp,k), &
                                       m%r(i) * m%thetaf(jm), m%r(i) * m%thetaf(j))
                        ! Coriolis -rho*ur*uth/r, LINEAL en uth: linearización
                        ! de Patankar — implícito (aP_extra) cuando el
                        ! coeficiente es positivo. Explícito cerraba el lazo de
                        ! realimentación con el término centrífugo
                        ! (uth^2/r -> ur -> ur*uth/r) y las velocidades
                        ! divergían (medido |u| -> 1e14).
                        aP_extra = alpha_f * ph%rho(i,j,k) * &
                                   max(ph%ur(i,j,k), 0.0_dp) / m%r(i) * vol
                        src_extra = -alpha_f * ph%rho(i,j,k) * &
                                    min(ph%ur(i,j,k), 0.0_dp) * ph%uth(i,j,k) / m%r(i)
                        if (.not. is_gas) src_extra = src_extra + sh%F_lorentz_th(i,j,k)
                        ! Laplaciano vectorial (M27): mu [lap u_th - u_th/r^2
                        ! + (2/r^2) du_r/dth]
                        aP_extra = aP_extra + max(alpha_q(i,j,k), 0.0_dp) * ph%mu_eff(i,j,k) &
                                   / m%r(i)**2 * vol
                        src_extra = src_extra + max(alpha_q(i,j,k), 0.0_dp) * ph%mu_eff(i,j,k) &
                                    * 2.0_dp / m%r(i)**2 * (ph%ur(i,jp,k) - ph%ur(i,jm,k)) &
                                    / (m%theta(jp) - m%theta(jm))
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
                        else if (lbf_m) then
                            ! FUERZA BALANCEADA POR CARAS del liquido continuo
                            ! (oct-2026; Francois et al. 2006, Mencinger & Zun
                            ! 2007, JCP 221). Con una sola p por celda, p tiene
                            ! un QUIEBRE en la superficie libre (la cara bajo la
                            ! celda de superficie pesa la MEZCLA, 0.7 rho_l en
                            ! bath_test) y la diferencia central de un p con
                            ! quiebre no equilibra un peso de celda uniforme:
                            ! la celda llena bajo la superficie quedaba con 11
                            ! kPa/m netos hacia abajo en el estado hidrostatico
                            ! exacto. Esa era la fuente del modo par-impar del
                            ! bano (u_z alternando, p en escalera; F1b). El
                            ! liquido ve ahora la presion REDUCIDA del gas
                            ! (F2.3): media de las caras de (p_N - p_P)/dz + W_f,
                            ! con W_f el peso del liquido continuo en la cara, y
                            ! su peso (con Boussinesq) va DENTRO de W_f, no como
                            ! fuerza de celda. La suma de fases da la mezcla
                            ! balanceada por caras; entre el liquido continuo y
                            ! el gas no queda flotacion relativa (interfase
                            ! grande, como ya hacia F2.3 con el gas). El Rhie-
                            ! Chow del liquido usa la misma forma (mod_pressure).
                            dp_dz = gas_pgrad_z(i, j, k, ok_bot, ok_top)
                        else
                            ! D2.5: superficie libre -> la presion del gas
                            ! actua en la cara (ver pgrad_fs)
                            dp_dz = pgrad_fs(pf(i,j,k-1), pf(i,j,k), pf(i,j,k+1), &
                                          m%z(k-1), m%z(k), m%z(k+1), ok_bot, ok_top, &
                                          fs_nb(i,j,k-1), fs_nb(i,j,k+1), m%zf(k-1), m%zf(k))
                        end if
                        ! Gravity + arc impingement; Boussinesq SOLO líquido
                        ! (rho constante): el gas ya tiene flotabilidad vía
                        ! rho(T) de gas ideal (hallazgo 3.13)
                        src_extra = -alpha_f * ph%rho(i,j,k) * GRAVITY &
                                  + sh%S_arc_mom(i,j,k)
                        ! fuerza balanceada: el peso del gas va en W_f y su
                        ! flotacion relativa en el lecho en las caras (bed_rel_f)
                        if (is_gas .and. lbf_m) src_extra = sh%S_arc_mom(i,j,k)
                        if (.not. is_gas) then
                            src_extra = src_extra &
                                  + alpha_f * ph%rho(i,j,k) * cfg%beta_expansion &
                                    * GRAVITY * (ph%T(i,j,k) - cfg%T_ref_boussinesq) &
                                  + sh%F_lorentz_z(i,j,k)
                            ! fuerza balanceada: el peso del liquido esta en W_f
                            ! y su flotacion relativa en el lecho en las caras
                            if (lbf_m) src_extra = sh%S_arc_mom(i,j,k) + sh%F_lorentz_z(i,j,k)
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
                    if (is_gas) then
                        ws_trg(i,j,k) = rho_vol_dt
                    else
                        ws_trl(i,j,k) = rho_vol_dt
                    end if
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_vol_dt &
                               + drag_coef(i,j,k) * vol + aP_extra &
                               + Kexch(i,j,k) * vol + wall_shear() &
                               + merge(mdot_m(i,j,k), 0.0_dp, cons)

                    if (probe_here) then
                        if (i == pi_ .and. j == pj_ .and. k == pk_) then
                            write(*,'(A,I8,A,3I4,A,ES11.3,A,ES11.3,A,ES11.3, &
                                     &A,ES11.3,A,ES11.3,A,ES11.3,A,ES11.3, &
                                     &A,ES11.3,A,ES11.3,A,ES11.3,A,ES11.3)') &
                                '[PROBE-MOM] paso', probe_current_step(), &
                                ' celda', cfg%probe_cell_i, cfg%probe_cell_j, &
                                cfg%probe_cell_k, &
                                ' al=', alpha_q(i,j,k), &
                                ' uz=', vel(i,j,k), &
                                ' uz_otra=', vel_other(i,j,k), &
                                ' | transit=', rho_vol_dt * vel_old(i,j,k), &
                                ' presion=', -alpha_f * dp_dz * vol, &
                                ' grav+arco=', src_extra * vol, &
                                ' K*u_otra=', Kexch(i,j,k) * vel_other(i,j,k) * vol, &
                                ' | aP=', aP(i,j,k), &
                                ' a_nb=', aW(i,j,k)+aE(i,j,k)+aS(i,j,k)+aN(i,j,k) &
                                          +aB(i,j,k)+aT(i,j,k), &
                                ' Ergun*V=', drag_coef(i,j,k) * vol, &
                                ' K*V=', Kexch(i,j,k) * vol
                        end if
                    end if
                end do
            end do
        end do

        ! aP FISICO del anillo del eje antes de la fila de relleno de la BC
        ! (u_r = 0 => aP = 1): el Poisson y F2.31 leen aP_ur(1) como
        ! coeficiente real y con el 1 la conductancia de la cara 1-2 era
        ! dimensionalmente arbitraria en todo el eje (auditoria 12-oct-2026, A15)
        if (comp == 'ur' .and. at_rmin) aP_axis = aP(istart,:,:)
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
        case ('ur')
            ph%aP_ur = aP
            if (at_rmin) ph%aP_ur(istart,:,:) = max(aP_axis, SMALL)
        case ('uth'); ph%aP_uth = aP
        case ('uz');  ph%aP_uz = aP
        end select



        deallocate(pf)

    contains

        ! Esfuerzo de PARED (auditoria M23): no deslizamiento u = 0 en la
        ! pared, conductancia de media celda alpha mu A/(delta/2) en la
        ! diagonal de las componentes TANGENCIALES a cada cara de pared (celda
        ! vecina inactiva: tazon, coraza, piso, techo). Antes la conductancia
        ! hacia la pared se ponia a cero: deslizamiento libre en todas partes
        ! aunque la CC decia no-slip. El eje (r = rmin) es simetria: sin pared.
        ! FLOTACION RELATIVA en el LECHO, POR CARAS (auditoria 2 N-C1;
        ! auditoria 3 A3-1 + M3-1, oct-2026). Con la fuerza balanceada ninguna
        ! fase lleva peso de celda: correcto en una interfase grande (bano
        ! estratificado), pero en el lecho (goteo a contracorriente) cada fase
        ! debe recuperar la forma CLASICA -alpha grad p - alpha rho_q g. Se
        ! hace sumando al gradiente reducido de cada cara el termino
        !     B_f = bed_f (w_q,f - W_f),
        ! con bed_f la mascara del lecho en la cara (media), w_q,f el peso
        ! propio de la fase en la cara y W_f el MISMO peso de mezcla del
        ! gradiente reducido: -alpha (g_f + B_f) = -alpha (dp/dz + w_q)_f.
        ! Por caras y no como fuerza de celda (bed_buoyancy, hasta A3-1) para
        ! que el Rhie-Chow lo cancele exactamente (mod_pressure usa la misma
        ! B_f en la cara y en el gradiente de celda; M3-1).
        ! El GAS la lleva SOLO donde es fluido del acople (ws_bed_gas: percola
        ! y alpha_g >= ALPHA_FLOW_CUTOFF): el gas residual de un poro saturado,
        ! con p = hidrostatica del liquido, recibiria alpha_g (rho_l - rho_g) g
        ! (bath_freeze n1/n4 0.58 cuando TODO el gas la llevaba). Sin la
        ! flotacion del gas (hasta A3-1) el gas libre del lecho fijaba
        ! dp/dz = -W (mezcla) y el empuje de drenaje del liquido quedaba
        ! multiplicado por alpha_g/eps (0.03 cerca de saturar: colgado otra
        ! vez) con sobrepresion de poro de int alpha_l drho g/eps dz.
        ! Para el gas la mascara de CARA es el MINIMO de las dos celdas, no la
        ! media: la cara entre el gas libre y un poro saturado (gas atrapado)
        ! o la celda de superficie de un bano con costra (bath_freeze) es una
        ! SUPERFICIE LIBRE y ahi vale el gradiente reducido de F2.3; con la
        ! media el gas de encima recibia 1/4 rho_l g (201 m/s en bath_freeze).
        pure real(dp) function bed_rel_f(ii, jj, ka, kb)
            integer, intent(in) :: ii, jj, ka, kb
            ! (auditoria 6) UNA definicion con el Poisson (mod_workspace::
            ! bed_rel_face; la logica de mascaras y el porque estan alli y en
            ! las notas de arriba)
            if (is_gas) then
                bed_rel_f = bed_rel_face(.true., ii, jj, ka, kb, &
                    ph_other%alpha(ii,jj,ka), ph_other%alpha(ii,jj,kb), &
                    ph%alpha(ii,jj,ka), ph%alpha(ii,jj,kb), own_w(ii, jj, ka), own_w(ii, jj, kb), &
                    liq_weight_f(ii, jj, ka, kb), lbf_m)
            else
                bed_rel_f = bed_rel_face(.false., ii, jj, ka, kb, &
                    ph%alpha(ii,jj,ka), ph%alpha(ii,jj,kb), &
                    ph%alpha(ii,jj,ka), ph%alpha(ii,jj,kb), own_w(ii, jj, ka), own_w(ii, jj, kb), &
                    liq_weight_f(ii, jj, ka, kb), lbf_m)
            end if
        end function bed_rel_f


        ! Peso propio de ESTA fase por unidad de su volumen [N/m3] (Boussinesq
        ! solo en el liquido; el gas lleva rho(p,T))
        pure real(dp) function own_w(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            if (is_gas) then
                own_w = GRAVITY * ph%rho(ii,jj,kk)
            else
                own_w = liq_w(ph%rho(ii,jj,kk), ph%T(ii,jj,kk), cfg%beta_expansion, cfg%T_ref_boussinesq, ii, jj, kk)
            end if
        end function own_w

        function wall_shear() result(ap_w)
            real(dp) :: ap_w, am
            ap_w = 0.0_dp
            am = max(alpha_q(i,j,k), 0.0_dp) * ph%mu_eff(i,j,k)
            if (am <= 0.0_dp) return
            if (comp /= 'ur') then
                if (m%cell_type(i-1,j,k) == 0 .and. .not. (i == istart .and. at_rmin)) &
                    ap_w = ap_w + am * m%Ar(i-1,j,k) / (0.5_dp * m%dr(i))
                if (m%cell_type(i+1,j,k) == 0) &
                    ap_w = ap_w + am * m%Ar(i,j,k) / (0.5_dp * m%dr(i))
            end if
            if (comp /= 'uth') then
                if (m%cell_type(i,j-1,k) == 0) &
                    ap_w = ap_w + am * m%Ath(i,j,k) / (0.5_dp * m%r(i) * m%dtheta(j))
                if (m%cell_type(i,j+1,k) == 0) &
                    ap_w = ap_w + am * m%Ath(i,j,k) / (0.5_dp * m%r(i) * m%dtheta(j))
            end if
            if (comp /= 'uz') then
                if (m%cell_type(i,j,k-1) == 0) &
                    ap_w = ap_w + am * m%Az(i,j,k-1) / (0.5_dp * m%dz(k))
                if (m%cell_type(i,j,k+1) == 0) &
                    ap_w = ap_w + am * m%Az(i,j,k) / (0.5_dp * m%dz(k))
            end if
        end function wall_shear

        ! Flujo de masa donor-cell en una cara orientada de 'lo' (lado -)
        ! a 'hi' (lado +): F>0 va de lo a hi y lleva alpha_lo; F<0 lleva
        ! alpha_hi. Misma definicion que mod_energy_3d::donor.
        pure function donor_a(F, a_lo, a_hi) result(Fd)
            real(dp), intent(in) :: F, a_lo, a_hi
            real(dp) :: Fd
            if (F >= 0.0_dp) then
                Fd = F * a_lo
            else
                Fd = F * a_hi
            end if
        end function donor_a

        ! Fraccion de fase EN LA CARA para la conductancia difusiva:
        ! media armonica (simetrica -> telescopa; NULA si un lado no
        ! tiene la fase). Misma definicion que mod_energy_3d::aface.
        pure function aface(a1, a2) result(af)
            real(dp), intent(in) :: a1, a2
            real(dp) :: af
            af = 2.0_dp * a1 * a2 / max(a1 + a2, SMALL)
        end function aface

        ! Vecina fluida SIN liquido continuo (superficie libre del liquido,
        ! D2.5): su presion actua en la cara. Solo para el LIQUIDO.
        pure logical function fs_nb(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            fs_nb = .false.
            if (is_gas .or. .not. cfg%pc_fs_liquid_gradient) return
            if (.not. ws_liq_cont_valid) return
            fs_nb = pv_ok(ii, jj, kk) .and. .not. ws_liq_cont(ii,jj,kk)
        end function fs_nb

        ! La celda tiene presion de fluido definida? (Bug 16)
        pure logical function pv_ok(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            if (ws_pv_valid) then
                pv_ok = ws_pv_active(ii,jj,kk)
            else
                pv_ok = (m%cell_type(ii,jj,kk) /= 0)
            end if
            ! D2.2b: la celda sellada para el liquido es pared de SU gradiente
            if (.not. is_gas .and. cfg%pc_liq_sealed_wall .and. ws_pv_liq_valid .and. &
                ws_pv_liq_id == probe_current_step()) pv_ok = pv_ok .and. ws_pv_liq(ii,jj,kk)
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
            w = 0.5_dp * (cell_w(ii, jj, ka) + cell_w(ii, jj, kb))
        end function liq_weight_f

        ! Peso por unidad de volumen de la celda que entra en W_f.
        ! Sin fuerza balanceada (F2.3, solo el gas): alpha_l rho_l g del
        ! liquido continuo. Con fuerza balanceada (liq_balanced_force): peso
        ! de la MEZCLA CONTINUA (liquido continuo + gas) por volumen de
        ! FLUIDO, (alpha_l rho_l + alpha_g rho_g) g / (alpha_l + alpha_g), y
        ! ninguna fase lleva peso de celda propio. Con el gas fuera de W, la
        ! hidrostatica de la mezcla empujaba al liquido de la celda de
        ! superficie (alpha_l alpha_g rho_g g: deriva lineal en bath_test); y
        ! por volumen de fluido porque en un poro lleno la hidrostatica es la
        ! intrinseca, grad p = rho_l g, el solido se sostiene solo
        ! (test_poisson_bath caso 5).
        pure real(dp) function cell_w(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            ! (auditoria 6) mod_workspace::mix_cell_weight, la MISMA que el Poisson
            if (is_gas) then
                cell_w = mix_cell_weight(ph_other%alpha(ii,jj,kk), &
                    liq_w(ph_other%rho(ii,jj,kk), ph_other%T(ii,jj,kk), cfg%beta_expansion, cfg%T_ref_boussinesq, ii, jj, kk), &
                    ph%alpha(ii,jj,kk), ph%rho(ii,jj,kk), cont_ok(ii,jj,kk), lbf_m)
            else
                cell_w = mix_cell_weight(ph%alpha(ii,jj,kk), &
                    liq_w(ph%rho(ii,jj,kk), ph%T(ii,jj,kk), cfg%beta_expansion, cfg%T_ref_boussinesq, ii, jj, kk), &
                    ph_other%alpha(ii,jj,kk), ph_other%rho(ii,jj,kk), cont_ok(ii,jj,kk), lbf_m)
            end if
        end function cell_w

        ! (auditoria 6) respaldo sin ws_liq_cont: el MISMO criterio que el
        ! act_l del Poisson (liq_cont_fallback; antes 0.3 aqui y 1e-2 alli: el
        ! peso de cara de la mezcla no coincidia en la rama de una fase)
        pure logical function cont_ok(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            if (ws_liq_cont_valid) then
                cont_ok = ws_liq_cont(ii,jj,kk)
            else if (is_gas) then
                cont_ok = liq_cont_fallback(ph_other%alpha(ii,jj,kk))
            else
                cont_ok = liq_cont_fallback(ph%alpha(ii,jj,kk))
            end if
        end function cont_ok

        ! Gradiente vertical REDUCIDO que ve esta fase: caras con el peso de
        ! la mezcla sumado y la flotacion relativa del lecho (bed_rel_f);
        ! media de las caras existentes
        pure function gas_pgrad_z(ii, jj, kk, okm, okp) result(g)
            integer, intent(in) :: ii, jj, kk
            logical, intent(in) :: okm, okp
            real(dp) :: g, gb, gt
            gb = 0.0_dp; gt = 0.0_dp
            if (okm) gb = (pf(ii,jj,kk) - pf(ii,jj,kk-1)) / (m%z(kk) - m%z(kk-1)) &
                          + liq_weight_f(ii, jj, kk-1, kk) + bed_rel_f(ii, jj, kk-1, kk)
            if (okp) gt = (pf(ii,jj,kk+1) - pf(ii,jj,kk)) / (m%z(kk+1) - m%z(kk)) &
                          + liq_weight_f(ii, jj, kk, kk+1) + bed_rel_f(ii, jj, kk, kk+1)
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
