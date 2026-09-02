!===============================================================================
! mod_mesh_3d.f90 - 3D structured cylindrical mesh (r, theta, z) for EAF
!
! Features:
!   - Geometric stretching in r and z
!   - Uniform spacing in theta (periodic)
!   - Bowl geometry via z_bowl(r) floor profile
!   - Cell type marking (fluid, wall, inactive)
!   - Electrode cell identification
!   - MPI parallelization: local subdomain with halo cells
!===============================================================================
module mod_mesh_3d
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology, only: mpi_exchange_halos_3d_int
    use mod_parallel_utils, only: gather_global_field, gather_global_field_int
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Generate parallel mesh with halos
    !---------------------------------------------------------------------------
    subroutine mesh_generate_parallel(m, cfg)
        type(mesh_t), intent(out)  :: m
        type(config_t), intent(in) :: cfg

        integer :: i, j, k, ig, jg, kg
        real(dp) :: r_min
        !integer :: nhalo
        
        ! Global dimensions
        integer :: nr_global, nth_global, nz_global
        
        ! Temporary global arrays
        real(dp), allocatable :: rf_global(:), thetaf_global(:), zf_global(:)
        
        ! Set parallel mode (only if nprocs > 1)
        m%is_parallel = (m%topo%nprocs > 1)
        
        ! Store global dimensions in topo (already set by mpi_init_topology)
        nr_global = m%topo%nr_global
        nth_global = m%topo%nth_global
        nz_global = m%topo%nz_global
        
        ! Local dimensions (mesh_t stores local sizes, not global)
        m%nr = m%topo%iloc
        m%ntheta = m%topo%jloc
        m%nz = m%topo%kloc
        m%ncells = m%nr * m%ntheta * m%nz  ! Local cells only
        
        ! Allocate 1D arrays with halos: -1:iloc+2 etc.
        allocate(m%r(-1:m%nr+2), m%theta(-1:m%ntheta+2), m%z(-1:m%nz+2))
        allocate(m%rf(-2:m%nr+2), m%thetaf(-2:m%ntheta+2), m%zf(-2:m%nz+2))
        allocate(m%dr(-1:m%nr+2), m%dtheta(-1:m%ntheta+2), m%dz(-1:m%nz+2))
        
        ! Allocate 3D arrays with halos
        allocate(m%vol(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%Ar(-2:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%Ath(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%Az(-1:m%nr+2, -1:m%ntheta+2, -2:m%nz+2))
        allocate(m%cell_type(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%z_bowl(-1:m%nr+2))
        allocate(m%is_electrode(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2, N_ELECTRODES))
        
        ! Generate global coordinate faces (only rank 0 needs this, but simpler to do all)
        allocate(rf_global(0:nr_global), thetaf_global(0:nth_global), &
                 zf_global(0:nz_global))
        
        r_min = R_AXIS_MIN
        call generate_stretched_faces(rf_global, nr_global, r_min, cfg%R_shell, cfg%stretch_r)
        
        do j = 0, nth_global
            thetaf_global(j) = TWO_PI * real(j, dp) / real(nth_global, dp)
        end do
        
        call generate_stretched_faces(zf_global, nz_global, 0.0_dp, cfg%H_total, cfg%stretch_z)
        
        ! Extract local portion of global faces (with halos)
        ! Radial: extract [iglobal_start-2 : iglobal_start+iloc+1]
        do i = -2, m%nr+2
            ig = m%topo%iglobal_start + i - 1
            ! Clamp to global bounds
            ig = max(0, min(nr_global, ig))
            m%rf(i) = rf_global(ig)
        end do
        
        ! Theta: coordenadas DESENROLLADAS (monótonas) también en los halos
        ! (hallazgo 3.7). El wrap anterior producía dtheta(0) < 0 y
        ! theta(0) ~ pi en la costura theta=0, corrompiendo los coeficientes
        ! de difusión y los gradientes azimutales en j=1 / j=ntheta. La malla
        ! azimutal es uniforme, así que la extensión lineal
        ! thetaf = 2*pi*jg/nth vale para cualquier jg entero (los valores de
        ! halo pueden salir de [0,2pi]: solo se usan en diferencias y en
        ! cos/sin, ambos correctos).
        do j = -2, m%ntheta+2
            jg = m%topo%jglobal_start + j - 1
            m%thetaf(j) = TWO_PI * real(jg, dp) / real(nth_global, dp)
        end do
        
        ! Axial: extract with clamping
        do k = -2, m%nz+2
            kg = m%topo%kglobal_start + k - 1
            kg = max(0, min(nz_global, kg))
            m%zf(k) = zf_global(kg)
        end do
        
        ! Compute cell centers and widths (including halos)
        do i = -1, m%nr+2
            m%dr(i) = m%rf(i) - m%rf(i-1)
            m%r(i) = 0.5_dp * (m%rf(i-1) + m%rf(i))
        end do
        
        do j = -1, m%ntheta+2
            m%dtheta(j) = m%thetaf(j) - m%thetaf(j-1)
            m%theta(j) = 0.5_dp * (m%thetaf(j-1) + m%thetaf(j))
        end do
        
        do k = -1, m%nz+2
            m%dz(k) = m%zf(k) - m%zf(k-1)
            m%z(k) = 0.5_dp * (m%zf(k-1) + m%zf(k))
        end do
        
        ! Compute metrics (including halos for safety in stencils)
        do k = -1, m%nz+2
            do j = -1, m%ntheta+2
                do i = -1, m%nr+2
                    m%vol(i,j,k) = 0.5_dp * (m%rf(i)**2 - m%rf(i-1)**2) &
                                   * m%dtheta(j) * m%dz(k)
                end do
            end do
        end do
        
        do k = -1, m%nz+2
            do j = -1, m%ntheta+2
                do i = -2, m%nr+2
                    m%Ar(i,j,k) = m%rf(i) * m%dtheta(j) * m%dz(k)
                end do
            end do
        end do
        
        do k = -1, m%nz+2
            do j = -1, m%ntheta+2
                do i = -1, m%nr+2
                    m%Ath(i,j,k) = m%dr(i) * m%dz(k)
                end do
            end do
        end do
        
        do k = -2, m%nz+2
            do j = -1, m%ntheta+2
                do i = -1, m%nr+2
                    m%Az(i,j,k) = 0.5_dp * (m%rf(i)**2 - m%rf(i-1)**2) * m%dtheta(j)
                end do
            end do
        end do
        
        ! Bowl profile
        do i = -1, m%nr+2
            if (m%r(i) <= cfg%R_bowl) then
                m%z_bowl(i) = cfg%H_bowl * (m%r(i) / cfg%R_bowl)**2
            else
                m%z_bowl(i) = cfg%H_bowl
            end if
        end do
        
        ! Mark cell types (including halos)
        m%cell_type = 1  ! Default: fluid
        do k = -1, m%nz+2
            do j = -1, m%ntheta+2
                do i = -1, m%nr+2
                    if (m%z(k) < m%z_bowl(i)) then
                        m%cell_type(i,j,k) = 0
                    end if
                    if (m%r(i) > cfg%R_shell) then
                        m%cell_type(i,j,k) = 0
                    end if
                end do
            end do
        end do
        
        ! Mark electrode cells (including halos)
        call mark_electrode_cells_parallel(m, cfg)
        
        ! Store global coords for HDF5 output (all ranks have rf/thetaf/zf_global here)
        allocate(m%r_global(nr_global), m%theta_global(nth_global), m%z_global(nz_global))
        do i = 1, nr_global
            m%r_global(i) = 0.5_dp * (rf_global(i-1) + rf_global(i))
        end do
        do j = 1, nth_global
            m%theta_global(j) = 0.5_dp * (thetaf_global(j-1) + thetaf_global(j))
        end do
        do k = 1, nz_global
            m%z_global(k) = 0.5_dp * (zf_global(k-1) + zf_global(k))
        end do

        ! Replicate global geometry on every rank: bitwise-identical inputs
        ! for decomposition-sensitive physics (arc heat, MC radiation)
        m%nr_g = nr_global; m%nth_g = nth_global; m%nz_g = nz_global
        allocate(m%rf_global(0:nr_global), m%zf_global(0:nz_global))
        m%rf_global = rf_global(0:nr_global)
        m%zf_global = zf_global(0:nz_global)
        allocate(m%vol_global(nr_global, nth_global, nz_global))
        allocate(m%cell_type_global(nr_global, nth_global, nz_global))
        call gather_global_field(m%vol, m%vol_global, m)
        call gather_global_field_int(m%cell_type, m%cell_type_global, m)

        ! Cleanup
        deallocate(rf_global, thetaf_global, zf_global)
        
        ! Report (rank 0 only)
        if (m%topo%rank == 0) then
            print '(A,I6,A,I6,A,I6,A,I10)', ' [MESH] Global cells: ', &
                  nr_global, ' x ', nth_global, ' x ', nz_global, ' = ', &
                  nr_global*nth_global*nz_global
        end if
        
        print '(A,I4,A,I6,A,I6,A,I6,A,I10)', ' [MESH] Rank ', m%topo%rank, &
              ' local: ', m%nr, ' x ', m%ntheta, ' x ', m%nz, ' = ', m%ncells
              
        ! Exchange cell_type halos
        call mpi_exchange_halos_3d_int(m%cell_type, m%topo)
        
    end subroutine mesh_generate_parallel

    !---------------------------------------------------------------------------
    ! Serial mesh generation (original)
    !---------------------------------------------------------------------------
    subroutine mesh_generate(m, cfg)
        type(mesh_t), intent(out)  :: m
        type(config_t), intent(in) :: cfg

        integer :: i, j, k
        real(dp) :: r_min

        m%nr     = cfg%nr
        m%ntheta = cfg%ntheta
        m%nz     = cfg%nz
        m%ncells = m%nr * m%ntheta * m%nz

        ! Allocate 1D coordinate arrays (with halos)
        allocate(m%r(-1:m%nr+2), m%theta(-1:m%ntheta+2), m%z(-1:m%nz+2))
        allocate(m%rf(-2:m%nr+2), m%thetaf(-2:m%ntheta+2), m%zf(-2:m%nz+2))
        allocate(m%dr(-1:m%nr+2), m%dtheta(-1:m%ntheta+2), m%dz(-1:m%nz+2))

        ! Allocate 3D metric arrays (with halos)
        allocate(m%vol(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%Ar(-2:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%Ath(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%Az(-1:m%nr+2, -1:m%ntheta+2, -2:m%nz+2))
        allocate(m%cell_type(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(m%z_bowl(-1:m%nr+2))
        allocate(m%is_electrode(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2, N_ELECTRODES))

        ! Radial faces: r_min (pole cell) to R_shell, with stretching
        r_min = R_AXIS_MIN
        call generate_stretched_faces(m%rf, m%nr, r_min, cfg%R_shell, cfg%stretch_r)

        ! Azimuthal faces: uniform 0 to 2*pi
        do j = 0, m%ntheta
            m%thetaf(j) = TWO_PI * real(j, dp) / real(m%ntheta, dp)
        end do

        ! Axial faces: 0 to H_total, with stretching
        call generate_stretched_faces(m%zf, m%nz, 0.0_dp, cfg%H_total, cfg%stretch_z)

        ! Cell centers and widths
        do i = 1, m%nr
            m%dr(i) = m%rf(i) - m%rf(i-1)
            m%r(i)  = 0.5_dp * (m%rf(i-1) + m%rf(i))
        end do
        do j = 1, m%ntheta
            m%dtheta(j) = m%thetaf(j) - m%thetaf(j-1)
            m%theta(j)  = 0.5_dp * (m%thetaf(j-1) + m%thetaf(j))
        end do
        do k = 1, m%nz
            m%dz(k) = m%zf(k) - m%zf(k-1)
            m%z(k)  = 0.5_dp * (m%zf(k-1) + m%zf(k))
        end do

        ! Cell volumes: V = 0.5*(rf(i)^2 - rf(i-1)^2) * dtheta * dz
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    m%vol(i,j,k) = 0.5_dp * (m%rf(i)**2 - m%rf(i-1)**2) &
                                   * m%dtheta(j) * m%dz(k)
                end do
            end do
        end do

        ! Radial face areas: A_r = rf(i) * dtheta * dz
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 0, m%nr
                    m%Ar(i,j,k) = m%rf(i) * m%dtheta(j) * m%dz(k)
                end do
            end do
        end do

        ! Azimuthal face areas: A_th = dr * dz
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    m%Ath(i,j,k) = m%dr(i) * m%dz(k)
                end do
            end do
        end do

        ! Axial face areas: A_z = 0.5*(rf(i)^2 - rf(i-1)^2) * dtheta
        do k = 0, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    m%Az(i,j,k) = 0.5_dp * (m%rf(i)**2 - m%rf(i-1)**2) * m%dtheta(j)
                end do
            end do
        end do

        ! Bowl geometry: parabolic profile z_bowl(r)
        call compute_bowl_profile(m, cfg)

        ! Mark cell types
        call mark_cell_types(m, cfg)

        ! Identify electrode cells
        call mark_electrode_cells(m, cfg)

        ! Global geometry mirrors (single rank: direct copies) so that the
        ! arc/MC physics uses one code path in serial and parallel
        m%nr_g = m%nr; m%nth_g = m%ntheta; m%nz_g = m%nz
        allocate(m%r_global(m%nr), m%theta_global(m%ntheta), m%z_global(m%nz))
        m%r_global     = m%r(1:m%nr)
        m%theta_global = m%theta(1:m%ntheta)
        m%z_global     = m%z(1:m%nz)
        allocate(m%rf_global(0:m%nr), m%zf_global(0:m%nz))
        m%rf_global = m%rf(0:m%nr)
        m%zf_global = m%zf(0:m%nz)
        allocate(m%vol_global(m%nr, m%ntheta, m%nz))
        allocate(m%cell_type_global(m%nr, m%ntheta, m%nz))
        m%vol_global       = m%vol(1:m%nr, 1:m%ntheta, 1:m%nz)
        m%cell_type_global = m%cell_type(1:m%nr, 1:m%ntheta, 1:m%nz)

        ! Report
        print '(A,I6,A,I6,A,I6,A,I10)', ' [MESH] Cells: ', m%nr, ' x ', &
              m%ntheta, ' x ', m%nz, ' = ', m%ncells
        print '(A,ES10.3,A,ES10.3,A,ES10.3)', ' [MESH] dr_min=', minval(m%dr), &
              ' dth=', m%dtheta(1)*180.0_dp/PI, 'deg  dz_min=', minval(m%dz)
        print '(A,I10)', ' [MESH] Active fluid cells: ', count(m%cell_type == 1)

    end subroutine mesh_generate

    !---------------------------------------------------------------------------
    ! Two-sided tanh stretching
    !---------------------------------------------------------------------------
    subroutine generate_stretched_faces(xf, n, x_min, x_max, stretch)
        real(dp), intent(out) :: xf(0:)
        integer, intent(in)   :: n
        real(dp), intent(in)  :: x_min, x_max, stretch

        integer :: i
        real(dp) :: L, xi, eta, s

        L = x_max - x_min
        xf(0) = x_min
        xf(n) = x_max

        if (abs(stretch - 1.0_dp) < 1.0e-10_dp) then
            do i = 1, n-1
                xf(i) = x_min + L * real(i, dp) / real(n, dp)
            end do
        else
            s = stretch
            do i = 1, n-1
                xi = real(i, dp) / real(n, dp)
                eta = 0.5_dp * (1.0_dp + tanh(s * (xi - 0.5_dp)) / tanh(0.5_dp * s))
                xf(i) = x_min + L * eta
            end do
        end if
    end subroutine generate_stretched_faces

    !---------------------------------------------------------------------------
    ! Bowl profile: parabolic z_bowl(r)
    ! z=0 at deepest point (center), z=H_bowl at r=R_bowl, z=0 for r>R_bowl
    ! Bowl bottom cell floor:
    !   if r <= R_bowl: z_floor = H_bowl * (1 - (r/R_bowl)^2)  [inverted parabola]
    !   else:           z_floor = 0 (flat bottom below shell)
    ! Coordinate system: z=0 at very bottom, z=H_bowl at shell floor level
    !---------------------------------------------------------------------------
    subroutine compute_bowl_profile(m, cfg)
        type(mesh_t), intent(inout) :: m
        type(config_t), intent(in)  :: cfg

        integer :: i
        real(dp) :: r_ratio

        do i = 1, m%nr
            if (m%r(i) <= cfg%R_bowl) then
                r_ratio = m%r(i) / cfg%R_bowl
                m%z_bowl(i) = cfg%H_bowl * r_ratio**2
            else
                m%z_bowl(i) = cfg%H_bowl
            end if
        end do
    end subroutine compute_bowl_profile

    !---------------------------------------------------------------------------
    ! Mark cell types based on geometry
    !---------------------------------------------------------------------------
    subroutine mark_cell_types(m, cfg)
        type(mesh_t), intent(inout) :: m
        type(config_t), intent(in)  :: cfg

        integer :: i, j, k

        m%cell_type = 1   ! Default: fluid

        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    ! Below bowl floor: inactive
                    if (m%z(k) < m%z_bowl(i)) then
                        m%cell_type(i,j,k) = 0
                    end if

                    ! Outside shell radius (shouldn't happen in cylindrical, but safety)
                    if (m%r(i) > cfg%R_shell) then
                        m%cell_type(i,j,k) = 0
                    end if
                end do
            end do
        end do
    end subroutine mark_cell_types

    !---------------------------------------------------------------------------
    ! Mark electrode cells (parallel version with halos)
    !---------------------------------------------------------------------------
    subroutine mark_electrode_cells_parallel(m, cfg)
        type(mesh_t), intent(inout) :: m
        type(config_t), intent(in)  :: cfg

        integer :: e, i, j, k
        real(dp) :: th_elec, x_elec, y_elec, x_cell, y_cell, dist

        m%is_electrode = .false.

        do e = 1, N_ELECTRODES
            th_elec = TWO_PI * real(e-1, dp) / real(N_ELECTRODES, dp)
            x_elec = cfg%R_pcd * cos(th_elec)
            y_elec = cfg%R_pcd * sin(th_elec)

            do k = -1, m%nz+2
                do j = -1, m%ntheta+2
                    do i = -1, m%nr+2
                        x_cell = m%r(i) * cos(m%theta(j))
                        y_cell = m%r(i) * sin(m%theta(j))
                        dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)

                        if (dist <= cfg%R_elec) then
                            m%is_electrode(i,j,k,e) = .true.
                        end if
                    end do
                end do
            end do
        end do
    end subroutine mark_electrode_cells_parallel

    !---------------------------------------------------------------------------
    ! Mark electrode cells at roof level
    ! 3 electrodes at theta = 0, 2pi/3, 4pi/3 on pitch circle R_pcd
    !---------------------------------------------------------------------------
    subroutine mark_electrode_cells(m, cfg)
        type(mesh_t), intent(inout) :: m
        type(config_t), intent(in)  :: cfg

        integer :: e, i, j, k
        real(dp) :: th_elec, x_elec, y_elec, x_cell, y_cell, dist

        m%is_electrode = .false.

        do e = 1, N_ELECTRODES
            th_elec = TWO_PI * real(e-1, dp) / real(N_ELECTRODES, dp)
            x_elec = cfg%R_pcd * cos(th_elec)
            y_elec = cfg%R_pcd * sin(th_elec)

            do k = 1, m%nz
                do j = 1, m%ntheta
                    do i = 1, m%nr
                        x_cell = m%r(i) * cos(m%theta(j))
                        y_cell = m%r(i) * sin(m%theta(j))
                        dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)

                        if (dist <= cfg%R_elec) then
                            m%is_electrode(i,j,k,e) = .true.
                        end if
                    end do
                end do
            end do
        end do

        print '(A,I8)', ' [MESH] Electrode cells per electrode (all z): ', &
              count(m%is_electrode(:,:,:,1))
    end subroutine mark_electrode_cells

    !---------------------------------------------------------------------------
    ! Deallocate
    !---------------------------------------------------------------------------
    subroutine mesh_destroy(m)
        type(mesh_t), intent(inout) :: m

        if (allocated(m%r))       deallocate(m%r)
        if (allocated(m%theta))   deallocate(m%theta)
        if (allocated(m%z))       deallocate(m%z)
        if (allocated(m%rf))      deallocate(m%rf)
        if (allocated(m%thetaf))  deallocate(m%thetaf)
        if (allocated(m%zf))      deallocate(m%zf)
        if (allocated(m%dr))      deallocate(m%dr)
        if (allocated(m%dtheta))  deallocate(m%dtheta)
        if (allocated(m%dz))      deallocate(m%dz)
        if (allocated(m%vol))     deallocate(m%vol)
        if (allocated(m%Ar))      deallocate(m%Ar)
        if (allocated(m%Ath))     deallocate(m%Ath)
        if (allocated(m%Az))      deallocate(m%Az)
        if (allocated(m%cell_type)) deallocate(m%cell_type)
        if (allocated(m%z_bowl))    deallocate(m%z_bowl)
        if (allocated(m%is_electrode)) deallocate(m%is_electrode)
        if (allocated(m%r_global))     deallocate(m%r_global)
        if (allocated(m%theta_global)) deallocate(m%theta_global)
        if (allocated(m%z_global))     deallocate(m%z_global)
        if (allocated(m%rf_global))        deallocate(m%rf_global)
        if (allocated(m%zf_global))        deallocate(m%zf_global)
        if (allocated(m%vol_global))       deallocate(m%vol_global)
        if (allocated(m%cell_type_global)) deallocate(m%cell_type_global)
    end subroutine mesh_destroy

end module mod_mesh_3d
