!===============================================================================
! mod_solid_phase.f90 - Dual-cell solid phase model (Eqs 7-8)
!
! Orchestrates solid mass balance, energy balance, melting, and collapse.
!   Mass balance (Eq. 7): dm_s/dt = -m_dot_s,mt
!   Energy balance (Eq. 8): dE_s/dt = Q_s_bar
!===============================================================================
module mod_solid_phase
    use mod_constants
    use mod_types_3d
    use mod_melting_3d
    use mod_scrap_collapse
    use mod_interphase_ht
    use mod_workspace, only: ensure_workspace, ws_Tsrc
    use mod_audit, only: audit_add, AUD_GAS_VOLFIX, AUD_ALPHA_CLIP_MASS
    implicit none

contains

    ! Fusión + colapso, ANTES del lazo SIMPLE (cierre 2026, punto 2): la
    ! ecuación de alpha_l y la fuente de masa de la energía usan el mdot de
    ! ESTE paso (antes el líquido recibía el fundido con un paso de
    ! retraso: dm del último paso —el mayor, con fusión en rampa— nunca
    ! estaba en el inventario del snapshot; ratio medido 0.857).
    subroutine update_solid_premelt(sol, liq, gas, slag, m, cfg, dt, sh)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: liq, gas
        type(slag_t),  intent(in)    :: slag
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: dt
        ! (auditoria 4, M4-4) el gas que crea la fusion/colapso tampoco trae
        ! especies (dilucion de Y en enforce_volume_constraint)
        type(shared_t), intent(inout), optional :: sh

        ! T de entrada del fundido la fija la fusion, ANTES del colapso
        ! (auditoria A3: el colapso mezcla en sol%T_s la entalpia de la
        ! chatarra que cae; M9: con la regla de la palanca ya no es T_s)
        call ensure_workspace(m)
        call compute_melting(sol, liq, m, cfg, dt, ws_Tsrc)
        call apply_scrap_collapse(sol, liq, slag, m, cfg)

        ! Restricción de volumen (C1.9, hallazgo 3.22b): fusión y colapso
        ! cambian alpha_s sin actualizar el gas -> Sum(alpha) quedaba en 0.5
        ! en celdas vaciadas. El gas absorbe/cede el volumen sobrante.
        ! (M4-4) con sh: el gas creado no trae especies
        call enforce_volume_constraint(liq, gas, sol, slag, m, sh)

    end subroutine update_solid_premelt

    ! Transferencia interfase, DESPUÉS de los solves de energía: modifica
    ! liq%T/gas%T directamente; correrla antes duplicaría el calor (el
    ! sólido lo recibe pero la energía re-resuelve T desde liq_old sin
    ! saber que el fluido lo cedió — medido: fusión 10x espuria).
    subroutine update_solid_postenergy(sol, liq, gas, m, cfg)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: liq, gas
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        call compute_interphase_heat(liq, gas, sol, m, cfg)

    end subroutine update_solid_postenergy

    !---------------------------------------------------------------------------
    subroutine enforce_volume_constraint(liq, gas, sol, slag, m, sh)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(slag_t),  intent(in)    :: slag
        type(mesh_t), intent(in)     :: m
        ! Especies (auditoria 3, A3-7): el gas que CREA el complemento no
        ! trae O2/CO/CO2 (la masa de cada especie se conserva: Y se diluye
        ! por alpha_old/alpha_new, como la dilucion M14); si no, el relleno
        ! del poro que deja el carbono oxidado creaba O y C de la nada
        ! (check_chem 9e-7 / 1.4e-7 con rtol 1e-7). Al destruir gas la especie
        ! se va con el (queda en m_gas_volfix).
        type(shared_t), intent(inout), optional :: sh

        integer :: i, j, k
        real(dp) :: a_new, dmg, fdil

        dmg = 0.0_dp
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    a_new = max(0.0_dp, 1.0_dp &
                        - sol%alpha_s(i,j,k) - liq%alpha(i,j,k) &
                        - slag%alpha_sl(i,j,k))
                    ! masa de gas creada/destruida (auditoria, bajos: antes
                    ! sin columna; la masa del gas la fija la EOS)
                    dmg = dmg + (a_new - gas%alpha(i,j,k)) * gas%rho(i,j,k) * m%vol(i,j,k)
                    if (present(sh) .and. a_new > gas%alpha(i,j,k) .and. a_new > 0.0_dp) then
                        fdil = max(gas%alpha(i,j,k), 0.0_dp) / a_new
                        sh%Y_O2(i,j,k)  = sh%Y_O2(i,j,k)  * fdil
                        sh%Y_CO(i,j,k)  = sh%Y_CO(i,j,k)  * fdil
                        sh%Y_CO2(i,j,k) = sh%Y_CO2(i,j,k) * fdil
                    end if
                    gas%alpha(i,j,k) = a_new
                end do
            end do
        end do
        call audit_add(AUD_GAS_VOLFIX, dmg)
    end subroutine enforce_volume_constraint

    !---------------------------------------------------------------------------
    ! Fuente/sumidero de MASA del liquido cuando no corre el transporte de
    ! alpha de dos fluidos (ramas de una sola fase y solo energia; auditoria 2,
    ! N-C4). En el modelo de dos fluidos el mdot de fusion/congelacion lo aplica
    ! solve_volume_fraction; sin el, el solido ganaba la masa congelada sin que
    ! el liquido la perdiera (bath_freeze sin flujo: +18 t de acero y +1.4e10 J
    ! por paso) y el fundido no entraba al liquido. alpha_l^{n+1} = alpha_l^n +
    ! mdot dt/(rho V); el gas es el complemento (restriccion de volumen). La
    ! congelacion esta acotada por RESOLID_LIMITER, asi que alpha_l >= 0.
    !---------------------------------------------------------------------------
    subroutine apply_mass_source_noflow(liq, gas, sol, slag, m, dt, sh)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(slag_t),  intent(in)    :: slag
        type(mesh_t), intent(in)     :: m
        real(dp), intent(in)         :: dt
        type(shared_t), intent(inout), optional :: sh
        integer :: i, j, k
        real(dp) :: a_new
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (sol%mdot(i,j,k) == 0.0_dp) cycle
                    a_new = liq%alpha(i,j,k) + sol%mdot(i,j,k) * dt / (liq%rho(i,j,k) * m%vol(i,j,k))
                    ! (auditoria 3, B3-10) lo que el max(0, .) recorta queda en
                    ! el clip auditado (nunca un recorte silencioso)
                    if (a_new < 0.0_dp) call audit_add(AUD_ALPHA_CLIP_MASS, -a_new * liq%rho(i,j,k) * m%vol(i,j,k))
                    liq%alpha(i,j,k) = max(0.0_dp, a_new)
                end do
            end do
        end do
        call enforce_volume_constraint(liq, gas, sol, slag, m, sh)
    end subroutine apply_mass_source_noflow

end module mod_solid_phase
