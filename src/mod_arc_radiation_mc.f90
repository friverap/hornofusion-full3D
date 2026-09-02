!===============================================================================
! mod_arc_radiation_mc.f90 - Monte Carlo arc radiation model
!
! Distributes the radiative fraction of arc power via random beams
! emitted isotropically from the arc column. Each beam carries a fraction
! of the total radiative power and deposits it in the first solid/liquid
! cell it hits.
!
! Decomposition-invariant implementation:
!   - The RNG is seeded with a FIXED seed (reproducible runs); every rank
!     generates the same beam directions in the same order.
!   - Beams are traced on the GLOBAL geometry (rf_global/zf_global, uniform
!     global theta) using the globally-replicated alpha_s, so the absorption
!     cell of each beam is identical on every rank and in serial.
!   - Only the rank owning the absorption cell deposits the beam power.
!===============================================================================
module mod_arc_radiation_mc
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_audit, only: audit_add, AUD_MC_DEPOSIT
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Reseed determinista POR PASO (C0.3): cada paso es función pura de
    ! (step, campos), no de la historia de draws. Requisito para comparar
    ! snapshots entre corridas/versiones y para la invarianza de
    ! descomposición (misma secuencia en todos los ranks).
    !---------------------------------------------------------------------------
    subroutine reseed_rng(step)
        integer, intent(in) :: step
        integer :: n, i
        integer, allocatable :: seed(:)

        call random_seed(size=n)
        allocate(seed(n))
        do i = 1, n
            seed(i) = 104729 + 37 * i + 7919 * step
        end do
        call random_seed(put=seed)
        deallocate(seed)
    end subroutine reseed_rng

    subroutine distribute_arc_radiation_mc(elec, sol, sh, m, cfg, n_elec, step)
        type(electrode_t), intent(in)   :: elec(:)
        type(solid_t), intent(in)       :: sol
        type(shared_t), intent(inout)   :: sh
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        integer, intent(in)             :: n_elec
        integer, intent(in)             :: step

        integer  :: e, beam
        real(dp) :: P_rad_per_beam
        real(dp) :: x0, y0, z0, dx, dy, dz
        real(dp) :: x, y, z_pos, r_pos, theta_pos
        real(dp) :: phi_rand, cos_theta, sin_theta
        real(dp) :: step_size, total_P_rad
        integer  :: ig, jg, kg, il, jl, kl
        real(dp) :: rnd1, rnd2, rnd3
        integer  :: n_steps
        logical  :: owned
        real(dp), allocatable :: alpha_g(:,:,:)
        integer, parameter :: MAX_TRACE_STEPS = 50000

        if (cfg%n_beams <= 0) return   ! MC apagado (n_beams = 0 en config)

        call reseed_rng(step)

        ! Globally-replicated alpha_s: every rank sees the same scrap surface
        allocate(alpha_g(m%nr_g, m%nth_g, m%nz_g))
        call gather_global_field(sol%alpha_s, alpha_g, m)

        ! Step size from the GLOBAL minimum radial width (identical on all ranks)
        step_size = minval(m%rf_global(1:m%nr_g) - m%rf_global(0:m%nr_g-1)) * 0.5_dp
        if (step_size < 1.0e-6_dp) step_size = 0.01_dp   ! absolute fallback

        do e = 1, n_elec
            ! Parte del presupuesto frac_rad asignada al MC (C1.6a): el
            ! complemento lo deposita distribute_arc_heat directo al sólido
            total_P_rad = elec(e)%arc_power * cfg%frac_rad * MC_RAD_SHARE
            if (total_P_rad < 1.0_dp) cycle

            P_rad_per_beam = total_P_rad / real(cfg%n_beams, dp)

            x0 = cfg%R_pcd * cos(elec(e)%theta_pos)
            y0 = cfg%R_pcd * sin(elec(e)%theta_pos)
            z0 = elec(e)%z_tip

            do beam = 1, cfg%n_beams
                ! Random direction (isotropic) — same sequence on every rank
                call random_number(rnd1)
                call random_number(rnd2)
                call random_number(rnd3)

                phi_rand = TWO_PI * rnd1
                cos_theta = 2.0_dp * rnd2 - 1.0_dp
                sin_theta = sqrt(max(1.0_dp - cos_theta**2, 0.0_dp))

                dx = sin_theta * cos(phi_rand)
                dy = sin_theta * sin(phi_rand)
                dz = cos_theta

                ! Trace beam on the global geometry
                x = x0; y = y0; z_pos = z0
                n_steps = 0

                trace: do
                    n_steps = n_steps + 1
                    if (n_steps > MAX_TRACE_STEPS) exit trace   ! safety guard

                    x = x + dx * step_size
                    y = y + dy * step_size
                    z_pos = z_pos + dz * step_size

                    ! Check bounds - use .not.(<=) to correctly handle NaN
                    r_pos = sqrt(x**2 + y**2)
                    if (.not. (r_pos <= cfg%R_shell)) exit trace
                    if (.not. (z_pos >= 0.0_dp .and. z_pos <= cfg%H_total)) exit trace

                    ! Find GLOBAL cell indices
                    theta_pos = atan2(y, x)
                    if (theta_pos < 0.0_dp) theta_pos = theta_pos + TWO_PI

                    call find_cell_global(r_pos, theta_pos, z_pos, m, ig, jg, kg)
                    if (ig < 1 .or. kg < 1) exit trace
                    if (m%cell_type_global(ig, jg, kg) == 0) exit trace

                    ! Check if beam hits solid or liquid
                    if (alpha_g(ig, jg, kg) > 0.1_dp .or. &
                        z_pos < cfg%H_bowl + 0.5_dp) then
                        ! Deposit energy — only the owner of the cell writes
                        call global_to_local(m, ig, jg, kg, il, jl, kl, owned)
                        if (owned) then
                            sh%S_arc(il, jl, kl) = sh%S_arc(il, jl, kl) + &
                                P_rad_per_beam / (m%vol_global(ig, jg, kg) + SMALL)
                            ! Auditoría: energía inyectada por el MC este paso
                            call audit_add(AUD_MC_DEPOSIT, P_rad_per_beam * cfg%dt)
                        end if
                        exit trace
                    end if
                end do trace
            end do
        end do

        deallocate(alpha_g)

    end subroutine distribute_arc_radiation_mc

    !---------------------------------------------------------------------------
    ! Find GLOBAL cell indices from physical coordinates
    !---------------------------------------------------------------------------
    subroutine find_cell_global(r, theta, z, m, ic, jc, kc)
        real(dp), intent(in)    :: r, theta, z
        type(mesh_t), intent(in) :: m
        integer, intent(out)    :: ic, jc, kc

        integer :: i

        ic = -1; jc = -1; kc = -1

        do i = 1, m%nr_g
            if (r <= m%rf_global(i)) then
                ic = i; exit
            end if
        end do
        if (ic < 0) return

        jc = int(theta / (TWO_PI / real(m%nth_g, dp))) + 1
        jc = max(1, min(m%nth_g, jc))

        do i = 1, m%nz_g
            if (z <= m%zf_global(i)) then
                kc = i; exit
            end if
        end do
    end subroutine find_cell_global

end module mod_arc_radiation_mc
