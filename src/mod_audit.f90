!===============================================================================
! mod_audit.f90 - Auditoría global de balances de masa y energía (C0.2)
!
! Escribe <output_dir>/audit.csv con una línea por paso (audit_freq):
! inventarios por fase, integrales de fuentes tal como las RECIBEN las
! ecuaciones de energía (mismo gating alpha >= ALPHA_CUTOFF y flags de
! física), potencia de arco, y los "clips" contabilizados como términos
! explícitos (energía descartada por caps, masa recortada por clipping de
! alpha, masa fundida/re-solidificada).
!
! NO INVASIVO: solo lee campos y acumula contadores; no altera ningún valor
! de la simulación (verificado por h5diff bit-idéntico contra pre-C0.2).
!
! Los módulos de física reportan sus clips/transferencias vía audit_add();
! los contadores son locales al rank y se reducen (allreduce) al escribir.
! Semántica de columnas: TODAS las columnas acumulativas (contadores acc()
! e integrales de fuente srcacc()) acumulan desde la línea anterior — con
! audit_freq>1 cubren TODOS los pasos del intervalo (audit_accumulate corre
! cada paso). Los inventarios son instantáneos al paso escrito.
!===============================================================================
module mod_audit
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology, only: mpi_allreduce_sum, mpi_allreduce_max
    use mod_parallel_utils, only: get_loop_bounds
    use mod_workspace, only: ws_Fg_r, ws_Fg_th, ws_Fg_z, ws_Fg_lk_r, ws_Fg_lk_th, ws_Fg_lk_z, ws_Fg_valid, &
                             ws_Fc_r, ws_Fc_th, ws_Fc_z, ws_Fc_valid, ws_Fr, ws_Fth, ws_Fz, ws_flux_valid, &
                             ws_Fc_lk_r, ws_Fc_lk_th, ws_Fc_lk_z, ws_pc_unl, ws_pc_unl_valid, ws_pc_unl_id, &
                             ws_pc_unl_used, ws_pc_unl_used_valid, ws_pc_unl_used_id, &
                             ws_lim_step, ws_lim_step_valid, ws_lim_step_id, &
                             ws_su_cc_used, ws_su_cc_used_valid, ws_su_cc_used_id, ws_gadv_used, &
                             ws_store_gas, ws_store_art
    use mod_probe, only: probe_current_step
    use mod_face_flux, only: face_mass_fluxes
    use mod_boundary_3d, only: physical_boundary_flags
    implicit none
    private

    public :: audit_init, audit_write_step, audit_add, audit_accumulate, audit_peek
    public :: audit_set_energy, eq_residual, gas_inventory_cell, gas_heat_capacity_ref, gas_log_exchange
    public :: AUD_ARC_DIRECT, AUD_ARC_DISCARD, AUD_MC_DEPOSIT
    public :: AUD_ALPHA_CLIP_MASS, AUD_MELT_MASS, AUD_RESOLID_MASS
    public :: AUD_MELT_E_SOLID, AUD_SLAG_INTERCEPT, AUD_SLAG_GAS, AUD_SLAG_LIQ, AUD_GAS_OUT, AUD_GAS_RXN, AUD_GAS_VOLFIX_E
    public :: AUD_RAD_SOL, AUD_RAD_WALL, AUD_CHEM_SOL, AUD_MC_LOST
    public :: AUD_ECS_MASS, AUD_ECS_ENERGY, AUD_FLUX_MASS, AUD_FLUX_E
    public :: AUD_FE_YIELD, AUD_FE_RETURN, AUD_SLAG_OX_E, AUD_SLAG_RED_E
    public :: AUD_RAD_FOAM
    public :: AUD_IPH_SOL, AUD_IPH_GAS, AUD_IPH_LIQ
    public :: AUD_ABS_LIQ_HOOK, AUD_RELAX_LIQ, AUD_RELAX_GAS
    public :: AUD_MG_ERR_FREE, AUD_MG_ERR_MULTI, AUD_MG_ERR_ABS, AUD_MG_ERR_OUT, AUD_MG_SKIP
    public :: audit_gas_cells, gas_cell_class, audit_volfix_cell, AUD_MG_VF_CELLS
    public :: audit_comp_cell, audit_eos_cell, AUD_MG_COMP, AUD_MG_EOS, AUD_MG_ERR_LIQ, &
              AUD_MG_ERR_ABS_MULTI, AUD_MG_ERR_REM_ABS, AUD_MG_LIQ_SKIP, AUD_MG_VPOIS_ABS, AUD_MG_VEFF_ABS, &
              AUD_MG_ERR_ABS_NOGAS, AUD_MG_COMP_ABS, AUD_MG_EOS_ABS, AUD_MG_ERR_LIQ_ALL, AUD_MG_ERR_REM_ABS_ALL, &
              AUD_MG_COMP_ABS_NOGAS, AUD_MG_ERR_ABS_NOLINK, AUD_MG_CELLS_NOLINK, AUD_MG_E2_NOLINK, &
              AUD_MG_ERR_LIQ_LK, AUD_MG_ERR_LIQ_UNL, AUD_MG_ERR_LIQ_UNL_ABS, AUD_MG_VPOIS_ABS_NOGAS, &
              AUD_MG_VEFF_ABS_NOGAS, AUD_MG_REJ_NOGAS, AUD_MG_E2_SKIP, &
              AUD_MG_COMP_MULTI, AUD_MG_EOS_MULTI, AUD_MG_FLUX_MULTI, AUD_MG_RX_MULTI, &
              AUD_MG_COMP_FREE, AUD_MG_EOS_FREE, AUD_MG_FLUX_FREE, AUD_MG_RX_FREE, &
              AUD_MG_ERR_CC_MULTI, AUD_MG_ERR_CC_FREE, AUD_MG_REM2_ABS_MULTI, AUD_MG_REM2_ABS_FREE, &
              AUD_MG_ERR_ABS_FREE, AUD_MG_CC_ABS_MULTI, AUD_MG_CC_ABS_FREE, AUD_MG_CC_SKIP, &
              AUD_MG_ERR_ART_MULTI, AUD_MG_ERR_ART_FREE, AUD_MG_ART_ABS_MULTI, AUD_MG_ART_ABS_FREE
    public :: AUD_RESID_MASS, AUD_RESID_E, AUD_SPILL_MASS
    public :: AUD_VOL_DALPHA, AUD_VOL_LIM, AUD_VOL_UNLINKED
    public :: AUD_CHARGE_MASS, AUD_CHARGE_E, AUD_C_OXID, AUD_DIL_O2, AUD_DIL_CO, AUD_DIL_CO2, AUD_GAS_VOLFIX, AUD_SLAG_TCLIP, AUD_MIX_INIT
    public :: AUD_RESOLID_E, AUD_ALPHA_CLIP_E
    public :: AUD_VF_O2, AUD_VF_CO, AUD_VF_CO2, audit_gas_destroyed, AUD_GAS_CCDROP
    public :: AUD_SLAG_CLIP_MASS, AUD_SLAG_CLIP_E, AUD_SLAG_SOL, AUD_STEEL_DEF_MASS, AUD_STEEL_DEF_E

    ! Contadores acumulativos (ids públicos para los hooks en física)
    integer, parameter :: AUD_ARC_DIRECT      = 1  ! J al sólido (P_rad directo)
    integer, parameter :: AUD_ARC_DISCARD     = 2  ! J descartados por DT_RAD_MAX
    integer, parameter :: AUD_MC_DEPOSIT      = 3  ! J depositados por el MC en S_arc
    integer, parameter :: AUD_ALPHA_CLIP_MASS = 4  ! kg netos quitados por clip de alpha
    integer, parameter :: AUD_MELT_MASS       = 5  ! kg fundidos (mdot*dt > 0)
    integer, parameter :: AUD_RESOLID_MASS    = 6  ! kg re-solidificados
    integer, parameter :: AUD_MELT_E_SOLID    = 7  ! J retirados del sólido al fundir
    integer, parameter :: AUD_SLAG_INTERCEPT  = 8  ! J de S_arc interceptados por escoria
    integer, parameter :: AUD_RAD_SOL         = 9  ! J radiativos depositados en el sólido
    integer, parameter :: AUD_RAD_WALL        = 10 ! J radiativos netos perdidos a paredes
    integer, parameter :: AUD_CHEM_SOL        = 11 ! J de oxidación primaria al sólido
    integer, parameter :: AUD_MC_LOST         = 12 ! J de beams MC que escapan del dominio
    integer, parameter :: AUD_ECS_MASS        = 13 ! kg cargados por el ECS (E1)
    integer, parameter :: AUD_ECS_ENERGY      = 14 ! J de entalpia cargada por el ECS
    integer, parameter :: AUD_FLUX_MASS       = 15 ! kg de adiciones a la escoria
    integer, parameter :: AUD_FLUX_E          = 16 ! J de entalpia de las adiciones
    integer, parameter :: AUD_FE_YIELD        = 17 ! kg Fe oxidados a la escoria
    integer, parameter :: AUD_FE_RETURN       = 18 ! kg Fe devueltos por reduccion
    integer, parameter :: AUD_SLAG_OX_E       = 19 ! J exo de Fe+1/2O2->FeO + diferencia de datos (aud. 19)
    integer, parameter :: AUD_SLAG_RED_E      = 20 ! J endo de FeO+C->Fe+CO + diferencia de datos y CO (aud. 19)
    integer, parameter :: AUD_RAD_FOAM        = 21 ! J radiativos a la espuma/escoria
    integer, parameter :: AUD_IPH_SOL         = 22 ! J interfase GANADOS por el sólido
    integer, parameter :: AUD_IPH_GAS         = 23 ! J interfase RETIRADOS del gas (tal como se aplicó)
    integer, parameter :: AUD_IPH_LIQ         = 24 ! J interfase RETIRADOS del líquido (idem)
    integer, parameter :: AUD_RESID_MASS      = 25 ! kg de solido residual cerrados al liquido (subconjunto de m_melted)
    integer, parameter :: AUD_RESID_E         = 26 ! J entregados con ese residuo (subconjunto de E_melt_from_solid)
    integer, parameter :: AUD_SPILL_MASS      = 27 ! kg de liquido derramados hacia arriba (conservativo; informativo)
    ! Plan D, D1 (oct-2026): desfases del acople alpha-p, por paso (ultima
    ! iteracion externa), en m3 de liquido
    integer, parameter :: AUD_VOL_DALPHA      = 28 ! m3: sum |alpha_l(tras transporte) - alpha_l(iterado entrante)| V
    integer, parameter :: AUD_VOL_LIM         = 29 ! m3: entrada de liquido BLOQUEADA por el limitador de hueco
    integer, parameter :: AUD_VOL_UNLINKED    = 30 ! m3: flujo de liquido por caras NO enlazadas en el Poisson (disperso/drift)
    ! Carga de cestas DESPUES del arranque (cesta 2): masa y entalpia que entran
    ! al solido (auditoria 12-oct-2026, A5; antes un salto sin termino fuente)
    integer, parameter :: AUD_CHARGE_MASS     = 31 ! kg cargados por cestas tras el arranque
    integer, parameter :: AUD_CHARGE_E        = 32 ! J de entalpia de esa carga
    integer, parameter :: AUD_C_OXID          = 33 ! kg de carbono del solido oxidado a CO (sale del acero, M15)
    ! kg de cada especie desplazados por la dilucion de la masa que entra al
    ! gas (-Y_k S_gas, M14): con la densidad del gas fijada por la EOS es la
    ! masa que la fuente expulsa de la celda
    integer, parameter :: AUD_DIL_O2          = 34
    integer, parameter :: AUD_DIL_CO          = 35
    integer, parameter :: AUD_DIL_CO2         = 36
    ! kg de gas que la restriccion de volumen (enforce_volume_constraint) crea
    ! (+) o destruye (-) al recalcular alpha_g = 1 - sum tras fusion/colapso
    integer, parameter :: AUD_GAS_VOLFIX      = 37
    ! J que el piso T_sl >= 300 K inyecta en la escoria (E_sl coherente con T)
    integer, parameter :: AUD_SLAG_TCLIP      = 38
    ! J que el liquido recibe del gas en el equilibrio de arranque del modelo
    ! de mezcla (la referencia del gas se reinicia: sin esta columna la
    ! perdida del gas no quedaba en ningun libro)
    integer, parameter :: AUD_MIX_INIT        = 39
    ! J que la congelacion entrega al solido (dm e_entry; auditoria 2, N-C3:
    ! el traspaso liquido->solido no tenia columna de energia)
    integer, parameter :: AUD_RESOLID_E       = 40
    ! J que se llevan los kg recortados por el clip de alpha (N-B1)
    integer, parameter :: AUD_ALPHA_CLIP_E    = 41
    ! DIAGNOSTICO (no entran a la identidad: su suma es E_conv_defect): el
    ! defecto convectivo del hook por fase y el calor que absorbe la ecuacion
    ! del gas segun su propio hook (auditoria 2, N-A7)
    integer, parameter :: AUD_CONV_LIQ        = 42
    integer, parameter :: AUD_CONV_GAS        = 43
    integer, parameter :: AUD_ABS_GAS_HOOK    = 44
    ! DIAGNOSTICO (auditoria 3, M3-7): J que la escoria recibe del gas y del
    ! bano (propia celda + qdown de la de abajo) en slag_energy; traspasos
    ! entre inventarios de estado, no entran a la identidad
    integer, parameter :: AUD_SLAG_GAS        = 45
    integer, parameter :: AUD_SLAG_LIQ        = 46
    ! (auditoria 4, A4-6) kg de gas venteados por las salidas del techo (masa
    ! neta que entra a las celdas outlet con los flujos conservativos ws_Fg) y
    ! kg que las reacciones aportan al gas (S_CO + S_CO2 + S_O2): con ellos y
    ! m_gas_volfix, el residuo de d m_gas es la masa que la EOS reescribe
    integer, parameter :: AUD_GAS_OUT         = 47
    integer, parameter :: AUD_GAS_RXN         = 48
    ! (auditoria 4, M4-13) J que entran/salen con la masa de gas que crea o
    ! destruye la restriccion de volumen (m_gas_volfix x cp T): fuente externa
    ! exacta de la identidad (slag_chem_test sin energia: 1e6 J en el paso 1)
    integer, parameter :: AUD_GAS_VOLFIX_E    = 49
    ! (auditoria 5, M5-5) kg de cada especie que SALEN con el gas destruido
    ! (restriccion de volumen, flotacion de la escoria, carga de cesta, ECS):
    ! el gas creado no trae especies (Y diluida), el destruido se las lleva.
    ! Con m_dil_* cierran los balances elementales de O y C con escoria
    ! (check_chem --slag).
    integer, parameter :: AUD_VF_O2           = 50
    integer, parameter :: AUD_VF_CO           = 51
    integer, parameter :: AUD_VF_CO2          = 52
    ! (auditoria 6, M6-1/M6-2) kg de gas cuya demanda de volumen el paso
    ! DESCARTA (rho_g x ws_cc_drop: desborde de la cota del acarreo, acarreo de
    ! celdas que salen del acople, sin gas o selladas). Es la parte del
    ! residuo de mass_gas (lo que la EOS reescribe) que tiene nombre.
    integer, parameter :: AUD_GAS_CCDROP      = 53
    ! (Plan H, P6) escoria CONDENSADA recortada por el acotado del transporte
    ! (recorte final del condensado, parte de escoria, y alpha_sl > alpha_c):
    ! masa con rho_sl y su E_sl (antes contada como acero o sin contar)
    integer, parameter :: AUD_SLAG_CLIP_MASS  = 54
    integer, parameter :: AUD_SLAG_CLIP_E     = 55
    ! (auditoria 18, A18-10) calor escoria -> solido por contacto en el lecho
    ! (interno entre inventarios; diagnostico)
    integer, parameter :: AUD_SLAG_SOL        = 56
    ! (auditoria 19, M19-C2) acero CREADO por el deficit de congelacion en el
    ! condensado (A18-5): columna propia (antes clip negativo que podia
    ! cancelar el clip por desborde en los techos)
    integer, parameter :: AUD_STEEL_DEF_MASS  = 57
    integer, parameter :: AUD_STEEL_DEF_E     = 58
    ! DIAGNOSTICO (WS-K3, C-096..C-098): absorbido del LIQUIDO segun su hook
    ! (eeq(1,1); antes no se escribia) y RESIDUO del enunciado discreto que
    ! queda en pie por fase, dt sum R(Tk) = absorbido - (arco + rad + quim +
    ! conv - pared + masa) del hook de la ultima iteracion externa. Con la
    ! sub-relajacion de T (alpha_T < 1) el campo guardado Tk no cumple la
    ! ecuacion y la diferencia es energia que el inventario pierde o gana:
    ! en B1 con alpha_T 0.7, ~-60 J/paso del liquido. Banco (C-096, C-098,
    ! C-103): neto ~-2..-4 J/paso con 0.85-1.0, pero con 0.85 la std por
    ! paso es 105 J (0.25 J con 1.0). Incluye tambien la convergencia interna
    ! incompleta (R(Tk) es lineal en Tk). El reparto por fase solo vale en dos
    ! fluidos: con mixture_model el intercambio gas-liquido entre el solve y
    ! la relajacion no lo ve el hook (solo la suma tiene sentido).
    ! NO entran a la identidad: la cuentan, no la cierran.
    integer, parameter :: AUD_ABS_LIQ_HOOK    = 59
    integer, parameter :: AUD_RELAX_LIQ       = 60
    integer, parameter :: AUD_RELAX_GAS       = 61
    ! DIAGNOSTICO (WS-K5, C-106..C-110): balance de masa del gas POR CELDA en
    ! el paso, e = (a rho V)^fin - (a rho V)^ini - dt sum caras ws_Fg - rxn,
    ! fuera de las celdas outlet (su e es el venteo). Separa donde la EOS
    ! reescribe masa: celdas de gas LIBRE (sin liquido ni solido: ahi solo
    ! queda la convergencia del lazo externo) y celdas MULTIFASE (el
    ! complemento alpha_g = 1 - sum crea gas donde el liquido se retira y lo
    ! destruye donde entra, sin flujo de gas que lo lleve: N-M4). B1 280 s,
    ! 59 pasos, 20 externas: libre +2e-5 kg, multifase -8.7e-4 kg con
    ! |e| 1.6e-2 kg (errores grandes que se compensan). (WS-K6) e RESTA el
    ! volfix de la celda (gas desplazado por fusion, carga, ECS, escoria),
    ! que las 6 rutas de AUD_GAS_VOLFIX registran por celda con
    ! audit_volfix_cell: las columnas miden solo la masa que reescriben la
    ! EOS y el complemento (antes cold_bucket2 daba multi -10.4 kg, casi
    ! todo volfix). m_gas_vf_cells = suma de lo registrado por celda;
    ! check_audit exige que iguale a m_gas_volfix. NO entran a mass_gas.
    ! (WS-K7, C-120) La 'alternativa' de transporte por caras ws_Fg_lk = 0
    ! es nula: ws_Fg vale 0 ahi (mod_pressure_3d, se anula en cada Poisson y
    ! solo se escribe con lk = 1).
    integer, parameter :: AUD_MG_ERR_FREE     = 62
    integer, parameter :: AUD_MG_ERR_MULTI    = 63
    integer, parameter :: AUD_MG_ERR_ABS      = 64
    ! e de las celdas OUTLET (su balance no cierra por construccion: la masa
    ! que les entra es el venteo) y pasos sin balance (ws_Fg no valido:
    ! mezcla, sin multifase). Identidad de cierre, al redondeo:
    !   EOS - (libre + multi + outlet) = venteo
    ! (las caras interiores se cancelan; check_audit la imprime)
    integer, parameter :: AUD_MG_ERR_OUT      = 65
    integer, parameter :: AUD_MG_SKIP         = 66
    integer, parameter :: AUD_MG_VF_CELLS     = 67
    ! (WS-K7, C-120/C-121) el inventario del gas solo cambia por TRES rutas:
    ! el complemento alpha_g = 1 - sum tras el transporte del liquido (3
    ! sitios de mod_continuity, audit_comp_cell: comp = rho_g V d alpha_g),
    ! la EOS en update_properties (audit_eos_cell: eos = alpha_g V d rho_g) y
    ! el volfix. Identidad exacta, check mass_gas_rewrites:
    !   d m_gas = m_gas_comp + m_gas_eos + m_gas_volfix.
    ! El flujo del gas NUNCA entra al inventario: e = comp + eos - dt sum F_g
    ! - rxn. Prediccion de la hipotesis C-110 (el piso multifase es el
    ! complemento SIN flujo de gas que lo lleve): el Poisson balancea el
    ! liquido que exporta (ws_Fc en caras enlazadas + la fuente E2 que ESE
    ! Poisson sumo a Su, ws_pc_unl_used, C-144; lk_any solo define la clase
    ! sin cara enlazada: m_gas_cells_nolink, _err_abs_nolink, _e2_nolink)
    ! contra el flujo del gas, pero el transporte real mueve ws_Fr/Fth/Fz
    ! (limitador, caras no enlazadas, derrame); el complemento sigue al
    ! transporte real. En celdas multifase:
    !   err_liq = rho_g (V_pois_in - V_eff_in),  e ~= err_liq si H.
    ! m_gas_err_rem_abs = sum |e - err_liq| frente a m_gas_err_abs_multi.
    integer, parameter :: AUD_MG_COMP         = 68
    integer, parameter :: AUD_MG_EOS          = 69
    integer, parameter :: AUD_MG_ERR_LIQ      = 70
    integer, parameter :: AUD_MG_ERR_ABS_MULTI = 71
    integer, parameter :: AUD_MG_ERR_REM_ABS  = 72
    integer, parameter :: AUD_MG_LIQ_SKIP     = 73
    ! sanidad de la medida: sum |rho_g V_pois_in| y sum |rho_g V_eff_in| en
    ! las mismas celdas (si err_liq es pequeno, que se vea que ambos NO lo son)
    integer, parameter :: AUD_MG_VPOIS_ABS    = 74
    integer, parameter :: AUD_MG_VEFF_ABS     = 75
    ! (panel WS-K7, C-124) los cocientes por celda recorren el MISMO conjunto:
    ! rem_abs suma |e - err_liq| en las celdas donde err_liq se evalua (gas
    ! al inicio o al final del paso, alpha_g > 0) y |e| (err_liq := 0) en el
    ! resto de las multifase; m_gas_err_abs_nogas = sum |e| de ese resto
    integer, parameter :: AUD_MG_ERR_ABS_NOGAS = 76
    ! (panel WS-K7 ronda 2, R1/R2; ronda 3, R-1 C-133) sum |dm| POR LLAMADA
    ! del complemento y de la EOS (mg_comp_abs/mg_eos_abs acumulan abs(dm)
    ! en cada gancho: creacion mas destruccion dentro del paso, sin la
    ! cancelacion que esconde el neto), y la definicion ORIGINAL de C-121:
    ! err_liq evaluado en TODAS las celdas multifase, sin filtro de gas
    integer, parameter :: AUD_MG_COMP_ABS     = 77
    integer, parameter :: AUD_MG_EOS_ABS      = 78
    integer, parameter :: AUD_MG_ERR_LIQ_ALL  = 79
    integer, parameter :: AUD_MG_ERR_REM_ABS_ALL = 80
    ! (panel ronda 3) sum |dm| por llamada del complemento en las multifase
    ! SIN gas en los extremos (gas que aparece y se destruye dentro del
    ! paso, R-1) y sum |e| en las multifase sin ninguna cara enlazada en el
    ! ultimo Poisson (donde E2 no entra y err_liq = -rho_g V_eff, M1)
    integer, parameter :: AUD_MG_COMP_ABS_NOGAS = 81
    integer, parameter :: AUD_MG_ERR_ABS_NOLINK = 82
    ! cuantas multifase sin cara enlazada hay (por paso, sumadas) y cuanta
    ! fuente E2 descarto ahi el Poisson, sum |rho_g dt ws_pc_unl| [kg]: el
    ! peso real del sesgo M1 (si el recuento es 0 la clase esta vacia)
    integer, parameter :: AUD_MG_CELLS_NOLINK = 83
    integer, parameter :: AUD_MG_E2_NOLINK    = 84
    ! (quinto ciclo, C-144; panel M-1) V_pois usa la E2 que el ULTIMO Poisson
    ! acepto (ws_pc_unl_used), no la del transporte posterior. Como unl_vol se
    ! construye con los MISMOS Fw..Ft que ws_Fr (caras no enlazadas), con la
    ! E2 del transporte N la parte no enlazada se cancelaba y err_liq se
    ! reducia a las caras enlazadas. Reparto exacto:
    !   err_liq_unl = rho_g dt (E2_used - ws_pc_unl(N))  [desfase E2 Poisson
    !                 frente a transporte; 0 al converger; -rho_g unl(N) dt si
    !                 el Poisson no acepto nada]
    !   err_liq_lk  = err_liq - err_liq_unl               [caras enlazadas:
    !                 limitador, alpha dador/a_f, rho_cara/rho_celda, derrame]
    ! (R1) en las multifase SIN gas: sum|rho_g V_pois|, sum|rho_g V_eff| y la
    ! entrada enlazada planeada que el limitador no admitio,
    !   rej = rho_g (1 - ws_lim_step) dt sum_caras max(Fc entrante, 0).
    integer, parameter :: AUD_MG_ERR_LIQ_LK   = 85
    integer, parameter :: AUD_MG_ERR_LIQ_UNL  = 86
    integer, parameter :: AUD_MG_ERR_LIQ_UNL_ABS = 87
    integer, parameter :: AUD_MG_VPOIS_ABS_NOGAS = 88
    integer, parameter :: AUD_MG_VEFF_ABS_NOGAS  = 89
    integer, parameter :: AUD_MG_REJ_NOGAS    = 90
    integer, parameter :: AUD_MG_E2_SKIP      = 91
    ! (WS-K8) reparto EXACTO del error por conjunto (multifase / gas libre):
    ! por celda e = comp + eos - fl - rx (el volfix se cancela), asi que
    !   e_conjunto = comp + eos - flux - rx  sobre sus celdas,
    ! con flux = sum fl = flujo neto de gas que ENTRA al conjunto por su
    ! frontera (las caras internas se cancelan). Y la mitad de compresibilidad
    ! del plan del Poisson: err_cc = eos + rho_g dt (su_cc - gadv - store_gas) - rx
    ! (su_cc = ws_su_cc_used, la demanda que el ultimo Poisson sumo a Su;
    ! gadv = ws_gadv_used, su termino advectivo sin pesar: el flujo de MASA
    ! ws_Fg ya lleva la densidad del dador, asi que en masa el plan es
    ! rho_P dt (su_cc - gadv); store_gas = compresion acustica real del gas
    ! almacenada en la diagonal, con el pp completo). Plan completo por celda
    ! e ~= err_liq + err_cc + err_art (err_art: AUD_MG_ERR_ART_*); el resto es
    ! residuo del CG, rho del iterado frente a la final y la parte de pp que
    ! la EOS no realiza (sh%p avanza alpha_p pp).
    integer, parameter :: AUD_MG_COMP_MULTI   = 92
    integer, parameter :: AUD_MG_EOS_MULTI    = 93
    integer, parameter :: AUD_MG_FLUX_MULTI   = 94
    integer, parameter :: AUD_MG_RX_MULTI     = 95
    integer, parameter :: AUD_MG_COMP_FREE    = 96
    integer, parameter :: AUD_MG_EOS_FREE     = 97
    integer, parameter :: AUD_MG_FLUX_FREE    = 98
    integer, parameter :: AUD_MG_RX_FREE      = 99
    integer, parameter :: AUD_MG_ERR_CC_MULTI = 100
    integer, parameter :: AUD_MG_ERR_CC_FREE  = 101
    integer, parameter :: AUD_MG_REM2_ABS_MULTI = 102
    integer, parameter :: AUD_MG_REM2_ABS_FREE = 103
    integer, parameter :: AUD_MG_ERR_ABS_FREE = 104
    integer, parameter :: AUD_MG_CC_ABS_MULTI = 105
    integer, parameter :: AUD_MG_CC_ABS_FREE  = 106
    integer, parameter :: AUD_MG_CC_SKIP      = 107
    ! almacenamiento ARTIFICIAL de la fila (compliance, piso D2.4, acustico
    ! del liquido): err_art = -rho_g dt store_art, gas que el Poisson dejo de
    ! evacuar sin que ninguna fase lo almacene. Plan completo por celda:
    !   e ~= err_liq_all + err_cc + err_art,
    ! con err_cc = eos + rho_g dt (su_cc - gadv - store_gas) - rx
    integer, parameter :: AUD_MG_ERR_ART_MULTI = 108
    integer, parameter :: AUD_MG_ERR_ART_FREE  = 109
    integer, parameter :: AUD_MG_ART_ABS_MULTI = 110
    integer, parameter :: AUD_MG_ART_ABS_FREE  = 111
    integer, parameter :: N_AUD = 111
    ! masa del gas por celda y su clase al inicio del paso (audit_gas_cells
    ! modo 0); no es estado entre pasos: se recaptura al inicio de cada paso
    real(dp), allocatable, save :: mg_ini(:,:,:)
    integer, allocatable, save  :: mg_cls0(:,:,:)
    ! volfix de la celda en el paso (audit_volfix_cell; se anula en el modo 0)
    real(dp), allocatable, save :: mg_vf(:,:,:)
    ! complemento y EOS por celda en el paso (WS-K7; se anulan en el modo 0):
    ! neto con signo (identidad) y suma de |dm| por llamada (R-1, C-133)
    real(dp), allocatable, save :: mg_comp(:,:,:), mg_eos(:,:,:)
    real(dp), allocatable, save :: mg_comp_abs(:,:,:), mg_eos_abs(:,:,:)
    ! alpha_g al inicio del paso: err_liq se evalua donde hay gas al inicio
    ! o al final (alpha_g > 0: el complemento y la EOS actuan sin umbral,
    ! C-124); en las demas multifase err_liq := 0 y |e| va a rem_abs igual
    real(dp), allocatable, save :: mg_ag0(:,:,:)
    logical, save :: mg_ini_ok = .false.

    real(dp), save :: acc(N_AUD) = 0.0_dp
    ! Integrales de fuente acumuladas POR PASO entre escrituras (9..16 del
    ! esquema de columnas): con audit_freq>1, evaluarlas solo al escribir
    ! subrepresentaba las columnas de fuente ~audit_freq veces (medido en el
    ! hito bore-in con audit_freq=10; los contadores acc() siempre fueron
    ! completos). audit_accumulate se llama CADA paso desde main.
    real(dp), save :: srcacc(9:19) = 0.0_dp
    ! (auditoria 5, B5-3) el libro del gas se parte en dos: la parte de la
    ! ECUACION (medida de estado lineal entre T_old y Tg_end, la T al final del
    ! SIMPLE) y los POKES (interfase gas-solido/gas-liquido, escoria), que son
    ! log-exactos y entran con su propio Q. Un poke log medido linealmente
    ! perdia O(dT^2) (arc_melt: gap -4.7e3 -> +3.2e5 J al pasar las interfases
    ! a log). book_split dice si la ultima acumulacion uso Tg_end.
    logical, save :: book_split = .false.

    ! Términos EXACTOS del enunciado discreto de la energía, reportados por
    ! solve_energy_3d en cada llamada (hook; la última iteración externa
    ! del paso SOBRESCRIBE — es la que queda en pie). Índice 1=líquido,
    ! 2=gas; columnas: absorbed, arc, rad, chem, conv_def, wall, mass.
    ! Es la instrumentación 'por iteración' que el xfail de energy_balance
    ! siempre pidió: el espejo post-hoc no puede reproducir la
    ! linearización de Newton de la radiación (T_it del ensamblado).
    real(dp), save :: eeq(2,7) = 0.0_dp
    character(len=320), save :: audit_path = ''

