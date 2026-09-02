!===============================================================================
! test_sn_weights.f90 - Momentos de las cuadraturas level-symmetric (C4.1)
!
! Para N = 4, 6, 8 verifica (guarda contra errores de transcripción):
!   momento 0:  Sum w            = 4*pi          (tol 1e-5 relativo)
!   momento 0': Sum_octante w    = pi/2
!   momento 1:  Sum w*s_i        = 0             (exacto por simetría)
!   momento 2:  Sum w*s_i*s_j    = (4*pi/3) d_ij (tol 1e-4: las tablas
!               publicadas tienen 7 cifras)
!   |s| = 1 en cada dirección (tol 1e-5)
! Y que S4 reproduce EXACTAMENTE la cuadratura histórica (peso pi/6).
!===============================================================================
program test_sn_weights
    use mod_constants
    use mod_radiation_do, only: get_sn_direction, n_quad_dirs
    implicit none

    integer  :: nq, d, ndir, iq
    real(dp) :: mu, eta, xi, w
    real(dp) :: m0, m1(3), m2(3,3), oct1, norm
    logical  :: ok
    integer, parameter :: NQS(3) = [4, 6, 8]

    ok = .true.
    do iq = 1, 3
        nq = NQS(iq)
        ndir = n_quad_dirs(nq)
        m0 = 0.0_dp; m1 = 0.0_dp; m2 = 0.0_dp; oct1 = 0.0_dp
        do d = 1, ndir
            call get_sn_direction(nq, d, mu, eta, xi, w)
            norm = sqrt(mu*mu + eta*eta + xi*xi)
            if (abs(norm - 1.0_dp) > 1.0e-5_dp) then
                print '(A,I2,I4,ES10.3)', '   FAIL |s|/=1: N,d,err ', &
                    nq, d, abs(norm-1.0_dp)
                ok = .false.
            end if
            m0 = m0 + w
            m1 = m1 + w * [mu, eta, xi]
            m2(1,1) = m2(1,1) + w*mu*mu
            m2(2,2) = m2(2,2) + w*eta*eta
            m2(3,3) = m2(3,3) + w*xi*xi
            m2(1,2) = m2(1,2) + w*mu*eta
            m2(1,3) = m2(1,3) + w*mu*xi
            m2(2,3) = m2(2,3) + w*eta*xi
            if (mu > 0 .and. eta > 0 .and. xi > 0) oct1 = oct1 + w
        end do

        if (abs(m0 - 4.0_dp*PI)/(4.0_dp*PI) > 1.0e-5_dp) then
            print '(A,I2,ES12.5)', '   FAIL momento 0 (4pi): N, sum = ', nq, m0
            ok = .false.
        end if
        if (abs(oct1 - 0.5_dp*PI)/(0.5_dp*PI) > 1.0e-5_dp) then
            print '(A,I2,ES12.5)', '   FAIL octante (pi/2): N, sum = ', nq, oct1
            ok = .false.
        end if
        if (maxval(abs(m1)) > 1.0e-10_dp) then
            print '(A,I2,ES10.3)', '   FAIL momento 1 (0): N, max = ', &
                nq, maxval(abs(m1))
            ok = .false.
        end if
        if (abs(m2(1,1) - 4.0_dp*PI/3.0_dp)/(4.0_dp*PI/3.0_dp) > 1.0e-4_dp &
            .or. abs(m2(2,2) - m2(1,1)) > 1.0e-4_dp &
            .or. abs(m2(3,3) - m2(1,1)) > 1.0e-4_dp) then
            print '(A,I2,3ES12.5)', '   FAIL momento 2 diag: N = ', &
                nq, m2(1,1), m2(2,2), m2(3,3)
            ok = .false.
        end if
        if (max(abs(m2(1,2)), abs(m2(1,3)), abs(m2(2,3))) > 1.0e-10_dp) then
            print '(A,I2)', '   FAIL momento 2 off-diag /= 0: N = ', nq
            ok = .false.
        end if
    end do

    ! S4 histórico: peso pi/6 exacto
    call get_sn_direction(4, 1, mu, eta, xi, w)
    if (abs(w - PI/6.0_dp) > 1.0e-14_dp) then
        print '(A,ES12.5)', '   FAIL S4 peso /= pi/6: ', w
        ok = .false.
    end if
    if (abs(mu - 0.9082483_dp) > 1e-12_dp .or. &
        abs(eta - 0.2958759_dp) > 1e-12_dp) then
        print '(A)', '   FAIL S4 d=1 no reproduce (a2,a1,a1)'
        ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_sn_weights (S4/S6/S8: momentos 0/1/2 OK)'
    else
        print '(A)', ' FAIL test_sn_weights'
        stop 1
    end if
end program test_sn_weights
