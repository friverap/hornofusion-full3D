!===============================================================================
! mod_output_3d.f90 - VTK output for 3D cylindrical mesh
!
! Writes VTK structured grid files in legacy ASCII format.
! Converts cylindrical (r,theta,z) to Cartesian (x,y,z) for visualization.
!===============================================================================
module mod_output_3d
    use mod_constants
    use mod_types_3d
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Write full 3D VTK file with all available fields
    !---------------------------------------------------------------------------
    subroutine write_vtk_3d(m, liq, gas, sol, shared, step, time, outdir)
        type(mesh_t), intent(in)    :: m
        type(phase_t), intent(in)   :: liq, gas
        type(solid_t), intent(in)   :: sol
        type(shared_t), intent(in)  :: shared
        integer, intent(in)         :: step
        real(dp), intent(in)        :: time
        character(len=*), intent(in) :: outdir

        character(len=512) :: fname
        integer :: iu, i, j, k, ios
        integer :: np, nc
        real(dp) :: x, y, zc

        np = (m%nr+1) * (m%ntheta+1) * (m%nz+1)
        nc = m%nr * m%ntheta * m%nz

        write(fname, '(A,A,I8.8,A)') trim(outdir), '/eaf3d_', step, '.vtk'

        open(newunit=iu, file=trim(fname), status='replace', iostat=ios)
        if (ios /= 0) then
            print '(A,A)', ' [OUTPUT] Cannot open: ', trim(fname)
            return
        end if

        ! Header
        write(iu, '(A)') '# vtk DataFile Version 3.0'
        write(iu, '(A,I8,A,ES12.5)') 'EAF 3D step=', step, ' time=', time
        write(iu, '(A)') 'ASCII'
        write(iu, '(A)') 'DATASET STRUCTURED_GRID'
        write(iu, '(A,3I8)') 'DIMENSIONS ', m%nr+1, m%ntheta+1, m%nz+1

        ! Points (node positions in Cartesian)
        write(iu, '(A,I12,A)') 'POINTS ', np, ' double'
        do k = 0, m%nz
            zc = m%zf(k)
            do j = 0, m%ntheta
                do i = 0, m%nr
                    x = m%rf(i) * cos(m%thetaf(j))
                    y = m%rf(i) * sin(m%thetaf(j))
                    write(iu, '(3ES16.8)') x, y, zc
                end do
            end do
        end do

        ! Cell data
        write(iu, '(A,I12)') 'CELL_DATA ', nc

        ! Liquid temperature
        write(iu, '(A)') 'SCALARS T_liquid double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') liq%T(i,j,k)
                end do
            end do
        end do

        ! Gas temperature
        write(iu, '(A)') 'SCALARS T_gas double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') gas%T(i,j,k)
                end do
            end do
        end do

        ! Solid temperature
        write(iu, '(A)') 'SCALARS T_solid double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') sol%T_s(i,j,k)
                end do
            end do
        end do

        ! Liquid volume fraction
        write(iu, '(A)') 'SCALARS alpha_liquid double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') liq%alpha(i,j,k)
                end do
            end do
        end do

        ! Gas volume fraction
        write(iu, '(A)') 'SCALARS alpha_gas double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') gas%alpha(i,j,k)
                end do
            end do
        end do

        ! Solid volume fraction
        write(iu, '(A)') 'SCALARS alpha_solid double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') sol%alpha_s(i,j,k)
                end do
            end do
        end do

        ! Pressure
        write(iu, '(A)') 'SCALARS pressure double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') shared%p(i,j,k)
                end do
            end do
        end do

        ! Cell type
        write(iu, '(A)') 'SCALARS cell_type int 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(I3)') m%cell_type(i,j,k)
                end do
            end do
        end do

        ! Liquid velocity (Cartesian components)
        write(iu, '(A)') 'VECTORS velocity_liquid double'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    x = liq%ur(i,j,k)*cos(m%theta(j)) - liq%uth(i,j,k)*sin(m%theta(j))
                    y = liq%ur(i,j,k)*sin(m%theta(j)) + liq%uth(i,j,k)*cos(m%theta(j))
                    zc = liq%uz(i,j,k)
                    write(iu, '(3ES16.8)') x, y, zc
                end do
            end do
        end do

        close(iu)

        if (mod(step, 500) == 0 .or. step <= 1) then
            print '(A,A)', ' [OUTPUT] Wrote: ', trim(fname)
        end if

    end subroutine write_vtk_3d

    !---------------------------------------------------------------------------
    ! Write mesh-only VTK (for verification)
    !---------------------------------------------------------------------------
    subroutine write_vtk_mesh(m, outdir)
        type(mesh_t), intent(in)    :: m
        character(len=*), intent(in) :: outdir

        character(len=512) :: fname
        integer :: iu, i, j, k, ios, np
        real(dp) :: x, y, zc

        np = (m%nr+1) * (m%ntheta+1) * (m%nz+1)

        write(fname, '(A,A)') trim(outdir), '/mesh_3d.vtk'
        open(newunit=iu, file=trim(fname), status='replace', iostat=ios)
        if (ios /= 0) return

        write(iu, '(A)') '# vtk DataFile Version 3.0'
        write(iu, '(A)') 'EAF 3D Mesh'
        write(iu, '(A)') 'ASCII'
        write(iu, '(A)') 'DATASET STRUCTURED_GRID'
        write(iu, '(A,3I8)') 'DIMENSIONS ', m%nr+1, m%ntheta+1, m%nz+1

        write(iu, '(A,I12,A)') 'POINTS ', np, ' double'
        do k = 0, m%nz
            zc = m%zf(k)
            do j = 0, m%ntheta
                do i = 0, m%nr
                    x = m%rf(i) * cos(m%thetaf(j))
                    y = m%rf(i) * sin(m%thetaf(j))
                    write(iu, '(3ES16.8)') x, y, zc
                end do
            end do
        end do

        ! Cell type field
        write(iu, '(A,I12)') 'CELL_DATA ', m%nr * m%ntheta * m%nz
        write(iu, '(A)') 'SCALARS cell_type int 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(I3)') m%cell_type(i,j,k)
                end do
            end do
        end do

        ! Bowl floor distance
        write(iu, '(A)') 'SCALARS z_bowl double 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    write(iu, '(ES16.8)') m%z_bowl(i)
                end do
            end do
        end do

        ! Electrode mask (combined)
        write(iu, '(A)') 'SCALARS electrode_id int 1'
        write(iu, '(A)') 'LOOKUP_TABLE default'
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    if (m%is_electrode(i,j,k,1)) then
                        write(iu, '(I3)') 1
                    else if (m%is_electrode(i,j,k,2)) then
                        write(iu, '(I3)') 2
                    else if (m%is_electrode(i,j,k,3)) then
                        write(iu, '(I3)') 3
                    else
                        write(iu, '(I3)') 0
                    end if
                end do
            end do
        end do

        close(iu)
        print '(A,A)', ' [OUTPUT] Mesh written: ', trim(fname)

    end subroutine write_vtk_mesh

    !---------------------------------------------------------------------------
    ! Console monitor
    !---------------------------------------------------------------------------
    subroutine print_monitor_3d(step, time, dt, conv, sol, m)
        integer, intent(in)            :: step
        real(dp), intent(in)           :: time, dt
        type(convergence_t), intent(in) :: conv
        type(solid_t), intent(in)      :: sol
        type(mesh_t), intent(in)       :: m

        real(dp) :: mass_solid
        integer :: i, j, k

        mass_solid = 0.0_dp
        do k = 1, m%nz
            do j = 1, m%ntheta
                do i = 1, m%nr
                    mass_solid = mass_solid + sol%m_s(i,j,k)
                end do
            end do
        end do

        print '(A,I8,A,F10.2,A,ES9.2,A,I3,A,ES9.2,A,ES9.2,A,F10.1)', &
              ' Step', step, ' t=', time, ' dt=', dt, &
              ' it=', conv%n_outer, &
              ' |cont|=', conv%res_cont, ' |E|=', conv%res_energy, &
              ' m_s=', mass_solid * 1.0e-3_dp

    end subroutine print_monitor_3d

end module mod_output_3d
