!===============================================================================
! mod_drag_ergun.f90 - Ergun porous media drag for fluid-solid interaction
!
! Non-Darcian momentum sink on fluid flowing through solid scrap:
!   F_drag = -[ mu/K + C_F*rho*|v|/sqrt(K) ] * v = -coef * v
!
! Ergun correlations:
!   K = d_p^2 * epsilon^3 / (150*(1-epsilon)^2)
!   C_F = 1.75 / (d_p * epsilon^3)
!
! where epsilon = 1 - alpha_s (porosity), d_p = particle diameter.
!
! C1.4 (hallazgo 3.11): devuelve el COEFICIENTE positivo coef [kg/(m^3 s)]
! para tratamiento IMPLÍCITO en momentum (aP += coef*vol). El tratamiento
! explícito anterior (Su -= coef*u*vol) tenía amplificación coef*dt/rho >>1
! en lecho denso y divergía (|u| medido hasta 2.8e66 m/s). La linealización
! de Picard usa |v| del iterado anterior; el punto fijo es idéntico.
!===============================================================================
module mod_drag_ergun
    use mod_constants
    use mod_types_3d
    implicit none

contains

    subroutine compute_ergun_drag(ph, sol, m, cfg, drag_coef)
        type(phase_t), intent(in)  :: ph
        type(solid_t), intent(in)  :: sol
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        ! Cota inferior explícita: los arrays con halos tienen LB=-1 y un
        ! dummy (:,:,:) los remapearía a 1 desplazando el campo +2 celdas
        ! (regla GFortran, ver CLAUDE.md). El contrato anterior (:,:,:) tenía
        ! exactamente ese defecto.
        real(dp), intent(out)      :: drag_coef(-1:,-1:,-1:)  ! >= 0 [kg/(m^3 s)]

        integer :: i, j, k
        real(dp) :: eps, alpha_s, K_perm, C_F
        real(dp) :: vmag, d_p, mu_f, rho_f

        d_p = cfg%d_particle
        drag_coef = 0.0_dp

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

                    drag_coef(i,j,k) = mu_f / (K_perm + SMALL) &
                                     + C_F * rho_f * vmag / (sqrt(K_perm) + SMALL)
                end do
            end do
        end do

    end subroutine compute_ergun_drag

end module mod_drag_ergun
