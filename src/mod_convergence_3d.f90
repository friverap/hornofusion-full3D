!===============================================================================
! mod_convergence_3d.f90 - Convergence monitoring and adaptive time stepping
!===============================================================================
module mod_convergence_3d
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use ieee_arithmetic, only: ieee_is_nan, ieee_is_finite
    implicit none

contains

    function check_convergence(conv, cfg) result(converged)
        type(convergence_t), intent(in) :: conv
        type(config_t), intent(in)      :: cfg
        logical :: converged

        converged = .true.

        ! Safety: if no physics enabled, always converged
        if (.not. cfg%solve_flow .and. .not. cfg%solve_energy .and. .not. cfg%solve_turb) then
            converged = .true.
            return
        end if

        ! Safety: check for invalid residuals (NaN or Inf)
        if (cfg%solve_flow) then
            if (ieee_is_nan(conv%res_cont) .or. .not. ieee_is_finite(conv%res_cont) &
                .or. conv%res_cont > 1.0e100_dp) then
                converged = .false.  ! NaN or Inf detected
                return
            end if
        end if

        if (cfg%solve_flow) then
            if (conv%res_cont > cfg%tol_cont) converged = .false.
            if (conv%res_ur > cfg%tol_mom)     converged = .false.
            if (conv%res_uth > cfg%tol_mom)    converged = .false.
            if (conv%res_uz > cfg%tol_mom)     converged = .false.
        end if

        if (cfg%solve_energy) then
            if (conv%res_energy > cfg%tol_energy) converged = .false.
        end if

        if (cfg%solve_turb) then
            if (conv%res_tke > cfg%tol_turb) converged = .false.
            if (conv%res_eps > cfg%tol_turb) converged = .false.
        end if
    end function check_convergence

    subroutine adapt_timestep(dt, conv, cfg)
        real(dp), intent(inout)         :: dt
        type(convergence_t), intent(in) :: conv
        type(config_t), intent(in)      :: cfg

        if (.not. cfg%adaptive_dt) return

        ! Only adapt if flow and energy are both active
        if (.not. cfg%solve_flow .and. .not. cfg%solve_energy) return

        ! Grow dt if converged quickly (< 3 outer iterations)
        if (conv%n_outer <= 3 .and. conv%converged) then
            dt = min(dt * 1.2_dp, cfg%dt_max)
        ! Shrink dt if struggling (> 15 outer iterations or not converged)
        else if (conv%n_outer >= 15 .or. .not. conv%converged) then
            dt = max(dt * 0.5_dp, cfg%dt_min)
        end if
    end subroutine adapt_timestep

end module mod_convergence_3d
