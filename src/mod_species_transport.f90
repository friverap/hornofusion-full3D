!===============================================================================
! mod_species_transport.f90 - Species transport for CO and CO2 mass fractions
!
! Solves: d(alpha_g*rho_g*Y)/dt + div(alpha_g*rho_g*u*Y)
!       = div(alpha_g*rho_g*D_eff*grad(Y)) + S_net   [kg/(m3·s)]
!
! D_eff = mu_eff / (rho_g * Sc_t)   with Sc_t = cfg%Sc_t_species
! Discretized: implicit Euler, upwind convection, central diffusion.
! Pattern is identical to solve_energy_3d with rho*cp replaced by rho.
!
! Auditoria 12-oct-2026:
!  M14: la masa del gas la fija la ecuacion de estado (no hay continuidad
!       del gas con fuente), asi que la masa que las reacciones aportan al gas
!       (S_gas = sum S_k; p.ej. el carbono del solido en C -> CO) desplaza
!       mezcla: la ecuacion en fraccion masica es
!          alpha rho DY_k/Dt = S_k - Y_k S_gas
!       (el inerte implicito 1 - sum Y recibe -Y_in S_gas). Sin el termino de
!       dilucion sum Y llegaba a 1.17 (aire -> CO).
!  M16: conductancia difusiva de CARA = media armonica de alpha*mu_eff/Sc_t
!       (antes alpha rho D de la celda P: no simetrica, no telescopaba) y nula
!       hacia celdas sin gas; tampoco se acepta conveccion entrante desde una
!       celda sin gas (su Y es rancia).
!===============================================================================
module mod_species_transport
    use mod_constants
    use mod_types_3d
    use mod_solver_3d
    use mod_boundary_3d
    use mod_parallel_utils
    use mod_face_flux
    implicit none

