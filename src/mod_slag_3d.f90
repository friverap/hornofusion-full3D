!===============================================================================
! mod_slag_3d.f90 - Slag layer (capa de escoria) pseudo-phase for EAF simulator
!
! Slag modeled as a tracked pseudo-phase (like solid_t) — NOT a full Eulerian
! N-S phase.  Physics:
!   1. Buoyancy:  slag rises above co-located liquid (local k-sweep, 3 passes)
!   2. Arc heat interception: slag absorbs alpha_sl fraction of S_arc
!   3. Heat exchange: slag <-> liquid (below) and slag <-> gas (same cell)
!   4. Volume constraint: gas fraction reduced where slag occupies cells
!===============================================================================
module mod_slag_3d
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology, only: mpi_allreduce_max, mpi_allreduce_sum, mpi_exchange_halos_3d
    use mod_parallel_utils, only: gather_global_field, global_to_local, should_print
    use mod_fields_3d, only: slag_exchange_halos
    use mod_audit, only: audit_add, audit_gas_destroyed, AUD_FLUX_MASS, AUD_FLUX_E, AUD_SLAG_INTERCEPT, AUD_SLAG_TCLIP, &
                         AUD_SLAG_GAS, AUD_SLAG_LIQ, AUD_GAS_VOLFIX, AUD_GAS_VOLFIX_E, &
                         gas_inventory_cell, gas_heat_capacity_ref, gas_log_exchange
    implicit none

    real(dp), parameter :: SMALL_SL = 1.0e-6_dp

