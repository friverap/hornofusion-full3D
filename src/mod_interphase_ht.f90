!===============================================================================
! mod_interphase_ht.f90 - Interphase heat transfer (Eq. 12 of paper)
!
! Gas-solid heat transfer (two regimes):
!   T_g <= 1373 K: h_vgs = (K_g/d_s)*(2 + 1.1*Pr_g^0.333*Re_gs^0.6)
!   T_g >  1373 K: h_gs*A_gs = A*f_omega*|v_g|^0.9*T_g^0.3/d_s^0.75
!
! Liquid-solid: convective exchange based on Nusselt correlations.
!
! Computes volumetric heat source Q_s_bar for solid energy balance (Eq. 8).
!===============================================================================
module mod_interphase_ht
    use mod_constants
    use mod_audit, only: audit_add, AUD_IPH_SOL, AUD_IPH_GAS, AUD_IPH_LIQ
    use mod_mpi_topology, only: mpi_allreduce_min
    use mod_types_3d
    use mod_melting_3d, only: solid_T_from_enthalpy
    implicit none

    ! Escala temporal mínima del acople interfase del último paso
    ! (tau = alpha_g*rho*cp / (h*A_sv)): por debajo de ~tau el intercambio
    ! explícito satura su clamp y fuerza equilibrio térmico local (régimen
    ! medido en S5-dpart y en B1 con dt=10 ms) — el dt adaptativo debe
    ! respetarla (adapt_timestep).
    real(dp), save :: tau_iph_local = 1.0e30_dp

    real(dp), parameter :: T_TRANSITION = 1373.0_dp  ! K
    real(dp), parameter :: A_RADIATION  = 3.6_dp     ! empirical constant
    real(dp), parameter :: F_OMEGA      = 0.7_dp     ! view factor parameter

