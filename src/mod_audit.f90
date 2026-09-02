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
! Semántica de columnas de contadores: acumulado desde la línea anterior.
!===============================================================================
module mod_audit
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology, only: mpi_allreduce_sum
    use mod_parallel_utils, only: get_loop_bounds
    implicit none
    private

    public :: audit_init, audit_write_step, audit_add
    public :: AUD_ARC_DIRECT, AUD_ARC_DISCARD, AUD_MC_DEPOSIT
    public :: AUD_ALPHA_CLIP_MASS, AUD_MELT_MASS, AUD_RESOLID_MASS
    public :: AUD_MELT_E_SOLID, AUD_SLAG_INTERCEPT
    public :: AUD_RAD_SOL, AUD_RAD_WALL

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
    integer, parameter :: N_AUD = 10

    real(dp), save :: acc(N_AUD) = 0.0_dp
    character(len=320), save :: audit_path = ''

contains

    !---------------------------------------------------------------------------
    subroutine audit_add(id, val)
        integer, intent(in)  :: id
        real(dp), intent(in) :: val
        acc(id) = acc(id) + val
    end subroutine audit_add

    !---------------------------------------------------------------------------
    ! Crea audit.csv con encabezado y escribe la línea del estado inicial
    ! (paso 0: solo inventarios; llamar DESPUÉS de charge_scrap/slag_init)
    !---------------------------------------------------------------------------
    subroutine audit_init(liq, gas, sol, slag, sh, elec, m, cfg)
        type(phase_t), intent(in)     :: liq, gas
        type(solid_t), intent(in)     :: sol
        type(slag_t),  intent(in)     :: slag
        type(shared_t), intent(in)    :: sh
        type(electrode_t), intent(in) :: elec(:)
        type(mesh_t), intent(in)      :: m
        type(config_t), intent(in)    :: cfg

        integer :: iu

        audit_path = trim(cfg%output_dir) // '/audit.csv'
        if (is_writer(m)) then
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
                'E_slag_intercept,E_rad_sol,E_rad_wall'
            close(iu)
        end if
        acc = 0.0_dp
        call audit_write_step(liq, gas, sol, slag, sh, elec, m, cfg, &
                              0, 0.0_dp)
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

        ! sums: 1-8 inventarios, 9-14 fuentes por fase (arc, rad, chem)
        integer, parameter :: NSUM = 14
        real(dp) :: s(NSUM), s_glob(NSUM), a(N_AUD)
        real(dp) :: vol, src_dt, P_arc, w_l, w_g, C0_datum
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

        s = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    vol = m%vol(i,j,k)

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
                    s(6) = s(6) + gas%alpha(i,j,k) * cfg%rho_gas * &
                                  cfg%T_ambient * gas%cp(i,j,k) * vol * &
                                  log(max(gas%T(i,j,k), T_MIN_GAS) / &
                                      cfg%T_ambient)
                    s(7) = s(7) + sol%E_s(i,j,k)
                    s(8) = s(8) + slag%E_sl(i,j,k)

                    ! Fuentes tal como las recibe cada ecuación de energía
                    ! (mismo guard de fase Y mismo peso w = alpha_q/(al+ag)
                    ! que solve_energy_3d, C1.7)
                    src_dt = vol * cfg%dt
                    w_l = liq%alpha(i,j,k) / &
                          (liq%alpha(i,j,k) + gas%alpha(i,j,k) + SMALL)
                    w_g = gas%alpha(i,j,k) / &
                          (liq%alpha(i,j,k) + gas%alpha(i,j,k) + SMALL)
                    if (liq_energy_on .and. &
                        liq%alpha(i,j,k) >= ALPHA_CUTOFF) then
                        s(9)  = s(9)  + sh%S_arc(i,j,k)  * w_l * src_dt
                        ! Radiación (C3.4): neto k_f*(G - 4 sigma T_fase^4),
                        ! evaluado con la T actual de la fase (espejo de la
                        ! linearización de solve_energy_3d)
                        s(10) = s(10) + sh%kappa_f(i,j,k) * (sh%G_rad(i,j,k) &
                                - 4.0_dp * STEFAN_BOLTZMANN * liq%T(i,j,k)**4) &
                                * w_l * src_dt
                        s(11) = s(11) + sh%S_chem(i,j,k) * w_l * src_dt
                    end if
                    if (gas_energy_on .and. &
                        gas%alpha(i,j,k) >= ALPHA_CUTOFF) then
                        s(12) = s(12) + sh%S_arc(i,j,k)  * w_g * src_dt
                        s(13) = s(13) + sh%kappa_f(i,j,k) * (sh%G_rad(i,j,k) &
                                - 4.0_dp * STEFAN_BOLTZMANN * gas%T(i,j,k)**4) &
                                * w_g * src_dt
                        s(14) = s(14) + sh%S_chem(i,j,k) * w_g * src_dt
                    end if
                end do
            end do
        end do

        ! Reducción global (contadores locales + sumas de celda)
        if (m%is_parallel) then
            do n = 1, NSUM
                call mpi_allreduce_sum(s(n), s_glob(n), m%topo)
            end do
            do n = 1, N_AUD
                call mpi_allreduce_sum(acc(n), a(n), m%topo)
            end do
        else
            s_glob = s
            a = acc
        end if
        acc = 0.0_dp

        P_arc = 0.0_dp
        do n = 1, size(elec)
            P_arc = P_arc + elec(n)%arc_power
        end do

        if (is_writer(m)) then
            open(newunit=iu, file=trim(audit_path), status='old', &
                 action='write', position='append')
            write(iu, '(I0,A,ES16.9,A,ES16.9,25(A,ES16.9))') &
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
                ',', a(AUD_RAD_SOL), ',', a(AUD_RAD_WALL)
            close(iu)
        end if
    end subroutine audit_write_step

    !---------------------------------------------------------------------------
    logical function is_writer(m)
        type(mesh_t), intent(in) :: m
        is_writer = (.not. m%is_parallel) .or. (m%topo%rank == 0)
    end function is_writer

end module mod_audit
