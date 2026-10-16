!===============================================================================
! test_gas_percolation.f90 - La percolacion del gas (F2.16) no depende del dt
! de la corrida para dt >= DT_MOB_REF (auditoria 8, M8-2; por debajo el
! juicio usa el dt real, auditoria 13).
!
! Columna (singleton MPI): capas 1-4 BOLSA de lecho seco (alpha_s 0.5,
! alpha_g 0.5); capa 5 SATURADA (alpha_s 0.5, alpha_l 0.485, gas de piso
! ALPHA_PORE_GAS 0.015, la via de F2.7); capas 6.. gas libre. Gas a 1850 K.
! El unico camino de la bolsa al freeboard es el gas de piso de la capa
! saturada, cuya movilidad (inercia frente a Ergun) cae cerca del umbral
! GAS_MOB_MIN. Con alpha_g rho_g/dt al dt de la corrida la capa cortaba el
! camino con dt >= ~6.5 ms y la bolsa quedaba pared (pocket_rise a 10 ms:
! sin subir, gas a 131 m/s). Exige: la bolsa percola, y la mascara es
! IDENTICA con dt = 2 ms y dt = 10 ms (solo celdas fluidas). Caso inverso: con
! la capa casi compacta (alpha_s 0.9, d_p 2 cm) la bolsa NO percola con ningun dt.
!===============================================================================
program test_gas_percolation
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_drag_ergun, only: compute_ergun_drag
    use mod_multiphase, only: gas_percolation_mask
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp), allocatable :: drag(:,:,:)
    logical, allocatable  :: perc2(:,:,:), perc10(:,:,:), reach(:,:,:), fluid(:,:,:)
    integer :: k, nr, nth, nz, npk
    logical :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 10
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    nr = mesh%nr; nth = mesh%ntheta; nz = mesh%nz
    ok = .true.

    sol%alpha_s = 0.0_dp; liq%alpha = 0.0_dp; gas%alpha = 1.0_dp
    do k = 1, 4
        sol%alpha_s(:,:,k) = 0.5_dp; gas%alpha(:,:,k) = 0.5_dp
    end do
    sol%alpha_s(:,:,5) = 0.5_dp
    liq%alpha(:,:,5) = 1.0_dp - 0.5_dp - ALPHA_PORE_GAS
    gas%alpha(:,:,5) = ALPHA_PORE_GAS
    gas%T = 1850.0_dp
    gas%rho = gas_eos(cfg%rho_gas, gas%T, 0.0_dp)
    gas%mu = 6.0e-5_dp
    gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
    where (mesh%cell_type == 0)
        sol%alpha_s = 0.0_dp; liq%alpha = 0.0_dp; gas%alpha = 0.0_dp
    end where

    allocate(drag, mold=gas%ur)
    allocate(perc2(-1:nr+2,-1:nth+2,-1:nz+2), perc10(-1:nr+2,-1:nth+2,-1:nz+2), &
             reach(-1:nr+2,-1:nth+2,-1:nz+2), fluid(-1:nr+2,-1:nth+2,-1:nz+2))
    fluid = .false.
    fluid(1:nr,1:nth,1:4) = mesh%cell_type(1:nr,1:nth,1:4) /= 0
    npk = count(fluid)
    call compute_ergun_drag(gas, sol, mesh, cfg, drag, alpha_held=liq%alpha)
    cfg%dt = 0.002_dp
    call gas_percolation_mask(gas, sol, mesh, cfg, drag, perc2, reach)
    cfg%dt = 0.010_dp
    call gas_percolation_mask(gas, sol, mesh, cfg, drag, perc10, reach)
    ! (solo celdas FLUIDAS: la mascara vale .true. en las inactivas)
    print '(A,3I6)', '   bolsa: celdas fluidas, percolan con 2 ms, con 10 ms: ', &
        npk, count(perc2 .and. fluid), count(perc10 .and. fluid)
    if (npk == 0 .or. count(perc2 .and. fluid) /= npk .or. count(perc10 .and. fluid) /= npk) then
        print '(A)', '   FAIL la bolsa no percola entera con algun dt (M8-2)'
        ok = .false.
    end if
    if (any((perc2(1:nr,1:nth,1:nz) .neqv. perc10(1:nr,1:nth,1:nz)) .and. &
            mesh%cell_type(1:nr,1:nth,1:nz) /= 0)) then
        print '(A)', '   FAIL la percolacion cambia con el dt de la corrida (M8-2)'
        ok = .false.
    end if

    ! caso inverso: capa 5 casi compacta (alpha_s 0.9) y particula de 2 cm: su
    ! gas de piso esta inmovilizado por Ergun (mob ~1e-3 << GAS_MOB_MIN) y la
    ! bolsa NO percola con ningun dt (0.5 ms ni 10 ms)
    sol%alpha_s(:,:,5) = 0.9_dp
    liq%alpha(:,:,5) = 1.0_dp - 0.9_dp - ALPHA_PORE_GAS
    gas%alpha(:,:,5) = ALPHA_PORE_GAS
    where (mesh%cell_type == 0)
        sol%alpha_s = 0.0_dp; liq%alpha = 0.0_dp; gas%alpha = 0.0_dp
    end where
    cfg%d_particle = 0.02_dp
    call compute_ergun_drag(gas, sol, mesh, cfg, drag, alpha_held=liq%alpha)
    cfg%dt = 0.0005_dp
    call gas_percolation_mask(gas, sol, mesh, cfg, drag, perc2, reach)
    cfg%dt = 0.010_dp
    call gas_percolation_mask(gas, sol, mesh, cfg, drag, perc10, reach)
    print '(A,2I6)', '   capa compacta: celdas de la bolsa que percolan (0.5 ms, 10 ms): ', &
        count(perc2 .and. fluid), count(perc10 .and. fluid)
    if (count(perc2 .and. fluid) /= 0 .or. count(perc10 .and. fluid) /= 0) then
        print '(A)', '   FAIL una capa compacta deja percolar la bolsa (el gas inmovil debe seguirlo)'
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_gas_percolation (la bolsa percola por el gas de piso; mascara independiente del dt >= 2 ms)'
    else
        print '(A)', ' FAIL test_gas_percolation'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_gas_percolation
