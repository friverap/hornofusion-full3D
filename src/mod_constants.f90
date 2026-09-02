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

    ! Re-solidification explicit sub-step limiter (fraction of the full mass
    ! transfer applied per timestep, CFL-like stabilization)
    real(dp), parameter :: RESOLID_LIMITER = 0.1_dp

    ! Pressure-reference "big coefficient" penalty (SIMPLE singular fix)
    real(dp), parameter :: PREF_PENALTY = 1.0e10_dp

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

end module mod_constants
