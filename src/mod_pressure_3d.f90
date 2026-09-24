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
!===============================================================================
module mod_pressure_3d
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
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

    ! Término acústico low-Mach: rho(p,T) = rho(T)*(1 + p'/P0) aporta
    ! d(alpha*rho)/dp' * V/dt = alpha*rho/P0 * V/dt a la DIAGONAL del
    ! Poisson. Acota la respuesta de pp (los picos se absorben como
    ! compresión física del gas en vez de exigir velocidades imposibles) y
    ! es la pieza que faltaba para que el lazo externo converja a CFL alto:
    ! sin él, n1/n4 divergían (p -> 2e9 Pa) mientras n8 encontraba el
    ! cuasi-estado por suerte de barrido. La corrección de densidad
    ! asociada (~pp/P0 ~ 1%) se DESCARTA tras el paso — aproximación
    ! documentada, pequeña frente al agujero EOS (~70%) que este acople
    ! elimina.
    real(dp), parameter :: P0_THERMO = 101325.0_dp

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

    subroutine solve_pressure_correction(liq, gas, gas_T_old, sh, m, cfg, &
                                          residual)
        use mod_workspace, only: ensure_workspace, aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su, ws_liq_cont, ws_liq_cont_valid, &
            ws_Fc_r, ws_Fc_th, ws_Fc_z, ws_Fc_lk_r, ws_Fc_lk_th, ws_Fc_lk_z, ws_Fc_valid, &
            ws_pcorr_g, ws_pcorr_valid
        type(phase_t), intent(inout) :: liq, gas
        ! T del gas del paso anterior: término de COMPRESIBILIDAD del gas
        ! ideal, -alpha_g*(rho(T)-rho(T_old))/dt*V. Sin él, el Poisson
        ! forzaba div=0 sobre un gas que DEBE expandirse al calentarse
        ! (rho ~ 1/T cae ~80x bajo el arco) -> presiones ficticias
        ! crecientes -> divergencia (medido p -> 1e18).
        real(dp), intent(in)         :: gas_T_old(-1:,-1:,-1:)
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
        ! Flujo de Rhie-Chow F* y coeficiente a_nb del LIQUIDO en las caras +
        ! (este/norte/tope) de cada celda propia, para exportar el flujo
        ! conservativo F = F* + a_nb (pp_P - pp_nb) tras el CG (Bug 19, F1)
        real(dp), allocatable :: Fs_r(:,:,:), Fs_th(:,:,:), Fs_z(:,:,:)
        real(dp), allocatable :: ac_r(:,:,:), ac_th(:,:,:), ac_z(:,:,:)
        integer  :: n_iter_cg
        real(dp) :: cg_res
        ! Residual de CONTINUIDAD del iterado entrante: desbalance de VOLUMEN
        ! sum |Su| (la fuente del Poisson es -div de los flujos volumetricos
        ! de Rhie-Chow mas las fuentes fisicas) normalizado por el flujo
        ! volumetrico total por caras. El residual del CG que se devolvia antes mide la solucion
        ! de pp, no si u* conserva masa (siempre <= SOR_TOL_PRESSURE).
        real(dp) :: flux_ref, sum_su, tmp
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        call ensure_workspace(m)
        allocate(gpr, mold=sh%pp); allocate(gpth, mold=sh%pp)
        allocate(gpz, mold=sh%pp)
        allocate(act_l(lbound(sh%pp,1):ubound(sh%pp,1), lbound(sh%pp,2):ubound(sh%pp,2), &
                       lbound(sh%pp,3):ubound(sh%pp,3)))
        allocate(act_g, mold=act_l)
        allocate(Fs_r, Fs_th, Fs_z, ac_r, ac_th, ac_z, mold=sh%pp)
        ! Completos a cero (halos incluidos): las caras de frontera fisica
        ! no las escribe nadie y el transporte de alpha las lee (leccion v10)
        Fs_r = 0.0_dp; Fs_th = 0.0_dp; Fs_z = 0.0_dp
        ac_r = 0.0_dp; ac_th = 0.0_dp; ac_z = 0.0_dp
        ws_Fc_r = 0.0_dp; ws_Fc_th = 0.0_dp; ws_Fc_z = 0.0_dp
        ws_Fc_lk_r = 0; ws_Fc_lk_th = 0; ws_Fc_lk_z = 0
        if (ws_liq_cont_valid) then
            act_l = ws_liq_cont
        else
            act_l = (liq%alpha >= ALPHA_FLOW_CUTOFF)
        end if
        act_g = (gas%alpha >= ALPHA_FLOW_CUTOFF)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp
        gpr = 0.0_dp; gpth = 0.0_dp; gpz = 0.0_dp
        sh%pp = 0.0_dp

        !-----------------------------------------------------------------------
        ! Gradientes de presión de celda por fase (central en el interior,
        ! one-sided SOLO en frontera física; mismas fórmulas que momentum).
        ! Liquido: p del Poisson. Gas: p + ws_pcorr_g (superficie libre).
        !-----------------------------------------------------------------------
        call cell_gradients(sh%p, gpr, gpth, gpz)
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) then
            allocate(p_g, gpr_g, gpth_g, gpz_g, mold=sh%pp)
            if (ws_pcorr_valid) then
                p_g = sh%p + ws_pcorr_g
            else
                p_g = sh%p
            end if
            call cell_gradients(p_g, gpr_g, gpth_g, gpz_g)
        end if

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
        flux_ref = 0.0_dp
        call add_phase_contribution(liq, act_l, .true., sh%p, gpr, gpth, gpz)
        ! Gas en el Poisson SOLO con multifase: sin gas momentum resuelto,
        ! sus aP_u* valen 0 y d_f = V/SMALL revienta los coeficientes.
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) &
            call add_phase_contribution(gas, act_g, .false., p_g, gpr_g, gpth_g, gpz_g)

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
            real(dp) :: src, cap
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (gas%alpha(i,j,k) < ALPHA_FLOW_CUTOFF) cycle
                        ! Forma de VOLUMEN: (alpha_g/rho_g) (rho(T) - rho(T_old))/dt V
                        src = gas%alpha(i,j,k) * m%vol(i,j,k) / cfg%dt * &
                              (gas%rho(i,j,k) - cfg%rho_gas * cfg%T_ambient &
                               / max(gas_T_old(i,j,k), T_MIN_GAS)) / max(gas%rho(i,j,k), SMALL)
                        cap = COMP_SRC_CAP * gas%alpha(i,j,k) * m%vol(i,j,k) / cfg%dt
                        Su(i,j,k) = Su(i,j,k) - max(-cap, min(cap, src))
                    end do
                end do
            end do
        end block
        end if

        ! Celdas activas sin contribución de ninguna fase: triviales
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (.not. act_l(i,j,k) .and. .not. act_g(i,j,k)) then
                        aW(i,j,k) = 0.0_dp; aE(i,j,k) = 0.0_dp
                        aS(i,j,k) = 0.0_dp; aN(i,j,k) = 0.0_dp
                        aB(i,j,k) = 0.0_dp; aT(i,j,k) = 0.0_dp
                        aP(i,j,k) = 1.0_dp; Su(i,j,k) = 0.0_dp
                    else
                        ! Compliance: ver nota de PP_COMPLIANCE arriba
                        aP(i,j,k) = (aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + &
                                     aN(i,j,k) + aB(i,j,k) + aT(i,j,k)) * &
                                    (1.0_dp + PP_COMPLIANCE)
                        ! Término acústico low-Mach (ver P0_THERMO arriba)
                        if (cfg%gas_compressibility .and. cfg%solve_multiphase &
                            .and. gas%alpha(i,j,k) >= ALPHA_FLOW_CUTOFF) then
                            ! (volumen: d alpha_g/dp' = alpha_g/P0)
                            aP(i,j,k) = aP(i,j,k) + gas%alpha(i,j,k) / P0_THERMO * &
                                m%vol(i,j,k) / cfg%dt
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
        ws_Fc_valid = .true.

        call correct_velocities(liq, sh, m, act_l)
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) &
            call correct_velocities(gas, sh, m, act_g)

        ! Correct pressure (con cota física, ver P_HYDRO_CAP)
        sh%p = sh%p + cfg%alpha_p * sh%pp
        sh%p = max(-P_HYDRO_CAP, min(P_HYDRO_CAP, sh%p))

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
                        if (act_l(i,j,k) .or. act_g(i,j,k)) cycle
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
        call mpi_exchange_halos_3d(sh%p, m%topo)

        deallocate(gpr, gpth, gpz, act_l, act_g)
        deallocate(Fs_r, Fs_th, Fs_z, ac_r, ac_th, ac_z)
        if (allocated(p_g)) deallocate(p_g, gpr_g, gpth_g, gpz_g)

    contains

        ! La celda tiene presion de fluido definida? (Bug 16)
        pure logical function pv_cell(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            pv_cell = (m%cell_type(ii,jj,kk) /= 0) .and. &
                      (act_l(ii,jj,kk) .or. act_g(ii,jj,kk))
        end function pv_cell

        ! Acumula la presion de una vecina CON fluido continuo (Neumann de
        ! pared para las celdas selladas; ver Bug 16)
        subroutine acc_nb(ii, jj, kk, psum, nnb)
            integer,  intent(in)    :: ii, jj, kk
            real(dp), intent(inout) :: psum
            integer,  intent(inout) :: nnb
            if (m%cell_type(ii,jj,kk) == 0) return
            if (.not. act_l(ii,jj,kk) .and. .not. act_g(ii,jj,kk)) return
            psum = psum + sh%p(ii,jj,kk); nnb = nnb + 1
        end subroutine acc_nb

        !-----------------------------------------------------------------------
        ! Suma al Laplaciano compacto y a la divergencia Rhie-Chow la
        ! contribución de una fase (con su alpha, sus aP de momentum y sus
        ! velocidades)
        !-----------------------------------------------------------------------
        subroutine add_phase_contribution(ph, act, export, pf, gr, gth, gz)
            type(phase_t), intent(in) :: ph
            logical, intent(in)       :: act(-1:,-1:,-1:)
            ! Presion y gradientes de celda que ve ESTA fase (el gas lleva la
            ! correccion de superficie libre ws_pcorr_g)
            real(dp), intent(in)      :: pf(-1:,-1:,-1:)
            real(dp), intent(in)      :: gr(-1:,-1:,-1:), gth(-1:,-1:,-1:), gz(-1:,-1:,-1:)
            ! Guardar Q* y a_nb de las caras + (solo el liquido, F1)
            logical, intent(in)       :: export

            integer  :: ii, jj, kk, jjm, jjp
            real(dp) :: d_f, af, u_f, delta

            do kk = kstart, kend
                do jj = jstart, jend
                    jjm = jj - 1; jjp = jj + 1
                    do ii = istart, iend
                        if (m%cell_type(ii,jj,kk) == 0) cycle
                        if (.not. act(ii,jj,kk)) cycle

                        ! --- Cara Oeste (i-1/2) ---
                        if (link(act, ii-1, jj, kk)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk)  / max(ph%aP_ur(ii,jj,kk),  SMALL) + &
                                               m%vol(ii-1,jj,kk)/ max(ph%aP_ur(ii-1,jj,kk),SMALL))
                            af = 0.5_dp * (ph%alpha(ii,jj,kk) + ph%alpha(ii-1,jj,kk))
                            delta  = m%r(ii) - m%r(ii-1)
                            aW(ii,jj,kk) = aW(ii,jj,kk) + af * d_f * m%Ar(ii-1,jj,kk) / delta
                            u_f = 0.5_dp * (ph%ur(ii-1,jj,kk) + ph%ur(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gr(ii-1,jj,kk) + gr(ii,jj,kk)) &
                                         - (pf(ii,jj,kk) - pf(ii-1,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) + af * u_f * m%Ar(ii-1,jj,kk)
                            flux_ref = flux_ref + abs(af * u_f * m%Ar(ii-1,jj,kk))
                        end if

                        ! --- Cara Este (i+1/2) ---
                        if (link(act, ii+1, jj, kk)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk)  / max(ph%aP_ur(ii,jj,kk),  SMALL) + &
                                               m%vol(ii+1,jj,kk)/ max(ph%aP_ur(ii+1,jj,kk),SMALL))
                            af = 0.5_dp * (ph%alpha(ii,jj,kk) + ph%alpha(ii+1,jj,kk))
                            delta  = m%r(ii+1) - m%r(ii)
                            aE(ii,jj,kk) = aE(ii,jj,kk) + af * d_f * m%Ar(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%ur(ii,jj,kk) + ph%ur(ii+1,jj,kk)) &
                                + d_f * (0.5_dp*(gr(ii,jj,kk) + gr(ii+1,jj,kk)) &
                                         - (pf(ii+1,jj,kk) - pf(ii,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) - af * u_f * m%Ar(ii,jj,kk)
                            flux_ref = flux_ref + abs(af * u_f * m%Ar(ii,jj,kk))
                            if (export) then
                                Fs_r(ii,jj,kk) = af * u_f * m%Ar(ii,jj,kk)
                                ac_r(ii,jj,kk) = af * d_f * m%Ar(ii,jj,kk) / delta
                                ws_Fc_lk_r(ii,jj,kk) = 1
                            end if
                        end if

                        ! --- Cara Sur (j-1/2) ---
                        if (link(act, ii, jjm, kk)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk) / max(ph%aP_uth(ii,jj,kk), SMALL) + &
                                               m%vol(ii,jjm,kk)/ max(ph%aP_uth(ii,jjm,kk),SMALL))
                            af = 0.5_dp * (ph%alpha(ii,jj,kk) + ph%alpha(ii,jjm,kk))
                            delta  = m%r(ii) * (m%theta(jj) - m%theta(jjm))
                            aS(ii,jj,kk) = aS(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%uth(ii,jjm,kk) + ph%uth(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gth(ii,jjm,kk) + gth(ii,jj,kk)) &
                                         - (pf(ii,jj,kk) - pf(ii,jjm,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) + af * u_f * m%Ath(ii,jj,kk)
                            flux_ref = flux_ref + abs(af * u_f * m%Ath(ii,jj,kk))
                        end if

                        ! --- Cara Norte (j+1/2) ---
                        if (link(act, ii, jjp, kk)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk) / max(ph%aP_uth(ii,jj,kk), SMALL) + &
                                               m%vol(ii,jjp,kk)/ max(ph%aP_uth(ii,jjp,kk),SMALL))
                            af = 0.5_dp * (ph%alpha(ii,jj,kk) + ph%alpha(ii,jjp,kk))
                            delta  = m%r(ii) * (m%theta(jjp) - m%theta(jj))
                            aN(ii,jj,kk) = aN(ii,jj,kk) + af * d_f * m%Ath(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%uth(ii,jj,kk) + ph%uth(ii,jjp,kk)) &
                                + d_f * (0.5_dp*(gth(ii,jj,kk) + gth(ii,jjp,kk)) &
                                         - (pf(ii,jjp,kk) - pf(ii,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) - af * u_f * m%Ath(ii,jj,kk)
                            flux_ref = flux_ref + abs(af * u_f * m%Ath(ii,jj,kk))
                            if (export) then
                                Fs_th(ii,jj,kk) = af * u_f * m%Ath(ii,jj,kk)
                                ac_th(ii,jj,kk) = af * d_f * m%Ath(ii,jj,kk) / delta
                                ws_Fc_lk_th(ii,jj,kk) = 1
                            end if
                        end if

                        ! --- Cara Inferior (k-1/2) ---
                        if (link(act, ii, jj, kk-1)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk)  / max(ph%aP_uz(ii,jj,kk),  SMALL) + &
                                               m%vol(ii,jj,kk-1)/ max(ph%aP_uz(ii,jj,kk-1),SMALL))
                            af = 0.5_dp * (ph%alpha(ii,jj,kk) + ph%alpha(ii,jj,kk-1))
                            delta  = m%z(kk) - m%z(kk-1)
                            aB(ii,jj,kk) = aB(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk-1) / delta
                            u_f = 0.5_dp * (ph%uz(ii,jj,kk-1) + ph%uz(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gz(ii,jj,kk-1) + gz(ii,jj,kk)) &
                                         - (pf(ii,jj,kk) - pf(ii,jj,kk-1)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) + af * u_f * m%Az(ii,jj,kk-1)
                            flux_ref = flux_ref + abs(af * u_f * m%Az(ii,jj,kk-1))
                        end if

                        ! --- Cara Superior (k+1/2) ---
                        if (link(act, ii, jj, kk+1)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk)  / max(ph%aP_uz(ii,jj,kk),  SMALL) + &
                                               m%vol(ii,jj,kk+1)/ max(ph%aP_uz(ii,jj,kk+1),SMALL))
                            af = 0.5_dp * (ph%alpha(ii,jj,kk) + ph%alpha(ii,jj,kk+1))
                            delta  = m%z(kk+1) - m%z(kk)
                            aT(ii,jj,kk) = aT(ii,jj,kk) + af * d_f * m%Az(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%uz(ii,jj,kk) + ph%uz(ii,jj,kk+1)) &
                                + d_f * (0.5_dp*(gz(ii,jj,kk) + gz(ii,jj,kk+1)) &
                                         - (pf(ii,jj,kk+1) - pf(ii,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) - af * u_f * m%Az(ii,jj,kk)
                            flux_ref = flux_ref + abs(af * u_f * m%Az(ii,jj,kk))
                            if (export) then
                                Fs_z(ii,jj,kk) = af * u_f * m%Az(ii,jj,kk)
                                ac_z(ii,jj,kk) = af * d_f * m%Az(ii,jj,kk) / delta
                                ws_Fc_lk_z(ii,jj,kk) = 1
                            end if
                        end if
                    end do
                end do
            end do
        end subroutine add_phase_contribution


        ! Gradientes de celda de un campo de presion (ver arriba)
        subroutine cell_gradients(pfld, gr, gth, gz)
            real(dp), intent(in)  :: pfld(-1:,-1:,-1:)
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
                    gr(i,j,k) = pgrad(pfld(i-1,j,k), pfld(i,j,k), pfld(i+1,j,k), &
                                       m%r(i-1), m%r(i), m%r(i+1), &
                                       i > istart .and. pv_cell(i-1,j,k), &
                                       i < iend   .and. pv_cell(i+1,j,k))

                    gth(i,j,k) = pgrad(pfld(i,jm,k), pfld(i,j,k), pfld(i,jp,k), &
                                        m%r(i) * m%theta(jm), m%r(i) * m%theta(j), &
                                        m%r(i) * m%theta(jp), &
                                        pv_cell(i,jm,k), pv_cell(i,jp,k))

                    gz(i,j,k) = pgrad(pfld(i,j,k-1), pfld(i,j,k), pfld(i,j,k+1), &
                                       m%z(k-1), m%z(k), m%z(k+1), &
                                       (k > kstart .or. .not. at_zmin) .and. pv_cell(i,j,k-1), &
                                       (k < kend   .or. .not. at_zmax) .and. pv_cell(i,j,k+1))
                end do
            end do
        end do

        call mpi_exchange_halos_3d(gr,  m%topo)
        call mpi_exchange_halos_3d(gth, m%topo)
        call mpi_exchange_halos_3d(gz,  m%topo)
        end subroutine cell_gradients

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
    subroutine correct_velocities(ph, sh, m, act)
        type(phase_t), intent(inout) :: ph
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        logical, intent(in)  :: act(-1:,-1:,-1:)

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: d_coeff
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax
        logical  :: skip_r, skip_z

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        ! Correcciones omitidas SOLO en fronteras físicas; en interfaces de
        ! rank se usan los halos de pp (hallazgo 3.6)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    ! Sin corrección bajo el umbral hidrodinámico (C2.2)
                    if (.not. act(i,j,k)) cycle

                    ! u_r correction
                    skip_r = (i == istart .and. at_rmin) .or. &
                             (i == iend   .and. at_rmax)
                    if (.not. skip_r .and. abs(ph%aP_ur(i,j,k)) > SMALL) then
                        d_coeff = m%vol(i,j,k) / ph%aP_ur(i,j,k)
                        ph%ur(i,j,k) = ph%ur(i,j,k) - d_coeff * &
                            (sh%pp(i+1,j,k) - sh%pp(i-1,j,k)) / (m%r(i+1) - m%r(i-1))
                    end if

                    ! u_theta correction
                    if (abs(ph%aP_uth(i,j,k)) > SMALL) then
                        d_coeff = m%vol(i,j,k) / ph%aP_uth(i,j,k)
                        ph%uth(i,j,k) = ph%uth(i,j,k) - d_coeff * &
                            (sh%pp(i,jp,k) - sh%pp(i,jm,k)) / &
                            (m%r(i) * (m%theta(jp) - m%theta(jm)))
                    end if

                    ! u_z correction
                    skip_z = (k == kstart .and. at_zmin) .or. &
                             (k == kend   .and. at_zmax)
                    if (.not. skip_z .and. abs(ph%aP_uz(i,j,k)) > SMALL) then
                        d_coeff = m%vol(i,j,k) / ph%aP_uz(i,j,k)
                        ph%uz(i,j,k) = ph%uz(i,j,k) - d_coeff * &
                            (sh%pp(i,j,k+1) - sh%pp(i,j,k-1)) / (m%z(k+1) - m%z(k-1))
                    end if
                end do
            end do
        end do

    end subroutine correct_velocities

end module mod_pressure_3d
