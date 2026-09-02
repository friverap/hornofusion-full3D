!===============================================================================
! mod_multiphase.f90 - Eulerian-Eulerian multiphase coupling
!
! Orchestrates:
!   1. Momentum for liquid phase
!   2. Momentum for gas phase
!   3. Shared pressure correction
!   4. Volume fraction update
!   5. Energy for both phases
!
! MPI-aware: Coordinates halo exchanges between physics modules
!===============================================================================
module mod_multiphase
    use mod_constants
    use mod_types_3d
    use mod_momentum_3d
    use mod_pressure_3d
    use mod_energy_3d
    use mod_continuity
    use mod_drag_ergun
    use mod_properties_3d
    use mod_fields_3d
    implicit none

contains

    subroutine multiphase_iteration(liq, gas, liq_old, gas_old, sol, slag, &
                                     sh, m, cfg, drag_coef, conv)
        type(phase_t), intent(inout) :: liq, gas, liq_old, gas_old
        type(solid_t), intent(inout) :: sol
        type(slag_t),  intent(in)    :: slag
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(inout)      :: drag_coef(-1:,-1:,-1:)
        type(convergence_t), intent(inout) :: conv

        real(dp) :: res_ur_l, res_uth_l, res_uz_l
        real(dp) :: res_ur_g, res_uth_g, res_uz_g
        real(dp) :: res_cont, res_energy_l, res_energy_g

        ! Copias del ITERADO externo anterior para la sub-relajación (C2.1).
        ! Workspace persistente (save): se realoca solo si cambia el tamaño.
        real(dp), allocatable, save :: p_lur(:,:,:), p_lth(:,:,:), p_luz(:,:,:)
        real(dp), allocatable, save :: p_gur(:,:,:), p_gth(:,:,:), p_guz(:,:,:)
        real(dp), allocatable, save :: p_lT(:,:,:), p_gT(:,:,:)

        if (.not. allocated(p_lur)) then
            allocate(p_lur, mold=liq%ur); allocate(p_lth, mold=liq%uth)
            allocate(p_luz, mold=liq%uz); allocate(p_lT, mold=liq%T)
            allocate(p_gur, mold=gas%ur); allocate(p_gth, mold=gas%uth)
            allocate(p_guz, mold=gas%uz); allocate(p_gT, mold=gas%T)
        end if
        p_lur = liq%ur; p_lth = liq%uth; p_luz = liq%uz; p_lT = liq%T
        p_gur = gas%ur; p_gth = gas%uth; p_guz = gas%uz; p_gT = gas%T

        ! Exchange halos before starting iteration
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)
        call solid_exchange_halos(sol, m)
        call shared_exchange_halos(sh, m)

        ! Compute Ergun drag coefficient from solid (Picard con |v| del líquido)
        call compute_ergun_drag(liq, sol, m, cfg, drag_coef)

        ! Liquid momentum
        call solve_momentum_3d(liq, liq_old, sh, m, cfg, liq%alpha, &
                               drag_coef, .false., res_ur_l, res_uth_l, res_uz_l)
        call relax_field(liq%ur,  p_lur, cfg%alpha_u, m)
        call relax_field(liq%uth, p_lth, cfg%alpha_u, m)
        call relax_field(liq%uz,  p_luz, cfg%alpha_u, m)

        ! Exchange halos after momentum
        call phase_exchange_halos(liq, m)

        ! Gas momentum (same drag coefficient: computed with liquid
        ! properties; a phase-specific coefficient would be more correct.
        ! Nota: la versión explícita anterior aplicaba al gas una FUERZA
        ! proporcional a la velocidad del LÍQUIDO; implícito, el coeficiente
        ! actúa sobre la velocidad propia de cada fase.)
        call solve_momentum_3d(gas, gas_old, sh, m, cfg, gas%alpha, &
                               drag_coef, .true., res_ur_g, res_uth_g, res_uz_g)
        call relax_field(gas%ur,  p_gur, cfg%alpha_u, m)
        call relax_field(gas%uth, p_gth, cfg%alpha_u, m)
        call relax_field(gas%uz,  p_guz, cfg%alpha_u, m)

        ! Exchange halos after momentum
        call phase_exchange_halos(gas, m)

        ! Pressure correction (uses liquid as primary phase)
        call solve_pressure_correction(liq, sh, m, cfg, liq%alpha, res_cont)
        
        ! Exchange halos after pressure
        call shared_exchange_halos(sh, m)
        call phase_exchange_halos(liq, m)

        ! Volume fraction update
        if (cfg%solve_multiphase) then
            call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, &
                                       liq_old%alpha, m, cfg)
            ! Exchange after volume fraction update
            call phase_exchange_halos(liq, m)
            call phase_exchange_halos(gas, m)
        end if

        ! Energy
        if (cfg%solve_energy) then
            call solve_energy_3d(liq, liq_old%T, sh, m, cfg, liq%alpha, &
                                 gas%alpha, sol%mdot, sol%T_s, &
                                 .false., res_energy_l)
            call relax_field(liq%T, p_lT, cfg%alpha_T, m)
            call phase_exchange_halos(liq, m)

            call solve_energy_3d(gas, gas_old%T, sh, m, cfg, gas%alpha, &
                                 liq%alpha, sol%mdot, sol%T_s, &
                                 .true., res_energy_g)
            call relax_field(gas%T, p_gT, cfg%alpha_T, m)
            call phase_exchange_halos(gas, m)
        else
            res_energy_l = 0.0_dp
            res_energy_g = 0.0_dp
        end if

        ! Update properties
        call update_properties(liq, gas, sh, m, cfg)

        ! Record convergence
        conv%res_ur   = max(res_ur_l, res_ur_g)
        conv%res_uth  = max(res_uth_l, res_uth_g)
        conv%res_uz   = max(res_uz_l, res_uz_g)
        conv%res_cont = res_cont
        conv%res_energy = max(res_energy_l, res_energy_g)

    end subroutine multiphase_iteration

end module mod_multiphase
