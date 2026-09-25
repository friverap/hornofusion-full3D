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
    use mod_probe, only: probe_active_now, probe_current_step
    use mod_face_flux
    use mod_mpi_topology, only: mpi_allreduce_max, mpi_exchange_halos_3d
    use mod_audit, only: audit_add, AUD_ALPHA_CLIP_MASS, AUD_SPILL_MASS
    use mod_workspace, only: ensure_workspace, ws_Fr, ws_Fth, ws_Fz, &
                             ws_Mr, ws_Mth, ws_Mz, ws_lim, ws_flux_valid, &
                             ws_Fc_r, ws_Fc_th, ws_Fc_z, ws_Fc_lk_r, ws_Fc_lk_th, &
                             ws_Fc_lk_z, ws_Fc_valid, ws_liq_cont, ws_liq_cont_valid, &
                             ws_ud_r, ws_ud_th, ws_ud_z, ws_ut, ws_drift_valid
    implicit none

    logical, save :: fallback_warned = .false.
    ! Clip auditado por PASO (sep-2026): solve_volume_fraction corre en
    ! cada iteración externa y rehace alpha desde alpha_old, así que el
    ! clip real del paso es el de la ÚLTIMA iteración, no la suma (B1 v9:
    ! el audit contaba 13.1 t con 2.6 t perdidas — exactamente x5 outers).
    ! Se audita la diferencia respecto a la llamada anterior del mismo paso.
    real(dp), save :: clip_step_prev = 0.0_dp
    integer,  save :: clip_step_id = -huge(1)
    real(dp), save :: spill_step_prev = 0.0_dp
    integer,  save :: spill_step_id = -huge(1)

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
        integer :: icfl, jcfl, kcfl
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: cfl_loc, cfl_max, cfl_glob, dt_sub, a_pre, flux_net
        integer, parameter :: N_SUB_MAX = 128
        ! Barridos del limitador: el "no cabe" se propaga UNA celda por
        ! barrido; una columna que se llena desde el fondo necesita ~nz.
        ! Se itera hasta convergencia (B1 v9: con 3 barridos fijos, el
        ! drenaje súbito de 425 s recortó 2.6 t en columnas de 10 celdas).
        integer, parameter :: N_LIM_MAX = 256
        integer, parameter :: N_SPILL_MAX = 128   ! >= nz de produccion (84): la cascada avanza una celda por pasada
        integer :: ilim, ipass, n_it_max
        real(dp) :: inflow, outflow, room, dlim, dlim_glob, clip_call
        real(dp) :: dlim_exit, cap, exc, room_up, give, exc_glob, spill_call
        real(dp) :: exc0_glob
        real(dp), allocatable :: a_new(:,:,:), lim_new(:,:,:)
        ! Velocidad EFECTIVA del liquido para el transporte de alpha: la del
        ! momento donde el liquido es fase CONTINUA (liq_continuous, Bug 15);
        ! donde es disperso (sin ecuacion de momento propia) la del gas mas la
        ! velocidad terminal de sedimentacion hacia abajo (cierre de
        ! deslizamiento algebraico, Manninen et al. 1996). Antes era 0:
        ! la niebla salpicada por el arco quedaba suspendida (B1 v11, 3.6 t).
        real(dp), allocatable :: ur_e(:,:,:), uth_e(:,:,:), uz_e(:,:,:)
        ! Flujo de masa SIN alpha (rho_f u_f A) por las caras + de cada celda,
        ! fijo durante los sub-pasos (las velocidades no cambian; solo alpha)
        real(dp), allocatable :: Gr(:,:,:), Gth(:,:,:), Gz(:,:,:)
        logical,  allocatable :: cont(:,:,:)

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        allocate(a_new, mold=liq%alpha)
        allocate(lim_new, mold=liq%alpha)
        lim_new = 1.0_dp
        allocate(ur_e, uth_e, uz_e, mold=liq%alpha)
        call effective_liquid_velocity(liq, gas, sol, m, cfg, ur_e, uth_e, uz_e)
        allocate(Gr, Gth, Gz, mold=liq%alpha)
        allocate(cont, mold=ws_liq_cont)
        if (ws_liq_cont_valid) then
            cont = ws_liq_cont
        else
            call liquid_continuity_mask(liq, sol, m, cont)
        end if
        call face_fluxes_noalpha_all(liq, m, ur_e, uth_e, uz_e, cont, Gr, Gth, Gz)

        ! n_sub UNIFORME GLOBAL desde el CFL donor-cell máximo
        ! (suma de flujos de salida * dt / (rho*V))
        cfl_max = 0.0_dp
        icfl = 0; jcfl = 0; kcfl = 0
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    Fw = Gr(i-1,j,k); Fe = Gr(i,j,k); Fs = Gth(i,j-1,k)
                    Fn = Gth(i,j,k);  Fb = Gz(i,j,k-1); Ft = Gz(i,j,k)
                    cfl_loc = (max(-Fw,0.0_dp) + max(Fe,0.0_dp) + &
                               max(-Fs,0.0_dp) + max(Fn,0.0_dp) + &
                               max(-Fb,0.0_dp) + max(Ft,0.0_dp)) * cfg%dt / &
                              (liq%rho(i,j,k) * m%vol(i,j,k))
                    if (cfl_loc > cfl_max) then
                        cfl_max = cfl_loc
                        icfl = i; jcfl = j; kcfl = k
                    end if
                end do
            end do
        end do
        if (m%is_parallel) then
            call mpi_allreduce_max(cfl_max, cfl_glob, m%topo)
        else
            cfl_glob = cfl_max
        end if
        ! sonda: el CFL del transporte de alpha con su celda dominante.
        ! Es el numero que no cuadra en B1 (1181 con |u| <= U_LIQ_MAX: la
        ! geometria de la malla solo lo explicaria con ~1800 m/s).
        if (probe_active_now(cfg) .and. icfl > 0 .and. &
            abs(cfl_max - cfl_glob) < 1.0e-12_dp) then
            print '(A,ES11.4,A,I0,A,I0,A,I0,A,ES11.4,A,ES11.4,A,F8.5,A,ES11.4)', &
                '   [PROBE-alpha] CFL=', cfl_glob, ' en (', &
                icfl + m%topo%iglobal_start - 1, ',', &
                jcfl + m%topo%jglobal_start - 1, ',', &
                kcfl + m%topo%kglobal_start - 1, ')  rho=', &
                liq%rho(icfl,jcfl,kcfl), '  V=', m%vol(icfl,jcfl,kcfl), &
                '  a_l=', liq%alpha(icfl,jcfl,kcfl), '  |u|=', &
                sqrt(liq%ur(icfl,jcfl,kcfl)**2 + liq%uth(icfl,jcfl,kcfl)**2 &
                     + liq%uz(icfl,jcfl,kcfl)**2)
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
                                              alpha_old, m, cfg, ur_e, uth_e, uz_e)
            deallocate(a_new, lim_new, ur_e, uth_e, uz_e, Gr, Gth, Gz, cont)
            return
        end if
        dt_sub = cfg%dt / real(n_sub, dp)

        ! Partir SIEMPRE de alpha_old (ancla temporal, hallazgo 3.2)
        liq%alpha = alpha_old
        call mpi_exchange_halos_3d(liq%alpha, m%topo)

        call ensure_workspace(m)
        ws_Fr = 0.0_dp; ws_Fth = 0.0_dp; ws_Fz = 0.0_dp
        n_it_max = 0; dlim_exit = 0.0_dp
        ! Arrays de cara COMPLETOS a cero (halos incluidos): los halos de
        ! frontera FÍSICA (eje i=0, piso k=0) los leen cell_in_out/eff_flux
        ! y nadie los escribe (no hay rank vecino que los intercambie).
        ! Con memoria sucia allí, B1 v10 creó 12 kg de líquido en el paso 5
        ! y 143 t (más que la carga) en 120 s; el mismo binario con heap
        ! limpio no lo reproducía (dependía del estado del heap).
        ws_Mr = 0.0_dp; ws_Mth = 0.0_dp; ws_Mz = 0.0_dp; ws_lim = 1.0_dp

        do isub = 1, n_sub
            ! (1) Flujo donor-cell CRUDO por las caras + de cada celda
            !     (rho*u simétrico en la cara x alpha del lado upwind)
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        ws_Mr(i,j,k) = 0.0_dp; ws_Mth(i,j,k) = 0.0_dp
                        ws_Mz(i,j,k) = 0.0_dp
                        if (m%cell_type(i,j,k) == 0) cycle
                        Fe = Gr(i,j,k); Fn = Gth(i,j,k); Ft = Gz(i,j,k)
                        ws_Mr(i,j,k)  = donor_flux(Fe, liq%alpha(i,j,k), liq%alpha(i+1,j,k))
                        ws_Mth(i,j,k) = donor_flux(Fn, liq%alpha(i,j,k), liq%alpha(i,j+1,k))
                        ws_Mz(i,j,k)  = donor_flux(Ft, liq%alpha(i,j,k), liq%alpha(i,j,k+1))
                    end do
                end do
            end do
            call mpi_exchange_halos_3d(ws_Mr,  m%topo)
            call mpi_exchange_halos_3d(ws_Mth, m%topo)
            call mpi_exchange_halos_3d(ws_Mz,  m%topo)

            ! (2) Limitador de HUECO (sep-2026): la entrada a una celda no
            !     puede exceder el volumen que le queda libre
            !     (1 - alpha_s - alpha_sl - alpha_l) más lo que sale de ella
            !     en el mismo sub-paso. Antes el exceso se recortaba
            !     (clip) y se PERDÍA: B1 v8, 4.4 t de acero en 427 s (7 t/min
            !     al final) drenando al fondo del lecho ya lleno. Físicamente
            !     el fundido percola por los huecos y, si no cabe, se
            !     acumula encima. El factor s(celda) escala TODAS sus
            !     entradas y lo aplican las dos celdas de cada cara =>
            !     conservativo por construcción. Iterado N_LIM_IT veces
            !     porque la salida de una celda es la entrada (limitada) de
            !     su vecina; el residuo va al clip auditado.
            ws_lim = 1.0_dp
            do ilim = 1, N_LIM_MAX
                do k = kstart, kend
                    do j = jstart, jend
                        do i = istart, iend
                            if (m%cell_type(i,j,k) == 0) cycle
                            call cell_in_out(i, j, k, inflow, outflow)
                            room = max(0.0_dp, liq_cap(sol%alpha_s(i,j,k), alpha_slag(i,j,k)) &
                                   - liq%alpha(i,j,k)) * &
                                   liq%rho(i,j,k) * m%vol(i,j,k) / dt_sub &
                                   + outflow - sol%mdot(i,j,k)
                            if (inflow > SMALL) then
                                lim_new(i,j,k) = min(1.0_dp, max(0.0_dp, room) / inflow)
                            else
                                lim_new(i,j,k) = 1.0_dp
                            end if
                        end do
                    end do
                end do
                dlim = maxval(abs(lim_new(istart:iend,jstart:jend,kstart:kend) &
                                - ws_lim(istart:iend,jstart:jend,kstart:kend)))
                ws_lim = lim_new
                call mpi_exchange_halos_3d(ws_lim, m%topo)
                if (m%is_parallel) then
                    call mpi_allreduce_max(dlim, dlim_glob, m%topo)
                else
                    dlim_glob = dlim
                end if
                if (dlim_glob < 1.0e-12_dp) exit
            end do
            n_it_max  = max(n_it_max, min(ilim, N_LIM_MAX))
            dlim_exit = max(dlim_exit, dlim_glob)

            ! (3) Actualización en forma de flujo con los flujos EFECTIVOS
            !     (mismo valor en las dos celdas de la cara) y acumulación
            !     para la energía
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) then
                            a_new(i,j,k) = 0.0_dp
                            cycle
                        end if
                        Fw = eff_flux(ws_Mr(i-1,j,k),  ws_lim(i-1,j,k), ws_lim(i,j,k))
                        Fe = eff_flux(ws_Mr(i,j,k),    ws_lim(i,j,k),   ws_lim(i+1,j,k))
                        Fs = eff_flux(ws_Mth(i,j-1,k), ws_lim(i,j-1,k), ws_lim(i,j,k))
                        Fn = eff_flux(ws_Mth(i,j,k),   ws_lim(i,j,k),   ws_lim(i,j+1,k))
                        Fb = eff_flux(ws_Mz(i,j,k-1),  ws_lim(i,j,k-1), ws_lim(i,j,k))
                        Ft = eff_flux(ws_Mz(i,j,k),    ws_lim(i,j,k),   ws_lim(i,j,k+1))
                        flux_net = Fw - Fe + Fs - Fn + Fb - Ft
                        a_new(i,j,k) = liq%alpha(i,j,k) + dt_sub * &
                            (flux_net + sol%mdot(i,j,k)) / &
                            (liq%rho(i,j,k) * m%vol(i,j,k))
                        ws_Fr(i,j,k)  = ws_Fr(i,j,k)  + Fe * dt_sub / cfg%dt
                        ws_Fth(i,j,k) = ws_Fth(i,j,k) + Fn * dt_sub / cfg%dt
                        ws_Fz(i,j,k)  = ws_Fz(i,j,k)  + Ft * dt_sub / cfg%dt
                    end do
                end do
            end do
            liq%alpha = a_new
            call mpi_exchange_halos_3d(liq%alpha, m%topo)
        end do
        call mpi_exchange_halos_3d(ws_Fr,  m%topo)
        call mpi_exchange_halos_3d(ws_Fth, m%topo)
        call mpi_exchange_halos_3d(ws_Fz,  m%topo)
        ws_flux_valid = .true.

        !-------------------------------------------------------------------
        ! Derrame CONSERVATIVO del exceso (sep-2026, B1 v11): lo que aun
        ! sobrepase la restriccion de volumen tras el limitador (residuo del
        ! punto fijo, ~g por paso en el bano lleno) se desplaza a la celda
        ! de ARRIBA con hueco en vez de recortarse — la superficie libre
        ! sube, que es lo que hace el liquido que no cabe. Propagacion
        ! dirigida (una celda por pasada, finita: profundidad del bano), con
        ! la misma cantidad aplicada por dador y receptor => conservativo e
        ! invariante a la descomposicion (z esta descompuesta: 'give' se
        ! intercambia por halos). La masa derramada entra a ws_Fz para que
        ! la energia la transporte con la T del dador. Lo que ni asi cabe
        ! (columna llena hasta el techo) va al clip auditado.
        !-------------------------------------------------------------------
        spill_call = 0.0_dp; exc0_glob = -1.0_dp
        do ipass = 1, N_SPILL_MAX
            exc = 0.0_dp
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        ws_lim(i,j,k) = 0.0_dp
                        if (m%cell_type(i,j,k) == 0) cycle
                        cap = liq_cap(sol%alpha_s(i,j,k), alpha_slag(i,j,k))
                        give = liq%alpha(i,j,k) - cap
                        if (give <= 1.0e-15_dp) cycle
                        exc = max(exc, give)
                        if (m%cell_type(i,j,k+1) == 0) cycle
                        ! Cascada (F2.8): la de arriba puede llenarse hasta su
                        ! hueco FISICO (por encima de su cap de poro) y cede el
                        ! exceso en la pasada siguiente. Con el hueco de poro
                        ! como tope, una columna del lecho exactamente en su cap
                        ! bloqueaba el derrame de la celda de abajo y el exceso
                        ! (congelacion, fusion en sitio) acababa en el clip
                        ! (bath_freeze: 2.4 t); con el Poisson cerrado hacia las
                        ! celdas en cap (face_open) el derrame es el unico
                        ! camino y tiene que empujar a traves de la columna.
                        room_up = max(0.0_dp, 1.0_dp - sol%alpha_s(i,j,k+1) &
                                  - alpha_slag(i,j,k+1) - liq%alpha(i,j,k+1)) &
                                  * m%vol(i,j,k+1) / m%vol(i,j,k)
                        ws_lim(i,j,k) = min(give, room_up)
                    end do
                end do
            end do
            if (m%is_parallel) then
                call mpi_allreduce_max(exc, exc_glob, m%topo)
            else
                exc_glob = exc
            end if
            if (exc0_glob < 0.0_dp) exc0_glob = exc_glob
            if (exc_glob <= 1.0e-15_dp) exit
            call mpi_exchange_halos_3d(ws_lim, m%topo)
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        give = ws_lim(i,j,k)
                        liq%alpha(i,j,k) = liq%alpha(i,j,k) - give
                        if (m%cell_type(i,j,k-1) /= 0) &
                            liq%alpha(i,j,k) = liq%alpha(i,j,k) + ws_lim(i,j,k-1) &
                                * m%vol(i,j,k-1) / m%vol(i,j,k)
                        if (give > 0.0_dp) then
                            ws_Fz(i,j,k) = ws_Fz(i,j,k) + give * liq%rho(i,j,k) &
                                           * m%vol(i,j,k) / cfg%dt
                            spill_call = spill_call + give * liq%rho(i,j,k) * m%vol(i,j,k)
                        end if
                    end do
                end do
            end do
            call mpi_exchange_halos_3d(liq%alpha, m%topo)
        end do
        call mpi_exchange_halos_3d(ws_Fz, m%topo)
        call audit_step_delta(AUD_SPILL_MASS, spill_call, spill_step_prev, spill_step_id)

        ! Restricciones de acotamiento (el ÚNICO error de masa; auditado)
        clip_call = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) then
                        liq%alpha(i,j,k) = 0.0_dp
                        gas%alpha(i,j,k) = 0.0_dp
                        cycle
                    end if

                    a_pre = liq%alpha(i,j,k)
                    ! (el recorte final usa el hueco FISICO, no el de poro: el gas
                    ! residual solo limita la ENTRADA y dirige el derrame; el
                    ! liquido ya presente nunca se borra)
                    liq%alpha(i,j,k) = max(0.0_dp, &
                        min(1.0_dp - sol%alpha_s(i,j,k) - alpha_slag(i,j,k), &
                            liq%alpha(i,j,k)))
                    clip_call = clip_call + &
                        (a_pre - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k)
                    gas%alpha(i,j,k) = 1.0_dp - sol%alpha_s(i,j,k) &
                                       - alpha_slag(i,j,k) - liq%alpha(i,j,k)
                    gas%alpha(i,j,k) = max(0.0_dp, gas%alpha(i,j,k))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(liq%alpha, m%topo)
        call mpi_exchange_halos_3d(gas%alpha, m%topo)
        call audit_step_delta(AUD_ALPHA_CLIP_MASS, clip_call, clip_step_prev, clip_step_id)

        ! Diagnostico del limitador/derrame (rank 0, espaciado): iteraciones
        ! del punto fijo, dlim al salir, exceso maximo antes del derrame,
        ! masa derramada y recortada en esta llamada (locales al rank 0)
        if (should_print(m) .and. mod(probe_current_step(), 250) == 0 .and. &
            (spill_call > 1.0e-3_dp .or. clip_call > 1.0e-3_dp)) then
            print '(A,I0,A,I0,A,ES9.2,A,ES9.2,A,ES10.3,A,ES10.3)', &
                '   [LIM] paso ', probe_current_step(), ' it_max=', n_it_max, &
                ' dlim_exit=', dlim_exit, ' exc0=', exc0_glob, &
                ' derramado=', spill_call, ' recortado=', clip_call
        end if

        deallocate(a_new, lim_new, ur_e, uth_e, uz_e, Gr, Gth, Gz, cont)

    contains

        ! Entradas y salidas CRUDAS de la celda [kg/s] (con el limitador
        ! actual de las receptoras aplicado a las salidas)
        subroutine cell_in_out(ii, jj, kk, fin, fout)
            integer, intent(in)   :: ii, jj, kk
            real(dp), intent(out) :: fin, fout
            real(dp) :: f
            fin = 0.0_dp; fout = 0.0_dp
            f = ws_Mr(ii-1,jj,kk)
            if (f > 0.0_dp) then; fin = fin + f
            else; fout = fout - f * ws_lim(ii-1,jj,kk); end if
            f = ws_Mr(ii,jj,kk)
            if (f < 0.0_dp) then; fin = fin - f
            else; fout = fout + f * ws_lim(ii+1,jj,kk); end if
            f = ws_Mth(ii,jj-1,kk)
            if (f > 0.0_dp) then; fin = fin + f
            else; fout = fout - f * ws_lim(ii,jj-1,kk); end if
            f = ws_Mth(ii,jj,kk)
            if (f < 0.0_dp) then; fin = fin - f
            else; fout = fout + f * ws_lim(ii,jj+1,kk); end if
            f = ws_Mz(ii,jj,kk-1)
            if (f > 0.0_dp) then; fin = fin + f
            else; fout = fout - f * ws_lim(ii,jj,kk-1); end if
            f = ws_Mz(ii,jj,kk)
            if (f < 0.0_dp) then; fin = fin - f
            else; fout = fout + f * ws_lim(ii,jj,kk+1); end if
        end subroutine cell_in_out

    end subroutine solve_volume_fraction


    !---------------------------------------------------------------------------
    ! Velocidad efectiva del liquido para el transporte de alpha (ver
    ! declaracion en solve_volume_fraction). Solo celdas propias + halos
    ! por intercambio; en las fronteras fisicas las caras no existen.
    !---------------------------------------------------------------------------
    !---------------------------------------------------------------------------
    ! Velocidad de DRIFT-FLUX del liquido disperso -> ws_ud_* (Bug 15).
    !
    ! Objetivo: gas + sedimentacion terminal (Schiller-Naumann), modulo
    ! acotado a U_SETTLE_MAX; en celdas CON chatarra (alpha_s >= 0.01) el
    ! liquido percola verticalmente a sqrt(2 g d_p) (~1.4 m/s) sin montar
    ! en el gas (Ergun con el solido domina). Sin esa cota, melt_forced
    ! saturaba p en 3 pasos (celdas del lecho entrando al Poisson con la
    ! velocidad del gas).
    !
    ! RELAJACION (Manninen 1996, forma con inercia de particula): la gota
    ! alcanza el objetivo con tau_p = u_t/g (regimen de Newton: ~3.5 s para
    ! 2 mm; percolacion ~0.14 s) — NO instantaneamente. La hipotesis del
    ! deslizamiento algebraico (tau_p << escala del flujo) no se cumple con
    ! dt = 2 ms, y con ajuste instantaneo el gas nunca sentia la inercia de
    ! la niebla (100x la suya a alpha_l = 0.5%): melt_forced, gas a 250 m/s
    ! y p 300 kPa sobre el lecho. Con la gota retrasada, el deslizamiento
    ! crece durante los transitorios del gas y K(u_l - u_g) frena al gas
    ! con la masa de la niebla. u_old = liq_old (ancla temporal) si se
    ! pasa; si no (transporte sin flujo resuelto), objetivo directo.
    !---------------------------------------------------------------------------
    subroutine compute_liquid_drift(liq, gas, sol, m, cfg, liq_old)
        type(phase_t), intent(in)   :: liq, gas
        type(solid_t), intent(in)   :: sol
        type(mesh_t), intent(in)    :: m
        type(config_t), intent(in)  :: cfg
        type(phase_t), intent(in), optional :: liq_old
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: u_t, tr, tth, tz, f
        call ensure_workspace(m)
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        ws_ud_r = liq%ur; ws_ud_th = liq%uth; ws_ud_z = liq%uz; ws_ut = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (ws_liq_cont_valid) then
                        if (ws_liq_cont(i,j,k)) cycle
                    else
                        if (liq_continuous(liq%alpha(i,j,k), sol%alpha_s(i,j,k))) cycle
                    end if
                    if (liq%alpha(i,j,k) <= 0.0_dp .or. cfg%d_droplet <= 0.0_dp) then
                        ws_ud_r(i,j,k) = 0.0_dp; ws_ud_th(i,j,k) = 0.0_dp; ws_ud_z(i,j,k) = 0.0_dp
                        cycle
                    end if
                    if (sol%alpha_s(i,j,k) >= 1.0e-2_dp) then
                        ! LECHO: percolacion al balance de Ergun (el estado
                        ! estacionario de SU PROPIA ecuacion de momento);
                        ! relajacion instantanea (tau = alpha_l rho_l /
                        ! drag_Ergun ~ 1e-4 s << dt) y no monta en el gas.
                        u_t = percolation_velocity(liq%alpha(i,j,k), sol%alpha_s(i,j,k), &
                                  liq%rho(i,j,k), gas%rho(i,j,k), liq%mu(i,j,k), cfg%d_particle)
                        ws_ut(i,j,k) = u_t
                        ws_ud_r(i,j,k) = 0.0_dp; ws_ud_th(i,j,k) = 0.0_dp
                        ws_ud_z(i,j,k) = -u_t
                        cycle
                    end if
                    u_t = settling_velocity(cfg%d_droplet, liq%rho(i,j,k), &
                                            gas%rho(i,j,k), gas%mu(i,j,k))
                    call drift_velocity(gas%ur(i,j,k), gas%uth(i,j,k), gas%uz(i,j,k), u_t, &
                                        tr, tth, tz)
                    ws_ut(i,j,k) = u_t
                    if (present(liq_old)) then
                        ! relajacion de particula hacia el objetivo (freeboard)
                        f = min(1.0_dp, cfg%dt * GRAVITY / max(u_t, SMALL))
                        ws_ud_r(i,j,k)  = liq_old%ur(i,j,k)  + f * (tr  - liq_old%ur(i,j,k))
                        ws_ud_th(i,j,k) = liq_old%uth(i,j,k) + f * (tth - liq_old%uth(i,j,k))
                        ws_ud_z(i,j,k)  = liq_old%uz(i,j,k)  + f * (tz  - liq_old%uz(i,j,k))
                    else
                        ws_ud_r(i,j,k) = tr; ws_ud_th(i,j,k) = tth; ws_ud_z(i,j,k) = tz
                    end if
                end do
            end do
        end do
        call mpi_exchange_halos_3d(ws_ud_r,  m%topo)
        call mpi_exchange_halos_3d(ws_ud_th, m%topo)
        call mpi_exchange_halos_3d(ws_ud_z,  m%topo)
        call mpi_exchange_halos_3d(ws_ut,    m%topo)
        ws_drift_valid = present(liq_old)
    end subroutine compute_liquid_drift

    !---------------------------------------------------------------------------
    ! Velocidad efectiva del liquido para el transporte de alpha (ver
    ! declaracion en solve_volume_fraction): la propia donde es continuo,
    ! el drift-flux donde es disperso. Reutiliza el drift relajado de la
    ! iteracion (multiphase) si existe; si no, objetivo directo.
    !---------------------------------------------------------------------------
    !---------------------------------------------------------------------------
    ! Mascara de LIQUIDO CONTINUO (Bug 15 + regla de superficie libre, Plan C
    ! F1). Regla elemental (liq_continuous): alpha_l >= ALPHA_LIQ_CONT en el
    ! freeboard, >= ALPHA_FLOW_CUTOFF dentro del lecho. Regla de SUPERFICIE
    ! LIBRE: la celda con liquido (>= ALPHA_FLOW_CUTOFF) que descansa sobre
    ! una celda de bano (elementalmente continua y con alpha_l >=
    ! ALPHA_LIQ_CONT) es la pelicula superficial del bano, no niebla: entra
    ! al momento y al Poisson enlazada con el bano. Sin ella, la celda de
    ! superficie oscilaba entre continua y dispersa al cruzar 0.3 (bath_test:
    ! al pasar a dispersa, su cara con el bano se desenlazaba del Poisson y
    ! el drift empujaba liquido al bano sellado -> succion de kPa -> gas a
    ! 300 m/s a t = 0.8 s). Un nivel, sin propagacion: la superficie ocupa
    ! una capa de celdas. Se evalua tambien en halos (funcion local de alpha
    ! y alpha_s ya intercambiados) => coherente entre ranks sin intercambio.
    !---------------------------------------------------------------------------
    subroutine liquid_continuity_mask(liq, sol, m, cont)
        type(phase_t), intent(in) :: liq
        type(solid_t), intent(in) :: sol
        type(mesh_t), intent(in)  :: m
        logical, intent(out)      :: cont(-1:,-1:,-1:)
        integer :: k, klo, khi
        cont = liq_continuous(liq%alpha, sol%alpha_s)
        klo = lbound(cont,3) + 1; khi = ubound(cont,3)
        do k = khi, klo, -1
            where (.not. cont(:,:,k) .and. m%cell_type(:,:,k) /= 0 &
                   .and. liq%alpha(:,:,k) >= ALPHA_FLOW_CUTOFF &
                   .and. m%cell_type(:,:,k-1) /= 0 &
                   .and. liq_continuous(liq%alpha(:,:,k-1), sol%alpha_s(:,:,k-1)) &
                   .and. liq%alpha(:,:,k-1) >= ALPHA_LIQ_CONT)
                cont(:,:,k) = .true.
            end where
        end do
    end subroutine liquid_continuity_mask

    !---------------------------------------------------------------------------
    ! Flujo de masa sin alpha (rho_f u_f A) por las caras + de cada celda
    ! propia, halos intercambiados (Bug 19, Plan C F1).
    !   - Cara ENLAZADA en el Poisson del liquido (ambas celdas con liquido
    !     continuo): el flujo volumetrico conservativo exportado, Q, pasado a
    !     rho_f Q/alpha_f — la velocidad de cara de Rhie-Chow que el CG dejo
    !     solenoidal. Es el mismo alpha_f que llevaba Q: G = rho_f u_f A.
    !   - Cara MIXTA (continuo | disperso): regla del DADOR. El liquido que
    !     sale de la celda continua lo hace a la velocidad de ESA celda; las
    !     gotas que caen a la continua, a su velocidad de drift. La media
    !     simetrica aplicaba al bano la velocidad del gas de la celda casi
    !     vacia de encima (50-300 m/s): la celda de superficie se vaciaba
    !     hacia arriba en un paso, pasaba a dispersa, y la cascada acababa
    !     con succion de kPa en el bano y gas en la cota (bath_test, 0.8 s).
    !     Flujos convergentes: la media (neto); divergentes: 0 (no hay
    !     liquido en la cara).
    !   - Resto de caras (ambas dispersas, o sin liquido): reconstruccion
    !     simetrica desde la velocidad efectiva de centro (camino previo).
    ! Antes TODAS las caras usaban la reconstruccion de centro, que no es
    ! solenoidal aunque p haya convergido: un charco puro en reposo se
    ! llenaba y drenaba solo (bath_test: d alpha 4.7e-2/s, |u_l| 0.7 m/s).
    !---------------------------------------------------------------------------
    subroutine face_fluxes_noalpha_all(liq, m, ur_e, uth_e, uz_e, cont, Gr, Gth, Gz)
        type(phase_t), intent(in) :: liq
        type(mesh_t), intent(in)  :: m
        real(dp), intent(in)      :: ur_e(-1:,-1:,-1:), uth_e(-1:,-1:,-1:)
        real(dp), intent(in)      :: uz_e(-1:,-1:,-1:)
        logical,  intent(in)      :: cont(-1:,-1:,-1:)
        real(dp), intent(out)     :: Gr(-1:,-1:,-1:), Gth(-1:,-1:,-1:), Gz(-1:,-1:,-1:)

        integer  :: i, j, k
        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        ! Completos a cero: las caras de frontera fisica las lee el
        ! transporte y nadie las escribe (leccion B1 v10)
        Gr = 0.0_dp; Gth = 0.0_dp; Gz = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    call face_mass_fluxes_noalpha(liq%rho, ur_e, uth_e, uz_e, &
                                                  m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                    Gr(i,j,k) = Fe; Gth(i,j,k) = Fn; Gz(i,j,k) = Ft
                    if (m%cell_type(i+1,j,k) /= 0 .and. (cont(i,j,k) .neqv. cont(i+1,j,k))) &
                        Gr(i,j,k) = donor_face_flux(liq%rho(i,j,k), ur_e(i,j,k), &
                                                    liq%rho(i+1,j,k), ur_e(i+1,j,k), m%Ar(i,j,k))
                    if (m%cell_type(i,j+1,k) /= 0 .and. (cont(i,j,k) .neqv. cont(i,j+1,k))) &
                        Gth(i,j,k) = donor_face_flux(liq%rho(i,j,k), uth_e(i,j,k), &
                                                     liq%rho(i,j+1,k), uth_e(i,j+1,k), m%Ath(i,j,k))
                    if (m%cell_type(i,j,k+1) /= 0 .and. (cont(i,j,k) .neqv. cont(i,j,k+1))) &
                        Gz(i,j,k) = donor_face_flux(liq%rho(i,j,k), uz_e(i,j,k), &
                                                    liq%rho(i,j,k+1), uz_e(i,j,k+1), m%Az(i,j,k))
                    if (.not. ws_Fc_valid) cycle
                    if (ws_Fc_lk_r(i,j,k) == 1) &
                        Gr(i,j,k) = conservative_noalpha(ws_Fc_r(i,j,k), &
                            liq%alpha(i,j,k), liq%rho(i,j,k), &
                            liq%alpha(i+1,j,k), liq%rho(i+1,j,k), Fe)
                    if (ws_Fc_lk_th(i,j,k) == 1) &
                        Gth(i,j,k) = conservative_noalpha(ws_Fc_th(i,j,k), &
                            liq%alpha(i,j,k), liq%rho(i,j,k), &
                            liq%alpha(i,j+1,k), liq%rho(i,j+1,k), Fn)
                    if (ws_Fc_lk_z(i,j,k) == 1) &
                        Gz(i,j,k) = conservative_noalpha(ws_Fc_z(i,j,k), &
                            liq%alpha(i,j,k), liq%rho(i,j,k), &
                            liq%alpha(i,j,k+1), liq%rho(i,j,k+1), Ft)
                end do
            end do
        end do
        call mpi_exchange_halos_3d(Gr,  m%topo)
        call mpi_exchange_halos_3d(Gth, m%topo)
        call mpi_exchange_halos_3d(Gz,  m%topo)
    end subroutine face_fluxes_noalpha_all

    ! Regla del dador en una cara mixta orientada de lo (-) a hi (+):
    ! quien cede liquido fija la velocidad de la cara (ver arriba)
    pure function donor_face_flux(rho_lo, u_lo, rho_hi, u_hi, A) result(G)
        real(dp), intent(in) :: rho_lo, u_lo, rho_hi, u_hi, A
        real(dp) :: G
        if (u_lo > 0.0_dp .and. u_hi >= 0.0_dp) then
            G = rho_lo * u_lo * A                      ! lo dona
        else if (u_lo <= 0.0_dp .and. u_hi < 0.0_dp) then
            G = rho_hi * u_hi * A                      ! hi dona
        else if (u_lo > 0.0_dp .and. u_hi < 0.0_dp) then
            G = 0.5_dp * (rho_lo * u_lo + rho_hi * u_hi) * A   ! convergen: neto
        else
            G = 0.0_dp                                 ! divergen: sin liquido en la cara
        end if
    end function donor_face_flux

    ! rho_f Q/alpha_f: del flujo VOLUMETRICO Q = alpha_f u_f A del Poisson a
    ! rho u_f A; si la cara no tiene liquido (no deberia estar enlazada) se
    ! conserva la reconstruccion de centro
    pure function conservative_noalpha(Q, a_lo, rho_lo, a_hi, rho_hi, F_center) result(G)
        real(dp), intent(in) :: Q, a_lo, rho_lo, a_hi, rho_hi, F_center
        real(dp) :: G, a_f
        a_f = 0.5_dp * (a_lo + a_hi)
        if (a_f > SMALL) then
            G = Q * 0.5_dp * (rho_lo + rho_hi) / a_f
        else
            G = F_center
        end if
    end function conservative_noalpha

    subroutine effective_liquid_velocity(liq, gas, sol, m, cfg, ur_e, uth_e, uz_e)
        type(phase_t), intent(in)   :: liq, gas
        type(solid_t), intent(in)   :: sol
        type(mesh_t), intent(in)    :: m
        type(config_t), intent(in)  :: cfg
        real(dp), intent(out)       :: ur_e(-1:,-1:,-1:), uth_e(-1:,-1:,-1:)
        real(dp), intent(out)       :: uz_e(-1:,-1:,-1:)
        if (.not. ws_drift_valid) call compute_liquid_drift(liq, gas, sol, m, cfg)
        ! Continuas: la velocidad ACTUAL (recien corregida por el Poisson —
        ! el transporte debe mover alpha con el campo libre de divergencia
        ! de esta iteracion; con la copia tomada al inicio de la iteracion,
        ! una iteracion atrasada, el Poisson nunca cerraba la divergencia y
        ! p crecia en cada solve: B1 v13 revento a los 5.5 s, en el primer
        ! liquido). Dispersas: el drift relajado de esta iteracion.
        if (ws_liq_cont_valid) then
            where (ws_liq_cont)
                ur_e = liq%ur; uth_e = liq%uth; uz_e = liq%uz
            elsewhere
                ur_e = ws_ud_r; uth_e = ws_ud_th; uz_e = ws_ud_z
            end where
        else
            where (liq_continuous(liq%alpha, sol%alpha_s))
                ur_e = liq%ur; uth_e = liq%uth; uz_e = liq%uz
            elsewhere
                ur_e = ws_ud_r; uth_e = ws_ud_th; uz_e = ws_ud_z
            end where
        end if
    end subroutine effective_liquid_velocity

    ! Flujo donor-cell en una cara orientada de lo (-) a hi (+)
    pure function donor_flux(F, a_lo, a_hi) result(Fd)
        real(dp), intent(in) :: F, a_lo, a_hi
        real(dp) :: Fd
        if (F >= 0.0_dp) then
            Fd = F * a_lo
        else
            Fd = F * a_hi
        end if
    end function donor_flux

    ! Flujo efectivo: el crudo escalado por el limitador de la celda
    ! RECEPTORA (hi si F>0, lo si F<0)
    pure function eff_flux(F, lim_lo, lim_hi) result(Fe)
        real(dp), intent(in) :: F, lim_lo, lim_hi
        real(dp) :: Fe
        if (F >= 0.0_dp) then
            Fe = F * lim_hi
        else
            Fe = F * lim_lo
        end if
    end function eff_flux

    !---------------------------------------------------------------------------
    ! Forma implícita ACOTADA (fallback para CFL > N_SUB_MAX*0.9): estable
    ! incondicional; no conservativa bajo div/=0 (defecto alpha*dF, medido
    ! por el audit). Es la forma que fue titular hasta el cierre 2026.
    !---------------------------------------------------------------------------
    subroutine solve_alpha_bounded_implicit(liq, gas, sol, alpha_slag, &
                                            alpha_old, m, cfg, ur_e, uth_e, uz_e)
        use mod_workspace, only: ensure_workspace, aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        real(dp), intent(in)         :: alpha_slag(-1:,-1:,-1:)
        real(dp), intent(in)         :: alpha_old(-1:,-1:,-1:)
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: ur_e(-1:,-1:,-1:), uth_e(-1:,-1:,-1:)
        real(dp), intent(in)         :: uz_e(-1:,-1:,-1:)

        integer :: i, j, k
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft, vol_dt, a_pre, clip_call

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call ensure_workspace(m)
        ws_flux_valid = .false.
        clip_call = 0.0_dp
        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    vol_dt = liq%rho(i,j,k) * m%vol(i,j,k) / cfg%dt
                    call face_mass_fluxes_noalpha(liq%rho, ur_e, uth_e, &
                        uz_e, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
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
                    ! (el recorte final usa el hueco FISICO, no el de poro: el gas
                    ! residual solo limita la ENTRADA y dirige el derrame; el
                    ! liquido ya presente nunca se borra)
                    liq%alpha(i,j,k) = max(0.0_dp, &
                        min(1.0_dp - sol%alpha_s(i,j,k) - alpha_slag(i,j,k), &
                            liq%alpha(i,j,k)))
                    clip_call = clip_call + &
                        (a_pre - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k)
                    gas%alpha(i,j,k) = 1.0_dp - sol%alpha_s(i,j,k) &
                                       - alpha_slag(i,j,k) - liq%alpha(i,j,k)
                    gas%alpha(i,j,k) = max(0.0_dp, gas%alpha(i,j,k))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(liq%alpha, m%topo)
        call mpi_exchange_halos_3d(gas%alpha, m%topo)
        call audit_step_delta(AUD_ALPHA_CLIP_MASS, clip_call, clip_step_prev, clip_step_id)
    end subroutine solve_alpha_bounded_implicit

    ! Audita el valor de ESTA llamada de modo que, al cierre del paso, el
    ! contador contenga el de la última iteración externa (las llamadas
    ! del mismo paso se auditan como diferencias telescópicas)
    subroutine audit_step_delta(id, val, prev, step_id)
        integer,  intent(in)    :: id
        real(dp), intent(in)    :: val
        real(dp), intent(inout) :: prev
        integer,  intent(inout) :: step_id
        integer :: step
        step = probe_current_step()
        if (step /= step_id) then
            step_id = step
            prev    = 0.0_dp
        end if
        call audit_add(id, val - prev)
        prev = val
    end subroutine audit_step_delta
end module mod_continuity
