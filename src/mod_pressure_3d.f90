!===============================================================================
! mod_pressure_3d.f90 - Pressure correction equation (SIMPLE, Rhie-Chow)
!
! C2.3 (hallazgo 3.9): acople presión-velocidad CONSISTENTE en malla colocada.
!
!   Velocidad de cara (Rhie-Chow): u_f = 0.5*(u_P+u_NB)
!            + d_f * [ 0.5*(grad_p|_P + grad_p|_NB) - (p_NB - p_P)/delta_f ]
!   con d_f = 0.5*(V_P/aP_P + V_NB/aP_NB). El término de suavizado acopla
!   presión y velocidad en la MISMA cara y elimina los modos par-impar
!   (checkerboard) invisibles para el gradiente ancho. La versión anterior
!   mezclaba una divergencia cuasi-escalonada con correcciones colocadas de
!   esténcil ancho: el lazo P-V nunca cerraba y p crecía sin límite.
!
! C2.4 (hallazgo 3.10): Poisson de MEZCLA. Divergencia y coeficientes suman
! las contribuciones de AMBAS fases (cada una con su propio d = V/aP) y la
! corrección se aplica a ambas. Con la corrección solo-líquido, el p
! construido para sostener el acero (saltos de Darcy ~1e5-1e6 Pa) aplastaba
! al gas (1000x menos denso) sin corregirlo: medido du_gas ~ 1e5 m/s por
! paso durante la fusión.
!
! Correcciones de celda: u_P -= (V_P/aP_P) * grad(pp)|_P (esténcil central,
! estándar en colocado con Rhie-Chow). Fases/celdas bajo ALPHA_FLOW_CUTOFF
! no participan (C2.2).
!
! ESTADO ACTUAL (auditoria 12-oct-2026; lo de arriba es historia): la ecuacion
! es la de VOLUMEN, Sum_q continuidad_q/rho_q (Plan C F2, GCBA), con
! d = alpha V/aP (aP equivalente del PEA, M30), gradientes con las paredes del
! predictor (pgrad + ws_pv_active, A16/A17), filas selladas = pared con
! Neumann (F2.29, mascara intercambiada en halos, M22), fuente de
! compresibilidad del gas termica + advectiva (A8) + reacciones (M14) con UN
! tope COMP_SRC_CAP y acarreo del exceso (ws_cc, M26), termino acustico como
! seudo-compresibilidad (M25). Solver: CG precondicionado (cg_3d_mpi).
!===============================================================================
module mod_pressure_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    use mod_probe, only: probe_active_now, probe_current_step
    use mod_mpi_topology, only: mpi_exchange_halos_3d
    implicit none

    ! Acople P-V del gas, formulación low-Mach (cierre 2026, punto 1):
    ! el gas participa del Poisson de mezcla y su expansión térmica entra
    ! como fuente de masa acotada. Requiere gas con momentum resuelto
    ! (solve_multiphase); ver notas en solve_pressure_correction.
    ! (S4 del roadmap del paper: ahora claves de config
    !  gas_in_poisson / gas_compressibility, defaults .true. — el estudio
    !  con/sin acople low-Mach se corre por campaña sin recompilar)

    ! Compliance diagonal simétrica aP *= (1+eps): regulariza los bolsones
    ! aislados (p.ej. líquido encerrado en chatarra densa cuyos vecinos
    ! están bajo ALPHA_FLOW_CUTOFF en ambas fases => bloque Neumann puro
    ! singular). Físicamente es una compresibilidad débil del medio: el
    ! desbalance de masa del bolsón sube su nivel de presión en vez de
    ! hacer estallar el CG. Simétrica en theta y entre descomposiciones —
    ! reemplaza al ancla big-coefficient (cuyo hoyuelo en la celda (1,1,1)
    ! rompía la simetría 120° con el gas activo).
    real(dp), parameter :: PP_COMPLIANCE = 1.0e-6_dp

    ! Cap de la fuente de compresibilidad: no se puede exigir ventear más
    ! de esta fracción de la masa de gas de la celda por paso. Sin cap,
    ! celdas que doblan T en un paso (encendido del arco) pedían purgar
    ! >50% de su masa instantáneamente => NaN medidos en -n 1/-n 4.
    real(dp), parameter :: COMP_SRC_CAP = 0.2_dp

    ! COMPRESION FISICA del gas (auditoria M25, oct-2026). La EOS es
    ! rho(P0 + p, T) (gas_eos, mod_constants) y la continuidad de volumen del
    ! gas lleva (alpha/rho) d rho/dt con rho^n = rho(P0 + p^n, T^n):
    !   - FUENTE: (alpha V/dt)(rho(p^k, T^k) - rho(p^n, T^n))/rho(p^k, T^k),
    !     que contiene el termino (p^k - p^n)/(P0 + p^k) y NO se anula al
    !     converger (el gas atrapado se comprime de verdad);
    !   - DIAGONAL: alpha/(P0 + p^k) V/dt, la linealizacion de Newton de esa
    !     fuente en pp (d rho/dp = rho/(P0 + p) a T fija).
    ! Antes (hasta M25) la EOS era rho(P0, T) y la diagonal alpha/P0 V/dt era
    ! SEUDO-compresibilidad: relajacion de pp que desaparecia al converger.
    ! Esa diagonal es la pieza que deja converger el lazo externo a CFL alto
    ! (sin ella n1/n4 divergian, p -> 2e9 Pa); ahora es ademas fisica.
    ! La energia del gas sigue sin trabajo de compresion (p dV): termino de
    ! orden p/P0 frente al calor sensible.

    ! Velocidad del sonido del acero líquido [m/s] (compresibilidad
    ! acústica de celdas líquido-puras en la diagonal del Poisson)
    real(dp), parameter :: C_SOUND_LIQ = 4000.0_dp

    ! Cota física de la presión hidrodinámica: en un EAF nada sostiene
    ! más de ~20 atm (el baño ~1.5e5 Pa; Darcy del lecho ~1e5-1e6 Pa).
    ! El clamp corta el círculo p->u->div->p en regímenes rotos (fusión
    ! forzada sintética: p medida 1e10-1e13 sin él) sin tocar la física
    ! sana (los campos reales quedan órdenes por debajo).
    real(dp), parameter :: P_HYDRO_CAP = 2.0e6_dp

