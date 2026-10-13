!===============================================================================
! mod_drag_ergun.f90 - Ergun porous media drag for fluid-solid interaction
!
! Sumidero de momento del fluido en el lecho de chatarra, F = -coef v con
!   coef = eps^2 A_E + eps^3 B_E |v|      (forma de Gidaspow, velocidad
!   A_E = 150 mu (1-eps)^2/(d_p^2 eps^3)   intersticial; auditoria A6)
!   B_E = 1.75 rho (1-eps)/(d_p eps^3)
! UNA definicion: mod_constants::ergun_coefficients. eps = 1 - alpha_s (para
! el gas del lecho, 1 - alpha_s - alpha_l: el liquido retenido es obstaculo,
! M29). (La forma Forchheimer mu/K + C_F rho|v|/sqrt(K) de versiones previas
! tenia C_F con unidades de 1/m: Bug 21.)
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
    subroutine compute_ergun_drag(ph, sol, m, cfg, drag_coef, on_bed, alpha_held)
        type(phase_t), intent(in)  :: ph
        type(solid_t), intent(in)  :: sol
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        logical, intent(in), optional :: on_bed
        ! Fraccion de la OTRA fase fluida retenida en el poro (auditoria M29):
        ! para el GAS de un lecho parcialmente inundado el liquido retenido es
        ! obstaculo adicional -> porosidad efectiva del gas 1 - alpha_s -
        ! alpha_l (modelo de permeabilidad relativa de Saez & Carbonell, AIChE
        ! J. 31 (1985) 52; Attou, Boyer & Ferschneider, Chem. Eng. Sci. 54
        ! (1999) 785). Antes el gas veia epsilon = 1 - alpha_s aunque el poro
        ! estuviera casi lleno de liquido. Solo en celdas del lecho propio.
        real(dp), intent(in), optional :: alpha_held(-1:,-1:,-1:)
        ! Cota inferior explícita: los arrays con halos tienen LB=-1 y un
        ! dummy (:,:,:) los remapearía a 1 desplazando el campo +2 celdas
        ! (regla GFortran, ver CLAUDE.md). El contrato anterior (:,:,:) tenía
        ! exactamente ese defecto.
        real(dp), intent(out)      :: drag_coef(-1:,-1:,-1:)  ! >= 0 [kg/(m^3 s)]

        integer :: i, j, k
        real(dp) :: alpha_s, A, B
        real(dp) :: vmag, d_p, fade
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
                    fade = 1.0_dp
                    if (use_below .and. alpha_s < 1.0e-2_dp) then
                        if (m%cell_type(i,j,k-1) /= 0) then
                            alpha_s = max(alpha_s, sol%alpha_s(i,j,k-1))
                            ! F2.28 (1-oct-2026): el Ergun EFECTIVO del lecho de
                            ! abajo (F2.15) solo frena al liquido que puede
                            ! PERCOLAR hacia el: una celda EMPACADA (alpha_l -> 1)
                            ! no tiene poro abierto, no puede drenar a ninguna
                            ! parte — su fila del Poisson se lo prohibe — y lo
                            ! que necesita como sumidero es la presion, no un
                            ! arrastre de 25 veces su inercia. Con el Ergun del
                            ! lecho (epsilon acotado a 0.01: A·V = 1.1e5 frente
                            ! a alpha rho V/dt = 4.7e3) la celda queda con
                            ! d = alpha V/aP minusculo, sus coeficientes en el
                            ! Poisson caen a 1e-7 y se vuelve el "numerical dead
                            ! end for the liquid" del water packing (TRACE
                            ! Theory Manual §2; RELAP5 Vol. I §3.4.6): cualquier
                            ! volumen que le empuja la celda de superficie
                            ! exige decenas de kPa y se descarga por la unica
                            ! cara blanda, la del gas (medido: 35-52 kPa y gas
                            ! a +90..+117 m/s, cinco pulsos de 80 ms bajo cada
                            ! electrodo, B1 v34 a 281 s; practicamente TODO el
                            ! bano descansa sobre lecho, 204 de 206 celdas).
                            ! El desvanecimiento es lineal con el liquido de la
                            ! celda: el charco parcial de F2.15 (alpha_l ~ 0.3)
                            ! conserva el 70 % del freno; la celda llena, nada.
                            fade = max(0.0_dp, 1.0_dp - ph%alpha(i,j,k))
                        end if
                    end if
                    if (alpha_s < 1.0e-6_dp .or. fade <= 0.0_dp) cycle
                    if (present(alpha_held)) then
                        if (sol%alpha_s(i,j,k) >= 1.0e-6_dp) &
                            alpha_s = min(alpha_s + max(alpha_held(i,j,k), 0.0_dp), 0.99_dp)
                    end if

                    ! Ergun (1952): coef = A + B |v| con la unica definicion de
                    ! los coeficientes (mod_constants::ergun_coefficients)
                    call ergun_coefficients(alpha_s, ph%rho(i,j,k), ph%mu(i,j,k), d_p, A, B)
                    vmag = sqrt(ph%ur(i,j,k)**2 + ph%uth(i,j,k)**2 + ph%uz(i,j,k)**2)
                    drag_coef(i,j,k) = fade * (A + B * vmag)
                end do
            end do
        end do

    end subroutine compute_ergun_drag

end module mod_drag_ergun
