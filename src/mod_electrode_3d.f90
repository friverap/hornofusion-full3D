!===============================================================================
! mod_electrode_3d.f90 - Electrode positioning and regulation for 3 AC electrodes
!
! 3 electrodes at theta = 0, 2pi/3, 4pi/3 on pitch circle R_pcd.
! Bore-in regulation: electrodes descend through scrap until reaching liquid.
! Regulacion posterior (auditoria 12-oct-2026, C2): la punta busca
!     z_tip = z_superficie + l_a,   l_a = (|V| - V_umbral)/E_columna
! donde z_superficie es el tope del material bajo el electrodo (chatarra o
! bano continuo), con ganancia por unidad de TIEMPO (constante TAU_REG) y
! velocidad acotada. Antes el error era l_a(V) - 0.20 m, sin ninguna
! dependencia de z_tip (lazo abierto), con l_a en cm tratada como m: la punta
! bajaba siempre hasta H_bowl + 0.05.
!===============================================================================
module mod_electrode_3d
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology, only: mpi_allreduce_max
    implicit none

    real(dp), parameter :: BORE_IN_SPEED  = 0.01_dp   ! m/s descent rate
    ! Longitud de arco de referencia SOLO para reconstruir la punta al reiniciar
    ! desde snapshots sin estado de electrodos (mod_restart)
    real(dp), parameter :: ARC_LENGTH_SET = 0.20_dp    ! m
    real(dp), parameter :: ELEC_SPEED_MAX = 0.005_dp   ! m/s max regulation speed
    real(dp), parameter :: TAU_REG        = 1.0_dp     ! s constante del regulador

contains

    subroutine update_electrodes(elec, sol, liq, m, cfg, dt)
        type(electrode_t), intent(inout) :: elec(:)
        type(solid_t), intent(in)       :: sol
        type(phase_t), intent(in)       :: liq
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        real(dp), intent(in)            :: dt

        integer :: e, i, j, k_tip
        real(dp) :: z_scrap_top, x_elec, y_elec, x_cell, y_cell, dist
        real(dp) :: dz, z_top_global, z_surf, z_target

        do e = 1, N_ELECTRODES
            x_elec = cfg%R_pcd * cos(elec(e)%theta_pos)
            y_elec = cfg%R_pcd * sin(elec(e)%theta_pos)

            ! Find scrap top below electrode
            z_scrap_top = 0.0_dp
            do k_tip = m%nz, 1, -1
                do j = 1, m%ntheta
                    do i = 1, m%nr
                        x_cell = m%r(i) * cos(m%theta(j))
                        y_cell = m%r(i) * sin(m%theta(j))
                        dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                        if (dist <= cfg%R_elec * 2.0_dp) then
                            if (sol%alpha_s(i,j,k_tip) > 0.01_dp) then
                                z_scrap_top = max(z_scrap_top, m%zf(k_tip))
                            end if
                        end if
                    end do
                end do
                if (z_scrap_top > 0.0_dp) exit
            end do

            ! Parallel: the scrap top must be GLOBAL — otherwise bore_in_done
            ! diverges across ranks and electrode state becomes inconsistent
            if (m%is_parallel) then
                call mpi_allreduce_max(z_scrap_top, z_top_global, m%topo)
                z_scrap_top = z_top_global
            end if

            if (.not. elec(e)%bore_in_done) then
                ! Bore-in phase: descend through scrap
                elec(e)%z_tip = elec(e)%z_tip - BORE_IN_SPEED * dt

                ! Check if we've reached liquid or bottom of scrap
                if (elec(e)%z_tip <= z_scrap_top .or. &
                    elec(e)%z_tip <= cfg%H_bowl + 0.1_dp) then
                    elec(e)%bore_in_done = .true.
                end if

                elec(e)%z_tip = max(elec(e)%z_tip, cfg%H_bowl + 0.05_dp)
            else
                ! Post bore-in: la punta sigue a la superficie del material
                ! bajo el electrodo (chatarra o bano continuo) a la distancia
                ! l_a que fija el voltaje
                z_surf = cfg%H_bowl
                do k_tip = m%nz, 1, -1
                    do j = 1, m%ntheta
                        do i = 1, m%nr
                            if (m%cell_type(i,j,k_tip) == 0) cycle
                            x_cell = m%r(i) * cos(m%theta(j))
                            y_cell = m%r(i) * sin(m%theta(j))
                            dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                            if (dist > cfg%R_elec * 2.0_dp) cycle
                            if (sol%alpha_s(i,j,k_tip) > 0.01_dp .or. &
                                liq%alpha(i,j,k_tip) >= ALPHA_LIQ_CONT) &
                                z_surf = max(z_surf, m%zf(k_tip))
                        end do
                    end do
                end do
                if (m%is_parallel) then
                    call mpi_allreduce_max(z_surf, z_top_global, m%topo)
                    z_surf = z_top_global
                end if
                z_target = z_surf + elec(e)%arc_length
                dz = (z_target - elec(e)%z_tip) * min(1.0_dp, dt / TAU_REG)
                dz = max(-ELEC_SPEED_MAX * dt, min(ELEC_SPEED_MAX * dt, dz))
                elec(e)%z_tip = elec(e)%z_tip + dz
                elec(e)%z_tip = max(elec(e)%z_tip, cfg%H_bowl + 0.05_dp)
                elec(e)%z_tip = min(elec(e)%z_tip, cfg%H_total - 0.1_dp)
            end if
        end do

    end subroutine update_electrodes

end module mod_electrode_3d
