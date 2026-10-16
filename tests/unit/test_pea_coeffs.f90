!===============================================================================
! test_pea_coeffs.f90 - aP equivalentes de la eliminacion parcial (auditoria 12,
! A12-T3). pea_coeffs (mod_constants) es la unica definicion: la usan pea2
! (mod_multiphase) y el test de venteo de F2.31 (pea_ref, con los transitorios
! a DT_MOB_REF). Casos:
!   1. La respuesta de cada fase a un gradiente de presion, resolviendo el
!      sistema 2x2 a_l u_l - KV u_g = -alpha_l V G, a_g u_g - KV u_l =
!      -alpha_g V G por Cramer, es d_q = alpha_q V / aP_eq,q (1e-12).
!   2. Limites: KV -> 0 da aP_eq = aP propio; KV -> inf da la mezcla
!      alpha_q (a_l + a_g)/(alpha_l + alpha_g).
!   3. Degenerados (aP <= 0, det <= 0): sin cambio.
!===============================================================================
program test_pea_coeffs
    use mod_constants
    implicit none
    real(dp) :: apl, apg, kv, al, ag, ale, age, V, G, det, ul, ug, dl, dg, mixl, mixg
    integer  :: n
    logical  :: ok
    ok = .true.; V = 0.37_dp; G = 1.0_dp

    do n = 1, 5
        ! el aP de cada fase lleva KV en la diagonal (det > 0), como en el momento
        kv = 2.3_dp * n; al = 0.15_dp * n; ag = 1.0_dp - al - 0.05_dp
        apl = 10.0_dp**(n - 2) * 3.1_dp + kv; apg = 0.7_dp * 10.0_dp**(3 - n) + kv
        call pea_coeffs(apl, apg, kv, al, ag, ale, age)
        det = apl * apg - kv * kv
        ! Cramer del sistema con la fuerza de presion -alpha V G de cada fase
        ul = ((-al * V * G) * apg + kv * (-ag * V * G)) / det
        ug = (apl * (-ag * V * G) + kv * (-al * V * G)) / det
        dl = -ul / G; dg = -ug / G
        if (abs(al * V / ale - dl) > 1.0e-12_dp * abs(dl) .or. abs(ag * V / age - dg) > 1.0e-12_dp * abs(dg)) then
            print '(A,I0,4ES14.6)', '   FAIL caso 1.', n, al * V / ale, dl, ag * V / age, dg
            ok = .false.
        end if
    end do

    call pea_coeffs(5.0_dp, 2.0_dp, 1.0e-9_dp, 0.4_dp, 0.5_dp, ale, age)
    if (abs(ale - 5.0_dp) > 1.0e-8_dp * 5.0_dp .or. abs(age - 2.0_dp) > 1.0e-8_dp * 2.0_dp) then
        print '(A,2ES14.6)', '   FAIL caso 2 (KV -> 0): ', ale, age; ok = .false.
    end if
    call pea_coeffs(5.0_dp + 1.0e8_dp, 2.0_dp + 1.0e8_dp, 1.0e8_dp, 0.4_dp, 0.5_dp, ale, age)
    mixl = 0.4_dp * (7.0_dp) / 0.9_dp; mixg = 0.5_dp * (7.0_dp) / 0.9_dp
    if (abs(ale - mixl) > 1.0e-6_dp * mixl .or. abs(age - mixg) > 1.0e-6_dp * mixg) then
        print '(A,4ES14.6)', '   FAIL caso 2 (KV -> inf): ', ale, mixl, age, mixg; ok = .false.
    end if

    call pea_coeffs(0.0_dp, 2.0_dp, 1.0_dp, 0.4_dp, 0.5_dp, ale, age)
    if (ale /= 0.0_dp .or. age /= 2.0_dp) then
        print '(A)', '   FAIL caso 3 (aP_l = 0 debe dejar los aP sin cambio)'; ok = .false.
    end if
    call pea_coeffs(1.0_dp, 1.0_dp, 2.0_dp, 0.4_dp, 0.5_dp, ale, age)
    if (ale /= 1.0_dp .or. age /= 1.0_dp) then
        print '(A)', '   FAIL caso 3 (det <= 0 debe dejar los aP sin cambio)'; ok = .false.
    end if

    if (ok) then
        print '(A)', ' PASS test_pea_coeffs (aP equivalentes = respuesta exacta del sistema 2x2; limites y degenerados)'
    else
        print '(A)', ' FAIL test_pea_coeffs'
        stop 1
    end if
end program test_pea_coeffs
