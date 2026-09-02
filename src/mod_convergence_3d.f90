!===============================================================================
! mod_convergence_3d.f90 - Convergence monitoring and adaptive time stepping
!===============================================================================
module mod_convergence_3d
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_mpi_topology, only: mpi_allreduce_max
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

    !---------------------------------------------------------------------------
    ! dt adaptativo (C3.2, hallazgo 3.17): criterio CFL físico + convergencia
    ! REAL del lazo externo (antes main forzaba converged=.true. en max_outer
    ! y la rama de reducción era inalcanzable: dt solo podía crecer).
    !---------------------------------------------------------------------------
    subroutine adapt_timestep(dt, conv, cfl_rate, cfg)
        real(dp), intent(inout)         :: dt
        type(convergence_t), intent(in) :: conv
        ! Tasa CFL global: max sobre celdas/fases de sum(|u_i|/dx_i) [1/s]
        real(dp), intent(in)            :: cfl_rate
        type(config_t), intent(in)      :: cfg

        if (.not. cfg%adaptive_dt) return
        if (.not. cfg%solve_flow .and. .not. cfg%solve_energy) return

        if (conv%converged .and. conv%n_outer <= 3) then
            dt = dt * 1.2_dp
        else if (.not. conv%converged) then
            dt = dt * 0.5_dp
        end if

        ! Límite CFL (implícito tolera CFL O(1); cfl_max configurable)
        if (cfl_rate > SMALL) dt = min(dt, cfg%cfl_max / cfl_rate)

        dt = min(max(dt, cfg%dt_min), cfg%dt_max)
    end subroutine adapt_timestep

    !---------------------------------------------------------------------------
    ! Tasa CFL global de ambas fases: max_celdas sum_i |u_i|/dx_i  [1/s]
    !---------------------------------------------------------------------------
    function compute_cfl_rate(liq, gas, m) result(rate)
        type(phase_t), intent(in) :: liq, gas
        type(mesh_t), intent(in)  :: m
        real(dp) :: rate

        integer :: i, j, k
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: local, glob, dth_len

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        local = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    dth_len = m%r(i) * m%dtheta(j)
                    local = max(local, &
                        abs(liq%ur(i,j,k))/m%dr(i) + abs(liq%uth(i,j,k))/dth_len &
                        + abs(liq%uz(i,j,k))/m%dz(k), &
                        abs(gas%ur(i,j,k))/m%dr(i) + abs(gas%uth(i,j,k))/dth_len &
                        + abs(gas%uz(i,j,k))/m%dz(k))
                end do
            end do
        end do
        if (m%is_parallel) then
            call mpi_allreduce_max(local, glob, m%topo)
            rate = glob
        else
            rate = local
        end if
    end function compute_cfl_rate

end module mod_convergence_3d
