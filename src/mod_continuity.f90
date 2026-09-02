!===============================================================================
! mod_continuity.f90 - Volume fraction transport (Eulerian-Eulerian)
!
! Eq. 4: d(alpha_q*rho_q)/dt + div(alpha_q*rho_q*v_q) = m_dot_s,mt
!
! Solved for liquid phase; gas alpha is computed from constraint:
!   alpha_l + alpha_g + alpha_s = 1
!
! CONSERVATIVO EXACTO (cierre 2026, punto 2): actualización explícita en
! forma de flujo (donor-cell upwind) con sub-pasos CFL uniformes globales.
! La suma de flujos internos telescopa a cero por construcción: el único
! error de masa es el clip de acotamiento, y se AUDITA. Historia:
!  - la forma implícita ACOTADA (aP sin dF) perdía ~6-15% del fundido
!    (alpha x residuo de continuidad, medido en melt_forced);
!  - la implícita conservativa (+dF) perdía dominancia diagonal con
!    div<0 y el TDMA producía basura;
!  - el "mapa corrector" local alpha*aP/(aP+dF) no telescopa (destruía
!    84% del fundido: reduce las celdas fuente sin dárselo a las de
!    aguas abajo).
! El sub-paso explícito es monótono a sub-CFL<1 (n_sub por allreduce del
! CFL máximo: uniforme global => telescopía y invarianza intactas).
!===============================================================================
module mod_continuity
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_parallel_utils
    use mod_face_flux
    use mod_mpi_topology, only: mpi_allreduce_max
    use mod_audit, only: audit_add, AUD_ALPHA_CLIP_MASS
    implicit none

    logical, save :: fallback_warned = .false.

