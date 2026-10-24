!===============================================================================
! test_relax_residual.f90 - Residuo del enunciado discreto de energia por fase
! (WS-K3, C-096..C-098): eq_residual(q) = absorbido - (arco + rad + quim +
! conv - pared + masa) de lo que el hook entrego con audit_set_energy (conv
! ya con signo de entrada, -s_conv). Columnas E_relax_liq / E_relax_gas.
!   1. Enunciado que se cumple (absorbido = suma de terminos): residuo 0.
!   2. Absorbido 60 J por debajo de los terminos (la fuga de B1 con
!      alpha_T 0.7): residuo -60 en el liquido, el gas intacto.
!   3. La pared RESTA y la conveccion SUMA tal como llegan: un error de signo
!      en cualquiera de las dos da otro numero.
!===============================================================================
program test_relax_residual
    use mod_constants
    use mod_audit, only: audit_set_energy, eq_residual
    implicit none
    integer :: nfail = 0

    ! 1. liquido que cumple: 100 = 70 + 20 + 5 + (-10) - 3 + 18
    call audit_set_energy(.false., 100.0_dp, 70.0_dp, 20.0_dp, 5.0_dp, -10.0_dp, 3.0_dp, 18.0_dp)
    call audit_set_energy(.true.,  50.0_dp, 30.0_dp, 15.0_dp, 5.0_dp,   2.0_dp, 2.0_dp,  0.0_dp)
    call check('cumple liq', eq_residual(1), 0.0_dp)
    call check('cumple gas', eq_residual(2), 0.0_dp)
    ! 2. absorbido 60 J menos en el liquido
    call audit_set_energy(.false., 40.0_dp, 70.0_dp, 20.0_dp, 5.0_dp, -10.0_dp, 3.0_dp, 18.0_dp)
    call check('fuga liq', eq_residual(1), -60.0_dp)
    call check('gas intacto', eq_residual(2), 0.0_dp)
    ! 3. signos: conveccion +10 en vez de -10 (+20) y pared 13 en vez de 3
    !    (-10): terminos 110, residuo 100 - 110 = -10
    call audit_set_energy(.false., 100.0_dp, 70.0_dp, 20.0_dp, 5.0_dp, 10.0_dp, 13.0_dp, 18.0_dp)
    call check('signos', eq_residual(1), -10.0_dp)

    if (nfail == 0) then
        print '(A)', 'PASS test_relax_residual'
    else
        print '(A,I0,A)', 'FAIL test_relax_residual (', nfail, ' casos)'
        error stop 1
    end if
contains
    subroutine check(name, got, want)
        character(*), intent(in) :: name
        real(dp), intent(in) :: got, want
        if (abs(got - want) > 1.0e-12_dp) then
            print '(A,A,2ES14.6)', 'FAIL ', name, got, want
            nfail = nfail + 1
        end if
    end subroutine check
end program test_relax_residual
