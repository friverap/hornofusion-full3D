!===============================================================================
! mod_slag_chemistry.f90 - Química de la escoria (E2.3/E2.4, roadmap paper)
!
! Oxidación (interfaz baño-escoria, E2.3):
!     Fe(l) + 1/2 O2 -> FeO(slag)      dH = -272 kJ/mol (exo, a la escoria)
!   Consume el O2 REMANENTE del paso (el que la química del carbono no
!   tomó: alpha_g*rho_g*Y_O2/dt + S_O2_src, con S_O2_src ya negativo),
!   escalado por la eficiencia calibrable eta_feo. El Fe sale del baño
!   (pérdida de rendimiento, auditada) y su entalpía VIAJA con él a la
!   escoria (transferencia interna: los inventarios la capturan); solo el
!   calor de reacción es fuente externa del balance (E_slag_ox).
!
! Reducción (celdas de escoria con carbón SL_C, E2.4):
!     FeO + C -> Fe(l) + CO            dH = +155 kJ/mol FeO (endo)
!   Primer orden en FeO (Morales-like), capada por FeO y C disponibles;
!   el Fe vuelve al baño con su entalpía a T_sl y el CO alimenta las
!   especies del gas (y la espuma, E2.5).
!
! Estabilizadores (riesgo #1 del roadmap: runaway FeO):
!   - cap por O2 disponible del paso (estructural),
!   - cap por fracción de masa del líquido de abajo (F_MAX_FE por paso),
!   - cap térmico Q <= m_sl*cp_sl*DT_MAX_SLAG (recorta la REACCIÓN, no el
!     calor: masa y energía siempre consistentes),
!   - eta_feo conservador por default (0.3).
!===============================================================================
module mod_slag_chemistry
    use mod_constants
    use mod_types_3d
    use mod_slag_3d, only: slag_T_from_E
    use mod_audit, only: audit_add, AUD_FE_YIELD, AUD_FE_RETURN, &
                         AUD_SLAG_OX_E, AUD_SLAG_RED_E, AUD_GAS_VOLFIX, AUD_GAS_VOLFIX_E, &
                         gas_inventory_cell
    use mod_melting_3d, only: liquid_datum_offset
    use mod_foam, only: xi_pretorius
    use mod_mpi_topology, only: mpi_exchange_halos_3d, mpi_allreduce_sum
    use mod_boundary_3d, only: physical_boundary_flags
    implicit none

    real(dp), parameter :: SMALL_SL = 1.0e-6_dp   ! (como mod_slag_3d)
    real(dp), parameter :: MW_FE   = 0.05585_dp   ! kg/mol
    real(dp), parameter :: MW_FEO  = 0.07185_dp   ! kg/mol
    real(dp), parameter :: MW_O2_S = 0.032_dp     ! kg/mol
    real(dp), parameter :: MW_C_S  = 0.012_dp     ! kg/mol
    real(dp), parameter :: MW_CO_S = 0.028_dp     ! kg/mol
    real(dp), parameter :: DH_FEO_OX  = -272.0e3_dp ! J/mol FeO (exo)
    real(dp), parameter :: DH_FEO_RED = +155.0e3_dp ! J/mol FeO (endo)

    ! Cinética de reducción (Morales-like, calibrable en B6)
    real(dp), parameter :: K_RED = 5.0_dp         ! 1/s (prefactor)
    real(dp), parameter :: E_RED = 1.2e5_dp       ! J/mol

    ! Estabilizadores
    real(dp), parameter :: F_MAX_FE     = 0.005_dp ! frac. de m_liq abajo/paso
    real(dp), parameter :: DT_MAX_SLAG  = 50.0_dp  ! K/paso por reacción

contains

    subroutine compute_slag_chemistry(slag, liq, liq_old, gas, sol, sh, m, cfg)
        type(slag_t),  intent(inout) :: slag
        type(phase_t), intent(inout) :: liq, gas
        ! Ancla temporal del liquido (auditoria 12-oct-2026, A1): el transporte
        ! de alpha REHACE el paso desde liq_old%alpha en cada iteracion externa,
        ! asi que la transferencia de Fe escoria<->bano se aplica tambien aqui
        ! (con liq_old%T consistente); antes se descartaba (Fe creado en la
        ! oxidacion, destruido en la reduccion, el audit decia otra cosa)
        type(phase_t), intent(inout) :: liq_old
        type(solid_t), intent(in)    :: sol
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer  :: i, j, k
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: o2_rem, r_feo, dm_feo, dm_fe, dm_o2, dm_b, fcap
        real(dp) :: vol, vol_b, q_rx, q_lim, e_fe, c0
        real(dp) :: r_red, dm_red, dm_c, dm_co
        real(dp) :: b2, x_feo, j_co, h_foam, rho_co, dm_co_cell
        ! Fe hacia/desde la celda de bano de ABAJO de cada celda de escoria
        ! [kg]: sale (oxidacion, a la T del bano) y entra (reduccion, a T_sl).
        ! Pasada 2 sobre las celdas de bano PROPIAS, leyendo la celda de arriba
        ! con halos intercambiados: invariante a la descomposicion en z (antes
        ! la escritura en un halo de k-1 se perdia; auditoria A14)
        real(dp), allocatable :: fe_out(:,:,:), fe_in(:,:,:), t_in(:,:,:)
        logical  :: below, cond
        real(dp) :: ag_new, ag_old, fdil, tsl_r, h_react, co_thr
        ! (auditoria 5, M5-5 bis) CO de la reduccion nacido en una celda de
        ! escoria SIN gas (alpha_g < ALPHA_CUTOFF: escoria sobre bano lleno).
        ! El solver de especies descarta la fuente de una celda sin gas (su
        ! guardia de fase minima) y slag_chem_test perdia el 24 % del CO. El
        ! CO burbujea hacia ARRIBA hasta la primera celda con gas: pasadas
        ! Jacobi con halos (invariante a la descomposicion en z).
        real(dp), allocatable :: co_up(:,:,:), co_new(:,:,:)
        ! (auditoria 5, B5-14) Fe de la reduccion que NO cupo en el bano de
        ! abajo al aplicarlo (dos celdas de escoria apiladas: la de arriba
        ! calculo su cap_b con la alpha del halo, sin lo que la de abajo ya
        ! habia metido): vuelve a la propia celda de escoria en una pasada 3
        ! (auditoria 6, M6-3/M6-4) reduccion en DOS fases: la pasada 1a calcula
        ! lo que cada celda de escoria QUIERE reducir (req_fe, kg de Fe tras
        ! las cotas cinetica y termica); el hueco de cada celda (room, kg,
        ! congelado antes de aplicar nada) se reparte con una regla fija y
        ! local: el Fe va PRIMERO a la propia celda de escoria (la superficie
        ! del bano) hasta su hueco, y el resto al bano de abajo hasta lo que le
        ! deja la escoria de esa celda. Asi ninguna celda recibe mas que su
        ! hueco (B5-14 devolvia el excedente sin cota: Sigma alpha > 1 en la
        ! escoria) y el reparto no depende del orden del lazo ni de la
        ! descomposicion (antes Gauss-Seidel dentro del rank y Jacobi entre
        ! ranks). Con prioridad al bano de abajo la escoria apilada reducia la
        ! mitad (la de arriba se llevaba el hueco de la de abajo).
        real(dp), allocatable :: req_fe(:,:,:), room(:,:,:)
        real(dp) :: dm_fe_req, o_own, o_below, o_up, b_up, gas_after
        real(dp) :: co_loc, co_tot, inc
        integer  :: npass
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        c0 = liquid_datum_offset(cfg)
        cond = slag_condensed_on(cfg)
        allocate(fe_out(lbound(liq%alpha,1):ubound(liq%alpha,1), &
                        lbound(liq%alpha,2):ubound(liq%alpha,2), &
                        lbound(liq%alpha,3):ubound(liq%alpha,3)))
        allocate(fe_in, t_in, co_up, co_new, req_fe, room, mold=fe_out)
        fe_out = 0.0_dp; fe_in = 0.0_dp; t_in = 0.0_dp; co_up = 0.0_dp; co_new = 0.0_dp
        req_fe = 0.0_dp; room = 0.0_dp
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        if (cond) call slag_oxidation_column(slag, liq, liq_old, gas, sh, m, cfg, c0)

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%m_sl(i,j,k) <= SMALL_SL) cycle
                    vol = m%vol(i,j,k)
                    dm_co_cell = 0.0_dp

                    !--------------------------------------------------------
                    ! E2.3: oxidación Fe + 1/2 O2 -> FeO (baño abajo)
                    !--------------------------------------------------------
                    ! (Plan I, I1) con la escoria condensada la oxidacion va
                    ! POR COLUMNA (slag_oxidation_column, antes de este lazo):
                    ! el estencil local contaria dos veces el mismo O2
                    if (.not. cond .and. m%cell_type(i,j,k-1) /= 0) then
                    if (liq%alpha(i,j,k-1) > SMALL_SL) then
                        vol_b = m%vol(i,j,k-1)
                        ! O2 remanente del paso en la celda de escoria
                        o2_rem = max(0.0_dp, gas%alpha(i,j,k) * &
                            gas%rho(i,j,k) * sh%Y_O2(i,j,k) / cfg%dt &
                            + sh%S_O2_src(i,j,k))
                        r_feo = cfg%slag_eta_feo * o2_rem * &
                                (MW_FEO / (0.5_dp * MW_O2_S))
                        dm_feo = r_feo * vol * cfg%dt
                        ! cap por Fe extraíble del baño de abajo
                        dm_fe = dm_feo * MW_FE / MW_FEO
                        dm_fe = min(dm_fe, F_MAX_FE * liq%alpha(i,j,k-1) * &
                                    liq%rho(i,j,k-1) * vol_b)
                        dm_feo = dm_fe * MW_FEO / MW_FE
                        ! cap térmico: recorta la REACCIÓN completa
                        q_rx = dm_feo * (-DH_FEO_OX) / MW_FEO
                        q_lim = slag%m_sl(i,j,k) * cfg%cp_slag * DT_MAX_SLAG
                        if (q_rx > q_lim .and. q_rx > SMALL) then
                            dm_feo = dm_feo * q_lim / q_rx
                            dm_fe  = dm_feo * MW_FE / MW_FEO
                            q_rx   = q_lim
                        end if

                        if (dm_feo > SMALL) then
                            dm_o2 = dm_feo * (0.5_dp * MW_O2_S) / MW_FEO
                            ! Fe sale del baño (pérdida de rendimiento)
                            e_fe = dm_fe * (liq%cp(i,j,k-1) * &
                                   liq%T(i,j,k-1) + c0)
                            fe_out(i,j,k) = fe_out(i,j,k) + dm_fe   ! pasada 2
                            ! FeO a la escoria; entalpía del Fe VIAJA + exo
                            ! (auditoria 19, fisica M1 = B3-9) la escoria gana el
                            ! FeO a SU temperatura (su dato es m cp_sl T) mas el
                            ! exotermico completo; el Fe sale del baño con su
                            ! entalpia (cp_l T + C0). La diferencia de datos
                            ! entre fases es parte del termino de reaccion
                            ! auditado (antes la escoria recibia e_fe + q: 168 de
                            ! 272 kJ/mol). (El O2 sale del inventario del gas)
                            tsl_r = slag%E_sl(i,j,k) / max(slag%m_sl(i,j,k) * cfg%cp_slag, SMALL)
                            slag%m_X(i,j,k,SL_FEO) = &
                                slag%m_X(i,j,k,SL_FEO) + dm_feo
                            slag%m_sl(i,j,k) = slag%m_sl(i,j,k) + dm_feo
                            slag%E_sl(i,j,k) = slag%E_sl(i,j,k) + dm_feo * cfg%cp_slag * tsl_r + q_rx
                            ! (dirigida A19, B3) T coherente para la reduccion de la
                            ! misma celda (tasa, h_react, e_fe y add_fe la leen)
                            slag%T_sl(i,j,k) = slag%E_sl(i,j,k) / (slag%m_sl(i,j,k) * cfg%cp_slag)
                            ! O2 consumido: sumidero adicional de especies
                            sh%S_O2_src(i,j,k) = sh%S_O2_src(i,j,k) - &
                                dm_o2 / (vol * cfg%dt)
                            call audit_add(AUD_FE_YIELD, dm_fe)
                            call audit_add(AUD_SLAG_OX_E, q_rx + dm_feo * cfg%cp_slag * tsl_r - e_fe)
                        end if
                    end if
                    end if

                    !--------------------------------------------------------
                    ! E2.4: reducción FeO + C -> Fe + CO (dentro de la capa)
                    !--------------------------------------------------------
                    if (slag%m_X(i,j,k,SL_C) > SMALL .and. &
                        slag%m_X(i,j,k,SL_FEO) > SMALL .and. &
                        slag%T_sl(i,j,k) > 800.0_dp) then
                        r_red = K_RED * exp(-E_RED / (R_GAS * &
                                slag%T_sl(i,j,k))) * slag%m_X(i,j,k,SL_FEO)
                        dm_red = r_red * cfg%dt                       ! kg FeO
                        dm_red = min(dm_red, slag%m_X(i,j,k,SL_FEO))
                        dm_red = min(dm_red, slag%m_X(i,j,k,SL_C) * &
                                     MW_FEO / MW_C_S)
                        ! cap térmico (endo: enfría la escoria)
                        q_rx = dm_red * DH_FEO_RED / MW_FEO
                        q_lim = slag%m_sl(i,j,k) * cfg%cp_slag * DT_MAX_SLAG
                        if (q_rx > q_lim .and. q_rx > SMALL) then
                            dm_red = dm_red * q_lim / q_rx
                            q_rx   = q_lim
                        end if
                        ! (M6-4) solo la SOLICITUD; se aplica en la pasada 1b
                        if (dm_red > SMALL) req_fe(i,j,k) = dm_red * MW_FE / MW_FEO
                    end if
                end do
            end do
        end do

        ! ── Huecos congelados de las celdas de bano (kg de Fe que caben) y
        ! solicitudes, con halos: la pasada 1b solo lee estos valores
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    room(i,j,k) = max(0.0_dp, liq_cap(sol%alpha_s(i,j,k), slag%alpha_sl(i,j,k)) &
                                  - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k)
                    ! (Plan H, auditoria 18 A1) con la escoria CONDENSADA la
                    ! capa esta compactada (sin gas): el hueco de la reduccion es
                    ! el volumen que libera la propia escoria reducida, (FeO +
                    ! C)/rho_sl, ~3.75 veces el del Fe que vuelve: el Fe propio
                    ! siempre cabe (antes solo reducia la celda tope con gas)
                    if (cond) room(i,j,k) = room(i,j,k) + req_fe(i,j,k) * liq%rho(i,j,k) &
                        * (MW_FEO + MW_C_S) / (cfg%rho_slag * MW_FE)
                end do
            end do
        end do
        call mpi_exchange_halos_3d(room,   m%topo)
        call mpi_exchange_halos_3d(req_fe, m%topo)

        ! ── Pasada 1b: aplicar la reduccion con el reparto fijo, T de la
        ! escoria y espuma
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%m_sl(i,j,k) <= SMALL_SL) cycle
                    vol = m%vol(i,j,k)
                    dm_co_cell = 0.0_dp
                    ! Fe que la escoria de ENCIMA mete en esta celda (su
                    ! sobrante tras llenar su propio hueco)
                    o_own = min(req_fe(i,j,k), room(i,j,k))
                    b_up = 0.0_dp
                    if (m%cell_type(i,j,k+1) /= 0) then
                        o_up = min(req_fe(i,j,k+1), room(i,j,k+1))
                        b_up = min(req_fe(i,j,k+1) - o_up, max(0.0_dp, room(i,j,k) - o_own))
                    end if
                    if (req_fe(i,j,k) > 0.0_dp) then
                        dm_fe_req = req_fe(i,j,k)
                        below = (m%cell_type(i,j,k-1) /= 0)
                        ! (M4-5) el sobrante al bano de ABAJO, hasta lo que le
                        ! deja la escoria de esa celda
                        dm_b = 0.0_dp
                        if (below) then
                            o_below = min(req_fe(i,j,k-1), room(i,j,k-1))
                            dm_b = min(dm_fe_req - o_own, max(0.0_dp, room(i,j,k-1) - o_below))
                        end if
                        dm_fe = o_own + dm_b
                        if (dm_fe > SMALL) then
                            ! si no cabe todo, el FeO queda sin reducir
                            ! (conservativo: nada se crea ni se pierde)
                            fcap = dm_fe / dm_fe_req
                            dm_red = dm_fe_req * MW_FEO / MW_FE * fcap
                            dm_c  = dm_red * MW_C_S / MW_FEO
                            dm_co = dm_red * MW_CO_S / MW_FEO
                            q_rx  = dm_red * DH_FEO_RED / MW_FEO
                            slag%m_X(i,j,k,SL_FEO) = &
                                slag%m_X(i,j,k,SL_FEO) - dm_red
                            slag%m_X(i,j,k,SL_C) = &
                                slag%m_X(i,j,k,SL_C) - dm_c
                            slag%m_sl(i,j,k) = slag%m_sl(i,j,k) &
                                               - dm_red - dm_c
                            ! (A1) la escoria condensada ocupa el volumen de su
                            ! masa: el volumen liberado queda disponible ya (para
                            ! el CO de abajo y la restriccion de volumen)
                            if (cond) slag%alpha_sl(i,j,k) = slag%m_sl(i,j,k) &
                                / (cfg%rho_slag * vol)
                            ! entalpia del Fe que VIAJA (a T_sl) + endo
                            e_fe = dm_fe * (cfg%cp_l * slag%T_sl(i,j,k) + c0)
                            if (dm_b > 0.0_dp) then
                                fe_in(i,j,k) = fe_in(i,j,k) + dm_b
                                t_in(i,j,k) = slag%T_sl(i,j,k)
                            end if
                            if (dm_fe - dm_b > 0.0_dp) &
                                call add_fe(i, j, k, dm_fe - dm_b, slag%T_sl(i,j,k))
                            ! (fisica M1 = B3-9) la escoria pierde la entalpia
                            ! sensible de los REACTIVOS a su T (dato m cp_sl T)
                            ! mas el endotermico; el Fe entra al baño con e_fe y
                            ! la diferencia (CO + datos) es parte del termino de
                            ! reaccion auditado (antes la escoria se enfriaba
                            ! 24 de 155 kJ/mol)
                            h_react = (dm_red + dm_c) * cfg%cp_slag * slag%T_sl(i,j,k)
                            slag%E_sl(i,j,k) = slag%E_sl(i,j,k) - h_react - q_rx
                            ! (M6-3) CO al gas de la celda solo si le QUEDA gas
                            ! despues del Fe (el propio y el de la escoria de
                            ! encima); si no, sube (pasada 3). Antes se decidia
                            ! con la alpha_g previa y el CO se perdia cuando el
                            ! Fe llenaba el hueco.
                            gas_after = 1.0_dp - sol%alpha_s(i,j,k) - slag%alpha_sl(i,j,k) &
                                      - liq%alpha(i,j,k) - b_up / (liq%rho(i,j,k) * vol)
                            ! (auditoria dirigida A18-1a/b) con la escoria
                            ! condensada el hueco que libera la reduccion se
                            ! rellena AQUI de gas (antes del transporte de especies,
                            ! que descarta fuentes en celdas sin gas), auditado
                            ! como el volfix: masa, inventario de energia y
                            ! dilucion de las Y (el gas creado no trae especies).
                            ! En condensado el Fe propio cabe en el volumen
                            ! liberado (b_up = 0): el CO decide con el gas REAL
                            if (cond) then
                                ag_new = max(0.0_dp, 1.0_dp - sol%alpha_s(i,j,k) &
                                    - slag%alpha_sl(i,j,k) - liq%alpha(i,j,k))
                                if (ag_new > gas%alpha(i,j,k)) then
                                    ag_old = max(gas%alpha(i,j,k), 0.0_dp)
                                    call audit_add(AUD_GAS_VOLFIX, (ag_new - ag_old) &
                                        * gas%rho(i,j,k) * vol)
                                    call audit_add(AUD_GAS_VOLFIX_E, &
                                        gas_inventory_cell(ag_new, gas%T(i,j,k), sh%p(i,j,k), &
                                                           gas%cp(i,j,k), vol, cfg) &
                                      - gas_inventory_cell(ag_old, gas%T(i,j,k), sh%p(i,j,k), &
                                                           gas%cp(i,j,k), vol, cfg))
                                    fdil = ag_old / ag_new
                                    sh%Y_O2(i,j,k)  = sh%Y_O2(i,j,k)  * fdil
                                    sh%Y_CO(i,j,k)  = sh%Y_CO(i,j,k)  * fdil
                                    sh%Y_CO2(i,j,k) = sh%Y_CO2(i,j,k) * fdil
                                    gas%alpha(i,j,k) = ag_new
                                end if
                                gas_after = gas%alpha(i,j,k)
                                ! (auditoria 19, A19-C1) el CO va a la celda solo
                                ! si queda gas RESUELTO (>= ALPHA_FLOW_CUTOFF): un
                                ! gas de ~1e-5 bajo la escoria lo compacta el sort
                                ! del paso siguiente (destruido con sus especies);
                                ! si no, sube (co_up) al gas de la cima. (m_dil_CO
                                ! NO es perdida: es el termino -Y S_gas de la forma
                                ! no conservativa de las especies, M14)
                                if (gas_after < ALPHA_FLOW_CUTOFF) gas_after = 0.0_dp
                            end if
                            if (gas_after >= ALPHA_CUTOFF) then
                                sh%S_CO_src(i,j,k) = sh%S_CO_src(i,j,k) + &
                                    dm_co / (vol * cfg%dt)
                            else
                                co_up(i,j,k) = co_up(i,j,k) + dm_co
                            end if
                            dm_co_cell = dm_co
                            call audit_add(AUD_FE_RETURN, dm_fe)
                            call audit_add(AUD_SLAG_RED_E, q_rx + h_react - e_fe)
                        end if
                    end if

                    ! T de la escoria consistente tras las reacciones
                    if (slag%m_sl(i,j,k) > SMALL_SL) &
                        call slag_T_from_E(slag, i, j, k, cfg)

                    !--------------------------------------------------------
                    ! E2.5: espuma local (atributo óptico): H = xi * j_CO
                    !--------------------------------------------------------
                    if (slag%m_sl(i,j,k) > SMALL_SL) then
                        b2 = slag%m_X(i,j,k,SL_CAO) / &
                             max(slag%m_X(i,j,k,SL_SIO2), SMALL)
                        x_feo = slag%m_X(i,j,k,SL_FEO) / slag%m_sl(i,j,k)
                        ! dm_co de la reducción de ESTA celda este paso
                        ! (0 si la rama no corrió)
                        rho_co = 101325.0_dp * MW_CO_S / &
                                 (R_GAS * max(slag%T_sl(i,j,k), 300.0_dp))
                        j_co = dm_co_cell / (cfg%dt * rho_co * &
                               max(m%Az(i,j,k), SMALL))
                        h_foam = xi_pretorius(b2, x_feo, &
                                 slag%T_sl(i,j,k)) * j_co
                        slag%alpha_foam(i,j,k) = min(1.0_dp, &
                            h_foam / max(m%dz(k), SMALL))
                    else
                        slag%alpha_foam(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do

        ! ── Pasada 2: celdas de bano PROPIAS reciben el Fe de la escoria de
        ! arriba (halos de las celdas de escoria intercambiados)
        call mpi_exchange_halos_3d(fe_out, m%topo)
        call mpi_exchange_halos_3d(fe_in,  m%topo)
        call mpi_exchange_halos_3d(t_in,   m%topo)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (fe_out(i,j,k+1) > 0.0_dp) call remove_fe(i, j, k, fe_out(i,j,k+1))
                    ! (M6-4) cabe por construccion (reparto de la pasada 1b)
                    if (fe_in(i,j,k+1) > 0.0_dp) call add_fe(i, j, k, fe_in(i,j,k+1), t_in(i,j,k+1))
                end do
            end do
        end do
        deallocate(fe_out, fe_in, t_in, req_fe, room)

        ! ── Pasada 3: el CO nacido sin gas sube hasta la primera celda con gas
        ! (co_up(k) es lo pendiente de pasar a k+1; cada pasada mueve una
        ! capa; en el techo fisico sin gas se deposita igual, el solver lo
        ! descartaria y quedaria sin columna)
        co_thr = ALPHA_CUTOFF
        if (cond) co_thr = ALPHA_FLOW_CUTOFF
        co_loc = sum(co_up(istart:iend, jstart:jend, kstart:kend))
        call mpi_allreduce_sum(co_loc, co_tot, m%topo)
        npass = 0
        do while (co_tot > 0.0_dp .and. npass < m%nz_g)
            npass = npass + 1
            call mpi_exchange_halos_3d(co_up, m%topo)
            co_new = 0.0_dp
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0 .or. m%cell_type(i,j,k-1) == 0) cycle
                        inc = co_up(i,j,k-1)
                        if (inc <= 0.0_dp) cycle
                        ! (dirigida A19, M1) con la escoria condensada, el mismo
                        ! umbral de gas resuelto que la celda propia: el gas de
                        ! ~1e-5 que rellena la reduccion de la celda de arriba
                        ! lo compacta el sort (el CO se destruiria)
                        if (gas%alpha(i,j,k) >= co_thr .or. (k == kend .and. at_zmax)) then
                            sh%S_CO_src(i,j,k) = sh%S_CO_src(i,j,k) + inc / (m%vol(i,j,k) * cfg%dt)
                        else
                            co_new(i,j,k) = inc
                        end if
                    end do
                end do
            end do
            co_up = co_new
            co_loc = sum(co_up(istart:iend, jstart:jend, kstart:kend))
            call mpi_allreduce_sum(co_loc, co_tot, m%topo)
        end do
        deallocate(co_up, co_new)

    contains

        ! Fe que sale del bano a la T del bano: alpha baja en el iterado y en el
        ! ancla temporal, T no cambia (entalpia especifica intacta)
        subroutine remove_fe(ii, jj, kk, dm)
            integer, intent(in)  :: ii, jj, kk
            real(dp), intent(in) :: dm
            real(dp) :: da
            da = dm / (liq%rho(ii,jj,kk) * m%vol(ii,jj,kk))
            liq%alpha(ii,jj,kk)     = max(0.0_dp, liq%alpha(ii,jj,kk) - da)
            liq_old%alpha(ii,jj,kk) = max(0.0_dp, liq_old%alpha(ii,jj,kk) - da)
        end subroutine remove_fe

        ! Fe que entra al bano a T_fe: mezcla de entalpias e_l = cp T + C0
        ! (lineal en T: conserva la energia exactamente) en el iterado y en el
        ! ancla temporal; una celda sin liquido toma T_fe (nunca la T rancia)
        subroutine add_fe(ii, jj, kk, dm, T_fe)
            integer, intent(in)  :: ii, jj, kk
            real(dp), intent(in) :: dm, T_fe
            real(dp) :: da, a0
            da = dm / (liq%rho(ii,jj,kk) * m%vol(ii,jj,kk))
            a0 = max(liq_old%alpha(ii,jj,kk), 0.0_dp)
            liq_old%T(ii,jj,kk) = (a0 * liq_old%T(ii,jj,kk) + da * T_fe) / (a0 + da)
            liq_old%alpha(ii,jj,kk) = a0 + da
            a0 = max(liq%alpha(ii,jj,kk), 0.0_dp)
            liq%T(ii,jj,kk) = (a0 * liq%T(ii,jj,kk) + da * T_fe) / (a0 + da)
            liq%alpha(ii,jj,kk) = a0 + da
        end subroutine add_fe

    end subroutine compute_slag_chemistry

    !---------------------------------------------------------------------------
    ! (Plan I, I1, 17-oct-2026) Oxidacion Fe + 1/2 O2 -> FeO POR COLUMNA con la
    ! escoria CONDENSADA. La capa compactada no tiene gas: el estencil local
    ! (O2 de la celda de escoria, Fe de la de abajo) solo actuaba donde una
    ! celda parcial tocaba el baño y la capa resuelta aislaba el metal del O2
    ! (slag_chem_flow 2.7 -> 0.99 kg). Por columna (i,j), en el tramo de
    ! escoria RESUELTA (alpha_sl >= ALPHA_FLOW_CUTOFF) MAS BAJO (kb = su celda
    ! inferior, kt = la superior):
    !   - O2: el remanente del paso del gas de kt mas el de kt+1 (gas libre
    !     encima), cada uno si la celda tiene gas (alpha_g >= ALPHA_CUTOFF);
    !   - Fe: del acero de kb hasta su cota y el resto del baño de kb-1;
    !   - FeO, su masa y su energia (dato coherente, auditoria 19) a la
    !     escoria de kb, con las MISMAS cotas que el estencil local (Fe
    !     extraible F_MAX_FE del acero de origen; termica sobre la escoria de kb).
    ! Patron invariante a la descomposicion: tramos por mascara con halos y
    ! MIN global 2D; los valores de las celdas elegidas (cada una con UN solo
    ! dueño) en planos 2D con una suma global exacta; mismo calculo en todos
    ! los ranks y cada uno escribe sus celdas propias. La alpha_sl no cambia
    ! (como el estencil local): el reordenamiento del paso siguiente la deriva
    ! de la masa. (dirigida I1, BAJO-5) corre ANTES de congelar el hueco de la
    ! reduccion: el Fe oxidado de kb ya libero su volumen y la reduccion puede
    ! ocuparlo aunque el FeO nuevo aun no figure en alpha_sl (Sigma alpha > 1
    ! en kb hasta el sort, que extiende el tramo sobre el gas; solo queda si la
    ! columna no tiene gas hasta el techo).
    !---------------------------------------------------------------------------
    subroutine slag_oxidation_column(slag, liq, liq_old, gas, sh, m, cfg, c0)
        use mpi
        type(slag_t),   intent(inout) :: slag
        type(phase_t),  intent(inout) :: liq, liq_old
        type(phase_t),  intent(in)    :: gas
        type(shared_t), intent(inout) :: sh
        type(mesh_t),   intent(in)    :: m
        type(config_t), intent(in)    :: cfg
        real(dp),       intent(in)    :: c0
        ! planos 2D: gas de kt y de kt+1, O2 (kg/s) en kt y kt+1,
        ! Fe extraible en kb y kb-1, cota termica de la escoria de kb
        integer, parameter :: P_AG_KT = 1, P_O2_KT = 2, P_O2_KT1 = 3, P_AG_KT1 = 4, &
                              P_CAP_KB = 5, P_CAP_KBM = 6, P_QLIM = 7, NPL = 7
        real(dp), allocatable :: mask(:,:,:), pl(:,:,:)
        integer,  allocatable :: kb_g(:,:), kt_g(:,:)
        integer  :: i, j, k, ig, jg, i0, j0, k0, kg, kb, kt, kl, ierr
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: o2_rate, o2_kt, o2_kt1, cap, dm_feo, dm_fe, dm_o2, q_rx, q_lim, tsl_r, dm_fe_kb
        real(dp) :: dm_fe_kbm, o2_s1

        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
            i0 = m%topo%iglobal_start; j0 = m%topo%jglobal_start
            k0 = m%topo%kglobal_start
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
            i0 = 1; j0 = 1; k0 = 1
        end if

        ! ── 1. Tramos de escoria RESUELTA (alpha_sl >= ALPHA_FLOW_CUTOFF):
        ! mascara con halos (los fisicos quedan en 0). (dirigida I1, MEDIO-4) la
        ! quimica corre antes del reordenamiento del paso: el upwind deja trazas
        ! de 1e-4..1e-3 en la celda de baño bajo la interfaz y con el umbral
        ! ALPHA_CUTOFF esa traza era kb (FeO a una masa diminuta y la cota
        ! termica sobre ella anulaba la oxidacion de la columna). La traza queda
        ! como parte del acero de kb-1
        allocate(mask, mold=liq%alpha)
        mask = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (slag%m_sl(i,j,k) > SMALL_SL .and. &
                        slag%alpha_sl(i,j,k) >= ALPHA_FLOW_CUTOFF) mask(i,j,k) = 1.0_dp
                end do
            end do
        end do
        call mpi_exchange_halos_3d(mask, m%topo)

        ! kb = la base mas baja de un tramo; kt = el tope mas bajo, que es el
        ! del MISMO tramo (los tramos son disjuntos y ordenados en z)
        allocate(kb_g(m%nr_g, m%nth_g), kt_g(m%nr_g, m%nth_g))
        kb_g = m%nz_g + 1; kt_g = m%nz_g + 1
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (mask(i,j,k) < 0.5_dp) cycle
                    ig = i0 + i - 1; jg = j0 + j - 1; kg = k0 + k - 1
                    if (mask(i,j,k-1) < 0.5_dp) kb_g(ig,jg) = min(kb_g(ig,jg), kg)
                    if (mask(i,j,k+1) < 0.5_dp) kt_g(ig,jg) = min(kt_g(ig,jg), kg)
                end do
            end do
        end do
        if (m%is_parallel) then
            call MPI_Allreduce(MPI_IN_PLACE, kb_g, size(kb_g), MPI_INTEGER, MPI_MIN, &
                               m%topo%comm_cart, ierr)
            call MPI_Allreduce(MPI_IN_PLACE, kt_g, size(kt_g), MPI_INTEGER, MPI_MIN, &
                               m%topo%comm_cart, ierr)
        end if

        ! ── 2. Valores de las celdas elegidas (un solo dueño por valor)
        allocate(pl(m%nr_g, m%nth_g, NPL))
        pl = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    ig = i0 + i - 1; jg = j0 + j - 1; kg = k0 + k - 1
                    kb = kb_g(ig,jg); kt = kt_g(ig,jg)
                    if (kb > m%nz_g) cycle
                    if (kg == kt) then
                        pl(ig,jg,P_AG_KT) = gas%alpha(i,j,k)
                        pl(ig,jg,P_O2_KT) = o2_remaining(i, j, k) * m%vol(i,j,k)
                    end if
                    if (kg == kt + 1) then
                        pl(ig,jg,P_O2_KT1) = o2_remaining(i, j, k) * m%vol(i,j,k)
                        pl(ig,jg,P_AG_KT1) = gas%alpha(i,j,k)
                    end if
                    if (kg == kb) then
                        pl(ig,jg,P_CAP_KB) = F_MAX_FE * liq%alpha(i,j,k) * liq%rho(i,j,k) * m%vol(i,j,k)
                        pl(ig,jg,P_QLIM)   = slag%m_sl(i,j,k) * cfg%cp_slag * DT_MAX_SLAG
                    end if
                    if (kg == kb - 1 .and. liq%alpha(i,j,k) > SMALL_SL) then
                        pl(ig,jg,P_CAP_KBM) = F_MAX_FE * liq%alpha(i,j,k) * liq%rho(i,j,k) * m%vol(i,j,k)
                    end if
                end do
            end do
        end do
        if (m%is_parallel) call MPI_Allreduce(MPI_IN_PLACE, pl, size(pl), MPI_DOUBLE_PRECISION, &
                                              MPI_SUM, m%topo%comm_cart, ierr)

        ! ── 3. Reaccion por columna (mismo calculo en todo rank) y escritura
        ! de las celdas propias
        do j = jstart, jend
            do i = istart, iend
                ig = i0 + i - 1; jg = j0 + j - 1
                kb = kb_g(ig,jg); kt = kt_g(ig,jg)
                if (kb > m%nz_g) cycle
                ! (dirigida I1, MEDIO-3) O2 del gas de kt MAS el de kt+1 (antes
                ! una sola celda por el umbral alpha_g(kt) >= ALPHA_FLOW_CUTOFF:
                ! la tasa saltaba ~90 veces); solo celdas con gas (alpha_g >=
                ! ALPHA_CUTOFF: el solver de especies descarta el sumidero de
                ! una celda sin gas y el O no cerraria)
                o2_kt = 0.0_dp; o2_kt1 = 0.0_dp
                if (pl(ig,jg,P_AG_KT)  >= ALPHA_CUTOFF) o2_kt  = pl(ig,jg,P_O2_KT)
                if (pl(ig,jg,P_AG_KT1) >= ALPHA_CUTOFF) o2_kt1 = pl(ig,jg,P_O2_KT1)
                o2_rate = o2_kt + o2_kt1
                if (o2_rate <= 0.0_dp) cycle
                ! (dirigida I1, MEDIO-2) Fe del acero de kb y del baño de kb-1
                ! con la suma de sus cotas (antes una sola fuente por umbral:
                ! la cota saltaba ~100 veces con alpha_l(kb) en torno a 0.01)
                cap = pl(ig,jg,P_CAP_KB) + pl(ig,jg,P_CAP_KBM)
                if (cap <= 0.0_dp) cycle
                dm_feo = cfg%slag_eta_feo * o2_rate * (MW_FEO / (0.5_dp * MW_O2_S)) * cfg%dt
                dm_fe  = min(dm_feo * MW_FE / MW_FEO, cap)
                dm_feo = dm_fe * MW_FEO / MW_FE
                q_rx  = dm_feo * (-DH_FEO_OX) / MW_FEO
                q_lim = pl(ig,jg,P_QLIM)
                if (q_rx > q_lim .and. q_rx > SMALL) then
                    dm_feo = dm_feo * q_lim / q_rx
                    dm_fe  = dm_feo * MW_FE / MW_FEO
                    q_rx   = q_lim
                end if
                if (dm_feo <= SMALL) cycle
                ! Fe sale del acero a su entalpia (cp_l T + C0): primero de kb
                ! hasta su cota, el resto del baño de kb-1 hasta la suya
                ! (dirigida I1-b, B-2: tras la cota termica dm_fe se recalcula y
                ! podia pasar 1 ulp de la cota; el resto iba a kb-1 aunque no
                ! tuviera acero). FeO, calor y O2 se rehacen desde ese dm_fe
                ! (cada parte <= su cota exacta; q_rx puede pasar q_lim en ~ulp)
                dm_fe_kb  = min(dm_fe, pl(ig,jg,P_CAP_KB))
                dm_fe_kbm = min(dm_fe - dm_fe_kb, pl(ig,jg,P_CAP_KBM))
                dm_fe  = dm_fe_kb + dm_fe_kbm
                dm_feo = dm_fe * MW_FEO / MW_FE
                q_rx   = dm_feo * (-DH_FEO_OX) / MW_FEO
                if (dm_feo <= SMALL) cycle
                dm_o2 = dm_feo * (0.5_dp * MW_O2_S) / MW_FEO
                call take_fe(i, j, kb - k0 + 1, dm_fe_kb)
                call take_fe(i, j, kb - 1 - k0 + 1, dm_fe_kbm)
                ! FeO a la escoria de kb a SU temperatura + el exotermico
                kl = kb - k0 + 1
                if (kl >= kstart .and. kl <= kend) then
                    tsl_r = slag%E_sl(i,j,kl) / max(slag%m_sl(i,j,kl) * cfg%cp_slag, SMALL)
                    slag%m_X(i,j,kl,SL_FEO) = slag%m_X(i,j,kl,SL_FEO) + dm_feo
                    slag%m_sl(i,j,kl) = slag%m_sl(i,j,kl) + dm_feo
                    slag%E_sl(i,j,kl) = slag%E_sl(i,j,kl) + dm_feo * cfg%cp_slag * tsl_r + q_rx
                    slag%T_sl(i,j,kl) = slag%E_sl(i,j,kl) / (slag%m_sl(i,j,kl) * cfg%cp_slag)
                    call audit_add(AUD_SLAG_OX_E, q_rx + dm_feo * cfg%cp_slag * tsl_r)
                end if
                ! O2 consumido del gas de kt y kt+1 en proporcion a su aporte;
                ! (dirigida I1-b, B-1) la segunda parte es el RESTO: las dos
                ! suman dm_o2 salvo el redondeo de la resta (~1 ulp)
                o2_s1 = dm_o2
                if (o2_kt1 > 0.0_dp) o2_s1 = dm_o2 * (o2_kt / o2_rate)
                kl = kt - k0 + 1
                if (o2_kt > 0.0_dp .and. kl >= kstart .and. kl <= kend) &
                    sh%S_O2_src(i,j,kl) = sh%S_O2_src(i,j,kl) - o2_s1 / (m%vol(i,j,kl) * cfg%dt)
                kl = kt + 1 - k0 + 1
                if (o2_kt1 > 0.0_dp .and. kl >= kstart .and. kl <= kend) &
                    sh%S_O2_src(i,j,kl) = sh%S_O2_src(i,j,kl) - (dm_o2 - o2_s1) / (m%vol(i,j,kl) * cfg%dt)
            end do
        end do
        deallocate(mask, pl, kb_g, kt_g)

    contains

        ! Fe que sale del acero de la celda local (ii,jj,kk) si es propia
        subroutine take_fe(ii, jj, kk, dm)
            integer,  intent(in) :: ii, jj, kk
            real(dp), intent(in) :: dm
            real(dp) :: da
            if (dm <= 0.0_dp .or. kk < kstart .or. kk > kend) return
            da = dm / (liq%rho(ii,jj,kk) * m%vol(ii,jj,kk))
            liq%alpha(ii,jj,kk)     = max(0.0_dp, liq%alpha(ii,jj,kk) - da)
            liq_old%alpha(ii,jj,kk) = max(0.0_dp, liq_old%alpha(ii,jj,kk) - da)
            call audit_add(AUD_FE_YIELD, dm)
            call audit_add(AUD_SLAG_OX_E, -dm * (liq%cp(ii,jj,kk) * liq%T(ii,jj,kk) + c0))
        end subroutine take_fe

        ! O2 remanente del paso en la celda [kg/(m3 s)] (como el estencil local)
        real(dp) function o2_remaining(ii, jj, kk) result(r)
            integer, intent(in) :: ii, jj, kk
            r = max(0.0_dp, gas%alpha(ii,jj,kk) * gas%rho(ii,jj,kk) * sh%Y_O2(ii,jj,kk) / cfg%dt &
                    + sh%S_O2_src(ii,jj,kk))
        end function o2_remaining

    end subroutine slag_oxidation_column

end module mod_slag_chemistry
