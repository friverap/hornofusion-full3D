!===============================================================================
! mod_constants.f90 - Physical and numerical constants for 3D EAF simulator
!
! Ugarte et al. (2024) Materials 17(21), 5139
!===============================================================================
module mod_constants
    implicit none

    integer, parameter :: dp = selected_real_kind(15, 307)

    ! Mathematical
    real(dp), parameter :: PI = 3.141592653589793238_dp
    real(dp), parameter :: TWO_PI = 6.283185307179586477_dp

    ! Physical
    real(dp), parameter :: STEFAN_BOLTZMANN = 5.670374419e-8_dp   ! W/(m^2 K^4)
    real(dp), parameter :: R_GAS = 8.314462_dp                     ! J/(mol K)
    real(dp), parameter :: GRAVITY = 9.81_dp                       ! m/s^2
    real(dp), parameter :: KELVIN_OFFSET = 273.15_dp               ! K
    real(dp), parameter :: MU_0 = 1.2566370614e-6_dp              ! H/m

    ! Steel properties (Table 2 of paper)
    real(dp), parameter :: RHO_STEEL    = 7500.0_dp    ! kg/m^3
    real(dp), parameter :: T_SOLIDUS    = 1600.0_dp    ! K
    real(dp), parameter :: T_LIQUIDUS   = 1809.0_dp    ! K
    real(dp), parameter :: T_LIQ_HBI   = 1798.1_dp    ! K
    real(dp), parameter :: CP_SOLID     = 400.0_dp     ! J/(kg K)
    real(dp), parameter :: CP_LIQUID    = 696.4_dp     ! J/(kg K)

    ! Steel properties (standard references, not in paper)
    real(dp), parameter :: H_FUSION     = 247000.0_dp  ! J/kg
    real(dp), parameter :: K_SOLID      = 35.0_dp      ! W/(m K)
    real(dp), parameter :: K_LIQUID     = 30.0_dp      ! W/(m K)
    real(dp), parameter :: MU_LIQUID    = 6.0e-3_dp    ! Pa s
    real(dp), parameter :: EMISSIVITY   = 0.7_dp
    real(dp), parameter :: BETA_EXPANSION = 1.2e-4_dp  ! 1/K

    ! Gas properties
    real(dp), parameter :: RHO_GAS_REF = 1.2_dp        ! kg/m^3
    real(dp), parameter :: CP_GAS      = 1000.0_dp     ! J/(kg K)
    real(dp), parameter :: K_GAS       = 0.5_dp        ! W/(m K)
    real(dp), parameter :: MU_GAS      = 5.0e-5_dp     ! Pa s

    ! k-epsilon
    real(dp), parameter :: C_MU      = 0.09_dp
    real(dp), parameter :: C1_EPS    = 1.44_dp
    real(dp), parameter :: C2_EPS    = 1.92_dp
    real(dp), parameter :: SIGMA_K   = 1.0_dp
    real(dp), parameter :: SIGMA_EPS = 1.3_dp
    real(dp), parameter :: PR_T      = 0.85_dp

    ! Numerical
    real(dp), parameter :: SMALL = 1.0e-30_dp
    real(dp), parameter :: LARGE = 1.0e+30_dp
    real(dp), parameter :: TOL_DEFAULT = 1.0e-6_dp

    ! Phase-fraction cutoff below which a cell is treated as void of the phase.
    ! Shared by energy, species and melting guards.
    real(dp), parameter :: ALPHA_CUTOFF = 1.0e-6_dp

    ! Umbral HIDRODINÁMICO (C2.2): por debajo, la fase no participa del
    ! acople momentum-presión (velocidad 0, sin corrección, enlace d nulo).
    ! Con el umbral de 1e-6, las celdas del frente de fusión (alpha~1e-3)
    ! tenían aP ~ alpha*rho*V/dt diminuto -> d = V/aP enorme -> Poisson en
    ! tablero de ajedrez (p oscilando +-1e5 Pa entre vecinas) y correcciones
    ! de velocidad de ~1e4 m/s que divergían a 1e14. La masa fundida sigue
    ! acumulándose vía la ecuación de alpha hasta cruzar el umbral.
    real(dp), parameter :: ALPHA_FLOW_CUTOFF = 1.0e-2_dp
    ! Fraccion RESIDUAL del solido (cierre de fase evanescente, sep-2026).
    ! Una celda con 0 < alpha_s <= este umbral ya no es un lecho: su masa y
    ! entalpia se entregan al liquido co-localizado (mismo camino que la
    ! fusion, conservacion exacta) y la celda queda EXACTAMENTE vacia.
    ! Motivo (B1, paso 235829): la guardia m_s > SMALL=1e-30 dejaba vivir
    ! solidos de microgramos cuya T_s = f(E_s/m_s) explotaba (3386 ->
    ! 35628 K en un paso) al recibir depositos no proporcionales a la masa
    ! -> T_l 1e26 -> NaN. Es el "vanishing phase problem" de los modelos de
    ! dos fluidos (Herard & Hurisse 2014; residualAlpha de OpenFOAM,
    ! 1e-4 en COMSOL Euler-Euler): por debajo del residuo la fase no tiene
    ! temperatura propia. Valor: 1e-4 (COMSOL); en la malla media son
    ! 0.05 g (eje) a 1.5 g (periferia) por celda — sin significado fisico
    ! como chatarra.
    real(dp), parameter :: ALPHA_SOLID_RESID = 1.0e-4_dp
    ! Cota física de velocidad del ACERO líquido [m/s]. El acero en el
    ! horno se mueve a O(1) m/s (plumas, EBT ~5-7 m/s); 20 m/s es 3x el
    ! máximo físico. Sin la cota, gotas apenas sobre ALPHA_FLOW_CUTOFF
    ! (inercia diminuta) acumulan velocidad por fuerzas de presión del
    ! arco hasta reventar el CFL del transporte de alpha (B1: CFL_liq
    ! 1181 => NaN a t=471 s). Misma familia que P_HYDRO_CAP/COMP_SRC_CAP.
    real(dp), parameter :: U_LIQ_MAX = 20.0_dp
    ! Cota de validez LOW-MACH del gas [m/s] (Bug 18). La formulacion
    ! low-Mach del gas (rho(p,T) con termino acustico diagonal, sin ecuacion
    ! de onda) solo vale para M << 1; con c ~ 780 m/s a 1500 K, 300 m/s son
    ! M ~ 0.4 y ya es el limite. Una solucion con M = 28 (B1 v15: 9.5 km/s)
    ! esta FUERA del dominio de validez del modelo, no es fisica que haya
    ! que conservar. Origen: celdas del lecho con el gas expulsado
    ! (alpha_g -> 0) y liquido continuo quedan hidraulicamente bloqueadas
    ! (Ergun + Kexch dominan aP => d = V/aP ~ 0), su fila del Poisson tiene
    ! coeficientes minusculos y cualquier desbalance de caras se absorbe con
    ! presiones de MPa; el gas vecino responde a ese gradiente. El CG
    ! converge (res_cont 1e-6): es el sistema discreto, no el solver.
    ! Misma familia que U_LIQ_MAX y P_HYDRO_CAP: cota del modelo, auditada
    ! (u_gas_max en audit.csv sigue mostrando cuando se toca).
    real(dp), parameter :: U_GAS_MAX = 300.0_dp
    ! Fraccion a partir de la cual el LIQUIDO es fase CONTINUA fuera del lecho
    ! (sep-2026, Bug 15): solo entonces resuelve su momento y entra al
    ! Poisson. Por debajo (gotas, niebla, salpicaduras: 0 < alpha_l < 0.3
    ! con alpha_s < 0.01) es fase dispersa y se mueve como drift-flux
    ! (velocidad del gas + sedimentacion terminal). Motivo: gotas que
    ! cruzaban ALPHA_FLOW_CUTOFF entraban al acople de presion con 20 m/s
    ! (U_LIQ_MAX) y exigian correcciones de MPa para frenarlas; esas puntas
    ! aceleraban el gas puro vecino (rho~0.3) a 400-600 m/s y a t~415 s (B1
    ! v11) la realimentacion saturo p = P_HYDRO_CAP en todo el horno, gas a
    ! km/s y el charco desplomado ("cave-in" espurio). En el lecho
    ! (alpha_s >= 0.01) el liquido sigue el tratamiento de dos fluidos con
    ! Ergun (percolacion), con el umbral ALPHA_FLOW_CUTOFF. 0.3 es el
    ! limite disperso->segregado habitual de los mapas de regimen
    ! (OpenFOAM blended interfacial models).
    real(dp), parameter :: ALPHA_LIQ_CONT = 0.3_dp
    ! Cota de la velocidad de sedimentacion [m/s]: con dz~0.1 m y dt=2 ms
    ! da CFL~1 => 1-2 sub-pasos; fisicamente u_t(2 mm) ~ 35 m/s
    real(dp), parameter :: U_SETTLE_MAX = 50.0_dp

    ! Re-solidification explicit sub-step limiter (fraction of the full mass
    ! transfer applied per timestep, CFL-like stabilization)
    real(dp), parameter :: RESOLID_LIMITER = 0.1_dp

    ! Pressure-reference "big coefficient" penalty (SIMPLE singular fix)

    ! SOR pressure solver defaults
    real(dp), parameter :: SOR_OMEGA        = 1.5_dp
    real(dp), parameter :: SOR_TOL_PRESSURE = 1.0e-5_dp
    integer,  parameter :: SOR_HALO_EVERY   = 2   ! halo exchange interval (iters)
    integer,  parameter :: SOR_CHECK_EVERY  = 10  ! global residual check interval

    ! Minimum gas temperature for the ideal-gas density update [K]
    real(dp), parameter :: T_MIN_GAS = 100.0_dp

    ! Minimum radius of the cylindrical mesh axis hole [m]
    real(dp), parameter :: R_AXIS_MIN = 0.02_dp

    ! Ergun porous media defaults
    real(dp), parameter :: D_PARTICLE = 0.10_dp   ! m (characteristic scrap chunk size)

    ! Cassie-Mayr arc defaults
    ! ARC_W is the arc cooling power [W].  Physical calibration:
    !   R_eq = P_rad / ARC_W.  With I~55 kA and R_eq~9 mOhm → P_arc~27.5 MW.
    !   ARC_W = 30 W  →  R_eq = 9.1e-3 Ohm  →  P_arc ≈ 27.5 MW  ✓
    !   ARC_W = 1e5 W →  R_eq = 2.7e-9 Ohm  →  short-circuit, P_arc ≈ 0  ✗
    real(dp), parameter :: ARC_TAU   = 3.0e-4_dp  ! s (arc time constant)
    real(dp), parameter :: ARC_W     = 30.0_dp    ! W (cooling power) — calibrated
    real(dp), parameter :: ARC_SIGMA = 1.0e3_dp   ! S/m (ionized air conductivity)
    real(dp), parameter :: ARC_T_REF = 12000.0_dp ! K (reference arc temperature)

    ! Acople de momentum gas-líquido (C2.4): K = a_l*a_g*rho_l/TAU_LG,
    ! implícito y simétrico en ambas fases. Sin él, el líquido disperso en
    ! gas (niebla del frente de fusión) quedaba en caída libre sin arrastre
    ! y el acople P-V divergía (medido p -> 1e84 en tablero de ajedrez).
    ! TAU_LG es un tiempo de relajación de régimen disperso (placeholder
    ! de una correlación de arrastre de gotas).
    real(dp), parameter :: TAU_LG = 0.01_dp   ! s

    ! Reparto del presupuesto radiativo del arco (C1.6): fracción de
    ! P_total*frac_rad que se distribuye vía Monte Carlo; el resto se
    ! deposita directo en la superficie de chatarra. Antes el MC era
    ! ADITIVO (inyectaba 0.5*frac_rad extra => hasta 125% de P_arc).
    real(dp), parameter :: MC_RAD_SHARE = 0.5_dp

    ! Arc length correlation (Eq. 3 of paper): l_a = (|V| - threshold) / gradient
    real(dp), parameter :: ARC_VOLT_THRESHOLD = 40.0_dp  ! V (anode+cathode drop)
    real(dp), parameter :: ARC_LENGTH_GRAD    = 11.5_dp  ! V/cm (column field gradient)
    real(dp), parameter :: ARC_LENGTH_MIN     = 0.01_dp  ! m (minimum arc length)

