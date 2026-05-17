!===============================================================================
! mod_radiation_do.f90 - Discrete Ordinate (DO) radiation model (S4 quadrature)
!
! Solves the radiative transfer equation:
!   dI/ds = kappa*(B - I),  B = sigma*T^4/pi  (Planck function)
!
! S4 quadrature: 24 directions in 3D.
! For each direction, sweep through mesh, accumulate intensity.
! Radiative source: S_rad = kappa*(G - 4*sigma*T^4)
! where G = integrated intensity over all directions.
! Sign: positive = net absorption (heat gain), negative = net emission (heat loss).
!===============================================================================
module mod_radiation_do
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    implicit none

    integer, parameter :: N_DIRECTIONS = 24
    real(dp), parameter :: KAPPA_GAS = 0.3_dp    ! 1/m (gas absorption coefficient)
    real(dp), parameter :: KAPPA_SOLID = 10.0_dp  ! 1/m (solid region)

contains

    subroutine solve_radiation_do(liq, gas, sol, sh, m)
        type(phase_t), intent(in)    :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m

        integer  :: i, j, k, d
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: G(:,:,:)
        real(dp) :: I_dir         ! no SAVE: declared without initializer
        real(dp) :: mu_d, eta_d, xi_d, w_d
        real(dp) :: kappa, emission, T_local
        real(dp) :: ds_r, ds_th, ds_z, ds_min
        ! Limiter: local sweep (no MPI cross-rank communication) can generate
        ! spurious large G near inflow edges; cap |S_rad| to prevent instability.
        ! 1e4 W/m^3 → max dT ≈ 4.2 K/step in gas (ρcp=1200 J/m³K, dt=0.5s)
        ! (1e5 caused thermal runaway: gas heats ~42 K/step → ρcp decreases → larger
        ! dT each step → res_energy=47 at step 8 → velocity divergence steps 9-10)
        real(dp), parameter :: S_RAD_LIMIT = 1.0e4_dp
        integer  :: i_start, i_end, i_step
        integer  :: j_start, j_end, j_step
        integer  :: k_start, k_end, k_step

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        
        ! Allocate G on heap (not stack!)
        allocate(G(m%nr, m%ntheta, m%nz))
        G = 0.0_dp

        ! Sweep all S4 directions
        do d = 1, N_DIRECTIONS
            call get_s4_direction(d, mu_d, eta_d, xi_d, w_d)

            ! Determine sweep direction
            if (mu_d > 0.0_dp) then
                i_start = istart; i_end = iend; i_step = 1
            else
                i_start = iend; i_end = istart; i_step = -1
            end if
            if (eta_d > 0.0_dp) then
                j_start = jstart; j_end = jend; j_step = 1
            else
                j_start = jend; j_end = jstart; j_step = -1
            end if
            if (xi_d > 0.0_dp) then
                k_start = kstart; k_end = kend; k_step = 1
            else
                k_start = kend; k_end = kstart; k_step = -1
            end if

            do k = k_start, k_end, k_step
                do j = j_start, j_end, j_step
                    ! Initialize I_dir to blackbody equilibrium at the first cell.
                    ! Using B(T_local) instead of 0 eliminates spurious "cold wall"
                    ! cooling and gives S_rad ≈ 0 at thermal equilibrium, which is
                    ! physically correct for the interior of a furnace.
                    T_local = liq%alpha(i_start,j,k) * liq%T(i_start,j,k) + &
                              gas%alpha(i_start,j,k) * gas%T(i_start,j,k) + &
                              sol%alpha_s(i_start,j,k) * sol%T_s(i_start,j,k)
                    T_local = max(T_local, 300.0_dp)
                    I_dir   = STEFAN_BOLTZMANN * T_local**4 / PI
                    do i = i_start, i_end, i_step
                        if (m%cell_type(i,j,k) == 0) cycle

                        ! Absorption coefficient — smooth interpolation with alpha_s
                        ! to prevent discontinuous kappa jumps when scrap collapses
                        kappa = KAPPA_GAS * (1.0_dp - sol%alpha_s(i,j,k)) + &
                                KAPPA_SOLID * sol%alpha_s(i,j,k)

                        ! Local temperature (mixture weighted)
                        T_local = liq%alpha(i,j,k) * liq%T(i,j,k) + &
                                  gas%alpha(i,j,k) * gas%T(i,j,k) + &
                                  sol%alpha_s(i,j,k) * sol%T_s(i,j,k)
                        T_local = max(T_local, 300.0_dp)

                        ! Planck function: B = sigma*T^4/pi  (no kappa here)
                        ! RTE: dI/ds = kappa*(B - I), so asymptote I->B, not kappa*B
                        emission = STEFAN_BOLTZMANN * T_local**4 / PI

                        ! Path length through cell
                        ds_r  = m%dr(i) / (abs(mu_d) + SMALL)
                        ds_th = m%r(i) * m%dtheta(j) / (abs(eta_d) + SMALL)
                        ds_z  = m%dz(k) / (abs(xi_d) + SMALL)
                        ds_min = min(ds_r, ds_th, ds_z)

                        ! Update intensity along this direction
                        I_dir = emission + (I_dir - emission) * exp(-kappa * ds_min)

                        ! Accumulate to G
                        G(i,j,k) = G(i,j,k) + w_d * I_dir
                    end do
                end do
            end do
        end do

        ! Radiative source: S_rad = kappa*(G - 4*sigma*T^4)
        ! Positive = net absorption (heating), negative = net emission (cooling).
        ! Convention matches energy equation: Su += S_rad * vol

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    kappa = KAPPA_GAS * (1.0_dp - sol%alpha_s(i,j,k)) + &
                            KAPPA_SOLID * sol%alpha_s(i,j,k)

                    T_local = liq%alpha(i,j,k) * liq%T(i,j,k) + &
                              gas%alpha(i,j,k) * gas%T(i,j,k) + &
                              sol%alpha_s(i,j,k) * sol%T_s(i,j,k)
                    T_local = max(T_local, 300.0_dp)

                    sh%S_rad(i,j,k) = kappa * (G(i,j,k) - 4.0_dp * STEFAN_BOLTZMANN * T_local**4)
                    sh%S_rad(i,j,k) = max(-S_RAD_LIMIT, min(S_RAD_LIMIT, sh%S_rad(i,j,k)))
                end do
            end do
        end do

        ! Free G array
        deallocate(G)

    end subroutine solve_radiation_do

    !---------------------------------------------------------------------------
    ! S4 quadrature directions and weights (24 directions)
    ! Symmetric set for 3D: octant directions with positive/negative combos
    !---------------------------------------------------------------------------
    subroutine get_s4_direction(d, mu, eta, xi, w)
        integer, intent(in)   :: d
        real(dp), intent(out) :: mu, eta, xi, w

        real(dp), parameter :: a1 = 0.2958759_dp
        real(dp), parameter :: a2 = 0.9082483_dp
        real(dp), parameter :: w1 = 0.5235987_dp  ! pi/6

        integer :: octant, local_d
        real(dp) :: s_mu, s_eta, s_xi

        ! 24 directions = 8 octants x 3 permutations
        octant  = (d - 1) / 3 + 1
        local_d = mod(d - 1, 3) + 1

        ! Signs for each octant
        s_mu  = merge(1.0_dp, -1.0_dp, mod(octant-1, 2) == 0)
        s_eta = merge(1.0_dp, -1.0_dp, mod((octant-1)/2, 2) == 0)
        s_xi  = merge(1.0_dp, -1.0_dp, mod((octant-1)/4, 2) == 0)

        select case (local_d)
        case (1)
            mu = s_mu * a2; eta = s_eta * a1; xi = s_xi * a1
        case (2)
            mu = s_mu * a1; eta = s_eta * a2; xi = s_xi * a1
        case (3)
            mu = s_mu * a1; eta = s_eta * a1; xi = s_xi * a2
        end select

        w = w1
    end subroutine get_s4_direction

end module mod_radiation_do
