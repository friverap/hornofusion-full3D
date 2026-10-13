!===============================================================================
! mod_arc_radiation_mc.f90 - Monte Carlo arc radiation model
!
! Distributes the radiative fraction of arc power via random beams
! emitted isotropically from the arc column. Each beam carries a fraction
! of the total radiative power and deposits it in the first solid/liquid
! cell it hits. Auditoria M12 (oct-2026): emision repartida a lo largo de la
! columna del arco, atenuacion Beer-Lambert del gas en el camino, impacto en
! el baño por alpha_l (no por altura) y sombra de los electrodos.
!
! Decomposition-invariant implementation:
!   - The RNG is seeded with a FIXED seed (reproducible runs); every rank
!     generates the same beam directions in the same order.
!   - Beams are traced on the GLOBAL geometry (rf_global/zf_global, uniform
!     global theta) using the globally-replicated alpha_s (gathered UNA vez
!     por paso en main y compartido con distribute_arc_heat — C4.2), so the
!     absorption cell of each beam is identical on every rank and in serial.
!   - C4.2: beams round-robin entre ranks; depósito acumulado en un array
!     global y reducido con MPI_SUM; solo el dueño de la celda escribe.
!===============================================================================
module mod_arc_radiation_mc
    use mpi
    use, intrinsic :: iso_fortran_env, only: int64
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_audit, only: audit_add, AUD_MC_DEPOSIT, AUD_MC_LOST, AUD_ARC_DIRECT
    use mod_arc_cassie_mayr, only: solid_arc_room
    use mod_melting_3d, only: solid_T_from_enthalpy
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Reseed determinista POR PASO (C0.3): cada paso es función pura de
    ! (step, campos), no de la historia de draws. Requisito para comparar
    ! snapshots entre corridas/versiones y para la invarianza de
    ! descomposición (misma secuencia en todos los ranks).
    !---------------------------------------------------------------------------
    subroutine reseed_rng(step)
        integer, intent(in) :: step
        integer :: n, i
        integer, allocatable :: seed(:)

        call random_seed(size=n)
        allocate(seed(n))
        ! aritmetica de 64 bits modulo 2^31 - 1 (auditoria, bajos): 7919*step
        ! desbordaba int32 desde el paso ~271 000 (B1 completo: ~2.5e6 pasos).
        ! Identica a la formula anterior mientras no hay desborde.
        do i = 1, n
            seed(i) = int(mod(104729_int64 + 37_int64 * i + 7919_int64 * int(step, int64), &
                              2147483647_int64))
        end do
        call random_seed(put=seed)
        deallocate(seed)
    end subroutine reseed_rng

    subroutine distribute_arc_radiation_mc(elec, sh, sol, m, cfg, alpha_g, alpha_lg, n_elec, step)
        type(electrode_t), intent(in)   :: elec(:)
        type(shared_t), intent(inout)   :: sh
        type(solid_t), intent(inout)    :: sol
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        ! alpha_g: alpha_s GLOBAL replicado (nombre historico); alpha_lg:
        ! alpha_l GLOBAL replicado (auditoria M12)
        real(dp), intent(in)            :: alpha_g(:,:,:)
        real(dp), intent(in)            :: alpha_lg(:,:,:)
        integer, intent(in)             :: n_elec
        integer, intent(in)             :: step

        integer  :: e, beam
        real(dp) :: w_s, Q_s, Q_fl   ! F2.30: reparto solido/fluido del deposito
        real(dp) :: P_rad_per_beam
        real(dp) :: x0, y0, z0, dx, dy, dz
        real(dp) :: x, y, z_pos, r_pos, theta_pos
        real(dp) :: phi_rand, cos_theta, sin_theta
        real(dp) :: step_size, total_P_rad
        integer  :: ig, jg, kg, il, jl, kl
        real(dp) :: rnd1, rnd2, rnd3, rnd4
        real(dp) :: P_beam, dP_abs, kap, z_att, xe2, ye2
        integer  :: e2
        logical  :: shadow
        integer  :: n_steps
        logical  :: owned
        integer  :: idx, ierr
        real(dp), allocatable :: dep_g(:,:,:)
        integer, parameter :: MAX_TRACE_STEPS = 50000

        if (cfg%n_beams <= 0) return   ! MC apagado (n_beams = 0 en config)

        call reseed_rng(step)

        ! C4.2: los beams se REPARTEN entre ranks (round-robin sobre el
        ! índice global de beam). Todos los ranks consumen la secuencia RNG
        ! completa (determinismo: las direcciones no dependen de nprocs);
        ! cada rank traza solo su subconjunto y el depósito se acumula en
        ! un array global reducido con MPI_SUM. La suma por celda puede
        ! reordenarse entre descomposiciones => invariante a ~1e-15, no
        ! bitwise (tolerado por compare_decomposition).
        allocate(dep_g(m%nr_g, m%nth_g, m%nz_g))
        dep_g = 0.0_dp
        idx = 0

        ! Step size from the GLOBAL minimum radial width (identical on all ranks)
        step_size = minval(m%rf_global(1:m%nr_g) - m%rf_global(0:m%nr_g-1)) * 0.5_dp
        if (step_size < 1.0e-6_dp) step_size = 0.01_dp   ! absolute fallback

        do e = 1, n_elec
            ! Parte del presupuesto frac_rad asignada al MC (C1.6a): el
            ! complemento lo deposita distribute_arc_heat directo al sólido
            total_P_rad = elec(e)%arc_power * cfg%frac_rad * elec(e)%mc_share
            if (total_P_rad < 1.0_dp) cycle

            P_rad_per_beam = total_P_rad / real(cfg%n_beams, dp)

            x0 = cfg%R_pcd * cos(elec(e)%theta_pos)
            y0 = cfg%R_pcd * sin(elec(e)%theta_pos)
            ! Columna del arco (auditoria M12): la emision se reparte a lo
            ! largo del arco, de la punta al pie (antes un punto en la punta)
            z_att = max(elec(e)%z_tip - max(elec(e)%arc_length, 0.0_dp), 0.0_dp)

            do beam = 1, cfg%n_beams
                ! Random direction (isotropic) — same sequence on every rank
                call random_number(rnd1)
                call random_number(rnd2)
                call random_number(rnd3)
                call random_number(rnd4)

                idx = idx + 1
                if (mod(idx - 1, m%topo%nprocs) /= m%topo%rank) cycle

                phi_rand = TWO_PI * rnd1
                cos_theta = 2.0_dp * rnd2 - 1.0_dp
                sin_theta = sqrt(max(1.0_dp - cos_theta**2, 0.0_dp))

                dx = sin_theta * cos(phi_rand)
                dy = sin_theta * sin(phi_rand)
                dz = cos_theta

                ! Trace beam on the global geometry
                z0 = z_att + rnd4 * (elec(e)%z_tip - z_att)
                x = x0; y = y0; z_pos = z0
                n_steps = 0
                P_beam = P_rad_per_beam

                ! Beams que escapan (fuera del dominio, celda inactiva o
                ! MAX_TRACE) se AUDITAN como E_mc_lost: radiación del arco
                ! que sale por techo/paredes — pérdida física conocida que
                ! antes dejaba el presupuesto del arco en ~0.95 sin causa
                ! visible. Solo el rank que traza el beam lo cuenta.
                trace: do
                    n_steps = n_steps + 1
                    if (n_steps > MAX_TRACE_STEPS) then
                        call audit_add(AUD_MC_LOST, P_beam * cfg%dt)
                        exit trace
                    end if

                    x = x + dx * step_size
                    y = y + dy * step_size
                    z_pos = z_pos + dz * step_size

                    ! Check bounds - use .not.(<=) to correctly handle NaN
                    r_pos = sqrt(x**2 + y**2)
                    if (.not. (r_pos <= cfg%R_shell)) then
                        call audit_add(AUD_MC_LOST, P_beam * cfg%dt)
                        exit trace
                    end if
                    if (.not. (z_pos >= 0.0_dp .and. z_pos <= cfg%H_total)) then
                        call audit_add(AUD_MC_LOST, P_beam * cfg%dt)
                        exit trace
                    end if

                    ! Find GLOBAL cell indices
                    theta_pos = atan2(y, x)
                    if (theta_pos < 0.0_dp) theta_pos = theta_pos + TWO_PI

                    call find_cell_global(r_pos, theta_pos, z_pos, m, ig, jg, kg)
                    if (ig < 1 .or. kg < 1) then
                        call audit_add(AUD_MC_LOST, P_beam * cfg%dt)
                        exit trace
                    end if
                    if (m%cell_type_global(ig, jg, kg) == 0) then
                        call audit_add(AUD_MC_LOST, P_beam * cfg%dt)
                        exit trace
                    end if

                    ! Sombra de los electrodos (M12): el rayo que entra en
                    ! la columna de grafito (sobre la punta, radio R_elec)
                    ! lo absorbe el electrodo -> sale del horno (auditado
                    ! como perdido, igual que el que escapa por el techo)
                    shadow = .false.
                    do e2 = 1, n_elec
                        if (z_pos < elec(e2)%z_tip) cycle
                        xe2 = cfg%R_pcd * cos(elec(e2)%theta_pos)
                        ye2 = cfg%R_pcd * sin(elec(e2)%theta_pos)
                        if ((x - xe2)**2 + (y - ye2)**2 <= cfg%R_elec**2) shadow = .true.
                    end do
                    if (shadow) then
                        call audit_add(AUD_MC_LOST, P_beam * cfg%dt)
                        exit trace
                    end if

                    ! Impacto (auditoria M12): chatarra (alpha_s > 0.1) o
                    ! superficie del BAÑO (alpha_l >= ALPHA_LIQ_CONT). Antes
                    ! el liquido era un sustituto geometrico z < H_bowl + 0.5
                    ! (rayos absorbidos en gas o chatarra fina bajo esa cota y
                    ! nunca en un baño mas alto).
                    if (alpha_g(ig, jg, kg) > ALPHA_SCRAP_SURF .or. &
                        alpha_lg(ig, jg, kg) >= ALPHA_LIQ_CONT) then
                        ! Acumular POTENCIA en la celda global; el depósito
                        ! real ocurre tras la reducción
                        dep_g(ig, jg, kg) = dep_g(ig, jg, kg) + P_beam
                        exit trace
                    end if

                    ! Atenuacion del gas por el camino (Beer-Lambert, M12):
                    ! la fraccion absorbida se deposita en la celda que
                    ! atraviesa (mismo reparto por absorcion de abajo). La
                    ! espuma la intercepta slag_intercept_arc (una sola
                    ! intercepcion, regla de E2): no se atenua aqui.
                    kap = KAPPA_GAS_ABS * max(1.0_dp - alpha_g(ig, jg, kg) - alpha_lg(ig, jg, kg), 0.0_dp)
                    dP_abs = P_beam * (1.0_dp - exp(-kap * step_size))
                    dep_g(ig, jg, kg) = dep_g(ig, jg, kg) + dP_abs
                    P_beam = P_beam - dP_abs
                end do trace
            end do
        end do

        call MPI_Allreduce(MPI_IN_PLACE, dep_g, size(dep_g), &
                           MPI_DOUBLE_PRECISION, MPI_SUM, MPI_COMM_WORLD, ierr)

        ! Depósito: solo el dueño de cada celda escribe (y audita)
        do kg = 1, m%nz_g
            do jg = 1, m%nth_g
                do ig = 1, m%nr_g
                    if (dep_g(ig, jg, kg) <= 0.0_dp) cycle
                    call global_to_local(m, ig, jg, kg, il, jl, kl, owned)
                    if (.not. owned) cycle
                    ! F2.30 (oct-2026): el rayo que "choca con la chatarra"
                    ! tiene que calentar a la CHATARRA. Antes todo el deposito
                    ! iba a S_arc y solve_energy_3d lo reparte SOLO entre
                    ! liquido y gas (w = alpha_q/(alpha_l+alpha_g)); en un poro
                    ! de chatarra densa (alpha_s 0.985, alpha_g 0.015, sin
                    ! liquido) el gas de poro atrapado se llevaba el 100 %:
                    ! 359 celdas por encima de 6000 K y 54 211 K de maximo a
                    ! los 400 s de B1 v35 (v33: 204 y 11 188 K), justo al
                    ! acabar el bore-in, cuando la punta (0.65 m) queda dentro
                    ! del lecho y los rayos laterales entran en celdas densas.
                    ! Reparto por ABSORCION, el mismo de la DO
                    ! (KAPPA_SOLID_ABS*alpha_s frente a KAPPA_GAS_ABS*(1-alpha_s)):
                    ! Fluent P-1/DO, MFiX TFM, Cai & Modest 2014. Los CFD de
                    ! EAF (Chen 2022 / Ugarte 2024, Logar 2012) no le dan
                    ! radiacion del arco al gas en absoluto: en un lecho denso
                    ! ambas formas coinciden (fraccion al gas ~5e-4). La parte
                    ! del solido va a E_s con el tope de estado solid_arc_room
                    ! del deposito directo (mod_arc_cassie_mayr) y el
                    ! excedente a S_arc: conservativo y auditado.
                    w_s = 0.0_dp
                    if (sol%m_s(il, jl, kl) > SMALL .and. alpha_g(ig, jg, kg) > 0.0_dp) &
                        w_s = KAPPA_SOLID_ABS * alpha_g(ig, jg, kg) / &
                              (KAPPA_SOLID_ABS * alpha_g(ig, jg, kg) + &
                               KAPPA_GAS_ABS * max(1.0_dp - alpha_g(ig, jg, kg), 0.0_dp) + SMALL)
                    Q_s  = w_s * dep_g(ig, jg, kg) * cfg%dt                 ! J al solido
                    ! tope de ESTADO (auditoria M13; antes 2 K por paso)
                    Q_s  = min(Q_s, solid_arc_room(sol%m_s(il, jl, kl), sol%E_s(il, jl, kl), cfg))
                    Q_fl = dep_g(ig, jg, kg) * cfg%dt - Q_s                 ! J al fluido
                    if (Q_s > 0.0_dp) then
                        sol%E_s(il, jl, kl) = sol%E_s(il, jl, kl) + Q_s
                        sol%T_s(il, jl, kl) = solid_T_from_enthalpy( &
                            sol%E_s(il, jl, kl) / sol%m_s(il, jl, kl), cfg)
                        call audit_add(AUD_ARC_DIRECT, Q_s)
                    end if
                    sh%S_arc(il, jl, kl) = sh%S_arc(il, jl, kl) + &
                        Q_fl / (m%vol_global(ig, jg, kg) * cfg%dt + SMALL)
                    call audit_add(AUD_MC_DEPOSIT, Q_fl)
                end do
            end do
        end do

        deallocate(dep_g)

    end subroutine distribute_arc_radiation_mc

    !---------------------------------------------------------------------------
    ! Find GLOBAL cell indices from physical coordinates
    !---------------------------------------------------------------------------
    subroutine find_cell_global(r, theta, z, m, ic, jc, kc)
        real(dp), intent(in)    :: r, theta, z
        type(mesh_t), intent(in) :: m
        integer, intent(out)    :: ic, jc, kc

        integer :: i

        ic = -1; jc = -1; kc = -1

        do i = 1, m%nr_g
            if (r <= m%rf_global(i)) then
                ic = i; exit
            end if
        end do
        if (ic < 0) return

        jc = int(theta / (TWO_PI / real(m%nth_g, dp))) + 1
        jc = max(1, min(m%nth_g, jc))

        do i = 1, m%nz_g
            if (z <= m%zf_global(i)) then
                kc = i; exit
            end if
        end do
    end subroutine find_cell_global

end module mod_arc_radiation_mc
