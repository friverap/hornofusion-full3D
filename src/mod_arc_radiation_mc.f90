!===============================================================================
! mod_arc_radiation_mc.f90 - Monte Carlo arc radiation model
!
! Distributes the radiative fraction of arc power via random beams
! emitted isotropically from the arc column. Each beam carries a fraction
! of the total radiative power and deposits it in the first solid/liquid
! cell it hits.
!===============================================================================
module mod_arc_radiation_mc
    use mod_constants
    use mod_types_3d
    implicit none

    integer, parameter :: N_BEAMS = 1000   ! beams per electrode per call

contains

    subroutine distribute_arc_radiation_mc(elec, sol, sh, m, cfg, n_elec)
        type(electrode_t), intent(in)   :: elec(:)
        type(solid_t), intent(in)       :: sol
        type(shared_t), intent(inout)   :: sh
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        integer, intent(in)             :: n_elec

        integer  :: e, beam
        real(dp) :: P_rad_per_beam
        real(dp) :: x0, y0, z0, dx, dy, dz
        real(dp) :: x, y, z_pos, r_pos, theta_pos
        real(dp) :: phi_rand, cos_theta, sin_theta
        real(dp) :: step_size, total_P_rad
        integer  :: i_cell, j_cell, k_cell
        real(dp) :: rnd1, rnd2, rnd3
        integer  :: n_steps
        integer, parameter :: MAX_TRACE_STEPS = 50000

        ! Use only interior cells (index 1:m%nr) to avoid zero-width halo cells
        step_size = minval(m%dr(1:m%nr)) * 0.5_dp
        if (step_size < 1.0e-6_dp) step_size = 0.01_dp   ! absolute fallback

        do e = 1, n_elec
            total_P_rad = elec(e)%arc_power * cfg%frac_rad * 0.5_dp
            if (total_P_rad < 1.0_dp) cycle

            P_rad_per_beam = total_P_rad / real(N_BEAMS, dp)

            x0 = cfg%R_pcd * cos(elec(e)%theta_pos)
            y0 = cfg%R_pcd * sin(elec(e)%theta_pos)
            z0 = elec(e)%z_tip

            do beam = 1, N_BEAMS
                ! Random direction (isotropic)
                call random_number(rnd1)
                call random_number(rnd2)
                call random_number(rnd3)

                phi_rand = TWO_PI * rnd1
                cos_theta = 2.0_dp * rnd2 - 1.0_dp
                sin_theta = sqrt(max(1.0_dp - cos_theta**2, 0.0_dp))

                dx = sin_theta * cos(phi_rand)
                dy = sin_theta * sin(phi_rand)
                dz = cos_theta

                ! Trace beam
                x = x0; y = y0; z_pos = z0
                n_steps = 0

                trace: do
                    n_steps = n_steps + 1
                    if (n_steps > MAX_TRACE_STEPS) exit trace   ! safety guard

                    x = x + dx * step_size
                    y = y + dy * step_size
                    z_pos = z_pos + dz * step_size

                    ! Check bounds - use .not.(<=) to correctly handle NaN
                    r_pos = sqrt(x**2 + y**2)
                    if (.not. (r_pos <= cfg%R_shell)) exit trace
                    if (.not. (z_pos >= 0.0_dp .and. z_pos <= cfg%H_total)) exit trace

                    ! Find cell indices
                    theta_pos = atan2(y, x)
                    if (theta_pos < 0.0_dp) theta_pos = theta_pos + TWO_PI

                    call find_cell(r_pos, theta_pos, z_pos, m, i_cell, j_cell, k_cell)
                    if (i_cell < 1 .or. k_cell < 1) exit trace
                    if (m%cell_type(i_cell, j_cell, k_cell) == 0) exit trace

                    ! Check if beam hits solid or liquid
                    if (sol%alpha_s(i_cell, j_cell, k_cell) > 0.1_dp .or. &
                        z_pos < cfg%H_bowl + 0.5_dp) then
                        ! Deposit energy
                        sh%S_arc(i_cell, j_cell, k_cell) = &
                            sh%S_arc(i_cell, j_cell, k_cell) + &
                            P_rad_per_beam / (m%vol(i_cell, j_cell, k_cell) + SMALL)
                        exit trace
                    end if
                end do trace
            end do
        end do

    end subroutine distribute_arc_radiation_mc

    !---------------------------------------------------------------------------
    ! Find cell indices from physical coordinates
    !---------------------------------------------------------------------------
    subroutine find_cell(r, theta, z, m, ic, jc, kc)
        real(dp), intent(in)    :: r, theta, z
        type(mesh_t), intent(in) :: m
        integer, intent(out)    :: ic, jc, kc

        integer :: i

        ic = -1; jc = -1; kc = -1

        do i = 1, m%nr
            if (r <= m%rf(i)) then
                ic = i; exit
            end if
        end do
        if (ic < 0) return

        jc = int(theta / (TWO_PI / real(m%ntheta, dp))) + 1
        jc = max(1, min(m%ntheta, jc))

        do i = 1, m%nz
            if (z <= m%zf(i)) then
                kc = i; exit
            end if
        end do
    end subroutine find_cell

end module mod_arc_radiation_mc
