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
    use mod_melting_3d, only: effective_cp, solid_enthalpy, &
                              solid_T_from_enthalpy, liquid_datum_offset
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

    ! Ida-vuelta E<->T de la función de entalpía única (C1.8)
    call roundtrip(500.0_dp, ok)
    call roundtrip(cfg%T_solidus - 1.0_dp, ok)
    call roundtrip(0.5_dp * (cfg%T_solidus + cfg%T_liquidus), ok)
    call roundtrip(cfg%T_liquidus + 50.0_dp, ok)
    ! Continuidad de e_s(T) en los quiebres (tolerancia: el salto de un
    ! branch mal cosido sería ~h_fusion ~ 2.5e5 J/kg; 1 J/kg lo detecta)
    call check_atol('e continua en T_sol', &
        solid_enthalpy(cfg%T_solidus - 1e-9_dp, cfg), &
        solid_enthalpy(cfg%T_solidus + 1e-9_dp, cfg), 1.0_dp, ok)
    call check_atol('e continua en T_liq', &
        solid_enthalpy(cfg%T_liquidus - 1e-9_dp, cfg), &
        solid_enthalpy(cfg%T_liquidus + 1e-9_dp, cfg), 1.0_dp, ok)
    ! Conservación del handoff: e_l(T) = e_s(T) para T >= T_liquidus
    call check('e_l = e_s sobre liquidus', &
        cfg%cp_l * 1815.0_dp + liquid_datum_offset(cfg), &
        solid_enthalpy(1815.0_dp, cfg), ok)

    if (ok) then
        print '(A)', ' PASS test_cp_eff'
    else
        print '(A)', ' FAIL test_cp_eff'
        stop 1
    end if

contains

    subroutine check_atol(label, got_v, want_v, atol, ok_flag)
        character(len=*), intent(in) :: label
        real(dp), intent(in)         :: got_v, want_v, atol
        logical, intent(inout)       :: ok_flag
        if (abs(got_v - want_v) > atol) then
            print '(A,A,A,ES14.6,A,ES14.6)', '   FAIL ', label, &
                ': got ', got_v, ' want ', want_v
            ok_flag = .false.
        end if
    end subroutine check_atol

    subroutine roundtrip(T, ok_flag)
        real(dp), intent(in)   :: T
        logical, intent(inout) :: ok_flag
        real(dp) :: T_back
        T_back = solid_T_from_enthalpy(solid_enthalpy(T, cfg), cfg)
        if (abs(T_back - T) > 1.0e-9_dp * T) then
            print '(A,F8.1,A,F12.4)', '   FAIL roundtrip E<->T en T=', T, &
                ': volvió ', T_back
            ok_flag = .false.
        end if
    end subroutine roundtrip

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
