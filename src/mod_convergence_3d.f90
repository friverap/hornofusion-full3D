!===============================================================================
! mod_convergence_3d.f90 - Convergence monitoring and adaptive time stepping
!===============================================================================
module mod_convergence_3d
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_mpi_topology, only: mpi_allreduce_max
    use ieee_arithmetic, only: ieee_is_nan, ieee_is_finite
    implicit none

contains

    !---------------------------------------------------------------------------
    ! FRENO DE NaN (2026-09): detecta NaN/Inf en residuales y en los campos
    ! de estado, imprime el diagnostico LOCAL del rank afectado (campo,
    ! indices, tiempo) y devuelve un flag GLOBAL.
    !
    ! El allreduce es OBLIGATORIO: un stop local dejaria a los demas ranks
    ! colgados en la siguiente colectiva. Todos los ranks deciden lo mismo
    ! y abortan juntos.
    !
    ! Motivo (B1, sep-2026): una corrida que reventaba en t=471.66 siguio
    ! 176,392 pasos escribiendo NaN y quemo dos dias de CPU con estado
    ! corrupto (m_sol -> 0.24 kg, m_liq -> 65 t espurios). El coste del
    ! barrido es <1 % del paso; el de NO frenar, dias.
    !---------------------------------------------------------------------------
    function nan_guard_triggered(conv, liq, gas, sol, sh, m, step, time) &
             result(bad)
        type(convergence_t), intent(in) :: conv
        type(phase_t), intent(in)       :: liq, gas
        type(solid_t), intent(in)       :: sol
        type(shared_t), intent(in)      :: sh
        type(mesh_t), intent(in)        :: m
        integer, intent(in)             :: step
        real(dp), intent(in)            :: time
        logical :: bad

        real(dp) :: local_flag, global_flag
        integer  :: rank

        local_flag = 0.0_dp
        rank = 0
        if (m%is_parallel) rank = m%topo%rank

        ! 1) residuales del lazo externo (coste cero: ya calculados)
        if (bad_value(conv%res_cont) .or. bad_value(conv%res_ur) .or. &
            bad_value(conv%res_uth) .or. bad_value(conv%res_uz) .or. &
            bad_value(conv%res_energy) .or. bad_value(conv%res_tke) .or. &
            bad_value(conv%res_eps)) then
            local_flag = 1.0_dp
            print '(A,I0,A,I0,A,ES12.4)', ' [NaN-GUARD] rank ', rank, &
                ': residual no finito en paso ', step, ', t = ', time
        end if

        ! 2) campos de estado (el NaN puede vivir donde el residual no mira)
        call scan_field(liq%ur,     'liq%ur',     local_flag, rank, step, m)
        call scan_field(liq%uth,    'liq%uth',    local_flag, rank, step, m)
        call scan_field(liq%uz,     'liq%uz',     local_flag, rank, step, m)
        call scan_field(liq%T,      'liq%T',      local_flag, rank, step, m)
        call scan_field(liq%alpha,  'liq%alpha',  local_flag, rank, step, m)
        call scan_field(gas%ur,     'gas%ur',     local_flag, rank, step, m)
        call scan_field(gas%uz,     'gas%uz',     local_flag, rank, step, m)
        call scan_field(gas%T,      'gas%T',      local_flag, rank, step, m)
        call scan_field(gas%alpha,  'gas%alpha',  local_flag, rank, step, m)
        call scan_field(sh%p,       'sh%p',       local_flag, rank, step, m)
        call scan_field(sol%T_s,    'sol%T_s',    local_flag, rank, step, m)
        call scan_field(sol%E_s,    'sol%E_s',    local_flag, rank, step, m)
        call scan_field(sol%m_s,    'sol%m_s',    local_flag, rank, step, m)
        call scan_field(sol%alpha_s,'sol%alpha_s',local_flag, rank, step, m)

        if (m%is_parallel) then
            call mpi_allreduce_max(local_flag, global_flag, m%topo)
        else
            global_flag = local_flag
        end if
        bad = (global_flag > 0.5_dp)
    end function nan_guard_triggered

    !---------------------------------------------------------------------------
    pure logical function bad_value(x)
        real(dp), intent(in) :: x
        bad_value = ieee_is_nan(x) .or. (.not. ieee_is_finite(x))
    end function bad_value

    !---------------------------------------------------------------------------
    ! Barre las celdas PROPIAS (sin halos: el halo del vecino es su
    ! problema y se detecta alla) e imprime la PRIMERA celda afectada.
    !---------------------------------------------------------------------------
    subroutine scan_field(f, name, flag, rank, step, m)
        real(dp), intent(in)         :: f(-1:,-1:,-1:)
        character(len=*), intent(in) :: name
        real(dp), intent(inout)      :: flag
        integer, intent(in)          :: rank, step
        type(mesh_t), intent(in)     :: m

        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (bad_value(f(i,j,k))) then
                        flag = 1.0_dp
                        print '(A,I0,A,A,A,I0,A,I0,A,I0,A,I0)', &
                            ' [NaN-GUARD] rank ', rank, ': ', trim(name), &
                            ' no finito en (i,j,k) = (', i, ',', j, ',', k, &
                            ') paso ', step
                        return
                    end if
                end do
            end do
        end do
    end subroutine scan_field

    function check_convergence(conv, cfg) result(converged)
        type(convergence_t), intent(in) :: conv
        type(config_t), intent(in)      :: cfg
        logical :: converged

        converged = .true.

        ! Safety: if no physics enabled, always converged
        if (.not. cfg%solve_flow .and. .not. cfg%solve_energy .and. .not. cfg%solve_turb) then
            converged = .true.
            return
        end if

        ! Safety: check for invalid residuals (NaN or Inf)
        if (cfg%solve_flow) then
            if (ieee_is_nan(conv%res_cont) .or. .not. ieee_is_finite(conv%res_cont) &
                .or. conv%res_cont > 1.0e100_dp) then
                converged = .false.  ! NaN or Inf detected
                return
            end if
        end if

        if (cfg%solve_flow) then
            if (conv%res_cont > cfg%tol_cont) converged = .false.
            if (conv%res_ur > cfg%tol_mom)     converged = .false.
            if (conv%res_uth > cfg%tol_mom)    converged = .false.
            if (conv%res_uz > cfg%tol_mom)     converged = .false.
        end if

        if (cfg%solve_energy) then
            if (conv%res_energy > cfg%tol_energy) converged = .false.
        end if

        if (cfg%solve_turb) then
            if (conv%res_tke > cfg%tol_turb) converged = .false.
            if (conv%res_eps > cfg%tol_turb) converged = .false.
        end if
    end function check_convergence

    !---------------------------------------------------------------------------
    ! dt adaptativo (C3.2, hallazgo 3.17): criterio CFL físico + convergencia
    ! REAL del lazo externo (antes main forzaba converged=.true. en max_outer
    ! y la rama de reducción era inalcanzable: dt solo podía crecer).
    !---------------------------------------------------------------------------
    subroutine adapt_timestep(dt, conv, cfl_rate, tau_iph, cfg)
        real(dp), intent(inout)         :: dt
        type(convergence_t), intent(in) :: conv
        ! Tasa CFL global: max sobre celdas/fases de sum(|u_i|/dx_i) [1/s]
        real(dp), intent(in)            :: cfl_rate
        ! Tau mínimo global del acople interfase gas-sólido [s]: con
        ! dt >~ tau el intercambio explícito satura su clamp y fuerza
        ! equilibrio térmico local (columna del arco drenada — medido en
        ! B1 con dt=10 ms vs C1 con dt=2 ms). dt <= safety*tau.
        real(dp), intent(in)            :: tau_iph
        type(config_t), intent(in)      :: cfg

        if (.not. cfg%adaptive_dt) return
        if (.not. cfg%solve_flow .and. .not. cfg%solve_energy) return

        if (conv%converged .and. conv%n_outer <= 3) then
            dt = dt * 1.2_dp
        else if (.not. conv%converged) then
            dt = dt * 0.5_dp
        end if

        ! Límite CFL (implícito tolera CFL O(1); cfl_max configurable)
        if (cfl_rate > SMALL) dt = min(dt, cfg%cfl_max / cfl_rate)

        ! Límite del acople interfase (ver arg tau_iph)
        if (cfg%iph_dt_safety > 0.0_dp .and. tau_iph < 1.0e29_dp) &
            dt = min(dt, cfg%iph_dt_safety * tau_iph)

        dt = min(max(dt, cfg%dt_min), cfg%dt_max)
    end subroutine adapt_timestep

    !---------------------------------------------------------------------------
    ! Tasa CFL global de ambas fases: max_celdas sum_i |u_i|/dx_i  [1/s]
    !---------------------------------------------------------------------------
    function compute_cfl_rate(liq, gas, m) result(rate)
        type(phase_t), intent(in) :: liq, gas
        type(mesh_t), intent(in)  :: m
        real(dp) :: rate

        integer :: i, j, k
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: local, glob, dth_len

        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        local = 0.0_dp
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    ! Escala azimutal acotada por el ancho radial local
                    ! (cierre 2026, punto 3): junto al eje r*dtheta -> 0
                    ! y dominaba el dt global (medido dt ~1-2 ms en el
                    ! hito bore-in, >3 h de pared para 300 s). Las celdas
                    ! theta del anillo interior son astillas del mismo
                    ! vecindario físico (sus centros distan < dr) y el
                    ! esquema es totalmente implícito: el CFL gobierna
                    ! precisión del transporte, no estabilidad — la escala
                    ! advectiva relevante no baja del ancho radial.
                    dth_len = max(m%r(i) * m%dtheta(j), m%dr(i))
                    local = max(local, &
                        abs(liq%ur(i,j,k))/m%dr(i) + abs(liq%uth(i,j,k))/dth_len &
                        + abs(liq%uz(i,j,k))/m%dz(k), &
                        abs(gas%ur(i,j,k))/m%dr(i) + abs(gas%uth(i,j,k))/dth_len &
                        + abs(gas%uz(i,j,k))/m%dz(k))
                end do
            end do
        end do
        if (m%is_parallel) then
            call mpi_allreduce_max(local, glob, m%topo)
            rate = glob
        else
            rate = local
        end if
    end function compute_cfl_rate

end module mod_convergence_3d
