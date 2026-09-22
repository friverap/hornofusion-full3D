!===============================================================================
! mod_multiphase.f90 - Eulerian-Eulerian multiphase coupling
!
! Orchestrates:
!   1. Momentum for liquid phase
!   2. Momentum for gas phase
!   3. Shared pressure correction
!   4. Volume fraction update
!   5. Energy for both phases
!
! MPI-aware: Coordinates halo exchanges between physics modules
!===============================================================================
module mod_multiphase
    use mod_constants
    use mod_types_3d
    use mod_momentum_3d
    use mod_pressure_3d
    use mod_energy_3d
    use mod_continuity
    use mod_drag_ergun
    use mod_properties_3d
    use mod_fields_3d
    use mod_probe, only: probe_report
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid, ws_ut, &
                             ws_liq_cont_prev
    implicit none

contains

    subroutine multiphase_iteration(liq, gas, liq_old, gas_old, sol, slag, &
                                     sh, m, cfg, drag_coef, conv)
        type(phase_t), intent(inout) :: liq, gas, liq_old, gas_old
        type(solid_t), intent(inout) :: sol
        type(slag_t),  intent(in)    :: slag
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(inout)      :: drag_coef(-1:,-1:,-1:)
        type(convergence_t), intent(inout) :: conv

        real(dp) :: res_ur_l, res_uth_l, res_uz_l
        real(dp) :: res_ur_g, res_uth_g, res_uz_g
        real(dp) :: res_cont, res_energy_l, res_energy_g

        ! Copias del ITERADO externo anterior para la sub-relajación (C2.1).
        ! Workspace persistente (save): se realoca solo si cambia el tamaño.
        real(dp), allocatable, save :: p_lur(:,:,:), p_lth(:,:,:), p_luz(:,:,:)
        real(dp), allocatable, save :: p_gur(:,:,:), p_gth(:,:,:), p_guz(:,:,:)
        real(dp), allocatable, save :: p_lT(:,:,:), p_gT(:,:,:)
        ! Coeficiente de intercambio de momentum gas-líquido (C2.4)
        real(dp), allocatable, save :: Kexch(:,:,:)
        integer :: i, j, k

        if (.not. allocated(Kexch)) then
            allocate(Kexch, mold=liq%ur); Kexch = 0.0_dp
        end if

        if (.not. allocated(p_lur)) then
            allocate(p_lur, mold=liq%ur); allocate(p_lth, mold=liq%uth)
            allocate(p_luz, mold=liq%uz); allocate(p_lT, mold=liq%T)
            allocate(p_gur, mold=gas%ur); allocate(p_gth, mold=gas%uth)
            allocate(p_guz, mold=gas%uz); allocate(p_gT, mold=gas%T)
        end if
        p_lur = liq%ur; p_lth = liq%uth; p_luz = liq%uz; p_lT = liq%T
        p_gur = gas%ur; p_gth = gas%uth; p_guz = gas%uz; p_gT = gas%T

        ! Exchange halos before starting iteration
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)
        call solid_exchange_halos(sol, m)
        call shared_exchange_halos(sh, m)

        ! Mascara de liquido CONTINUO (Bug 15; halos de alpha ya intercambiados)
        call ensure_workspace(m)
        ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s)
        ws_liq_cont_valid = .true.
        call compute_liquid_drift(liq, gas, sol, m, cfg, liq_old)

        ! Transicion DISPERSO -> CONTINUO (Bug 15): la celda entra al momento
        ! y al Poisson con la velocidad promedio de sus vecinas continuas
        ! (0 si no hay), tambien en el ancla temporal liq_old. Con la
        ! velocidad de drift 'horneada' en liq%u, el Poisson tenia que
        ! frenar acero a m/s en un paso: rho_l u dx/dt ~ MPa.
        call reset_new_continuous(liq, liq_old, m)
        ws_liq_cont_prev = ws_liq_cont

        ! Compute Ergun drag coefficient from solid (Picard con |v| del líquido)
        call compute_ergun_drag(liq, sol, m, cfg, drag_coef)


        ! Coeficiente de intercambio gas-líquido: K = a_l*a_g*rho_l/TAU_LG
        ! (régimen disperso; ver mod_constants::TAU_LG)
        ! Donde el liquido es DISPERSO (Bug 15) el arrastre es el FISICO de
        ! una gota a velocidad terminal: K = alpha_l (rho_l - rho_g) g / u_t,
        ! exacto en el punto de operacion (arrastre = peso con deslizamiento
        ! u_t) e implicito en ambas fases: la inercia de la niebla (100x la
        ! del gas a alpha_l = 0.5%) amortigua al gas con tau_g = alpha_g
        ! rho_g u_t/(alpha_l rho_l g) ~ 30 ms. TAU_LG = 0.01 s daba 0.1 ms
        ! (300x demasiado rigido: era lo que 'estabilizaba' el gas en v11);
        ! K = 0 dejaba al gas libre bajo 100x su masa (melt_forced: gas a
        ! 845 m/s y p en la cota en 3 pasos).
        do k = lbound(Kexch,3)+2, ubound(Kexch,3)-2
            do j = lbound(Kexch,2)+2, ubound(Kexch,2)-2
                do i = lbound(Kexch,1)+2, ubound(Kexch,1)-2
                    if (ws_liq_cont(i,j,k)) then
                        Kexch(i,j,k) = liq%alpha(i,j,k) * gas%alpha(i,j,k) * &
                                       liq%rho(i,j,k) / TAU_LG
                    else if (ws_ut(i,j,k) > SMALL .and. liq%alpha(i,j,k) > 0.0_dp) then
                        Kexch(i,j,k) = liq%alpha(i,j,k) * &
                            max(liq%rho(i,j,k) - gas%rho(i,j,k), 0.0_dp) * GRAVITY / ws_ut(i,j,k)
                    else
                        Kexch(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do

        ! Liquid momentum
        call solve_momentum_3d(liq, liq_old, gas, Kexch, sh, m, cfg, liq%alpha, &
                               drag_coef, .false., res_ur_l, res_uth_l, res_uz_l)
        call relax_field(liq%ur,  p_lur, cfg%alpha_u, m)
        call relax_field(liq%uth, p_lth, cfg%alpha_u, m)
        call relax_field(liq%uz,  p_luz, cfg%alpha_u, m)

        ! Cota física |u_liq| <= U_LIQ_MAX preservando dirección (ver
        ! mod_constants): las celdas-gota apenas sobre el corte no tienen
        ! inercia para oponerse al gradiente de presión del arco y su
        ! velocidad diverge (B1). El cap es post-solve y pre-halos.
        call probe_report('post-momentum ', liq, gas, sol, sh, m, cfg)
        call cap_liquid_velocity(liq, m)
        call probe_report('post-cap1     ', liq, gas, sol, sh, m, cfg)

        ! Exchange halos after momentum
        call phase_exchange_halos(liq, m)

        ! Gas momentum (same drag coefficient: computed with liquid
        ! properties; a phase-specific coefficient would be more correct.
        ! Nota: la versión explícita anterior aplicaba al gas una FUERZA
        ! proporcional a la velocidad del LÍQUIDO; implícito, el coeficiente
        ! actúa sobre la velocidad propia de cada fase.)
        call solve_momentum_3d(gas, gas_old, liq, Kexch, sh, m, cfg, gas%alpha, &
                               drag_coef, .true., res_ur_g, res_uth_g, res_uz_g)
        call relax_field(gas%ur,  p_gur, cfg%alpha_u, m)
        call relax_field(gas%uth, p_gth, cfg%alpha_u, m)
        call relax_field(gas%uz,  p_guz, cfg%alpha_u, m)

        ! Exchange halos after momentum
        call phase_exchange_halos(gas, m)

        ! Pressure correction de MEZCLA: ambas fases contribuyen y ambas
        ! se corrigen (C2.4)
        call solve_pressure_correction(liq, gas, gas_old%T, sh, m, cfg, res_cont)

        ! Cota fisica TAMBIEN tras la correccion de presion: la correccion
        ! u' = u - V*grad(p')/aP con aP diminuto (celda-gota apenas sobre
        ! ALPHA_FLOW_CUTOFF) puede disparar |u| en UN paso — B1 v3 murio en
        ! el MISMO paso que v2 (235829, t=471.66: el cap pre-presion nunca
        ! disparo; el blow-up nace aqui). Bit-identico cuando no dispara.
        call probe_report('post-presion  ', liq, gas, sol, sh, m, cfg)
        call cap_liquid_velocity(liq, m)
        call probe_report('post-cap2     ', liq, gas, sol, sh, m, cfg)

        ! Exchange halos after pressure
        call shared_exchange_halos(sh, m)
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)

        ! Volume fraction update
        if (cfg%solve_multiphase) then
            call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, &
                                       liq_old%alpha, m, cfg)
            ! Exchange after volume fraction update
            call phase_exchange_halos(liq, m)
            call phase_exchange_halos(gas, m)
        end if

        call probe_report('post-alpha    ', liq, gas, sol, sh, m, cfg)

        ! Energy
        if (cfg%solve_energy) then
            call solve_energy_3d(liq, liq_old%T, sh, m, cfg, liq%alpha, &
                                 gas%alpha, liq_old%alpha, sol%mdot, sol%T_s, &
                                 .false., res_energy_l)
            call relax_field(liq%T, p_lT, cfg%alpha_T, m)
            call phase_exchange_halos(liq, m)

            ! gas: alpha_old no se usa (forma T con rho(T)); se pasa la
            ! fracción actual por uniformidad de la interfaz
            call solve_energy_3d(gas, gas_old%T, sh, m, cfg, gas%alpha, &
                                 liq%alpha, gas%alpha, sol%mdot, sol%T_s, &
                                 .true., res_energy_g)
            call relax_field(gas%T, p_gT, cfg%alpha_T, m)
            call phase_exchange_halos(gas, m)
        else
            res_energy_l = 0.0_dp
            res_energy_g = 0.0_dp
        end if

        ! Update properties
        call update_properties(liq, gas, sh, m, cfg)

        ! Record convergence
        conv%res_ur   = max(res_ur_l, res_ur_g)
        conv%res_uth  = max(res_uth_l, res_uth_g)
        conv%res_uz   = max(res_uz_l, res_uz_g)
        conv%res_cont = res_cont
        conv%res_energy = max(res_energy_l, res_energy_g)

    end subroutine multiphase_iteration

    !---------------------------------------------------------------------------
    ! Cota física de velocidad del líquido (ver U_LIQ_MAX en mod_constants).
    ! Escala el vector completo => preserva dirección; solo celdas activas.
    !---------------------------------------------------------------------------
    subroutine cap_liquid_velocity(liq, m)
        type(phase_t), intent(inout) :: liq
        type(mesh_t), intent(in)     :: m

        integer  :: i, j, k
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: vmag, f

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    ! El liquido DISPERSO lleva la velocidad de drift-flux,
                    ! ya acotada a U_SETTLE_MAX (Bug 15): no se capa aqui
                    if (ws_liq_cont_valid) then
                        if (.not. ws_liq_cont(i,j,k)) cycle
                    end if
                    vmag = sqrt(liq%ur(i,j,k)**2 + liq%uth(i,j,k)**2 + &
                                liq%uz(i,j,k)**2)
                    if (vmag > U_LIQ_MAX) then
                        f = U_LIQ_MAX / vmag
                        liq%ur(i,j,k)  = liq%ur(i,j,k)  * f
                        liq%uth(i,j,k) = liq%uth(i,j,k) * f
                        liq%uz(i,j,k)  = liq%uz(i,j,k)  * f
                    end if
                end do
            end do
        end do
    end subroutine cap_liquid_velocity

    !---------------------------------------------------------------------------
    ! Celdas que acaban de volverse liquido CONTINUO: velocidad = promedio de
    ! las vecinas continuas (0 si ninguna), en liq y en el ancla liq_old.
    !---------------------------------------------------------------------------
    subroutine reset_new_continuous(liq, liq_old, m)
        type(phase_t), intent(inout) :: liq, liq_old
        type(mesh_t), intent(in)     :: m
        integer  :: i, j, k, n, istart, iend, jstart, jend, kstart, kend
        integer  :: di(6), dj(6), dk(6), q, ii, jj, kk
        real(dp) :: sr, sth, sz
        di = [-1, 1, 0, 0, 0, 0]; dj = [0, 0, -1, 1, 0, 0]; dk = [0, 0, 0, 0, -1, 1]
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (.not. ws_liq_cont(i,j,k) .or. ws_liq_cont_prev(i,j,k)) cycle
                    n = 0; sr = 0.0_dp; sth = 0.0_dp; sz = 0.0_dp
                    do q = 1, 6
                        ii = i + di(q); jj = j + dj(q); kk = k + dk(q)
                        if (m%cell_type(ii,jj,kk) == 0) cycle
                        if (.not. ws_liq_cont_prev(ii,jj,kk)) cycle
                        n = n + 1
                        sr = sr + liq%ur(ii,jj,kk); sth = sth + liq%uth(ii,jj,kk)
                        sz = sz + liq%uz(ii,jj,kk)
                    end do
                    if (n > 0) then
                        sr = sr / n; sth = sth / n; sz = sz / n
                    end if
                    liq%ur(i,j,k) = sr;      liq%uth(i,j,k) = sth;      liq%uz(i,j,k) = sz
                    liq_old%ur(i,j,k) = sr;  liq_old%uth(i,j,k) = sth;  liq_old%uz(i,j,k) = sz
                end do
            end do
        end do
        call phase_exchange_halos(liq, m)
    end subroutine reset_new_continuous

end module mod_multiphase