contains

    !---------------------------------------------------------------------------
    ! El liquido de la celda es fase continua (momento propio + Poisson)?
    ! Fuera del lecho: alpha_l >= ALPHA_LIQ_CONT. En el lecho (hay chatarra):
    ! el umbral hidrodinamico ordinario (el arrastre de Ergun gobierna).
    !---------------------------------------------------------------------------
    pure elemental logical function liq_continuous(al, as)
        real(dp), intent(in) :: al, as
        if (as >= 1.0e-2_dp) then
            liq_continuous = (al >= ALPHA_FLOW_CUTOFF)
        else
            liq_continuous = (al >= ALPHA_LIQ_CONT)
        end if
    end function liq_continuous

    !---------------------------------------------------------------------------
    ! Velocidad terminal de una gota de liquido en el gas local (Schiller-
    ! Naumann, punto fijo sobre Re; C_d = 0.44 en regimen de Newton).
    ! Acotada a U_SETTLE_MAX para que el sub-paso CFL siga acotado.
    !---------------------------------------------------------------------------
    pure function settling_velocity(d, rho_l, rho_g, mu_g) result(u_t)
        real(dp), intent(in) :: d, rho_l, rho_g, mu_g
        real(dp) :: u_t, Re, Cd
        integer  :: it
        u_t = 0.0_dp
        if (d <= 0.0_dp .or. rho_g <= 0.0_dp) return
        u_t = sqrt(4.0_dp * GRAVITY * d * max(rho_l - rho_g, 0.0_dp) / (3.0_dp * 0.44_dp * rho_g))
        do it = 1, 20
            Re = max(rho_g * u_t * d / max(mu_g, SMALL), 1.0e-6_dp)
            if (Re < 1000.0_dp) then
                Cd = 24.0_dp / Re * (1.0_dp + 0.15_dp * Re**0.687_dp)
            else
                Cd = 0.44_dp
            end if
            u_t = sqrt(4.0_dp * GRAVITY * d * max(rho_l - rho_g, 0.0_dp) / (3.0_dp * Cd * rho_g))
        end do
        u_t = min(u_t, U_SETTLE_MAX)
    end function settling_velocity

    !---------------------------------------------------------------------------
    ! Gradiente 1D de presion con vecinas OPCIONALES (Bug 16): una celda sin
    ! fase continua — o una celda de pared — no tiene presion de fluido y se
    ! trata como frontera (diferencia unilateral). Con la centrada a traves
    ! de ella, su valor (rancio o cero) empujaba al fluido para siempre.
    !---------------------------------------------------------------------------
    pure function pgrad(pm, p0, pp_, xm, x0, xp, okm, okp) result(g)
        real(dp), intent(in) :: pm, p0, pp_, xm, x0, xp
        logical,  intent(in) :: okm, okp
        real(dp) :: g
        if (okm .and. okp) then
            g = (pp_ - pm) / (xp - xm)
        else if (okp) then
            g = (pp_ - p0) / (xp - x0)
        else if (okm) then
            g = (p0 - pm) / (x0 - xm)
        else
            g = 0.0_dp
        end if
    end function pgrad

    !---------------------------------------------------------------------------
    ! Velocidad de PERCOLACION del liquido disperso por el lecho de chatarra:
    ! el punto estacionario de SU PROPIA ecuacion de momento, es decir donde
    ! el arrastre de Ergun iguala el peso boyante:
    !     (mu/K + C_F rho |u| / sqrt(K)) u = alpha_l (rho_l - rho_g) g
    ! (raiz positiva, forma numericamente estable). Con d_p = 0.1 m,
    ! eps = 0.5 y alpha_l = 0.01 da ~2 mm/s. La estimacion anterior por
    ! caida libre, sqrt(2 g d_p) ~ 1.4 m/s, era 700x mayor: drenaba el
    ! primer fundido de la zona caliente antes de que se acumulara y lo
    ! congelaba en la chatarra fria de abajo (B1 v14: 8 kg de bano a 30 s
    ! frente a 89 kg de la referencia v11).
    !---------------------------------------------------------------------------
    pure function percolation_velocity(alpha_l, alpha_s, rho_l, rho_g, mu_l, d_p) result(u)
        real(dp), intent(in) :: alpha_l, alpha_s, rho_l, rho_g, mu_l, d_p
        real(dp) :: u, eps, K_perm, C_F, A, B, C
        u = 0.0_dp
        if (alpha_l <= 0.0_dp .or. d_p <= 0.0_dp) return
        eps    = max(1.0_dp - alpha_s, 0.01_dp)
        K_perm = d_p**2 * eps**3 / (150.0_dp * (1.0_dp - eps)**2 + SMALL)
        C_F    = 1.75_dp / (d_p * eps**3 + SMALL)
        A = mu_l / (K_perm + SMALL)
        B = C_F * rho_l / (sqrt(K_perm) + SMALL)
        C = alpha_l * max(rho_l - rho_g, 0.0_dp) * GRAVITY
        u = 2.0_dp * C / (A + sqrt(A*A + 4.0_dp * B * C))
        u = min(u, U_SETTLE_MAX)
    end function percolation_velocity

    !---------------------------------------------------------------------------
    ! Velocidad de DRIFT-FLUX del liquido disperso: la del gas menos la
    ! terminal de sedimentacion en z, con el modulo acotado a U_SETTLE_MAX
    ! (misma cota en momento y transporte de alpha => campos consistentes;
    ! el gas en el arco puede ir a cientos de m/s y una gota arrastrada a
    ! esa velocidad rompe el sub-paso CFL del transporte).
    !---------------------------------------------------------------------------
    pure subroutine drift_velocity(ug_r, ug_th, ug_z, u_t, ur, uth, uz)
        real(dp), intent(in)  :: ug_r, ug_th, ug_z, u_t
        real(dp), intent(out) :: ur, uth, uz
        real(dp) :: vmag, f
        ur = ug_r; uth = ug_th; uz = ug_z - u_t
        vmag = sqrt(ur*ur + uth*uth + uz*uz)
        if (vmag > U_SETTLE_MAX) then
            f = U_SETTLE_MAX / vmag
            ur = ur * f; uth = uth * f; uz = uz * f
        end if
    end subroutine drift_velocity

end module mod_constants
