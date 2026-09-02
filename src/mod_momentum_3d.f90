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
    use mod_face_flux
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Solve all three momentum components for a single phase
    !---------------------------------------------------------------------------
    subroutine solve_momentum_3d(ph, ph_old, ph_other, Kexch, sh, m, cfg, &
                                  alpha_q, drag_coef, is_gas, &
                                  res_ur, res_uth, res_uz)
        type(phase_t), intent(inout) :: ph
        type(phase_t), intent(in)    :: ph_old
        ! Otra fase fluida + coeficiente de intercambio de momentum K [kg/(m3 s)]
        ! (C2.4): aP += K*vol, Su += K*u_otra*vol — implícito y simétrico.
        type(phase_t), intent(in)    :: ph_other
        real(dp), intent(in)         :: Kexch(-1:,-1:,-1:)
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        ! Coeficiente de Ergun (>=0), tratado IMPLÍCITO: aP += coef*vol (C1.4)
        real(dp), intent(in)         :: drag_coef(-1:,-1:,-1:)
        ! Identidad de fase: el gas NO recibe Boussinesq (su rho(T) de gas
        ! ideal ya aporta la flotabilidad; sumarle beta del acero la
        ! duplicaba — hallazgo 3.13)
        logical, intent(in)          :: is_gas
        real(dp), intent(out)        :: res_ur, res_uth, res_uz

        ! Solve each component
        call solve_momentum_component(ph%ur, ph_old%ur, ph_other%ur, Kexch, &
                                       ph, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'ur', res_ur)

        call solve_momentum_component(ph%uth, ph_old%uth, ph_other%uth, Kexch, &
                                       ph, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'uth', res_uth)

        call solve_momentum_component(ph%uz, ph_old%uz, ph_other%uz, Kexch, &
                                       ph, sh, m, cfg, &
                                       alpha_q, drag_coef, is_gas, 'uz', res_uz)

    end subroutine solve_momentum_3d

    !---------------------------------------------------------------------------
    ! Single momentum component solver (MPI-aware)
    !---------------------------------------------------------------------------
    subroutine solve_momentum_component(vel, vel_old, vel_other, Kexch, &
                                         ph, sh, m, cfg, &
                                         alpha_q, drag_coef, is_gas, comp, residual)
        real(dp), intent(inout)      :: vel(-1:,-1:,-1:)
        real(dp), intent(in)         :: vel_old(-1:,-1:,-1:)
        real(dp), intent(in)         :: vel_other(-1:,-1:,-1:)
        real(dp), intent(in)         :: Kexch(-1:,-1:,-1:)
        type(phase_t), intent(inout) :: ph
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        real(dp), intent(in)         :: drag_coef(-1:,-1:,-1:)
        logical, intent(in)          :: is_gas
        character(len=*), intent(in) :: comp
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: aW(:,:,:), aE(:,:,:), aS(:,:,:), aN(:,:,:)
        real(dp), allocatable :: aB(:,:,:), aT(:,:,:), aP(:,:,:), Su(:,:,:)
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: mu_f, vol, alpha_f, rho_vol_dt
        real(dp) :: dp_dr, dp_dth, dp_dz, src_extra, aP_extra
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

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

                    ! Fase por debajo del umbral hidrodinámico: velocidad 0
                    ! (C2.2, ALPHA_FLOW_CUTOFF; antes vel=vel_old con umbral
                    ! 1e-6 dejaba celdas casi vacías con aP diminuto en el
                    ! acople de presión)
                    if (alpha_q(i,j,k) < ALPHA_FLOW_CUTOFF) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = 0.0_dp
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

                    ! Flujos convectivos de cara únicos (C2.2)
                    call face_mass_fluxes(alpha_q, ph%rho, ph%ur, ph%uth, &
                        ph%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)

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
                    aP_extra = 0.0_dp

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
                                   + (-alpha_f * dp_dr + src_extra) * vol

                    case ('uth')
                        ! theta desenrollada en halos: la diferencia es
                        ! correcta también en la costura (el parche
                        ! merge(jp<jm) anterior nunca se activaba: comparaba
                        ! ÍNDICES, y jp=j+1 > jm=j-1 siempre)
                        dp_dth = (sh%p(i,jp,k) - sh%p(i,jm,k)) / &
                                 (m%r(i) * (m%theta(jp) - m%theta(jm)))
                        ! Coriolis -rho*ur*uth/r, LINEAL en uth: linearización
                        ! de Patankar — implícito (aP_extra) cuando el
                        ! coeficiente es positivo. Explícito cerraba el lazo de
                        ! realimentación con el término centrífugo
                        ! (uth^2/r -> ur -> ur*uth/r) y las velocidades
                        ! divergían (medido |u| -> 1e14).
                        aP_extra = alpha_f * ph%rho(i,j,k) * &
                                   max(ph%ur(i,j,k), 0.0_dp) / m%r(i) * vol
                        src_extra = -alpha_f * ph%rho(i,j,k) * &
                                    min(ph%ur(i,j,k), 0.0_dp) * ph%uth(i,j,k) / m%r(i) &
                                  + sh%F_lorentz_th(i,j,k)
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dth + src_extra) * vol

                    case ('uz')
                        ! Central salvo en frontera FÍSICA; en interfaces de
                        ! rank el halo de p es válido (hallazgo 3.6)
                        if ((k > kstart .or. .not. at_zmin) .and. &
                            (k < kend   .or. .not. at_zmax)) then
                            dp_dz = (sh%p(i,j,k+1) - sh%p(i,j,k-1)) / (m%z(k+1) - m%z(k-1))
                        else if (k == kstart .and. kend > kstart) then
                            dp_dz = (sh%p(i,j,k+1) - sh%p(i,j,k)) / (m%z(k+1) - m%z(k))
                        else if (k == kend .and. kend > kstart) then
                            dp_dz = (sh%p(i,j,k) - sh%p(i,j,k-1)) / (m%z(k) - m%z(k-1))
                        end if
                        ! Gravity + arc impingement; Boussinesq SOLO líquido
                        ! (rho constante): el gas ya tiene flotabilidad vía
                        ! rho(T) de gas ideal (hallazgo 3.13)
                        src_extra = -alpha_f * ph%rho(i,j,k) * GRAVITY &
                                  + sh%S_arc_mom(i,j,k)
                        if (.not. is_gas) then
                            src_extra = src_extra &
                                  + alpha_f * ph%rho(i,j,k) * cfg%beta_expansion &
                                    * GRAVITY * (ph%T(i,j,k) - cfg%T_ambient)
                        end if
                        Su(i,j,k) = rho_vol_dt * vel_old(i,j,k) &
                                   + (-alpha_f * dp_dz + src_extra) * vol
                    end select

                    ! Central coefficient (drag de Ergun IMPLÍCITO: coef*vol —
                    ! incondicionalmente estable, mismo punto fijo que la
                    ! versión explícita divergente; hallazgo 3.11)
                    ! Intercambio de momentum entre fases (C2.4), implícito
                    Su(i,j,k) = Su(i,j,k) + Kexch(i,j,k) * vel_other(i,j,k) * vol

                    ! Forma ACOTADA de Patankar (sin dF; ver mod_energy)
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_vol_dt &
                               + drag_coef(i,j,k) * vol + aP_extra &
                               + Kexch(i,j,k) * vol
                end do
            end do
        end do

        ! Boundary conditions
        call apply_momentum_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, comp)

        ! Solve with MPI-aware TDMA
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, vel, m, cfg%max_inner_mom)

        ! (C2.1: la sub-relajación se hace en el LAZO EXTERNO contra el
        ! iterado anterior — ver multiphase_iteration/relax_field. Relajar
        ! aquí contra vel_old del paso temporal sesgaba el punto fijo.)

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
