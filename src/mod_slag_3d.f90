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
    use mod_parallel_utils, only: gather_global_field, global_to_local
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

        ! Loop bounds
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
                    slag%T_sl(i, j, k_local)     = cfg%T_initial
                    slag%E_sl(i, j, k_local)     = slag%m_sl(i, j, k_local) * cfg%cp_slag * cfg%T_initial
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
                                                        * cfg%T_initial
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
    subroutine slag_intercept_arc(slag, liq, gas, sh, m, cfg)
        type(slag_t),  intent(inout) :: slag
        ! fluidos de la celda: el reparto es por ABSORCION (auditoria, bajos;
        ! F2.30): w = (k_sl a_sl + k_f a_foam)/(... + k_l a_l + k_g a_g), el
        ! mismo criterio con que la energia reparte S_arc entre liquido y gas.
        ! Antes: fraccion de VOLUMEN alpha_sl (y sin la espuma)
        type(phase_t), intent(in)    :: liq, gas
        type(shared_t),intent(inout) :: sh
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: dE, ksl, kfl, w

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
                    dE = sh%S_arc(i,j,k) * m%vol(i,j,k) * cfg%dt * w
                    slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + dE
                    sh%S_arc(i,j,k)  = sh%S_arc(i,j,k) * (1.0_dp - w)
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
        if (msl_glob <= SMALL_SL) return   ! sin capa donde depositar

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

        call slag_buoyancy(slag, liq, gas, sol, m, cfg, sh)
        call slag_energy(slag, liq, gas, m, cfg, dt, sh)
    end subroutine update_slag

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
        real(dp) :: Mcol, Ecol, Xcol(N_SLAG_COMP), vneed, room, dv, f
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
                ! superficie: celda activa mas alta con bano continuo o lecho;
                ! sin material, la celda activa mas baja
                ks = -1
                do k = m%nz_g, 1, -1
                    if (m%cell_type_global(i,j,k) == 0) cycle
                    if (al_g(i,j,k) >= ALPHA_LIQ_CONT .or. as_g(i,j,k) >= ALPHA_BED) then
                        ks = k; exit
                    end if
                end do
                if (ks < 0) then
                    do k = 1, m%nz_g
                        if (m%cell_type_global(i,j,k) /= 0) then
                            ks = k; exit
                        end if
                    end do
                end if
                if (ks < 0) cycle
                vneed = Mcol / cfg%rho_slag
                do kk = ks, m%nz_g
                    if (vneed <= 0.0_dp) exit
                    if (m%cell_type_global(i,j,kk) == 0) cycle
                    ! (auditoria 5, B5-13) hueco con el piso de gas del poro
                    ! (liq_cap): la escoria no ocupa el gas residual del lecho
                    room = max(0.0_dp, liq_cap(as_g(i,j,kk), 0.0_dp) - al_g(i,j,kk)) * m%vol_global(i,j,kk)
                    if (kk == m%nz_g) room = vneed           ! techo: lo que no cupo queda aqui
                    dv = min(vneed, room)
                    if (dv <= 0.0_dp) cycle
                    f = dv / (Mcol / cfg%rho_slag)
                    ms_n(i,j,kk) = ms_n(i,j,kk) + f * Mcol
                    es_n(i,j,kk) = es_n(i,j,kk) + f * Ecol
                    x_n(i,j,kk,:) = x_n(i,j,kk,:) + f * Xcol
                    vneed = vneed - dv
                end do
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
