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
    use mod_face_flux
    implicit none

contains

    subroutine solve_energy_3d(ph, T_old, sh, m, cfg, alpha_q, alpha_other, &
                               mdot, T_src, is_gas, residual)
        use mod_workspace, only: ensure_workspace, aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su
        type(phase_t), intent(inout) :: ph
        real(dp), intent(in)         :: T_old(-1:,-1:,-1:)
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        ! Fracción de la OTRA fase fluida: las fuentes volumétricas (S_arc,
        ! S_rad, S_chem) se reparten por peso w = alpha_q/(alpha_l+alpha_g).
        ! Antes cada fase recibía el 100% de cada fuente: donde ambas
        ! superaban el cutoff la potencia se DUPLICABA (hallazgo 3.1b).
        real(dp), intent(in)         :: alpha_other(-1:,-1:,-1:)
        ! Fuente de masa por fusión/solidificación (C1.8, solo líquido):
        ! mdot>0 la masa fundida entra a T_src (temperatura del sólido);
        ! mdot<0 sumidero a T_P + liberación del latente al líquido.
        real(dp), intent(in)         :: mdot(-1:,-1:,-1:)
        real(dp), intent(in)         :: T_src(-1:,-1:,-1:)
        ! Identidad de fase: el LÍQUIDO difunde con k_eff = k + cp*mu_t/Pr_t
        ! (transporte térmico turbulento, hallazgo 3.12 — antes ausente
        ! mientras momentum sí usaba mu_t); el gas usa su k molecular
        ! (mu_t proviene del k-eps del líquido y no le aplica).
        logical, intent(in)          :: is_gas
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: rho_f, k_f, vol, rho_cp_vol_dt
        real(dp) :: alpha_f, w_src, C0_datum, aP_rad, T_it, aP_wall

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Dato común de entalpía: e_l(T) = cp_l*T + C0 (ver mod_melting_3d)
        C0_datum = (cfg%cp_s - cfg%cp_l) * cfg%T_liquidus + cfg%h_fusion

        ! Allocate with halos
        call ensure_workspace(m)

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
                            k_f = harm(keff(i,j,k), keff(i-1,j,k))
                            Dw = alpha_f * k_f * m%Ar(i-1,j,k) / &
                                 (0.5_dp * (m%dr(i) + m%dr(i-1)))
                        end if

                    ! East face (i+1/2)
                    if (m%cell_type(i+1,j,k) /= 0) then
                            k_f = harm(keff(i,j,k), keff(i+1,j,k))
                            De = alpha_f * k_f * m%Ar(i,j,k) / &
                                 (0.5_dp * (m%dr(i) + m%dr(i+1)))
                        end if

                    ! South face (j-1/2) in theta
                    k_f = harm(keff(i,j,k), keff(i,jm,k))
                    Ds = alpha_f * k_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jm)))

                    ! North face (j+1/2) in theta
                    k_f = harm(keff(i,j,k), keff(i,jp,k))
                    Dn = alpha_f * k_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jp)))

                    ! Bottom face (k-1/2)
                    if (m%cell_type(i,j,k-1) /= 0) then
                            k_f = harm(keff(i,j,k), keff(i,j,k-1))
                            Db = alpha_f * k_f * m%Az(i,j,k-1) / &
                                 (0.5_dp * (m%dz(k) + m%dz(k-1)))
                        end if

                    ! Top face (k+1/2)
                    if (m%cell_type(i,j,k+1) /= 0) then
                            k_f = harm(keff(i,j,k), keff(i,j,k+1))
                            Dt = alpha_f * k_f * m%Az(i,j,k) / &
                                 (0.5_dp * (m%dz(k) + m%dz(k+1)))
                        end if

                    ! --- Convection (upwind) ---
                    rho_f = ph%rho(i,j,k)
                    Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp; Fn = 0.0_dp
                    Fb = 0.0_dp; Ft = 0.0_dp

                    if (cfg%solve_flow) then
                        ! Flujos de cara únicos y conservativos (C2.2),
                        ! multiplicados por cp: el flujo convectivo de calor
                        ! es mdot*cp*T. El código original sumaba F [kg/s]
                        ! directamente a D [W/K] — la convección térmica
                        ! quedaba subponderada ~cp (x700-1000).
                        call face_mass_fluxes(alpha_q, ph%rho, ph%ur, &
                            ph%uth, ph%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                        Fw = Fw * ph%cp(i,j,k); Fe = Fe * ph%cp(i,j,k)
                        Fs = Fs * ph%cp(i,j,k); Fn = Fn * ph%cp(i,j,k)
                        Fb = Fb * ph%cp(i,j,k); Ft = Ft * ph%cp(i,j,k)
                    end if

                    ! Upwind: a_nb = D + max(F, 0) or D + max(-F, 0)
                    aW(i,j,k) = Dw + max( Fw, 0.0_dp)
                    aE(i,j,k) = De + max(-Fe, 0.0_dp)
                    aS(i,j,k) = Ds + max( Fs, 0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn, 0.0_dp)
                    aB(i,j,k) = Db + max( Fb, 0.0_dp)
                    aT(i,j,k) = Dt + max(-Ft, 0.0_dp)

                    ! Source: transient + heat sources ponderadas por fase.
                    ! Radiación (C3.4): linearización de NEWTON de la emisión
                    ! alrededor del ITERADO actual T_it (Patankar):
                    !   k(G - 4σT^4) ≈ k(G + 12σT_it^4) - 16kσT_it^3 · T
                    ! S_C a Su y S_P a aP. Con pendiente 4σT_old^3 (anclada
                    ! al paso anterior) una celda fría con G grande saltaba a
                    ! T ~ G/(4σT_old^3) astronómica.
                    w_src = alpha_q(i,j,k) / &
                            (alpha_q(i,j,k) + alpha_other(i,j,k) + SMALL)
                    T_it = max(ph%T(i,j,k), 200.0_dp)
                    Su(i,j,k) = rho_cp_vol_dt * T_old(i,j,k) &
                               + (sh%S_arc(i,j,k) + sh%S_chem(i,j,k)) &
                                 * w_src * vol &
                               + w_src * sh%kappa_f(i,j,k) * vol * &
                                 (sh%G_rad(i,j,k) + 12.0_dp * &
                                  STEFAN_BOLTZMANN * T_it**4)

                    ! Pérdidas de pared Robin (C3.1): en cada cara contra
                    ! celda inactiva (pared física o refractario del tazón):
                    ! flujo = h_wall*A*alpha*(T - T_wall), implícito
                    ! (aP += hA*alpha; Su += hA*alpha*T_wall). h_wall=0 (el
                    ! default) mantiene el comportamiento adiabático previo.
                    aP_wall = 0.0_dp
                    if (cfg%h_wall > 0.0_dp) then
                        if (m%cell_type(i-1,j,k) == 0) &
                            aP_wall = aP_wall + m%Ar(i-1,j,k)
                        if (m%cell_type(i+1,j,k) == 0) &
                            aP_wall = aP_wall + m%Ar(i,j,k)
                        if (m%cell_type(i,jm,k) == 0) &
                            aP_wall = aP_wall + m%Ath(i,j,k)
                        if (m%cell_type(i,jp,k) == 0) &
                            aP_wall = aP_wall + m%Ath(i,j,k)
                        if (m%cell_type(i,j,k-1) == 0) &
                            aP_wall = aP_wall + m%Az(i,j,k-1)
                        if (m%cell_type(i,j,k+1) == 0) &
                            aP_wall = aP_wall + m%Az(i,j,k)
                        aP_wall = aP_wall * cfg%h_wall * alpha_f
                        Su(i,j,k) = Su(i,j,k) + aP_wall * cfg%T_wall
                    end if

                    ! Emisión radiativa implícita (pendiente de Newton a aP)
                    aP_rad = w_src * sh%kappa_f(i,j,k) * 16.0_dp * &
                             STEFAN_BOLTZMANN * T_it**3 * vol

                    ! Central coefficient — forma ACOTADA de Patankar
                    ! (aP = Sum(a_nb) + transitorio + rad). Se probaron la
                    ! conservativa implícita (+dF: T -> -2e4 K en compresión)
                    ! y la corrección diferida (diverge al converger el lazo);
                    ! el déficit conservativo de la forma acotada
                    ! (phi x residuo de continuidad) queda medido por el audit.
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_cp_vol_dt &
                               + aP_rad + aP_wall

                    ! Fuente de masa por fusión/solidificación (C1.8, líquido)
                    if (.not. is_gas) then
                        if (mdot(i,j,k) > 0.0_dp) then
                            ! Fundido entra a T_src: Su += mdot*cp*T_in,
                            ! aP += mdot*cp (la masa nueva trae su propia T)
                            Su(i,j,k) = Su(i,j,k) + mdot(i,j,k) * &
                                        ph%cp(i,j,k) * T_src(i,j,k)
                            aP(i,j,k) = aP(i,j,k) + mdot(i,j,k) * ph%cp(i,j,k)
                        else if (mdot(i,j,k) < 0.0_dp) then
                            ! Sumidero a T_P (upwind: aP += |mdot|*cp) más el
                            ! latente liberado e_l(T_old) - e_entry >= 0
                            ! entregado al líquido, con el MISMO e_entry que
                            ! usa compute_melting (min con e_s(T_solidus)
                            ! garantiza fuente no negativa)
                            aP(i,j,k) = aP(i,j,k) - mdot(i,j,k) * ph%cp(i,j,k)
                            Su(i,j,k) = Su(i,j,k) - mdot(i,j,k) * &
                                (ph%cp(i,j,k) * T_old(i,j,k) + C0_datum &
                                 - min(cfg%cp_s * cfg%T_solidus, &
                                       ph%cp(i,j,k) * T_old(i,j,k) + C0_datum))
                        end if
                    end if
                end do
            end do
        end do

        ! Apply boundary conditions
        call apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, cfg%T_ambient)

        ! Solve with MPI-aware TDMA
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, ph%T, m, cfg%max_inner_mom)

        ! (C2.1: sub-relajación en el lazo externo contra el iterado
        ! anterior — ver multiphase_iteration/relax_field)

        ! Residual
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, ph%T, m)


    contains

        ! Conductividad efectiva del centro de celda: k + cp*mu_t/Pr_t para
        ! el líquido (transporte turbulento); molecular para el gas
        pure function keff(ii, jj, kk) result(kv)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: kv
            kv = ph%kth(ii,jj,kk)
            if (.not. is_gas) then
                kv = kv + ph%cp(ii,jj,kk) * sh%mu_t(ii,jj,kk) / PR_T
            end if
        end function keff

        pure function harm(ka, kb) result(kf)
            real(dp), intent(in) :: ka, kb
            real(dp) :: kf
            kf = 2.0_dp * ka * kb / max(ka + kb, SMALL)
        end function harm

    end subroutine solve_energy_3d

end module mod_energy_3d
