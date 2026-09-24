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
    logical, save :: ws_Fc_valid = .false.
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
    real(dp), allocatable :: ws_pcorr_g(:,:,:)
    logical, save :: ws_pcorr_valid = .false.
    ! Bolsa SELLADA del lecho (F2.5): celda con chatarra (alpha_s >= 1e-2) y
    ! sin gas activo (alpha_g < ALPHA_FLOW_CUTOFF), p.ej. chatarra empaquetada
    ! que funde en sitio (alpha_s 0.9 + alpha_l 0.1). Bloqueada por Ergun, su
    ! fila del Poisson es casi vacia y su p deriva (-10 kPa); NO es presion de
    ! gas: para el gradiente del GAS es pared (momento y Poisson). Las celdas
    ! de bano puro (alpha_s < 1e-2) NO entran: el gas de la pelicula de
    ! superficie necesita ver la linea hidrostatica del bano de abajo.
    logical, allocatable :: ws_gas_wall(:,:,:)
    logical, save :: ws_gas_wall_valid = .false.

contains

    subroutine ensure_workspace(m)
        type(mesh_t), intent(in) :: m

        if (allocated(ws_aP)) return
        allocate(ws_aW(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(ws_aE, ws_aS, ws_aN, ws_aB, ws_aT, ws_aP, ws_Su, mold=ws_aW)
        allocate(ws_Fr, ws_Fth, ws_Fz, ws_Mr, ws_Mth, ws_Mz, ws_lim, mold=ws_aW)
        allocate(ws_liq_cont(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        ws_liq_cont = .true.
        allocate(ws_liq_cont_prev, ws_pv_active, mold=ws_liq_cont)
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
        allocate(ws_pcorr_g, mold=ws_aW); ws_pcorr_g = 0.0_dp
        allocate(ws_gas_wall, mold=ws_liq_cont); ws_gas_wall = .false.
    end subroutine ensure_workspace

end module mod_workspace
