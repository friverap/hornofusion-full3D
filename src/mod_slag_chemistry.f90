!===============================================================================
! mod_slag_chemistry.f90 - Química de la escoria (E2.3/E2.4, roadmap paper)
!
! Oxidación (interfaz baño-escoria, E2.3):
!     Fe(l) + 1/2 O2 -> FeO(slag)      dH = -272 kJ/mol (exo, a la escoria)
!   Consume el O2 REMANENTE del paso (el que la química del carbono no
!   tomó: alpha_g*rho_g*Y_O2/dt + S_O2_src, con S_O2_src ya negativo),
!   escalado por la eficiencia calibrable eta_feo. El Fe sale del baño
!   (pérdida de rendimiento, auditada) y su entalpía VIAJA con él a la
!   escoria (transferencia interna: los inventarios la capturan); solo el
!   calor de reacción es fuente externa del balance (E_slag_ox).
!
! Reducción (celdas de escoria con carbón SL_C, E2.4):
!     FeO + C -> Fe(l) + CO            dH = +155 kJ/mol FeO (endo)
!   Primer orden en FeO (Morales-like), capada por FeO y C disponibles;
!   el Fe vuelve al baño con su entalpía a T_sl y el CO alimenta las
!   especies del gas (y la espuma, E2.5).
!
! Estabilizadores (riesgo #1 del roadmap: runaway FeO):
!   - cap por O2 disponible del paso (estructural),
!   - cap por fracción de masa del líquido de abajo (F_MAX_FE por paso),
!   - cap térmico Q <= m_sl*cp_sl*DT_MAX_SLAG (recorta la REACCIÓN, no el
!     calor: masa y energía siempre consistentes),
!   - eta_feo conservador por default (0.3).
!===============================================================================
module mod_slag_chemistry
    use mod_constants
    use mod_types_3d
    use mod_audit, only: audit_add, AUD_FE_YIELD, AUD_FE_RETURN, &
                         AUD_SLAG_OX_E, AUD_SLAG_RED_E
    use mod_melting_3d, only: liquid_datum_offset
    use mod_foam, only: xi_pretorius
    implicit none

    real(dp), parameter :: SMALL_SL = 1.0e-6_dp   ! (como mod_slag_3d)
    real(dp), parameter :: MW_FE   = 0.05585_dp   ! kg/mol
    real(dp), parameter :: MW_FEO  = 0.07185_dp   ! kg/mol
    real(dp), parameter :: MW_O2_S = 0.032_dp     ! kg/mol
    real(dp), parameter :: MW_C_S  = 0.012_dp     ! kg/mol
    real(dp), parameter :: MW_CO_S = 0.028_dp     ! kg/mol
    real(dp), parameter :: DH_FEO_OX  = -272.0e3_dp ! J/mol FeO (exo)
    real(dp), parameter :: DH_FEO_RED = +155.0e3_dp ! J/mol FeO (endo)

    ! Cinética de reducción (Morales-like, calibrable en B6)
    real(dp), parameter :: K_RED = 5.0_dp         ! 1/s (prefactor)
    real(dp), parameter :: E_RED = 1.2e5_dp       ! J/mol

    ! Estabilizadores
    real(dp), parameter :: F_MAX_FE     = 0.005_dp ! frac. de m_liq abajo/paso
    real(dp), parameter :: DT_MAX_SLAG  = 50.0_dp  ! K/paso por reacción

contains

    subroutine compute_slag_chemistry(slag, liq, gas, sh, m, cfg)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer  :: i, j, k
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: o2_rem, r_feo, dm_feo, dm_fe, dm_o2
        real(dp) :: vol, vol_b, q_rx, q_lim, e_fe, c0
        real(dp) :: r_red, dm_red, dm_c, dm_co
        real(dp) :: b2, x_feo, j_co, h_foam, rho_co, dm_co_cell

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        c0 = liquid_datum_offset(cfg)

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%m_sl(i,j,k) <= SMALL_SL) cycle
                    vol = m%vol(i,j,k)
                    dm_co_cell = 0.0_dp

                    !--------------------------------------------------------
                    ! E2.3: oxidación Fe + 1/2 O2 -> FeO (baño abajo)
                    !--------------------------------------------------------
                    if (k > kstart - 1 .and. k > 1) then
                    if (m%cell_type(i,j,k-1) /= 0 .and. &
                        liq%alpha(i,j,k-1) > SMALL_SL) then
                        vol_b = m%vol(i,j,k-1)
                        ! O2 remanente del paso en la celda de escoria
                        o2_rem = max(0.0_dp, gas%alpha(i,j,k) * &
                            gas%rho(i,j,k) * sh%Y_O2(i,j,k) / cfg%dt &
                            + sh%S_O2_src(i,j,k))
                        r_feo = cfg%slag_eta_feo * o2_rem * &
                                (MW_FEO / (0.5_dp * MW_O2_S))
                        dm_feo = r_feo * vol * cfg%dt
                        ! cap por Fe extraíble del baño de abajo
                        dm_fe = dm_feo * MW_FE / MW_FEO
                        dm_fe = min(dm_fe, F_MAX_FE * liq%alpha(i,j,k-1) * &
                                    liq%rho(i,j,k-1) * vol_b)
                        dm_feo = dm_fe * MW_FEO / MW_FE
                        ! cap térmico: recorta la REACCIÓN completa
                        q_rx = dm_feo * (-DH_FEO_OX) / MW_FEO
                        q_lim = slag%m_sl(i,j,k) * cfg%cp_slag * DT_MAX_SLAG
                        if (q_rx > q_lim .and. q_rx > SMALL) then
                            dm_feo = dm_feo * q_lim / q_rx
                            dm_fe  = dm_feo * MW_FE / MW_FEO
                            q_rx   = q_lim
                        end if

                        if (dm_feo > SMALL) then
                            dm_o2 = dm_feo * (0.5_dp * MW_O2_S) / MW_FEO
                            ! Fe sale del baño (pérdida de rendimiento)
                            e_fe = dm_fe * (liq%cp(i,j,k-1) * &
                                   liq%T(i,j,k-1) + c0)
                            liq%alpha(i,j,k-1) = max(0.0_dp, &
                                liq%alpha(i,j,k-1) - dm_fe / &
                                (liq%rho(i,j,k-1) * vol_b))
                            ! FeO a la escoria; entalpía del Fe VIAJA + exo
                            slag%m_X(i,j,k,SL_FEO) = &
                                slag%m_X(i,j,k,SL_FEO) + dm_feo
                            slag%m_sl(i,j,k) = slag%m_sl(i,j,k) + dm_feo
                            slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + e_fe + q_rx
                            ! O2 consumido: sumidero adicional de especies
                            sh%S_O2_src(i,j,k) = sh%S_O2_src(i,j,k) - &
                                dm_o2 / (vol * cfg%dt)
                            call audit_add(AUD_FE_YIELD, dm_fe)
                            call audit_add(AUD_SLAG_OX_E, q_rx)
                        end if
                    end if
                    end if

                    !--------------------------------------------------------
                    ! E2.4: reducción FeO + C -> Fe + CO (dentro de la capa)
                    !--------------------------------------------------------
                    if (slag%m_X(i,j,k,SL_C) > SMALL .and. &
                        slag%m_X(i,j,k,SL_FEO) > SMALL .and. &
                        slag%T_sl(i,j,k) > 800.0_dp) then
                        r_red = K_RED * exp(-E_RED / (R_GAS * &
                                slag%T_sl(i,j,k))) * slag%m_X(i,j,k,SL_FEO)
                        dm_red = r_red * cfg%dt                       ! kg FeO
                        dm_red = min(dm_red, slag%m_X(i,j,k,SL_FEO))
                        dm_red = min(dm_red, slag%m_X(i,j,k,SL_C) * &
                                     MW_FEO / MW_C_S)
                        ! cap térmico (endo: enfría la escoria)
                        q_rx = dm_red * DH_FEO_RED / MW_FEO
                        q_lim = slag%m_sl(i,j,k) * cfg%cp_slag * DT_MAX_SLAG
                        if (q_rx > q_lim .and. q_rx > SMALL) then
                            dm_red = dm_red * q_lim / q_rx
                            q_rx   = q_lim
                        end if
                        if (dm_red > SMALL) then
                            dm_c  = dm_red * MW_C_S / MW_FEO
                            dm_fe = dm_red * MW_FE / MW_FEO
                            dm_co = dm_red * MW_CO_S / MW_FEO
                            slag%m_X(i,j,k,SL_FEO) = &
                                slag%m_X(i,j,k,SL_FEO) - dm_red
                            slag%m_X(i,j,k,SL_C) = &
                                slag%m_X(i,j,k,SL_C) - dm_c
                            slag%m_sl(i,j,k) = slag%m_sl(i,j,k) &
                                               - dm_red - dm_c
                            ! Fe vuelve al baño de abajo (si existe; si no,
                            ! a la propia celda si tiene líquido)
                            e_fe = dm_fe * (cfg%cp_l * slag%T_sl(i,j,k) + c0)
                            if (k > 1) then
                                if (m%cell_type(i,j,k-1) /= 0) then
                                    liq%alpha(i,j,k-1) = liq%alpha(i,j,k-1) &
                                        + dm_fe / (liq%rho(i,j,k-1) * &
                                          m%vol(i,j,k-1))
                                end if
                            end if
                            slag%E_sl(i,j,k) = slag%E_sl(i,j,k) - e_fe - q_rx
                            ! CO al gas (fuente de especies) y a la espuma
                            sh%S_CO_src(i,j,k) = sh%S_CO_src(i,j,k) + &
                                dm_co / (vol * cfg%dt)
                            dm_co_cell = dm_co
                            call audit_add(AUD_FE_RETURN, dm_fe)
                            call audit_add(AUD_SLAG_RED_E, q_rx)
                        end if
                    end if

                    ! T de la escoria consistente tras las reacciones
                    if (slag%m_sl(i,j,k) > SMALL_SL) then
                        slag%T_sl(i,j,k) = max(300.0_dp, &
                            slag%E_sl(i,j,k) / (slag%m_sl(i,j,k) * &
                            cfg%cp_slag))
                    end if

                    !--------------------------------------------------------
                    ! E2.5: espuma local (atributo óptico): H = xi * j_CO
                    !--------------------------------------------------------
                    if (slag%m_sl(i,j,k) > SMALL_SL) then
                        b2 = slag%m_X(i,j,k,SL_CAO) / &
                             max(slag%m_X(i,j,k,SL_SIO2), SMALL)
                        x_feo = slag%m_X(i,j,k,SL_FEO) / slag%m_sl(i,j,k)
                        ! dm_co de la reducción de ESTA celda este paso
                        ! (0 si la rama no corrió)
                        rho_co = 101325.0_dp * MW_CO_S / &
                                 (R_GAS * max(slag%T_sl(i,j,k), 300.0_dp))
                        j_co = dm_co_cell / (cfg%dt * rho_co * &
                               max(m%Az(i,j,k), SMALL))
                        h_foam = xi_pretorius(b2, x_feo, &
                                 slag%T_sl(i,j,k)) * j_co
                        slag%alpha_foam(i,j,k) = min(1.0_dp, &
                            h_foam / max(m%dz(k), SMALL))
                    else
                        slag%alpha_foam(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do

    end subroutine compute_slag_chemistry

end module mod_slag_chemistry
