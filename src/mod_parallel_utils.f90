!===============================================================================
! mod_parallel_utils.f90 - Utility functions for parallel/serial compatibility
!
! Provides helpers to get loop bounds consistently across all physics modules
!===============================================================================
module mod_parallel_utils
    use mod_constants
    use mod_types_3d
    use mpi
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Get loop bounds for a given mesh (parallel or serial)
    !---------------------------------------------------------------------------
    subroutine get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        type(mesh_t), intent(in) :: m
        integer, intent(out) :: istart, iend, jstart, jend, kstart, kend
        
        if (m%is_parallel) then
            istart = m%topo%istart
            iend = m%topo%iend
            jstart = m%topo%jstart
            jend = m%topo%jend
            kstart = m%topo%kstart
            kend = m%topo%kend
        else
            istart = 1
            iend = m%nr
            jstart = 1
            jend = m%ntheta
            kstart = 1
            kend = m%nz
        end if
    end subroutine get_loop_bounds
    
    !---------------------------------------------------------------------------
    ! Check if periodic in theta
    !---------------------------------------------------------------------------
    function is_periodic_theta(m) result(periodic)
        type(mesh_t), intent(in) :: m
        logical :: periodic
        
        if (m%is_parallel) then
            periodic = m%topo%periodic_theta
        else
            periodic = .true.  ! Default for serial
        end if
    end function is_periodic_theta
    
    !---------------------------------------------------------------------------
    ! Print only from rank 0 (or always in serial)
    !---------------------------------------------------------------------------
    function should_print(m) result(do_print)
        type(mesh_t), intent(in) :: m
        logical :: do_print

        if (m%is_parallel) then
            do_print = (m%topo%rank == 0)
        else
            do_print = .true.
        end if
    end function should_print

    !---------------------------------------------------------------------------
    ! Assemble the global copy of a local field on every rank.
    ! Each global cell has exactly ONE owner contributing a nonzero value, so
    ! the SUM reduction over disjoint contributions is bitwise exact.
    !---------------------------------------------------------------------------
    subroutine gather_global_field(local, global, m)
        real(dp), intent(in)    :: local(-1:,-1:,-1:)
        real(dp), intent(inout) :: global(:,:,:)
        type(mesh_t), intent(in) :: m

        integer :: ierr, i0, j0, k0

        if (m%is_parallel) then
            global = 0.0_dp
            i0 = m%topo%iglobal_start
            j0 = m%topo%jglobal_start
            k0 = m%topo%kglobal_start
            global(i0:i0+m%topo%iloc-1, j0:j0+m%topo%jloc-1, k0:k0+m%topo%kloc-1) = &
                local(1:m%topo%iloc, 1:m%topo%jloc, 1:m%topo%kloc)
            call MPI_Allreduce(MPI_IN_PLACE, global, size(global), &
                               MPI_DOUBLE_PRECISION, MPI_SUM, m%topo%comm_cart, ierr)
        else
            global = local(1:m%nr, 1:m%ntheta, 1:m%nz)
        end if
    end subroutine gather_global_field

    !---------------------------------------------------------------------------
    ! Same as gather_global_field for an integer field
    !---------------------------------------------------------------------------
    subroutine gather_global_field_int(local, global, m)
        integer, intent(in)     :: local(-1:,-1:,-1:)
        integer, intent(inout)  :: global(:,:,:)
        type(mesh_t), intent(in) :: m

        integer :: ierr, i0, j0, k0

        if (m%is_parallel) then
            global = 0
            i0 = m%topo%iglobal_start
            j0 = m%topo%jglobal_start
            k0 = m%topo%kglobal_start
            global(i0:i0+m%topo%iloc-1, j0:j0+m%topo%jloc-1, k0:k0+m%topo%kloc-1) = &
                local(1:m%topo%iloc, 1:m%topo%jloc, 1:m%topo%kloc)
            call MPI_Allreduce(MPI_IN_PLACE, global, size(global), &
                               MPI_INTEGER, MPI_SUM, m%topo%comm_cart, ierr)
        else
            global = local(1:m%nr, 1:m%ntheta, 1:m%nz)
        end if
    end subroutine gather_global_field_int

    !---------------------------------------------------------------------------
    ! Map a global cell index to local indices; owned = the cell lives in this
    ! rank's interior. In serial, mapping is the identity and owned is true.
    !---------------------------------------------------------------------------
    subroutine global_to_local(m, ig, jg, kg, il, jl, kl, owned)
        type(mesh_t), intent(in) :: m
        integer, intent(in)  :: ig, jg, kg
        integer, intent(out) :: il, jl, kl
        logical, intent(out) :: owned

        if (m%is_parallel) then
            il = ig - m%topo%iglobal_start + 1
            jl = jg - m%topo%jglobal_start + 1
            kl = kg - m%topo%kglobal_start + 1
            owned = (il >= 1 .and. il <= m%topo%iloc .and. &
                     jl >= 1 .and. jl <= m%topo%jloc .and. &
                     kl >= 1 .and. kl <= m%topo%kloc)
        else
            il = ig; jl = jg; kl = kg
            owned = .true.
        end if
    end subroutine global_to_local

end module mod_parallel_utils
