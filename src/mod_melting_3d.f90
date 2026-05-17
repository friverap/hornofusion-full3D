!===============================================================================
! mod_melting_3d.f90 - Melting/re-solidification model (Eqs 9-10 of paper)
!
! Phase change criterion (Eq. 9):
!   m_dot_s,mt = dm_s/dt   if T_s >= T_liquidus  (melting)
!              = -dm_l/dt  if T_l < T_solidus    (re-solidification)
!
! Effective specific heat (Eq. 10):
!   Cp_eff = Cp_s                                    if T < T_solidus
!          = Cp_s + h_fusion/(T_liq - T_sol)         if T_sol <= T <= T_liq
!          = Cp_l                                    if T > T_liquidus
!===============================================================================
module mod_melting_3d
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    implicit none

contains

    subroutine compute_melting(sol, liq, m, cfg, dt)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: liq
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: dt

        integer :: i, j, k
        real(dp) :: T_s, T_l, dm, cp_eff
        real(dp) :: dT_range, max_melt_rate
        real(dp) :: E_available

        dT_range = cfg%T_liquidus - cfg%T_solidus

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle

                    sol%mdot(i,j,k) = 0.0_dp
                    T_s = sol%T_s(i,j,k)
                    T_l = liq%T(i,j,k)

                    ! Melting: solid above liquidus transfers mass to liquid
                    if (sol%alpha_s(i,j,k) > 1.0e-6_dp .and. T_s >= cfg%T_liquidus) then
                        ! Energy available for melting
                        cp_eff = effective_cp(T_s, cfg)
                        E_available = sol%m_s(i,j,k) * cp_eff * (T_s - cfg%T_liquidus)

                        ! Mass that can melt
                        dm = E_available / (cfg%h_fusion + cfg%cp_l * (cfg%T_liquidus - cfg%T_solidus))
                        dm = min(dm, sol%m_s(i,j,k))
                        dm = max(dm, 0.0_dp)

                        ! Rate limited by timestep
                        max_melt_rate = sol%m_s(i,j,k) / dt
                        sol%mdot(i,j,k) = min(dm / dt, max_melt_rate)

                        ! Update solid mass and energy
                        sol%m_s(i,j,k) = sol%m_s(i,j,k) - sol%mdot(i,j,k) * dt
                        sol%m_s(i,j,k) = max(sol%m_s(i,j,k), 0.0_dp)
                        ! Remove BOTH latent heat AND the sensible heat of the departed mass.
                        ! Without the cp_eff*T_s term, E_s/m_s_new > T_s_old (thermal runaway).
                        ! Derivation: T_s_new = T_s - dm*h_fus/((m_s-dm)*cp_eff)  < T_s ✓
                        sol%E_s(i,j,k) = sol%E_s(i,j,k) - sol%mdot(i,j,k) * dt &
                                        * (cfg%h_fusion + cp_eff * T_s)

                        ! Update solid volume fraction
                        if (m%vol(i,j,k) > SMALL) then
                            sol%alpha_s(i,j,k) = sol%m_s(i,j,k) / &
                                                  (cfg%rho_steel * m%vol(i,j,k))
                        end if
                        sol%alpha_s(i,j,k) = max(0.0_dp, min(1.0_dp, sol%alpha_s(i,j,k)))

                        ! Update solid temperature from energy
                        if (sol%m_s(i,j,k) > SMALL) then
                            sol%T_s(i,j,k) = sol%E_s(i,j,k) / (sol%m_s(i,j,k) * cp_eff)
                        end if

                    ! Re-solidification: liquid below solidus deposits mass to solid
                    else if (liq%alpha(i,j,k) > 1.0e-6_dp .and. T_l < cfg%T_solidus) then
                        dm = liq%alpha(i,j,k) * liq%rho(i,j,k) * m%vol(i,j,k) * &
                             (cfg%T_solidus - T_l) * cfg%cp_l / cfg%h_fusion
                        dm = max(dm, 0.0_dp) * 0.1_dp  ! stability limiter

                        sol%mdot(i,j,k) = -dm / dt
                        sol%m_s(i,j,k) = sol%m_s(i,j,k) + dm
                        sol%E_s(i,j,k) = sol%E_s(i,j,k) + dm * cfg%cp_s * cfg%T_solidus

                        if (m%vol(i,j,k) > SMALL) then
                            sol%alpha_s(i,j,k) = sol%m_s(i,j,k) / &
                                                  (cfg%rho_steel * m%vol(i,j,k))
                        end if
                        sol%alpha_s(i,j,k) = max(0.0_dp, min(1.0_dp, sol%alpha_s(i,j,k)))
                    end if
                end do
            end do
        end do

    end subroutine compute_melting

    !---------------------------------------------------------------------------
    ! Effective Cp (Eq. 10)
    !---------------------------------------------------------------------------
    pure function effective_cp(T, cfg) result(cp_eff)
        real(dp), intent(in) :: T
        type(config_t), intent(in) :: cfg
        real(dp) :: cp_eff

        if (T < cfg%T_solidus) then
            cp_eff = cfg%cp_s
        else if (T <= cfg%T_liquidus) then
            cp_eff = cfg%cp_s + cfg%h_fusion / (cfg%T_liquidus - cfg%T_solidus)
        else
            cp_eff = cfg%cp_l
        end if
    end function effective_cp

end module mod_melting_3d
