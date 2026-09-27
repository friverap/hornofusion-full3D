!===============================================================================
! mod_drag_ergun.f90 - Ergun porous media drag for fluid-solid interaction
!
! Non-Darcian momentum sink on fluid flowing through solid scrap:
!   F_drag = -[ mu/K + C_F*rho*|v|/sqrt(K) ] * v = -coef * v
!
! Ergun correlations:
!   K = d_p^2 * epsilon^3 / (150*(1-epsilon)^2)
!   coef = A + B|v|, A = 150 mu (1-eps)^2/(d_p^2 eps^3), B = 1.75 rho (1-eps)/(d_p eps^3)
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

    ! on_bed (F2.15, 2026-09-27): usar el alpha_s EFECTIVO max(propio, de la
    ! celda de abajo). Una celda sin chatarra propia que descansa sobre el
    ! lecho es una pelicula drenando hacia el: su sumidero de momento es la
    ! resistencia del lecho al que drena, no el arrastre del gas. Sin esto
    ! quedaba sin freno alguno (Ergun 0 por alpha_s = 0) y caia en caida libre
    ! hasta U_LIQ_MAX sobre la celda del lecho en cap. Es la MISMA regla que
    ! F2.14 aplica al drift del liquido disperso, de modo que las dos ramas
    ! (continua y dispersa) coinciden en el umbral ALPHA_LIQ_CONT. Solo para
    ! el LIQUIDO: el gas de la celda de encima no drena al lecho.
    subroutine compute_ergun_drag(ph, sol, m, cfg, drag_coef, on_bed)
        type(phase_t), intent(in)  :: ph
        type(solid_t), intent(in)  :: sol
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        logical, intent(in), optional :: on_bed
        ! Cota inferior explícita: los arrays con halos tienen LB=-1 y un
        ! dummy (:,:,:) los remapearía a 1 desplazando el campo +2 celdas
        ! (regla GFortran, ver CLAUDE.md). El contrato anterior (:,:,:) tenía
        ! exactamente ese defecto.
        real(dp), intent(out)      :: drag_coef(-1:,-1:,-1:)  ! >= 0 [kg/(m^3 s)]

        integer :: i, j, k
        real(dp) :: alpha_s, A, B
        real(dp) :: vmag, d_p
        logical  :: use_below

        use_below = .false.
        if (present(on_bed)) use_below = on_bed
        d_p = cfg%d_particle
        drag_coef = 0.0_dp

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle

                    alpha_s = sol%alpha_s(i,j,k)
                    if (use_below .and. alpha_s < 1.0e-2_dp) then
                        if (m%cell_type(i,j,k-1) /= 0) &
                            alpha_s = max(alpha_s, sol%alpha_s(i,j,k-1))
                    end if
                    if (alpha_s < 1.0e-6_dp) cycle

                    ! Ergun (1952): coef = A + B |v| con la unica definicion de
                    ! los coeficientes (mod_constants::ergun_coefficients)
                    call ergun_coefficients(alpha_s, ph%rho(i,j,k), ph%mu(i,j,k), d_p, A, B)
                    vmag = sqrt(ph%ur(i,j,k)**2 + ph%uth(i,j,k)**2 + ph%uz(i,j,k)**2)
                    drag_coef(i,j,k) = A + B * vmag
                end do
            end do
        end do

    end subroutine compute_ergun_drag

end module mod_drag_ergun
