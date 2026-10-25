!===============================================================================
! mod_ecs_feed.f90 - Cargador continuo ECS (E1.2, roadmap del paper)
!
! Fuente de masa sólida por "banda": el material entra por una región de la
! periferia (r >= ecs_r_inner, sector |theta - theta_c| <= width/2 con wrap)
! sobre la superficie local del material, a caudal mdot(t) [kg/s]. Entra a
! T_charge con fracción sólida objetivo ecs_vfrac y carbono proporcional.
!
! Diseño MPI-invariante por construcción (mismo patrón que el colapso):
!   1. Altura de material h(i, j_global) por columna, reducida GLOBALMENTE
!      (z está descompuesta: ninguna decisión usa datos solo locales).
!   2. La celda destino de cada columna se deriva de h y de z_global
!      (idénticos en todos los ranks); el dueño computa su capacidad local
!      C_cell = rho_steel * max(0, min(ecs_vfrac - alpha_s, alpha_g)) * V
!      (con la escoria CONDENSADA, Plan I I2: alpha_g + alpha_sl y el
!      presupuesto de volumen libre de la columna, ver mas abajo).
!   3. C_glob = allreduce_sum; el depósito es PROPORCIONAL:
!      dm_cell = dm_nivel * C_cell / C_glob  (<= C_cell por construcción).
!   4. Si el nivel se llena, se sube al siguiente; si el horno se llena,
!      el excedente queda en m_ecs_pending (conserva masa; warn rank 0).
!
! El depósito ACUMULA (m_s/E_s/m_C) y desplaza gas; nunca toca liq%alpha.
! En legado nunca toca la escoria; con la condensada la atraviesa (el solape
! lo resuelve slag_condensed_sort al inicio del paso). La mezcla entálpica usa la función única
! solid_enthalpy / solid_T_from_enthalpy (exacta). layer_id = ID_ECS.
!
! Auditoría: AUD_ECS_MASS / AUD_ECS_ENERGY por celda depositada (columnas
! m_ecs_in / E_ecs_in del audit.csv); el test de integración exige
! inventario == integral del caudal a redondeo.
!===============================================================================
module mod_ecs_feed
    use mpi
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils, only: global_to_local
    use mod_mpi_topology, only: mpi_allreduce_sum
    use mod_melting_3d, only: solid_enthalpy, solid_T_from_enthalpy
    use mod_audit, only: audit_add, audit_volfix_cell, AUD_ECS_MASS, AUD_ECS_ENERGY, AUD_GAS_VOLFIX, AUD_GAS_VOLFIX_E, &
                         gas_inventory_cell, audit_gas_destroyed
    implicit none

    ! layer_id de la carga continua (las capas de receta usan 1..MAX_LAYERS)
    integer, parameter :: ID_ECS = MAX_LAYERS + 1

    ! Umbral de "hay material" para definir la superficie de la columna
    real(dp), parameter :: ECS_SURF_ALPHA = ALPHA_SCRAP_SURF

    ! Máximo de niveles sobre la superficie a intentar por paso
    integer, parameter :: ECS_MAX_LEVELS = 4

    real(dp), save :: m_ecs_pending = 0.0_dp
    logical,  save :: ecs_warned_full = .false.

