!===============================================================================
! mod_turbulence_3d.f90 - Standard k-epsilon turbulence in 3D cylindrical
!
! d(rho*k)/dt + div(rho*v*k) = div((mu + mu_t/sigma_k)*grad(k)) + G_k - rho*eps
! d(rho*eps)/dt + div(rho*v*eps) = div((mu + mu_t/sigma_eps)*grad(eps))
!                                 + C1*eps/k*G_k - C2*rho*eps^2/k
! mu_t = rho * C_mu * k^2 / epsilon
!
! G_k = production of k from mean velocity gradients.
!===============================================================================
module mod_turbulence_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    use mod_face_flux
    implicit none

contains

    subroutine solve_k_epsilon(liq, sh, m, cfg, dt)
        type(phase_t), intent(in)    :: liq
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: dt

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: aW(:,:,:), aE(:,:,:), aS(:,:,:), aN(:,:,:)
        real(dp), allocatable :: aB(:,:,:), aT(:,:,:), aP(:,:,:), Su(:,:,:)
        real(dp), allocatable :: Gk(:,:,:), tke_old(:,:,:), eps_old(:,:,:)
        real(dp) :: Dw, De, Ds, Dn, Db, Dt_d
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft_f
        real(dp) :: mu_eff, rho_f, vol, rho_vol_dt
        real(dp) :: dur_dr, dur_dz, duth_dr, duth_dz, duz_dr, duz_dz
        real(dp) :: dur_dth, duz_dth, duth_dth, S2, dT_dz, G_b
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax
        logical  :: interior_z

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        ! Gradientes centrales también en interfaces de rank (halos válidos);
        ! solo se degradan a cero en frontera FÍSICA (hallazgo 3.6)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        ! Allocate with halos
        allocate(aW, mold=sh%tke)
        allocate(aE, mold=sh%tke)
        allocate(aS, mold=sh%tke)
        allocate(aN, mold=sh%tke)
        allocate(aB, mold=sh%tke)
        allocate(aT, mold=sh%tke)
        allocate(aP, mold=sh%tke)
        allocate(Su, mold=sh%tke)
        allocate(Gk, mold=sh%tke)
        allocate(tke_old, mold=sh%tke)
        allocate(eps_old, mold=sh%eps)

        tke_old = sh%tke
        eps_old = sh%eps
        Gk = 0.0_dp

        ! Compute G_k (production) from velocity gradients
        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    ! Approximate velocity gradients using central differences
                    dur_dr = 0.0_dp; duth_dr = 0.0_dp; duz_dr = 0.0_dp
                    dur_dth = 0.0_dp; duz_dth = 0.0_dp
                    dur_dz = 0.0_dp; duth_dz = 0.0_dp; duz_dz = 0.0_dp

                    if (i > 1 .and. i < iend) then
                        dur_dr = (liq%ur(i+1,j,k) - liq%ur(i-1,j,k)) / (m%r(i+1) - m%r(i-1))
                        duth_dr = (liq%uth(i+1,j,k) - liq%uth(i-1,j,k)) / (m%r(i+1) - m%r(i-1))
                        duz_dr = (liq%uz(i+1,j,k) - liq%uz(i-1,j,k)) / (m%r(i+1) - m%r(i-1))
                    end if
                    dur_dth = (liq%ur(i,jp,k) - liq%ur(i,jm,k)) / &
                              (m%r(i) * (m%theta(jp) - m%theta(jm)))
                    duz_dth = (liq%uz(i,jp,k) - liq%uz(i,jm,k)) / &
                              (m%r(i) * (m%theta(jp) - m%theta(jm)))
                    duth_dth = (liq%uth(i,jp,k) - liq%uth(i,jm,k)) / &
                               (m%r(i) * (m%theta(jp) - m%theta(jm)))
                    interior_z = (k > kstart .or. .not. at_zmin) .and. &
                                 (k < kend   .or. .not. at_zmax)
                    if (interior_z) then
                        dur_dz = (liq%ur(i,j,k+1) - liq%ur(i,j,k-1)) / (m%z(k+1) - m%z(k-1))
                        duth_dz = (liq%uth(i,j,k+1) - liq%uth(i,j,k-1)) / (m%z(k+1) - m%z(k-1))
                        duz_dz = (liq%uz(i,j,k+1) - liq%uz(i,j,k-1)) / (m%z(k+1) - m%z(k-1))
                    end if

                    ! S^2 = 2*S_ij*S_ij — E_thth completo (C3.5): incluye
                    ! (1/r)duth/dth + ur/r (antes faltaba duth_dth)
                    S2 = 2.0_dp * (dur_dr**2 &
                       + (duth_dth + liq%ur(i,j,k)/(m%r(i)+SMALL))**2 &
                       + duz_dz**2) &
                       + (dur_dz + duz_dr)**2 &
                       + (dur_dth + duth_dr - liq%uth(i,j,k)/(m%r(i)+SMALL))**2 &
                       + (duz_dth + duth_dz)**2

                    ! Producción de flotabilidad (Boussinesq, líquido):
                    ! G_b = beta*g*(mu_t/Pr_t)*dT/dz; solo la parte
                    ! desestabilizante (>0) entra como producción (C3.5)
                    dT_dz = 0.0_dp
                    if (interior_z) then
                        dT_dz = (liq%T(i,j,k+1) - liq%T(i,j,k-1)) / &
                                (m%z(k+1) - m%z(k-1))
                    end if
                    G_b = max(0.0_dp, cfg%beta_expansion * GRAVITY * &
                              sh%mu_t(i,j,k) / PR_T * dT_dz)

                    ! Limitador de producción estándar (C3.5): sin él, zonas
                    ! de gradiente espurio disparaban k sin freno
                    Gk(i,j,k) = min(sh%mu_t(i,j,k) * S2 + G_b, &
                                    10.0_dp * liq%rho(i,j,k) * eps_old(i,j,k))
                end do
            end do
        end do

        !-----------------------------------------------------------------------
        ! Solve k equation
        !-----------------------------------------------------------------------
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
                    rho_vol_dt = rho_f * vol / dt
                    mu_eff = liq%mu(i,j,k) + sh%mu_t(i,j,k) / SIGMA_K

                    ! Diffusion
                    ! Enlaces de difusión también en interfaces de rank
                    ! (halos válidos); en frontera física los anula
                    ! apply_scalar_bc (hallazgo 3.6)
                    Dw=0; De=0; Ds=0; Dn=0; Db=0; Dt_d=0
                    if ((i > istart .or. .not. at_rmin) .and. &
                        m%cell_type(i-1,j,k) /= 0) &
                        Dw = mu_eff * m%Ar(i-1,j,k) / (0.5_dp*(m%dr(i)+m%dr(i-1)))
                    if ((i < iend .or. .not. at_rmax) .and. &
                        m%cell_type(i+1,j,k) /= 0) &
                        De = mu_eff * m%Ar(i,j,k) / (0.5_dp*(m%dr(i)+m%dr(i+1)))
                    Ds = mu_eff * m%Ath(i,j,k) / (m%r(i)*0.5_dp*(m%dtheta(j)+m%dtheta(jm)))
                    Dn = mu_eff * m%Ath(i,j,k) / (m%r(i)*0.5_dp*(m%dtheta(j)+m%dtheta(jp)))
                    if ((k > kstart .or. .not. at_zmin) .and. &
                        m%cell_type(i,j,k-1) /= 0) &
                        Db = mu_eff * m%Az(i,j,k-1) / (0.5_dp*(m%dz(k)+m%dz(k-1)))
                    if ((k < kend .or. .not. at_zmax) .and. &
                        m%cell_type(i,j,k+1) /= 0) &
                        Dt_d = mu_eff * m%Az(i,j,k) / (0.5_dp*(m%dz(k)+m%dz(k+1)))

                    ! Flujos convectivos de cara únicos (C2.2; el helper
                    ! enmascara caras contra celdas inactivas/frontera)
                    call face_mass_fluxes_noalpha(liq%rho, liq%ur, liq%uth, &
                        liq%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft_f)

                    aW(i,j,k) = Dw + max(Fw,0.0_dp)
                    aE(i,j,k) = De + max(-Fe,0.0_dp)
                    aS(i,j,k) = Ds + max(Fs,0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn,0.0_dp)
                    aB(i,j,k) = Db + max(Fb,0.0_dp)
                    aT(i,j,k) = Dt_d + max(-Ft_f,0.0_dp)

                    ! Source: G_k + transient - rho*epsilon (linearized)
                    Su(i,j,k) = rho_vol_dt * tke_old(i,j,k) + Gk(i,j,k) * vol
                    ! Forma ACOTADA de Patankar (sin dF; ver mod_energy)
                    aP(i,j,k) = aW(i,j,k)+aE(i,j,k)+aS(i,j,k)+aN(i,j,k)+aB(i,j,k)+aT(i,j,k) &
                               + rho_vol_dt + rho_f * eps_old(i,j,k) * vol / (tke_old(i,j,k)+SMALL)
                end do
            end do
        end do

        call apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, 1.0e-4_dp)
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, sh%tke, m, 3)
        sh%tke = cfg%alpha_k * sh%tke + (1.0_dp - cfg%alpha_k) * tke_old
        sh%tke = max(sh%tke, 1.0e-10_dp)

        !-----------------------------------------------------------------------
        ! Solve epsilon equation
        !-----------------------------------------------------------------------
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
                    rho_vol_dt = rho_f * vol / dt
                    mu_eff = liq%mu(i,j,k) + sh%mu_t(i,j,k) / SIGMA_EPS

                    ! Enlaces de difusión también en interfaces de rank
                    ! (halos válidos); en frontera física los anula
                    ! apply_scalar_bc (hallazgo 3.6)
                    Dw=0; De=0; Ds=0; Dn=0; Db=0; Dt_d=0
                    if ((i > istart .or. .not. at_rmin) .and. &
                        m%cell_type(i-1,j,k) /= 0) &
                        Dw = mu_eff * m%Ar(i-1,j,k) / (0.5_dp*(m%dr(i)+m%dr(i-1)))
                    if ((i < iend .or. .not. at_rmax) .and. &
                        m%cell_type(i+1,j,k) /= 0) &
                        De = mu_eff * m%Ar(i,j,k) / (0.5_dp*(m%dr(i)+m%dr(i+1)))
                    Ds = mu_eff * m%Ath(i,j,k) / (m%r(i)*0.5_dp*(m%dtheta(j)+m%dtheta(jm)))
                    Dn = mu_eff * m%Ath(i,j,k) / (m%r(i)*0.5_dp*(m%dtheta(j)+m%dtheta(jp)))
                    if ((k > kstart .or. .not. at_zmin) .and. &
                        m%cell_type(i,j,k-1) /= 0) &
                        Db = mu_eff * m%Az(i,j,k-1) / (0.5_dp*(m%dz(k)+m%dz(k-1)))
                    if ((k < kend .or. .not. at_zmax) .and. &
                        m%cell_type(i,j,k+1) /= 0) &
                        Dt_d = mu_eff * m%Az(i,j,k) / (0.5_dp*(m%dz(k)+m%dz(k+1)))

                    call face_mass_fluxes_noalpha(liq%rho, liq%ur, liq%uth, &
                        liq%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft_f)

                    aW(i,j,k) = Dw + max(Fw,0.0_dp)
                    aE(i,j,k) = De + max(-Fe,0.0_dp)
                    aS(i,j,k) = Ds + max(Fs,0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn,0.0_dp)
                    aB(i,j,k) = Db + max(Fb,0.0_dp)
                    aT(i,j,k) = Dt_d + max(-Ft_f,0.0_dp)

                    Su(i,j,k) = rho_vol_dt * eps_old(i,j,k) &
                               + C1_EPS * eps_old(i,j,k) / (tke_old(i,j,k)+SMALL) * Gk(i,j,k) * vol
                    aP(i,j,k) = aW(i,j,k)+aE(i,j,k)+aS(i,j,k)+aN(i,j,k)+aB(i,j,k)+aT(i,j,k) &
                               + rho_vol_dt &
                               + C2_EPS * rho_f * eps_old(i,j,k) * vol / (tke_old(i,j,k)+SMALL)

                    Dw=0; De=0; Ds=0; Dn=0; Db=0; Dt_d=0
                end do
            end do
        end do

        call apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, 1.0e-3_dp)
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, sh%eps, m, 3)
        sh%eps = cfg%alpha_eps * sh%eps + (1.0_dp - cfg%alpha_eps) * eps_old
        sh%eps = max(sh%eps, 1.0e-10_dp)

        ! Update turbulent viscosity
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    sh%mu_t(i,j,k) = liq%rho(i,j,k) * C_MU * &
                                      sh%tke(i,j,k)**2 / (sh%eps(i,j,k) + SMALL)
                end do
            end do
        end do

        deallocate(aW, aE, aS, aN, aB, aT, aP, Su, Gk, tke_old, eps_old)
    end subroutine solve_k_epsilon

end module mod_turbulence_3d
