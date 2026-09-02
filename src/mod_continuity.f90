!===============================================================================
! mod_continuity.f90 - Volume fraction transport (Eulerian-Eulerian)
!
! Eq. 4: d(alpha_q*rho_q)/dt + div(alpha_q*rho_q*v_q) = m_dot_s,mt
!
! Solved for liquid phase; gas alpha is computed from constraint:
!   alpha_l + alpha_g + alpha_s = 1
!
! Discretized: implicit Euler, upwind convection.
!===============================================================================
module mod_continuity
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_parallel_utils
    use mod_audit, only: audit_add, AUD_ALPHA_CLIP_MASS
    implicit none

contains

    subroutine solve_volume_fraction(liq, gas, sol, alpha_old, m, cfg)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        ! alpha del PASO TEMPORAL anterior (liq_old%alpha). El término
        ! transitorio debe anclarse a él: usar el iterado actual aplicaría la
        ! fuente de fusión mdot una vez POR ITERACIÓN EXTERNA (masa líquida
        ! multiplicada ~max_outer veces por paso). Hallazgo 3.2.
        real(dp), intent(in)         :: alpha_old(-1:,-1:,-1:)
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: aW(:,:,:), aE(:,:,:), aS(:,:,:), aN(:,:,:)
        real(dp), allocatable :: aB(:,:,:), aT(:,:,:), aP(:,:,:), Su(:,:,:)
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: rho_f, vol, vol_dt, a_pre

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Allocate with halos
        allocate(aW, mold=liq%alpha)
        allocate(aE, mold=liq%alpha)
        allocate(aS, mold=liq%alpha)
        allocate(aN, mold=liq%alpha)
        allocate(aB, mold=liq%alpha)
        allocate(aT, mold=liq%alpha)
        allocate(aP, mold=liq%alpha)
        allocate(Su, mold=liq%alpha)
        
        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    vol = m%vol(i,j,k)
                    rho_f = liq%rho(i,j,k)
                    vol_dt = rho_f * vol / cfg%dt

                    ! Upwind convective fluxes (using liquid velocity)
                    Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp; Fn = 0.0_dp
                    Fb = 0.0_dp; Ft = 0.0_dp
                    Fw = rho_f * liq%ur(i,j,k) * m%Ar(i-1,j,k)
                    Fe = rho_f * liq%ur(i,j,k) * m%Ar(i,j,k)
                    Fs = rho_f * liq%uth(i,j,k) * m%Ath(i,j,k) / m%r(i)
                    Fn = Fs
                    Fb = rho_f * liq%uz(i,j,k) * m%Az(i,j,k-1)
                    Ft = rho_f * liq%uz(i,j,k) * m%Az(i,j,k)

                    aW(i,j,k) = max( Fw, 0.0_dp)
                    aE(i,j,k) = max(-Fe, 0.0_dp)
                    aS(i,j,k) = max( Fs, 0.0_dp)
                    aN(i,j,k) = max(-Fn, 0.0_dp)
                    aB(i,j,k) = max( Fb, 0.0_dp)
                    aT(i,j,k) = max(-Ft, 0.0_dp)

                    ! Source: transient + melting rate
                    ! sol%mdot is [kg/s] per cell (= dm/dt); vol_dt*alpha is also [kg/s].
                    ! Do NOT multiply by vol — that would give wrong units [kg*m^3/s].
                    Su(i,j,k) = vol_dt * alpha_old(i,j,k) + sol%mdot(i,j,k)

                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + vol_dt &
                               + max(-Fw,0.0_dp) + max(Fe,0.0_dp) &
                               + max(-Fs,0.0_dp) + max(Fn,0.0_dp) &
                               + max(-Fb,0.0_dp) + max(Ft,0.0_dp)
                end do
            end do
        end do

        ! Solve for liquid alpha with MPI-aware solver
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, liq%alpha, m, 3)

        ! Under-relax
        ! (alpha is bounded, no separate under-relaxation, just clip)

        ! Enforce constraints
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) then
                        liq%alpha(i,j,k) = 0.0_dp
                        gas%alpha(i,j,k) = 0.0_dp
                        cycle
                    end if

                    a_pre = liq%alpha(i,j,k)
                    liq%alpha(i,j,k) = max(0.0_dp, min(1.0_dp - sol%alpha_s(i,j,k), &
                                                         liq%alpha(i,j,k)))
                    ! Auditoría: masa neta quitada/añadida por el clipping
                    call audit_add(AUD_ALPHA_CLIP_MASS, &
                        (a_pre - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k))
                    gas%alpha(i,j,k) = 1.0_dp - sol%alpha_s(i,j,k) - liq%alpha(i,j,k)
                    gas%alpha(i,j,k) = max(0.0_dp, gas%alpha(i,j,k))
                end do
            end do
        end do

        deallocate(aW, aE, aS, aN, aB, aT, aP, Su)
    end subroutine solve_volume_fraction

end module mod_continuity