contains

    subroutine ecs_feed(sol, gas, liq, m, cfg, mdot, dt, sh, slag)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: gas
        ! liquido: el tope del BAÑO tambien es superficie (auditoria M38)
        type(phase_t), intent(in)    :: liq
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: mdot   ! kg/s (ya evaluado en main)
        real(dp), intent(in)         :: dt
        ! (auditoria 5, M5-4) p para el inventario del gas desplazado
        type(shared_t), intent(in), optional :: sh
        ! (Plan I, I2) con la escoria CONDENSADA la chatarra ATRAVIESA la capa:
        ! la capacidad de la celda incluye la escoria (no solo el gas). El gas
        ! se desplaza primero; el solape con la escoria lo resuelve el
        ! reordenamiento de inicio de paso (slag_condensed_sort, que corre
        ! despues: sube la escoria desplazada y audita el gas como el volfix).
        ! La superficie ya es el tope del ACERO (alpha_l es solo acero)
        type(slag_t), intent(in), optional :: slag
        real(dp) :: ag_old, pc, dmg, deg
        logical  :: thru
        ! (auditoria general Plan I, MEDIO-1) presupuesto de VOLUMEN por
        ! columna con thru: la chatarra nueva no supera el VOLUMEN LIBRE de la
        ! columna (con signo y descontado el poro desde la base k0, mas los
        ! deficits por solape bajo k0 con el poro del lecho): asi el sort
        ! siempre puede subir la escoria desplazada y nunca queda un
        ! sobrellenado que el transporte recortaria (clip). Lo que no cabe
        ! queda pendiente, como con el techo
        real(dp), allocatable :: bud(:,:), dvb(:,:)
        real(dp) :: vfree

        real(dp), allocatable :: h_loc(:,:), h_glob(:,:)
        integer,  allocatable :: k0_glob(:,:)
        logical,  allocatable :: in_band(:,:)
        real(dp) :: dm_total, dm_level, dm_cell
        real(dp) :: c_loc, c_glob, cap_alpha, vol, e_in, dth
        integer  :: i, ig, jg, kg, il, jl, kl, lvl, k, ierr
        logical  :: owned

        thru = .false.
        if (present(slag)) thru = slag_condensed_on(cfg)
        dm_total = mdot * dt + m_ecs_pending
        m_ecs_pending = 0.0_dp
        if (dm_total <= 0.0_dp) return

        ! ── 1. Altura de material por columna (GLOBAL en r y theta) ─────────
        ! Auditoria (M32/M38): r SI se descompone (factorize_3d; 12 ranks ->
        ! 2x3x2): el indice radial es GLOBAL (iglobal_start), no el local.
        ! Antes se suponia i local == i global y con npr > 1 la superficie y la
        ! banda quedaban mal asignadas. El tope del BAÑO (alpha_l >=
        ! ALPHA_LIQ_CONT) es superficie: la chatarra cae sobre el baño (el
        ! colapso no la hunde y la fusion la consume); antes solo contaban la
        ! chatarra y el tazon, y con mas de ECS_MAX_LEVELS celdas de baño en la
        ! banda (sin gas: capacidad 0) toda la carga quedaba pendiente.
        allocate(h_loc(m%nr_g, m%nth_g), h_glob(m%nr_g, m%nth_g))
        allocate(k0_glob(m%nr_g, m%nth_g), in_band(m%nr_g, m%nth_g))
        h_loc = 0.0_dp   ! piso: sin material => superficie en z=0/bowl

        do kl = 1, m%nz
            do jl = 1, m%ntheta
                jg = m%topo%jglobal_start + jl - 1
                do i = 1, m%nr
                    ig = m%topo%iglobal_start + i - 1
                    if (m%cell_type(i,jl,kl) == 0) then
                        ! el bowl también es "superficie": se apila encima
                        h_loc(ig,jg) = max(h_loc(ig,jg), m%zf(kl))
                        cycle
                    end if
                    if (sol%alpha_s(i,jl,kl) > ECS_SURF_ALPHA .or. &
                        liq%alpha(i,jl,kl) >= ALPHA_LIQ_CONT) &
                        h_loc(ig,jg) = max(h_loc(ig,jg), m%zf(kl))
                end do
            end do
        end do
        if (m%is_parallel) then
            ! un solo allreduce del array completo (nr_g x nth_g)
            h_glob = h_loc
            call MPI_Allreduce(MPI_IN_PLACE, h_glob, size(h_glob), &
                               MPI_DOUBLE_PRECISION, MPI_MAX, &
                               m%topo%comm_cart, ierr)
        else
            h_glob = h_loc
        end if

        ! ── 2. Banda y celda destino base por columna (todo global) ────────
        do jg = 1, m%nth_g
            dth = atan2(sin(m%theta_global(jg) - cfg%ecs_theta_center), &
                        cos(m%theta_global(jg) - cfg%ecs_theta_center))
            do i = 1, m%nr_g
                in_band(i,jg) = (m%r_global(i) >= cfg%ecs_r_inner) .and. &
                                (abs(dth) <= 0.5_dp * cfg%ecs_theta_width)
                ! primera celda global cuyo centro queda sobre la superficie
                k0_glob(i,jg) = m%nz_g + 1
                do k = 1, m%nz_g
                    if (m%z_global(k) > h_glob(i,jg)) then
                        k0_glob(i,jg) = k
                        exit
                    end if
                end do
            end do
        end do

        e_in = solid_enthalpy(cfg%ecs_T_charge, cfg)

        if (thru) then
            allocate(bud(m%nr_g, m%nth_g), dvb(m%nr_g, m%nth_g))
            bud = 0.0_dp
            do kl = 1, m%nz
                do jl = 1, m%ntheta
                    jg = m%topo%jglobal_start + jl - 1
                    do i = 1, m%nr
                        ig = m%topo%iglobal_start + i - 1
                        kg = m%topo%kglobal_start + kl - 1
                        if (.not. in_band(ig,jg)) cycle
                        if (m%cell_type(i,jl,kl) == 0) cycle
                        ! (dirigida general, BAJO-1/2) suma CON SIGNO: el poro
                        ! se reserva en TODA celda desde la base (una celda de
                        ! escoria llena que pasa a lecho en esta llamada lo
                        ! exige) y solo si el piso de poro esta activo.
                        ! (general 2, BAJO-1 / MPI B1) VOLUMEN LIBRE real
                        ! 1 - as - al - asl, no alpha_g: un solape previo del
                        ! mismo paso (cesta 2 antes del sort) cuenta negativo
                        ! (dirigida general 2, M2) por DEBAJO de la base solo
                        ! cuentan los DEFICITS (solape de una cesta 2 del mismo
                        ! paso bajo la superficie del ECS: el sort tambien tiene
                        ! que subir esa escoria); el gas de abajo no cuenta
                        vfree = 1.0_dp - sol%alpha_s(i,jl,kl) - liq%alpha(i,jl,kl) &
                              - slag%alpha_sl(i,jl,kl)
                        if (kg >= k0_glob(ig,jg)) then
                            bud(ig,jg) = bud(ig,jg) + (vfree &
                                - merge(ALPHA_PORE_GAS, 0.0_dp, pore_floor_on)) * m%vol(i,jl,kl)
                        else
                            ! (dirigida corta, BAJO-1) con el poro que el sort
                            ! reserva en las celdas de lecho (liq_cap)
                            bud(ig,jg) = bud(ig,jg) + min(0.0_dp, liq_cap(sol%alpha_s(i,jl,kl), 0.0_dp) &
                                - liq%alpha(i,jl,kl) - slag%alpha_sl(i,jl,kl)) * m%vol(i,jl,kl)
                        end if
                    end do
                end do
            end do
            if (m%is_parallel) call MPI_Allreduce(MPI_IN_PLACE, bud, size(bud), &
                MPI_DOUBLE_PRECISION, MPI_SUM, m%topo%comm_cart, ierr)
            bud = max(0.0_dp, bud)
        end if

        ! ── 3. Depósito proporcional por niveles ────────────────────────────
        do lvl = 0, ECS_MAX_LEVELS - 1
            if (dm_total <= 0.0_dp) exit
            if (thru) dvb = 0.0_dp

            ! capacidad local de las celdas propias del nivel
            c_loc = 0.0_dp
            do jg = 1, m%nth_g
                do i = 1, m%nr_g
                    if (.not. in_band(i,jg)) cycle
                    kg = k0_glob(i,jg) + lvl
                    if (kg > m%nz_g) cycle
                    call global_to_local(m, i, jg, kg, il, jl, kl, owned)
                    if (.not. owned) cycle
                    if (m%cell_type(il,jl,kl) == 0) cycle
                    cap_alpha = max(0.0_dp, &
                        min(cfg%ecs_vfrac - sol%alpha_s(il,jl,kl), &
                            gas%alpha(il,jl,kl)))
                    if (thru) cap_alpha = max(0.0_dp, &
                        min(cfg%ecs_vfrac - sol%alpha_s(il,jl,kl), &
                            gas%alpha(il,jl,kl) + slag%alpha_sl(il,jl,kl), &
                            bud(i,jg) / m%vol(il,jl,kl)))
                    c_loc = c_loc + cfg%rho_steel * cap_alpha * &
                            m%vol(il,jl,kl)
                end do
            end do
            if (m%is_parallel) then
                call mpi_allreduce_sum(c_loc, c_glob, m%topo)
            else
                c_glob = c_loc
            end if
            if (c_glob <= SMALL) cycle

            dm_level = min(dm_total, c_glob)

            do jg = 1, m%nth_g
                do i = 1, m%nr_g
                    if (.not. in_band(i,jg)) cycle
                    kg = k0_glob(i,jg) + lvl
                    if (kg > m%nz_g) cycle
                    call global_to_local(m, i, jg, kg, il, jl, kl, owned)
                    if (.not. owned) cycle
                    if (m%cell_type(il,jl,kl) == 0) cycle
                    vol = m%vol(il,jl,kl)
                    cap_alpha = max(0.0_dp, &
                        min(cfg%ecs_vfrac - sol%alpha_s(il,jl,kl), &
                            gas%alpha(il,jl,kl)))
                    if (thru) cap_alpha = max(0.0_dp, &
                        min(cfg%ecs_vfrac - sol%alpha_s(il,jl,kl), &
                            gas%alpha(il,jl,kl) + slag%alpha_sl(il,jl,kl), &
                            bud(i,jg) / m%vol(il,jl,kl)))
                    dm_cell = dm_level * (cfg%rho_steel * cap_alpha * vol) &
                              / c_glob
                    if (dm_cell <= 0.0_dp) cycle

                    sol%m_s(il,jl,kl) = sol%m_s(il,jl,kl) + dm_cell
                    sol%E_s(il,jl,kl) = sol%E_s(il,jl,kl) + dm_cell * e_in
                    sol%m_C(il,jl,kl) = sol%m_C(il,jl,kl) + &
                                        cfg%ecs_carbon_frac * dm_cell
                    sol%alpha_s(il,jl,kl) = sol%m_s(il,jl,kl) / &
                                            (cfg%rho_steel * vol)
                    sol%T_s(il,jl,kl) = solid_T_from_enthalpy( &
                        sol%E_s(il,jl,kl) / sol%m_s(il,jl,kl), cfg)
                    sol%layer_id(il,jl,kl) = ID_ECS
                    if (thru) dvb(i,jg) = dvb(i,jg) + dm_cell / cfg%rho_steel
                    ag_old = gas%alpha(il,jl,kl)
                    gas%alpha(il,jl,kl) = max(0.0_dp, gas%alpha(il,jl,kl) &
                        - dm_cell / (cfg%rho_steel * vol))

                    call audit_add(AUD_ECS_MASS, dm_cell)
                    call audit_add(AUD_ECS_ENERGY, dm_cell * e_in)
                    ! (M5-4) el gas que la carga desplaza: masa y energia de
                    ! inventario al libro del gas (antes sin columna: ecs_test
                    ! destruia 0.048 kg con m_gas_volfix = 0)
                    pc = 0.0_dp
                    if (present(sh)) pc = sh%p(il,jl,kl)
                    dmg = (gas%alpha(il,jl,kl) - ag_old) * gas%rho(il,jl,kl) * vol
                    deg = gas_inventory_cell(gas%alpha(il,jl,kl), gas%T(il,jl,kl), pc, &
                              gas%cp(il,jl,kl), vol, cfg) &
                        - gas_inventory_cell(ag_old, gas%T(il,jl,kl), pc, gas%cp(il,jl,kl), vol, cfg)
                    call audit_add(AUD_GAS_VOLFIX, dmg)
                    call audit_volfix_cell(il, jl, kl, dmg)
                    call audit_add(AUD_GAS_VOLFIX_E, deg)
                    if (present(sh)) call audit_gas_destroyed(sh, il, jl, kl, -dmg)
                end do
            end do

            dm_total = dm_total - dm_level
            ! presupuesto restante de cada columna (volumen ya colocado)
            if (thru) then
                if (m%is_parallel) call MPI_Allreduce(MPI_IN_PLACE, dvb, size(dvb), &
                    MPI_DOUBLE_PRECISION, MPI_SUM, m%topo%comm_cart, ierr)
                bud = max(0.0_dp, bud - dvb)
            end if
        end do

        ! ── 4. Excedente: conservar y avisar (una vez) ─────────────────────
        if (dm_total > 0.0_dp) then
            m_ecs_pending = dm_total
            if (.not. ecs_warned_full .and. &
                (.not. m%is_parallel .or. m%topo%rank == 0)) then
                print '(A,ES12.4,A)', ' [ECS] AVISO: banda llena; ', &
                    dm_total, ' kg pendientes (se re-intentan cada paso)'
                ecs_warned_full = .true.
            end if
        end if

        deallocate(h_loc, h_glob, k0_glob, in_band)
        if (thru) deallocate(bud, dvb)

    end subroutine ecs_feed

end module mod_ecs_feed
