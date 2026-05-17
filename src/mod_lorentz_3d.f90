!===============================================================================
! mod_lorentz_3d.f90 - Lorentz / electromagnetic stirring forces for EAF bath
!
! Simplified analytical model (no Poisson solve):
!
!   Current I flows downward (-z) from each electrode through the liquid bath.
!   Distribution: J_z(r_loc) = -I * exp(-r_loc^2/σ_J^2) / (π σ_J^2)
!   where r_loc = horizontal distance from electrode axis, σ_J = 3*R_elec.
!
!   Magnetic field from Ampere's law (around electrode axis):
!   B_mag(r_loc) = μ₀ * I_enc(r_loc) / (2π r_loc)
!   I_enc(r_loc) = I * (1 - exp(-r_loc^2/σ_J^2))
!
!   Lorentz force:  F = J × B   (J = J_z ẑ, B horizontal around electrode axis)
!   F = -(J_z * B_mag / r_loc) * (ξ x̂ + η ŷ)      [N/m³, Cartesian]
!   With J_z < 0: F points OUTWARD from electrode → creates bath stirring.
!
!   Converted to cylindrical furnace coordinates (r̂, θ̂) and applied only
!   where liquid phase is present (alpha_l > threshold).
!
! Reference: Trindade & Vilela (2020), ISIJ Int. 60(7) — simplified MHD for EAF.
!===============================================================================
module mod_lorentz_3d
    use mod_constants
    use mod_types_3d
    implicit none

contains

    !---------------------------------------------------------------------------
    ! Compute Lorentz force density and store in sh%F_lorentz_r/th
    !
    !   elec        : electrode array (position, current)
    !   alpha_l     : liquid volume fraction (-1:,-1:,-1:)
    !   sh          : shared fields (F_lorentz_r/th are updated here)
    !   m           : mesh
    !   cfg         : configuration (R_elec, R_pcd)
    !   I_electrode : electrode current [A] (from profile interpolation)
    !   n_elec      : number of electrodes
    !---------------------------------------------------------------------------
    subroutine compute_lorentz_force(elec, alpha_l, sh, m, cfg, I_electrode, n_elec)
        type(electrode_t), intent(in)   :: elec(:)
        real(dp), intent(in)            :: alpha_l(-1:,-1:,-1:)
        type(shared_t), intent(inout)   :: sh
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        real(dp), intent(in)            :: I_electrode
        integer, intent(in)             :: n_elec

        integer  :: e, i, j, k
        real(dp) :: x_elec, y_elec, x_cell, y_cell
        real(dp) :: xi, eta, r_loc, r2_loc
        real(dp) :: sigma_J, sigma_J2
        real(dp) :: exp_fac, J_z_local, I_enc, B_mag
        real(dp) :: F_cart_x, F_cart_y
        real(dp) :: F_r_local, F_th_local
        real(dp) :: alpha_liq

        ! σ_J: current spreads to 3× electrode radius
        sigma_J  = cfg%R_elec * 3.0_dp
        sigma_J2 = sigma_J**2

        sh%F_lorentz_r  = 0.0_dp
        sh%F_lorentz_th = 0.0_dp

        ! No current → no Lorentz force
        if (abs(I_electrode) < 1.0_dp) return

        do e = 1, n_elec
            x_elec = cfg%R_pcd * cos(elec(e)%theta_pos)
            y_elec = cfg%R_pcd * sin(elec(e)%theta_pos)

            do k = 1, m%nz
                do j = 1, m%ntheta
                    do i = 1, m%nr
                        if (m%cell_type(i,j,k) == 0) cycle

                        ! Apply only where liquid is present
                        alpha_liq = alpha_l(i,j,k)
                        if (alpha_liq < 1.0e-4_dp) cycle

                        ! Horizontal displacement from electrode axis
                        x_cell = m%r(i) * cos(m%theta(j))
                        y_cell = m%r(i) * sin(m%theta(j))
                        xi  = x_cell - x_elec
                        eta = y_cell - y_elec
                        r_loc = sqrt(xi**2 + eta**2)

                        ! Avoid singularity at electrode center
                        if (r_loc < 1.0e-3_dp) cycle

                        r2_loc  = (xi**2 + eta**2) / sigma_J2
                        exp_fac = exp(-r2_loc)

                        ! Current density: J_z < 0 (current flows DOWN: electrode → bath)
                        J_z_local = -I_electrode * exp_fac / (PI * sigma_J2)

                        ! Enclosed current fraction within r_loc
                        I_enc = I_electrode * (1.0_dp - exp_fac)

                        ! Azimuthal B field around electrode axis (Ampere's law)
                        B_mag = MU_0 * I_enc / (TWO_PI * r_loc)

                        ! Lorentz force in Cartesian:
                        !   F = J×B = J_z ẑ × (B_x x̂ + B_y ŷ)
                        !   F_x = -J_z * B_y = -J_z * B_mag * (ξ/r_loc)
                        !   F_y = +J_z * B_x = -J_z * B_mag * (η/r_loc)   [B_x = -B_mag*(η/r_loc)]
                        ! Combined: F = -(J_z * B_mag / r_loc) * (ξ, η)
                        ! With J_z < 0: F points OUTWARD → bath stirring
                        F_cart_x = -(J_z_local * B_mag / r_loc) * xi
                        F_cart_y = -(J_z_local * B_mag / r_loc) * eta

                        ! Convert to cylindrical furnace coordinates
                        F_r_local  =  F_cart_x * cos(m%theta(j)) + F_cart_y * sin(m%theta(j))
                        F_th_local = -F_cart_x * sin(m%theta(j)) + F_cart_y * cos(m%theta(j))

                        ! Accumulate (weight by liquid fraction: force acts on liquid volume)
                        sh%F_lorentz_r(i,j,k)  = sh%F_lorentz_r(i,j,k)  + alpha_liq * F_r_local
                        sh%F_lorentz_th(i,j,k) = sh%F_lorentz_th(i,j,k) + alpha_liq * F_th_local

                    end do
                end do
            end do
        end do

    end subroutine compute_lorentz_force

end module mod_lorentz_3d
