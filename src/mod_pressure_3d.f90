!===============================================================================
! mod_pressure_3d.f90 - Pressure correction equation (SIMPLE)
!
! Solves the pressure Poisson equation derived from continuity:
!   sum_f (d_f * A_f * dp'/dn) = -sum_f (rho * alpha * u* * A_f)
!
! where d_f = V_f / aP_f is the Rhie-Chow coefficient.
!
! After solving p', correct velocities and pressure:
!   u' = -d * dp'/dn   (at each face)
!   p  = p + alpha_p * p'
!
! MPI-aware: Uses local loops and SOR with global residual
!===============================================================================
module mod_pressure_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    implicit none

contains

    subroutine solve_pressure_correction(ph, sh, m, cfg, alpha_q, residual)
        type(phase_t), intent(inout) :: ph
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: aW(:,:,:), aE(:,:,:), aS(:,:,:), aN(:,:,:)
        real(dp), allocatable :: aB(:,:,:), aT(:,:,:), aP(:,:,:), Su(:,:,:)
        real(dp) :: dW, dE, dS, dN, dB, dT
        real(dp) :: alpha_f, rho_f
        integer  :: n_iter_sor
        real(dp) :: sor_res

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Allocate with halos
        allocate(aW, mold=sh%pp)
        allocate(aE, mold=sh%pp)
        allocate(aS, mold=sh%pp)
        allocate(aN, mold=sh%pp)
        allocate(aB, mold=sh%pp)
        allocate(aT, mold=sh%pp)
        allocate(aP, mold=sh%pp)
        allocate(Su, mold=sh%pp)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp
        sh%pp = 0.0_dp

        ! Loop over local cells
        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    ! Negligible liquid fraction: pp = 0 (no correction needed).
                    ! Prevents large Rhie-Chow d = vol/aP_ur when aP_ur is tiny
                    ! (alpha × ρ × vol/dt → 0 for small alpha), which would make
                    ! the pressure Poisson ill-conditioned and cause the SOR to
                    ! diverge to Inf → NaN in the residual.
                    ! Matches the guard in solve_momentum_component and solve_energy_3d.
                    if (alpha_q(i,j,k) < ALPHA_CUTOFF) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = 0.0_dp
                        cycle
                    end if

                    alpha_f = max(alpha_q(i,j,k), SMALL)
                    rho_f = ph%rho(i,j,k)

                    ! Rhie-Chow d-coefficients: d = alpha * vol / aP
                    ! West
                    if (m%cell_type(i-1,j,k) /= 0) then
                            dW = 0.5_dp * (m%vol(i,j,k)/max(ph%aP_ur(i,j,k),SMALL) + &
                                 m%vol(i-1,j,k)/max(ph%aP_ur(i-1,j,k),SMALL))
                            aW(i,j,k) = alpha_f * rho_f * dW * m%Ar(i-1,j,k) / &
                                        (0.5_dp*(m%dr(i)+m%dr(i-1)))
                        end if
                    ! East
                    if (m%cell_type(i+1,j,k) /= 0) then
                            dE = 0.5_dp * (m%vol(i,j,k)/max(ph%aP_ur(i,j,k),SMALL) + &
                                 m%vol(i+1,j,k)/max(ph%aP_ur(i+1,j,k),SMALL))
                            aE(i,j,k) = alpha_f * rho_f * dE * m%Ar(i,j,k) / &
                                        (0.5_dp*(m%dr(i)+m%dr(i+1)))
                        end if
                    ! South
                    dS = 0.5_dp * (m%vol(i,j,k)/max(ph%aP_uth(i,j,k),SMALL) + &
                         m%vol(i,jm,k)/max(ph%aP_uth(i,jm,k),SMALL))
                    aS(i,j,k) = alpha_f * rho_f * dS * m%Ath(i,j,k) / &
                                (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jm)))
                    ! North
                    dN = 0.5_dp * (m%vol(i,j,k)/max(ph%aP_uth(i,j,k),SMALL) + &
                         m%vol(i,jp,k)/max(ph%aP_uth(i,jp,k),SMALL))
                    aN(i,j,k) = alpha_f * rho_f * dN * m%Ath(i,j,k) / &
                                (m%r(i) * 0.5_dp*(m%dtheta(j)+m%dtheta(jp)))
                    ! Bottom
                    if (m%cell_type(i,j,k-1) /= 0) then
                            dB = 0.5_dp * (m%vol(i,j,k)/max(ph%aP_uz(i,j,k),SMALL) + &
                                 m%vol(i,j,k-1)/max(ph%aP_uz(i,j,k-1),SMALL))
                            aB(i,j,k) = alpha_f * rho_f * dB * m%Az(i,j,k-1) / &
                                        (0.5_dp*(m%dz(k)+m%dz(k-1)))
                        end if
                    ! Top
                    if (m%cell_type(i,j,k+1) /= 0) then
                            dT = 0.5_dp * (m%vol(i,j,k)/max(ph%aP_uz(i,j,k),SMALL) + &
                                 m%vol(i,j,k+1)/max(ph%aP_uz(i,j,k+1),SMALL))
                            aT(i,j,k) = alpha_f * rho_f * dT * m%Az(i,j,k) / &
                                        (0.5_dp*(m%dz(k)+m%dz(k+1)))
                        end if

                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k)

                    ! Mass source (continuity imbalance)
                    Su(i,j,k) = 0.0_dp
                    ! Radial fluxes
                    if (i > 1) Su(i,j,k) = Su(i,j,k) + &
                        alpha_f * rho_f * ph%ur(i,j,k) * m%Ar(i-1,j,k)
                    if (i < iend) Su(i,j,k) = Su(i,j,k) - &
                        alpha_f * rho_f * ph%ur(i+1,j,k) * m%Ar(i,j,k)
                    ! Theta fluxes
                    Su(i,j,k) = Su(i,j,k) + &
                        alpha_f * rho_f * ph%uth(i,j,k) * m%Ath(i,j,k) / m%r(i) - &
                        alpha_f * rho_f * ph%uth(i,jp,k) * m%Ath(i,j,k) / m%r(i)
                    ! Axial fluxes
                    Su(i,j,k) = Su(i,j,k) + &
                        alpha_f * rho_f * ph%uz(i,j,k) * m%Az(i,j,k-1)
                    if (k < kend) Su(i,j,k) = Su(i,j,k) - &
                        alpha_f * rho_f * ph%uz(i,j,k+1) * m%Az(i,j,k)
                end do
            end do
        end do

        ! Pressure BCs
        call apply_pressure_bc(aW, aE, aS, aN, aB, aT, aP, Su, m)

        ! Fix reference pressure (avoid singular matrix).
        ! Only the process owning global cell (1,1,1) anchors the level; if that
        ! cell is inactive (bowl geometry), fall back to its first active cell.
        if (.not. m%is_parallel .or. &
            (m%topo%iglobal_start == 1 .and. m%topo%jglobal_start == 1 .and. &
             m%topo%kglobal_start == 1)) then
            call fix_pressure_reference(aP, Su, m, istart, iend, jstart, jend, &
                                        kstart, kend)
        end if

        ! Solve with SOR (MPI-aware)
        call sor_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, sh%pp, m, &
                        SOR_OMEGA, cfg%max_inner_pres, SOR_TOL_PRESSURE, &
                        sor_res, n_iter_sor)
        
        residual = sor_res

        ! Correct velocities
        call correct_velocities(ph, sh, m)

        ! Correct pressure
        sh%p = sh%p + cfg%alpha_p * sh%pp

        deallocate(aW, aE, aS, aN, aB, aT, aP, Su)
    end subroutine solve_pressure_correction

    !---------------------------------------------------------------------------
    ! Anchor the pressure level at the first active cell of the local block
    ! using the big-coefficient method
    !---------------------------------------------------------------------------
    subroutine fix_pressure_reference(aP, Su, m, istart, iend, jstart, jend, &
                                      kstart, kend)
        real(dp), intent(inout)  :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer, intent(in)      :: istart, iend, jstart, jend, kstart, kend

        integer :: i, j, k

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) /= 0) then
                        aP(i,j,k) = aP(i,j,k) * PREF_PENALTY
                        Su(i,j,k) = 0.0_dp
                        return
                    end if
                end do
            end do
        end do
    end subroutine fix_pressure_reference

    !---------------------------------------------------------------------------
    ! Correct velocities using pressure correction gradient
    !---------------------------------------------------------------------------
    subroutine correct_velocities(ph, sh, m)
        type(phase_t), intent(inout) :: ph
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: d_coeff

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    ! u_r correction
                    if (i > 1 .and. i < iend .and. abs(ph%aP_ur(i,j,k)) > SMALL) then
                        d_coeff = m%vol(i,j,k) / ph%aP_ur(i,j,k)
                        ph%ur(i,j,k) = ph%ur(i,j,k) - d_coeff * &
                            (sh%pp(i+1,j,k) - sh%pp(i-1,j,k)) / (m%r(i+1) - m%r(i-1))
                    end if

                    ! u_theta correction
                    if (abs(ph%aP_uth(i,j,k)) > SMALL) then
                        d_coeff = m%vol(i,j,k) / ph%aP_uth(i,j,k)
                        ph%uth(i,j,k) = ph%uth(i,j,k) - d_coeff * &
                            (sh%pp(i,jp,k) - sh%pp(i,jm,k)) / &
                            (m%r(i) * (m%theta(jp) - m%theta(jm) + &
                             merge(TWO_PI, 0.0_dp, jp < jm)))
                    end if

                    ! u_z correction
                    if (k > 1 .and. k < kend .and. abs(ph%aP_uz(i,j,k)) > SMALL) then
                        d_coeff = m%vol(i,j,k) / ph%aP_uz(i,j,k)
                        ph%uz(i,j,k) = ph%uz(i,j,k) - d_coeff * &
                            (sh%pp(i,j,k+1) - sh%pp(i,j,k-1)) / (m%z(k+1) - m%z(k-1))
                    end if
                end do
            end do
        end do

    end subroutine correct_velocities

end module mod_pressure_3d