contains

    subroutine solve_pressure_correction(liq, gas, gas_T_ref, sh, m, cfg, &
                                          residual)
        use mod_workspace, only: ensure_workspace, own_weight_face, liq_own_weight, liq_w, mix_cell_weight, &
                                 liq_cont_fallback, bed_rel_face, ws_cc, ws_cc_new, ws_cc_drop, ws_qin_cap, ws_qin_step, ws_p_n, aW => ws_aW, &
            ws_trg, ws_trl, ws_f231_excl, ws_f231_step, ws_pea_kv, ws_pea_al, ws_pea_ag, ws_peal_r, ws_peal_th, ws_peal_z, ws_peag_r, ws_peag_th, ws_peag_z, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su, ws_liq_cont, ws_liq_cont_valid, &
            ws_Fc_r, ws_Fc_th, ws_Fc_z, ws_Fc_lk_r, ws_Fc_lk_th, ws_Fc_lk_z, ws_Fc_valid, &
            ws_Fc_af_r, ws_Fc_af_th, ws_Fc_af_z, ws_liq_fr, ws_liq_fth, ws_liq_fz, &
            ws_Fg_r, ws_Fg_th, ws_Fg_z, ws_Fg_lk_r, ws_Fg_lk_th, ws_Fg_lk_z, ws_Fg_valid, &
            ws_liq_room, ws_liq_room_valid, ws_pv_active, ws_pv_valid, &
            ws_sat_goff, ws_sat_goff_id, &
            ws_lim_step, ws_lim_step_valid, ws_lim_step_id, &
            ws_pc_unl, ws_pc_unl_valid, ws_pc_unl_id, &
            ws_pv_liq, ws_pv_liq_valid, ws_pv_liq_id, &
            ws_gas_perc, ws_gas_reach, ws_gas_perc_valid, &
            ws_bed, ws_bed_gas, ws_bed_liq, ws_bedl_f, ws_bub, ws_bub_f, ws_bed_valid
        type(phase_t), intent(inout) :: liq, gas
        ! T del gas del paso anterior: término de COMPRESIBILIDAD del gas
        ! ideal, -alpha_g*(rho(T)-rho(T_old))/dt*V. Sin él, el Poisson
        ! forzaba div=0 sobre un gas que DEBE expandirse al calentarse
        ! (rho ~ 1/T cae ~80x bajo el arco) -> presiones ficticias
        ! crecientes -> divergencia (medido p -> 1e18).
        real(dp), intent(in)         :: gas_T_ref(-1:,-1:,-1:)
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        real(dp), intent(out)        :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        ! Gradientes de presión de CELDA (los mismos que usa momentum)
        real(dp), allocatable :: gpr(:,:,:), gpth(:,:,:), gpz(:,:,:)
        real(dp), allocatable :: p_g(:,:,:), gpr_g(:,:,:), gpth_g(:,:,:), gpz_g(:,:,:)
        ! Fases ACTIVAS en el acople P-V por celda (Bug 15): gas por el
        ! umbral hidrodinamico; liquido solo donde es fase continua
        logical, allocatable :: act_l(:,:,:), act_g(:,:,:)
        logical, allocatable :: sealed(:,:,:)
        real(dp), allocatable :: lcoef(:,:,:)   ! D2.2b: suma de coeficientes de cara del LIQUIDO por celda
        ! D2.6: suma por DIRECCION (regla cinematica: sin cara abierta en una
        ! direccion, la componente de velocidad del liquido es nula)
        real(dp), allocatable :: lcoef_r(:,:,:), lcoef_th(:,:,:), lcoef_z(:,:,:)
        ! D2.6: mascaras del gradiente que uso el PREDICTOR de este outer
        ! (pared de Bug 16/D2.2b y superficie libre de D2.5), para que el
        ! corrector use el MISMO operador
        logical, allocatable :: pvl(:,:,:), fsl(:,:,:), pvg(:,:,:)
        ! D2.6: celda LLENA de liquido (su superficie libre esta en la cara
        ! superior): gas residual por debajo de este umbral
        real(dp), parameter :: FS_FULL_EPS = 1.0e-3_dp
        logical :: grad_is_gas = .false.
        ! Fuerza vertical del liquido balanceada por caras (liq_balanced_force;
        ! ver mod_momentum_3d): el liquido ve la MISMA presion reducida que el
        ! gas, (p_N - p_P)/dz + W_f, en el Rhie-Chow y en sus gradientes de celda
        logical :: lbf
        logical :: liq_mask_on               ! D2.2b: mascara del liquido del outer anterior (mismo paso)
        ! Flujo de Rhie-Chow F* y coeficiente a_nb del LIQUIDO en las caras +
        ! (este/norte/tope) de cada celda propia, para exportar el flujo
        ! conservativo F = F* + a_nb (pp_P - pp_nb) tras el CG (Bug 19, F1)
        ! Fraccion del gas en los coeficientes de cara (F2.17: la REAL)
        real(dp), allocatable :: ag_eff(:,:,:)
        real(dp), allocatable :: gadv(:,:,:)   ! A8: fuente advectiva del gas [m3/s]
        ! (auditoria 6, M6-1) caudal de gas ENTRANTE por celda [m3/s]: la cota
        ! de la fuente de compresibilidad se mide contra el gas que ATRAVIESA
        ! la celda en el paso (propio + entrante), no solo contra el propio
        real(dp), allocatable :: qin_g(:,:,:)
        ! parte acotada de la demanda de compresibilidad que entra a Su (para
        ! registrar lo que una fila sellada descarta, M6-2)
        real(dp), allocatable :: su_cc(:,:,:)
        real(dp), allocatable :: Fs_r(:,:,:), Fs_th(:,:,:), Fs_z(:,:,:)
        real(dp), allocatable :: Fg_r(:,:,:), Fg_th(:,:,:), Fg_z(:,:,:), ag_r(:,:,:), ag_th(:,:,:), ag_z(:,:,:)
        real(dp), allocatable :: ac_r(:,:,:), ac_th(:,:,:), ac_z(:,:,:)
        integer  :: n_iter_cg
        real(dp) :: cg_res
        ! Residual de CONTINUIDAD del iterado entrante: desbalance de VOLUMEN
        ! sum |Su| (la fuente del Poisson es -div de los flujos volumetricos
        ! de Rhie-Chow mas las fuentes fisicas) normalizado por el flujo
        ! volumetrico total por caras. El residual del CG que se devolvia antes mide la solucion
        ! de pp, no si u* conserva masa (siempre <= SOR_TOL_PRESSURE).
        real(dp) :: flux_ref, sum_su, tmp
        ! Sonda de la FILA DE PRESION de una celda (cfg%probe_cell_*)
        integer  :: pi_, pj_, pk_
        logical  :: probe_here, probe_own
        real(dp) :: su_liq_p, su_gas_p, su_comp_p
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        call ensure_workspace(m)
        allocate(gpr, mold=sh%pp); allocate(gpth, mold=sh%pp)
        allocate(gpz, mold=sh%pp)
        allocate(act_l(lbound(sh%pp,1):ubound(sh%pp,1), lbound(sh%pp,2):ubound(sh%pp,2), &
                       lbound(sh%pp,3):ubound(sh%pp,3)))
        allocate(act_g, mold=act_l)
        allocate(sealed, mold=act_l); sealed = .false.
        allocate(lcoef, mold=sh%pp); lcoef = 0.0_dp
        allocate(lcoef_r, lcoef_th, lcoef_z, mold=sh%pp)
        lcoef_r = 0.0_dp; lcoef_th = 0.0_dp; lcoef_z = 0.0_dp
        allocate(pvl, fsl, pvg, mold=act_l)
        liq_mask_on = cfg%pc_liq_sealed_wall .and. ws_pv_liq_valid .and. (ws_pv_liq_id == probe_current_step())
        allocate(ag_eff, mold=sh%pp)
        allocate(gadv, qin_g, su_cc, mold=sh%pp); gadv = 0.0_dp; qin_g = 0.0_dp; su_cc = 0.0_dp
        allocate(Fs_r, Fs_th, Fs_z, ac_r, ac_th, ac_z, mold=sh%pp)
        ! Completos a cero (halos incluidos): las caras de frontera fisica
        ! no las escribe nadie y el transporte de alpha las lee (leccion v10)
        Fs_r = 0.0_dp; Fs_th = 0.0_dp; Fs_z = 0.0_dp
        ac_r = 0.0_dp; ac_th = 0.0_dp; ac_z = 0.0_dp
        ws_Fc_r = 0.0_dp; ws_Fc_th = 0.0_dp; ws_Fc_z = 0.0_dp
        ws_Fc_lk_r = 0; ws_Fc_lk_th = 0; ws_Fc_lk_z = 0
        ws_Fc_af_r = 0.0_dp; ws_Fc_af_th = 0.0_dp; ws_Fc_af_z = 0.0_dp
        allocate(Fg_r, Fg_th, Fg_z, ag_r, ag_th, ag_z, mold=sh%pp)
        Fg_r = 0.0_dp; Fg_th = 0.0_dp; Fg_z = 0.0_dp
        ag_r = 0.0_dp; ag_th = 0.0_dp; ag_z = 0.0_dp
        ws_Fg_r = 0.0_dp; ws_Fg_th = 0.0_dp; ws_Fg_z = 0.0_dp
        ws_Fg_lk_r = 0; ws_Fg_lk_th = 0; ws_Fg_lk_z = 0
        if (ws_liq_cont_valid) then
            act_l = ws_liq_cont
        else
            act_l = liq_cont_fallback(liq%alpha)   ! (auditoria 6) mismo respaldo que momento
        end if
        ! Gas del acople (F2.16/F2.17): activo donde hay gas que percola, y
        ! tambien — con el CANAL RESIDUAL — donde el gas puede entrar aunque
        ! hoy no lo haya (celda de bano puro que cede liquido). El gas
        ! atrapado queda fuera: ni coeficientes ni compresibilidad.
        act_g = (gas%alpha >= ALPHA_FLOW_CUTOFF)
        if (ws_pv_valid) act_g = act_g .and. ws_pv_active
        ! F2.21: el gas entra al sistema tambien donde TODAVIA no lo hay pero
        ! puede llegar. CATHARE/NEPTUNE resuelven las ecuaciones de ambas
        ! fases aunque una desaparezca; aqui eso significa que la cara entre
        ! una celda de bano puro y el gas de encima EXISTE, de modo que el gas
        ! puede ocupar el hueco que deja el liquido al drenar. Lo que hace que
        ! esto no destruya un bano en reposo (cuatro intentos fallidos,
        ! docs/dev-history F2.17-F2.19) es F2.20: la velocidad de la fase
        ! evanescente esta atada a la de la otra fase, no puesta a cero, asi
        ! que en un charco quieto la cara ve u ~ 0 y no inyecta caudal.
        if (ws_gas_perc_valid) &
            act_g = act_g .or. (ws_gas_reach .and. gas%alpha < ALPHA_FLOW_CUTOFF &
                                .and. m%cell_type /= 0)
        ! Plan F (oct-2026): gas SIEMPRE activo donde hay gas o donde puede
        ! llegar (toda celda con liquido continuo: generaliza el canal
        ! residual F2.21 a todo el dominio). Sin umbral hidrodinamico en la
        ! actividad: los coeficientes de cara ya escalan con alpha_f d_f y la
        ! compresibilidad con alpha_g, asi que la fase evanescente pesa lo que
        ! pesa (continuo), en vez de entrar y salir del acople al cruzar 1e-2
        ! (cada cruce es un "primer contacto" y cuesta rho u dx/dt de presion).
        if (cfg%pc_gas_spring) &
            act_g = (m%cell_type /= 0) .and. (gas%alpha > 0.0_dp .or. act_l)
        ag_eff = gas%alpha

        ! F2.31 (oct-2026): el gas de una celda es fluido del acople solo si
        ! su conductancia REAL en esta ecuacion de presion puede ventear su
        ! propia demanda de compresibilidad con menos de P_VENT. Es el
        ! criterio de Hilfer (Phys. Rev. E 58 (1998) 2090: la subfase
        ! conectada es "the region inside of which an external applied
        ! pressure gradient can propagate") medido con la conductancia del
        ! Poisson, no con la movilidad por arrastre de F2.16: en el piso del
        ! lecho la movilidad del gas de poro cae justo en la banda del umbral
        ! (762 celdas entre 1e-3 y 1e-1 a 322 s de B1 v35) y la celda que se
        ! queda con una conductancia total de 1e-8 seguia contando como
        ! conectada. Su demanda de compresibilidad (gas calentandose, 1.9e-4
        ! m3/s) dividida por esa conductancia exigia -600 Pa POR ITERACION,
        ! sostenidos: -55 -> -139 kPa en 0.17 s y saturacion en -2 MPa (sonda
        ! [PROBE-P]). Es la patologia de F2.13 reaparecida por la puerta de la
        ! percolacion. Una celda que no puede ventear queda FUERA del acople
        ! del gas; si su fila se queda sin caras, F2.29 la vuelve pared.
        if (cfg%gas_in_poisson .and. cfg%gas_compressibility .and. cfg%solve_multiphase &
            .and. .not. cfg%pc_gas_spring) then
        block
            real(dp), parameter :: P_VENT = 5.0e3_dp
            real(dp) :: cg, src, dloc, fdt
            logical, allocatable :: keep(:,:,:)
            real(dp), allocatable :: aRr(:,:,:), aRt(:,:,:), aRz(:,:,:)
            allocate(keep, mold=act_g); keep = act_g
            ! (auditoria 11, M11-1pv) la conductancia del test se evalua con el
            ! transitorio del momento a DT_MOB_REF (como la movilidad de F2.16,
            ! M8-2): con el del dt de la corrida crecia ~ dt donde la inercia
            ! pesa (5x a 10 ms frente a 2 ms; 250x al dt de produccion) y la
            ! clasificacion dependia del integrador. En las celdas PEA el aP del
            ! gas es el EQUIVALENTE de la eliminacion, que lleva el transitorio
            ! del LIQUIDO: se recalcula con la MISMA formula de pea2 y los dos
            ! transitorios a DT_MOB_REF. Con dt = DT_MOB_REF, identico bit a bit.
            ! (auditoria 13) referencia min(dt, DT_MOB_REF): solo se desplaza
            ! con dt > dt_ref; con dt < dt_ref el juicio es el real (desplazarlo
            ! a 2 ms lo volvia MAS laxo que el Poisson: cota a la mitad)
            fdt = cfg%dt / min(cfg%dt, DT_MOB_REF) - 1.0_dp
            allocate(aRr, aRt, aRz, mold=gas%aP_ur)
            aRr = gas%aP_ur; aRt = gas%aP_uth; aRz = gas%aP_uz
            if (fdt /= 0.0_dp) then
                do k = kstart, kend
                    do j = jstart, jend
                        do i = istart, iend
                            if (m%cell_type(i,j,k) == 0) cycle
                            if (ws_pea_kv(i,j,k) > 0.0_dp) then
                                aRr(i,j,k) = pea_ref(ws_peal_r(i,j,k), ws_peag_r(i,j,k), i, j, k, fdt)
                                aRt(i,j,k) = pea_ref(ws_peal_th(i,j,k), ws_peag_th(i,j,k), i, j, k, fdt)
                                aRz(i,j,k) = pea_ref(ws_peal_z(i,j,k), ws_peag_z(i,j,k), i, j, k, fdt)
                            else
                                aRr(i,j,k) = gas%aP_ur(i,j,k) + ws_trg(i,j,k) * fdt
                                aRt(i,j,k) = gas%aP_uth(i,j,k) + ws_trg(i,j,k) * fdt
                                aRz(i,j,k) = gas%aP_uz(i,j,k) + ws_trg(i,j,k) * fdt
                            end if
                        end do
                    end do
                end do
                call mpi_exchange_halos_3d(aRr, m%topo)
                call mpi_exchange_halos_3d(aRt, m%topo)
                call mpi_exchange_halos_3d(aRz, m%topo)
            end if
            do k = kstart, kend
                do j = jstart, jend
                    jm = j - 1; jp = j + 1
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (.not. act_g(i,j,k)) cycle
                        if (gas%alpha(i,j,k) < ALPHA_FLOW_CUTOFF) cycle
                        src = abs(gas%alpha(i,j,k) * m%vol(i,j,k) / cfg%dt * &
                              (gas%rho(i,j,k) - gas_eos(cfg%rho_gas, gas_T_ref(i,j,k), &
                               ws_p_n(i,j,k))) / max(gas%rho(i,j,k), SMALL))
                        ! (auditoria 4, A4-2) la MISMA ponderacion fsat de la
                        ! fuente: el gas de piso de un poro saturado no pide
                        ! volumen, asi que no se le juzga con una demanda que
                        ! no plantea (sin esto salia de act_g y F2.29 sellaba la
                        ! fila: E1b -cerrar la valvula, NEGATIVO en B1- por la
                        ! puerta de atras)
                        src = src * fsat_cell(i, j, k)
                        ! (auditoria 6, M6-2) la demanda que juzga el venteo
                        ! es la que plantea la fuente, CON SIGNO: expansion
                        ! termica (-src, aqui src ya es |.|: se recupera el
                        ! signo), reacciones y acarreo (B5-9 sumaba |termica| +
                        ! acarreo: con gas que se enfria el signo salia
                        ! invertido). El advectivo aun no existe aqui (se arma
                        ! con las caras del Poisson).
                        src = abs(sign(src, gas_eos(cfg%rho_gas, gas_T_ref(i,j,k), ws_p_n(i,j,k)) &
                                             - gas%rho(i,j,k)) &
                                  + (sh%S_CO_src(i,j,k) + sh%S_CO2_src(i,j,k) + sh%S_O2_src(i,j,k)) &
                                    * m%vol(i,j,k) / max(gas%rho(i,j,k), SMALL) &
                                  + ws_cc(i,j,k) / cfg%dt * min(1.0_dp, DT_MOB_REF / cfg%dt))
                        ! (auditoria 12, M12-1) con dt > dt_ref el ACARREO existe
                        ! porque la cota de la FUENTE (0.2 alpha V/dt) es mas
                        ! estrecha que la del test a DT_MOB_REF (con dt < dt_ref
                        ! es al reves y el factor vale 1); contarlo entero a dt grande
                        ! hacia parpadear la celda paso a paso (sale, se
                        ! descarta el acarreo, vuelve, lo acumula). En el
                        ! estado de referencia (dt_ref) ese volumen se habria
                        ! emitido: se escala por dt_ref/dt (identico a 2 ms).
                        ! (M11-1pv) la cota de la demanda tambien a DT_MOB_REF:
                        ! el juicio es del estado, no del paso
                        src = min(src, COMP_SRC_CAP * gas%alpha(i,j,k) * m%vol(i,j,k) / min(cfg%dt, DT_MOB_REF))
                        if (src <= 0.0_dp) cycle
                        cg = 0.0_dp
                        dloc = gas%alpha(i,j,k) * m%vol(i,j,k)
                        if (link(act_g, i-1, j, k)) cg = cg + gcond(dloc/max(aRr(i,j,k),SMALL), &
                            gas%alpha(i-1,j,k)*m%vol(i-1,j,k)/max(aRr(i-1,j,k),SMALL), &
                            gas%alpha(i,j,k), gas%alpha(i-1,j,k), m%Ar(i-1,j,k), m%r(i)-m%r(i-1))
                        if (link(act_g, i+1, j, k)) cg = cg + gcond(dloc/max(aRr(i,j,k),SMALL), &
                            gas%alpha(i+1,j,k)*m%vol(i+1,j,k)/max(aRr(i+1,j,k),SMALL), &
                            gas%alpha(i,j,k), gas%alpha(i+1,j,k), m%Ar(i,j,k), m%r(i+1)-m%r(i))
                        if (link(act_g, i, jm, k)) cg = cg + gcond(dloc/max(aRt(i,j,k),SMALL), &
                            gas%alpha(i,jm,k)*m%vol(i,jm,k)/max(aRt(i,jm,k),SMALL), &
                            gas%alpha(i,j,k), gas%alpha(i,jm,k), m%Ath(i,j,k), m%r(i)*(m%theta(j)-m%theta(jm)))
                        if (link(act_g, i, jp, k)) cg = cg + gcond(dloc/max(aRt(i,j,k),SMALL), &
                            gas%alpha(i,jp,k)*m%vol(i,jp,k)/max(aRt(i,jp,k),SMALL), &
                            gas%alpha(i,j,k), gas%alpha(i,jp,k), m%Ath(i,j,k), m%r(i)*(m%theta(jp)-m%theta(j)))
                        if (link(act_g, i, j, k-1)) cg = cg + gcond(dloc/max(aRz(i,j,k),SMALL), &
                            gas%alpha(i,j,k-1)*m%vol(i,j,k-1)/max(aRz(i,j,k-1),SMALL), &
                            gas%alpha(i,j,k), gas%alpha(i,j,k-1), m%Az(i,j,k-1), m%z(k)-m%z(k-1))
                        if (link(act_g, i, j, k+1)) cg = cg + gcond(dloc/max(aRz(i,j,k),SMALL), &
                            gas%alpha(i,j,k+1)*m%vol(i,j,k+1)/max(aRz(i,j,k+1),SMALL), &
                            gas%alpha(i,j,k), gas%alpha(i,j,k+1), m%Az(i,j,k), m%z(k+1)-m%z(k))
                        if (cg * P_VENT < src) keep(i,j,k) = .false.
                    end do
                end do
            end do
            ! (M12-E1) histeresis dentro del paso: excluida una vez (en
            ! cualquier llamada del paso, incluidas las pasadas n_pc_max),
            ! excluida hasta el paso siguiente. SOLO con dt >= 2 DT_MOB_REF: el
            ! parpadeo que corrige lo induce el juicio desplazado a dt_ref
            ! (bath_fill a 10 ms: 0,0,144,240,288 celdas por iteracion; energia
            ! por paso 0.94 -> 0.26 de lo permitido). En el regimen de B1
            ! (dt ~1-3 ms) la clasificacion queda como se calibro: la
            ! histeresis alli saca del acople todo el paso a celdas excluidas en
            ! un iterado intermedio (el mecanismo del muro de B1) y no hay juez
            ! de B1 con que validarlo.
            if (cfg%dt >= 2.0_dp * DT_MOB_REF) then
                if (probe_current_step() /= ws_f231_step) then
                    ws_f231_excl = .false.
                    ws_f231_step = probe_current_step()
                end if
                ws_f231_excl = ws_f231_excl .or. (act_g .and. .not. keep)
                keep = keep .and. .not. ws_f231_excl
            end if
            act_g = keep
            deallocate(keep, aRr, aRt, aRz)
            call exchange_logical_halos_p(act_g)
        end block
        end if

        ! Plan E E1b (oct-2026): el gas RESIDUAL de un poro SATURADO no es
        ! fluido del acople. ALPHA_PORE_GAS se puso por ENCIMA de
        ! ALPHA_FLOW_CUTOFF (F2.7) para que la celda "nunca quede sellada
        ! hidraulicamente"; medido en B1 a 320 s (sonda [PROBE-P], celda
        ! (8,60,3): alpha_s 0.835, alpha_l 0.150 = cap, alpha_g 0.015 = piso)
        ! eso es una VALVULA FICTICIA: la fila pide 7.5e-4 m3/s de liquido
        ! que compensa con 7.2e-4 m3/s de gas saliendo a 2.4 m/s por el bano
        ! de encima, y ni alpha_l ni alpha_g cambian en 120 pasos porque el
        ! limitador rechaza el liquido (vol_lim) y alpha_g = 1 - suma repone
        ! el gas. El bano de encima baja a 0.33 m/s "dentro" del poro cada
        ! paso y el derrame mueve lo rechazado. Sin la valvula la fila del
        ! poro saturado es incompresible (con E1, transmisiva): la presion
        ! para el bano antes de que la velocidad exista.
        ! La mascara se FIJA en la primera iteracion externa del paso y se
        ! mantiene en las siguientes: medido en el banco (sonda (1,16,4), celda
        ! de bano con 1.3 % de chatarra) que si se reevalua por outer la celda
        ! cruza su capacidad y vuelve en outers consecutivos, el gas entra y
        ! sale del acople, la fila alterna blanda/rigida y pp cambia de signo
        ! en cada outer (+1.3e4, +0.9e4, +4.3e4, +0.05e4, +3.8e4 en un paso).
        if (cfg%pc_sat_gas_off .and. ws_liq_room_valid .and. .not. cfg%pc_gas_spring) then
            if (ws_sat_goff_id /= probe_current_step()) then
                ws_sat_goff = (ws_liq_room <= 1.0e-4_dp)
                ws_sat_goff_id = probe_current_step()
            end if
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (ws_sat_goff(i,j,k)) act_g(i,j,k) = .false.
                    end do
                end do
            end do
            call exchange_logical_halos_p(act_g)
        end if

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp
        gpr = 0.0_dp; gpth = 0.0_dp; gpz = 0.0_dp
        sh%pp = 0.0_dp

        !-----------------------------------------------------------------------
        ! Gradientes de presión de celda por fase (central en el interior,
        ! one-sided SOLO en frontera física; mismas fórmulas que momentum).
        ! Liquido: p del Poisson. Gas: p con gas_pgrad_z en las caras verticales (F2.3).
        !-----------------------------------------------------------------------
        grad_is_gas = .false.
        lbf = cfg%liq_balanced_force .and. .not. cfg%pc_fs_liquid_gradient
        call cell_gradients(sh%p, .false., gpr, gpth, gpz)
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) then
            allocate(p_g, gpr_g, gpth_g, gpz_g, mold=sh%pp)
            p_g = sh%p   ! (F2.3: superficie libre via gas_gz / liq_weight_f)
            grad_is_gas = .true.
            call cell_gradients(p_g, .true., gpr_g, gpth_g, gpz_g)
            grad_is_gas = .false.
        end if
        ! D2.6: mascaras del operador de gradiente de ESTE outer (halos
        ! incluidos: act_l/act_g/ws_pv_liq/ws_liq_cont ya intercambiados)
        do k = lbound(act_l,3), ubound(act_l,3)
            do j = lbound(act_l,2), ubound(act_l,2)
                do i = lbound(act_l,1), ubound(act_l,1)
                    pvl(i,j,k) = pv_cell(i, j, k)
                    fsl(i,j,k) = fs_cell(i, j, k)
                    pvg(i,j,k) = (m%cell_type(i,j,k) /= 0) .and. (act_l(i,j,k) .or. act_g(i,j,k))
                end do
            end do
        end do

        !-----------------------------------------------------------------------
        ! POISSON DE VOLUMEN (Bug 19, Plan C F2): la ecuacion de presion de un
        ! modelo multifluido es la suma de las continuidades de fase divididas
        ! por su densidad, sum_q [d alpha_q/dt + div(alpha_q u_q)] = fuentes
        ! (volumen), NO la continuidad de la MASA de la mezcla. Con la forma de
        ! masa, el liquido que entraba a una celda debia compensarse con gas de
        ! igual MASA (7500x su volumen): imposible -> la unica salida eran MPa
        ! (celdas de liquido puro de B1 v16; charco sobre chatarra fria de B1
        ! v19). En volumen: el liquido desplaza igual volumen de gas; la fusion
        ! y la re-solidificacion (rho_l = rho_s) son exactamente neutras sin
        ! fuente alguna; la compresibilidad del gas entra como
        ! (alpha_g/rho_g) D rho_g/Dt. Los coeficientes son alpha_f d_f A/delta y
        ! el Su, -sum alpha_f u_f A (flujo volumetrico). Los flujos
        ! conservativos exportados (ws_Fc_*) son volumetricos.
        !-----------------------------------------------------------------------
        !-----------------------------------------------------------------------
        ! Acumular contribuciones de AMBAS fases (C2.4, reactivado tras C3.4:
        ! con la radiación DO real el gas queda en ~3000-6000 K y su
        ! expansión es absorbible por el Poisson)
        !-----------------------------------------------------------------------
        probe_here = .false.; pi_ = 0; pj_ = 0; pk_ = 0
        su_liq_p = 0.0_dp; su_gas_p = 0.0_dp; su_comp_p = 0.0_dp
        if (cfg%probe_cell_k > 0) then
            if (probe_active_now(cfg)) then
                call global_to_local(m, cfg%probe_cell_i, cfg%probe_cell_j, &
                                     cfg%probe_cell_k, pi_, pj_, pk_, probe_own)
                probe_here = probe_own
            end if
        end if
        flux_ref = 0.0_dp
        call add_phase_contribution(liq, liq%alpha, act_l, .true., sh%p, gpr, gpth, gpz, .false.)
        ! D2.2b: celda ACTIVA para el liquido sin ninguna cara de liquido abierta
        ! => sellada para el liquido: pared de su gradiente de presion (outers
        ! siguientes de este paso) y liquido inmovil (mod_multiphase)
        ! D2.6 (regla cinematica por direccion): la componente del liquido
        ! continuo sin ninguna cara de liquido abierta en esa direccion es
        ! nula (velocidad de celda = media de dos caras cerradas). Es lo que
        ! mata la velocidad FANTASMA del charco de una celda sobre un poro
        ! lleno con gas encima (B1 330 s: -5..-11 m/s con p hidrostatica
        ! exacta; el Poisson no la ve por ninguna cara y nada la frena).
        if (cfg%pc_liq_sealed_wall .or. cfg%pc_liq_closed_dir) then
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        ws_pv_liq(i,j,k) = (m%cell_type(i,j,k) /= 0) .and. &
                                           (act_l(i,j,k) .or. act_g(i,j,k)) .and. &
                                           .not. (act_l(i,j,k) .and. lcoef(i,j,k) <= 0.0_dp)
                        ws_liq_fr(i,j,k)  = .not. (act_l(i,j,k) .and. lcoef_r(i,j,k)  <= 0.0_dp)
                        ws_liq_fth(i,j,k) = .not. (act_l(i,j,k) .and. lcoef_th(i,j,k) <= 0.0_dp)
                        ws_liq_fz(i,j,k)  = .not. (act_l(i,j,k) .and. lcoef_z(i,j,k)  <= 0.0_dp)
                    end do
                end do
            end do
            call exchange_logical_halos_p(ws_pv_liq)
            call exchange_logical_halos_p(ws_liq_fr)
            call exchange_logical_halos_p(ws_liq_fth)
            call exchange_logical_halos_p(ws_liq_fz)
            ws_pv_liq_valid = .true.
            ws_pv_liq_id = probe_current_step()
        end if
        if (probe_here) su_liq_p = Su(pi_,pj_,pk_)
        ! Gas en el Poisson SOLO con multifase: sin gas momentum resuelto,
        ! sus aP_u* valen 0 y d_f = V/SMALL revienta los coeficientes.
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) &
            call add_phase_contribution(gas, ag_eff, act_g, .false., p_g, gpr_g, gpth_g, gpz_g, .true.)
        if (probe_here) su_gas_p = Su(pi_,pj_,pk_) - su_liq_p

        ! NOTA (cierre 2026): NO añadir aquí la fuente de masa de fusión
        ! del líquido (Su += mdot - rho*dalpha/dt). Se probó: realimenta
        ! p con ganancia >1 (p crecía x50/paso hasta 1e35 en melt_forced,
        ! con y sin cap). La conservación fusión->alpha->inventario ya es
        ! EXACTA vía el transporte explícito de alpha (ratio 1.0000
        ! medido); el gas desplazado por el fundido lo absorbe la
        ! restricción de volumen + el término acústico.
        ! Compresibilidad del gas ideal (low-Mach):
        !   Su -= alpha_g*(rho(T_it)-rho(T_old))/dt*V   (expansión => Su
        ! sube => pp empuja flujo de salida). ACOTADA a COMP_SRC_CAP de la
        ! masa de gas de la celda por paso: el exceso queda para los pasos
        ! siguientes (rho sigue a T, la demanda se re-emite sola).
        ! Aproximación: alpha_g fijo en el término temporal (el cambio de
        ! alpha por fusión/colapso es de segundo orden aquí).
        if (cfg%gas_compressibility .and. cfg%solve_multiphase) then
        block
            real(dp) :: src, cap, dvol, dcl, fsat
            ! (auditoria 6, M6-2) el acarreo vive SOLO mientras la celda esta
            ! en el acople: una celda fuera de act_g (F2.13/F2.31), sin gas o
            ! sellada (F2.29, abajo) lo DESCARTA con registro (ws_cc_drop ->
            ! m_gas_ccdrop). B5-9 lo conservaba congelado: la exclusion de F2.31
            ! se volvia pegajosa (el acarreo entraba al test de venteo) y
            ! slag_chem_flow guardaba acarreo creciente en 24 celdas sin gas.
            ! Las celdas OUTLET (Dirichlet p' = 0) no plantean demanda ni
            ! acarrean (B5-7): son el sumidero.
            ws_cc_new = 0.0_dp
            ws_cc_drop = 0.0_dp
            ! (M7-5) cota con el caudal de la PRIMERA llamada del paso
            if (probe_current_step() /= ws_qin_step) then
                ws_qin_cap = qin_g
                ws_qin_step = probe_current_step()
            end if
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (at_zmax .and. k == kend) then
                            if (any(m%is_electrode(i,j,k,:))) cycle
                        end if
                        if (.not. act_g(i,j,k) .or. gas%alpha(i,j,k) < ALPHA_CUTOFF) then
                            ws_cc_drop(i,j,k) = ws_cc(i,j,k)
                            cycle
                        end if
                        ! El gas RESIDUAL de un poro SATURADO (alpha_g en el
                        ! piso ALPHA_PORE_GAS, liquido en el cap) es un canal
                        ! hidraulico (F2.7), no un inventario termodinamico: su
                        ! expansion al calentarse no pide volumen (auditoria 3,
                        ! A3-3: con la referencia Tg_end y el area de pelicula
                        ! de A3-2 el piso se calentaba 5x en un paso y bombeaba
                        ! el 7.5 % del volumen de cada poro de bath_freeze a
                        ! traves del bano: 138 kPa, freeboard a 20 m/s y
                        ! caotico, n1/n4 3e-8 -> 0.14). La fila sigue activa
                        ! (la valvula de Plan E no se cierra); solo no bombea.
                        ! Peso CONTINUO en el hueco del poro (0 saturado, 1 con
                        ! hueco >= ALPHA_PORE_GAS): un interruptor en room <=
                        ! 1e-4 saltaba a distinto paso segun el redondeo
                        ! (n1/n4 1.7e-4). Las fuentes de masa de las reacciones
                        ! no se pesan: esa masa tiene que ventear.
                        fsat = fsat_cell(i, j, k)
                        ! Forma de VOLUMEN: (alpha_g/rho_g) (rho(T) - rho(T_old))/dt V
                        src = gas%alpha(i,j,k) * m%vol(i,j,k) / cfg%dt * &
                              (gas%rho(i,j,k) - gas_eos(cfg%rho_gas, gas_T_ref(i,j,k), &
                               ws_p_n(i,j,k))) / max(gas%rho(i,j,k), SMALL)
                        ! (auditoria 6, M6-1) la cota es el 20 % del gas que
                        ! ATRAVIESA la celda en el paso (propio + entrante): en
                        ! un poro con caudal pasante la contraccion del gas
                        ! caliente que entra vale 1.2-1.6 veces el gas propio
                        ! por paso (bath_fill) y la cota sobre el propio la
                        ! recortaba cada paso (acarreo saturado: la EOS
                        ! reescribia esa masa, N-M4)
                        ! (auditoria 7, M7-5) con el caudal CONGELADO del paso:
                        ! la cota sobre el caudal del iterado volvia al lazo
                        ! externo menos contractivo (cold 0.97 con 5 iteraciones)
                        cap = COMP_SRC_CAP * (gas%alpha(i,j,k) * m%vol(i,j,k) / cfg%dt + ws_qin_cap(i,j,k))
                        ! Demanda de volumen del gas [m3/s]: expansion termica
                        ! (-src), A8 advectiva (gadv), M14 fuente de masa de las
                        ! reacciones (S_gas/rho_g) y lo que el tope no dejo
                        ! salir en el paso anterior (M26). UN solo tope sobre el
                        ! total; el exceso se ACARREA (antes se perdia: el
                        ! comentario decia que la demanda se re-emitia, pero la
                        ! referencia del paso siguiente ya es la T nueva)
                        ! (auditoria 5, M5-3) el acarreo NO se vuelve a pesar:
                        ! ws_cc es el resto de una demanda YA pesada (B4-9 lo
                        ! multiplicaba otra vez por fsat y con fsat = f perdia
                        ! (1 - f) del acarreo por paso sin columna; y la masa
                        ! de CO/CO2 que no cupo bajo COMP_SRC_CAP desaparecia
                        ! al saturarse el poro, contra la regla de que las
                        ! reacciones no se pesan). Solo la demanda NUEVA
                        ! (termica + advectiva) lleva fsat.
                        dvol = fsat * (-src + gadv(i,j,k)) + ws_cc(i,j,k) / cfg%dt &
                             + (sh%S_CO_src(i,j,k) + sh%S_CO2_src(i,j,k) + sh%S_O2_src(i,j,k)) &
                               * m%vol(i,j,k) / max(gas%rho(i,j,k), SMALL)
                        dcl = max(-cap, min(cap, dvol))
                        Su(i,j,k) = Su(i,j,k) + dcl
                        su_cc(i,j,k) = dcl
                        ! acarreo acotado por el mismo volumen de referencia
                        ! que la cota; lo que lo excede se descarta CON registro
                        ws_cc_new(i,j,k) = sign(min(abs(dvol - dcl) * cfg%dt, &
                            gas%alpha(i,j,k) * m%vol(i,j,k) + ws_qin_cap(i,j,k) * cfg%dt), dvol - dcl)
                        ws_cc_drop(i,j,k) = (dvol - dcl) * cfg%dt - ws_cc_new(i,j,k)
                    end do
                end do
            end do
        end block
        end if

        ! Plan E E2 (oct-2026): el volumen de liquido que entra por caras que
        ! esta ecuacion NO enlaza (goteo disperso por la regla del dador,
        ! derrame), medido en el ultimo transporte de alpha de ESTE paso, es
        ! una FUENTE conocida: entra como "inflow" y la presion lo evacua por
        ! las caras enlazadas en la misma iteracion (gas de la celda, o
        ! liquido si esta saturada). Es el termino de drift-flux de la
        ! continuidad de mezcla (Manninen 1996). Sin el, el goteo llenaba
        ! celdas que la presion nunca vio y la diferencia se cobraba como
        ! presion un paso despues (D1: vol_unlinked, Spearman 0.93 con p_max).
        if (cfg%pc_drift_source .and. ws_pc_unl_valid .and. &
            ws_pc_unl_id == probe_current_step()) then
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (.not. (act_l(i,j,k) .or. act_g(i,j,k))) cycle
                        Su(i,j,k) = Su(i,j,k) + ws_pc_unl(i,j,k)
                    end do
                end do
            end do
        end if

        ! Celdas activas sin contribución de ninguna fase: triviales
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if ((act_l(i,j,k) .or. act_g(i,j,k)) .and. &
                        aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) + &
                        aB(i,j,k) + aT(i,j,k) <= 0.0_dp) sealed(i,j,k) = .true.
                    if ((.not. act_l(i,j,k) .and. .not. act_g(i,j,k)) .or. sealed(i,j,k)) then
                        aW(i,j,k) = 0.0_dp; aE(i,j,k) = 0.0_dp
                        aS(i,j,k) = 0.0_dp; aN(i,j,k) = 0.0_dp
                        aB(i,j,k) = 0.0_dp; aT(i,j,k) = 0.0_dp
                        aP(i,j,k) = 1.0_dp; Su(i,j,k) = 0.0_dp
                        ! (M6-2) la fila sellada no evacua nada: lo que la
                        ! celda planteo este paso (Su ya incluia la parte
                        ! acotada) se descarta CON registro
                        if (cfg%gas_compressibility .and. cfg%solve_multiphase .and. sealed(i,j,k)) then
                            ws_cc_drop(i,j,k) = ws_cc_drop(i,j,k) + ws_cc_new(i,j,k) + su_cc(i,j,k) * cfg%dt
                            ws_cc_new(i,j,k) = 0.0_dp
                        end if
                    else
                        ! Compliance: ver nota de PP_COMPLIANCE arriba
                        aP(i,j,k) = (aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + &
                                     aN(i,j,k) + aB(i,j,k) + aT(i,j,k)) * &
                                    (1.0_dp + PP_COMPLIANCE)
                        ! Término acústico low-Mach (ver P0_THERMO arriba)
                        if (cfg%gas_compressibility .and. cfg%solve_multiphase) then
                        block
                            real(dp) :: ag_c
                            ag_c = 0.0_dp
                            if (act_g(i,j,k)) ag_c = gas%alpha(i,j,k)
                            ! D2.4 (Plan D, oct-2026): COMPLIANCIA RESIDUAL en
                            ! toda celda con liquido activo. Cuando una celda de
                            ! bano expulsa su ultimo gas, su compliancia cae de
                            ! alpha_g/P0 a ~0 en un paso y parar la columna que
                            ! le llega cuesta Su/aP ~ 1e5-1e6 Pa (water packing;
                            ! RELAP5 §3.4.6: "discontinuous change in
                            ! compressibility between a two-phase mixture of
                            ! small void fraction and a pure liquid"). Un piso
                            ! alpha_g_comp_min en la DIAGONAL (no en el balance
                            ! de volumen ni en la masa) acota ese salto: es gas/
                            ! porosidad no resuelta de un bano sobre chatarra
                            ! (compresibilidad artificial; Plan C B-2). El
                            ! exceso de volumen que deja lo mueve el derrame,
                            ! auditado. Default 0 = bit-identico.
                            if (act_l(i,j,k)) ag_c = max(ag_c, cfg%alpha_g_comp_min)
                            ! (volumen: d alpha_g/dp' = alpha_g/(P0 + p), M25)
                            if (ag_c > 0.0_dp) aP(i,j,k) = aP(i,j,k) + ag_c &
                                / max(P0_THERMO + sh%p(i,j,k), P_ABS_MIN) * m%vol(i,j,k) / cfg%dt
                        end block
                        end if
                        ! Compresibilidad acústica del LÍQUIDO (física,
                        ! c~4000 m/s): diagonal para celdas líquido-puras
                        ! (sin gas no hay término acústico del gas y la
                        ! compliance sola deja el nivel de p sin física)
                        if (act_l(i,j,k)) then
                            ! (volumen: alpha_l/(rho_l c^2))
                            aP(i,j,k) = aP(i,j,k) + liq%alpha(i,j,k) * m%vol(i,j,k) / &
                                (liq%rho(i,j,k) * C_SOUND_LIQ**2 * cfg%dt)
                        end if
                    end if
                end do
            end do
        end do
        ! Auditoria M22: la vecina sellada de OTRO rank debe verse sellada en
        ! el Neumann de F2.29 (acc_nb); sin el intercambio el halo quedaba en
        ! .false. y el resultado dependia de la descomposicion
        call exchange_logical_halos_p(sealed)

        if (probe_here) then
            su_comp_p = Su(pi_,pj_,pk_) - su_liq_p - su_gas_p
            write(*,'(A,I8,A,3I4,A,2L1,18(A,ES11.3))') &
                '[PROBE-P] paso', probe_current_step(), ' celda', cfg%probe_cell_i, cfg%probe_cell_j, cfg%probe_cell_k, &
                ' act_l/g=', act_l(pi_,pj_,pk_), act_g(pi_,pj_,pk_), &
                ' | Su_liq=', su_liq_p, ' Su_gas=', su_gas_p, ' Su_comp=', su_comp_p, &
                ' | aW=', aW(pi_,pj_,pk_), ' aE=', aE(pi_,pj_,pk_), ' aS=', aS(pi_,pj_,pk_), ' aN=', aN(pi_,pj_,pk_), &
                ' aB=', aB(pi_,pj_,pk_), ' aT=', aT(pi_,pj_,pk_), ' aP=', aP(pi_,pj_,pk_), &
                ' | p_in=', sh%p(pi_,pj_,pk_), ' al=', liq%alpha(pi_,pj_,pk_), ' ag=', gas%alpha(pi_,pj_,pk_), &
                ' | aPuz=', liq%aP_uz(pi_,pj_,pk_), ' aPuz_T=', liq%aP_uz(pi_,pj_,pk_+1), ' aPur_W=', liq%aP_ur(pi_-1,pj_,pk_), &
                ' aPur=', liq%aP_ur(pi_,pj_,pk_), ' aPuth=', liq%aP_uth(pi_,pj_,pk_)
        end if
        ! Pressure BCs
        call apply_pressure_bc(aW, aE, aS, aN, aB, aT, aP, Su, m)

        ! Residual de continuidad del iterado entrante (ver flux_ref). Tras
        ! las BC: las celdas de SALIDA (Dirichlet pp = 0 en los agujeros de
        ! electrodo) quedan con Su = 0 — su desbalance es el venteo fisico
        ! que cierra por la frontera, no un residuo (con ellas dentro el
        ! residual tenia un piso de 3e-2 en outer_conv con 100 outers).
        sum_su = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (act_l(i,j,k) .or. act_g(i,j,k)) sum_su = sum_su + abs(Su(i,j,k))
                end do
            end do
        end do
        if (m%is_parallel) then
            call mpi_allreduce_sum(sum_su, tmp, m%topo);   sum_su   = tmp
            call mpi_allreduce_sum(flux_ref, tmp, m%topo); flux_ref = tmp
        end if
        residual = sum_su / max(flux_ref, SMALL)

        ! (El ancla big-coefficient fue retirada: con el gas en el Poisson
        ! todo el dominio activo conecta a los Dirichlet del techo y la
        ! compliance regulariza los bolsones aislados. El hoyuelo del ancla
        ! en la celda (1,1,1) rompía la simetría 120°.)

        ! Solve con CG precondicionado Jacobi (C4.3 adelantado: el SOR
        ! omega=1.5 con halos retardados divergía; la matriz de cara
        ! compacta con Dirichlet plegados es simétrica)
        call cg_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, sh%pp, m, &
                       cfg%max_inner_pres, SOR_TOL_PRESSURE, &
                       cg_res, n_iter_cg)
        if (probe_here) write(*,'(A,I8,A,ES11.3,A,6ES11.3)') '[PROBE-P] paso', probe_current_step(), &
            ' pp=', sh%pp(pi_,pj_,pk_), ' pp_vec(W,E,S,N,B,T)=', sh%pp(pi_-1,pj_,pk_), sh%pp(pi_+1,pj_,pk_), &
            sh%pp(pi_,pj_-1,pk_), sh%pp(pi_,pj_+1,pk_), sh%pp(pi_,pj_,pk_-1), sh%pp(pi_,pj_,pk_+1)

        ! (residual = desbalance de masa del iterado entrante, calculado
        ! antes del CG; cg_res queda como diagnostico del solver lineal)
        if (cg_res /= cg_res) residual = cg_res   ! NaN del CG: propagarlo

        !-------------------------------------------------------------------
        ! Flujos CONSERVATIVOS (volumetricos, m3/s) del liquido por las caras
        ! + (Bug 19, F1/F2): Q = Q* + a_nb (pp_P - pp_nb). Es el flujo cuya divergencia el CG
        ! acaba de anular (salvo compliance/acustico); el transporte de
        ! alpha del liquido continuo los usa en vez de reconstruir flujos
        ! desde velocidades de centro (que NO son solenoidales aunque p
        ! haya convergido: la causa de que un bano en reposo se llenara y
        ! drenara solo). Caras propias + halos por intercambio.
        !-------------------------------------------------------------------
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (ws_Fc_lk_r(i,j,k) == 1) ws_Fc_r(i,j,k) = Fs_r(i,j,k) + &
                        ac_r(i,j,k) * (sh%pp(i,j,k) - sh%pp(i+1,j,k))
                    if (ws_Fc_lk_th(i,j,k) == 1) ws_Fc_th(i,j,k) = Fs_th(i,j,k) + &
                        ac_th(i,j,k) * (sh%pp(i,j,k) - sh%pp(i,j+1,k))
                    if (ws_Fc_lk_z(i,j,k) == 1) ws_Fc_z(i,j,k) = Fs_z(i,j,k) + &
                        ac_z(i,j,k) * (sh%pp(i,j,k) - sh%pp(i,j,k+1))
                end do
            end do
        end do
        call mpi_exchange_halos_3d(ws_Fc_r,  m%topo)
        call mpi_exchange_halos_3d(ws_Fc_th, m%topo)
        call mpi_exchange_halos_3d(ws_Fc_z,  m%topo)
        call mpi_exchange_halos_3d_int(ws_Fc_lk_r,  m%topo)
        call mpi_exchange_halos_3d_int(ws_Fc_lk_th, m%topo)
        call mpi_exchange_halos_3d_int(ws_Fc_lk_z,  m%topo)
        call mpi_exchange_halos_3d(ws_Fc_af_r,  m%topo)
        call mpi_exchange_halos_3d(ws_Fc_af_th, m%topo)
        call mpi_exchange_halos_3d(ws_Fc_af_z,  m%topo)
        ws_Fc_valid = .true.

        ! Flujos de MASA conservativos del GAS (auditoria M24, gas): el
        ! volumetrico corregido por la densidad del DADOR. El momento del gas
        ! los usa desde la 2.a iteracion externa del paso.
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) then
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (ws_Fg_lk_r(i,j,k) == 1) ws_Fg_r(i,j,k) = gmass(Fg_r(i,j,k) + &
                            ag_r(i,j,k) * (sh%pp(i,j,k) - sh%pp(i+1,j,k)), i, j, k, i+1, j, k)
                        if (ws_Fg_lk_th(i,j,k) == 1) ws_Fg_th(i,j,k) = gmass(Fg_th(i,j,k) + &
                            ag_th(i,j,k) * (sh%pp(i,j,k) - sh%pp(i,j+1,k)), i, j, k, i, j+1, k)
                        if (ws_Fg_lk_z(i,j,k) == 1) ws_Fg_z(i,j,k) = gmass(Fg_z(i,j,k) + &
                            ag_z(i,j,k) * (sh%pp(i,j,k) - sh%pp(i,j,k+1)), i, j, k, i, j, k+1)
                    end do
                end do
            end do
            call mpi_exchange_halos_3d(ws_Fg_r,  m%topo)
            call mpi_exchange_halos_3d(ws_Fg_th, m%topo)
            call mpi_exchange_halos_3d(ws_Fg_z,  m%topo)
            call mpi_exchange_halos_3d_int(ws_Fg_lk_r,  m%topo)
            call mpi_exchange_halos_3d_int(ws_Fg_lk_th, m%topo)
            call mpi_exchange_halos_3d_int(ws_Fg_lk_z,  m%topo)
            ws_Fg_valid = .true.
        end if

        ! D2.6: el corrector usa el MISMO operador de gradiente que el
        ! predictor de este outer (pvl/fsl: paredes y superficie libre del
        ! liquido; pvg: paredes del gas) y la regla cinematica por direccion
        if (cfg%pc_liq_closed_dir) then
            call correct_velocities(liq, sh, m, act_l, pvl, fsl, cfg%pc_consistent_corrector, &
                                    ws_liq_fr, ws_liq_fth, ws_liq_fz)
        else
            call correct_velocities(liq, sh, m, act_l, pvl, fsl, cfg%pc_consistent_corrector)
        end if
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) &
            call correct_velocities(gas, sh, m, act_g, pvg, fsl, cfg%pc_consistent_corrector, &
                                    use_fs=.false.)

        ! Correct pressure (con cota física, ver P_HYDRO_CAP)
        sh%p = sh%p + cfg%alpha_p * sh%pp
        ! (auditoria 3, B3-11) un NaN no se enmascara con la cota: min/max
        ! con NaN devuelven el otro operando y la guardia de NaN no lo veia
        if (.not. any(sh%p /= sh%p)) sh%p = max(-P_HYDRO_CAP, min(P_HYDRO_CAP, sh%p))

        !-------------------------------------------------------------------
        ! Celdas SIN fase continua (Bug 16): su pp es identicamente 0 (aP=1,
        ! Su=0), asi que su presion queda CONGELADA para siempre en el valor
        ! que tuviera al sellarse — y los vecinos la leen en dp/dx del
        ! momento. B1 v14: una celda con alpha_s = 1.0000 exacto quedo con
        ! 613 kPa a t=42 s y sostuvo un chorro de gas de 200 m/s tres celdas
        ! mas arriba durante el resto de la corrida (p_max identico a 5
        ! cifras durante 20 s de simulacion). Se les impone Neumann: la
        ! media de sus vecinas con fluido (0 si no hay ninguna), que es la
        ! condicion de pared y anula el gradiente espurio.
        !-------------------------------------------------------------------
        block
            real(dp) :: psum
            integer  :: nnb
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if ((act_l(i,j,k) .or. act_g(i,j,k)) .and. .not. sealed(i,j,k)) cycle
                        psum = 0.0_dp; nnb = 0
                        call acc_nb(i-1, j, k, psum, nnb)
                        call acc_nb(i+1, j, k, psum, nnb)
                        call acc_nb(i, j-1, k, psum, nnb)
                        call acc_nb(i, j+1, k, psum, nnb)
                        call acc_nb(i, j, k-1, psum, nnb)
                        call acc_nb(i, j, k+1, psum, nnb)
                        if (nnb > 0) then
                            sh%p(i,j,k) = psum / real(nnb, dp)
                        else
                            sh%p(i,j,k) = 0.0_dp
                        end if
                    end do
                end do
            end do
        end block

        !-------------------------------------------------------------------
        ! Aberturas del techo (agujeros de los electrodos, Dirichlet pp = 0)
        ! con REFLUJO: presion TOTAL ambiente, p = p0 - 1/2 rho_g u_in^2 si el
        ! gas entra (u_in > 0, ver abajo), p0 si sale (totalPressure +
        ! pressureInletOutletVelocity de OpenFOAM; "backflow" de las salidas
        ! de presion de Fluent). Con p = 0 fijo en la celda el caudal de
        ! entrada no tenia freno: el chorro bajaba la presion debajo y se
        ! realimentaba hasta U_GAS_MAX (B1 258.52-258.56 s: borde del agujero
        ! del electrodo 2, chorro de 2 m a 290 m/s con 1.4 kPa de succion;
        ! Bernoulli da ~110 m/s). Sub-relajado con alpha_p, por iteracion.
        !-------------------------------------------------------------------
        ! (dirigida) solo donde el gas del Poisson se corrige (dos fluidos,
        ! gas_in_poisson; la mezcla resuelve su presion aparte); u_in acotada
        ! a U_GAS_MAX (cap_gas_velocity corre despues) y p a P_HYDRO_CAP: la
        ! salida es el ancla del nivel de presion; un NaN no se escribe. Una
        ! abertura sin gas (alpha_g < ALPHA_FLOW_CUTOFF) no se relaja y conserva
        ! el valor que tenga (Dirichlet fijo, como sin la clave): p0 es la
        ! columna de GAS y alli no hay gas que refluya
        if (cfg%pc_outlet_total_pressure .and. at_zmax .and. cfg%solve_multiphase &
            .and. cfg%gas_in_poisson .and. .not. cfg%mixture_model .and. ws_Fg_valid) then
            block
            real(dp) :: u_in, p_new
            k = kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (.not. any(m%is_electrode(i,j,k,:))) cycle
                    if (gas%alpha(i,j,k) < ALPHA_FLOW_CUTOFF) cycle
                    ! velocidad de ENTRADA = masa que la celda de salida inyecta
                    ! netamente al dominio por sus caras (la abertura absorbe
                    ! el desbalance; mismo criterio que m_gas_out del audit)
                    ! sobre rho_g y el area de la abertura; u_z de centro no
                    ! vale: en el borde del agujero el gas entra de lado
                    u_in = outlet_inflow_velocity(ws_Fg_r(i,j,k), ws_Fg_r(i-1,j,k), ws_Fg_th(i,j,k), &
                        ws_Fg_th(i,j-1,k), ws_Fg_z(i,j,k-1), gas%rho(i,j,k), m%vol(i,j,k), m%zf(k) - m%zf(k-1))
                    ! referencia p0: la columna de gas de media celda sobre el
                    ! centro (la de initialize_hydrostatic_pressure con la
                    ! cara superior a 0): en reposo el objetivo es el valor
                    ! inicial y el Dirichlet no se mueve (relajar hacia 0
                    ! desequilibraba slag_rest y bath_test_stretch)
                    p_new = outlet_total_pressure(sh%p(i,j,k), &
                        gas%rho(i,j,k) * GRAVITY * (m%zf(k) - m%z(k)), gas%rho(i,j,k), u_in, cfg%alpha_p)
                    if (p_new /= p_new) cycle
                    sh%p(i,j,k) = p_new
                end do
            end do
            end block
        end if
        call mpi_exchange_halos_3d(sh%p, m%topo)

        deallocate(gpr, gpth, gpz, act_l, act_g, ag_eff, sealed, lcoef, gadv, qin_g, su_cc)
        deallocate(lcoef_r, lcoef_th, lcoef_z, pvl, fsl, pvg)
        deallocate(Fs_r, Fs_th, Fs_z, ac_r, ac_th, ac_z)
        deallocate(Fg_r, Fg_th, Fg_z, ag_r, ag_th, ag_z)
        if (allocated(p_g)) deallocate(p_g, gpr_g, gpth_g, gpz_g)

    contains

        ! (M11-1pv) aP equivalente del gas tras la eliminacion parcial (pea2 de
        ! mod_multiphase, MISMA formula y orden de operaciones) con los
        ! transitorios de ambas fases desplazados a DT_MOB_REF
        pure function pea_ref(apl0, apg0, ii, jj, kk, fd) result(ar)
            real(dp), intent(in) :: apl0, apg0, fd
            integer, intent(in)  :: ii, jj, kk
            real(dp) :: ar, dummy
            ! (A12-T3) la MISMA funcion que pea2, con los transitorios de las
            ! dos fases desplazados a DT_MOB_REF y las alpha de la eliminacion
            call pea_coeffs(apl0 + ws_trl(ii,jj,kk) * fd, apg0 + ws_trg(ii,jj,kk) * fd, &
                            ws_pea_kv(ii,jj,kk), ws_pea_al(ii,jj,kk), ws_pea_ag(ii,jj,kk), dummy, ar)
        end function pea_ref

        ! (auditoria 4, A4-2; B4-9/B4-12) Peso de la demanda de volumen del
        ! gas de una celda del lecho: 1 con hueco de poro >= ALPHA_PORE_GAS, 0
        ! en el poro SATURADO (el gas de piso es un canal hidraulico, F2.7, no
        ! un inventario). UNA definicion para la fuente y el test de venteo
        ! de F2.31. La saturacion exige LIQUIDO (rampa alpha_l 0 -> APG): un
        ! lecho seco compactado con poco hueco no esta saturado y su gas
        ! demanda entero. Sin piso de poro (pc_gas_spring, mixture_model:
        ! pore_floor_on = .false.) no hay canal y el peso es 1 (antes salia
        ! alpha_g/APG, incoherente con el resorte de Plan F).
        pure real(dp) function fsat_cell(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: sat
            fsat_cell = 1.0_dp
            if (.not. (pore_floor_on .and. ws_liq_room_valid .and. ws_bed_valid)) return
            if (ws_bed(ii,jj,kk) <= 0.0_dp) return
            sat = 1.0_dp - min(1.0_dp, max(0.0_dp, ws_liq_room(ii,jj,kk) / ALPHA_PORE_GAS))
            sat = sat * min(1.0_dp, max(0.0_dp, liq%alpha(ii,jj,kk) / ALPHA_PORE_GAS))
            fsat_cell = 1.0_dp - sat
        end function fsat_cell

        ! Flujo de masa del gas por una cara: volumetrico q (orientado de P a N)
        ! por la densidad del dador (M24, gas)
        pure real(dp) function gmass(q, ip, jp_, kp, in_, jn_, kn_)
            real(dp), intent(in) :: q
            integer, intent(in)  :: ip, jp_, kp, in_, jn_, kn_
            if (q >= 0.0_dp) then
                gmass = q * gas%rho(ip,jp_,kp)
            else
                gmass = q * gas%rho(in_,jn_,kn_)
            end if
        end function gmass

        ! Termino ADVECTIVO de la compresibilidad del gas (auditoria 12-oct-2026,
        ! A8): la continuidad de VOLUMEN del gas es d alpha/dt + div(alpha u) =
        ! -(alpha/rho)(d rho/dt + u.grad rho); solo estaba d rho/dt. Upwind:
        ! el gas que ENTRA por una cara con la densidad de la vecina cambia de
        ! volumen al tomar la de la celda, Q_in (rho_N - rho_P)/rho_P (frio que
        ! entra a una celda caliente se expande); el que sale no aporta. Se
        ! acumula en gadv y entra a Su con el tope COMP_SRC_CAP, como la parte
        ! temporal. Sin esto, en un chorro estacionario calentado por el arco
        ! el gas no conservaba masa (flujo de volumen igual con densidades
        ! distintas).
        subroutine gas_adv(ii, jj, kk, in_, jn_, kn_, qin)
            integer, intent(in)  :: ii, jj, kk, in_, jn_, kn_
            real(dp), intent(in) :: qin
            if (.not. (cfg%gas_compressibility .and. cfg%solve_multiphase)) return
            if (qin <= 0.0_dp) return
            ! (auditoria 6, M6-1) solo donde la energia del gas se resuelve
            ! (alpha_g >= ALPHA_CUTOFF en las DOS celdas): en una celda sin gas
            ! T_g es rancia y el termino salia en -3.6e4 veces su volumen de
            ! gas (slag_chem_flow, capa de escoria)
            if (gas%alpha(ii,jj,kk) < ALPHA_CUTOFF .or. gas%alpha(in_,jn_,kn_) < ALPHA_CUTOFF) return
            ! (auditoria 7, M7-5) el caudal que agranda la cota, con la MISMA
            ! guardia: desde una vecina con gas evanescente la alpha de cara
            ! simetrica daba 1/2 alpha_P u_f A de caudal fantasma
            qin_g(ii,jj,kk) = qin_g(ii,jj,kk) + qin
            gadv(ii,jj,kk) = gadv(ii,jj,kk) + qin * (gas%rho(in_,jn_,kn_) - gas%rho(ii,jj,kk)) &
                                                  / max(gas%rho(ii,jj,kk), SMALL)
        end subroutine gas_adv

        ! Peso del liquido en la cara (ka,kb) [N/m3], con Boussinesq (F2.3)
        pure function liq_weight_f(ii, jj, ka, kb) result(w)
            integer, intent(in) :: ii, jj, ka, kb
            real(dp) :: w
            ! Solo liquido CONTINUO (act_l): ver nota en mod_momentum_3d
            ! (cell_w alli: con fuerza balanceada, mezcla continua por volumen
            ! de fluido)
            w = 0.5_dp * (cell_wp(ii, jj, ka) + cell_wp(ii, jj, kb))
        end function liq_weight_f

        pure real(dp) function cell_wp(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            ! (auditoria 6) mod_workspace::mix_cell_weight, la MISMA que momento
            cell_wp = mix_cell_weight(liq%alpha(ii,jj,kk), &
                liq_w(liq%rho(ii,jj,kk), liq%T(ii,jj,kk), cfg%beta_expansion, cfg%T_ref_boussinesq, ii, jj, kk), &
                gas%alpha(ii,jj,kk), gas%rho(ii,jj,kk), act_l(ii,jj,kk), lbf)
        end function cell_wp

        ! Flotacion relativa de la fase en el LECHO, en la cara (ka,kb)
        ! [N/m3]: bed_f (w_q,f - W_f). MISMA definicion que
        ! mod_momentum_3d::bed_rel_f (cara y gradiente de celda: el
        ! Rhie-Chow la cancela exactamente; A3-1/M3-1). El gas solo donde es
        ! fluido del acople (ws_bed_gas).
        pure real(dp) function bed_rel_fp(isg_, ii, jj, ka, kb)
            logical, intent(in) :: isg_
            integer, intent(in) :: ii, jj, ka, kb
            if (isg_) then
                bed_rel_fp = bed_rel_face(.true., ii, jj, ka, kb, &
                    liq%alpha(ii,jj,ka), liq%alpha(ii,jj,kb), gas%alpha(ii,jj,ka), gas%alpha(ii,jj,kb), &
                    GRAVITY * gas%rho(ii,jj,ka), GRAVITY * gas%rho(ii,jj,kb), liq_weight_f(ii, jj, ka, kb), lbf)
            else
                bed_rel_fp = bed_rel_face(.false., ii, jj, ka, kb, &
                    liq%alpha(ii,jj,ka), liq%alpha(ii,jj,kb), liq%alpha(ii,jj,ka), liq%alpha(ii,jj,kb), &
                    liq_w(liq%rho(ii,jj,ka), liq%T(ii,jj,ka), cfg%beta_expansion, cfg%T_ref_boussinesq, ii, jj, ka), &
                    liq_w(liq%rho(ii,jj,kb), liq%T(ii,jj,kb), cfg%beta_expansion, cfg%T_ref_boussinesq, ii, jj, kb), &
                    liq_weight_f(ii, jj, ka, kb), lbf)
            end if
        end function bed_rel_fp

        ! Gradiente vertical de celda que ve el GAS: caras sin el peso del
        ! liquido, media de las existentes (mismo esquema que momentum)
        pure function gas_gz(pfld, ii, jj, kk, okm, okp) result(g)
            real(dp), intent(in) :: pfld(-1:,-1:,-1:)
            integer, intent(in)  :: ii, jj, kk
            logical, intent(in)  :: okm, okp
            real(dp) :: g, gb, gt
            gb = 0.0_dp; gt = 0.0_dp
            if (okm) gb = (pfld(ii,jj,kk) - pfld(ii,jj,kk-1)) / (m%z(kk) - m%z(kk-1)) &
                          + liq_weight_f(ii, jj, kk-1, kk) + bed_rel_fp(grad_is_gas, ii, jj, kk-1, kk)
            if (okp) gt = (pfld(ii,jj,kk+1) - pfld(ii,jj,kk)) / (m%z(kk+1) - m%z(kk)) &
                          + liq_weight_f(ii, jj, kk, kk+1) + bed_rel_fp(grad_is_gas, ii, jj, kk, kk+1)
            if (okm .and. okp) then
                g = 0.5_dp * (gb + gt)
            else if (okp) then
                g = gt
            else if (okm) then
                g = gb
            else
                g = 0.0_dp
            end if
        end function gas_gz

        ! Vecina fluida SIN liquido continuo (superficie libre, D2.5): solo
        ! para los gradientes del LIQUIDO (grad_is_gas = .false.)
        pure logical function fs_cell(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            fs_cell = .false.
            if (grad_is_gas .or. .not. cfg%pc_fs_liquid_gradient) return
            if (.not. ws_liq_cont_valid) return
            fs_cell = pv_cell(ii, jj, kk) .and. .not. ws_liq_cont(ii,jj,kk)
        end function fs_cell

        ! La celda tiene presion de fluido definida? (Bug 16)
        pure logical function pv_cell(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            ! MISMA mascara de pared que el predictor de momento (ws_pv_active)
            ! para los gradientes de celda del Rhie-Chow y el corrector: el
            ! termino d_f (media de gradientes de celda - gradiente de cara)
            ! solo cancela el gradiente que llevo u* si es el mismo operador.
            ! Antes se usaba act_l/act_g DESPUES de F2.21/F2.31/E1b, y en las
            ! celdas que F2.31 saca del acople (piso del lecho) aparecian flujos
            ! de cara espurios (auditoria 12-oct-2026, A17). La conectividad de
            ! la matriz sigue siendo la del acople final (link/act).
            if (ws_pv_valid) then
                pv_cell = (m%cell_type(ii,jj,kk) /= 0) .and. ws_pv_active(ii,jj,kk)
            else
                pv_cell = (m%cell_type(ii,jj,kk) /= 0) .and. &
                          (act_l(ii,jj,kk) .or. act_g(ii,jj,kk))
            end if
            ! D2.2b: para el gradiente del LIQUIDO la celda sellada es pared
            if (liq_mask_on .and. .not. grad_is_gas) pv_cell = pv_cell .and. ws_pv_liq(ii,jj,kk)
        end function pv_cell

        ! Acumula la presion de una vecina CON fluido continuo (Neumann de
        ! pared para las celdas selladas; ver Bug 16)
        subroutine acc_nb(ii, jj, kk, psum, nnb)
            integer,  intent(in)    :: ii, jj, kk
            real(dp), intent(inout) :: psum
            integer,  intent(inout) :: nnb
            if (m%cell_type(ii,jj,kk) == 0) return
            if (.not. act_l(ii,jj,kk) .and. .not. act_g(ii,jj,kk)) return
            if (sealed(ii,jj,kk)) return
            psum = psum + sh%p(ii,jj,kk); nnb = nnb + 1
        end subroutine acc_nb

        !-----------------------------------------------------------------------
        ! Suma al Laplaciano compacto y a la divergencia Rhie-Chow la
        ! contribución de una fase (con su alpha, sus aP de momentum y sus
        ! velocidades)
        !-----------------------------------------------------------------------
        ! d_f = (alpha V/aP)_f (alpharAU de OpenFOAM, alpha/D de Liu 2024,
        ! F2.1): el predictor lleva -alpha grad p V, asi que la respuesta
        ! de la velocidad a la presion es alpha V/aP, no V/aP (era 1/alpha
        ! veces demasiado fuerte fuera de las celdas puras).
        subroutine add_phase_contribution(ph, aef, act, export, pf, gr, gth, gz, isg)
            type(phase_t), intent(in) :: ph
            ! Fraccion efectiva en los COEFICIENTES (F2.17): para el gas puede
            ! ser el canal residual donde todavia no hay gas. La masa y la
            ! compresibilidad siguen usando aef.
            real(dp), intent(in)      :: aef(-1:,-1:,-1:)
            logical, intent(in)       :: act(-1:,-1:,-1:)
            ! Fase gas: caras verticales sin el peso del liquido (F2.3)
            logical, intent(in)       :: isg
            ! Presion y gradientes de celda que ve ESTA fase (el gas lleva la
            ! correccion de superficie libre: gas_pgrad_z, F2.3)
            real(dp), intent(in)      :: pf(-1:,-1:,-1:)
            real(dp), intent(in)      :: gr(-1:,-1:,-1:), gth(-1:,-1:,-1:), gz(-1:,-1:,-1:)
            ! Guardar Q* y a_nb de las caras + (solo el liquido, F1)
            logical, intent(in)       :: export

            integer  :: ii, jj, kk, jjm, jjp
            real(dp) :: d_f, af, u_f, delta, fl, a_fs, q_fs, af_fs
            logical  :: fs_on, open_fs

            ! D2.6 (oct-2026): la SUPERFICIE LIBRE del liquido es una cara de
            ! liquido del Poisson, unilateral desde la celda de liquido (ver
            ! fs_face). Hasta aqui una cara liquido|gas no existia para el
            ! liquido: la superficie no podia subir por el Poisson (solo por
            ! derrame), una celda de liquido suspendida sobre gas no podia
            ! caer, y la velocidad vertical de un charco de una celda entre
            ! un poro lleno y el gas era invisible para la presion.
            fs_on = (.not. isg) .and. cfg%pc_fs_liquid_face .and. &
                    cfg%pc_fs_liquid_gradient .and. ws_liq_cont_valid

            do kk = kstart, kend
                do jj = jstart, jend
                    jjm = jj - 1; jjp = jj + 1
                    do ii = istart, iend
                        if (m%cell_type(ii,jj,kk) == 0) cycle
                        if (.not. act(ii,jj,kk)) then
                            ! D2.6: celda fluida SIN liquido continuo: recibe
                            ! las caras de superficie libre de sus vecinas de
                            ! liquido (lado simetrico de la matriz)
                            if (fs_on) then
                                if (fs_cell(ii,jj,kk)) call fs_gas_side(ii, jj, kk)
                            end if
                            cycle
                        end if

                        ! --- Cara Oeste (i-1/2) ---
                        if (link(act, ii-1, jj, kk)) then
                            d_f    = 0.5_dp * (aef(ii,jj,kk) * m%vol(ii,jj,kk) / max(ph%aP_ur(ii,jj,kk), SMALL) + &
                                               aef(ii-1,jj,kk) * m%vol(ii-1,jj,kk) / max(ph%aP_ur(ii-1,jj,kk), SMALL))
                            af = 0.5_dp * (aef(ii,jj,kk) + aef(ii-1,jj,kk))
                            delta  = m%r(ii) - m%r(ii-1)
                            u_f = 0.5_dp * (ph%ur(ii-1,jj,kk) + ph%ur(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gr(ii-1,jj,kk) + gr(ii,jj,kk)) &
                                         - (pf(ii,jj,kk) - pf(ii-1,jj,kk)) / delta)
                            fl = face_lim(isg, u_f, ii-1,jj,kk, ii,jj,kk)
                            if (fl > 0.0_dp) then
                            af = af * fl
                            aW(ii,jj,kk) = aW(ii,jj,kk) + af * d_f * m%Ar(ii-1,jj,kk) / delta
                            if (.not. isg) then
                                lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + af * d_f * m%Ar(ii-1,jj,kk) / delta
                                lcoef_r(ii,jj,kk) = lcoef_r(ii,jj,kk) + af * d_f * m%Ar(ii-1,jj,kk) / delta
                            end if
                            Su(ii,jj,kk) = Su(ii,jj,kk) + af * u_f * m%Ar(ii-1,jj,kk)
                            if (isg) call gas_adv(ii, jj, kk, ii-1, jj, kk,  af * u_f * m%Ar(ii-1,jj,kk))
                            flux_ref = flux_ref + abs(af * u_f * m%Ar(ii-1,jj,kk))
                            end if
                        else if (fs_on) then
                            if (fs_cell(ii-1,jj,kk)) then
                                call fs_face(ii, jj, kk, 1, -1, a_fs, q_fs, af_fs, open_fs)
                                if (open_fs) then
                                    aW(ii,jj,kk) = aW(ii,jj,kk) + a_fs
                                    lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + a_fs
                                    lcoef_r(ii,jj,kk) = lcoef_r(ii,jj,kk) + a_fs
                                    Su(ii,jj,kk) = Su(ii,jj,kk) + q_fs
                                    flux_ref = flux_ref + abs(q_fs)
                                end if
                            end if
                        end if

                        ! --- Cara Este (i+1/2) ---
                        if (link(act, ii+1, jj, kk)) then
                            d_f    = 0.5_dp * (aef(ii,jj,kk) * m%vol(ii,jj,kk) / max(ph%aP_ur(ii,jj,kk), SMALL) + &
                                               aef(ii+1,jj,kk) * m%vol(ii+1,jj,kk) / max(ph%aP_ur(ii+1,jj,kk), SMALL))
                            af = 0.5_dp * (aef(ii,jj,kk) + aef(ii+1,jj,kk))
                            delta  = m%r(ii+1) - m%r(ii)
                            u_f = 0.5_dp * (ph%ur(ii,jj,kk) + ph%ur(ii+1,jj,kk)) &
                                + d_f * (0.5_dp*(gr(ii,jj,kk) + gr(ii+1,jj,kk)) &
                                         - (pf(ii+1,jj,kk) - pf(ii,jj,kk)) / delta)
                            fl = face_lim(isg, u_f, ii,jj,kk, ii+1,jj,kk)
                            if (fl > 0.0_dp) then
                            af = af * fl
                            aE(ii,jj,kk) = aE(ii,jj,kk) + af * d_f * m%Ar(ii,jj,kk) / delta
                            if (.not. isg) then
                                lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + af * d_f * m%Ar(ii,jj,kk) / delta
                                lcoef_r(ii,jj,kk) = lcoef_r(ii,jj,kk) + af * d_f * m%Ar(ii,jj,kk) / delta
                            end if
                            Su(ii,jj,kk) = Su(ii,jj,kk) - af * u_f * m%Ar(ii,jj,kk)
                            if (isg) call gas_adv(ii, jj, kk, ii+1, jj, kk, -af * u_f * m%Ar(ii,jj,kk))
                            flux_ref = flux_ref + abs(af * u_f * m%Ar(ii,jj,kk))
                            if (export) then
                                Fs_r(ii,jj,kk) = af * u_f * m%Ar(ii,jj,kk)
                                ac_r(ii,jj,kk) = af * d_f * m%Ar(ii,jj,kk) / delta
                                ws_Fc_lk_r(ii,jj,kk) = 1
                                ws_Fc_af_r(ii,jj,kk) = af
                            end if
                            if (isg) then
                                Fg_r(ii,jj,kk) = af * u_f * m%Ar(ii,jj,kk)
                                ag_r(ii,jj,kk) = af * d_f * m%Ar(ii,jj,kk) / delta
                                ws_Fg_lk_r(ii,jj,kk) = 1
                            end if
                            end if
                        else if (fs_on) then
                            if (fs_cell(ii+1,jj,kk)) then
                                call fs_face(ii, jj, kk, 1, +1, a_fs, q_fs, af_fs, open_fs)
                                if (open_fs) then
                                    aE(ii,jj,kk) = aE(ii,jj,kk) + a_fs
                                    lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + a_fs
                                    lcoef_r(ii,jj,kk) = lcoef_r(ii,jj,kk) + a_fs
                                    Su(ii,jj,kk) = Su(ii,jj,kk) - q_fs
                                    flux_ref = flux_ref + abs(q_fs)
                                    if (export) then
                                        Fs_r(ii,jj,kk) = q_fs; ac_r(ii,jj,kk) = a_fs
                                        ws_Fc_lk_r(ii,jj,kk) = 1; ws_Fc_af_r(ii,jj,kk) = af_fs
                                    end if
                                end if
                            end if
                        end if

                        ! --- Cara Sur (j-1/2) ---
                        if (link(act, ii, jjm, kk)) then
                            d_f    = 0.5_dp * (aef(ii,jj,kk) * m%vol(ii,jj,kk) / max(ph%aP_uth(ii,jj,kk), SMALL) + &
                                               aef(ii,jjm,kk) * m%vol(ii,jjm,kk) / max(ph%aP_uth(ii,jjm,kk), SMALL))
                            af = 0.5_dp * (aef(ii,jj,kk) + aef(ii,jjm,kk))
                            delta  = m%r(ii) * (m%theta(jj) - m%theta(jjm))
                            u_f = 0.5_dp * (ph%uth(ii,jjm,kk) + ph%uth(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gth(ii,jjm,kk) + gth(ii,jj,kk)) &
                                         - (pf(ii,jj,kk) - pf(ii,jjm,kk)) / delta)
                            fl = face_lim(isg, u_f, ii,jjm,kk, ii,jj,kk)
                            if (fl > 0.0_dp) then
                            af = af * fl
                            aS(ii,jj,kk) = aS(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                            if (.not. isg) then
                                lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                                lcoef_th(ii,jj,kk) = lcoef_th(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                            end if
                            Su(ii,jj,kk) = Su(ii,jj,kk) + af * u_f * m%Ath(ii,jj,kk)
                            if (isg) call gas_adv(ii, jj, kk, ii, jjm, kk,  af * u_f * m%Ath(ii,jj,kk))
                            flux_ref = flux_ref + abs(af * u_f * m%Ath(ii,jj,kk))
                            end if
                        else if (fs_on) then
                            if (fs_cell(ii,jjm,kk)) then
                                call fs_face(ii, jj, kk, 2, -1, a_fs, q_fs, af_fs, open_fs)
                                if (open_fs) then
                                    aS(ii,jj,kk) = aS(ii,jj,kk) + a_fs
                                    lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + a_fs
                                    lcoef_th(ii,jj,kk) = lcoef_th(ii,jj,kk) + a_fs
                                    Su(ii,jj,kk) = Su(ii,jj,kk) + q_fs
                                    flux_ref = flux_ref + abs(q_fs)
                                end if
                            end if
                        end if

                        ! --- Cara Norte (j+1/2) ---
                        if (link(act, ii, jjp, kk)) then
                            d_f    = 0.5_dp * (aef(ii,jj,kk) * m%vol(ii,jj,kk) / max(ph%aP_uth(ii,jj,kk), SMALL) + &
                                               aef(ii,jjp,kk) * m%vol(ii,jjp,kk) / max(ph%aP_uth(ii,jjp,kk), SMALL))
                            af = 0.5_dp * (aef(ii,jj,kk) + aef(ii,jjp,kk))
                            delta  = m%r(ii) * (m%theta(jjp) - m%theta(jj))
                            u_f = 0.5_dp * (ph%uth(ii,jj,kk) + ph%uth(ii,jjp,kk)) &
                                + d_f * (0.5_dp*(gth(ii,jj,kk) + gth(ii,jjp,kk)) &
                                         - (pf(ii,jjp,kk) - pf(ii,jj,kk)) / delta)
                            fl = face_lim(isg, u_f, ii,jj,kk, ii,jjp,kk)
                            if (fl > 0.0_dp) then
                            af = af * fl
                            aN(ii,jj,kk) = aN(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                            if (.not. isg) then
                                lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                                lcoef_th(ii,jj,kk) = lcoef_th(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                            end if
                            Su(ii,jj,kk) = Su(ii,jj,kk) - af * u_f * m%Ath(ii,jj,kk)
                            if (isg) call gas_adv(ii, jj, kk, ii, jjp, kk, -af * u_f * m%Ath(ii,jj,kk))
                            flux_ref = flux_ref + abs(af * u_f * m%Ath(ii,jj,kk))
                            if (export) then
                                Fs_th(ii,jj,kk) = af * u_f * m%Ath(ii,jj,kk)
                                ac_th(ii,jj,kk) = af * d_f * m%Ath(ii,jj,kk) / delta
                                ws_Fc_lk_th(ii,jj,kk) = 1
                                ws_Fc_af_th(ii,jj,kk) = af
                            end if
                            if (isg) then
                                Fg_th(ii,jj,kk) = af * u_f * m%Ath(ii,jj,kk)
                                ag_th(ii,jj,kk) = af * d_f * m%Ath(ii,jj,kk) / delta
                                ws_Fg_lk_th(ii,jj,kk) = 1
                            end if
                            end if
                        else if (fs_on) then
                            if (fs_cell(ii,jjp,kk)) then
                                call fs_face(ii, jj, kk, 2, +1, a_fs, q_fs, af_fs, open_fs)
                                if (open_fs) then
                                    aN(ii,jj,kk) = aN(ii,jj,kk) + a_fs
                                    lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + a_fs
                                    lcoef_th(ii,jj,kk) = lcoef_th(ii,jj,kk) + a_fs
                                    Su(ii,jj,kk) = Su(ii,jj,kk) - q_fs
                                    flux_ref = flux_ref + abs(q_fs)
                                    if (export) then
                                        Fs_th(ii,jj,kk) = q_fs; ac_th(ii,jj,kk) = a_fs
                                        ws_Fc_lk_th(ii,jj,kk) = 1; ws_Fc_af_th(ii,jj,kk) = af_fs
                                    end if
                                end if
                            end if
                        end if

                        ! --- Cara Inferior (k-1/2) ---
                        if (link(act, ii, jj, kk-1)) then
                            d_f    = 0.5_dp * (aef(ii,jj,kk) * m%vol(ii,jj,kk) / max(ph%aP_uz(ii,jj,kk), SMALL) + &
                                               aef(ii,jj,kk-1) * m%vol(ii,jj,kk-1) / max(ph%aP_uz(ii,jj,kk-1), SMALL))
                            af = 0.5_dp * (aef(ii,jj,kk) + aef(ii,jj,kk-1))
                            delta  = m%z(kk) - m%z(kk-1)
                            u_f = 0.5_dp * (ph%uz(ii,jj,kk-1) + ph%uz(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gz(ii,jj,kk-1) + gz(ii,jj,kk)) &
                                         - (pf(ii,jj,kk) - pf(ii,jj,kk-1)) / delta &
                                         - merge(liq_weight_f(ii,jj,kk-1,kk) &
                                                 + bed_rel_fp(isg, ii,jj,kk-1,kk), 0.0_dp, isg .or. lbf))
                            fl = face_lim(isg, u_f, ii,jj,kk-1, ii,jj,kk)
                            if (fl > 0.0_dp) then
                            af = af * fl
                            aB(ii,jj,kk) = aB(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk-1) / delta
                            if (.not. isg) then
                                lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk-1) / delta
                                lcoef_z(ii,jj,kk) = lcoef_z(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk-1) / delta
                            end if
                            Su(ii,jj,kk) = Su(ii,jj,kk) + af * u_f * m%Az(ii,jj,kk-1)
                            if (isg) call gas_adv(ii, jj, kk, ii, jj, kk-1,  af * u_f * m%Az(ii,jj,kk-1))
                            flux_ref = flux_ref + abs(af * u_f * m%Az(ii,jj,kk-1))
                            end if
                        else if (fs_on) then
                            if (fs_cell(ii,jj,kk-1)) then
                                call fs_face(ii, jj, kk, 3, -1, a_fs, q_fs, af_fs, open_fs)
                                if (open_fs) then
                                    aB(ii,jj,kk) = aB(ii,jj,kk) + a_fs
                                    lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + a_fs
                                    lcoef_z(ii,jj,kk) = lcoef_z(ii,jj,kk) + a_fs
                                    Su(ii,jj,kk) = Su(ii,jj,kk) + q_fs
                                    flux_ref = flux_ref + abs(q_fs)
                                end if
                            end if
                        end if

                        ! --- Cara Superior (k+1/2) ---
                        if (link(act, ii, jj, kk+1)) then
                            d_f    = 0.5_dp * (aef(ii,jj,kk) * m%vol(ii,jj,kk) / max(ph%aP_uz(ii,jj,kk), SMALL) + &
                                               aef(ii,jj,kk+1) * m%vol(ii,jj,kk+1) / max(ph%aP_uz(ii,jj,kk+1), SMALL))
                            af = 0.5_dp * (aef(ii,jj,kk) + aef(ii,jj,kk+1))
                            delta  = m%z(kk+1) - m%z(kk)
                            u_f = 0.5_dp * (ph%uz(ii,jj,kk) + ph%uz(ii,jj,kk+1)) &
                                + d_f * (0.5_dp*(gz(ii,jj,kk) + gz(ii,jj,kk+1)) &
                                         - (pf(ii,jj,kk+1) - pf(ii,jj,kk)) / delta &
                                         - merge(liq_weight_f(ii,jj,kk,kk+1) &
                                                 + bed_rel_fp(isg, ii,jj,kk,kk+1), 0.0_dp, isg .or. lbf))
                            fl = face_lim(isg, u_f, ii,jj,kk, ii,jj,kk+1)
                            if (fl > 0.0_dp) then
                            af = af * fl
                            aT(ii,jj,kk) = aT(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk) / delta
                            if (.not. isg) then
                                lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk) / delta
                                lcoef_z(ii,jj,kk) = lcoef_z(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk) / delta
                            end if
                            Su(ii,jj,kk) = Su(ii,jj,kk) - af * u_f * m%Az(ii,jj,kk)
                            if (isg) call gas_adv(ii, jj, kk, ii, jj, kk+1, -af * u_f * m%Az(ii,jj,kk))
                            flux_ref = flux_ref + abs(af * u_f * m%Az(ii,jj,kk))
                            if (export) then
                                Fs_z(ii,jj,kk) = af * u_f * m%Az(ii,jj,kk)
                                ac_z(ii,jj,kk) = af * d_f * m%Az(ii,jj,kk) / delta
                                ws_Fc_lk_z(ii,jj,kk) = 1
                                ws_Fc_af_z(ii,jj,kk) = af
                            end if
                            if (isg) then
                                Fg_z(ii,jj,kk) = af * u_f * m%Az(ii,jj,kk)
                                ag_z(ii,jj,kk) = af * d_f * m%Az(ii,jj,kk) / delta
                                ws_Fg_lk_z(ii,jj,kk) = 1
                            end if
                            end if
                        else if (fs_on) then
                            if (fs_cell(ii,jj,kk+1)) then
                                call fs_face(ii, jj, kk, 3, +1, a_fs, q_fs, af_fs, open_fs)
                                if (open_fs) then
                                    aT(ii,jj,kk) = aT(ii,jj,kk) + a_fs
                                    lcoef(ii,jj,kk) = lcoef(ii,jj,kk) + a_fs
                                    lcoef_z(ii,jj,kk) = lcoef_z(ii,jj,kk) + a_fs
                                    Su(ii,jj,kk) = Su(ii,jj,kk) - q_fs
                                    flux_ref = flux_ref + abs(q_fs)
                                    if (export) then
                                        Fs_z(ii,jj,kk) = q_fs; ac_z(ii,jj,kk) = a_fs
                                        ws_Fc_lk_z(ii,jj,kk) = 1; ws_Fc_af_z(ii,jj,kk) = af_fs
                                    end if
                                end if
                            end if
                        end if
                    end do
                end do
            end do
        end subroutine add_phase_contribution

        !-----------------------------------------------------------------------
        ! D2.6: cara de SUPERFICIE LIBRE del liquido entre la celda de liquido
        ! continuo L y su vecina fluida sin liquido continuo N (gas, gas con
        ! niebla), en la direccion dir (1 r, 2 theta, 3 z) y el lado sgn
        ! (+1: N es la vecina +, -1: la vecina -). Rhie-Chow UNILATERAL desde
        ! L con el MISMO gradiente de superficie libre que el predictor
        ! (D2.5: presion de N en la cara, distancia centro-cara):
        !     u_f = u_L + d_L [ g_L - (p_N - p_L)/(sgn delta) ],   d_L = alpha_L V_L/aP_L
        ! (con el gradiente unilateral de L el corchete es cero: u_f = u_L,
        ! la velocidad de la celda es la velocidad de su superficie).
        ! Coeficiente a = alpha_L d_L A/delta; flujo Q = alpha_L u_f A
        ! (orientado hacia +). La cara es DONANTE: solo cede liquido de L a N
        ! (sgn u_f >= 0); nada entra desde N, que no tiene liquido continuo.
        ! La cara SUPERIOR solo se abre con L LLENA (fs_full): el liquido se
        ! estratifica dentro de la celda y su superficie no toca la cara
        ! superior hasta que no queda gas. Hueco de la receptora (F2.8) y
        ! limitador (D2.2) como en cualquier cara (face_lim).
        ! Lo que no se puede hacer: la media simetrica 1/2(u_L + u_N): u_N es
        ! el drift del liquido disperso de la celda de gas (-49.7 m/s de
        ! sedimentacion), el caudal fantasma de F2.24.
        !-----------------------------------------------------------------------
        subroutine fs_face(iL, jL, kL, dir, sgn, a, q, afd, open)
            integer,  intent(in)  :: iL, jL, kL, dir, sgn
            real(dp), intent(out) :: a, q, afd
            logical,  intent(out) :: open
            integer  :: iN, jN, kN
            real(dp) :: dL, delta, area, u_f, fl
            a = 0.0_dp; q = 0.0_dp; afd = 0.0_dp; open = .false.
            iN = iL; jN = jL; kN = kL
            select case (dir)
            case (1)
                iN = iL + sgn
                dL = liq%alpha(iL,jL,kL) * m%vol(iL,jL,kL) / max(liq%aP_ur(iL,jL,kL), SMALL)
                if (sgn > 0) then
                    delta = m%rf(iL) - m%r(iL);  area = m%Ar(iL,jL,kL)
                else
                    delta = m%r(iL) - m%rf(iL-1); area = m%Ar(iL-1,jL,kL)
                end if
                u_f = liq%ur(iL,jL,kL) + dL * (gpr(iL,jL,kL) &
                      - (sh%p(iN,jN,kN) - sh%p(iL,jL,kL)) / (real(sgn,dp) * delta))
            case (2)
                jN = jL + sgn
                dL = liq%alpha(iL,jL,kL) * m%vol(iL,jL,kL) / max(liq%aP_uth(iL,jL,kL), SMALL)
                if (sgn > 0) then
                    delta = m%r(iL) * (m%thetaf(jL) - m%theta(jL))
                else
                    delta = m%r(iL) * (m%theta(jL) - m%thetaf(jL-1))
                end if
                area = m%Ath(iL,jL,kL)
                u_f = liq%uth(iL,jL,kL) + dL * (gpth(iL,jL,kL) &
                      - (sh%p(iN,jN,kN) - sh%p(iL,jL,kL)) / (real(sgn,dp) * delta))
            case default
                kN = kL + sgn
                dL = liq%alpha(iL,jL,kL) * m%vol(iL,jL,kL) / max(liq%aP_uz(iL,jL,kL), SMALL)
                if (sgn > 0) then
                    delta = m%zf(kL) - m%z(kL);  area = m%Az(iL,jL,kL)
                else
                    delta = m%z(kL) - m%zf(kL-1); area = m%Az(iL,jL,kL-1)
                end if
                u_f = liq%uz(iL,jL,kL) + dL * (gpz(iL,jL,kL) &
                      - (sh%p(iN,jN,kN) - sh%p(iL,jL,kL)) / (real(sgn,dp) * delta))
            end select
            if (delta <= 0.0_dp) return
            ! Donante: solo de L hacia N
            open = (real(sgn,dp) * u_f >= 0.0_dp)
            if (.not. open) return
            ! Cara superior: solo con L llena
            if (dir == 3 .and. sgn > 0) open = fs_full(iL, jL, kL)
            if (.not. open) return
            ! Hueco de la receptora (F2.8) y limitador (D2.2): (lo, hi) por orientacion
            if (sgn > 0) then
                fl = face_lim(.false., u_f, iL,jL,kL, iN,jN,kN)
            else
                fl = face_lim(.false., u_f, iN,jN,kN, iL,jL,kL)
            end if
            open = (fl > 0.0_dp)
            if (.not. open) return
            afd = liq%alpha(iL,jL,kL) * fl
            a = afd * dL * area / delta
            q = afd * u_f * area
        end subroutine fs_face

        ! Celda de liquido LLENA (D2.6): sin gas por encima del residual. En
        ! el lecho, hueco de poro agotado (ws_liq_room); fuera, gas < eps.
        pure logical function fs_full(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            fs_full = (gas%alpha(ii,jj,kk) <= FS_FULL_EPS)
            if (ws_liq_room_valid) fs_full = fs_full .or. (ws_liq_room(ii,jj,kk) <= 1.0e-4_dp)
        end function fs_full

        ! Lado del GAS de las caras de superficie libre (D2.6): la celda G
        ! (fluida, sin liquido continuo) recibe el coeficiente simetrico y el
        ! flujo de cada vecina de liquido continuo L. Las caras + de G
        ! (vecina al Este/Norte/Tope) las exporta G, como cualquier cara +.
        subroutine fs_gas_side(iG, jG, kG)
            integer, intent(in) :: iG, jG, kG
            real(dp) :: a, q, afd
            logical  :: op
            ! r
            if (link(act_l, iG-1, jG, kG)) then
                call fs_face(iG-1, jG, kG, 1, +1, a, q, afd, op)
                if (op) then
                    aW(iG,jG,kG) = aW(iG,jG,kG) + a
                    Su(iG,jG,kG) = Su(iG,jG,kG) + q
                    flux_ref = flux_ref + abs(q)
                end if
            end if
            if (link(act_l, iG+1, jG, kG)) then
                call fs_face(iG+1, jG, kG, 1, -1, a, q, afd, op)
                if (op) then
                    aE(iG,jG,kG) = aE(iG,jG,kG) + a
                    Su(iG,jG,kG) = Su(iG,jG,kG) - q
                    flux_ref = flux_ref + abs(q)
                    Fs_r(iG,jG,kG) = q; ac_r(iG,jG,kG) = a
                    ws_Fc_lk_r(iG,jG,kG) = 1; ws_Fc_af_r(iG,jG,kG) = afd
                end if
            end if
            ! theta
            if (link(act_l, iG, jG-1, kG)) then
                call fs_face(iG, jG-1, kG, 2, +1, a, q, afd, op)
                if (op) then
                    aS(iG,jG,kG) = aS(iG,jG,kG) + a
                    Su(iG,jG,kG) = Su(iG,jG,kG) + q
                    flux_ref = flux_ref + abs(q)
                end if
            end if
            if (link(act_l, iG, jG+1, kG)) then
                call fs_face(iG, jG+1, kG, 2, -1, a, q, afd, op)
                if (op) then
                    aN(iG,jG,kG) = aN(iG,jG,kG) + a
                    Su(iG,jG,kG) = Su(iG,jG,kG) - q
                    flux_ref = flux_ref + abs(q)
                    Fs_th(iG,jG,kG) = q; ac_th(iG,jG,kG) = a
                    ws_Fc_lk_th(iG,jG,kG) = 1; ws_Fc_af_th(iG,jG,kG) = afd
                end if
            end if
            ! z
            if (link(act_l, iG, jG, kG-1)) then
                call fs_face(iG, jG, kG-1, 3, +1, a, q, afd, op)
                if (op) then
                    aB(iG,jG,kG) = aB(iG,jG,kG) + a
                    Su(iG,jG,kG) = Su(iG,jG,kG) + q
                    flux_ref = flux_ref + abs(q)
                end if
            end if
            if (link(act_l, iG, jG, kG+1)) then
                call fs_face(iG, jG, kG+1, 3, -1, a, q, afd, op)
                if (op) then
                    aT(iG,jG,kG) = aT(iG,jG,kG) + a
                    Su(iG,jG,kG) = Su(iG,jG,kG) - q
                    flux_ref = flux_ref + abs(q)
                    Fs_z(iG,jG,kG) = q; ac_z(iG,jG,kG) = a
                    ws_Fc_lk_z(iG,jG,kG) = 1; ws_Fc_af_z(iG,jG,kG) = afd
                end if
            end if
        end subroutine fs_gas_side



        ! Gradientes de celda de un campo de presion (ver arriba)
        subroutine cell_gradients(pfld, isg, gr, gth, gz)
            real(dp), intent(in)  :: pfld(-1:,-1:,-1:)
            ! Gas: gradiente vertical sin el peso del liquido (F2.3)
            logical,  intent(in)  :: isg
            real(dp), intent(out) :: gr(-1:,-1:,-1:), gth(-1:,-1:,-1:), gz(-1:,-1:,-1:)
            gr = 0.0_dp; gth = 0.0_dp; gz = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1; jp = j + 1
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    ! Gradientes con las celdas SIN fluido tratadas como
                    ! pared (Bug 16): su presion no es de fluido y entraba
                    ! al termino de Rhie-Chow del propio Poisson.
                    ! D2.5: para el LIQUIDO, la vecina fluida sin liquido
                    ! continuo (superficie libre) aporta su presion en la cara
                    gr(i,j,k) = pgrad_fs(pfld(i-1,j,k), pfld(i,j,k), pfld(i+1,j,k), &
                                       m%r(i-1), m%r(i), m%r(i+1), &
                                       (i > istart .or. .not. at_rmin) .and. pv_cell(i-1,j,k), &
                                       (i < iend   .or. .not. at_rmax) .and. pv_cell(i+1,j,k), &
                                       fs_cell(i-1,j,k), fs_cell(i+1,j,k), m%rf(i-1), m%rf(i))

                    gth(i,j,k) = pgrad_fs(pfld(i,jm,k), pfld(i,j,k), pfld(i,jp,k), &
                                        m%r(i) * m%theta(jm), m%r(i) * m%theta(j), &
                                        m%r(i) * m%theta(jp), &
                                        pv_cell(i,jm,k), pv_cell(i,jp,k), &
                                        fs_cell(i,jm,k), fs_cell(i,jp,k), &
                                        m%r(i) * m%thetaf(jm), m%r(i) * m%thetaf(j))

                    gz(i,j,k) = pgrad_fs(pfld(i,j,k-1), pfld(i,j,k), pfld(i,j,k+1), &
                                       m%z(k-1), m%z(k), m%z(k+1), &
                                       (k > kstart .or. .not. at_zmin) .and. pv_cell(i,j,k-1), &
                                       (k < kend   .or. .not. at_zmax) .and. pv_cell(i,j,k+1), &
                                       fs_cell(i,j,k-1), fs_cell(i,j,k+1), m%zf(k-1), m%zf(k))
                    if (isg .or. lbf) gz(i,j,k) = gas_gz(pfld, i, j, k, &
                                       (k > kstart .or. .not. at_zmin) .and. pv_cell(i,j,k-1), &
                                       (k < kend   .or. .not. at_zmax) .and. pv_cell(i,j,k+1))
                end do
            end do
        end do

        call mpi_exchange_halos_3d(gr,  m%topo)
        call mpi_exchange_halos_3d(gth, m%topo)
        call mpi_exchange_halos_3d(gz,  m%topo)
        end subroutine cell_gradients

        ! Cara del liquido ABIERTA en el Poisson (F2.8): cerrada (a = 0,
        ! Q* = 0, simetrico) si la celda receptora, segun el signo de u_f,
        ! es una celda del lecho sin hueco de poro (ws_liq_room <= eps). Asi
        ! la ecuacion de presion dice lo mismo que el limitador. El gas y
        ! las celdas de bano puro (hueco 1 por definicion) no se tocan.
        pure logical function face_open(isg, u_f, room_neg, room_pos)
            logical,  intent(in) :: isg
            real(dp), intent(in) :: u_f, room_neg, room_pos
            real(dp), parameter :: ROOM_EPS = 1.0e-4_dp
            face_open = .true.
            ! Plan E E1 (oct-2026): una celda del lecho con el poro LLENO es
            ! un medio poroso incompresible, no una pared. Sus caras de
            ! liquido quedan abiertas y su fila, sin almacenamiento, impone
            ! div(alpha_l u_l) = 0: la presion se propaga por el lecho
            ! saturado (continuacion hidrostatica) y el liquido lo atraviesa
            ! a la velocidad de Darcy. Con el cierre F2.8 el lecho inundado
            ! era pared (F2.29: Neumann), la columna de encima leia 1/2 g y
            ! caia contra un piso incompresible: golpe de ariete de MPa
            ! (Plan D D2.2, sonda PROBE-MOM; PLAN_E seccion 2).
            if (cfg%pc_sat_open .or. cfg%pc_gas_spring) return
            if (isg .or. .not. ws_liq_room_valid) return
            if (u_f > 0.0_dp .and. room_pos <= ROOM_EPS) face_open = .false.
            if (u_f < 0.0_dp .and. room_neg <= ROOM_EPS) face_open = .false.
        end function face_open

        ! Factor de la cara del liquido en el Poisson (Plan D D2.2): la
        ! fraccion de la entrada que CUPO en la celda receptora (segun el
        ! signo de u_f) en el ultimo transporte de alpha de ESTE paso.
        ! Escala coeficiente y Q* a la vez (la ecuacion de presion pide por
        ! esa cara exactamente lo que el limitador dejara pasar: el poro
        ! lleno deja de ser un "numerical dead end" que solo la presion
        ! puede cerrar). 0 = cara cerrada (F2.8). 1 = sin limitador.
        function face_lim(isg, u_f, in_, jn_, kn_, ip_, jp_, kp_) result(fl)
            logical,  intent(in) :: isg
            real(dp), intent(in) :: u_f
            integer,  intent(in) :: in_, jn_, kn_, ip_, jp_, kp_
            real(dp) :: fl
            fl = 1.0_dp
            if (isg) return
            if (.not. face_open(isg, u_f, rm(in_,jn_,kn_), rm(ip_,jp_,kp_))) then
                fl = 0.0_dp
                return
            end if
            if (.not. cfg%pc_limiter_faces) return
            if (.not. ws_lim_step_valid) return
            if (ws_lim_step_id /= probe_current_step()) return
            ! Cierre BINARIO (D2.2c): la cara hacia una celda cuya entrada
            ! pedida NO cupo en mas de (1 - pc_lim_dead) se cierra del todo
            ! (a = 0, Q* = 0). El escalado continuo (D2.2) dejaba la celda
            ! con caras residuales: no quedaba sellada, el momento de la
            ! donante seguia diferenciando a traves de ella y cayendo.
            ! Con el cierre binario la celda muerta se sella, D2.2b la vuelve
            ! pared y la columna de arriba se queda hidrostatica.
            if (u_f > 0.0_dp) then
                if (ws_lim_step(ip_,jp_,kp_) < cfg%pc_lim_dead) fl = 0.0_dp
            else if (u_f < 0.0_dp) then
                if (ws_lim_step(in_,jn_,kn_) < cfg%pc_lim_dead) fl = 0.0_dp
            end if
        end function face_lim

        pure function rm(ii, jj, kk) result(r)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: r
            r = ws_liq_room(ii,jj,kk)
        end function rm

        ! Conductancia de una cara del gas en el Poisson: alpha_f d_f A/delta
        pure function gcond(d1, d2, a1, a2, area, dl) result(c)
            real(dp), intent(in) :: d1, d2, a1, a2, area, dl
            real(dp) :: c
            c = 0.5_dp * (a1 + a2) * 0.5_dp * (d1 + d2) * area / max(dl, SMALL)
        end function gcond

        subroutine exchange_logical_halos_p(msk)
            logical, intent(inout) :: msk(-1:,-1:,-1:)
            real(dp), allocatable :: tmp(:,:,:)
            allocate(tmp(lbound(msk,1):ubound(msk,1), lbound(msk,2):ubound(msk,2), lbound(msk,3):ubound(msk,3)))
            tmp = merge(1.0_dp, 0.0_dp, msk)
            call mpi_exchange_halos_3d(tmp, m%topo)
            msk = tmp > 0.5_dp
            deallocate(tmp)
        end subroutine exchange_logical_halos_p

        ! Cara con flujo de ESTA fase: vecino activo en el acople
        logical function link(act, ii, jj, kk)
            logical, intent(in) :: act(-1:,-1:,-1:)
            integer, intent(in) :: ii, jj, kk
            link = (m%cell_type(ii,jj,kk) /= 0) .and. act(ii,jj,kk)
        end function link

    end subroutine solve_pressure_correction

    !---------------------------------------------------------------------------
    ! Correct velocities using pressure correction gradient (esténcil central
    ! de celda; el suavizado de cara lo aporta Rhie-Chow en la divergencia)
    !---------------------------------------------------------------------------
    subroutine correct_velocities(ph, sh, m, act, pv, fs, consistent, op_r, op_th, op_z, use_fs)
        type(phase_t), intent(inout) :: ph
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        logical, intent(in)  :: act(-1:,-1:,-1:)
        ! D2.6: celda con presion de fluido para ESTA fase (pared si no, Bug
        ! 16/D2.2b) y vecina de superficie libre (D2.5, solo liquido): las
        ! MISMAS mascaras que uso el predictor de momento de este outer
        logical, intent(in)  :: pv(-1:,-1:,-1:), fs(-1:,-1:,-1:)
        ! .false. = estencil central crudo (anterior a D2.6)
        logical, intent(in)  :: consistent
        ! D2.6 regla cinematica (solo liquido): caras abiertas por direccion;
        ! sin cara abierta la componente queda en cero
        logical, intent(in), optional :: op_r(-1:,-1:,-1:), op_th(-1:,-1:,-1:), op_z(-1:,-1:,-1:)
        logical, intent(in), optional :: use_fs

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        ! d = alpha V/aP (F2.1): mismo operador que el predictor (-alpha grad p V)
        real(dp) :: d_coeff, g, gb, gt
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax
        logical  :: skip_r, skip_z, okm, okp, fsm, fsp, wfs, kin

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        ! Correcciones omitidas SOLO en fronteras físicas; en interfaces de
        ! rank se usan los halos de pp (hallazgo 3.6)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)
        wfs = .true.
        if (present(use_fs)) wfs = use_fs
        kin = present(op_r) .and. present(op_th) .and. present(op_z)

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    ! Sin corrección bajo el umbral hidrodinámico (C2.2)
                    if (.not. act(i,j,k)) cycle

                    if (.not. consistent) then
                        ! Estencil con las MISMAS paredes que el predictor (Bug 16:
                        ! celdas sin fluido, tazon, selladas -> diferencia
                        ! unilateral; pgrad), sin la superficie libre de D2.6.
                        ! Antes era el central crudo y leia pp = 0 de esas celdas
                        ! (auditoria 12-oct-2026, A16)
                        skip_r = (i == istart .and. at_rmin) .or. &
                                 (i == iend   .and. at_rmax)
                        if (.not. skip_r .and. abs(ph%aP_ur(i,j,k)) > SMALL) then
                            d_coeff = ph%alpha(i,j,k) * m%vol(i,j,k) / ph%aP_ur(i,j,k)
                            ph%ur(i,j,k) = ph%ur(i,j,k) - d_coeff * &
                                pgrad(sh%pp(i-1,j,k), sh%pp(i,j,k), sh%pp(i+1,j,k), &
                                      m%r(i-1), m%r(i), m%r(i+1), &
                                      (i > istart .or. .not. at_rmin) .and. pv(i-1,j,k), &
                                      (i < iend .or. .not. at_rmax) .and. pv(i+1,j,k))
                        end if
                        if (abs(ph%aP_uth(i,j,k)) > SMALL) then
                            d_coeff = ph%alpha(i,j,k) * m%vol(i,j,k) / ph%aP_uth(i,j,k)
                            ph%uth(i,j,k) = ph%uth(i,j,k) - d_coeff * &
                                pgrad(sh%pp(i,jm,k), sh%pp(i,j,k), sh%pp(i,jp,k), &
                                      m%r(i) * m%theta(jm), m%r(i) * m%theta(j), &
                                      m%r(i) * m%theta(jp), pv(i,jm,k), pv(i,jp,k))
                        end if
                        skip_z = (k == kstart .and. at_zmin) .or. &
                                 (k == kend   .and. at_zmax)
                        if (.not. skip_z .and. abs(ph%aP_uz(i,j,k)) > SMALL) then
                            d_coeff = ph%alpha(i,j,k) * m%vol(i,j,k) / ph%aP_uz(i,j,k)
                            ph%uz(i,j,k) = ph%uz(i,j,k) - d_coeff * &
                                pgrad(sh%pp(i,j,k-1), sh%pp(i,j,k), sh%pp(i,j,k+1), &
                                      m%z(k-1), m%z(k), m%z(k+1), &
                                      (k > kstart .or. .not. at_zmin) .and. pv(i,j,k-1), &
                                      (k < kend   .or. .not. at_zmax) .and. pv(i,j,k+1))
                        end if
                    else
                        ! D2.6: el MISMO operador que el predictor (pgrad_fs con
                        ! paredes unilaterales y distancia a la cara en la
                        ! superficie libre; el gas, media de las caras que
                        ! existen en z como gas_pgrad_z). Con el estencil
                        ! central crudo, la celda de superficie no sentia su
                        ! propio pp (pp_N - pp_B no la contiene) y las paredes
                        ! entraban con pp = 0.
                        ! (en las fronteras fisicas la componente normal no se
                        ! resuelve — aP de relleno 1.0 — y tampoco se corrige,
                        ! como antes; en la celda del eje d = alpha V/1 daba
                        ! 1e3 m/s con pp de kPa)
                        skip_r = (i == istart .and. at_rmin) .or. &
                                 (i == iend   .and. at_rmax)
                        skip_z = (k == kstart .and. at_zmin) .or. &
                                 (k == kend   .and. at_zmax)
                        ! u_r
                        if (.not. skip_r .and. abs(ph%aP_ur(i,j,k)) > SMALL) then
                            if (kin) then
                                if (.not. op_r(i,j,k)) then
                                    ph%ur(i,j,k) = 0.0_dp
                                    goto 10
                                end if
                            end if
                            okm = (i > istart .or. .not. at_rmin) .and. pv(i-1,j,k)
                            okp = (i < iend .or. .not. at_rmax) .and. pv(i+1,j,k)
                            fsm = wfs .and. fs(i-1,j,k); fsp = wfs .and. fs(i+1,j,k)
                            g = pgrad_fs(sh%pp(i-1,j,k), sh%pp(i,j,k), sh%pp(i+1,j,k), &
                                         m%r(i-1), m%r(i), m%r(i+1), okm, okp, fsm, fsp, &
                                         m%rf(i-1), m%rf(i))
                            d_coeff = ph%alpha(i,j,k) * m%vol(i,j,k) / ph%aP_ur(i,j,k)
                            ph%ur(i,j,k) = ph%ur(i,j,k) - d_coeff * g
                        end if
10                      continue
                        ! u_theta
                        if (abs(ph%aP_uth(i,j,k)) > SMALL) then
                            if (kin) then
                                if (.not. op_th(i,j,k)) then
                                    ph%uth(i,j,k) = 0.0_dp
                                    goto 20
                                end if
                            end if
                            okm = pv(i,jm,k); okp = pv(i,jp,k)
                            fsm = wfs .and. fs(i,jm,k); fsp = wfs .and. fs(i,jp,k)
                            g = pgrad_fs(sh%pp(i,jm,k), sh%pp(i,j,k), sh%pp(i,jp,k), &
                                         m%r(i) * m%theta(jm), m%r(i) * m%theta(j), &
                                         m%r(i) * m%theta(jp), okm, okp, fsm, fsp, &
                                         m%r(i) * m%thetaf(jm), m%r(i) * m%thetaf(j))
                            d_coeff = ph%alpha(i,j,k) * m%vol(i,j,k) / ph%aP_uth(i,j,k)
                            ph%uth(i,j,k) = ph%uth(i,j,k) - d_coeff * g
                        end if
20                      continue
                        ! u_z
                        if (.not. skip_z .and. abs(ph%aP_uz(i,j,k)) > SMALL) then
                            if (kin) then
                                if (.not. op_z(i,j,k)) then
                                    ph%uz(i,j,k) = 0.0_dp
                                    goto 30
                                end if
                            end if
                            okm = (k > kstart .or. .not. at_zmin) .and. pv(i,j,k-1)
                            okp = (k < kend   .or. .not. at_zmax) .and. pv(i,j,k+1)
                            if (wfs) then
                                g = pgrad_fs(sh%pp(i,j,k-1), sh%pp(i,j,k), sh%pp(i,j,k+1), &
                                             m%z(k-1), m%z(k), m%z(k+1), okm, okp, &
                                             fs(i,j,k-1), fs(i,j,k+1), m%zf(k-1), m%zf(k))
                            else
                                ! gas: media de las caras existentes (gas_pgrad_z sin pesos)
                                gb = 0.0_dp; gt = 0.0_dp
                                if (okm) gb = (sh%pp(i,j,k) - sh%pp(i,j,k-1)) / (m%z(k) - m%z(k-1))
                                if (okp) gt = (sh%pp(i,j,k+1) - sh%pp(i,j,k)) / (m%z(k+1) - m%z(k))
                                if (okm .and. okp) then
                                    g = 0.5_dp * (gb + gt)
                                else if (okp) then
                                    g = gt
                                else if (okm) then
                                    g = gb
                                else
                                    g = 0.0_dp
                                end if
                            end if
                            d_coeff = ph%alpha(i,j,k) * m%vol(i,j,k) / ph%aP_uz(i,j,k)
                            ph%uz(i,j,k) = ph%uz(i,j,k) - d_coeff * g
                        end if
30                      continue
                    end if
                end do
            end do
        end do

    end subroutine correct_velocities

    !---------------------------------------------------------------------------
    ! Presion de una abertura del techo con reflujo (pc_outlet_total_pressure):
    ! objetivo p0 - 1/2 rho u_in^2 con u_in = velocidad de ENTRADA (<= 0: el gas
    ! sale y el objetivo es p0), u_in acotada a U_GAS_MAX y el objetivo a
    ! -P_HYDRO_CAP; sub-relajado con a_p sobre p_old en forma incremental (exacta
    ! si p_old ya es el objetivo: en reposo el ancla no se mueve ni 1 ulp).
    ! Con NaN en p0, rho o u_in el resultado es NaN (max() de gfortran lo
    ! tragaria): quien llama no lo escribe (test_outlet_total_pressure)
    !---------------------------------------------------------------------------
    pure real(dp) function outlet_total_pressure(p_old, p0, rho, u_in, a_p) result(p_new)
        real(dp), intent(in) :: p_old, p0, rho, u_in, a_p
        real(dp) :: u, t
        u = min(U_GAS_MAX, max(0.0_dp, u_in))
        t = p0 - 0.5_dp * rho * u**2
        if (t == t) t = max(-P_HYDRO_CAP, t)
        if (u_in /= u_in) t = u_in
        p_new = p_old + a_p * (t - p_old)
    end function outlet_total_pressure

    !---------------------------------------------------------------------------
    ! Velocidad de ENTRADA por la abertura de una celda de salida del techo: la
    ! masa que la celda inyecta netamente al dominio por sus caras (fe, fn de
    ! cara +; fw, fs de cara -; fb la cara inferior, todos positivos hacia +;
    ! la abertura absorbe el desbalance, = -m_gas_out del audit) sobre rho y el
    ! area de la abertura (vol/dz). > 0 entra gas, < 0 sale
    !---------------------------------------------------------------------------
    pure real(dp) function outlet_inflow_velocity(fe, fw, fn, fs, fb, rho, vol, dz) result(u_in)
        real(dp), intent(in) :: fe, fw, fn, fs, fb, rho, vol, dz
        u_in = (fe - fw + fn - fs - fb) * dz / max(rho * vol, SMALL)
    end function outlet_inflow_velocity

end module mod_pressure_3d
