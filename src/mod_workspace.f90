!===============================================================================
! mod_workspace.f90 - Workspace persistente de coeficientes (C4.1, hallazgo 3.22a)
!
! Los 7 ensambladores (momentum, energía, especies, k-eps, fracción de
! volumen, presión, radiación DO) alocaban/dealocaban los 8 arrays de
! coeficientes en CADA llamada (~24 alloc/dealloc de campos completos por
! iteración externa). Aquí viven una sola vez, con los halos estándar
! (-1:n+2). Es seguro compartirlos porque:
!   (a) cada rank es mono-hilo y los ensambladores nunca se anidan, y
!   (b) TODOS los ensambladores ceran los 8 arrays completos antes de
!       usarlos, así que el contenido previo jamás se lee
! => el cambio es BIT-idéntico por construcción (verificado con h5diff).
!
! Uso en cada ensamblador:
!     use mod_workspace, only: ensure_workspace, aW => ws_aW, ... , Su => ws_Su
!     ...
!     call ensure_workspace(m)
!===============================================================================
module mod_workspace
    use mod_constants
    use mod_types_3d
    implicit none

    real(dp), allocatable :: ws_aW(:,:,:), ws_aE(:,:,:)
    real(dp), allocatable :: ws_aS(:,:,:), ws_aN(:,:,:)
    real(dp), allocatable :: ws_aB(:,:,:), ws_aT(:,:,:)
    real(dp), allocatable :: ws_aP(:,:,:), ws_Su(:,:,:)
    ! Flujos de masa EFECTIVOS del líquido [kg/s] por las caras + de cada
    ! celda (este i+1/2, norte j+1/2, tope k+1/2), promediados sobre los
    ! sub-pasos del transporte de alpha (limitador de hueco incluido).
    ! Los consume solve_energy_3d para que la convección del líquido mueva
    ! exactamente la masa que movió la continuidad (forma alpha^n exacta).
    ! ws_flux_valid lo pone solve_volume_fraction (camino explícito) y lo
    ! quita el fallback implícito. ws_M*/ws_lim: temporales del limitador.
    real(dp), allocatable :: ws_Fr(:,:,:), ws_Fth(:,:,:), ws_Fz(:,:,:)
    real(dp), allocatable :: ws_Mr(:,:,:), ws_Mth(:,:,:), ws_Mz(:,:,:)
    real(dp), allocatable :: ws_lim(:,:,:)
    ! Plan D D2.2: fraccion de la entrada de liquido pedida por el Poisson que
    ! CUPO en la celda en el ultimo transporte de alpha del paso (agregado de
    ! los sub-pasos; 1 donde no hubo entrada). El Poisson de la iteracion
    ! externa siguiente escala con ella sus caras de liquido hacia la celda.
    ! Solo vale dentro del paso en que se calculo (ws_lim_step_id): sin
    ! estado entre pasos => nada que persistir en el reinicio.
    real(dp), allocatable :: ws_lim_step(:,:,:)
    ! Plan E E2 (oct-2026): volumen de liquido por unidad de tiempo [m3/s]
    ! que entro a cada celda por caras que el Poisson NO enlazo (goteo
    ! disperso, regla del dador, derrame) en el ultimo transporte de alpha
    ! del paso: fuente CONOCIDA de la ecuacion de presion de la iteracion
    ! siguiente (termino de drift-flux de la continuidad de mezcla). Solo
    ! vale dentro del paso (ws_pc_unl_id): sin estado en el reinicio.
    real(dp), allocatable :: ws_pc_unl(:,:,:)
    logical, save :: ws_pc_unl_valid = .false.
    integer, save :: ws_pc_unl_id = -huge(1)
    ! Plan D D2.2b: celdas con presion de fluido PARA EL LIQUIDO. Falsa en la
    ! celda cuyo liquido quedo sin ninguna cara abierta en el ultimo Poisson
    ! del paso (hidraulicamente sellada para el liquido, tenga o no gas): es
    ! PARED para el gradiente de presion del liquido (diferencia unilateral)
    ! y su liquido no se mueve. Sin ella, la celda de bano sobre un poro
    ! lleno diferenciaba a traves de la presion rancia del poro y caia a g/2
    ! contra una cara cerrada (bed_flood: sonda [PROBE-MOM], presion/grav 0.7).
    ! Solo vale dentro del paso (ws_pv_liq_id): sin estado en el reinicio.
    logical, allocatable :: ws_pv_liq(:,:,:)
    logical, save :: ws_pv_liq_valid = .false.
    integer, save :: ws_pv_liq_id = -huge(1)
    logical, save :: ws_lim_step_valid = .false.
    integer, save :: ws_lim_step_id = -huge(1)
    logical, save :: ws_flux_valid = .false.
    ! Mascara de LIQUIDO CONTINUO (Bug 15): la calcula multiphase_iteration
    ! (necesita alpha_s) antes de los solves; momentum y presion la leen.
    ! Sin ella (camino monofasico) rige el umbral ALPHA_FLOW_CUTOFF.
    logical, allocatable :: ws_liq_cont(:,:,:)
    logical, save :: ws_liq_cont_valid = .false.
    ! Mascara de la llamada anterior: detecta la transicion disperso ->
    ! continuo (la velocidad del liquido debe entrar desde la fase continua
    ! vecina, no desde el drift: con la del gas 'horneada' exigia MPa)
    logical, allocatable :: ws_liq_cont_prev(:,:,:)
    ! Celdas CON alguna fase continua en el acople P-V (Bug 16): las demas
    ! no tienen presion de fluido — su pp es 0 y el valor que guarden queda
    ! congelado. Momento las trata como pared en dp/dx y la correccion de
    ! presion les impone el Neumann de sus vecinas con fluido.
    logical, allocatable :: ws_pv_active(:,:,:)
    logical, save :: ws_pv_valid = .false.
    ! Velocidad de DRIFT-FLUX del liquido disperso (Bug 15), calculada UNA
    ! vez por iteracion externa en compute_liquid_drift (mod_continuity):
    ! gas + sedimentacion terminal, acotada; en el lecho la sedimentacion
    ! se limita a la velocidad de percolacion sqrt(2 g d_p). La leen
    ! momentum (celdas dispersas) y el transporte de alpha.
    real(dp), allocatable :: ws_ud_r(:,:,:), ws_ud_th(:,:,:), ws_ud_z(:,:,:)
    ! Velocidad terminal EFECTIVA usada en el drift (0 donde no aplica):
    ! fija el arrastre fisico gas-gota K = alpha_l (rho_l-rho_g) g / u_t
    real(dp), allocatable :: ws_ut(:,:,:)
    ! ws_ud_* calculado con RELAJACION desde liq_old (multiphase) en esta
    ! iteracion: el transporte de alpha lo reutiliza en vez de recomputar
    logical, save :: ws_drift_valid = .false.
    ! Flujos VOLUMETRICOS conservativos del liquido continuo [m3/s] por las
    ! caras + de cada celda (este, norte, tope), exportados por el Poisson de
    ! volumen (Bug 19, Plan C F1/F2): Q = Q* + a_nb (pp_P - pp_nb), con
    ! Q* = alpha_f u_f A el flujo de Rhie-Chow y a_nb = alpha_f d_f A/delta. Su
    ! divergencia por celda es EXACTAMENTE el residuo del Poisson (mas el
    ! almacenamiento de compliance/acustico), asi que el transporte de alpha
    ! que los use no llena ni drena celdas que el Poisson dejo en balance.
    ! ws_Fc_lk_*: la cara esta ENLAZADA en el Poisson del liquido (ambas
    ! celdas con liquido continuo); en las demas caras el transporte cae al
    ! flujo reconstruido de la velocidad efectiva (disperso / drift).
    real(dp), allocatable :: ws_Fc_r(:,:,:), ws_Fc_th(:,:,:), ws_Fc_z(:,:,:)
    integer,  allocatable :: ws_Fc_lk_r(:,:,:), ws_Fc_lk_th(:,:,:), ws_Fc_lk_z(:,:,:)  ! 1 = enlazada
    ! ws_Fc_af_*: alpha_f que uso el Poisson en esa cara (D2.6): el transporte
    ! de alpha convierte Q -> rho u_f A dividiendo por EXACTAMENTE esta
    ! fraccion (en la cara de superficie libre es la de la donante, no la
    ! media con la celda de gas, que valdria la mitad y doblaria el caudal)
    real(dp), allocatable :: ws_Fc_af_r(:,:,:), ws_Fc_af_th(:,:,:), ws_Fc_af_z(:,:,:)
    ! D2.6 regla cinematica: el liquido continuo de la celda tiene alguna
    ! cara de liquido abierta en esa direccion en el ultimo Poisson del paso
    ! (vigencia: ws_pv_liq_id). Sin cara abierta la componente es nula.
    logical, allocatable :: ws_liq_fr(:,:,:), ws_liq_fth(:,:,:), ws_liq_fz(:,:,:)
    logical, save :: ws_Fc_valid = .false.
    ! Volumen de gas que la compresibilidad pidio ventear y COMP_SRC_CAP no
    ! dejo salir [m3] (auditoria M26): se acarrea al paso siguiente. ws_cc es
    ! el del inicio del paso (estado: va al snapshot de reinicio) y ws_cc_new
    ! el que deja la ultima iteracion externa.
    real(dp), allocatable :: ws_cc(:,:,:), ws_cc_new(:,:,:)
    ! Presion manometrica al INICIO del paso (auditoria M25): referencia
    ! p^n de la densidad rho(P0 + p^n, T^n) en la fuente de compresibilidad.
    ! Se copia de sh%p al empezar cada paso (sh%p va al reinicio).
    real(dp), allocatable :: ws_p_n(:,:,:)
    ! Plan G (modelo de mezcla, mod_mixture_3d): flujo VOLUMETRICO
    ! conservativo de la mezcla [m3/s] por las caras + de cada celda
    ! (Q = Q* + a (pp_P - pp_N), el que el Poisson acaba de hacer
    ! solenoidal) y velocidad de deslizamiento de la celda [m/s] (rapidez
    ! relativa liquido-gas, vertical, liquido hacia abajo). Valen solo dentro
    ! del paso (ws_mix_id): sin estado entre pasos.
    real(dp), allocatable :: ws_mQ_r(:,:,:), ws_mQ_th(:,:,:), ws_mQ_z(:,:,:)
    real(dp), allocatable :: ws_mW(:,:,:)
    ! coeficientes de Ergun de cada fase en las celdas del LECHO (0 fuera):
    ! el transporte evalua con ellos el flujo fraccional de Buckley-Leverett
    ! lambda_l/lambda_T, lambda_q = alpha_q^2/K_q, con la alpha del sub-paso
    real(dp), allocatable :: ws_mKl(:,:,:), ws_mKg(:,:,:)
    ! peso disperso de las gotas libres (logistica AIAD), 0 fuera
    logical, save :: ws_mix_valid = .false.
    ! Temperatura de ENTRADA del fundido del paso [K] (auditoria 12-oct-2026,
    ! A3): copia de sol%T_s tomada justo despues de compute_melting y ANTES del
    ! colapso, que mezcla en sol%T_s la chatarra que cae sobre la celda que
    ! funde. La energia del liquido la usa como T_src de mdot. Se recalcula
    ! cada paso antes de usarse: sin estado en el reinicio.
    real(dp), allocatable :: ws_Tsrc(:,:,:)
    integer, save :: ws_mix_id = -huge(1)
    ! Correccion de la presion que ve el GAS en una celda de bano (Plan C
    ! F1): p_gas = p + rho_l g_eff dz (1/2 - alpha_l). El Poisson de mezcla
    ! tiene una sola p por celda y el momento del liquido la pone sobre SU
    ! linea hidrostatica; el gas de la celda de encima leia esa p de centro
    ! (que incluye media carga de liquido) y salia disparado (bath_test:
    ! 50-200 m/s sobre un bano en reposo, y la niebla arrancada montaba en
    ! el). Con liquido estratificado en el fondo de la celda (espesor
    ! alpha_l dz) la p del gas en la interfase es la de la linea del liquido
    ! evaluada en su tope: p + rho_l g dz (1/2 - alpha_l). Solo celdas de
    ! liquido continuo fuera del lecho (alpha_s < 1e-2); 0 en las demas.
    ! Lo usan el momento del gas y su contribucion al Poisson (gradientes
    ! de celda y de cara).
    ! Hueco de poro que le queda al liquido en cada celda del LECHO (F2.8):
    ! liq_cap - alpha_l si alpha_s >= 1e-2, 1 en el resto. La cara del
    ! Poisson del liquido hacia una celda del lecho sin hueco se CIERRA
    ! (a = 0, Q* = 0, simetrico), para que la ecuacion de presion diga lo
    ! mismo que el limitador: B1 v22 (t = 34 s) tenia 12 celdas exactamente
    ! en su cap de poro con 70-360 kPa porque el Poisson seguia empujando
    ! liquido que el limitador rechazaba (water packing).
    real(dp), allocatable :: ws_liq_room(:,:,:)
    logical, save :: ws_liq_room_valid = .false.
    ! Plan E E1b: mascara del gas residual de poro saturado FUERA del acople,
    ! fijada UNA vez por paso (primera iteracion externa) para que la fila no
    ! alterne blanda/rigida entre outers (banco e1b: pp de signo alternante)
    logical, allocatable :: ws_sat_goff(:,:,:)
    integer, save :: ws_sat_goff_id = -huge(1)
    ! Gas PERCOLANTE (F2.16, Hilfer 1998): el gas de la celda esta conectado
    ! al freeboard por un camino de celdas cuyo gas puede moverse. El gas NO
    ! percolante es una subfase DESCONECTADA (atrapada): inmovil, su presion
    ! no es parte del campo conectado y no debe entrar al acople P-V. El
    ! criterio es de CAMINO, no local: F2.13 lo probaba celda a celda y al
    ! declarar pared a las celdas del piso de poro dejaba encerrada a una
    ! vecina con alpha_g = 0.16 que si tenia movilidad local (B1 v33,
    ! t = 204 s: 1.38 MPa).
    logical, allocatable :: ws_gas_perc(:,:,:)
    ! Celdas a las que el gas PUEDE llegar (F2.21): percolantes mas una capa
    ! de vecinas fuera del lecho. Es GEOMETRICO (no depende del flujo), asi
    ! que la cara existe ANTES de que la celda empiece a drenar; un criterio
    ! reactivo llega siempre un paso tarde (F2.18).
    logical, allocatable :: ws_gas_reach(:,:,:)
    logical, save :: ws_gas_perc_valid = .false.

