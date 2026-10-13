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
        real(dp) :: x_elec, y_elec, x_cell, y_cell, dist
        real(dp) :: dz, z_glob, z_scrap, z_liq, z_surf, z_target

        do e = 1, N_ELECTRODES
            x_elec = cfg%R_pcd * cos(elec(e)%theta_pos)
            y_elec = cfg%R_pcd * sin(elec(e)%theta_pos)

            ! Superficie del material bajo el electrodo (radio 2 R_elec): tope
            ! de la chatarra y tope del bano continuo, ambos GLOBALES (si no,
            ! el estado del electrodo diverge entre ranks)
            z_scrap = -1.0_dp; z_liq = -1.0_dp   ! -1: sin material bajo el electrodo
            do k_tip = m%nz, 1, -1
                do j = 1, m%ntheta
                    do i = 1, m%nr
                        if (m%cell_type(i,j,k_tip) == 0) cycle
                        x_cell = m%r(i) * cos(m%theta(j))
                        y_cell = m%r(i) * sin(m%theta(j))
                        dist = sqrt((x_cell - x_elec)**2 + (y_cell - y_elec)**2)
                        if (dist > cfg%R_elec * 2.0_dp) cycle
                        if (sol%alpha_s(i,j,k_tip) > 0.01_dp) z_scrap = max(z_scrap, m%zf(k_tip))
                        if (liq%alpha(i,j,k_tip) >= ALPHA_LIQ_CONT) z_liq = max(z_liq, m%zf(k_tip))
                    end do
                end do
            end do
            if (m%is_parallel) then
                call mpi_allreduce_max(z_scrap, z_glob, m%topo); z_scrap = z_glob
                call mpi_allreduce_max(z_liq,   z_glob, m%topo); z_liq   = z_glob
            end if
            z_surf = max(z_scrap, z_liq)
            if (z_surf < 0.0_dp) z_surf = cfg%H_bowl
            z_target = z_surf + elec(e)%arc_length

            if (.not. elec(e)%bore_in_done) then
                ! Perforacion (auditoria 12-oct-2026, A10): la punta sigue a la
                ! superficie de la chatarra bajo el electrodo (el arco funde el
                ! crater) a la distancia l_a, bajando como maximo a
                ! BORE_IN_SPEED. Termina cuando el material de arriba bajo el
                ! electrodo es BANO (o al llegar al fondo). Antes bajaba a
                ! velocidad fija y terminaba al tocar la CIMA de la chatarra.
                dz = max(-BORE_IN_SPEED * dt, min(ELEC_SPEED_MAX * dt, z_target - elec(e)%z_tip))
                elec(e)%z_tip = elec(e)%z_tip + dz
                if (z_liq >= 0.0_dp .and. z_liq >= z_scrap) elec(e)%bore_in_done = .true.
                if (elec(e)%z_tip <= cfg%H_bowl + 0.1_dp) elec(e)%bore_in_done = .true.
            else
                ! Regulacion (C2): la punta sigue a superficie + l_a(V)
                dz = (z_target - elec(e)%z_tip) * min(1.0_dp, dt / TAU_REG)
                dz = max(-ELEC_SPEED_MAX * dt, min(ELEC_SPEED_MAX * dt, dz))
                elec(e)%z_tip = elec(e)%z_tip + dz
            end if
            elec(e)%z_tip = max(elec(e)%z_tip, cfg%H_bowl + 0.05_dp)
            elec(e)%z_tip = min(elec(e)%z_tip, cfg%H_total - 0.1_dp)
        end do

    end subroutine update_electrodes

end module mod_electrode_3d
