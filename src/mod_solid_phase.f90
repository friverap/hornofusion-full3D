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
    implicit none

contains

    subroutine update_solid_phase(sol, liq, gas, m, cfg, dt)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: liq, gas
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: dt

        ! Interphase heat transfer (heats solid, cools fluids)
        call compute_interphase_heat(liq, gas, sol, m, cfg)

        ! Melting / re-solidification
        call compute_melting(sol, liq, m, cfg, dt)

        ! Scrap collapse
        call apply_scrap_collapse(sol, m, cfg)

    end subroutine update_solid_phase

end module mod_solid_phase
