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

    subroutine update_solid_phase(sol, liq, gas, slag, m, cfg, dt)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: liq, gas
        type(slag_t),  intent(in)    :: slag
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: dt

        ! Interphase heat transfer (heats solid, cools fluids)
        call compute_interphase_heat(liq, gas, sol, m, cfg)

        ! Melting / re-solidification
        call compute_melting(sol, liq, m, cfg, dt)

        ! Scrap collapse
        call apply_scrap_collapse(sol, m, cfg)

        ! Restricción de volumen (C1.9, hallazgo 3.22b): fusión y colapso
        ! cambian alpha_s sin actualizar el gas -> Sum(alpha) quedaba en 0.5
        ! en celdas vaciadas. El gas absorbe/cede el volumen sobrante.
        call enforce_volume_constraint(liq, gas, sol, slag, m)

    end subroutine update_solid_phase

    !---------------------------------------------------------------------------
    subroutine enforce_volume_constraint(liq, gas, sol, slag, m)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(slag_t),  intent(in)    :: slag
        type(mesh_t), intent(in)     :: m

        integer :: i, j, k

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    gas%alpha(i,j,k) = max(0.0_dp, 1.0_dp &
                        - sol%alpha_s(i,j,k) - liq%alpha(i,j,k) &
                        - slag%alpha_sl(i,j,k))
                end do
            end do
        end do
    end subroutine enforce_volume_constraint

end module mod_solid_phase
