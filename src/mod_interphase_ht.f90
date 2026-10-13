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
    use mod_audit, only: audit_add, AUD_IPH_SOL, AUD_IPH_GAS, AUD_IPH_LIQ
    use mod_mpi_topology, only: mpi_allreduce_min
    use mod_types_3d
    use mod_melting_3d, only: solid_T_from_enthalpy
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

    subroutine compute_interphase_heat(liq, gas, sol, m, cfg)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(inout) :: sol
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

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
                    cap_g = gas%alpha(i,j,k) * gas%rho(i,j,k) * gas%cp(i,j,k) * m%vol(i,j,k)
                    cap_l = liq%alpha(i,j,k) * liq%rho(i,j,k) * liq%cp(i,j,k) * m%vol(i,j,k)
                    cap_s = sol%m_s(i,j,k) * cfg%cp_s
                    b_g = 0.0_dp; b_l = 0.0_dp
                    if (G_gs > 0.0_dp .and. cap_g > 0.0_dp) &
                        b_g = G_gs * cfg%dt * cap_g / (cap_g + G_gs * cfg%dt)
                    if (G_ls > 0.0_dp .and. cap_l > 0.0_dp) &
                        b_l = G_ls * cfg%dt * cap_l / (cap_l + G_ls * cfg%dt)
                    Q_gs = 0.0_dp; Q_ls = 0.0_dp
                    if (b_g + b_l > 0.0_dp .and. cap_s > 0.0_dp) then
                        T_sn = (cap_s * T_s + b_g * T_g + b_l * T_l) / (cap_s + b_g + b_l)
                        Q_gs = b_g * (T_g - T_sn) / cfg%dt
                        Q_ls = b_l * (T_l - T_sn) / cfg%dt
                    end if

                    Q_total = Q_gs + Q_ls

                    ! Apply heat to solid energy balance
                    sol%E_s(i,j,k) = sol%E_s(i,j,k) + Q_total * cfg%dt
                    ! Auditoría del intercambio interfase (el hook del gas
                    ! no ve este retiro: se contabiliza aquí tal como se
                    ! aplica, con el mismo denominador +SMALL)
                    call audit_add(AUD_IPH_SOL, Q_total * cfg%dt)

                    ! Update solid temperature (función de entalpía ÚNICA, C1.8:
                    ! antes E/(m*cp_s) chocaba con el cp_eff de la fusión)
                    if (sol%m_s(i,j,k) > SMALL) then
                        sol%T_s(i,j,k) = solid_T_from_enthalpy( &
                            sol%E_s(i,j,k) / sol%m_s(i,j,k), cfg)
                    end if

                    ! Corresponding heat removal from fluid phases
                    if (gas%alpha(i,j,k) > 1.0e-6_dp .and. abs(Q_gs) > SMALL) then
                        cap_g = gas%alpha(i,j,k) * gas%rho(i,j,k) * &
                                gas%cp(i,j,k) * m%vol(i,j,k)
                        gas%T(i,j,k) = gas%T(i,j,k) - Q_gs * cfg%dt / (cap_g + SMALL)
                        ! energía realmente retirada del estado del gas
                        call audit_add(AUD_IPH_GAS, &
                            Q_gs * cfg%dt * cap_g / (cap_g + SMALL))
                    end if
                    if (liq%alpha(i,j,k) > 1.0e-6_dp .and. abs(Q_ls) > SMALL) then
                        cap_l = liq%alpha(i,j,k) * liq%rho(i,j,k) * &
                                liq%cp(i,j,k) * m%vol(i,j,k)
                        liq%T(i,j,k) = liq%T(i,j,k) - Q_ls * cfg%dt / (cap_l + SMALL)
                        call audit_add(AUD_IPH_LIQ, &
                            Q_ls * cfg%dt * cap_l / (cap_l + SMALL))
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
    subroutine compute_gas_liquid_heat(liq, gas, sol, m, cfg)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        integer  :: i, j, k, jm, jp
        real(dp) :: al, ag, cg, cl, G, f, q, d, k_mol, urel, Re, h, a_i
        real(dp) :: gr, gth, gz, L
        d = cfg%d_droplet
        if (d <= 0.0_dp) d = 2.0e-3_dp
        do k = 1, m%nz
            do j = 1, m%ntheta
                jm = j - 1; jp = j + 1
                do i = 1, m%nr
                    if (m%cell_type(i,j,k) == 0) cycle
                    al = liq%alpha(i,j,k); ag = gas%alpha(i,j,k)
                    if (al <= 1.0e-6_dp .or. ag <= 1.0e-6_dp) cycle
                    cg = ag * gas%rho(i,j,k) * gas%cp(i,j,k) * m%vol(i,j,k)
                    cl = al * liq%rho(i,j,k) * liq%cp(i,j,k) * m%vol(i,j,k)
                    k_mol = gas%mu(i,j,k) * gas%cp(i,j,k) / PR_GAS_MOL
                    urel = sqrt((gas%ur(i,j,k) - liq%ur(i,j,k))**2 + &
                                (gas%uth(i,j,k) - liq%uth(i,j,k))**2 + &
                                (gas%uz(i,j,k) - liq%uz(i,j,k))**2)
                    if (liq_continuous(al, sol%alpha_s(i,j,k))) then
                        ! |grad alpha_l| central; vecina inactiva = sin salto
                        gr  = (anb(i+1,j,k, al) - anb(i-1,j,k, al)) / (m%r(i+1) - m%r(i-1) + SMALL)
                        gth = (anb(i,jp,k, al) - anb(i,jm,k, al)) / &
                              (m%r(i) * (m%theta(jp) - m%theta(jm)) + SMALL)
                        gz  = (anb(i,j,k+1, al) - anb(i,j,k-1, al)) / (m%z(k+1) - m%z(k-1) + SMALL)
                        a_i = sqrt(gr**2 + gth**2 + gz**2)
                        L = m%dz(k)
                        Re = gas%rho(i,j,k) * urel * L / (gas%mu(i,j,k) + SMALL)
                        h = k_mol / L * (2.0_dp + 0.664_dp * sqrt(Re) * PR_GAS_MOL**(1.0_dp/3.0_dp))
                    else
                        a_i = 6.0_dp * al / d
                        Re = gas%rho(i,j,k) * urel * d / (gas%mu(i,j,k) + SMALL)
                        h = k_mol / d * (2.0_dp + 0.6_dp * sqrt(Re) * PR_GAS_MOL**(1.0_dp/3.0_dp))
                    end if
                    G = h * a_i * m%vol(i,j,k)
                    if (G <= 0.0_dp) cycle
                    f = 1.0_dp - exp(-cfg%dt * G * (1.0_dp / cg + 1.0_dp / cl))
                    q = cg * cl / (cg + cl) * (gas%T(i,j,k) - liq%T(i,j,k)) * f
                    gas%T(i,j,k) = gas%T(i,j,k) - q / cg
                    liq%T(i,j,k) = liq%T(i,j,k) + q / cl
                    call audit_add(AUD_IPH_GAS,  q)
                    call audit_add(AUD_IPH_LIQ, -q)
                end do
            end do
        end do
    contains
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
