!===============================================================================
! test_outlet_total_pressure.f90 - Presion total en las aberturas del techo
! (pc_outlet_total_pressure; rafaga de gas de B1 258.5 s, auditoria dirigida M4)
!
! Motivo: con p fija en la celda de salida el reflujo por el agujero del
! electrodo no tenia freno (chorro a U_GAS_MAX); la salida pasa a presion
! TOTAL: p = p0 - 1/2 rho u_in^2 con u_in >= 0 la velocidad de entrada.
!
! Casos:
!   1. Sin entrada (u_in = 0, y u_in < 0 = gas que sale) y p = p0: p no se
!      mueve (bit a bit; relajar hacia 0 desequilibraba slag_rest).
!   2. Con entrada y alpha_p = 1: p = p0 - 1/2 rho u_in^2.
!   3. Sub-relajacion: p = (1-a) p_old + a (p0 - 1/2 rho u_in^2).
!   4. u_in acotada a U_GAS_MAX y p a -P_HYDRO_CAP (centinelas sin subir).
!   5. Reposo exacto para cualquier p0 y alpha_p (forma incremental) y NaN
!      propagado (quien llama no lo escribe; max() lo tragaria).
!   6. Signo de outlet_inflow_velocity: gas que sube por la cara inferior y
!      sale por la abertura => u_in < 0; gas que baja => u_in > 0, con
!      |u_in| = caudal / (rho * area); flujo que solo atraviesa la celda => 0.
!===============================================================================
program test_outlet_total_pressure
    use mod_constants
    use mod_pressure_3d, only: outlet_total_pressure, outlet_inflow_velocity, P_HYDRO_CAP
    implicit none

    real(dp), parameter :: p0 = 0.067_dp, rho = 0.3_dp
    real(dp) :: pr, nan, area, u
    integer  :: n
    logical :: ok

    ok = .true.

    ! ---- caso 1: reposo ----
    if (outlet_total_pressure(p0, p0, rho, 0.0_dp, 0.3_dp) /= p0) &
        call fail('caso 1: sin entrada p se mueve de p0')
    if (outlet_total_pressure(p0, p0, rho, -50.0_dp, 0.3_dp) /= p0) &
        call fail('caso 1: gas que sale cambia p')

    ! ---- caso 2: entrada a 20 m/s ----
    if (abs(outlet_total_pressure(5.0_dp, p0, rho, 20.0_dp, 1.0_dp) - (p0 - 60.0_dp)) > 1.0e-12_dp) &
        call fail('caso 2: p /= p0 - 1/2 rho u^2')

    ! ---- caso 3: sub-relajacion ----
    if (abs(outlet_total_pressure(5.0_dp, p0, rho, 20.0_dp, 0.3_dp) &
            - (0.7_dp * 5.0_dp + 0.3_dp * (p0 - 60.0_dp))) > 1.0e-12_dp) &
        call fail('caso 3: relajacion con alpha_p')

    ! ---- caso 4: centinelas ----
    if (abs(outlet_total_pressure(0.0_dp, p0, rho, 1.0e4_dp, 1.0_dp) &
            - (p0 - 0.5_dp * rho * U_GAS_MAX**2)) > 1.0e-9_dp) &
        call fail('caso 4: u_in no acotada a U_GAS_MAX')
    if (outlet_total_pressure(0.0_dp, p0, 1.0e3_dp, U_GAS_MAX, 1.0_dp) /= -P_HYDRO_CAP) &
        call fail('caso 4: p no acotada a -P_HYDRO_CAP')

    ! ---- caso 5: reposo exacto y NaN ----
    do n = 1, 1000
        pr = 1.0e-3_dp * real(n, dp) * 3.7_dp
        if (outlet_total_pressure(pr, pr, rho, 0.0_dp, 0.7_dp) /= pr .or. &
            outlet_total_pressure(pr, pr, rho, 0.0_dp, 0.3_dp) /= pr) then
            call fail('caso 5: en reposo p se mueve (no incremental)'); exit
        end if
    end do
    nan = 0.0_dp; nan = nan / nan
    pr = outlet_total_pressure(p0, nan, rho, 20.0_dp, 0.7_dp)
    if (pr == pr) call fail('caso 5: NaN en p0 no se propaga')
    pr = outlet_total_pressure(p0, p0, rho, nan, 0.7_dp)
    if (pr == pr) call fail('caso 5: NaN en u_in no se propaga')

    ! ---- caso 6: signo de la velocidad de entrada ----
    ! celda de vol 2 m^3 y dz 0.5 m (abertura de 4 m^2), rho 0.3
    area = 4.0_dp
    u = outlet_inflow_velocity(0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 1.2_dp, rho, 2.0_dp, 0.5_dp)
    if (abs(u + 1.2_dp / (rho * area)) > 1.0e-12_dp) call fail('caso 6: gas que sale no da u_in < 0')
    u = outlet_inflow_velocity(0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, -1.2_dp, rho, 2.0_dp, 0.5_dp)
    if (abs(u - 1.2_dp / (rho * area)) > 1.0e-12_dp) call fail('caso 6: gas que baja no da u_in > 0')
    u = outlet_inflow_velocity(0.6_dp, 0.0_dp, 0.0_dp, 0.0_dp, -0.6_dp, rho, 2.0_dp, 0.5_dp) &
      - 2.0_dp * 0.6_dp / (rho * area)
    if (abs(u) > 1.0e-12_dp) call fail('caso 6: salida lateral no suma a la entrada')
    u = outlet_inflow_velocity(0.6_dp, 0.6_dp, 0.3_dp, 0.3_dp, 0.0_dp, rho, 2.0_dp, 0.5_dp)
    if (abs(u) > 1.0e-15_dp) call fail('caso 6: flujo que atraviesa la celda no es 0')

    if (ok) then
        print '(a)', 'test_outlet_total_pressure: OK'
    else
        error stop 1
    end if

contains

    subroutine fail(msg)
        character(len=*), intent(in) :: msg
        print '(2a)', 'FAIL ', msg
        ok = .false.
    end subroutine fail

end program test_outlet_total_pressure
