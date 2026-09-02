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
        logical :: at_rmin, at_rmax, at_zmin, at_zmax

        nr  = m%nr
        nth = m%ntheta
        nz  = m%nz
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

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
                    if (i == 1 .and. at_rmin) then
                        aW(i,j,k) = 0.0_dp
                    end if

                    ! Outer radius (i=nr): adiabatic wall
                    if (i == nr .and. at_rmax) then
                        aE(i,j,k) = 0.0_dp
                    end if

                    ! Bottom (k=1): adiabatic
                    if (k == 1 .and. at_zmin) then
                        aB(i,j,k) = 0.0_dp
                    end if

                    ! Top (k=nz): adiabatic
                    if (k == nz .and. at_zmax) then
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
        logical :: at_rmin, at_rmax, at_zmin, at_zmax

        nr  = m%nr
        nth = m%ntheta
        nz  = m%nz
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

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
                    if (i == 1 .and. at_rmin) then
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
                    if (i == nr .and. at_rmax) then
                        aE(i,j,k) = 0.0_dp
                        ! Large aP to enforce zero at wall-adjacent
                    end if

                    ! Bottom wall
                    if (k == 1 .and. at_zmin) then
                        aB(i,j,k) = 0.0_dp
                    end if

                    ! Top wall
                    if (k == nz .and. at_zmax) then
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
        logical :: at_rmin, at_rmax, at_zmin, at_zmax
        logical, allocatable :: out_mask(:,:,:)

        nr  = m%nr
        nth = m%ntheta
        nz  = m%nz
        call physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)

        ! Máscara de celdas de salida (Dirichlet pp=0) para plegar los
        ! enlaces de sus vecinas y mantener la matriz SIMÉTRICA (requisito
        ! del CG; el valor 0 no aporta a Su, así que el plegado es exacto)
        allocate(out_mask(-1:nr+2, -1:nth+2, -1:nz+2))
        ! Incluye HALOS: is_electrode está marcado también en halos, y sin
        ! esto el plegado Dirichlet se saltaba a los vecinos de salidas al
        ! otro lado de una costura de rank (o de la costura periódica
        ! theta=0 en serial) — asimetría medible del plegado.
        out_mask = .false.
        if (at_zmax) then
            do j = -1, nth+2
                do i = -1, nr+2
                    do e = 1, N_ELECTRODES
                        if (m%is_electrode(i,j,nz,e)) out_mask(i,j,nz) = .true.
                    end do
                end do
            end do
        end if

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
                    if (i == 1 .and. at_rmin)  aW(i,j,k) = 0.0_dp
                    if (i == nr .and. at_rmax) aE(i,j,k) = 0.0_dp
                    if (k == 1 .and. at_zmin)  aB(i,j,k) = 0.0_dp

                    ! Top: check if outlet (electrode holes)
                    if (k == nz .and. at_zmax) then
                        is_outlet = out_mask(i,j,k)
                        if (is_outlet) then
                            ! Dirichlet p' = 0 at outlet: fix the cell value,
                            ! which also anchors the pressure level
                            aW(i,j,k) = 0.0_dp; aE(i,j,k) = 0.0_dp
                            aS(i,j,k) = 0.0_dp; aN(i,j,k) = 0.0_dp
                            aB(i,j,k) = 0.0_dp; aT(i,j,k) = 0.0_dp
                            aP(i,j,k) = 1.0_dp; Su(i,j,k) = 0.0_dp
                            cycle
                        else
                            ! Wall: Neumann dp'/dn = 0
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

                    ! Plegado Dirichlet: enlaces hacia celdas de salida a 0
                    ! (pp=0 allí; aP conserva el término -> exacto y simétrico)
                    if (out_mask(i-1,j,k)) aW(i,j,k) = 0.0_dp
                    if (out_mask(i+1,j,k)) aE(i,j,k) = 0.0_dp
                    if (out_mask(i,j-1,k)) aS(i,j,k) = 0.0_dp
                    if (out_mask(i,j+1,k)) aN(i,j,k) = 0.0_dp
                    if (out_mask(i,j,k-1)) aB(i,j,k) = 0.0_dp
                    if (out_mask(i,j,k+1)) aT(i,j,k) = 0.0_dp
                end do
            end do
        end do

        deallocate(out_mask)

    end subroutine apply_pressure_bc

    !---------------------------------------------------------------------------
    ! Determine which faces of the local block are PHYSICAL boundaries.
    ! In parallel, i==1 / i==nr (local indices) may be internal rank-to-rank
    ! interfaces where no wall BC must be applied (halos carry neighbor data).
    !---------------------------------------------------------------------------
    subroutine physical_boundary_flags(m, at_rmin, at_rmax, at_zmin, at_zmax)
        type(mesh_t), intent(in) :: m
        logical, intent(out) :: at_rmin, at_rmax, at_zmin, at_zmax

        if (m%is_parallel) then
            at_rmin = (m%topo%coords(1) == 0)
            at_rmax = (m%topo%coords(1) == m%topo%npr - 1)
            at_zmin = (m%topo%coords(3) == 0)
            at_zmax = (m%topo%coords(3) == m%topo%npz - 1)
        else
            at_rmin = .true.
            at_rmax = .true.
            at_zmin = .true.
            at_zmax = .true.
        end if
    end subroutine physical_boundary_flags

end module mod_boundary_3d
