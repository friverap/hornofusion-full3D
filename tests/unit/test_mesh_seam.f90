!===============================================================================
! test_mesh_seam.f90 - Métrica azimutal en la costura periódica theta=0
!
! Detecta el hallazgo 3.7: el wrap de coordenadas en mod_mesh_3d deja
! dtheta(0) < 0 y centros theta no monótonos en los halos de la costura, lo
! que corrompe difusión y gradientes azimutales en j=1 / j=ntheta.
!
! Invariantes (deben valer también en los HALOS):
!   - dtheta(j) > 0 para j = -1 .. ntheta+2
!   - theta(j) estrictamente creciente para j = -1 .. ntheta+2
!
! XFAIL hasta C1.3 (ver tests/xfail.list).
!===============================================================================
program test_mesh_seam
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    integer :: j
    logical :: ok

    call config_set_defaults(cfg)
    cfg%nr = 10; cfg%ntheta = 12; cfg%nz = 8

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)

    ok = .true.

    do j = -1, mesh%ntheta + 2
        if (mesh%dtheta(j) <= 0.0_dp) then
            print '(A,I3,A,ES12.4)', '   FAIL dtheta(', j, ') = ', mesh%dtheta(j)
            ok = .false.
        end if
    end do

    do j = 0, mesh%ntheta + 2
        if (mesh%theta(j) <= mesh%theta(j-1)) then
            print '(A,I3,A,ES12.4,A,ES12.4)', '   FAIL theta no monótona en j=', &
                j, ': ', mesh%theta(j-1), ' -> ', mesh%theta(j)
            ok = .false.
        end if
    end do

    call mpi_finalize_topology(mesh%topo)

    if (ok) then
        print '(A)', ' PASS test_mesh_seam'
    else
        print '(A)', ' FAIL test_mesh_seam'
        stop 1
    end if
end program test_mesh_seam
