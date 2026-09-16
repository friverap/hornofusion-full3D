!===============================================================================
! mod_melting_3d.f90 - Melting/re-solidification model (Eqs 9-10 of paper)
!
! C1.8 (hallazgo 3.3): entalpía específica del sólido e_s(T) ÚNICA, usada por
! todos los módulos que convierten E<->T (fusión, interfase, colapso, arco,
! carga). Antes cada módulo usaba un cp distinto (cp_s vs cp_eff), lo que
! desplomaba T_s de 1815 a ~1036 K tras fundir y disparaba re-solidificación
! espuria que destruía el líquido recién creado.
!
!   e_s(T) = cp_s*T                          T <= T_sol
!          = cp_s*T_sol + cp_m*(T - T_sol)   T_sol < T <= T_liq
!          = e_lb + cp_l*(T - T_liq)         T > T_liq
!   cp_m = cp_s + h_fusion/(T_liq - T_sol)   (Eq. 10: el latente vive en la
!   zona mushy);  e_lb = e_s(T_liq) = cp_s*T_liq + h_fusion.
!
! Entalpía del líquido en el MISMO dato: e_l(T) = cp_l*T + C0 con
! C0 = (cp_s - cp_l)*T_liq + h_fusion, de modo que e_l(T) = e_s(T) para
! T >= T_liq: la transferencia de masa fundida es EXACTAMENTE conservativa.
!
! Fusión: el fundido sale a T_s llevando su entalpía completa e_s(T_s); el
! sólido restante conserva su temperatura. La ecuación de energía del
! líquido recibe la masa a T_in = T_s (término de fuente de masa en
! solve_energy_3d). Re-solidificación: el congelado entra al sólido a
! e_s(T_solidus); el excedente e_l(T_l) - e_s(T_sol) (latente liberado)
! calienta al líquido — sin él, la congelación se retroalimentaba.
!===============================================================================
module mod_melting_3d
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_audit, only: audit_add, AUD_MELT_MASS, AUD_RESOLID_MASS, &
                         AUD_MELT_E_SOLID, AUD_RESID_MASS, AUD_RESID_E
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Entalpía específica del sólido [J/kg] — función ÚNICA E<->T
    !---------------------------------------------------------------------------
    pure function solid_enthalpy(T, cfg) result(e)
        real(dp), intent(in)       :: T
        type(config_t), intent(in) :: cfg
        real(dp) :: e, cp_m

        cp_m = cfg%cp_s + cfg%h_fusion / (cfg%T_liquidus - cfg%T_solidus)
        if (T <= cfg%T_solidus) then
            e = cfg%cp_s * T
        else if (T <= cfg%T_liquidus) then
            e = cfg%cp_s * cfg%T_solidus + cp_m * (T - cfg%T_solidus)
        else
            e = cfg%cp_s * cfg%T_liquidus + cfg%h_fusion &
                + cfg%cp_l * (T - cfg%T_liquidus)
        end if
    end function solid_enthalpy

    !---------------------------------------------------------------------------
    ! Inversa: temperatura desde entalpía específica [J/kg]
    !---------------------------------------------------------------------------
    pure function solid_T_from_enthalpy(e, cfg) result(T)
        real(dp), intent(in)       :: e
        type(config_t), intent(in) :: cfg
        real(dp) :: T, cp_m, e_sol, e_lb

        cp_m  = cfg%cp_s + cfg%h_fusion / (cfg%T_liquidus - cfg%T_solidus)
        e_sol = cfg%cp_s * cfg%T_solidus
        e_lb  = cfg%cp_s * cfg%T_liquidus + cfg%h_fusion
        if (e <= e_sol) then
            T = e / max(cfg%cp_s, SMALL)
        else if (e <= e_lb) then
            T = cfg%T_solidus + (e - e_sol) / cp_m
        else
            T = cfg%T_liquidus + (e - e_lb) / cfg%cp_l
        end if
    end function solid_T_from_enthalpy

    !---------------------------------------------------------------------------
    ! Constante de dato entre reservorios: e_l(T) = cp_l*T + C0 [J/kg]
    !---------------------------------------------------------------------------
    pure function liquid_datum_offset(cfg) result(C0)
        type(config_t), intent(in) :: cfg
        real(dp) :: C0
        C0 = (cfg%cp_s - cfg%cp_l) * cfg%T_liquidus + cfg%h_fusion
    end function liquid_datum_offset

    !---------------------------------------------------------------------------
    ! Masa residual del solido en una celda [kg]: por debajo, la celda se
    ! cierra (ver ALPHA_SOLID_RESID en mod_constants).
    !---------------------------------------------------------------------------
    pure function solid_residual_mass(vol, cfg) result(m_min)
        real(dp), intent(in)       :: vol
        type(config_t), intent(in) :: cfg
        real(dp) :: m_min
        m_min = cfg%rho_steel * vol * ALPHA_SOLID_RESID
    end function solid_residual_mass

    !---------------------------------------------------------------------------
    ! Temperatura de ENTRADA al liquido que transporta exactamente la
    ! entalpia especifica e del solido: e_l(T_in) = cp_l*T_in + C0 = e.
    ! Para e >= e_s(T_liq) coincide con solid_T_from_enthalpy(e); por debajo
    ! (remanente frio) es menor: el liquido paga el latente que al
    ! remanente le faltaba. Es la unica T_src que hace conservativo el
    ! termino mdot*cp_l*T_src de solve_energy_3d para cualquier e.
    !---------------------------------------------------------------------------
    pure function liquid_entry_T(e, cfg) result(T_in)
        real(dp), intent(in)       :: e
        type(config_t), intent(in) :: cfg
        real(dp) :: T_in
        T_in = (e - liquid_datum_offset(cfg)) / cfg%cp_l
    end function liquid_entry_T

    !---------------------------------------------------------------------------
    ! Fusion, re-solidificacion y CIERRE del solido residual.
    !
    ! Cierre de fase evanescente (sep-2026, causa raiz del NaN de B1): tras
    ! fundir, una celda con 0 < m_s <= m_min = rho_s*V*ALPHA_SOLID_RESID
    ! entrega TODA su masa y entalpia al liquido por el mismo camino que el
    ! fundido (mdot, T_src) y queda exactamente vacia (m_s=E_s=m_C=0,
    ! alpha_s=0). Conservacion exacta por construccion: el liquido recibe
    ! dm*(e - C0) por la fuente de masa y dm*C0 por el inventario. El
    ! cierre NO se aplica en el paso en que la celda re-solidifica (mdot<0):
    ! el solver de energia contabiliza el latente liberado con el signo de
    ! mdot y mezclar signos en la misma celda lo perderia; el remanente
    ! congelado se cierra al paso siguiente si no siguio creciendo.
    ! Celdas vacias con liquido: T_s esclavizada a T_l (diagnostico; la
    ! fase residual no tiene temperatura propia — Herard & Hurisse 2014).
    !---------------------------------------------------------------------------
    subroutine compute_melting(sol, liq, m, cfg, dt)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: liq
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: dt

        integer :: i, j, k
        real(dp) :: T_s, T_l, dm, e_spec, m_min

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle

                    sol%mdot(i,j,k) = 0.0_dp
                    T_l = liq%T(i,j,k)
                    m_min = solid_residual_mass(m%vol(i,j,k), cfg)

                    if (sol%m_s(i,j,k) > SMALL) then
                        e_spec = sol%E_s(i,j,k) / sol%m_s(i,j,k)
                        T_s = solid_T_from_enthalpy(e_spec, cfg)
                        sol%T_s(i,j,k) = T_s
                    else
                        e_spec = 0.0_dp
                        T_s = sol%T_s(i,j,k)
                        ! Celda sin solido: T_s esclavizada al portador
                        if (liq%alpha(i,j,k) > ALPHA_CUTOFF) then
                            sol%T_s(i,j,k) = T_l
                            T_s = T_l
                        end if
                    end if

                    ! Melting: solid above liquidus converts to liquid.
                    ! Tasa fenomenológica (como antes): proporcional al
                    ! sobrecalentamiento sobre el liquidus.
                    if (sol%alpha_s(i,j,k) > ALPHA_CUTOFF .and. &
                        sol%m_s(i,j,k) > SMALL .and. &
                        T_s >= cfg%T_liquidus) then

                        dm = sol%m_s(i,j,k) * cfg%cp_l * (T_s - cfg%T_liquidus) / &
                             (cfg%h_fusion + cfg%cp_l * (cfg%T_liquidus - cfg%T_solidus))
                        dm = max(0.0_dp, min(dm, sol%m_s(i,j,k)))
                        sol%mdot(i,j,k) = dm / dt

                        ! El fundido sale a T_s llevando e_s(T_s) por kg: el
                        ! sólido restante conserva su temperatura y el líquido
                        ! recibe la masa a T_in = T_s (solve_energy_3d).
                        ! Conservación EXACTA: e_l(T_s) = e_s(T_s) para T>=T_liq.
                        ! El carbono del inventario acompaña al fundido
                        ! proporcionalmente (C3.3; se disuelve en el baño y
                        ! sale del inventario oxidable de superficie)
                        sol%m_C(i,j,k) = sol%m_C(i,j,k) * &
                            max(0.0_dp, 1.0_dp - dm / sol%m_s(i,j,k))
                        sol%m_s(i,j,k) = sol%m_s(i,j,k) - dm
                        sol%E_s(i,j,k) = sol%E_s(i,j,k) - dm * e_spec
                        call audit_add(AUD_MELT_MASS, dm)
                        call audit_add(AUD_MELT_E_SOLID, dm * e_spec)

                        if (m%vol(i,j,k) > SMALL) then
                            sol%alpha_s(i,j,k) = sol%m_s(i,j,k) / &
                                                  (cfg%rho_steel * m%vol(i,j,k))
                        end if
                        sol%alpha_s(i,j,k) = max(0.0_dp, min(1.0_dp, sol%alpha_s(i,j,k)))

                        if (sol%m_s(i,j,k) > SMALL) then
                            sol%T_s(i,j,k) = solid_T_from_enthalpy( &
                                sol%E_s(i,j,k) / sol%m_s(i,j,k), cfg)
                        end if

                    ! Re-solidification: liquid below solidus deposits mass to solid
                    else if (liq%alpha(i,j,k) > ALPHA_CUTOFF .and. T_l < cfg%T_solidus) then
                        dm = liq%alpha(i,j,k) * liq%rho(i,j,k) * m%vol(i,j,k) * &
                             (cfg%T_solidus - T_l) * cfg%cp_l / cfg%h_fusion
                        dm = max(dm, 0.0_dp) * RESOLID_LIMITER

                        sol%mdot(i,j,k) = -dm / dt
                        ! El congelado entra al sólido con
                        !   e_entry = min(e_s(T_solidus), e_l(T_l))
                        ! y el latente liberado e_l(T_l) - e_entry >= 0
                        ! calienta al líquido (término de masa de
                        ! solve_energy_3d, mismo e_entry). El min garantiza
                        ! fuente NO NEGATIVA: entrar siempre a T_solidus
                        ! producía fuentes negativas para T_l < 1334 K y
                        ! empujaba T_liquid bajo cero.
                        sol%m_s(i,j,k) = sol%m_s(i,j,k) + dm
                        sol%E_s(i,j,k) = sol%E_s(i,j,k) + dm * &
                            min(cfg%cp_s * cfg%T_solidus, &
                                cfg%cp_l * T_l + liquid_datum_offset(cfg))
                        call audit_add(AUD_RESOLID_MASS, dm)

                        if (m%vol(i,j,k) > SMALL) then
                            sol%alpha_s(i,j,k) = sol%m_s(i,j,k) / &
                                                  (cfg%rho_steel * m%vol(i,j,k))
                        end if
                        sol%alpha_s(i,j,k) = max(0.0_dp, min(1.0_dp, sol%alpha_s(i,j,k)))

                        if (sol%m_s(i,j,k) > SMALL) then
                            sol%T_s(i,j,k) = solid_T_from_enthalpy( &
                                sol%E_s(i,j,k) / sol%m_s(i,j,k), cfg)
                        end if
                    end if

                    ! --- Cierre del solido residual (fase evanescente) ---
                    if (sol%mdot(i,j,k) >= 0.0_dp .and. &
                        sol%m_s(i,j,k) > 0.0_dp .and. &
                        sol%m_s(i,j,k) <= m_min) then
                        dm = sol%m_s(i,j,k)
                        if (dm > SMALL) then
                            e_spec = sol%E_s(i,j,k) / dm
                        else
                            ! masa por debajo de la precision: la entalpia
                            ! que pudiera quedar es no representable como
                            ! mdot*T_src; se contabiliza en el mismo ledger
                            e_spec = 0.0_dp
                        end if
                        ! Toda la masa que sale de la celda en este paso
                        ! (fundido + remanente) comparte e_spec: la fusion
                        ! conserva la entalpia especifica del solido.
                        sol%mdot(i,j,k) = sol%mdot(i,j,k) + dm / dt
                        sol%T_s(i,j,k)  = liquid_entry_T(e_spec, cfg)
                        call audit_add(AUD_MELT_MASS, dm)
                        call audit_add(AUD_MELT_E_SOLID, dm * e_spec)
                        call audit_add(AUD_RESID_MASS, dm)
                        call audit_add(AUD_RESID_E, dm * e_spec)
                        sol%m_s(i,j,k)     = 0.0_dp
                        sol%E_s(i,j,k)     = 0.0_dp
                        sol%m_C(i,j,k)     = 0.0_dp
                        sol%alpha_s(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do

    end subroutine compute_melting

    !---------------------------------------------------------------------------
    ! Effective Cp (Eq. 10) — pendiente de e_s(T); se conserva por
    ! compatibilidad (correlaciones y tests)
    !---------------------------------------------------------------------------
    pure function effective_cp(T, cfg) result(cp_eff)
        real(dp), intent(in) :: T
        type(config_t), intent(in) :: cfg
        real(dp) :: cp_eff

        if (T < cfg%T_solidus) then
            cp_eff = cfg%cp_s
        else if (T <= cfg%T_liquidus) then
            cp_eff = cfg%cp_s + cfg%h_fusion / (cfg%T_liquidus - cfg%T_solidus)
        else
            cp_eff = cfg%cp_l
        end if
    end function effective_cp

end module mod_melting_3d
