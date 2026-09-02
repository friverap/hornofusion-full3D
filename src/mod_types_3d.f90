!===============================================================================
! mod_types_3d.f90 - Derived types for 3D EAF simulator
!
! Cylindrical coordinates (r, theta, z) with Eulerian-Eulerian multiphase
! and dual-cell solid phase.
! 
! MPI parallelization: mesh_t contains MPI topology info
!===============================================================================
module mod_types_3d
    use mod_constants, only: dp
    use mod_mpi_topology, only: mpi_topology_t
    implicit none

    integer, parameter :: MAX_LAYERS = 30
    integer, parameter :: N_ELECTRODES = 3

    !---------------------------------------------------------------------------
    ! Configuration
    !---------------------------------------------------------------------------
    type :: config_t
        ! EAF Geometry
        real(dp) :: R_shell       ! Furnace inner radius [m]
        real(dp) :: H_total       ! Total height (bowl bottom to roof) [m]
        real(dp) :: H_bowl        ! Bowl depth [m]
        real(dp) :: R_bowl        ! Bowl radius at shell floor [m]
        real(dp) :: R_pcd         ! Pitch circle radius of electrodes [m]
        real(dp) :: R_elec        ! Electrode radius [m]
        real(dp) :: R_outlet      ! Outlet region radius at roof [m]

        ! Mesh
        integer  :: nr, ntheta, nz
        real(dp) :: stretch_r, stretch_z

        ! Time
        real(dp) :: dt, dt_min, dt_max, t_final
        real(dp) :: cfl_max      ! límite CFL para dt adaptativo (C3.2)
        logical  :: adaptive_dt

        ! SIMPLE
        integer  :: max_outer, max_inner_mom, max_inner_pres
        real(dp) :: alpha_u, alpha_p, alpha_T
        real(dp) :: alpha_k, alpha_eps, alpha_alpha

        ! Convergence
        real(dp) :: tol_cont, tol_mom, tol_energy, tol_turb

        ! Material properties
        real(dp) :: rho_steel, T_solidus, T_liquidus, T_liq_hbi
        real(dp) :: cp_s, cp_l, h_fusion
        real(dp) :: k_s, k_l, mu_l
        real(dp) :: emissivity, beta_expansion
        real(dp) :: rho_gas, cp_gas, k_gas, mu_gas

        ! Ergun
        real(dp) :: d_particle

        ! Arc
        real(dp) :: arc_tau, arc_w, arc_sigma_cond, arc_T_ref
        real(dp) :: frac_rad, frac_conv, frac_elec

        ! Boundary conditions
        real(dp) :: T_ambient, T_initial

        ! Physics flags
        logical :: solve_flow, solve_energy, solve_melting
        logical :: solve_turb, solve_radiation, solve_chemistry
        logical :: solve_arc, solve_multiphase

        ! Output
        integer :: output_freq, monitor_freq
        integer :: audit_freq   ! frecuencia de audit.csv (pasos); 0 = off
        integer :: n_beams      ! rayos MC por electrodo por paso; 0 = MC off
        character(len=256) :: output_dir

        ! Charge recipe
        integer :: n_layers_b1, n_layers_b2
        real(dp) :: layer_vfrac(MAX_LAYERS)
        real(dp) :: layer_mass(MAX_LAYERS)
        integer  :: layer_bucket(MAX_LAYERS)
        integer  :: n_layers_total

        ! Bucket timing
        real(dp) :: t_bucket2_charge

        ! Slag
        real(dp) :: rho_slag       ! Slag density              [kg/m³]   ~2800
        real(dp) :: cp_slag        ! Slag heat capacity        [J/(kg·K)] ~1200
        real(dp) :: k_slag         ! Slag conductivity         [W/(m·K)]  ~1.5
        real(dp) :: h_contact_sl   ! Slag-steel interface h    [W/(m²·K)] ~1000
        real(dp) :: m_slag_init    ! Initial slag mass         [kg]       ~3300
        logical  :: solve_slag     ! Enable slag model

        ! Species transport (CO/CO2)
        logical  :: solve_species     ! Enable CO/CO2 transport
        real(dp) :: Sc_t_species      ! Turbulent Schmidt number [-]  default 0.7
        real(dp) :: alpha_Y_species   ! Under-relaxation for Y   [-]  default 0.5
    end type config_t

    !---------------------------------------------------------------------------
    ! 3D Cylindrical Mesh
    !---------------------------------------------------------------------------
    type :: mesh_t
        ! Parallel or serial mode
        logical :: is_parallel
        type(mpi_topology_t) :: topo
        
        ! Dimensions (global in parallel mode, local otherwise)
        integer :: nr, ntheta, nz
        integer :: ncells

        ! 1D coordinate arrays (global coordinates even in parallel mode)
        real(dp), allocatable :: r(:)        ! Cell center r   (with halos in parallel)
        real(dp), allocatable :: theta(:)    ! Cell center th  (with halos in parallel)
        real(dp), allocatable :: z(:)        ! Cell center z   (with halos in parallel)

        real(dp), allocatable :: rf(:)       ! Face r          (with halos in parallel)
        real(dp), allocatable :: thetaf(:)   ! Face theta      (with halos in parallel)
        real(dp), allocatable :: zf(:)       ! Face z          (with halos in parallel)

        real(dp), allocatable :: dr(:)       ! Cell width r    (with halos in parallel)
        real(dp), allocatable :: dtheta(:)   ! Cell width th   (with halos in parallel)  [radians]
        real(dp), allocatable :: dz(:)       ! Cell width z    (with halos in parallel)

        ! 3D arrays (dimensions include halos in parallel mode: -1:iloc+2, etc.)
        real(dp), allocatable :: vol(:,:,:)  ! Cell volumes
        real(dp), allocatable :: Ar(:,:,:)   ! Radial face area
        real(dp), allocatable :: Ath(:,:,:)  ! Azimuthal face area
        real(dp), allocatable :: Az(:,:,:)   ! Axial face area

        ! Cell flags: 0=inactive, 1=fluid, 2=wall (with halos in parallel)
        integer, allocatable :: cell_type(:,:,:)

        ! Bowl geometry: z_bowl(i) = bottom z for radial index i
        real(dp), allocatable :: z_bowl(:)

        ! Global coordinates (all ranks, for HDF5 output)
        real(dp), allocatable :: r_global(:)      ! nr_global cell centers
        real(dp), allocatable :: theta_global(:)  ! nth_global cell centers
        real(dp), allocatable :: z_global(:)      ! nz_global cell centers

        ! Global geometry replicated on every rank so that decomposition-
        ! sensitive physics (arc heat, MC radiation) can be computed in the
        ! exact same order as the serial code, bit-for-bit.
        integer :: nr_g, nth_g, nz_g                       ! global dimensions
        real(dp), allocatable :: rf_global(:)              ! 0:nr_g face radii
        real(dp), allocatable :: zf_global(:)              ! 0:nz_g face heights
        real(dp), allocatable :: vol_global(:,:,:)         ! global cell volumes
        integer,  allocatable :: cell_type_global(:,:,:)   ! global cell flags

        ! Electrode cells mask (1..N_ELECTRODES, per electrode) (with halos in parallel)
        logical, allocatable :: is_electrode(:,:,:,:)
    end type mesh_t

    !---------------------------------------------------------------------------
    ! Phase fields (one instance per fluid phase: liquid + gas)
    !---------------------------------------------------------------------------
    type :: phase_t
        real(dp), allocatable :: alpha(:,:,:)  ! Volume fraction
        real(dp), allocatable :: ur(:,:,:)     ! Radial velocity
        real(dp), allocatable :: uth(:,:,:)    ! Azimuthal velocity
        real(dp), allocatable :: uz(:,:,:)     ! Axial velocity
        real(dp), allocatable :: T(:,:,:)      ! Temperature [K]

        ! Properties (spatially varying)
        real(dp), allocatable :: rho(:,:,:)
        real(dp), allocatable :: cp(:,:,:)
        real(dp), allocatable :: kth(:,:,:)
        real(dp), allocatable :: mu(:,:,:)
        real(dp), allocatable :: mu_eff(:,:,:)

        ! SIMPLE coefficients
        real(dp), allocatable :: aP_ur(:,:,:)
        real(dp), allocatable :: aP_uth(:,:,:)
        real(dp), allocatable :: aP_uz(:,:,:)
    end type phase_t

    !---------------------------------------------------------------------------
    ! Solid phase (dual-cell approach)
    !---------------------------------------------------------------------------
    type :: solid_t
        real(dp), allocatable :: alpha_s(:,:,:)   ! Solid volume fraction
        real(dp), allocatable :: m_s(:,:,:)       ! Solid mass per cell [kg]
        real(dp), allocatable :: T_s(:,:,:)       ! Solid temperature [K]
        real(dp), allocatable :: E_s(:,:,:)       ! Solid energy per cell [J]
        integer,  allocatable :: layer_id(:,:,:)  ! Which charge layer
        real(dp), allocatable :: mdot(:,:,:)      ! Melting rate [kg/s]
    end type solid_t

    !---------------------------------------------------------------------------
    ! Slag phase (pseudo-phase tracked by buoyancy, no full N-S)
    !---------------------------------------------------------------------------
    type :: slag_t
        real(dp), allocatable :: alpha_sl(:,:,:)  ! Slag volume fraction  [-]
        real(dp), allocatable :: m_sl(:,:,:)      ! Slag mass per cell    [kg]
        real(dp), allocatable :: T_sl(:,:,:)      ! Slag temperature      [K]
        real(dp), allocatable :: E_sl(:,:,:)      ! Slag internal energy  [J]
    end type slag_t

    !---------------------------------------------------------------------------
    ! Shared fields
    !---------------------------------------------------------------------------
    type :: shared_t
        real(dp), allocatable :: p(:,:,:)      ! Pressure [Pa]
        real(dp), allocatable :: pp(:,:,:)     ! Pressure correction

        ! Turbulence (applied to liquid phase)
        real(dp), allocatable :: tke(:,:,:)
        real(dp), allocatable :: eps(:,:,:)
        real(dp), allocatable :: mu_t(:,:,:)

        ! Arc sources
        real(dp), allocatable :: S_arc(:,:,:)      ! Arc heat source [W/m^3]
        real(dp), allocatable :: S_arc_mom(:,:,:)  ! Arc impingement momentum [N/m^3]

        ! Lorentz / electromagnetic stirring (liquid only, [N/m^3])
        real(dp), allocatable :: F_lorentz_r(:,:,:)   ! Radial Lorentz force density
        real(dp), allocatable :: F_lorentz_th(:,:,:)  ! Azimuthal Lorentz force density

        ! Radiation
        real(dp), allocatable :: S_rad(:,:,:)

        ! Chemistry
        real(dp), allocatable :: S_chem(:,:,:)

        ! Gas species mass fractions and volumetric source terms
        real(dp), allocatable :: Y_CO(:,:,:)       ! CO mass fraction         [-]
        real(dp), allocatable :: Y_CO2(:,:,:)      ! CO2 mass fraction        [-]
        real(dp), allocatable :: S_CO_src(:,:,:)   ! CO net source            [kg/(m3·s)]
        real(dp), allocatable :: S_CO2_src(:,:,:)  ! CO2 net source           [kg/(m3·s)]
    end type shared_t

    !---------------------------------------------------------------------------
    ! Electrode state
    !---------------------------------------------------------------------------
    type :: electrode_t
        real(dp) :: theta_pos     ! Azimuthal position [rad]
        real(dp) :: z_tip         ! Current tip z-position [m]
        real(dp) :: arc_length    ! Current arc length [m]
        real(dp) :: arc_R         ! Current arc resistance [Ohm]
        real(dp) :: arc_power     ! Current arc power [W]
        real(dp) :: voltage       ! Current voltage [V]
        real(dp) :: current       ! Current current [A]
        logical  :: bore_in_done  ! Has bore-in completed?
    end type electrode_t

    !---------------------------------------------------------------------------
    ! Convergence
    !---------------------------------------------------------------------------
    type :: convergence_t
        real(dp) :: res_cont, res_ur, res_uth, res_uz
        real(dp) :: res_energy, res_tke, res_eps
        integer  :: n_outer
        logical  :: converged
    end type convergence_t

end module mod_types_3d
