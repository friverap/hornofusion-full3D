!===============================================================================
! mod_species_transport.f90 - Species transport for CO and CO2 mass fractions
!
! Solves: d(alpha_g*rho_g*Y)/dt + div(alpha_g*rho_g*u*Y)
!       = div(alpha_g*rho_g*D_eff*grad(Y)) + S_net   [kg/(m3·s)]
!
! D_eff = mu_eff / (rho_g * Sc_t)   with Sc_t = cfg%Sc_t_species
! Discretized: implicit Euler, upwind convection, central diffusion.
! Pattern is identical to solve_energy_3d with rho*cp replaced by rho.
!===============================================================================
module mod_species_transport
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    use mod_face_flux
    implicit none

contains

    subroutine solve_species_3d(gas, Y, Y_old, S_net, m, cfg, residual)
        use mod_workspace, only: ensure_workspace, aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su
        type(phase_t), intent(in)    :: gas
        real(dp),      intent(inout) :: Y(-1:,-1:,-1:)
        real(dp),      intent(in)    :: Y_old(-1:,-1:,-1:)
        real(dp),      intent(in)    :: S_net(-1:,-1:,-1:)   ! [kg/(m3·s)]
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        real(dp),      intent(out)   :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: rho_f, D_eff, vol, rho_Y_vol_dt
        real(dp) :: alpha_f

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Allocate coefficient arrays (same bounds as Y via mold)
        call ensure_workspace(m)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    vol     = m%vol(i,j,k)
                    alpha_f = gas%alpha(i,j,k)

                    ! Negligible gas fraction: keep Y = Y_old
                    if (alpha_f < 1.0e-6_dp) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = Y_old(i,j,k)
                        cycle
                    end if

                    rho_f        = gas%rho(i,j,k)
                    rho_Y_vol_dt = alpha_f * rho_f * vol / cfg%dt

                    ! Effective diffusivity: D_eff = mu_eff / (rho * Sc_t)
                    D_eff = gas%mu_eff(i,j,k) / max(rho_f * cfg%Sc_t_species, SMALL)

                    ! --- Diffusion conductances ---
                    Dw = 0.0_dp; De = 0.0_dp; Db = 0.0_dp; Dt = 0.0_dp

                    ! West face (i-1/2)
                    if (m%cell_type(i-1,j,k) /= 0) then
                        Dw = alpha_f * rho_f * D_eff * m%Ar(i-1,j,k) / &
                             (0.5_dp * (m%dr(i) + m%dr(i-1)))
                    end if

                    ! East face (i+1/2)
                    if (m%cell_type(i+1,j,k) /= 0) then
                        De = alpha_f * rho_f * D_eff * m%Ar(i,j,k) / &
                             (0.5_dp * (m%dr(i) + m%dr(i+1)))
                    end if

                    ! South face (j-1/2) in theta
                    Ds = alpha_f * rho_f * D_eff * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jm)))

                    ! North face (j+1/2) in theta
                    Dn = alpha_f * rho_f * D_eff * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jp)))

                    ! Bottom face (k-1/2)
                    if (m%cell_type(i,j,k-1) /= 0) then
                        Db = alpha_f * rho_f * D_eff * m%Az(i,j,k-1) / &
                             (0.5_dp * (m%dz(k) + m%dz(k-1)))
                    end if

                    ! Top face (k+1/2)
                    if (m%cell_type(i,j,k+1) /= 0) then
                        Dt = alpha_f * rho_f * D_eff * m%Az(i,j,k) / &
                             (0.5_dp * (m%dz(k) + m%dz(k+1)))
                    end if

                    ! --- Convection fluxes (upwind) ---
                    Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp; Fn = 0.0_dp
                    Fb = 0.0_dp; Ft = 0.0_dp

                    if (cfg%solve_flow) then
                        ! Flujos de cara únicos y conservativos (C2.2)
                        call face_mass_fluxes(gas%alpha, gas%rho, gas%ur, &
                            gas%uth, gas%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                    end if

                    ! Upwind coefficients
                    aW(i,j,k) = Dw + max( Fw, 0.0_dp)
                    aE(i,j,k) = De + max(-Fe, 0.0_dp)
                    aS(i,j,k) = Ds + max( Fs, 0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn, 0.0_dp)
                    aB(i,j,k) = Db + max( Fb, 0.0_dp)
                    aT(i,j,k) = Dt + max(-Ft, 0.0_dp)

                    ! Source: transient + species net source
                    Su(i,j,k) = rho_Y_vol_dt * Y_old(i,j,k) + S_net(i,j,k) * vol

                    ! Central coefficient
                    ! Forma ACOTADA de Patankar (sin dF; ver mod_energy)
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_Y_vol_dt
                end do
            end do
        end do

        ! Neumann BC at all boundaries (zero-gradient): Y_bc = 0.0
        call apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, 0.0_dp)

        ! Solve with MPI-aware TDMA
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, Y, m, cfg%max_inner_mom)

        ! Under-relaxation
        Y = cfg%alpha_Y_species * Y + (1.0_dp - cfg%alpha_Y_species) * Y_old

        ! Clip to physical bounds [0, 1]
        where (Y < 0.0_dp) Y = 0.0_dp
        where (Y > 1.0_dp) Y = 1.0_dp

        ! Residual
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, Y, m)


    end subroutine solve_species_3d

end module mod_species_transport
