!===============================================================================
! mod_chemistry_carbon.f90 - Oxidación de carbono (C3.3, hallazgo 3.4)
!
!   Primaria (superficie de chatarra, cinética de Maahs):
!       C + 1/2 O2 -> CO       (dH = -110.5 kJ/mol, calor AL SÓLIDO)
!   Secundaria (fase gas):
!       CO + 1/2 O2 -> CO2     (dH = -283.0 kJ/mol, calor al gas via S_chem)
!
! Correcciones sobre la versión original:
!  - El O2 se TRANSPORTA y se AGOTA (sh%Y_O2, inicial 0.232 = aire; sin
!    ingreso de aire modelado — horno sellado, documentado). Antes
!    P_O2 = 0.21 atm siempre: oxidante infinito.
!  - El CARBONO es finito: inventario sol%m_C = carbon_frac * m_s en la
!    carga; se consume y la reacción para en 0. Antes m_s intacto.
!  - AMBAS reacciones limitadas por el suministro local de O2 y por el
!    reactivo disponible en el paso: la tasa queda en régimen limitado por
!    difusión/suministro, lo que acota físicamente la cinética de Maahs
!    (cuyo prefactor A, con P_O2 fijo, producía S_chem ~ 5.7e10 W/m3 y
!    T_gas -> 1e10 K — medido en producción pre-roadmap).
!  - El calor primario va al SÓLIDO (E_s, con inventario de entalpía
!    consistente y contador de auditoría E_chem_sol); antes iba entero a
!    los fluidos.
!  - Cinética secundaria con unidades saneadas: r = A2 * rho_CO * rho_O2 *
!    exp(-E/RT) con A2 [m3/(kg s)] (segundo orden en densidades parciales).
!
! Estequiometría (por kg): C->CO consume 4/3 kg O2 y produce 7/3 kg CO;
! CO->CO2 consume 4/7 kg O2 y produce 11/7 kg CO2.
!===============================================================================
module mod_chemistry_carbon
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_melting_3d, only: solid_T_from_enthalpy
    use mod_audit, only: audit_add, AUD_CHEM_SOL
    implicit none

    real(dp), parameter :: A_MAAHS   = 2.3e5_dp   ! pre-exponential factor [kg/(m^2 s Pa)]
    real(dp), parameter :: E_MAAHS   = 1.63e5_dp  ! activation energy [J/mol]
    real(dp), parameter :: MW_C      = 0.012_dp    ! kg/mol
    real(dp), parameter :: MW_O2     = 0.032_dp    ! kg/mol
    real(dp), parameter :: MW_CO     = 0.028_dp    ! kg/mol
    real(dp), parameter :: MW_AIR    = 0.02897_dp  ! kg/mol
    real(dp), parameter :: DH_REACT  = -110.5e3_dp ! J/mol (exothermic partial oxidation)
    ! Secondary combustion: CO + 1/2 O2 -> CO2
    real(dp), parameter :: A_CO2    = 1.0e4_dp    ! [m3/(kg s)] segundo orden (calibrable)
    real(dp), parameter :: E_CO2    = 1.25e5_dp   ! activation energy [J/mol]
    real(dp), parameter :: MW_CO2   = 0.044_dp    ! kg/mol
    real(dp), parameter :: DH_CO2   = -283.0e3_dp ! J/mol (CO + 1/2 O2 -> CO2, exothermic)

