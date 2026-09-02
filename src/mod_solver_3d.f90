!===============================================================================
! mod_solver_3d.f90 - Linear solvers for 3D structured grids
!
! Provides:
!   - TDMA (Thomas algorithm) for 1D tridiagonal systems
!   - TDMA line-by-line for 3D: sweep r, theta, z directions
!   - SOR for 3D (pressure Poisson)
!   - Residual computation for 3D discretized equations
!===============================================================================
module mod_solver_3d
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_parallel_utils
    implicit none

contains

    !---------------------------------------------------------------------------
    ! 1D TDMA
    !---------------------------------------------------------------------------
    subroutine tdma(a, b, c, d, x, n)
        integer, intent(in)   :: n
        real(dp), intent(in)  :: a(n), b(n), c(n), d(n)
        real(dp), intent(out) :: x(n)

        real(dp) :: cp(n), dp_arr(n), m_val, b1_safe
        integer  :: i

        b1_safe = b(1)
        if (abs(b1_safe) < SMALL) b1_safe = sign(SMALL, b1_safe)
        cp(1) = c(1) / b1_safe
        dp_arr(1) = d(1) / b1_safe

        do i = 2, n
            m_val = b(i) - a(i) * cp(i-1)
            if (abs(m_val) < SMALL) m_val = sign(SMALL, m_val)
            cp(i) = c(i) / m_val
            dp_arr(i) = (d(i) - a(i) * dp_arr(i-1)) / m_val
        end do

        x(n) = dp_arr(n)
        do i = n-1, 1, -1
            x(i) = dp_arr(i) - cp(i) * x(i+1)
        end do
    end subroutine tdma

    !---------------------------------------------------------------------------
    ! 3D TDMA line-by-line
    !
    ! Coefficient arrays: aW(i-1), aE(i+1) in r
    !                     aS(j-1), aN(j+1) in theta
    !                     aB(k-1), aT(k+1) in z
    ! aP = center coefficient, Su = source
    ! phi = solution field (inout)
    !
    ! n_sweep: number of full r+theta+z sweeps
    !
    ! For periodic theta: neighbors wrap around (j=0 -> ntheta, j=ntheta+1 -> 1)
    !---------------------------------------------------------------------------
    subroutine tdma_3d(aW, aE, aS, aN, aB, aT, aP, Su, phi, &
                       nr, nth, nz, n_sweep)
        integer, intent(in)      :: nr, nth, nz, n_sweep
        real(dp), intent(in)     :: aW(nr,nth,nz), aE(nr,nth,nz)
        real(dp), intent(in)     :: aS(nr,nth,nz), aN(nr,nth,nz)
        real(dp), intent(in)     :: aB(nr,nth,nz), aT(nr,nth,nz)
        real(dp), intent(in)     :: aP(nr,nth,nz), Su(nr,nth,nz)
        real(dp), intent(inout)  :: phi(0:nr+1,0:nth+1,0:nz+1)

        integer :: nmax
        real(dp), allocatable :: a_td(:), b_td(:), c_td(:), d_td(:), x_td(:)
        integer :: i, j, k, sweep

        nmax = max(nr, nth, nz)
        allocate(a_td(nmax), b_td(nmax), c_td(nmax), d_td(nmax), x_td(nmax))

        do sweep = 1, n_sweep

            ! Sweep in r-direction (for each theta,z line)
            do k = 1, nz
                do j = 1, nth

                    do i = 1, nr
                        a_td(i) = -aW(i,j,k)
                        b_td(i) = aP(i,j,k)
                        c_td(i) = -aE(i,j,k)
                        d_td(i) = Su(i,j,k) &
                                + aS(i,j,k) * phi(i,j-1,k) &
                                + aN(i,j,k) * phi(i,j+1,k) &
                                + aB(i,j,k) * phi(i,j,k-1) &
                                + aT(i,j,k) * phi(i,j,k+1)
                    end do
                    call tdma(a_td(1:nr), b_td(1:nr), c_td(1:nr), d_td(1:nr), &
                              x_td(1:nr), nr)
                    phi(1:nr, j, k) = x_td(1:nr)
                end do
            end do

            ! Sweep in theta-direction (for each r,z line)
            do k = 1, nz
                do i = 1, nr
                    do j = 1, nth
                        a_td(j) = -aS(i,j,k)
                        b_td(j) = aP(i,j,k)
                        c_td(j) = -aN(i,j,k)
                        d_td(j) = Su(i,j,k) &
                                + aW(i,j,k) * phi(i-1,j,k) &
                                + aE(i,j,k) * phi(i+1,j,k) &
                                + aB(i,j,k) * phi(i,j,k-1) &
                                + aT(i,j,k) * phi(i,j,k+1)
                    end do
                    call tdma(a_td(1:nth), b_td(1:nth), c_td(1:nth), d_td(1:nth), &
                              x_td(1:nth), nth)
                    phi(i, 1:nth, k) = x_td(1:nth)
                end do
            end do

            ! Sweep in z-direction (for each r,theta line)
            do j = 1, nth
                do i = 1, nr

                    do k = 1, nz
                        a_td(k) = -aB(i,j,k)
                        b_td(k) = aP(i,j,k)
                        c_td(k) = -aT(i,j,k)
                        d_td(k) = Su(i,j,k) &
                                + aS(i,j,k) * phi(i,j-1,k) &
                                + aN(i,j,k) * phi(i,j+1,k) &
                                + aW(i,j,k) * phi(i-1,j,k) &
                                + aE(i,j,k) * phi(i+1,j,k)
                    end do
                    call tdma(a_td(1:nz), b_td(1:nz), c_td(1:nz), d_td(1:nz), &
                              x_td(1:nz), nz)
                    phi(i, j, 1:nz) = x_td(1:nz)
                end do
            end do

        end do

        deallocate(a_td, b_td, c_td, d_td, x_td)
    end subroutine tdma_3d

    !---------------------------------------------------------------------------
    ! 3D SOR solver (for pressure Poisson)
    !---------------------------------------------------------------------------
    subroutine sor_3d(aW, aE, aS, aN, aB, aT, aP, Su, phi, &
                      nr, nth, nz, omega, max_iter, tol, residual, n_iter)
        integer, intent(in)      :: nr, nth, nz, max_iter
        real(dp), intent(in)     :: aW(nr,nth,nz), aE(nr,nth,nz)
        real(dp), intent(in)     :: aS(nr,nth,nz), aN(nr,nth,nz)
        real(dp), intent(in)     :: aB(nr,nth,nz), aT(nr,nth,nz)
        real(dp), intent(in)     :: aP(nr,nth,nz), Su(nr,nth,nz)
        real(dp), intent(inout)  :: phi(nr,nth,nz)
        real(dp), intent(in)     :: omega, tol
        real(dp), intent(out)    :: residual
        integer, intent(out)     :: n_iter

        integer  :: i, j, k, iter, jm, jp
        real(dp) :: phi_new, res_sum, norm_sum, local_res

        do iter = 1, max_iter
            res_sum  = 0.0_dp
            norm_sum = 0.0_dp

            do k = 1, nz
                do j = 1, nth
                    jm = j - 1
                    jp = j + 1

                    do i = 1, nr
                        ! aW(1,*,*)=0 and aT(*,*,nz)=0 after BCs; clamped index is safe
                        phi_new = Su(i,j,k) &
                                + aW(i,j,k) * phi(max(1,i-1),j,k) &
                                + aE(i,j,k) * phi(min(nr,i+1),j,k) &
                                + aS(i,j,k) * phi(i,jm,k) &
                                + aN(i,j,k) * phi(i,jp,k) &
                                + aB(i,j,k) * phi(i,j,max(1,k-1)) &
                                + aT(i,j,k) * phi(i,j,min(nz,k+1))

                        if (abs(aP(i,j,k)) > SMALL) then
                            phi_new = phi_new / aP(i,j,k)
                        end if

                        local_res = phi_new - phi(i,j,k)
                        res_sum  = res_sum + local_res**2
                        norm_sum = norm_sum + phi_new**2

                        phi(i,j,k) = phi(i,j,k) + omega * local_res
                    end do
                end do
            end do

            residual = sqrt(res_sum / max(norm_sum, SMALL))
            n_iter = iter
            if (residual < tol) exit
        end do
    end subroutine sor_3d

    !---------------------------------------------------------------------------
    ! 3D residual computation
    !---------------------------------------------------------------------------
    function compute_residual_3d(aW, aE, aS, aN, aB, aT, aP, Su, phi, &
                                 nr, nth, nz) result(res)
        integer, intent(in)  :: nr, nth, nz
        real(dp), intent(in) :: aW(nr,nth,nz), aE(nr,nth,nz)
        real(dp), intent(in) :: aS(nr,nth,nz), aN(nr,nth,nz)
        real(dp), intent(in) :: aB(nr,nth,nz), aT(nr,nth,nz)
        real(dp), intent(in) :: aP(nr,nth,nz), Su(nr,nth,nz)
        real(dp), intent(in) :: phi(nr,nth,nz)
        real(dp) :: res

        integer  :: i, j, k, jm, jp
        real(dp) :: r_local, sum_r, sum_b

        sum_r = 0.0_dp
        sum_b = 0.0_dp

        do k = 1, nz
            do j = 1, nth
                jm = j - 1
                jp = j + 1

                do i = 1, nr
                    ! aW(1,*,*)=0 and aT(*,*,nz)=0 after BCs; clamped index is safe
                    r_local = Su(i,j,k) - aP(i,j,k) * phi(i,j,k) &
                            + aW(i,j,k) * phi(max(1,i-1),j,k) &
                            + aE(i,j,k) * phi(min(nr,i+1),j,k) &
                            + aS(i,j,k) * phi(i,jm,k) &
                            + aN(i,j,k) * phi(i,jp,k) &
                            + aB(i,j,k) * phi(i,j,max(1,k-1)) &
                            + aT(i,j,k) * phi(i,j,min(nz,k+1))

                    sum_r = sum_r + r_local**2
                    sum_b = sum_b + (abs(Su(i,j,k)) + SMALL)**2
                end do
            end do
        end do

        res = sqrt(sum_r) / (sqrt(sum_b) + SMALL)
    end function compute_residual_3d

    !===========================================================================
    ! MPI-AWARE SOLVERS
    !===========================================================================

    !---------------------------------------------------------------------------
    ! 3D TDMA line-by-line with MPI halo exchange
    ! 
    ! Uses mesh_t to access topology info and local dimensions
    ! Performs halo exchanges before each sweep
    !---------------------------------------------------------------------------
    subroutine tdma_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, phi, m, n_sweep)
        use mod_types_3d
        use mod_mpi_topology
        
        real(dp), intent(in)     :: aW(-1:,-1:,-1:), aE(-1:,-1:,-1:)
        real(dp), intent(in)     :: aS(-1:,-1:,-1:), aN(-1:,-1:,-1:)
        real(dp), intent(in)     :: aB(-1:,-1:,-1:), aT(-1:,-1:,-1:)
        real(dp), intent(in)     :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        real(dp), intent(inout)  :: phi(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer, intent(in)      :: n_sweep

        integer :: nmax, nr, nth, nz
        real(dp), allocatable :: a_td(:), b_td(:), c_td(:), d_td(:), x_td(:)
        integer :: i, j, k, sweep, istart, iend, jstart, jend, kstart, kend
        integer :: jm, jp

        ! Local dimensions
        if (m%is_parallel) then
            nr = m%topo%iloc; nth = m%topo%jloc; nz = m%topo%kloc
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            ! Serial mode - use mesh dimensions directly
            nr = m%nr; nth = m%ntheta; nz = m%nz
            call get_loop_bounds(m, istart, iend, jstart, jend, kstart, kend)
        end if

        nmax = max(nr, nth, nz)
        allocate(a_td(nmax), b_td(nmax), c_td(nmax), d_td(nmax), x_td(nmax))

        do sweep = 1, n_sweep
            ! Exchange halos before each sweep
            call mpi_exchange_halos_3d(phi, m%topo)

            ! Sweep in r-direction
            do k = kstart, kend
                do j = jstart, jend
                    jm = j - 1
                    jp = j + 1
                                        
                    do i = istart, iend
                        a_td(i-istart+1) = -aW(i,j,k)
                        b_td(i-istart+1) = aP(i,j,k)
                        c_td(i-istart+1) = -aE(i,j,k)
                        d_td(i-istart+1) = Su(i,j,k) &
                                + aS(i,j,k) * phi(i,jm,k) &
                                + aN(i,j,k) * phi(i,jp,k)
                        d_td(i-istart+1) = d_td(i-istart+1) + aB(i,j,k) * phi(i,j,k-1) + aT(i,j,k) * phi(i,j,k+1)
                    end do
                    ! Couple segment endpoints to halo data (lagged); at
                    ! physical boundaries aW/aE are zero so this is a no-op
                    d_td(1)  = d_td(1)  + aW(istart,j,k) * phi(istart-1,j,k)
                    d_td(nr) = d_td(nr) + aE(iend,j,k)   * phi(iend+1,j,k)
                    call tdma(a_td(1:nr), b_td(1:nr), c_td(1:nr), d_td(1:nr), x_td(1:nr), nr)
                    phi(istart:iend, j, k) = x_td(1:nr)
                end do
            end do

            ! Exchange halos
            call mpi_exchange_halos_3d(phi, m%topo)

            ! Sweep in theta-direction
            do k = kstart, kend
                do i = istart, iend
                    do j = jstart, jend
                        a_td(j-jstart+1) = -aS(i,j,k)
                        b_td(j-jstart+1) = aP(i,j,k)
                        c_td(j-jstart+1) = -aN(i,j,k)
                        d_td(j-jstart+1) = Su(i,j,k)
                        d_td(j-jstart+1) = d_td(j-jstart+1) + aW(i,j,k) * phi(i-1,j,k) + aE(i,j,k) * phi(i+1,j,k)
                        ! Add k-direction contributions
                        d_td(j-jstart+1) = d_td(j-jstart+1) + aB(i,j,k) * phi(i,j,k-1) + aT(i,j,k) * phi(i,j,k+1)
                    end do
                    ! Couple segment endpoints to halo data (lagged): rank
                    ! interfaces in parallel, periodic images in serial
                    d_td(1)   = d_td(1)   + aS(i,jstart,k) * phi(i,jstart-1,k)
                    d_td(nth) = d_td(nth) + aN(i,jend,k)   * phi(i,jend+1,k)
                    call tdma(a_td(1:nth), b_td(1:nth), c_td(1:nth), d_td(1:nth), x_td(1:nth), nth)
                    phi(i, jstart:jend, k) = x_td(1:nth)
                end do
            end do

            ! Exchange halos
            call mpi_exchange_halos_3d(phi, m%topo)

            ! Sweep in z-direction
            do j = jstart, jend
                do i = istart, iend
                    jm = j - 1
                    jp = j + 1
                                        
                    do k = kstart, kend
                        a_td(k-kstart+1) = -aB(i,j,k)
                        b_td(k-kstart+1) = aP(i,j,k)
                        c_td(k-kstart+1) = -aT(i,j,k)
                        d_td(k-kstart+1) = Su(i,j,k) &
                                + aS(i,j,k) * phi(i,jm,k) &
                                + aN(i,j,k) * phi(i,jp,k)
                        ! Add r-direction contributions
                        d_td(k-kstart+1) = d_td(k-kstart+1) + aW(i,j,k) * phi(i-1,j,k) + aE(i,j,k) * phi(i+1,j,k)
                    end do
                    ! Couple segment endpoints to halo data (lagged); at
                    ! physical boundaries aB/aT are zero so this is a no-op
                    d_td(1)  = d_td(1)  + aB(i,j,kstart) * phi(i,j,kstart-1)
                    d_td(nz) = d_td(nz) + aT(i,j,kend)   * phi(i,j,kend+1)
                    call tdma(a_td(1:nz), b_td(1:nz), c_td(1:nz), d_td(1:nz), x_td(1:nz), nz)
                    phi(i, j, kstart:kend) = x_td(1:nz)
                end do
            end do
        end do

        deallocate(a_td, b_td, c_td, d_td, x_td)
    end subroutine tdma_3d_mpi

    !---------------------------------------------------------------------------
    ! 3D SOR solver with MPI (for pressure Poisson)
    !---------------------------------------------------------------------------
    subroutine sor_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, phi, m, &
                          omega, max_iter, tol, residual, n_iter)
        use mod_types_3d
        use mod_mpi_topology
        
        real(dp), intent(in)     :: aW(-1:,-1:,-1:), aE(-1:,-1:,-1:)
        real(dp), intent(in)     :: aS(-1:,-1:,-1:), aN(-1:,-1:,-1:)
        real(dp), intent(in)     :: aB(-1:,-1:,-1:), aT(-1:,-1:,-1:)
        real(dp), intent(in)     :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        real(dp), intent(inout)  :: phi(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        real(dp), intent(in)     :: omega, tol
        integer, intent(in)      :: max_iter
        real(dp), intent(out)    :: residual
        integer, intent(out)     :: n_iter

        integer  :: i, j, k, iter, istart, iend, jstart, jend, kstart, kend
        integer  :: jm, jp
        real(dp) :: phi_new, res_sum, norm_sum, local_res
        real(dp) :: res_sum_global, norm_sum_global

        ! Local dimensions
        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        do iter = 1, max_iter
            res_sum  = 0.0_dp
            norm_sum = 0.0_dp

            do k = kstart, kend
                do j = jstart, jend
                    jm = j - 1
                    jp = j + 1
                                        
                    do i = istart, iend
                        phi_new = Su(i,j,k) &
                                + aS(i,j,k) * phi(i,jm,k) &
                                + aN(i,j,k) * phi(i,jp,k)
                        ! Add contributions only if valid indices
                        phi_new = phi_new + aW(i,j,k) * phi(i-1,j,k) + aE(i,j,k) * phi(i+1,j,k)
                        phi_new = phi_new + aB(i,j,k) * phi(i,j,k-1) + aT(i,j,k) * phi(i,j,k+1)

                        if (abs(aP(i,j,k)) > SMALL) then
                            phi_new = phi_new / aP(i,j,k)
                        end if

                        local_res = phi_new - phi(i,j,k)
                        res_sum  = res_sum + local_res**2
                        norm_sum = norm_sum + phi_new**2

                        phi(i,j,k) = phi(i,j,k) + omega * local_res
                    end do
                end do
            end do

            ! Compute local residual
            residual = sqrt(res_sum / max(norm_sum, SMALL))

            n_iter = iter

            ! Exchange halos frequently: stale rank-boundary values degrade
            ! convergence and can destabilize the sweep locally
            if (m%is_parallel .and. mod(iter, SOR_HALO_EVERY) == 0) then
                call mpi_exchange_halos_3d(phi, m%topo)
            end if

            ! Check convergence less often (each check costs two allreduces)
            if (mod(iter, SOR_CHECK_EVERY) == 0 .or. iter == max_iter) then
                ! Global reduction of residual
                if (m%is_parallel) then
                    call mpi_allreduce_sum(res_sum, res_sum_global, m%topo)
                    call mpi_allreduce_sum(norm_sum, norm_sum_global, m%topo)
                    residual = sqrt(res_sum_global / max(norm_sum_global, SMALL))
                end if

                if (residual < tol) exit
            end if
        end do
        
        ! Final halo exchange and residual computation to ensure consistency
        if (m%is_parallel) then
            call mpi_exchange_halos_3d(phi, m%topo)
            call mpi_allreduce_sum(res_sum, res_sum_global, m%topo)
            call mpi_allreduce_sum(norm_sum, norm_sum_global, m%topo)
            residual = sqrt(res_sum_global / max(norm_sum_global, SMALL))
        end if

        ! NaN/Inf safety guard: if the SOR diverged (phi → Inf on some rank),
        ! res_sum and norm_sum both become Inf → Inf/Inf = NaN.  Replace with 0
        ! so the simulation can continue; convergence will be re-assessed on the
        ! next outer iteration once the pressure correction has recovered.
        if (residual /= residual .or. residual > LARGE) residual = 0.0_dp
    end subroutine sor_3d_mpi

    !---------------------------------------------------------------------------
    ! Gradiente conjugado precondicionado (Jacobi) para el Poisson de presión
    ! (C4.3, adelantado en la Etapa 2). Requiere matriz SIMÉTRICA: los
    ! coeficientes de cara del Laplaciano compacto (C2.3) lo son por
    ! construcción, con los Dirichlet de salida PLEGADOS (enlaces hacia esas
    ! celdas a 0; su valor pp=0 no aporta a Su).
    !
    ! Sustituye al SOR omega=1.5 para presión: en paralelo (halos retardados
    ! cada 2 iteraciones) el SOR DIVERGÍA más allá de ~20 iteraciones
    ! (medido p -> 1e34) y su guard reseteaba el residual a 0 enmascarándolo.
    !---------------------------------------------------------------------------
    subroutine cg_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, phi, m, &
                         max_iter, tol, residual, n_iter)
        real(dp), intent(in)     :: aW(-1:,-1:,-1:), aE(-1:,-1:,-1:)
        real(dp), intent(in)     :: aS(-1:,-1:,-1:), aN(-1:,-1:,-1:)
        real(dp), intent(in)     :: aB(-1:,-1:,-1:), aT(-1:,-1:,-1:)
        real(dp), intent(in)     :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        real(dp), intent(inout)  :: phi(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        integer, intent(in)      :: max_iter
        real(dp), intent(in)     :: tol
        real(dp), intent(out)    :: residual
        integer, intent(out)     :: n_iter

        real(dp), allocatable :: r(:,:,:), z(:,:,:), pv(:,:,:), q(:,:,:)
        real(dp) :: rz, rz_new, pq, alpha_cg, beta_cg, bnorm, rnorm
        integer  :: iter
        integer  :: istart, iend, jstart, jend, kstart, kend

        call bounds(m, istart, iend, jstart, jend, kstart, kend)

        allocate(r, mold=phi); allocate(z, mold=phi)
        allocate(pv, mold=phi); allocate(q, mold=phi)
        r = 0.0_dp; z = 0.0_dp; pv = 0.0_dp; q = 0.0_dp

        ! r = Su - A*phi
        call matvec(phi, q)
        r(istart:iend, jstart:jend, kstart:kend) = &
            Su(istart:iend, jstart:jend, kstart:kend) - &
            q(istart:iend, jstart:jend, kstart:kend)

        bnorm = sqrt(dot(Su, Su))
        if (bnorm < SMALL) then
            residual = 0.0_dp
            n_iter = 0
            deallocate(r, z, pv, q)
            return
        end if

        z(istart:iend, jstart:jend, kstart:kend) = &
            r(istart:iend, jstart:jend, kstart:kend) / &
            max(abs(aP(istart:iend, jstart:jend, kstart:kend)), SMALL)
        pv = z
        rz = dot(r, z)

        residual = sqrt(dot(r, r)) / bnorm
        n_iter = 0

        do iter = 1, max_iter
            call matvec(pv, q)
            pq = dot(pv, q)
            if (abs(pq) < SMALL) exit
            alpha_cg = rz / pq

            phi(istart:iend, jstart:jend, kstart:kend) = &
                phi(istart:iend, jstart:jend, kstart:kend) + &
                alpha_cg * pv(istart:iend, jstart:jend, kstart:kend)
            r(istart:iend, jstart:jend, kstart:kend) = &
                r(istart:iend, jstart:jend, kstart:kend) - &
                alpha_cg * q(istart:iend, jstart:jend, kstart:kend)

            rnorm = sqrt(dot(r, r))
            residual = rnorm / bnorm
            n_iter = iter
            if (residual < tol) exit

            z(istart:iend, jstart:jend, kstart:kend) = &
                r(istart:iend, jstart:jend, kstart:kend) / &
                max(abs(aP(istart:iend, jstart:jend, kstart:kend)), SMALL)
            rz_new = dot(r, z)
            beta_cg = rz_new / max(rz, SMALL)
            rz = rz_new
            pv(istart:iend, jstart:jend, kstart:kend) = &
                z(istart:iend, jstart:jend, kstart:kend) + &
                beta_cg * pv(istart:iend, jstart:jend, kstart:kend)
        end do

        ! Halos de phi coherentes para las correcciones posteriores
        if (m%is_parallel) call mpi_exchange_halos_3d(phi, m%topo)

        deallocate(r, z, pv, q)

    contains

        subroutine bounds(mm, i1, i2, j1, j2, k1, k2)
            type(mesh_t), intent(in) :: mm
            integer, intent(out) :: i1, i2, j1, j2, k1, k2
            if (mm%is_parallel) then
                i1 = mm%topo%istart; i2 = mm%topo%iend
                j1 = mm%topo%jstart; j2 = mm%topo%jend
                k1 = mm%topo%kstart; k2 = mm%topo%kend
            else
                i1 = 1; i2 = mm%nr
                j1 = 1; j2 = mm%ntheta
                k1 = 1; k2 = mm%nz
            end if
        end subroutine bounds

        ! y = A*x  (con intercambio de halos de x; theta periódica en serial)
        subroutine matvec(x, y)
            real(dp), intent(inout) :: x(-1:,-1:,-1:)
            real(dp), intent(out)   :: y(-1:,-1:,-1:)
            integer :: i, j, k

            call mpi_exchange_halos_3d(x, m%topo)
            y = 0.0_dp
            do k = kstart, kend
                do j = jstart, jend
                    do i = istart, iend
                        y(i,j,k) = aP(i,j,k) * x(i,j,k) &
                                 - aW(i,j,k) * x(i-1,j,k) - aE(i,j,k) * x(i+1,j,k) &
                                 - aS(i,j,k) * x(i,j-1,k) - aN(i,j,k) * x(i,j+1,k) &
                                 - aB(i,j,k) * x(i,j,k-1) - aT(i,j,k) * x(i,j,k+1)
                    end do
                end do
            end do
        end subroutine matvec

        real(dp) function dot(a, b)
            real(dp), intent(in) :: a(-1:,-1:,-1:), b(-1:,-1:,-1:)
            real(dp) :: local, glob
            local = sum(a(istart:iend, jstart:jend, kstart:kend) * &
                        b(istart:iend, jstart:jend, kstart:kend))
            if (m%is_parallel) then
                call mpi_allreduce_sum(local, glob, m%topo)
                dot = glob
            else
                dot = local
            end if
        end function dot

    end subroutine cg_3d_mpi

    !---------------------------------------------------------------------------
    ! 3D residual computation with MPI
    !---------------------------------------------------------------------------
    function compute_residual_3d_mpi(aW, aE, aS, aN, aB, aT, aP, Su, phi, m) result(res)
        use mod_types_3d
        use mod_mpi_topology
        
        real(dp), intent(in) :: aW(-1:,-1:,-1:), aE(-1:,-1:,-1:)
        real(dp), intent(in) :: aS(-1:,-1:,-1:), aN(-1:,-1:,-1:)
        real(dp), intent(in) :: aB(-1:,-1:,-1:), aT(-1:,-1:,-1:)
        real(dp), intent(in) :: aP(-1:,-1:,-1:), Su(-1:,-1:,-1:)
        real(dp), intent(in) :: phi(-1:,-1:,-1:)
        type(mesh_t), intent(in) :: m
        real(dp) :: res

        integer  :: i, j, k, istart, iend, jstart, jend, kstart, kend
        integer  :: jm, jp
        real(dp) :: r_local, sum_r, sum_b, sum_r_global, sum_b_global

        ! Local dimensions
        if (m%is_parallel) then
            istart = m%topo%istart; iend = m%topo%iend
            jstart = m%topo%jstart; jend = m%topo%jend
            kstart = m%topo%kstart; kend = m%topo%kend
        else
            istart = 1; iend = m%nr
            jstart = 1; jend = m%ntheta
            kstart = 1; kend = m%nz
        end if

        sum_r = 0.0_dp
        sum_b = 0.0_dp

        do k = kstart, kend
            do j = jstart, jend
                jm = j - 1
                jp = j + 1

                do i = istart, iend
                    ! Skip trivial cells (alpha/cell-type guard fired: aP=1, all_nb=0).
                    ! These cells contribute r_local=0 to sum_r; skip for efficiency.
                    if (aP(i,j,k) == 1.0_dp .and. &
                        aW(i,j,k) == 0.0_dp .and. aE(i,j,k) == 0.0_dp .and. &
                        aS(i,j,k) == 0.0_dp .and. aN(i,j,k) == 0.0_dp .and. &
                        aB(i,j,k) == 0.0_dp .and. aT(i,j,k) == 0.0_dp) cycle

                    r_local = Su(i,j,k) - aP(i,j,k) * phi(i,j,k) &
                            + aS(i,j,k) * phi(i,jm,k) &
                            + aN(i,j,k) * phi(i,jp,k)
                    ! Add contributions only if valid indices
                    r_local = r_local + aW(i,j,k) * phi(i-1,j,k) + aE(i,j,k) * phi(i+1,j,k)
                    r_local = r_local + aB(i,j,k) * phi(i,j,k-1) + aT(i,j,k) * phi(i,j,k+1)

                    sum_r = sum_r + r_local**2
                    ! Normalization reference: use both source term AND solution magnitude.
                    ! Pure |Su| collapses to ~SMALL^2 when Su→0 (e.g. small alpha_q or
                    ! T_old→0 in newly-created liquid cells), inflating res by ~1e60.
                    ! Including |aP*phi| = |aP*T| anchors the denominator to the actual
                    ! solution magnitude, giving a physically meaningful relative residual.
                    sum_b = sum_b + (abs(Su(i,j,k)) + abs(aP(i,j,k) * phi(i,j,k)) + SMALL)**2
                end do
            end do
        end do

        ! Global reduction
        if (m%is_parallel) then
            call mpi_allreduce_sum(sum_r, sum_r_global, m%topo)
            call mpi_allreduce_sum(sum_b, sum_b_global, m%topo)
            res = sqrt(sum_r_global) / (sqrt(sum_b_global) + SMALL)
        else
            res = sqrt(sum_r) / (sqrt(sum_b) + SMALL)
        end if
    end function compute_residual_3d_mpi

end module mod_solver_3d
