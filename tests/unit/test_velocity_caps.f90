!===============================================================================
! test_velocity_caps.f90 - Cotas de validez del modelo (sep-2026)
!
! U_LIQ_MAX (20 m/s, C2.2) y U_GAS_MAX (300 m/s, Bug 18) acotan la
! velocidad de cada fase a su dominio de validez: el acero del horno se
! mueve a O(1) m/s y la formulacion low-Mach del gas exige M << 1. Ambas
! preservan la DIRECCION (escalan el vector) y solo tocan lo que excede.
!
! Casos:
!   1. Gas por encima de la cota -> modulo exactamente U_GAS_MAX, direccion
!      intacta (producto cruz nulo con el original).
!   2. Gas por debajo -> bit-identico.
!   3. Liquido DISPERSO por encima de U_LIQ_MAX -> NO se toca (lleva la
!      velocidad de deriva, ya acotada a U_SETTLE_MAX).
!   4. Liquido CONTINUO por encima -> acotado a U_LIQ_MAX.
!===============================================================================
program test_velocity_caps
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_multiphase, only: cap_gas_velocity, cap_liquid_velocity
    use mod_workspace, only: ensure_workspace, ws_liq_cont, ws_liq_cont_valid
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(phase_t)  :: liq, gas
    type(solid_t)  :: sol
    type(slag_t)   :: slag
    type(shared_t) :: sh
    real(dp) :: v0(3), vmag, cross
    integer  :: ic, jc, kc, id, jd, kd
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 6; cfg%ntheta = 8; cfg%nz = 6
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call phase_allocate(liq, mesh); call phase_allocate(gas, mesh)
    call solid_allocate(sol, mesh); call slag_allocate(slag, mesh)
    call shared_allocate(sh, mesh)
    call fields_initialize_all(liq, gas, sol, slag, sh, mesh, cfg)
    call ensure_workspace(mesh)
    ok = .true.
    ic = 3; jc = 4; kc = 3        ! celda rapida
    id = 2; jd = 4; kd = 3        ! celda lenta

    ! ---- casos 1 y 2: gas ----
    gas%ur = 0.0_dp; gas%uth = 0.0_dp; gas%uz = 0.0_dp
    v0 = [900.0_dp, -1200.0_dp, 600.0_dp]      ! |v| = 1616 m/s
    gas%ur(ic,jc,kc) = v0(1); gas%uth(ic,jc,kc) = v0(2); gas%uz(ic,jc,kc) = v0(3)
    gas%ur(id,jd,kd) = 10.0_dp; gas%uth(id,jd,kd) = -5.0_dp; gas%uz(id,jd,kd) = 2.0_dp
    call cap_gas_velocity(gas, mesh)
    vmag = sqrt(gas%ur(ic,jc,kc)**2 + gas%uth(ic,jc,kc)**2 + gas%uz(ic,jc,kc)**2)
    if (abs(vmag - U_GAS_MAX) > 1.0e-10_dp) then
        print '(A,F12.5)', '   FAIL caso 1: |u_gas| tras la cota = ', vmag
        ok = .false.
    end if
    cross = abs(gas%uth(ic,jc,kc)*v0(3) - gas%uz(ic,jc,kc)*v0(2)) &
          + abs(gas%uz(ic,jc,kc)*v0(1) - gas%ur(ic,jc,kc)*v0(3)) &
          + abs(gas%ur(ic,jc,kc)*v0(2) - gas%uth(ic,jc,kc)*v0(1))
    if (cross > 1.0e-9_dp * U_GAS_MAX * sqrt(sum(v0**2))) then
        print '(A,ES10.3)', '   FAIL caso 1: la cota giro el vector, |cruz| = ', cross
        ok = .false.
    end if
    if (abs(gas%ur(id,jd,kd) - 10.0_dp) > 0.0_dp .or. &
        abs(gas%uth(id,jd,kd) + 5.0_dp) > 0.0_dp) then
        print '(A)', '   FAIL caso 2: la cota toco una celda por debajo del limite'
        ok = .false.
    end if

    ! ---- casos 3 y 4: liquido disperso vs continuo ----
    sol%alpha_s = 0.0_dp
    liq%alpha = 0.0_dp
    liq%alpha(ic,jc,kc) = 0.05_dp      ! DISPERSO (freeboard, < ALPHA_LIQ_CONT)
    liq%alpha(id,jd,kd) = 0.60_dp      ! CONTINUO
    ws_liq_cont = liq_continuous(liq%alpha, sol%alpha_s); ws_liq_cont_valid = .true.
    liq%ur = 0.0_dp; liq%uth = 0.0_dp; liq%uz = 0.0_dp
    liq%uz(ic,jc,kc) = -40.0_dp
    liq%uz(id,jd,kd) = -40.0_dp
    call cap_liquid_velocity(liq, mesh)
    if (abs(liq%uz(ic,jc,kc) + 40.0_dp) > 1.0e-12_dp) then
        print '(A,F10.4)', '   FAIL caso 3: el liquido disperso fue capado: ', liq%uz(ic,jc,kc)
        ok = .false.
    end if
    if (abs(abs(liq%uz(id,jd,kd)) - U_LIQ_MAX) > 1.0e-10_dp) then
        print '(A,F10.4)', '   FAIL caso 4: el liquido continuo no fue capado: ', liq%uz(id,jd,kd)
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_velocity_caps'
    else
        print '(A)', ' FAIL test_velocity_caps'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)
end program test_velocity_caps