contains

    !---------------------------------------------------------------------------
    ! Inventario de energia del gas ideal de UNA celda (M4-13): la unica
    ! definicion. La usan el inventario E_gas del audit y las columnas que
    ! crean/destruyen gas por reescritura de alpha_g (enforce_volume_constraint,
    ! slag_buoyancy): E_gas_volfix = inv(alpha_nueva) - inv(alpha_vieja) a T
    ! fija, de modo que la identidad por inventarios (solve_energy = false)
    ! cierra a maquina. Forma log porque rho = rho_ref*T_ref/T hace la
    ! capacidad alpha*rho(T)*cp y la energia absorbida int alpha*rho*cp dT =
    ! alpha*rho_ref*T_ref*cp*ln(T/T_ref); M25: factor (P0 + p)/P0 (el modelo
    ! de mezcla es low-Mach: p no entra).
    !---------------------------------------------------------------------------
    !---------------------------------------------------------------------------
    ! Intercambio implicito entre el GAS (inventario log: energia Cg ln T,
    ! capacidad lineal Cg/T) y un nodo LINEAL (Co, To) con conductancia G
    ! [W/K] durante dt, y opcionalmente un segundo nodo lineal (C2, T2, G2)
    ! que se relaja al mismo objetivo (el solido con gas y liquido). El gas
    ! se relaja EXACTAMENTE hacia la T nueva del nodo objetivo T*:
    !   Cg/T dT/dt = -G (T - T*)  =>  1 - T*/T = (1 - T*/Tg) exp(-G T* dt/Cg)
    ! (tasa inicial exacta hA (Tg - T*), acotada entre Tg y T*), y entrega
    ! Q = Cg ln(Tg/Tg'). El nodo objetivo cumple el balance
    !   Co (T* - To) = Q(T*) + Q2(T*),   Q2 = b2 (T2 - T*), b2 = G2 dt C2/(C2 + G2 dt)
    ! (F monotona en T*: biseccion acotada entre el minimo y el maximo de las
    ! T). Conservativo por construccion, sin sobrepaso, tasa fisica a dt -> 0
    ! y equilibrio exacto a dt -> inf. Un poke lineal T -= Q/(alpha rho cp V)
    ! perdia O(dT^2) en el inventario (M4-13 escoria; auditoria 5, B5-3
    ! interfases; el primer intento aplicaba la fraccion lineal en ln T y
    ! daba 1.7x el calor fisico a dt pequeno).
    !---------------------------------------------------------------------------
    pure subroutine gas_log_exchange(Cg, Tg, Co, To, G, dt, Tg_new, Q, C2, T2, G2, Q2)
        real(dp), intent(in)  :: Cg, Tg, Co, To, G, dt
        real(dp), intent(out) :: Tg_new, Q
        real(dp), intent(in),  optional :: C2, T2, G2
        real(dp), intent(out), optional :: Q2
        real(dp) :: lo, hi, Ts, b2, Fn, Qg, Qs
        integer  :: it
        b2 = 0.0_dp
        ! (bajo B6-12) el segundo nodo existe solo con sus TRES argumentos: con
        ! C2 y G2 pero sin T2 se leia un opcional ausente
        if (present(C2) .and. present(G2) .and. present(T2)) then
            if (C2 > 0.0_dp .and. G2 > 0.0_dp) b2 = G2 * dt * C2 / (C2 + G2 * dt)
        end if
        lo = min(Tg, To); hi = max(Tg, To)
        if (b2 > 0.0_dp) then
            lo = min(lo, T2); hi = max(hi, T2)
        end if
        if (hi - lo <= 1.0e-12_dp * hi .or. Cg <= 0.0_dp .or. Co <= 0.0_dp) then
            Tg_new = Tg; Q = 0.0_dp
            if (present(Q2)) Q2 = 0.0_dp
            return
        end if
        do it = 1, 60
            Ts = 0.5_dp * (lo + hi)
            Qg = q_gas(Ts)
            Qs = 0.0_dp
            if (b2 > 0.0_dp) Qs = b2 * (T2 - Ts)
            Fn = Co * (Ts - To) - Qg - Qs
            if (Fn > 0.0_dp) then
                hi = Ts
            else
                lo = Ts
            end if
            if (hi - lo <= 1.0e-14_dp * hi) exit
        end do
        Ts = 0.5_dp * (lo + hi)
        Tg_new = t_gas(Ts)
        Q = Cg * log(Tg / Tg_new)
        if (present(Q2)) then
            Q2 = 0.0_dp
            if (b2 > 0.0_dp) Q2 = b2 * (T2 - Ts)
        end if
    contains
        pure function t_gas(Tstar) result(Tn)
            real(dp), intent(in) :: Tstar
            real(dp) :: Tn, x
            x = (1.0_dp - Tstar / Tg) * exp(-G * Tstar * dt / Cg)
            Tn = Tstar / (1.0_dp - x)
        end function t_gas
        pure function q_gas(Tstar) result(Qv)
            real(dp), intent(in) :: Tstar
            real(dp) :: Qv
            Qv = Cg * log(Tg / t_gas(Tstar))
        end function q_gas
    end subroutine gas_log_exchange

    pure function gas_inventory_cell(alpha, T, p, cp, vol, cfg) result(e)
        real(dp),       intent(in) :: alpha, T, p, cp, vol
        type(config_t), intent(in) :: cfg
        real(dp) :: e
        e = gas_heat_capacity_ref(alpha, p, cp, vol, cfg) * &
            log(max(T, T_MIN_GAS) / T_RHO_GAS_REF)
    end function gas_inventory_cell

    ! Capacidad de REFERENCIA C_g = alpha*rho_ref*T_ref*cp*V*(P0 + p)/P0 [J]:
    ! inv = C_g ln(T/T_ref) y dinv/dT = C_g/T = alpha*rho(T)*cp*V (la
    ! capacidad lineal de los 'pokes'). Un calor Q entregado al gas a alpha
    ! fija sube T a T*exp(Q/C_g) (slag_energy, M4-13).
    pure function gas_heat_capacity_ref(alpha, p, cp, vol, cfg) result(c)
        real(dp),       intent(in) :: alpha, p, cp, vol
        type(config_t), intent(in) :: cfg
        real(dp) :: c
        c = alpha * cfg%rho_gas * T_RHO_GAS_REF * cp * vol * &
            max(P0_THERMO + merge(0.0_dp, p, cfg%mixture_model), P_ABS_MIN) / P0_THERMO
    end function gas_heat_capacity_ref

    !---------------------------------------------------------------------------
    subroutine audit_set_energy(is_gas, absorbed, e_arc, e_rad, e_chem, &
                                e_conv, e_wall, e_mass)
        logical, intent(in)  :: is_gas
        real(dp), intent(in) :: absorbed, e_arc, e_rad, e_chem
        real(dp), intent(in) :: e_conv, e_wall, e_mass
        integer :: q
        q = merge(2, 1, is_gas)
        eeq(q,1) = absorbed; eeq(q,2) = e_arc; eeq(q,3) = e_rad
        eeq(q,4) = e_chem;   eeq(q,5) = e_conv; eeq(q,6) = e_wall
        eeq(q,7) = e_mass
    end subroutine audit_set_energy

    ! Residuo del enunciado discreto de la fase q (1 liquido, 2 gas) que dejo
    ! el hook: absorbido - (arco + rad + quim + conv - pared + masa); eeq(q,5)
    ! ya es la contribucion convectiva con signo de entrada (-s_conv)
    pure real(dp) function eq_residual(q)
        integer, intent(in) :: q
        eq_residual = eeq(q,1) - (eeq(q,2) + eeq(q,3) + eeq(q,4) + eeq(q,5) &
                                  - eeq(q,6) + eeq(q,7))
    end function eq_residual

    !---------------------------------------------------------------------------
    ! (auditoria 19, tests B6) lectura del contador acumulado desde la ultima
    ! fila escrita (para los unit tests de las rutas auditadas)
    real(dp) function audit_peek(id)
        integer, intent(in) :: id
        audit_peek = acc(id)
    end function audit_peek

    subroutine audit_add(id, val)
        integer, intent(in)  :: id
        real(dp), intent(in) :: val
        acc(id) = acc(id) + val
    end subroutine audit_add

    ! Especies que se van con dm kg de gas destruido en la celda (i,j,k)
    ! (M5-5): columnas m_vf_O2/CO/CO2. dm <= 0 no hace nada.
    subroutine audit_gas_destroyed(sh, i, j, k, dm)
        type(shared_t), intent(in) :: sh
        integer, intent(in)        :: i, j, k
        real(dp), intent(in)       :: dm
        if (dm <= 0.0_dp) return
        acc(AUD_VF_O2)  = acc(AUD_VF_O2)  + sh%Y_O2(i,j,k)  * dm
        acc(AUD_VF_CO)  = acc(AUD_VF_CO)  + sh%Y_CO(i,j,k)  * dm
        acc(AUD_VF_CO2) = acc(AUD_VF_CO2) + sh%Y_CO2(i,j,k) * dm
    end subroutine audit_gas_destroyed

    !---------------------------------------------------------------------------
    ! Crea audit.csv con encabezado y escribe la línea del estado inicial
    ! (paso 0: solo inventarios; llamar DESPUÉS de charge_scrap/slag_init)
    !---------------------------------------------------------------------------
    subroutine audit_init(liq, gas, sol, slag, sh, elec, m, cfg, step, time)
        type(phase_t), intent(in)     :: liq, gas
        type(solid_t), intent(in)     :: sol
        type(slag_t),  intent(in)     :: slag
        type(shared_t), intent(in)    :: sh
        type(electrode_t), intent(in) :: elec(:)
        type(mesh_t), intent(in)      :: m
        type(config_t), intent(in)    :: cfg
        ! Estado inicial (0, 0.0 en arranque frio; el paso y tiempo del
        ! snapshot en un reinicio)
        integer, intent(in)           :: step
        real(dp), intent(in)          :: time

        integer :: iu

        audit_path = trim(cfg%output_dir) // '/audit.csv'
        if (is_writer(m)) then
            ! Al reanudar sobre un directorio con audit.csv, el anterior se
            ! conserva como audit_prev_<paso>.csv (auditoria M4: status='replace'
            ! borraba el historial)
            block
                logical :: ex
                character(len=600) :: bak
                inquire(file=trim(audit_path), exist=ex)
                if (ex .and. len_trim(cfg%restart_file) > 0) then
                    write(bak, '(A,A,I8.8,A)') trim(cfg%output_dir), '/audit_prev_', step, '.csv'
                    ! rename() es extension GNU (no enlaza con -std=f2008)
                    call execute_command_line('mv "'//trim(audit_path)//'" "'//trim(bak)//'"', &
                                              wait=.true.)
                end if
            end block
            open(newunit=iu, file=trim(audit_path), status='replace', &
                 action='write')
            write(iu, '(A)') 'step,time,dt,' // &
                'm_liq,m_gas,m_sol,m_slag,' // &
                'E_liq,E_gas,E_sol,E_slag,' // &
                'P_arc,' // &
                'E_src_liq_arc,E_src_liq_rad,E_src_liq_chem,' // &
                'E_src_gas_arc,E_src_gas_rad,E_src_gas_chem,' // &
                'E_arc_direct_sol,E_arc_discarded,E_mc_deposit,' // &
                'm_melted,m_resolid,E_melt_from_solid,m_alpha_clip,' // &
                'E_slag_intercept,E_rad_sol,E_rad_wall,E_conv_defect,' // &
                'E_wall_conv,E_chem_sol,E_mc_lost,E_out_conv,E_gas_abs,' // &
                'E_mass_liq,m_ecs_in,E_ecs_in,m_flux_in,E_flux_in,' // &
                'm_fe_yield,m_fe_return,E_slag_ox,E_slag_red,E_rad_foam,' // &
                'E_iph_sol,E_iph_gas,E_iph_liq,' // &
                'm_resid_closed,E_resid_closed,m_spill,' // &
                'vol_dalpha_outer,vol_lim,vol_unlinked,' // &
                'p_max,u_gas_max,u_liq_max,m_charge_in,E_charge_in,m_C_oxid,' // &
                'm_dil_O2,m_dil_CO,m_dil_CO2,m_gas_volfix,E_slag_tclip,E_mix_init,E_resolid,E_alpha_clip,E_conv_liq,E_conv_gas,E_abs_gas_hook,E_slag_gas,E_slag_liq,m_gas_out,m_gas_rxn,E_gas_volfix,' // &
                'm_vf_O2,m_vf_CO,m_vf_CO2,m_gas_ccdrop,m_slag_clip,E_slag_clip,E_slag_sol,m_steel_deficit,E_steel_deficit,E_abs_liq_hook,E_relax_liq,E_relax_gas,m_gas_err_free,m_gas_err_multi,m_gas_err_abs,m_gas_err_out,m_gas_cells_skip,m_gas_vf_cells,m_gas_comp,m_gas_eos,m_gas_err_liq,m_gas_err_abs_multi,m_gas_err_rem_abs,m_gas_liq_skip,m_gas_vpois_abs,m_gas_veff_abs,m_gas_err_abs_nogas,m_gas_comp_abs,m_gas_eos_abs,m_gas_err_liq_all,m_gas_err_rem_abs_all,m_gas_comp_abs_nogas,m_gas_err_abs_nolink,m_gas_cells_nolink,m_gas_e2_nolink,m_gas_err_liq_lk,m_gas_err_liq_unl,m_gas_err_liq_unl_abs,m_gas_vpois_abs_nogas,m_gas_veff_abs_nogas,m_gas_rej_nogas,m_gas_e2_skip,m_gas_comp_multi,m_gas_eos_multi,m_gas_flux_multi,m_gas_rx_multi,m_gas_comp_free,m_gas_eos_free,m_gas_flux_free,m_gas_rx_free,m_gas_err_cc_multi,m_gas_err_cc_free,m_gas_rem2_abs_multi,m_gas_rem2_abs_free,m_gas_err_abs_free,m_gas_cc_abs_multi,m_gas_cc_abs_free,m_gas_cc_skip,m_gas_err_art_multi,m_gas_err_art_free,m_gas_art_abs_multi,m_gas_art_abs_free'
            close(iu)
        end if
        acc = 0.0_dp
        call audit_write_step(liq, gas, sol, slag, sh, elec, m, cfg, &
                              step, time)
    end subroutine audit_init

    !---------------------------------------------------------------------------
    ! Inventarios globales + integrales de fuentes del paso y línea CSV.
    ! Llamar ANTES de adapt_timestep (usa el dt con el que corrió el paso).
    !---------------------------------------------------------------------------
    subroutine audit_write_step(liq, gas, sol, slag, sh, elec, m, cfg, &
                                step, time)
        type(phase_t), intent(in)     :: liq, gas
        type(solid_t), intent(in)     :: sol
        type(slag_t),  intent(in)     :: slag
        type(shared_t), intent(in)    :: sh
        type(electrode_t), intent(in) :: elec(:)
        type(mesh_t), intent(in)      :: m
        type(config_t), intent(in)    :: cfg
        integer, intent(in)           :: step
        real(dp), intent(in)          :: time

        ! sums: 1-8 inventarios, 9-14 fuentes por fase (arc, rad, chem),
        ! 15: déficit conservativo de la convección de energía (forma
        ! acotada de Patankar: se resta la continuidad discreta x T; el
        ! déficit global = Sum dF_neto*cp*T — la entalpía de pluma que el
        ! operador no entrega; físicamente ~ el off-gas no ventilado)
        ! 16: pérdida convectiva a paredes Robin (C3.1), sum alpha*h*A*(T-Tw)
        integer, parameter :: NSUM = 19
        real(dp) :: s(NSUM), s_glob(NSUM), a(N_AUD)
        real(dp) :: vol, P_arc, C0_datum
        ! Diagnosticos de MAXIMO (Bug 15): el blow-up del acople P-V de B1
        ! v11 (p = 2 MPa en todo el horno, gas a km/s) era INVISIBLE para
        ! las columnas de inventario y balance — la masa y la energia se
        ! conservaban. Se reducen con allreduce_max.
        real(dp) :: mx(3), mx_glob(3), ug, ul
        integer  :: i, j, k, n, iu
        integer  :: istart, iend, jstart, jend, kstart, kend
        logical  :: liq_energy_on, gas_energy_on

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        liq_energy_on = cfg%solve_energy
        gas_energy_on = cfg%solve_energy .and. cfg%solve_flow .and. &
                        cfg%solve_multiphase

        ! Dato común de entalpía (C1.8): el inventario del líquido se mide
        ! como m*(cp_l*T + C0) para que la transferencia sólido<->líquido
        ! por fusión cierre exactamente (C0 = e_s(T_liq) - cp_l*T_liq)
        C0_datum = (cfg%cp_s - cfg%cp_l) * cfg%T_liquidus + cfg%h_fusion

        s = 0.0_dp; mx = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    vol = m%vol(i,j,k)
                    mx(1) = max(mx(1), abs(sh%p(i,j,k)))
                    if (gas%alpha(i,j,k) >= ALPHA_FLOW_CUTOFF) then
                        ug = sqrt(gas%ur(i,j,k)**2 + gas%uth(i,j,k)**2 + gas%uz(i,j,k)**2)
                        mx(2) = max(mx(2), ug)
                    end if
                    if (liq%alpha(i,j,k) >= ALPHA_FLOW_CUTOFF) then
                        ul = sqrt(liq%ur(i,j,k)**2 + liq%uth(i,j,k)**2 + liq%uz(i,j,k)**2)
                        mx(3) = max(mx(3), ul)
                    end if

                    s(1) = s(1) + liq%alpha(i,j,k) * liq%rho(i,j,k) * vol
                    s(2) = s(2) + gas%alpha(i,j,k) * gas%rho(i,j,k) * vol
                    s(3) = s(3) + sol%m_s(i,j,k)
                    s(4) = s(4) + slag%m_sl(i,j,k)

                    s(5) = s(5) + liq%alpha(i,j,k) * liq%rho(i,j,k) * &
                                  (liq%cp(i,j,k) * liq%T(i,j,k) + C0_datum) * vol
                    ! Inventario del gas ideal CONSISTENTE con el esquema:
                    ! con rho = rho_ref*T_amb/T, la capacidad efectiva es
                    ! alpha*rho(T)*cp y la energía absorbida acumulada es
                    ! integral de alpha*rho(T)*cp dT = alpha*rho_ref*T_amb*
                    ! cp*ln(T/T_amb). El inventario rho(T)*cp*T era CONSTANTE
                    ! en T (el 'agujero' de ~70% del balance).
                    ! M25: con rho(P0 + p, T) el factor (P0 + p)/P0 entra al
                    ! inventario (a p fija sigue siendo la integral exacta)
                    s(6) = s(6) + gas_inventory_cell(gas%alpha(i,j,k), gas%T(i,j,k), &
                                  sh%p(i,j,k), gas%cp(i,j,k), vol, cfg)
                    s(7) = s(7) + sol%E_s(i,j,k)
                    s(8) = s(8) + slag%E_sl(i,j,k)

                end do
            end do
        end do

        ! Las integrales de fuente (columnas 9..16) las acumula
        ! audit_accumulate CADA paso; aquí solo se recogen
        s(9:19) = srcacc(9:19)
        ! (B5-3) E_gas_abs = parte de la ecuacion + pokes exactos (lo que el
        ! gas ENTREGO a solido, liquido y escoria, con signo de absorcion)
        if (book_split) s(18) = s(18) - acc(AUD_IPH_GAS) - acc(AUD_SLAG_GAS)

        ! Reducción global (contadores locales + sumas de celda)
        if (m%is_parallel) then
            do n = 1, NSUM
                call mpi_allreduce_sum(s(n), s_glob(n), m%topo)
            end do
            do n = 1, N_AUD
                call mpi_allreduce_sum(acc(n), a(n), m%topo)
            end do
            do n = 1, 3
                call mpi_allreduce_max(mx(n), mx_glob(n), m%topo)
            end do
        else
            s_glob = s
            a = acc
            mx_glob = mx
        end if
        acc = 0.0_dp
        srcacc = 0.0_dp

        P_arc = 0.0_dp
        do n = 1, size(elec)
            P_arc = P_arc + elec(n)%arc_power
        end do

        if (is_writer(m)) then
            open(newunit=iu, file=trim(audit_path), status='old', &
                 action='write', position='append')
            ! ES24.16E3 (doble completo; auditoria 3, M3-6: con 10 cifras un
            ! inventario de 1e5 kg se escribia a 1e-5 kg y la identidad del
            ! solido no resolvia 1 kg de C oxidado). Sin E3 un valor < 1e-99
            ! imprime '6.678-178' (sin la
            ! E) y rompe el CSV (B1 v9, m_alpha_clip subnormal)
            write(iu, '(I0,A,ES24.16E3,A,ES24.16E3,200(A,ES24.16E3))') &
                step, ',', time, ',', cfg%dt, &
                ',', s_glob(1), ',', s_glob(2), ',', s_glob(3), ',', s_glob(4), &
                ',', s_glob(5), ',', s_glob(6), ',', s_glob(7), ',', s_glob(8), &
                ',', P_arc, &
                ',', s_glob(9), ',', s_glob(10), ',', s_glob(11), &
                ',', s_glob(12), ',', s_glob(13), ',', s_glob(14), &
                ',', a(AUD_ARC_DIRECT), ',', a(AUD_ARC_DISCARD), &
                ',', a(AUD_MC_DEPOSIT), &
                ',', a(AUD_MELT_MASS), ',', a(AUD_RESOLID_MASS), &
                ',', a(AUD_MELT_E_SOLID), ',', a(AUD_ALPHA_CLIP_MASS), &
                ',', a(AUD_SLAG_INTERCEPT), &
                ',', a(AUD_RAD_SOL), ',', a(AUD_RAD_WALL), &
                ',', s_glob(15), ',', s_glob(16), ',', a(AUD_CHEM_SOL), &
                ',', a(AUD_MC_LOST), ',', s_glob(17), ',', s_glob(18), &
                ',', s_glob(19), ',', a(AUD_ECS_MASS), ',', a(AUD_ECS_ENERGY), &
                ',', a(AUD_FLUX_MASS), ',', a(AUD_FLUX_E), &
                ',', a(AUD_FE_YIELD), ',', a(AUD_FE_RETURN), &
                ',', a(AUD_SLAG_OX_E), ',', a(AUD_SLAG_RED_E), &
                ',', a(AUD_RAD_FOAM), &
                ',', a(AUD_IPH_SOL), ',', a(AUD_IPH_GAS), ',', a(AUD_IPH_LIQ), &
                ',', a(AUD_RESID_MASS), ',', a(AUD_RESID_E), ',', a(AUD_SPILL_MASS), &
                ',', a(AUD_VOL_DALPHA), ',', a(AUD_VOL_LIM), ',', a(AUD_VOL_UNLINKED), &
                ',', mx_glob(1), ',', mx_glob(2), ',', mx_glob(3), &
                ',', a(AUD_CHARGE_MASS), ',', a(AUD_CHARGE_E), ',', a(AUD_C_OXID), &
                ',', a(AUD_DIL_O2), ',', a(AUD_DIL_CO), ',', a(AUD_DIL_CO2), &
                ',', a(AUD_GAS_VOLFIX), ',', a(AUD_SLAG_TCLIP), ',', a(AUD_MIX_INIT), &
                ',', a(AUD_RESOLID_E), ',', a(AUD_ALPHA_CLIP_E), &
                ',', a(AUD_CONV_LIQ), ',', a(AUD_CONV_GAS), ',', a(AUD_ABS_GAS_HOOK), &
                ',', a(AUD_SLAG_GAS), ',', a(AUD_SLAG_LIQ), &
                ',', a(AUD_GAS_OUT), ',', a(AUD_GAS_RXN), ',', a(AUD_GAS_VOLFIX_E), &
                ',', a(AUD_VF_O2), ',', a(AUD_VF_CO), ',', a(AUD_VF_CO2), &
                ',', a(AUD_GAS_CCDROP), ',', a(AUD_SLAG_CLIP_MASS), ',', a(AUD_SLAG_CLIP_E), ',', a(AUD_SLAG_SOL), ',', a(AUD_STEEL_DEF_MASS), ',', a(AUD_STEEL_DEF_E), &
                ',', a(AUD_ABS_LIQ_HOOK), ',', a(AUD_RELAX_LIQ), ',', a(AUD_RELAX_GAS), &
                ',', a(AUD_MG_ERR_FREE), ',', a(AUD_MG_ERR_MULTI), ',', a(AUD_MG_ERR_ABS), &
                ',', a(AUD_MG_ERR_OUT), ',', a(AUD_MG_SKIP), ',', a(AUD_MG_VF_CELLS), &
                ',', a(AUD_MG_COMP), ',', a(AUD_MG_EOS), ',', a(AUD_MG_ERR_LIQ), &
                ',', a(AUD_MG_ERR_ABS_MULTI), ',', a(AUD_MG_ERR_REM_ABS), ',', a(AUD_MG_LIQ_SKIP), &
                ',', a(AUD_MG_VPOIS_ABS), ',', a(AUD_MG_VEFF_ABS), ',', a(AUD_MG_ERR_ABS_NOGAS), &
                ',', a(AUD_MG_COMP_ABS), ',', a(AUD_MG_EOS_ABS), ',', a(AUD_MG_ERR_LIQ_ALL), ',', a(AUD_MG_ERR_REM_ABS_ALL), &
                ',', a(AUD_MG_COMP_ABS_NOGAS), ',', a(AUD_MG_ERR_ABS_NOLINK), ',', a(AUD_MG_CELLS_NOLINK), ',', a(AUD_MG_E2_NOLINK), &
                ',', a(AUD_MG_ERR_LIQ_LK), ',', a(AUD_MG_ERR_LIQ_UNL), ',', a(AUD_MG_ERR_LIQ_UNL_ABS), &
                ',', a(AUD_MG_VPOIS_ABS_NOGAS), ',', a(AUD_MG_VEFF_ABS_NOGAS), ',', a(AUD_MG_REJ_NOGAS), ',', a(AUD_MG_E2_SKIP), &
                ',', a(AUD_MG_COMP_MULTI), ',', a(AUD_MG_EOS_MULTI), ',', a(AUD_MG_FLUX_MULTI), ',', a(AUD_MG_RX_MULTI), &
                ',', a(AUD_MG_COMP_FREE), ',', a(AUD_MG_EOS_FREE), ',', a(AUD_MG_FLUX_FREE), ',', a(AUD_MG_RX_FREE), &
                ',', a(AUD_MG_ERR_CC_MULTI), ',', a(AUD_MG_ERR_CC_FREE), ',', a(AUD_MG_REM2_ABS_MULTI), &
                ',', a(AUD_MG_REM2_ABS_FREE), ',', a(AUD_MG_ERR_ABS_FREE), ',', a(AUD_MG_CC_ABS_MULTI), &
                ',', a(AUD_MG_CC_ABS_FREE), ',', a(AUD_MG_CC_SKIP), &
                ',', a(AUD_MG_ERR_ART_MULTI), ',', a(AUD_MG_ERR_ART_FREE), ',', a(AUD_MG_ART_ABS_MULTI), &
                ',', a(AUD_MG_ART_ABS_FREE)
            close(iu)
        end if
    end subroutine audit_write_step

    !---------------------------------------------------------------------------
    ! Integrales de fuente del PASO (columnas 9..16): fuentes tal como las
    ! recibe cada ecuación de energía (mismo guard de fase y mismo peso
    ! w = alpha_q/(al+ag) que solve_energy_3d, C1.7). Llamar CADA paso,
    ! después de resolver la física y ANTES de adapt_timestep (usa cfg%dt
    ! del paso corrido). Local al rank; se reduce al escribir.
    !---------------------------------------------------------------------------
    subroutine audit_accumulate(liq, gas, gas_T_old, sh, m, cfg, ag_heat)
        type(phase_t), intent(in)  :: liq, gas
        ! alpha_g con la que el gas ABSORBIO el calor del paso (antes de que la
        ! flotacion de la escoria la cambie; auditoria 2, N-A1/N-B2): con dT
        ! grande en el encendido la alpha final desfasaba el libro un 14 %
        real(dp), intent(in), optional :: ag_heat(-1:,-1:,-1:)
        ! T del gas al INICIO del paso: medida integral del calor absorbido
        ! por la ecuación del gas (forma T con rho(T)): E_gas_abs +=
        ! alpha*rho(T)*cp*(T - T_old)*V. Con EOS rho~1/T el inventario de
        ! estado alpha*rho*cp*T es CONSTANTE bajo calentamiento puro, y la
        ! forma log deja de valer cuando la masa ADVECTA (low-Mach): la
        ! única medida consistente con el esquema es esta integral por
        ! paso (el balance la usa en lugar de dE_gas de estado).
        real(dp), intent(in)       :: gas_T_old(-1:,-1:,-1:)
        type(shared_t), intent(in) :: sh
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg

        real(dp) :: vol, src_dt, w_l, w_g, dT_eq
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft, dfl, dfg
        integer  :: i, j, k
        integer  :: istart, iend, jstart, jend, kstart, kend
        logical  :: liq_energy_on, gas_energy_on, gas_mass_on
        logical  :: at_rmin_aud, at_rmax_aud, at_zmin_aud, at_zmax_aud

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin_aud, at_rmax_aud, &
                                     at_zmin_aud, at_zmax_aud)
        ! (B5-3) Tg_end valido en todas las ramas salvo la mezcla (B4-9)
        book_split = (.not. cfg%mixture_model) .and. allocated(sh%Tg_end)
        if (book_split) book_split = all(sh%Tg_end(istart:iend,jstart:jend,kstart:kend) > 0.0_dp)
        liq_energy_on = cfg%solve_energy
        gas_energy_on = cfg%solve_energy .and. cfg%solve_flow .and. &
                        cfg%solve_multiphase
        ! (WS-K9) la MASA venteada (AUD_GAS_OUT) no depende de la energia:
        ! audit_gas_cells y el cierre mass_gas_flux_closure solo exigen flujo
        ! multifase; con solve_energy = false m_gas_out quedaba en 0 y el
        ! cierre daba una falsa alarma (panel WS-K8, auditor B1)
        gas_mass_on = cfg%solve_flow .and. cfg%solve_multiphase

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    vol = m%vol(i,j,k)
                    src_dt = vol * cfg%dt   ! (hooks: ver audit_set_energy)
                    if (gas_energy_on .and. &
                        gas%alpha(i,j,k) >= ALPHA_CUTOFF) then
                        ! Calor absorbido por el gas en el PASO completo
                        ! (medida alpha*rho(T)*cp*dT, consistente con la
                        ! ecuación en forma T; incluye la remoción explícita
                        ! de la interfase, que ocurre tras el solve).
                        ! LIMITACIÓN MEDIDA (2026-09): es una cuadratura de
                        ! integral de camino por paso; con dT/paso grande
                        ! (ignición sobre lecho denso) su error es O(dT^2):
                        ! la forma lineal con rho(T_fin) da -1.5% y la forma
                        ! log rho*T*ln(T/T_old) +2% en el cold de 10 pasos —
                        ! ACOTAN el balance. En régimen convergido el error
                        ! cae al residuo iterativo (3e-6, gate deep). La
                        ! medida exacta exige acumular en cada update de T
                        ! con el rho local (pendiente del audit).
                        ! (B5-3) hasta Tg_end (fin del SIMPLE) si existe: lo
                        ! que la ECUACION hizo; los pokes posteriores entran
                        ! exactos al escribir (ver audit_write_step)
                        if (book_split) then
                            dT_eq = sh%Tg_end(i,j,k) - gas_T_old(i,j,k)
                        else
                            dT_eq = gas%T(i,j,k) - gas_T_old(i,j,k)
                        end if
                        if (present(ag_heat)) then
                            srcacc(18) = srcacc(18) + ag_heat(i,j,k) * &
                                gas%rho(i,j,k) * gas%cp(i,j,k) * dT_eq * vol
                        else
                            srcacc(18) = srcacc(18) + gas%alpha(i,j,k) * &
                                gas%rho(i,j,k) * gas%cp(i,j,k) * dT_eq * vol
                        end if
                    end if

                    ! masa que las reacciones aportan al gas (A4-6)
                    acc(AUD_GAS_RXN) = acc(AUD_GAS_RXN) + (sh%S_CO_src(i,j,k) + &
                        sh%S_CO2_src(i,j,k) + sh%S_O2_src(i,j,k)) * vol * cfg%dt
                    ! Entalpía del gas venteado por las salidas del techo.
                    ! Las celdas outlet tienen fila IDENTIDAD en el Poisson
                    ! (Dirichlet pp=0): su divergencia no está controlada y
                    ! son el SUMIDERO del dominio — la masa/entalpía que les
                    ! entra por las caras 'desaparece' ahí (no por la cara
                    ! superior, cuyo flujo es 0 contra el halo inactivo).
                    ! Se contabiliza la entalpía convectiva NETA que entra.
                    if (gas_mass_on .and. k == m%nz .and. at_zmax_aud) then
                        block
                            integer :: e
                            logical :: is_out
                            real(dp) :: ein
                            is_out = .false.
                            do e = 1, N_ELECTRODES
                                if (m%is_electrode(i,j,k,e)) is_out = .true.
                            end do
                            if (is_out) then
                                ! (auditoria 4, A4-6) los MISMOS flujos de masa
                                ! conservativos que usa la energia del gas
                                ! (ws_Fg, M24); con face_mass_fluxes el venteo
                                ! medido no era el de la ecuacion y la cota al
                                ! defecto convectivo no podia cerrarse
                                if (ws_Fg_valid) then
                                    Fw = ws_Fg_r(i-1,j,k) * ws_Fg_lk_r(i-1,j,k)
                                    Fe = ws_Fg_r(i,j,k)   * ws_Fg_lk_r(i,j,k)
                                    Fs = ws_Fg_th(i,j-1,k) * ws_Fg_lk_th(i,j-1,k)
                                    Fn = ws_Fg_th(i,j,k)   * ws_Fg_lk_th(i,j,k)
                                    Fb = ws_Fg_z(i,j,k-1) * ws_Fg_lk_z(i,j,k-1)
                                    Ft = ws_Fg_z(i,j,k)   * ws_Fg_lk_z(i,j,k)
                                else
                                call face_mass_fluxes(gas%alpha, gas%rho, &
                                    gas%ur, gas%uth, gas%uz, m, i, j, k, &
                                    Fw, Fe, Fs, Fn, Fb, Ft)
                                end if
                                if (gas_energy_on) then
                                ein = ( max(Fw,0.0_dp)*gas%T(i-1,j,k) &
                                      - max(-Fw,0.0_dp)*gas%T(i,j,k)  &
                                      - max(Fe,0.0_dp)*gas%T(i,j,k)   &
                                      + max(-Fe,0.0_dp)*gas%T(i+1,j,k) &
                                      + max(Fs,0.0_dp)*gas%T(i,j-1,k) &
                                      - max(-Fs,0.0_dp)*gas%T(i,j,k)  &
                                      - max(Fn,0.0_dp)*gas%T(i,j,k)   &
                                      + max(-Fn,0.0_dp)*gas%T(i,j+1,k) &
                                      + max(Fb,0.0_dp)*gas%T(i,j,k-1) &
                                      - max(-Fb,0.0_dp)*gas%T(i,j,k)  &
                                      - max(Ft,0.0_dp)*gas%T(i,j,k)   &
                                      + max(-Ft,0.0_dp)*gas%T(i,j,k+1) ) * &
                                      gas%cp(i,j,k)
                                srcacc(17) = srcacc(17) + ein * cfg%dt
                                end if
                                ! masa neta que entra a la celda outlet (A4-6)
                                acc(AUD_GAS_OUT) = acc(AUD_GAS_OUT) + cfg%dt * &
                                    (Fw - Fe + Fs - Fn + Fb - Ft)
                            end if
                        end block
                    end if

                end do
            end do
        end do

        ! Volcar los términos exactos del hook del solver (última outer del
        ! paso) y resetear para el siguiente paso. La remoción explícita de
        ! la interfase (post-energía) queda capturada por los INVENTARIOS.
        srcacc(9)  = srcacc(9)  + eeq(1,2)   ! liq arc
        srcacc(10) = srcacc(10) + eeq(1,3)   ! liq rad
        srcacc(11) = srcacc(11) + eeq(1,4)   ! liq chem
        srcacc(12) = srcacc(12) + eeq(2,2)   ! gas arc
        srcacc(13) = srcacc(13) + eeq(2,3)   ! gas rad
        srcacc(14) = srcacc(14) + eeq(2,4)   ! gas chem
        srcacc(15) = srcacc(15) + eeq(1,5) + eeq(2,5)   ! conv defect
        srcacc(16) = srcacc(16) + eeq(1,6) + eeq(2,6)   ! wall
        ! (eeq(:,1) = absorbed del hook: diagnóstico; el absorbed del GAS
        ! para el balance es la integral post-paso de abajo, que incluye la
        ! remoción explícita de la interfase)
        srcacc(19) = srcacc(19) + eeq(1,7)   ! liq mass terms (fusión)
        acc(AUD_CONV_LIQ) = acc(AUD_CONV_LIQ) + eeq(1,5)
        acc(AUD_CONV_GAS) = acc(AUD_CONV_GAS) + eeq(2,5)
        acc(AUD_ABS_GAS_HOOK) = acc(AUD_ABS_GAS_HOOK) + eeq(2,1)
        acc(AUD_ABS_LIQ_HOOK) = acc(AUD_ABS_LIQ_HOOK) + eeq(1,1)
        acc(AUD_RELAX_LIQ) = acc(AUD_RELAX_LIQ) + eq_residual(1)
        acc(AUD_RELAX_GAS) = acc(AUD_RELAX_GAS) + eq_residual(2)
        eeq = 0.0_dp
    end subroutine audit_accumulate

    !---------------------------------------------------------------------------
    ! (WS-K6) Volfix de UNA celda propia (indices locales): las rutas que
    ! suman AUD_GAS_VOLFIX lo registran tambien aqui con el mismo dm, para
    ! que el balance por celda lo reste. Antes del primer paso (carga de la
    ! cesta 1, flotacion inicial) o sin audit no hace nada.
    !---------------------------------------------------------------------------
    subroutine audit_volfix_cell(i, j, k, dm)
        integer, intent(in)  :: i, j, k
        real(dp), intent(in) :: dm
        if (.not. allocated(mg_vf)) return
        mg_vf(i,j,k) = mg_vf(i,j,k) + dm
    end subroutine audit_volfix_cell

    !---------------------------------------------------------------------------
    ! (WS-K7) Complemento alpha_g = 1 - sum de UNA celda (indices locales):
    ! dm = rho_g V (alpha_g nueva - vieja) en los sitios de mod_continuity.
    ! Sin asignar (antes del primer paso, sin audit) no hace nada. Las celdas
    ! de halo pueden escribirse: la suma del modo 1 solo recorre las propias.
    !---------------------------------------------------------------------------
    subroutine audit_comp_cell(i, j, k, dm)
        integer, intent(in)  :: i, j, k
        real(dp), intent(in) :: dm
        if (.not. allocated(mg_comp)) return
        mg_comp(i,j,k) = mg_comp(i,j,k) + dm
        mg_comp_abs(i,j,k) = mg_comp_abs(i,j,k) + abs(dm)
    end subroutine audit_comp_cell

    ! (WS-K7) EOS de UNA celda: dm = alpha_g V (rho_g nueva - vieja) en
    ! update_properties.
    subroutine audit_eos_cell(i, j, k, dm)
        integer, intent(in)  :: i, j, k
        real(dp), intent(in) :: dm
        if (.not. allocated(mg_eos)) return
        mg_eos(i,j,k) = mg_eos(i,j,k) + dm
        mg_eos_abs(i,j,k) = mg_eos_abs(i,j,k) + abs(dm)
    end subroutine audit_eos_cell

    !---------------------------------------------------------------------------
    ! Clase de una celda para el balance de masa del gas: 0 outlet (sumidero,
    ! su e es el venteo), 1 gas libre (sin liquido, escoria NI solido),
    ! 2 multifase. asl es la escoria en volumen (Plan H): fuera de la vista
    ! condensada liq%alpha no la incluye y el complemento tambien actua ahi.
    !---------------------------------------------------------------------------
    pure integer function gas_cell_class(al, asl, as, is_out)
        real(dp), intent(in) :: al, asl, as
        logical, intent(in)  :: is_out
        if (is_out) then
            gas_cell_class = 0
        else if (al < ALPHA_FLOW_CUTOFF .and. asl < ALPHA_FLOW_CUTOFF .and. as < ALPHA_FLOW_CUTOFF) then
            gas_cell_class = 1
        else
            gas_cell_class = 2
        end if
    end function gas_cell_class

    !---------------------------------------------------------------------------
    ! Balance de masa del gas POR CELDA (WS-K5). mode 0 al INICIO del paso
    ! guarda a rho V y la clase; mode 1 al FINAL (tras la ultima EOS, el
    ! estado que escribe m_gas) acumula e = d(a rho V) - dt sum ws_Fg - rxn.
    ! Una celda es libre solo si lo es al inicio Y al final del paso (la
    ! clase de un solo instante atribuia al gas libre el cambio de fase de
    ! la celda). Sin ws_Fg valido (mezcla, sin multifase) cuenta el paso en
    ! m_gas_cells_skip y no acumula: las columnas valdrian 0 en silencio.
    !---------------------------------------------------------------------------
    subroutine audit_gas_cells(mode, liq, gas, sol, slag, sh, m, cfg)
        integer, intent(in)        :: mode
        type(phase_t), intent(in)  :: liq, gas
        type(solid_t), intent(in)  :: sol
        type(slag_t), intent(in)   :: slag
        type(shared_t), intent(in) :: sh
        type(mesh_t), intent(in)   :: m
        type(config_t), intent(in) :: cfg
        integer  :: i, j, k, e, c, istart, iend, jstart, jend, kstart, kend
        real(dp) :: fl, rx, ee, vp, ve, el, el_unl, el_lk, vin, cc, ecc, eart, elf
        logical  :: is_out, liq_ok, has_gas, lk_any, e2_ok, unl_ok, lim_ok, cc_ok
        logical  :: at_rmin_aud, at_rmax_aud, at_zmin_aud, at_zmax_aud

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin_aud, at_rmax_aud, at_zmin_aud, at_zmax_aud)
        if (mode == 0) then
            if (.not. allocated(mg_ini)) allocate(mg_ini, mold=gas%alpha)
            if (.not. allocated(mg_vf)) allocate(mg_vf, mold=gas%alpha)
            mg_vf = 0.0_dp
            if (.not. allocated(mg_comp)) allocate(mg_comp, mold=gas%alpha)
            if (.not. allocated(mg_eos)) allocate(mg_eos, mold=gas%alpha)
            if (.not. allocated(mg_ag0)) allocate(mg_ag0, mold=gas%alpha)
            if (.not. allocated(mg_comp_abs)) allocate(mg_comp_abs, mold=gas%alpha)
            if (.not. allocated(mg_eos_abs)) allocate(mg_eos_abs, mold=gas%alpha)
            mg_comp = 0.0_dp; mg_eos = 0.0_dp; mg_comp_abs = 0.0_dp; mg_eos_abs = 0.0_dp
            if (.not. allocated(mg_cls0)) allocate(mg_cls0(lbound(gas%alpha,1):ubound(gas%alpha,1), &
                lbound(gas%alpha,2):ubound(gas%alpha,2), lbound(gas%alpha,3):ubound(gas%alpha,3)))
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        mg_ini(i,j,k) = gas%alpha(i,j,k) * gas%rho(i,j,k) * m%vol(i,j,k)
                        mg_ag0(i,j,k) = gas%alpha(i,j,k)
                        mg_cls0(i,j,k) = gas_cell_class(liq%alpha(i,j,k), slag_vol(i,j,k), &
                                                        sol%alpha_s(i,j,k), outlet(i,j,k))
                    end do
                end do
            end do
            mg_ini_ok = .true.
            return
        end if
        ! (WS-K7) complemento y EOS del paso: entran SIEMPRE que el modo 0
        ! haya corrido (tambien en mezcla y una fase, donde el balance por
        ! celda se omite): la identidad d m_gas = comp + eos + volfix no
        ! depende de ws_Fg
        if (mg_ini_ok) then
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        if (m%cell_type(i,j,k) == 0) cycle
                        acc(AUD_MG_COMP) = acc(AUD_MG_COMP) + mg_comp(i,j,k)
                        acc(AUD_MG_EOS)  = acc(AUD_MG_EOS)  + mg_eos(i,j,k)
                        acc(AUD_MG_COMP_ABS) = acc(AUD_MG_COMP_ABS) + mg_comp_abs(i,j,k)
                        acc(AUD_MG_EOS_ABS)  = acc(AUD_MG_EOS_ABS)  + mg_eos_abs(i,j,k)
                    end do
                end do
            end do
        end if
        if (.not. (mg_ini_ok .and. ws_Fg_valid .and. cfg%solve_flow .and. cfg%solve_multiphase)) then
            ! un contador por paso (lo suma solo el rank 0 tras la reduccion)
            if ((.not. m%is_parallel) .or. m%topo%rank == 0) acc(AUD_MG_SKIP) = acc(AUD_MG_SKIP) + 1.0_dp
            mg_ini_ok = .false.
            return
        end if
        mg_ini_ok = .false.
        ! (WS-K7) desajuste liquido Poisson/transporte: exige los flujos del
        ! ultimo Poisson (ws_Fc) y del ultimo transporte explicito (ws_Fr);
        ! el fallback implicito los invalida y el paso se cuenta aparte
        ! (B-1) con escoria condensada ws_Fr es el flujo del acero y el
        ! complemento sigue al condensado: err_liq no vale, se cuenta el paso
        liq_ok = ws_Fc_valid .and. ws_flux_valid .and. .not. slag_condensed_on(cfg)
        if (.not. liq_ok) then
            if ((.not. m%is_parallel) .or. m%topo%rank == 0) acc(AUD_MG_LIQ_SKIP) = acc(AUD_MG_LIQ_SKIP) + 1.0_dp
        end if
        ! (C-144) E2 aceptada por el ultimo Poisson de ESTE paso, y la E2 del
        ! ultimo transporte (para el desfase); fraccion admitida del limitador
        e2_ok  = cfg%pc_drift_source .and. ws_pc_unl_used_valid .and. ws_pc_unl_used_id == probe_current_step()
        unl_ok = ws_pc_unl_valid .and. ws_pc_unl_id == probe_current_step()
        lim_ok = ws_lim_step_valid .and. ws_lim_step_id == probe_current_step()
        if (cfg%pc_drift_source .and. .not. e2_ok) then
            if ((.not. m%is_parallel) .or. m%topo%rank == 0) acc(AUD_MG_E2_SKIP) = acc(AUD_MG_E2_SKIP) + 1.0_dp
        end if
        ! (WS-K8) demanda de compresibilidad aceptada por el ultimo Poisson
        cc_ok = ws_su_cc_used_valid .and. ws_su_cc_used_id == probe_current_step()
        if (.not. cc_ok) then
            if ((.not. m%is_parallel) .or. m%topo%rank == 0) acc(AUD_MG_CC_SKIP) = acc(AUD_MG_CC_SKIP) + 1.0_dp
        end if
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    is_out = outlet(i,j,k)
                    c = gas_cell_class(liq%alpha(i,j,k), slag_vol(i,j,k), sol%alpha_s(i,j,k), is_out)
                    if (c == 1 .and. mg_cls0(i,j,k) == 2) c = 2
                    fl = cfg%dt * ( ws_Fg_r(i-1,j,k) * ws_Fg_lk_r(i-1,j,k) - ws_Fg_r(i,j,k) * ws_Fg_lk_r(i,j,k) &
                                  + ws_Fg_th(i,j-1,k) * ws_Fg_lk_th(i,j-1,k) - ws_Fg_th(i,j,k) * ws_Fg_lk_th(i,j,k) &
                                  + ws_Fg_z(i,j,k-1) * ws_Fg_lk_z(i,j,k-1) - ws_Fg_z(i,j,k) * ws_Fg_lk_z(i,j,k) )
                    rx = (sh%S_CO_src(i,j,k) + sh%S_CO2_src(i,j,k) + sh%S_O2_src(i,j,k)) * m%vol(i,j,k) * cfg%dt
                    ee = gas%alpha(i,j,k) * gas%rho(i,j,k) * m%vol(i,j,k) - mg_ini(i,j,k) - fl - rx &
                       - mg_vf(i,j,k)
                    acc(AUD_MG_VF_CELLS) = acc(AUD_MG_VF_CELLS) + mg_vf(i,j,k)
                    ! (WS-K8) gas que el Poisson planeo ventear por compresibilidad
                    ! (rho_g dt (su_cc - gadv - store_gas)) frente a lo que la EOS
                    ! reescribio, y almacenamiento artificial de la fila (eart)
                    cc = 0.0_dp; eart = 0.0_dp
                    if (cc_ok) then
                        cc = gas%rho(i,j,k) * cfg%dt * (ws_su_cc_used(i,j,k) - ws_gadv_used(i,j,k) &
                                                        - ws_store_gas(i,j,k))
                        eart = -gas%rho(i,j,k) * cfg%dt * ws_store_art(i,j,k)
                    end if
                    ecc = mg_eos(i,j,k) + cc - rx
                    ! desajuste del liquido tambien en gas libre (goteo, E2)
                    elf = 0.0_dp
                    if (liq_ok) then
                        vp = cfg%dt * ( ws_Fc_r(i-1,j,k) - ws_Fc_r(i,j,k) + ws_Fc_th(i,j-1,k) - ws_Fc_th(i,j,k) &
                                      + ws_Fc_z(i,j,k-1) - ws_Fc_z(i,j,k) )
                        if (e2_ok) vp = vp + cfg%dt * ws_pc_unl_used(i,j,k)
                        ve = cfg%dt * ( ws_Fr(i-1,j,k) - ws_Fr(i,j,k) + ws_Fth(i,j-1,k) - ws_Fth(i,j,k) &
                                      + ws_Fz(i,j,k-1) - ws_Fz(i,j,k) ) / liq%rho(i,j,k)
                        elf = gas%rho(i,j,k) * (vp - ve)
                    end if
                    select case (c)
                    case (0)
                        acc(AUD_MG_ERR_OUT) = acc(AUD_MG_ERR_OUT) + ee
                        cycle
                    case (1)
                        acc(AUD_MG_ERR_FREE) = acc(AUD_MG_ERR_FREE) + ee
                        acc(AUD_MG_ERR_ABS_FREE) = acc(AUD_MG_ERR_ABS_FREE) + abs(ee)
                        acc(AUD_MG_COMP_FREE) = acc(AUD_MG_COMP_FREE) + mg_comp(i,j,k)
                        acc(AUD_MG_EOS_FREE)  = acc(AUD_MG_EOS_FREE)  + mg_eos(i,j,k)
                        acc(AUD_MG_FLUX_FREE) = acc(AUD_MG_FLUX_FREE) + fl
                        acc(AUD_MG_RX_FREE)   = acc(AUD_MG_RX_FREE)   + rx
                        acc(AUD_MG_ERR_CC_FREE) = acc(AUD_MG_ERR_CC_FREE) + ecc
                        acc(AUD_MG_CC_ABS_FREE) = acc(AUD_MG_CC_ABS_FREE) + abs(cc)
                        acc(AUD_MG_ERR_ART_FREE) = acc(AUD_MG_ERR_ART_FREE) + eart
                        acc(AUD_MG_ART_ABS_FREE) = acc(AUD_MG_ART_ABS_FREE) + abs(eart)
                        if (cc_ok .and. liq_ok) acc(AUD_MG_REM2_ABS_FREE) = acc(AUD_MG_REM2_ABS_FREE) &
                            + abs(ee - elf - ecc - eart)
                    case default
                        acc(AUD_MG_ERR_MULTI) = acc(AUD_MG_ERR_MULTI) + ee
                        acc(AUD_MG_ERR_ABS_MULTI) = acc(AUD_MG_ERR_ABS_MULTI) + abs(ee)
                        acc(AUD_MG_COMP_MULTI) = acc(AUD_MG_COMP_MULTI) + mg_comp(i,j,k)
                        acc(AUD_MG_EOS_MULTI)  = acc(AUD_MG_EOS_MULTI)  + mg_eos(i,j,k)
                        acc(AUD_MG_FLUX_MULTI) = acc(AUD_MG_FLUX_MULTI) + fl
                        acc(AUD_MG_RX_MULTI)   = acc(AUD_MG_RX_MULTI)   + rx
                        acc(AUD_MG_ERR_CC_MULTI) = acc(AUD_MG_ERR_CC_MULTI) + ecc
                        acc(AUD_MG_CC_ABS_MULTI) = acc(AUD_MG_CC_ABS_MULTI) + abs(cc)
                        acc(AUD_MG_ERR_ART_MULTI) = acc(AUD_MG_ERR_ART_MULTI) + eart
                        acc(AUD_MG_ART_ABS_MULTI) = acc(AUD_MG_ART_ABS_MULTI) + abs(eart)
                        ! conjunto con gas (C-126): alpha_g > 0 al inicio o al final
                        has_gas = gas%alpha(i,j,k) > 0.0_dp .or. mg_ag0(i,j,k) > 0.0_dp
                        ! alguna cara enlazada en el ultimo Poisson (liquido o gas):
                        ! define la clase nolink (C-132). V_pois ya no la usa: lleva
                        ! la E2 que el Poisson acepto de verdad (ws_pc_unl_used, C-144)
                        lk_any = ws_Fc_lk_r(i-1,j,k) == 1 .or. ws_Fc_lk_r(i,j,k) == 1 &
                            .or. ws_Fc_lk_th(i,j-1,k) == 1 .or. ws_Fc_lk_th(i,j,k) == 1 &
                            .or. ws_Fc_lk_z(i,j,k-1) == 1 .or. ws_Fc_lk_z(i,j,k) == 1 &
                            .or. ws_Fg_lk_r(i-1,j,k) == 1 .or. ws_Fg_lk_r(i,j,k) == 1 &
                            .or. ws_Fg_lk_th(i,j-1,k) == 1 .or. ws_Fg_lk_th(i,j,k) == 1 &
                            .or. ws_Fg_lk_z(i,j,k-1) == 1 .or. ws_Fg_lk_z(i,j,k) == 1
                        ! (B2) los conjuntos se cuentan aunque falten los flujos del liquido
                        if (.not. has_gas) then
                            acc(AUD_MG_ERR_ABS_NOGAS) = acc(AUD_MG_ERR_ABS_NOGAS) + abs(ee)
                            acc(AUD_MG_COMP_ABS_NOGAS) = acc(AUD_MG_COMP_ABS_NOGAS) + mg_comp_abs(i,j,k)
                        end if
                        if (.not. lk_any) then
                            acc(AUD_MG_ERR_ABS_NOLINK) = acc(AUD_MG_ERR_ABS_NOLINK) + abs(ee)
                            acc(AUD_MG_CELLS_NOLINK) = acc(AUD_MG_CELLS_NOLINK) + 1.0_dp
                            ! lo que SE HABRIA sumado (ws_pc_unl del transporte N)
                            if (cfg%pc_drift_source .and. unl_ok) acc(AUD_MG_E2_NOLINK) = &
                                acc(AUD_MG_E2_NOLINK) + abs(gas%rho(i,j,k) * cfg%dt * ws_pc_unl(i,j,k))
                        end if
                        if (liq_ok) then
                            ! volumen de liquido que el Poisson balanceo (ws_Fc es
                            ! VOLUMETRICO, alpha_f u_f A, en caras enlazadas; mas la
                            ! fuente E2 que ESE Poisson acepto, ws_pc_unl_used) y el
                            ! que el transporte movio (ws_Fr es MASA, todas las caras)
                            vp = cfg%dt * ( ws_Fc_r(i-1,j,k) - ws_Fc_r(i,j,k) + ws_Fc_th(i,j-1,k) - ws_Fc_th(i,j,k) &
                                          + ws_Fc_z(i,j,k-1) - ws_Fc_z(i,j,k) )
                            if (e2_ok) vp = vp + cfg%dt * ws_pc_unl_used(i,j,k)
                            ve = cfg%dt * ( ws_Fr(i-1,j,k) - ws_Fr(i,j,k) + ws_Fth(i,j-1,k) - ws_Fth(i,j,k) &
                                          + ws_Fz(i,j,k-1) - ws_Fz(i,j,k) ) / liq%rho(i,j,k)
                            el = gas%rho(i,j,k) * (vp - ve)
                            ! reparto: desfase E2 (no enlazadas) y resto (enlazadas)
                            el_unl = 0.0_dp
                            if (e2_ok .and. unl_ok) el_unl = gas%rho(i,j,k) * cfg%dt * &
                                (ws_pc_unl_used(i,j,k) - ws_pc_unl(i,j,k))
                            el_lk = el - el_unl
                            ! definicion original de C-121: todas las multifase
                            acc(AUD_MG_ERR_LIQ_ALL) = acc(AUD_MG_ERR_LIQ_ALL) + el
                            acc(AUD_MG_ERR_REM_ABS_ALL) = acc(AUD_MG_ERR_REM_ABS_ALL) + abs(ee - el)
                            acc(AUD_MG_ERR_LIQ_LK)  = acc(AUD_MG_ERR_LIQ_LK)  + el_lk
                            acc(AUD_MG_ERR_LIQ_UNL) = acc(AUD_MG_ERR_LIQ_UNL) + el_unl
                            acc(AUD_MG_ERR_LIQ_UNL_ABS) = acc(AUD_MG_ERR_LIQ_UNL_ABS) + abs(el_unl)
                            ! (WS-K8) plan completo del Poisson: liquido + compresibilidad
                            if (cc_ok) acc(AUD_MG_REM2_ABS_MULTI) = acc(AUD_MG_REM2_ABS_MULTI) + abs(ee - el - ecc - eart)
                            if (has_gas) then
                                acc(AUD_MG_ERR_LIQ) = acc(AUD_MG_ERR_LIQ) + el
                                acc(AUD_MG_ERR_REM_ABS) = acc(AUD_MG_ERR_REM_ABS) + abs(ee - el)
                                acc(AUD_MG_VPOIS_ABS) = acc(AUD_MG_VPOIS_ABS) + abs(gas%rho(i,j,k) * vp)
                                acc(AUD_MG_VEFF_ABS)  = acc(AUD_MG_VEFF_ABS)  + abs(gas%rho(i,j,k) * ve)
                            else
                                ! fuera del conjunto con gas: err_liq := 0 en C-126
                                acc(AUD_MG_ERR_REM_ABS) = acc(AUD_MG_ERR_REM_ABS) + abs(ee)
                                ! (R1) tamano del plan del Poisson y del transporte real
                                acc(AUD_MG_VPOIS_ABS_NOGAS) = acc(AUD_MG_VPOIS_ABS_NOGAS) + abs(gas%rho(i,j,k) * vp)
                                acc(AUD_MG_VEFF_ABS_NOGAS)  = acc(AUD_MG_VEFF_ABS_NOGAS)  + abs(gas%rho(i,j,k) * ve)
                                if (lim_ok) then
                                    vin = cfg%dt * ( max(ws_Fc_r(i-1,j,k), 0.0_dp) + max(-ws_Fc_r(i,j,k), 0.0_dp) &
                                                   + max(ws_Fc_th(i,j-1,k), 0.0_dp) + max(-ws_Fc_th(i,j,k), 0.0_dp) &
                                                   + max(ws_Fc_z(i,j,k-1), 0.0_dp) + max(-ws_Fc_z(i,j,k), 0.0_dp) )
                                    acc(AUD_MG_REJ_NOGAS) = acc(AUD_MG_REJ_NOGAS) + &
                                        gas%rho(i,j,k) * (1.0_dp - ws_lim_step(i,j,k)) * vin
                                end if
                            end if
                        end if
                    end select
                    acc(AUD_MG_ERR_ABS) = acc(AUD_MG_ERR_ABS) + abs(ee)
                end do
            end do
        end do
    contains
        ! outlet: misma definicion que m_gas_out (celdas de electrodo del techo)
        logical function outlet(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            outlet = .false.
            if (kk == m%nz .and. at_zmax_aud) then
                do e = 1, N_ELECTRODES
                    if (m%is_electrode(ii,jj,kk,e)) outlet = .true.
                end do
            end if
        end function outlet
        real(dp) function slag_vol(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            slag_vol = 0.0_dp
            if (allocated(slag%alpha_sl)) slag_vol = slag%alpha_sl(ii,jj,kk)
        end function slag_vol
    end subroutine audit_gas_cells

    !---------------------------------------------------------------------------
    logical function is_writer(m)
        type(mesh_t), intent(in) :: m
        is_writer = (.not. m%is_parallel) .or. (m%topo%rank == 0)
    end function is_writer

end module mod_audit
