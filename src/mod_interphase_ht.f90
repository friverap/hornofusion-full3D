!===============================================================================
! mod_interphase_ht.f90 - Interphase heat transfer (Eq. 12 of paper)
!
! Gas-solid heat transfer (two regimes):
!   T_g <= 1373 K: h_vgs = (K_g/d_s)*(2 + 1.1*Pr_g^0.333*Re_gs^0.6)
!   T_g >  1373 K: h_gs*A_gs = A*f_omega*|v_g|^0.9*T_g^0.3/d_s^0.75
!
! Liquid-solid: Ranz-Marshall Nu = 2 + 0.6 Re^1/2 Pr^1/3 con la velocidad del
! liquido (auditoria M39). Gas-solido con la conductividad MOLECULAR
! mu cp/Pr (Pr = 0.7), no la efectiva cfg%k_gas.
!
! Computes volumetric heat source Q_s_bar for solid energy balance (Eq. 8).
!===============================================================================
module mod_interphase_ht
    use mod_constants
    use mod_audit, only: audit_add, AUD_IPH_SOL, AUD_IPH_GAS, AUD_IPH_LIQ, &
                         gas_heat_capacity_ref, gas_log_exchange
    use mod_mpi_topology, only: mpi_allreduce_min, mpi_exchange_halos_3d
    use mod_types_3d
    use mod_melting_3d, only: solid_T_from_enthalpy
    use mod_workspace, only: ws_liq_cont, ws_liq_cont_valid
    implicit none

    ! Escala temporal mínima del acople interfase del último paso
    ! (tau = alpha_g*rho*cp / (h*A_sv)): por debajo de ~tau el intercambio
    ! explícito satura su clamp y fuerza equilibrio térmico local (régimen
    ! medido en S5-dpart y en B1 con dt=10 ms) — el dt adaptativo debe
    ! respetarla (adapt_timestep).
    real(dp), save :: tau_iph_local = 1.0e30_dp

    real(dp), parameter :: T_TRANSITION = 1373.0_dp  ! K
    real(dp), parameter :: A_RADIATION  = 3.6_dp     ! empirical constant
    real(dp), parameter :: F_OMEGA      = 0.7_dp     ! view factor parameter
    real(dp), parameter :: PR_GAS_MOL   = 0.7_dp     ! Prandtl molecular del gas (N2/aire caliente)

