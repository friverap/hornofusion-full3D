!===============================================================================
! mod_mixture_3d.f90 - Modelo de MEZCLA con deslizamiento algebraico (Plan G)
!
! Alternativa al modelo de dos fluidos para el acople presion-velocidad-alpha
! (clave `mixture_model`, default false). Motivo: el modelo de dos fluidos con
! una sola presion pierde la hiperbolicidad cuando una fase desaparece, y en el
! lecho inundado de B1 (~320 s) cada mecanismo para tratar la fase evanescente
! (F2.13, F2.16, F2.31, Planes D/E/F) cambiaba de sitio el golpe de ariete del
! poro que se llena (docs/PLAN_F_gas_resorte.md). En el modelo de mezcla no hay
! fase que desaparezca DENTRO del acople: una sola velocidad, una sola presion,
! y la fraccion de liquido se transporta con el flujo de la mezcla mas un
! deslizamiento acotado que la presion no ve.
!
! Formulacion (drift-flux, Ishii 1977 / Zuber-Findlay 1965, Manninen 1996, en
! forma VOLUMETRICA como el Poisson de volumen de Plan C F2):
!   eps   = 1 - alpha_s - alpha_sl        porosidad fluida (liquido + gas)
!   s     = alpha_l / eps                 saturacion de liquido
!   rho_m = (alpha_l rho_l + alpha_g rho_g) / eps   densidad intersticial
!   v     = (alpha_l u_l + alpha_g u_g) / eps       velocidad VOLUMETRICA
!                                                   intersticial de la mezcla
!   continuidad (volumen):  div(eps v) = fuentes de compresibilidad del gas
!       (la fusion es neutra en volumen: rho_l = rho_s; Plan C F2)
!   momento:  eps rho_m Dv/Dt = -eps grad p + eps rho_m g - K_Ergun v
!             + Lorentz + chorro del arco + viscoso
!   liquido:  d alpha_l/dt + div(s eps v + eps s (1-s) u_r) = mdot/rho_l
!   u_r = u_l - u_g (relativa, vertical): gota en el freeboard (terminal),
!         burbuja en el bano (Harmathy), percolacion de Ergun en el lecho.
!   Fases: u_l = v + (1-s) u_r,  u_g = v - s u_r  (energia, especies, salida).
!
! Aproximaciones documentadas: (1) el momento usa la velocidad volumetrica
! con la inercia de la mezcla (se desprecia el tensor de drift
! div(alpha rho u_dr u_dr) y la diferencia entre la velocidad masica y la
! volumetrica: equilibrio local de deslizamiento); (2) el deslizamiento es
! algebraico (sin relajacion de particula).
!
! Discretizacion: FVM colocado, Rhie-Chow con FUERZAS DE CARA BALANCEADAS
! (presion + gravedad evaluadas en la cara, la fuerza de celda es la media de
! las de sus caras; Francois et al. 2006, interFoam): en equilibrio
! hidrostatico discreto toda fuerza de cara es cero y no hay corrientes
! espurias en la superficie del bano (salto de densidad 7000:1).
!
! Acople alpha-p IMPLICITO: el transporte de alpha corre DENTRO de cada
! iteracion externa con los flujos conservativos de esa iteracion y la
! convergencia exige |dalpha| entre iteraciones < tol_alpha_mix
! (check_convergence): el paso converge en (v, p, alpha) a la vez (Picard).
! Sin estado entre pasos: v se reconstruye de las velocidades de fase
! guardadas => el reinicio es bit a bit sin campos nuevos.
!===============================================================================
module mod_mixture_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    use mod_mpi_topology, only: mpi_exchange_halos_3d, mpi_allreduce_max, mpi_allreduce_sum, &
                                mpi_allreduce_min
    use mod_energy_3d
    use mod_continuity
    use mod_properties_3d
    use mod_fields_3d
    use mod_pressure_3d, only: C_SOUND_LIQ, COMP_SRC_CAP, P_HYDRO_CAP, PP_COMPLIANCE
    use mod_multiphase, only: cap_gas_velocity, cap_liquid_velocity
    use mod_probe, only: probe_current_step
    use mod_audit, only: AUD_IPH_GAS, AUD_IPH_LIQ, AUD_MIX_INIT, audit_add
    use mod_workspace, only: ensure_workspace, ws_cc, ws_cc_new, aW => ws_aW, aE => ws_aE, aS => ws_aS, &
        aN => ws_aN, aB => ws_aB, aT => ws_aT, aP => ws_aP, Su => ws_Su, &
        ws_liq_cont, ws_liq_cont_valid, ws_ud_r, ws_ud_th, ws_ud_z, ws_ut, ws_mQ_r, ws_mQ_th, ws_mQ_z, ws_mW, &
        ws_mix_valid, ws_mix_id, ws_mKl, ws_mKg, ws_Tsrc
    implicit none
    private
    public :: mixture_iteration

    ! Tension superficial del acero liquido [N/m] (burbuja de Harmathy)
    real(dp), parameter :: SIGMA_STEEL = 1.8_dp

    ! Estado de trabajo del paso (save: se realoca una vez)
    real(dp), allocatable, save :: vr(:,:,:), vth(:,:,:), vz(:,:,:)        ! iterado de v
    real(dp), allocatable, save :: vr_o(:,:,:), vth_o(:,:,:), vz_o(:,:,:)  ! v del paso anterior
    real(dp), allocatable, save :: pr_r(:,:,:), pr_th(:,:,:), pr_z(:,:,:)  ! iterado previo (relajacion)
    real(dp), allocatable, save :: eps(:,:,:), rhom(:,:,:), mum(:,:,:), mul(:,:,:)
    ! densidad de FLOTACION (peso) con el Boussinesq del liquido: va en la
    ! fuerza de cara, no como fuente de celda (fuerza balanceada)
    real(dp), allocatable, save :: rhob(:,:,:)
    ! densidad INERCIAL de la mezcla: rho_m fuera del lecho; en el lecho la de
    ! las movilidades (lo que mueve la velocidad de mezcla es la fase movil;
    ! el liquido de un lecho con gas continuo lo sostiene el lecho)
    real(dp), allocatable, save :: rhoi(:,:,:)
    logical,  allocatable, save :: bedc(:,:,:)
    ! (Regimen de GOTAS con velocidad propia dentro de la mezcla — deriva
    ! relajada de Bug 15 + arrastre Kd con el gas —: PROBADO Y NEGATIVO el
    ! 12-oct-2026 (bath_fill 0.52 MPa y gas en la cota frente a 61 kPa sin el).
    ! El codigo, apagado por un parametro, se retiro en la auditoria (bajos):
    ! las gotas siguen a la mezcla con deslizamiento terminal; ver la historia
    ! de git (commit 9335d31) si se quiere reintentar.)
    real(dp), allocatable, save :: mass_o(:,:,:)                           ! masa fluida del paso anterior [kg]
    real(dp), allocatable, save :: Dr(:,:,:), Dth(:,:,:), Dz(:,:,:)        ! eps V / aP
    real(dp), allocatable, save :: Gr(:,:,:), Gth(:,:,:), Gz(:,:,:)        ! fuerza de celda (p + g) [N/m3]
    real(dp), allocatable, save :: drag(:,:,:)
    real(dp), allocatable, save :: p_lT(:,:,:), p_gT(:,:,:), a_in(:,:,:)
    logical,  allocatable, save :: fl(:,:,:)                               ! celda fluida del acople
    real(dp), save :: beta_b = 0.0_dp, T_amb_b = 0.0_dp
    ! referencia de la fuente de compresibilidad del paso (= sh%Tg_end del
    ! final del lazo SIMPLE del paso anterior), congelada durante el paso
    real(dp), allocatable, save :: Tg_ref(:,:,:)
    integer, save :: tgref_id = -huge(1)
    logical, save :: mix_inited = .false.   ! (M4-2) equilibrado de arranque hecho

