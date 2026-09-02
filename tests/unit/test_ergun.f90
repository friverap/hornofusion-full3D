!===============================================================================
! test_ergun.f90 - Unit test del coeficiente de arrastre de Ergun
!
! Contrato C1.4: compute_ergun_drag devuelve el COEFICIENTE positivo
! coef = mu/K + C_F*rho*|v|/sqrt(K)  [kg/(m^3 s)] para tratamiento implícito
! en momentum (aP += coef*vol). Verificación contra cálculo independiente:
!   K   = d_p^2 * eps^3 / (150*(1-eps)^2)
!   C_F = 1.75 / (d_p * eps^3)
! Los arrays llevan halos (-1:n+2) como en producción (regla GFortran de
! cotas inferiores).
!===============================================================================
program test_ergun
    use mod_constants
    use mod_types_3d
    use mod_config_3d, only: config_set_defaults
    use mod_drag_ergun, only: compute_ergun_drag
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: m
    type(phase_t)  :: ph
    type(solid_t)  :: sol
    real(dp), allocatable :: coef(:,:,:)
    real(dp) :: eps, K, C_F, vmag, want
    logical  :: ok

    call config_set_defaults(cfg)   ! d_particle = 0.10 m

    m%nr = 1; m%ntheta = 1; m%nz = 1
    allocate(m%cell_type(-1:3,-1:3,-1:3)); m%cell_type = 1

    allocate(ph%mu(-1:3,-1:3,-1:3), ph%rho(-1:3,-1:3,-1:3))
    allocate(ph%ur(-1:3,-1:3,-1:3), ph%uth(-1:3,-1:3,-1:3), ph%uz(-1:3,-1:3,-1:3))
    ph%mu = 6.0e-3_dp; ph%rho = 7500.0_dp
    ph%ur = 0.1_dp; ph%uth = -0.05_dp; ph%uz = 0.2_dp

    allocate(sol%alpha_s(-1:3,-1:3,-1:3)); sol%alpha_s = 0.5_dp
    allocate(coef(-1:3,-1:3,-1:3))

    call compute_ergun_drag(ph, sol, m, cfg, coef)

    ! Cálculo independiente
    eps  = 0.5_dp
    K    = cfg%d_particle**2 * eps**3 / (150.0_dp * (1.0_dp - eps)**2)
    C_F  = 1.75_dp / (cfg%d_particle * eps**3)
    vmag = sqrt(0.1_dp**2 + 0.05_dp**2 + 0.2_dp**2)
    want = 6.0e-3_dp / K + C_F * 7500.0_dp * vmag / sqrt(K)

    ok = .true.
    if (abs(coef(1,1,1) - want) > 1.0e-9_dp * want) then
        print '(A,ES16.8,A,ES16.8)', '   FAIL coef: got ', coef(1,1,1), &
            ' want ', want
        ok = .false.
    end if
    if (coef(1,1,1) <= 0.0_dp) then
        print '(A)', '   FAIL coef debe ser > 0'
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_ergun'
    else
        print '(A)', ' FAIL test_ergun'
        stop 1
    end if
end program test_ergun
