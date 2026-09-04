!===============================================================================
! test_config.f90 - Unit test del parser de configuración (mod_config_3d)
!
! Escribe un config temporal con claves conocidas (int, real, bool en ambas
! sintaxis, repetida: la última gana) y una desconocida (debe ignorarse con
! warning, sin abortar), lo lee y verifica los valores.
!===============================================================================
program test_config
    use mod_constants
    use mod_types_3d
    use mod_config_3d, only: config_set_defaults, config_read
    implicit none

    type(config_t) :: cfg
    integer :: iu
    logical :: ok
    character(len=*), parameter :: tmpfile = 'tests/out/tmp_test_config.dat'

    call execute_command_line('mkdir -p tests/out')

    open(newunit=iu, file=tmpfile, status='replace', action='write')
    write(iu, '(A)') '# comentario'
    write(iu, '(A)') '! otro comentario'
    write(iu, '(A)') 'nr = 7'
    write(iu, '(A)') 'dt = 0.25'
    write(iu, '(A)') 'dt = 0.125'          ! repetida: la última gana
    write(iu, '(A)') 'solve_flow = false'
    write(iu, '(A)') 'solve_slag = .true.'
    write(iu, '(A)') 'alpha_u=0.4'         ! sin espacios
    write(iu, '(A)') 'clave_inexistente = 42'
    write(iu, '(A)') 'output_dir = tests/out/xyz'
    write(iu, '(A)') 'solve_ecs = true'
    write(iu, '(A)') 'ecs_rate = 55.5'
    write(iu, '(A)') 'ecs_theta_width = 0.7854'
    write(iu, '(A)') 'ecs_mode = coupled'
    write(iu, '(A)') 'ecs_profile_file = input/ecs.dat'
    write(iu, '(A)') 'd_particle = 0.025'
    write(iu, '(A)') 'alpha_k = 0.45'
    close(iu)

    call config_set_defaults(cfg)
    call config_read(cfg, tmpfile)

    ok = .true.
    if (cfg%nr /= 7)                        call fail('nr', ok)
    if (abs(cfg%dt - 0.125_dp) > 1e-15_dp)  call fail('dt (última gana)', ok)
    if (cfg%solve_flow)                     call fail('solve_flow=false', ok)
    if (.not. cfg%solve_slag)               call fail('solve_slag=.true.', ok)
    if (abs(cfg%alpha_u - 0.4_dp) > 1e-15_dp) call fail('alpha_u sin espacios', ok)
    if (trim(cfg%output_dir) /= 'tests/out/xyz') call fail('output_dir', ok)
    if (.not. cfg%solve_ecs)                call fail('solve_ecs', ok)
    if (abs(cfg%ecs_rate - 55.5_dp) > 1e-12_dp) call fail('ecs_rate', ok)
    if (abs(cfg%d_particle - 0.025_dp) > 1e-12_dp) call fail('d_particle', ok)
    if (abs(cfg%alpha_k - 0.45_dp) > 1e-12_dp)  call fail('alpha_k', ok)
    if (abs(cfg%ecs_theta_width - 0.7854_dp) > 1e-12_dp) &
                                            call fail('ecs_theta_width', ok)
    if (trim(cfg%ecs_mode) /= 'coupled')    call fail('ecs_mode', ok)
    if (trim(cfg%ecs_profile_file) /= 'input/ecs.dat') &
                                            call fail('ecs_profile_file', ok)

    open(newunit=iu, file=tmpfile, status='old')
    close(iu, status='delete')

    if (ok) then
        print '(A)', ' PASS test_config'
    else
        print '(A)', ' FAIL test_config'
        stop 1
    end if

contains

    subroutine fail(what, ok_flag)
        character(len=*), intent(in) :: what
        logical, intent(inout)       :: ok_flag
        print '(A,A)', '   FAIL parse: ', what
        ok_flag = .false.
    end subroutine fail

end program test_config