contains

    !===========================================================================
    ! Una iteracion externa del modelo de mezcla (sustituye a
    ! multiphase_iteration con cfg%mixture_model)
    !===========================================================================
    subroutine mixture_iteration(liq, gas, liq_old, gas_old, sol, slag, sh, m, cfg, conv)
        type(phase_t), intent(inout)  :: liq, gas, liq_old, gas_old
        type(solid_t), intent(inout)  :: sol
        type(slag_t),  intent(in)     :: slag
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)      :: m
        type(config_t), intent(in)    :: cfg
        type(convergence_t), intent(inout) :: conv

        integer  :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: res_r, res_th, res_z, res_cont, res_el, res_eg, da_loc, da_glob
        real(dp) :: fl_loc, fl_glob, e_liq0

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call ensure_workspace(m)
        call alloc_state(m)

        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)
        call solid_exchange_halos(sol, m)
        call shared_exchange_halos(sh, m)
        ! liquido continuo: solo para k-eps (mod_turbulence) y diagnosticos
        call liquid_continuity_mask(liq, sol, m, ws_liq_cont)
        ws_liq_cont_valid = .true.
        ! deriva del liquido disperso (gotas: relajacion de particula hacia gas +
        ! sedimentacion; pelicula sobre el lecho: percolacion, F2.14)

        p_lT = liq%T; p_gT = gas%T; a_in = liq%alpha
        ! Fuente de compresibilidad contra la T del gas al FINAL del SIMPLE del
        ! paso anterior, no contra la T de inicio de paso: los operadores
        ! partidos de despues del SIMPLE (interfase con el solido) cambian la
        ! T del gas sin pasar por el Poisson, y el gas vuelve dentro del paso
        ! a su equilibrio con el liquido. Medida contra T_old, esa ida y vuelta
        ! era una EXPANSION neta cada paso (la contraccion nunca se veia):
        ! bombeo que integraba presion en filas de conductancia minima (lecho
        ! denso inundado de bed_flood: +35 K por paso, 45 -> 2000 kPa en 3 s;
        ! es el mecanismo por el que F2.13 saca el gas de poro del acople).
        if (tgref_id /= probe_current_step()) then
            tgref_id = probe_current_step()
            ! Estado sin Tg_end (arranque, o reinicio desde un snapshot del
            ! modelo de dos fluidos, que no tenia intercambio gas-liquido):
            ! las burbujas se equilibran con el liquido ANTES del primer
            ! Poisson y esa T es la referencia. Sin esto el primer paso apagaba
            ! de golpe el gas a temperatura de arco que traia el bano (B1 a
            ! 300 s: succion de -1.6 MPa en celdas de bano con 26 % de gas).
            ! Decision GLOBAL sobre celdas propias (auditoria, bajos): el
            ! all() local incluia halos y dos ranks podian discrepar -> unos
            ! entraban a los intercambios de halos colectivos y otros no
            ! (auditoria 4, M4-2) se equilibra en el PRIMER paso de la sesion
            ! salvo que reanude un snapshot escrito por la propia mezcla
            ! (atributo model_mixture); desde A3-3 todo snapshot trae Tg_end
            ! >= 0 y la deteccion por Tg_end ya no distinguia los modelos
            fl_loc = 1.0_dp
            if (mix_inited .or. sh%restart_mixture) fl_loc = 0.0_dp
            if (m%is_parallel) then
                call mpi_allreduce_min(fl_loc, fl_glob, m%topo)
            else
                fl_glob = fl_loc
            end if
            if (fl_glob > 0.5_dp) then
                ! energia que el gas cede al liquido en el equilibrio de
                ! arranque: la referencia del gas se reinicia (gas_old = gas)
                ! y esa perdida no quedaba en ningun libro -> columna propia
                ! (E_mix_init) que entra a la identidad del balance
                e_liq0 = liq_energy_local()
                call exchange_gas_liquid(liq, gas, m, cfg, full=.true.)
                call audit_add(AUD_MIX_INIT, liq_energy_local() - e_liq0)
                call phase_exchange_halos(liq, m)
                call phase_exchange_halos(gas, m)
                call update_properties(liq, gas, sh, m, cfg)
                gas_old%T = gas%T; liq_old%T = liq%T
                gas_old%rho = gas%rho; liq_old%rho = liq%rho
                sh%Tg_end = gas%T
            end if
            mix_inited = .true.
            where (sh%Tg_end > 0.0_dp)
                Tg_ref = sh%Tg_end
            elsewhere
                Tg_ref = gas_old%T
            end where
        end if
        beta_b = cfg%beta_expansion; T_amb_b = cfg%T_ref_boussinesq

        ! 1. propiedades de mezcla, v del paso anterior e iterado, deslizamiento
        call mixture_state(liq, gas, liq_old, gas_old, sol, slag, m)
        call mixture_drag(liq, gas, sol, m, cfg)
        call slip_speed(liq, gas, sol, m, cfg)

        ! 2. fuerzas de celda (presion + gravedad) con el p actual
        call cell_forces(sh%p, m, Gr, Gth, Gz)

        ! 3. momento de la mezcla (predictor)
        pr_r = vr; pr_th = vth; pr_z = vz
        call mixture_momentum('r',  liq, gas, sh, m, cfg, res_r)
        call mixture_momentum('th', liq, gas, sh, m, cfg, res_th)
        call mixture_momentum('z',  liq, gas, sh, m, cfg, res_z)
        ! (sub-relajacion LOCAL dentro de mixture_momentum)
        call cap_mixture(m)
        call mpi_exchange_halos_3d(vr,  m%topo)
        call mpi_exchange_halos_3d(vth, m%topo)
        call mpi_exchange_halos_3d(vz,  m%topo)

        ! 4. correccion de presion de volumen (flujos conservativos -> ws_mQ_*)
        call mixture_pressure(liq, gas, gas_old, sh, m, cfg, res_cont)
        ws_mix_valid = .true.
        ws_mix_id = probe_current_step()

        ! 5. transporte de alpha_l DENTRO de la iteracion (acople implicito)
        if (cfg%solve_multiphase) then
            call solve_volume_fraction(liq, gas, sol, slag%alpha_sl, liq_old%alpha, m, cfg)
            call phase_exchange_halos(liq, m)
            call phase_exchange_halos(gas, m)
        end if
        da_loc = maxval(abs(liq%alpha(istart:iend,jstart:jend,kstart:kend) &
                          - a_in(istart:iend,jstart:jend,kstart:kend)))
        if (m%is_parallel) then
            call mpi_allreduce_max(da_loc, da_glob, m%topo)
        else
            da_glob = da_loc
        end if
        conv%dalpha_pc = da_glob
        conv%n_pc = 1

        ! 6. velocidades de fase (energia, especies, k-eps, salida)
        call slip_speed(liq, gas, sol, m, cfg)
        call phase_velocities(liq, gas, m)
        ! topes CENTINELA que conservan el flujo de mezcla (auditoria, bajos:
        ! cap_liquid/cap_gas_velocity por separado rompian alpha_l u_l +
        ! alpha_g u_g = eps v)
        call cap_phases_mixture(liq, gas, m)
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)

        ! 7. energia (identica al modelo de dos fluidos: el liquido usa los
        !    flujos de masa del transporte de alpha, ws_Fr/ws_Fth/ws_Fz)
        if (cfg%solve_energy) then
            call solve_energy_3d(liq, liq_old%T, sh, m, cfg, liq%alpha, &
                                 gas%alpha, liq_old%alpha, sol%mdot, ws_Tsrc, &
                                 .false., res_el)
            call solve_energy_3d(gas, gas_old%T, sh, m, cfg, gas%alpha, &
                                 liq%alpha, gas%alpha, sol%mdot, ws_Tsrc, &
                                 .true., res_eg)
            ! Intercambio gas-liquido sobre las soluciones SIN relajar y luego
            ! la relajacion (auditoria 12-oct-2026, A18): aplicado despues de
            ! relajar, el punto fijo era X = E(alpha S + (1-alpha) X) y la
            ! transferencia q/alpha_T dependia del factor de relajacion
            call exchange_gas_liquid(liq, gas, m, cfg)
            call relax_field(liq%T, p_lT, cfg%alpha_T, m)
            call relax_field(gas%T, p_gT, cfg%alpha_T, m)
            call phase_exchange_halos(liq, m)
            call phase_exchange_halos(gas, m)
        else
            res_el = 0.0_dp; res_eg = 0.0_dp
        end if
        call update_properties(liq, gas, sh, m, cfg)

        sh%Tg_end = gas%T
        conv%res_ur = res_r; conv%res_uth = res_th; conv%res_uz = res_z
        conv%res_cont = res_cont
        conv%res_energy = max(res_el, res_eg)
    contains

        ! energia sensible del liquido en celdas propias [J] (la diferencia
        ! antes/despues del equilibrio de arranque; masa constante)
        function liq_energy_local() result(e)
            real(dp) :: e
            integer :: ii, jj, kk
            e = 0.0_dp
            do kk = kstart, kend
                do jj = jstart, jend
                    do ii = istart, iend
                        if (m%cell_type(ii,jj,kk) == 0) cycle
                        e = e + max(liq%alpha(ii,jj,kk), 0.0_dp) * liq%rho(ii,jj,kk) &
                              * liq%cp(ii,jj,kk) * liq%T(ii,jj,kk) * m%vol(ii,jj,kk)
                    end do
                end do
            end do
        end function liq_energy_local

    end subroutine mixture_iteration

    !---------------------------------------------------------------------------
    subroutine alloc_state(m)
        type(mesh_t), intent(in) :: m
        if (allocated(vr)) return
        allocate(vr(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(vth, vz, vr_o, vth_o, vz_o, pr_r, pr_th, pr_z, mold=vr)
        allocate(rhoi, mold=vr); rhoi = 0.0_dp
        allocate(eps, rhom, rhob, mum, mul, mass_o, Dr, Dth, Dz, Gr, Gth, Gz, drag, mold=vr)
        allocate(p_lT, p_gT, a_in, Tg_ref, mold=vr)
        allocate(fl(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(bedc, mold=fl); bedc = .false.
        vr = 0.0_dp; vth = 0.0_dp; vz = 0.0_dp
        vr_o = 0.0_dp; vth_o = 0.0_dp; vz_o = 0.0_dp
        pr_r = 0.0_dp; pr_th = 0.0_dp; pr_z = 0.0_dp
        eps = 0.0_dp; rhom = 0.0_dp; rhob = 0.0_dp; mum = 0.0_dp; mul = 0.0_dp; mass_o = 0.0_dp
        Dr = 0.0_dp; Dth = 0.0_dp; Dz = 0.0_dp; Gr = 0.0_dp; Gth = 0.0_dp; Gz = 0.0_dp
        drag = 0.0_dp; p_lT = 0.0_dp; p_gT = 0.0_dp; a_in = 0.0_dp
        fl = .false.
    end subroutine alloc_state

    !---------------------------------------------------------------------------
    ! Porosidad, densidad/viscosidad de mezcla, masa fluida del paso anterior
    ! y velocidades volumetricas (iterado y paso anterior) reconstruidas de las
    ! velocidades de fase: alpha_l u_l + alpha_g u_g = eps v exactamente para
    ! las velocidades que escribe phase_velocities. Arrays COMPLETOS (halos
    ! incluidos: todos los campos de entrada vienen intercambiados).
    !---------------------------------------------------------------------------
    subroutine mixture_state(liq, gas, liq_old, gas_old, sol, slag, m)
        type(phase_t), intent(in)  :: liq, gas, liq_old, gas_old
        type(solid_t), intent(in)  :: sol
        type(slag_t),  intent(in)  :: slag
        type(mesh_t), intent(in)   :: m
        integer  :: i, j, k
        real(dp) :: al, ag, e, eo
        logical  :: onbed

        do k = lbound(eps,3), ubound(eps,3)
            do j = lbound(eps,2), ubound(eps,2)
                do i = lbound(eps,1), ubound(eps,1)
                    eps(i,j,k) = 0.0_dp
                    fl(i,j,k) = .false.
                    rhom(i,j,k) = gas%rho(i,j,k); mum(i,j,k) = gas%mu_eff(i,j,k)
                    rhob(i,j,k) = gas%rho(i,j,k)
                    rhoi(i,j,k) = gas%rho(i,j,k)
                    mul(i,j,k) = gas%mu(i,j,k)
                    vr(i,j,k) = 0.0_dp; vth(i,j,k) = 0.0_dp; vz(i,j,k) = 0.0_dp
                    vr_o(i,j,k) = 0.0_dp; vth_o(i,j,k) = 0.0_dp; vz_o(i,j,k) = 0.0_dp
                    mass_o(i,j,k) = 0.0_dp
                    if (m%cell_type(i,j,k) == 0) cycle
                    e = max(0.0_dp, 1.0_dp - sol%alpha_s(i,j,k) - slag%alpha_sl(i,j,k))
                    eps(i,j,k) = e
                    if (e <= EPS_MIX) cycle
                    fl(i,j,k) = .true.
                    al = min(max(liq%alpha(i,j,k), 0.0_dp), e)
                    ag = e - al
                    rhom(i,j,k) = (al * liq%rho(i,j,k) + ag * gas%rho(i,j,k)) / e
                    rhob(i,j,k) = (al * liq%rho(i,j,k) * (1.0_dp - beta_b * (liq%T(i,j,k) - T_amb_b)) &
                                   + ag * gas%rho(i,j,k)) / e
                    rhoi(i,j,k) = rhom(i,j,k)
                    mum(i,j,k)  = (al * liq%mu_eff(i,j,k) + ag * gas%mu_eff(i,j,k)) / e
                    mul(i,j,k)  = (al * liq%mu(i,j,k) + ag * gas%mu(i,j,k)) / e
                    ! iterado: reconstruccion con las fracciones de fase guardadas
                    al = max(liq%alpha(i,j,k), 0.0_dp); ag = max(gas%alpha(i,j,k), 0.0_dp)
                    if (al + ag > EPS_MIX) then
                        vr(i,j,k)  = (al * liq%ur(i,j,k)  + ag * gas%ur(i,j,k))  / (al + ag)
                        vth(i,j,k) = (al * liq%uth(i,j,k) + ag * gas%uth(i,j,k)) / (al + ag)
                        vz(i,j,k)  = (al * liq%uz(i,j,k)  + ag * gas%uz(i,j,k))  / (al + ag)
                    end if
                    ! paso anterior (ancla temporal)
                    al = max(liq_old%alpha(i,j,k), 0.0_dp); ag = max(gas_old%alpha(i,j,k), 0.0_dp)
                    eo = al + ag
                    ! masa del PASO ANTERIOR con las densidades del paso
                    ! anterior (auditoria, bajos: mezclaba alpha^n con rho^k)
                    mass_o(i,j,k) = (al * liq_old%rho(i,j,k) + ag * gas_old%rho(i,j,k)) * m%vol(i,j,k)
                    if (eo > EPS_MIX) then
                        vr_o(i,j,k)  = (al * liq_old%ur(i,j,k)  + ag * gas_old%ur(i,j,k))  / eo
                        vth_o(i,j,k) = (al * liq_old%uth(i,j,k) + ag * gas_old%uth(i,j,k)) / eo
                        vz_o(i,j,k)  = (al * liq_old%uz(i,j,k)  + ag * gas_old%uz(i,j,k))  / eo
                    end if
                end do
            end do
        end do
        ! halos de la velocidad de mezcla reconstruida (auditoria, bajos: el
        ! primer predictor leia los de la iteracion/paso anterior)
        call mpi_exchange_halos_3d(vr,  m%topo)
        call mpi_exchange_halos_3d(vth, m%topo)
        call mpi_exchange_halos_3d(vz,  m%topo)
    end subroutine mixture_state

    !---------------------------------------------------------------------------
    ! Rapidez de deslizamiento de la celda (liquido hacia abajo respecto del
    ! gas) segun el regimen, con la MISMA clasificacion que el modelo de dos
    ! fluidos (F2.14: chatarra propia o lecho debajo = goteo de Ergun):
    !   lecho:     percolacion de Ergun (percolation_velocity, Bug 17)
    !   sin lecho: mezcla logistica AIAD (A_AIAD, ALPHA_AIAD_LIM) entre gota
    !              terminal (settling_velocity, poco liquido) y burbuja de
    !              Harmathy 1.53 (sigma g drho / rho_l^2)^(1/4) (bano)
    ! -> ws_mW (halos intercambiados)
    !---------------------------------------------------------------------------
    subroutine slip_speed(liq, gas, sol, m, cfg)
        type(phase_t), intent(in)  :: liq, gas
        type(solid_t), intent(in)  :: sol
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: al, ut, ub, xb, fd, lam_l, lam_g, sv
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        ws_mW = 0.0_dp; ws_mKl = 0.0_dp; ws_mKg = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (eps(i,j,k) <= EPS_MIX) cycle
                    al = max(liq%alpha(i,j,k), 0.0_dp)
                    ub = 1.53_dp * (SIGMA_STEEL * GRAVITY * max(liq%rho(i,j,k) - gas%rho(i,j,k), 0.0_dp) &
                                    / liq%rho(i,j,k)**2)**0.25_dp
                    if (in_bed(sol%alpha_s(i,j,k))) then
                        ! Darcy bifasico: eps s (1-s) W = lambda_l lambda_g/lambda_T drho g,
                        ! acotado por la burbuja de Harmathy: el gas residual de
                        ! un poro casi saturado no percola con la movilidad de
                        ! Ergun del gas solo (que no ve que esta rodeado de
                        ! liquido) sino como burbuja (bath_fill: 6-12 m/s en el
                        ! lecho saturado y el liquido drenandose a 9 cm/s).
                        call bed_mobilities(liq, gas, sol, cfg, i, j, k, lam_l, lam_g)
                        sv = min(1.0_dp, al / eps(i,j,k))
                        call bed_ergun(liq, gas, sol, cfg, i, j, k, ws_mKl(i,j,k), ws_mKg(i,j,k))
                        if (lam_l + lam_g > 0.0_dp) ws_mW(i,j,k) = min(ub, &
                            max(liq%rho(i,j,k) - gas%rho(i,j,k), 0.0_dp) * GRAVITY &
                            * lam_l * lam_g / (lam_l + lam_g) &
                            / (eps(i,j,k) * max(sv * (1.0_dp - sv), 1.0e-12_dp)))
                    else if (m%cell_type(i,j,k-1) /= 0 .and. in_bed(sol%alpha_s(i,j,k-1))) then
                        ! celda sin lecho propio que DESCANSA sobre el lecho: el
                        ! liquido gotea a la velocidad de percolacion del lecho de
                        ! abajo (F2.14), no cae como gota a 17-50 m/s
                        ws_mW(i,j,k) = percolation_velocity(al, sol%alpha_s(i,j,k-1), liq%rho(i,j,k), &
                            gas%rho(i,j,k), liq%mu(i,j,k), cfg%d_particle)
                    else
                        ut = 0.0_dp
                        if (cfg%d_droplet > 0.0_dp) ut = settling_velocity(cfg%d_droplet, &
                            liq%rho(i,j,k), gas%rho(i,j,k), gas%mu(i,j,k))
                        xb = A_AIAD * (al - ALPHA_AIAD_LIM)
                        fd = 1.0_dp / (1.0_dp + exp(min(max(xb, -60.0_dp), 60.0_dp)))
                        ws_mW(i,j,k) = fd * ut + (1.0_dp - fd) * ub
                    end if
                end do
            end do
        end do
        call mpi_exchange_halos_3d(ws_mW, m%topo)
        call mpi_exchange_halos_3d(ws_mKl, m%topo)
        call mpi_exchange_halos_3d(ws_mKg, m%topo)
    end subroutine slip_speed

    !---------------------------------------------------------------------------
    ! Movilidades de Darcy de las dos fases en una celda del LECHO
    ! (alpha_s >= 1e-2): el balance de cada fase sin inercia es
    !     K_q u_q = alpha_q (-grad p + rho_q g),  K_q = Ergun de la fase
    ! (Bug 21: ergun_coefficients con rho_q, mu_q, |u_q|), de modo que el flujo
    ! superficial es j_q = lambda_q (-grad p + rho_q g), lambda_q = alpha_q^2/K_q.
    !---------------------------------------------------------------------------
    subroutine bed_ergun(liq, gas, sol, cfg, i, j, k, Kl, Kg)
        type(phase_t), intent(in)  :: liq, gas
        type(solid_t), intent(in)  :: sol
        type(config_t), intent(in) :: cfg
        integer, intent(in)        :: i, j, k
        real(dp), intent(out)      :: Kl, Kg
        real(dp) :: A, B, ul, ug, ase
        ul = sqrt(liq%ur(i,j,k)**2 + liq%uth(i,j,k)**2 + liq%uz(i,j,k)**2)
        ug = sqrt(gas%ur(i,j,k)**2 + gas%uth(i,j,k)**2 + gas%uz(i,j,k)**2)
        ase = sol%alpha_s(i,j,k)
        if (cfg%mix_eps_perm_min > 0.0_dp) ase = min(ase, 1.0_dp - cfg%mix_eps_perm_min)
        call ergun_coefficients(ase, liq%rho(i,j,k), liq%mu(i,j,k), cfg%d_particle, A, B)
        Kl = max(A + B * ul, SMALL)
        call ergun_coefficients(ase, gas%rho(i,j,k), gas%mu(i,j,k), cfg%d_particle, A, B)
        Kg = max(A + B * ug, SMALL)
    end subroutine bed_ergun

    subroutine bed_mobilities(liq, gas, sol, cfg, i, j, k, lam_l, lam_g)
        type(phase_t), intent(in)  :: liq, gas
        type(solid_t), intent(in)  :: sol
        type(config_t), intent(in) :: cfg
        integer, intent(in)        :: i, j, k
        real(dp), intent(out)      :: lam_l, lam_g
        real(dp) :: al, ag, Kl, Kg
        al = min(max(liq%alpha(i,j,k), 0.0_dp), eps(i,j,k))
        ag = eps(i,j,k) - al
        call bed_ergun(liq, gas, sol, cfg, i, j, k, Kl, Kg)
        lam_l = al * al / Kl
        lam_g = ag * ag / Kg
    end subroutine bed_mobilities

    pure logical function in_bed(as)
        real(dp), intent(in) :: as
        in_bed = (as >= 1.0e-2_dp)
    end function in_bed

    !---------------------------------------------------------------------------
    ! Arrastre de la mezcla y densidad de FLOTACION.
    !
    ! LECHO (alpha_s >= 1e-2): limite de Darcy BIFASICO (Buckley-Leverett con
    ! gravedad). El flujo total es j = lambda_T (-grad p + rho_lam g), con
    ! lambda_T = lambda_l + lambda_g y rho_lam = (lambda_l rho_l + lambda_g
    ! rho_g)/lambda_T; el liquido se separa con el deslizamiento
    ! lambda_l lambda_g/lambda_T (rho_l - rho_g) g (slip_speed). En el momento
    ! de la mezcla (eps rho_m Dv/Dt = eps(-grad p + rho g) - K v, j = eps v)
    ! eso es K = eps^2/lambda_T y rho = rho_lam. El modelo HOMOGENEO (Ergun de
    ! la mezcla con rho_m y peso rho_m g) trataba gas y acero como si se
    ! movieran juntos contra el lecho: la columna con mas gas "flotaba" como
    ! un airlift y la mezcla daba vueltas por el lecho saturado (bath_fill:
    ! 0.07 m3/s bajando por la pared y entrando por el fondo, p a 300-600 kPa
    ! en la celda de la esquina). Con movilidades el gas, 1e3-1e4 veces mas
    ! movil que el acero, sube por su cuenta y el peso del liquido lo carga
    ! el lecho mientras percola.
    !
    ! FUERA DEL LECHO: Ergun de mezcla (rho_m, viscosidad molecular, |v|) en
    ! celdas con chatarra residual; peso rho_b (mezcla con Boussinesq).
    !---------------------------------------------------------------------------
    subroutine mixture_drag(liq, gas, sol, m, cfg)
        type(phase_t), intent(in)  :: liq, gas
        type(solid_t), intent(in)  :: sol
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: A, B, vmag, lam_l, lam_g, lam_t, rl
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        drag = 0.0_dp; bedc = .false.
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (.not. fl(i,j,k)) cycle
                    if (sol%alpha_s(i,j,k) < 1.0e-6_dp) cycle
                    if (in_bed(sol%alpha_s(i,j,k))) then
                        call bed_mobilities(liq, gas, sol, cfg, i, j, k, lam_l, lam_g)
                        lam_t = lam_l + lam_g
                        if (lam_t <= 0.0_dp) cycle
                        drag(i,j,k) = eps(i,j,k)**2 / lam_t
                        rl = liq%rho(i,j,k) * (1.0_dp - beta_b * (liq%T(i,j,k) - T_amb_b))
                        rhob(i,j,k) = (lam_l * rl + lam_g * gas%rho(i,j,k)) / lam_t
                        rhoi(i,j,k) = (lam_l * liq%rho(i,j,k) + lam_g * gas%rho(i,j,k)) / lam_t
                        bedc(i,j,k) = .true.
                    else
                        call ergun_coefficients(sol%alpha_s(i,j,k), rhom(i,j,k), mul(i,j,k), &
                                                cfg%d_particle, A, B)
                        vmag = sqrt(vr(i,j,k)**2 + vth(i,j,k)**2 + vz(i,j,k)**2)
                        drag(i,j,k) = A + B * vmag
                    end if
                end do
            end do
        end do
        call mpi_exchange_halos_3d(rhob, m%topo)
        call mpi_exchange_halos_3d(rhoi, m%topo)
    end subroutine mixture_drag

    !---------------------------------------------------------------------------
    ! Fuerza de CELDA por unidad de volumen fluido en cada direccion: media de
    ! las fuerzas de las caras fluidas (presion y, en z, gravedad con la
    ! densidad de cara). Celdas propias + halos.
    !---------------------------------------------------------------------------
    subroutine cell_forces(pf, m, fr, fth, fz)
        real(dp), intent(in)  :: pf(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        real(dp), intent(out) :: fr(-1:,-1:,-1:), fth(-1:,-1:,-1:), fz(-1:,-1:,-1:)
        integer  :: i, j, k, n, istart, iend, jstart, jend, kstart, kend
        real(dp) :: s
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        fr = 0.0_dp; fth = 0.0_dp; fz = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (.not. fl(i,j,k)) cycle
                    s = 0.0_dp; n = 0
                    if (fl(i-1,j,k)) then; s = s + face_force(pf, m, i-1, j, k, 1); n = n + 1; end if
                    if (fl(i+1,j,k)) then; s = s + face_force(pf, m, i, j, k, 1);   n = n + 1; end if
                    if (n > 0) fr(i,j,k) = s / real(n, dp)
                    s = 0.0_dp; n = 0
                    if (fl(i,j-1,k)) then; s = s + face_force(pf, m, i, j-1, k, 2); n = n + 1; end if
                    if (fl(i,j+1,k)) then; s = s + face_force(pf, m, i, j, k, 2);   n = n + 1; end if
                    if (n > 0) fth(i,j,k) = s / real(n, dp)
                    s = 0.0_dp; n = 0
                    if (fl(i,j,k-1)) then; s = s + face_force(pf, m, i, j, k-1, 3); n = n + 1; end if
                    if (fl(i,j,k+1)) then; s = s + face_force(pf, m, i, j, k, 3);   n = n + 1; end if
                    if (n > 0) fz(i,j,k) = s / real(n, dp)
                end do
            end do
        end do
        call mpi_exchange_halos_3d(fr,  m%topo)
        call mpi_exchange_halos_3d(fth, m%topo)
        call mpi_exchange_halos_3d(fz,  m%topo)
    end subroutine cell_forces

    ! Fuerza de la cara + de la celda (i,j,k) en la direccion dir [N/m3]:
    ! -(p_N - p_P)/delta (- rho_f g en z)
    function face_force(pf, m, i, j, k, dir) result(f)
        real(dp), intent(in) :: pf(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer, intent(in)  :: i, j, k, dir
        real(dp) :: f
        select case (dir)
        case (1)
            f = -(pf(i+1,j,k) - pf(i,j,k)) / (m%r(i+1) - m%r(i))
        case (2)
            f = -(pf(i,j+1,k) - pf(i,j,k)) / (m%r(i) * (m%theta(j+1) - m%theta(j)))
        case default
            f = -(pf(i,j,k+1) - pf(i,j,k)) / (m%z(k+1) - m%z(k))
            f = f - 0.5_dp * (rhob(i,j,k) + rhob(i,j,k+1)) * GRAVITY
        end select
    end function face_force

    pure function hface(a, b) result(h)
        real(dp), intent(in) :: a, b
        real(dp) :: h
        h = 0.0_dp
        if (a > 0.0_dp .and. b > 0.0_dp) h = 2.0_dp * a * b / (a + b)
    end function hface

    !---------------------------------------------------------------------------
    ! Momento de la mezcla, una componente. Forma ACOTADA de Patankar con la
    ! masa fluida del paso anterior en el transitorio (la masa que llega entra
    ! por a_nb de entrada; como el liquido de dos fluidos, sep-2026) y flujo
    ! de masa de cara = rho_m del DADOR x flujo volumetrico (el conservativo
    ! de la iteracion anterior del paso si existe; si no, interpolado).
    !---------------------------------------------------------------------------
    subroutine mixture_momentum(comp, liq, gas, sh, m, cfg, residual)
        character(len=*), intent(in) :: comp
        type(phase_t), intent(in)    :: liq, gas
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(out)        :: residual

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: vol, e, Dw, De, Ds, Dn, Db, Dt, Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: mt, src, apx, rho_e
        logical  :: useQ, at_rmin, at_rmax, at_zmin, at_zmax
        real(dp), allocatable :: vel(:,:,:)

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)
        useQ = ws_mix_valid .and. (ws_mix_id == probe_current_step())
        allocate(vel, mold=vr)
        select case (comp)
        case ('r');  vel = vr
        case ('th'); vel = vth
        case default; vel = vz
        end select

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (.not. fl(i,j,k)) then
                        aP(i,j,k) = 1.0_dp; Su(i,j,k) = 0.0_dp
                        cycle
                    end if
                    vol = m%vol(i,j,k); e = eps(i,j,k)

                    ! difusion viscosa (eps de cara armonica: nula hacia solido)
                    Dw = 0.0_dp; De = 0.0_dp; Ds = 0.0_dp; Dn = 0.0_dp; Db = 0.0_dp; Dt = 0.0_dp
                    if (fl(i-1,j,k)) Dw = hface(e, eps(i-1,j,k)) * hface(mum(i,j,k), mum(i-1,j,k)) &
                                          * m%Ar(i-1,j,k) / (m%r(i) - m%r(i-1))
                    if (fl(i+1,j,k)) De = hface(e, eps(i+1,j,k)) * hface(mum(i,j,k), mum(i+1,j,k)) &
                                          * m%Ar(i,j,k) / (m%r(i+1) - m%r(i))
                    if (fl(i,j-1,k)) Ds = hface(e, eps(i,j-1,k)) * hface(mum(i,j,k), mum(i,j-1,k)) &
                                          * m%Ath(i,j,k) / (m%r(i) * (m%theta(j) - m%theta(j-1)))
                    if (fl(i,j+1,k)) Dn = hface(e, eps(i,j+1,k)) * hface(mum(i,j,k), mum(i,j+1,k)) &
                                          * m%Ath(i,j,k) / (m%r(i) * (m%theta(j+1) - m%theta(j)))
                    if (fl(i,j,k-1)) Db = hface(e, eps(i,j,k-1)) * hface(mum(i,j,k), mum(i,j,k-1)) &
                                          * m%Az(i,j,k-1) / (m%z(k) - m%z(k-1))
                    if (fl(i,j,k+1)) Dt = hface(e, eps(i,j,k+1)) * hface(mum(i,j,k), mum(i,j,k+1)) &
                                          * m%Az(i,j,k) / (m%z(k+1) - m%z(k))

                    ! flujos de masa de cara (orientados +)
                    Fw = mflux(i-1, j, k, 1); Fe = mflux(i, j, k, 1)
                    Fs = mflux(i, j-1, k, 2); Fn = mflux(i, j, k, 2)
                    Fb = mflux(i, j, k-1, 3); Ft = mflux(i, j, k, 3)

                    aW(i,j,k) = Dw + max( Fw, 0.0_dp)
                    aE(i,j,k) = De + max(-Fe, 0.0_dp)
                    aS(i,j,k) = Ds + max( Fs, 0.0_dp)
                    aN(i,j,k) = Dn + max(-Fn, 0.0_dp)
                    aB(i,j,k) = Db + max( Fb, 0.0_dp)
                    aT(i,j,k) = Dt + max(-Ft, 0.0_dp)

                    ! transitorio con la masa del paso anterior (piso: celda
                    ! recien abierta por la fusion)
                    rho_e = e * rhoi(i,j,k)
                    if (bedc(i,j,k)) then
                        mt = rho_e * vol / cfg%dt
                    else
                        mt = max(mass_o(i,j,k), 1.0e-3_dp * rho_e * vol) / cfg%dt
                    end if
                    apx = 0.0_dp
                    select case (comp)
                    case ('r')
                        src = e * Gr(i,j,k) + rho_e * vth(i,j,k)**2 / m%r(i) + sh%F_lorentz_r(i,j,k)
                        Su(i,j,k) = mt * vr_o(i,j,k) + src * vol
                    case ('th')
                        apx = rho_e * max(vr(i,j,k), 0.0_dp) / m%r(i) * vol
                        src = e * Gth(i,j,k) - rho_e * min(vr(i,j,k), 0.0_dp) * vth(i,j,k) / m%r(i) &
                              + sh%F_lorentz_th(i,j,k)
                        Su(i,j,k) = mt * vth_o(i,j,k) + src * vol
                    case default
                        ! gravedad (con el Boussinesq del liquido, rhob) dentro
                        ! de Gz: fuerza de cara balanceada. Como fuente de celda
                        ! el Boussinesq rompia el equilibrio discreto de la
                        ! superficie (bath_test: 18.6 % del peso del bano sin
                        ! contrapartida en la cara -> modo par-impar del gas)
                        src = e * Gz(i,j,k) + sh%S_arc_mom(i,j,k) + sh%F_lorentz_z(i,j,k)
                        Su(i,j,k) = mt * vz_o(i,j,k) + src * vol
                    end select
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) + aB(i,j,k) + aT(i,j,k) &
                               + mt + drag(i,j,k) * vol + apx
                end do
            end do
        end do

        call apply_momentum_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, &
                               merge('ur ', merge('uth', 'uz ', comp == 'th'), comp == 'r'))
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, vel, m)
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, vel, m, cfg%max_inner_mom)

        ! Sub-relajacion LOCAL contra el iterado anterior: alpha_eff = alpha_u
        ! + (1 - alpha_u) f, f = fraccion de aP que es arrastre de Ergun. La
        ! relajacion existe para la no linealidad de la conveccion; en una
        ! celda dominada por el arrastre (Darcy) es pura MEMORIA: el 70 % de
        ! la velocidad del iterado anterior entraba en el flujo de Rhie-Chow
        ! v_f y el corrector, con d = eps V/aP minusculo, no podia borrarlo.
        ! El flujo del lecho quedaba dictado por esa memoria y no por Darcy
        ! (bath_fill: 0.27 m3/s bajando por la pared hacia el lecho saturado
        ! con la fuerza neta hacia ARRIBA, p a 200-470 kPa en la esquina).
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (.not. fl(i,j,k)) cycle
                    rho_e = cfg%alpha_u + (1.0_dp - cfg%alpha_u) &
                            * min(1.0_dp, drag(i,j,k) * m%vol(i,j,k) / max(aP(i,j,k), SMALL))
                    select case (comp)
                    case ('r');  vel(i,j,k) = rho_e * vel(i,j,k) + (1.0_dp - rho_e) * pr_r(i,j,k)
                    case ('th'); vel(i,j,k) = rho_e * vel(i,j,k) + (1.0_dp - rho_e) * pr_th(i,j,k)
                    case default; vel(i,j,k) = rho_e * vel(i,j,k) + (1.0_dp - rho_e) * pr_z(i,j,k)
                    end select
                end do
            end do
        end do

        ! d = eps V/aP; en las filas forzadas por la BC (eje: u_r = 0) el aP
        ! de relleno 1.0 daria d = eps V: se usa el de la componente theta
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (.not. fl(i,j,k)) then
                        vel(i,j,k) = 0.0_dp
                        select case (comp)
                        case ('r');  Dr(i,j,k) = 0.0_dp
                        case ('th'); Dth(i,j,k) = 0.0_dp
                        case default; Dz(i,j,k) = 0.0_dp
                        end select
                        cycle
                    end if
                    select case (comp)
                    case ('r');  Dr(i,j,k)  = eps(i,j,k) * m%vol(i,j,k) / aP(i,j,k)
                    case ('th'); Dth(i,j,k) = eps(i,j,k) * m%vol(i,j,k) / aP(i,j,k)
                    case default; Dz(i,j,k) = eps(i,j,k) * m%vol(i,j,k) / aP(i,j,k)
                    end select
                end do
            end do
        end do
        select case (comp)
        case ('r')
            vr = vel
        case ('th')
            vth = vel
            ! (la componente r se resolvio antes: corregir su d del eje)
            if (at_rmin) Dr(istart,:,:) = Dth(istart,:,:)
            call mpi_exchange_halos_3d(Dr,  m%topo)
            call mpi_exchange_halos_3d(Dth, m%topo)
        case default
            vz = vel
            call mpi_exchange_halos_3d(Dz, m%topo)
        end select
        deallocate(vel)

    contains

        ! Flujo de masa [kg/s] por la cara + de (ii,jj,kk) en dir
        function mflux(ii, jj, kk, dir) result(F)
            integer, intent(in) :: ii, jj, kk, dir
            real(dp) :: F, Q
            integer :: in, jn, kn
            F = 0.0_dp
            in = ii; jn = jj; kn = kk
            select case (dir)
            case (1); in = ii + 1
            case (2); jn = jj + 1
            case default; kn = kk + 1
            end select
            if (.not. (fl(ii,jj,kk) .and. fl(in,jn,kn))) return
            if (useQ) then
                select case (dir)
                case (1); Q = ws_mQ_r(ii,jj,kk)
                case (2); Q = ws_mQ_th(ii,jj,kk)
                case default; Q = ws_mQ_z(ii,jj,kk)
                end select
            else
                select case (dir)
                case (1); Q = 0.5_dp * (eps(ii,jj,kk)*vr(ii,jj,kk) + eps(in,jn,kn)*vr(in,jn,kn)) * m%Ar(ii,jj,kk)
                case (2); Q = 0.5_dp * (eps(ii,jj,kk)*vth(ii,jj,kk) + eps(in,jn,kn)*vth(in,jn,kn)) * m%Ath(ii,jj,kk)
                case default; Q = 0.5_dp * (eps(ii,jj,kk)*vz(ii,jj,kk) + eps(in,jn,kn)*vz(in,jn,kn)) * m%Az(ii,jj,kk)
                end select
            end if
            if (Q >= 0.0_dp) then
                F = rhoi(ii,jj,kk) * Q
            else
                F = rhoi(in,jn,kn) * Q
            end if
        end function mflux

    end subroutine mixture_momentum

    !---------------------------------------------------------------------------
    ! Centinela de la velocidad de mezcla (U_GAS_MAX, preservando direccion):
    ! si se activa, el acople se rompio (no es una cota operativa)
    !---------------------------------------------------------------------------
    subroutine cap_mixture(m)
        type(mesh_t), intent(in) :: m
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: vm, f
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    vm = sqrt(vr(i,j,k)**2 + vth(i,j,k)**2 + vz(i,j,k)**2)
                    if (vm > U_GAS_MAX) then
                        f = U_GAS_MAX / vm
                        vr(i,j,k) = vr(i,j,k) * f; vth(i,j,k) = vth(i,j,k) * f
                        vz(i,j,k) = vz(i,j,k) * f
                    end if
                end do
            end do
        end do
    end subroutine cap_mixture

    !---------------------------------------------------------------------------
    ! Correccion de presion de VOLUMEN de la mezcla:
    !   coeficientes  a_f = eps_f D_f A / delta     (eps_f armonica)
    !   flujo         Q*  = eps_f A [ v_f + D_f (G_f - (G_P + G_N)/2) ]
    !   diagonal      + (alpha_g/P0 + alpha_l/(rho_l c^2)) V/dt  (acustica)
    !   fuente        - compresibilidad del gas ideal (acotada, COMP_SRC_CAP)
    ! Exporta Q = Q* + a (pp_P - pp_N) a ws_mQ_* (caras +, halos), corrige v
    ! con el mismo operador de fuerza de celda y actualiza p.
    !---------------------------------------------------------------------------
    subroutine mixture_pressure(liq, gas, gas_old, sh, m, cfg, residual)
        type(phase_t), intent(in)     :: liq, gas, gas_old
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)      :: m
        type(config_t), intent(in)    :: cfg
        real(dp), intent(out)         :: residual

        integer  :: i, j, k, n_it, nnb, istart, iend, jstart, jend, kstart, kend
        real(dp) :: q, a, flux_ref, sum_su, tmp, src, cap, ag, al, cg_res, psum, dvol, dcl
        real(dp), allocatable :: Qs_r(:,:,:), Qs_th(:,:,:), Qs_z(:,:,:)
        real(dp), allocatable :: gadv(:,:,:)
        real(dp), allocatable :: ac_r(:,:,:), ac_th(:,:,:), ac_z(:,:,:)
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)
        allocate(Qs_r, Qs_th, Qs_z, ac_r, ac_th, ac_z, mold=vr)
        allocate(gadv, mold=vr); gadv = 0.0_dp
        Qs_r = 0.0_dp; Qs_th = 0.0_dp; Qs_z = 0.0_dp
        ac_r = 0.0_dp; ac_th = 0.0_dp; ac_z = 0.0_dp

        ! fuerzas de celda con el p de ESTE momento (no ha cambiado)
        call cell_forces(sh%p, m, Gr, Gth, Gz)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp
        sh%pp = 0.0_dp
        flux_ref = 0.0_dp

        ! caras + de cada celda propia (y las - por simetria de la matriz)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (.not. fl(i,j,k)) cycle
                    ! oeste / este
                    if (fl(i-1,j,k)) then
                        call face_rc(i-1, j, k, 1, q, a)
                        aW(i,j,k) = a; Su(i,j,k) = Su(i,j,k) + q; flux_ref = flux_ref + abs(q)
                        call gadv_add(i, j, k, i-1, j, k, q)
                    end if
                    if (fl(i+1,j,k)) then
                        call face_rc(i, j, k, 1, q, a)
                        aE(i,j,k) = a; Su(i,j,k) = Su(i,j,k) - q; flux_ref = flux_ref + abs(q)
                        call gadv_add(i, j, k, i+1, j, k, -q)
                        Qs_r(i,j,k) = q; ac_r(i,j,k) = a
                    end if
                    if (fl(i,j-1,k)) then
                        call face_rc(i, j-1, k, 2, q, a)
                        aS(i,j,k) = a; Su(i,j,k) = Su(i,j,k) + q; flux_ref = flux_ref + abs(q)
                        call gadv_add(i, j, k, i, j-1, k, q)
                    end if
                    if (fl(i,j+1,k)) then
                        call face_rc(i, j, k, 2, q, a)
                        aN(i,j,k) = a; Su(i,j,k) = Su(i,j,k) - q; flux_ref = flux_ref + abs(q)
                        call gadv_add(i, j, k, i, j+1, k, -q)
                        Qs_th(i,j,k) = q; ac_th(i,j,k) = a
                    end if
                    if (fl(i,j,k-1)) then
                        call face_rc(i, j, k-1, 3, q, a)
                        aB(i,j,k) = a; Su(i,j,k) = Su(i,j,k) + q; flux_ref = flux_ref + abs(q)
                        call gadv_add(i, j, k, i, j, k-1, q)
                    end if
                    if (fl(i,j,k+1)) then
                        call face_rc(i, j, k, 3, q, a)
                        aT(i,j,k) = a; Su(i,j,k) = Su(i,j,k) - q; flux_ref = flux_ref + abs(q)
                        call gadv_add(i, j, k, i, j, k+1, -q)
                        Qs_z(i,j,k) = q; ac_z(i,j,k) = a
                    end if
                end do
            end do
        end do

        ! diagonal, acustica y compresibilidad del gas
        ws_cc_new = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (.not. fl(i,j,k)) then
                        aW(i,j,k) = 0.0_dp; aE(i,j,k) = 0.0_dp; aS(i,j,k) = 0.0_dp
                        aN(i,j,k) = 0.0_dp; aB(i,j,k) = 0.0_dp; aT(i,j,k) = 0.0_dp
                        aP(i,j,k) = 1.0_dp; Su(i,j,k) = 0.0_dp
                        cycle
                    end if
                    ag = max(gas%alpha(i,j,k), 0.0_dp)
                    al = max(liq%alpha(i,j,k), 0.0_dp)
                    aP(i,j,k) = (aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) + aB(i,j,k) &
                                 + aT(i,j,k)) * (1.0_dp + PP_COMPLIANCE)
                    if (cfg%gas_compressibility) then
                        ! compliancia residual opcional (D2.4, default 0)
                        if (al > 0.0_dp) ag = max(ag, cfg%alpha_g_comp_min)
                        ! La MEZCLA sigue low-Mach (EOS rho(P0, T), diagonal
                        ! alpha_g/P0 como seudo-compresibilidad). Auditoria M25,
                        ! medido: con la compresion fisica (rho(P0 + p, T), su
                        ! fuente temporal y la advectiva) el baño en reposo de
                        ! bath_mix crece x10 por paso en la superficie libre y
                        ! llega a U_GAS_MAX en 5 pasos; con cualquiera de las dos
                        ! fuentes sola, igual. El gas es el complemento de la
                        ! mezcla (sin masa propia): el volumen que pierde al
                        ! comprimirse lo gana el liquido y nada lo devuelve. El
                        ! acople de dos fluidos (el de B1) si lleva la compresion.
                        aP(i,j,k) = aP(i,j,k) + ag / P0_THERMO * m%vol(i,j,k) / cfg%dt
                        ag = max(gas%alpha(i,j,k), 0.0_dp)
                        src = ag * m%vol(i,j,k) / cfg%dt * &
                              (gas%rho(i,j,k) - gas_eos(cfg%rho_gas, Tg_ref(i,j,k), &
                               0.0_dp)) / max(gas%rho(i,j,k), SMALL)
                        cap = COMP_SRC_CAP * ag * m%vol(i,j,k) / cfg%dt
                        ! demanda total con un solo tope y acarreo (M26; ver
                        ! mod_pressure_3d)
                        dvol = -src + gadv(i,j,k) &
                             + (sh%S_CO_src(i,j,k) + sh%S_CO2_src(i,j,k) + sh%S_O2_src(i,j,k)) &
                               * m%vol(i,j,k) / max(gas%rho(i,j,k), SMALL) &
                             + ws_cc(i,j,k) / cfg%dt
                        dcl = max(-cap, min(cap, dvol))
                        Su(i,j,k) = Su(i,j,k) + dcl
                        ws_cc_new(i,j,k) = sign(min(abs(dvol - dcl) * cfg%dt, &
                            ag * m%vol(i,j,k)), dvol - dcl)
                    end if
                    aP(i,j,k) = aP(i,j,k) + al * m%vol(i,j,k) / &
                                (liq%rho(i,j,k) * C_SOUND_LIQ**2 * cfg%dt)
                end do
            end do
        end do
        call apply_pressure_bc(aW, aE, aS, aN, aB, aT, aP, Su, m)

        sum_su = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (fl(i,j,k)) sum_su = sum_su + abs(Su(i,j,k))
                end do
            end do
        end do
        if (m%is_parallel) then
            call mpi_allreduce_sum(sum_su, tmp, m%topo);   sum_su = tmp
            call mpi_allreduce_sum(flux_ref, tmp, m%topo); flux_ref = tmp
        end if
        residual = sum_su / max(flux_ref, SMALL)

        call cg_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, sh%pp, m, &
                       cfg%max_inner_pres, SOR_TOL_PRESSURE, cg_res, n_it)
        if (cg_res /= cg_res) residual = cg_res

        ! flujos conservativos de cara (volumetricos)
        ws_mQ_r = 0.0_dp; ws_mQ_th = 0.0_dp; ws_mQ_z = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (.not. fl(i,j,k)) cycle
                    if (fl(i+1,j,k)) ws_mQ_r(i,j,k)  = Qs_r(i,j,k)  + ac_r(i,j,k)  * (sh%pp(i,j,k) - sh%pp(i+1,j,k))
                    if (fl(i,j+1,k)) ws_mQ_th(i,j,k) = Qs_th(i,j,k) + ac_th(i,j,k) * (sh%pp(i,j,k) - sh%pp(i,j+1,k))
                    if (fl(i,j,k+1)) ws_mQ_z(i,j,k)  = Qs_z(i,j,k)  + ac_z(i,j,k)  * (sh%pp(i,j,k) - sh%pp(i,j,k+1))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(ws_mQ_r,  m%topo)
        call mpi_exchange_halos_3d(ws_mQ_th, m%topo)
        call mpi_exchange_halos_3d(ws_mQ_z,  m%topo)

        ! Velocidad de CELDA reconstruida desde los flujos CONSERVATIVOS de sus
        ! caras (media de las velocidades normales de las dos caras de cada
        ! direccion; pared o solido = cara con velocidad 0), como el
        ! fvc::reconstruct de interFoam. El corrector clasico de celda
        ! (u_P += d_P * media de los gradientes de pp de sus caras) solo
        ! cancela la MITAD de un salto de fuerza concentrado en una cara: en la
        ! celda de gas sobre la superficie del bano (d 7000x el del liquido)
        ! cada cambio de alpha de la celda de abajo dejaba un medio golpe
        ! alternante en la velocidad de celda aunque los flujos de cara
        ! estuvieran balanceados (bath_fill: gas a 300 m/s en un paso, celda
        ! (3,1,7)). Esa velocidad entraba como ancla temporal del paso
        ! siguiente y a la energia del gas.
        call mpi_exchange_halos_3d(sh%pp, m%topo)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (.not. fl(i,j,k)) cycle
                    ! Auditoria M35: solo el EJE queda fuera (u_r lo fija su CC
                    ! de simetria). Junto a coraza, piso y techo la cara de pared
                    ! aporta velocidad normal 0 (fvel) y la reconstruccion vale
                    ! igual; antes esas celdas conservaban la velocidad del
                    ! predictor, nunca corregida
                    if (.not. (i == istart .and. at_rmin)) &
                        vr(i,j,k) = 0.5_dp * (fvel(ws_mQ_r(i-1,j,k), i-1, j, k, 1) &
                                            + fvel(ws_mQ_r(i,j,k),   i,   j, k, 1))
                    vth(i,j,k) = 0.5_dp * (fvel(ws_mQ_th(i,j-1,k), i, j-1, k, 2) &
                                         + fvel(ws_mQ_th(i,j,k),   i, j,   k, 2))
                    vz(i,j,k) = 0.5_dp * (fvel(ws_mQ_z(i,j,k-1), i, j, k-1, 3) &
                                        + fvel(ws_mQ_z(i,j,k),   i, j, k,   3))
                end do
            end do
        end do
        call cap_mixture(m)
        call mpi_exchange_halos_3d(vr,  m%topo)
        call mpi_exchange_halos_3d(vth, m%topo)
        call mpi_exchange_halos_3d(vz,  m%topo)

        sh%p = sh%p + cfg%alpha_p * sh%pp
        sh%p = max(-P_HYDRO_CAP, min(P_HYDRO_CAP, sh%p))
        ! celdas sin fluido: Neumann de pared (Bug 16)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (fl(i,j,k)) cycle
                    psum = 0.0_dp; nnb = 0
                    if (fl(i-1,j,k)) then; psum = psum + sh%p(i-1,j,k); nnb = nnb + 1; end if
                    if (fl(i+1,j,k)) then; psum = psum + sh%p(i+1,j,k); nnb = nnb + 1; end if
                    if (fl(i,j-1,k)) then; psum = psum + sh%p(i,j-1,k); nnb = nnb + 1; end if
                    if (fl(i,j+1,k)) then; psum = psum + sh%p(i,j+1,k); nnb = nnb + 1; end if
                    if (fl(i,j,k-1)) then; psum = psum + sh%p(i,j,k-1); nnb = nnb + 1; end if
                    if (fl(i,j,k+1)) then; psum = psum + sh%p(i,j,k+1); nnb = nnb + 1; end if
                    if (nnb > 0) then
                        sh%p(i,j,k) = psum / real(nnb, dp)
                    else
                        sh%p(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do
        call mpi_exchange_halos_3d(sh%p, m%topo)
        deallocate(Qs_r, Qs_th, Qs_z, ac_r, ac_th, ac_z, gadv)

    contains

        ! Termino ADVECTIVO de la compresibilidad del gas (auditoria A8): el gas
        ! que entra por una cara (fraccion de gas del dador por el flujo de
        ! mezcla) cambia de volumen al tomar la densidad de la celda:
        ! Q_g,in (rho_N - rho_P)/rho_P
        subroutine gadv_add(ii, jj, kk, in_, jn_, kn_, qin)
            integer, intent(in)  :: ii, jj, kk, in_, jn_, kn_
            real(dp), intent(in) :: qin
            real(dp) :: fg
            if (.not. cfg%gas_compressibility) return
            if (qin <= 0.0_dp) return
            if (eps(in_,jn_,kn_) <= EPS_MIX) return
            fg = max(gas%alpha(in_,jn_,kn_), 0.0_dp) / eps(in_,jn_,kn_)
            gadv(ii,jj,kk) = gadv(ii,jj,kk) + fg * qin * (gas%rho(in_,jn_,kn_) - gas%rho(ii,jj,kk)) &
                                                       / max(gas%rho(ii,jj,kk), SMALL)
        end subroutine gadv_add

        ! Velocidad normal intersticial de la cara + de (ii,jj,kk): Q/(eps_f A);
        ! 0 si la cara no es fluida (pared, solido)
        function fvel(qf, ii, jj, kk, dir) result(u)
            real(dp), intent(in) :: qf
            integer, intent(in)  :: ii, jj, kk, dir
            real(dp) :: u, ef, area
            integer  :: in, jn, kn
            u = 0.0_dp
            in = ii; jn = jj; kn = kk
            select case (dir)
            case (1); in = ii + 1; area = m%Ar(ii,jj,kk)
            case (2); jn = jj + 1; area = m%Ath(ii,jj,kk)
            case default; kn = kk + 1; area = m%Az(ii,jj,kk)
            end select
            if (.not. (fl(ii,jj,kk) .and. fl(in,jn,kn))) return
            ef = hface(eps(ii,jj,kk), eps(in,jn,kn))
            if (ef * area <= 0.0_dp) return
            u = qf / (ef * area)
        end function fvel

        ! Rhie-Chow de la cara + de (ii,jj,kk) en dir: Q* [m3/s] y coeficiente
        subroutine face_rc(ii, jj, kk, dir, qs, ac)
            integer, intent(in)   :: ii, jj, kk, dir
            real(dp), intent(out) :: qs, ac
            integer  :: in, jn, kn
            real(dp) :: ef, df, vf, area, dl
            in = ii; jn = jj; kn = kk
            select case (dir)
            case (1)
                in = ii + 1
                df = 0.5_dp * (Dr(ii,jj,kk) + Dr(in,jn,kn))
                vf = 0.5_dp * (vr(ii,jj,kk) + vr(in,jn,kn)) + df * (face_force(sh%p, m, ii, jj, kk, 1) &
                     - 0.5_dp * (Gr(ii,jj,kk) + Gr(in,jn,kn)))
                area = m%Ar(ii,jj,kk); dl = m%r(in) - m%r(ii)
            case (2)
                jn = jj + 1
                df = 0.5_dp * (Dth(ii,jj,kk) + Dth(in,jn,kn))
                vf = 0.5_dp * (vth(ii,jj,kk) + vth(in,jn,kn)) + df * (face_force(sh%p, m, ii, jj, kk, 2) &
                     - 0.5_dp * (Gth(ii,jj,kk) + Gth(in,jn,kn)))
                area = m%Ath(ii,jj,kk); dl = m%r(ii) * (m%theta(jn) - m%theta(jj))
            case default
                kn = kk + 1
                df = 0.5_dp * (Dz(ii,jj,kk) + Dz(in,jn,kn))
                vf = 0.5_dp * (vz(ii,jj,kk) + vz(in,jn,kn)) + df * (face_force(sh%p, m, ii, jj, kk, 3) &
                     - 0.5_dp * (Gz(ii,jj,kk) + Gz(in,jn,kn)))
                area = m%Az(ii,jj,kk); dl = m%z(kn) - m%z(kk)
            end select
            ef = hface(eps(ii,jj,kk), eps(in,jn,kn))
            qs = ef * vf * area
            ac = ef * df * area / dl
        end subroutine face_rc

    end subroutine mixture_pressure

    !---------------------------------------------------------------------------
    ! Intercambio de calor GAS-LIQUIDO en la celda (el modelo no tenia
    ! ninguno: solo solido-gas y solido-liquido). En el modelo de mezcla el gas
    ! de una celda rica en liquido (burbujas) o el liquido de una celda de gas
    ! (gotas) comparten celda y velocidad; sin intercambio, el gas del bano
    ! recibia su parte w_src del arco y de la radiacion, llegaba a 3000 K con
    ! el acero a 1850 K y su expansion hinchaba el bano (bath_fill: chorro de
    ! 19 m/s y -580 kPa debajo). Burbuja de diametro d_droplet, Nu = 2:
    ! h = 2 k_g/d, area 6 alpha_g/d, pesada por la logistica de burbuja de
    ! AIAD (alpha_g < ALPHA_AIAD_LIM). Paso partido EXACTO de dos
    ! nodos (relajacion exponencial hacia la temperatura de equilibrio,
    ! conservativo), tras los solves de energia de cada iteracion externa.
    ! Audit: AUD_IPH_GAS += Q (retirado del gas), AUD_IPH_LIQ -= Q, con
    ! semantica de ultima iteracion externa del paso (audit_step_delta).
    !---------------------------------------------------------------------------
    subroutine exchange_gas_liquid(liq, gas, m, cfg, full)
        type(phase_t), intent(inout) :: liq, gas
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        logical, intent(in), optional :: full   ! equilibrio completo (arranque)
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: al, ag, cg, cl, hA, f, q, qsum, d, xb, fdisp
        logical  :: feq
        real(dp), save :: qg_prev = 0.0_dp, ql_prev = 0.0_dp
        integer,  save :: qg_id = -huge(1), ql_id = -huge(1)
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        feq = .false.
        if (present(full)) feq = full
        d = cfg%d_droplet
        if (d <= 0.0_dp) d = 2.0e-3_dp
        qsum = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    al = liq%alpha(i,j,k); ag = gas%alpha(i,j,k)
                    if (al <= 1.0e-6_dp .or. ag <= 1.0e-6_dp) cycle
                    cg = ag * gas%rho(i,j,k) * gas%cp(i,j,k) * m%vol(i,j,k)
                    cl = al * liq%rho(i,j,k) * liq%cp(i,j,k) * m%vol(i,j,k)
                    ! solo BURBUJAS (logistica AIAD sobre alpha_g, Hoehne-Vallee):
                    ! el gas atrapado en el liquido. Gotas en el gas e interfase
                    ! resuelta quedan como en el modelo de dos fluidos (sin
                    ! intercambio): con el area de gota de la logistica, el gas
                    ! frio de bath_test sobre el bano (37 % de liquido, 3 % de
                    ! "gota") se calentaba de 300 a 1230 K en dos pasos
                    xb = A_AIAD * (ag - ALPHA_AIAD_LIM)
                    fdisp = 1.0_dp / (1.0_dp + exp(min(max(xb, -60.0_dp), 60.0_dp)))
                    if (fdisp < 1.0e-6_dp) cycle
                    hA = fdisp * 2.0_dp * gas%kth(i,j,k) / d * 6.0_dp * ag / d * m%vol(i,j,k)
                    f = 1.0_dp - exp(-cfg%dt * hA * (1.0_dp / cg + 1.0_dp / cl))
                    if (feq .and. fdisp > 0.5_dp) f = 1.0_dp
                    q = cg * cl / (cg + cl) * (gas%T(i,j,k) - liq%T(i,j,k)) * f
                    gas%T(i,j,k) = gas%T(i,j,k) - q / cg
                    liq%T(i,j,k) = liq%T(i,j,k) + q / cl
                    qsum = qsum + q
                end do
            end do
        end do
        call audit_step_delta(AUD_IPH_GAS,  qsum, qg_prev, qg_id)
        call audit_step_delta(AUD_IPH_LIQ, -qsum, ql_prev, ql_id)
    end subroutine exchange_gas_liquid

    !---------------------------------------------------------------------------
    ! Velocidades de fase desde la mezcla: u_l = v + (1-s) u_r,
    ! u_g = v - s u_r, u_r = (0, 0, -W) (alpha_l u_l + alpha_g u_g = eps v
    ! exacto). Celdas sin fluido: cero.
    !---------------------------------------------------------------------------
    subroutine phase_velocities(liq, gas, m)
        type(phase_t), intent(inout) :: liq, gas
        type(mesh_t), intent(in)     :: m
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: e, s, w, ff, al, ag
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    liq%ur(i,j,k) = 0.0_dp; liq%uth(i,j,k) = 0.0_dp; liq%uz(i,j,k) = 0.0_dp
                    gas%ur(i,j,k) = 0.0_dp; gas%uth(i,j,k) = 0.0_dp; gas%uz(i,j,k) = 0.0_dp
                    if (m%cell_type(i,j,k) == 0) cycle
                    e = max(liq%alpha(i,j,k), 0.0_dp) + max(gas%alpha(i,j,k), 0.0_dp)
                    if (e <= EPS_MIX .or. .not. fl(i,j,k)) cycle
                    s = min(1.0_dp, max(liq%alpha(i,j,k), 0.0_dp) / e)
                    w = ws_mW(i,j,k)
                    al = max(liq%alpha(i,j,k), 0.0_dp); ag = max(gas%alpha(i,j,k), 0.0_dp)
                    ff = s
                    if (ws_mKl(i,j,k) > 0.0_dp .and. ws_mKg(i,j,k) > 0.0_dp) then
                        if (al*al/ws_mKl(i,j,k) + ag*ag/ws_mKg(i,j,k) > 0.0_dp) &
                            ff = (al*al/ws_mKl(i,j,k)) / (al*al/ws_mKl(i,j,k) + ag*ag/ws_mKg(i,j,k))
                    end if
                    if (abs(ff - s) <= 1.0e-14_dp .or. al <= 1.0e-12_dp .or. ag <= 1.0e-12_dp) then
                        liq%ur(i,j,k) = vr(i,j,k); liq%uth(i,j,k) = vth(i,j,k)
                        gas%ur(i,j,k) = vr(i,j,k); gas%uth(i,j,k) = vth(i,j,k)
                        liq%uz(i,j,k) = vz(i,j,k) - (1.0_dp - s) * w
                        gas%uz(i,j,k) = vz(i,j,k) + s * w
                    else
                        ! lecho: flujo fraccional j_l = f e v + slip (abajo)
                        liq%ur(i,j,k)  = ff * e * vr(i,j,k) / al
                        liq%uth(i,j,k) = ff * e * vth(i,j,k) / al
                        liq%uz(i,j,k)  = (ff * e * vz(i,j,k) - e * s * (1.0_dp - s) * w) / al
                        gas%ur(i,j,k)  = (e * vr(i,j,k)  - al * liq%ur(i,j,k))  / ag
                        gas%uth(i,j,k) = (e * vth(i,j,k) - al * liq%uth(i,j,k)) / ag
                        gas%uz(i,j,k)  = (e * vz(i,j,k)  - al * liq%uz(i,j,k))  / ag
                    end if
                end do
            end do
        end do
    end subroutine phase_velocities

    !---------------------------------------------------------------------------
    ! Topes de velocidad de fase (U_LIQ_MAX, U_GAS_MAX: centinelas) aplicados
    ! conservando el flujo volumetrico de mezcla: la fase que no se recorta
    ! absorbe el resto por la identidad alpha_l u_l + alpha_g u_g = e v. Solo
    ! con las DOS fases en su tope queda un residuo (ambas centinelas activas).
    !---------------------------------------------------------------------------
    subroutine cap_phases_mixture(liq, gas, m)
        type(phase_t), intent(inout) :: liq, gas
        type(mesh_t), intent(in)     :: m
        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        real(dp) :: al, ag, e, ul(3), ug(3), vm(3), sp
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    al = max(liq%alpha(i,j,k), 0.0_dp); ag = max(gas%alpha(i,j,k), 0.0_dp)
                    e = al + ag
                    vm = [vr(i,j,k), vth(i,j,k), vz(i,j,k)]
                    ul = [liq%ur(i,j,k), liq%uth(i,j,k), liq%uz(i,j,k)]
                    ug = [gas%ur(i,j,k), gas%uth(i,j,k), gas%uz(i,j,k)]
                    sp = norm2(ul)
                    if (sp > U_LIQ_MAX) then
                        ul = ul * (U_LIQ_MAX / sp)
                        if (ag > 1.0e-12_dp) ug = (e * vm - al * ul) / ag
                    end if
                    sp = norm2(ug)
                    if (sp > U_GAS_MAX) then
                        ug = ug * (U_GAS_MAX / sp)
                        if (al > 1.0e-12_dp) then
                            ul = (e * vm - ag * ug) / al
                            sp = norm2(ul)
                            if (sp > U_LIQ_MAX) ul = ul * (U_LIQ_MAX / sp)
                        end if
                    end if
                    liq%ur(i,j,k) = ul(1); liq%uth(i,j,k) = ul(2); liq%uz(i,j,k) = ul(3)
                    gas%ur(i,j,k) = ug(1); gas%uth(i,j,k) = ug(2); gas%uz(i,j,k) = ug(3)
                end do
            end do
        end do
    end subroutine cap_phases_mixture

end module mod_mixture_3d
