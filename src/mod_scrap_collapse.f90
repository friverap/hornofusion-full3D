!===============================================================================
! mod_scrap_collapse.f90 - Vertical stack collapse model
!
! At each time step, scan columns (for each r,theta):
!   If a cell has alpha_s > 0 but cell below has alpha_s = 0 (void),
!   the solid "falls" -- redistribute mass downward conservatively.
!===============================================================================
module mod_scrap_collapse
    use mod_constants
    use mod_types_3d
    use mod_parallel_utils
    implicit none

contains

    subroutine apply_scrap_collapse(sol, m, cfg)
        type(solid_t), intent(inout) :: sol
        type(mesh_t), intent(in)     :: m
        type(config_t), intent(in)   :: cfg

        integer :: i, j, k, k_below, k_dest
        real(dp) :: m_falling, E_falling, T_falling
        integer  :: lid_falling
        logical  :: did_collapse

        did_collapse = .false.

        do j = 1, m%ntheta
            do i = 1, m%nr
                ! Sweep top-to-bottom: if cell has solid and cell below is empty, drop
                do k = m%nz, 2, -1
                    if (m%cell_type(i,j,k) == 0) cycle
                    if (sol%alpha_s(i,j,k) < 1.0e-6_dp) cycle

                    k_below = k - 1

                    ! Find lowest empty cell below this one
                    if (m%cell_type(i,j,k_below) == 0) cycle
                    if (sol%alpha_s(i,j,k_below) > 0.01_dp) cycle

                    ! Solid has void below -- it falls
                    ! Find destination: lowest empty cell in column
                    k_dest = k_below
                    do while (k_dest > 1)
                        if (m%cell_type(i,j,k_dest-1) == 0) exit
                        if (sol%alpha_s(i,j,k_dest-1) > 0.01_dp) exit
                        k_dest = k_dest - 1
                    end do

                    ! Transfer solid mass from k to k_dest
                    m_falling   = sol%m_s(i,j,k)
                    E_falling   = sol%E_s(i,j,k)
                    T_falling   = sol%T_s(i,j,k)
                    lid_falling = sol%layer_id(i,j,k)

                    ! Remove from source
                    sol%m_s(i,j,k) = 0.0_dp
                    sol%E_s(i,j,k) = 0.0_dp
                    sol%alpha_s(i,j,k) = 0.0_dp
                    sol%layer_id(i,j,k) = 0

                    ! Add to destination (merge with existing if any)
                    sol%m_s(i,j,k_dest)     = sol%m_s(i,j,k_dest) + m_falling
                    sol%E_s(i,j,k_dest)     = sol%E_s(i,j,k_dest) + E_falling
                    sol%layer_id(i,j,k_dest) = lid_falling

                    ! Recompute alpha_s and T_s
                    if (m%vol(i,j,k_dest) > SMALL) then
                        sol%alpha_s(i,j,k_dest) = sol%m_s(i,j,k_dest) / &
                                                    (cfg%rho_steel * m%vol(i,j,k_dest))
                    end if
                    sol%alpha_s(i,j,k_dest) = min(1.0_dp, sol%alpha_s(i,j,k_dest))

                    if (sol%m_s(i,j,k_dest) > SMALL) then
                        sol%T_s(i,j,k_dest) = sol%E_s(i,j,k_dest) / &
                                               (sol%m_s(i,j,k_dest) * cfg%cp_s)
                    end if

                    did_collapse = .true.
                end do
            end do
        end do

    end subroutine apply_scrap_collapse

end module mod_scrap_collapse
