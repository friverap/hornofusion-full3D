!===============================================================================
! mod_scrap_collapse.f90 - Vertical stack collapse model
!
! At each time step, scan columns (for each r,theta):
!   If a cell has alpha_s > 0 but cell below has alpha_s = 0 (void),
!   the solid "falls" -- redistribute mass downward conservatively.
!
! Implementación invariante a la descomposición (C1.2, hallazgo 3.6): el
! colapso es una operación de COLUMNA GLOBAL en z, pero z está descompuesta
! en MPI; operar solo sobre el rango local impedía que la chatarra cayera a
! través de las interfaces de rank (medido: 528 celdas colapsadas en -n 1
! vs 336 en -n 8). Igual que distribute_arc_heat: se replican los campos
! del sólido globalmente, se colapsa sobre la malla GLOBAL en el mismo
! orden que en serial, y cada rank escribe de vuelta solo sus celdas.
!===============================================================================
module mod_scrap_collapse
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    use mod_melting_3d, only: solid_T_from_enthalpy
    implicit none

contains

    subroutine apply_scrap_collapse(sol, m, cfg)
        type(solid_t), intent(inout) :: sol
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k, k_below, k_dest
        integer :: il, jl, kl
        logical :: owned
        real(dp) :: m_falling, E_falling
        integer  :: lid_falling
        real(dp), allocatable :: m_g(:,:,:), E_g(:,:,:), a_g(:,:,:), T_g(:,:,:)
        real(dp), allocatable :: mc_g(:,:,:)
        integer,  allocatable :: lid_g(:,:,:)

        allocate(m_g(m%nr_g, m%nth_g, m%nz_g), E_g(m%nr_g, m%nth_g, m%nz_g))
        allocate(a_g(m%nr_g, m%nth_g, m%nz_g), T_g(m%nr_g, m%nth_g, m%nz_g))
        allocate(lid_g(m%nr_g, m%nth_g, m%nz_g))
        allocate(mc_g(m%nr_g, m%nth_g, m%nz_g))

        call gather_global_field(sol%m_s, m_g, m)
        call gather_global_field(sol%E_s, E_g, m)
        call gather_global_field(sol%alpha_s, a_g, m)
        call gather_global_field(sol%T_s, T_g, m)
        call gather_global_field(sol%m_C, mc_g, m)
        call gather_global_field_int(sol%layer_id, lid_g, m)

        do j = 1, m%nth_g
            do i = 1, m%nr_g
                ! Sweep top-to-bottom: if cell has solid and cell below is empty, drop
                do k = m%nz_g, 2, -1
                    if (m%cell_type_global(i,j,k) == 0) cycle
                    if (a_g(i,j,k) < 1.0e-6_dp) cycle

                    k_below = k - 1

                    ! Find lowest empty cell below this one
                    if (m%cell_type_global(i,j,k_below) == 0) cycle
                    if (a_g(i,j,k_below) > 0.01_dp) cycle

                    ! Solid has void below -- it falls
                    ! Find destination: lowest empty cell in column
                    k_dest = k_below
                    do while (k_dest > 1)
                        if (m%cell_type_global(i,j,k_dest-1) == 0) exit
                        if (a_g(i,j,k_dest-1) > 0.01_dp) exit
                        k_dest = k_dest - 1
                    end do

                    ! Transfer solid mass from k to k_dest
                    m_falling   = m_g(i,j,k)
                    E_falling   = E_g(i,j,k)
                    lid_falling = lid_g(i,j,k)

                    ! Remove from source
                    mc_g(i,j,k_dest) = mc_g(i,j,k_dest) + mc_g(i,j,k)
                    mc_g(i,j,k) = 0.0_dp
                    m_g(i,j,k) = 0.0_dp
                    E_g(i,j,k) = 0.0_dp
                    a_g(i,j,k) = 0.0_dp
                    lid_g(i,j,k) = 0

                    ! Add to destination (merge with existing if any)
                    m_g(i,j,k_dest)   = m_g(i,j,k_dest) + m_falling
                    E_g(i,j,k_dest)   = E_g(i,j,k_dest) + E_falling
                    lid_g(i,j,k_dest) = lid_falling

                    ! Recompute alpha_s and T_s
                    if (m%vol_global(i,j,k_dest) > SMALL) then
                        a_g(i,j,k_dest) = m_g(i,j,k_dest) / &
                                          (cfg%rho_steel * m%vol_global(i,j,k_dest))
                    end if
                    a_g(i,j,k_dest) = min(1.0_dp, a_g(i,j,k_dest))

                    if (m_g(i,j,k_dest) > SMALL) then
                        T_g(i,j,k_dest) = solid_T_from_enthalpy( &
                            E_g(i,j,k_dest) / m_g(i,j,k_dest), cfg)
                    end if
                end do
            end do
        end do

        ! Write back: solo las celdas propias de este rank
        do k = 1, m%nz_g
            do j = 1, m%nth_g
                do i = 1, m%nr_g
                    call global_to_local(m, i, j, k, il, jl, kl, owned)
                    if (.not. owned) cycle
                    sol%m_s(il,jl,kl)      = m_g(i,j,k)
                    sol%E_s(il,jl,kl)      = E_g(i,j,k)
                    sol%alpha_s(il,jl,kl)  = a_g(i,j,k)
                    sol%T_s(il,jl,kl)      = T_g(i,j,k)
                    sol%layer_id(il,jl,kl) = lid_g(i,j,k)
                    sol%m_C(il,jl,kl)      = mc_g(i,j,k)
                end do
            end do
        end do

        deallocate(m_g, E_g, a_g, T_g, lid_g, mc_g)

    end subroutine apply_scrap_collapse

end module mod_scrap_collapse
