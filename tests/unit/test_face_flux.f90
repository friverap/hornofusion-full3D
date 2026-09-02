!===============================================================================
! test_face_flux.f90 - Telescopía de los flujos de cara (C2.2, hallazgo 3.8)
!
! Con campos suaves arbitrarios, la suma sobre TODAS las celdas activas de
! (Fe-Fw) + (Fn-Fs) + (Ft-Fb) debe anularse: las caras internas cancelan por
! pares (el flujo de la cara compartida es idéntico visto desde ambas
! celdas), las caras de pared son 0 (impermeables) y theta es periódica.
! Con los flujos de celda centrada anteriores esta suma NO se anulaba
! (creación/destrucción de masa).
!===============================================================================
program test_face_flux
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_face_flux
    use mod_fields_3d, only: fill_periodic_theta
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    real(dp), allocatable :: aq(:,:,:), rho(:,:,:)
    real(dp), allocatable :: ur(:,:,:), uth(:,:,:), uz(:,:,:)
    real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
    real(dp) :: net_sum, abs_sum, err
    integer  :: i, j, k
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 10; cfg%ntheta = 12; cfg%nz = 8
    cfg%stretch_r = 1.3_dp; cfg%stretch_z = 1.2_dp

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)

    allocate(aq(-1:cfg%nr+2, -1:cfg%ntheta+2, -1:cfg%nz+2))
    allocate(rho, mold=aq); allocate(ur, mold=aq)
    allocate(uth, mold=aq); allocate(uz, mold=aq)
    aq = 0.0_dp; rho = 0.0_dp; ur = 0.0_dp; uth = 0.0_dp; uz = 0.0_dp

    ! Campos suaves arbitrarios (deterministas, sin RNG)
    do k = 1, cfg%nz
        do j = 1, cfg%ntheta
            do i = 1, cfg%nr
                aq(i,j,k)  = 0.3_dp + 0.2_dp * sin(0.5_dp*i) * cos(0.4_dp*k)
                rho(i,j,k) = 1000.0_dp + 200.0_dp * cos(0.3_dp*i + 0.2_dp*j)
                ur(i,j,k)  = 0.5_dp * sin(0.7_dp*i + 0.3_dp*j + 0.2_dp*k)
                uth(i,j,k) = 0.4_dp * cos(0.2_dp*i - 0.5_dp*j)
                uz(i,j,k)  = 0.6_dp * sin(0.3_dp*j + 0.6_dp*k)
            end do
        end do
    end do
    ! Halos periódicos en theta (serial)
    call fill_periodic_theta(aq, cfg%ntheta)
    call fill_periodic_theta(rho, cfg%ntheta)
    call fill_periodic_theta(ur, cfg%ntheta)
    call fill_periodic_theta(uth, cfg%ntheta)
    call fill_periodic_theta(uz, cfg%ntheta)

    net_sum = 0.0_dp; abs_sum = 0.0_dp
    do k = 1, cfg%nz
        do j = 1, cfg%ntheta
            do i = 1, cfg%nr
                if (mesh%cell_type(i,j,k) == 0) cycle
                call face_mass_fluxes(aq, rho, ur, uth, uz, mesh, i, j, k, &
                                      Fw, Fe, Fs, Fn, Fb, Ft)
                net_sum = net_sum + (Fe - Fw) + (Fn - Fs) + (Ft - Fb)
                abs_sum = abs_sum + abs(Fe) + abs(Fw) + abs(Fn) + abs(Fs) &
                                  + abs(Ft) + abs(Fb)
            end do
        end do
    end do

    call mpi_finalize_topology(mesh%topo)

    err = abs(net_sum) / max(abs_sum, SMALL)
    ok = err < 1.0e-13_dp
    if (ok) then
        print '(A,ES10.3)', ' PASS test_face_flux  telescopía err = ', err
    else
        print '(A,ES10.3)', ' FAIL test_face_flux  telescopía err = ', err
        stop 1
    end if
end program test_face_flux
