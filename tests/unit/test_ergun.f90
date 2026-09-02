!===============================================================================
! test_ergun.f90 - Unit test del arrastre de Ergun (mod_drag_ergun)
!
! Celda única con alpha_s = 0.5, d_p = 0.1 m, v = (0.1, -0.05, 0.2) m/s.
! Verifica S_drag = -(mu/K + C_F*rho*|v|/sqrt(K)) * u contra el cálculo
! independiente con las correlaciones de Ergun:
!   K   = d_p^2 * eps^3 / (150*(1-eps)^2)
!   C_F = 1.75 / (d_p * eps^3)
! Cambiará de contrato en C1.4 (drag implícito devuelve coeficiente).
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
    real(dp) :: Sr(1,1,1), Sth(1,1,1), Sz(1,1,1)
    real(dp) :: eps, K, C_F, vmag, coeff
    real(dp) :: want_r, want_th, want_z
    logical  :: ok

    call config_set_defaults(cfg)   ! d_particle = 0.10 m

    m%nr = 1; m%ntheta = 1; m%nz = 1
    allocate(m%cell_type(1,1,1)); m%cell_type = 1

    allocate(ph%mu(1,1,1), ph%rho(1,1,1))
    allocate(ph%ur(1,1,1), ph%uth(1,1,1), ph%uz(1,1,1))
    ph%mu = 6.0e-3_dp; ph%rho = 7500.0_dp
    ph%ur = 0.1_dp; ph%uth = -0.05_dp; ph%uz = 0.2_dp

    allocate(sol%alpha_s(1,1,1)); sol%alpha_s = 0.5_dp

    call compute_ergun_drag(ph, sol, m, cfg, Sr, Sth, Sz)

    ! Cálculo independiente
    eps   = 0.5_dp
    K     = cfg%d_particle**2 * eps**3 / (150.0_dp * (1.0_dp - eps)**2)
    C_F   = 1.75_dp / (cfg%d_particle * eps**3)
    vmag  = sqrt(0.1_dp**2 + 0.05_dp**2 + 0.2_dp**2)
    coeff = 6.0e-3_dp / K + C_F * 7500.0_dp * vmag / sqrt(K)
    want_r  = -coeff * 0.1_dp
    want_th = -coeff * (-0.05_dp)
    want_z  = -coeff * 0.2_dp

    ok = .true.
    call check('S_drag_r',  Sr(1,1,1),  want_r,  ok)
    call check('S_drag_th', Sth(1,1,1), want_th, ok)
    call check('S_drag_z',  Sz(1,1,1),  want_z,  ok)

    if (ok) then
        print '(A)', ' PASS test_ergun'
    else
        print '(A)', ' FAIL test_ergun'
        stop 1
    end if

contains

    subroutine check(label, got, want, ok_flag)
        character(len=*), intent(in) :: label
        real(dp), intent(in)         :: got, want
        logical, intent(inout)       :: ok_flag
        if (abs(got - want) > 1.0e-9_dp * abs(want)) then
            print '(A,A,A,ES16.8,A,ES16.8)', '   FAIL ', label, &
                ': got ', got, ' want ', want
            ok_flag = .false.
        end if
    end subroutine check

end program test_ergun
