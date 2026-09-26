# Candidato B (F2.12-B): en caras NO enlazadas al Poisson el liquido que entra a
# una celda del LECHO desde una celda libre lo hace como maximo a la velocidad
# terminal de Ergun (percolation_velocity con la alpha del dador): la lluvia
# dispersa bajo el jet del arco (drift = gas, 20 m/s) llenaba la celda del lecho
# en 0.05 s hasta el cap y respondia con 50-80 kPa (B1 v30, rafagas de fusion).
import sys; root=sys.argv[1]
p=root+'/src/mod_continuity.f90'; s=open(p).read()
old="        call face_fluxes_noalpha_all(liq, m, ur_e, uth_e, uz_e, cont, Gr, Gth, Gz)\n"
new="        call face_fluxes_noalpha_all(liq, gas, sol, cfg, m, ur_e, uth_e, uz_e, cont, Gr, Gth, Gz)\n"
assert old in s; s=s.replace(old,new,1)
old="""    subroutine face_fluxes_noalpha_all(liq, m, ur_e, uth_e, uz_e, cont, Gr, Gth, Gz)
        type(phase_t), intent(in) :: liq
        type(mesh_t), intent(in)  :: m
"""
new="""    subroutine face_fluxes_noalpha_all(liq, gas, sol, cfg, m, ur_e, uth_e, uz_e, cont, Gr, Gth, Gz)
        type(phase_t), intent(in) :: liq, gas
        type(solid_t), intent(in) :: sol
        type(config_t), intent(in) :: cfg
        type(mesh_t), intent(in)  :: m
"""
assert old in s; s=s.replace(old,new,1)
old="""                    if (.not. ws_Fc_valid) cycle
                    if (ws_Fc_lk_r(i,j,k) == 1) &"""
new="""                    ! Entrada al LECHO (F2.12-B): en la cara libre|lecho el flujo
                    ! hacia la celda del lecho no supera la terminal de Ergun del
                    ! liquido que llega (alpha del dador). Solo caras no enlazadas
                    ! (las enlazadas las gobierna el Poisson, abajo).
                    if (.not. (ws_Fc_valid .and. ws_Fc_lk_r(i,j,k) == 1)) &
                        Gr(i,j,k) = bed_entry_cap(Gr(i,j,k), i, j, k, i+1, j, k, m%Ar(i,j,k))
                    if (.not. (ws_Fc_valid .and. ws_Fc_lk_th(i,j,k) == 1)) &
                        Gth(i,j,k) = bed_entry_cap(Gth(i,j,k), i, j, k, i, j+1, k, m%Ath(i,j,k))
                    if (.not. (ws_Fc_valid .and. ws_Fc_lk_z(i,j,k) == 1)) &
                        Gz(i,j,k) = bed_entry_cap(Gz(i,j,k), i, j, k, i, j, k+1, m%Az(i,j,k))
                    if (.not. ws_Fc_valid) cycle
                    if (ws_Fc_lk_r(i,j,k) == 1) &"""
assert old in s; s=s.replace(old,new,1)
old="""        call mpi_exchange_halos_3d(Gr,  m%topo)
        call mpi_exchange_halos_3d(Gth, m%topo)
        call mpi_exchange_halos_3d(Gz,  m%topo)
    end subroutine face_fluxes_noalpha_all
"""
new="""        call mpi_exchange_halos_3d(Gr,  m%topo)
        call mpi_exchange_halos_3d(Gth, m%topo)
        call mpi_exchange_halos_3d(Gz,  m%topo)

    contains

        ! Cara orientada de lo (i,j,k) a hi: si el flujo G (rho u_f A, > 0 hacia
        ! hi) entra a una celda del lecho desde una celda libre, |u_f| se acota a
        ! la velocidad terminal de Ergun del liquido del dador en ese lecho
        pure function bed_entry_cap(G, il, jl, kl, ih, jh, kh, A) result(Gc)
            real(dp), intent(in) :: G, A
            integer,  intent(in) :: il, jl, kl, ih, jh, kh
            real(dp) :: Gc, u_t, Gmax
            logical  :: bed_lo, bed_hi
            Gc = G
            if (m%cell_type(ih,jh,kh) == 0) return
            bed_lo = sol%alpha_s(il,jl,kl) >= 1.0e-2_dp
            bed_hi = sol%alpha_s(ih,jh,kh) >= 1.0e-2_dp
            if (bed_lo .eqv. bed_hi) return
            if (G > 0.0_dp .and. bed_hi) then          ! lo (libre) dona hacia el lecho hi
                u_t = percolation_velocity(liq%alpha(il,jl,kl), sol%alpha_s(ih,jh,kh), &
                          liq%rho(il,jl,kl), gas%rho(il,jl,kl), liq%mu(il,jl,kl), cfg%d_particle)
                Gmax = liq%rho(il,jl,kl) * u_t * A
                Gc = min(G, Gmax)
            else if (G < 0.0_dp .and. bed_lo) then     ! hi (libre) dona hacia el lecho lo
                u_t = percolation_velocity(liq%alpha(ih,jh,kh), sol%alpha_s(il,jl,kl), &
                          liq%rho(ih,jh,kh), gas%rho(ih,jh,kh), liq%mu(ih,jh,kh), cfg%d_particle)
                Gmax = liq%rho(ih,jh,kh) * u_t * A
                Gc = max(G, -Gmax)
            end if
        end function bed_entry_cap
    end subroutine face_fluxes_noalpha_all
"""
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print('B ok')
