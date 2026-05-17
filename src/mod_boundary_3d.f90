!===============================================================================
! mod_boundary_3d.f90 - Boundary conditions for 3D cylindrical mesh
!
! Handles:
!   - Inner radius (r_min): symmetry-like (dphi/dr=0)
!   - Outer radius (R_shell): wall (no-slip, adiabatic/Robin)
!   - Bottom (z=0 or bowl): wall
!   - Top (z=H): wall or outlet
!   - Theta: periodic (handled in solver via wraparound)
!   - Inactive cells: zeroed out
!===============================================================================
module mod_boundary_3d
    use mod_constants
    use mod_types_3d
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Apply BCs to a scalar field (temperature, species, etc.)
    ! Modifies coefficient arrays aW,aE,aS,aN,aB,aT,aP,Su
    ! for boundary cells. T_bc is the wall/inactive value.
    !---------------------------------------------------------------------------
    subroutine apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, T_bc)
        real(dp), intent(inout) :: aW(-1:,-1:,-1:), aE(-1:,-1:,-1:)
        real(dp), intent(inout) :: aS(-1:,-1:,-1:), aN(-1:,-1:,-1:)
        real(dp), intent(inout) :: aB(-1:,-1:,-1:), aT(-1:,-1:,-1:)
        real(dp), intent(inout) :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        real(dp), intent(in) :: T_bc

        integer :: i, j, k, nr, nth, nz

        nr  = m%nr
        nth = m%ntheta
        nz  = m%nz

        do k = 1, nz
            do j = 1, nth
                do i = 1, nr
                    ! Inactive cells: set phi = T_bc, zero all coefficients
                    if (m%cell_type(i,j,k) == 0) then
                        aW(i,j,k) = 0.0_dp
                        aE(i,j,k) = 0.0_dp
                        aS(i,j,k) = 0.0_dp
                        aN(i,j,k) = 0.0_dp
                        aB(i,j,k) = 0.0_dp
                        aT(i,j,k) = 0.0_dp
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = T_bc
                        cycle
                    end if

                    ! Inner radius (i=1): zero-gradient dphi/dr = 0
                    if (i == 1) then
                        aW(i,j,k) = 0.0_dp
                    end if

                    ! Outer radius (i=nr): adiabatic wall
                    if (i == nr) then
                        aE(i,j,k) = 0.0_dp
                    end if

                    ! Bottom (k=1): adiabatic
                    if (k == 1) then
                        aB(i,j,k) = 0.0_dp
                    end if

                    ! Top (k=nz): adiabatic
                    if (k == nz) then
                        aT(i,j,k) = 0.0_dp
                    end if

                    ! Neighbor is inactive cell: zero that coefficient
                    if (i > 1) then
                        if (m%cell_type(i-1,j,k) == 0) aW(i,j,k) = 0.0_dp
                    end if
                    if (i < nr) then
                        if (m%cell_type(i+1,j,k) == 0) aE(i,j,k) = 0.0_dp
                    end if
                    if (k > 1) then
                        if (m%cell_type(i,j,k-1) == 0) aB(i,j,k) = 0.0_dp
                    end if
                    if (k < nz) then
                        if (m%cell_type(i,j,k+1) == 0) aT(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do

    end subroutine apply_scalar_bc

    !---------------------------------------------------------------------------
    ! Apply momentum BCs (no-slip walls)
    ! Same structure, but velocity = 0 at walls
    !---------------------------------------------------------------------------
    subroutine apply_momentum_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, component)
        real(dp), intent(inout) :: aW(-1:,-1:,-1:), aE(-1:,-1:,-1:)
        real(dp), intent(inout) :: aS(-1:,-1:,-1:), aN(-1:,-1:,-1:)
        real(dp), intent(inout) :: aB(-1:,-1:,-1:), aT(-1:,-1:,-1:)
        real(dp), intent(inout) :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        character(len=*), intent(in) :: component

        integer :: i, j, k, nr, nth, nz

        nr  = m%nr
        nth = m%ntheta
        nz  = m%nz

        do k = 1, nz
            do j = 1, nth
                do i = 1, nr
                    if (m%cell_type(i,j,k) == 0) then
                        aW(i,j,k) = 0.0_dp; aE(i,j,k) = 0.0_dp
                        aS(i,j,k) = 0.0_dp; aN(i,j,k) = 0.0_dp
                        aB(i,j,k) = 0.0_dp; aT(i,j,k) = 0.0_dp
                        aP(i,j,k) = 1.0_dp; Su(i,j,k) = 0.0_dp
                        cycle
                    end if

                    ! Inner radius: u_r=0 (symmetry), du_th/dr=0, du_z/dr=0
                    if (i == 1) then
                        if (component == 'ur') then
                            aW(i,j,k) = 0.0_dp
                            aE(i,j,k) = 0.0_dp
                            aS(i,j,k) = 0.0_dp
                            aN(i,j,k) = 0.0_dp
                            aB(i,j,k) = 0.0_dp
                            aT(i,j,k) = 0.0_dp
                            aP(i,j,k) = 1.0_dp
                            Su(i,j,k) = 0.0_dp
                        else
                            aW(i,j,k) = 0.0_dp
                        end if
                    end if

                    ! Outer wall: no-slip v=0
                    if (i == nr) then
                        aE(i,j,k) = 0.0_dp
                        ! Large aP to enforce zero at wall-adjacent
                    end if

                    ! Bottom wall
                    if (k == 1) then
                        aB(i,j,k) = 0.0_dp
                    end if

                    ! Top wall
                    if (k == nz) then
                        aT(i,j,k) = 0.0_dp
                    end if

                    ! Neighbor inactive
                    if (i > 1) then
                        if (m%cell_type(i-1,j,k) == 0) aW(i,j,k) = 0.0_dp
                    end if
                    if (i < nr) then
                        if (m%cell_type(i+1,j,k) == 0) aE(i,j,k) = 0.0_dp
                    end if
                    if (k > 1) then
                        if (m%cell_type(i,j,k-1) == 0) aB(i,j,k) = 0.0_dp
                    end if
                    if (k < nz) then
                        if (m%cell_type(i,j,k+1) == 0) aT(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do

    end subroutine apply_momentum_bc

    !---------------------------------------------------------------------------
    ! Apply pressure BCs (Neumann everywhere, Dirichlet at outlets)
    !---------------------------------------------------------------------------
    subroutine apply_pressure_bc(aW, aE, aS, aN, aB, aT, aP, Su, m)
        real(dp), intent(inout) :: aW(-1:,-1:,-1:), aE(-1:,-1:,-1:)
        real(dp), intent(inout) :: aS(-1:,-1:,-1:), aN(-1:,-1:,-1:)
        real(dp), intent(inout) :: aB(-1:,-1:,-1:), aT(-1:,-1:,-1:)
        real(dp), intent(inout) :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m

        integer :: i, j, k, nr, nth, nz, e
        logical :: is_outlet

        nr  = m%nr
        nth = m%ntheta
        nz  = m%nz

        do k = 1, nz
            do j = 1, nth
                do i = 1, nr
                    if (m%cell_type(i,j,k) == 0) then
                        aW(i,j,k) = 0.0_dp; aE(i,j,k) = 0.0_dp
                        aS(i,j,k) = 0.0_dp; aN(i,j,k) = 0.0_dp
                        aB(i,j,k) = 0.0_dp; aT(i,j,k) = 0.0_dp
                        aP(i,j,k) = 1.0_dp; Su(i,j,k) = 0.0_dp
                        cycle
                    end if

                    ! Walls: Neumann dp/dn = 0
                    if (i == 1)  aW(i,j,k) = 0.0_dp
                    if (i == nr) aE(i,j,k) = 0.0_dp
                    if (k == 1)  aB(i,j,k) = 0.0_dp

                    ! Top: check if outlet (electrode holes)
                    if (k == nz) then
                        is_outlet = .false.
                        do e = 1, N_ELECTRODES
                            if (m%is_electrode(i,j,k,e)) is_outlet = .true.
                        end do
                        if (is_outlet) then
                            ! p' = 0 at outlet (Dirichlet)
                            aT(i,j,k) = 0.0_dp
                        else
                            aT(i,j,k) = 0.0_dp
                        end if
                    end if

                    ! Neighbor inactive
                    if (i > 1) then
                        if (m%cell_type(i-1,j,k) == 0) aW(i,j,k) = 0.0_dp
                    end if
                    if (i < nr) then
                        if (m%cell_type(i+1,j,k) == 0) aE(i,j,k) = 0.0_dp
                    end if
                    if (k > 1) then
                        if (m%cell_type(i,j,k-1) == 0) aB(i,j,k) = 0.0_dp
                    end if
                    if (k < nz) then
                        if (m%cell_type(i,j,k+1) == 0) aT(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do

    end subroutine apply_pressure_bc

end module mod_boundary_3d
