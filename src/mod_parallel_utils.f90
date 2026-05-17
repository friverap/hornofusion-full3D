!===============================================================================
! mod_parallel_utils.f90 - Utility functions for parallel/serial compatibility
!
! Provides helpers to get loop bounds consistently across all physics modules
!===============================================================================
module mod_parallel_utils
    use mod_constants
    use mod_types_3d
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

end module mod_parallel_utils
