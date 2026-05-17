!===============================================================================
! mod_arc_impingement.f90 - Arc jet impingement (Eq. 11 of paper)
!
!   p_l = m_l * rho_a * v_a^2 / rho_l
!
! Applied as downward momentum source on liquid beneath electrode tips
! after bore-in is complete. Models the arc jet pushing down on the bath.
!===============================================================================
module mod_arc_impingement
    use mod_constants
    use mod_types_3d
    implicit none

    real(dp), parameter :: RHO_ARC  = 0.1_dp    ! kg/m^3 (arc plasma density)
    real(dp), parameter :: V_ARC    = 200.0_dp   ! m/s (arc jet velocity)

contains

    subroutine compute_arc_impingement(elec, sh, m, cfg, n_elec)
        type(electrode_t), intent(in)   :: elec(:)
        type(shared_t), intent(inout)   :: sh
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        integer, intent(in)             :: n_elec

        integer  :: e, i, j, k
        real(dp) :: x_elec, y_elec, x_cell, y_cell, dist
        real(dp) :: p_imp, sigma_r, r2

        sh%S_arc_mom = 0.0_dp
        sigma_r = cfg%R_elec

        do e = 1, n_elec
            if (.not. elec(e)%bore_in_done) cycle
            if (elec(e)%arc_power < 1.0_dp) cycle

            x_elec = cfg%R_pcd * cos(elec(e)%theta_pos)
            y_elec = cfg%R_pcd * sin(elec(e)%theta_pos)

            ! Impingement pressure: p = rho_arc * v_arc^2
            p_imp = RHO_ARC * V_ARC**2

            do k = 1, m%nz
                if (m%z(k) > elec(e)%z_tip) cycle

                do j = 1, m%ntheta
                    do i = 1, m%nr
                        if (m%cell_type(i,j,k) == 0) cycle

                        x_cell = m%r(i) * cos(m%theta(j))
                        y_cell = m%r(i) * sin(m%theta(j))
                        dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                        r2 = dist**2 / (sigma_r**2 + SMALL)

                        if (r2 < 9.0_dp) then
                            ! Gaussian distribution, downward force (negative z)
                            sh%S_arc_mom(i,j,k) = sh%S_arc_mom(i,j,k) - &
                                p_imp * exp(-r2) / (PI * sigma_r**2) * &
                                (RHO_ARC / (cfg%rho_steel + SMALL))
                        end if
                    end do
                end do
            end do
        end do

    end subroutine compute_arc_impingement

end module mod_arc_impingement
