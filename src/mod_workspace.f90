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
    ! (auditoria 6, M6-1/M6-2) volumen de demanda de compresibilidad que el
    ! paso DESCARTA [m3, con signo]: desborde de la cota del acarreo y acarreo
    ! de celdas que salen del acople, quedan selladas o sin gas. Lo escribe la
    ! ultima iteracion externa; main lo pasa al audit (m_gas_ccdrop) y lo cera.
    real(dp), allocatable :: ws_cc_drop(:,:,:)
    ! Presion manometrica al INICIO del paso (auditoria M25): referencia
    ! p^n de la densidad rho(P0 + p^n, T^n) en la fuente de compresibilidad.
    ! Se copia de sh%p al empezar cada paso (sh%p va al reinicio).
    real(dp), allocatable :: ws_p_n(:,:,:)
    ! Celda del LECHO (alpha_s propio >= 1e-2, la regla de liq_continuous):
    ! con la fuerza balanceada, ahi cada fase recupera su flotacion relativa
    ! (goteo a contracorriente; auditoria 2, N-C1). 1 = lecho, 0 = fuera.
    real(dp), allocatable :: ws_bed(:,:,:)
    ! Lecho para el GAS (auditoria 3, A3-1): ws_bed solo donde el gas es
    ! fluido del acople P-V (alpha_g >= ALPHA_FLOW_CUTOFF, percola al
    ! freeboard, ws_pv_active). El gas residual de poro / atrapado NO lleva
    ! flotacion relativa: en un poro saturado con p = hidrostatica del
    ! liquido recibiria alpha_g (rho_l - rho_g) g (73 kPa/m) contra Ergun
    ! (~18 m/s en el poro; bath_freeze n1/n4 0.58 en el intento de N-C1).
    real(dp), allocatable :: ws_bed_gas(:,:,:)
    ! Lecho para el LIQUIDO (auditoria 4, A4-1): ws_bed por la rampa de
    ! SATURACION del poro (0 con el gas en el piso ALPHA_PORE_GAS, 1 desde
    ! 2x), SIN la condicion de percolacion del gas: donde el gas esta atrapado
    ! (fuera del acople) el liquido sigue drenando clasico (bed_drain: con la
    ! mascara del gas el liquido bajo la capa densa volvia a colgar, uz -0.09
    ! frente a -0.37 m/s). ws_bed_gas = ws_bed_liq x (gas del acople), asi
    ! que donde el gas es fluido del acople ambas mascaras coinciden y
    ! sum alpha_q B_q = 0 en toda cara.
    real(dp), allocatable :: ws_bed_liq(:,:,:)
    ! Mascara de CARA vertical (k | k+1, guardada en k) de la flotacion
    ! relativa del LIQUIDO (A4-1): la rampa de saturacion de la celda
    ! RECEPTORA segun el signo de u_f del liquido al inicio de la iteracion
    ! externa (con u_f ~ 0, el minimo de las dos), o las burbujas (minimo).
    ! El liquido es clasico en una cara solo si la celda a la que va tiene
    ! hueco (gas continuo): asi drena de un poro saturado hacia un lecho
    ! seco (bed_drain) y no empuja contra una columna sellada (bed_bath_rest).
    ! Con la rampa de la celda de ORIGEN o el minimo, la cara
    ! saturado|seco quedaba como superficie libre (el colchon de presion de
    ! la forma reducida sostiene la columna) y el liquido no drenaba por Darcy
    ! (bed_drain 0.52 -> 0.42 m/s). Fija por iteracion externa: momento y
    ! Poisson leen la MISMA (cancelacion exacta del Rhie-Chow).
    real(dp), allocatable :: ws_bedl_f(:,:,:)
    ! BURBUJAS en el bano (auditoria 3, A3-5): celda de liquido continuo FUERA
    ! del lecho con gas del acople (alpha_g >= ALPHA_FLOW_CUTOFF, percola) y
    ! con bano continuo (sin lecho) ENCIMA: no es superficie libre, el gas es
    ! fase dispersa dentro del liquido y ambas fases recuperan la forma
    ! clasica (el gas sube, el liquido baja; la mezcla no cambia). Peso 0 -> 1
    ! entre 1x y 2x ALPHA_FLOW_CUTOFF. Mascara de cara = MINIMO de las dos
    ! celdas para AMBAS fases: la cara de la superficie libre (celda de bano
    ! bajo celda de superficie con alpha_g < cutoff, o bajo el freeboard) no
    ! la lleva, y el bano en reposo sigue siendo punto fijo exacto.
    real(dp), allocatable :: ws_bub(:,:,:)
    ! Mascara de CARA (k | k+1, en k) de las burbujas (A4-8): la de la celda
    ! inferior si la superior es bano INTERIOR (liquido continuo con liquido
    ! continuo encima, sin lecho). Asi el frente de una burbuja avanza hacia
    ! bano sin gas (con el minimo de celdas nunca subia) y NUNCA hacia la
    ! celda de superficie (el gas de la superficie leeria el salto de presion
    ! del bano: el chorro de F2.3). Comun a las dos fases.
    real(dp), allocatable :: ws_bub_f(:,:,:)
    ! (auditoria 6) mascara de CARA del gas (k|k+1), armada en mod_multiphase
    ! junto a ws_bedl_f: gas_face_mask = max(min de ws_bed_gas de las dos
    ! celdas, ws_bub_f) (A4-1)
    real(dp), allocatable :: ws_bedg_f(:,:,:)
    logical, save :: ws_bed_valid = .false.
    ! Flujos de MASA conservativos del GAS por las caras + [kg/s] (auditoria
    ! M24, gas): Q = Q* + a (pp_P - pp_N) del Poisson por la densidad del
    ! dador (la misma upwind del termino advectivo de la compresibilidad).
    ! ws_Fg_lk_*: la cara esta enlazada en el Poisson del gas. Vigencia: el
    ! paso en curso desde la 2.a iteracion externa (ws_Fg_valid se apaga al
    ! empezar cada paso, como ws_flux_valid: el reinicio sigue bit a bit).
    real(dp), allocatable :: ws_Fg_r(:,:,:), ws_Fg_th(:,:,:), ws_Fg_z(:,:,:)
    integer,  allocatable :: ws_Fg_lk_r(:,:,:), ws_Fg_lk_th(:,:,:), ws_Fg_lk_z(:,:,:)
    logical, save :: ws_Fg_valid = .false.
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

    !---------------------------------------------------------------------------
    ! (auditoria 4, B4-10) Peso propio de UNA fase en una cara vertical: media
    ! de las dos celdas PONDERADA por la alpha de esa fase. La rho y la T de
    ! una celda SIN la fase son rancias (liquido a 300 K en una celda vacia:
    ! Boussinesq x1.18 en los bordes del lecho seco; gas de poro frente a gas
    ! libre). UNA definicion para momento (bed_rel_f) y Poisson (bed_rel_fp):
    ! la cancelacion del Rhie-Chow exige la misma expresion en los dos.
    !---------------------------------------------------------------------------
    pure real(dp) function own_weight_face(wa, wb, aa, ab)
        real(dp), intent(in) :: wa, wb, aa, ab
        if (aa + ab > 0.0_dp) then
            own_weight_face = (aa * wa + ab * wb) / (aa + ab)
        else
            own_weight_face = 0.5_dp * (wa + wb)
        end if
    end function own_weight_face

    !---------------------------------------------------------------------------
    ! FLOTACION RELATIVA DEL LECHO por caras: UNA definicion para momento
    ! (bed_rel_f) y Poisson (bed_rel_fp) (auditoria 6: el pendiente de la
    ! auditoria 4 era un unitario que las comparara; eran dos copias internas
    ! de sus subrutinas, intestables, y el peso de celda de la mezcla usaba dos
    ! criterios de continuidad de respaldo distintos). El Rhie-Chow del Poisson
    ! cancela la flotacion exactamente solo si las dos son identicas.
    ! Test: test_bed_rel_face.
    !---------------------------------------------------------------------------

    ! Peso propio del LIQUIDO por unidad de su volumen [N/m3], con Boussinesq
    ! referido a T_ref (A7)
    pure real(dp) function liq_own_weight(rho, T, beta, Tref)
        real(dp), intent(in) :: rho, T, beta, Tref
        liq_own_weight = GRAVITY * rho * (1.0_dp - beta * (T - Tref))
    end function liq_own_weight

    ! Peso de celda que entra en el W_f de la fuerza balanceada [N/m3]: sin
    ! fuerza balanceada, alpha_l w_l del liquido CONTINUO; con ella (lbf), el
    ! de la MEZCLA CONTINUA por volumen de FLUIDO (alpha_l w_l + alpha_g rho_g
    ! g)/(alpha_l + alpha_g) (0 sin fluido)
    pure real(dp) function mix_cell_weight(al, wl, ag, rg, cont, lbf)
        real(dp), intent(in) :: al, wl, ag, rg
        logical, intent(in)  :: cont, lbf
        real(dp) :: eps
        mix_cell_weight = merge(1.0_dp, 0.0_dp, cont) * al * wl
        if (lbf) then
            eps = max(al, 0.0_dp) + max(ag, 0.0_dp)
            if (eps > 1.0e-12_dp) then
                mix_cell_weight = (mix_cell_weight + GRAVITY * max(ag, 0.0_dp) * rg) / eps
            else
                mix_cell_weight = 0.0_dp
            end if
        end if
    end function mix_cell_weight

    ! Mascara de cara del gas POR DEFECTO (A4-1): el minimo de las dos celdas
    ! (la cara gas libre | poro saturado es superficie libre) o la burbuja
    pure real(dp) function gas_face_mask(bg_a, bg_b, bub_f)
        real(dp), intent(in) :: bg_a, bg_b, bub_f
        gas_face_mask = max(min(bg_a, bg_b), bub_f)
    end function gas_face_mask

    ! Continuidad del liquido de RESPALDO cuando ws_liq_cont no es valida
    ! (rama de una fase): la del Poisson (act_l), para momento y Poisson
    pure elemental logical function liq_cont_fallback(al)
        real(dp), intent(in) :: al
        liq_cont_fallback = (al >= ALPHA_FLOW_CUTOFF)
    end function liq_cont_fallback

    ! Flotacion relativa en la cara (ka,kb) de la columna (ii,jj) [N/m3]:
    ! B_f = bm (w_q,f - W_f), con las mascaras de cara de mod_multiphase:
    ! gas = ws_bedg_f (por defecto gas_face_mask: max(min de ws_bed_gas de las
    ! dos celdas, ws_bub_f), A4-1); liquido = ws_bedl_f. 0 EXACTO sin fuerza balanceada, sin mascaras
    ! validas o sin liquido en la cara (corridas frias bit a bit). w_q,f es el
    ! peso propio ponderado por la alpha de la fase (own_weight_face, B4-10).
    pure real(dp) function bed_rel_face(isg, ii, jj, ka, kb, al_a, al_b, &
                                        aq_a, aq_b, wq_a, wq_b, wf, lbf)
        logical, intent(in)  :: isg, lbf
        integer, intent(in)  :: ii, jj, ka, kb
        real(dp), intent(in) :: al_a, al_b, aq_a, aq_b, wq_a, wq_b, wf
        real(dp) :: bm
        bed_rel_face = 0.0_dp
        if (.not. (lbf .and. ws_bed_valid)) return
        if (max(al_a, al_b) < ALPHA_CUTOFF) return
        if (isg) then
            bm = ws_bedg_f(ii, jj, min(ka, kb))
        else
            bm = ws_bedl_f(ii, jj, min(ka, kb))
        end if
        if (bm <= 0.0_dp) return
        bed_rel_face = bm * (own_weight_face(wq_a, wq_b, aq_a, aq_b) - wf)
    end function bed_rel_face

    subroutine ensure_workspace(m)
        type(mesh_t), intent(in) :: m

        if (allocated(ws_aP)) return
        allocate(ws_aW(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(ws_aE, ws_aS, ws_aN, ws_aB, ws_aT, ws_aP, ws_Su, mold=ws_aW)
        allocate(ws_Fr, ws_Fth, ws_Fz, ws_Mr, ws_Mth, ws_Mz, ws_lim, mold=ws_aW)
        allocate(ws_lim_step, mold=ws_aW); ws_lim_step = 1.0_dp
        allocate(ws_cc, ws_cc_new, ws_cc_drop, mold=ws_aW); ws_cc = 0.0_dp; ws_cc_new = 0.0_dp
        ws_cc_drop = 0.0_dp
        allocate(ws_p_n, mold=ws_aW); ws_p_n = 0.0_dp
        allocate(ws_bed, ws_bed_gas, ws_bed_liq, ws_bedl_f, ws_bub, ws_bub_f, ws_bedg_f, mold=ws_aW)
        ws_bedg_f = 0.0_dp
        ws_bed = 0.0_dp; ws_bed_gas = 0.0_dp; ws_bed_liq = 0.0_dp; ws_bedl_f = 0.0_dp; ws_bub = 0.0_dp; ws_bub_f = 0.0_dp
        allocate(ws_Fg_r, ws_Fg_th, ws_Fg_z, mold=ws_aW)
        ws_Fg_r = 0.0_dp; ws_Fg_th = 0.0_dp; ws_Fg_z = 0.0_dp
        allocate(ws_Fg_lk_r(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(ws_Fg_lk_th, ws_Fg_lk_z, mold=ws_Fg_lk_r)
        ws_Fg_lk_r = 0; ws_Fg_lk_th = 0; ws_Fg_lk_z = 0
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
