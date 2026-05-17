!===============================================================================
! mod_mpi_topology.f90 - MPI topology and domain decomposition for 3D EAF
!
! Features:
!   - 3D Cartesian topology (npr x npth x npz processes)
!   - Domain decomposition with load balancing
!   - 26-neighbor connectivity (faces, edges, corners)
!   - Halo exchange (2 ghost cell layers)
!   - Collective operations (gather, reduce)
!===============================================================================
module mod_mpi_topology
    use mod_constants
    use mpi
    implicit none
    public :: mpi_topology_t
    public :: mpi_init_topology, mpi_finalize_topology
    public :: mpi_exchange_halos_3d, mpi_exchange_halos_3d_int
    public :: mpi_allreduce_sum, mpi_allreduce_max
    

    type :: mpi_topology_t
        ! Communicators
        integer :: comm_world
        integer :: comm_cart
        integer :: rank
        integer :: nprocs
        
        ! 3D process grid (npr x npth x npz)
        integer :: npr, npth, npz
        integer :: coords(3)  ! (ir, ith, iz) coordinates in process grid
        
        ! Neighbors: -1:1 in each direction = 3x3x3 = 27 (including self)
        ! neighbors(i,j,k) where i,j,k in {-1,0,+1}
        ! MPI_PROC_NULL for non-existent neighbors
        integer :: neighbors(-1:1, -1:1, -1:1)
        
        ! Global mesh dimensions
        integer :: nr_global, nth_global, nz_global
        
        ! Local mesh dimensions (without halos)
        integer :: iloc, jloc, kloc
        
        ! Local mesh dimensions (with 2 halo layers each side)
        integer :: iloc_h, jloc_h, kloc_h
        
        ! Starting indices in global numbering (1-based)
        integer :: iglobal_start, jglobal_start, kglobal_start
        
        ! Local index ranges (in local arrays without halos: 1:iloc, etc.)
        integer :: istart, iend, jstart, jend, kstart, kend
        
        ! Periodic boundary flags
        logical :: periodic_theta
        
        ! MPI datatypes for halo exchange
        integer :: halo_r_type, halo_th_type, halo_z_type
        
        ! Statistics
        integer :: n_exchanges
        real(dp) :: time_exchange
    end type mpi_topology_t

