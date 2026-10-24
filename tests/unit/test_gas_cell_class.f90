!===============================================================================
! test_gas_cell_class.f90 - Clase de celda del balance de masa del gas por
! celda (WS-K5, C-110): columnas m_gas_err_free / m_gas_err_multi.
!   1. Outlet manda sobre todo: 0 aunque sea gas puro o este en el lecho.
!   2. Gas libre (1) solo sin liquido NI solido (ambos < ALPHA_FLOW_CUTOFF).
!   3. Multifase (2) con liquido o solido justo en ALPHA_FLOW_CUTOFF: el borde
!      es del lado multifase (el complemento ya actua ahi).
!   4. Escoria en volumen (Plan H): una celda solo escoria + gas es multifase
!      (panel WS-K5, K5-M1: sin alpha_sl caia como gas libre en arc_slag).
!===============================================================================
program test_gas_cell_class
    use mod_constants
    use mod_audit, only: gas_cell_class
    implicit none
    integer :: nfail = 0
    real(dp), parameter :: c = ALPHA_FLOW_CUTOFF

    call check('outlet gas puro', gas_cell_class(0.0_dp, 0.0_dp, 0.0_dp, .true.), 0)
    call check('outlet en lecho', gas_cell_class(0.0_dp, 0.0_dp, 0.5_dp, .true.), 0)
    call check('gas libre',       gas_cell_class(0.0_dp, 0.0_dp, 0.0_dp, .false.), 1)
    call check('trazas',          gas_cell_class(0.3_dp*c, 0.3_dp*c, 0.3_dp*c, .false.), 1)
    call check('borde liquido',   gas_cell_class(c, 0.0_dp, 0.0_dp, .false.), 2)
    call check('borde solido',    gas_cell_class(0.0_dp, 0.0_dp, c, .false.), 2)
    call check('solo escoria',    gas_cell_class(0.0_dp, 0.2_dp, 0.0_dp, .false.), 2)
    call check('borde escoria',   gas_cell_class(0.0_dp, c, 0.0_dp, .false.), 2)
    call check('outlet escoria',  gas_cell_class(0.0_dp, 0.2_dp, 0.0_dp, .true.), 0)
    call check('poro saturado',   gas_cell_class(0.68_dp, 0.0_dp, 0.3_dp, .false.), 2)

    if (nfail == 0) then
        print '(A)', 'PASS test_gas_cell_class'
    else
        print '(A,I0,A)', 'FAIL test_gas_cell_class (', nfail, ' casos)'
        error stop 1
    end if
contains
    subroutine check(name, got, want)
        character(*), intent(in) :: name
        integer, intent(in) :: got, want
        if (got /= want) then
            print '(A,A,2I4)', 'FAIL ', name, got, want
            nfail = nfail + 1
        end if
    end subroutine check
end program test_gas_cell_class
