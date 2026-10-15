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
    real(dp), parameter :: KAPPA_VK  = 0.41_dp       ! constante de von Karman (funcion de pared)
    real(dp), parameter :: MUT_RATIO_MAX = 1.0e5_dp  ! tope de mu_t/mu (razon de viscosidad turbulenta)
    real(dp), parameter :: C1_EPS    = 1.44_dp
    real(dp), parameter :: C2_EPS    = 1.92_dp
    real(dp), parameter :: SIGMA_K   = 1.0_dp
    real(dp), parameter :: SIGMA_EPS = 1.3_dp
    real(dp), parameter :: PR_T      = 0.85_dp

    ! Numerical
    real(dp), parameter :: SMALL = 1.0e-30_dp
    real(dp), parameter :: LARGE = 1.0e+30_dp

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
    ! Umbral de LECHO (auditoria 4, B4-26): una celda con alpha_s >= ALPHA_BED
    ! tiene chatarra que gobierna (Ergun, pelicula, poro con gas residual,
    ! liquido continuo con ALPHA_FLOW_CUTOFF). Mismo valor numerico que
    ! ALPHA_FLOW_CUTOFF a proposito (M3-2: ws_bed es un interruptor que
    ! acompana a la pertenencia del liquido al Poisson). UNA definicion:
    ! antes era el literal 1e-2 en una docena de sitios.
    real(dp), parameter :: ALPHA_BED = 1.0e-2_dp
    ! Gas RESIDUAL de poro (Plan C F2.7): en una celda del LECHO (alpha_s >=
    ! 1e-2) el liquido no puede ocupar todo el hueco; queda al menos
    ! ALPHA_PORE_GAS de gas (> ALPHA_FLOW_CUTOFF, asi el gas sigue activo en
    ! el Poisson y la celda nunca queda sellada hidraulicamente). Sin esto,
    ! el fundido que percola desde un charco llenaba el poro hasta expulsar
    ! el gas y la celda, bloqueada por Ergun y sin gas, respondia a la
    ! siguiente rafaga con MPa (B1 v21, 34 s; reproductores F2.4/F2.5). El
    ! exceso se DERRAMA hacia arriba (conservativo, m_spill), nunca se
    ! recorta. Es una regularizacion del volumen, no de la presion (el canal
    ! residual de gas tipo residualAlpha en el Poisson dejaba pasar liquido
    ! a celdas selladas: 1.6 t recortadas en bath_freeze, descartado).
    real(dp), parameter :: ALPHA_PORE_GAS = 1.5e-2_dp
    ! Plan F (oct-2026, `pc_gas_spring`): sin piso de gas de poro en la
    ! capacidad del liquido (liq_cap = hueco fisico). Lo fija config_read;
    ! .true. = comportamiento F2.7 (goldens, tests unitarios).
    ! Plan G (modelo de mezcla): porosidad fluida minima para que una celda
    ! sea fluido del acople (por debajo: chatarra maciza, pared)
    real(dp), parameter :: EPS_MIX = 1.0e-4_dp
    logical, save :: pore_floor_on = .true.
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
    ! Fraccion de chatarra que define la SUPERFICIE del material (auditoria,
    ! bajos): la usan el regulador de electrodos, la carga ECS y el impacto
    ! del MC del arco (antes 0.01 / 0.05 / 0.1 para el mismo concepto). El
    ! umbral hidraulico del lecho (in_bed, 1e-2) es otro concepto.
    real(dp), parameter :: ALPHA_SCRAP_SURF = 0.05_dp
    ! Chatarra RECEPTORA del P_rad directo del arco (auditoria 5, B5-15):
    ! mismo valor que ALPHA_BED, concepto distinto (una celda del borde del
    ! crater con 1 % de chatarra ve fotones)
    real(dp), parameter :: ALPHA_ARC_RECV = 1.0e-2_dp
    ! ESPESOR EQUIVALENTE de material [m] que una capa necesita (chatarra +
    ! bano, ponderados por la gaussiana del arco hasta 4 sigma, divididos por
    ! el area ponderada) para ser la SUPERFICIE bajo la punta (M4-7, A5-1).
    ! (auditoria 6, M6-5) antes era una FRACCION del volumen de la capa (5 %):
    ! dependia de dz y con la malla de produccion (dz 0.054 m) bastaban ~13 kg
    ! de liquido ponderado para recibir P_elec (5.5 MW). 0.014 m es el 5 % de
    ! la celda de los bancos (dz 0.28 m): los bancos no cambian y la masa
    ! minima (~67 kg ponderados con sigma = 0.45 m) ya no depende de la malla.
    real(dp), parameter :: ARC_SURF_H = 0.014_dp
    ! (auditoria 7, M7-1) la CHATARRA se mide por su FRACCION del volumen
    ! ponderado de la capa (es un lecho: una capa llena de carga tiene alpha_s
    ! ~0.5, no espesor dz), con el 5 % de siempre; el espesor equivalente
    ! (M6-5) vale para el BANO. Con el espesor tambien para la chatarra, en la
    ! malla de produccion un crater a medio fundir (alpha_s < 0.22-0.37) dejaba
    ! de ser superficie y la potencia caia al bano de debajo.
    real(dp), parameter :: ARC_SURF_FRAC_S = 0.05_dp
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

    ! Fraccion maxima del liquido de una celda que congela en un paso
    ! (auditoria M9: ya no es la tasa —la congelacion es la regla de la
    ! palanca— sino la cota de positividad del transporte explicito de
    ! alpha, que aplica el sumidero junto con las salidas por caras)
    real(dp), parameter :: RESOLID_LIMITER = 0.1_dp

    ! Pressure-reference "big coefficient" penalty (SIMPLE singular fix)

    ! SOR pressure solver defaults
    real(dp), parameter :: SOR_TOL_PRESSURE = 1.0e-8_dp
    integer,  parameter :: SOR_HALO_EVERY   = 2   ! halo exchange interval (iters)
    integer,  parameter :: SOR_CHECK_EVERY  = 10  ! global residual check interval

    ! Minimum gas temperature for the ideal-gas density update [K]
    real(dp), parameter :: T_MIN_GAS = 100.0_dp
    ! Temperatura a la que vale cfg%rho_gas (auditoria, bajos): la EOS
    ! rho = rho_gas T_REF/T se referia a cfg%T_ambient, asi que un caso con
    ! T_ambient = 900 K tenia aire de 1.2 kg/m3 a 900 K (3x)
    real(dp), parameter :: T_RHO_GAS_REF = 300.0_dp
    ! Presion termodinamica de referencia [Pa]: sh%p es MANOMETRICA respecto
    ! de P0 (cero en la boveda), la absoluta es P0 + p
    real(dp), parameter :: P0_THERMO = 101325.0_dp
    ! Piso de la presion ABSOLUTA en la EOS del gas [Pa]: p < -P0 no tiene
    ! sentido fisico (solo aparece si el acople P-V se rompe y p va a la
    ! centinela -P_HYDRO_CAP); el piso mantiene rho > 0 en ese caso
    real(dp), parameter :: P_ABS_MIN = 0.05_dp * P0_THERMO

    ! Radio de la primera cara radial [m]. EJE REAL (auditoria M31, oct-2026):
    ! la cara del eje tiene area nula (A_r = r_f dtheta dz = 0) y las celdas
    ! del primer anillo son cunas que se tocan en el eje, lo que es exacto
    ! en volumen finito (ningun flujo atraviesa una linea). Antes 0.02 m: un
    ! pasador solido de 4 cm de diametro con pared en el eje.
    real(dp), parameter :: R_AXIS_MIN = 0.0_dp

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
    ! Velocidad terminal de BURBUJA en acero liquido (auditoria 4, B4-25):
    ! burbujas elipsoidales de 3-10 mm en liquidos de baja viscosidad suben a
    ! ~0.2-0.3 m/s (Clift, Grace & Weber 1978, cap. 7; en acero medido
    ! 0.2-0.25 m/s). El cierre de interfase resuelta (TAU_LG) fijaba el
    ! deslizamiento de una burbuja en el bano en g tau ~ 0.1 m/s, sin
    ! dependencia de nada: en las celdas de BURBUJA (ws_bub: bano con gas que
    ! puede deslizar y bano encima) el arrastre es el fisico,
    ! K = alpha_g alpha_l (rho_l - rho_g) g / U_BUBBLE (estado estacionario
    ! del momento de la fase dispersa, Bug 17, con la flotacion RELATIVA de la
    ! forma balanceada alpha_g (rho_mez - rho_g) g; auditoria 5, B5-10),
    ! mezclado con el peso de ws_bub.
    real(dp), parameter :: U_BUBBLE = 0.23_dp   ! m/s

    ! Cizalla interfacial de SUPERFICIE LIBRE (AIAD; Hoehne-Egorov, HZDR;
    ! ANSYS AIAD): donde el liquido NO es niebla suspendida en gas — charco,
    ! pelicula, o liquido dentro/sobre el lecho — el intercambio de momento
    ! gas-liquido es la cizalla en la interfase,
    !     K_fs = C_FS_SHEAR rho_g |u_g - u_l| |grad alpha_l|   [kg/(m3 s)],
    ! con |grad alpha_l| como densidad de area interfacial. NO es el
    ! arrastre de regimen disperso: la cizalla no iguala velocidades.
    ! Con TAU_LG en una celda 30 % liquido sobre el lecho bajo el arco,
    ! K = 1.6e5 arrastraba el charco a la velocidad del chorro (20 m/s) en
    ! ~7 pasos y lo estrellaba contra la celda del lecho en cap: 134 kPa
    ! (B1 v31, t = 113.5 s). C_FS_SHEAR = 1/2 C_D con C_D ~ 1.
    real(dp), parameter :: C_FS_SHEAR = 0.5_dp

    ! --- F2.22 (29-sep-2026): MEZCLA de morfologia, no interruptor.
    !
    ! El interruptor duro de F2.15 (cizalla si hay chatarra propia > 1e-4 o
    ! de abajo >= 1e-2; relajacion dispersa si no) saltaba una mediana de
    ! 1.5e8 veces al cruzarlo. Ningun codigo Euler-Euler hace eso: AIAD
    ! (Hoehne & Vallee, WIT Trans. Eng. Sci. 63 (2010) 123, ecs. 6-9) MEZCLA
    ! los coeficientes con una logistica
    !     f = [1 + exp(a (alpha - alpha_lim))]^-1
    ! y GENTOP (Haensch et al., Int. J. Multiphase Flow 47 (2012) 171) con la
    ! tanh equivalente; ambos con alpha_lim = 0.3 y a = 50 (Fluent) a 70.
    ! TRACE/RELAP interpolan sobre bandas de 0.2-0.3. Nunca un umbral.
    !
    ! MEDIDO (bath_test, t = 0, en reposo exacto): el campo de presion es el
    ! hidrostato de la MEZCLA con densidad de cara aritmetica (g implicita
    ! 8.984 identica en las tres caras). La fuerza neta sobre el liquido de
    ! una celda mixta NO es cero y NO es un error de discretizacion: es la
    ! flotacion relativa de la fase pesada dentro de la mezcla,
    !     F_q = alpha_q (rho_mezcla - rho_q) g
    ! (predicha -16262 N/m3, medida -14988; en las celdas puras el neto es
    ! cero). Lo que la equilibra es el arrastre de interfase. Por eso el
    ! cierre de interfase RESUELTA no se puede debilitar: con la friccion de
    ! AIAD (K ~ 1e3) la celda de superficie se separa y bath_test pierde la
    ! hidrostatica. La relajacion alpha_l alpha_g rho/TAU_LG es el cierre de
    ! Strubelj & Tiselj (2011) — el `time-scale-drag` de Fluent, estandar
    ! para interfase resuelta en malla gruesa —, y con TAU_LG = 0.01 s
    ! equilibra esa flotacion con un deslizamiento de 0.09 m/s.
    !
    ! Lo que SI se corrige: (i) la densidad es la de MEZCLA, no rho_l
    !     rho_ab = (rho_a r_a + rho_b r_b)/(r_a + r_b)
    ! (Strubelj & Tiselj 2011, ec. 4; Meller et al., HZDR), y (ii) el cierre
    ! se MEZCLA con el arrastre de gota en vez de conmutar.
    real(dp), parameter :: ALPHA_AIAD_LIM = 0.3_dp   ! centro de la mezcla
    real(dp), parameter :: A_AIAD         = 50.0_dp  ! pendiente (Fluent)

    ! Movilidad del gas en una celda (F2.16): fraccion de su balance de
    ! momento que NO se lleva el arrastre del lecho,
    !     mob = (alpha_g rho_g/DT_MOB_REF) / (alpha_g rho_g/DT_MOB_REF + drag_Ergun).
    ! mob ~ 1 gas libre; mob -> 0 gas inmovilizado por la chatarra. La
    ! distribucion es BIMODAL (medido en B1 v33: el grueso del gas activo
    ! entre 0.4 y 1.0, la cola bloqueada en 1e-5..1e-6), asi que el umbral
    ! no es critico: entre 1e-2 y 1e-4 el conteo de celdas bloqueadas cambia
    ! menos del 12 %.
    real(dp), parameter :: GAS_MOB_MIN = 1.0e-2_dp
    ! (auditoria 8, M8-2) La inercia de la movilidad se evalua con un paso de
    ! REFERENCIA fijo, no con el dt de la corrida: con alpha_g rho_g/dt la
    ! clasificacion dependia del integrador. El gas de piso de una capa
    ! saturada (eps_g = 0.015, la via de F2.7) tiene mob ~0.025 con 2 ms y
    ! ~0.01 con 5 ms: con dt >= ~6.5 ms la capa cortaba el camino y una bolsa
    ! bajo el lecho inundado quedaba pared (pocket_rise a 10 ms: sin subir y
    ! gas a 131 m/s). 2 ms es el dt de B1 (v33, donde se midio la
    ! distribucion bimodal; 125 000 pasos hasta 296 s): B1 y los bancos a
    ! 2 ms no cambian, y el desplazamiento del umbral por el dt adaptativo
    ! de B1 (~2.4 ms) es << el rango 1e-2..1e-4 medido como no critico.
    real(dp), parameter :: DT_MOB_REF = 2.0e-3_dp

    ! Fraccion residual de una fase EVANESCENTE (F2.20; CATHARE usa 1e-5,
    ! NEPTUNE lo mismo, AUSM+ para dos fluidos 1e-4). Solo entra en el aP de
    ! momento para que la movilidad de la fase residual sea la fisica
    ! (d = dt/rho) en vez del aP ficticio de 1: es el "numerical conditioning
    ! of the interfacial and wall friction source terms in order to provide a
    ! proper mechanical model for the coupling of the residual phases" de
    ! CATHARE. No es masa: la fraccion real no se toca.
    real(dp), parameter :: ALPHA_PHASE_MIN = 1.0e-5_dp

    ! Coeficientes de absorcion por fase para REPARTIR un deposito radiativo
    ! dentro de una celda (F2.30, oct-2026). Son los de la DO (mod_radiation_do
    ! usa los mismos valores): el solido absorbe KAPPA_SOLID_ABS*alpha_s y el
    ! fluido KAPPA_GAS_ABS*(1-alpha_s). Es la forma estandar (Fluent P-1/DO
    ! ecs. 5.3-10/5.3-14; MFiX TFM ecs. 20-21; Cai & Modest 2014): cada fase
    ! absorbe en proporcion a SU coeficiente, nunca a su fraccion de volumen.
    ! En un poro de chatarra (alpha_s 0.985) el gas se lleva 5e-4 del deposito.
    real(dp), parameter :: KAPPA_SOLID_ABS = 10.0_dp   ! 1/m
    real(dp), parameter :: KAPPA_GAS_ABS   = 0.3_dp    ! 1/m
    ! Acero liquido (y su mezcla con gas) en la DO: OPACO (auditoria 12-oct-2026,
    ! A11). Con KAPPA_GAS (0.3 1/m) un bano de 0.6 m tenia espesor optico ~0.2 y
    ! radiaba en volumen hacia el tazon. 100 1/m da espesor optico >> 1 en una
    ! celda (la absorcion real es superficial, micrometros).
    real(dp), parameter :: KAPPA_LIQ_ABS   = 100.0_dp  ! 1/m
    ! Espuma (atributo optico de la escoria, E2.6; calibrable en B6) y
    ! escoria densa (oxido fundido, opaca como el baño). UNA sola definicion
    ! de cada kappa (auditoria, bajos: la DO tenia copias propias)
    real(dp), parameter :: KAPPA_FOAM_ABS  = 30.0_dp   ! 1/m
    real(dp), parameter :: KAPPA_SLAG_ABS  = 100.0_dp  ! 1/m


    ! Reparto del presupuesto radiativo del arco (C1.6): fracción de
    ! P_total*frac_rad que se distribuye vía Monte Carlo; el resto se
    ! deposita directo en la superficie de chatarra. Antes el MC era
    ! ADITIVO (inyectaba 0.5*frac_rad extra => hasta 125% de P_arc).
    real(dp), parameter :: MC_RAD_SHARE = 0.5_dp

    ! Arc length correlation (Eq. 3 of paper): l_a = (|V| - threshold) / gradient
    real(dp), parameter :: ARC_VOLT_THRESHOLD = 40.0_dp  ! V (anode+cathode drop)
    ! Gradiente de campo de la columna del arco: 11.5 V/cm = 1150 V/m. Estaba
    ! declarado en V/cm y usado contra metros (auditoria 12-oct-2026, C2): con
    ! 500 V la longitud salia 40 "m" en vez de 0.40 m.
    real(dp), parameter :: ARC_LENGTH_GRAD    = 1150.0_dp  ! V/m (column field gradient)
    real(dp), parameter :: ARC_LENGTH_MIN     = 0.01_dp  ! m (minimum arc length)