contains

    subroutine ensure_workspace(m)
        type(mesh_t), intent(in) :: m

        if (allocated(ws_aP)) return
        allocate(ws_aW(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(ws_aE, ws_aS, ws_aN, ws_aB, ws_aT, ws_aP, ws_Su, mold=ws_aW)
        allocate(ws_Fr, ws_Fth, ws_Fz, ws_Mr, ws_Mth, ws_Mz, ws_lim, mold=ws_aW)
        allocate(ws_lim_step, mold=ws_aW); ws_lim_step = 1.0_dp
        allocate(ws_cc, ws_cc_new, mold=ws_aW); ws_cc = 0.0_dp; ws_cc_new = 0.0_dp
        allocate(ws_p_n, mold=ws_aW); ws_p_n = 0.0_dp
        allocate(ws_pc_unl, mold=ws_aW); ws_pc_unl = 0.0_dp
        allocate(ws_liq_cont(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        ws_liq_cont = .true.
        allocate(ws_liq_cont_prev, ws_pv_active, mold=ws_liq_cont)
        allocate(ws_pv_liq, mold=ws_liq_cont); ws_pv_liq = .true.
        ws_liq_cont_prev = .true.; ws_pv_active = .true.
        allocate(ws_ud_r, ws_ud_th, ws_ud_z, ws_ut, mold=ws_aW)
        ws_ud_r = 0.0_dp; ws_ud_th = 0.0_dp; ws_ud_z = 0.0_dp; ws_ut = 0.0_dp
        ws_Fr = 0.0_dp; ws_Fth = 0.0_dp; ws_Fz = 0.0_dp
        ws_Mr = 0.0_dp; ws_Mth = 0.0_dp; ws_Mz = 0.0_dp; ws_lim = 1.0_dp
        allocate(ws_Fc_r, ws_Fc_th, ws_Fc_z, mold=ws_aW)
        ws_Fc_r = 0.0_dp; ws_Fc_th = 0.0_dp; ws_Fc_z = 0.0_dp
        allocate(ws_Fc_lk_r(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(ws_Fc_lk_th, ws_Fc_lk_z, mold=ws_Fc_lk_r)
        ws_Fc_lk_r = 0; ws_Fc_lk_th = 0; ws_Fc_lk_z = 0
        allocate(ws_Fc_af_r, ws_Fc_af_th, ws_Fc_af_z, mold=ws_aW)
        ws_Fc_af_r = 0.0_dp; ws_Fc_af_th = 0.0_dp; ws_Fc_af_z = 0.0_dp
        allocate(ws_liq_fr, ws_liq_fth, ws_liq_fz, mold=ws_liq_cont)
        ws_liq_fr = .true.; ws_liq_fth = .true.; ws_liq_fz = .true.
        allocate(ws_gas_perc, ws_gas_reach, mold=ws_liq_cont)
        ws_gas_perc = .true.; ws_gas_reach = .true.
        allocate(ws_liq_room, mold=ws_aW); ws_liq_room = 1.0_dp
        allocate(ws_sat_goff, mold=ws_liq_cont); ws_sat_goff = .false.
        allocate(ws_Tsrc, mold=ws_aW); ws_Tsrc = 0.0_dp
        allocate(ws_mQ_r, ws_mQ_th, ws_mQ_z, ws_mW, ws_mKl, ws_mKg, mold=ws_aW)
        ws_mQ_r = 0.0_dp; ws_mQ_th = 0.0_dp; ws_mQ_z = 0.0_dp; ws_mW = 0.0_dp
        ws_mKl = 0.0_dp; ws_mKg = 0.0_dp
    end subroutine ensure_workspace

end module mod_workspace
