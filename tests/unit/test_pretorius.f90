!===============================================================================
! test_pretorius.f90 - Ventana de espuma (E2.5)
!
! Propiedades que la parametrización debe cumplir (Pretorius & Carlisle):
!   1. Máximo dentro de la ventana: xi(2.2, 0.18, 1823) > 0.8 * XI_MAX
!   2. FeO alto mata la espuma: xi(2.2, 0.33, 1823) < 0.1 * xi_ventana
!      (el caso FCEL02 de la Radiografía: mediana FeO 33%)
!   3. B2 bajo mata la espuma: xi(1.5, 0.18, 1823) < 0.15 * xi_ventana
!   4. Monotonía en B2 en el tramo 1.5 -> 2.3 (creciente)
!   5. Monotonía decreciente en T por encima de la referencia
!   6. xi >= 0 siempre y acotado por XI_MAX * 2 (clamp de f_T)
!===============================================================================
program test_pretorius
    use mod_constants
    use mod_foam
    implicit none

    real(dp) :: xi_win, xi, xi_prev, b2, t
    logical :: ok
    integer :: n

    ok = .true.
    xi_win = xi_pretorius(2.2_dp, 0.18_dp, 1823.0_dp)

    if (xi_win < 0.8_dp * XI_MAX) then
        print '(A,F8.4)', '   FAIL ventana: xi(2.2,0.18) = ', xi_win
        ok = .false.
    end if

    xi = xi_pretorius(2.2_dp, 0.33_dp, 1823.0_dp)
    if (xi > 0.1_dp * xi_win) then
        print '(A,F8.4)', '   FAIL FeO 33% no mata la espuma: xi = ', xi
        ok = .false.
    end if

    xi = xi_pretorius(1.5_dp, 0.18_dp, 1823.0_dp)
    if (xi > 0.15_dp * xi_win) then
        print '(A,F8.4)', '   FAIL B2 1.5 no mata la espuma: xi = ', xi
        ok = .false.
    end if

    xi_prev = -1.0_dp
    do n = 0, 8
        b2 = 1.5_dp + 0.1_dp * n
        xi = xi_pretorius(b2, 0.18_dp, 1823.0_dp)
        if (xi < xi_prev) then
            print '(A,F5.2)', '   FAIL no-monotonia en B2 = ', b2
            ok = .false.
        end if
        xi_prev = xi
    end do

    xi_prev = 1.0e30_dp
    do n = 0, 6
        t = 1823.0_dp + 100.0_dp * n
        xi = xi_pretorius(2.2_dp, 0.18_dp, t)
        if (xi > xi_prev + 1e-12_dp) then
            print '(A,F7.0)', '   FAIL no decrece con T = ', t
            ok = .false.
        end if
        xi_prev = xi
    end do

    if (xi_pretorius(0.5_dp, 0.9_dp, 3000.0_dp) < 0.0_dp .or. &
        xi_pretorius(3.0_dp, 0.18_dp, 1200.0_dp) > 2.0_dp * XI_MAX) then
        print '(A)', '   FAIL cotas de xi'
        ok = .false.
    end if

    if (ok) then
        print '(A,F6.3,A)', ' PASS test_pretorius (xi ventana = ', xi_win, ' s)'
    else
        print '(A)', ' FAIL test_pretorius'
        stop 1
    end if
end program test_pretorius
