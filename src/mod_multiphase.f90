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
    use mod_parallel_utils, only: gather_global_field_int, get_loop_bounds
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid, ws_gas_perc, ws_gas_reach, ws_gas_perc_valid, ws_ut, &
                             ws_pcorr_g, ws_pcorr_valid, ws_liq_room, ws_liq_room_valid, &
                             ws_liq_cont_prev, ws_pv_active, ws_pv_valid
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
        ! Velocidades del liquido USADAS por el solve del gas (PEA, F2.2)
        real(dp), allocatable :: ul_used_r(:,:,:), ul_used_th(:,:,:), ul_used_z(:,:,:)
        ! Solucion SIN relajar del momento del liquido (para el PEA)
        real(dp), allocatable :: ul_sol_r(:,:,:), ul_sol_th(:,:,:), ul_sol_z(:,:,:)

        ! Copias del ITERADO externo anterior para la sub-relajación (C2.1).
        ! Workspace persistente (save): se realoca solo si cambia el tamaño.
        real(dp), allocatable, save :: p_lur(:,:,:), p_lth(:,:,:), p_luz(:,:,:)
        real(dp), allocatable, save :: p_gur(:,:,:), p_gth(:,:,:), p_guz(:,:,:)
        real(dp), allocatable, save :: p_lT(:,:,:), p_gT(:,:,:)
        ! Coeficiente de intercambio de momentum gas-líquido (C2.4)
        real(dp), allocatable, save :: Kexch(:,:,:)
        real(dp), allocatable, save :: drag_gas(:,:,:)
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
        call liquid_continuity_mask(liq, sol, m, ws_liq_cont)
        ws_liq_cont_valid = .true.
        ! (la mascara de presion de fluido, ws_pv_active, se fija mas abajo:
        !  necesita el arrastre de Ergun del gas para la percolacion, F2.16)
        ws_pcorr_g = 0.0_dp; ws_pcorr_valid = .false.   ! (F2.3: sustituido por gas_pgrad_z)
        ! Hueco de poro del liquido en el lecho (F2.8; ver ws_liq_room)
        where (sol%alpha_s >= 1.0e-2_dp)
            ws_liq_room = liq_cap(sol%alpha_s, slag%alpha_sl) - liq%alpha
        elsewhere
            ws_liq_room = 1.0_dp
        end where
        ws_liq_room_valid = .true.
        call compute_liquid_drift(liq, gas, sol, m, cfg, liq_old)

        ! Transicion DISPERSO -> CONTINUO (Bug 15): la celda entra al momento
        ! y al Poisson con la velocidad promedio de sus vecinas continuas
        ! (0 si no hay), tambien en el ancla temporal liq_old. Con la
        ! velocidad de drift 'horneada' en liq%u, el Poisson tenia que
        ! frenar acero a m/s en un paso: rho_l u dx/dt ~ MPa.
        call reset_new_continuous(liq, liq_old, m)
        ws_liq_cont_prev = ws_liq_cont

        ! Compute Ergun drag coefficient from solid (Picard con |v| del líquido)
        call compute_ergun_drag(liq, sol, m, cfg, drag_coef, on_bed=.true.)
        ! Ergun del GAS con sus propias rho, mu y |v| (Bug 15, addendum 3):
        ! el coeficiente del liquido (rho_l = 7500, |v_l|) aplicado al gas
        ! daba, en cuanto el liquido disperso se movia a ~1 m/s por el
        ! lecho, un termino de Forchheimer ~4e8 kg/m3/s que congelaba el
        ! gas celda a celda; el Poisson perdia sus caminos por el lecho y
        ! p subia en cada solve (B1 v13, 5.5 s). Dormia con u_l = 0.
        if (.not. allocated(drag_gas)) then
            allocate(drag_gas, mold=liq%ur); drag_gas = 0.0_dp
        end if
        call compute_ergun_drag(gas, sol, m, cfg, drag_gas)

        ! Percolacion del gas (F2.16) y, con ella, las celdas que tienen
        ! presion de fluido (Bug 16). El gas atrapado no la tiene.
        call gas_percolation_mask(gas, sol, m, cfg, drag_gas, ws_gas_perc, ws_gas_reach)
        ws_gas_perc_valid = .true.
        ws_pv_active = (ws_liq_cont .or. &
                        (gas%alpha >= ALPHA_FLOW_CUTOFF .and. ws_gas_perc)) &
                       .and. (m%cell_type /= 0)
        ws_pv_valid = .true.

        ! Coeficiente de intercambio gas-líquido (ver F2.15 abajo)
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
                    ! F2.15 (2026-09-27): MORFOLOGIA del acople en el LECHO
                    ! (AIAD). El liquido que esta dentro del lecho o descansa
                    ! sobre el no es niebla suspendida en gas: su peso lo
                    ! lleva Ergun contra el solido y con el gas solo
                    ! intercambia CIZALLA de interfase. Con el TAU_LG de
                    ! regimen disperso, una celda 30 % liquido sobre el lecho
                    ! bajo el arco quedaba atada al chorro (u_l/u_g = 0.99
                    ! medido) y caia a 20 m/s sobre la celda del lecho en cap:
                    ! 134 kPa (B1 v31, 113.5 s). Fuera del lecho el charco
                    ! libre conserva el acople anterior: es lo unico que frena
                    ! al gas sobre un bano en reposo (bath_test: con cizalla
                    ! sola el gas se va a 143 m/s).
                    if (sol%alpha_s(i,j,k) > ALPHA_SOLID_RESID .or. &
                        sol%alpha_s(i,j,k-1) >= 1.0e-2_dp) then
                        Kexch(i,j,k) = fs_shear(i, j, k)
                    else if (ws_liq_cont(i,j,k)) then
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
        allocate(ul_sol_r, ul_sol_th, ul_sol_z, mold=liq%ur)
        ul_sol_r = liq%ur; ul_sol_th = liq%uth; ul_sol_z = liq%uz
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

        ! Gas momentum con SU coeficiente de Ergun (drag_gas; ver arriba).
        ! Nota: la versión explícita anterior aplicaba al gas una FUERZA
        ! proporcional a la velocidad del LÍQUIDO; implícito, el coeficiente
        ! actúa sobre la velocidad propia de cada fase.
        allocate(ul_used_r, ul_used_th, ul_used_z, mold=liq%ur)
        ul_used_r = liq%ur; ul_used_th = liq%uth; ul_used_z = liq%uz
        call solve_momentum_3d(gas, gas_old, liq, Kexch, sh, m, cfg, gas%alpha, &
                               drag_gas, .true., res_ur_g, res_uth_g, res_uz_g)
        ! Eliminacion parcial del arrastre (PEA; Spalding 1980, Karema & Lo
        ! 1999, Darwish & Moukalled 2001 ec. 29) en la etapa de momento y
        ! sobre las soluciones SIN relajar (la identidad H = aP u - K V
        ! u_otro solo vale para la solucion del TDMA): el liquido se resolvio
        ! con el gas de la iteracion anterior (p_g) y el gas con el liquido
        ! relajado (ul_used). Con K = 1.8e5 en las celdas de superficie
        ! (tau_gas ~ 3 us << dt) ese desfase secuencial diverge (bath_test:
        ! modo theta en el anillo del eje). Luego cada fase se relaja contra
        ! su iterado anterior como siempre.
        liq%ur = ul_sol_r; liq%uth = ul_sol_th; liq%uz = ul_sol_z
        call partial_elimination(liq, gas, Kexch, p_gur, p_gth, p_guz, &
                                 ul_used_r, ul_used_th, ul_used_z, m)
        deallocate(ul_used_r, ul_used_th, ul_used_z, ul_sol_r, ul_sol_th, ul_sol_z)
        call relax_field(liq%ur,  p_lur, cfg%alpha_u, m)
        call relax_field(liq%uth, p_lth, cfg%alpha_u, m)
        call relax_field(liq%uz,  p_luz, cfg%alpha_u, m)
        call cap_liquid_velocity(liq, m)
        call phase_exchange_halos(liq, m)
        call relax_field(gas%ur,  p_gur, cfg%alpha_u, m)
        call relax_field(gas%uth, p_gth, cfg%alpha_u, m)
        call relax_field(gas%uz,  p_guz, cfg%alpha_u, m)
        call cap_gas_velocity(gas, m)

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
        call cap_gas_velocity(gas, m)
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

    contains

        ! Cizalla interfacial de superficie libre (F2.15, AIAD):
        !   K_fs = C_FS_SHEAR rho_g |u_g - u_l| |grad alpha_l|
        ! |grad alpha_l| es la densidad de area interfacial (AIAD); sin
        ! interfase (gradiente nulo) no hay intercambio, que es lo correcto
        ! dentro de un charco o de una bolsa de gas homogenea.
        pure function fs_shear(ii, jj, kk) result(K)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: K, du, ga, gr_, gth_, gz_
            du = sqrt((gas%ur(ii,jj,kk)  - liq%ur(ii,jj,kk))**2 + &
                      (gas%uth(ii,jj,kk) - liq%uth(ii,jj,kk))**2 + &
                      (gas%uz(ii,jj,kk)  - liq%uz(ii,jj,kk))**2)
            gr_  = 0.5_dp * (liq%alpha(ii+1,jj,kk) - liq%alpha(ii-1,jj,kk)) / &
                   max(m%r(ii+1) - m%r(ii-1), SMALL) * 2.0_dp
            gth_ = 0.5_dp * (liq%alpha(ii,jj+1,kk) - liq%alpha(ii,jj-1,kk)) / &
                   max(m%r(ii) * (m%theta(jj+1) - m%theta(jj-1)), SMALL) * 2.0_dp
            gz_  = 0.5_dp * (liq%alpha(ii,jj,kk+1) - liq%alpha(ii,jj,kk-1)) / &
                   max(m%z(kk+1) - m%z(kk-1), SMALL) * 2.0_dp
            ga = sqrt(gr_*gr_ + gth_*gth_ + gz_*gz_)
            K = C_FS_SHEAR * gas%rho(ii,jj,kk) * du * ga
        end function fs_shear

    end subroutine multiphase_iteration

    !---------------------------------------------------------------------------
    ! Cota física de velocidad del líquido (ver U_LIQ_MAX en mod_constants).
    ! Escala el vector completo => preserva dirección; solo celdas activas.
    !---------------------------------------------------------------------------
    ! Cota de validez low-Mach del gas (Bug 18); ver U_GAS_MAX
    subroutine cap_gas_velocity(gas, m)
        type(phase_t), intent(inout) :: gas
        type(mesh_t), intent(in)     :: m

        integer  :: i, j, k
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: vmag, f

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    vmag = sqrt(gas%ur(i,j,k)**2 + gas%uth(i,j,k)**2 + &
                                gas%uz(i,j,k)**2)
                    if (vmag > U_GAS_MAX) then
                        f = U_GAS_MAX / vmag
                        gas%ur(i,j,k)  = gas%ur(i,j,k)  * f
                        gas%uth(i,j,k) = gas%uth(i,j,k) * f
                        gas%uz(i,j,k)  = gas%uz(i,j,k)  * f
                    end if
                end do
            end do
        end do
    end subroutine cap_gas_velocity

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

    !---------------------------------------------------------------------------
    ! PEA para dos fases (F2.2). Por celda y componente, con
    !   H_l = aP_l u_l - K V u_g,usado   (todo lo que no es el acople)
    !   H_g = aP_g u_g - K V u_l,usado
    ! se resuelve  aP_l u_l' - K V u_g' = H_l ;  aP_g u_g' - K V u_l' = H_g:
    !   u_l' = (aP_g H_l + K V H_g)/det,  u_g' = (aP_l H_g + K V H_l)/det,
    !   det = aP_l aP_g - (K V)^2 > 0  (aP_k ya incluye K V en la diagonal).
    ! Solo donde ambas fases tienen ecuacion de momento (liquido continuo
    ! y gas sobre el umbral); en el resto no hay desfase que eliminar.
    !---------------------------------------------------------------------------
    subroutine partial_elimination(liq, gas, Kexch, ug_r, ug_th, ug_z, &
                                   ul_r, ul_th, ul_z, m)
        type(phase_t), intent(inout) :: liq, gas
        real(dp), intent(in) :: Kexch(-1:,-1:,-1:)
        real(dp), intent(in) :: ug_r(-1:,-1:,-1:), ug_th(-1:,-1:,-1:), ug_z(-1:,-1:,-1:)
        real(dp), intent(in) :: ul_r(-1:,-1:,-1:), ul_th(-1:,-1:,-1:), ul_z(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: KV
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (.not. ws_liq_cont(i,j,k)) cycle
                    if (gas%alpha(i,j,k) < ALPHA_FLOW_CUTOFF) cycle
                    KV = Kexch(i,j,k) * m%vol(i,j,k)
                    if (KV <= SMALL) cycle
                    call pea2(liq%ur(i,j,k),  gas%ur(i,j,k),  liq%aP_ur(i,j,k),  gas%aP_ur(i,j,k),  KV, ug_r(i,j,k),  ul_r(i,j,k))
                    call pea2(liq%uth(i,j,k), gas%uth(i,j,k), liq%aP_uth(i,j,k), gas%aP_uth(i,j,k), KV, ug_th(i,j,k), ul_th(i,j,k))
                    call pea2(liq%uz(i,j,k),  gas%uz(i,j,k),  liq%aP_uz(i,j,k),  gas%aP_uz(i,j,k),  KV, ug_z(i,j,k),  ul_z(i,j,k))
                end do
            end do
        end do
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)
    contains
        pure subroutine pea2(ul, ug, apl, apg, KV, ug_used, ul_used)
            real(dp), intent(inout) :: ul, ug
            real(dp), intent(in)    :: apl, apg, KV, ug_used, ul_used
            real(dp) :: Hl, Hg, det
            if (apl <= SMALL .or. apg <= SMALL) return
            det = apl * apg - KV * KV
            if (det <= SMALL) return
            Hl = apl * ul - KV * ug_used
            Hg = apg * ug - KV * ul_used
            ul = (apg * Hl + KV * Hg) / det
            ug = (apl * Hg + KV * Hl) / det
        end subroutine pea2
    end subroutine partial_elimination

    !---------------------------------------------------------------------------
    ! Percolacion del gas (F2.16, 2026-09-29)
    !
    ! Hilfer (Phys. Rev. E 58 (1998) 2090) divide cada fase fluida de un medio
    ! poroso en una subfase CONECTADA (percolante) y otra DESCONECTADA
    ! (atrapada), y define la conectada como "the region inside of which an
    ! external applied pressure gradient can propagate"; las desconectadas son
    ! INMOVILES (v = 0) y su presion "is generally not continuous and hence not
    ! differentiable", por lo que no participa del campo de presion conectado.
    ! Esa es exactamente la patologia de B1 v33: bolsas de gas en el lecho que
    ! se calientan, no pueden ventear y acumulan p ~ P0 (T/T0 - 1) hasta la
    ! cota, y cuyas vecinas leen esa presion como gradiente.
    !
    ! Criterio, de CAMINO y no local (la leccion de F2.13, que probaba celda a
    ! celda y al declarar pared a las celdas del piso de poro encerraba a una
    ! vecina que si tenia movilidad local):
    !   - movil: gas activo cuyo arrastre de Ergun no domina su inercia,
    !     mob = (alpha_g rho_g/dt)/(alpha_g rho_g/dt + drag) > GAS_MOB_MIN;
    !   - percola: conectada al FREEBOARD (plano superior) por un camino de
    !     celdas moviles a traves de caras (theta periodico, r sin eje).
    ! Barrido global sobre el campo reunido (patron invariante a la
    ! descomposicion: gather + mismo recorrido en todos los ranks + escritura
    ! de celdas propias). Si no hay semilla (ninguna celda movil arriba) NO se
    ! atrapa nada: el criterio nunca puede amurallar el dominio entero.
    !---------------------------------------------------------------------------
    subroutine gas_percolation_mask(gas, sol, m, cfg, drag_gas, perc, reach)
        type(phase_t), intent(in)  :: gas
        type(solid_t), intent(in)  :: sol
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        real(dp), intent(in)       :: drag_gas(-1:,-1:,-1:)
        logical, intent(out)       :: perc(-1:,-1:,-1:)
        ! F2.21: donde el gas PUEDE entrar (percolantes + una capa fuera del lecho)
        logical, intent(out)       :: reach(-1:,-1:,-1:)

        integer, allocatable :: mob_loc(:,:,:), mob_g(:,:,:), seen(:,:,:)
        integer, allocatable :: free_loc(:,:,:), free_g(:,:,:), rch(:,:,:)
        integer, allocatable :: qi(:), qj(:), qk(:)
        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend
        integer :: ig, jg, kg, nrg, nthg, nzg, head, tail, nq, d, ii, jj, kk
        real(dp) :: tr, mob
        integer, parameter :: DIR(3,6) = reshape( &
            [ 1,0,0,  -1,0,0,  0,1,0,  0,-1,0,  0,0,1,  0,0,-1 ], [3,6])

        nrg = m%nr_g; nthg = m%nth_g; nzg = m%nz_g
        allocate(mob_loc(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(mob_g(nrg, nthg, nzg), seen(nrg, nthg, nzg))
        allocate(free_loc(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(free_g(nrg, nthg, nzg), rch(nrg, nthg, nzg))
        mob_loc = 0; free_loc = 0
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (gas%alpha(i,j,k) < ALPHA_FLOW_CUTOFF) cycle
                    tr = gas%alpha(i,j,k) * gas%rho(i,j,k) / cfg%dt
                    mob = tr / max(tr + max(drag_gas(i,j,k), 0.0_dp), SMALL)
                    if (mob > GAS_MOB_MIN) mob_loc(i,j,k) = 1
                end do
            end do
        end do
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (sol%alpha_s(i,j,k) < 1.0e-2_dp) free_loc(i,j,k) = 1
                end do
            end do
        end do
        call gather_global_field_int(mob_loc, mob_g, m)
        call gather_global_field_int(free_loc, free_g, m)

        ! Barrido en anchura desde el freeboard (plano superior)
        seen = 0
        nq = nrg * nthg * nzg
        allocate(qi(nq), qj(nq), qk(nq))
        head = 1; tail = 0
        do jg = 1, nthg
            do ig = 1, nrg
                if (mob_g(ig,jg,nzg) == 1) then
                    seen(ig,jg,nzg) = 1
                    tail = tail + 1; qi(tail) = ig; qj(tail) = jg; qk(tail) = nzg
                end if
            end do
        end do
        if (tail == 0) then
            ! sin salida al exterior no se atrapa nada (guarda: nunca amurallar)
            seen = mob_g
        else
            do while (head <= tail)
                ig = qi(head); jg = qj(head); kg = qk(head); head = head + 1
                do d = 1, 6
                    ii = ig + DIR(1,d)
                    jj = jg + DIR(2,d)
                    kk = kg + DIR(3,d)
                    if (jj < 1)    jj = nthg      ! theta periodico
                    if (jj > nthg) jj = 1
                    if (ii < 1 .or. ii > nrg) cycle
                    if (kk < 1 .or. kk > nzg) cycle
                    if (mob_g(ii,jj,kk) == 1 .and. seen(ii,jj,kk) == 0) then
                        seen(ii,jj,kk) = 1
                        tail = tail + 1; qi(tail) = ii; qj(tail) = jj; qk(tail) = kk
                    end if
                end do
            end do
        end if

        ! Dilatacion de UNA capa: el gas puede entrar a una celda vecina de
        ! gas percolante si no esta en el lecho. No propaga: una celda de bano
        ! puro es receptora, no conducto.
        rch = seen
        do kg = 1, nzg
            do jg = 1, nthg
                do ig = 1, nrg
                    if (seen(ig,jg,kg) == 1 .or. free_g(ig,jg,kg) /= 1) cycle
                    do d = 1, 6
                        ii = ig + DIR(1,d); jj = jg + DIR(2,d); kk = kg + DIR(3,d)
                        if (jj < 1)    jj = nthg
                        if (jj > nthg) jj = 1
                        if (ii < 1 .or. ii > nrg) cycle
                        if (kk < 1 .or. kk > nzg) cycle
                        if (seen(ii,jj,kk) == 1) then
                            rch(ig,jg,kg) = 1; exit
                        end if
                    end do
                end do
            end do
        end do

        ! Escritura de celdas propias (+ halos por intercambio)
        perc = .true.; reach = .true.
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    call local_to_global(m, i, j, k, ig, jg, kg)
                    perc(i,j,k) = (seen(ig,jg,kg) == 1)
                    reach(i,j,k) = (rch(ig,jg,kg) == 1)
                end do
            end do
        end do
        deallocate(mob_loc, mob_g, seen, qi, qj, qk, free_loc, free_g, rch)
        call exchange_logical_halos(perc, m)
        call exchange_logical_halos(reach, m)
    end subroutine gas_percolation_mask

    pure subroutine local_to_global(m, i, j, k, ig, jg, kg)
        type(mesh_t), intent(in) :: m
        integer, intent(in)  :: i, j, k
        integer, intent(out) :: ig, jg, kg
        if (m%is_parallel) then
            ig = m%topo%iglobal_start + (i - m%topo%istart)
            jg = m%topo%jglobal_start + (j - m%topo%jstart)
            kg = m%topo%kglobal_start + (k - m%topo%kstart)
        else
            ig = i; jg = j; kg = k
        end if
    end subroutine local_to_global

    ! Halos de una mascara logica (via entero: no hay intercambio logico)
    subroutine exchange_logical_halos(mask, m)
        logical, intent(inout)   :: mask(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer, allocatable :: tmp(:,:,:)
        allocate(tmp(lbound(mask,1):ubound(mask,1), lbound(mask,2):ubound(mask,2), &
                     lbound(mask,3):ubound(mask,3)))
        tmp = merge(1, 0, mask)
        if (m%is_parallel) then
            call mpi_exchange_halos_3d_int(tmp, m%topo)
        else
            tmp(:, -1, :)            = tmp(:, m%ntheta-1, :)
            tmp(:, 0, :)             = tmp(:, m%ntheta,   :)
            tmp(:, m%ntheta+1, :)    = tmp(:, 1,          :)
            tmp(:, m%ntheta+2, :)    = tmp(:, 2,          :)
        end if
        mask = (tmp == 1)
        deallocate(tmp)
    end subroutine exchange_logical_halos

end module mod_multiphase
