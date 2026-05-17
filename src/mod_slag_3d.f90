!===============================================================================
! mod_slag_3d.f90 - Slag layer (capa de escoria) pseudo-phase for EAF simulator
!
! Slag modeled as a tracked pseudo-phase (like solid_t) — NOT a full Eulerian
! N-S phase.  Physics:
!   1. Buoyancy:  slag rises above co-located liquid (local k-sweep, 3 passes)
!   2. Arc heat interception: slag absorbs alpha_sl fraction of S_arc
!   3. Heat exchange: slag <-> liquid (below) and slag <-> gas (same cell)
!   4. Volume constraint: gas fraction reduced where slag occupies cells
!===============================================================================
module mod_slag_3d
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology, only: mpi_allreduce_max, mpi_allreduce_sum
    implicit none

    real(dp), parameter :: SMALL_SL = 1.0e-6_dp

contains

    !---------------------------------------------------------------------------
    ! Place initial slag layer just above the scrap surface
    !---------------------------------------------------------------------------
    subroutine slag_initialize(slag, sol, gas, m, cfg)
        type(slag_t),  intent(inout) :: slag
        type(solid_t), intent(in)    :: sol
        type(phase_t), intent(inout) :: gas
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg

        integer  :: i, j, k, k_global, k_local
        integer  :: istart, iend, jstart, jend, kstart, kend, nz_global
        integer  :: k_top_local, k_top_global
        real(dp) :: k_top_real, k_top_real_global
        real(dp) :: avail_vol, alpha_add, vol_target
        real(dp) :: vol_local, vol_global, scale_fac

        ! Loop bounds
        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
            nz_global = m%topo%nz_global
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
            nz_global = m%nz
        end if

        ! Find local highest k with scrap (expressed as global k index)
        k_top_local = 0
        do k = kend, kstart, -1
            if (any(sol%alpha_s(istart:iend, jstart:jend, k) > 0.01_dp)) then
                if (m%is_parallel) then
                    k_top_local = k + m%topo%kglobal_start - 1
                else
                    k_top_local = k
                end if
                exit
            end if
        end do

        ! Global max k_top across all ranks
        if (m%is_parallel) then
            k_top_real = real(k_top_local, dp)
            call mpi_allreduce_max(k_top_real, k_top_real_global, m%topo)
            k_top_global = nint(k_top_real_global)
        else
            k_top_global = k_top_local
        end if

        ! Fall back to bottom k if no scrap found (pre-charge run)
        if (k_top_global < 1) k_top_global = 0

        vol_target = cfg%m_slag_init / cfg%rho_slag   ! ~1.18 m³

        ! Pass 1: fill cells immediately above scrap (up to 3 k-levels)
        vol_local = 0.0_dp
        do k_global = k_top_global + 1, min(k_top_global + 3, nz_global)
            ! Map global k to local k
            if (m%is_parallel) then
                k_local = k_global - m%topo%kglobal_start + 1
                if (k_local < kstart .or. k_local > kend) cycle
            else
                k_local = k_global
                if (k_local < kstart .or. k_local > kend) cycle
            end if

            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i, j, k_local) /= 1) cycle
                    avail_vol = (1.0_dp - sol%alpha_s(i, j, k_local)) * m%vol(i, j, k_local)
                    if (avail_vol < SMALL_SL) cycle

                    alpha_add = avail_vol / m%vol(i, j, k_local)
                    slag%alpha_sl(i, j, k_local) = alpha_add
                    slag%m_sl(i, j, k_local)     = cfg%rho_slag * avail_vol
                    slag%T_sl(i, j, k_local)     = cfg%T_initial
                    slag%E_sl(i, j, k_local)     = slag%m_sl(i, j, k_local) * cfg%cp_slag * cfg%T_initial
                    gas%alpha(i, j, k_local)     = max(0.0_dp, gas%alpha(i, j, k_local) - alpha_add)
                    vol_local = vol_local + avail_vol
                end do
            end do
        end do

        ! Global total volume placed
        if (m%is_parallel) then
            call mpi_allreduce_sum(vol_local, vol_global, m%topo)
        else
            vol_global = vol_local
        end if

        ! Scale to hit m_slag_init exactly (can only scale down, not up)
        if (vol_global > SMALL_SL) then
            scale_fac = min(1.0_dp, vol_target / vol_global)

            do k_global = k_top_global + 1, min(k_top_global + 3, nz_global)
                if (m%is_parallel) then
                    k_local = k_global - m%topo%kglobal_start + 1
                    if (k_local < kstart .or. k_local > kend) cycle
                else
                    k_local = k_global
                    if (k_local < kstart .or. k_local > kend) cycle
                end if

                do j = jstart, jend
                    do i = istart, iend
                        if (slag%alpha_sl(i, j, k_local) < SMALL_SL) cycle
                        ! Restore gas, then re-remove with scaled fraction
                        gas%alpha(i, j, k_local) = gas%alpha(i, j, k_local) &
                                                    + slag%alpha_sl(i, j, k_local)
                        slag%alpha_sl(i, j, k_local) = slag%alpha_sl(i, j, k_local) * scale_fac
                        slag%m_sl(i, j, k_local)     = cfg%rho_slag * slag%alpha_sl(i, j, k_local) &
                                                        * m%vol(i, j, k_local)
                        slag%E_sl(i, j, k_local)     = slag%m_sl(i, j, k_local) * cfg%cp_slag &
                                                        * cfg%T_initial
                        gas%alpha(i, j, k_local)     = max(0.0_dp, gas%alpha(i, j, k_local) &
                                                            - slag%alpha_sl(i, j, k_local))
                    end do
                end do
            end do
            vol_global = vol_global * scale_fac
        end if

        if (.not. m%is_parallel .or. m%topo%rank == 0) then
            print '(A,ES10.3,A,ES10.3,A)', &
                ' [SLAG] Initialized: V_slag=', vol_global, &
                ' m³  m_slag=', vol_global * cfg%rho_slag, ' kg'
        end if

    end subroutine slag_initialize

    !---------------------------------------------------------------------------
    ! Timestep update: buoyancy settling + energy exchange
    !---------------------------------------------------------------------------
    subroutine update_slag(slag, liq, gas, sh, m, cfg, dt)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(shared_t),intent(inout) :: sh
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        real(dp),      intent(in)    :: dt

        call slag_buoyancy(slag, liq, gas, m, cfg)
        call slag_energy(slag, liq, gas, sh, m, cfg, dt)
    end subroutine update_slag

    !---------------------------------------------------------------------------
    ! Buoyancy: sweep k=kstart..kend-1 upward, float slag above liquid
    !---------------------------------------------------------------------------
    subroutine slag_buoyancy(slag, liq, gas, m, cfg)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend, isweep
        real(dp) :: frac, frac_new, avail_above, frac_ratio

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        ! 3 upward sweeps for stability
        do isweep = 1, 3
            do k = kstart, kend - 1
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k)   == 0) cycle
                        if (m%cell_type(i,j,k+1) == 0) cycle
                        if (slag%alpha_sl(i,j,k) < SMALL_SL) cycle
                        if (liq%alpha(i,j,k)     < SMALL_SL) cycle

                        frac = slag%alpha_sl(i,j,k)

                        ! Available space in cell above: not occupied by liq or slag
                        avail_above = max(0.0_dp, 1.0_dp - liq%alpha(i,j,k+1) &
                                                          - slag%alpha_sl(i,j,k+1))
                        frac_new = min(frac, avail_above)
                        if (frac_new < SMALL_SL) cycle

                        frac_ratio = frac_new / frac

                        ! Transfer mass and energy from k to k+1
                        slag%m_sl(i,j,k+1)     = slag%m_sl(i,j,k+1)  + slag%m_sl(i,j,k)  * frac_ratio
                        slag%E_sl(i,j,k+1)     = slag%E_sl(i,j,k+1)  + slag%E_sl(i,j,k)  * frac_ratio
                        slag%alpha_sl(i,j,k+1) = slag%alpha_sl(i,j,k+1) + frac_new

                        ! Remove from k
                        slag%m_sl(i,j,k)     = slag%m_sl(i,j,k)  * (1.0_dp - frac_ratio)
                        slag%E_sl(i,j,k)     = slag%E_sl(i,j,k)  * (1.0_dp - frac_ratio)
                        slag%alpha_sl(i,j,k) = slag%alpha_sl(i,j,k) - frac_new

                        ! Gas compensates volume
                        gas%alpha(i,j,k)   = min(1.0_dp, gas%alpha(i,j,k)   + frac_new)
                        gas%alpha(i,j,k+1) = max(0.0_dp, gas%alpha(i,j,k+1) - frac_new)

                        ! Clear nearly-empty cell k
                        if (slag%alpha_sl(i,j,k) < SMALL_SL) then
                            slag%alpha_sl(i,j,k) = 0.0_dp
                            slag%m_sl(i,j,k)     = 0.0_dp
                            slag%E_sl(i,j,k)     = 0.0_dp
                            slag%T_sl(i,j,k)     = 0.0_dp
                        end if
                    end do
                end do
            end do
        end do

        ! Update T_sl from E_sl and m_sl after buoyancy movement
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (slag%m_sl(i,j,k) > SMALL_SL) then
                        slag%T_sl(i,j,k) = slag%E_sl(i,j,k) / (slag%m_sl(i,j,k) * cfg%cp_slag)
                        slag%T_sl(i,j,k) = max(300.0_dp, slag%T_sl(i,j,k))
                    end if
                end do
            end do
        end do

    end subroutine slag_buoyancy

    !---------------------------------------------------------------------------
    ! Explicit energy update for slag
    !---------------------------------------------------------------------------
    subroutine slag_energy(slag, liq, gas, sh, m, cfg, dt)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(shared_t),intent(inout) :: sh
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        real(dp),      intent(in)    :: dt

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: dE, Q_sl, Q_lim, dT_liq, dT_gas, vol

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%alpha_sl(i,j,k) < SMALL_SL) cycle
                    if (slag%m_sl(i,j,k)     < SMALL_SL) cycle

                    vol = m%vol(i,j,k)

                    ! 1. Arc heat interception: slag absorbs proportional share of S_arc
                    dE = sh%S_arc(i,j,k) * vol * dt * slag%alpha_sl(i,j,k)
                    slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + dE
                    sh%S_arc(i,j,k)  = sh%S_arc(i,j,k) * (1.0_dp - slag%alpha_sl(i,j,k))

                    ! 2. Slag-liquid HT (liquid in cell below at k-1)
                    !    Guard: k > kstart so k-1 is in this rank's interior (safe to write)
                    if (k > kstart .and. liq%alpha(i,j,k-1) > SMALL_SL) then
                        Q_sl = cfg%h_contact_sl * m%Az(i,j,k-1) &
                               * (liq%T(i,j,k-1) - slag%T_sl(i,j,k))
                        Q_lim = liq%alpha(i,j,k-1) * liq%rho(i,j,k-1) * liq%cp(i,j,k-1) &
                                * m%vol(i,j,k-1) * abs(liq%T(i,j,k-1) - slag%T_sl(i,j,k)) / dt
                        Q_sl = sign(min(abs(Q_sl), Q_lim), Q_sl)

                        slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + Q_sl * dt
                        dT_liq = Q_sl * dt / (liq%alpha(i,j,k-1) * liq%rho(i,j,k-1) &
                                              * liq%cp(i,j,k-1) * m%vol(i,j,k-1))
                        liq%T(i,j,k-1) = liq%T(i,j,k-1) - dT_liq
                    end if

                    ! 3. Slag-gas HT (gas co-located in same cell)
                    if (gas%alpha(i,j,k) > SMALL_SL) then
                        Q_sl = cfg%h_contact_sl * m%Az(i,j,k) &
                               * (gas%T(i,j,k) - slag%T_sl(i,j,k))
                        Q_lim = gas%alpha(i,j,k) * gas%rho(i,j,k) * gas%cp(i,j,k) &
                                * vol * abs(gas%T(i,j,k) - slag%T_sl(i,j,k)) / dt
                        Q_sl = sign(min(abs(Q_sl), Q_lim), Q_sl)

                        slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + Q_sl * dt
                        dT_gas = Q_sl * dt / (gas%alpha(i,j,k) * gas%rho(i,j,k) &
                                              * gas%cp(i,j,k) * vol)
                        gas%T(i,j,k) = gas%T(i,j,k) - dT_gas
                    end if

                    ! 4. Update slag temperature
                    if (slag%m_sl(i,j,k) > SMALL_SL) then
                        slag%T_sl(i,j,k) = slag%E_sl(i,j,k) / (slag%m_sl(i,j,k) * cfg%cp_slag)
                    end if
                    slag%T_sl(i,j,k) = max(300.0_dp, slag%T_sl(i,j,k))

                end do
            end do
        end do

    end subroutine slag_energy

end module mod_slag_3d