contains

    subroutine solve_species_3d(gas, Y, Y_old, S_net, S_gas, m, cfg, residual)
        use mod_workspace, only: ensure_workspace, aW => ws_aW, &
            aE => ws_aE, aS => ws_aS, aN => ws_aN, aB => ws_aB, &
            aT => ws_aT, aP => ws_aP, Su => ws_Su
        type(phase_t), intent(in)    :: gas
        real(dp),      intent(inout) :: Y(-1:,-1:,-1:)
        real(dp),      intent(in)    :: Y_old(-1:,-1:,-1:)
        real(dp),      intent(in)    :: S_net(-1:,-1:,-1:)   ! [kg/(m3·s)]
        ! fuente NETA de masa del gas (suma de las especies) [kg/(m3·s)] (M14)
        real(dp),      intent(in)    :: S_gas(-1:,-1:,-1:)
        type(mesh_t),  intent(in)    :: m
        type(config_t),intent(in)    :: cfg
        real(dp),      intent(out)   :: residual

        integer :: i, j, k, jm, jp
        integer :: istart, iend, jstart, jend, kstart, kend
        real(dp) :: Fw, Fe, Fs, Fn, Fb, Ft
        real(dp) :: Dw, De, Ds, Dn, Db, Dt
        real(dp) :: rho_f, vol, rho_Y_vol_dt
        real(dp) :: alpha_f

        ! Get loop bounds
        call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)

        ! Allocate coefficient arrays (same bounds as Y via mold)
        call ensure_workspace(m)

        aW = 0.0_dp; aE = 0.0_dp; aS = 0.0_dp; aN = 0.0_dp
        aB = 0.0_dp; aT = 0.0_dp; aP = 0.0_dp; Su = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    if (m%cell_type(i,j,k) == 0) cycle

                    vol     = m%vol(i,j,k)
                    alpha_f = gas%alpha(i,j,k)

                    ! Negligible gas fraction: keep Y = Y_old
                    if (alpha_f < 1.0e-6_dp) then
                        aP(i,j,k) = 1.0_dp
                        Su(i,j,k) = Y_old(i,j,k)
                        cycle
                    end if

                    rho_f        = gas%rho(i,j,k)
                    rho_Y_vol_dt = alpha_f * rho_f * vol / cfg%dt

                    ! --- Conductancias difusivas de CARA (M16) ---
                    Dw = gface(i-1,j,k) * m%Ar(i-1,j,k) / (0.5_dp * (m%dr(i) + m%dr(i-1)))
                    De = gface(i+1,j,k) * m%Ar(i,j,k)   / (0.5_dp * (m%dr(i) + m%dr(i+1)))
                    Ds = gface(i,jm,k) * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jm)))
                    Dn = gface(i,jp,k) * m%Ath(i,j,k) / &
                         (m%r(i) * 0.5_dp * (m%dtheta(j) + m%dtheta(jp)))
                    Db = gface(i,j,k-1) * m%Az(i,j,k-1) / (0.5_dp * (m%dz(k) + m%dz(k-1)))
                    Dt = gface(i,j,k+1) * m%Az(i,j,k)   / (0.5_dp * (m%dz(k) + m%dz(k+1)))

                    ! --- Convection fluxes (upwind) ---
                    Fw = 0.0_dp; Fe = 0.0_dp; Fs = 0.0_dp; Fn = 0.0_dp
                    Fb = 0.0_dp; Ft = 0.0_dp

                    if (cfg%solve_flow) then
                        ! Flujos de cara únicos y conservativos (C2.2)
                        call face_mass_fluxes(gas%alpha, gas%rho, gas%ur, &
                            gas%uth, gas%uz, m, i, j, k, Fw, Fe, Fs, Fn, Fb, Ft)
                    end if

                    ! Upwind coefficients; sin entrada desde celdas sin gas (M16)
                    aW(i,j,k) = Dw + merge(max( Fw, 0.0_dp), 0.0_dp, has_gas(i-1,j,k))
                    aE(i,j,k) = De + merge(max(-Fe, 0.0_dp), 0.0_dp, has_gas(i+1,j,k))
                    aS(i,j,k) = Ds + merge(max( Fs, 0.0_dp), 0.0_dp, has_gas(i,jm,k))
                    aN(i,j,k) = Dn + merge(max(-Fn, 0.0_dp), 0.0_dp, has_gas(i,jp,k))
                    aB(i,j,k) = Db + merge(max( Fb, 0.0_dp), 0.0_dp, has_gas(i,j,k-1))
                    aT(i,j,k) = Dt + merge(max(-Ft, 0.0_dp), 0.0_dp, has_gas(i,j,k+1))

                    ! Source: transient + species net source
                    Su(i,j,k) = rho_Y_vol_dt * Y_old(i,j,k) + S_net(i,j,k) * vol

                    ! Central coefficient
                    ! Forma ACOTADA de Patankar (sin dF; ver mod_energy)
                    aP(i,j,k) = aW(i,j,k) + aE(i,j,k) + aS(i,j,k) + aN(i,j,k) &
                               + aB(i,j,k) + aT(i,j,k) + rho_Y_vol_dt

                    ! Dilucion por la masa que entra/sale del gas (M14):
                    ! -Y_k S_gas, implicito si S_gas > 0 (acotado), explicito
                    ! con Y_old (positivo) si S_gas < 0
                    if (S_gas(i,j,k) > 0.0_dp) then
                        aP(i,j,k) = aP(i,j,k) + S_gas(i,j,k) * vol
                    else
                        Su(i,j,k) = Su(i,j,k) - S_gas(i,j,k) * vol * Y_old(i,j,k)
                    end if
                end do
            end do
        end do

        ! Neumann BC at all boundaries (zero-gradient): Y_bc = 0.0
        call apply_scalar_bc(aW, aE, aS, aN, aB, aT, aP, Su, m, 0.0_dp)

        ! Solve with MPI-aware TDMA
        call tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, Y, m, cfg%max_inner_mom)

        ! (Sin sub-relajacion: las especies se resuelven UNA vez por paso, fuera
        ! del lazo externo, asi que Y_old es Y^n y relajar contra el es relajar
        ! contra el paso temporal. Con 0.5 la quimica consumia todo el O2 del
        ! paso pero el solver aplicaba la mitad del sumidero: se oxidaba ~2x el
        ! O2 existente (auditoria 12-oct-2026, A2). alpha_Y_species queda sin
        ! efecto.)

        ! Clip to physical bounds [0, 1]
        where (Y < 0.0_dp) Y = 0.0_dp
        where (Y > 1.0_dp) Y = 1.0_dp

        ! Residual
        residual = compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, Y, m)


    contains

        logical function has_gas(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            has_gas = .false.
            if (m%cell_type(ii,jj,kk) == 0) return   ! sin cortocircuito en Fortran
            has_gas = gas%alpha(ii,jj,kk) >= 1.0e-6_dp
        end function has_gas

        ! alpha rho D_eff de cara = media armonica de alpha mu_eff/Sc_t
        ! (rho se cancela); nula si alguna de las dos celdas no tiene gas
        real(dp) function gface(ii, jj, kk)
            integer, intent(in) :: ii, jj, kk
            real(dp) :: gp, gn
            gface = 0.0_dp
            if (.not. has_gas(ii, jj, kk)) return
            gp = gas%alpha(i,j,k) * gas%mu_eff(i,j,k) / cfg%Sc_t_species
            gn = gas%alpha(ii,jj,kk) * gas%mu_eff(ii,jj,kk) / cfg%Sc_t_species
            if (gp + gn > 0.0_dp) gface = 2.0_dp * gp * gn / (gp + gn)
        end function gface

    end subroutine solve_species_3d

end module mod_species_transport
