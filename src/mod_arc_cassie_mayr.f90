!===============================================================================
! mod_arc_cassie_mayr.f90 - Cassie-Mayr AC arc model (Eqs 1-3 of paper)
!
! Arc power (Eq. 1):  P_a = u*i = i^2 * R
! Arc resistance ODE (Eq. 2):
!   dR/dt = (R/tau)*[1 - (u*i)/(2*pi^0.5*sigma^0.5*l_a^1.5*sigma_SB*T_arc^4*R)] - w
! Arc length (Eq. 3):  l_a = (u - 40) / 11.5
!
! Integrated using 4th-order Runge-Kutta with sub-stepping.
!===============================================================================
module mod_arc_cassie_mayr
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_audit, only: audit_add, AUD_ARC_DIRECT, AUD_ARC_DISCARD
    use mod_melting_3d, only: solid_T_from_enthalpy, solid_enthalpy
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Update arc for one electrode at the given time step
    !---------------------------------------------------------------------------
    ! Estado electrico del arco a partir del perfil V/I medido.
    ! Auditoria (bajos, oct-2026): aqui se integraba la EDO de Cassie-Mayr con
    ! RK4 sub-pasado, pero su R no se usaba (la potencia es V I del perfil:
    ! con V e I impuestos el equilibrio de la EDO es INESTABLE y R -> 1e-8) y
    ! el termino P_rad R no era dimensionalmente coherente. Codigo muerto
    ! retirado: arc_R es ahora la resistencia eficaz V/I (diagnostico). Las
    ! claves arc_tau, arc_w, arc_sigma_cond y arc_T_ref quedan sin efecto.
    subroutine update_arc_resistance(elec, voltage, current)
        type(electrode_t), intent(inout) :: elec
        real(dp), intent(in)             :: voltage, current

        elec%arc_R = abs(voltage) / max(abs(current), 1.0_dp)
        elec%arc_power = abs(voltage * current)
        elec%voltage = voltage
        elec%current = current

        ! Arc length (Eq. 3)
        elec%arc_length = max((abs(voltage) - ARC_VOLT_THRESHOLD) / ARC_LENGTH_GRAD, &
                              ARC_LENGTH_MIN)

    end subroutine update_arc_resistance

    !---------------------------------------------------------------------------
    ! Distribute arc heat to the mesh
    !
    ! Physical model:
    !   P_rad  (frac_rad)  : arc radiation travels DOWN the plasma column and
    !                        deposits at the SCRAP SURFACE (kg_scrap level).
    !   P_conv (frac_conv) : convective enthalpy of arc plasma column, deposited
    !                        over the full arc column (kg_scrap → kg_tip).
    !   P_elec (frac_elec) : electron-flow heating of liquid bath; deposited
    !                        below the tip AFTER bore_in_done.
    !
    ! Decomposition-invariant implementation: every rank receives alpha_s
    ! replicado globalmente (gather único por paso en main, compartido con el
    ! MC — C4.2) and computes the arc column and
    ! the weight sums by looping over the GLOBAL mesh in the same order as a
    ! serial run, so the totals are bit-identical regardless of the MPI
    ! decomposition.  Deposits are then applied only to locally-owned cells.
    !---------------------------------------------------------------------------
    subroutine distribute_arc_heat(elec, sh, sol, m, cfg, alpha_g, n_elec, alpha_lg)
        type(electrode_t), intent(inout) :: elec(:)
        type(shared_t), intent(inout)   :: sh
        type(solid_t), intent(inout)    :: sol
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        real(dp), intent(in)            :: alpha_g(:,:,:)
        integer, intent(in)             :: n_elec
        ! alpha_l GLOBAL (N-A2): P_elec va al baño bajo el electrodo
        real(dp), intent(in)            :: alpha_lg(:,:,:)

        integer  :: e, ig, jg, kg, il, jl, kl, kg_tip, kg_scrap, kc_lo, kc_hi
        real(dp) :: P_total, P_rad_arc, P_conv, P_elec_flow
        real(dp) :: x_elec, y_elec, x_cell, y_cell, dist
        real(dp) :: r2, sigma_r, gw
        real(dp) :: total_gw_vol_rad, total_gw_vol_conv, total_vol
        logical  :: found_scrap, owned, any_liq
        ! (El tope de 2 K por paso al solido se sustituyo por el tope de estado
        ! solid_arc_room: auditoria 12-oct-2026, M13.)

        sh%S_arc     = 0.0_dp
        sh%S_arc_mom = 0.0_dp

        sigma_r = cfg%R_elec * 1.5_dp

        do e = 1, n_elec
            P_total = elec(e)%arc_power
            if (P_total < 1.0_dp) cycle

            ! El MC (si está activo) toma SU parte del presupuesto frac_rad;
            ! el depósito directo recibe el resto (C1.6a: antes el MC era
            ! aditivo y se inyectaba 1 + 0.5*frac_rad veces P_arc)
            elec(e)%mc_share = MC_RAD_SHARE
            if (cfg%n_beams > 0) then
                P_rad_arc = P_total * cfg%frac_rad * (1.0_dp - MC_RAD_SHARE)
            else
                P_rad_arc = P_total * cfg%frac_rad
            end if
            P_conv      = P_total * cfg%frac_conv
            P_elec_flow = P_total * cfg%frac_elec

            ! Antes del bore-in la fracción electrónica no tiene baño que
            ! calentar: se deposita en la columna del arco junto con P_conv
            ! (antes se PERDÍA: presupuesto medido 0.20 en noflow_energy)
            if (.not. elec(e)%bore_in_done) then
                P_conv      = P_conv + P_elec_flow
                P_elec_flow = 0.0_dp
            end if

            x_elec = cfg%R_pcd * cos(elec(e)%theta_pos)
            y_elec = cfg%R_pcd * sin(elec(e)%theta_pos)

            ! ── Electrode tip k-level (global) ──────────────────────────────
            kg_tip = 1
            do kg = m%nz_g, 1, -1
                if (m%z_global(kg) <= elec(e)%z_tip) then
                    kg_tip = kg
                    exit
                end if
            end do

            ! ── Scrap surface below electrode (global search) ───────────────
            kg_scrap = max(1, kg_tip - 1)
            found_scrap = .false.
            kscrap: do kg = kg_tip, 1, -1
                do jg = 1, m%nth_g
                    do ig = 1, m%nr_g
                        if (m%cell_type_global(ig,jg,kg) == 0) cycle
                        x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                        y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                        dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                        if (dist <= sigma_r * 2.0_dp .and. &
                            alpha_g(ig,jg,kg) > ALPHA_SCRAP_SURF) then
                            kg_scrap     = kg
                            found_scrap  = .true.
                            exit kscrap
                        end if
                    end do
                end do
            end do kscrap

            ! ── Superficie del BAÑO bajo el electrodo (auditoria 2, N-A2) ───
            ! Sin chatarra, el chorro de plasma pega en el baño: P_conv va a la
            ! capa de la superficie del baño (antes a la columna de gas bajo la
            ! punta, que no podia cederlo al baño: N-A1)
            kc_lo = kg_scrap; kc_hi = kg_tip
            if (.not. found_scrap) then
                kbath: do kg = kg_tip, 1, -1
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            if (dist <= sigma_r * 2.0_dp .and. &
                                alpha_lg(ig,jg,kg) >= ALPHA_LIQ_CONT) then
                                kc_lo = kg; kc_hi = kg
                                exit kbath
                            end if
                        end do
                    end do
                end do kbath
            end if

            ! ── P_rad: first pass — Gaussian weight sum at scrap surface ───
            total_gw_vol_rad = 0.0_dp
            if (found_scrap) then
                do kg = max(1, kg_scrap-1), min(m%nz_g, kg_scrap+1)
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            if (alpha_g(ig,jg,kg) < 0.01_dp) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            r2 = dist**2 / (sigma_r**2 + SMALL)
                            if (r2 < 16.0_dp) then
                                total_gw_vol_rad = total_gw_vol_rad + &
                                    exp(-r2) * m%vol_global(ig,jg,kg)
                            end if
                        end do
                    end do
                end do
            end if

            ! ── P_conv: first pass — weight sum over full arc column ────────
            total_gw_vol_conv = 0.0_dp
            do kg = kc_lo, kc_hi
                do jg = 1, m%nth_g
                    do ig = 1, m%nr_g
                        if (m%cell_type_global(ig,jg,kg) == 0) cycle
                        x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                        y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                        dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                        r2 = dist**2 / (sigma_r**2 + SMALL)
                        if (r2 < 16.0_dp) then
                            total_gw_vol_conv = total_gw_vol_conv + &
                                exp(-r2) * m%vol_global(ig,jg,kg)
                        end if
                    end do
                end do
            end do

            ! Sin superficie de chatarra que reciba P_rad directo y con MC:
            ! TODA la radiacion del arco la traza el MC (auditoria 2, N-A2:
            ! antes iba a la columna de gas kg_tip +- 3 -incluso dentro del
            ! grafito-, ~7 MW por electrodo que no llegaban al baño; con baño
            ! plano el liquido recibia el 6.9 % del arco absorbido)
            if (cfg%n_beams > 0 .and. .not. (found_scrap .and. total_gw_vol_rad > SMALL)) then
                elec(e)%mc_share = 1.0_dp
                P_rad_arc = 0.0_dp
            end if

            ! ── P_rad: second pass — deposit DIRECTLY into solid energy ──────
            ! P_rad bypasses the gas: arc photons hit the scrap surface and
            ! heat it directly (no gas bottleneck via h_gs).
            if (found_scrap .and. total_gw_vol_rad > SMALL) then
                do kg = max(1, kg_scrap-1), min(m%nz_g, kg_scrap+1)
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            if (alpha_g(ig,jg,kg) < 0.01_dp) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            r2 = dist**2 / (sigma_r**2 + SMALL)
                            if (r2 >= 16.0_dp) cycle

                            call global_to_local(m, ig, jg, kg, il, jl, kl, owned)
                            if (.not. owned) cycle

                            gw = exp(-r2)
                            ! P_rad directo: los fotones del arco calientan la
                            ! chatarra (fraccion 1 al solido, con el tope de
                            ! estado; el excedente al fluido de la celda)
                            call arc_deposit(sol, sh, cfg, il, jl, kl, alpha_g(ig,jg,kg), &
                                m%vol_global(ig,jg,kg), P_rad_arc * gw / total_gw_vol_rad, 1.0_dp)
                        end do
                    end do
                end do
            else
                ! Respaldo: sin superficie de chatarra que reciba P_rad (baño
                ! plano, horno vacío, o chatarra presente pero sin ninguna celda
                ! que pase el umbral de la superficie). P_rad va a la columna del
                ! arco kg_tip-3..kg_tip+3 con su PROPIO normalizador sobre ese
                ! mismo rango (auditoría 12-oct-2026, C1): antes se normalizaba
                ! con la suma de P_conv (kg_scrap..kg_tip, 2 capas) y se
                ! depositaba en 7 capas, ~3.5x P_rad (energía creada); y con
                ! chatarra pero total_gw_vol_rad = 0 no entraba en ninguna rama y
                ! P_rad se perdía.
                total_vol = 0.0_dp
                if (P_rad_arc > 0.0_dp) then
                do kg = max(1, kg_tip-3), min(m%nz_g, kg_tip+3)
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            r2 = dist**2 / (sigma_r**2 + SMALL)
                            if (r2 < 16.0_dp) total_vol = total_vol + &
                                exp(-r2) * m%vol_global(ig,jg,kg)
                        end do
                    end do
                end do
                end if
                if (total_vol > SMALL) then
                do kg = max(1, kg_tip-3), min(m%nz_g, kg_tip+3)
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            r2 = dist**2 / (sigma_r**2 + SMALL)
                            if (r2 >= 16.0_dp) cycle

                            call global_to_local(m, ig, jg, kg, il, jl, kl, owned)
                            if (.not. owned) cycle

                            gw = exp(-r2)
                            call arc_deposit(sol, sh, cfg, il, jl, kl, alpha_g(ig,jg,kg), &
                                m%vol_global(ig,jg,kg), P_rad_arc * gw / total_vol, -1.0_dp)
                        end do
                    end do
                end do
                end if
            end if

            ! ── P_conv: second pass — deposit over arc column ───────────────
            if (total_gw_vol_conv > SMALL) then
                do kg = kc_lo, kc_hi
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            r2 = dist**2 / (sigma_r**2 + SMALL)
                            if (r2 >= 16.0_dp) cycle

                            call global_to_local(m, ig, jg, kg, il, jl, kl, owned)
                            if (.not. owned) cycle

                            gw = exp(-r2)
                            call arc_deposit(sol, sh, cfg, il, jl, kl, alpha_g(ig,jg,kg), &
                                m%vol_global(ig,jg,kg), P_conv * gw / total_gw_vol_conv, -1.0_dp)
                        end do
                    end do
                end do
            end if

            ! ── P_elec: electron-flow heating to liquid bath (post bore-in) ─
            ! (N-A2) peso alpha_l V: la columna bajo la punta incluye el gas
            ! entre el baño y la punta y la chatarra residual (~20 % de P_elec
            ! iba al gas); sin baño en la columna, por volumen como antes
            if (elec(e)%bore_in_done) then
                any_liq = .false.
                do kg = 1, kg_tip
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            if (dist <= cfg%R_elec * 2.0_dp .and. alpha_lg(ig,jg,kg) > ALPHA_CUTOFF) &
                                any_liq = .true.
                        end do
                    end do
                end do
                total_vol = 0.0_dp
                do kg = 1, kg_tip
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            if (dist <= cfg%R_elec * 2.0_dp) then
                                total_vol = total_vol + wel(ig, jg, kg)
                            end if
                        end do
                    end do
                end do
                if (total_vol > SMALL) then
                    do kg = 1, kg_tip
                        do jg = 1, m%nth_g
                            do ig = 1, m%nr_g
                                if (m%cell_type_global(ig,jg,kg) == 0) cycle
                                x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                                y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                                dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                                if (dist > cfg%R_elec * 2.0_dp) cycle

                                call global_to_local(m, ig, jg, kg, il, jl, kl, owned)
                                if (.not. owned) cycle

                                if (wel(ig, jg, kg) <= 0.0_dp) cycle
                                call arc_deposit(sol, sh, cfg, il, jl, kl, alpha_g(ig,jg,kg), &
                                    m%vol_global(ig,jg,kg), P_elec_flow * wel(ig, jg, kg) &
                                    / (total_vol * m%vol_global(ig,jg,kg)), -1.0_dp)
                            end do
                        end do
                    end do
                end if
            end if

        end do

    contains

        pure real(dp) function wel(ig, jg, kg)
            integer, intent(in) :: ig, jg, kg
            if (any_liq) then
                wel = max(alpha_lg(ig,jg,kg), 0.0_dp) * m%vol_global(ig,jg,kg)
            else
                wel = m%vol_global(ig,jg,kg)
            end if
        end function wel

    end subroutine distribute_arc_heat

    !---------------------------------------------------------------------------
    ! Energia [J] que el solido de una celda puede recibir del arco en un
    ! paso: hasta la entalpia de T_liquidus + DT_SH_ARC (la fusion del paso
    ! siguiente la convierte en liquido). Tope de ESTADO (auditoria 12-oct-2026,
    ! M13): el anterior era 2 K POR PASO, dependiente de dt, y su excedente
    ! iba al gas de poro.
    !---------------------------------------------------------------------------
    function solid_arc_room(m_s, E_s, cfg) result(q)
        real(dp), intent(in)       :: m_s, E_s
        type(config_t), intent(in) :: cfg
        real(dp) :: q
        real(dp), parameter :: DT_SH_ARC = 100.0_dp
        q = 0.0_dp
        if (m_s <= SMALL) return
        q = max(0.0_dp, m_s * solid_enthalpy(cfg%T_liquidus + DT_SH_ARC, cfg) - E_s)
    end function solid_arc_room

    !---------------------------------------------------------------------------
    ! Deposito de una densidad de potencia del arco Pd [W/m3] en la celda
    ! propia (il,jl,kl) de volumen vol, repartido por ABSORCION entre el
    ! solido (KAPPA_SOLID_ABS alpha_s) y el fluido (KAPPA_GAS_ABS (1-alpha_s)),
    ! como el MC desde F2.30 (auditoria 12-oct-2026, A9): P_conv, P_elec y el
    ! respaldo de P_rad iban enteros a S_arc y en una celda de chatarra el gas
    ! de poro se llevaba todo. La parte del solido va a E_s con el tope
    ! solid_arc_room y el excedente vuelve al fluido. w_s_in < 0: reparto por
    ! absorcion; si no, fraccion impuesta (P_rad directo: 1).
    !---------------------------------------------------------------------------
    subroutine arc_deposit(sol, sh, cfg, il, jl, kl, as_c, vol, Pd, w_s_in)
        type(solid_t), intent(inout)  :: sol
        type(shared_t), intent(inout) :: sh
        type(config_t), intent(in)    :: cfg
        integer, intent(in)           :: il, jl, kl
        real(dp), intent(in)          :: as_c, vol, Pd, w_s_in
        real(dp) :: Q, w_s, Q_s, Q_fl
        Q = Pd * vol * cfg%dt
        if (Q <= 0.0_dp) return
        w_s = 0.0_dp
        if (sol%m_s(il,jl,kl) > SMALL .and. as_c > 0.0_dp) then
            if (w_s_in >= 0.0_dp) then
                w_s = w_s_in
            else
                w_s = KAPPA_SOLID_ABS * as_c / (KAPPA_SOLID_ABS * as_c + &
                      KAPPA_GAS_ABS * max(1.0_dp - as_c, 0.0_dp) + SMALL)
            end if
        end if
        Q_s = min(w_s * Q, solid_arc_room(sol%m_s(il,jl,kl), sol%E_s(il,jl,kl), cfg))
        Q_fl = Q - Q_s
        if (Q_s > 0.0_dp) then
            sol%E_s(il,jl,kl) = sol%E_s(il,jl,kl) + Q_s
            sol%T_s(il,jl,kl) = solid_T_from_enthalpy(sol%E_s(il,jl,kl) / sol%m_s(il,jl,kl), cfg)
            call audit_add(AUD_ARC_DIRECT, Q_s)
        end if
        sh%S_arc(il,jl,kl) = sh%S_arc(il,jl,kl) + Q_fl / (vol * cfg%dt + SMALL)
    end subroutine arc_deposit

end module mod_arc_cassie_mayr
