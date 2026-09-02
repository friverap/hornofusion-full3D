!===============================================================================
! test_cp_eff.f90 - Unit test del cp efectivo de fusión (mod_melting_3d)
!
! Verifica los tres tramos de effective_cp (Eq. 10 del paper):
!   T < T_solidus            -> cp_s
!   T_solidus <= T <= T_liq  -> cp_s + h_fusion/(T_liq - T_sol)
!   T > T_liquidus           -> cp_l
!
! C1.8 extenderá este test con la ida-vuelta E<->T de la función unificada.
!===============================================================================
program test_cp_eff
    use mod_constants
    use mod_types_3d
    use mod_config_3d, only: config_set_defaults
    use mod_melting_3d, only: effective_cp
    implicit none

    type(config_t) :: cfg
    real(dp) :: got, want
    logical  :: ok

    call config_set_defaults(cfg)
    ok = .true.

    got  = effective_cp(1000.0_dp, cfg)
    want = cfg%cp_s
    call check('tramo sólido', got, want, ok)

    got  = effective_cp(0.5_dp * (cfg%T_solidus + cfg%T_liquidus), cfg)
    want = cfg%cp_s + cfg%h_fusion / (cfg%T_liquidus - cfg%T_solidus)
    call check('tramo mushy', got, want, ok)

    got  = effective_cp(cfg%T_liquidus + 100.0_dp, cfg)
    want = cfg%cp_l
    call check('tramo líquido', got, want, ok)

    if (ok) then
        print '(A)', ' PASS test_cp_eff'
    else
        print '(A)', ' FAIL test_cp_eff'
        stop 1
    end if

contains

    subroutine check(label, got_v, want_v, ok_flag)
        character(len=*), intent(in) :: label
        real(dp), intent(in)         :: got_v, want_v
        logical, intent(inout)       :: ok_flag
        if (abs(got_v - want_v) > 1.0e-12_dp * max(abs(want_v), 1.0_dp)) then
            print '(A,A,A,ES14.6,A,ES14.6)', '   FAIL ', label, &
                ': got ', got_v, ' want ', want_v
            ok_flag = .false.
        end if
    end subroutine check

end program test_cp_eff
