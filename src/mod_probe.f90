!===============================================================================
! mod_probe.f90 - Sonda de diagnostico por subetapa (sep-2026)
!
! Motivo: B1 revienta SIEMPRE en el paso 235829 (t=471.66 s), de forma
! determinista, y dos cotas de velocidad no lo evitaron. Los sintomas del
! log son insuficientes para saber que termino explota primero:
!   - res_cont llevaba cientos de pasos en 0.35 (tolerancia 1e-4);
!   - res_energy se satura en 0.142857 exacto 3 pasos antes del NaN;
!   - el transporte de alpha reporta CFL 1181, que la geometria de la
!     malla NO explica con |u| <= U_LIQ_MAX (haria falta ~1800 m/s).
!
! La sonda imprime, SOLO dentro de una ventana de pasos (probe_step_from,
! probe_step_to; desactivada por defecto), una linea por subetapa del lazo
! con los extremos globales y DONDE ocurren. Coste fuera de la ventana:
! una comparacion de enteros.
!===============================================================================
module mod_probe
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils, only: get_loop_bounds
    use mod_mpi_topology, only: mpi_allreduce_max
    implicit none

    private
    public :: probe_active, probe_active_now, probe_current_step, probe_report, probe_set_step

    ! el paso lo fija main cada iteracion: asi las subetapas del lazo
    ! multifase no necesitan cambiar de firma para instrumentarse
    integer, save :: current_step = -1

contains

    !---------------------------------------------------------------------------
    subroutine probe_set_step(step)
        integer, intent(in) :: step
        current_step = step
    end subroutine probe_set_step

    !---------------------------------------------------------------------------
    pure integer function probe_current_step()
        probe_current_step = current_step
    end function probe_current_step

    pure logical function probe_active_now(cfg)
        type(config_t), intent(in) :: cfg
        probe_active_now = probe_active(cfg, current_step)
    end function probe_active_now

    !---------------------------------------------------------------------------
    pure logical function probe_active(cfg, step)
        type(config_t), intent(in) :: cfg
        integer, intent(in)        :: step
        probe_active = (cfg%probe_step_to > 0) .and. &
                       (step >= cfg%probe_step_from) .and. &
                       (step <= cfg%probe_step_to)
    end function probe_active

    !---------------------------------------------------------------------------
    ! Una linea por subetapa: extremos GLOBALES y la celda que los produce.
    ! El rank duenio del extremo imprime su (i,j,k) global; los demas callan.
    !---------------------------------------------------------------------------
    subroutine probe_report(tag, liq, gas, sol, sh, m, cfg)
        character(len=*), intent(in) :: tag
        type(phase_t), intent(in)    :: liq, gas
        type(solid_t), intent(in)    :: sol
        type(shared_t), intent(in)   :: sh
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg
        integer :: step

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        integer  :: iu, ju, ku, it, jt, kt
        real(dp) :: umag, umax_loc, umax_glob
        real(dp) :: tmax_loc, tmax_glob, rmin_loc, rmin_glob
        real(dp) :: amax_loc, amax_glob, pmax_loc, pmax_glob
        real(dp) :: tsmax_loc, tsmax_glob
        integer  :: rank

        step = current_step
        if (.not. probe_active(cfg, step)) return

        rank = 0
        if (m%is_parallel) rank = m%topo%rank
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        umax_loc = 0.0_dp; tmax_loc = 0.0_dp; amax_loc = 0.0_dp
        pmax_loc = 0.0_dp; tsmax_loc = 0.0_dp
        rmin_loc = 1.0e30_dp
        iu = 0; ju = 0; ku = 0; it = 0; jt = 0; kt = 0

        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle
                    umag = sqrt(liq%ur(i,j,k)**2 + liq%uth(i,j,k)**2 + &
                                liq%uz(i,j,k)**2)
                    if (umag > umax_loc) then
                        umax_loc = umag; iu = i; ju = j; ku = k
                    end if
                    if (liq%T(i,j,k) > tmax_loc) then
                        tmax_loc = liq%T(i,j,k); it = i; jt = j; kt = k
                    end if
                    if (liq%alpha(i,j,k) > 1.0e-6_dp) then
                        rmin_loc = min(rmin_loc, liq%rho(i,j,k))
                    end if
                    amax_loc  = max(amax_loc,  liq%alpha(i,j,k))
                    pmax_loc  = max(pmax_loc,  abs(sh%p(i,j,k)))
                    tsmax_loc = max(tsmax_loc, sol%T_s(i,j,k))
                end do
            end do
        end do

        if (m%is_parallel) then
            call mpi_allreduce_max(umax_loc,  umax_glob,  m%topo)
            call mpi_allreduce_max(tmax_loc,  tmax_glob,  m%topo)
            call mpi_allreduce_max(amax_loc,  amax_glob,  m%topo)
            call mpi_allreduce_max(pmax_loc,  pmax_glob,  m%topo)
            call mpi_allreduce_max(tsmax_loc, tsmax_glob, m%topo)
            call mpi_allreduce_max(-rmin_loc, rmin_glob,  m%topo)
            rmin_glob = -rmin_glob
        else
            umax_glob = umax_loc; tmax_glob = tmax_loc; amax_glob = amax_loc
            pmax_glob = pmax_loc; tsmax_glob = tsmax_loc; rmin_glob = rmin_loc
        end if

        ! rank 0 imprime el resumen; el duenio de cada extremo su celda
        if (rank == 0) then
            print '(A,I0,A,A,A,ES11.4,A,ES11.4,A,ES11.4,A,F8.4,A,ES11.4,A,F9.2)', &
                ' [PROBE ', step, '] ', tag, &
                ' |u|max=', umax_glob, ' T_l max=', tmax_glob, &
                ' rho_l min=', rmin_glob, ' a_l max=', amax_glob, &
                ' |p|max=', pmax_glob, ' T_s max=', tsmax_glob
        end if
        if (umax_glob > 1.0_dp .and. abs(umax_loc - umax_glob) < 1.0e-12_dp) then
            print '(A,I0,A,I0,A,I0,A,I0,A,ES11.4,A,F8.4,A,ES11.4)', &
                '   [PROBE-loc] rank ', rank, ' |u|max en (', &
                iu + m%topo%iglobal_start - 1, ',', &
                ju + m%topo%jglobal_start - 1, ',', &
                ku + m%topo%kglobal_start - 1, ')  u=', umax_glob, &
                '  a_l=', liq%alpha(iu,ju,ku), '  rho=', liq%rho(iu,ju,ku)
        end if
        if (tmax_glob > 2500.0_dp .and. abs(tmax_loc - tmax_glob) < 1.0e-9_dp) then
            print '(A,I0,A,I0,A,I0,A,I0,A,F10.1,A,F8.4)', &
                '   [PROBE-loc] rank ', rank, ' T_l max en (', &
                it + m%topo%iglobal_start - 1, ',', &
                jt + m%topo%jglobal_start - 1, ',', &
                kt + m%topo%kglobal_start - 1, ')  T=', tmax_glob, &
                '  a_l=', liq%alpha(it,jt,kt)
        end if
    end subroutine probe_report

end module mod_probe
