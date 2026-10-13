!===============================================================================
! mod_input_profiles.f90 - Electrode V/I profiles and charge recipe reader
!
! Reads:
!   - Voltage/current time series for 3-phase AC
!   - Charge recipe (layer masses, solid fractions, HBI content)
!===============================================================================
module mod_input_profiles
    use mpi
    use mod_constants
    use mod_types_3d
    implicit none

    integer, parameter :: MAX_PROFILE_POINTS = 10000

    type :: elec_profile_t
        integer  :: n_points
        real(dp) :: time(MAX_PROFILE_POINTS)
        real(dp) :: voltage(MAX_PROFILE_POINTS)
        real(dp) :: current(MAX_PROFILE_POINTS)
    end type elec_profile_t

    ! Perfil tabulado genérico valor(t) (E1.1): caudal del cargador
    ! continuo, adiciones de cal/carbón, etc. Formato de archivo:
    ! dos columnas "t valor" con # comentarios, como electrode_profile.
    type :: rate_profile_t
        integer  :: n_points = 0
        real(dp) :: time(MAX_PROFILE_POINTS)
        real(dp) :: value(MAX_PROFILE_POINTS)
    end type rate_profile_t

contains

    ! Auditoria (bajos, oct-2026): la ruta estaba fija en el codigo y, si el
    ! archivo faltaba, la corrida seguia en silencio con 500 V / 50 kA
    ! (impreso por todos los ranks). Ahora es la clave electrode_profile_file
    ! (default 'input/electrode_profile.dat'); un archivo configurado que no
    ! abre es ERROR, y '' pide explicitamente el perfil constante
    ! elec_V_const/elec_I_const.
    subroutine read_electrode_profile(prof, filename, V_const, I_const)
        type(elec_profile_t), intent(out) :: prof
        character(len=*), intent(in)      :: filename
        real(dp), intent(in)              :: V_const, I_const

        integer :: iu, ios, n
        real(dp) :: t, v, c
        character(len=512) :: line

        if (len_trim(filename) == 0) then
            call set_const()
            if (io_root()) print '(A,F8.1,A,F10.1,A)', &
                ' [INPUT] Electrodos: perfil CONSTANTE ', V_const, ' V / ', I_const, &
                ' A (electrode_profile_file vacio)'
            return
        end if
        open(newunit=iu, file=trim(filename), status='old', iostat=ios)
        if (ios /= 0) call input_fatal('no se puede abrir electrode_profile_file: ' // trim(filename))

        n = 0
        do
            read(iu, '(A)', iostat=ios) line
            if (ios /= 0) exit
            line = adjustl(line)
            if (len_trim(line) == 0) cycle
            if (line(1:1) == '#' .or. line(1:1) == '!') cycle
            read(line, *, iostat=ios) t, v, c
            if (ios /= 0) cycle
            if (n >= MAX_PROFILE_POINTS) then
                call warn_truncated(filename)
                exit
            end if
            n = n + 1
            prof%time(n) = t
            prof%voltage(n) = v
            prof%current(n) = c
        end do
        close(iu)

        prof%n_points = n
        if (n == 0) call input_fatal('electrode_profile_file sin puntos validos: ' // trim(filename))
        if (io_root()) print '(A,I5,A)', ' [INPUT] Loaded electrode profile: ', prof%n_points, ' points'
    contains
        subroutine set_const()
            prof%n_points = 2
            prof%time(1) = 0.0_dp;     prof%voltage(1) = V_const; prof%current(1) = I_const
            prof%time(2) = 1.0e30_dp;  prof%voltage(2) = V_const; prof%current(2) = I_const
        end subroutine set_const
    end subroutine read_electrode_profile

    !---------------------------------------------------------------------------
    ! Perfil genérico valor(t): lector con fallback a valor constante
    !---------------------------------------------------------------------------
    subroutine read_rate_profile(prof, filename, default_value)
        type(rate_profile_t), intent(out) :: prof
        character(len=*), intent(in)      :: filename
        real(dp), intent(in)              :: default_value

        integer :: iu, ios, n
        real(dp) :: t, v
        character(len=512) :: line

        prof%n_points = 0
        if (len_trim(filename) > 0) then
            open(newunit=iu, file=trim(filename), status='old', iostat=ios)
            ! archivo configurado que no abre: ERROR (antes: valor constante
            ! por defecto en silencio)
            if (ios /= 0) call input_fatal('no se puede abrir el perfil: ' // trim(filename))
            if (ios == 0) then
                n = 0
                do
                    read(iu, '(A)', iostat=ios) line
                    if (ios /= 0) exit
                    line = adjustl(line)
                    if (len_trim(line) == 0) cycle
                    if (line(1:1) == '#' .or. line(1:1) == '!') cycle
                    read(line, *, iostat=ios) t, v
                    if (ios /= 0) cycle
                    if (n >= MAX_PROFILE_POINTS) then
                        call warn_truncated(filename)
                        exit
                    end if
                    n = n + 1
                    prof%time(n) = t
                    prof%value(n) = v
                end do
                close(iu)
                prof%n_points = n
            end if
        end if

        if (prof%n_points == 0) then
            ! Constante: dos puntos con el valor por defecto
            prof%n_points = 2
            prof%time(1) = 0.0_dp;   prof%value(1) = default_value
            prof%time(2) = 1.0e30_dp; prof%value(2) = default_value
        else
            if (io_root()) print '(A,I5,A,A)', ' [INPUT] Loaded rate profile: ', &
                prof%n_points, ' points from ', trim(filename)
        end if
    end subroutine read_rate_profile

    pure function interpolate_rate(prof, time) result(v)
        type(rate_profile_t), intent(in) :: prof
        real(dp), intent(in)             :: time
        real(dp) :: v, frac
        integer  :: i

        if (prof%n_points <= 0) then
            v = 0.0_dp; return
        end if
        if (time <= prof%time(1)) then
            v = prof%value(1); return
        end if
        if (time >= prof%time(prof%n_points)) then
            v = prof%value(prof%n_points); return
        end if
        do i = 1, prof%n_points - 1
            if (time >= prof%time(i) .and. time < prof%time(i+1)) then
                frac = (time - prof%time(i)) / &
                       (prof%time(i+1) - prof%time(i) + SMALL)
                v = prof%value(i) + frac * (prof%value(i+1) - prof%value(i))
                return
            end if
        end do
        v = prof%value(prof%n_points)
    end function interpolate_rate

    subroutine interpolate_profile(prof, time, voltage, current)
        type(elec_profile_t), intent(in) :: prof
        real(dp), intent(in)             :: time
        real(dp), intent(out)            :: voltage, current

        integer :: i
        real(dp) :: frac

        if (prof%n_points <= 0) then
            voltage = 500.0_dp; current = 50000.0_dp; return
        end if

        if (time <= prof%time(1)) then
            voltage = prof%voltage(1)
            current = prof%current(1)
            return
        end if
        if (time >= prof%time(prof%n_points)) then
            voltage = prof%voltage(prof%n_points)
            current = prof%current(prof%n_points)
            return
        end if

        do i = 1, prof%n_points - 1
            if (time >= prof%time(i) .and. time < prof%time(i+1)) then
                frac = (time - prof%time(i)) / (prof%time(i+1) - prof%time(i) + SMALL)
                voltage = prof%voltage(i) + frac * (prof%voltage(i+1) - prof%voltage(i))
                current = prof%current(i) + frac * (prof%current(i+1) - prof%current(i))
                return
            end if
        end do

        voltage = prof%voltage(prof%n_points)
        current = prof%current(prof%n_points)
    end subroutine interpolate_profile

    !---------------------------------------------------------------------------
    ! Read charge recipe
    !---------------------------------------------------------------------------
    subroutine read_charge_recipe(cfg, filename)
        type(config_t), intent(inout) :: cfg
        character(len=*), intent(in)  :: filename

        integer :: iu, ios, n, bucket
        real(dp) :: mass, vfrac
        character(len=512) :: line

        open(newunit=iu, file=trim(filename), status='old', iostat=ios)
        if (ios /= 0) then
            if (io_root()) print '(A,A)', ' [INPUT] Cannot open charge recipe: ', trim(filename)
            call default_charge_recipe(cfg)
            return
        end if

        n = 0
        cfg%n_layers_b1 = 0
        cfg%n_layers_b2 = 0

        do
            read(iu, '(A)', iostat=ios) line
            if (ios /= 0) exit
            line = adjustl(line)
            if (len_trim(line) == 0) cycle
            if (line(1:1) == '#' .or. line(1:1) == '!') cycle
            read(line, *, iostat=ios) bucket, mass, vfrac
            if (ios /= 0) cycle
            if (n >= MAX_LAYERS) then
                call warn_truncated(filename)
                exit
            end if
            n = n + 1
            cfg%layer_bucket(n) = bucket
            cfg%layer_mass(n) = mass
            cfg%layer_vfrac(n) = vfrac
            if (bucket == 1) cfg%n_layers_b1 = cfg%n_layers_b1 + 1
            if (bucket == 2) cfg%n_layers_b2 = cfg%n_layers_b2 + 1
        end do
        close(iu)

        cfg%n_layers_total = n
        if (io_root()) print '(A,I3,A,I3,A,I3)', ' [INPUT] Charge recipe: ', n, ' layers  B1=', &
              cfg%n_layers_b1, '  B2=', cfg%n_layers_b2
    end subroutine read_charge_recipe

    !---------------------------------------------------------------------------
    ! Default charge: 14 layers bucket 1 + 13 layers bucket 2
    !---------------------------------------------------------------------------
    subroutine default_charge_recipe(cfg)
        type(config_t), intent(inout) :: cfg

        integer :: i
        real(dp) :: mass_b1, mass_b2

        mass_b1 = 65700.0_dp   ! kg first bucket
        mass_b2 = 66200.0_dp   ! kg second bucket
        cfg%n_layers_b1 = 14
        cfg%n_layers_b2 = 13
        cfg%n_layers_total = 27

        ! Equal mass per layer, typical solid fraction 0.5
        do i = 1, cfg%n_layers_b1
            cfg%layer_bucket(i) = 1
            cfg%layer_mass(i) = mass_b1 / real(cfg%n_layers_b1, dp)
            cfg%layer_vfrac(i) = 0.50_dp
        end do
        do i = cfg%n_layers_b1 + 1, cfg%n_layers_total
            cfg%layer_bucket(i) = 2
            cfg%layer_mass(i) = mass_b2 / real(cfg%n_layers_b2, dp)
            cfg%layer_vfrac(i) = 0.50_dp
        end do

        if (io_root()) print '(A,F8.1,A,F8.1,A)', ' [INPUT] Default charge: B1=', &
              mass_b1*1e-3_dp, 't  B2=', mass_b2*1e-3_dp, 't'
    end subroutine default_charge_recipe

    !---------------------------------------------------------------------------
    ! Utilidades de E/S: solo rank 0 imprime; error fatal colectivo
    !---------------------------------------------------------------------------
    logical function io_root()
        integer :: rk, ierr
        logical :: init
        call MPI_Initialized(init, ierr)
        io_root = .true.
        if (.not. init) return
        call MPI_Comm_rank(MPI_COMM_WORLD, rk, ierr)
        io_root = (rk == 0)
    end function io_root

    subroutine input_fatal(msg)
        character(len=*), intent(in) :: msg
        integer :: ierr
        logical :: init
        if (io_root()) print '(A,A)', ' [INPUT] ERROR: ', trim(msg)
        call MPI_Initialized(init, ierr)
        if (init) call MPI_Abort(MPI_COMM_WORLD, 4, ierr)
        stop 4
    end subroutine input_fatal

    subroutine warn_truncated(filename)
        character(len=*), intent(in) :: filename
        if (io_root()) print '(A,A,A)', ' [INPUT] AVISO: ', trim(filename), &
            ' supera el maximo de puntos/capas; se trunca (desborde de arreglo evitado)'
    end subroutine warn_truncated

end module mod_input_profiles
