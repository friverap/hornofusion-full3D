!===============================================================================
! mod_energy_3d.f90 - Energy equation in 3D cylindrical coordinates
!
! Solves: rho*cp*(dT/dt + u_r*dT/dr + u_th/r*dT/dtheta + u_z*dT/dz)
!       = 1/r*d/dr(r*k*dT/dr) + 1/r^2*d/dtheta(k*dT/dtheta) + d/dz(k*dT/dz) + S
!
! Discretized with FVM: implicit Euler, upwind convection, central diffusion.
! Phase-specific: called once for liquid, once for gas, with respective alpha_q.
!===============================================================================
module mod_energy_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    implicit none

contains

    subroutine solve_energy_3d(ph, T_old, sh, m, cfg, alpha_q, residual)
        type(phase_t), intent(inout) :: ph
        real(dp), intent(in)         :: T_old(-1:,-1:,-1:)
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: aW(:,:,:), aE(:,:,:), aS(:,:,:), aN(:,:,:)
        real(dp), allocatable :: aB(:,:,:), aT(:,:,:), aP(:,:,:), Su(:,:,:)
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: rho_f, k_f, vol, rho_cp_vol_dt
        real(dp) :: alpha_f

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Allocate with halos
        allocate(aW, mold=ph%T)
        allocate(aE, mold=ph%T)
        allocate(aS, mold=ph%T)
        allocate(aN, mold=ph%T)
        allocate(aB, mold=ph%T)
        allocate(aT, mold=ph%T)
        allocate(aP, mold=ph%T)
        allocate(Su, mold=ph%T)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    vol = m%vol(i,j,k)
                    alpha_f = max(alpha_q(i,j,k), SMALL)

                    ! Negligible phase fraction: trivial equation keeps T = T_old.
                    ! Prevents near-zero aP from making the TDMA diagonal singular.
                    if (alpha_q(i,j,k) < ALPHA_CUTOFF) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = T_old(i,j,k)
                        cycle
                    end if

                    rho_cp_vol_dt = alpha_f * ph%rho(i,j,k) * ph%cp(i,j,k) * vol / cfg%dt

                    ! --- Diffusion conductances ---
                    Dw = 0.0_dp; De = 0.0_dp; Db = 0.0_dp; Dt = 0.0_dp
                    ! West face (i-1/2)
                    if (m%cell_type(i-1,j,k) /= 0) then
                            k_f = 2.0_dp * ph%kth(i,j,k) * ph%kth(i-1,j,k) / &
                                  max(ph%kth(i,j,k) + ph%kth(i-1,j,k), SMALL)
                            Dw = alpha_f * k_f * m%Ar(i-1,j,k) / &
                                 (0.5_dp * (m%dr(i) + m%dr(i-1)))
                        end if

                    ! East face (i+1/2)
                    if (m%cell_type(i+1,j,k) /= 0) then
                            k_f = 2.0_dp * ph%kth(i,j,k) * ph%kth(i+1,j,k) / &
                                  max(ph%kth(i,j,k) + ph%kth(i+1,j,k), SMALL)
                            De = alpha_f * k_f * m%Ar(i,j,k) / &
                                 (0.5_dp * (m%dr(i) + m%dr(i+1)))
                        end if

                    ! South face (j-1/2) in theta
                    k_f = 2.0_dp * ph%kth(i,j,k) * ph%kth(i,jm,k) / &
                          max(ph%kth(i,j,k) + ph%kth(i,jm,k), SMALL)
                    Ds = alpha_f * k_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jm)))

                    ! North face (j+1/2) in theta
                    k_f = 2.0_dp * ph%kth(i,j,k) * ph%kth(i,jp,k) / &
                          max(ph%kth(i,j,k) + ph%kth(i,jp,k), SMALL)
                    Dn = alpha_f * k_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jp)))

                    ! Bottom face (k-1/2)
                    if (m%cell_type(i,j,k-1) /= 0) then
                            k_f = 2.0_dp * ph%kth(i,j,k) * ph%kth(i,j,k-1) / &
                                  max(ph%kth(i,j,k) + ph%kth(i,j,k-1), SMALL)
                            Db = alpha_f * k_f * m%Az(i,j,k-1) / &
                                 (0.5_dp * (m%dz(k) + m%dz(k-1)))
                        end if

                    ! Top face (k+1/2)
                    if (m%cell_type(i,j,k+1) /= 0) then
                            k_f = 2.0_dp * ph%kth(i,j,k) * ph%kth(i,j,k+1) / &
                                  max(ph%kth(i,j,k) + ph%kth(i,j,k+1), SMALL)
                            Dt = alpha_f * k_f * m%Az(i,j,k) / &
                                 (0.5_dp * (m%dz(k) + m%dz(k+1)))
                        end if

                    ! --- Convection (upwind) ---
                    rho_f = ph%rho(i,j,k)
                    Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp; Fn = 0.0_dp
                    Fb = 0.0_dp; Ft = 0.0_dp

                    if (cfg%solve_flow) then
                        Fw = alpha_f * rho_f * ph%ur(i,j,k) * m%Ar(i-1,j,k)
                        Fe = alpha_f * rho_f * ph%ur(i,j,k) * m%Ar(i,j,k)
                        Fs = alpha_f * rho_f * ph%uth(i,j,k) * m%Ath(i,j,k) / m%r(i)
                        Fn = Fs
                        Fb = alpha_f * rho_f * ph%uz(i,j,k) * m%Az(i,j,k-1)
                        Ft = alpha_f * rho_f * ph%uz(i,j,k) * m%Az(i,j,k)
                    end if

                    ! Upwind: a_nb = D + max(F, 0) or D + max(-F, 0)
                    aW(i,j,k) = Dw + max( Fw, 0.0_dp)
                    aE(i,j,k) = De + max(-Fe, 0.0_dp)
                    aS(i,j,k) = Ds + max( Fs, 0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn, 0.0_dp)
                    aB(i,j,k) = Db + max( Fb, 0.0_dp)
                    aT(i,j,k) = Dt + max(-Ft, 0.0_dp)

                    ! Source: transient + heat sources
                    Su(i,j,k) = rho_cp_vol_dt * T_old(i,j,k) &
                               + (sh%S_arc(i,j,k) + sh%S_rad(i,j,k) + sh%S_chem(i,j,k)) * vol

                    ! Central coefficient
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_cp_vol_dt &
                               + max(-Fw, 0.0_dp) + max(Fe, 0.0_dp) &
                               + max(-Fs, 0.0_dp) + max(Fn, 0.0_dp) &
                               + max(-Fb, 0.0_dp) + max(Ft, 0.0_dp)
                end do
            end do
        end do

        ! Apply boundary conditions
        call apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, cfg%T_ambient)

        ! Solve with MPI-aware TDMA
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, ph%T, m, cfg%max_inner_mom)

        ! Under-relaxation (interior cells only: halo values were just received
        ! from neighbor ranks and must not be blended with stale T_old halos)
        ph%T(istart:iend, jstart:jend, kstart:kend) = &
            cfg%alpha_T * ph%T(istart:iend, jstart:jend, kstart:kend) + &
            (1.0_dp - cfg%alpha_T) * T_old(istart:iend, jstart:jend, kstart:kend)

        ! Residual
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, ph%T, m)

        deallocate(aW, aE, aS, aN, aB, aT, aP, Su)

    end subroutine solve_energy_3d

end module mod_energy_3d
