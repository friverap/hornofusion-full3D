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
            print '(A,A)', ' [CONFIG] Cannot open: ', trim(filename)
            return
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
        case ('R_shell');    read(val, *) cfg%R_shell
        case ('H_total');    read(val, *) cfg%H_total
        case ('H_bowl');     read(val, *) cfg%H_bowl
        case ('R_bowl');     read(val, *) cfg%R_bowl
        case ('R_pcd');      read(val, *) cfg%R_pcd
        case ('R_elec');     read(val, *) cfg%R_elec
        ! Mesh
        case ('nr');         read(val, *) cfg%nr
        case ('ntheta');     read(val, *) cfg%ntheta
        case ('nz');         read(val, *) cfg%nz
        case ('stretch_r');  read(val, *) cfg%stretch_r
        case ('stretch_z');  read(val, *) cfg%stretch_z
        ! Time
        case ('dt');         read(val, *) cfg%dt
        case ('dt_min');     read(val, *) cfg%dt_min
        case ('dt_max');     read(val, *) cfg%dt_max
        case ('t_final');    read(val, *) cfg%t_final
        case ('adaptive_dt'); cfg%adaptive_dt = (trim(val) == 'true' .or. trim(val) == '.true.')
        ! SIMPLE
        case ('max_outer');       read(val, *) cfg%max_outer
        case ('max_inner_mom');   read(val, *) cfg%max_inner_mom
        case ('max_inner_pres');  read(val, *) cfg%max_inner_pres
        case ('alpha_u');    read(val, *) cfg%alpha_u
        case ('alpha_p');    read(val, *) cfg%alpha_p
        case ('alpha_T');    read(val, *) cfg%alpha_T
        ! Convergence
        case ('tol_cont');   read(val, *) cfg%tol_cont
        case ('tol_mom');    read(val, *) cfg%tol_mom
        case ('tol_energy'); read(val, *) cfg%tol_energy
        ! Material
        case ('rho_steel');  read(val, *) cfg%rho_steel
        case ('T_solidus');  read(val, *) cfg%T_solidus
        case ('T_liquidus'); read(val, *) cfg%T_liquidus
        case ('cp_s');       read(val, *) cfg%cp_s
        case ('cp_l');       read(val, *) cfg%cp_l
        case ('h_fusion');   read(val, *) cfg%h_fusion
        case ('T_initial');  read(val, *) cfg%T_initial
        case ('T_ambient');  read(val, *) cfg%T_ambient
        ! Physics flags
        case ('solve_flow');    cfg%solve_flow = (trim(val) == 'true' .or. trim(val) == '.true.')
        case ('solve_energy');  cfg%solve_energy = (trim(val) == 'true' .or. trim(val) == '.true.')
        case ('solve_melting'); cfg%solve_melting = (trim(val) == 'true' .or. trim(val) == '.true.')
        case ('solve_turb');    cfg%solve_turb = (trim(val) == 'true' .or. trim(val) == '.true.')
        case ('solve_arc');     cfg%solve_arc = (trim(val) == 'true' .or. trim(val) == '.true.')
        case ('solve_radiation'); cfg%solve_radiation = (trim(val) == 'true' .or. trim(val) == '.true.')
        case ('solve_chemistry'); cfg%solve_chemistry = (trim(val) == 'true' .or. trim(val) == '.true.')
        case ('solve_multiphase'); cfg%solve_multiphase = (trim(val) == 'true' .or. trim(val) == '.true.')
        ! Output
        case ('output_freq');  read(val, *) cfg%output_freq
        case ('monitor_freq'); read(val, *) cfg%monitor_freq
        case ('output_dir');   cfg%output_dir = trim(val)
        ! Bucket timing
        case ('t_bucket2_charge'); read(val, *) cfg%t_bucket2_charge
        ! Arc heat partition fractions
        case ('frac_conv');  read(val, *) cfg%frac_conv
        case ('frac_rad');   read(val, *) cfg%frac_rad
        case ('frac_elec');  read(val, *) cfg%frac_elec
        case ('arc_w');      read(val, *) cfg%arc_w
        ! Slag
        case ('rho_slag');     read(val, *) cfg%rho_slag
        case ('cp_slag');      read(val, *) cfg%cp_slag
        case ('k_slag');       read(val, *) cfg%k_slag
        case ('h_contact_sl'); read(val, *) cfg%h_contact_sl
        case ('m_slag_init');  read(val, *) cfg%m_slag_init
        case ('solve_slag');   cfg%solve_slag = (trim(val)=='true' .or. trim(val)=='.true.')
        ! Species transport
        case ('solve_species');   cfg%solve_species = (trim(val)=='true' .or. trim(val)=='.true.')
        case ('Sc_t_species');    read(val,*) cfg%Sc_t_species
        case ('alpha_Y_species'); read(val,*) cfg%alpha_Y_species
        case default
            ! ignore unknown keys silently
        end select
    end subroutine config_set_value

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
