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
    use mod_melting_3d, only: solid_T_from_enthalpy
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Update arc for one electrode at the given time step
    !---------------------------------------------------------------------------
    subroutine update_arc_resistance(elec, voltage, current, cfg, dt)
        type(electrode_t), intent(inout) :: elec
        real(dp), intent(in)             :: voltage, current
        type(config_t), intent(in)       :: cfg
        real(dp), intent(in)             :: dt

        integer :: n_sub, s
        real(dp) :: dt_sub, R, t_local
        real(dp) :: V, I_amp
        real(dp) :: k1, k2, k3, k4

        ! Sub-step the ODE (arc time constant ~ 3e-4 s, need dt_sub << tau)
        n_sub = max(1, int(dt / (0.1_dp * cfg%arc_tau)) + 1)
        n_sub = min(n_sub, 10000)
        dt_sub = dt / real(n_sub, dp)

        R = max(elec%arc_R, 1.0e-6_dp)
        V = voltage
        I_amp = current

        do s = 1, n_sub
            t_local = real(s - 1, dp) * dt_sub

            k1 = dt_sub * arc_rhs(R, V, I_amp, elec%arc_length, cfg)
            k2 = dt_sub * arc_rhs(R + 0.5_dp*k1, V, I_amp, elec%arc_length, cfg)
            k3 = dt_sub * arc_rhs(R + 0.5_dp*k2, V, I_amp, elec%arc_length, cfg)
            k4 = dt_sub * arc_rhs(R + k3, V, I_amp, elec%arc_length, cfg)

            R = R + (k1 + 2.0_dp*k2 + 2.0_dp*k3 + k4) / 6.0_dp
            R = max(R, 1.0e-8_dp)
        end do

        elec%arc_R = R
        ! arc_power = V·I directly from the electrode profile.
        !
        ! The Cassie-Mayr ODE has an UNSTABLE equilibrium when V and I are
        ! imposed externally (no circuit feedback).  Starting from any
        ! R_0 < R_eq = ARC_W*ARC_TAU, the ODE drives R → R_min = 1e-8 Ω,
        ! giving I²·R ≈ 30 W instead of the intended 27.5 MW.
        !
        ! Physical interpretation: V and I in the electrode profile are
        ! measured furnace quantities, so P_arc = V·I is the correct arc
        ! power.  The ODE (and the R it produces) is kept only for arc-length
        ! dynamics and future circuit-coupled extensions.
        elec%arc_power = abs(V * I_amp)
        elec%voltage = V
        elec%current = I_amp

        ! Arc length (Eq. 3)
        elec%arc_length = max((abs(V) - ARC_VOLT_THRESHOLD) / ARC_LENGTH_GRAD, &
                              ARC_LENGTH_MIN)

    end subroutine update_arc_resistance

    !---------------------------------------------------------------------------
    ! RHS of Cassie-Mayr ODE (Eq. 2)
    !---------------------------------------------------------------------------
    pure function arc_rhs(R, V, I_amp, l_a, cfg) result(dRdt)
        real(dp), intent(in)         :: R, V, I_amp, l_a
        type(config_t), intent(in)   :: cfg
        real(dp) :: dRdt

        real(dp) :: P_arc, P_rad, tau, w

        tau = cfg%arc_tau
        w   = cfg%arc_w

        P_arc = abs(V * I_amp)
        P_rad = 2.0_dp * sqrt(PI) * sqrt(cfg%arc_sigma_cond) * &
                l_a**1.5_dp * STEFAN_BOLTZMANN * cfg%arc_T_ref**4

        dRdt = (R / tau) * (1.0_dp - P_arc / (P_rad * R + SMALL)) - w
    end function arc_rhs

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
    ! Decomposition-invariant implementation: every rank replicates alpha_s
    ! globally (exact disjoint-owner gather) and computes the arc column and
    ! the weight sums by looping over the GLOBAL mesh in the same order as a
    ! serial run, so the totals are bit-identical regardless of the MPI
    ! decomposition.  Deposits are then applied only to locally-owned cells.
    !---------------------------------------------------------------------------
    subroutine distribute_arc_heat(elec, sh, sol, m, cfg, alpha_s, n_elec)
        type(electrode_t), intent(in)   :: elec(:)
        type(shared_t), intent(inout)   :: sh
        type(solid_t), intent(inout)    :: sol
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        real(dp), intent(in)            :: alpha_s(-1:,-1:,-1:)
        integer, intent(in)             :: n_elec

        integer  :: e, ig, jg, kg, il, jl, kl, kg_tip, kg_scrap
        real(dp) :: P_total, P_rad_arc, P_conv, P_elec_flow
        real(dp) :: x_elec, y_elec, x_cell, y_cell, dist
        real(dp) :: r2, sigma_r, gw
        real(dp) :: total_gw_vol_rad, total_gw_vol_conv, total_vol
        real(dp) :: Q_rad, Q_rad_lim
        real(dp), allocatable :: alpha_g(:,:,:)
        logical  :: found_scrap, owned
        ! Maximum ΔT_solid per timestep from direct arc radiation [K].
        ! Prevents T_s → NaN/Inf in cells with small m_s (explicit E_s update
        ! has no implicit solver to absorb large source terms).
        real(dp), parameter :: DT_RAD_MAX = 2.0_dp

        allocate(alpha_g(m%nr_g, m%nth_g, m%nz_g))
        call gather_global_field(alpha_s, alpha_g, m)

        sh%S_arc     = 0.0_dp
        sh%S_arc_mom = 0.0_dp

        sigma_r = cfg%R_elec * 1.5_dp

        do e = 1, n_elec
            P_total = elec(e)%arc_power
            if (P_total < 1.0_dp) cycle

            ! El MC (si está activo) toma SU parte del presupuesto frac_rad;
            ! el depósito directo recibe el resto (C1.6a: antes el MC era
            ! aditivo y se inyectaba 1 + 0.5*frac_rad veces P_arc)
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
                            alpha_g(ig,jg,kg) > 0.05_dp) then
                            kg_scrap     = kg
                            found_scrap  = .true.
                            exit kscrap
                        end if
                    end do
                end do
            end do kscrap

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
            do kg = kg_scrap, kg_tip
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
                            if (sol%m_s(il,jl,kl) > SMALL) then
                                ! [W/m^3] * [m^3] * [s] = [J]
                                Q_rad = P_rad_arc * gw / total_gw_vol_rad * &
                                        m%vol_global(ig,jg,kg) * cfg%dt
                                ! Stability guard: limit ΔT_s to DT_RAD_MAX per step.
                                Q_rad_lim = DT_RAD_MAX * sol%m_s(il,jl,kl) * cfg%cp_s
                                ! C1.6c: el excedente del cap NO se descarta —
                                ! va a S_arc de la misma celda (los fluidos lo
                                ! transportan y llega al sólido vía interfase).
                                ! AUD_ARC_DISCARD queda como centinela (=0).
                                if (Q_rad > Q_rad_lim) then
                                    sh%S_arc(il,jl,kl) = sh%S_arc(il,jl,kl) + &
                                        (Q_rad - Q_rad_lim) / &
                                        (m%vol_global(ig,jg,kg) * cfg%dt + SMALL)
                                    Q_rad = Q_rad_lim
                                end if
                                call audit_add(AUD_ARC_DIRECT, Q_rad)
                                sol%E_s(il,jl,kl) = sol%E_s(il,jl,kl) + Q_rad
                                sol%T_s(il,jl,kl) = solid_T_from_enthalpy( &
                                    sol%E_s(il,jl,kl) / sol%m_s(il,jl,kl), cfg)
                            end if
                        end do
                    end do
                end do
            else if (.not. found_scrap .and. total_gw_vol_conv > SMALL) then
                ! Fallback: no scrap below electrode (pre-charge or empty furnace).
                ! Deposit P_rad in the arc column (same as P_conv).
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
                            sh%S_arc(il,jl,kl) = sh%S_arc(il,jl,kl) + &
                                P_rad_arc * gw / total_gw_vol_conv
                        end do
                    end do
                end do
            end if

            ! ── P_conv: second pass — deposit over arc column ───────────────
            if (total_gw_vol_conv > SMALL) then
                do kg = kg_scrap, kg_tip
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
                            sh%S_arc(il,jl,kl) = sh%S_arc(il,jl,kl) + &
                                P_conv * gw / total_gw_vol_conv
                        end do
                    end do
                end do
            end if

            ! ── P_elec: electron-flow heating to liquid bath (post bore-in) ─
            if (elec(e)%bore_in_done) then
                total_vol = 0.0_dp
                do kg = 1, kg_tip
                    do jg = 1, m%nth_g
                        do ig = 1, m%nr_g
                            if (m%cell_type_global(ig,jg,kg) == 0) cycle
                            x_cell = m%r_global(ig) * cos(m%theta_global(jg))
                            y_cell = m%r_global(ig) * sin(m%theta_global(jg))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            if (dist <= cfg%R_elec * 2.0_dp) then
                                total_vol = total_vol + m%vol_global(ig,jg,kg)
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

                                sh%S_arc(il,jl,kl) = sh%S_arc(il,jl,kl) + &
                                    P_elec_flow / total_vol
                            end do
                        end do
                    end do
                end if
            end if

        end do

        deallocate(alpha_g)

    end subroutine distribute_arc_heat

end module mod_arc_cassie_mayr
