!===============================================================================
! mod_drag_ergun.f90 - Ergun porous media drag for fluid-solid interaction
!
! Non-Darcian momentum sink on fluid flowing through solid scrap:
!   F_drag = -(mu/K)*v + (C_F*rho/sqrt(K))*|v|*v
!
! Ergun correlations:
!   K = d_p^2 * epsilon^3 / (150*(1-epsilon)^2)
!   C_F = 1.75 / (d_p * epsilon^3)
!
! where epsilon = 1 - alpha_s (porosity), d_p = particle diameter.
!===============================================================================
module mod_drag_ergun
    use mod_constants
    use mod_types_3d
    implicit none

contains

    subroutine compute_ergun_drag(ph, sol, m, cfg, &
                                   S_drag_r, S_drag_th, S_drag_z)
        type(phase_t), intent(in)  :: ph
        type(solid_t), intent(in)  :: sol
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        real(dp), intent(out)      :: S_drag_r(:,:,:), S_drag_th(:,:,:), S_drag_z(:,:,:)

        integer :: i, j, k
        real(dp) :: eps, alpha_s, K_perm, C_F
        real(dp) :: vmag, d_p, mu_f, rho_f
        real(dp) :: darcy_coeff, forch_coeff

        d_p = cfg%d_particle
        S_drag_r = 0.0_dp; S_drag_th = 0.0_dp; S_drag_z = 0.0_dp

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle

                    alpha_s = sol%alpha_s(i,j,k)
                    if (alpha_s < 1.0e-6_dp) cycle

                    eps = 1.0_dp - alpha_s
                    eps = max(eps, 0.01_dp)

                    ! Ergun permeability and Forchheimer coefficient
                    K_perm = d_p**2 * eps**3 / (150.0_dp * (1.0_dp - eps)**2 + SMALL)
                    C_F = 1.75_dp / (d_p * eps**3 + SMALL)

                    mu_f  = ph%mu(i,j,k)
                    rho_f = ph%rho(i,j,k)

                    vmag = sqrt(ph%ur(i,j,k)**2 + ph%uth(i,j,k)**2 + ph%uz(i,j,k)**2)

                    darcy_coeff = mu_f / (K_perm + SMALL)
                    forch_coeff = C_F * rho_f * vmag / (sqrt(K_perm) + SMALL)

                    ! Drag source: negative = opposes flow
                    S_drag_r(i,j,k)  = -(darcy_coeff + forch_coeff) * ph%ur(i,j,k)
                    S_drag_th(i,j,k) = -(darcy_coeff + forch_coeff) * ph%uth(i,j,k)
                    S_drag_z(i,j,k)  = -(darcy_coeff + forch_coeff) * ph%uz(i,j,k)
                end do
            end do
        end do

    end subroutine compute_ergun_drag

end module mod_drag_ergun
