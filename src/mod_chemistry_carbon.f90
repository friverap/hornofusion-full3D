!===============================================================================
! mod_chemistry_carbon.f90 - Carbon oxidation via Maahs rate
!
! C + 0.5*O2 -> CO
! Temperature-dependent reaction rate for HBI layers.
! Minimal impact expected (no burners in this operation).
!===============================================================================
module mod_chemistry_carbon
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    implicit none

    real(dp), parameter :: A_MAAHS   = 2.3e5_dp   ! pre-exponential factor [kg/(m^2 s Pa)]
    real(dp), parameter :: E_MAAHS   = 1.63e5_dp  ! activation energy [J/mol]
    real(dp), parameter :: MW_C      = 0.012_dp    ! kg/mol
    real(dp), parameter :: MW_O2     = 0.032_dp    ! kg/mol
    real(dp), parameter :: MW_CO     = 0.028_dp    ! kg/mol
    real(dp), parameter :: DH_REACT  = -110.5e3_dp ! J/mol (exothermic partial oxidation)
    ! Secondary combustion: CO + 1/2 O2 -> CO2
    real(dp), parameter :: A_CO2    = 1.0e6_dp    ! pre-exponential [m3/(kg·s·Pa)]
    real(dp), parameter :: E_CO2    = 1.25e5_dp   ! activation energy [J/mol]
    real(dp), parameter :: MW_CO2   = 0.044_dp    ! kg/mol
    real(dp), parameter :: DH_CO2   = -283.0e3_dp ! J/mol (CO + 1/2 O2 -> CO2, exothermic)

contains

    subroutine compute_carbon_oxidation(sol, gas, sh, m, cfg)
        type(solid_t), intent(in)    :: sol
        type(phase_t), intent(in)    :: gas
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k
        real(dp) :: T_s, T_g, rate, P_O2, A_surf
        real(dp) :: Q_chem, r_co2

        sh%S_chem    = 0.0_dp
        sh%S_CO_src  = 0.0_dp
        sh%S_CO2_src = 0.0_dp

        ! Primary oxidation: C + 1/2 O2 -> CO (Maahs rate on scrap surface)
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (sol%alpha_s(i,j,k) < 0.01_dp) cycle

                    T_s = sol%T_s(i,j,k)
                    if (T_s < 800.0_dp) cycle

                    ! O2 partial pressure (approximate)
                    P_O2 = 0.21_dp * 101325.0_dp * gas%alpha(i,j,k)

                    ! Maahs rate [kg_C/(m^2·s)]
                    rate = A_MAAHS * P_O2 * exp(-E_MAAHS / (R_GAS * T_s))

                    ! Specific surface area
                    A_surf = 6.0_dp * sol%alpha_s(i,j,k) / (cfg%d_particle + SMALL)

                    ! Volumetric heat release [W/m^3]
                    Q_chem = -DH_REACT / MW_C * rate * A_surf
                    sh%S_chem(i,j,k) = sh%S_chem(i,j,k) + Q_chem

                    ! CO production source [kg_CO/(m^3·s)]
                    sh%S_CO_src(i,j,k) = sh%S_CO_src(i,j,k) + rate * A_surf * (MW_CO / MW_C)
                end do
            end do
        end do

        ! Secondary combustion: CO + 1/2 O2 -> CO2 (gas-phase, T > 600 K)
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (gas%alpha(i,j,k) < SMALL) cycle

                    T_g = gas%T(i,j,k)
                    if (T_g < 600.0_dp) cycle
                    if (sh%Y_CO(i,j,k) < SMALL) cycle

                    P_O2  = 0.21_dp * 101325.0_dp * gas%alpha(i,j,k)
                    r_co2 = A_CO2 * sh%Y_CO(i,j,k) * P_O2 * exp(-E_CO2 / (R_GAS * T_g))

                    ! Anti-overshoot: cannot destroy more CO than available this step
                    r_co2 = min(r_co2, sh%Y_CO(i,j,k) * gas%rho(i,j,k) * gas%alpha(i,j,k) &
                                       / max(cfg%dt, 1.0e-10_dp))

                    sh%S_CO_src(i,j,k)  = sh%S_CO_src(i,j,k)  - r_co2
                    sh%S_CO2_src(i,j,k) = sh%S_CO2_src(i,j,k) + r_co2 * (MW_CO2 / MW_CO)
                    ! Exothermic heat released to gas [W/m^3]
                    sh%S_chem(i,j,k)    = sh%S_chem(i,j,k)    + (-DH_CO2 / MW_CO) * r_co2
                end do
            end do
        end do

    end subroutine compute_carbon_oxidation

end module mod_chemistry_carbon
