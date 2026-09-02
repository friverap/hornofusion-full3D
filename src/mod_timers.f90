!===============================================================================
! mod_timers.f90 - Timers de pared por bloque del paso (P0.1, roadmap paper)
!
! NO INVASIVO: solo lee el reloj (system_clock); no toca ningún campo de la
! simulación (verificable por h5diff bit-idéntico). Uso:
!     call timer_start(T_SIMPLE) ... call timer_stop(T_SIMPLE)
! y al final call timer_report(m): tabla por bloque con el acumulado del
! rank 0 y el MÁXIMO entre ranks (el máximo es el que gobierna el paso en
! MPI síncrono). Base para el estudio de escalamiento S6 y para decidir
! dónde optimizar antes de las campañas.
!===============================================================================
module mod_timers
    use mod_constants, only: dp
    use mod_types_3d
    use mod_mpi_topology, only: mpi_allreduce_max
    implicit none

    integer, parameter :: T_ARC    = 1  ! Cassie-Mayr + depósito + MC + Lorentz
    integer, parameter :: T_RAD    = 2  ! radiación DO
    integer, parameter :: T_CHEM   = 3  ! química + transporte de especies
    integer, parameter :: T_SIMPLE = 4  ! lazo externo SIMPLE completo
    integer, parameter :: T_SOLID  = 5  ! fusión + colapso + interfase
    integer, parameter :: T_SLAG   = 6  ! capa de escoria
    integer, parameter :: T_IO     = 7  ! HDF5 + audit + monitor
    integer, parameter :: N_TIMERS = 7

    character(len=18), parameter :: TIMER_NAME(N_TIMERS) = [ &
        'arco              ', 'radiacion DO      ', &
        'quimica+especies  ', 'lazo SIMPLE       ', &
        'fase solida       ', 'escoria           ', &
        'salida/auditoria  ' ]

    real(dp), save :: t_acc(N_TIMERS) = 0.0_dp
    integer(kind=8), save :: t_start_count(N_TIMERS) = 0_8

contains

    subroutine timer_start(id)
        integer, intent(in) :: id
        call system_clock(t_start_count(id))
    end subroutine timer_start

    subroutine timer_stop(id)
        integer, intent(in) :: id
        integer(kind=8) :: t1, rate
        call system_clock(t1, rate)
        t_acc(id) = t_acc(id) + real(t1 - t_start_count(id), dp) / &
                    real(rate, dp)
    end subroutine timer_stop

    subroutine timer_report(m)
        type(mesh_t), intent(in) :: m
        real(dp) :: t_max(N_TIMERS), total
        integer  :: i

        do i = 1, N_TIMERS
            if (m%is_parallel) then
                call mpi_allreduce_max(t_acc(i), t_max(i), m%topo)
            else
                t_max(i) = t_acc(i)
            end if
        end do
        total = sum(t_max)

        if (.not. m%is_parallel .or. m%topo%rank == 0) then
            print *, ''
            print '(A)', ' [TIMERS] pared acumulada por bloque ' // &
                         '(max entre ranks):'
            do i = 1, N_TIMERS
                print '(A,A,F10.2,A,F6.1,A)', '   ', TIMER_NAME(i), &
                    t_max(i), ' s  (', &
                    100.0_dp * t_max(i) / max(total, 1.0e-12_dp), ' %)'
            end do
            print '(A,F10.2,A)', '   TOTAL instrumentado  ', total, ' s'
        end if
    end subroutine timer_report

end module mod_timers