contains

    subroutine compute_interphase_heat(liq, gas, sol, m, cfg)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(inout) :: sol
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k
        real(dp) :: T_g, T_l, T_s, alpha_s, d_s
        real(dp) :: vmag_g, Re_gs, Pr_g, h_gs, h_ls
        real(dp) :: Q_gs, Q_ls, Q_total
        real(dp) :: A_sv, eps_s, Q_lim, Q_lim_sol, cap_g, cap_l

        d_s = cfg%d_particle
        tau_iph_local = 1.0e30_dp

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle

                    alpha_s = sol%alpha_s(i,j,k)
                    if (alpha_s < 1.0e-6_dp) cycle

                    T_s = sol%T_s(i,j,k)
                    T_g = gas%T(i,j,k)
                    T_l = liq%T(i,j,k)

                    ! Specific surface area of solid (sphere packing)
                    eps_s = max(1.0_dp - alpha_s, 0.01_dp)
                    A_sv = 6.0_dp * alpha_s / (d_s + SMALL)

                    ! Gas-solid heat transfer
                    Q_gs = 0.0_dp
                    if (gas%alpha(i,j,k) > 1.0e-6_dp) then
                        vmag_g = sqrt(gas%ur(i,j,k)**2 + gas%uth(i,j,k)**2 + gas%uz(i,j,k)**2)
                        Pr_g = gas%mu(i,j,k) * gas%cp(i,j,k) / (gas%kth(i,j,k) + SMALL)
                        Re_gs = gas%rho(i,j,k) * vmag_g * d_s / (gas%mu(i,j,k) + SMALL)

                        if (T_g <= T_TRANSITION) then
                            h_gs = (gas%kth(i,j,k) / d_s) * &
                                   (2.0_dp + 1.1_dp * Pr_g**0.333_dp * Re_gs**0.6_dp)
                        else
                            h_gs = A_RADIATION * F_OMEGA * vmag_g**0.9_dp * &
                                   T_g**0.3_dp / (d_s**0.75_dp + SMALL)
                        end if

                        tau_iph_local = min(tau_iph_local, &
                            gas%alpha(i,j,k) * gas%rho(i,j,k) * &
                            gas%cp(i,j,k) / (h_gs * A_sv + SMALL))
                        Q_gs = h_gs * A_sv * (T_g - T_s) * m%vol(i,j,k)
                        ! Clamp por AMBOS lados: ni el gas ni el sólido pueden
                        ! rebasar la T del otro en un paso explícito. El clamp
                        ! solo-fluido dejaba dispararse T_s en celdas casi
                        ! fundidas (m_s pequeña): medido T_s = 66000 K.
                        Q_lim = gas%alpha(i,j,k) * gas%rho(i,j,k) * gas%cp(i,j,k) * &
                                m%vol(i,j,k) * abs(T_g - T_s) / cfg%dt
                        Q_lim_sol = sol%m_s(i,j,k) * cfg%cp_s * &
                                    abs(T_g - T_s) / cfg%dt
                        Q_gs = sign(min(abs(Q_gs), Q_lim, Q_lim_sol), Q_gs)
                    end if

                    ! Liquid-solid heat transfer (Ranz-Marshall)
                    Q_ls = 0.0_dp
                    if (liq%alpha(i,j,k) > 1.0e-6_dp) then
                        h_ls = (liq%kth(i,j,k) / d_s) * 6.0_dp
                        Q_ls = h_ls * A_sv * (T_l - T_s) * m%vol(i,j,k)
                        ! Clamp por ambos lados (ver Q_gs)
                        Q_lim = liq%alpha(i,j,k) * liq%rho(i,j,k) * liq%cp(i,j,k) * &
                                m%vol(i,j,k) * abs(T_l - T_s) / cfg%dt
                        Q_lim_sol = sol%m_s(i,j,k) * cfg%cp_s * &
                                    abs(T_l - T_s) / cfg%dt
                        Q_ls = sign(min(abs(Q_ls), Q_lim, Q_lim_sol), Q_ls)
                    end if

                    Q_total = Q_gs + Q_ls

                    ! Apply heat to solid energy balance
                    sol%E_s(i,j,k) = sol%E_s(i,j,k) + Q_total * cfg%dt
                    ! Auditoría del intercambio interfase (el hook del gas
                    ! no ve este retiro: se contabiliza aquí tal como se
                    ! aplica, con el mismo denominador +SMALL)
                    call audit_add(AUD_IPH_SOL, Q_total * cfg%dt)

                    ! Update solid temperature (función de entalpía ÚNICA, C1.8:
                    ! antes E/(m*cp_s) chocaba con el cp_eff de la fusión)
                    if (sol%m_s(i,j,k) > SMALL) then
                        sol%T_s(i,j,k) = solid_T_from_enthalpy( &
                            sol%E_s(i,j,k) / sol%m_s(i,j,k), cfg)
                    end if

                    ! Corresponding heat removal from fluid phases
                    if (gas%alpha(i,j,k) > 1.0e-6_dp .and. abs(Q_gs) > SMALL) then
                        cap_g = gas%alpha(i,j,k) * gas%rho(i,j,k) * &
                                gas%cp(i,j,k) * m%vol(i,j,k)
                        gas%T(i,j,k) = gas%T(i,j,k) - Q_gs * cfg%dt / (cap_g + SMALL)
                        ! energía realmente retirada del estado del gas
                        call audit_add(AUD_IPH_GAS, &
                            Q_gs * cfg%dt * cap_g / (cap_g + SMALL))
                    end if
                    if (liq%alpha(i,j,k) > 1.0e-6_dp .and. abs(Q_ls) > SMALL) then
                        cap_l = liq%alpha(i,j,k) * liq%rho(i,j,k) * &
                                liq%cp(i,j,k) * m%vol(i,j,k)
                        liq%T(i,j,k) = liq%T(i,j,k) - Q_ls * cfg%dt / (cap_l + SMALL)
                        call audit_add(AUD_IPH_LIQ, &
                            Q_ls * cfg%dt * cap_l / (cap_l + SMALL))
                    end if
                end do
            end do
        end do

    end subroutine compute_interphase_heat

    !---------------------------------------------------------------------------
    ! Tau mínimo GLOBAL del acople interfase del último paso [s]
    !---------------------------------------------------------------------------
    function interphase_tau_global(m) result(tau)
        type(mesh_t), intent(in) :: m
        real(dp) :: tau
        if (m%is_parallel) then
            call mpi_allreduce_min(tau_iph_local, tau, m%topo)
        else
            tau = tau_iph_local
        end if
    end function interphase_tau_global

end module mod_interphase_ht
