!===============================================================================
! mod_fields_3d.f90 - Allocation and initialization of all field variables
!
! MPI-aware: supports allocation with halos and halo exchange
!===============================================================================
module mod_fields_3d
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_melting_3d, only: solid_enthalpy
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Allocate a phase (liquid or gas) with halos for parallel mode
    !---------------------------------------------------------------------------
    subroutine phase_allocate(ph, m)
        type(phase_t), intent(out) :: ph
        type(mesh_t), intent(in) :: m

        integer :: i1, i2, j1, j2, k1, k2, ierr

        ! Always allocate with halos (-1 to N+2) for consistency
        i1 = -1; i2 = m%nr + 2
        j1 = -1; j2 = m%ntheta + 2
        k1 = -1; k2 = m%nz + 2

        allocate(ph%alpha(i1:i2, j1:j2, k1:k2), ph%ur(i1:i2, j1:j2, k1:k2), &
                 ph%uth(i1:i2, j1:j2, k1:k2), ph%uz(i1:i2, j1:j2, k1:k2), &
                 ph%T(i1:i2, j1:j2, k1:k2), ph%rho(i1:i2, j1:j2, k1:k2), &
                 ph%cp(i1:i2, j1:j2, k1:k2), ph%kth(i1:i2, j1:j2, k1:k2), &
                 ph%mu(i1:i2, j1:j2, k1:k2), ph%mu_eff(i1:i2, j1:j2, k1:k2), &
                 ph%aP_ur(i1:i2, j1:j2, k1:k2), ph%aP_uth(i1:i2, j1:j2, k1:k2), &
                 ph%aP_uz(i1:i2, j1:j2, k1:k2), stat=ierr)
        call check_alloc(ierr, 'phase fields')

        ph%alpha = 0.0_dp; ph%ur = 0.0_dp; ph%uth = 0.0_dp; ph%uz = 0.0_dp
        ph%T = 0.0_dp; ph%rho = 0.0_dp; ph%cp = 0.0_dp; ph%kth = 0.0_dp
        ph%mu = 0.0_dp; ph%mu_eff = 0.0_dp
        ph%aP_ur = 0.0_dp; ph%aP_uth = 0.0_dp; ph%aP_uz = 0.0_dp
    end subroutine phase_allocate

    !---------------------------------------------------------------------------
    ! Abort cleanly (all MPI processes) if a field allocation failed
    !---------------------------------------------------------------------------
    subroutine check_alloc(ierr, what)
        integer, intent(in) :: ierr
        character(len=*), intent(in) :: what

        integer :: abort_err

        if (ierr /= 0) then
            write(*,'(3A,I0)') '[FIELDS] ERROR: cannot allocate ', what, &
                  ', stat=', ierr
            call MPI_Abort(MPI_COMM_WORLD, 1, abort_err)
        end if
    end subroutine check_alloc

    !---------------------------------------------------------------------------
    ! Exchange halos for a phase (all fields)
    !---------------------------------------------------------------------------
    subroutine phase_exchange_halos(ph, m)
        type(phase_t), intent(inout) :: ph
        type(mesh_t), intent(in) :: m

        integer :: nth

        nth = m%ntheta

        if (m%is_parallel) then
            call mpi_exchange_halos_3d(ph%alpha,  m%topo)
            call mpi_exchange_halos_3d(ph%ur,     m%topo)
            call mpi_exchange_halos_3d(ph%uth,    m%topo)
            call mpi_exchange_halos_3d(ph%uz,     m%topo)
            call mpi_exchange_halos_3d(ph%T,      m%topo)
            call mpi_exchange_halos_3d(ph%rho,    m%topo)
            call mpi_exchange_halos_3d(ph%cp,     m%topo)
            call mpi_exchange_halos_3d(ph%kth,    m%topo)
            call mpi_exchange_halos_3d(ph%mu,     m%topo)
            call mpi_exchange_halos_3d(ph%mu_eff, m%topo)
            call mpi_exchange_halos_3d(ph%aP_ur,  m%topo)
            call mpi_exchange_halos_3d(ph%aP_uth, m%topo)
            call mpi_exchange_halos_3d(ph%aP_uz,  m%topo)
        else
            ! Serial: fill periodic theta halos
            call fill_periodic_theta(ph%alpha,  nth)
            call fill_periodic_theta(ph%ur,     nth)
            call fill_periodic_theta(ph%uth,    nth)
            call fill_periodic_theta(ph%uz,     nth)
            call fill_periodic_theta(ph%T,      nth)
            call fill_periodic_theta(ph%rho,    nth)
            call fill_periodic_theta(ph%cp,     nth)
            call fill_periodic_theta(ph%kth,    nth)
            call fill_periodic_theta(ph%mu,     nth)
            call fill_periodic_theta(ph%mu_eff, nth)
            call fill_periodic_theta(ph%aP_ur,  nth)
            call fill_periodic_theta(ph%aP_uth, nth)
            call fill_periodic_theta(ph%aP_uz,  nth)
        end if
    end subroutine phase_exchange_halos

    subroutine phase_destroy(ph)
        type(phase_t), intent(inout) :: ph

        if (allocated(ph%alpha))  deallocate(ph%alpha)
        if (allocated(ph%ur))     deallocate(ph%ur)
        if (allocated(ph%uth))    deallocate(ph%uth)
        if (allocated(ph%uz))     deallocate(ph%uz)
        if (allocated(ph%T))      deallocate(ph%T)
        if (allocated(ph%rho))    deallocate(ph%rho)
        if (allocated(ph%cp))     deallocate(ph%cp)
        if (allocated(ph%kth))    deallocate(ph%kth)
        if (allocated(ph%mu))     deallocate(ph%mu)
        if (allocated(ph%mu_eff)) deallocate(ph%mu_eff)
        if (allocated(ph%aP_ur))  deallocate(ph%aP_ur)
        if (allocated(ph%aP_uth)) deallocate(ph%aP_uth)
        if (allocated(ph%aP_uz))  deallocate(ph%aP_uz)
    end subroutine phase_destroy

    !---------------------------------------------------------------------------
    ! Allocate solid phase with halos
    !---------------------------------------------------------------------------
    subroutine solid_allocate(sol, m)
        type(solid_t), intent(out) :: sol
        type(mesh_t), intent(in) :: m

        integer :: i1, i2, j1, j2, k1, k2, ierr

        i1 = -1; i2 = m%nr + 2
        j1 = -1; j2 = m%ntheta + 2
        k1 = -1; k2 = m%nz + 2

        allocate(sol%alpha_s(i1:i2, j1:j2, k1:k2), sol%m_s(i1:i2, j1:j2, k1:k2), &
                 sol%T_s(i1:i2, j1:j2, k1:k2), sol%E_s(i1:i2, j1:j2, k1:k2), &
                 sol%layer_id(i1:i2, j1:j2, k1:k2), sol%mdot(i1:i2, j1:j2, k1:k2), &
                 stat=ierr)
        call check_alloc(ierr, 'solid fields')

        sol%alpha_s = 0.0_dp; sol%m_s = 0.0_dp; sol%T_s = 0.0_dp
        sol%E_s = 0.0_dp; sol%layer_id = 0; sol%mdot = 0.0_dp
    end subroutine solid_allocate
    
    !---------------------------------------------------------------------------
    ! Exchange halos for solid phase
    !---------------------------------------------------------------------------
    subroutine solid_exchange_halos(sol, m)
        type(solid_t), intent(inout) :: sol
        type(mesh_t), intent(in) :: m

        integer :: nth

        nth = m%ntheta

        if (m%is_parallel) then
            call mpi_exchange_halos_3d(sol%alpha_s, m%topo)
            call mpi_exchange_halos_3d(sol%m_s,     m%topo)
            call mpi_exchange_halos_3d(sol%T_s,     m%topo)
            call mpi_exchange_halos_3d(sol%E_s,     m%topo)
            call mpi_exchange_halos_3d(sol%mdot,    m%topo)
        else
            call fill_periodic_theta(sol%alpha_s, nth)
            call fill_periodic_theta(sol%m_s,     nth)
            call fill_periodic_theta(sol%T_s,     nth)
            call fill_periodic_theta(sol%E_s,     nth)
            call fill_periodic_theta(sol%mdot,    nth)
        end if
    end subroutine solid_exchange_halos

    subroutine solid_destroy(sol)
        type(solid_t), intent(inout) :: sol

        if (allocated(sol%alpha_s))  deallocate(sol%alpha_s)
        if (allocated(sol%m_s))      deallocate(sol%m_s)
        if (allocated(sol%T_s))      deallocate(sol%T_s)
        if (allocated(sol%E_s))      deallocate(sol%E_s)
        if (allocated(sol%layer_id)) deallocate(sol%layer_id)
        if (allocated(sol%mdot))     deallocate(sol%mdot)
    end subroutine solid_destroy

    !---------------------------------------------------------------------------
    ! Allocate slag phase with halos
    !---------------------------------------------------------------------------
    subroutine slag_allocate(slag, m)
        type(slag_t), intent(out) :: slag
        type(mesh_t), intent(in)  :: m

        integer :: i1, i2, j1, j2, k1, k2, ierr

        i1 = -1; i2 = m%nr + 2
        j1 = -1; j2 = m%ntheta + 2
        k1 = -1; k2 = m%nz + 2

        allocate(slag%alpha_sl(i1:i2, j1:j2, k1:k2), slag%m_sl(i1:i2, j1:j2, k1:k2), &
                 slag%T_sl(i1:i2, j1:j2, k1:k2), slag%E_sl(i1:i2, j1:j2, k1:k2), &
                 stat=ierr)
        call check_alloc(ierr, 'slag fields')

        slag%alpha_sl = 0.0_dp; slag%m_sl = 0.0_dp
        slag%T_sl = 0.0_dp; slag%E_sl = 0.0_dp
    end subroutine slag_allocate

    !---------------------------------------------------------------------------
    ! Exchange halos for slag phase
    !---------------------------------------------------------------------------
    subroutine slag_exchange_halos(slag, m)
        type(slag_t), intent(inout) :: slag
        type(mesh_t), intent(in)    :: m

        integer :: nth

        nth = m%ntheta

        if (m%is_parallel) then
            call mpi_exchange_halos_3d(slag%alpha_sl, m%topo)
            call mpi_exchange_halos_3d(slag%m_sl,     m%topo)
            call mpi_exchange_halos_3d(slag%T_sl,     m%topo)
            call mpi_exchange_halos_3d(slag%E_sl,     m%topo)
        else
            call fill_periodic_theta(slag%alpha_sl, nth)
            call fill_periodic_theta(slag%m_sl,     nth)
            call fill_periodic_theta(slag%T_sl,     nth)
            call fill_periodic_theta(slag%E_sl,     nth)
        end if
    end subroutine slag_exchange_halos

    subroutine slag_destroy(slag)
        type(slag_t), intent(inout) :: slag

        if (allocated(slag%alpha_sl)) deallocate(slag%alpha_sl)
        if (allocated(slag%m_sl))     deallocate(slag%m_sl)
        if (allocated(slag%T_sl))     deallocate(slag%T_sl)
        if (allocated(slag%E_sl))     deallocate(slag%E_sl)
    end subroutine slag_destroy

    !---------------------------------------------------------------------------
    ! Allocate shared fields with halos
    !---------------------------------------------------------------------------
    subroutine shared_allocate(sh, m)
        type(shared_t), intent(out) :: sh
        type(mesh_t), intent(in) :: m

        integer :: i1, i2, j1, j2, k1, k2, ierr

        i1 = -1; i2 = m%nr + 2
        j1 = -1; j2 = m%ntheta + 2
        k1 = -1; k2 = m%nz + 2

        allocate(sh%p(i1:i2, j1:j2, k1:k2), sh%pp(i1:i2, j1:j2, k1:k2), &
                 sh%tke(i1:i2, j1:j2, k1:k2), sh%eps(i1:i2, j1:j2, k1:k2), &
                 sh%mu_t(i1:i2, j1:j2, k1:k2), sh%S_arc(i1:i2, j1:j2, k1:k2), &
                 sh%S_arc_mom(i1:i2, j1:j2, k1:k2), sh%F_lorentz_r(i1:i2, j1:j2, k1:k2), &
                 sh%F_lorentz_th(i1:i2, j1:j2, k1:k2), sh%S_rad(i1:i2, j1:j2, k1:k2), &
                 sh%G_rad(i1:i2, j1:j2, k1:k2), sh%kappa_f(i1:i2, j1:j2, k1:k2), &
                 sh%S_chem(i1:i2, j1:j2, k1:k2), sh%Y_CO(i1:i2, j1:j2, k1:k2), &
                 sh%Y_CO2(i1:i2, j1:j2, k1:k2), sh%S_CO_src(i1:i2, j1:j2, k1:k2), &
                 sh%S_CO2_src(i1:i2, j1:j2, k1:k2), stat=ierr)
        call check_alloc(ierr, 'shared fields')

        sh%p = 0.0_dp; sh%pp = 0.0_dp; sh%tke = 0.0_dp; sh%eps = 0.0_dp
        sh%mu_t = 0.0_dp; sh%S_arc = 0.0_dp; sh%S_arc_mom = 0.0_dp
        sh%F_lorentz_r = 0.0_dp; sh%F_lorentz_th = 0.0_dp
        sh%S_rad = 0.0_dp; sh%S_chem = 0.0_dp
        sh%G_rad = 0.0_dp; sh%kappa_f = 0.0_dp
        sh%Y_CO = 0.0_dp; sh%Y_CO2 = 0.0_dp
        sh%S_CO_src = 0.0_dp; sh%S_CO2_src = 0.0_dp
    end subroutine shared_allocate
    
    !---------------------------------------------------------------------------
    ! Exchange halos for shared fields
    !---------------------------------------------------------------------------
    subroutine shared_exchange_halos(sh, m)
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in) :: m

        integer :: nth

        nth = m%ntheta

        if (m%is_parallel) then
            call mpi_exchange_halos_3d(sh%p,      m%topo)
            call mpi_exchange_halos_3d(sh%pp,     m%topo)
            call mpi_exchange_halos_3d(sh%tke,    m%topo)
            call mpi_exchange_halos_3d(sh%eps,    m%topo)
            call mpi_exchange_halos_3d(sh%mu_t,   m%topo)
            call mpi_exchange_halos_3d(sh%Y_CO,   m%topo)
            call mpi_exchange_halos_3d(sh%Y_CO2,  m%topo)
        else
            call fill_periodic_theta(sh%p,     nth)
            call fill_periodic_theta(sh%pp,    nth)
            call fill_periodic_theta(sh%tke,   nth)
            call fill_periodic_theta(sh%eps,   nth)
            call fill_periodic_theta(sh%mu_t,  nth)
            call fill_periodic_theta(sh%Y_CO,  nth)
            call fill_periodic_theta(sh%Y_CO2, nth)
        end if
    end subroutine shared_exchange_halos

    subroutine shared_destroy(sh)
        type(shared_t), intent(inout) :: sh

        if (allocated(sh%p))        deallocate(sh%p)
        if (allocated(sh%pp))       deallocate(sh%pp)
        if (allocated(sh%tke))      deallocate(sh%tke)
        if (allocated(sh%eps))      deallocate(sh%eps)
        if (allocated(sh%mu_t))     deallocate(sh%mu_t)
        if (allocated(sh%S_arc))         deallocate(sh%S_arc)
        if (allocated(sh%S_arc_mom))     deallocate(sh%S_arc_mom)
        if (allocated(sh%F_lorentz_r))   deallocate(sh%F_lorentz_r)
        if (allocated(sh%F_lorentz_th))  deallocate(sh%F_lorentz_th)
        if (allocated(sh%S_rad))         deallocate(sh%S_rad)
        if (allocated(sh%G_rad))         deallocate(sh%G_rad)
        if (allocated(sh%kappa_f))       deallocate(sh%kappa_f)
        if (allocated(sh%S_chem))        deallocate(sh%S_chem)
        if (allocated(sh%Y_CO))          deallocate(sh%Y_CO)
        if (allocated(sh%Y_CO2))         deallocate(sh%Y_CO2)
        if (allocated(sh%S_CO_src))      deallocate(sh%S_CO_src)
        if (allocated(sh%S_CO2_src))     deallocate(sh%S_CO2_src)
    end subroutine shared_destroy

    !---------------------------------------------------------------------------
    ! Initialize all fields for start of simulation
    !---------------------------------------------------------------------------
    subroutine fields_initialize_all(liq, gas, sol, slag, sh, m, cfg)
        type(phase_t), intent(inout) :: liq, gas
        type(solid_t), intent(inout) :: sol
        type(slag_t),  intent(inout) :: slag
        type(shared_t), intent(inout) :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend
        
        ! Determine loop bounds
        if (m%is_parallel) then
            istart = m%topo%istart
            iend = m%topo%iend
            jstart = m%topo%jstart
            jend = m%topo%jend
            kstart = m%topo%kstart
            kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) then
                        ! Inactive cells
                        liq%alpha(i,j,k) = 0.0_dp
                        gas%alpha(i,j,k) = 0.0_dp
                        sol%alpha_s(i,j,k) = 0.0_dp
                    else
                        ! Initially: all gas, scrap loaded via charge_scrap
                        gas%alpha(i,j,k) = 1.0_dp
                        liq%alpha(i,j,k) = 0.0_dp
                        sol%alpha_s(i,j,k) = 0.0_dp
                    end if

                    ! Slag: initially empty
                    slag%alpha_sl(i,j,k) = 0.0_dp
                    slag%m_sl(i,j,k)     = 0.0_dp
                    slag%T_sl(i,j,k)     = cfg%T_initial
                    slag%E_sl(i,j,k)     = 0.0_dp

                    ! Temperatures
                    liq%T(i,j,k) = cfg%T_initial
                    gas%T(i,j,k) = cfg%T_ambient
                    sol%T_s(i,j,k) = cfg%T_initial

                    ! Properties
                    liq%rho(i,j,k)    = cfg%rho_steel
                    liq%cp(i,j,k)     = cfg%cp_l
                    liq%kth(i,j,k)    = cfg%k_l
                    liq%mu(i,j,k)     = cfg%mu_l
                    liq%mu_eff(i,j,k) = cfg%mu_l

                    gas%rho(i,j,k)    = cfg%rho_gas
                    gas%cp(i,j,k)     = cfg%cp_gas
                    gas%kth(i,j,k)    = cfg%k_gas
                    gas%mu(i,j,k)     = cfg%mu_gas
                    gas%mu_eff(i,j,k) = cfg%mu_gas
                end do
            end do
        end do

        ! Turbulence initial conditions (including halos for simplicity)
        sh%tke = 1.0e-4_dp
        sh%eps = 1.0e-3_dp

        if (.not. m%is_parallel .or. m%topo%rank == 0) then
            print *, ' [FIELDS] All fields initialized'
        end if
    end subroutine fields_initialize_all

    !---------------------------------------------------------------------------
    ! Load scrap charge into furnace (bucket 1 or 2)
    ! MPI-aware: each process handles its local subdomain
    !---------------------------------------------------------------------------
    subroutine charge_scrap(sol, gas, m, cfg, bucket)
        type(solid_t), intent(inout)  :: sol
        type(phase_t), intent(inout)  :: gas
        type(mesh_t), intent(in)      :: m
        type(config_t), intent(in)    :: cfg
        integer, intent(in)           :: bucket

        integer :: i, j, k, k_global, n
        real(dp) :: vfrac, mass_layer, vol_needed, vol_acc
        real(dp) :: z_top, z_top_global
        real(dp) :: local_vol_add, global_vol_add
        integer :: layer_start, layer_end
        integer :: istart, iend, jstart, jend, kstart, kend
        integer :: nz_global
        
        ! Determine loop bounds
        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
            nz_global = m%topo%nz_global
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
            nz_global = m%nz
        end if

        ! Determine which layers belong to this bucket
        if (bucket == 1) then
            layer_start = 1
            layer_end   = cfg%n_layers_b1
        else
            layer_start = cfg%n_layers_b1 + 1
            layer_end   = cfg%n_layers_total
        end if

        ! Find starting z for charge (above existing material)
        ! In parallel: need global z_top
        z_top = 0.0_dp
        do k = kend, kstart, -1
            if (any(sol%alpha_s(istart:iend,jstart:jend,k) > 0.01_dp)) then
                z_top = m%zf(k)
                exit
            end if
        end do
        
        ! Global max z_top across all processes
        if (m%is_parallel) then
            call mpi_allreduce_max(z_top, z_top_global, m%topo)
            z_top = z_top_global
        end if
        
        if (z_top < cfg%H_bowl) z_top = cfg%H_bowl

        ! Find starting global k index
        ! m%zf_global should be used here, but we can just use m%zf(k) when it's in our range
        ! A simpler way: we just iterate over all possible global k
        ! Let's assume we can start from k_global=1
        k_global = 1
        
        ! Fill layers bottom-up globally
        do n = layer_start, layer_end
            vfrac = cfg%layer_vfrac(n)
            mass_layer = cfg%layer_mass(n)
            if (mass_layer <= 0.0_dp) cycle

            vol_needed = mass_layer / (cfg%rho_steel * vfrac)
            vol_acc = 0.0_dp

            ! Loop over global k
            do while (vol_acc < vol_needed .and. k_global <= nz_global)
                ! Skip if this global k is below z_top
                ! We need a safe way to check this. If we just let it run, 
                ! cells with m%zf < z_top shouldn't be filled.
                
                local_vol_add = 0.0_dp
                
                ! Check if global k is in our local domain
                ! Note: m%nz is global nz in serial, but in parallel it might be local
                ! Let's use the topo%kglobal_start to map k_global to local k
                k = -1
                if (m%is_parallel) then
                    if (k_global >= m%topo%kglobal_start .and. &
                        k_global < m%topo%kglobal_start + m%topo%kloc) then
                        k = k_global - m%topo%kglobal_start + 1
                    end if
                else
                    k = k_global
                end if
                
                if (k >= kstart .and. k <= kend) then
                    if (m%zf(k) > z_top) then
                        do j = jstart, jend
                            do i = istart, iend
                                if (m%cell_type(i,j,k) == 1) then
                                    sol%alpha_s(i,j,k) = vfrac
                                    sol%m_s(i,j,k) = cfg%rho_steel * vfrac * m%vol(i,j,k)
                                    sol%T_s(i,j,k) = cfg%T_initial
                                    ! Entalpía consistente con la función única
                                    ! (incluye latente si T_initial > T_solidus)
                                    sol%E_s(i,j,k) = sol%m_s(i,j,k) * &
                                        solid_enthalpy(cfg%T_initial, cfg)
                                    sol%layer_id(i,j,k) = n
                                    gas%alpha(i,j,k) = 1.0_dp - vfrac
                                end if
                            end do
                        end do
                        
                        ! Accumulate volume (local contribution)
                        local_vol_add = sum(m%vol(istart:iend,jstart:jend,k), &
                                           mask=(m%cell_type(istart:iend,jstart:jend,k)==1))
                    end if
                end if
                
                ! In parallel, need global sum
                if (m%is_parallel) then
                    call mpi_allreduce_sum(local_vol_add, global_vol_add, m%topo)
                    local_vol_add = global_vol_add
                end if
                vol_acc = vol_acc + local_vol_add
                
                k_global = k_global + 1
            end do
            ! No z_top bookkeeping needed between layers: k_global is not
            ! reset, so the next layer continues filling above this one
        end do

        if (.not. m%is_parallel .or. m%topo%rank == 0) then
            print '(A,I1,A,I3,A,I3)', ' [CHARGE] Bucket ', bucket, &
                  ' loaded, layers ', layer_start, '-', layer_end
        end if

    end subroutine charge_scrap

    !---------------------------------------------------------------------------
    ! Fill periodic theta halos in serial mode
    ! j=0  <- j=nth, j=-1 <- j=nth-1 (left halo)
    ! j=nth+1 <- j=1, j=nth+2 <- j=2 (right halo)
    !---------------------------------------------------------------------------
    subroutine fill_periodic_theta(field, nth)
        real(dp), intent(inout) :: field(-1:,-1:,-1:)
        integer,  intent(in)    :: nth

        field(:, -1,    :) = field(:, nth-1, :)
        field(:,  0,    :) = field(:, nth,   :)
        field(:, nth+1, :) = field(:, 1,     :)
        field(:, nth+2, :) = field(:, 2,     :)
    end subroutine fill_periodic_theta

end module mod_fields_3d
