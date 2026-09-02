!===============================================================================
! test_tdma.f90 - Unit test del solver Thomas (mod_solver_3d::tdma)
!
! Sistema tridiagonal a_i*x_{i-1} + b_i*x_i + c_i*x_{i+1} = d_i con solución
! exacta prescrita x_i = sin(i); diagonal dominante (b=4, a=c=1).
! Criterio: max|x - x_exacta| < 1e-12.
!===============================================================================
program test_tdma
    use mod_constants
    use mod_solver_3d, only: tdma
    implicit none

    integer, parameter :: n = 50
    real(dp) :: a(n), b(n), c(n), d(n), x(n), xe(n)
    integer  :: i
    real(dp) :: err

    do i = 1, n
        xe(i) = sin(real(i, dp))
    end do
    a = 1.0_dp; b = 4.0_dp; c = 1.0_dp
    a(1) = 0.0_dp; c(n) = 0.0_dp

    d(1) = b(1) * xe(1) + c(1) * xe(2)
    d(n) = a(n) * xe(n-1) + b(n) * xe(n)
    do i = 2, n - 1
        d(i) = a(i) * xe(i-1) + b(i) * xe(i) + c(i) * xe(i+1)
    end do

    call tdma(a, b, c, d, x, n)

    err = maxval(abs(x - xe))
    if (err < 1.0e-12_dp) then
        print '(A,ES10.3)', ' PASS test_tdma  err = ', err
    else
        print '(A,ES10.3)', ' FAIL test_tdma  err = ', err
        stop 1
    end if
end program test_tdma
