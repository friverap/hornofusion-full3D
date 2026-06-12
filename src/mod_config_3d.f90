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
        cfg%R_outlet = 0.35_dp

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

        ! SIMPLE
        cfg%max_outer     = 20
        cfg%max_inner_mom  = 5
        cfg%max_inner_pres = 50
        cfg%alpha_u    = 0.3_dp
        cfg%alpha_p    = 0.7_dp
        cfg%alpha_T    = 0.7_dp
        cfg%alpha_k    = 0.5_dp
        cfg%alpha_eps  = 0.5_dp
        cfg%alpha_alpha = 0.3_dp

        ! Convergence
        cfg%tol_cont   = 1.0e-4_dp
        cfg%tol_mom    = 1.0e-4_dp
        cfg%tol_energy = 1.0e-3_dp
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

        ! Material - gas
        cfg%rho_gas = RHO_GAS_REF
        cfg%cp_gas  = CP_GAS
        cfg%k_gas   = K_GAS
        cfg%mu_gas  = MU_GAS

        ! Ergun
        cfg%d_particle = D_PARTICLE

        ! Arc
        cfg%arc_tau       = ARC_TAU
        cfg%arc_w         = ARC_W
        cfg%arc_sigma_cond = ARC_SIGMA
        cfg%arc_T_ref     = ARC_T_REF
        cfg%frac_rad      = 0.50_dp
        cfg%frac_conv     = 0.30_dp
        cfg%frac_elec     = 0.20_dp

        ! BCs
        cfg%T_ambient = 300.0_dp
        cfg%T_initial = 300.0_dp

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
        cfg%output_dir   = 'output'

        ! Slag
        cfg%rho_slag     = 2800.0_dp
        cfg%cp_slag      = 1200.0_dp
        cfg%k_slag       = 1.5_dp
        cfg%h_contact_sl = 1000.0_dp
        cfg%m_slag_init  = 3300.0_dp
        cfg%solve_slag   = .false.

        ! Species transport (CO/CO2)
        cfg%solve_species   = .false.
        cfg%Sc_t_species    = 0.7_dp
        cfg%alpha_Y_species = 0.5_dp

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
        integer :: eq_pos

        open(newunit=iu, file=trim(filename), status='old', iostat=ios)
        if (ios /= 0) then
            print '(A,A)', ' [CONFIG] ERROR: cannot open config file: ', trim(filename)
            stop 1
        end if
        print '(A,A)', ' [CONFIG] Reading: ', trim(filename)

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

            call config_set_value(cfg, trim(key), trim(val))
        end do
        close(iu)
    end subroutine config_read

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
        ! SIMPLE
        case ('max_outer');       call parse_int(val, key, cfg%max_outer)
        case ('max_inner_mom');   call parse_int(val, key, cfg%max_inner_mom)
        case ('max_inner_pres');  call parse_int(val, key, cfg%max_inner_pres)
        case ('alpha_u');    call parse_real(val, key, cfg%alpha_u)
        case ('alpha_p');    call parse_real(val, key, cfg%alpha_p)
        case ('alpha_T');    call parse_real(val, key, cfg%alpha_T)
        ! Convergence
        case ('tol_cont');   call parse_real(val, key, cfg%tol_cont)
        case ('tol_mom');    call parse_real(val, key, cfg%tol_mom)
        case ('tol_energy'); call parse_real(val, key, cfg%tol_energy)
        ! Material
        case ('rho_steel');  call parse_real(val, key, cfg%rho_steel)
        case ('T_solidus');  call parse_real(val, key, cfg%T_solidus)
        case ('T_liquidus'); call parse_real(val, key, cfg%T_liquidus)
        case ('cp_s');       call parse_real(val, key, cfg%cp_s)
        case ('cp_l');       call parse_real(val, key, cfg%cp_l)
        case ('h_fusion');   call parse_real(val, key, cfg%h_fusion)
        case ('T_initial');  call parse_real(val, key, cfg%T_initial)
        case ('T_ambient');  call parse_real(val, key, cfg%T_ambient)
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
        case ('output_dir');   cfg%output_dir = trim(val)
        ! Bucket timing
        case ('t_bucket2_charge'); call parse_real(val, key, cfg%t_bucket2_charge)
        ! Arc heat partition fractions
        case ('frac_conv');  call parse_real(val, key, cfg%frac_conv)
        case ('frac_rad');   call parse_real(val, key, cfg%frac_rad)
        case ('frac_elec');  call parse_real(val, key, cfg%frac_elec)
        case ('arc_w');      call parse_real(val, key, cfg%arc_w)
        ! Slag
        case ('rho_slag');     call parse_real(val, key, cfg%rho_slag)
        case ('cp_slag');      call parse_real(val, key, cfg%cp_slag)
        case ('k_slag');       call parse_real(val, key, cfg%k_slag)
        case ('h_contact_sl'); call parse_real(val, key, cfg%h_contact_sl)
        case ('m_slag_init');  call parse_real(val, key, cfg%m_slag_init)
        case ('solve_slag');   cfg%solve_slag = parse_bool(val)
        ! Species transport
        case ('solve_species');   cfg%solve_species = parse_bool(val)
        case ('Sc_t_species');    call parse_real(val, key, cfg%Sc_t_species)
        case ('alpha_Y_species'); call parse_real(val, key, cfg%alpha_Y_species)
        case default
            print '(A,A,A)', ' [CONFIG] WARNING: unknown key "', trim(key), &
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
            print '(5A)', ' [CONFIG] ERROR: invalid value "', trim(val), &
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
            print '(5A)', ' [CONFIG] ERROR: invalid value "', trim(val), &
                  '" for key "', trim(key), '"'
            stop 1
        end if
        n = tmp
    end subroutine parse_int

    pure function parse_bool(val) result(b)
        character(len=*), intent(in) :: val
        logical :: b

        b = (trim(val) == 'true' .or. trim(val) == '.true.')
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
        call require(cfg%output_freq >= 1 .and. cfg%monitor_freq >= 1, &
                     'output_freq and monitor_freq must be >= 1', ok)
        call require(cfg%rho_steel > 0.0_dp .and. cfg%cp_s > 0.0_dp &
                     .and. cfg%cp_l > 0.0_dp .and. cfg%h_fusion > 0.0_dp, &
                     'material properties must be > 0', ok)
        call require(cfg%R_shell > 0.0_dp .and. cfg%H_total > 0.0_dp, &
                     'R_shell and H_total must be > 0', ok)

        if (.not. ok) then
            print *, ' [CONFIG] Aborting due to invalid configuration.'
            stop 1
        end if
    end subroutine config_validate

    subroutine require(cond, msg, ok)
        logical, intent(in) :: cond
        character(len=*), intent(in) :: msg
        logical, intent(inout) :: ok

        if (.not. cond) then
            print '(A,A)', ' [CONFIG] ERROR: ', msg
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
        print '(A,I3,A,F5.2)', '  max_outer=', cfg%max_outer, '  alpha_u=', cfg%alpha_u
        print '(A,F8.1,A,F8.1,A,F8.1)', '  rho_steel=', cfg%rho_steel, &
              '  T_sol=', cfg%T_solidus, '  T_liq=', cfg%T_liquidus
        print '(A,L1,A,L1,A,L1,A,L1)', '  flow=', cfg%solve_flow, &
              ' energy=', cfg%solve_energy, ' melt=', cfg%solve_melting, &
              ' turb=', cfg%solve_turb
        print *, '============================================================'
    end subroutine config_print

end module mod_config_3d
