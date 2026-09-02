!===============================================================================
! mod_face_flux.f90 - Flujos másicos de CARA únicos y conservativos (C2.2)
!
! Hallazgo 3.8: la convección usaba la velocidad del CENTRO de cada celda
! para sus dos caras de cada dirección (y Fs = Fn exactamente): el flujo de
! la cara compartida difería según qué celda lo evaluara -> la convección no
! telescopaba y creaba/destruía masa y energía (medido: 59% de la masa
! fundida desaparecía en el transporte).
!
! Definición única: densidad de flujo promediada aritméticamente a la cara,
!   F_(i-1/2) = 0.5*( (a*rho*u)|_{i-1} + (a*rho*u)|_i ) * A_(i-1/2)
! idéntica vista desde ambas celdas => telescopía exacta.
!
! Correcciones incluidas:
! - Flujo azimutal FÍSICO: F = a*rho*u_th * Ath (el /r anterior lo
!   subestimaba por un factor r; Ath = dr*dz ya es el área de la cara).
! - Caras contra celdas inactivas o fronteras físicas: F = 0 (paredes
!   impermeables; antes quedaba un flujo espurio de pared en aP).
!   Requiere que los halos de cell_type en fronteras físicas estén
!   marcados 0 (mesh_generate_parallel).
!===============================================================================
module mod_face_flux
    use mod_constants
    use mod_types_3d
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Flujos másicos de fase por las 6 caras de la celda (i,j,k):
    !   F = 0.5*(aq*rho*u|_P + aq*rho*u|_NB) * A_cara,  0 contra inactivas.
    !---------------------------------------------------------------------------
    subroutine face_mass_fluxes(aq, rho, ur, uth, uz, m, i, j, k, &
                                Fw, Fe, Fs, Fn, Fb, Ft)
        real(dp), intent(in) :: aq(-1:,-1:,-1:), rho(-1:,-1:,-1:)
        real(dp), intent(in) :: ur(-1:,-1:,-1:), uth(-1:,-1:,-1:)
        real(dp), intent(in) :: uz(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer, intent(in)  :: i, j, k
        real(dp), intent(out) :: Fw, Fe, Fs, Fn, Fb, Ft

        real(dp) :: gP_r, gP_th, gP_z

        gP_r  = aq(i,j,k) * rho(i,j,k) * ur(i,j,k)
        gP_th = aq(i,j,k) * rho(i,j,k) * uth(i,j,k)
        gP_z  = aq(i,j,k) * rho(i,j,k) * uz(i,j,k)

        Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp
        Fn = 0.0_dp; Fb = 0.0_dp; Ft = 0.0_dp

        if (m%cell_type(i-1,j,k) /= 0) &
            Fw = 0.5_dp * (aq(i-1,j,k)*rho(i-1,j,k)*ur(i-1,j,k) + gP_r) &
                 * m%Ar(i-1,j,k)
        if (m%cell_type(i+1,j,k) /= 0) &
            Fe = 0.5_dp * (gP_r + aq(i+1,j,k)*rho(i+1,j,k)*ur(i+1,j,k)) &
                 * m%Ar(i,j,k)
        if (m%cell_type(i,j-1,k) /= 0) &
            Fs = 0.5_dp * (aq(i,j-1,k)*rho(i,j-1,k)*uth(i,j-1,k) + gP_th) &
                 * m%Ath(i,j,k)
        if (m%cell_type(i,j+1,k) /= 0) &
            Fn = 0.5_dp * (gP_th + aq(i,j+1,k)*rho(i,j+1,k)*uth(i,j+1,k)) &
                 * m%Ath(i,j,k)
        if (m%cell_type(i,j,k-1) /= 0) &
            Fb = 0.5_dp * (aq(i,j,k-1)*rho(i,j,k-1)*uz(i,j,k-1) + gP_z) &
                 * m%Az(i,j,k-1)
        if (m%cell_type(i,j,k+1) /= 0) &
            Ft = 0.5_dp * (gP_z + aq(i,j,k+1)*rho(i,j,k+1)*uz(i,j,k+1)) &
                 * m%Az(i,j,k)
    end subroutine face_mass_fluxes

    !---------------------------------------------------------------------------
    ! Variante sin fracción de fase (ecuación de alpha, k-eps):
    !   F = 0.5*(rho*u|_P + rho*u|_NB) * A_cara
    !---------------------------------------------------------------------------
    subroutine face_mass_fluxes_noalpha(rho, ur, uth, uz, m, i, j, k, &
                                        Fw, Fe, Fs, Fn, Fb, Ft)
        real(dp), intent(in) :: rho(-1:,-1:,-1:)
        real(dp), intent(in) :: ur(-1:,-1:,-1:), uth(-1:,-1:,-1:)
        real(dp), intent(in) :: uz(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer, intent(in)  :: i, j, k
        real(dp), intent(out) :: Fw, Fe, Fs, Fn, Fb, Ft

        real(dp) :: gP_r, gP_th, gP_z

        gP_r  = rho(i,j,k) * ur(i,j,k)
        gP_th = rho(i,j,k) * uth(i,j,k)
        gP_z  = rho(i,j,k) * uz(i,j,k)

        Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp
        Fn = 0.0_dp; Fb = 0.0_dp; Ft = 0.0_dp

        if (m%cell_type(i-1,j,k) /= 0) &
            Fw = 0.5_dp * (rho(i-1,j,k)*ur(i-1,j,k) + gP_r) * m%Ar(i-1,j,k)
        if (m%cell_type(i+1,j,k) /= 0) &
            Fe = 0.5_dp * (gP_r + rho(i+1,j,k)*ur(i+1,j,k)) * m%Ar(i,j,k)
        if (m%cell_type(i,j-1,k) /= 0) &
            Fs = 0.5_dp * (rho(i,j-1,k)*uth(i,j-1,k) + gP_th) * m%Ath(i,j,k)
        if (m%cell_type(i,j+1,k) /= 0) &
            Fn = 0.5_dp * (gP_th + rho(i,j+1,k)*uth(i,j+1,k)) * m%Ath(i,j,k)
        if (m%cell_type(i,j,k-1) /= 0) &
            Fb = 0.5_dp * (rho(i,j,k-1)*uz(i,j,k-1) + gP_z) * m%Az(i,j,k-1)
        if (m%cell_type(i,j,k+1) /= 0) &
            Ft = 0.5_dp * (gP_z + rho(i,j,k+1)*uz(i,j,k+1)) * m%Az(i,j,k)
    end subroutine face_mass_fluxes_noalpha

end module mod_face_flux
