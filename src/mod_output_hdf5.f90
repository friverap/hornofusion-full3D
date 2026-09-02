!===============================================================================
! mod_output_hdf5.f90 - Parallel HDF5 output using MPI-IO
!
! Replaces VTK serial output with HDF5 parallel collective writes
! Structure: /mesh, /fields, /metadata
!===============================================================================
module mod_output_hdf5
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use hdf5
    use mpi
    implicit none

    private
    public :: write_hdf5_parallel, write_monitor_line

contains

    !---------------------------------------------------------------------------
    ! Write complete HDF5 snapshot (mesh + all fields) in parallel
    !---------------------------------------------------------------------------
    subroutine write_hdf5_parallel(m, liq, gas, sol, slag, sh, step, time, output_dir)
        type(mesh_t), intent(in) :: m
        type(phase_t), intent(in) :: liq, gas
        type(solid_t), intent(in) :: sol
        type(slag_t),  intent(in) :: slag
        type(shared_t), intent(in) :: sh
        integer, intent(in) :: step
        real(dp), intent(in) :: time
        character(len=*), intent(in) :: output_dir
        
        character(len=512) :: filename
        integer(HID_T) :: file_id, plist_id, plist_xfer
        integer :: error, rank
        
        rank = 0
        if (m%is_parallel) rank = m%topo%rank
        
        ! Build filename
        write(filename, '(A,A,I8.8,A)') trim(output_dir), '/eaf3d_', step, '.h5'
        
        ! Initialize HDF5
        call h5open_f(error)
        call check_h5(error, 'h5open_f', rank)

        ! Create file access property list for MPI-IO
        call h5pcreate_f(H5P_FILE_ACCESS_F, plist_id, error)
        call check_h5(error, 'h5pcreate_f(file access)', rank)
        if (m%is_parallel) then
            call h5pset_fapl_mpio_f(plist_id, m%topo%comm_cart, MPI_INFO_NULL, error)
            call check_h5(error, 'h5pset_fapl_mpio_f', rank)
        end if

        ! Create file
        call h5fcreate_f(filename, H5F_ACC_TRUNC_F, file_id, error, access_prp=plist_id)
        call check_h5(error, 'h5fcreate_f: '//trim(filename), rank)
        call h5pclose_f(plist_id, error)

        ! Create transfer property list for collective I/O
        call h5pcreate_f(H5P_DATASET_XFER_F, plist_xfer, error)
        call check_h5(error, 'h5pcreate_f(xfer)', rank)
        if (m%is_parallel) then
            call h5pset_dxpl_mpio_f(plist_xfer, H5FD_MPIO_COLLECTIVE_F, error)
            call check_h5(error, 'h5pset_dxpl_mpio_f', rank)
        end if
        
        ! Write mesh coordinates
        call write_mesh_group(file_id, m)
        
        ! Write all field variables
        call write_fields_group(file_id, m, liq, gas, sol, slag, sh, plist_xfer)
        
        ! Write metadata (attributes)
        call write_metadata(file_id, m, step, time)
        
        ! Close
        call h5pclose_f(plist_xfer, error)
        call h5fclose_f(file_id, error)
        call check_h5(error, 'h5fclose_f: '//trim(filename), rank)
        call h5close_f(error)
        
        if (rank == 0) then
            print '(A,I8,A,F10.2,A,A)', ' [HDF5] Written step ', step, &
                  ' (t=', time, 's) -> ', trim(filename)
        end if
        
    end subroutine write_hdf5_parallel
    
    !---------------------------------------------------------------------------
    ! Write mesh coordinates (1D arrays: r, theta, z)
    !---------------------------------------------------------------------------
    subroutine write_mesh_group(file_id, m)
        integer(HID_T), intent(in) :: file_id
        type(mesh_t), intent(in) :: m

        integer(HID_T) :: group_id, dspace_id, dset_id
        integer(HSIZE_T) :: dims(1)
        integer :: error

        ! Create /mesh group (collective in parallel HDF5)
        call h5gcreate_f(file_id, '/mesh', group_id, error)

        if (m%is_parallel) then
            ! In parallel HDF5, dataset create/close are collective (all ranks must call).
            ! Only rank 0 writes the data (independent I/O); others skip h5dwrite_f.

            ! r coordinates
            dims(1) = m%topo%nr_global
            call h5screate_simple_f(1, dims, dspace_id, error)
            call h5dcreate_f(group_id, 'r', H5T_NATIVE_DOUBLE, dspace_id, dset_id, error)
            if (m%topo%rank == 0) then
                call h5dwrite_f(dset_id, H5T_NATIVE_DOUBLE, m%r_global, dims, error)
            end if
            call h5dclose_f(dset_id, error)
            call h5sclose_f(dspace_id, error)

            ! theta coordinates
            dims(1) = m%topo%nth_global
            call h5screate_simple_f(1, dims, dspace_id, error)
            call h5dcreate_f(group_id, 'theta', H5T_NATIVE_DOUBLE, dspace_id, dset_id, error)
            if (m%topo%rank == 0) then
                call h5dwrite_f(dset_id, H5T_NATIVE_DOUBLE, m%theta_global, dims, error)
            end if
            call h5dclose_f(dset_id, error)
            call h5sclose_f(dspace_id, error)

            ! z coordinates
            dims(1) = m%topo%nz_global
            call h5screate_simple_f(1, dims, dspace_id, error)
            call h5dcreate_f(group_id, 'z', H5T_NATIVE_DOUBLE, dspace_id, dset_id, error)
            if (m%topo%rank == 0) then
                call h5dwrite_f(dset_id, H5T_NATIVE_DOUBLE, m%z_global, dims, error)
            end if
            call h5dclose_f(dset_id, error)
            call h5sclose_f(dspace_id, error)
        else
            ! Serial: write directly
            dims(1) = m%nr
            call write_1d_dataset(group_id, 'r', m%r(1:m%nr), dims)

            dims(1) = m%ntheta
            call write_1d_dataset(group_id, 'theta', m%theta(1:m%ntheta), dims)

            dims(1) = m%nz
            call write_1d_dataset(group_id, 'z', m%z(1:m%nz), dims)
        end if

        call h5gclose_f(group_id, error)

    end subroutine write_mesh_group
    
    !---------------------------------------------------------------------------
    ! Write all field variables as 3D datasets
    !---------------------------------------------------------------------------
    subroutine write_fields_group(file_id, m, liq, gas, sol, slag, sh, plist_xfer)
        integer(HID_T), intent(in) :: file_id, plist_xfer
        type(mesh_t), intent(in) :: m
        type(phase_t), intent(in) :: liq, gas
        type(solid_t), intent(in) :: sol
        type(slag_t),  intent(in) :: slag
        type(shared_t), intent(in) :: sh
        
        integer(HID_T) :: group_id
        integer :: error
        
        ! Create /fields group
        call h5gcreate_f(file_id, '/fields', group_id, error)
        
        ! Write liquid phase
        call write_3d_field(group_id, 'T_liquid', liq%T, m, plist_xfer)
        call write_3d_field(group_id, 'alpha_liquid', liq%alpha, m, plist_xfer)
        call write_3d_field(group_id, 'velocity_r_liquid', liq%ur, m, plist_xfer)
        call write_3d_field(group_id, 'velocity_th_liquid', liq%uth, m, plist_xfer)
        call write_3d_field(group_id, 'velocity_z_liquid', liq%uz, m, plist_xfer)
        
        ! Write gas phase
        call write_3d_field(group_id, 'T_gas', gas%T, m, plist_xfer)
        call write_3d_field(group_id, 'alpha_gas', gas%alpha, m, plist_xfer)
        call write_3d_field(group_id, 'velocity_r_gas', gas%ur, m, plist_xfer)
        call write_3d_field(group_id, 'velocity_th_gas', gas%uth, m, plist_xfer)
        call write_3d_field(group_id, 'velocity_z_gas', gas%uz, m, plist_xfer)
        
        ! Write solid phase
        call write_3d_field(group_id, 'alpha_solid', sol%alpha_s, m, plist_xfer)
        call write_3d_field(group_id, 'T_solid', sol%T_s, m, plist_xfer)
        call write_3d_field(group_id, 'mass_solid', sol%m_s, m, plist_xfer)

        ! Write slag phase
        call write_3d_field(group_id, 'alpha_slag', slag%alpha_sl, m, plist_xfer)
        call write_3d_field(group_id, 'T_slag',     slag%T_sl,     m, plist_xfer)
        
        ! Write shared fields
        call write_3d_field(group_id, 'pressure', sh%p, m, plist_xfer)
        call write_3d_field(group_id, 'tke', sh%tke, m, plist_xfer)
        call write_3d_field(group_id, 'epsilon', sh%eps, m, plist_xfer)
        call write_3d_field(group_id, 'S_arc', sh%S_arc, m, plist_xfer)
        call write_3d_field(group_id, 'S_rad', sh%S_rad, m, plist_xfer)
        call write_3d_field(group_id, 'G_rad', sh%G_rad, m, plist_xfer)
        call write_3d_field(group_id, 'F_lorentz_r', sh%F_lorentz_r, m, plist_xfer)
        call write_3d_field(group_id, 'F_lorentz_th', sh%F_lorentz_th, m, plist_xfer)
        call write_3d_field(group_id, 'Y_O2',     sh%Y_O2,     m, plist_xfer)
        call write_3d_field(group_id, 'Y_CO',     sh%Y_CO,     m, plist_xfer)
        call write_3d_field(group_id, 'Y_CO2',    sh%Y_CO2,    m, plist_xfer)
        call write_3d_field(group_id, 'S_CO_src', sh%S_CO_src, m, plist_xfer)
        call write_3d_field(group_id, 'S_chem',   sh%S_chem,   m, plist_xfer)

        call h5gclose_f(group_id, error)
        
    end subroutine write_fields_group
    
    !---------------------------------------------------------------------------
    ! Write a single 3D field with parallel hyperslab
    !---------------------------------------------------------------------------
    subroutine write_3d_field(group_id, name, field, m, plist_xfer)
        integer(HID_T), intent(in) :: group_id, plist_xfer
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: field(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        
        integer(HID_T) :: dspace_global_id, dspace_local_id, dset_id
        integer(HSIZE_T) :: dims_global(3), dims_local(3), offset(3)
        integer :: error, istart, iend, jstart, jend, kstart, kend
        real(dp), allocatable :: field_local(:,:,:)
        
        if (m%is_parallel) then
            ! Global dimensions
            dims_global(1) = m%topo%nr_global
            dims_global(2) = m%topo%nth_global
            dims_global(3) = m%topo%nz_global
            
            ! Local dimensions (without halos)
            dims_local(1) = m%topo%iloc
            dims_local(2) = m%topo%jloc
            dims_local(3) = m%topo%kloc
            
            ! Offset in global array
            offset(1) = m%topo%iglobal_start - 1
            offset(2) = m%topo%jglobal_start - 1
            offset(3) = m%topo%kglobal_start - 1
            
            ! Extract local data (without halos)
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
            
            allocate(field_local(dims_local(1), dims_local(2), dims_local(3)))
            field_local = field(istart:iend, jstart:jend, kstart:kend)
            
            ! Create dataspaces
            call h5screate_simple_f(3, dims_global, dspace_global_id, error)
            call h5screate_simple_f(3, dims_local, dspace_local_id, error)
            
            ! Create dataset
            call h5dcreate_f(group_id, name, H5T_NATIVE_DOUBLE, &
                            dspace_global_id, dset_id, error)
            call check_h5(error, 'h5dcreate_f: '//name, m%topo%rank)

            ! Select hyperslab in file
            call h5sselect_hyperslab_f(dspace_global_id, H5S_SELECT_SET_F, &
                                       offset, dims_local, error)

            ! Write collectively
            call h5dwrite_f(dset_id, H5T_NATIVE_DOUBLE, field_local, dims_local, error, &
                           mem_space_id=dspace_local_id, file_space_id=dspace_global_id, &
                           xfer_prp=plist_xfer)
            call check_h5(error, 'h5dwrite_f: '//name, m%topo%rank)
            
            ! Close
            call h5sclose_f(dspace_local_id, error)
            call h5sclose_f(dspace_global_id, error)
            call h5dclose_f(dset_id, error)
            
            deallocate(field_local)
        else
            ! Serial: write entire array
            dims_global(1) = m%nr
            dims_global(2) = m%ntheta
            dims_global(3) = m%nz
            
            call h5screate_simple_f(3, dims_global, dspace_global_id, error)
            call h5dcreate_f(group_id, name, H5T_NATIVE_DOUBLE, &
                            dspace_global_id, dset_id, error)
            call h5dwrite_f(dset_id, H5T_NATIVE_DOUBLE, field(1:m%nr, 1:m%ntheta, 1:m%nz), &
                           dims_global, error)
            call h5dclose_f(dset_id, error)
            call h5sclose_f(dspace_global_id, error)
        end if
        
    end subroutine write_3d_field
    
    !---------------------------------------------------------------------------
    ! Write metadata as attributes
    !---------------------------------------------------------------------------
    subroutine write_metadata(file_id, m, step, time)
        integer(HID_T), intent(in) :: file_id
        type(mesh_t), intent(in) :: m
        integer, intent(in) :: step
        real(dp), intent(in) :: time
        
        integer(HID_T) :: group_id, aspace_id, attr_id
        integer(HSIZE_T) :: adims(1)
        integer :: error, nprocs
        
        nprocs = 1
        if (m%is_parallel) nprocs = m%topo%nprocs
        
        ! Create /metadata group
        call h5gcreate_f(file_id, '/metadata', group_id, error)
        
        ! Write scalar attributes
        adims(1) = 1
        call h5screate_simple_f(1, adims, aspace_id, error)
        
        ! Time
        call h5acreate_f(group_id, 'time', H5T_NATIVE_DOUBLE, aspace_id, attr_id, error)
        call h5awrite_f(attr_id, H5T_NATIVE_DOUBLE, time, adims, error)
        call h5aclose_f(attr_id, error)
        
        ! Step
        call h5acreate_f(group_id, 'step', H5T_NATIVE_INTEGER, aspace_id, attr_id, error)
        call h5awrite_f(attr_id, H5T_NATIVE_INTEGER, step, adims, error)
        call h5aclose_f(attr_id, error)
        
        ! Nprocs
        call h5acreate_f(group_id, 'nprocs', H5T_NATIVE_INTEGER, aspace_id, attr_id, error)
        call h5awrite_f(attr_id, H5T_NATIVE_INTEGER, nprocs, adims, error)
        call h5aclose_f(attr_id, error)
        
        call h5sclose_f(aspace_id, error)
        call h5gclose_f(group_id, error)
        
    end subroutine write_metadata
    
    !---------------------------------------------------------------------------
    ! Helper: write 1D dataset
    !---------------------------------------------------------------------------
    subroutine write_1d_dataset(group_id, name, data, dims)
        integer(HID_T), intent(in) :: group_id
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: data(:)
        integer(HSIZE_T), intent(in) :: dims(1)

        integer(HID_T) :: dspace_id, dset_id
        integer :: error
        
        call h5screate_simple_f(1, dims, dspace_id, error)
        call h5dcreate_f(group_id, name, H5T_NATIVE_DOUBLE, dspace_id, dset_id, error)
        call h5dwrite_f(dset_id, H5T_NATIVE_DOUBLE, data, dims, error)
        call h5dclose_f(dset_id, error)
        call h5sclose_f(dspace_id, error)
        
    end subroutine write_1d_dataset
    
    !---------------------------------------------------------------------------
    ! Write monitor line (appending to ASCII file)
    ! Only rank 0 writes
    !---------------------------------------------------------------------------
    subroutine write_monitor_line(m, step, time, conv, sol, output_dir)
        type(mesh_t), intent(in) :: m
        integer, intent(in) :: step
        real(dp), intent(in) :: time
        type(convergence_t), intent(in) :: conv
        type(solid_t), intent(in) :: sol
        character(len=*), intent(in) :: output_dir
        
        character(len=512) :: filename
        integer :: iu, ios
        real(dp) :: m_s_total, m_s_local
        logical :: file_exists
        
        ! Compute total solid mass — the reduction is collective, so ALL ranks
        ! must execute it before any rank-0-only early return
        if (m%is_parallel) then
            m_s_local = sum(sol%m_s(m%topo%istart:m%topo%iend, &
                                    m%topo%jstart:m%topo%jend, &
                                    m%topo%kstart:m%topo%kend))
            call mpi_allreduce_sum(m_s_local, m_s_total, m%topo)
        else
            m_s_total = sum(sol%m_s(1:m%nr, 1:m%ntheta, 1:m%nz))
        end if

        ! Only rank 0 writes the file
        if (m%is_parallel .and. m%topo%rank /= 0) return

        ! Open/create monitor file
        filename = trim(output_dir) // '/monitor.log'
        inquire(file=filename, exist=file_exists)
        
        open(newunit=iu, file=filename, status='unknown', position='append', iostat=ios)
        if (ios /= 0) then
            print *, 'ERROR: Cannot open monitor file: ', trim(filename)
            return
        end if
        
        ! Write header if new file
        if (.not. file_exists) then
            write(iu, '(A)') '# step  time[s]  m_s[kg]  res_cont  res_ur  res_energy  n_outer'
        end if
        
        ! Write data
        write(iu, '(I8,F12.2,ES14.6,4ES12.4,I6)') &
            step, time, m_s_total, conv%res_cont, conv%res_ur, conv%res_energy, conv%n_outer
        
        close(iu)

    end subroutine write_monitor_line

    !---------------------------------------------------------------------------
    ! Abort with a clear message if an HDF5 call failed
    !---------------------------------------------------------------------------
    subroutine check_h5(error, context, rank)
        integer, intent(in) :: error
        character(len=*), intent(in) :: context
        integer, intent(in) :: rank

        integer :: abort_err

        if (error < 0) then
            write(*,'(A,A,A,I0,A,I0)') '[HDF5] ERROR in ', trim(context), &
                  ', code=', error, ', rank=', rank
            call MPI_Abort(MPI_COMM_WORLD, 1, abort_err)
        end if
    end subroutine check_h5

end module mod_output_hdf5
