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
!      C_cell = rho_steel * max(0, min(ecs_vfrac - alpha_s, alpha_g)) * V.
!   3. C_glob = allreduce_sum; el depósito es PROPORCIONAL:
!      dm_cell = dm_nivel * C_cell / C_glob  (<= C_cell por construcción).
!   4. Si el nivel se llena, se sube al siguiente; si el horno se llena,
!      el excedente queda en m_ecs_pending (conserva masa; warn rank 0).
!
! El depósito ACUMULA (m_s/E_s/m_C) y desplaza SOLO gas: nunca toca
! liq%alpha ni la escoria. La mezcla entálpica usa la función única
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
    use mod_audit, only: audit_add, AUD_ECS_MASS, AUD_ECS_ENERGY
    implicit none

    ! layer_id de la carga continua (las capas de receta usan 1..MAX_LAYERS)
    integer, parameter :: ID_ECS = MAX_LAYERS + 1

    ! Umbral de "hay material" para definir la superficie de la columna
    real(dp), parameter :: ECS_SURF_ALPHA = 0.05_dp

    ! Máximo de niveles sobre la superficie a intentar por paso
    integer, parameter :: ECS_MAX_LEVELS = 4

    real(dp), save :: m_ecs_pending = 0.0_dp
    logical,  save :: ecs_warned_full = .false.

contains

    subroutine ecs_feed(sol, gas, m, cfg, mdot, dt)
        type(solid_t), intent(inout) :: sol
        type(phase_t), intent(inout) :: gas
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: mdot   ! kg/s (ya evaluado en main)
        real(dp), intent(in)         :: dt

        real(dp), allocatable :: h_loc(:,:), h_glob(:,:)
        integer,  allocatable :: k0_glob(:,:)
        logical,  allocatable :: in_band(:,:)
        real(dp) :: dm_total, dm_level, dm_cell
        real(dp) :: c_loc, c_glob, cap_alpha, vol, e_in, dth
        integer  :: i, jg, kg, il, jl, kl, lvl, k, ierr
        logical  :: owned

        dm_total = mdot * dt + m_ecs_pending
        m_ecs_pending = 0.0_dp
        if (dm_total <= 0.0_dp) return

        ! ── 1. Altura de material por columna (GLOBAL; r no se descompone,
        !      i local == i global) ─────────────────────────────────────────
        allocate(h_loc(m%nr, m%nth_g), h_glob(m%nr, m%nth_g))
        allocate(k0_glob(m%nr, m%nth_g), in_band(m%nr, m%nth_g))
        h_loc = 0.0_dp   ! piso: sin material => superficie en z=0/bowl

        do kl = 1, m%nz
            do jl = 1, m%ntheta
                jg = m%topo%jglobal_start + jl - 1
                do i = 1, m%nr
                    if (m%cell_type(i,jl,kl) == 0) then
                        ! el bowl también es "superficie": se apila encima
                        h_loc(i,jg) = max(h_loc(i,jg), m%zf(kl))
                        cycle
                    end if
                    if (sol%alpha_s(i,jl,kl) > ECS_SURF_ALPHA) &
                        h_loc(i,jg) = max(h_loc(i,jg), m%zf(kl))
                end do
            end do
        end do
        if (m%is_parallel) then
            ! un solo allreduce del array completo (nr x nth_g)
            h_glob = h_loc
            call MPI_Allreduce(MPI_IN_PLACE, h_glob, size(h_glob), &
                               MPI_DOUBLE_PRECISION, MPI_MAX, &
                               MPI_COMM_WORLD, ierr)
        else
            h_glob = h_loc
        end if

        ! ── 2. Banda y celda destino base por columna (todo global) ────────
        do jg = 1, m%nth_g
            dth = atan2(sin(m%theta_global(jg) - cfg%ecs_theta_center), &
                        cos(m%theta_global(jg) - cfg%ecs_theta_center))
            do i = 1, m%nr
                in_band(i,jg) = (m%r(i) >= cfg%ecs_r_inner) .and. &
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

        ! ── 3. Depósito proporcional por niveles ────────────────────────────
        do lvl = 0, ECS_MAX_LEVELS - 1
            if (dm_total <= 0.0_dp) exit

            ! capacidad local de las celdas propias del nivel
            c_loc = 0.0_dp
            do jg = 1, m%nth_g
                do i = 1, m%nr
                    if (.not. in_band(i,jg)) cycle
                    kg = k0_glob(i,jg) + lvl
                    if (kg > m%nz_g) cycle
                    call global_to_local(m, i, jg, kg, il, jl, kl, owned)
                    if (.not. owned) cycle
                    if (m%cell_type(il,jl,kl) == 0) cycle
                    cap_alpha = max(0.0_dp, &
                        min(cfg%ecs_vfrac - sol%alpha_s(il,jl,kl), &
                            gas%alpha(il,jl,kl)))
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
                do i = 1, m%nr
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
                    gas%alpha(il,jl,kl) = max(0.0_dp, gas%alpha(il,jl,kl) &
                        - dm_cell / (cfg%rho_steel * vol))

                    call audit_add(AUD_ECS_MASS, dm_cell)
                    call audit_add(AUD_ECS_ENERGY, dm_cell * e_in)
                end do
            end do

            dm_total = dm_total - dm_level
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

    end subroutine ecs_feed

end module mod_ecs_feed
