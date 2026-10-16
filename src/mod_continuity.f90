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
    use mod_audit, only: audit_add, AUD_ALPHA_CLIP_MASS, AUD_ALPHA_CLIP_E, AUD_SPILL_MASS, &
                         AUD_VOL_DALPHA, AUD_VOL_LIM, AUD_VOL_UNLINKED
    use mod_workspace, only: ensure_workspace, ws_Fr, ws_Fth, ws_Fz, &
                             ws_Mr, ws_Mth, ws_Mz, ws_lim, ws_flux_valid, &
                             ws_lim_step, ws_lim_step_valid, ws_lim_step_id, &
                             ws_pc_unl, ws_pc_unl_valid, ws_pc_unl_id, &
                             ws_Fc_r, ws_Fc_th, ws_Fc_z, ws_Fc_lk_r, ws_Fc_lk_th, &
                             ws_Fc_lk_z, ws_Fc_valid, ws_liq_cont, ws_liq_cont_valid, &
                             ws_Fc_af_r, ws_Fc_af_th, ws_Fc_af_z, &
                             ws_ud_r, ws_ud_th, ws_ud_z, ws_ut, ws_drift_valid, &
                             ws_mQ_r, ws_mQ_th, ws_mQ_z, ws_mW, ws_mKl, ws_mKg, ws_mix_valid, ws_mix_id
    implicit none

    logical, save :: fallback_warned = .false.
    ! Clip auditado por PASO (sep-2026): solve_volume_fraction corre en
    ! cada iteración externa y rehace alpha desde alpha_old, así que el
    ! clip real del paso es el de la ÚLTIMA iteración, no la suma (B1 v9:
    ! el audit contaba 13.1 t con 2.6 t perdidas — exactamente x5 outers).
    ! Se audita la diferencia respecto a la llamada anterior del mismo paso.
    real(dp), save :: clip_step_prev = 0.0_dp
    integer,  save :: clip_step_id = -huge(1)
    ! energia de lo recortado (N-B1), misma semantica por paso
    real(dp), save :: clipE_step_prev = 0.0_dp
    integer,  save :: clipE_step_id = -huge(1)
    real(dp), save :: spill_step_prev = 0.0_dp
    ! Plan D, D1: desfases alpha-p (ultima iteracion externa del paso)
    real(dp), save :: vd_step_prev = 0.0_dp, vl_step_prev = 0.0_dp, vu_step_prev = 0.0_dp
    integer,  save :: vd_step_id = -1, vl_step_id = -1, vu_step_id = -1
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
        real(dp) :: mv, mv_glob
        integer, parameter :: N_SPILL_MAX = 128   ! >= nz de produccion (84): la cascada avanza una celda por pasada
        integer :: ilim, ipass, n_it_max
        real(dp) :: inflow, outflow, room, dlim, dlim_glob, clip_call, clipE_call
        real(dp) :: dlim_exit, cap, exc, room_up, give, exc_glob, spill_call, fslag
        real(dp) :: dlim_prev, dist_est, dist_exit
        real(dp) :: exc0_glob
        real(dp) :: vol_dalpha, vol_lim, vol_unl
        real(dp), allocatable :: a_in(:,:,:), in_tot(:,:,:), in_ok(:,:,:)
        real(dp), allocatable :: a_new(:,:,:), lim_new(:,:,:)
        ! Plan E E2: volumen [m3] entrado por caras NO enlazadas (y derrame)
        real(dp), allocatable :: unl_vol(:,:,:)
        real(dp) :: unl
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
        ! Plan G: transporte del modelo de MEZCLA (flujos volumetricos de la
        ! mezcla + deslizamiento acotado; ver mixflux)
        logical :: mixture
        logical, save :: mix_sub_warned = .false.

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        mixture = cfg%mixture_model .and. ws_mix_valid .and. (ws_mix_id == probe_current_step())
        ! a_new se asigna como COPIA de liq%alpha (no solo con mold): el
        ! transporte escribe las celdas propias y luego liq%alpha = a_new;
        ! con mold, los halos FISICOS (eje, pared, piso, techo: nadie los
        ! escribe ni los intercambia) heredaban la basura del heap y
        ! liq%alpha quedaba con halos basura desde el primer paso (medido con
        ! malloc relleno de sNaN: 3584 halos; corridas no reproducibles,
        ! dependientes de la presion de memoria de la maquina; Bug 22, oct-2026).
        allocate(a_new, mold=liq%alpha); a_new = liq%alpha
        allocate(lim_new, mold=liq%alpha)
        lim_new = 1.0_dp
        allocate(ur_e, uth_e, uz_e, mold=liq%alpha)
        allocate(Gr, Gth, Gz, mold=liq%alpha)
        ! (workspace asignado ANTES de tomar su forma: regresion de Plan G,
        ! los unit tests llegan aqui sin workspace)
        call ensure_workspace(m)
        allocate(cont, mold=ws_liq_cont)
        if (.not. mixture) then
        call effective_liquid_velocity(liq, gas, sol, m, cfg, ur_e, uth_e, uz_e)
        if (ws_liq_cont_valid) then
            cont = ws_liq_cont
        else
            call liquid_continuity_mask(liq, sol, m, cont)
        end if
        call face_fluxes_noalpha_all(liq, m, ur_e, uth_e, uz_e, cont, Gr, Gth, Gz)
        else
            ur_e = 0.0_dp; uth_e = 0.0_dp; uz_e = 0.0_dp
            Gr = 0.0_dp; Gth = 0.0_dp; Gz = 0.0_dp; cont = .true.
        end if

        ! n_sub UNIFORME GLOBAL desde el CFL donor-cell máximo
        ! (suma de flujos de salida * dt / (rho*V))
        cfl_max = 0.0_dp
        icfl = 0; jcfl = 0; kcfl = 0
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (mixture) then
                        ! acotamiento del donor en SATURACION: la celda no
                        ! puede ceder mas que su liquido, s_P (sum Q_out + slip)
                        ! dt <= alpha_P V  <=>  dt (sum Q_out + slip) <= eps V
                        cfl_loc = (max(-ws_mQ_r(i-1,j,k),0.0_dp) + max(ws_mQ_r(i,j,k),0.0_dp) + &
                                   max(-ws_mQ_th(i,j-1,k),0.0_dp) + max(ws_mQ_th(i,j,k),0.0_dp) + &
                                   max(-ws_mQ_z(i,j,k-1),0.0_dp) + max(ws_mQ_z(i,j,k),0.0_dp) + &
                                   ws_mW(i,j,k) * m%Az(i,j,k-1) * fluid_eps(i,j,k)) * cfg%dt / &
                                  (max(fluid_eps(i,j,k), EPS_MIX) * m%vol(i,j,k))
                        ! el dador cede ffrac Q de liquido: con ffrac > s (lecho:
                        ! el liquido es mas movil que la mezcla) la cota es
                        ! dt sum Q_out <= (s/ffrac) eps V (auditoria, bajos)
                        if (sat(i,j,k) > 1.0e-12_dp) &
                            cfl_loc = cfl_loc * max(1.0_dp, ffrac(i,j,k) / sat(i,j,k))
                        if (cfl_loc > cfl_max) then
                            cfl_max = cfl_loc; icfl = i; jcfl = j; kcfl = k
                        end if
                        cycle
                    end if
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
        if (mixture .and. n_sub > N_SUB_MAX) then
            ! Modelo de mezcla: sin fallback implicito (sus velocidades son
            ! las del liquido de dos fluidos). Se acota el numero de
            ! sub-pasos; el limitador de hueco y el clip auditado cubren el
            ! exceso. Aviso una vez.
            if (.not. mix_sub_warned .and. should_print(m)) then
                print '(A,F9.1,A)', ' [ALPHA] AVISO (mezcla): CFL del transporte ', cfl_glob, &
                    ' > sub-pasable; n_sub acotado (regimen fuera de validez)'
                mix_sub_warned = .true.
            end if
            n_sub = N_SUB_MAX
        end if
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
            ws_lim_step_valid = .false.
            deallocate(a_new, lim_new, ur_e, uth_e, uz_e, Gr, Gth, Gz, cont)
            return
        end if
        dt_sub = cfg%dt / real(n_sub, dp)

        ! D1: iterado ENTRANTE (el alpha con el que se armo el Poisson de
        ! esta iteracion externa) para medir el desfase alpha-p
        allocate(a_in, mold=liq%alpha); a_in = liq%alpha
        allocate(in_tot, in_ok, mold=liq%alpha); in_tot = 0.0_dp; in_ok = 0.0_dp
        allocate(unl_vol, mold=liq%alpha); unl_vol = 0.0_dp
        vol_dalpha = 0.0_dp; vol_lim = 0.0_dp; vol_unl = 0.0_dp

        ! Partir SIEMPRE de alpha_old (ancla temporal, hallazgo 3.2)
        liq%alpha = alpha_old
        call mpi_exchange_halos_3d(liq%alpha, m%topo)

        call ensure_workspace(m)
        ws_Fr = 0.0_dp; ws_Fth = 0.0_dp; ws_Fz = 0.0_dp
        n_it_max = 0; dlim_exit = 0.0_dp; dist_exit = 0.0_dp
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
                        if (mixture) then
                            ws_Mr(i,j,k)  = mixflux(ws_mQ_r(i,j,k),  i, j, k, i+1, j, k, 1)
                            ws_Mth(i,j,k) = mixflux(ws_mQ_th(i,j,k), i, j, k, i, j+1, k, 2)
                            ws_Mz(i,j,k)  = mixflux(ws_mQ_z(i,j,k),  i, j, k, i, j, k+1, 3)
                            cycle
                        end if
                        Fe = Gr(i,j,k); Fn = Gth(i,j,k); Ft = Gz(i,j,k)
                        ws_Mr(i,j,k)  = donor_flux(Fe, liq%alpha(i,j,k), liq%alpha(i+1,j,k))
                        ws_Mth(i,j,k) = donor_flux(Fn, liq%alpha(i,j,k), liq%alpha(i,j+1,k))
                        ws_Mz(i,j,k)  = donor_flux(Ft, liq%alpha(i,j,k), liq%alpha(i,j,k+1))
                        ! D1: volumen de liquido por caras que el Poisson NO enlazo
                        if (ws_Fc_valid) then
                            if (ws_Fc_lk_r(i,j,k) == 0 .and. m%cell_type(i+1,j,k) /= 0) &
                                vol_unl = vol_unl + abs(ws_Mr(i,j,k)) * dt_sub / liq%rho(i,j,k)
                            if (ws_Fc_lk_th(i,j,k) == 0 .and. m%cell_type(i,j+1,k) /= 0) &
                                vol_unl = vol_unl + abs(ws_Mth(i,j,k)) * dt_sub / liq%rho(i,j,k)
                            if (ws_Fc_lk_z(i,j,k) == 0 .and. m%cell_type(i,j,k+1) /= 0) &
                                vol_unl = vol_unl + abs(ws_Mz(i,j,k)) * dt_sub / liq%rho(i,j,k)
                        end if
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
            dlim_prev = huge(1.0_dp)
            do ilim = 1, N_LIM_MAX
                do k = kstart, kend
                    do j = jstart, jend
                        do i = istart, iend
                            if (m%cell_type(i,j,k) == 0) cycle
                            call cell_in_out(i, j, k, inflow, outflow)
                            ! (auditoria 9, M9-6) max(0, .) A PROPOSITO: el hueco
                            ! con signo (una celda sobre su cap solo admite lo
                            ! que le sale menos su exceso) se midio en
                            ! bath_freeze: derrame 10.4 -> 2.1 t pero volumen
                            ! bloqueado +58 % (0.74 -> 1.17 m3) y gas recreado
                            ! por la EOS 11.5 -> 16.9 %: agranda el desfase
                            ! alpha-p (vol_lim, la familia de B1). No adoptado.
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
                if (ilim < N_LIM_MAX) dlim_prev = dlim_glob
            end do
            n_it_max  = max(n_it_max, min(ilim, N_LIM_MAX))
            dlim_exit = max(dlim_exit, dlim_glob)
            ! (auditoria 9, M9-6) la iteracion es MONOTONA desde s = 1 (siempre
            ! sobreadmite): dlim es el cambio entre barridos, no la distancia
            ! al punto fijo. Con convergencia geometrica de razon r la
            ! distancia es ~dlim r/(1 - r) (diagnostico; el exceso que deja lo
            ! mueve el derrame y lo audita m_spill)
            if (ilim > N_LIM_MAX .and. dlim_prev < huge(1.0_dp)) then
                if (dlim_glob < dlim_prev) then
                    dist_est = dlim_glob * (dlim_glob / dlim_prev) / (1.0_dp - dlim_glob / dlim_prev)
                else
                    dist_est = 1.0_dp
                end if
                dist_exit = max(dist_exit, min(dist_est, 1.0_dp))
            end if
            ! D1: entrada de liquido que el limitador BLOQUEA (el Poisson la
            ! pidio); D2.2: agregado por celda de lo pedido y lo que cupo
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        call cell_in_out(i, j, k, inflow, outflow)
                        if (inflow <= SMALL) cycle
                        in_tot(i,j,k) = in_tot(i,j,k) + inflow * dt_sub
                        in_ok(i,j,k)  = in_ok(i,j,k)  + ws_lim(i,j,k) * inflow * dt_sub
                        vol_lim = vol_lim + (1.0_dp - ws_lim(i,j,k)) * inflow * dt_sub / liq%rho(i,j,k)
                    end do
                end do
            end do

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
                        ! Plan E E2: entrada neta EFECTIVA por caras que el
                        ! Poisson no enlazo (fuente conocida de la presion)
                        if (ws_Fc_valid) then
                            unl = 0.0_dp
                            if (ws_Fc_lk_r(i-1,j,k) == 0)  unl = unl + Fw
                            if (ws_Fc_lk_r(i,j,k) == 0)    unl = unl - Fe
                            if (ws_Fc_lk_th(i,j-1,k) == 0) unl = unl + Fs
                            if (ws_Fc_lk_th(i,j,k) == 0)   unl = unl - Fn
                            if (ws_Fc_lk_z(i,j,k-1) == 0)  unl = unl + Fb
                            if (ws_Fc_lk_z(i,j,k) == 0)    unl = unl - Ft
                            unl_vol(i,j,k) = unl_vol(i,j,k) + unl * dt_sub / liq%rho(i,j,k)
                        end if
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
                        ! (auditoria 15) con ESCORIA arriba, dentro del lecho,
                        ! se reserva el gas de poro (completo desde a_sl >=
                        ! ALPHA_FLOW_CUTOFF, rampa lineal por debajo): la escoria llena hasta liq_cap y deja libre
                        ! ALPHA_PORE_GAS; con el hueco fisico la cascada metia
                        ! acero en ese poro y la celda (liq_cap 0) lo cedia
                        ! arriba: el acero cruzaba la escoria (M9-4). Celda
                        ! llena de escoria: tope liq_cap; escoria traza: el
                        ! hueco fisico de F2.8 (un tope liq_cap con umbral
                        ! ALPHA_CUTOFF mandaba al clip la cascada del lecho
                        ! por 1e-6 de escoria, auditoria dirigida 16). Fuera
                        ! del lecho no hay poro reservado: identico.
                        if (alpha_slag(i,j,k+1) > 0.0_dp .and. pore_floor_on .and. &
                            sol%alpha_s(i,j,k+1) >= ALPHA_BED) then
                            ! rampa ABSOLUTA (dirigida 17): la proporcional al
                            ! llenado dejaba poro abierto en la interfaz
                            ! acero+escoria (caso 12) y era singular en costras
                            ! con a_s > 1 - ALPHA_PORE_GAS
                            fslag = min(1.0_dp, alpha_slag(i,j,k+1) / ALPHA_FLOW_CUTOFF)
                            room_up = max(0.0_dp, 1.0_dp - sol%alpha_s(i,j,k+1) &
                                      - alpha_slag(i,j,k+1) - liq%alpha(i,j,k+1) &
                                      - ALPHA_PORE_GAS * fslag) * m%vol(i,j,k+1) / m%vol(i,j,k)
                        end if
                        ws_lim(i,j,k) = min(give, room_up)
                        ! (auditoria 8) una celda de arriba LLENA DE LIQUIDO no
                        ! bloquea: recibe el exceso y lo cede en la pasada
                        ! siguiente (relevo de piston: su give pasa a ser > 0).
                        ! Antes una columna de bano llena cortaba la cascada y
                        ! el exceso del fondo iba al clip con hueco encima
                        ! (pocket_rise_dt10: 32 mg). (auditoria 9, M9-4) Solo
                        ! a traves de LIQUIDO: una celda llena con escoria
                        ! (la escoria llena hasta liq_cap, dentro y fuera del
                        ! lecho; la interfaz acero|escoria queda llena y
                        ! mixta: con escoria ni el relevo ni la cascada pasan
                        ! de ella, esta ultima por el tope liq_cap) o
                        ! una costra sin liquido NO se atraviesa -- el acero
                        ! quedaba ENCIMA de la escoria y el limitador le
                        ! impedia volver a bajar --; ni una costra con trazas
                        ! de liquido (< ALPHA_FLOW_CUTOFF). Ahi el exceso sigue yendo
                        ! al clip auditado, como antes.
                        if (room_up <= 1.0e-15_dp .and. alpha_slag(i,j,k+1) < ALPHA_CUTOFF &
                            .and. liq%alpha(i,j,k+1) >= ALPHA_FLOW_CUTOFF) ws_lim(i,j,k) = give
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
            ! sin progreso posible (columnas llenas hasta el techo): salir en
            ! vez de recorrer las N_SPILL_MAX pasadas en vano (auditoria,
            ! bajos); lo que queda va al clip auditado como antes
            mv = maxval(ws_lim(istart:iend, jstart:jend, kstart:kend))
            if (m%is_parallel) then
                call mpi_allreduce_max(mv, mv_glob, m%topo)
            else
                mv_glob = mv
            end if
            if (mv_glob <= 1.0e-15_dp) exit
            call mpi_exchange_halos_3d(ws_lim, m%topo)
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        give = ws_lim(i,j,k)
                        liq%alpha(i,j,k) = liq%alpha(i,j,k) - give
                        ! (pc_spill_source: el derrame como fuente REALIMENTA al
                        ! reves — al dador lleno le dice que perdio volumen y el
                        ! Poisson le mete mas; banco e12: P_HYDRO_CAP, vol_lim
                        ! 0.66 m3. Default false: el derrame es la correccion del
                        ! limitador, no un flujo fisico que la presion deba
                        ! compensar.)
                        if (cfg%pc_spill_source) unl_vol(i,j,k) = unl_vol(i,j,k) - give * m%vol(i,j,k)
                        if (m%cell_type(i,j,k-1) /= 0) then
                            liq%alpha(i,j,k) = liq%alpha(i,j,k) + ws_lim(i,j,k-1) &
                                * m%vol(i,j,k-1) / m%vol(i,j,k)
                            if (cfg%pc_spill_source) &
                                unl_vol(i,j,k) = unl_vol(i,j,k) + ws_lim(i,j,k-1) * m%vol(i,j,k-1)
                        end if
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
        clip_call = 0.0_dp; clipE_call = 0.0_dp
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
                    clipE_call = clipE_call + &
                        (a_pre - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k) &
                        * (liq%cp(i,j,k) * liq%T(i,j,k) + (cfg%cp_s - cfg%cp_l) &
                           * cfg%T_liquidus + cfg%h_fusion)
                    gas%alpha(i,j,k) = 1.0_dp - sol%alpha_s(i,j,k) &
                                       - alpha_slag(i,j,k) - liq%alpha(i,j,k)
                    gas%alpha(i,j,k) = max(0.0_dp, gas%alpha(i,j,k))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(liq%alpha, m%topo)
        call mpi_exchange_halos_3d(gas%alpha, m%topo)
        call audit_step_delta(AUD_ALPHA_CLIP_MASS, clip_call, clip_step_prev, clip_step_id)
        call audit_step_delta(AUD_ALPHA_CLIP_E, clipE_call, clipE_step_prev, clipE_step_id)

        ! Diagnostico del limitador/derrame (rank 0, espaciado): iteraciones
        ! del punto fijo, dlim al salir, exceso maximo antes del derrame,
        ! masa derramada y recortada en esta llamada (locales al rank 0)
        if (should_print(m) .and. mod(probe_current_step(), 250) == 0 .and. &
            (spill_call > 1.0e-3_dp .or. clip_call > 1.0e-3_dp .or. n_it_max >= N_LIM_MAX)) then
            print '(A,I0,A,I0,A,ES9.2,A,ES9.2,A,ES9.2,A,ES10.3,A,ES10.3)', &
                '   [LIM] paso ', probe_current_step(), ' it_max=', n_it_max, &
                ' dlim_exit=', dlim_exit, ' dist_est=', dist_exit, ' exc0=', exc0_glob, &
                ' derramado=', spill_call, ' recortado=', clip_call
        end if

        ! D1: desfase alpha-p de esta iteracion externa
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    vol_dalpha = vol_dalpha + abs(liq%alpha(i,j,k) - a_in(i,j,k)) * m%vol(i,j,k)
                end do
            end do
        end do
        call audit_step_delta(AUD_VOL_DALPHA,   vol_dalpha, vd_step_prev, vd_step_id)
        call audit_step_delta(AUD_VOL_LIM,      vol_lim,    vl_step_prev, vl_step_id)
        call audit_step_delta(AUD_VOL_UNLINKED, vol_unl,    vu_step_prev, vu_step_id)
        ! D2.2: fraccion de la entrada que cupo, para el Poisson de la
        ! iteracion externa siguiente (halos: la cara se evalua desde ambas celdas)
        where (in_tot > SMALL)
            ws_lim_step = in_ok / in_tot
        elsewhere
            ws_lim_step = 1.0_dp
        end where
        ws_lim_step = min(1.0_dp, max(0.0_dp, ws_lim_step))
        call mpi_exchange_halos_3d(ws_lim_step, m%topo)
        ws_lim_step_valid = .true.
        ws_lim_step_id = probe_current_step()
        ! Plan E E2: fuente conocida [m3/s] para el Poisson siguiente del paso
        if (ws_Fc_valid) then
            ws_pc_unl = unl_vol / cfg%dt
            call mpi_exchange_halos_3d(ws_pc_unl, m%topo)
            ws_pc_unl_valid = .true.
            ws_pc_unl_id = probe_current_step()
        else
            ws_pc_unl_valid = .false.
        end if
        deallocate(a_in, in_tot, in_ok, unl_vol)

        deallocate(a_new, lim_new, ur_e, uth_e, uz_e, Gr, Gth, Gz, cont)

    contains

        ! Porosidad FLUIDA de la celda (hueco que comparten liquido y gas)
        pure function fluid_eps(ii, jj, kk) result(e)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: e
            e = 0.0_dp
            if (m%cell_type(ii,jj,kk) == 0) return
            e = max(0.0_dp, 1.0_dp - sol%alpha_s(ii,jj,kk) - alpha_slag(ii,jj,kk))
        end function fluid_eps

        ! Saturacion de liquido s = alpha_l/eps en [0, 1]
        pure function sat(ii, jj, kk) result(sv)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: sv, e
            e = fluid_eps(ii, jj, kk)
            sv = 0.0_dp
            if (e <= EPS_MIX) return
            sv = min(1.0_dp, max(0.0_dp, liq%alpha(ii,jj,kk) / e))
        end function sat

        ! Fraccion convectiva del liquido con la alpha ACTUAL del sub-paso:
        ! saturacion fuera del lecho; flujo fraccional de Buckley-Leverett
        ! lambda_l/lambda_T en el lecho (lambda_q = alpha_q^2/K_q)
        pure function ffrac(ii, jj, kk) result(f)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: f, e, al, ll, lg
            f = sat(ii, jj, kk)
            if (ws_mKl(ii,jj,kk) <= 0.0_dp .or. ws_mKg(ii,jj,kk) <= 0.0_dp) return
            e = fluid_eps(ii, jj, kk)
            al = min(max(liq%alpha(ii,jj,kk), 0.0_dp), e)
            ll = al * al / ws_mKl(ii,jj,kk)
            lg = (e - al)**2 / ws_mKg(ii,jj,kk)
            if (ll + lg > 0.0_dp) f = ll / (ll + lg)
        end function ffrac

        !-----------------------------------------------------------------------
        ! Plan G: flujo de MASA de liquido [kg/s] por la cara entre L (lado -)
        ! y H (lado +) en el modelo de mezcla (drift-flux, Ishii/Zuber-Findlay
        ! en forma volumetrica):
        !     j_l = s j + eps s (1 - s) u_r
        ! - conveccion con el flujo VOLUMETRICO conservativo de la mezcla Q
        !   (el que el Poisson hizo solenoidal) y la saturacion del DADOR;
        ! - deslizamiento (solo caras verticales, liquido hacia abajo) con la
        !   discretizacion ACOTADA de los modelos de sedimentacion (Godunov
        !   para f = s (1 - s); Burger et al.): saturacion del dador de
        !   ARRIBA por el hueco de gas de la receptora de ABAJO, con la rapidez
        !   de deslizamiento del regimen de la celda de arriba (ws_mW). Se
        !   anula sola si arriba no hay liquido o abajo no queda gas: el
        !   deslizamiento nunca llena una celda saturada, y la presion no lo
        !   ve (es un intercambio de volumen liquido-gas a flujo neto nulo).
        !-----------------------------------------------------------------------
        function mixflux(Q, iL, jL, kL, iH, jH, kH, dir) result(F)
            real(dp), intent(in) :: Q
            integer,  intent(in) :: iL, jL, kL, iH, jH, kH, dir
            real(dp) :: F, eL, eH, ef, area
            F = 0.0_dp
            if (m%cell_type(iH,jH,kH) == 0) return
            select case (dir)
            case (1)
                area = m%Ar(iL,jL,kL)
            case (2)
                area = m%Ath(iL,jL,kL)
            case default
                area = m%Az(iL,jL,kL)
            end select
            ! flujo fraccional del dador (las gotas siguen a la mezcla; el
            ! regimen de gotas con deriva propia se retiro: ver mod_mixture_3d)
            if (Q >= 0.0_dp) then
                F = F + liq%rho(iL,jL,kL) * ffrac(iL,jL,kL) * Q
            else
                F = F + liq%rho(iH,jH,kH) * ffrac(iH,jH,kH) * Q
            end if
            ! deslizamiento acotado (caras verticales, H continuo o lecho)
            if (dir /= 3) return
            eL = fluid_eps(iL,jL,kL); eH = fluid_eps(iH,jH,kH)
            if (eL <= EPS_MIX .or. eH <= EPS_MIX) return
            ef = 2.0_dp * eL * eH / (eL + eH)
            if (sol%alpha_s(iH,jH,kH) >= ALPHA_BED .and. ws_mKl(iH,jH,kH) > 0.0_dp &
                .and. ws_mKg(iH,jH,kH) > 0.0_dp) then
                ! LECHO arriba (auditoria M37): flujo de GODUNOV de Buckley-
                ! Leverett con la funcion de flujo de Darcy bifasico de la
                ! celda de arriba, f(s) = min(ub ef s(1-s), drho g ll lg/(ll+lg)).
                ! Con W de centro de la celda de arriba un estrato SATURADO
                ! (lambda_g = 0 -> W = 0) no drenaba hacia uno seco; Godunov
                ! toma el maximo de f entre las dos saturaciones.
                F = F - liq%rho(iH,jH,kH) * area * &
                        god_bl(sat(iH,jH,kH), sat(iL,jL,kL), ef, ws_mKl(iH,jH,kH), &
                               ws_mKg(iH,jH,kH), max(liq%rho(iH,jH,kH) - gas%rho(iH,jH,kH), 0.0_dp), &
                               liq%rho(iH,jH,kH))
            else
                F = F - liq%rho(iH,jH,kH) * ef * sat(iH,jH,kH) * (1.0_dp - sat(iL,jL,kL)) &
                        * ws_mW(iH,jH,kH) * area
            end if
        end function mixflux

        ! Flujo de Godunov (superficial, m/s, hacia abajo) entre el dador de
        ! arriba (sU) y el receptor de abajo (sD) para la funcion de flujo de
        ! deslizamiento del lecho. sU >= sD: max de f en [sD, sU]; si no, min
        ! en [sU, sD] (Godunov para flujo en el sentido U -> D).
        function god_bl(sU, sD, e, Kl, Kg, drho, rl) result(fg)
            real(dp), intent(in) :: sU, sD, e, Kl, Kg, drho, rl
            real(dp) :: fg, a, b, sv, fv, ub
            integer  :: n
            integer, parameter :: NS = 40
            ub = 1.53_dp * (1.8_dp * GRAVITY * drho / rl**2)**0.25_dp
            a = min(sU, sD); b = max(sU, sD)
            if (sU >= sD) then
                fg = 0.0_dp
            else
                fg = huge(1.0_dp)
            end if
            do n = 0, NS
                sv = a + (b - a) * real(n, dp) / real(NS, dp)
                fv = fbl(sv, e, Kl, Kg, drho, ub)
                if (sU >= sD) then
                    fg = max(fg, fv)
                else
                    fg = min(fg, fv)
                end if
            end do
            if (fg == huge(1.0_dp)) fg = 0.0_dp
        end function god_bl

        ! Funcion de flujo de deslizamiento del lecho (Darcy bifasico acotado
        ! por la burbuja de Harmathy), superficial [m/s]
        pure real(dp) function fbl(sx, e, Kl, Kg, drho, ub)
            real(dp), intent(in) :: sx, e, Kl, Kg, drho, ub
            real(dp) :: ll, lg
            ll = (e * sx)**2 / Kl
            lg = (e * (1.0_dp - sx))**2 / Kg
            fbl = 0.0_dp
            if (ll + lg > 0.0_dp) fbl = min(ub * e * sx * (1.0_dp - sx), &
                                            drho * GRAVITY * ll * lg / (ll + lg))
        end function fbl


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
        real(dp) :: u_t, tr, tth, tz, f, as_eff
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
                    ! LECHO o EN CONTACTO con el lecho (F2.14, 2026-09-26): la
                    ! celda tiene chatarra propia (aunque sea residual) o descansa
                    ! sobre una celda del lecho. En los modelos de lecho empacado
                    ! (Austin-Nogami-Yagi 1997, TFM de lechos de goteo) el arrastre
                    ! liquido-solido crece como 1/alpha_l^2 y la velocidad del
                    ! liquido tiende a la del SOLIDO cuando alpha_l -> 0: el
                    ! liquido disperso sobre chatarra es pelicula/goteo, nunca
                    ! gotas montadas en el gas. Con el umbral 1e-2 la celda recien
                    ! fundida (alpha_s 0.003-0.01) bajo el arco se trataba como
                    ! freeboard y su liquido llovia al lecho a la velocidad del
                    ! jet (20 m/s): rafagas de 25-84 kPa en B1 v30.
                    as_eff = max(sol%alpha_s(i,j,k), sol%alpha_s(i,j,k-1))
                    if (sol%alpha_s(i,j,k) > ALPHA_SOLID_RESID .or. &
                        sol%alpha_s(i,j,k-1) >= ALPHA_BED) then
                        ! percolacion al balance de Ergun (el estado
                        ! estacionario de SU PROPIA ecuacion de momento);
                        ! relajacion instantanea (tau = alpha_l rho_l /
                        ! drag_Ergun ~ 1e-4 s << dt) y no monta en el gas.
                        u_t = percolation_velocity(liq%alpha(i,j,k), as_eff, &
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
                            ws_Fc_af_r(i,j,k), liq%rho(i,j,k), liq%rho(i+1,j,k), Fe)
                    if (ws_Fc_lk_th(i,j,k) == 1) &
                        Gth(i,j,k) = conservative_noalpha(ws_Fc_th(i,j,k), &
                            ws_Fc_af_th(i,j,k), liq%rho(i,j,k), liq%rho(i,j+1,k), Fn)
                    if (ws_Fc_lk_z(i,j,k) == 1) &
                        Gz(i,j,k) = conservative_noalpha(ws_Fc_z(i,j,k), &
                            ws_Fc_af_z(i,j,k), liq%rho(i,j,k), liq%rho(i,j,k+1), Ft)
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
    ! (D2.6: a_f es la fraccion de cara que uso el Poisson, ws_Fc_af_*; para
    ! una cara continuo|continuo es la media de las dos celdas, como antes)
    pure function conservative_noalpha(Q, a_f, rho_lo, rho_hi, F_center) result(G)
        real(dp), intent(in) :: Q, a_f, rho_lo, rho_hi, F_center
        real(dp) :: G
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
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft, vol_dt, a_pre, clip_call, clipE_call

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call ensure_workspace(m)
        ws_flux_valid = .false.
        clip_call = 0.0_dp; clipE_call = 0.0_dp
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
                    clipE_call = clipE_call + &
                        (a_pre - liq%alpha(i,j,k)) * liq%rho(i,j,k) * m%vol(i,j,k) &
                        * (liq%cp(i,j,k) * liq%T(i,j,k) + (cfg%cp_s - cfg%cp_l) &
                           * cfg%T_liquidus + cfg%h_fusion)
                    gas%alpha(i,j,k) = 1.0_dp - sol%alpha_s(i,j,k) &
                                       - alpha_slag(i,j,k) - liq%alpha(i,j,k)
                    gas%alpha(i,j,k) = max(0.0_dp, gas%alpha(i,j,k))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(liq%alpha, m%topo)
        call mpi_exchange_halos_3d(gas%alpha, m%topo)
        call audit_step_delta(AUD_ALPHA_CLIP_MASS, clip_call, clip_step_prev, clip_step_id)
        call audit_step_delta(AUD_ALPHA_CLIP_E, clipE_call, clipE_step_prev, clipE_step_id)
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
