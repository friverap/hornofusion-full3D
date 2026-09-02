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
    use mod_mpi_topology, only: mpi_allreduce_sum
    use mod_parallel_utils, only: get_loop_bounds
    use mod_face_flux, only: face_mass_fluxes
    use mod_boundary_3d, only: physical_boundary_flags
    implicit none
    private

    public :: audit_init, audit_write_step, audit_add, audit_accumulate
    public :: audit_set_energy
    public :: AUD_ARC_DIRECT, AUD_ARC_DISCARD, AUD_MC_DEPOSIT
    public :: AUD_ALPHA_CLIP_MASS, AUD_MELT_MASS, AUD_RESOLID_MASS
    public :: AUD_MELT_E_SOLID, AUD_SLAG_INTERCEPT
    public :: AUD_RAD_SOL, AUD_RAD_WALL, AUD_CHEM_SOL, AUD_MC_LOST

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
    integer, parameter :: N_AUD = 12

    real(dp), save :: acc(N_AUD) = 0.0_dp
    ! Integrales de fuente acumuladas POR PASO entre escrituras (9..16 del
    ! esquema de columnas): con audit_freq>1, evaluarlas solo al escribir
    ! subrepresentaba las columnas de fuente ~audit_freq veces (medido en el
    ! hito bore-in con audit_freq=10; los contadores acc() siempre fueron
    ! completos). audit_accumulate se llama CADA paso desde main.
    real(dp), save :: srcacc(9:19) = 0.0_dp

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
                'E_slag_intercept,E_rad_sol,E_rad_wall,E_conv_defect,' // &
                'E_wall_conv,E_chem_sol,E_mc_lost,E_out_conv,E_gas_abs,E_mass_liq'
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

        ! sums: 1-8 inventarios, 9-14 fuentes por fase (arc, rad, chem),
        ! 15: déficit conservativo de la convección de energía (forma
        ! acotada de Patankar: se resta la continuidad discreta x T; el
        ! déficit global = Sum dF_neto*cp*T — la entalpía de pluma que el
        ! operador no entrega; físicamente ~ el off-gas no ventilado)
        ! 16: pérdida convectiva a paredes Robin (C3.1), sum alpha*h*A*(T-Tw)
        integer, parameter :: NSUM = 19
        real(dp) :: s(NSUM), s_glob(NSUM), a(N_AUD)
        real(dp) :: vol, P_arc, C0_datum
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

                end do
            end do
        end do

        ! Las integrales de fuente (columnas 9..16) las acumula
        ! audit_accumulate CADA paso; aquí solo se recogen
        s(9:19) = srcacc(9:19)

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
        srcacc = 0.0_dp

        P_arc = 0.0_dp
        do n = 1, size(elec)
            P_arc = P_arc + elec(n)%arc_power
        end do

        if (is_writer(m)) then
            open(newunit=iu, file=trim(audit_path), status='old', &
                 action='write', position='append')
            write(iu, '(I0,A,ES16.9,A,ES16.9,32(A,ES16.9))') &
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
                ',', s_glob(19)
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
    subroutine audit_accumulate(liq, gas, gas_T_old, sh, m, cfg)
        type(phase_t), intent(in)  :: liq, gas
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

        real(dp) :: vol, src_dt, w_l, w_g
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft, dfl, dfg
        integer  :: i, j, k
        integer  :: istart, iend, jstart, jend, kstart, kend
        logical  :: liq_energy_on, gas_energy_on
        logical  :: at_rmin_aud, at_rmax_aud, at_zmin_aud, at_zmax_aud

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        call physical_boundary_flags(m, at_rmin_aud, at_rmax_aud, &
                                     at_zmin_aud, at_zmax_aud)
        liq_energy_on = cfg%solve_energy
        gas_energy_on = cfg%solve_energy .and. cfg%solve_flow .and. &
                        cfg%solve_multiphase

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
                        ! de la interfase, que ocurre tras el solve)
                        srcacc(18) = srcacc(18) + gas%alpha(i,j,k) * &
                            gas%rho(i,j,k) * gas%cp(i,j,k) * &
                            (gas%T(i,j,k) - gas_T_old(i,j,k)) * vol
                    end if

                    ! Entalpía del gas venteado por las salidas del techo.
                    ! Las celdas outlet tienen fila IDENTIDAD en el Poisson
                    ! (Dirichlet pp=0): su divergencia no está controlada y
                    ! son el SUMIDERO del dominio — la masa/entalpía que les
                    ! entra por las caras 'desaparece' ahí (no por la cara
                    ! superior, cuyo flujo es 0 contra el halo inactivo).
                    ! Se contabiliza la entalpía convectiva NETA que entra.
                    if (gas_energy_on .and. k == m%nz .and. at_zmax_aud) then
                        block
                            integer :: e
                            logical :: is_out
                            real(dp) :: ein
                            is_out = .false.
                            do e = 1, N_ELECTRODES
                                if (m%is_electrode(i,j,k,e)) is_out = .true.
                            end do
                            if (is_out) then
                                call face_mass_fluxes(gas%alpha, gas%rho, &
                                    gas%ur, gas%uth, gas%uz, m, i, j, k, &
                                    Fw, Fe, Fs, Fn, Fb, Ft)
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
        eeq = 0.0_dp
    end subroutine audit_accumulate

    !---------------------------------------------------------------------------
    logical function is_writer(m)
        type(mesh_t), intent(in) :: m
        is_writer = (.not. m%is_parallel) .or. (m%topo%rank == 0)
    end function is_writer

end module mod_audit