contains

    subroutine compute_interphase_heat(liq, gas, sol, m, cfg, sh)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(inout) :: sol
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        ! (auditoria 5, B5-3) p para la capacidad de referencia del gas (log)
        type(shared_t), intent(in), optional :: sh
        real(dp) :: Cg_log, Tg_new, pc

        integer :: i, j, k
        real(dp) :: T_g, T_l, T_s, alpha_s, d_s
        real(dp) :: vmag_g, Re_gs, Pr_g, h_gs, h_ls
        real(dp) :: Q_gs, Q_ls, Q_total
        real(dp) :: A_sv, eps_s, cap_g, cap_l, cap_s, G_gs, G_ls, b_g, b_l, T_sn
        real(dp) :: f_l, f_g, w_l, w_g, k_mol, vmag_l, Re_ls, Pr_l

        d_s = cfg%d_particle
        tau_iph_local = 1.0e30_dp

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle

                    alpha_s = sol%alpha_s(i,j,k)
                    if (alpha_s < 1.0e-6_dp) cycle

                    T_s = sol%T_s(i,j,k)
                    T_g = gas%T(i,j,k)
                    T_l = liq%T(i,j,k)

                    ! Superficie especifica del solido (esferas), REPARTIDA entre
                    ! las fases que la mojan (auditoria M7): gas y liquido usaban
                    ! cada uno 6 alpha_s/d completo -> area contada dos veces en
                    ! toda celda con ambos fluidos. Reparto por fraccion de poro
                    ! (mojado proporcional; sin modelo de pelicula).
                    eps_s = max(1.0_dp - alpha_s, 0.01_dp)
                    A_sv = 6.0_dp * alpha_s / (d_s + SMALL)
                    f_l = 0.0_dp
                    if (liq%alpha(i,j,k) > 1.0e-6_dp) f_l = liq%alpha(i,j,k)
                    f_g = 0.0_dp
                    if (gas%alpha(i,j,k) > 1.0e-6_dp) f_g = gas%alpha(i,j,k)
                    if (f_l + f_g > 0.0_dp) then
                        w_l = f_l / (f_l + f_g); w_g = f_g / (f_l + f_g)
                    else
                        w_l = 0.0_dp; w_g = 0.0_dp
                    end if

                    ! Conductancias G = h A V [W/K]
                    G_gs = 0.0_dp
                    if (w_g > 0.0_dp) then
                        vmag_g = sqrt(gas%ur(i,j,k)**2 + gas%uth(i,j,k)**2 + gas%uz(i,j,k)**2)
                        ! Conductividad MOLECULAR del gas para la correlacion
                        ! (auditoria M39): Wakao se define con k molecular y
                        ! Pr ~ 0.7; cfg%k_gas (0.5) es la conductividad
                        ! efectiva de la difusion del gas y daba Pr = 0.1 y
                        ! un h ~4x mayor que el de la literatura
                        k_mol = gas%mu(i,j,k) * gas%cp(i,j,k) / PR_GAS_MOL
                        Pr_g = PR_GAS_MOL
                        Re_gs = gas%rho(i,j,k) * vmag_g * d_s / (gas%mu(i,j,k) + SMALL)

                        ! Wakao (Nu = 2 + 1.1 Pr^1/3 Re^0.6) siempre; sobre
                        ! T_TRANSITION, el MAYOR de Wakao y la correlacion de alta
                        ! T (auditoria 12-oct-2026, A12): la de alta T va como
                        ! |v|^0.9 y se anulaba con gas quieto (sin el piso
                        ! conductivo Nu = 2), y saltaba x2.4-8.6 en T_TRANSITION.
                        ! El gas de poro estancado bajo el arco quedaba sin acople
                        ! termico con la chatarra.
                        h_gs = (k_mol / d_s) * &
                               (2.0_dp + 1.1_dp * Pr_g**0.333_dp * Re_gs**0.6_dp)
                        if (T_g > T_TRANSITION) h_gs = max(h_gs, &
                            A_RADIATION * F_OMEGA * vmag_g**0.9_dp * &
                            T_g**0.3_dp / (d_s**0.75_dp + SMALL))
                        G_gs = h_gs * A_sv * w_g * m%vol(i,j,k)
                        tau_iph_local = min(tau_iph_local, &
                            gas%alpha(i,j,k) * gas%rho(i,j,k) * &
                            gas%cp(i,j,k) / (h_gs * A_sv * w_g + SMALL))
                    end if
                    G_ls = 0.0_dp
                    if (w_l > 0.0_dp) then
                        ! Ranz-Marshall REAL con la velocidad del liquido
                        ! respecto de la chatarra quieta (auditoria M39; antes
                        ! Nu = 6 fijo, ~2-4 kW/m2K frente a 5-20 de la
                        ! literatura de fusion de chatarra en baño agitado)
                        vmag_l = sqrt(liq%ur(i,j,k)**2 + liq%uth(i,j,k)**2 + liq%uz(i,j,k)**2)
                        Re_ls = liq%rho(i,j,k) * vmag_l * d_s / (liq%mu(i,j,k) + SMALL)
                        Pr_l = liq%mu(i,j,k) * liq%cp(i,j,k) / (liq%kth(i,j,k) + SMALL)
                        h_ls = (liq%kth(i,j,k) / d_s) * &
                               (2.0_dp + 0.6_dp * sqrt(Re_ls) * Pr_l**(1.0_dp/3.0_dp))
                        G_ls = h_ls * A_sv * w_l * m%vol(i,j,k)
                    end if

                    ! Paso IMPLICITO exacto de tres nodos (auditoria M6). Antes
                    ! cada flujo se recortaba por separado a min(Q, C_f dT/dt,
                    ! C_s dT/dt): el tope C dT/dt deja cruzar el equilibrio
                    ! C_f C_s/(C_f+C_s) dT, y Q_gs y Q_ls recortados cada uno
                    ! contra su propio dT podian llevar T_s por encima de AMBOS
                    ! fluidos. Euler implicito de
                    !   C_g dT_g = -G_gs (T_g - T_s) dt, C_l dT_l = -G_ls (T_l - T_s) dt,
                    !   C_s dT_s = G_gs (T_g - T_s) dt + G_ls (T_l - T_s) dt
                    ! (todas en el nivel nuevo) se resuelve en cerrado:
                    !   b_q = a_q C_q/(C_q + a_q), a_q = G_q dt,
                    !   T_s' = (C_s T_s + b_g T_g + b_l T_l)/(C_s + b_g + b_l),
                    !   Q_q dt = b_q (T_q - T_s')
                    ! T_s' es una media ponderada (acotada por los tres) y cada
                    ! fluido queda entre su T y T_s': sin rebase con ningun dt.
                    ! C_s = m_s cp_s sin latente: con fusion la capacidad real es
                    ! mayor y la T_s final (de la entalpia) queda por debajo de
                    ! T_s' -> sigue acotada.
                    ! (auditoria 5, B5-3) el GAS lleva su inventario LOG
                    ! (M4-13): gas_log_exchange relaja el gas exacto hacia la
                    ! T NUEVA del solido (tasa hA (Tg - T_s') a dt -> 0,
                    ! acotado entre Tg y T_s'), el liquido lineal implicito
                    ! hacia la misma T, y T_s' cumple el balance del solido
                    ! (biseccion monotona). Conservacion exacta en los
                    ! inventarios de estado; el poke lineal perdia O(dT^2)
                    ! (96 J, 0.28 %, en noflow_energy).
                    pc = 0.0_dp
                    if (present(sh)) pc = sh%p(i,j,k)
                    Cg_log = gas_heat_capacity_ref(gas%alpha(i,j,k), pc, gas%cp(i,j,k), &
                                                   m%vol(i,j,k), cfg)
                    T_g = max(T_g, T_MIN_GAS)
                    cap_l = liq%alpha(i,j,k) * liq%rho(i,j,k) * liq%cp(i,j,k) * m%vol(i,j,k)
                    cap_s = sol%m_s(i,j,k) * cfg%cp_s
                    if (gas%alpha(i,j,k) <= 1.0e-6_dp .or. Cg_log <= 0.0_dp) G_gs = 0.0_dp
                    if (liq%alpha(i,j,k) <= 1.0e-6_dp .or. cap_l <= 0.0_dp) G_ls = 0.0_dp
                    Q_gs = 0.0_dp; Q_ls = 0.0_dp; Tg_new = T_g
                    if ((G_gs > 0.0_dp .or. G_ls > 0.0_dp) .and. cap_s > 0.0_dp) then
                        if (G_gs > 0.0_dp) then
                            call gas_log_exchange(Cg_log, T_g, cap_s, T_s, G_gs, cfg%dt, Tg_new, Q_gs, &
                                                  cap_l, T_l, G_ls, Q_ls)
                        else
                            b_l = G_ls * cfg%dt * cap_l / (cap_l + G_ls * cfg%dt)
                            T_sn = (cap_s * T_s + b_l * T_l) / (cap_s + b_l)
                            Q_ls = b_l * (T_l - T_sn)
                        end if
                        Q_gs = Q_gs / cfg%dt; Q_ls = Q_ls / cfg%dt
                    end if

                    ! Retiro de los fluidos PRIMERO (el solido recibe lo que
                    ! de verdad salio de cada inventario).
                    ! (auditoria 5, B5-3) GAS en forma LOG (M4-13): Q_gs es la
                    ! tasa del cierre lineal de tres nodos; el estado del gas
                    ! avanza T = Tg exp(-Q dt/Cg) acotado entre Tg y T_s' (sin
                    ! la cota, un gas frio sobre chatarra caliente rebasaba
                    ! T_s': exp(x - 1) >= x) y Q_gs se REDEFINE como lo que
                    ! perdio el inventario log: conservacion exacta, el poke
                    ! lineal perdia O(dT^2) (96 J, 0.28 %, en noflow_energy).
                    if (abs(Q_gs) > SMALL) then
                        gas%T(i,j,k) = Tg_new
                        call audit_add(AUD_IPH_GAS, Q_gs * cfg%dt)
                    else
                        Q_gs = 0.0_dp
                    end if
                    if (abs(Q_ls) > SMALL) then
                        liq%T(i,j,k) = liq%T(i,j,k) - Q_ls * cfg%dt / cap_l
                        call audit_add(AUD_IPH_LIQ, Q_ls * cfg%dt)
                    else
                        Q_ls = 0.0_dp
                    end if
                    Q_total = Q_gs + Q_ls

                    ! Apply heat to solid energy balance (lo que salio de los
                    ! fluidos, exacto)
                    sol%E_s(i,j,k) = sol%E_s(i,j,k) + Q_total * cfg%dt
                    call audit_add(AUD_IPH_SOL, Q_total * cfg%dt)

                    ! Update solid temperature (función de entalpía ÚNICA, C1.8:
                    ! antes E/(m*cp_s) chocaba con el cp_eff de la fusión)
                    if (sol%m_s(i,j,k) > SMALL) then
                        sol%T_s(i,j,k) = solid_T_from_enthalpy( &
                            sol%E_s(i,j,k) / sol%m_s(i,j,k), cfg)
                    end if
                end do
            end do
        end do

    end subroutine compute_interphase_heat

    !---------------------------------------------------------------------------
    ! Intercambio de calor GAS-LIQUIDO del modelo de dos fluidos (auditoria 2,
    ! N-A1). No existia: el gas a 300 K sobre acero a 1850 K quedaba a 300 K,
    ! y la columna del arco y el gas caliente sobre el baño no podian cederle
    ! calor. Area interfacial:
    !   - liquido CONTINUO: superficie libre resuelta, a = |grad alpha_l| (la
    !     densidad de area del AIAD, Hoehne-Vallee 2010);
    !   - liquido DISPERSO (gotas, fuera del lecho): a = 6 alpha_l / d_gota.
    ! h del lado del gas con k molecular (el liquido conduce ~100x mas):
    !   gotas Nu = 2 + 0.6 Re^1/2 Pr^1/3 (Ranz-Marshall, longitud d_gota);
    !   superficie Nu = 2 + 0.664 Re^1/2 Pr^1/3 (placa plana, longitud dz),
    ! con la velocidad RELATIVA gas-liquido. Paso IMPLICITO exacto de dos nodos
    ! (sin rebase con ningun dt): q = C_g C_l/(C_g + C_l) (T_g - T_l)
    ! (1 - exp(-G dt (1/C_g + 1/C_l))). Conservativo: lo que pierde el gas lo
    ! gana el liquido (E_iph_gas = -E_iph_liq; la identidad de la interfase
    ! sigue cerrando). La radiacion entre la superficie y el gas la lleva la DO.
    !---------------------------------------------------------------------------
    subroutine compute_gas_liquid_heat(liq, gas, sol, m, cfg, sh)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        ! (auditoria 5, B5-3) p para la capacidad de referencia del gas (log)
        type(shared_t), intent(in), optional :: sh
        integer  :: i, j, k, jm, jp, kl, kg, sweep, k_off
        real(dp) :: al, ag, as, cg, cl, G, f, q, d, dp_, k_mol, urel, xb, f_disp, wet
        real(dp) :: fbed, G_in, G_out, a_fs, Cg_log, Tg_new, pc, fb2
        logical  :: cont_el, cont
        d = cfg%d_droplet
        if (d <= 0.0_dp) d = 2.0e-3_dp
        dp_ = max(cfg%d_particle, 1.0e-3_dp)
        do k = 1, m%nz
            do j = 1, m%ntheta
                jm = j - 1; jp = j + 1
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    al = liq%alpha(i,j,k); ag = gas%alpha(i,j,k); as = sol%alpha_s(i,j,k)
                    if (al <= 1.0e-6_dp .or. ag <= 1.0e-6_dp) cycle
                    cg = ag * gas%rho(i,j,k) * gas%cp(i,j,k) * m%vol(i,j,k)
                    cl = al * liq%rho(i,j,k) * liq%cp(i,j,k) * m%vol(i,j,k)
                    k_mol = gas%mu(i,j,k) * gas%cp(i,j,k) / PR_GAS_MOL
                    urel = sqrt((gas%ur(i,j,k) - liq%ur(i,j,k))**2 + &
                                (gas%uth(i,j,k) - liq%uth(i,j,k))**2 + &
                                (gas%uz(i,j,k) - liq%uz(i,j,k))**2)
                    ! MORFOLOGIA (auditoria 3, A3-2): mezcla, nunca interruptor
                    ! (F2.22), y la misma regla de continuidad que el resto del
                    ! codigo (ws_liq_cont, con la superficie libre):
                    !   LECHO (alpha_s >= 1e-2): pelicula sobre la chatarra;
                    !     area de las particulas 6 alpha_s/d_p por la fraccion
                    !     mojada alpha_l/(1 - alpha_s), Ranz-Marshall con d_p.
                    !     Antes una pelicula uniforme (|grad alpha| = 0) no
                    !     intercambiaba nada.
                    !   FUERA DEL LECHO: logistica AIAD en alpha_l entre GOTAS
                    !     (6 alpha_l/d, Ranz-Marshall con d) e INTERFASE
                    !     RESUELTA (|grad alpha_l|, placa con L = dz). La celda
                    !     de SUPERFICIE del bano (continua por la regla de
                    !     superficie libre aunque alpha_l < 0.3) es interfase
                    !     resuelta: con liq_continuous elemental recibia el area
                    !     de gota, 60-600x la de la superficie, y el gas de esa
                    !     capa salia a T_l en un paso.
                    ! (auditoria 4, M4-9) MEZCLA entre la pelicula del lecho y la
                    ! morfologia de fuera: rampa 0 -> 1 en alpha_s 1e-2 .. 2e-2
                    ! (un interruptor en 1e-2 saltaba x2500 para gotas que
                    ! cruzan chatarra rala)
                    fbed = min(1.0_dp, max(0.0_dp, (as - ALPHA_BED) / ALPHA_BED))
                    G_in = 0.0_dp; G_out = 0.0_dp
                    if (fbed > 0.0_dp) then
                        wet = min(1.0_dp, al / max(1.0_dp - as, SMALL))
                        G_in = h_sphere(dp_) * 6.0_dp * as / dp_ * wet
                    end if
                    if (fbed < 1.0_dp) then
                        cont_el = liq_continuous(al, as)
                        cont = cont_el
                        if (ws_liq_cont_valid) cont = ws_liq_cont(i,j,k)
                        ! (auditoria 4, A4-3) el liquido CONTINUO es interfase
                        ! resuelta, con cualquier alpha_l: la celda de superficie
                        ! del bano barre alpha_l de 0 a 1 al subir el nivel y con
                        ! la logistica en alpha_l entre 0.3 y ~0.45 recibia area
                        ! de gota (x1200 en 0.3: el gas de la capa salia a T_l
                        ! en un paso, el sintoma que A3-2 decia cerrar). La
                        ! logistica queda solo para el liquido DISPERSO (gotas
                        ! con cola hacia la interfase al acercarse a 0.3).
                        if (cont) then
                            f_disp = 0.0_dp
                        else
                            xb = A_AIAD * (al - ALPHA_AIAD_LIM)
                            f_disp = 1.0_dp / (1.0_dp + exp(min(max(xb, -60.0_dp), 60.0_dp)))
                        end if
                        ! (auditoria 4, M4-10) area de la interfase resuelta por
                        ! CARAS: sum |alpha_P - alpha_N| A_f / (2 V), que para una
                        ! superficie nitida 1|0.5|0 da A/V en la celda de superficie
                        ! (el gradiente central daba 0.5 A/V y pulsaba con la
                        ! posicion del nivel); y placa con la longitud de flujo del
                        ! horno (R_shell), no la altura de celda (h ~ L^-1/2: con dz
                        ! salia x8-10 y dependia de la malla)
                        a_fs = (abs(al - anb(i-1,j,k, al)) * m%Ar(i-1,j,k) + abs(al - anb(i+1,j,k, al)) * m%Ar(i,j,k) &
                              + abs(al - anb(i,jm,k, al)) * m%Ath(i,j,k) + abs(al - anb(i,jp,k, al)) * m%Ath(i,j,k) &
                              + abs(al - anb(i,j,k-1, al)) * m%Az(i,j,k-1) + abs(al - anb(i,j,k+1, al)) * m%Az(i,j,k)) &
                              / (2.0_dp * m%vol(i,j,k))
                        ! el liquido CONTINUO intercambia por las CARAS (lazo de
                        ! abajo, M4-10): aqui solo las gotas del disperso
                        G_out = f_disp * h_sphere(d) * 6.0_dp * al / d
                    end if
                    G = fbed * G_in + (1.0_dp - fbed) * G_out
                    G = G * m%vol(i,j,k)
                    if (G <= 0.0_dp) cycle
                    ! (B5-3) gas en forma log: relajacion exacta hacia la T
                    ! nueva del liquido, que cumple el balance
                    pc = 0.0_dp
                    if (present(sh)) pc = sh%p(i,j,k)
                    Cg_log = gas_heat_capacity_ref(ag, pc, gas%cp(i,j,k), m%vol(i,j,k), cfg)
                    call gas_log_exchange(Cg_log, max(gas%T(i,j,k), T_MIN_GAS), cl, liq%T(i,j,k), G, cfg%dt, Tg_new, q)
                    gas%T(i,j,k) = Tg_new
                    liq%T(i,j,k) = liq%T(i,j,k) + q / cl
                    call audit_add(AUD_IPH_GAS,  q)
                    call audit_add(AUD_IPH_LIQ, -q)
                end do
            end do
        end do

        ! ---- Superficie LIBRE por caras verticales (auditoria 4, M4-10) ----
        ! Una interfase nitida (celda llena | celda vacia) no tiene ninguna
        ! celda con las dos fases y el intercambio por celda no actuaba
        ! (bath_test_cold: el gas a 300 K sobre acero a 1850 K no se calentaba).
        ! En cada cara (k | k+1) el nodo liquido es el de la celda con mas
        ! liquido continuo y el nodo gas el de la otra, con area A_z |d alpha_l|;
        ! h = conduccion 2k/dz + placa con la longitud de flujo L. Dos nodos
        ! implicitos exactos; cada rank aplica solo a sus celdas propias y la
        ! Q se evalua igual a los dos lados de la frontera de bloque. Fuera
        ! del lecho (celdas de superficie: sin chatarra el area de pelicula no
        ! aplica).
        ! (auditoria 5, M5-2) para que los dos ranks de una frontera de bloque
        ! en z evaluen la MISMA q hace falta que lean las mismas T: el lazo
        ! por celda de arriba ya modifico las T propias (el halo del vecino
        ! es rancio) y un barrido Gauss-Seidel en k usaba en la cara k|k+1
        ! la T recien modificada por la cara k-1|k. Dos barridos por PARIDAD
        ! de la cara GLOBAL (k_g par, luego impar), con halos de T frescos
        ! antes de cada uno: dentro de un barrido ninguna celda toca dos
        ! caras, asi que cada cara ve las T de entrada del barrido (dos nodos
        ! exactos, sin sobrepaso) y el resultado no depende del corte. La
        ! matriz no lo veia: la superficie de los bancos queda a k = 4-5 y los
        ! cortes en k = 8 (n4) y 5|6 (n9); produccion 2x3x2 corta en k = 42.
        k_off = m%topo%kglobal_start - 1
        do sweep = 0, 1
        call mpi_exchange_halos_3d(gas%T, m%topo)
        call mpi_exchange_halos_3d(liq%T, m%topo)
        do k = 0, m%nz
            if (mod(k + k_off, 2) /= sweep) cycle
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0 .or. m%cell_type(i,j,k+1) == 0) cycle
                    ! (auditoria 5, B5-2) rampa del lecho (1 - fbed) de la
                    ! celda con mas chatarra, como el lazo por celda (M4-9):
                    ! el corte duro en 2e-2 saltaba al cruzarlo
                    fb2 = min(1.0_dp, max(0.0_dp, (max(sol%alpha_s(i,j,k), sol%alpha_s(i,j,k+1)) &
                                                   - ALPHA_BED) / ALPHA_BED))
                    if (fb2 >= 1.0_dp) cycle
                    if (liq%alpha(i,j,k) >= liq%alpha(i,j,k+1)) then
                        kl = k; kg = k + 1
                    else
                        kl = k + 1; kg = k
                    end if
                    al = liq%alpha(i,j,kl); ag = gas%alpha(i,j,kg)
                    ! (auditoria 5, B5-1) el nodo liquido es CONTINUO por la
                    ! misma regla que el resto del codigo (ws_liq_cont, con la
                    ! superficie libre): la celda de superficie con alpha_l <
                    ! 0.3 (bath_fill 0.15-0.22) quedaba sin intercambio y el
                    ! area saltaba al cruzar 0.3
                    if (ws_liq_cont_valid) then
                        cont = ws_liq_cont(i,j,kl)
                    else
                        cont = (al >= ALPHA_LIQ_CONT)
                    end if
                    if (.not. cont .or. al <= 1.0e-6_dp .or. ag <= 1.0e-6_dp) cycle
                    a_fs = abs(liq%alpha(i,j,k) - liq%alpha(i,j,k+1)) * m%Az(i,j,k) * (1.0_dp - fb2)
                    if (a_fs <= 0.0_dp) cycle
                    cl = al * liq%rho(i,j,kl) * liq%cp(i,j,kl) * m%vol(i,j,kl)
                    cg = ag * gas%rho(i,j,kg) * gas%cp(i,j,kg) * m%vol(i,j,kg)
                    if (cl <= 0.0_dp .or. cg <= 0.0_dp) cycle
                    k_mol = gas%mu(i,j,kg) * gas%cp(i,j,kg) / PR_GAS_MOL
                    urel = sqrt((gas%ur(i,j,kg) - liq%ur(i,j,kl))**2 + &
                                (gas%uth(i,j,kg) - liq%uth(i,j,kl))**2 + &
                                (gas%uz(i,j,kg) - liq%uz(i,j,kl))**2)
                    G = k_mol * (2.0_dp / m%dz(kg) + 0.664_dp * PR_GAS_MOL**(1.0_dp/3.0_dp) * &
                        sqrt(gas%rho(i,j,kg) * urel * max(cfg%R_shell, m%dz(kg)) / (gas%mu(i,j,kg) + SMALL)) &
                        / max(cfg%R_shell, m%dz(kg))) * a_fs
                    ! (B5-3) gas en forma log, mismo helper que el lazo por celda
                    pc = 0.0_dp
                    if (present(sh)) pc = sh%p(i,j,kg)
                    Cg_log = gas_heat_capacity_ref(ag, pc, gas%cp(i,j,kg), m%vol(i,j,kg), cfg)
                    call gas_log_exchange(Cg_log, max(gas%T(i,j,kg), T_MIN_GAS), cl, liq%T(i,j,kl), G, cfg%dt, Tg_new, q)
                    if (kg >= 1 .and. kg <= m%nz) then
                        gas%T(i,j,kg) = Tg_new
                        call audit_add(AUD_IPH_GAS, q)
                    end if
                    if (kl >= 1 .and. kl <= m%nz) then
                        liq%T(i,j,kl) = liq%T(i,j,kl) + q / cl
                        call audit_add(AUD_IPH_LIQ, -q)
                    end if
                end do
            end do
        end do
        end do
    contains
        ! Ranz-Marshall para esfera de diametro dd [W/m2/K]
        pure real(dp) function h_sphere(dd)
            real(dp), intent(in) :: dd
            real(dp) :: Re
            Re = gas%rho(i,j,k) * urel * dd / (gas%mu(i,j,k) + SMALL)
            h_sphere = k_mol / dd * (2.0_dp + 0.6_dp * sqrt(Re) * PR_GAS_MOL**(1.0_dp/3.0_dp))
        end function h_sphere
        ! Placa plana (interfase resuelta) [W/m2/K]: conduccion hasta el
        ! centro de la celda (2 k / dz: gas en reposo sobre el bano) + conveccion
        ! forzada con la longitud de flujo L (M4-10: con L = dz la parte
        ! convectiva iba como dz^-1/2; con L = R_shell en la conduccion el gas
        ! en reposo no intercambiaba nada)
        pure real(dp) function h_plate(L)
            real(dp), intent(in) :: L
            real(dp) :: Re
            Re = gas%rho(i,j,k) * urel * L / (gas%mu(i,j,k) + SMALL)
            h_plate = k_mol * (2.0_dp / m%dz(k) + 0.664_dp * sqrt(Re) * PR_GAS_MOL**(1.0_dp/3.0_dp) / L)
        end function h_plate
        ! alpha_l de la vecina; inactiva (pared, halo fisico) = la propia
        pure real(dp) function anb(ii, jj, kk, aown)
            integer, intent(in)  :: ii, jj, kk
            real(dp), intent(in) :: aown
            if (m%cell_type(ii,jj,kk) == 0) then
                anb = aown
            else
                anb = liq%alpha(ii,jj,kk)
            end if
        end function anb
    end subroutine compute_gas_liquid_heat

    !---------------------------------------------------------------------------
    ! Tau mínimo GLOBAL del acople interfase del último paso [s]
    !---------------------------------------------------------------------------
    function interphase_tau_global(m) result(tau)
        type(mesh_t), intent(in) :: m
        real(dp) :: tau
        if (m%is_parallel) then
            call mpi_allreduce_min(tau_iph_local, tau, m%topo)
        else
            tau = tau_iph_local
        end if
    end function interphase_tau_global

end module mod_interphase_ht
