!===============================================================================
! mod_energy_3d.f90 - Energy equation in 3D cylindrical coordinates
!
! Solves: rho*cp*(dT/dt + u_r*dT/dr + u_th/r*dT/dtheta + u_z*dT/dz)
!       = 1/r*d/dr(r*k*dT/dr) + 1/r^2*d/dtheta(k*dT/dtheta) + d/dz(k*dT/dz) + S
!
! Discretized with FVM: implicit Euler, upwind convection, central diffusion.
! Phase-specific: called once for liquid, once for gas, with respective alpha_q.
!===============================================================================
module mod_energy_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    use mod_face_flux
    use mod_audit, only: audit_set_energy
    implicit none

contains

    subroutine solve_energy_3d(ph, T_old, sh, m, cfg, alpha_q, alpha_other, &
                               alpha_old, mdot, T_src, is_gas, residual)
        use mod_face_flux, only: face_mass_fluxes_noalpha
        use mod_workspace, only: ensure_workspace, ws_Fr, ws_Fth, ws_Fz, &
            ws_Fg_r, ws_Fg_th, ws_Fg_z, ws_Fg_valid, &
            ws_flux_valid, ws_mQ_r, ws_mQ_th, ws_mQ_z, ws_mix_valid, aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su
        type(phase_t), intent(inout) :: ph
        real(dp), intent(in)         :: T_old(-1:,-1:,-1:)
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(in)         :: alpha_q(-1:,-1:,-1:)
        ! Fracción de la OTRA fase fluida: las fuentes volumétricas (S_arc,
        ! S_rad, S_chem) se reparten por peso w = alpha_q/(alpha_l+alpha_g).
        ! Antes cada fase recibía el 100% de cada fuente: donde ambas
        ! superaban el cutoff la potencia se DUPLICABA (hallazgo 3.1b).
        real(dp), intent(in)         :: alpha_other(-1:,-1:,-1:)
        ! Fracción de ESTA fase al inicio del paso (alpha^n). Forma exacta de
        ! Patankar (continuidad discreta restada): el transitorio lleva la
        ! masa VIEJA, alpha^n*rho*cp*V/dt*(T - T_old); la masa nueva entra
        ! por sus propios términos (a_nb de entrada, mdot*cp*T_src). Con
        ! alpha^{n+1} en el transitorio (forma previa) la masa recién
        ! llegada figuraba como si hubiera existido a T_old: una celda vacía
        ! (T_old = 300 K inicial) que recibe fundido a 1809 K quedaba a
        ! (300+1809)/2 y re-solidificaba al paso siguiente — B1 v6: 9646 kg
        ! fundidos, 9315 re-solidificados, 10 kg de baño a los 442 s, 68%
        ! de las celdas líquidas bajo el solidus (mediana 740 K). Solo se
        ! usa para el LÍQUIDO: el gas conserva la forma T con rho(T) a la
        ! que está calibrado su libro (E_gas_abs).
        real(dp), intent(in)         :: alpha_old(-1:,-1:,-1:)
        ! Fuente de masa por fusión/solidificación (C1.8, solo líquido):
        ! mdot>0 la masa fundida entra a T_src (temperatura del sólido);
        ! mdot<0: sumidero de congelacion (auditoria 2, N-C2): con el
        ! transitorio alpha^n la forma exacta es M^n (e' - e^n) = dm (e' -
        ! e_entry) -> aP -= |mdot| cp, Su += |mdot| (C0 - e_entry) (ver el
        ! ensamblado). La forma "el sumidero se cancela" (hasta oct-2026)
        ! evaluaba el latente con T_old y perdia dm (e' - e^n) por paso.
        real(dp), intent(in)         :: mdot(-1:,-1:,-1:)
        real(dp), intent(in)         :: T_src(-1:,-1:,-1:)
        ! Identidad de fase: el LÍQUIDO difunde con k_eff = k + cp*mu_t/Pr_t
        ! (transporte térmico turbulento, hallazgo 3.12 — antes ausente
        ! mientras momentum sí usaba mu_t); el gas usa su k molecular
        ! (mu_t proviene del k-eps del líquido y no le aplica).
        logical, intent(in)          :: is_gas
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: rho_f, k_f, vol, rho_cp_vol_dt, alpha_tr, ee
        real(dp) :: alpha_f, w_src, w_rad, C0_datum, aP_rad, T_it, aP_wall

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Dato común de entalpía: e_l(T) = cp_l*T + C0 (ver mod_melting_3d)
        C0_datum = (cfg%cp_s - cfg%cp_l) * cfg%T_liquidus + cfg%h_fusion

        ! Allocate with halos
        call ensure_workspace(m)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    vol = m%vol(i,j,k)
                    alpha_f = max(alpha_q(i,j,k), SMALL)

                    ! Negligible phase fraction: trivial equation keeps T = T_old.
                    ! Prevents near-zero aP from making the TDMA diagonal singular.
                    if (alpha_q(i,j,k) < ALPHA_CUTOFF) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = T_old(i,j,k)
                        cycle
                    end if

                    ! Transitorio con la masa VIEJA (líquido; ver alpha_old)
                    if (is_gas) then
                        alpha_tr = alpha_f
                    else
                        alpha_tr = max(alpha_old(i,j,k), 0.0_dp)
                    end if
                    rho_cp_vol_dt = alpha_tr * ph%rho(i,j,k) * ph%cp(i,j,k) * vol / cfg%dt

                    ! --- Diffusion conductances ---
                    Dw = 0.0_dp; De = 0.0_dp; Db = 0.0_dp; Dt = 0.0_dp
                    ! West face (i-1/2)
                    if (m%cell_type(i-1,j,k) /= 0) then
                            k_f = harm(keff(i,j,k), keff(i-1,j,k))
                            Dw = aface(alpha_q(i,j,k), alpha_q(i-1,j,k)) * k_f * m%Ar(i-1,j,k) / &
                                 (0.5_dp * (m%dr(i) + m%dr(i-1)))
                        end if

                    ! East face (i+1/2)
                    if (m%cell_type(i+1,j,k) /= 0) then
                            k_f = harm(keff(i,j,k), keff(i+1,j,k))
                            De = aface(alpha_q(i,j,k), alpha_q(i+1,j,k)) * k_f * m%Ar(i,j,k) / &
                                 (0.5_dp * (m%dr(i) + m%dr(i+1)))
                        end if

                    ! South face (j-1/2) in theta
                    k_f = harm(keff(i,j,k), keff(i,jm,k))
                    Ds = aface(alpha_q(i,j,k), alpha_q(i,jm,k)) * k_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jm)))

                    ! North face (j+1/2) in theta
                    k_f = harm(keff(i,j,k), keff(i,jp,k))
                    Dn = aface(alpha_q(i,j,k), alpha_q(i,jp,k)) * k_f * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jp)))

                    ! Bottom face (k-1/2)
                    if (m%cell_type(i,j,k-1) /= 0) then
                            k_f = harm(keff(i,j,k), keff(i,j,k-1))
                            Db = aface(alpha_q(i,j,k), alpha_q(i,j,k-1)) * k_f * m%Az(i,j,k-1) / &
                                 (0.5_dp * (m%dz(k) + m%dz(k-1)))
                        end if

                    ! Top face (k+1/2)
                    if (m%cell_type(i,j,k+1) /= 0) then
                            k_f = harm(keff(i,j,k), keff(i,j,k+1))
                            Dt = aface(alpha_q(i,j,k), alpha_q(i,j,k+1)) * k_f * m%Az(i,j,k) / &
                                 (0.5_dp * (m%dz(k) + m%dz(k+1)))
                        end if

                    ! --- Convection (upwind) ---
                    rho_f = ph%rho(i,j,k)
                    Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp; Fn = 0.0_dp
                    Fb = 0.0_dp; Ft = 0.0_dp

                    if (cfg%solve_flow) then
                        ! Flujos de cara únicos y conservativos (C2.2),
                        ! multiplicados por cp: el flujo convectivo de calor
                        ! es mdot*cp*T. El código original sumaba F [kg/s]
                        ! directamente a D [W/K] — la convección térmica
                        ! quedaba subponderada ~cp (x700-1000).
                        if (is_gas .and. cfg%mixture_model .and. ws_mix_valid &
                            .and. ws_flux_valid) then
                            ! MEZCLA (auditoria M36): el gas mueve el
                            ! COMPLEMENTO del flujo volumetrico de mezcla,
                            ! Q_g = Q - Q_l (Q_l = flujo de masa del transporte
                            ! de alpha / rho_steel, densidad constante del
                            ! liquido), con la rho_g del dador. Antes: flujos
                            ! reconstruidos de las velocidades de fase, que no
                            ! suman Q -> la energia del gas no movia el volumen
                            ! que dejo la continuidad.
                            Fw = gflux(ws_mQ_r(i-1,j,k) - ws_Fr(i-1,j,k) / cfg%rho_steel, i-1, j, k, i, j, k)
                            Fe = gflux(ws_mQ_r(i,j,k)   - ws_Fr(i,j,k)   / cfg%rho_steel, i, j, k, i+1, j, k)
                            Fs = gflux(ws_mQ_th(i,jm,k) - ws_Fth(i,jm,k) / cfg%rho_steel, i, jm, k, i, j, k)
                            Fn = gflux(ws_mQ_th(i,j,k)  - ws_Fth(i,j,k)  / cfg%rho_steel, i, j, k, i, jp, k)
                            Fb = gflux(ws_mQ_z(i,j,k-1) - ws_Fz(i,j,k-1) / cfg%rho_steel, i, j, k-1, i, j, k)
                            Ft = gflux(ws_mQ_z(i,j,k)   - ws_Fz(i,j,k)   / cfg%rho_steel, i, j, k, i, j, k+1)
                        else if (is_gas .and. ws_Fg_valid) then
                            ! GAS con los flujos de MASA conservativos de su
                            ! Poisson (auditoria 2, N-M3), los mismos que su
                            ! momento (M24): la reconstruccion simetrica de
                            ! centro no es solenoidal y el deficit convectivo de
                            ! la forma acotada ~ T x (desbalance de masa) no
                            ! cerraba la energia (bed_drain: -9e7 J)
                            Fw = ws_Fg_r(i-1,j,k);  Fe = ws_Fg_r(i,j,k)
                            Fs = ws_Fg_th(i,jm,k);  Fn = ws_Fg_th(i,j,k)
                            Fb = ws_Fg_z(i,j,k-1);  Ft = ws_Fg_z(i,j,k)
                        else if (is_gas) then
                            call face_mass_fluxes(alpha_q, ph%rho, ph%ur, &
                                ph%uth, ph%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                        else
                            ! LÍQUIDO (sep-2026): flujo DONOR-CELL, el mismo
                            ! que usa el transporte de alpha (mod_continuity):
                            ! rho*u simétrico en la cara x alpha del lado
                            ! upwind. Con la interpolación simétrica de alpha
                            ! una celda vacía (alpha=0) "entregaba" ½·alpha_P·
                            ! rho·u de masa fantasma a la T rancia de la celda
                            ! vacía (300 K inicial): en B1 v7 el 42% de las
                            ! caras de celdas líquidas daban a vecinas vacías
                            ! y el déficit convectivo acumulaba -2.2 GJ (la
                            ! mitad de la entalpía fundida). Es además la
                            ! única forma en que la forma con continuidad
                            ! restada (alpha_old) es exacta.
                            if (ws_flux_valid) then
                                ! flujos EFECTIVOS del transporte de alpha
                                ! (limitador de hueco incluido, promedio de
                                ! sub-pasos): la energía mueve exactamente la
                                ! masa que movió la continuidad
                                Fw = ws_Fr(i-1,j,k);  Fe = ws_Fr(i,j,k)
                                Fs = ws_Fth(i,jm,k);  Fn = ws_Fth(i,j,k)
                                Fb = ws_Fz(i,j,k-1);  Ft = ws_Fz(i,j,k)
                            else
                                call face_mass_fluxes_noalpha(ph%rho, ph%ur, &
                                    ph%uth, ph%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                                Fw = donor(Fw, alpha_q(i-1,j,k), alpha_q(i,j,k))
                                Fe = donor(Fe, alpha_q(i,j,k), alpha_q(i+1,j,k))
                                Fs = donor(Fs, alpha_q(i,jm,k), alpha_q(i,j,k))
                                Fn = donor(Fn, alpha_q(i,j,k), alpha_q(i,jp,k))
                                Fb = donor(Fb, alpha_q(i,j,k-1), alpha_q(i,j,k))
                                Ft = donor(Ft, alpha_q(i,j,k), alpha_q(i,j,k+1))
                            end if
                        end if
                        Fw = Fw * ph%cp(i,j,k); Fe = Fe * ph%cp(i,j,k)
                        Fs = Fs * ph%cp(i,j,k); Fn = Fn * ph%cp(i,j,k)
                        Fb = Fb * ph%cp(i,j,k); Ft = Ft * ph%cp(i,j,k)
                    end if

                    ! Upwind: a_nb = D + max(F, 0) or D + max(-F, 0)
                    aW(i,j,k) = Dw + max( Fw, 0.0_dp)
                    aE(i,j,k) = De + max(-Fe, 0.0_dp)
                    aS(i,j,k) = Ds + max( Fs, 0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn, 0.0_dp)
                    aB(i,j,k) = Db + max( Fb, 0.0_dp)
                    aT(i,j,k) = Dt + max(-Ft, 0.0_dp)

                    ! Source: transient + heat sources ponderadas por fase.
                    ! Radiación (C3.4): linearización de NEWTON de la emisión
                    ! alrededor del ITERADO actual T_it (Patankar):
                    !   k(G - 4σT^4) ≈ k(G + 12σT_it^4) - 16kσT_it^3 · T
                    ! S_C a Su y S_P a aP. Con pendiente 4σT_old^3 (anclada
                    ! al paso anterior) una celda fría con G grande saltaba a
                    ! T ~ G/(4σT_old^3) astronómica.
                    w_src = alpha_q(i,j,k) / &
                            (alpha_q(i,j,k) + alpha_other(i,j,k) + SMALL)
                    ! Radiacion: reparto por ABSORCION kappa_q alpha_q (A11; el
                    ! liquido es opaco en la DO). El ARCO tambien (auditoria 2,
                    ! N-A2): S_arc es sobre todo radiacion del MC y el chorro
                    ! que pega en la superficie; por fraccion de volumen el gas
                    ! de una celda de superficie se llevaba 50-70 % (con baño
                    ! plano el liquido recibia el 6.9 % del arco absorbido). La
                    ! quimica va al gas (w_chem).
                    w_rad = rad_weight(alpha_q(i,j,k), alpha_other(i,j,k))
                    T_it = max(ph%T(i,j,k), 200.0_dp)
                    ! (auditoria 4, A4-5) la EMISION que resta esta ecuacion es
                    ! la MISMA que transporto la DO (a T_old, la T con la que se
                    ! llamo): kappa (G - 4 sigma T_old^4). La pendiente de
                    ! Newton 16 sigma T_it^3 sigue implicita (aP) y su termino
                    ! fuente 16 sigma T_it^3 T_it hace que se ANULE al converger
                    ! (T = T_it): asi la radiacion cierra (sum fases + solido +
                    ! pared = 0 hasta la convergencia de la DO). Antes el nivel
                    ! era 12 sigma T_it^4, es decir emision a T_it al converger:
                    ! 4 kappa sigma (T_it^4 - T_old^4) de energia creada o
                    ! destruida por paso (1.2-2.5 % del arco; 41 % de lo
                    ! radiado en cold_10step).
                    Su(i,j,k) = rho_cp_vol_dt * T_old(i,j,k) &
                               + (sh%S_arc(i,j,k) * w_rad &
                                  + sh%S_chem(i,j,k) * w_chem(i,j,k, w_src)) * vol &
                               + w_rad * sh%kappa_f(i,j,k) * vol * &
                                 (sh%G_rad(i,j,k) + STEFAN_BOLTZMANN * &
                                  (16.0_dp * T_it**4 - 4.0_dp * max(T_old(i,j,k), 200.0_dp)**4))

                    ! Pérdidas de pared Robin (C3.1): en cada cara contra
                    ! celda inactiva (pared física o refractario del tazón):
                    ! flujo = h_wall*A*alpha*(T - T_wall), implícito
                    ! (aP += hA*alpha; Su += hA*alpha*T_wall). h_wall=0 (el
                    ! default) mantiene el comportamiento adiabático previo.
                    aP_wall = 0.0_dp
                    if (cfg%h_wall > 0.0_dp) then
                        if (m%cell_type(i-1,j,k) == 0) &
                            aP_wall = aP_wall + m%Ar(i-1,j,k)
                        if (m%cell_type(i+1,j,k) == 0) &
                            aP_wall = aP_wall + m%Ar(i,j,k)
                        if (m%cell_type(i,jm,k) == 0) &
                            aP_wall = aP_wall + m%Ath(i,j,k)
                        if (m%cell_type(i,jp,k) == 0) &
                            aP_wall = aP_wall + m%Ath(i,j,k)
                        if (m%cell_type(i,j,k-1) == 0) &
                            aP_wall = aP_wall + m%Az(i,j,k-1)
                        if (m%cell_type(i,j,k+1) == 0) &
                            aP_wall = aP_wall + m%Az(i,j,k)
                        aP_wall = aP_wall * cfg%h_wall * alpha_f
                        Su(i,j,k) = Su(i,j,k) + aP_wall * cfg%T_wall
                    end if

                    ! Emisión radiativa implícita (pendiente de Newton a aP)
                    aP_rad = w_rad * sh%kappa_f(i,j,k) * 16.0_dp * &
                             STEFAN_BOLTZMANN * T_it**3 * vol

                    ! Central coefficient — forma ACOTADA de Patankar
                    ! (aP = Sum(a_nb) + transitorio + rad). Se probaron la
                    ! conservativa implícita (+dF: T -> -2e4 K en compresión)
                    ! y la corrección diferida (diverge al converger el lazo);
                    ! el déficit conservativo de la forma acotada
                    ! (phi x residuo de continuidad) queda medido por el audit.
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_cp_vol_dt &
                               + aP_rad + aP_wall

                    ! Fuente de masa por fusión/solidificación (C1.8, líquido)
                    if (.not. is_gas) then
                        if (mdot(i,j,k) > 0.0_dp) then
                            ! Fundido entra a T_src: Su += mdot*cp*T_in,
                            ! aP += mdot*cp (la masa nueva trae su propia T)
                            Su(i,j,k) = Su(i,j,k) + mdot(i,j,k) * &
                                        ph%cp(i,j,k) * T_src(i,j,k)
                            aP(i,j,k) = aP(i,j,k) + mdot(i,j,k) * ph%cp(i,j,k)
                        else if (mdot(i,j,k) < 0.0_dp) then
                            ! Sumidero de CONGELACION (auditoria 2, N-C2). Con
                            ! el transitorio alpha^n la forma exacta es
                            !   M^n (e' - e^n) = dm (e' - e_entry)
                            ! (la masa congelada sale del liquido a e' y entra
                            ! al solido a e_entry, el MISMO de compute_melting;
                            ! min con e_s(T_solidus) <=> fuente no negativa).
                            ! En T: aP -= |mdot| cp, Su += |mdot| (C0 - e_entry).
                            ! Antes el latente se evaluaba con T_old: se perdia
                            ! dm (e' - e^n) por paso y el liquido no llegaba a
                            ! e_lb (bath_freeze: -1.8e9 J sin fuente). aP sigue
                            ! > 0: dm <= RESOLID_LIMITER M^n < M^n.
                            ee = min(cfg%cp_s * cfg%T_solidus, &
                                     ph%cp(i,j,k) * T_old(i,j,k) + C0_datum)
                            aP(i,j,k) = aP(i,j,k) + mdot(i,j,k) * ph%cp(i,j,k)
                            Su(i,j,k) = Su(i,j,k) - mdot(i,j,k) * (C0_datum - ee)
                        end if
                    end if

                    ! Celda con fase nueva pero sin masa vieja, sin entrada
                    ! por caras, sin fuente de masa ni difusión (continuidad
                    ! discreta no exacta, p.ej. fallback implícito de alpha):
                    ! ecuación trivial en vez de diagonal nula.
                    if (aP(i,j,k) <= SMALL) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = T_old(i,j,k)
                    end if
                end do
            end do
        end do

        ! Apply boundary conditions
        call apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, cfg%T_ambient)

        ! Residual del ITERADO ENTRANTE (semántica correcta del lazo
        ! externo, cierre 2026): mide si el campo QUE QUEDA EN PIE satisface
        ! la ecuación. El residual del campo recién resuelto (post-TDMA) es
        ! siempre ~0 y declaraba convergencia en 1 outer mientras el campo
        ! relajado solo aplicaba alpha_T (~70%) del solve — 29% de las
        ! fuentes de energía se perdía por paso (medido: era exactamente el
        ! hueco del balance).
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, &
                                           ph%T, m)

        ! Solve with MPI-aware TDMA (Tpre = iterado del ensamblado, para
        ! reconstruir la linearización de Newton en el hook de auditoría)
        block
            real(dp), allocatable :: Tpre(:,:,:)
            allocate(Tpre, mold=ph%T)
            Tpre = ph%T
            call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, ph%T, m, &
                             cfg%max_inner_mom)
            ! Halos de la solucion: el TDMA los intercambia ANTES de cada
            ! barrido, no despues del ultimo (auditoria M5: el hook leia T
            ! rancia de las vecinas de otro rank y la convección no
            ! telescopaba entre ranks -> identidad dependiente de la
            ! descomposición)
            call mpi_exchange_halos_3d(ph%T, m%topo)
            call energy_audit_hook(Tpre)
            deallocate(Tpre)
        end block

        ! (C2.1: sub-relajación en el lazo externo contra el iterado
        ! anterior — ver multiphase_iteration/relax_field)

    contains

        ! Peso de S_chem (auditoria, bajos): es calor de la combustion CO -> CO2
        ! EN FASE GAS (mas la entalpia del C que sale con el CO, M15): todo al
        ! gas donde lo hay; al liquido solo sin gas resuelto (rama sin energia
        ! del gas, alpha_other = 0). Antes se repartia por fraccion de volumen y
        ! calentaba tambien al liquido.
        pure function w_chem(ii, jj, kk, wv) result(w)
            integer, intent(in)  :: ii, jj, kk
            real(dp), intent(in) :: wv
            real(dp) :: w
            if (is_gas) then
                w = 1.0_dp
            else if (alpha_other(ii,jj,kk) >= ALPHA_CUTOFF) then
                w = 0.0_dp
            else
                w = wv
            end if
        end function w_chem

        ! Flujo de masa del gas en una cara de lo -> hi con caudal volumetrico
        ! Qg: rho_g del dador (M36); 0 si alguna celda es pared
        function gflux(Qg, il, jl, kl, ih, jh, kh) result(F)
            real(dp), intent(in) :: Qg
            integer, intent(in)  :: il, jl, kl, ih, jh, kh
            real(dp) :: F
            F = 0.0_dp
            if (m%cell_type(il,jl,kl) == 0 .or. m%cell_type(ih,jh,kh) == 0) return
            if (Qg >= 0.0_dp) then
                F = ph%rho(il,jl,kl) * Qg
            else
                F = ph%rho(ih,jh,kh) * Qg
            end if
        end function gflux

        ! Conductividad efectiva del centro de celda: k + cp*mu_t/Pr_t para
        ! el líquido (transporte turbulento); molecular para el gas
        pure function keff(ii, jj, kk) result(kv)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: kv
            kv = ph%kth(ii,jj,kk)
            if (.not. is_gas) then
                kv = kv + ph%cp(ii,jj,kk) * sh%mu_t(ii,jj,kk) / PR_T
            end if
        end function keff

        ! Fracción de fase EN LA CARA para la conductancia difusiva: media
    ! armónica (simétrica -> la difusión telescopa exactamente; nula si
    ! un lado no tiene la fase). Con alpha_P sola, una celda líquida
    ! conducía calor hacia el "líquido" inexistente de la vecina vacía
    ! (T rancia = 300 K): sumidero infinito no auditado (B1 v6/v7).
    pure function aface(a1, a2) result(af)
        real(dp), intent(in) :: a1, a2
        real(dp) :: af
        af = 2.0_dp * a1 * a2 / max(a1 + a2, SMALL)
    end function aface

    ! Flujo de masa donor-cell en una cara orientada de "lo" (lado -) a
    ! "hi" (lado +): F>0 va de lo a hi y lleva alpha_lo; F<0 lleva alpha_hi.
    pure function donor(F, a_lo, a_hi) result(Fd)
        real(dp), intent(in) :: F, a_lo, a_hi
        real(dp) :: Fd
        if (F >= 0.0_dp) then
            Fd = F * a_lo
        else
            Fd = F * a_hi
        end if
    end function donor

    pure function harm(ka, kb) result(kf)
            real(dp), intent(in) :: ka, kb
            real(dp) :: kf
            kf = 2.0_dp * ka * kb / max(ka + kb, SMALL)
        end function harm


        !-------------------------------------------------------------------
        ! Hook de auditoría (cierre 2026): términos EXACTOS del enunciado
        ! discreto de ESTA llamada, con los arrays ensamblados y la
        ! linearización de Newton evaluada en el iterado del ensamblado
        ! (T_it = max(Tpre,200)). La última iteración externa del paso
        ! sobrescribe (audit_set_energy) — es la solución que queda en pie.
        !-------------------------------------------------------------------
        subroutine energy_audit_hook(Tpre)
            real(dp), intent(in) :: Tpre(-1:,-1:,-1:)

            integer  :: ii, jj, kk
            real(dp) :: s_abs, s_arc, s_rad, s_chem, s_conv, s_wall, s_mass
            real(dp) :: ww, Tit, rcv, apw, vv, ee
            real(dp), allocatable :: Tk(:,:,:)

            ! Campo que QUEDA EN PIE (auditoria M5): todos los llamadores
            ! relajan contra el iterado de entrada con cfg%alpha_T
            ! (relax_field). Evaluar los flujos sobre la solucion SIN relajar
            ! medía un campo que nunca se guarda: con el lazo externo sin
            ! converger la identidad cerraba contra un estado inexistente.
            ! (Modelo de mezcla: el intercambio gas-liquido se aplica entre
            ! el solve y la relajacion; es interno y se cancela entre fases.)
            allocate(Tk, mold=ph%T)
            Tk = cfg%alpha_T * ph%T + (1.0_dp - cfg%alpha_T) * Tpre

            s_abs=0.0_dp; s_arc=0.0_dp; s_rad=0.0_dp; s_chem=0.0_dp
            s_conv=0.0_dp; s_wall=0.0_dp; s_mass=0.0_dp
            do kk = kstart, kend
                do jj = jstart, jend
                    do ii = istart, iend
                        if (m%cell_type(ii,jj,kk) == 0) cycle
                        if (alpha_q(ii,jj,kk) < ALPHA_CUTOFF) cycle
                        vv  = m%vol(ii,jj,kk)
                        if (is_gas) then
                            rcv = max(alpha_q(ii,jj,kk), SMALL)
                        else
                            rcv = max(alpha_old(ii,jj,kk), 0.0_dp)
                        end if
                        rcv = rcv * ph%rho(ii,jj,kk) * ph%cp(ii,jj,kk) * vv / cfg%dt
                        ww  = alpha_q(ii,jj,kk) / (alpha_q(ii,jj,kk) + &
                              alpha_other(ii,jj,kk) + SMALL)
                        Tit = max(Tpre(ii,jj,kk), 200.0_dp)
                        s_abs = s_abs + rcv * (Tk(ii,jj,kk) - &
                                T_old(ii,jj,kk)) * cfg%dt
                        s_arc = s_arc + sh%S_arc(ii,jj,kk) &
                                * rad_weight(alpha_q(ii,jj,kk), alpha_other(ii,jj,kk)) * vv * cfg%dt
                        s_chem = s_chem + sh%S_chem(ii,jj,kk) * w_chem(ii,jj,kk, ww) * vv * cfg%dt
                        s_rad = s_rad + rad_weight(alpha_q(ii,jj,kk), alpha_other(ii,jj,kk)) &
                                * sh%kappa_f(ii,jj,kk) * vv * &
                                (sh%G_rad(ii,jj,kk) + STEFAN_BOLTZMANN * &
                                 (16.0_dp * Tit**4 - 4.0_dp * max(T_old(ii,jj,kk), 200.0_dp)**4 &
                                  - 16.0_dp * Tit**3 * Tk(ii,jj,kk))) * cfg%dt
                        ! Convección+difusión del enunciado acotado (la
                        ! difusión telescopa; el residuo es el déficit
                        ! convectivo). Signo: contribución a E_in = -esto.
                        s_conv = s_conv + cfg%dt * ( &
                              aW(ii,jj,kk)*(Tk(ii,jj,kk)-Tk(ii-1,jj,kk)) &
                            + aE(ii,jj,kk)*(Tk(ii,jj,kk)-Tk(ii+1,jj,kk)) &
                            + aS(ii,jj,kk)*(Tk(ii,jj,kk)-Tk(ii,jj-1,kk)) &
                            + aN(ii,jj,kk)*(Tk(ii,jj,kk)-Tk(ii,jj+1,kk)) &
                            + aB(ii,jj,kk)*(Tk(ii,jj,kk)-Tk(ii,jj,kk-1)) &
                            + aT(ii,jj,kk)*(Tk(ii,jj,kk)-Tk(ii,jj,kk+1)) )
                        if (cfg%h_wall > 0.0_dp) then
                            apw = 0.0_dp
                            if (m%cell_type(ii-1,jj,kk) == 0) apw = apw + m%Ar(ii-1,jj,kk)
                            if (m%cell_type(ii+1,jj,kk) == 0) apw = apw + m%Ar(ii,jj,kk)
                            if (m%cell_type(ii,jj-1,kk) == 0) apw = apw + m%Ath(ii,jj,kk)
                            if (m%cell_type(ii,jj+1,kk) == 0) apw = apw + m%Ath(ii,jj,kk)
                            if (m%cell_type(ii,jj,kk-1) == 0) apw = apw + m%Az(ii,jj,kk-1)
                            if (m%cell_type(ii,jj,kk+1) == 0) apw = apw + m%Az(ii,jj,kk)
                            apw = apw * cfg%h_wall * max(alpha_q(ii,jj,kk), SMALL)
                            s_wall = s_wall + apw * (Tk(ii,jj,kk) - &
                                     cfg%T_wall) * cfg%dt
                        end if
                        if (.not. is_gas) then
                            if (mdot(ii,jj,kk) > 0.0_dp) then
                                s_mass = s_mass + mdot(ii,jj,kk) * &
                                    ph%cp(ii,jj,kk) * (T_src(ii,jj,kk) - &
                                    Tk(ii,jj,kk)) * cfg%dt
                            else if (mdot(ii,jj,kk) < 0.0_dp) then
                                ! latente con la e NUEVA (N-C2; misma forma que
                                ! el solver): |mdot| (e(Tk) - e_entry)
                                ee = min(cfg%cp_s * cfg%T_solidus, &
                                     ph%cp(ii,jj,kk) * T_old(ii,jj,kk) + C0_datum)
                                s_mass = s_mass + cfg%dt * ( &
                                    - mdot(ii,jj,kk) * (ph%cp(ii,jj,kk) * &
                                      Tk(ii,jj,kk) + C0_datum - ee) )
                            end if
                        end if
                    end do
                end do
            end do
            deallocate(Tk)
            call audit_set_energy(is_gas, s_abs, s_arc, s_rad, s_chem, &
                                  -s_conv, s_wall, s_mass)
        end subroutine energy_audit_hook

        ! Fraccion de la absorcion/emision radiativa del fluido que toca a ESTA
        ! fase: kappa_q alpha_q / (kappa_l alpha_l + kappa_g alpha_g), los
        ! mismos coeficientes con que la DO arma kappa_f (A11)
        pure function rad_weight(aq, ao) result(w)
            real(dp), intent(in) :: aq, ao
            real(dp) :: w, kq, ko
            if (is_gas) then
                kq = KAPPA_GAS_ABS * max(aq, 0.0_dp); ko = KAPPA_LIQ_ABS * max(ao, 0.0_dp)
            else
                kq = KAPPA_LIQ_ABS * max(aq, 0.0_dp); ko = KAPPA_GAS_ABS * max(ao, 0.0_dp)
            end if
            w = kq / (kq + ko + SMALL)
        end function rad_weight

    end subroutine solve_energy_3d

end module mod_energy_3d