contains

    subroutine compute_carbon_oxidation(sol, gas, sh, m, cfg)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(in)    :: gas
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k
        real(dp) :: T_s, T_g, P_O2, A_surf, vol
        real(dp) :: r_C, r_CO, o2_avail_rate, Q_chem
        real(dp) :: rho_CO, rho_O2

        sh%S_chem    = 0.0_dp
        sh%S_CO_src  = 0.0_dp
        sh%S_CO2_src = 0.0_dp
        sh%S_O2_src  = 0.0_dp

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (gas%alpha(i,j,k) < ALPHA_CUTOFF) cycle

                    vol = m%vol(i,j,k)
                    T_g = gas%T(i,j,k)

                    ! Presión parcial de O2 desde la fracción másica
                    ! (aprox. de fracción molar con MW del aire)
                    P_O2 = 101325.0_dp * sh%Y_O2(i,j,k) * MW_AIR / MW_O2
                    if (P_O2 <= 0.0_dp) cycle

                    ! Tasa de suministro local de O2 [kg O2/(m3 s)]
                    o2_avail_rate = gas%alpha(i,j,k) * gas%rho(i,j,k) * &
                                    sh%Y_O2(i,j,k) / cfg%dt

                    !------------------------------------------------------
                    ! Primaria: C + 1/2 O2 -> CO (Maahs en la superficie)
                    !------------------------------------------------------
                    if (sol%alpha_s(i,j,k) >= 0.01_dp .and. &
                        sol%m_C(i,j,k) > SMALL .and. &
                        sol%m_s(i,j,k) > SMALL) then
                        T_s = sol%T_s(i,j,k)
                        if (T_s >= 800.0_dp) then
                            A_surf = 6.0_dp * sol%alpha_s(i,j,k) / &
                                     (cfg%d_particle + SMALL)
                            ! Cinética de Maahs [kg C/(m3 s)]
                            r_C = A_MAAHS * P_O2 * &
                                  exp(-E_MAAHS / (R_GAS * T_s)) * A_surf
                            ! Límites físicos: carbono del inventario y O2
                            ! disponible este paso (régimen de suministro)
                            r_C = min(r_C, sol%m_C(i,j,k) / (vol * cfg%dt))
                            r_C = min(r_C, 0.75_dp * o2_avail_rate)

                            if (r_C > 0.0_dp) then
                                sol%m_C(i,j,k) = max(0.0_dp, &
                                    sol%m_C(i,j,k) - r_C * vol * cfg%dt)
                                sh%S_CO_src(i,j,k) = sh%S_CO_src(i,j,k) + &
                                    r_C * (MW_CO / MW_C)
                                sh%S_O2_src(i,j,k) = sh%S_O2_src(i,j,k) - &
                                    r_C * (0.5_dp * MW_O2 / MW_C)
                                o2_avail_rate = o2_avail_rate - &
                                    r_C * (0.5_dp * MW_O2 / MW_C)

                                ! Calor de oxidación primaria AL SÓLIDO
                                Q_chem = (-DH_REACT / MW_C) * r_C * vol * cfg%dt
                                sol%E_s(i,j,k) = sol%E_s(i,j,k) + Q_chem
                                sol%T_s(i,j,k) = solid_T_from_enthalpy( &
                                    sol%E_s(i,j,k) / sol%m_s(i,j,k), cfg)
                                call audit_add(AUD_CHEM_SOL, Q_chem)
                            end if
                        end if
                    end if

                    !------------------------------------------------------
                    ! Secundaria: CO + 1/2 O2 -> CO2 (fase gas, T > 600 K)
                    !------------------------------------------------------
                    if (T_g >= 600.0_dp .and. sh%Y_CO(i,j,k) > SMALL .and. &
                        o2_avail_rate > 0.0_dp) then
                        rho_CO = gas%alpha(i,j,k) * gas%rho(i,j,k) * sh%Y_CO(i,j,k)
                        rho_O2 = gas%alpha(i,j,k) * gas%rho(i,j,k) * sh%Y_O2(i,j,k)
                        ! Segundo orden en densidades parciales [kg CO/(m3 s)]
                        r_CO = A_CO2 * rho_CO * rho_O2 * &
                               exp(-E_CO2 / (R_GAS * T_g))
                        ! Límites: CO disponible y O2 restante del paso
                        r_CO = min(r_CO, rho_CO / cfg%dt)
                        r_CO = min(r_CO, o2_avail_rate * (2.0_dp * MW_CO / MW_O2))

                        if (r_CO > 0.0_dp) then
                            sh%S_CO_src(i,j,k)  = sh%S_CO_src(i,j,k)  - r_CO
                            sh%S_CO2_src(i,j,k) = sh%S_CO2_src(i,j,k) + &
                                r_CO * (MW_CO2 / MW_CO)
                            sh%S_O2_src(i,j,k)  = sh%S_O2_src(i,j,k)  - &
                                r_CO * (0.5_dp * MW_O2 / MW_CO)
                            ! Calor de combustión al gas (vía S_chem,
                            ! ponderado por fase en la energía)
                            sh%S_chem(i,j,k) = sh%S_chem(i,j,k) + &
                                (-DH_CO2 / MW_CO) * r_CO
                        end if
                    end if
                end do
            end do
        end do

    end subroutine compute_carbon_oxidation

end module mod_chemistry_carbon
