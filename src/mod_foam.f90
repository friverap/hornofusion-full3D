!===============================================================================
! mod_foam.f90 - Índice de espuma de la escoria (E2.5, roadmap del paper)
!
! Ventana de Pretorius & Carlisle (1999) parametrizada de forma suave y
! PURA (unit-testeable punto a punto):
!
!   xi(B2, X_FeO, T) = XI_MAX * f_B2 * f_FeO * f_T   [s]
!
!   f_B2  : sigmoide creciente hacia el plateau de saturación
!           (B2 >= ~2.1 con MgO saturado sostiene la espuma; B2 bajo =
!           escoria líquida agresiva que no atrapa el CO).
!   f_FeO : campana centrada en la ventana 15-20% (FeO alto baja la
!           viscosidad efectiva y mata la espuma: FCEL02 con mediana 33%
!           es el caso documentado por la Radiografía).
!   f_T   : decaimiento suave con el sobrecalentamiento (viscosidad).
!
! Altura de espuma local: H = xi * j_CO con j_CO la velocidad superficial
! del CO generado por la reducción FeO+C en la propia celda (v1 LOCAL:
! la espuma vive donde se genera el gas y donde hay escoria; sin
! apilamiento por columna => invariante MPI trivial). alpha_foam es un
! atributo óptico: NO entra en la restricción de volumen.
!===============================================================================
module mod_foam
    use mod_constants
    implicit none

    real(dp), parameter :: XI_MAX    = 1.2_dp     ! s (indice máximo)
    real(dp), parameter :: B2_HALF   = 1.9_dp     ! centro de la sigmoide
    real(dp), parameter :: B2_WIDTH  = 0.15_dp
    real(dp), parameter :: FEO_CTR   = 0.18_dp    ! centro de la ventana
    real(dp), parameter :: FEO_WIDTH = 0.08_dp
    real(dp), parameter :: T_REF_FOAM = 1823.0_dp ! K
    real(dp), parameter :: T_SCALE    = 500.0_dp  ! K

contains

    pure function xi_pretorius(b2, x_feo, T) result(xi)
        real(dp), intent(in) :: b2, x_feo, T
        real(dp) :: xi, f_b2, f_feo, f_t

        f_b2  = 1.0_dp / (1.0_dp + exp(-(b2 - B2_HALF) / B2_WIDTH))
        f_feo = exp(-((x_feo - FEO_CTR) / FEO_WIDTH)**2)
        f_t   = min(2.0_dp, max(0.2_dp, exp(-(T - T_REF_FOAM) / T_SCALE)))
        xi = XI_MAX * f_b2 * f_feo * f_t
    end function xi_pretorius

end module mod_foam
