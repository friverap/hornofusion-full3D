!===============================================================================
! mod_config_3d.f90 - Configuration reader for 3D EAF simulator
!===============================================================================
module mod_config_3d
    use mod_constants
    use mod_types_3d
    implicit none

contains

    subroutine config_set_defaults(cfg)
        type(config_t), intent(out) :: cfg

        ! EAF Geometry (typical 130-ton AC EAF)
        cfg%R_shell  = 3.80_dp
        cfg%H_total  = 4.50_dp
        cfg%H_bowl   = 0.60_dp
        cfg%R_bowl   = 2.50_dp
        cfg%R_pcd    = 0.85_dp
        cfg%R_elec   = 0.30_dp

        ! Mesh (~604,800 cells)
        cfg%nr      = 60
        cfg%ntheta  = 120
        cfg%nz      = 84
        cfg%stretch_r = 1.5_dp
        cfg%stretch_z = 1.5_dp

        ! Time
        cfg%dt      = 0.1_dp
        cfg%dt_min  = 1.0e-3_dp
        cfg%dt_max  = 1.0_dp
        cfg%t_final = 5040.0_dp
        cfg%adaptive_dt = .true.
        cfg%cfl_max = 2.0_dp

        ! SIMPLE
        cfg%max_outer     = 20
        cfg%max_inner_mom  = 5
        cfg%max_inner_pres = 50
        cfg%alpha_u    = 0.3_dp
        cfg%alpha_p    = 0.7_dp
        cfg%alpha_T    = 0.7_dp
        cfg%alpha_k    = 0.5_dp
        cfg%alpha_eps  = 0.5_dp

        ! Convergence
        cfg%tol_cont   = 1.0e-4_dp
        cfg%tol_mom    = 1.0e-4_dp
        ! Residual de energia normalizado con |aP T| (T ABSOLUTA, como Fluent):
        ! 1e-3 dejaba 0.7 K sin aplicar sobre 1550 K y el lazo se cortaba con
        ! 2.8 % de las fuentes del paso fuera (auditoria 2, N-C5). Fluent usa
        ! 1e-6 para la energia por la misma razon.
        cfg%tol_energy = 1.0e-6_dp
        cfg%tol_turb   = 1.0e-4_dp

        ! Material - steel (Table 2)
        cfg%rho_steel   = RHO_STEEL
        cfg%T_solidus   = T_SOLIDUS
        cfg%T_liquidus  = T_LIQUIDUS
        cfg%T_liq_hbi   = T_LIQ_HBI
        cfg%cp_s        = CP_SOLID
        cfg%cp_l        = CP_LIQUID
        cfg%h_fusion    = H_FUSION
        cfg%k_s         = K_SOLID
        cfg%k_l         = K_LIQUID
        cfg%mu_l        = MU_LIQUID
        cfg%emissivity  = EMISSIVITY
        cfg%beta_expansion = BETA_EXPANSION
        cfg%T_ref_boussinesq = cfg%T_liquidus   ! (un valor < 0 en el config tambien significa T_liquidus)

        ! Material - gas
        cfg%rho_gas = RHO_GAS_REF
        cfg%cp_gas  = CP_GAS
        cfg%k_gas   = K_GAS
        cfg%mu_gas  = MU_GAS

        ! Ergun
        cfg%d_particle = D_PARTICLE
        ! Gotas de acero salpicadas por el arco: 2 mm nominal (u_t ~ 35 m/s
        ! en gas a 1800 K; insensible entre 1 y 5 mm porque u_t >> caida
        ! libre de 3 m). B1 v11: 3.6 t de niebla a alpha=0.01 suspendida
        ! porque bajo el umbral la velocidad era 0 y la gravedad no actuaba.
        cfg%d_droplet  = 2.0e-3_dp
        cfg%charge_recipe_file = 'input/charge_recipe.dat'
        cfg%electrode_profile_file = 'input/electrode_profile.dat'
        cfg%elec_V_const = 500.0_dp
        cfg%elec_I_const = 50000.0_dp
        cfg%pc_limiter_faces = .false.   ! D2.2/D2.2c: perjudicial en el banco (ver dev-history Plan D)
        cfg%pc_liq_sealed_wall = .false.   ! Plan D (cerrado negativo 10-oct-2026): solo el banco bed_flood
        cfg%pc_lim_dead = 0.5_dp
        cfg%alpha_g_comp_min = 0.0_dp
        cfg%pc_fs_liquid_gradient = .false.   ! Plan D (cerrado negativo 10-oct-2026): solo el banco bed_flood
        cfg%pc_fs_liquid_face = .false.   ! Plan D (cerrado negativo 10-oct-2026): solo el banco bed_flood
        cfg%pc_consistent_corrector = .false.   ! Plan D (cerrado negativo 10-oct-2026): solo el banco bed_flood
        cfg%liq_balanced_force = .true.         ! fuerza del liquido balanceada por caras (oct-2026)
        cfg%pc_liq_closed_dir = .false.   ! Plan D (cerrado negativo 10-oct-2026): solo el banco bed_flood
        cfg%pc_sat_open = .false.         ! Plan E E1 (10-oct-2026): juez B1 negativo, solo banco
        cfg%pc_sat_gas_off = .false.      ! Plan E E1b (10-oct-2026): juez B1 negativo, nadie la activa
        cfg%pc_gas_spring = .false.       ! Plan F (12-oct-2026): juez B1 NEGATIVO, nadie la activa
        cfg%pc_keep_pore_floor = .false.  ! Plan F (diagnostico del banco)
        cfg%mixture_model = .false.       ! Plan G (oct-2026): en evaluacion
        cfg%tol_alpha_mix = 1.0e-4_dp
        cfg%mix_eps_perm_min = 0.0_dp
        cfg%pc_drift_source = .false.     ! Plan E E2 (10-oct-2026): sin efecto medible en el banco con E1 (e12ns); off
        cfg%pc_spill_source = .false.
        cfg%n_pc_max = 1
        cfg%tol_alpha_pc = 1.0e-6_dp
        ! dt adaptativo <= safety * tau_interfase (0 = desactivado): evita
        ! operar en el régimen de clamp/equilibrio local (S5-dpart, B1)
        cfg%iph_dt_safety = 0.5_dp
        ! sonda de diagnostico (mod_probe): desactivada por defecto
        cfg%probe_step_from = 0
        cfg%probe_step_to   = 0
        cfg%probe_cell_i = 0
        cfg%probe_cell_j = 0
        cfg%probe_cell_k = 0

        ! Arc
        cfg%arc_tau       = ARC_TAU
        cfg%arc_w         = ARC_W
        cfg%arc_sigma_cond = ARC_SIGMA
        cfg%arc_T_ref     = ARC_T_REF
        cfg%frac_rad      = 0.50_dp
        cfg%frac_conv     = 0.30_dp
        cfg%frac_elec     = 0.20_dp
        cfg%n_beams       = 1000

        ! BCs
        cfg%T_ambient = 300.0_dp
        cfg%T_initial = 300.0_dp
        cfg%T_wall    = 300.0_dp
        cfg%h_wall    = 0.0_dp

        ! Physics
        cfg%solve_flow       = .true.
        cfg%solve_energy     = .true.
        cfg%solve_melting    = .true.
        cfg%solve_turb       = .true.
        cfg%solve_radiation  = .true.
        cfg%solve_chemistry  = .false.
        cfg%solve_arc        = .true.
        cfg%solve_multiphase = .true.

        ! Output
        cfg%output_freq  = 100
        cfg%monitor_freq = 10
        cfg%audit_freq   = 1
        cfg%wall_time_max = 0.0_dp
        cfg%output_dir   = 'output'
        cfg%restart_file = ''

        ! Slag
        cfg%rho_slag     = 2800.0_dp
        cfg%cp_slag      = 1200.0_dp
        cfg%k_slag       = 1.5_dp
        cfg%h_contact_sl = 1000.0_dp
        cfg%m_slag_init  = 3300.0_dp
        cfg%solve_slag   = .false.
        cfg%slag_in_volume = .false.

        ! Species transport (CO/CO2)
        cfg%solve_species   = .false.
        cfg%carbon_frac     = 0.005_dp
        ! ECS (E1): apagado por defecto (golden intacto)
        cfg%solve_ecs        = .false.
        cfg%charge_bucket1   = .true.
        cfg%do_quadrature    = 4
        cfg%gas_in_poisson      = .true.
        cfg%gas_compressibility = .true.
        ! composición típica de escoria EAF (ventana de Pretorius; la
        ! Radiografía FCEL02 reporta FeO mediana 26.8% en 2022)
        cfg%slag_x_feo_init  = 0.25_dp
        cfg%slag_x_cao_init  = 0.35_dp
        cfg%slag_x_sio2_init = 0.16_dp
        cfg%slag_x_mgo_init  = 0.08_dp
        cfg%cal_rate         = 0.0_dp
        cfg%cal_profile_file = ''
        cfg%cal_frac_cao     = 0.75_dp   ! cal sidérgica/dolomítica típica
        cfg%cal_frac_mgo     = 0.20_dp
        cfg%carbon_inj_rate  = 0.0_dp
        cfg%slag_eta_feo     = 0.3_dp
        cfg%heel_mass        = 0.0_dp
        cfg%heel_T           = 1850.0_dp
        cfg%carbon_inj_profile_file = ''
        cfg%ecs_rate         = 0.0_dp
        cfg%ecs_profile_file = ''
        cfg%ecs_theta_center = PI
        cfg%ecs_theta_width  = PI / 6.0_dp
        cfg%ecs_r_inner      = 2.8_dp
        cfg%ecs_vfrac        = 0.5_dp
        cfg%ecs_T_charge     = 300.0_dp
        cfg%ecs_carbon_frac  = 0.005_dp
        cfg%ecs_t_start      = 0.0_dp
        cfg%ecs_t_stop       = 1.0e30_dp
        cfg%ecs_mode         = 'table'
        cfg%ecs_k_power      = 0.0_dp
        cfg%ecs_total_mass   = 0.0_dp
        cfg%Sc_t_species    = 0.7_dp
        cfg%alpha_Y_species = 1.0_dp   ! OBSOLETA (auditoria A2): sin efecto

        ! Charge recipe (initialized empty)
        cfg%n_layers_b1    = 0
        cfg%n_layers_b2    = 0
        cfg%n_layers_total = 0
        cfg%layer_vfrac    = 0.0_dp
        cfg%layer_mass     = 0.0_dp
        cfg%layer_bucket   = 0
        cfg%t_bucket2_charge = 2100.0_dp
    end subroutine config_set_defaults

    subroutine config_read(cfg, filename)
        type(config_t), intent(inout) :: cfg
        character(len=*), intent(in)  :: filename

        integer :: iu, ios
        character(len=512) :: line, key, val
        integer :: eq_pos, cpos

        open(newunit=iu, file=trim(filename), status='old', iostat=ios)
        if (ios /= 0) then
            if (cfg_root()) print '(A,A)', ' [CONFIG] ERROR: cannot open config file: ', trim(filename)
            stop 1
        end if
        if (cfg_root()) print '(A,A)', ' [CONFIG] Reading: ', trim(filename)

        do
            read(iu, '(A)', iostat=ios) line
            if (ios /= 0) exit
            line = adjustl(line)
            if (len_trim(line) == 0) cycle
            if (line(1:1) == '#' .or. line(1:1) == '!') cycle

            eq_pos = index(line, '=')
            if (eq_pos < 2) cycle
            key = adjustl(line(1:eq_pos-1))
            val = adjustl(line(eq_pos+1:))
            ! Comentario al final de linea ('valor  # nota'): precedido de
            ! blanco o tabulador. Antes llegaba entero al parser y un booleano
            ! 'true  # nota' se leia como FALSO en silencio.
            cpos = scan_inline_comment(val)
            if (cpos > 0) val = val(1:cpos-1)

            call config_set_value(cfg, trim(key), trim(val))
        end do
        close(iu)
        ! Plan F: la capacidad del liquido (liq_cap, mod_constants) es el hueco
        ! FISICO cuando el gas es siempre fluido del acople (sin piso F2.7)
        ! Plan G: en el modelo de mezcla la capacidad del liquido es el hueco
        ! fisico; el piso de gas de poro (F2.7) existia para que la fila del
        ! liquido del modelo de dos fluidos nunca quedara sellada
        pore_floor_on = .not. (cfg%pc_gas_spring .or. cfg%mixture_model) .or. cfg%pc_keep_pore_floor
        ! Boussinesq del liquido referido a la T de su densidad rho_steel (la del
        ! liquido recien fundido), no a T_ambient = 300 K: con 300 K el peso del
        ! bano a 1850 K quedaba x0.81 mientras la inercia usaba 7500 (auditoria
        ! 12-oct-2026, A7)
        if (cfg%T_ref_boussinesq < 0.0_dp) cfg%T_ref_boussinesq = cfg%T_liquidus
    end subroutine config_read

    ! Posicion del primer '#' o '!' precedido de blanco/tabulador (0 si no hay)
    pure integer function scan_inline_comment(val) result(pos)
        character(len=*), intent(in) :: val
        integer :: i
        pos = 0
        do i = 2, len_trim(val)
            if ((val(i:i) == '#' .or. val(i:i) == '!') .and. &
                (val(i-1:i-1) == ' ' .or. val(i-1:i-1) == achar(9))) then
                pos = i
                return
            end if
        end do
    end function scan_inline_comment

    subroutine config_set_value(cfg, key, val)
        type(config_t), intent(inout) :: cfg
        character(len=*), intent(in)  :: key, val

        select case (trim(key))
        ! Geometry
        case ('R_shell');    call parse_real(val, key, cfg%R_shell)
        case ('H_total');    call parse_real(val, key, cfg%H_total)
        case ('H_bowl');     call parse_real(val, key, cfg%H_bowl)
        case ('R_bowl');     call parse_real(val, key, cfg%R_bowl)
        case ('R_pcd');      call parse_real(val, key, cfg%R_pcd)
        case ('R_elec');     call parse_real(val, key, cfg%R_elec)
        ! Mesh
        case ('nr');         call parse_int(val, key, cfg%nr)
        case ('ntheta');     call parse_int(val, key, cfg%ntheta)
        case ('nz');         call parse_int(val, key, cfg%nz)
        case ('stretch_r');  call parse_real(val, key, cfg%stretch_r)
        case ('stretch_z');  call parse_real(val, key, cfg%stretch_z)
        ! Time
        case ('dt');         call parse_real(val, key, cfg%dt)
        case ('dt_min');     call parse_real(val, key, cfg%dt_min)
        case ('dt_max');     call parse_real(val, key, cfg%dt_max)
        case ('t_final');    call parse_real(val, key, cfg%t_final)
        case ('adaptive_dt'); cfg%adaptive_dt = parse_bool(val)
        case ('cfl_max');    call parse_real(val, key, cfg%cfl_max)
        ! SIMPLE
        case ('max_outer');       call parse_int(val, key, cfg%max_outer)
        case ('max_inner_mom');   call parse_int(val, key, cfg%max_inner_mom)
        case ('max_inner_pres');  call parse_int(val, key, cfg%max_inner_pres)
        case ('alpha_u');    call parse_real(val, key, cfg%alpha_u)
        case ('alpha_p');    call parse_real(val, key, cfg%alpha_p)
        case ('alpha_T');    call parse_real(val, key, cfg%alpha_T)
        case ('alpha_k');    call parse_real(val, key, cfg%alpha_k)
        case ('alpha_eps');  call parse_real(val, key, cfg%alpha_eps)
        ! Convergence
        case ('tol_cont');   call parse_real(val, key, cfg%tol_cont)
        case ('tol_mom');    call parse_real(val, key, cfg%tol_mom)
        case ('tol_energy'); call parse_real(val, key, cfg%tol_energy)
        case ('tol_turb');   call parse_real(val, key, cfg%tol_turb)
        ! Material
        case ('rho_steel');  call parse_real(val, key, cfg%rho_steel)
        case ('T_solidus');  call parse_real(val, key, cfg%T_solidus)
        case ('T_liquidus'); call parse_real(val, key, cfg%T_liquidus)
        case ('T_ref_boussinesq'); call parse_real(val, key, cfg%T_ref_boussinesq)
        case ('cp_s');       call parse_real(val, key, cfg%cp_s)
        case ('cp_l');       call parse_real(val, key, cfg%cp_l)
        case ('h_fusion');   call parse_real(val, key, cfg%h_fusion)
        case ('k_s');        call parse_real(val, key, cfg%k_s); call warn_noeffect(key)
        case ('k_l');        call parse_real(val, key, cfg%k_l)
        case ('d_particle'); call parse_real(val, key, cfg%d_particle)
        case ('d_droplet');  call parse_real(val, key, cfg%d_droplet)
        case ('charge_recipe_file'); cfg%charge_recipe_file = val
        case ('electrode_profile_file'); cfg%electrode_profile_file = trim(val)
        case ('elec_V_const'); call parse_real(val, key, cfg%elec_V_const)
        case ('elec_I_const'); call parse_real(val, key, cfg%elec_I_const)
        case ('pc_limiter_faces'); cfg%pc_limiter_faces = parse_bool(val)
        case ('pc_liq_sealed_wall'); cfg%pc_liq_sealed_wall = parse_bool(val)
        case ('pc_lim_dead'); call parse_real(val, key, cfg%pc_lim_dead)
        case ('alpha_g_comp_min'); call parse_real(val, key, cfg%alpha_g_comp_min)
        case ('pc_fs_liquid_gradient'); cfg%pc_fs_liquid_gradient = parse_bool(val)
        case ('pc_fs_liquid_face'); cfg%pc_fs_liquid_face = parse_bool(val)
        case ('pc_consistent_corrector'); cfg%pc_consistent_corrector = parse_bool(val)
        case ('liq_balanced_force'); cfg%liq_balanced_force = parse_bool(val)
        case ('pc_liq_closed_dir'); cfg%pc_liq_closed_dir = parse_bool(val)
        case ('pc_sat_open'); cfg%pc_sat_open = parse_bool(val)
        case ('pc_sat_gas_off'); cfg%pc_sat_gas_off = parse_bool(val)
        case ('pc_gas_spring'); cfg%pc_gas_spring = parse_bool(val)
        case ('pc_keep_pore_floor'); cfg%pc_keep_pore_floor = parse_bool(val)
        case ('mixture_model'); cfg%mixture_model = parse_bool(val)
        case ('tol_alpha_mix'); call parse_real(val, key, cfg%tol_alpha_mix)
        case ('mix_eps_perm_min'); call parse_real(val, key, cfg%mix_eps_perm_min)
        case ('pc_drift_source'); cfg%pc_drift_source = parse_bool(val)
        case ('pc_spill_source'); cfg%pc_spill_source = parse_bool(val)
        case ('n_pc_max'); call parse_int(val, key, cfg%n_pc_max)
        case ('tol_alpha_pc'); call parse_real(val, key, cfg%tol_alpha_pc)
        case ('iph_dt_safety'); call parse_real(val, key, cfg%iph_dt_safety)
        case ('probe_step_from'); call parse_int(val, key, cfg%probe_step_from)
        case ('probe_step_to');   call parse_int(val, key, cfg%probe_step_to)
        case ('probe_cell_i');    call parse_int(val, key, cfg%probe_cell_i)
        case ('probe_cell_j');    call parse_int(val, key, cfg%probe_cell_j)
        case ('probe_cell_k');    call parse_int(val, key, cfg%probe_cell_k)
        case ('emissivity'); call parse_real(val, key, cfg%emissivity); call warn_noeffect(key)
        case ('T_initial');  call parse_real(val, key, cfg%T_initial)
        case ('T_ambient');  call parse_real(val, key, cfg%T_ambient)
        case ('T_wall');     call parse_real(val, key, cfg%T_wall)
        case ('h_wall');     call parse_real(val, key, cfg%h_wall)
        ! Physics flags
        case ('solve_flow');       cfg%solve_flow = parse_bool(val)
        case ('solve_energy');     cfg%solve_energy = parse_bool(val)
        case ('solve_melting');    cfg%solve_melting = parse_bool(val)
        case ('solve_turb');       cfg%solve_turb = parse_bool(val)
        case ('solve_arc');        cfg%solve_arc = parse_bool(val)
        case ('solve_radiation');  cfg%solve_radiation = parse_bool(val)
        case ('solve_chemistry');  cfg%solve_chemistry = parse_bool(val)
        case ('solve_multiphase'); cfg%solve_multiphase = parse_bool(val)
        ! Output
        case ('output_freq');  call parse_int(val, key, cfg%output_freq)
        case ('monitor_freq'); call parse_int(val, key, cfg%monitor_freq)
        case ('audit_freq');   call parse_int(val, key, cfg%audit_freq)
        case ('wall_time_max'); call parse_real(val, key, cfg%wall_time_max)
        case ('output_dir');   cfg%output_dir = trim(val)
        case ('restart_file'); cfg%restart_file = trim(val)
        ! Bucket timing
        case ('t_bucket2_charge'); call parse_real(val, key, cfg%t_bucket2_charge)
        ! Arc heat partition fractions
        case ('frac_conv');  call parse_real(val, key, cfg%frac_conv)
        case ('frac_rad');   call parse_real(val, key, cfg%frac_rad)
        case ('frac_elec');  call parse_real(val, key, cfg%frac_elec)
        case ('arc_w');      call parse_real(val, key, cfg%arc_w); call warn_noeffect(key)
        case ('n_beams');    call parse_int(val, key, cfg%n_beams)
        ! Slag
        case ('rho_slag');     call parse_real(val, key, cfg%rho_slag)
        case ('cp_slag');      call parse_real(val, key, cfg%cp_slag)
        case ('k_slag');       call parse_real(val, key, cfg%k_slag); call warn_noeffect(key)
        case ('h_contact_sl'); call parse_real(val, key, cfg%h_contact_sl)
        case ('m_slag_init');  call parse_real(val, key, cfg%m_slag_init)
        case ('solve_slag');   cfg%solve_slag = parse_bool(val)
        case ('slag_in_volume'); cfg%slag_in_volume = parse_bool(val)
        ! Species transport
        case ('solve_species');   cfg%solve_species = parse_bool(val)
        case ('carbon_frac');     call parse_real(val, key, cfg%carbon_frac)
        case ('solve_ecs');        cfg%solve_ecs = parse_bool(val)
        case ('charge_bucket1');   cfg%charge_bucket1 = parse_bool(val)
        case ('do_quadrature');    call parse_int(val, key, cfg%do_quadrature)
        case ('gas_in_poisson');      cfg%gas_in_poisson = parse_bool(val)
        case ('gas_compressibility'); cfg%gas_compressibility = parse_bool(val)
        case ('slag_x_feo_init');  call parse_real(val, key, cfg%slag_x_feo_init)
        case ('slag_x_cao_init');  call parse_real(val, key, cfg%slag_x_cao_init)
        case ('slag_x_sio2_init'); call parse_real(val, key, cfg%slag_x_sio2_init)
        case ('slag_x_mgo_init');  call parse_real(val, key, cfg%slag_x_mgo_init)
        case ('cal_rate');         call parse_real(val, key, cfg%cal_rate)
        case ('cal_profile_file'); cfg%cal_profile_file = trim(val)
        case ('cal_frac_cao');     call parse_real(val, key, cfg%cal_frac_cao)
        case ('cal_frac_mgo');     call parse_real(val, key, cfg%cal_frac_mgo)
        case ('carbon_inj_rate');  call parse_real(val, key, cfg%carbon_inj_rate)
        case ('slag_eta_feo');     call parse_real(val, key, cfg%slag_eta_feo)
        case ('heel_mass');        call parse_real(val, key, cfg%heel_mass)
        case ('heel_T');           call parse_real(val, key, cfg%heel_T)
        case ('carbon_inj_profile_file'); cfg%carbon_inj_profile_file = trim(val)
        case ('ecs_rate');         call parse_real(val, key, cfg%ecs_rate)
        case ('ecs_profile_file'); cfg%ecs_profile_file = trim(val)
        case ('ecs_theta_center'); call parse_real(val, key, cfg%ecs_theta_center)
        case ('ecs_theta_width');  call parse_real(val, key, cfg%ecs_theta_width)
        case ('ecs_r_inner');      call parse_real(val, key, cfg%ecs_r_inner)
        case ('ecs_vfrac');        call parse_real(val, key, cfg%ecs_vfrac)
        case ('ecs_T_charge');     call parse_real(val, key, cfg%ecs_T_charge)
        case ('ecs_carbon_frac');  call parse_real(val, key, cfg%ecs_carbon_frac)
        case ('ecs_t_start');      call parse_real(val, key, cfg%ecs_t_start)
        case ('ecs_t_stop');       call parse_real(val, key, cfg%ecs_t_stop)
        case ('ecs_mode');         cfg%ecs_mode = trim(val); call warn_noeffect(key)
        case ('ecs_k_power');      call parse_real(val, key, cfg%ecs_k_power); call warn_noeffect(key)
        case ('ecs_total_mass');   call parse_real(val, key, cfg%ecs_total_mass); call warn_noeffect(key)
        case ('Sc_t_species');    call parse_real(val, key, cfg%Sc_t_species)
        case ('alpha_Y_species'); call parse_real(val, key, cfg%alpha_Y_species)
        case default
            if (cfg_root()) print '(A,A,A)', ' [CONFIG] WARNING: unknown key "', trim(key), &
                  '" ignored (check for typos)'
        end select
    end subroutine config_set_value

    !---------------------------------------------------------------------------
    ! Parsing helpers: report malformed values instead of crashing mid-read
    !---------------------------------------------------------------------------
    subroutine parse_real(val, key, x)
        character(len=*), intent(in) :: val, key
        real(dp), intent(inout) :: x

        integer :: ios
        real(dp) :: tmp

        read(val, *, iostat=ios) tmp
        if (ios /= 0) then
            if (cfg_root()) print '(5A)', ' [CONFIG] ERROR: invalid value "', trim(val), &
                  '" for key "', trim(key), '"'
            stop 1
        end if
        x = tmp
    end subroutine parse_real

    subroutine parse_int(val, key, n)
        character(len=*), intent(in) :: val, key
        integer, intent(inout) :: n

        integer :: ios, tmp

        read(val, *, iostat=ios) tmp
        if (ios /= 0) then
            if (cfg_root()) print '(5A)', ' [CONFIG] ERROR: invalid value "', trim(val), &
                  '" for key "', trim(key), '"'
            stop 1
        end if
        n = tmp
    end subroutine parse_int

    ! Booleano SIN distinguir mayusculas (oct-2026): antes solo 'true' y
    ! '.true.' eran verdaderos y CUALQUIER otro texto era falso en silencio;
    ! los configs de campana escritos desde Python ('True') corrieron B1 con
    ! adaptive_dt y solve_species APAGADOS. Un valor no reconocido es error.
    function parse_bool(val) result(b)
        character(len=*), intent(in) :: val
        logical :: b

        character(len=len(val)) :: v
        integer :: i, c

        v = adjustl(val)
        do i = 1, len_trim(v)
            c = iachar(v(i:i))
            if (c >= iachar('A') .and. c <= iachar('Z')) v(i:i) = achar(c + 32)
        end do
        select case (trim(v))
        case ('true', '.true.', 't', '.t.', 'yes', 'on', '1')
            b = .true.
        case ('false', '.false.', 'f', '.f.', 'no', 'off', '0')
            b = .false.
        case default
            if (cfg_root()) print '(3A)', ' [CONFIG] ERROR: invalid boolean value "', trim(val), '"'
            stop 1
        end select
    end function parse_bool

    !---------------------------------------------------------------------------
    ! Validate configuration ranges. Called before MPI init, so a plain stop
    ! terminates every launched process with a clear message.
    !---------------------------------------------------------------------------
    subroutine config_validate(cfg)
        type(config_t), intent(in) :: cfg

        logical :: ok

        ok = .true.

        call require(cfg%nr >= 1 .and. cfg%ntheta >= 1 .and. cfg%nz >= 1, &
                     'mesh dimensions nr/ntheta/nz must be >= 1', ok)
        call require(cfg%dt > 0.0_dp, 'dt must be > 0', ok)
        call require(cfg%dt_min > 0.0_dp .and. cfg%dt_min <= cfg%dt_max, &
                     'requires 0 < dt_min <= dt_max', ok)
        call require(cfg%t_final > 0.0_dp, 't_final must be > 0', ok)
        call require(cfg%T_solidus < cfg%T_liquidus, &
                     'T_solidus must be < T_liquidus', ok)
        call require(cfg%alpha_u > 0.0_dp .and. cfg%alpha_u <= 1.0_dp, &
                     'alpha_u must be in (0, 1]', ok)
        call require(cfg%n_pc_max >= 1 .and. cfg%tol_alpha_pc > 0.0_dp, &
                     'n_pc_max must be >= 1 and tol_alpha_pc > 0', ok)
        call require(cfg%alpha_p > 0.0_dp .and. cfg%alpha_p <= 1.0_dp, &
                     'alpha_p must be in (0, 1]', ok)
        call require(cfg%alpha_T > 0.0_dp .and. cfg%alpha_T <= 1.0_dp, &
                     'alpha_T must be in (0, 1]', ok)
        call require(cfg%max_outer >= 1 .and. cfg%max_inner_mom >= 1 &
                     .and. cfg%max_inner_pres >= 1, &
                     'iteration limits must be >= 1', ok)
        call require(cfg%tol_cont > 0.0_dp .and. cfg%tol_mom > 0.0_dp &
                     .and. cfg%tol_energy > 0.0_dp, &
                     'convergence tolerances must be > 0', ok)
        call require(abs(cfg%frac_rad + cfg%frac_conv + cfg%frac_elec - 1.0_dp) &
                     < 1.0e-6_dp, &
                     'frac_rad + frac_conv + frac_elec must equal 1.0', ok)
        ! (auditoria 4, B4-15) una fraccion negativa compensada por otra > 1
        ! pasaba la suma: es una fuente de energia negativa
        call require(cfg%frac_rad >= 0.0_dp .and. cfg%frac_conv >= 0.0_dp &
                     .and. cfg%frac_elec >= 0.0_dp, &
                     'frac_rad, frac_conv, frac_elec must be >= 0', ok)
        call require(cfg%output_freq >= 1 .and. cfg%monitor_freq >= 1, &
                     'output_freq and monitor_freq must be >= 1', ok)
        call require(cfg%rho_steel > 0.0_dp .and. cfg%cp_s > 0.0_dp &
                     .and. cfg%cp_l > 0.0_dp .and. cfg%h_fusion > 0.0_dp, &
                     'material properties must be > 0', ok)
        call require(cfg%R_shell > 0.0_dp .and. cfg%H_total > 0.0_dp, &
                     'R_shell and H_total must be > 0', ok)
        ! auditoria (bajos): validaciones que faltaban
        call require(cfg%stretch_r > 0.0_dp .and. cfg%stretch_z > 0.0_dp, &
                     'stretch_r and stretch_z must be > 0', ok)
        call require(cfg%H_bowl >= 0.0_dp .and. cfg%H_bowl < cfg%H_total, &
                     'requires 0 <= H_bowl < H_total', ok)
        call require(cfg%R_bowl > 0.0_dp .and. cfg%R_bowl <= cfg%R_shell, &
                     'requires 0 < R_bowl <= R_shell', ok)
        call require(cfg%R_elec > 0.0_dp .and. cfg%R_pcd + cfg%R_elec < cfg%R_shell, &
                     'requires R_elec > 0 and R_pcd + R_elec < R_shell', ok)
        if (cfg%adaptive_dt) call require(cfg%dt >= cfg%dt_min .and. cfg%dt <= cfg%dt_max, &
                     'requires dt_min <= dt <= dt_max (adaptive_dt)', ok)
        call require(cfg%wall_time_max >= 0.0_dp, 'wall_time_max must be >= 0 (0 = off)', ok)
        ! (Plan H) la vista condensada solo existe en dos fluidos con flujo
        if (cfg%slag_in_volume) call require(cfg%solve_slag .and. cfg%solve_flow .and. &
            cfg%solve_multiphase .and. .not. cfg%mixture_model, &
            'slag_in_volume requires solve_slag, solve_flow, solve_multiphase and not mixture_model', ok)
        call require(cfg%do_quadrature == 4 .or. cfg%do_quadrature == 6 &
                     .or. cfg%do_quadrature == 8, &
                     'do_quadrature must be 4, 6 or 8', ok)
        ! Auditoria M21: sin transporte, Y_O2 nunca se agota (la quimica
        ! limita por el O2 de la celda y el solver no lo descuenta): O2
        ! infinito, ~690 MW/m3 de calor de oxidacion
        if (cfg%solve_chemistry) then
            call require(cfg%solve_species, &
                         'solve_chemistry requires solve_species (O2 finito)', ok)
        end if
        ! (auditoria 5, B5-4) en la rama de UNA fase (flujo sin dos fluidos)
        ! solo se resuelve la energia del liquido: la parte del gas de la
        ! radiacion de la DO (w_g kappa_f (G - 4 sigma T_g^4)) no la paga nadie
        if (cfg%solve_flow .and. .not. cfg%solve_multiphase) then
            call require(.not. cfg%solve_radiation, &
                         'solve_radiation with solve_flow requires solve_multiphase ' // &
                         '(rama de una fase: la emision del gas quedaria sin pagar)', ok)
        end if
        ! (B5-8) con n_pc_max > 1 la cancelacion del Rhie-Chow deja de ser
        ! exacta desde la segunda pasada (la alpha del Poisson ya no es la del
        ! momento); ningun config lo usa
        if (cfg%n_pc_max > 1 .and. cfg_root()) print '(A)', &
            ' [CONFIG] NOTA: n_pc_max > 1: la cancelacion del Rhie-Chow (bed_rel_f/bed_rel_fp con ' // &
            'own_weight_face) no es exacta desde la segunda pasada (auditoria 5, B5-8)'
        if (cfg%solve_ecs) then
            call require(cfg%ecs_vfrac > 0.0_dp .and. cfg%ecs_vfrac <= 1.0_dp, &
                         'ecs_vfrac must be in (0, 1]', ok)
            call require(cfg%ecs_theta_width > 0.0_dp, &
                         'ecs_theta_width must be > 0', ok)
            call require(cfg%ecs_r_inner < cfg%R_shell, &
                         'ecs_r_inner must be < R_shell', ok)
            call require(cfg%ecs_rate >= 0.0_dp, &
                         'ecs_rate must be >= 0', ok)
            call require(cfg%ecs_T_charge > 0.0_dp, &
                         'ecs_T_charge must be > 0', ok)
            ! 'coupled' (caudal ligado a la potencia, v2) esta DISEÑADO pero no
            ! implementado: se aceptaba sin efecto (auditoria, bajos)
            call require(trim(cfg%ecs_mode) == 'table', &
                         "ecs_mode must be 'table' ('coupled' no implementado)", ok)
        end if

        if (.not. ok) then
            if (cfg_root()) print *, ' [CONFIG] Aborting due to invalid configuration.'
            stop 1
        end if
    end subroutine config_validate

    subroutine require(cond, msg, ok)
        logical, intent(in) :: cond
        character(len=*), intent(in) :: msg
        logical, intent(inout) :: ok

        if (.not. cond) then
            if (cfg_root()) print '(A,A)', ' [CONFIG] ERROR: ', msg
            ok = .false.
        end if
    end subroutine require

    subroutine config_print(cfg)
        type(config_t), intent(in) :: cfg

        print *, '============================================================'
        print *, '  3D EAF CFD Solver - Configuration'
        print *, '============================================================'
        print '(A,F8.3,A,F8.3)', '  R_shell=', cfg%R_shell, '  H_total=', cfg%H_total
        print '(A,I5,A,I5,A,I5,A,I10)', '  Mesh: ', cfg%nr, ' x ', cfg%ntheta, &
              ' x ', cfg%nz, ' = ', cfg%nr * cfg%ntheta * cfg%nz
        print '(A,ES10.3,A,ES10.3)', '  dt=', cfg%dt, '  t_final=', cfg%t_final
        if (len_trim(cfg%restart_file) > 0) &
            print '(A,A)', '  restart_file=', trim(cfg%restart_file)
        print '(A,I3,A,F5.2)', '  max_outer=', cfg%max_outer, '  alpha_u=', cfg%alpha_u
        print '(A,F8.1,A,F8.1,A,F8.1)', '  rho_steel=', cfg%rho_steel, &
              '  T_sol=', cfg%T_solidus, '  T_liq=', cfg%T_liquidus
        print '(A,L1,A,L1,A,L1,A,L1)', '  flow=', cfg%solve_flow, &
              ' energy=', cfg%solve_energy, ' melt=', cfg%solve_melting, &
              ' turb=', cfg%solve_turb
        print *, '============================================================'
    end subroutine config_print

    ! Claves que se leen pero NO tienen efecto en el modelo (auditoria, bajos):
    ! se avisa en vez de aceptarlas en silencio
    subroutine warn_noeffect(key)
        character(len=*), intent(in) :: key
        if (cfg_root()) print '(3A)', ' [CONFIG] AVISO: la clave "', trim(key), &
            '" no tiene efecto en esta version (se ignora)'
    end subroutine warn_noeffect

    ! Solo rank 0 imprime al leer/validar el config (auditoria, bajos: todos
    ! los ranks leen el archivo y cada uno repetia los mensajes)
    logical function cfg_root()
        use mpi
        integer :: rk, ierr
        logical :: init
        cfg_root = .true.
        call MPI_Initialized(init, ierr)
        if (.not. init) return
        call MPI_Comm_rank(MPI_COMM_WORLD, rk, ierr)
        cfg_root = (rk == 0)
    end function cfg_root

end module mod_config_3d
