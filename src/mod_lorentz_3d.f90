!===============================================================================
! mod_lorentz_3d.f90 - Fuerza de Lorentz en el baño (auditoria 12-oct-2026, M11)
!
! Modelo de FUENTE PUNTUAL de corriente en un conductor semi-infinito
! (Shercliff, J. Fluid Mech. 40 (1970) 241; Sozou, J. Fluid Mech. 46 (1971)
! 25; Szekely et al., Met. Trans. B 14 (1983) 189): la corriente I de cada
! electrodo entra al baño en el pie del arco P y se reparte radialmente en
! el hemisferio inferior,
!     J = I/(2 pi rho^2) rho_hat,     B_phi = mu0 I (1 - cos th)/(2 pi r_loc)
! (rho = distancia a P, th = angulo con la vertical descendente, r_loc =
! distancia horizontal al eje del electrodo). La fuerza
!     F = J x B = -J B th_hat,  th_hat = cos th e_h + sin th z_hat
! apunta HACIA el eje y HACIA ABAJO, y su rotacional no es nulo: es lo que
! impulsa el chorro descendente bajo el electrodo y la recirculacion del baño.
! El punto fuente P es el MAS BAJO entre el pie del arco (punta - l_a) y el
! tope del baño bajo el electrodo (radio 2 R_elec, reduccion GLOBAL como en
! update_electrodes): con chatarra entre el arco y el baño la corriente entra
! al baño por su superficie. Sin baño bajo el electrodo no hay fuerza.
! Regularizacion en el pie del arco: rho_eff^2 = rho^2 + R_elec^2 (mancha del
! arco del orden del radio del electrodo), es decir fuente a profundidad
! efectiva sqrt(dz^2 + R_elec^2): cos th = dz_ef/rho_eff (N-A3). Con AC la fuerza va con I^2 (no
! cambia de signo); I es el valor eficaz.
!
! Antes (modelo de Trindade-Vilela simplificado): J vertical uniforme en z con
! B de una corriente ASCENDENTE -> fuerza hacia AFUERA (signo invertido),
! puramente radial alrededor del electrodo e independiente de z (un gradiente:
! la absorbia la presion y no agitaba), sumada tambien a la ecuacion del gas y
! aplicada a la niebla del freeboard. Ahora: solo liquido CONTINUO (baño,
! alpha_l >= ALPHA_LIQ_CONT) bajo el pie del arco, y solo en el liquido.
!===============================================================================
module mod_lorentz_3d
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology, only: mpi_allreduce_max
    implicit none

contains

    subroutine compute_lorentz_force(elec, alpha_l, sh, m, cfg, I_electrode, n_elec)
        type(electrode_t), intent(in)   :: elec(:)
        real(dp), intent(in)            :: alpha_l(-1:,-1:,-1:)
        type(shared_t), intent(inout)   :: sh
        type(mesh_t), intent(in)        :: m
        type(config_t), intent(in)      :: cfg
        real(dp), intent(in)            :: I_electrode
        integer, intent(in)             :: n_elec

        integer  :: e, i, j, k
        real(dp) :: x_elec, y_elec, z_att, xi, eta, r_loc, dz, rho2, rho
        real(dp) :: cth, sth, J_rho, B_phi, Fmag, Fh, Fx, Fy, z_bath, z_glob

        sh%F_lorentz_r  = 0.0_dp
        sh%F_lorentz_th = 0.0_dp
        sh%F_lorentz_z  = 0.0_dp
        if (abs(I_electrode) < 1.0_dp) return

        do e = 1, n_elec
            x_elec = cfg%R_pcd * cos(elec(e)%theta_pos)
            y_elec = cfg%R_pcd * sin(elec(e)%theta_pos)
            ! tope del baño bajo el electrodo (global: z esta descompuesta)
            z_bath = -1.0_dp
            do k = 1, m%nz
                do j = 1, m%ntheta
                    do i = 1, m%nr
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (alpha_l(i,j,k) < ALPHA_LIQ_CONT) cycle
                        if ((m%r(i) * cos(m%theta(j)) - x_elec)**2 + &
                            (m%r(i) * sin(m%theta(j)) - y_elec)**2 > (2.0_dp * cfg%R_elec)**2) cycle
                        z_bath = max(z_bath, m%zf(k))
                    end do
                end do
            end do
            if (m%is_parallel) then
                call mpi_allreduce_max(z_bath, z_glob, m%topo); z_bath = z_glob
            end if
            if (z_bath < 0.0_dp) cycle        ! sin baño bajo el electrodo
            ! pie del arco: punta menos la longitud de arco (m, C2), o la
            ! superficie del baño si esta mas abajo
            z_att = min(elec(e)%z_tip - max(elec(e)%arc_length, 0.0_dp), z_bath)

            do k = 1, m%nz
                dz = z_att - m%z(k)            ! profundidad bajo el pie (> 0)
                if (dz <= 0.0_dp) cycle
                do j = 1, m%ntheta
                    do i = 1, m%nr
                        if (m%cell_type(i,j,k) == 0) cycle
                        if (alpha_l(i,j,k) < ALPHA_LIQ_CONT) cycle   ! solo baño

                        xi  = m%r(i) * cos(m%theta(j)) - x_elec
                        eta = m%r(i) * sin(m%theta(j)) - y_elec
                        r_loc = sqrt(xi**2 + eta**2)
                        if (r_loc < 1.0e-6_dp) cycle    ! sobre el eje: F = 0

                        ! Mancha del arco = fuente puntual a profundidad
                        ! EFECTIVA dz_ef = sqrt(dz^2 + R_elec^2) (auditoria 2,
                        ! N-A3): cos th = dz_ef/rho y sin th = r_loc/rho forman
                        ! un vector unitario y la corriente encerrada
                        ! I (1 - cos th) se anula en el eje (B ~ r_loc). Antes
                        ! cos th = dz/rho con el rho regularizado: 1 - cos th no
                        ! se anulaba y B divergia como 1/r_loc junto al eje de
                        ! cada electrodo (0.29 T a 1 cm frente a 5e-4 fisico)
                        rho2 = r_loc**2 + dz**2 + cfg%R_elec**2
                        rho  = sqrt(rho2)
                        cth = sqrt(dz**2 + cfg%R_elec**2) / rho
                        sth = r_loc / rho
                        J_rho = abs(I_electrode) / (TWO_PI * rho2)
                        B_phi = MU_0 * abs(I_electrode) * (1.0_dp - cth) / (TWO_PI * r_loc)
                        Fmag = J_rho * B_phi * alpha_l(i,j,k)

                        ! -th_hat: horizontal hacia el eje, vertical hacia abajo
                        Fh = -Fmag * cth
                        Fx = Fh * xi / r_loc
                        Fy = Fh * eta / r_loc
                        sh%F_lorentz_r(i,j,k)  = sh%F_lorentz_r(i,j,k) &
                            + Fx * cos(m%theta(j)) + Fy * sin(m%theta(j))
                        sh%F_lorentz_th(i,j,k) = sh%F_lorentz_th(i,j,k) &
                            - Fx * sin(m%theta(j)) + Fy * cos(m%theta(j))
                        sh%F_lorentz_z(i,j,k)  = sh%F_lorentz_z(i,j,k) - Fmag * sth
                    end do
                end do
            end do
        end do

    end subroutine compute_lorentz_force

end module mod_lorentz_3d