contains

    !---------------------------------------------------------------------------
    ! Place initial slag layer just above the scrap surface
    !---------------------------------------------------------------------------
    ! T de la escoria desde su entalpia con piso de 300 K; si el piso actua,
    ! E_sl se lleva al valor COHERENTE y la energia inyectada se audita
    ! (auditoria, bajos: antes se recortaba T sin tocar E_sl)
    subroutine slag_T_from_E(slag, i, j, k, cfg)
        type(slag_t), intent(inout) :: slag
        integer, intent(in)         :: i, j, k
        type(config_t), intent(in)  :: cfg
        real(dp) :: E_min
        E_min = slag%m_sl(i,j,k) * cfg%cp_slag * 300.0_dp
        if (slag%E_sl(i,j,k) < E_min) then
            call audit_add(AUD_SLAG_TCLIP, E_min - slag%E_sl(i,j,k))
            slag%E_sl(i,j,k) = E_min
        end if
        slag%T_sl(i,j,k) = slag%E_sl(i,j,k) / (slag%m_sl(i,j,k) * cfg%cp_slag)
    end subroutine slag_T_from_E

    subroutine slag_initialize(slag, sol, liq, gas, m, cfg)
        type(slag_t),  intent(inout) :: slag
        type(solid_t), intent(in)    :: sol
        type(phase_t), intent(in)    :: liq
        type(phase_t), intent(inout) :: gas
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg

        integer  :: i, j, k, k_global, k_local
        integer  :: istart, iend, jstart, jend, kstart, kend, nz_global
        integer  :: k_top_local, k_top_global
        real(dp) :: k_top_real, k_top_real_global
        real(dp) :: avail_vol, alpha_add, vol_target
        real(dp) :: vol_local, vol_global, scale_fac
        ! (auditoria 17, M17-1) la escoria inicial es la de la colada anterior:
        ! con talon, a la T del talon (antes a T_initial: 300 K sobre la
        ! chatarra fria en produccion); sin talon, a T_initial
        real(dp) :: T_sl0

        ! Loop bounds
        T_sl0 = cfg%T_initial
        if (cfg%heel_mass > 0.0_dp) T_sl0 = cfg%heel_T
        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
            nz_global = m%topo%nz_global
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
            nz_global = m%nz
        end if

        ! Find local highest k with MATERIAL (scrap or liquid bath): en el
        ! modo de carga continua con baño plano no hay cestas y la escoria
        ! flota sobre el LÍQUIDO (fallback E2.3; antes solo chatarra y con
        ! horno sin cestas quedaba V_slag = 0)
        k_top_local = 0
        do k = kend, kstart, -1
            if (any(sol%alpha_s(istart:iend, jstart:jend, k) > ALPHA_BED) &
                .or. any(liq%alpha(istart:iend, jstart:jend, k) > 0.01_dp)) then
                if (m%is_parallel) then
                    k_top_local = k + m%topo%kglobal_start - 1
                else
                    k_top_local = k
                end if
                exit
            end if
        end do

        ! Global max k_top across all ranks
        if (m%is_parallel) then
            k_top_real = real(k_top_local, dp)
            call mpi_allreduce_max(k_top_real, k_top_real_global, m%topo)
            k_top_global = nint(k_top_real_global)
        else
            k_top_global = k_top_local
        end if

        ! Fall back to bottom k if no scrap found (pre-charge run)
        if (k_top_global < 1) k_top_global = 0

        vol_target = cfg%m_slag_init / cfg%rho_slag   ! ~1.18 m³

        ! Pass 1: fill cells immediately above scrap (up to 3 k-levels)
        vol_local = 0.0_dp
        do k_global = k_top_global + 1, min(k_top_global + 3, nz_global)
            ! Map global k to local k
            if (m%is_parallel) then
                k_local = k_global - m%topo%kglobal_start + 1
                if (k_local < kstart .or. k_local > kend) cycle
            else
                k_local = k_global
                if (k_local < kstart .or. k_local > kend) cycle
            end if

            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i, j, k_local) /= 1) cycle
                    avail_vol = (1.0_dp - sol%alpha_s(i, j, k_local)) * m%vol(i, j, k_local)
                    if (avail_vol < SMALL_SL) cycle

                    alpha_add = avail_vol / m%vol(i, j, k_local)
                    slag%alpha_sl(i, j, k_local) = alpha_add
                    slag%m_sl(i, j, k_local)     = cfg%rho_slag * avail_vol
                    slag%T_sl(i, j, k_local)     = T_sl0
                    slag%E_sl(i, j, k_local)     = slag%m_sl(i, j, k_local) * cfg%cp_slag * T_sl0
                    gas%alpha(i, j, k_local)     = max(0.0_dp, gas%alpha(i, j, k_local) - alpha_add)
                    vol_local = vol_local + avail_vol
                end do
            end do
        end do

        ! Global total volume placed
        if (m%is_parallel) then
            call mpi_allreduce_sum(vol_local, vol_global, m%topo)
        else
            vol_global = vol_local
        end if

        ! Scale to hit m_slag_init exactly (can only scale down, not up)
        if (vol_global > SMALL_SL) then
            scale_fac = min(1.0_dp, vol_target / vol_global)

            do k_global = k_top_global + 1, min(k_top_global + 3, nz_global)
                if (m%is_parallel) then
                    k_local = k_global - m%topo%kglobal_start + 1
                    if (k_local < kstart .or. k_local > kend) cycle
                else
                    k_local = k_global
                    if (k_local < kstart .or. k_local > kend) cycle
                end if

                do j = jstart, jend
                    do i = istart, iend
                        if (slag%alpha_sl(i, j, k_local) < SMALL_SL) cycle
                        ! Restore gas, then re-remove with scaled fraction
                        gas%alpha(i, j, k_local) = gas%alpha(i, j, k_local) &
                                                    + slag%alpha_sl(i, j, k_local)
                        slag%alpha_sl(i, j, k_local) = slag%alpha_sl(i, j, k_local) * scale_fac
                        slag%m_sl(i, j, k_local)     = cfg%rho_slag * slag%alpha_sl(i, j, k_local) &
                                                        * m%vol(i, j, k_local)
                        slag%E_sl(i, j, k_local)     = slag%m_sl(i, j, k_local) * cfg%cp_slag &
                                                        * T_sl0
                        gas%alpha(i, j, k_local)     = max(0.0_dp, gas%alpha(i, j, k_local) &
                                                            - slag%alpha_sl(i, j, k_local))
                    end do
                end do
            end do
            vol_global = vol_global * scale_fac
        end if

        ! Composición inicial (E2.1): fracciones de config aplicadas a la
        ! masa final de cada celda (el resto queda como inerte)
        do k_local = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (slag%m_sl(i,j,k_local) < SMALL_SL) cycle
                    slag%m_X(i,j,k_local,SL_FEO)  = cfg%slag_x_feo_init  * slag%m_sl(i,j,k_local)
                    slag%m_X(i,j,k_local,SL_CAO)  = cfg%slag_x_cao_init  * slag%m_sl(i,j,k_local)
                    slag%m_X(i,j,k_local,SL_SIO2) = cfg%slag_x_sio2_init * slag%m_sl(i,j,k_local)
                    slag%m_X(i,j,k_local,SL_MGO)  = cfg%slag_x_mgo_init  * slag%m_sl(i,j,k_local)
                end do
            end do
        end do

        if (.not. m%is_parallel .or. m%topo%rank == 0) then
            print '(A,ES10.3,A,ES10.3,A)', &
                ' [SLAG] Initialized: V_slag=', vol_global, &
                ' m³  m_slag=', vol_global * cfg%rho_slag, ' kg'
        end if

    end subroutine slag_initialize

    !---------------------------------------------------------------------------
    ! Intercepción del calor del arco por la escoria (C1.6b, hallazgo 3.1d).
    ! Debe llamarse INMEDIATAMENTE después de distribuir S_arc y ANTES de que
    ! las ecuaciones de energía lo consuman. La versión anterior interceptaba
    ! al final del paso, cuando los fluidos ya habían absorbido el 100% de
    ! S_arc (y éste se regenera al paso siguiente): la escoria creaba energía.
    !---------------------------------------------------------------------------
    subroutine slag_intercept_arc(slag, liq, gas, sh, m, cfg, S_rad)
        type(slag_t),  intent(inout) :: slag
        ! fluidos de la celda: el reparto es por ABSORCION (auditoria, bajos;
        ! F2.30): w = (k_sl a_sl + k_f a_foam)/(... + k_l a_l + k_g a_g), el
        ! mismo criterio con que la energia reparte S_arc entre liquido y gas.
        ! Antes: fraccion de VOLUMEN alpha_sl (y sin la espuma)
        type(phase_t), intent(in)    :: liq, gas
        type(shared_t),intent(inout) :: sh
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        ! (oct-2026, dirigida del modelo termico M1) la parte RADIATIVA del
        ! S_arc (la que deposito el MC): solo ella la intercepta la escoria.
        ! P_elec y P_conv van al metal por la cavidad del arco aunque la
        ! celda sea mixta (antes la escoria se llevaba su fraccion kappa de
        ! TODO el S_arc: hasta el 30 % del arco en arc_slag). Sin el
        ! argumento, todo el S_arc (comportamiento anterior).
        real(dp), intent(in), optional :: S_rad(-1:,-1:,-1:)

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: dE, ksl, kfl, w, sa, fb

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%alpha_sl(i,j,k) < SMALL_SL) cycle
                    if (slag%m_sl(i,j,k)     < SMALL_SL) cycle

                    ksl = KAPPA_SLAG_ABS * slag%alpha_sl(i,j,k) &
                        + KAPPA_FOAM_ABS * slag%alpha_foam(i,j,k)
                    kfl = KAPPA_LIQ_ABS * max(liq%alpha(i,j,k), 0.0_dp) &
                        + KAPPA_GAS_ABS * max(gas%alpha(i,j,k), 0.0_dp)
                    w = ksl / (ksl + kfl + SMALL)
                    sa = sh%S_arc(i,j,k)
                    ! (dirigida M1-M4, Medio 1) P_elec/P_conv van al METAL por
                    ! la cavidad si la celda tiene bano continuo (rampa 0.2-0.4
                    ! en alpha_l); en una
                    ! celda sin el (poros de chatarra llenos de escoria) la
                    ! escoria se lleva su parte kappa de todo el S_arc: si no,
                    ! el gas de poro (alpha_g 0.015) lo recibia entero
                    ! rampa 0.2-0.4 en alpha_l (la de M4-7), no un corte duro
                    ! en ALPHA_LIQ_CONT (dirigida de 126c426, bajo 1)
                    if (present(S_rad)) then
                        fb = min(1.0_dp, max(0.0_dp, (liq%alpha(i,j,k) - 0.2_dp) / 0.2_dp))
                        sa = min(max(S_rad(i,j,k), 0.0_dp), sh%S_arc(i,j,k))
                        sa = sa + (1.0_dp - fb) * (sh%S_arc(i,j,k) - sa)
                    end if
                    dE = sa * w * m%vol(i,j,k) * cfg%dt
                    slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + dE
                    sh%S_arc(i,j,k)  = sh%S_arc(i,j,k) - sa * w
                    call audit_add(AUD_SLAG_INTERCEPT, dE)

                    call slag_T_from_E(slag, i, j, k, cfg)
                end do
            end do
        end do
    end subroutine slag_intercept_arc

    !---------------------------------------------------------------------------
    ! Timestep update: buoyancy settling + energy exchange
    !---------------------------------------------------------------------------
    !---------------------------------------------------------------------------
    ! Adiciones a la escoria (E2.2): cal/dolomita (CaO+MgO) y carbón
    ! inyectado (SL_C). Reparto MPI-invariante proporcional a la masa de
    ! escoria de cada celda (dm_cell = dm * m_sl_cell / m_sl_global, una
    ! allreduce). Entran a T_ambient: entalpía sensible auditada
    ! (AUD_FLUX_MASS / AUD_FLUX_E, columnas m_flux_in / E_flux_in).
    !---------------------------------------------------------------------------
    subroutine slag_additions(slag, m, cfg, mdot_cal, mdot_cinj, dt)
        type(slag_t), intent(inout) :: slag
        type(mesh_t), intent(in)    :: m
        type(config_t), intent(in)  :: cfg
        real(dp), intent(in)        :: mdot_cal, mdot_cinj, dt

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: msl_loc, msl_glob, w, dm_cal, dm_c, dm_cell, de
        logical, save :: warned_noslag = .false.

        if (mdot_cal <= 0.0_dp .and. mdot_cinj <= 0.0_dp) return

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        msl_loc = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    msl_loc = msl_loc + slag%m_sl(i,j,k)
                end do
            end do
        end do
        if (m%is_parallel) then
            call mpi_allreduce_sum(msl_loc, msl_glob, m%topo)
        else
            msl_glob = msl_loc
        end if
        if (msl_glob <= SMALL_SL) then   ! sin capa donde depositar
            ! (auditoria dirigida de 147fad5) aviso UNA vez: sin escoria (sin
            ! talon ni escoria inicial) la adicion se descarta y la escoria
            ! nunca llega a formarse (no hay via que la cree desde cero)
            if (.not. warned_noslag .and. should_print(m)) print '(A,ES10.3,A)', &
                ' [SLAG] AVISO: adicion de ', (mdot_cal + mdot_cinj) * dt, &
                ' kg descartada: no hay escoria donde depositarla (m_slag_init 0 sin talon)'
            warned_noslag = .true.
            return
        end if

        dm_cal = mdot_cal  * dt
        dm_c   = mdot_cinj * dt

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%m_sl(i,j,k) <= SMALL_SL) cycle
                    w = slag%m_sl(i,j,k) / msl_glob
                    dm_cell = (dm_cal + dm_c) * w
                    slag%m_X(i,j,k,SL_CAO) = slag%m_X(i,j,k,SL_CAO) + &
                        dm_cal * w * cfg%cal_frac_cao
                    slag%m_X(i,j,k,SL_MGO) = slag%m_X(i,j,k,SL_MGO) + &
                        dm_cal * w * cfg%cal_frac_mgo
                    ! el resto de la cal (impurezas) queda como inerte
                    slag%m_X(i,j,k,SL_C)   = slag%m_X(i,j,k,SL_C) + dm_c * w
                    slag%m_sl(i,j,k) = slag%m_sl(i,j,k) + dm_cell
                    de = dm_cell * cfg%cp_slag * cfg%T_ambient
                    slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + de
                    call audit_add(AUD_FLUX_MASS, dm_cell)
                    call audit_add(AUD_FLUX_E, de)
                end do
            end do
        end do
    end subroutine slag_additions

    subroutine update_slag(slag, liq, gas, sol, m, cfg, dt, sh)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        real(dp),      intent(in)    :: dt
        ! p para el inventario del gas (M4-13); especies del gas creado (M5-5)
        type(shared_t), intent(inout), optional :: sh

        if (slag_condensed_on(cfg)) then
            ! (Plan H) la escoria es condensado: flotacion neutra en volumen
            call slag_condensed_sort(slag, liq, gas, sol, m, cfg, sh)
        else
            call slag_buoyancy(slag, liq, gas, sol, m, cfg, sh)
        end if
        call slag_energy(slag, liq, gas, m, cfg, dt, sh)
    end subroutine update_slag

    !---------------------------------------------------------------------------
    ! (Plan H, P3) FLOTACION CONDENSADA: reordenamiento NEUTRO EN VOLUMEN de la
    ! composicion acero/escoria dentro de cada SEGMENTO CONDENSADO contiguo de
    ! cada columna global (celdas con alpha_c = alpha_l + alpha_sl >=
    ! ALPHA_FLOW_CUTOFF). Conserva alpha_c de cada celda (no crea ni destruye
    ! gas: sin volfix): el acero llena de abajo arriba y la escoria encima.
    ! Remapeo lagrangiano: cada parcela de acero lleva su T (cp_l constante:
    ! energia exacta) y cada parcela de escoria su E_sl y m_X (M17-arc1). Un
    ! segmento ya ordenado no se reescribe (sin ruido de redondeo). Patron
    ! invariante MPI: gather global, mismo barrido, escritura de celdas propias.
    !---------------------------------------------------------------------------
    subroutine slag_condensed_sort(slag, liq, gas, sol, m, cfg, sh, a_pend)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        type(shared_t), intent(inout), optional :: sh
        ! (auditoria 18, A18-4) volumen del FUNDIDO PENDIENTE del paso
        ! (max(mdot,0) dt/(rho_l V)): entra a alpha_l en el transporte, asi
        ! que la compactacion no lo ocupa y el gas complemento no lo rellena
        ! (sin esto: el gas fantasma de N-M4 en celdas que funden bajo la
        ! escoria). Solo en la llamada de inicio de paso
        real(dp), intent(in), optional :: a_pend(-1:,-1:,-1:)
        real(dp), allocatable :: ap_g(:,:,:)
        ! (compactacion) en los segmentos CON escoria el condensado llena de
        ! abajo arriba hasta la capacidad de cada celda (liq_cap(alpha_s,0)): el
        ! gas atrapado bajo la escoria sube a la cima del segmento (el transporte
        ! deja ~1e-6 por paso en la celda de interfaz y crecia hasta el pico de
        ! succion de F2.16). El gas reubicado se audita como el volfix.
        real(dp), allocatable :: ss_g(:,:,:), acn(:,:,:)
        real(dp) :: vcond, capk, ag_new, dmg, deg, pc, fdil, capsum, as_m
        logical  :: has_slag
        integer  :: k2e, kc

        real(dp), allocatable :: al_g(:,:,:), tl_g(:,:,:), as_g(:,:,:), ms_g(:,:,:), es_g(:,:,:)
        real(dp), allocatable :: x_g(:,:,:,:), tmp(:,:,:)
        real(dp), allocatable :: al_n(:,:,:), tl_n(:,:,:), as_n(:,:,:), ms_n(:,:,:), es_n(:,:,:), x_n(:,:,:,:)
        logical,  allocatable :: chg(:,:,:)
        integer  :: i, j, k, k1, k2, kk, ko, c, il, jl, kl
        logical  :: owned, ordered, seen_slag
        real(dp) :: vst, cap, s_need, d, rem, vt, ac, vc

        allocate(al_g(m%nr_g, m%nth_g, m%nz_g), tl_g(m%nr_g, m%nth_g, m%nz_g), as_g(m%nr_g, m%nth_g, m%nz_g))
        allocate(ms_g(m%nr_g, m%nth_g, m%nz_g), es_g(m%nr_g, m%nth_g, m%nz_g))
        allocate(x_g(m%nr_g, m%nth_g, m%nz_g, N_SLAG_COMP))
        allocate(tmp, mold=slag%m_sl)
        allocate(ss_g(m%nr_g, m%nth_g, m%nz_g), acn(m%nr_g, m%nth_g, m%nz_g))
        call gather_global_field(sol%alpha_s, ss_g, m)
        allocate(ap_g(m%nr_g, m%nth_g, m%nz_g)); ap_g = 0.0_dp
        if (present(a_pend)) call gather_global_field(a_pend, ap_g, m)
        call gather_global_field(liq%alpha, al_g, m)
        call gather_global_field(liq%T, tl_g, m)
        call gather_global_field(slag%alpha_sl, as_g, m)
        call gather_global_field(slag%m_sl, ms_g, m)
        call gather_global_field(slag%E_sl, es_g, m)
        do c = 1, N_SLAG_COMP
            tmp = slag%m_X(:,:,:,c)
            call gather_global_field(tmp, x_g(:,:,:,c), m)
        end do
        allocate(al_n, tl_n, as_n, ms_n, es_n, mold=al_g)
        allocate(x_n, mold=x_g); allocate(chg(m%nr_g, m%nth_g, m%nz_g))
        chg = .false.; dmg = 0.0_dp; deg = 0.0_dp
        ! (P5) la escoria ocupa el VOLUMEN DE SU MASA: las fuentes (quimica,
        ! adiciones) cambian m_sl, E_sl y m_X sin tocar alpha_sl; aqui
        ! alpha_sl = m_sl/(rho_sl V) y el volumen nuevo desplaza gas (la
        ! compactacion lo sube por la columna; gas auditado como el volfix).
        ! Solo donde difieren mas que el redondeo (m_sl = alpha_sl rho_sl V
        ! tras el transporte: no reescribir con ruido)
        do k = 1, m%nz_g
            do j = 1, m%nth_g
                do i = 1, m%nr_g
                    if (m%cell_type_global(i,j,k) == 0) cycle
                    as_m = ms_g(i,j,k) / (cfg%rho_slag * m%vol_global(i,j,k))
                    if (abs(as_m - as_g(i,j,k)) > 1.0e-12_dp * max(as_g(i,j,k), as_m)) then
                        as_g(i,j,k) = as_m
                        chg(i,j,k) = .true.
                    end if
                end do
            end do
        end do
        al_n = al_g; tl_n = tl_g; as_n = as_g; ms_n = ms_g; es_n = es_g; x_n = x_g

        do j = 1, m%nth_g
            do i = 1, m%nr_g
                k = 1
                do while (k <= m%nz_g)
                    if (m%cell_type_global(i,j,k) == 0 .or. &
                        al_g(i,j,k) + as_g(i,j,k) < ALPHA_FLOW_CUTOFF) then
                        k = k + 1; cycle
                    end if
                    k1 = k
                    do while (k <= m%nz_g)
                        if (m%cell_type_global(i,j,k) == 0) exit
                        if (al_g(i,j,k) + as_g(i,j,k) < ALPHA_FLOW_CUTOFF) exit
                        k = k + 1
                    end do
                    k2 = k - 1
                    ! capacidad condensada objetivo de cada celda
                    ! (auditoria P4 M5) compacta solo con escoria RESUELTA y solo
                    ! desde la celda bajo la escoria mas baja: con cualquier traza
                    ! se compactaba la columna entera y las burbujas del fondo del
                    ! baño subian a la cima en un paso
                    has_slag = any(as_g(i,j,k1:k2) >= ALPHA_CUTOFF)
                    vcond = 0.0_dp
                    do kk = k1, k2
                        acn(i,j,kk) = al_g(i,j,kk) + as_g(i,j,kk)
                    end do
                    if (has_slag) then
                        kc = k1
                        do kk = k1, k2
                            if (as_g(i,j,kk) >= ALPHA_CUTOFF) then
                                kc = max(k1, kk - 1); exit
                            end if
                        end do
                        do kk = kc, k2
                            vcond = vcond + acn(i,j,kk) * m%vol_global(i,j,kk)
                        end do
                        ! (P5) si el condensado no cabe, el tramo se extiende
                        ! hacia arriba sobre las celdas de gas de la columna
                        capsum = 0.0_dp
                        do kk = kc, k2
                            capsum = capsum + max(0.0_dp, liq_cap(ss_g(i,j,kk), 0.0_dp) - ap_g(i,j,kk)) * m%vol_global(i,j,kk)
                        end do
                        k2e = k2
                        do while (vcond > capsum * (1.0_dp + 1.0e-14_dp) .and. k2e < m%nz_g)
                            if (m%cell_type_global(i,j,k2e+1) == 0) exit
                            k2e = k2e + 1
                            acn(i,j,k2e) = al_g(i,j,k2e) + as_g(i,j,k2e)
                            vcond = vcond + acn(i,j,k2e) * m%vol_global(i,j,k2e)
                            capsum = capsum + max(0.0_dp, liq_cap(ss_g(i,j,k2e), 0.0_dp) - ap_g(i,j,k2e)) * m%vol_global(i,j,k2e)
                        end do
                        if (k2e > k2) then
                            k2 = k2e
                            k = k2 + 1
                        end if
                        ! (auditoria P4 M4) si ni hasta el techo cabe, no se
                        ! compacta (la ultima celda quedaria por encima de su
                        ! hueco): solo se reordena con las alpha_c de cada celda
                        if (vcond <= capsum * (1.0_dp + 1.0e-14_dp)) then
                            do kk = kc, k2
                                capk = max(0.0_dp, liq_cap(ss_g(i,j,kk), 0.0_dp) - ap_g(i,j,kk)) * m%vol_global(i,j,kk)
                                if (kk == k2) capk = vcond
                                capk = max(min(capk, vcond), 0.0_dp)
                                acn(i,j,kk) = capk / m%vol_global(i,j,kk)
                                vcond = vcond - capk
                            end do
                        end if
                    end if
                    ! ya ordenado: ninguna celda con acero por encima de una
                    ! celda con escoria (dentro del segmento) y nada que compactar
                    ordered = .true.; seen_slag = .false.
                    do kk = k1, k2
                        if (abs(acn(i,j,kk) - (al_g(i,j,kk) + as_g(i,j,kk))) > 1.0e-14_dp) ordered = .false.
                    end do
                    do kk = k1, k2
                        if (seen_slag .and. al_g(i,j,kk) > 0.0_dp) ordered = .false.
                        if (as_g(i,j,kk) > 0.0_dp) seen_slag = .true.
                    end do
                    ! una celda mixta en el tope del acero esta permitida: la
                    ! condicion anterior marca escoria y exige que lo de arriba
                    ! no tenga acero
                    if (ordered) cycle
                    ! volumen total de acero del segmento
                    vst = 0.0_dp
                    do kk = k1, k2
                        vst = vst + al_g(i,j,kk) * m%vol_global(i,j,kk)
                    end do
                    ! --- acero: llenar de abajo arriba (remapeo con su T)
                    ko = k1 - 1; rem = 0.0_dp
                    do kk = k1, k2
                        ac = acn(i,j,kk)
                        cap = ac * m%vol_global(i,j,kk)
                        s_need = min(vst, cap)
                        vst = vst - s_need
                        al_n(i,j,kk) = s_need / m%vol_global(i,j,kk)
                        vt = 0.0_dp
                        do while (s_need > 0.0_dp)
                            if (rem <= 0.0_dp) then
                                ko = ko + 1
                                if (ko > k2) exit
                                rem = al_g(i,j,ko) * m%vol_global(i,j,ko)
                                cycle
                            end if
                            d = min(s_need, rem)
                            vt = vt + d * tl_g(i,j,ko)
                            rem = rem - d; s_need = s_need - d
                        end do
                        if (al_n(i,j,kk) > 0.0_dp) tl_n(i,j,kk) = vt / (al_n(i,j,kk) * m%vol_global(i,j,kk))
                        chg(i,j,kk) = .true.
                    end do
                    ! --- escoria: el resto de cada celda, parcelas en orden
                    ko = k1 - 1; rem = 0.0_dp
                    do kk = k1, k2
                        ac = acn(i,j,kk)
                        vc = max(0.0_dp, ac - al_n(i,j,kk)) * m%vol_global(i,j,kk)   ! volumen de escoria
                        as_n(i,j,kk) = vc / m%vol_global(i,j,kk)
                        ms_n(i,j,kk) = 0.0_dp; es_n(i,j,kk) = 0.0_dp; x_n(i,j,kk,:) = 0.0_dp
                        s_need = vc
                        do while (s_need > 0.0_dp)
                            if (rem <= 0.0_dp) then
                                ko = ko + 1
                                if (ko > k2) exit
                                rem = as_g(i,j,ko) * m%vol_global(i,j,ko)
                                cycle
                            end if
                            d = min(s_need, rem)
                            if (as_g(i,j,ko) > 0.0_dp) then
                                ms_n(i,j,kk) = ms_n(i,j,kk) + d / (as_g(i,j,ko) * m%vol_global(i,j,ko)) * ms_g(i,j,ko)
                                es_n(i,j,kk) = es_n(i,j,kk) + d / (as_g(i,j,ko) * m%vol_global(i,j,ko)) * es_g(i,j,ko)
                                x_n(i,j,kk,:) = x_n(i,j,kk,:) + d / (as_g(i,j,ko) * m%vol_global(i,j,ko)) * x_g(i,j,ko,:)
                            end if
                            rem = rem - d; s_need = s_need - d
                        end do
                    end do
                end do
            end do
        end do

        do k = 1, m%nz_g
            do j = 1, m%nth_g
                do i = 1, m%nr_g
                    if (.not. chg(i,j,k)) cycle
                    call global_to_local(m, i, j, k, il, jl, kl, owned)
                    if (.not. owned) cycle
                    liq%alpha(il,jl,kl) = al_n(i,j,k)
                    liq%T(il,jl,kl) = tl_n(i,j,k)
                    slag%alpha_sl(il,jl,kl) = as_n(i,j,k)
                    slag%m_sl(il,jl,kl) = ms_n(i,j,k)
                    slag%E_sl(il,jl,kl) = es_n(i,j,k)
                    slag%m_X(il,jl,kl,:) = x_n(i,j,k,:)
                    if (ms_n(i,j,k) > SMALL_SL) then
                        slag%T_sl(il,jl,kl) = es_n(i,j,k) / (ms_n(i,j,k) * cfg%cp_slag)
                    end if
                    ! gas: complemento (compactacion), auditado como el volfix
                    ag_new = max(0.0_dp, 1.0_dp - sol%alpha_s(il,jl,kl) - liq%alpha(il,jl,kl) &
                                          - slag%alpha_sl(il,jl,kl) - ap_g(i,j,k))
                    if (ag_new /= gas%alpha(il,jl,kl)) then
                        pc = 0.0_dp
                        if (present(sh)) pc = sh%p(il,jl,kl)
                        dmg = dmg + (ag_new - gas%alpha(il,jl,kl)) * gas%rho(il,jl,kl) * m%vol(il,jl,kl)
                        deg = deg + gas_inventory_cell(ag_new, gas%T(il,jl,kl), pc, gas%cp(il,jl,kl), &
                                                       m%vol(il,jl,kl), cfg) &
                                  - gas_inventory_cell(gas%alpha(il,jl,kl), gas%T(il,jl,kl), pc, &
                                                       gas%cp(il,jl,kl), m%vol(il,jl,kl), cfg)
                        if (present(sh) .and. ag_new > gas%alpha(il,jl,kl) .and. ag_new > 0.0_dp) then
                            fdil = max(gas%alpha(il,jl,kl), 0.0_dp) / ag_new
                            sh%Y_O2(il,jl,kl)  = sh%Y_O2(il,jl,kl)  * fdil
                            sh%Y_CO(il,jl,kl)  = sh%Y_CO(il,jl,kl)  * fdil
                            sh%Y_CO2(il,jl,kl) = sh%Y_CO2(il,jl,kl) * fdil
                        else if (present(sh) .and. ag_new < gas%alpha(il,jl,kl)) then
                            call audit_gas_destroyed(sh, il, jl, kl, &
                                (gas%alpha(il,jl,kl) - ag_new) * gas%rho(il,jl,kl) * m%vol(il,jl,kl))
                        end if
                        gas%alpha(il,jl,kl) = ag_new
                    end if
                end do
            end do
        end do
        call audit_add(AUD_GAS_VOLFIX, dmg)
        call audit_add(AUD_GAS_VOLFIX_E, deg)
        call slag_exchange_halos(slag, m)
        call mpi_exchange_halos_3d(liq%alpha, m%topo)
        call mpi_exchange_halos_3d(liq%T, m%topo)
        call mpi_exchange_halos_3d(gas%alpha, m%topo)
        deallocate(al_g, tl_g, as_g, ms_g, es_g, x_g, tmp, al_n, tl_n, as_n, ms_n, es_n, x_n, chg, ss_g, acn, ap_g)
    end subroutine slag_condensed_sort

    !---------------------------------------------------------------------------
    ! Flotacion por COLUMNA GLOBAL (auditoria 12-oct-2026: A14, M17, M18).
    ! Cada columna (r, theta) reune su escoria (masa, entalpia, componentes) y
    ! la coloca sobre la SUPERFICIE del material condensado (bano continuo o
    ! lecho de chatarra), llenando el hueco libre 1 - alpha_s - alpha_l hacia
    ! arriba; alpha_sl = m_sl/(rho_slag V) siempre. Antes: barridos locales
    ! k = kstart..kend-1 (la escoria no cruzaba la frontera de rank en z: la
    ! capa dependia de la descomposicion), solo SUBIA y solo con liquido en su
    ! celda (quedaba suspendida en el freeboard al fundirse la chatarra), el
    ! hueco de arriba ignoraba la chatarra (Sigma alpha > 1) y alpha_sl no
    ! seguia a m_sl en las adiciones y la quimica. Patron invariante: gather
    ! global + mismo barrido en todos los ranks + escritura de celdas propias.
    !---------------------------------------------------------------------------
    subroutine slag_buoyancy(slag, liq, gas, sol, m, cfg, sh)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        type(shared_t), intent(inout), optional :: sh
        real(dp) :: fdil

        integer  :: i, j, k, c, ks, kk, il, jl, kl
        logical  :: owned
        real(dp) :: Mcol, Ecol, Xcol(N_SLAG_COMP), vneed, room, dv, f, mrem, mneed, dm
        integer  :: kold, klast
        real(dp) :: ag_new, dmg, deg, pc
        real(dp), allocatable :: ms_g(:,:,:), es_g(:,:,:), as_g(:,:,:), al_g(:,:,:)
        real(dp), allocatable :: x_g(:,:,:,:), ms_n(:,:,:), es_n(:,:,:), x_n(:,:,:,:)
        real(dp), allocatable :: tmp(:,:,:)

        allocate(ms_g(m%nr_g, m%nth_g, m%nz_g), es_g(m%nr_g, m%nth_g, m%nz_g))
        allocate(as_g(m%nr_g, m%nth_g, m%nz_g), al_g(m%nr_g, m%nth_g, m%nz_g))
        allocate(ms_n(m%nr_g, m%nth_g, m%nz_g), es_n(m%nr_g, m%nth_g, m%nz_g))
        allocate(x_g(m%nr_g, m%nth_g, m%nz_g, N_SLAG_COMP), x_n(m%nr_g, m%nth_g, m%nz_g, N_SLAG_COMP))
        allocate(tmp, mold=slag%m_sl)
        dmg = 0.0_dp; deg = 0.0_dp
        call gather_global_field(slag%m_sl, ms_g, m)
        call gather_global_field(slag%E_sl, es_g, m)
        call gather_global_field(liq%alpha, al_g, m)
        call gather_global_field(sol%alpha_s, as_g, m)
        do c = 1, N_SLAG_COMP
            tmp = slag%m_X(:,:,:,c)
            call gather_global_field(tmp, x_g(:,:,:,c), m)
        end do
        ms_n = 0.0_dp; es_n = 0.0_dp; x_n = 0.0_dp

        do j = 1, m%nth_g
            do i = 1, m%nr_g
                Mcol = 0.0_dp; Ecol = 0.0_dp; Xcol = 0.0_dp
                do k = 1, m%nz_g
                    if (m%cell_type_global(i,j,k) == 0) cycle
                    Mcol = Mcol + ms_g(i,j,k); Ecol = Ecol + es_g(i,j,k)
                    Xcol = Xcol + x_g(i,j,k,:)
                end do
                if (Mcol <= SMALL_SL) then
                    ! residuos de componentes sin masa: se conservan donde estan
                    x_n(i,j,:,:) = x_g(i,j,:,:)
                    cycle
                end if
                ! soporte: la escoria (liquida) descansa sobre el ACERO
                ! SATURADO MAS ALTO de la columna y se infiltra en los poros
                ! de la chatarra a ese nivel (hueco liq_cap - alpha_l).
                ! Saturada = alpha_l >= min(ALPHA_LIQ_CONT, max(ALPHA_FLOW_CUTOFF,
                ! liq_cap/2)): fuera del lecho es la regla clasica (0.3); en un
                ! lecho denso (liq_cap < 0.3) es relativa a su hueco (el bano
                ! si se detecta, dirigida M1-M4 Medio 3b). Una bolsa de gas o un
                ! fondo seco bajo el acero NO cortan la busqueda (dirigida de
                ! 126c426, Medio 1: el barrido contiguo desde el fondo metia la
                ! escoria DEBAJO de la capa saturada de pocket_rise). Un charco
                ! encaramado tambien la sostiene: la escoria no atraviesa acero.
                ! Solo sin acero se apoya en la cima del lecho (M4: con 'bano O
                ! lecho' la cesta 2 sobre bano con escoria la subia metros);
                ! sin material, la celda activa mas baja.
                ks = -1
                do k = m%nz_g, 1, -1
                    if (m%cell_type_global(i,j,k) == 0) cycle
                    if (al_g(i,j,k) >= min(ALPHA_LIQ_CONT, max(ALPHA_FLOW_CUTOFF, &
                            0.5_dp * liq_cap(as_g(i,j,k), 0.0_dp)))) then
                        ks = k; exit
                    end if
                end do
                if (ks < 0) then
                    do k = m%nz_g, 1, -1
                        if (m%cell_type_global(i,j,k) == 0) cycle
                        if (as_g(i,j,k) >= ALPHA_BED) then
                            ks = k; exit
                        end if
                    end do
                end if
                if (ks < 0) then
                    do k = 1, m%nz_g
                        if (m%cell_type_global(i,j,k) /= 0) then
                            ks = k; exit
                        end if
                    end do
                end if
                if (ks < 0) cycle
                ! (auditoria 17, M17-arc1) REMAPEO LAGRANGIANO: la masa de la
                ! pila vieja, de abajo arriba, llena la pila nueva de abajo
                ! arriba y cada parcela lleva SU entalpia y composicion. Antes
                ! cada celda recibia la fraccion de la entalpia MEDIA de la
                ! columna: la escoria quedaba a una sola T en cada paso
                ! (conductividad vertical infinita; arc_slag: |T(k18)-T(k19)|
                ! <= 0.03 K y la capa superior emitia a la T de la interfaz).
                ! Si la escoria no se mueve, cada celda conserva su E. Masa,
                ! energia y componentes de la columna exactos (el resto de
                ! redondeo va a la ultima celda llenada).
                vneed = Mcol / cfg%rho_slag
                kold = 0; mrem = 0.0_dp; klast = -1
                do kk = ks, m%nz_g
                    if (vneed <= 0.0_dp) exit
                    if (m%cell_type_global(i,j,kk) == 0) cycle
                    ! (auditoria 5, B5-13) hueco con el piso de gas del poro
                    ! (liq_cap): la escoria no ocupa el gas residual del lecho
                    room = max(0.0_dp, liq_cap(as_g(i,j,kk), 0.0_dp) - al_g(i,j,kk)) * m%vol_global(i,j,kk)
                    if (kk == m%nz_g) room = vneed           ! techo: lo que no cupo queda aqui
                    dv = min(vneed, room)
                    if (dv <= 0.0_dp) cycle
                    mneed = dv * cfg%rho_slag
                    klast = kk
                    do while (mneed > 0.0_dp)
                        if (mrem <= 0.0_dp) then
                            ! siguiente parcela vieja (de abajo arriba)
                            do kold = kold + 1, m%nz_g
                                if (m%cell_type_global(i,j,kold) == 0) cycle
                                if (ms_g(i,j,kold) > 0.0_dp) exit
                            end do
                            if (kold > m%nz_g) exit
                            mrem = ms_g(i,j,kold)
                        end if
                        dm = min(mneed, mrem)
                        ms_n(i,j,kk) = ms_n(i,j,kk) + dm
                        es_n(i,j,kk) = es_n(i,j,kk) + dm * es_g(i,j,kold) / ms_g(i,j,kold)
                        x_n(i,j,kk,:) = x_n(i,j,kk,:) + dm * x_g(i,j,kold,:) / ms_g(i,j,kold)
                        mrem = mrem - dm; mneed = mneed - dm
                    end do
                    vneed = vneed - dv
                end do
                ! cierre exacto: lo que quede de la pila vieja (redondeo de
                ! dv*rho frente a la masa) va a la ultima celda llenada, y la
                ! energia/componentes se ajustan al total de la columna
                if (klast > 0) then
                    ms_n(i,j,klast) = ms_n(i,j,klast) + (Mcol - sum(ms_n(i,j,:)))
                    es_n(i,j,klast) = es_n(i,j,klast) + (Ecol - sum(es_n(i,j,:)))
                    do c = 1, N_SLAG_COMP
                        x_n(i,j,klast,c) = x_n(i,j,klast,c) + (Xcol(c) - sum(x_n(i,j,:,c)))
                    end do
                end if
            end do
        end do

        do k = 1, m%nz_g
            do j = 1, m%nth_g
                do i = 1, m%nr_g
                    call global_to_local(m, i, j, k, il, jl, kl, owned)
                    if (.not. owned) cycle
                    if (m%cell_type(il,jl,kl) == 0) cycle
                    slag%m_sl(il,jl,kl) = ms_n(i,j,k)
                    slag%E_sl(il,jl,kl) = es_n(i,j,k)
                    slag%m_X(il,jl,kl,:) = x_n(i,j,k,:)
                    slag%alpha_sl(il,jl,kl) = ms_n(i,j,k) / (cfg%rho_slag * m%vol(il,jl,kl))
                    if (ms_n(i,j,k) > SMALL_SL) then
                        slag%T_sl(il,jl,kl) = es_n(i,j,k) / (ms_n(i,j,k) * cfg%cp_slag)
                    else
                        slag%T_sl(il,jl,kl) = 0.0_dp
                        slag%alpha_foam(il,jl,kl) = 0.0_dp
                    end if
                    ! El gas es el complemento: la escoria que se mueve crea y
                    ! destruye gas (la EOS fija su masa). Masa y energia de
                    ! inventario auditadas como el volfix (M4-13): sin esto el
                    ! paso 1 de slag_chem_test dejaba 1e6 J sin columna.
                    ag_new = max(0.0_dp, 1.0_dp - as_g(i,j,k) - liq%alpha(il,jl,kl) &
                                          - slag%alpha_sl(il,jl,kl))
                    pc = 0.0_dp
                    if (present(sh)) pc = sh%p(il,jl,kl)
                    dmg = dmg + (ag_new - gas%alpha(il,jl,kl)) * gas%rho(il,jl,kl) * m%vol(il,jl,kl)
                    deg = deg + gas_inventory_cell(ag_new, gas%T(il,jl,kl), pc, gas%cp(il,jl,kl), &
                                                   m%vol(il,jl,kl), cfg) &
                              - gas_inventory_cell(gas%alpha(il,jl,kl), gas%T(il,jl,kl), pc, &
                                                   gas%cp(il,jl,kl), m%vol(il,jl,kl), cfg)
                    ! (auditoria 5, M5-5) el gas CREADO no trae especies: Y se
                    ! diluye por alpha_old/alpha_new como en el volfix (A3-7);
                    ! antes las Y quedaban y el gas que reaparecia bajo la
                    ! escoria creaba O y C de la nada. Al destruir gas la
                    ! especie se va con el.
                    if (present(sh) .and. ag_new > gas%alpha(il,jl,kl) .and. ag_new > 0.0_dp) then
                        fdil = max(gas%alpha(il,jl,kl), 0.0_dp) / ag_new
                        sh%Y_O2(il,jl,kl)  = sh%Y_O2(il,jl,kl)  * fdil
                        sh%Y_CO(il,jl,kl)  = sh%Y_CO(il,jl,kl)  * fdil
                        sh%Y_CO2(il,jl,kl) = sh%Y_CO2(il,jl,kl) * fdil
                    else if (present(sh)) then
                        call audit_gas_destroyed(sh, il, jl, kl, &
                            (gas%alpha(il,jl,kl) - ag_new) * gas%rho(il,jl,kl) * m%vol(il,jl,kl))
                    end if
                    gas%alpha(il,jl,kl) = ag_new
                end do
            end do
        end do
        call audit_add(AUD_GAS_VOLFIX, dmg)
        call audit_add(AUD_GAS_VOLFIX_E, deg)
        deallocate(ms_g, es_g, as_g, al_g, ms_n, es_n, x_g, x_n, tmp)
    end subroutine slag_buoyancy

    !---------------------------------------------------------------------------
    ! Intercambio de calor de la escoria con el bano y el gas: paso partido
    ! EXACTO de dos nodos (relajacion exponencial hacia el equilibrio,
    ! conservativo e incondicionalmente estable; auditoria M20: el explicito
    ! con el tope del lado del fluido oscilaba con escoria escasa). El bano es
    ! el de la propia celda si lo hay, si no el de abajo (otro rank posible:
    ! dos pasadas con halos, auditoria A14). La T de la escoria es E/(m cp)
    ! sin recorte (el recorte a 300 K desacoplaba T de E).
    !---------------------------------------------------------------------------
    subroutine slag_energy(slag, liq, gas, m, cfg, dt, sh)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        real(dp),      intent(in)    :: dt
        type(shared_t), intent(in), optional :: sh

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: Cs, Cf, Cb, hA, f, Q, Cg, Tg, Ts, pc
        real(dp), allocatable :: qdown(:,:,:)

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if
        allocate(qdown, mold=slag%m_sl); qdown = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%m_sl(i,j,k) <= SMALL_SL) cycle
                    Cs = slag%m_sl(i,j,k) * cfg%cp_slag
                    ! bano: propia celda o la de abajo, la de MAYOR capacidad
                    ! (A13-1, oct-2026): con la escoria en su propia capa la
                    ! celda guarda una traza de liquido y el acople iba a esa
                    ! traza (10-30 J por paso en arc_slag frente a 2.3e5 J del
                    ! arco), nunca al bano de abajo
                    Cf = 0.0_dp
                    if (liq%alpha(i,j,k) > SMALL_SL) Cf = liq%alpha(i,j,k) * liq%rho(i,j,k) &
                        * liq%cp(i,j,k) * m%vol(i,j,k)
                    Cb = 0.0_dp
                    if (m%cell_type(i,j,k-1) /= 0) then
                        if (liq%alpha(i,j,k-1) > SMALL_SL) Cb = liq%alpha(i,j,k-1) &
                            * liq%rho(i,j,k-1) * liq%cp(i,j,k-1) * m%vol(i,j,k-1)
                    end if
                    if (Cf > 0.0_dp .and. Cf >= Cb) then
                        Cf = liq%alpha(i,j,k) * liq%rho(i,j,k) * liq%cp(i,j,k) * m%vol(i,j,k)
                        hA = cfg%h_contact_sl * m%Az(i,j,k-1)
                        f = 1.0_dp - exp(-dt * hA * (1.0_dp / Cs + 1.0_dp / Cf))
                        Q = Cs * Cf / (Cs + Cf) * (liq%T(i,j,k) - slag%E_sl(i,j,k) / Cs) * f
                        slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + Q
                        liq%T(i,j,k) = liq%T(i,j,k) - Q / Cf
                        call audit_add(AUD_SLAG_LIQ, Q)
                    else if (Cb > 0.0_dp) then
                        Cf = liq%alpha(i,j,k-1) * liq%rho(i,j,k-1) * liq%cp(i,j,k-1) * m%vol(i,j,k-1)
                        hA = cfg%h_contact_sl * m%Az(i,j,k-1)
                        f = 1.0_dp - exp(-dt * hA * (1.0_dp / Cs + 1.0_dp / Cf))
                        Q = Cs * Cf / (Cs + Cf) * (liq%T(i,j,k-1) - slag%E_sl(i,j,k) / Cs) * f
                        slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + Q
                        qdown(i,j,k) = Q        ! se le resta al bano de abajo en la pasada 2
                        call audit_add(AUD_SLAG_LIQ, Q)
                    end if
                    ! gas de la propia celda
                    ! Gas de la propia celda, CONSISTENTE con el inventario del
                    ! gas (M4-13): su energia es C_g ln(T/T_ref) (la masa la fija
                    ! la EOS, rho ~ 1/T), asi que la capacidad lineal C_g/T solo
                    ! vale a primer orden. El poke T -= Q/Cf dejaba sin contar el
                    ! 30 % de Q cuando el gas frio (300 K) tocaba la escoria a
                    ! 1800 K (slag_chem_test, paso 1: 1.0e6 J; paso 2: 50 % de
                    ! 8e3 J). Equilibrio exacto Cs (Ts - Teq) = C_g ln(Teq/Tg)
                    ! (Newton acotado). El GAS avanza la fraccion f hacia Teq en
                    ! ln T (T = Tg (Teq/Tg)^f, acotada entre Tg y Teq) y la
                    ! escoria recibe EXACTAMENTE lo que perdio el inventario del
                    ! gas, Q = C_g ln(Tg/T): conservacion por construccion, la
                    ! precision del Newton solo afecta a la tasa. (Despejar T de
                    ! Q con exp(-Q/C_g) y Q de Cs (Teq - Ts) dejaba el gas a 3 K
                    ! cuando C_g << Cs: el residuo del Newton, escalado con Cs,
                    ! era enorme frente a C_g.)
                    if (gas%alpha(i,j,k) > SMALL_SL) then
                        pc = 0.0_dp
                        if (present(sh)) pc = sh%p(i,j,k)
                        Cg = gas_heat_capacity_ref(gas%alpha(i,j,k), pc, gas%cp(i,j,k), &
                                                   m%vol(i,j,k), cfg)
                        Tg = max(gas%T(i,j,k), T_MIN_GAS)
                        Ts = slag%E_sl(i,j,k) / Cs
                        hA = cfg%h_contact_sl * m%Az(i,j,k)
                        ! (auditoria 5, B5-3) una sola definicion del
                        ! intercambio log de dos nodos (gas_log_exchange):
                        ! el gas se relaja exacto hacia la T NUEVA de la
                        ! escoria, que cumple el balance; Q hacia la escoria
                        call gas_log_exchange(Cg, Tg, Cs, Ts, hA, dt, gas%T(i,j,k), Q)
                        slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + Q
                        call audit_add(AUD_SLAG_GAS, Q)
                    end if
                    slag%T_sl(i,j,k) = slag%E_sl(i,j,k) / Cs
                end do
            end do
        end do

        ! pasada 2: el bano de abajo cede lo que recibio la escoria de arriba
        call mpi_exchange_halos_3d(qdown, m%topo)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (qdown(i,j,k+1) == 0.0_dp) cycle
                    Cf = liq%alpha(i,j,k) * liq%rho(i,j,k) * liq%cp(i,j,k) * m%vol(i,j,k)
                    if (Cf > 0.0_dp) liq%T(i,j,k) = liq%T(i,j,k) - qdown(i,j,k+1) / Cf
                end do
            end do
        end do
        deallocate(qdown)
    end subroutine slag_energy

end module mod_slag_3d
