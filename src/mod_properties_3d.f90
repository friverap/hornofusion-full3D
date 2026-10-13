!===============================================================================
! mod_properties_3d.f90 - Phase-dependent material properties
!
! Updates rho, cp, kth, mu, mu_eff for liquid and gas phases.
! Liquid: constant properties + turbulent viscosity.
! Gas: temperature-dependent density (ideal gas approximation).
!===============================================================================
module mod_properties_3d
    use mod_constants
    use mod_types_3d
    implicit none

contains

    subroutine update_properties(liq, gas, sh, m, cfg)
        type(phase_t), intent(inout)  :: liq, gas
        type(shared_t), intent(in)    :: sh
        type(mesh_t), intent(in)      :: m
        type(config_t), intent(in)    :: cfg

        integer :: i, j, k

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle

                    ! Liquid steel: constant base properties
                    liq%rho(i,j,k) = cfg%rho_steel
                    liq%cp(i,j,k)  = cfg%cp_l
                    liq%kth(i,j,k) = cfg%k_l
                    liq%mu(i,j,k)  = cfg%mu_l
                    liq%mu_eff(i,j,k) = cfg%mu_l + sh%mu_t(i,j,k)

                    ! Gas ideal rho(P0 + p, T): EOS unica gas_eos
                    ! (mod_constants; compresion fisica, auditoria M25).
                    ! El modelo de MEZCLA (opt-in) sigue low-Mach rho(P0, T):
                    ! ver la nota en mod_mixture_3d
                    gas%rho(i,j,k) = gas_eos(cfg%rho_gas, gas%T(i,j,k), &
                                             merge(0.0_dp, sh%p(i,j,k), cfg%mixture_model))
                    gas%cp(i,j,k)  = cfg%cp_gas
                    gas%kth(i,j,k) = cfg%k_gas
                    gas%mu(i,j,k)  = cfg%mu_gas
                    ! mu_t proviene del k-eps resuelto con rho del LÍQUIDO
                    ! (7500 kg/m3): sumarlo al gas inflaba su viscosidad
                    ! ~1e6x (hallazgo 3.12). El gas queda laminar hasta tener
                    ! su propio modelo de turbulencia.
                    gas%mu_eff(i,j,k) = cfg%mu_gas
                end do
            end do
        end do

    end subroutine update_properties

end module mod_properties_3d
