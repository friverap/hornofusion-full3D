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
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_parallel_utils
    use mod_config_3d
    use mod_mesh_3d
    use mod_fields_3d
    use mod_output_hdf5
    use mod_solver_3d
    use mod_boundary_3d
    use mod_energy_3d
    use mod_properties_3d
    use mod_momentum_3d
    use mod_pressure_3d
    use mod_drag_ergun
    use mod_continuity
    use mod_multiphase
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
    implicit none

    ! Main variables
    type(config_t)        :: cfg
    type(mesh_t)          :: mesh
    type(phase_t)         :: liq, gas
    type(phase_t)         :: liq_old, gas_old
    type(solid_t)         :: sol
    type(slag_t)          :: slag
    type(shared_t)        :: sh
    type(electrode_t)     :: elec(N_ELECTRODES)
    type(convergence_t)   :: conv
    type(elec_profile_t)  :: elec_prof
    type(rate_profile_t)  :: ecs_prof, cal_prof, cinj_prof
    real(dp) :: mdot_ecs

    ! Time loop
    real(dp) :: time, V_elec, I_elec
    integer  :: step, outer, e

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
    real(dp), allocatable :: alpha_sg(:,:,:)
    real(dp) :: res_Y_CO, res_Y_CO2, res_Y_O2

    ! Config and input files
    character(len=256) :: config_file
    integer :: nargs

    !===================================================================
    ! INITIALIZATION
    !===================================================================
    
    ! Read configuration FIRST (before MPI init!)
    call config_set_defaults(cfg)
    nargs = command_argument_count()
    if (nargs >= 1) then
        call get_command_argument(1, config_file)
        call config_read(cfg, config_file)
    else
        print *, ' [MAIN] No config file specified, using defaults.'
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
    call read_charge_recipe(cfg, 'input/charge_recipe.dat')
    call read_electrode_profile(elec_prof, 'input/electrode_profile.dat')
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

    ! Load first bucket (omitible para tests de carga continua pura;
    ! NOTA hallazgo E1.3: charge_scrap asigna NIVELES enteros con el vfrac
    ! de la capa aunque la capa pida menos volumen — la masa cargada excede
    ! la receta (~5x medido). Revisar en B1 (benchmark Ugarte).)
    if (cfg%charge_bucket1) then
        call charge_scrap(sol, gas, mesh, cfg, 1)
    end if

    ! Initialize slag layer (above scrap surface)
    if (cfg%solve_slag) then
        call slag_initialize(slag, sol, gas, mesh, cfg)
        call slag_exchange_halos(slag, mesh)
    end if

    ! Write initial state (t=0, step=0)
    call write_hdf5_parallel(mesh, liq, gas, sol, slag, sh, 0, 0.0_dp, cfg%output_dir)

    ! Auditoría de balances: encabezado + línea del estado inicial
    if (cfg%audit_freq > 0) then
        call audit_init(liq, gas, sol, slag, sh, elec, mesh, cfg)
    end if

    !===================================================================
    ! TIME LOOP
    !===================================================================
    time = 0.0_dp
    step = 0
    conv%converged = .false.

    if (should_print(mesh)) then
        print *, ''
        print *, ' [MAIN] Starting time integration...'
        print *, ''
    end if

    time_loop: do while (time < cfg%t_final)

        step = step + 1
        time = time + cfg%dt
        
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

        ! Second bucket
        if (cfg%n_layers_b2 > 0 .and. &
            time >= cfg%t_bucket2_charge .and. &
            time - cfg%dt < cfg%t_bucket2_charge) then
            call charge_scrap(sol, gas, mesh, cfg, 2)
            if (should_print(mesh)) then
                print '(A,F10.1)', ' [MAIN] Second bucket charged at t=', time
            end if
        end if

        ! Cargador continuo ECS (E1): fuente de masa por banda
        if (cfg%solve_ecs .and. time >= cfg%ecs_t_start .and. &
            time <= cfg%ecs_t_stop) then
            mdot_ecs = interpolate_rate(ecs_prof, time)
            call ecs_feed(sol, gas, mesh, cfg, mdot_ecs, cfg%dt)
            call solid_exchange_halos(sol, mesh)
            if (mesh%is_parallel) &
                call mpi_exchange_halos_3d(gas%alpha, mesh%topo)
        end if

        ! Update electrode V/I from profile
        call interpolate_profile(elec_prof, time, V_elec, I_elec)

        ! Update arc model
        call timer_start(T_ARC)
        if (cfg%solve_arc) then
            do e = 1, N_ELECTRODES
                call update_arc_resistance(elec(e), V_elec, I_elec, cfg, cfg%dt)
            end do
            call update_electrodes(elec, sol, mesh, cfg, cfg%dt)
            ! C4.2: un solo gather global de alpha_s por paso, compartido por
            ! el depósito directo y el MC (antes cada uno hacía el suyo)
            if (.not. allocated(alpha_sg)) &
                allocate(alpha_sg(mesh%nr_g, mesh%nth_g, mesh%nz_g))
            call gather_global_field(sol%alpha_s, alpha_sg, mesh)
            call distribute_arc_heat(elec, sh, sol, mesh, cfg, alpha_sg, N_ELECTRODES)
            call distribute_arc_radiation_mc(elec, sh, mesh, cfg, alpha_sg, &
                                             N_ELECTRODES, step)
            ! (mod_arc_impingement retirado en C4.4: unidades N/m4 en vez
            ! de N/m3 y magnitud ~0.2 N/m3 despreciable; la depresión del
            ! baño por el jet requiere búsqueda global de superficie —
            ! reintroducir con ese diseño si se necesita. S_arc_mom queda
            ! en 0 y el término de momentum inerte.)
            call compute_lorentz_force(elec, liq%alpha, sh, mesh, cfg, I_elec, N_ELECTRODES)
            ! La escoria intercepta su fracción de S_arc AHORA (antes de que
            ! las ecuaciones de energía lo consuman; C1.6b)
            if (cfg%solve_slag) then
                call slag_intercept_arc(slag, sh, mesh, cfg)
            end if
        end if
        call timer_stop(T_ARC)

        ! Radiation (DO model)
        call timer_start(T_RAD)
        if (cfg%solve_radiation) then
            call solve_radiation_do(liq, gas, sol, sh, mesh, cfg)
        end if
        call timer_stop(T_RAD)

        ! Chemistry
        call timer_start(T_CHEM)
        if (cfg%solve_chemistry) then
            call compute_carbon_oxidation(sol, gas, sh, mesh, cfg)
        end if

        ! Species transport (CO / CO2)
        if (cfg%solve_species) then
            Y_CO_old  = sh%Y_CO
            Y_CO2_old = sh%Y_CO2
            Y_O2_old  = sh%Y_O2
            call solve_species_3d(gas, sh%Y_CO,  Y_CO_old,  sh%S_CO_src,  mesh, cfg, res_Y_CO)
            call solve_species_3d(gas, sh%Y_CO2, Y_CO2_old, sh%S_CO2_src, mesh, cfg, res_Y_CO2)
            call solve_species_3d(gas, sh%Y_O2,  Y_O2_old,  sh%S_O2_src,  mesh, cfg, res_Y_O2)
            if (mesh%is_parallel) then
                call mpi_exchange_halos_3d(sh%Y_CO,  mesh%topo)
                call mpi_exchange_halos_3d(sh%Y_CO2, mesh%topo)
                call mpi_exchange_halos_3d(sh%Y_O2,  mesh%topo)
            end if
        end if
        call timer_stop(T_CHEM)

        !---------------------------------------------------------------
        ! OUTER ITERATION LOOP (SIMPLE)
        !---------------------------------------------------------------
        
        ! Fusión + colapso ANTES del SIMPLE; la transferencia interfase va
        ! DESPUÉS de los solves de energía (ver notas en mod_solid_phase)
        call timer_start(T_SOLID)
        if (cfg%solve_melting) then
            call update_solid_premelt(sol, liq, gas, slag, mesh, cfg, cfg%dt)
        end if
        call timer_stop(T_SOLID)

        ! Initialize residuals to zero
        conv%res_ur = 0.0_dp
        conv%res_uth = 0.0_dp
        conv%res_uz = 0.0_dp
        conv%res_cont = 0.0_dp
        conv%res_energy = 0.0_dp
        conv%res_tke = 0.0_dp
        conv%res_eps = 0.0_dp
        conv%converged = .false.
        
        call timer_start(T_SIMPLE)
        do outer = 1, cfg%max_outer

            ! Ergun drag coefficient from solid
            if (cfg%solve_flow) then
                call compute_ergun_drag(liq, sol, mesh, cfg, drag_coef)
            end if

            ! Multiphase SIMPLE iteration
            if (cfg%solve_flow .and. cfg%solve_multiphase) then
                call multiphase_iteration(liq, gas, liq_old, gas_old, sol, slag, &
                                          sh, mesh, cfg, drag_coef, conv)
            else if (cfg%solve_flow) then
                prev_ur = liq%ur; prev_uth = liq%uth
                prev_uz = liq%uz; prev_T = liq%T
                call solve_momentum_3d(liq, liq_old, gas, K_zero, sh, mesh, &
                                       cfg, liq%alpha, drag_coef, .false., &
                                       conv%res_ur, conv%res_uth, conv%res_uz)
                call relax_field(liq%ur,  prev_ur,  cfg%alpha_u, mesh)
                call relax_field(liq%uth, prev_uth, cfg%alpha_u, mesh)
                call relax_field(liq%uz,  prev_uz,  cfg%alpha_u, mesh)
                ! Refresh halos (incl. aP_*) before Rhie-Chow in the pressure solve
                call phase_exchange_halos(liq, mesh)
                call solve_pressure_correction(liq, gas, gas%T, sh, mesh, cfg, conv%res_cont)
                if (cfg%solve_energy) then
                    call solve_energy_3d(liq, liq_old%T, sh, mesh, cfg, liq%alpha, &
                                         gas%alpha, sol%mdot, sol%T_s, &
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
                                     K_zero, sol%mdot, sol%T_s, &
                                     .false., conv%res_energy)
                call relax_field(liq%T, prev_T, cfg%alpha_T, mesh)
                ! Propiedades tambien sin flujo: rho_gas(T) debe seguir a T
                ! (antes quedaba congelada en el valor inicial en esta rama)
                call update_properties(liq, gas, sh, mesh, cfg)
                conv%res_cont = 0.0_dp
            else
                ! No physics enabled - mark as converged immediately
                conv%converged = .true.
                exit
            end if

            ! Turbulence
            if (cfg%solve_turb) then
                call solve_k_epsilon(liq, sh, mesh, cfg, cfg%dt)
            end if

            ! Convergence check
            conv%n_outer = outer
            conv%converged = check_convergence(conv, cfg)
            
            ! (C3.2: ya NO se fuerza converged en max_outer — el lazo está
            ! acotado por el do; la convergencia REAL gobierna el dt)
            if (conv%converged) exit
        end do
        call timer_stop(T_SIMPLE)

        ! Transferencia interfase (tras los solves de energía)
        call timer_start(T_SOLID)
        if (cfg%solve_melting) then
            call update_solid_postenergy(sol, liq, gas, mesh, cfg)
        end if
        call timer_stop(T_SOLID)

        ! Slag layer update (adiciones + buoyancy + energy exchange)
        call timer_start(T_SLAG)
        if (cfg%solve_slag) then
            call slag_additions(slag, mesh, cfg, &
                interpolate_rate(cal_prof, time), &
                interpolate_rate(cinj_prof, time), cfg%dt)
            call update_slag(slag, liq, gas, sh, mesh, cfg, cfg%dt)
            call slag_exchange_halos(slag, mesh)
        end if
        call timer_stop(T_SLAG)

        ! Auditoría de balances (antes de adaptar dt: usa el dt del paso).
        ! Las integrales de fuente se acumulan CADA paso; la línea CSV se
        ! escribe cada audit_freq pasos y cubre todo el intervalo.
        call timer_start(T_IO)
        if (cfg%audit_freq > 0) then
            call audit_accumulate(liq, gas, gas_old%T, sh, mesh, cfg)
            if (mod(step, cfg%audit_freq) == 0) then
                call audit_write_step(liq, gas, sol, slag, sh, elec, mesh, &
                                      cfg, step, time)
            end if
        end if
        call timer_stop(T_IO)

        ! Adaptive time stepping (criterio CFL + convergencia real; C3.2)
        call adapt_timestep(cfg%dt, conv, &
                            compute_cfl_rate(liq, gas, mesh), cfg)

        !---------------------------------------------------------------
        ! OUTPUT (HDF5 parallel)
        !---------------------------------------------------------------
        if (mod(step, cfg%monitor_freq) == 0) then
            if (should_print(mesh)) then
                ! TODO: Implement print_monitor_3d or use monitor.log
                print '(A,I8,A,F10.2,A,I3,A,5ES12.4)', &
                    ' [STEP] ', step, '  t=', time, '  outer=', conv%n_outer, &
                    '  res: ', conv%res_ur, conv%res_cont, conv%res_energy
            end if
        end if

        if (mod(step, cfg%output_freq) == 0) then
            call timer_start(T_IO)
            call write_hdf5_parallel(mesh, liq, gas, sol, slag, sh, step, time, cfg%output_dir)
            call timer_stop(T_IO)
        end if
        
        if (should_print(mesh)) then
            !print '(A,I0,A,F8.2)', ' [DEBUG] Completed step ', step, ' t=', time
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

    call write_hdf5_parallel(mesh, liq, gas, sol, slag, sh, step, time, cfg%output_dir)

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