contains

    !---------------------------------------------------------------------------
    ! Initialize MPI and create topology
    !---------------------------------------------------------------------------
    subroutine mpi_init_topology(nr, nth, nz, topo)
        integer, intent(in) :: nr, nth, nz
        type(mpi_topology_t), intent(out) :: topo
        
        integer :: ierr
        logical :: periods(3), reorder
        
        ! Initialize MPI
        call MPI_Init(ierr)
        
        topo%comm_world = MPI_COMM_WORLD
        call MPI_Comm_rank(topo%comm_world, topo%rank, ierr)
        call MPI_Comm_size(topo%comm_world, topo%nprocs, ierr)
        
        ! Store global dimensions
        topo%nr_global = nr
        topo%nth_global = nth
        topo%nz_global = nz
        
        ! Determine optimal process grid decomposition
        call factorize_3d(topo%nprocs, nr, nth, nz, &
                         topo%npr, topo%npth, topo%npz)
        
        ! Periodic in theta, non-periodic in r and z
        periods(1) = .false.  ! r
        periods(2) = .true.   ! theta
        periods(3) = .false.  ! z
        topo%periodic_theta = .true.
        
        reorder = .true.  ! Allow MPI to reorder for better topology
        
        ! Create 3D Cartesian topology
        call MPI_Cart_create(topo%comm_world, 3, &
                            [topo%npr, topo%npth, topo%npz], &
                            periods, reorder, topo%comm_cart, ierr)
        
        ! Get coordinates in process grid
        call MPI_Cart_coords(topo%comm_cart, topo%rank, 3, topo%coords, ierr)
        
        ! Decompose domain
        call decompose_domain(topo)
        
        ! Setup neighbors
        call setup_neighbors(topo)
        
        ! Initialize statistics
        topo%n_exchanges = 0
        topo%time_exchange = 0.0_dp
        
        ! Print topology info (rank 0 only)
        if (topo%rank == 0) then
            print *, ''
            print *, '============================================================'
            print *, '  MPI Parallel Configuration'
            print *, '============================================================'
            print '(A,I6,A,I3,A,I3,A,I3)', '  Total processes:  ', topo%nprocs, &
                  ' (', topo%npr, ' x ', topo%npth, ' x ', topo%npz, ')'
            print '(A,I6,A,I6,A,I6)', '  Global mesh:      ', nr, ' x ', nth, ' x ', nz
            print '(A,I6)', '  Total cells:      ', nr * nth * nz
            print *, '============================================================'
        end if
        
    end subroutine mpi_init_topology
    
    !---------------------------------------------------------------------------
    ! Factorize nprocs into npr x npth x npz, trying to balance load
    ! Constraints: npth must divide nth evenly (periodic boundary)
    !---------------------------------------------------------------------------
    subroutine factorize_3d(nprocs, nr, nth, nz, npr, npth, npz)
        integer, intent(in) :: nprocs, nr, nth, nz
        integer, intent(out) :: npr, npth, npz
        
        integer :: test_npr, test_npth, test_npz
        real(dp) :: test_aspect
        real(dp) :: cell_r, cell_th, cell_z
        integer :: best_npr, best_npth, best_npz
        real(dp) :: best_aspect
        
        best_aspect = 1.0e20_dp
        best_npr = 1; best_npth = 1; best_npz = nprocs
        
        ! Try all factorizations
        do test_npr = 1, nprocs
            if (mod(nprocs, test_npr) /= 0) cycle
            
            do test_npth = 1, nprocs/test_npr
                if (mod(nprocs/test_npr, test_npth) /= 0) cycle
                ! Constraint: npth must divide nth evenly
                if (mod(nth, test_npth) /= 0) cycle
                
                test_npz = nprocs / (test_npr * test_npth)
                
                ! Compute local block sizes
                cell_r = real(nr, dp) / real(test_npr, dp)
                cell_th = real(nth, dp) / real(test_npth, dp)
                cell_z = real(nz, dp) / real(test_npz, dp)
                
                ! Prefer aspect ratio close to 1 (cubic blocks)
                test_aspect = max(cell_r/cell_th, cell_th/cell_r) * &
                             max(cell_r/cell_z, cell_z/cell_r) * &
                             max(cell_th/cell_z, cell_z/cell_th)
                
                if (test_aspect < best_aspect) then
                    best_aspect = test_aspect
                    best_npr = test_npr
                    best_npth = test_npth
                    best_npz = test_npz
                end if
            end do
        end do
        
        npr = best_npr
        npth = best_npth
        npz = best_npz
        
    end subroutine factorize_3d
    
    !---------------------------------------------------------------------------
    ! Decompose domain into local blocks
    !---------------------------------------------------------------------------
    subroutine decompose_domain(topo)
        type(mpi_topology_t), intent(inout) :: topo
        
        integer :: ir, ith, iz
        
        ir = topo%coords(1)
        ith = topo%coords(2)
        iz = topo%coords(3)
        
        ! Compute local dimensions (without halos)
        topo%iloc = topo%nr_global / topo%npr
        topo%jloc = topo%nth_global / topo%npth
        topo%kloc = topo%nz_global / topo%npz
        
        ! Handle remainders (last process gets extra cells)
        if (ir == topo%npr - 1) then
            topo%iloc = topo%iloc + mod(topo%nr_global, topo%npr)
        end if
        if (ith == topo%npth - 1) then
            topo%jloc = topo%jloc + mod(topo%nth_global, topo%npth)
        end if
        if (iz == topo%npz - 1) then
            topo%kloc = topo%kloc + mod(topo%nz_global, topo%npz)
        end if
        
        ! Local dimensions with halos (2 layers each side)
        topo%iloc_h = topo%iloc + 4  ! -1:iloc+2
        topo%jloc_h = topo%jloc + 4
        topo%kloc_h = topo%kloc + 4
        
        ! Starting indices in global numbering (1-based)
        topo%iglobal_start = ir * (topo%nr_global / topo%npr) + 1
        topo%jglobal_start = ith * (topo%nth_global / topo%npth) + 1
        topo%kglobal_start = iz * (topo%nz_global / topo%npz) + 1
        
        ! Local index ranges (1:iloc, etc.)
        topo%istart = 1
        topo%iend = topo%iloc
        topo%jstart = 1
        topo%jend = topo%jloc
        topo%kstart = 1
        topo%kend = topo%kloc
        
    end subroutine decompose_domain
    
    !---------------------------------------------------------------------------
    ! Setup 26 neighbors (27 including self)
    !---------------------------------------------------------------------------
    subroutine setup_neighbors(topo)
        type(mpi_topology_t), intent(inout) :: topo
        
        integer :: di, dj, dk, ierr
        integer :: neighbor_coords(3)
        
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    neighbor_coords(1) = topo%coords(1) + di
                    neighbor_coords(2) = topo%coords(2) + dj
                    neighbor_coords(3) = topo%coords(3) + dk
                    
                    ! Check bounds (non-periodic in r and z)
                    if (neighbor_coords(1) < 0 .or. &
                        neighbor_coords(1) >= topo%npr .or. &
                        neighbor_coords(3) < 0 .or. &
                        neighbor_coords(3) >= topo%npz) then
                        topo%neighbors(di, dj, dk) = MPI_PROC_NULL
                    else
                        ! Theta is periodic, handled by Cart_rank
                        call MPI_Cart_rank(topo%comm_cart, neighbor_coords, &
                                          topo%neighbors(di, dj, dk), ierr)
                    end if
                end do
            end do
        end do
        
    end subroutine setup_neighbors
    
    !---------------------------------------------------------------------------
    ! Exchange halos for a 3D field (2 ghost layers)
    ! Field dimensions: (-1:iloc+2, -1:jloc+2, -1:kloc+2)
    !---------------------------------------------------------------------------
    subroutine mpi_exchange_halos_3d(field, topo)
        real(dp), intent(inout) :: field(-1:, -1:, -1:)
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: ierr, send_tag, recv_tag
        integer :: nreq_send, nreq_recv
        integer, allocatable :: req_send(:), req_recv(:)
        integer :: di, dj, dk, idx
        real(dp), allocatable :: sendbufs(:,:), recvbufs(:,:)
        integer :: bufsize, max_bufsize
        real(dp) :: t_start
        
        ! Handle serial case with periodic boundaries
        if (topo%nprocs == 1) then
            if (topo%periodic_theta) then
                field(:, 0, :) = field(:, topo%jloc, :)
                field(:, -1, :) = field(:, topo%jloc-1, :)
                field(:, topo%jloc+1, :) = field(:, 1, :)
                field(:, topo%jloc+2, :) = field(:, 2, :)
            end if
            return
        end if
        
        t_start = MPI_Wtime()
        
        ! Find max buffer size needed
        max_bufsize = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    bufsize = compute_halo_size(di, dj, dk, topo)
                    max_bufsize = max(max_bufsize, bufsize)
                end do
            end do
        end do
        
        if (max_bufsize == 0) return
        
        ! Allocate persistent buffers and requests
        allocate(req_send(26), req_recv(26))
        allocate(sendbufs(max_bufsize, 26), recvbufs(max_bufsize, 26))
        nreq_send = 0
        nreq_recv = 0
        
        ! Post receives first
        idx = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    
                    idx = idx + 1
                    bufsize = compute_halo_size(di, dj, dk, topo)
                    
                    recv_tag = 100 + encode_direction(-di, -dj, -dk)
                    nreq_recv = nreq_recv + 1
                    
                    call MPI_Irecv(recvbufs(1:bufsize, idx), bufsize, MPI_DOUBLE_PRECISION, &
                                  topo%neighbors(di, dj, dk), recv_tag, &
                                  topo%comm_cart, req_recv(nreq_recv), ierr)
                end do
            end do
        end do
        
        ! Pack and post sends
        idx = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    
                    idx = idx + 1
                    bufsize = compute_halo_size(di, dj, dk, topo)
                    
                    call pack_halo(field, sendbufs(1:bufsize, idx), di, dj, dk, topo)
                    
                    send_tag = 100 + encode_direction(di, dj, dk)
                    nreq_send = nreq_send + 1
                    
                    call MPI_Isend(sendbufs(1:bufsize, idx), bufsize, MPI_DOUBLE_PRECISION, &
                                  topo%neighbors(di, dj, dk), send_tag, &
                                  topo%comm_cart, req_send(nreq_send), ierr)
                end do
            end do
        end do
        
        ! Wait for receives and sends
        if (nreq_recv > 0) call MPI_Waitall(nreq_recv, req_recv(1:nreq_recv), MPI_STATUSES_IGNORE, ierr)
        if (nreq_send > 0) call MPI_Waitall(nreq_send, req_send(1:nreq_send), MPI_STATUSES_IGNORE, ierr)
        
        ! Unpack
        idx = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    
                    idx = idx + 1
                    bufsize = compute_halo_size(di, dj, dk, topo)
                    call unpack_halo(field, recvbufs(1:bufsize, idx), di, dj, dk, topo)
                end do
            end do
        end do
        
        deallocate(req_send, req_recv, sendbufs, recvbufs)
        
    end subroutine mpi_exchange_halos_3d
    
    !---------------------------------------------------------------------------
    ! Helper: encode direction to unique tag
    !---------------------------------------------------------------------------
    pure function encode_direction(di, dj, dk) result(tag)
        integer, intent(in) :: di, dj, dk
        integer :: tag
        
        tag = (di+1) + 3*(dj+1) + 9*(dk+1)
    end function encode_direction
    
    !---------------------------------------------------------------------------
    ! Helper: compute halo buffer size for direction (di, dj, dk)
    !---------------------------------------------------------------------------
    function compute_halo_size(di, dj, dk, topo) result(bufsize)
        integer, intent(in) :: di, dj, dk
        type(mpi_topology_t), intent(in) :: topo
        integer :: bufsize
        
        integer :: ni, nj, nk
        integer, parameter :: nhalo = 2
        
        ! Determine size in each direction
        if (di /= 0) then
            ni = nhalo
        else
            ni = topo%iloc
        end if
        
        if (dj /= 0) then
            nj = nhalo
        else
            nj = topo%jloc
        end if
        
        if (dk /= 0) then
            nk = nhalo
        else
            nk = topo%kloc
        end if
        
        bufsize = ni * nj * nk
        
    end function compute_halo_size
    
    !---------------------------------------------------------------------------
    ! Pack halo data for sending
    ! Field indexed as (-1:iloc+2, -1:jloc+2, -1:kloc+2)
    !---------------------------------------------------------------------------
    subroutine pack_halo(field, buffer, di, dj, dk, topo)
        real(dp), intent(in) :: field(-1:, -1:, -1:)
        real(dp), intent(out) :: buffer(:)
        integer, intent(in) :: di, dj, dk
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend
        integer :: idx
        integer :: nhalo
        
        nhalo = 2
        
        ! Determine which region to pack
        if (di == -1) then  ! Send to left in r
            istart = 1
            iend = nhalo
        else if (di == 1) then  ! Send to right in r
            istart = topo%iloc - nhalo + 1
            iend = topo%iloc
        else
            istart = 1
            iend = topo%iloc
        end if
        
        if (dj == -1) then
            jstart = 1
            jend = nhalo
        else if (dj == 1) then
            jstart = topo%jloc - nhalo + 1
            jend = topo%jloc
        else
            jstart = 1
            jend = topo%jloc
        end if
        
        if (dk == -1) then
            kstart = 1
            kend = nhalo
        else if (dk == 1) then
            kstart = topo%kloc - nhalo + 1
            kend = topo%kloc
        else
            kstart = 1
            kend = topo%kloc
        end if
        
        ! Pack data
        idx = 1
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    buffer(idx) = field(i, j, k)
                    idx = idx + 1
                end do
            end do
        end do
        
    end subroutine pack_halo
    
    !---------------------------------------------------------------------------
    ! Unpack received halo data
    !---------------------------------------------------------------------------
    subroutine unpack_halo(field, buffer, di, dj, dk, topo)
        real(dp), intent(inout) :: field(-1:, -1:, -1:)
        real(dp), intent(in) :: buffer(:)
        integer, intent(in) :: di, dj, dk
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend
        integer :: idx
        integer :: nhalo
        
        nhalo = 2
        
        ! Determine where to unpack (halo regions)
        if (di == -1) then  ! Received from left
            istart = -1
            iend = 0
        else if (di == 1) then  ! Received from right
            istart = topo%iloc + 1
            iend = topo%iloc + nhalo
        else
            istart = 1
            iend = topo%iloc
        end if
        
        if (dj == -1) then
            jstart = -1
            jend = 0
        else if (dj == 1) then
            jstart = topo%jloc + 1
            jend = topo%jloc + nhalo
        else
            jstart = 1
            jend = topo%jloc
        end if
        
        if (dk == -1) then
            kstart = -1
            kend = 0
        else if (dk == 1) then
            kstart = topo%kloc + 1
            kend = topo%kloc + nhalo
        else
            kstart = 1
            kend = topo%kloc
        end if
        
        ! Unpack data
        idx = 1
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    field(i, j, k) = buffer(idx)
                    idx = idx + 1
                end do
            end do
        end do
        
    end subroutine unpack_halo
    
    !---------------------------------------------------------------------------
    ! Global sum reduction
    !---------------------------------------------------------------------------
    subroutine mpi_allreduce_sum(local_val, global_val, topo)
        real(dp), intent(in) :: local_val
        real(dp), intent(out) :: global_val
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: ierr
        
        call MPI_Allreduce(local_val, global_val, 1, MPI_DOUBLE_PRECISION, &
                          MPI_SUM, topo%comm_cart, ierr)
    end subroutine mpi_allreduce_sum
    
    !---------------------------------------------------------------------------
    ! Global max reduction
    !---------------------------------------------------------------------------
    subroutine mpi_allreduce_max(local_val, global_val, topo)
        real(dp), intent(in) :: local_val
        real(dp), intent(out) :: global_val
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: ierr
        
        call MPI_Allreduce(local_val, global_val, 1, MPI_DOUBLE_PRECISION, &
                          MPI_MAX, topo%comm_cart, ierr)
    end subroutine mpi_allreduce_max
    
    !---------------------------------------------------------------------------
    ! Finalize MPI
    !---------------------------------------------------------------------------
    subroutine mpi_finalize_topology(topo)
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: ierr
        
        if (topo%rank == 0) then
            print *, ''
            print '(A,I10)', '  Total halo exchanges: ', topo%n_exchanges
            if (topo%n_exchanges > 0) then
                print '(A,F10.3,A)', '  Avg time per exchange: ', &
                      topo%time_exchange / real(topo%n_exchanges, dp) * 1000.0_dp, ' ms'
            end if
        end if
        
        call MPI_Finalize(ierr)
        
    end subroutine mpi_finalize_topology


    !---------------------------------------------------------------------------
    ! Exchange halos for an integer 3D field (2 ghost layers)
    ! Field dimensions: (-1:iloc+2, -1:jloc+2, -1:kloc+2)
    !---------------------------------------------------------------------------
    subroutine mpi_exchange_halos_3d_int(field, topo)
        integer, intent(inout) :: field(-1:, -1:, -1:)
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: ierr, send_tag, recv_tag
        integer :: nreq_send, nreq_recv
        integer, allocatable :: req_send(:), req_recv(:)
        integer :: di, dj, dk, idx
        integer, allocatable :: sendbufs(:,:), recvbufs(:,:)
        integer :: bufsize, max_bufsize
        real(dp) :: t_start
        
        ! Handle serial case with periodic boundaries
        if (topo%nprocs == 1) then
            if (topo%periodic_theta) then
                field(:, 0, :) = field(:, topo%jloc, :)
                field(:, -1, :) = field(:, topo%jloc-1, :)
                field(:, topo%jloc+1, :) = field(:, 1, :)
                field(:, topo%jloc+2, :) = field(:, 2, :)
            end if
            return
        end if
        
        t_start = MPI_Wtime()
        
        ! Find max buffer size needed
        max_bufsize = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    bufsize = compute_halo_size(di, dj, dk, topo)
                    max_bufsize = max(max_bufsize, bufsize)
                end do
            end do
        end do
        
        if (max_bufsize == 0) return
        
        ! Allocate persistent buffers and requests
        allocate(req_send(26), req_recv(26))
        allocate(sendbufs(max_bufsize, 26), recvbufs(max_bufsize, 26))
        nreq_send = 0
        nreq_recv = 0
        
        ! Post receives first
        idx = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    
                    idx = idx + 1
                    bufsize = compute_halo_size(di, dj, dk, topo)
                    
                    recv_tag = 100 + encode_direction(-di, -dj, -dk)
                    nreq_recv = nreq_recv + 1
                    
                    call MPI_Irecv(recvbufs(1:bufsize, idx), bufsize, MPI_INTEGER, &
                                  topo%neighbors(di, dj, dk), recv_tag, &
                                  topo%comm_cart, req_recv(nreq_recv), ierr)
                end do
            end do
        end do
        
        ! Pack and post sends
        idx = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    
                    idx = idx + 1
                    bufsize = compute_halo_size(di, dj, dk, topo)
                    
                    call pack_halo_int(field, sendbufs(1:bufsize, idx), di, dj, dk, topo)
                    
                    send_tag = 100 + encode_direction(di, dj, dk)
                    nreq_send = nreq_send + 1
                    
                    call MPI_Isend(sendbufs(1:bufsize, idx), bufsize, MPI_INTEGER, &
                                  topo%neighbors(di, dj, dk), send_tag, &
                                  topo%comm_cart, req_send(nreq_send), ierr)
                end do
            end do
        end do
        
        ! Wait for receives and sends
        if (nreq_recv > 0) call MPI_Waitall(nreq_recv, req_recv(1:nreq_recv), MPI_STATUSES_IGNORE, ierr)
        if (nreq_send > 0) call MPI_Waitall(nreq_send, req_send(1:nreq_send), MPI_STATUSES_IGNORE, ierr)
        
        ! Unpack receives
        idx = 0
        do dk = -1, 1
            do dj = -1, 1
                do di = -1, 1
                    if (di == 0 .and. dj == 0 .and. dk == 0) cycle
                    if (topo%neighbors(di, dj, dk) == MPI_PROC_NULL) cycle
                    
                    idx = idx + 1
                    call unpack_halo_int(field, recvbufs(:, idx), -di, -dj, -dk, topo)
                end do
            end do
        end do
        
        deallocate(req_send, req_recv, sendbufs, recvbufs)
        
    end subroutine mpi_exchange_halos_3d_int
    
    !---------------------------------------------------------------------------
    ! Pack halo data for sending (integer)
    !---------------------------------------------------------------------------
    subroutine pack_halo_int(field, buffer, di, dj, dk, topo)
        integer, intent(in) :: field(-1:, -1:, -1:)
        integer, intent(out) :: buffer(:)
        integer, intent(in) :: di, dj, dk
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend
        integer :: idx
        integer, parameter :: nhalo = 2
        
        if (di == -1) then
            istart = 1; iend = nhalo
        else if (di == 1) then
            istart = topo%iloc - nhalo + 1; iend = topo%iloc
        else
            istart = 1; iend = topo%iloc
        end if
        
        if (dj == -1) then
            jstart = 1; jend = nhalo
        else if (dj == 1) then
            jstart = topo%jloc - nhalo + 1; jend = topo%jloc
        else
            jstart = 1; jend = topo%jloc
        end if
        
        if (dk == -1) then
            kstart = 1; kend = nhalo
        else if (dk == 1) then
            kstart = topo%kloc - nhalo + 1; kend = topo%kloc
        else
            kstart = 1; kend = topo%kloc
        end if
        
        idx = 1
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    buffer(idx) = field(i, j, k)
                    idx = idx + 1
                end do
            end do
        end do
    end subroutine pack_halo_int
    
    !---------------------------------------------------------------------------
    ! Unpack received halo data (integer)
    !---------------------------------------------------------------------------
    subroutine unpack_halo_int(field, buffer, di, dj, dk, topo)
        integer, intent(inout) :: field(-1:, -1:, -1:)
        integer, intent(in) :: buffer(:)
        integer, intent(in) :: di, dj, dk
        type(mpi_topology_t), intent(in) :: topo
        
        integer :: i, j, k, istart, iend, jstart, jend, kstart, kend
        integer :: idx
        integer, parameter :: nhalo = 2
        
        if (di == -1) then
            istart = -1; iend = 0
        else if (di == 1) then
            istart = topo%iloc + 1; iend = topo%iloc + nhalo
        else
            istart = 1; iend = topo%iloc
        end if
        
        if (dj == -1) then
            jstart = -1; jend = 0
        else if (dj == 1) then
            jstart = topo%jloc + 1; jend = topo%jloc + nhalo
        else
            jstart = 1; jend = topo%jloc
        end if
        
        if (dk == -1) then
            kstart = -1; kend = 0
        else if (dk == 1) then
            kstart = topo%kloc + 1; kend = topo%kloc + nhalo
        else
            kstart = 1; kend = topo%kloc
        end if
        
        idx = 1
        do k = kstart, kend
            do j = jstart, jend
                do i = istart, iend
                    field(i, j, k) = buffer(idx)
                    idx = idx + 1
                end do
            end do
        end do
    end subroutine unpack_halo_int

end module mod_mpi_topology
