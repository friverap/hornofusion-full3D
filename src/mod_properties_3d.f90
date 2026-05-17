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

                    ! Gas: ideal gas approximation rho = rho_ref * T_ref / T
                    if (gas%T(i,j,k) > 100.0_dp) then
                        gas%rho(i,j,k) = cfg%rho_gas * cfg%T_ambient / gas%T(i,j,k)
                    else
                        gas%rho(i,j,k) = cfg%rho_gas
                    end if
                    gas%cp(i,j,k)  = cfg%cp_gas
                    gas%kth(i,j,k) = cfg%k_gas
                    gas%mu(i,j,k)  = cfg%mu_gas
                    gas%mu_eff(i,j,k) = cfg%mu_gas + sh%mu_t(i,j,k)
                end do
            end do
        end do

    end subroutine update_properties

end module mod_properties_3d
