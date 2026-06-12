!===============================================================================
! mod_momentum_3d.f90 - 3D momentum equations in cylindrical coordinates
!
! Solves for u_r, u_theta, u_z with:
!   - First-order upwind convection
!   - Central differencing diffusion
!   - Implicit Euler time integration
!   - Cylindrical extra terms:
!       r-mom:     -rho*u_theta^2/r (centrifugal)
!       theta-mom: +rho*u_r*u_theta/r (Coriolis)
!   - Source terms: gravity, drag (Ergun), arc impingement
!
! Returns aP coefficients for Rhie-Chow pressure correction.
!
! MPI-aware: Uses local loops and halo exchanges
!===============================================================================
module mod_momentum_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Solve all three momentum components for a single phase
    !---------------------------------------------------------------------------
    subroutine solve_momentum_3d(ph, ph_old, sh, m, cfg, alpha_q, &
                                  S_drag_r, S_drag_th, S_drag_z, &
                                  res_ur, res_uth, res_uz)
        type(phase_t), intent(inout) :: ph
        type(phase_t), intent(in)    :: ph_old
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        real(dp), intent(in)         :: S_drag_r(-1:,-1:,-1:), S_drag_th(-1:,-1:,-1:), S_drag_z(-1:,-1:,-1:)
        real(dp), intent(out)        :: res_ur, res_uth, res_uz

        ! Solve each component
        call solve_momentum_component(ph%ur, ph_old%ur, ph, sh, m, cfg, &
                                       alpha_q, S_drag_r, 'ur', res_ur)
        
        call solve_momentum_component(ph%uth, ph_old%uth, ph, sh, m, cfg, &
                                       alpha_q, S_drag_th, 'uth', res_uth)
        
        call solve_momentum_component(ph%uz, ph_old%uz, ph, sh, m, cfg, &
                                       alpha_q, S_drag_z, 'uz', res_uz)
        
    end subroutine solve_momentum_3d

    !---------------------------------------------------------------------------
    ! Single momentum component solver (MPI-aware)
    !---------------------------------------------------------------------------
    subroutine solve_momentum_component(vel, vel_old, ph, sh, m, cfg, &
                                         alpha_q, S_drag, comp, residual)
        real(dp), intent(inout)      :: vel(-1:,-1:,-1:)
        real(dp), intent(in)         :: vel_old(-1:,-1:,-1:)
        type(phase_t), intent(inout) :: ph
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        real(dp), intent(in)         :: S_drag(-1:,-1:,-1:)
        character(len=*), intent(in) :: comp
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: aW(:,:,:), aE(:,:,:), aS(:,:,:), aN(:,:,:)
        real(dp), allocatable :: aB(:,:,:), aT(:,:,:), aP(:,:,:), Su(:,:,:)
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: mu_f, vol, alpha_f, rho_vol_dt
        real(dp) :: dp_dr, dp_dth, dp_dz, src_extra

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Allocate coefficient arrays (with same dimensions as fields)
        allocate(aW, mold=vel)
        allocate(aE, mold=vel)
        allocate(aS, mold=vel)
        allocate(aN, mold=vel)
        allocate(aB, mold=vel)
        allocate(aT, mold=vel)
        allocate(aP, mold=vel)
        allocate(Su, mold=vel)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        ! Loop over local cells only
        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    vol = m%vol(i,j,k)
                    alpha_f = max(alpha_q(i,j,k), SMALL)

                    ! Negligible phase fraction: trivial equation keeps vel = vel_old.
                    ! Prevents near-zero aP (= 0 * rho * vol / dt) from making
                    ! the TDMA diagonal singular.
                    if (alpha_q(i,j,k) < ALPHA_CUTOFF) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = vel_old(i,j,k)
                        cycle
                    end if

                    rho_vol_dt = alpha_f * ph%rho(i,j,k) * vol / cfg%dt

                    ! Diffusion coefficients (viscous)
                    Dw = 0.0_dp; De = 0.0_dp; Ds = 0.0_dp; Dn = 0.0_dp
                    Db = 0.0_dp; Dt = 0.0_dp
                    ! West
                    if (m%cell_type(i-1,j,k) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i-1,j,k))
                            Dw = alpha_f * mu_f * m%Ar(i-1,j,k) / (0.5_dp*(m%dr(i)+m%dr(i-1)))
                        end if
                    ! East
                    if (m%cell_type(i+1,j,k) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i+1,j,k))
                            De = alpha_f * mu_f * m%Ar(i,j,k) / (0.5_dp*(m%dr(i)+m%dr(i+1)))
                        end if
                    ! South (theta-)
                    mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,jm,k))
                    Ds = alpha_f * mu_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jm)))
                    ! North (theta+)
                    mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,jp,k))
                    Dn = alpha_f * mu_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jp)))
                    ! Bottom
                    if (m%cell_type(i,j,k-1) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,j,k-1))
                            Db = alpha_f * mu_f * m%Az(i,j,k-1) / (0.5_dp*(m%dz(k)+m%dz(k-1)))
                        end if
                    ! Top
                    if (m%cell_type(i,j,k+1) /= 0) then
                            mu_f = 0.5_dp * (ph%mu_eff(i,j,k) + ph%mu_eff(i,j,k+1))
                            Dt = alpha_f * mu_f * m%Az(i,j,k) / (0.5_dp*(m%dz(k)+m%dz(k+1)))
                        end if

                    ! Convective fluxes
                    Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp; Fn = 0.0_dp
                    Fb = 0.0_dp; Ft = 0.0_dp
                    Fw = alpha_f * ph%rho(i,j,k) * ph%ur(i,j,k) * m%Ar(i-1,j,k)
                    Fe = alpha_f * ph%rho(i,j,k) * ph%ur(i,j,k) * m%Ar(i,j,k)
                    Fs = alpha_f * ph%rho(i,j,k) * ph%uth(i,j,k) * m%Ath(i,j,k) / m%r(i)
                    Fn = Fs
                    Fb = alpha_f * ph%rho(i,j,k) * ph%uz(i,j,k) * m%Az(i,j,k-1)
                    Ft = alpha_f * ph%rho(i,j,k) * ph%uz(i,j,k) * m%Az(i,j,k)

                    ! Upwind coefficients
                    aW(i,j,k) = Dw + max( Fw, 0.0_dp)
                    aE(i,j,k) = De + max(-Fe, 0.0_dp)
                    aS(i,j,k) = Ds + max( Fs, 0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn, 0.0_dp)
                    aB(i,j,k) = Db + max( Fb, 0.0_dp)
                    aT(i,j,k) = Dt + max(-Ft, 0.0_dp)

                    ! Pressure gradient and extra cylindrical sources
                    dp_dr = 0.0_dp; dp_dth = 0.0_dp; dp_dz = 0.0_dp
                    src_extra = 0.0_dp

                    select case (comp)
                    case ('ur')
                        if (i > 1 .and. i < iend) then
                            dp_dr = (sh%p(i+1,j,k) - sh%p(i-1,j,k)) / (m%r(i+1) - m%r(i-1))
                        else if (i == istart .and. iend > istart) then
                            dp_dr = (sh%p(i+1,j,k) - sh%p(i,j,k)) / (m%r(i+1) - m%r(i))
                        else if (i == iend .and. iend > istart) then
                            dp_dr = (sh%p(i,j,k) - sh%p(i-1,j,k)) / (m%r(i) - m%r(i-1))
                        end if
                        ! Centrifugal: +rho*u_th^2/r  +  Lorentz r-stirring
                        src_extra = alpha_f * ph%rho(i,j,k) * ph%uth(i,j,k)**2 / m%r(i) &
                                  + sh%F_lorentz_r(i,j,k)
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dr + src_extra + S_drag(i,j,k)) * vol

                    case ('uth')
                        dp_dth = (sh%p(i,jp,k) - sh%p(i,jm,k)) / &
                                 (m%r(i) * (m%theta(jp) - m%theta(jm) + &
                                  merge(TWO_PI, 0.0_dp, jp < jm)))
                        ! Coriolis: -rho*u_r*u_th/r  +  Lorentz theta-stirring
                        src_extra = -alpha_f * ph%rho(i,j,k) * ph%ur(i,j,k) * ph%uth(i,j,k) / m%r(i) &
                                  + sh%F_lorentz_th(i,j,k)
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dth + src_extra + S_drag(i,j,k)) * vol

                    case ('uz')
                        if (k > 1 .and. k < kend) then
                            dp_dz = (sh%p(i,j,k+1) - sh%p(i,j,k-1)) / (m%z(k+1) - m%z(k-1))
                        else if (k == kstart .and. kend > kstart) then
                            dp_dz = (sh%p(i,j,k+1) - sh%p(i,j,k)) / (m%z(k+1) - m%z(k))
                        else if (k == kend .and. kend > kstart) then
                            dp_dz = (sh%p(i,j,k) - sh%p(i,j,k-1)) / (m%z(k) - m%z(k-1))
                        end if
                        ! Gravity + Boussinesq buoyancy + arc impingement
                        ! Boussinesq: α_f * ρ * g * β * (T - T_ref)  (upward when T > T_ref)
                        src_extra = -alpha_f * ph%rho(i,j,k) * GRAVITY &
                                  + alpha_f * ph%rho(i,j,k) * cfg%beta_expansion * GRAVITY &
                                    * (ph%T(i,j,k) - cfg%T_ambient) &
                                  + sh%S_arc_mom(i,j,k)
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dz + src_extra + S_drag(i,j,k)) * vol
                    end select

                    ! Central coefficient
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_vol_dt &
                               + max(-Fw, 0.0_dp) + max(Fe, 0.0_dp) &
                               + max(-Fs, 0.0_dp) + max(Fn, 0.0_dp) &
                               + max(-Fb, 0.0_dp) + max(Ft, 0.0_dp)
                end do
            end do
        end do

        ! Boundary conditions
        call apply_momentum_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, comp)

        ! Solve with MPI-aware TDMA
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, vel, m, cfg%max_inner_mom)

        ! Under-relaxation (interior cells only: halo values were just received
        ! from neighbor ranks and must not be blended with stale vel_old halos)
        vel(istart:iend, jstart:jend, kstart:kend) = &
            cfg%alpha_u * vel(istart:iend, jstart:jend, kstart:kend) + &
            (1.0_dp - cfg%alpha_u) * vel_old(istart:iend, jstart:jend, kstart:kend)

        ! Store aP for Rhie-Chow
        select case (comp)
        case ('ur');  ph%aP_ur = aP
        case ('uth'); ph%aP_uth = aP
        case ('uz');  ph%aP_uz = aP
        end select

        ! Compute residual (MPI-aware)
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, vel, m)

        deallocate(aW, aE, aS, aN, aB, aT, aP, Su)
    end subroutine solve_momentum_component

end module mod_momentum_3d
