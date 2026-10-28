!===============================================================================
! main_3d.f90 - 3D EAF Multiphysics Simulator (MPI-enabled)
!
! Replicates Ugarte et al. (2024) Materials 17(21), 5139
! 3D Cylindrical (r, theta, z) coordinates
! Finite Volume Method with SIMPLE pressure-velocity coupling
! Eulerian-Eulerian multiphase (gas + liquid) + dual-cell solid
! Cassie-Mayr AC arc model + Monte Carlo arc radiation
! k-epsilon turbulence + Discrete Ordinate radiation
! Carbon oxidation (Maahs rate)
!
! MPI: 3D domain decomposition with halo exchange
!===============================================================================
program eaf_3d_simulator
    use, intrinsic :: iso_fortran_env, only: compiler_version
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_parallel_utils
    use mod_config_3d
    use mod_mesh_3d
    use mod_fields_3d
    use mod_output_hdf5
    use mod_restart
    use mod_probe, only: probe_report, probe_set_step, probe_active
    use mod_solver_3d
    use mod_boundary_3d
    use mod_energy_3d
    use mod_properties_3d
    use mod_momentum_3d
    use mod_pressure_3d
    use mod_drag_ergun
    use mod_continuity
    use mod_multiphase
    use mod_mixture_3d
    use mod_workspace, only: ensure_workspace, ws_liq_cont_prev, ws_sp_asl, ws_sp_es, ws_sp_mx, ws_Tsrc, ws_flux_valid, ws_Fc_valid, ws_cc, ws_cc_new, ws_cc_drop, ws_p_n, ws_Fg_valid, &
                             ws_liq_cont, ws_liq_cont_valid
    use mod_solid_phase
    use mod_melting_3d
    use mod_scrap_collapse
    use mod_interphase_ht
    use mod_arc_cassie_mayr
    use mod_electrode_3d
    use mod_arc_radiation_mc
    use mod_lorentz_3d
    use mod_slag_3d
    use mod_turbulence_3d
    use mod_radiation_do
    use mod_chemistry_carbon
    use mod_species_transport
    use mod_convergence_3d
    use mod_input_profiles
    use mod_audit
    use mod_timers
    use mod_ecs_feed
    use mod_slag_chemistry
    implicit none

    ! Main variables
    type(config_t)        :: cfg
    type(mesh_t)          :: mesh
    type(phase_t)         :: liq, gas
    type(phase_t)         :: liq_old, gas_old
    real(dp), allocatable :: sort_a(:,:,:), sort_t(:,:,:), sort_p(:,:,:)   ! (Plan H P5) delta del reordenamiento
    type(solid_t)         :: sol
    type(slag_t)          :: slag
    type(shared_t)        :: sh
    type(electrode_t)     :: elec(N_ELECTRODES)
    type(convergence_t)   :: conv
    real(dp), allocatable :: tke_n(:,:,:), eps_n(:,:,:)   ! ancla temporal de k-eps (A13)
    type(elec_profile_t)  :: elec_prof
    type(rate_profile_t)  :: ecs_prof, cal_prof, cinj_prof
    real(dp) :: mdot_ecs
    real(dp), allocatable :: ag_heat(:,:,:)

    ! Time loop
    real(dp) :: time, V_elec, I_elec
    real(dp) :: dt_nominal = 0.0_dp
    real(dp) :: dt_step = 0.0_dp      ! (B6-1) dt del ultimo paso dado
    ! (auditoria 5, B5-28/B5-29) ultimo paso decidido UNA vez con el dt del
    ! paso; fila del audit ya escrita en este paso (el freno de NaN no la repite)
    logical  :: last_step = .false., audit_written = .false.
    integer  :: step, outer, e
    integer  :: step_start   ! paso del estado inicial (0 o el del snapshot; B4-5)
    ! (auditoria 16, M16-I2) parada por tiempo de reloj
    integer(8) :: wall_c0, wall_c, wall_rate
    real(dp)   :: wall_loc, wall_glob
    logical    :: wall_stop = .false.

    ! Coeficiente de drag de Ergun (implícito en aP; C1.4)
    real(dp), allocatable :: drag_coef(:,:,:)

    ! Iterado externo anterior para sub-relajación en las ramas
    ! no-multifase (C2.1; la rama multifase lo maneja multiphase_iteration)
    real(dp), allocatable :: prev_ur(:,:,:), prev_uth(:,:,:)
    real(dp), allocatable :: prev_uz(:,:,:), prev_T(:,:,:)
    ! Kexch nulo para la rama monofásica
    real(dp), allocatable :: K_zero(:,:,:)

    ! Species transport old-timestep arrays
    real(dp), allocatable :: Y_CO_old(:,:,:), Y_CO2_old(:,:,:), Y_O2_old(:,:,:)
    real(dp), allocatable :: alpha_sg(:,:,:), alpha_lg(:,:,:), S_gas_net(:,:,:), alsl_g(:,:,:), S_arc_mc(:,:,:)
    real(dp) :: res_Y_CO, res_Y_CO2, res_Y_O2

    ! Config and input files
    character(len=256) :: config_file
    integer :: nargs
    ! Reinicio desde snapshot (restart_file en el config)
    logical :: restarting

    !===================================================================
    ! INITIALIZATION
    !===================================================================
    
    ! MPI se inicializa ANTES de leer el config (auditoria, bajos): la lectura
    ! la hacen todos los ranks y asi solo rank 0 imprime sus mensajes. La
    ! TOPOLOGIA (que necesita las dimensiones de la malla) va despues.
    block
        use mpi
        integer :: ierr_init
        call MPI_Init(ierr_init)
    end block
    call config_set_defaults(cfg)
    nargs = command_argument_count()
    if (nargs >= 1) then
        call get_command_argument(1, config_file)
        call config_read(cfg, config_file)
    else
        if (cfg_root()) print *, ' [MAIN] No config file specified, using defaults.'
    end if
    call config_validate(cfg)
    
    ! Initialize MPI with correct mesh dimensions
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    
    if (should_print(mesh)) then
        print *, '============================================================'
        print *, '  3D EAF Multiphysics Simulator (MPI Parallel)'
        print *, '  Ugarte et al. (2024) - HBI/Scrap Melting in Industrial EAF'
        print *, '  Cylindrical FVM / SIMPLE / Eulerian-Eulerian'
        print *, '  Cassie-Mayr AC arc / k-eps / DO radiation'
        print *, '============================================================'
        print '(A,I0,A)', '  Running on ', mesh%topo%nprocs, ' MPI processes'
        ! (WS-K9) que binario corrio queda en run.log (panel WS-K8, evidencia
        ! O4: los bancos de campana usan binarios copiados en campaigns/bin)
        block
            character(len=1024) :: exe
            call get_command_argument(0, exe)
            print '(A,A)', '  Ejecutable: ', trim(exe)
            print '(A,A)', '  Compilador: ', compiler_version()
        end block
        print *, '============================================================'
    end if

    if (should_print(mesh)) call config_print(cfg)

    ! Generate mesh (parallel with halos)
    call mesh_generate_parallel(mesh, cfg)

    ! Allocate fields (with halos in parallel mode)
    call phase_allocate(liq, mesh)
    call phase_allocate(gas, mesh)
    call phase_allocate(liq_old, mesh)
    call phase_allocate(gas_old, mesh)
    call solid_allocate(sol, mesh)
    call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    sh%model_mixture = cfg%mixture_model
    call ensure_workspace(mesh)   ! ws_Tsrc (auditoria A3) se pasa a la energia en todas las ramas
    allocate(tke_n, eps_n, mold=sh%tke)
    tke_n = sh%tke; eps_n = sh%eps

    allocate(drag_coef, mold=liq%ur)
    drag_coef = 0.0_dp
    allocate(prev_ur, mold=liq%ur); allocate(prev_uth, mold=liq%uth)
    allocate(prev_uz, mold=liq%uz); allocate(prev_T, mold=liq%T)
    allocate(K_zero, mold=liq%ur); K_zero = 0.0_dp

    allocate(Y_CO_old,  mold=sh%Y_CO);  Y_CO_old  = 0.0_dp
    allocate(Y_CO2_old, mold=sh%Y_CO2); Y_CO2_old = 0.0_dp
    allocate(Y_O2_old,  mold=sh%Y_O2);  Y_O2_old  = 0.0_dp

    ! Initialize all fields
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)

    ! Initialize electrodes
    call init_electrodes(elec, cfg)

    ! Load charge recipe (input/charge_recipe.dat; con fallback al default
    ! si no existe — C4.4: antes el archivo JAMÁS se leía) y perfil V/I
    ! Una receta NOMBRADA en el config que no existe es un error (con el
    ! fallback silencioso al default, un banco lanzado desde otro directorio
    ! corrio la carga por defecto sin avisar, Plan D 7-oct-2026). La ruta por
    ! defecto conserva el fallback (configs antiguos; test_recipe).
    block
        logical :: recipe_ok
        inquire(file=trim(cfg%charge_recipe_file), exist=recipe_ok)
        if (.not. recipe_ok .and. trim(cfg%charge_recipe_file) /= 'input/charge_recipe.dat') then
            if (should_print(mesh)) print '(3A)', ' [INPUT] ERROR: charge_recipe_file "', &
                trim(cfg%charge_recipe_file), '" no existe (ruta relativa al directorio de trabajo)'
            call mpi_finalize_topology(mesh%topo)
            stop 1
        end if
    end block
    call read_charge_recipe(cfg, trim(cfg%charge_recipe_file))
    call read_electrode_profile(elec_prof, trim(cfg%electrode_profile_file), &
                                cfg%elec_V_const, cfg%elec_I_const)
    if (cfg%solve_ecs) then
        call read_rate_profile(ecs_prof, cfg%ecs_profile_file, cfg%ecs_rate)
    end if
    if (cfg%solve_slag) then
        call read_rate_profile(cal_prof, cfg%cal_profile_file, cfg%cal_rate)
        call read_rate_profile(cinj_prof, cfg%carbon_inj_profile_file, &
                               cfg%carbon_inj_rate)
    end if

    ! Create output directory (only rank 0), then synchronize so no rank
    ! tries to create the HDF5 file before the directory exists
    if (should_print(mesh)) then
        call execute_command_line('mkdir -p ' // trim(cfg%output_dir))
    end if
    if (mesh%is_parallel) then
        block
            integer :: ierr_barrier
            call MPI_Barrier(mesh%topo%comm_cart, ierr_barrier)
        end block
    end if

    ! Write initial mesh (HDF5)
    if (should_print(mesh)) then
        print *, ' [MAIN] Writing initial state...'
    end if

    time = 0.0_dp
    step = 0
    restarting = len_trim(cfg%restart_file) > 0

    if (.not. restarting) then
        ! Load first bucket (omitible para tests de carga continua pura;
        ! NOTA hallazgo E1.3: charge_scrap asigna NIVELES enteros con el vfrac
        ! de la capa aunque la capa pida menos volumen — la masa cargada excede
        ! la receta (~5x medido). Revisar en B1 (benchmark Ugarte).)
        if (cfg%charge_bucket1) then
            call charge_scrap(sol, gas, mesh, cfg, 1)
            ! (bajo N-B15) halos del solido y del gas coherentes antes de que
            ! init_heel / slag_initialize lean vecinas
            call solid_exchange_halos(sol, mesh)
            call phase_exchange_halos(gas, mesh)
        end if
        call init_heel(liq, gas, sol, mesh, cfg)
        call phase_exchange_halos(liq, mesh)

        ! Initialize slag layer (above scrap surface)
        if (cfg%solve_slag) then
            call slag_initialize(slag, sol, liq, gas, mesh, cfg)
            call slag_exchange_halos(slag, mesh)
            ! (Plan H) la colocacion legada UNA vez (llena el hueco de la celda
            ! de superficie, gas auditado); despues solo reordenamiento
            if (slag_condensed_on(cfg) .and. len_trim(cfg%restart_file) == 0) then
                call slag_buoyancy(slag, liq, gas, sol, mesh, cfg, sh)
                call slag_exchange_halos(slag, mesh)
                call phase_exchange_halos(gas, mesh)
            end if
        end if
        ! (dirigida de bajos A18, B4) init_heel y slag_initialize reescriben
        ! alpha_g en celdas propias: halos del gas coherentes en toda rama
        call phase_exchange_halos(gas, mesh)
        ! Presion hidrostatica inicial de la mezcla fluida (remanente en reposo;
        ! Plan C F2): evita el golpe de 50-70 kPa del primer paso
        if (slag_condensed_on(cfg)) then
            call initialize_hydrostatic_pressure(liq, gas, sh, mesh, cfg, slag%alpha_sl)
        else
            call initialize_hydrostatic_pressure(liq, gas, sh, mesh, cfg)
        end if
        ! rho del gas con la presion inicial (EOS rho(P0 + p, T), M25)
        call update_properties(liq, gas, sh, mesh, cfg)
    else
        ! Reinicio: el estado completo (campos, solido, escoria, electrodos,
        ! dt, paso y tiempo) viene del snapshot; la carga, el remanente y la
        ! hidrostatica inicial NO se repiten. La receta y los perfiles si se
        ! leyeron (cubeta 2, ECS, adiciones siguen gobernados por el tiempo).
        call restart_read(cfg%restart_file, mesh, cfg, liq, gas, sol, slag, &
                          sh, elec, step, time)
    end if

    ! Write initial state (t=0, step=0; o el estado reanudado). Al reanudar
    ! NO se sobrescribe un snapshot existente (auditoria 12-oct-2026, M4): si
    ! restart_file estaba en output_dir, se truncaba el snapshot de origen y se
    ! reescribia con las fuentes en cero.
    block
        character(len=512) :: fn0
        logical :: ex0
        write(fn0, '(A,A,I8.8,A)') trim(cfg%output_dir), '/eaf3d_', step, '.h5'
        inquire(file=trim(fn0), exist=ex0)
        if (.not. (restarting .and. ex0)) &
            call write_hdf5_parallel(mesh, liq, gas, sol, slag, sh, elec, cfg%dt, &
                                     step, time, cfg%output_dir)
    end block

    step_start = step

    ! Auditoría de balances: encabezado + línea del estado inicial
    if (cfg%audit_freq > 0) then
        call audit_init(liq, gas, sol, slag, sh, elec, mesh, cfg, step, time)
    end if

    !===================================================================
    ! TIME LOOP
    !===================================================================
    conv%converged = .false.

    if (should_print(mesh)) then
        print *, ''
        print *, ' [MAIN] Starting time integration...'
        print *, ''
    end if

    call system_clock(wall_c0, wall_rate)
    dt_step = cfg%dt
    time_loop: do while (time < cfg%t_final)

        ! El ultimo paso termina EXACTAMENTE en t_final (auditoria, bajos: el
        ! lazo lo rebasaba y, por el redondeo de la suma de dt, podia dar un
        ! paso de mas: melt_forced t_final 0.11 / dt 0.01 corria 12 pasos)
        ! El dt TRUNCADO del ultimo paso no es estado (auditoria 3, M3-12):
        ! el snapshot final guardaba el recorte y una corrida extendida desde
        ! el arrancaba con ese dt (o desde dt_min), sin ser bit a bit con la
        ! continua. Se guarda el nominal y se restituye al salir del lazo.
        ! (B5-28) el ultimo paso lo decidio el paso anterior con SU dt (antes
        ! este test usaba el dt ya adaptado y podia discrepar del predicado
        ! que escribio la ultima fila del audit)
        if (last_step) exit time_loop
        dt_nominal = cfg%dt
        if (time + cfg%dt > cfg%t_final) then
            ! (bajo B6-1) mismo umbral que decidio last_step (dt del paso
            ! anterior, dt_step): con el dt ya adaptado habia una franja en la
            ! que se salia sin la fila final del audit; aqui last_step era falso
            ! y el hueco es > 1e-6 dt_step: se da el paso corto final
            if (cfg%t_final - time <= 1.0e-6_dp * dt_step) exit time_loop
            cfg%dt = cfg%t_final - time
        end if

        step = step + 1
        time = time + cfg%dt
        ! (WS-K5) masa del gas por celda al inicio del paso: balance por celda
        if (cfg%audit_freq > 0) call audit_gas_cells(0, liq, gas, sol, slag, sh, mesh, cfg)
        dt_step = cfg%dt
        last_step = (cfg%t_final - time <= 1.0e-6_dp * cfg%dt)
        audit_written = .false.
        
        if (should_print(mesh)) then
            !print '(A,I0,A,F8.2)', ' [DEBUG] Starting step ', step, ' t=', time
        end if

        ! Store old fields
        liq_old%T   = liq%T;   liq_old%ur  = liq%ur
        liq_old%uth = liq%uth; liq_old%uz  = liq%uz
        liq_old%alpha = liq%alpha
        gas_old%T   = gas%T;   gas_old%ur  = gas%ur
        gas_old%uth = gas%uth; gas_old%uz  = gas%uz
        gas_old%alpha = gas%alpha
        ! densidades del paso anterior (auditoria, bajos: la masa del
        ! transitorio de la mezcla las usa; antes *_old%rho no se copiaba)
        liq_old%rho = liq%rho; gas_old%rho = gas%rho
        ! p^n de la EOS de referencia de la compresibilidad (M25)
        ws_p_n = sh%p
        ! Ancla temporal de k-eps (auditoria A13)
        tke_n = sh%tke; eps_n = sh%eps

        ! Second bucket
        if (cfg%n_layers_b2 > 0 .and. &
            time >= cfg%t_bucket2_charge .and. &
            time - cfg%dt < cfg%t_bucket2_charge) then
            call charge_scrap(sol, gas, mesh, cfg, 2, sh, slag)
            ! Recarga (auditoria A10): los electrodos se retiran al techo y la
            ! perforacion de la nueva cesta empieza de nuevo
            do e = 1, N_ELECTRODES
                elec(e)%z_tip = cfg%H_total - 0.1_dp
                elec(e)%bore_in_done = .false.
            end do
            call solid_exchange_halos(sol, mesh)
            call phase_exchange_halos(gas, mesh)
            if (should_print(mesh)) then
                print '(A,F10.1)', ' [MAIN] Second bucket charged at t=', time
            end if
        end if

        ! Cargador continuo ECS (E1): fuente de masa por banda
        if (cfg%solve_ecs .and. time >= cfg%ecs_t_start .and. &
            time <= cfg%ecs_t_stop) then
            mdot_ecs = interpolate_rate(ecs_prof, time)
            call ecs_feed(sol, gas, liq, mesh, cfg, mdot_ecs, cfg%dt, sh, slag)
            call solid_exchange_halos(sol, mesh)
            ! (auditoria 21, B21-P1) sin el if: en serie el intercambio hace
            ! el relleno periodico en theta (como B4-1 con las Y)
            call mpi_exchange_halos_3d(gas%alpha, mesh%topo)
        end if

        ! Update electrode V/I from profile
        call interpolate_profile(elec_prof, time, V_elec, I_elec)

        ! Update arc model
        call timer_start(T_ARC)
        if (cfg%solve_arc) then
            do e = 1, N_ELECTRODES
                call update_arc_resistance(elec(e), V_elec, I_elec)
            end do
            call update_electrodes(elec, sol, liq, mesh, cfg, cfg%dt)
            ! C4.2: un solo gather global de alpha_s por paso, compartido por
            ! el depósito directo y el MC (antes cada uno hacía el suyo)
            if (.not. allocated(alpha_sg)) &
                allocate(alpha_sg(mesh%nr_g, mesh%nth_g, mesh%nz_g))
            call gather_global_field(sol%alpha_s, alpha_sg, mesh)
            ! M12: el impacto en el baño se decide con alpha_l global (y N-A2:
            ! P_elec va al baño bajo el electrodo)
            if (.not. allocated(alpha_lg)) &
                allocate(alpha_lg(mesh%nr_g, mesh%nth_g, mesh%nz_g))
            call gather_global_field(liq%alpha, alpha_lg, mesh)
            if (cfg%solve_slag) then
                if (.not. allocated(alsl_g)) allocate(alsl_g(mesh%nr_g, mesh%nth_g, mesh%nz_g))
                call gather_global_field(slag%alpha_sl, alsl_g, mesh)
                call distribute_arc_heat(elec, sh, sol, mesh, cfg, alpha_sg, N_ELECTRODES, alpha_lg, alsl_g)
            else
                call distribute_arc_heat(elec, sh, sol, mesh, cfg, alpha_sg, N_ELECTRODES, alpha_lg)
            end if
            ! (M12-1arc, A13-1, oct-2026) el arco ABRE una cavidad en la
            ! escoria: P_elec y P_conv van al metal bajo ella (alpha_l), pero
            ! la RADIACION del arco la intercepta la escoria que lo rodea
            ! (apantallamiento): los rayos del MC ven alpha_l + alpha_sl y
            ! slag_intercept_arc pasa a E_sl la parte de la escoria por su
            ! kappa. Hacer de la escoria superficie de TODO el arco se probo
            ! (se llevaba ~43 MW en arc_slag, +72 K/s en su celda): no fisico.
            if (cfg%solve_slag) then
                alsl_g = alpha_lg + alsl_g
                if (.not. allocated(S_arc_mc)) allocate(S_arc_mc, mold=sh%S_arc)
                S_arc_mc = sh%S_arc
                call distribute_arc_radiation_mc(elec, sh, sol, mesh, cfg, alpha_sg, &
                                                 alsl_g, N_ELECTRODES, step)
                S_arc_mc = sh%S_arc - S_arc_mc   ! lo que deposito el MC
            else
                call distribute_arc_radiation_mc(elec, sh, sol, mesh, cfg, alpha_sg, &
                                                 alpha_lg, N_ELECTRODES, step)
            end if
            ! (mod_arc_impingement retirado en C4.4: unidades N/m4 en vez
            ! de N/m3 y magnitud ~0.2 N/m3 despreciable; la depresión del
            ! baño por el jet requiere búsqueda global de superficie —
            ! reintroducir con ese diseño si se necesita. S_arc_mom queda
            ! en 0 y el término de momentum inerte.)
            call compute_lorentz_force(elec, liq%alpha, sh, mesh, cfg, I_elec, N_ELECTRODES)
            ! La escoria intercepta su fracción de S_arc AHORA (antes de que
            ! las ecuaciones de energía lo consuman; C1.6b)
            if (cfg%solve_slag) then
                call slag_intercept_arc(slag, liq, gas, sh, mesh, cfg, S_arc_mc)
            end if
        end if
        call timer_stop(T_ARC)

        ! Radiation (DO model)
        call timer_start(T_RAD)
        if (cfg%solve_radiation) then
            call solve_radiation_do(liq, gas, sol, slag, sh, mesh, cfg)
        end if
        call timer_stop(T_RAD)

        ! Chemistry
        call timer_start(T_CHEM)
        if (cfg%solve_chemistry) then
            call compute_carbon_oxidation(sol, gas, sh, mesh, cfg)
            ! (auditoria 4, B4-2) la oxidacion del C reescribe m_s/E_s/alpha_s:
            ! halos del solido coherentes antes de que nadie lea alpha_s de una
            ! vecina (el hueco de A3-7 dependia de la descomposicion en z)
            call solid_exchange_halos(sol, mesh)
            ! Química de escoria (E2.3/E2.4): tras el carbono (usa su O2
            ! remanente) y antes del transporte de especies
            if (cfg%solve_slag) then
                call compute_slag_chemistry(slag, liq, liq_old, gas, sol, sh, mesh, cfg)
                call slag_exchange_halos(slag, mesh)
                call phase_exchange_halos(liq, mesh)
                call phase_exchange_halos(liq_old, mesh)
                ! (A18-1b) con la escoria condensada la reduccion rellena de gas
                ! el volumen que libera (gas y sus Y cambian)
                if (slag_condensed_on(cfg)) then
                    call phase_exchange_halos(gas, mesh)
                    call shared_exchange_halos(sh, mesh)
                end if
            end if
            ! Sin transporte de alpha de dos fluidos nadie repone el gas que
            ! la quimica desplaza (oxidacion del C baja alpha_s, Fe de la
            ! escoria mueve alpha_l): alpha_g es el complemento (auditoria 3,
            ! A3-7; chem_test sum_alpha 7.7e-6). Con dos fluidos lo hace la
            ! continuidad del SIMPLE. Masa de gas auditada (m_gas_volfix).
            if (.not. (cfg%solve_flow .and. cfg%solve_multiphase)) then
                call enforce_volume_constraint(liq, gas, sol, slag, mesh, cfg, sh)
                call phase_exchange_halos(gas, mesh)
                call shared_exchange_halos(sh, mesh)
            end if
        end if

        ! Species transport (CO / CO2)
        if (cfg%solve_species) then
            Y_CO_old  = sh%Y_CO
            Y_CO2_old = sh%Y_CO2
            Y_O2_old  = sh%Y_O2
            ! Fuente neta de masa del gas (dilucion, auditoria M14)
            if (.not. allocated(S_gas_net)) allocate(S_gas_net, mold=sh%S_CO_src)
            S_gas_net = sh%S_CO_src + sh%S_CO2_src + sh%S_O2_src
            call solve_species_3d(gas, sh%Y_CO,  Y_CO_old,  sh%S_CO_src,  S_gas_net, mesh, cfg, res_Y_CO)
            call solve_species_3d(gas, sh%Y_CO2, Y_CO2_old, sh%S_CO2_src, S_gas_net, mesh, cfg, res_Y_CO2)
            call solve_species_3d(gas, sh%Y_O2,  Y_O2_old,  sh%S_O2_src,  S_gas_net, mesh, cfg, res_Y_O2)
            ! Masa de cada especie desplazada por la dilucion (M14), con la
            ! misma discretizacion del solver (implicito si S_gas > 0)
            block
                integer :: ia, ja, ka, i0a, i1a, j0a, j1a, k0a, k1a
                real(dp) :: dl(3), wv
                call get_loop_bounds(mesh, i0a, i1a, j0a, j1a, k0a, k1a)
                dl = 0.0_dp
                do ka = k0a, k1a
                    do ja = j0a, j1a
                        do ia = i0a, i1a
                            if (mesh%cell_type(ia,ja,ka) == 0) cycle
                            if (gas%alpha(ia,ja,ka) < 1.0e-6_dp) cycle
                            wv = S_gas_net(ia,ja,ka) * mesh%vol(ia,ja,ka) * cfg%dt
                            if (S_gas_net(ia,ja,ka) > 0.0_dp) then
                                dl = dl + wv * [sh%Y_O2(ia,ja,ka), sh%Y_CO(ia,ja,ka), sh%Y_CO2(ia,ja,ka)]
                            else
                                dl = dl + wv * [Y_O2_old(ia,ja,ka), Y_CO_old(ia,ja,ka), Y_CO2_old(ia,ja,ka)]
                            end if
                        end do
                    end do
                end do
                call audit_add(AUD_DIL_O2, dl(1))
                call audit_add(AUD_DIL_CO, dl(2))
                call audit_add(AUD_DIL_CO2, dl(3))
            end block
            ! (auditoria 4, B4-1) tambien en serie: el relleno periodico en
            ! theta lo hace la misma rutina
            call species_exchange_halos(sh, mesh)
        end if
        call timer_stop(T_CHEM)

        !---------------------------------------------------------------
        ! OUTER ITERATION LOOP (SIMPLE)
        !---------------------------------------------------------------
        
        ! Fusión + colapso ANTES del SIMPLE; la transferencia interfase va
        ! DESPUÉS de los solves de energía (ver notas en mod_solid_phase)
        call timer_start(T_SOLID)
        if (cfg%solve_melting) then
            call update_solid_premelt(sol, liq, gas, slag, mesh, cfg, cfg%dt, sh)
            ! sin transporte de alpha de dos fluidos, el mdot se aplica aqui
            ! (auditoria 2, N-C4)
            if (.not. (cfg%solve_flow .and. cfg%solve_multiphase)) then
                call apply_mass_source_noflow(liq, gas, sol, slag, mesh, cfg, cfg%dt, sh)
                call phase_exchange_halos(liq, mesh)
                call phase_exchange_halos(gas, mesh)
                call species_exchange_halos(sh, mesh)   ! (B4-1) Y diluidas por el volfix
                ! (auditoria 5, B5-12) halos del solido tras fusion/colapso:
                ! los lee el lazo de caras del intercambio gas-liquido (en la
                ! rama de dos fluidos los intercambia multiphase_iteration)
                call solid_exchange_halos(sol, mesh)
            end if
        end if
        call timer_stop(T_SOLID)

        ! Initialize residuals to zero
        conv%res_ur = 0.0_dp
        conv%res_uth = 0.0_dp
        conv%res_uz = 0.0_dp
        conv%res_cont = 0.0_dp
        conv%n_pc = 1; conv%dalpha_pc = 0.0_dp
        conv%res_energy = 0.0_dp
        conv%res_tke = 0.0_dp
        conv%res_eps = 0.0_dp
        conv%converged = .false.
        call probe_set_step(step)
        call probe_report('inicio-paso   ', liq, gas, sol, sh, mesh, cfg)

        call timer_start(T_SIMPLE)
        ! Los flujos conservativos del transporte de alpha valen dentro del
        ! paso (el momento del liquido los usa desde la 2a iteracion externa,
        ! M24); los del paso anterior no se arrastran: no son estado del
        ! snapshot y romperian el reinicio bit a bit. Igual los del gas (M24)
        ! y los conservativos del Poisson (auditoria 20, B20-1: sin esto un paso
        ! sin Poisson leeria los ws_Fc del paso anterior en el transporte)
        ws_flux_valid = .false.
        ws_Fg_valid = .false.
        ws_Fc_valid = .false.
        ! (Plan H) estado de la escoria al INICIO del paso: el transporte
        ! condensado de cada iteracion externa parte de el
        if (slag_condensed_on(cfg)) then
            if (.not. allocated(ws_sp_asl)) then
                allocate(ws_sp_asl, ws_sp_es, mold=slag%alpha_sl)
                allocate(ws_sp_mx, mold=slag%m_X)
            end if
            ! (P5) las fuentes de escoria que cambian su masa sin tocar alpha_sl
            ! (oxidacion; la reduccion ya fija alpha_sl y rellena de gas, A18-1)
            ! se llevan al volumen de su masa antes de fijar el estado de inicio
            ! de paso; acero
            ! remapeado con su T (energia exacta) -> liq_old lo sigue (la
            ! quimica ya mantenia liq_old = liq en alpha)
            ! (auditoria 18, bajo MPI-1) guarda propia: no depender de ws_sp_*
            if (.not. allocated(sort_a)) allocate(sort_a, sort_t, sort_p, mold=liq%alpha)
            sort_a = liq%alpha; sort_t = liq%T
            ! (A18-4) el fundido pendiente del paso es volumen del liquido
            sort_p = 0.0_dp
            where (mesh%cell_type /= 0) sort_p = max(sol%mdot, 0.0_dp) * cfg%dt / (liq%rho * mesh%vol)
            call slag_condensed_sort(slag, liq, gas, sol, mesh, cfg, sh, a_pend=sort_p)
            liq_old%alpha = liq_old%alpha + (liq%alpha - sort_a)
            liq_old%T = liq_old%T + (liq%T - sort_t)
            ! (auditoria 18 MPI-5; auditoria 19 B1) entre la copia de gas_old y
            ! aqui NO hay transporte (quimica con su relleno de gas, volfix de la
            ! prefusion, sort): todo cambio de alpha_g es no convectivo y el
            ! transitorio del momento del gas debe partir del estado actual
            gas_old%alpha = gas%alpha
            ws_sp_asl = slag%alpha_sl
            ws_sp_es = slag%E_sl; ws_sp_mx = slag%m_X
        end if
        do outer = 1, cfg%max_outer

            ! Multiphase SIMPLE iteration
            if (cfg%solve_flow .and. cfg%solve_multiphase .and. cfg%mixture_model) then
                ! Plan G: modelo de mezcla con deslizamiento (mod_mixture_3d)
                call mixture_iteration(liq, gas, liq_old, gas_old, sol, slag, &
                                       sh, mesh, cfg, conv)
            else if (cfg%solve_flow .and. cfg%solve_multiphase) then
                call multiphase_iteration(liq, gas, liq_old, gas_old, sol, slag, &
                                          sh, mesh, cfg, drag_coef, conv)
            else if (cfg%solve_flow) then
                ! Ergun solo en la rama de una fase: el modelo de dos fluidos
                ! calcula el suyo (on_bed) y la mezcla no lo usa (auditoria,
                ! bajos: se calculaba en vano en cada iteracion externa)
                call compute_ergun_drag(liq, sol, mesh, cfg, drag_coef)
                prev_ur = liq%ur; prev_uth = liq%uth
                prev_uz = liq%uz; prev_T = liq%T
                call solve_momentum_3d(liq, liq_old, gas, K_zero, sh, mesh, &
                                       cfg, liq%alpha, drag_coef, .false., &
                                       conv%res_ur, conv%res_uth, conv%res_uz, &
                                       mdot_l=sol%mdot)
                call relax_field(liq%ur,  prev_ur,  cfg%alpha_u, mesh)
                call relax_field(liq%uth, prev_uth, cfg%alpha_u, mesh)
                call relax_field(liq%uz,  prev_uz,  cfg%alpha_u, mesh)
                ! Refresh halos (incl. aP_*) before Rhie-Chow in the pressure solve
                call phase_exchange_halos(liq, mesh)
                call solve_pressure_correction(liq, gas, gas%T, sh, mesh, cfg, conv%res_cont)
                if (cfg%solve_energy) then
                    ! (auditoria 4, B4-8) alpha_other = 0 tambien aqui: en la
                    ! rama de una fase el gas no tiene energia y el liquido es
                    ! el unico consumidor de las fuentes (como en la rama sin
                    ! flujo, N-M15)
                    call solve_energy_3d(liq, liq_old%T, sh, mesh, cfg, liq%alpha, &
                                         K_zero, liq_old%alpha, sol%mdot, ws_Tsrc, &
                                         .false., conv%res_energy)
                    call relax_field(liq%T, prev_T, cfg%alpha_T, mesh)
                end if
                call update_properties(liq, gas, sh, mesh, cfg)
            else if (cfg%solve_energy) then
                prev_T = liq%T
                ! alpha_other = 0: sin energía del gas, el líquido es el
                ! único consumidor de S_arc/S_chem/radiación (w_src = 1);
                ! con gas%alpha se perdía ~85% del arco (budget 0.154)
                call solve_energy_3d(liq, liq_old%T, sh, mesh, cfg, liq%alpha, &
                                     K_zero, liq_old%alpha, sol%mdot, ws_Tsrc, &
                                     .false., conv%res_energy)
                call relax_field(liq%T, prev_T, cfg%alpha_T, mesh)
                ! Propiedades tambien sin flujo: rho_gas(T) debe seguir a T
                ! (antes quedaba congelada en el valor inicial en esta rama)
                call update_properties(liq, gas, sh, mesh, cfg)
                conv%res_cont = 0.0_dp
            else
                ! No physics enabled - mark as converged immediately
                ! (bajo N-B13) con n_outer definido: llega a monitor.log y a
                ! adapt_timestep
                conv%converged = .true.
                conv%n_outer = outer
                exit
            end if

            ! Turbulence
            if (cfg%solve_turb) then
                call solve_k_epsilon(liq, sh, mesh, cfg, cfg%dt, tke_n, eps_n, &
                                     conv%res_tke, conv%res_eps)
            end if

            ! Convergence check
            conv%n_outer = outer
            conv%converged = check_convergence(conv, cfg)
            
            ! (C3.2: ya NO se fuerza converged en max_outer — el lazo está
            ! acotado por el do; la convergencia REAL gobierna el dt)
            if (conv%converged) exit
        end do
        call timer_stop(T_SIMPLE)
        ! Acarreo del exceso de compresibilidad: el de la ultima iteracion
        ! externa pasa al paso siguiente (M26)
        ws_cc = ws_cc_new
        ! (auditoria 6, M6-1/M6-2) lo que la ultima iteracion externa descarto
        ! de la demanda de compresibilidad, como masa de gas (rho_g del paso)
        if (cfg%audit_freq > 0) then
            block
                integer :: ia, ja, ka, i0a, i1a, j0a, j1a, k0a, k1a
                real(dp) :: dmc
                call get_loop_bounds(mesh, i0a, i1a, j0a, j1a, k0a, k1a)
                dmc = 0.0_dp
                do ka = k0a, k1a
                    do ja = j0a, j1a
                        do ia = i0a, i1a
                            dmc = dmc + ws_cc_drop(ia,ja,ka) * gas%rho(ia,ja,ka)
                        end do
                    end do
                end do
                call audit_add(AUD_GAS_CCDROP, dmc)
            end block
        end if
        ws_cc_drop = 0.0_dp
        ! T del gas al final del SIMPLE: referencia de la fuente de
        ! compresibilidad del paso siguiente (A3-3; la mezcla fija la suya).
        ! Estado del reinicio (/restart Tg_end).
        ! (auditoria 4, B4-9) en TODAS las ramas salvo la mezcla (que fija la
        ! suya): sin flujo el gas no cambia de T y la referencia es la misma;
        ! antes la rama sin flujo arrastraba el Tg_end del snapshot de origen
        ! y un tercer reinicio con dos fluidos partia de una referencia rancia
        if (.not. cfg%mixture_model) sh%Tg_end = gas%T

        call probe_report('fin-SIMPLE    ', liq, gas, sol, sh, mesh, cfg)

        ! Transferencia interfase (tras los solves de energía)
        call timer_start(T_SOLID)
        if (cfg%solve_melting) then
            call update_solid_postenergy(sol, liq, gas, mesh, cfg, sh)
            ! (auditoria 2, N-M10) slag_energy lee liq%T del halo
            call phase_exchange_halos(liq, mesh)
            call phase_exchange_halos(gas, mesh)
        end if
        ! Intercambio gas-liquido de dos fluidos (auditoria 2, N-A1; la mezcla
        ! lleva el suyo, y sin energia del gas su T no evoluciona)
        if (cfg%solve_flow .and. cfg%solve_multiphase .and. cfg%solve_energy &
            .and. .not. cfg%mixture_model) then
            ! (auditoria 4, B4-7) mascara de liquido continuo con la alpha FINAL
            ! del paso: la de ws_liq_cont era la del inicio de la ultima
            ! iteracion externa (halos de alpha ya intercambiados)
            ! (histeresis de la pelicula) prev es la mascara de la ultima
            ! iteracion externa, tomada con la vista condensada acero+escoria;
            ! aqui liq%alpha es solo acero: con escoria la pelicula que era
            ! continua se queda con acero >= 0.01, como antes del cambio
            call liquid_continuity_mask(liq, sol, mesh, ws_liq_cont, ws_liq_cont_prev)
            ws_liq_cont_valid = .true.
            if (slag_condensed_on(cfg)) then
                call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg, sh, slag%alpha_sl)
            else
                call compute_gas_liquid_heat(liq, gas, sol, mesh, cfg, sh)
            end if
            call phase_exchange_halos(liq, mesh)
            call phase_exchange_halos(gas, mesh)
        end if
        call timer_stop(T_SOLID)

        ! alpha_g con la que el gas absorbio el calor del paso (el libro del
        ! gas del audit; la flotacion de la escoria la cambia despues)
        if (.not. allocated(ag_heat)) allocate(ag_heat, mold=gas%alpha)
        ag_heat = gas%alpha
        ! Slag layer update (adiciones + buoyancy + energy exchange)
        call timer_start(T_SLAG)
        if (cfg%solve_slag) then
            call slag_additions(slag, mesh, cfg, &
                interpolate_rate(cal_prof, time), &
                interpolate_rate(cinj_prof, time), cfg%dt)
            call update_slag(slag, liq, gas, sol, mesh, cfg, cfg%dt, sh)
            ! (A18-10) el contacto escoria-chatarra cambia E_s/T_s
            if (slag_condensed_on(cfg)) call solid_exchange_halos(sol, mesh)
            call phase_exchange_halos(liq, mesh)
            call phase_exchange_halos(gas, mesh)
            call slag_exchange_halos(slag, mesh)
            ! (M5-5) la flotacion diluye las Y del gas que crea
            if (cfg%solve_species) call species_exchange_halos(sh, mesh)
        end if
        call timer_stop(T_SLAG)
        ! Auditoría de balances (antes de adaptar dt: usa el dt del paso).
        ! Las integrales de fuente se acumulan CADA paso; la línea CSV se
        ! escribe cada audit_freq pasos y cubre todo el intervalo.
        ! (auditoria 4, M4-3) propiedades coherentes con la T FINAL del paso,
        ! ANTES del snapshot (el reinicio arranca con ellas, bit a bit). Con
        ! gas%rho rancio (de la ultima iteracion externa) la fuente de
        ! compresibilidad del paso siguiente valia 0 bit a bit en la primera
        ! iteracion externa (rho = rho(Tg_end)), F2.31 no excluia nada en el
        ! outer 1 y si desde el 2 (topologia del acople alternando por outer),
        ! y con un solo outer se perdia la demanda.
        ! El LIBRO del gas (audit_accumulate, E_gas_abs) se acumula ANTES de
        ! actualizar propiedades: usa la rho con la que se resolvio la energia
        ! (M4-3; medido en la auditoria 5: con rho(T_fin) el balance de
        ! arc_melt pasa de -4.7e3 a -5.8e5 J). La FILA (inventarios) se
        ! escribe DESPUES (B5-25): describe el estado que va al snapshot (m_gas
        ! con la rho final; el reinicio arranca su fila 0 de ese estado y
        ! compare_audit la exige igual; antes bath_freeze s50 difería 1.1e-3).
        call timer_start(T_IO)
        if (cfg%audit_freq > 0) &
            call audit_accumulate(liq, gas, gas_old%T, sh, mesh, cfg, ag_heat)
        call timer_stop(T_IO)
        if (cfg%solve_flow .and. cfg%solve_multiphase .and. cfg%solve_energy) then
            call update_properties(liq, gas, sh, mesh, cfg)
            call phase_exchange_halos(liq, mesh)
            call phase_exchange_halos(gas, mesh)
        end if
        ! (WS-K5) balance de masa del gas por celda con la rho FINAL (la de m_gas)
        if (cfg%audit_freq > 0) call audit_gas_cells(1, liq, gas, sol, slag, sh, mesh, cfg)
        ! (auditoria 16, M16-I2) parada por tiempo de reloj: decision GLOBAL
        ! (max entre ranks) ANTES del audit, para que este paso cierre el
        ! intervalo del audit como cualquier snapshot (B4-4); el snapshot lo
        ! escribe la finalizacion (dt nominal adaptado, reanudable)
        if (cfg%wall_time_max > 0.0_dp .and. .not. last_step) then
            call system_clock(wall_c)
            wall_loc = real(wall_c - wall_c0, dp) / real(max(wall_rate, 1_8), dp)
            if (mesh%is_parallel) then
                call mpi_allreduce_max(wall_loc, wall_glob, mesh%topo)
            else
                wall_glob = wall_loc
            end if
            wall_stop = (wall_glob >= cfg%wall_time_max)
        end if
        call timer_start(T_IO)
        ! (auditoria 4, B4-4) todo SNAPSHOT (output_freq y el final de la
        ! corrida) cierra ademas el intervalo del audit: con audit_freq > 1 el
        ! tramo acumulado desde la ultima linea no se escribia en ninguna
        ! parte y un reinicio desde ese snapshot (que arranca su audit de
        ! cero) lo perdia. Con audit_freq = 1 no cambia nada.
        if (cfg%audit_freq > 0) then
            if (mod(step, cfg%audit_freq) == 0 .or. mod(step, cfg%output_freq) == 0 &
                .or. last_step .or. wall_stop) then
                call audit_write_step(liq, gas, sol, slag, sh, elec, mesh, &
                                      cfg, step, time)
                audit_written = .true.
            end if
        end if
        call timer_stop(T_IO)

        !---------------------------------------------------------------
        ! FRENO DE NaN: si algun campo o residual dejo de ser finito, la
        ! corrida NO puede producir nada util — se vuelca el estado para
        ! diagnostico y se aborta (exit 3). Decision GLOBAL: todos los
        ! ranks salen juntos (ver nan_guard_triggered).
        !---------------------------------------------------------------
        if (nan_guard_triggered(conv, liq, gas, sol, sh, mesh, step, time, slag)) then
            if (should_print(mesh)) then
                print '(A)', ''
                print '(A)', ' ================================================'
                print '(A,I0,A,F10.3,A)', ' [ABORT] NaN/Inf en el paso ', &
                      step, ' (t = ', time, ' s): corrida detenida.'
                print '(A)', ' Estado volcado para diagnostico:'
                print '(A,A)', '   snapshot: ', trim(cfg%output_dir)
                print '(A)', ' ================================================'
            end if
            ! volcado colectivo del estado corrupto (todos los ranks);
            ! (B5-29) sin repetir la fila si este paso ya la escribio
            if (cfg%audit_freq > 0 .and. .not. audit_written) then
                call audit_write_step(liq, gas, sol, slag, sh, elec, mesh, &
                                      cfg, step, time)
            end if
            call write_hdf5_parallel(mesh, liq, gas, sol, slag, sh, elec, cfg%dt, &
                                     step, time, cfg%output_dir)
            call mpi_finalize_topology(mesh%topo)
            stop 3
        end if

        ! Adaptive time stepping (criterio CFL + convergencia real; C3.2)
        ! (auditoria 5, B5-27) se adapta el dt NOMINAL, no el truncado del
        ! ultimo paso: asi el snapshot final guarda el nominal YA adaptado por
        ! el ultimo paso (M4-1 restituia el nominal sin adaptar y una corrida
        ! extendida no era bit a bit con la continua). En los pasos no
        ! truncados nominal = cfg%dt y nada cambia.
        cfg%dt = dt_nominal
        call adapt_timestep(cfg%dt, conv, &
                            compute_cfl_rate(liq, gas, mesh), &
                            interphase_tau_global(mesh), cfg)
        dt_nominal = cfg%dt

        !---------------------------------------------------------------
        ! OUTPUT (HDF5 parallel)
        !---------------------------------------------------------------
        if (mod(step, cfg%monitor_freq) == 0) then
            ! monitor.log (auditoria M33: la documentacion lo usaba y nunca se
            ! escribia). Colectiva: la masa de solido se reduce en todos los
            ! ranks; solo rank 0 escribe.
            call write_monitor_line(mesh, step, time, conv, sol, cfg%output_dir)
            if (should_print(mesh)) then
                print '(A,I8,A,F10.2,A,I3,A,5ES12.4)', &
                    ' [STEP] ', step, '  t=', time, '  outer=', conv%n_outer, &
                    '  res: ', conv%res_ur, conv%res_cont, conv%res_energy
            end if
        end if

        if (mod(step, cfg%output_freq) == 0) then
            call timer_start(T_IO)
            call write_hdf5_parallel(mesh, liq, gas, sol, slag, sh, elec, cfg%dt, &
                                     step, time, cfg%output_dir)
            call timer_stop(T_IO)
        end if
        
        if (should_print(mesh)) then
            !print '(A,I0,A,F8.2)', ' [DEBUG] Completed step ', step, ' t=', time
        end if

        if (wall_stop) then
            if (should_print(mesh)) print '(A,F12.1,A,I0,A,F12.4,A)', &
                ' [WALL] wall_time_max alcanzado (', wall_glob, ' s): snapshot en el paso ', &
                step, ' (t = ', time, ' s); reanudar con restart_file'
            exit time_loop
        end if

    end do time_loop

    !===================================================================
    ! FINALIZATION
    !===================================================================
    if (should_print(mesh)) then
        print *, ''
        print *, '============================================================'
        print '(A,I8,A,F10.2,A)', '  Simulation complete. Steps: ', step, '  Time: ', time, ' s'
        print *, '============================================================'
    end if

    ! dt nominal (no el truncado del ultimo paso) en el snapshot final (M3-12;
    ! auditoria 4 M4-1: tambien con dt adaptativo, que es el default de
    ! produccion: adapt_timestep partia del recorte -o de dt_min- y eso iba al
    ! snapshot; dt_nominal es el dt que el paso iba a usar)
    if (dt_nominal > 0.0_dp) cfg%dt = dt_nominal
    ! (auditoria 4, B4-5) sin ningun paso dado (t_final <= time al reanudar)
    ! el estado inicial ya quedo escrito -o protegido- arriba: reescribirlo
    ! truncaba el snapshot de origen con las fuentes S_* en cero
    if (step > step_start) &
        call write_hdf5_parallel(mesh, liq, gas, sol, slag, sh, elec, cfg%dt, &
                                 step, time, cfg%output_dir)

    ! Cleanup
    call phase_destroy(liq)
    call phase_destroy(gas)
    call phase_destroy(liq_old)
    call phase_destroy(gas_old)
    call solid_destroy(sol)
    call slag_destroy(slag)
    call shared_destroy(sh)
    call mesh_destroy(mesh)
    deallocate(drag_coef)
    deallocate(Y_CO_old, Y_CO2_old, Y_O2_old)

    if (should_print(mesh)) then
        print *, '  Resources freed. Done.'
    end if

    ! Finalize MPI (must be the last MPI-related action)
    call timer_report(mesh)

    call mpi_finalize_topology(mesh%topo)

contains

    subroutine init_electrodes(elec, cfg)
        type(electrode_t), intent(out) :: elec(N_ELECTRODES)
        type(config_t), intent(in)     :: cfg
        integer :: e

        do e = 1, N_ELECTRODES
            elec(e)%theta_pos  = TWO_PI * real(e-1, dp) / real(N_ELECTRODES, dp)
            elec(e)%z_tip      = cfg%H_total - 0.1_dp
            elec(e)%arc_length = 0.05_dp
            elec(e)%arc_R      = 1.0e-3_dp
            elec(e)%arc_power  = 0.0_dp
            elec(e)%voltage    = 0.0_dp
            elec(e)%current    = 0.0_dp
            elec(e)%bore_in_done = .false.
        end do
    end subroutine init_electrodes

end program eaf_3d_simulator