contains

    !---------------------------------------------------------------------------
    ! El liquido de la celda es fase continua (momento propio + Poisson)?
    ! Fuera del lecho: alpha_l >= ALPHA_LIQ_CONT. En el lecho (hay chatarra):
    ! el umbral hidrodinamico ordinario (el arrastre de Ergun gobierna).
    !---------------------------------------------------------------------------
    pure elemental logical function liq_continuous(al, as)
        real(dp), intent(in) :: al, as
        if (as >= ALPHA_BED) then
            liq_continuous = (al >= ALPHA_FLOW_CUTOFF)
        else
            liq_continuous = (al >= ALPHA_LIQ_CONT)
        end if
    end function liq_continuous

    ! Fraccion de liquido que cabe en la celda (F2.7): hueco menos el gas
    ! residual de poro en el lecho
    pure elemental function liq_cap(as, asl) result(c)
        real(dp), intent(in) :: as, asl
        real(dp) :: c
        c = 1.0_dp - as - asl
        if (as >= ALPHA_BED .and. pore_floor_on) c = c - ALPHA_PORE_GAS
        c = max(c, 0.0_dp)
    end function liq_cap

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
    ! Gradiente de presion del LIQUIDO con SUPERFICIE LIBRE (Plan D D2.5,
    ! oct-2026): si la vecina es fluido pero no tiene liquido continuo (gas,
    ! gas con niebla), su presion es la del gas EN LA CARA (continuidad de
    ! presion en la interfase, sin tension superficial): la distancia del
    ! gradiente llega hasta la cara xf, no hasta el centro de la vecina. Con
    ! el centro, la celda superficial de una columna hidrostatica exacta
    ! sentia (0 - 3/2 rho g dz)/(2 dz) = 3/4 rho g y caia a g/4 (bath_rest:
    ! corriente fantasma; bed_flood: la superficie drenaba a -1.5 m/s hacia
    ! la celda de abajo hasta llenarla y reventarla, water packing). Con la
    ! cara: (0 - 3/2 rho g dz)/(3/2 dz) = rho g, exacto.
    !---------------------------------------------------------------------------
    pure function pgrad_fs(pm, p0, pp_, xm, x0, xp, okm, okp, fsm, fsp, xfm, xfp) result(g)
        real(dp), intent(in) :: pm, p0, pp_, xm, x0, xp, xfm, xfp
        logical,  intent(in) :: okm, okp, fsm, fsp
        real(dp) :: g, xm_e, xp_e
        xm_e = merge(xfm, xm, fsm)
        xp_e = merge(xfp, xp, fsp)
        g = pgrad(pm, p0, pp_, xm_e, x0, xp_e, okm, okp)
    end function pgrad_fs

    !---------------------------------------------------------------------------
    ! Velocidad de PERCOLACION del liquido disperso por el lecho de chatarra:
    ! el punto estacionario de SU PROPIA ecuacion de momento, es decir donde
    ! el arrastre de Ergun iguala el peso boyante:
    !     (mu/K + C_F rho |u| / sqrt(K)) u = alpha_l (rho_l - rho_g) g
    ! (raiz positiva, forma numericamente estable). Con d_p = 0.1 m,
    ! eps = 0.5 y alpha_l = 0.01 da ~0.11 m/s con la convencion de velocidad
    ! intersticial de ergun_coefficients (auditoria A6; 37 mm/s con la anterior,
    ! y el "~2 mm/s" de este comentario era del Ergun previo a Bug 21). La estimacion anterior por
    ! caida libre, sqrt(2 g d_p) ~ 1.4 m/s, era 700x mayor: drenaba el
    ! primer fundido de la zona caliente antes de que se acumulara y lo
    ! congelaba en la chatarra fria de abajo (B1 v14: 8 kg de bano a 30 s
    ! frente a 89 kg de la referencia v11).
    !---------------------------------------------------------------------------
    !---------------------------------------------------------------------------
    ! Coeficientes de Ergun (1952) del lecho de particulas d_p con fraccion
    ! solida alpha_s (porosidad eps = 1 - alpha_s), para el fluido (rho, mu):
    !   -grad p = A_E U + B_E U|U| (U superficial),
    !   A_E = 150 mu (1-eps)^2 / (d_p^2 eps^3),  B_E = 1.75 rho (1-eps) / (d_p eps^3)
    ! (ver la convencion de velocidad abajo: la rutina devuelve eps^2 A_E, eps^3 B_E)
    ! Es la UNICA definicion (momento, percolacion, tests). Hasta el 25-sep-2026
    ! el Forchheimer se escribia C_F rho |u| / sqrt(K) con C_F = 1.75/(d_p eps^3)
    ! [1/m] en vez del adimensional 1.75/sqrt(150 eps^3): el termino quedaba
    ! sqrt(150)/(d_p eps^1.5) veces (~500-800x con d_p = 0.075-0.10 m) mayor
    ! que Ergun. Consecuencias medidas: percolacion del liquido de 2-3 mm/s
    ! (Ergun: 0.1-0.2 m/s), gas de poro incapaz de ventear por el lecho y
    ! "bolsas hidraulicamente bloqueadas" que respondian con kPa-MPa
    ! (B1 v16-v27, Bug 18/19).
    !---------------------------------------------------------------------------
    !
    ! CONVENCION DE VELOCIDAD (auditoria 12-oct-2026, A6): Ergun da la caida de
    ! presion por la velocidad SUPERFICIAL U = eps u. El codigo usa la
    ! velocidad INTERSTICIAL de la fase u y el gradiente de presion pesado por
    ! la fraccion (momento: alpha(-grad p) = coef u, por volumen total). Para el
    ! lecho saturado eso es eps(-dp/dx) = eps^2 A_E u + eps^3 B_E u|u|: los
    ! coeficientes que devuelve esta rutina son los de Gidaspow,
    !   A = eps^2 A_E = 150 mu (1-eps)^2/(d_p^2 eps)     [kg/(m3 s)]
    !   B = eps^3 B_E = 1.75 rho (1-eps)/d_p             [kg/m4]
    ! Antes devolvia A_E y B_E tal cual: arrastre 1/eps^2 (viscoso) y 1/eps^3
    ! (inercial) veces mayor — 4x/8x con eps = 0.5 y 400x/8000x con eps = 0.05,
    ! justo el lecho compactado del piso de B1.
    pure subroutine ergun_coefficients(alpha_s, rho, mu, d_p, A, B)
        real(dp), intent(in)  :: alpha_s, rho, mu, d_p
        real(dp), intent(out) :: A, B
        real(dp) :: eps
        eps = max(1.0_dp - alpha_s, 0.01_dp)
        A = 150.0_dp * mu * (1.0_dp - eps)**2 / (d_p**2 * eps + SMALL)
        B = 1.75_dp * rho * (1.0_dp - eps) / (d_p + SMALL)
    end subroutine ergun_coefficients

    pure function percolation_velocity(alpha_l, alpha_s, rho_l, rho_g, mu_l, d_p) result(u)
        real(dp), intent(in) :: alpha_l, alpha_s, rho_l, rho_g, mu_l, d_p
        real(dp) :: u, A, B, C
        u = 0.0_dp
        if (alpha_l <= 0.0_dp .or. d_p <= 0.0_dp) return
        call ergun_coefficients(alpha_s, rho_l, mu_l, d_p, A, B)
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


    !---------------------------------------------------------------------------
    ! EOS UNICA del gas ideal (auditoria M25, oct-2026): rho(P0 + p, T).
    ! Antes rho(P0, T) (low-Mach puro); con la compresion fisica la presion
    ! manometrica cambia la densidad: un bolsillo de gas atrapado bajo el
    ! lecho inundado se comprime como un resorte real (P0 V = cte a T fija).
    !---------------------------------------------------------------------------
    pure elemental function gas_eos(rho_ref, T, p) result(rho)
        real(dp), intent(in) :: rho_ref, T, p
        real(dp) :: rho
        rho = rho_ref * T_RHO_GAS_REF / max(T, T_MIN_GAS) &
            * max(P0_THERMO + p, P_ABS_MIN) / P0_THERMO
    end function gas_eos

end module mod_constants
