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
    use mod_workspace, only: ws_rho_fluid_old, ws_rho_mix_valid, ws_mdot, ws_pv_valid
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
            ws_rho_fluid_old, ws_rho_mix_valid
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
        ! Fases ACTIVAS en el acople P-V por celda (Bug 15): gas por el
        ! umbral hidrodinamico; liquido solo donde es fase continua
        logical, allocatable :: act_l(:,:,:), act_g(:,:,:)
        integer  :: n_iter_cg
        real(dp) :: cg_res
        logical  :: at_rmin, at_rmax, at_zmin, at_zmax

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        call ensure_workspace(m)
        allocate(gpr, mold=sh%pp); allocate(gpth, mold=sh%pp)
        allocate(gpz, mold=sh%pp)
        allocate(act_l(lbound(sh%pp,1):ubound(sh%pp,1), lbound(sh%pp,2):ubound(sh%pp,2), &
                       lbound(sh%pp,3):ubound(sh%pp,3)))
        allocate(act_g, mold=act_l)
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
        ! Gradientes de presión de celda (central en el interior, one-sided
        ! SOLO en frontera física; mismas fórmulas que momentum)
        !-----------------------------------------------------------------------
        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1; jp = j + 1
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    ! Gradientes con las celdas SIN fluido tratadas como
                    ! pared (Bug 16): su presion no es de fluido y entraba
                    ! al termino de Rhie-Chow del propio Poisson.
                    gpr(i,j,k) = pgrad(sh%p(i-1,j,k), sh%p(i,j,k), sh%p(i+1,j,k), &
                                       m%r(i-1), m%r(i), m%r(i+1), &
                                       i > istart .and. pv_cell(i-1,j,k), &
                                       i < iend   .and. pv_cell(i+1,j,k))

                    gpth(i,j,k) = pgrad(sh%p(i,jm,k), sh%p(i,j,k), sh%p(i,jp,k), &
                                        m%r(i) * m%theta(jm), m%r(i) * m%theta(j), &
                                        m%r(i) * m%theta(jp), &
                                        pv_cell(i,jm,k), pv_cell(i,jp,k))

                    gpz(i,j,k) = pgrad(sh%p(i,j,k-1), sh%p(i,j,k), sh%p(i,j,k+1), &
                                       m%z(k-1), m%z(k), m%z(k+1), &
                                       (k > kstart .or. .not. at_zmin) .and. pv_cell(i,j,k-1), &
                                       (k < kend   .or. .not. at_zmax) .and. pv_cell(i,j,k+1))
                end do
            end do
        end do

        call mpi_exchange_halos_3d(gpr, m%topo)
        call mpi_exchange_halos_3d(gpth, m%topo)
        call mpi_exchange_halos_3d(gpz, m%topo)

        !-----------------------------------------------------------------------
        ! Acumular contribuciones de AMBAS fases (C2.4, reactivado tras C3.4:
        ! con la radiación DO real el gas queda en ~3000-6000 K y su
        ! expansión es absorbible por el Poisson)
        !-----------------------------------------------------------------------
        call add_phase_contribution(liq, act_l)
        ! Gas en el Poisson SOLO con multifase: sin gas momentum resuelto,
        ! sus aP_u* valen 0 y d_f = V/SMALL revienta los coeficientes.
        if (cfg%gas_in_poisson .and. cfg%solve_multiphase) &
            call add_phase_contribution(gas, act_g)

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
            real(dp) :: src, cap, rho_f
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (.not. act_l(i,j,k) .and. .not. act_g(i,j,k)) cycle
                        if (ws_rho_mix_valid .and. ws_pv_valid) then
                            ! Transitorio de la mezcla FLUIDA menos el fundido
                            ! (Bug 19):
                            !   d(a_l rho_l + a_g rho_g)/dt + div(...) = mdot
                            ! Subsume el termino historico de compresibilidad
                            ! del gas (a_g fijo, rho_g(T)) y anade el CAMBIO DE
                            ! COMPOSICION, que era lo que faltaba: una celda de
                            ! bano que se llena o drena, sin gas que absorba el
                            ! volumen, exigia div u = 0 y respondia con +-MPa
                            ! (B1 v16: 1.8 MPa en las primeras celdas de liquido
                            ! puro, t=75 s).
                            ! La fusion sale EXACTAMENTE neutra (el termino
                            ! d(a_l rho_l)/dt que crea cancela con mdot): ese
                            ! fue el error del intento historico que metia solo
                            ! mdot (ganancia >1, p x50/paso). El SOLIDO no entra
                            ! en rho_f — no tiene flujo en el Poisson —, asi que
                            ! el colapso solo pide el gas que debe llenar el
                            ! hueco (delta*rho_g, minusculo), no delta*rho_s.
                            rho_f = liq%alpha(i,j,k) * liq%rho(i,j,k) &
                                  + gas%alpha(i,j,k) * gas%rho(i,j,k)
                            src = m%vol(i,j,k) / cfg%dt * &
                                  (rho_f - ws_rho_fluid_old(i,j,k)) - ws_mdot(i,j,k)
                            cap = COMP_SRC_CAP * rho_f * m%vol(i,j,k) / cfg%dt
                        else
                            if (gas%alpha(i,j,k) < ALPHA_FLOW_CUTOFF) cycle
                            src = gas%alpha(i,j,k) * m%vol(i,j,k) / cfg%dt * &
                                  (gas%rho(i,j,k) - cfg%rho_gas * cfg%T_ambient &
                                   / max(gas_T_old(i,j,k), T_MIN_GAS))
                            cap = COMP_SRC_CAP * gas%alpha(i,j,k) * &
                                  gas%rho(i,j,k) * m%vol(i,j,k) / cfg%dt
                        end if
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
                            aP(i,j,k) = aP(i,j,k) + gas%alpha(i,j,k) * &
                                gas%rho(i,j,k) / P0_THERMO * &
                                m%vol(i,j,k) / cfg%dt
                        end if
                        ! Compresibilidad acústica del LÍQUIDO (física,
                        ! c~4000 m/s): diagonal para celdas líquido-puras
                        ! (sin gas no hay término acústico del gas y la
                        ! compliance sola deja el nivel de p sin física)
                        if (act_l(i,j,k)) then
                            aP(i,j,k) = aP(i,j,k) + liq%alpha(i,j,k) * &
                                m%vol(i,j,k) / (C_SOUND_LIQ**2 * cfg%dt)
                        end if
                    end if
                end do
            end do
        end do

        ! Pressure BCs
        call apply_pressure_bc(aW, aE, aS, aN, aB, aT, aP, Su, m)

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

        residual = cg_res

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
        subroutine add_phase_contribution(ph, act)
            type(phase_t), intent(in) :: ph
            logical, intent(in)       :: act(-1:,-1:,-1:)

            integer  :: ii, jj, kk, jjm, jjp
            real(dp) :: d_f, arho_f, u_f, delta

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
                            arho_f = 0.5_dp * (ph%alpha(ii,jj,kk)*ph%rho(ii,jj,kk) + &
                                               ph%alpha(ii-1,jj,kk)*ph%rho(ii-1,jj,kk))
                            delta  = m%r(ii) - m%r(ii-1)
                            aW(ii,jj,kk) = aW(ii,jj,kk) + arho_f * d_f * m%Ar(ii-1,jj,kk) / delta
                            u_f = 0.5_dp * (ph%ur(ii-1,jj,kk) + ph%ur(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gpr(ii-1,jj,kk) + gpr(ii,jj,kk)) &
                                         - (sh%p(ii,jj,kk) - sh%p(ii-1,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) + arho_f * u_f * m%Ar(ii-1,jj,kk)
                        end if

                        ! --- Cara Este (i+1/2) ---
                        if (link(act, ii+1, jj, kk)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk)  / max(ph%aP_ur(ii,jj,kk),  SMALL) + &
                                               m%vol(ii+1,jj,kk)/ max(ph%aP_ur(ii+1,jj,kk),SMALL))
                            arho_f = 0.5_dp * (ph%alpha(ii,jj,kk)*ph%rho(ii,jj,kk) + &
                                               ph%alpha(ii+1,jj,kk)*ph%rho(ii+1,jj,kk))
                            delta  = m%r(ii+1) - m%r(ii)
                            aE(ii,jj,kk) = aE(ii,jj,kk) + arho_f * d_f * m%Ar(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%ur(ii,jj,kk) + ph%ur(ii+1,jj,kk)) &
                                + d_f * (0.5_dp*(gpr(ii,jj,kk) + gpr(ii+1,jj,kk)) &
                                         - (sh%p(ii+1,jj,kk) - sh%p(ii,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) - arho_f * u_f * m%Ar(ii,jj,kk)
                        end if

                        ! --- Cara Sur (j-1/2) ---
                        if (link(act, ii, jjm, kk)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk) / max(ph%aP_uth(ii,jj,kk), SMALL) + &
                                               m%vol(ii,jjm,kk)/ max(ph%aP_uth(ii,jjm,kk),SMALL))
                            arho_f = 0.5_dp * (ph%alpha(ii,jj,kk)*ph%rho(ii,jj,kk) + &
                                               ph%alpha(ii,jjm,kk)*ph%rho(ii,jjm,kk))
                            delta  = m%r(ii) * (m%theta(jj) - m%theta(jjm))
                            aS(ii,jj,kk) = aS(ii,jj,kk) + arho_f * d_f * m%Ath(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%uth(ii,jjm,kk) + ph%uth(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gpth(ii,jjm,kk) + gpth(ii,jj,kk)) &
                                         - (sh%p(ii,jj,kk) - sh%p(ii,jjm,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) + arho_f * u_f * m%Ath(ii,jj,kk)
                        end if

                        ! --- Cara Norte (j+1/2) ---
                        if (link(act, ii, jjp, kk)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk) / max(ph%aP_uth(ii,jj,kk), SMALL) + &
                                               m%vol(ii,jjp,kk)/ max(ph%aP_uth(ii,jjp,kk),SMALL))
                            arho_f = 0.5_dp * (ph%alpha(ii,jj,kk)*ph%rho(ii,jj,kk) + &
                                               ph%alpha(ii,jjp,kk)*ph%rho(ii,jjp,kk))
                            delta  = m%r(ii) * (m%theta(jjp) - m%theta(jj))
                            aN(ii,jj,kk) = aN(ii,jj,kk) + arho_f * d_f * m%Ath(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%uth(ii,jj,kk) + ph%uth(ii,jjp,kk)) &
                                + d_f * (0.5_dp*(gpth(ii,jj,kk) + gpth(ii,jjp,kk)) &
                                         - (sh%p(ii,jjp,kk) - sh%p(ii,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) - arho_f * u_f * m%Ath(ii,jj,kk)
                        end if

                        ! --- Cara Inferior (k-1/2) ---
                        if (link(act, ii, jj, kk-1)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk)  / max(ph%aP_uz(ii,jj,kk),  SMALL) + &
                                               m%vol(ii,jj,kk-1)/ max(ph%aP_uz(ii,jj,kk-1),SMALL))
                            arho_f = 0.5_dp * (ph%alpha(ii,jj,kk)*ph%rho(ii,jj,kk) + &
                                               ph%alpha(ii,jj,kk-1)*ph%rho(ii,jj,kk-1))
                            delta  = m%z(kk) - m%z(kk-1)
                            aB(ii,jj,kk) = aB(ii,jj,kk) + arho_f * d_f * m%Az(ii,jj,kk-1) / delta
                            u_f = 0.5_dp * (ph%uz(ii,jj,kk-1) + ph%uz(ii,jj,kk)) &
                                + d_f * (0.5_dp*(gpz(ii,jj,kk-1) + gpz(ii,jj,kk)) &
                                         - (sh%p(ii,jj,kk) - sh%p(ii,jj,kk-1)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) + arho_f * u_f * m%Az(ii,jj,kk-1)
                        end if

                        ! --- Cara Superior (k+1/2) ---
                        if (link(act, ii, jj, kk+1)) then
                            d_f    = 0.5_dp * (m%vol(ii,jj,kk)  / max(ph%aP_uz(ii,jj,kk),  SMALL) + &
                                               m%vol(ii,jj,kk+1)/ max(ph%aP_uz(ii,jj,kk+1),SMALL))
                            arho_f = 0.5_dp * (ph%alpha(ii,jj,kk)*ph%rho(ii,jj,kk) + &
                                               ph%alpha(ii,jj,kk+1)*ph%rho(ii,jj,kk+1))
                            delta  = m%z(kk+1) - m%z(kk)
                            aT(ii,jj,kk) = aT(ii,jj,kk) + arho_f * d_f * m%Az(ii,jj,kk) / delta
                            u_f = 0.5_dp * (ph%uz(ii,jj,kk) + ph%uz(ii,jj,kk+1)) &
                                + d_f * (0.5_dp*(gpz(ii,jj,kk) + gpz(ii,jj,kk+1)) &
                                         - (sh%p(ii,jj,kk+1) - sh%p(ii,jj,kk)) / delta)
                            Su(ii,jj,kk) = Su(ii,jj,kk) - arho_f * u_f * m%Az(ii,jj,kk)
                        end if
                    end do
                end do
            end do
        end subroutine add_phase_contribution

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

    !---------------------------------------------------------------------------
    ! Ancla la densidad de los FLUIDOS al INICIO del paso (llamar desde main
    ! antes de la fusion y el colapso). Ver Bug 19.
    !---------------------------------------------------------------------------
    subroutine store_mixture_density(liq, gas, m)
        type(phase_t), intent(in) :: liq, gas
        type(mesh_t),  intent(in) :: m
        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) then
                        ws_rho_fluid_old(i,j,k) = 0.0_dp
                    else
                        ws_rho_fluid_old(i,j,k) = liq%alpha(i,j,k) * liq%rho(i,j,k) &
                                                + gas%alpha(i,j,k) * gas%rho(i,j,k)
                    end if
                end do
            end do
        end do
        ws_rho_mix_valid = .true.
    end subroutine store_mixture_density

end module mod_pressure_3d
