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
    use mod_probe, only: probe_report, probe_current_step
    use mod_parallel_utils, only: gather_global_field_int, get_loop_bounds
    use mod_mpi_topology, only: mpi_allreduce_max, mpi_exchange_halos_3d
    use mod_workspace, only: ensure_workspace, cond_view_enter, cond_view_exit, ws_cond_on, &
                             ws_sp_asl, ws_sp_es, ws_sp_mx, ws_liq_cont, ws_liq_cont_valid, ws_bed, ws_bed_gas, ws_bed_liq, ws_bedl_f, ws_bedg_f, gas_face_mask, ws_bub, ws_bub_f, ws_bed_valid, ws_gas_perc, ws_gas_reach, ws_gas_perc_valid, ws_ut, &
                             ws_liq_room, ws_liq_room_valid, &
                             ws_liq_fr, ws_liq_fth, ws_liq_fz, &
                             ws_liq_cont_prev, ws_pv_active, ws_pv_valid, ws_pv_liq, ws_pv_liq_valid, ws_pv_liq_id, ws_Tsrc, &
                             ws_pea_kv, ws_pea_al, ws_pea_ag, ws_peal_r, ws_peal_th, ws_peal_z, ws_peag_r, ws_peag_th, ws_peag_z
    implicit none

contains

    subroutine multiphase_iteration(liq, gas, liq_old, gas_old, sol, slag, &
                                     sh, m, cfg, drag_coef, conv)
        type(phase_t), intent(inout) :: liq, gas, liq_old, gas_old
        type(solid_t), intent(inout) :: sol
        type(slag_t),  intent(inout) :: slag
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(inout)      :: drag_coef(-1:,-1:,-1:)
        type(convergence_t), intent(inout) :: conv

        real(dp) :: res_ur_l, res_uth_l, res_uz_l
        real(dp) :: res_ur_g, res_uth_g, res_uz_g
        real(dp) :: res_cont, res_energy_l, res_energy_g
        ! Plan E E2: corrector interno alpha<->p (n_pc_max pasadas)
        integer  :: ic, n_pc_used
        logical  :: cond
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: res_ic, dalpha_loc, dalpha_pc
        real(dp), allocatable :: a_prev(:,:,:)
        real(dp) :: al_c, ag_c, as_e, xb, f_bed, f_disp, K_int, K_disp, rho_mix  ! F2.22
        ! Velocidades del liquido USADAS por el solve del gas (PEA, F2.2)
        real(dp), allocatable :: ul_used_r(:,:,:), ul_used_th(:,:,:), ul_used_z(:,:,:)
        real(dp), allocatable :: md_g(:,:,:)
        ! Solucion SIN relajar del momento del liquido (para el PEA)
        real(dp), allocatable :: ul_sol_r(:,:,:), ul_sol_th(:,:,:), ul_sol_z(:,:,:)

        ! Copias del ITERADO externo anterior para la sub-relajación (C2.1).
        ! Workspace persistente (save): se realoca solo si cambia el tamaño.
        real(dp), allocatable, save :: p_lur(:,:,:), p_lth(:,:,:), p_luz(:,:,:)
        real(dp), allocatable, save :: p_gur(:,:,:), p_gth(:,:,:), p_guz(:,:,:)
        real(dp), allocatable, save :: p_lT(:,:,:), p_gT(:,:,:)
        ! Referencia de T del gas para la fuente de compresibilidad (A3-3)
        real(dp), allocatable, save :: Tg_ref(:,:,:)
        ! Coeficiente de intercambio de momentum gas-líquido (C2.4)
        real(dp), allocatable, save :: Kexch(:,:,:)
        real(dp), allocatable, save :: drag_gas(:,:,:)
        integer :: i, j, k
        real(dp) :: uf, bm, rlo, rhi, sdir
        real(dp), parameter :: U_BEDL = 1.0e-3_dp

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
        ! (Plan H, P4) VISTA CONDENSADA acero+escoria para mascaras, momento y
        ! Poisson (la escoria es volumen desplazable, no tapa rigida: M17-PV1)
        cond = slag_condensed_on(cfg)
        ! (auditoria P4, bajo) el estado de inicio de paso lo fija main; un
        ! driver que llame sin el (tests) lo toma del estado actual
        if (cond .and. .not. allocated(ws_sp_asl)) then
            allocate(ws_sp_asl, ws_sp_es, mold=slag%alpha_sl)
            allocate(ws_sp_mx, mold=slag%m_X)
            ws_sp_asl = slag%alpha_sl; ws_sp_es = slag%E_sl; ws_sp_mx = slag%m_X
        end if
        if (cond) call cond_view_enter(liq, liq_old, slag%alpha_sl, ws_sp_asl, cfg%rho_slag, &
                                       cfg%beta_expansion, cfg%T_ref_boussinesq, cfg%mu_slag)
        call liquid_continuity_mask(liq, sol, m, ws_liq_cont)
        ! mascara del lecho (N-C1): misma regla que liq_continuous, halos
        ! incluidos (sol%alpha_s ya intercambiado; los halos fisicos tienen
        ! cell_type = 0)
        ws_bed = merge(1.0_dp, 0.0_dp, sol%alpha_s >= ALPHA_BED .and. m%cell_type /= 0)
        ws_bed_valid = .true.
        ws_liq_cont_valid = .true.
        ! (la mascara de presion de fluido, ws_pv_active, se fija mas abajo:
        !  necesita el arrastre de Ergun del gas para la percolacion, F2.16)
        ! Hueco de poro del liquido en el lecho (F2.8; ver ws_liq_room)
        if (cond) then
            ! condensado: la escoria ya esta en liq%alpha (vista)
            where (sol%alpha_s >= ALPHA_BED)
                ws_liq_room = liq_cap(sol%alpha_s, 0.0_dp) - liq%alpha
            elsewhere
                ws_liq_room = 1.0_dp
            end where
        else
        where (sol%alpha_s >= ALPHA_BED)
            ws_liq_room = liq_cap(sol%alpha_s, slag%alpha_sl) - liq%alpha
        elsewhere
            ws_liq_room = 1.0_dp
        end where
        end if
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
        call compute_ergun_drag(gas, sol, m, cfg, drag_gas, alpha_held=liq%alpha)

        ! Percolacion del gas (F2.16) y, con ella, las celdas que tienen
        ! presion de fluido (Bug 16). El gas atrapado no la tiene.
        if (cfg%pc_gas_spring) then
            ! Plan F (oct-2026): el gas es SIEMPRE fluido del acople. Una bolsa
            ! atrapada bajo el lecho inundado (B1 325 s: alpha_g 0.36 en el
            ! piso, sin camino al freeboard) no es una pared de presion
            ! (Neumann) sino un RESORTE: su fila lleva la compresibilidad
            ! alpha_g V/(P0 dt) y su presion sube al comprimirla y baja al
            ! drenarla. Medido en la serie densa base_dense325: 412 de 428
            ! celdas-snapshot con |p| > 100 kPa estan en k = 1-2 (bolsas y
            ! lecho denso del piso), con +550 kPa al llenarse y -535 kPa al
            ! vaciarse: es el volumen que la pared no absorbe cobrandose en
            ! la compresibilidad acustica del liquido. Hilfer (1998) dice que
            ! la subfase desconectada no propaga GRADIENTES, no que carezca
            ! de presion.
            ws_gas_perc = .true.; ws_gas_reach = .true.
            ws_gas_perc_valid = .true.
            ws_pv_active = (ws_liq_cont .or. gas%alpha > 0.0_dp) .and. (m%cell_type /= 0)
        else
            call gas_percolation_mask(gas, sol, m, cfg, drag_gas, ws_gas_perc, ws_gas_reach)
            ! (Plan H) con la escoria CONDENSADA el volumen sale por la cima de la
            ! escoria (gas real): sin canal residual de gas (F2.21) en las
            ! celdas con escoria, por donde el Poisson metia gas FANTASMA bajo la
            ! escoria (gas dentro del bano: ~1e-6 por paso y pico de succion)
            if (cond) ws_gas_reach = ws_gas_reach .and. (slag%alpha_sl < ALPHA_CUTOFF .or. &
                                                         gas%alpha >= ALPHA_FLOW_CUTOFF)
            ws_gas_perc_valid = .true.
            ws_pv_active = (ws_liq_cont .or. &
                            (gas%alpha >= ALPHA_FLOW_CUTOFF .and. ws_gas_perc)) &
                           .and. (m%cell_type /= 0)
        end if
        ws_pv_valid = .true.
        ! Lecho del GAS (A3-1): flotacion relativa solo para el gas que es
        ! fluido del acople (percola y esta en ws_pv_active) Y que es la fase
        ! CONTINUA del poro: peso 0 en el piso residual pore_floor(alpha_s)
        ! (poro saturado; ALPHA_PORE_GAS en el lecho pleno, rampa desde
        ! ALPHA_BED) y 1 desde el piso + ALPHA_PORE_GAS, lineal entre ambos
        ! (mezcla, no interruptor). El gas residual del poro saturado esta por encima de
        ! ALPHA_FLOW_CUTOFF a proposito (F2.7) y percola: con la forma
        ! clasica era una BOMBA de alpha_g (rho_l - rho_g) g que quitaba a la
        ! presion de poro el peso del liquido (bath_freeze: 31 -> 16 kPa en la
        ! capa saturada, gas de encima a 113 m/s) — la valvula ficticia de
        ! Plan E con motor. El atrapado conserva el gradiente reducido.
        ! Halos validos: gas%alpha intercambiado, ws_gas_perc/ws_pv_active
        ! con halos.
        ! (A4-1) rampa de saturacion comun; el gas ademas solo como fluido del
        ! acople (ver mod_workspace)
        ws_bed_liq = ws_bed * min(1.0_dp, max(0.0_dp, (gas%alpha - pore_floor(sol%alpha_s)) / ALPHA_PORE_GAS))
        ws_bed_gas = ws_bed_liq * merge(1.0_dp, 0.0_dp, &
            gas%alpha >= ALPHA_FLOW_CUTOFF .and. ws_gas_perc .and. ws_pv_active)
        ! Burbujas en el bano (A3-5; A4-8): celda de BANO (alpha_l >=
        ! ALPHA_LIQ_CONT, sin lecho) con gas que PUEDE deslizar (alpha_g >=
        ! ALPHA_FLOW_CUTOFF: con gas evanescente, atado al liquido, la
        ! flotacion del liquido no tenia contraparte y bath_test perdia el
        ! reposo, 0.13 m/s) y con BANO encima (alpha_l(k+1) >= ALPHA_LIQ_CONT,
        ! sin lecho: ni la superficie ni la pelicula son burbujas, M4-11). Sin
        ! condicion de percolacion (fuera del lecho el gas movil es fluido del
        ! acople, ver gas_percolation_mask). La mascara de CARA ws_bub_f es la
        ! de la celda inferior si la superior es bano INTERIOR (con liquido
        ! continuo encima): el frente avanza hacia bano sin gas y nunca hacia
        ! la celda de superficie. Celdas propias; halos intercambiados.
        ws_bub = 0.0_dp; ws_bub_f = 0.0_dp
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (liq%alpha(i,j,k) < ALPHA_LIQ_CONT .or. ws_bed(i,j,k) > 0.0_dp) cycle
                    if (m%cell_type(i,j,k+1) == 0) cycle
                    if (liq%alpha(i,j,k+1) < ALPHA_LIQ_CONT .or. ws_bed(i,j,k+1) > 0.0_dp) cycle
                    ws_bub(i,j,k) = min(1.0_dp, max(0.0_dp, &
                        (gas%alpha(i,j,k) - ALPHA_FLOW_CUTOFF) / ALPHA_FLOW_CUTOFF))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(ws_bub, m%topo)
        do k = 0, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (ws_bub(i,j,k) <= 0.0_dp) cycle
                    if (m%cell_type(i,j,k+2) == 0) cycle
                    if (.not. (ws_liq_cont(i,j,k+1) .and. ws_liq_cont(i,j,k+2))) cycle
                    if (ws_bed(i,j,k+1) > 0.0_dp) cycle
                    ws_bub_f(i,j,k) = ws_bub(i,j,k)
                end do
            end do
        end do
        call mpi_exchange_halos_3d(ws_bub_f, m%topo)
        ! Mascara de cara del liquido (A4-1; ver mod_workspace): caras
        ! (k|k+1) con k = 0..nz (la cara inferior de la celda 1 usa el halo)
        ws_bedl_f = 0.0_dp
        ws_bedg_f = 0.0_dp      ! (bajo B7-7) como ws_bedl_f: caras saltadas sin rancio
        do k = 0, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0 .or. m%cell_type(i,j,k+1) == 0) cycle
                    ! SUAVE en u_f (un interruptor en el signo rompia la
                    ! simetria 120 grados por el redondeo: T_gas 3.7e-5): del
                    ! minimo de las dos rampas en reposo al valor de la celda
                    ! receptora cuando |u_f| >> U_BEDL (1 mm/s)
                    uf = 0.5_dp * (liq%uz(i,j,k) + liq%uz(i,j,k+1))
                    rlo = min(ws_bed_liq(i,j,k), ws_bed_liq(i,j,k+1))
                    rhi = max(ws_bed_liq(i,j,k), ws_bed_liq(i,j,k+1))
                    if (ws_bed_liq(i,j,k+1) >= ws_bed_liq(i,j,k)) then
                        sdir = uf          ! la receptora de mayor rampa esta arriba
                    else
                        sdir = -uf
                    end if
                    bm = rlo + (rhi - rlo) * tanh(max(0.0_dp, sdir) / U_BEDL)
                    ws_bedl_f(i,j,k) = max(bm, ws_bub_f(i,j,k))
                    ! mascara de cara del gas (A4-1; explicita desde la
                    ! auditoria 6, una sola definicion: gas_face_mask)
                    ws_bedg_f(i,j,k) = gas_face_mask(ws_bed_gas(i,j,k), ws_bed_gas(i,j,k+1), ws_bub_f(i,j,k))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(ws_bedl_f, m%topo)
        call mpi_exchange_halos_3d(ws_bedg_f, m%topo)

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
                    ! F2.22 (2026-09-29): MEZCLA de morfologia (AIAD ecs.
                    ! 6-9), nunca un interruptor. TRES morfologias, dos
                    ! logisticas, como el f_B/f_D/f_FS de AIAD:
                    !
                    !   LECHO (goteo): hay esqueleto solido. El peso del
                    !     liquido lo lleva Ergun contra la chatarra y con el
                    !     gas solo hay cizalla de pelicula. K ~ 0.2 medido:
                    !     el gas de poro queda LIBRE para ventear, que es la
                    !     condicion de F2.13/F2.16.
                    !   INTERFASE RESUELTA (sin solido, liquido abundante):
                    !     cierre de Strubelj & Tiselj, alpha_l alpha_g
                    !     rho_MEZCLA/TAU_LG. Es lo que equilibra la flotacion
                    !     relativa alpha_q (rho_mez - rho_q) g de una celda
                    !     mixta (medido en bath_test: la sostiene con 0.09
                    !     m/s de deslizamiento).
                    !   DISPERSA (sin solido, poco liquido): arrastre fisico
                    !     de la gota a velocidad terminal.
                    !
                    ! Lo que sustituye: un interruptor sobre alpha_s que
                    ! saltaba una mediana de 1.5e8 veces al cruzar 1e-2. En
                    ! cuanto el arco perforaba el lecho la celda de bano
                    ! cambiaba de rama de golpe y el colapso se extendia a
                    ! toda la superficie (v33: 3 celdas a 250 s, 1143 a 400 s).
                    !
                    ! Por que la logistica del LECHO no se puede quitar
                    ! (medido, juez F2.22 de dos vias, 29-sep): sin ella el
                    ! gas de poro pasa de K/inercia 0.02 a 4.6 POR PASO (644x
                    ! la mediana), queda soldado al liquido inmovil del lecho,
                    ! no puede ventear, se calienta y su compresibilidad
                    ! integra presion: 4.5 -> 63 kPa lineales en 0.8 s.
                    al_c = liq%alpha(i,j,k)
                    ag_c = gas%alpha(i,j,k)
                    ! celda de abajo solo si existe (auditoria, bajos: en
                    ! k = 1 y sobre el tazon se leia el halo fisico)
                    as_e = sol%alpha_s(i,j,k)
                    if (m%cell_type(i,j,k-1) /= 0) as_e = max(as_e, sol%alpha_s(i,j,k-1))
                    xb = A_AIAD * (ALPHA_AIAD_LIM - as_e)
                    f_bed = 1.0_dp / (1.0_dp + exp(min(max(xb, -60.0_dp), 60.0_dp)))
                    xb = A_AIAD * (al_c - ALPHA_AIAD_LIM)
                    f_disp = 1.0_dp / (1.0_dp + exp(min(max(xb, -60.0_dp), 60.0_dp)))
                    rho_mix = (al_c * liq%rho(i,j,k) + ag_c * gas%rho(i,j,k)) &
                              / max(al_c + ag_c, SMALL)
                    K_int = al_c * ag_c * rho_mix / TAU_LG
                    if (ws_ut(i,j,k) > SMALL .and. al_c > 0.0_dp) then
                        K_disp = al_c * max(liq%rho(i,j,k) - gas%rho(i,j,k), &
                                            0.0_dp) * GRAVITY / ws_ut(i,j,k)
                    else
                        K_disp = 0.0_dp
                    end if
                    ! (auditoria 4, B4-25) en las celdas de burbuja el cierre
                    ! de interfase resuelta cede al arrastre de burbuja
                    ! (U_BUBBLE; ws_bub es 0 en la celda de superficie, que
                    ! conserva TAU_LG)
                    ! (auditoria 5, B5-10) la flotacion que el gas ve en la
                    ! forma balanceada es la RELATIVA alpha_g (rho_mez - rho_g) g
                    ! = alpha_g alpha_l (rho_l - rho_g) g, asi que el K que da
                    ! un deslizamiento U_BUBBLE lleva alpha_l (antes el
                    ! deslizamiento efectivo era alpha_l U_BUBBLE)
                    if (ws_bub(i,j,k) > 0.0_dp) then
                        K_int = (1.0_dp - ws_bub(i,j,k)) * K_int + ws_bub(i,j,k) * &
                                ag_c * al_c * max(liq%rho(i,j,k) - gas%rho(i,j,k), 0.0_dp) * GRAVITY / U_BUBBLE
                    end if
                    Kexch(i,j,k) = f_bed * fs_shear(i, j, k) &
                        + (1.0_dp - f_bed) * ((1.0_dp - f_disp) * K_int &
                                              + f_disp * K_disp)
                end do
            end do
        end do

        ! Liquid momentum
        call solve_momentum_3d(liq, liq_old, gas, Kexch, sh, m, cfg, liq%alpha, &
                               drag_coef, .false., res_ur_l, res_uth_l, res_uz_l, &
                               mdot_l=sol%mdot)
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
        ! Masa que las reacciones anaden al gas [kg/s por celda] (M24, gas):
        ! entra con velocidad nula
        allocate(md_g, mold=gas%alpha)
        md_g = max(sh%S_CO_src + sh%S_CO2_src + sh%S_O2_src, 0.0_dp) * m%vol
        call solve_momentum_3d(gas, gas_old, liq, Kexch, sh, m, cfg, gas%alpha, &
                               drag_gas, .true., res_ur_g, res_uth_g, res_uz_g, md_g)
        deallocate(md_g)
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
        ! D2.2b: el liquido de una celda sellada para el liquido (todas sus
        ! caras de liquido cerradas en el ultimo Poisson del paso) no se mueve
        if (cfg%pc_liq_sealed_wall .and. ws_pv_liq_valid .and. ws_pv_liq_id == probe_current_step()) then
            where (ws_liq_cont .and. .not. ws_pv_liq)
                liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
            end where
        end if
        ! D2.6 (regla cinematica por direccion): sin cara de liquido abierta
        ! en una direccion, esa componente es nula (ver mod_pressure_3d)
        if (cfg%pc_liq_closed_dir .and. ws_pv_liq_valid .and. ws_pv_liq_id == probe_current_step()) then
            where (ws_liq_cont .and. .not. ws_liq_fr)  liq%ur  = 0.0_dp
            where (ws_liq_cont .and. .not. ws_liq_fth) liq%uth = 0.0_dp
            where (ws_liq_cont .and. .not. ws_liq_fz)  liq%uz  = 0.0_dp
        end if
        call phase_exchange_halos(liq, m)
        call relax_field(gas%ur,  p_gur, cfg%alpha_u, m)
        call relax_field(gas%uth, p_gth, cfg%alpha_u, m)
        call relax_field(gas%uz,  p_guz, cfg%alpha_u, m)
        call cap_gas_velocity(gas, m)

        ! Exchange halos after momentum
        call phase_exchange_halos(gas, m)

        ! Plan E E2 (oct-2026): CORRECTOR INTERNO alpha <-> p. Cada pasada es
        ! una correccion de presion completa (p += alpha_p pp, u -= d grad pp,
        ! flujos conservativos exportados) seguida del transporte de alpha
        ! desde alpha_old con esos flujos; el transporte deja en ws_pc_unl la
        ! fuente de goteo/derrame y en ws_lim_step lo que cupo, y la pasada
        ! siguiente los ve. Sale cuando alpha deja de cambiar entre pasadas
        ! (tol_alpha_pc) o en n_pc_max. Es el lazo alpha-presion de
        ! NEPTUNE_CFD (Guelfi 2007) con el momento rezagado; n_pc_max = 1
        ! es el algoritmo segregado de siempre, bit a bit.
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        if (cfg%n_pc_max > 1) allocate(a_prev, mold=liq%alpha)
        dalpha_pc = 0.0_dp
        do ic = 1, max(1, cfg%n_pc_max)
        if (cond .and. .not. ws_cond_on) call cond_view_enter(liq, liq_old, slag%alpha_sl, ws_sp_asl, &
                                       cfg%rho_slag, cfg%beta_expansion, cfg%T_ref_boussinesq, cfg%mu_slag)
        ! Pressure correction de MEZCLA: ambas fases contribuyen y ambas
        ! se corrigen (C2.4)
        ! Referencia de la fuente de compresibilidad (auditoria 3, A3-3): la T
        ! del gas al FINAL del SIMPLE anterior (sh%Tg_end), no gas_old%T. Entre
        ! ambas estan la interfase gas-solido (update_solid_postenergy) y el
        ! intercambio gas-liquido, que calientan el gas DESPUES del Poisson:
        ! medida contra gas_old%T esa expansion no pasaba por ningun Poisson
        ! (la EOS reescribia la masa del gas sin fuente de volumen; es el
        ! mecanismo de F2.13 y lo que Plan G ya corregia con Tg_end). Sin
        ! Tg_end (arranque, reinicio de un snapshot viejo, solve_flow off) se
        ! usa gas_old%T.
        if (.not. allocated(Tg_ref)) allocate(Tg_ref, mold=gas%T)
        where (sh%Tg_end > 0.0_dp)
            Tg_ref = sh%Tg_end
        elsewhere
            Tg_ref = gas_old%T
        end where
        call solve_pressure_correction(liq, gas, Tg_ref, sh, m, cfg, res_ic)
        ! el residual del lazo externo es el del iterado ENTRANTE (Bug 20)
        if (ic == 1) res_cont = res_ic

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
            if (cfg%n_pc_max > 1) a_prev = liq%alpha
            if (cond) then
                ! (Plan H) fuera de la vista: transporte condensado acero+escoria
                ! desde el estado de inicio de paso (liq_old acero, ws_sp_*)
                call cond_view_exit(liq, liq_old)
                if (cfg%n_pc_max > 1) a_prev = liq%alpha
                call solve_condensed_fraction(liq, gas, sol, slag, ws_sp_asl, ws_sp_es, &
                                              ws_sp_mx, liq_old%alpha, m, cfg)
            else
            call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, &
                                       liq_old%alpha, m, cfg)
            end if
            ! Exchange after volume fraction update
            call phase_exchange_halos(liq, m)
            call phase_exchange_halos(gas, m)
            if (cfg%n_pc_max > 1) then
                ! (auditoria 4, B4-11) el hueco de poro que ve la pasada
                ! siguiente (fsat, limitador de F2.8, F2.29) es el de la alpha
                ! recien transportada; las mascaras de CARA (ws_bedl_f) siguen
                ! fijas por iteracion externa a proposito (A4-1)
                if (cond) then
                    where (sol%alpha_s >= ALPHA_BED)
                        ws_liq_room = liq_cap(sol%alpha_s, 0.0_dp) - (liq%alpha + slag%alpha_sl)
                    elsewhere
                        ws_liq_room = 1.0_dp
                    end where
                else
                where (sol%alpha_s >= ALPHA_BED)
                    ws_liq_room = liq_cap(sol%alpha_s, slag%alpha_sl) - liq%alpha
                elsewhere
                    ws_liq_room = 1.0_dp
                end where
                end if
                dalpha_loc = maxval(abs(liq%alpha(istart:iend,jstart:jend,kstart:kend) &
                                      - a_prev(istart:iend,jstart:jend,kstart:kend)))
                if (m%is_parallel) then
                    call mpi_allreduce_max(dalpha_loc, dalpha_pc, m%topo)
                else
                    dalpha_pc = dalpha_loc
                end if
                if (dalpha_pc < cfg%tol_alpha_pc) exit
            end if
        else
            exit
        end if
        end do
        n_pc_used = min(ic, max(1, cfg%n_pc_max))
        conv%n_pc = n_pc_used; conv%dalpha_pc = dalpha_pc
        if (cfg%n_pc_max > 1) deallocate(a_prev)

        call probe_report('post-alpha    ', liq, gas, sol, sh, m, cfg)

        ! Energy
        if (cfg%solve_energy) then
            call solve_energy_3d(liq, liq_old%T, sh, m, cfg, liq%alpha, &
                                 gas%alpha, liq_old%alpha, sol%mdot, ws_Tsrc, &
                                 .false., res_energy_l)
            call relax_field(liq%T, p_lT, cfg%alpha_T, m)
            call phase_exchange_halos(liq, m)

            ! gas: alpha_old no se usa (forma T con rho(T)); se pasa la
            ! fracción actual por uniformidad de la interfaz
            call solve_energy_3d(gas, gas_old%T, sh, m, cfg, gas%alpha, &
                                 liq%alpha, gas%alpha, sol%mdot, ws_Tsrc, &
                                 .true., res_energy_g)
            call relax_field(gas%T, p_gT, cfg%alpha_T, m)
            call phase_exchange_halos(gas, m)
        else
            res_energy_l = 0.0_dp
            res_energy_g = 0.0_dp
        end if

        ! Update properties (+ halos: las especies del paso siguiente leian
        ! gas%rho rancio en las fronteras de rank; auditoria 2, N-M8)
        call update_properties(liq, gas, sh, m, cfg)
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)

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
            ! gradiente de alpha_l con diferencias UNILATERALES junto a celdas
            ! inactivas (pared: sin interfase). Auditoria (bajos): antes se
            ! leian los halos fisicos y las celdas del tazon como si fueran
            ! fluido
            gr_  = g1(liq%alpha(ii-1,jj,kk), liq%alpha(ii,jj,kk), liq%alpha(ii+1,jj,kk), &
                      m%cell_type(ii-1,jj,kk) /= 0, m%cell_type(ii+1,jj,kk) /= 0, &
                      m%r(ii) - m%r(ii-1), m%r(ii+1) - m%r(ii))
            gth_ = g1(liq%alpha(ii,jj-1,kk), liq%alpha(ii,jj,kk), liq%alpha(ii,jj+1,kk), &
                      m%cell_type(ii,jj-1,kk) /= 0, m%cell_type(ii,jj+1,kk) /= 0, &
                      m%r(ii) * (m%theta(jj) - m%theta(jj-1)), m%r(ii) * (m%theta(jj+1) - m%theta(jj)))
            gz_  = g1(liq%alpha(ii,jj,kk-1), liq%alpha(ii,jj,kk), liq%alpha(ii,jj,kk+1), &
                      m%cell_type(ii,jj,kk-1) /= 0, m%cell_type(ii,jj,kk+1) /= 0, &
                      m%z(kk) - m%z(kk-1), m%z(kk+1) - m%z(kk))
            ga = sqrt(gr_*gr_ + gth_*gth_ + gz_*gz_)
            K = C_FS_SHEAR * gas%rho(ii,jj,kk) * du * ga
        end function fs_shear

        pure function g1(am, ac, ap, okm, okp, dm, dpl) result(g)
            real(dp), intent(in) :: am, ac, ap, dm, dpl
            logical, intent(in)  :: okm, okp
            real(dp) :: g
            if (okm .and. okp) then
                g = (ap - am) / max(dm + dpl, SMALL)
            else if (okp) then
                g = (ap - ac) / max(dpl, SMALL)
            else if (okm) then
                g = (ac - am) / max(dm, SMALL)
            else
                g = 0.0_dp
            end if
        end function g1

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
        real(dp) :: KV, al, ag
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        ! (M11-1pv) aP de cada fase ANTES de la eliminacion, para que F2.31 la
        ! reevalue con los transitorios a DT_MOB_REF
        ws_pea_kv = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (.not. ws_liq_cont(i,j,k)) cycle
                    if (gas%alpha(i,j,k) < ALPHA_FLOW_CUTOFF) cycle
                    KV = Kexch(i,j,k) * m%vol(i,j,k)
                    if (KV <= SMALL) cycle
                    al = liq%alpha(i,j,k); ag = gas%alpha(i,j,k)
                    ws_pea_kv(i,j,k) = KV; ws_pea_al(i,j,k) = al; ws_pea_ag(i,j,k) = ag
                    ws_peal_r(i,j,k) = liq%aP_ur(i,j,k);  ws_peag_r(i,j,k) = gas%aP_ur(i,j,k)
                    ws_peal_th(i,j,k) = liq%aP_uth(i,j,k); ws_peag_th(i,j,k) = gas%aP_uth(i,j,k)
                    ws_peal_z(i,j,k) = liq%aP_uz(i,j,k);  ws_peag_z(i,j,k) = gas%aP_uz(i,j,k)
                    call pea2(liq%ur(i,j,k),  gas%ur(i,j,k),  liq%aP_ur(i,j,k),  gas%aP_ur(i,j,k),  KV, ug_r(i,j,k),  ul_r(i,j,k))
                    call pea2(liq%uth(i,j,k), gas%uth(i,j,k), liq%aP_uth(i,j,k), gas%aP_uth(i,j,k), KV, ug_th(i,j,k), ul_th(i,j,k))
                    call pea2(liq%uz(i,j,k),  gas%uz(i,j,k),  liq%aP_uz(i,j,k),  gas%aP_uz(i,j,k),  KV, ug_z(i,j,k),  ul_z(i,j,k))
                end do
            end do
        end do
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)
    contains
        ! PEA de dos fases + coeficientes de presion CONSISTENTES (auditoria
        ! M30; Karema & Lo, Powder Technol. 1999): del sistema acoplado
        !   a_l u_l - KV u_g = -alpha_l V grad p + ...
        !   a_g u_g - KV u_l = -alpha_g V grad p + ...
        ! la respuesta de cada fase a la presion es
        !   d_l = V (alpha_l a_g + KV alpha_g)/det, d_g = V (alpha_g a_l + KV alpha_l)/det
        ! y el Poisson y el corrector (d = alpha V/aP) reciben el aP
        ! equivalente alpha V/d. Antes usaban el aP de cada fase por separado:
        ! con K grande las fases se mueven juntas (d -> d de la mezcla) pero el
        ! Poisson veia cada una frenada por K.
        subroutine pea2(ul, ug, apl, apg, KV, ug_used, ul_used)
            real(dp), intent(inout) :: ul, ug, apl, apg
            real(dp), intent(in)    :: KV, ug_used, ul_used
            real(dp) :: Hl, Hg, det
            if (apl <= SMALL .or. apg <= SMALL) return
            det = apl * apg - KV * KV
            if (det <= SMALL) return
            Hl = apl * ul - KV * ug_used
            Hg = apg * ug - KV * ul_used
            ul = (apg * Hl + KV * Hg) / det
            ug = (apl * Hg + KV * Hl) / det
            ! (A12-T3) aP equivalentes: una sola definicion (mod_constants)
            call pea_coeffs(apl, apg, KV, al, ag, Hl, Hg)
            apl = Hl; apg = Hg
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
    !     mob = (alpha_g rho_g/dt_ref)/(alpha_g rho_g/dt_ref + drag) >
    !     GAS_MOB_MIN, con dt_ref = min(dt, DT_MOB_REF) (M8-2, auditoria 13);
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
                    ! (auditoria 13) el paso del juicio es min(dt, DT_MOB_REF):
                    ! nunca mayor que el de calibracion (con dt grande el gas de
                    ! piso de una capa saturada quedaba inmovil: M8-2), y con
                    ! dt < 2 ms el real (el regimen de B1 tal como se calibro)
                    tr = gas%alpha(i,j,k) * gas%rho(i,j,k) / min(cfg%dt, DT_MOB_REF)
                    mob = tr / max(tr + max(drag_gas(i,j,k), 0.0_dp), SMALL)
                    if (mob > GAS_MOB_MIN) mob_loc(i,j,k) = 1
                end do
            end do
        end do
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (sol%alpha_s(i,j,k) < ALPHA_BED) free_loc(i,j,k) = 1
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
                    ! (auditoria 4, A4-8) FUERA del lecho el gas movil es
                    ! fluido del acople aunque no tenga camino al freeboard:
                    ! una burbuja en el bano sube desplazando liquido (el
                    ! Poisson de volumen lo resuelve); Hilfer es un criterio
                    ! de medio poroso y fuera del lecho no aplica (la bolsa
                    ! aislada quedaba pared y sin flotacion para siempre)
                    perc(i,j,k) = (seen(ig,jg,kg) == 1) .or. &
                                  (free_g(ig,jg,kg) == 1 .and. mob_g(ig,jg,kg) == 1)
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