contains

    subroutine solve_volume_fraction(liq, gas, sol, alpha_slag, alpha_old, m, cfg)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        ! Fracción de escoria: participa en la restricción de volumen
        real(dp), intent(in)         :: alpha_slag(-1:,-1:,-1:)
        ! alpha del PASO TEMPORAL anterior (liq_old%alpha): cada iteración
        ! externa REHACE el paso desde alpha_old con las velocidades del
        ! iterado (hallazgo 3.2: partir del iterado aplicaría mdot una vez
        ! por iteración externa).
        real(dp), intent(in)         :: alpha_old(-1:,-1:,-1:)
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k, isub, n_sub
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: cfl_loc, cfl_max, cfl_glob, dt_sub, a_pre, flux_net
        integer, parameter :: N_SUB_MAX = 128
        real(dp), allocatable :: a_new(:,:,:)

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        allocate(a_new, mold=liq%alpha)

        ! n_sub UNIFORME GLOBAL desde el CFL donor-cell máximo
        ! (suma de flujos de salida * dt / (rho*V))
        cfl_max = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    call face_mass_fluxes_noalpha(liq%rho, liq%ur, liq%uth, &
                        liq%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                    cfl_loc = (max(-Fw,0.0_dp) + max(Fe,0.0_dp) + &
                               max(-Fs,0.0_dp) + max(Fn,0.0_dp) + &
                               max(-Fb,0.0_dp) + max(Ft,0.0_dp)) * cfg%dt / &
                              (liq%rho(i,j,k) * m%vol(i,j,k))
                    cfl_max = max(cfl_max, cfl_loc)
                end do
            end do
        end do
        if (m%is_parallel) then
            call mpi_allreduce_max(cfl_max, cfl_glob, m%topo)
        else
            cfl_glob = cfl_max
        end if
        n_sub = max(1, ceiling(cfl_glob / 0.9_dp))
        if (n_sub > N_SUB_MAX) then
            if (.not. fallback_warned .and. .not. m%is_parallel .or. &
                (.not. fallback_warned .and. m%topo%rank == 0)) then
                print '(A,F8.1,A)', ' [ALPHA] AVISO: CFL liquido ', cfl_glob, &
                    ' > sub-pasable; fallback implicito acotado (defecto de' &
                    // ' masa NO auditado — regimen numericamente invalido)'
                fallback_warned = .true.
            end if
            ! Régimen roto/brutal (CFL > ~57): el explícito ya no puede
            ! garantizar monotonía. Fallback al implícito ACOTADO (estable
            ! incondicional; su defecto de masa alpha*dF queda medido por
            ! el audit mass_liq). En producción con dt por CFL esto no se
            ! alcanza.
            call solve_alpha_bounded_implicit(liq, gas, sol, alpha_slag, &
                                              alpha_old, m, cfg)
            deallocate(a_new)
            return
        end if
        dt_sub = cfg%dt / real(n_sub, dp)

        ! Partir SIEMPRE de alpha_old (ancla temporal, hallazgo 3.2)
        liq%alpha = alpha_old
        call mpi_exchange_halos_3d(liq%alpha, m%topo)

        do isub = 1, n_sub
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) then
                            a_new(i,j,k) = 0.0_dp
                            cycle
                        end if
                        call face_mass_fluxes_noalpha(liq%rho, liq%ur, &
                            liq%uth, liq%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                        ! Donor-cell: flujo de cara * alpha del lado upwind
                        flux_net = &
                              max(Fw,0.0_dp)*liq%alpha(i-1,j,k) &
                            - max(-Fw,0.0_dp)*liq%alpha(i,j,k)  &
                            - max(Fe,0.0_dp)*liq%alpha(i,j,k)   &
                            + max(-Fe,0.0_dp)*liq%alpha(i+1,j,k) &
                            + max(Fs,0.0_dp)*liq%alpha(i,j-1,k) &
                            - max(-Fs,0.0_dp)*liq%alpha(i,j,k)  &
                            - max(Fn,0.0_dp)*liq%alpha(i,j,k)   &
                            + max(-Fn,0.0_dp)*liq%alpha(i,j+1,k) &
                            + max(Fb,0.0_dp)*liq%alpha(i,j,k-1) &
                            - max(-Fb,0.0_dp)*liq%alpha(i,j,k)  &
                            - max(Ft,0.0_dp)*liq%alpha(i,j,k)   &
                            + max(-Ft,0.0_dp)*liq%alpha(i,j,k+1)
                        a_new(i,j,k) = liq%alpha(i,j,k) + dt_sub * &
                            (flux_net + sol%mdot(i,j,k)) / &
                            (liq%rho(i,j,k) * m%vol(i,j,k))
                    end do
                end do
            end do
            liq%alpha = a_new
            call mpi_exchange_halos_3d(liq%alpha, m%topo)
        end do

        ! Restricciones de acotamiento (el ÚNICO error de masa; auditado)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) then
                        liq%alpha(i,j,k) = 0.0_dp
                        gas%alpha(i,j,k) = 0.0_dp
                        cycle
                    end if

                    a_pre = liq%alpha(i,j,k)
                    liq%alpha(i,j,k) = max(0.0_dp, &
                        min(1.0_dp - sol%alpha_s(i,j,k) - alpha_slag(i,j,k), &
                            liq%alpha(i,j,k)))
                    call audit_add(AUD_ALPHA_CLIP_MASS, &
                        (a_pre - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k))
                    gas%alpha(i,j,k) = 1.0_dp - sol%alpha_s(i,j,k) &
                                       - alpha_slag(i,j,k) - liq%alpha(i,j,k)
                    gas%alpha(i,j,k) = max(0.0_dp, gas%alpha(i,j,k))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(liq%alpha, m%topo)
        call mpi_exchange_halos_3d(gas%alpha, m%topo)

        deallocate(a_new)

    end subroutine solve_volume_fraction

    !---------------------------------------------------------------------------
    ! Forma implícita ACOTADA (fallback para CFL > N_SUB_MAX*0.9): estable
    ! incondicional; no conservativa bajo div/=0 (defecto alpha*dF, medido
    ! por el audit). Es la forma que fue titular hasta el cierre 2026.
    !---------------------------------------------------------------------------
    subroutine solve_alpha_bounded_implicit(liq, gas, sol, alpha_slag, &
                                            alpha_old, m, cfg)
        use mod_workspace, only: ensure_workspace, aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        real(dp), intent(in)         :: alpha_slag(-1:,-1:,-1:)
        real(dp), intent(in)         :: alpha_old(-1:,-1:,-1:)
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft, vol_dt, a_pre

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call ensure_workspace(m)
        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    vol_dt = liq%rho(i,j,k) * m%vol(i,j,k) / cfg%dt
                    call face_mass_fluxes_noalpha(liq%rho, liq%ur, liq%uth, &
                        liq%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                    aW(i,j,k) = max( Fw, 0.0_dp)
                    aE(i,j,k) = max(-Fe, 0.0_dp)
                    aS(i,j,k) = max( Fs, 0.0_dp)
                    aN(i,j,k) = max(-Fn, 0.0_dp)
                    aB(i,j,k) = max( Fb, 0.0_dp)
                    aT(i,j,k) = max(-Ft, 0.0_dp)
                    Su(i,j,k) = vol_dt * alpha_old(i,j,k) + sol%mdot(i,j,k)
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + &
                                aN(i,j,k) + aB(i,j,k) + aT(i,j,k) + vol_dt
                end do
            end do
        end do

        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, liq%alpha, m, 10)
        call mpi_exchange_halos_3d(liq%alpha, m%topo)

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) then
                        liq%alpha(i,j,k) = 0.0_dp
                        gas%alpha(i,j,k) = 0.0_dp
                        cycle
                    end if
                    a_pre = liq%alpha(i,j,k)
                    liq%alpha(i,j,k) = max(0.0_dp, &
                        min(1.0_dp - sol%alpha_s(i,j,k) - alpha_slag(i,j,k), &
                            liq%alpha(i,j,k)))
                    call audit_add(AUD_ALPHA_CLIP_MASS, &
                        (a_pre - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k))
                    gas%alpha(i,j,k) = 1.0_dp - sol%alpha_s(i,j,k) &
                                       - alpha_slag(i,j,k) - liq%alpha(i,j,k)
                    gas%alpha(i,j,k) = max(0.0_dp, gas%alpha(i,j,k))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(liq%alpha, m%topo)
        call mpi_exchange_halos_3d(gas%alpha, m%topo)
    end subroutine solve_alpha_bounded_implicit
end module mod_continuity
