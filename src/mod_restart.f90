!===============================================================================
! mod_restart.f90 - Reinicio desde un snapshot HDF5 (estado completo)
!
! Motivo (Plan C, 2026-09-25): los episodios de presion de B1 aparecen a
! t ~ 34 s en la malla media, a ~3 h de maquina del arranque. Reanudar desde
! el snapshot anterior permite iterar sobre ese instante en minutos.
!
! Contrato:
!   - El snapshot lo escribe write_hdf5_parallel: /fields (estado visible) +
!     /restart (E_s, m_C, layer_id, escoria, mu_t, dt, electrodos) +
!     /metadata (time, step). Con los tres grupos el reinicio es COMPLETO:
!     todo lo que no se lee (propiedades, aP, fuentes S_*, pp, workspace,
!     iterados previos de la sub-relajacion) se recalcula en el primer paso.
!   - La malla del snapshot debe ser la del config (nr x ntheta x nz);
!     el numero de ranks puede cambiar (lectura por hyperslab propio).
!   - Snapshots anteriores a este modulo (sin /restart) se aceptan con
!     RECONSTRUCCION aproximada y aviso explicito por stdout:
!       E_s = m_s * solid_enthalpy(T_s)     (exacta si T_s no esta en el
!                                            intervalo de fusion)
!       m_C = carbon_frac * m_s             (ignora el carbono ya oxidado)
!       layer_id = 0
!       m_sl = alpha_sl rho_sl V, E_sl = m_sl cp_sl T_sl, m_X = X * m_sl
!       mu_t = 0 (se recalcula en el primer k-eps)
!       rho_g, mu_eff_l = update_properties(T, mu_t)  (la corrida continua
!                          arranca el paso con las de la ULTIMA iteracion
!                          externa, previas a la interfase y al k-eps:
!                          por eso el snapshot nuevo las guarda)
!       dt = el del config
!       electrodos: trayectoria de bore-in desde el tiempo (descenso a
!       BORE_IN_SPEED desde H_total-0.1: EXACTA mientras no ha terminado,
!       que es el caso de B1 a 30 s); si ya llego a la chatarra, punta a
!       ARC_LENGTH_SET sobre ella (aprox.). Ponerla directamente sobre la
!       chatarra movia el arco al lecho: 33 kPa en el primer paso.
!   - El audit arranca de cero en el nuevo output_dir: sus identidades son
!     por intervalo, no necesitan historia.
!===============================================================================
module mod_restart
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_fields_3d, only: phase_exchange_halos, solid_exchange_halos, &
                             slag_exchange_halos, fill_periodic_theta
    use mod_melting_3d, only: solid_enthalpy
    use mod_properties_3d, only: update_properties
    use mod_electrode_3d, only: ARC_LENGTH_SET, BORE_IN_SPEED
    use hdf5
    use mpi
    implicit none

    private
    public :: restart_read

contains

    subroutine restart_read(filename, m, cfg, liq, gas, sol, slag, sh, elec, &
                            step, time)
        character(len=*), intent(in)     :: filename
        type(mesh_t), intent(in)         :: m
        type(config_t), intent(inout)    :: cfg      ! dt del snapshot
        type(phase_t), intent(inout)     :: liq, gas
        type(solid_t), intent(inout)     :: sol
        type(slag_t),  intent(inout)     :: slag
        type(shared_t), intent(inout)    :: sh
        type(electrode_t), intent(inout) :: elec(:)
        integer, intent(out)             :: step
        real(dp), intent(out)            :: time

        integer(HID_T) :: file_id, plist_id, plist_xfer, gid, rid
        integer :: error, rank, c, e, ne
        logical :: has_restart, ex
        real(dp), allocatable :: xdiag(:,:,:), rv(:)
        integer,  allocatable :: iv(:)
        integer(HSIZE_T) :: adims(1)
        character(len=9), parameter :: XNAME(N_SLAG_COMP) = &
            ['m_FeO    ', 'm_CaO    ', 'm_SiO2   ', 'm_MgO    ', 'm_C_slag ']
        character(len=6), parameter :: XFRAC(N_SLAG_COMP) = &
            ['X_FeO ', 'X_CaO ', 'X_SiO2', 'X_MgO ', 'X_C   ']

        rank = 0
        if (m%is_parallel) rank = m%topo%rank

        inquire(file=filename, exist=ex)
        if (.not. ex) then
            if (rank == 0) print '(A,A)', ' [RESTART] ERROR: no existe ', trim(filename)
            call MPI_Abort(MPI_COMM_WORLD, 1, error)
        end if

        call h5open_f(error)
        call h5pcreate_f(H5P_FILE_ACCESS_F, plist_id, error)
        if (m%is_parallel) &
            call h5pset_fapl_mpio_f(plist_id, m%topo%comm_cart, MPI_INFO_NULL, error)
        call h5fopen_f(filename, H5F_ACC_RDONLY_F, file_id, error, access_prp=plist_id)
        call check_h5(error, 'h5fopen_f: '//trim(filename), rank)
        call h5pclose_f(plist_id, error)
        call h5pcreate_f(H5P_DATASET_XFER_F, plist_xfer, error)
        if (m%is_parallel) &
            call h5pset_dxpl_mpio_f(plist_xfer, H5FD_MPIO_COLLECTIVE_F, error)

        !--- /fields: estado visible -----------------------------------------
        call h5gopen_f(file_id, '/fields', gid, error)
        call check_h5(error, 'h5gopen_f: /fields', rank)
        call check_dims(gid, 'alpha_liquid', m, rank)

        call read_3d_field(gid, 'T_liquid',           liq%T,   m, plist_xfer)
        call read_3d_field(gid, 'alpha_liquid',       liq%alpha, m, plist_xfer)
        call read_3d_field(gid, 'velocity_r_liquid',  liq%ur,  m, plist_xfer)
        call read_3d_field(gid, 'velocity_th_liquid', liq%uth, m, plist_xfer)
        call read_3d_field(gid, 'velocity_z_liquid',  liq%uz,  m, plist_xfer)
        call read_3d_field(gid, 'T_gas',              gas%T,   m, plist_xfer)
        call read_3d_field(gid, 'alpha_gas',          gas%alpha, m, plist_xfer)
        call read_3d_field(gid, 'velocity_r_gas',     gas%ur,  m, plist_xfer)
        call read_3d_field(gid, 'velocity_th_gas',    gas%uth, m, plist_xfer)
        call read_3d_field(gid, 'velocity_z_gas',     gas%uz,  m, plist_xfer)
        call read_3d_field(gid, 'alpha_solid',        sol%alpha_s, m, plist_xfer)
        call read_3d_field(gid, 'T_solid',            sol%T_s, m, plist_xfer)
        call read_3d_field(gid, 'mass_solid',         sol%m_s, m, plist_xfer)
        call read_3d_field(gid, 'alpha_slag',         slag%alpha_sl, m, plist_xfer)
        call read_3d_field(gid, 'T_slag',             slag%T_sl, m, plist_xfer)
        call read_3d_field(gid, 'pressure',           sh%p,    m, plist_xfer)
        call read_3d_field(gid, 'tke',                sh%tke,  m, plist_xfer)
        call read_3d_field(gid, 'epsilon',            sh%eps,  m, plist_xfer)
        call read_3d_field(gid, 'Y_O2',               sh%Y_O2, m, plist_xfer)
        call read_3d_field(gid, 'Y_CO',               sh%Y_CO, m, plist_xfer)
        call read_3d_field(gid, 'Y_CO2',              sh%Y_CO2, m, plist_xfer)

        !--- /restart: complemento (o reconstruccion si no existe) -------------
        call h5lexists_f(file_id, '/restart', has_restart, error)
        if (has_restart) then
            call h5gopen_f(file_id, '/restart', rid, error)
            call read_3d_field(rid, 'E_solid', sol%E_s, m, plist_xfer)
            call read_3d_field(rid, 'm_C',     sol%m_C, m, plist_xfer)
            call read_3d_field_int(rid, 'layer_id', sol%layer_id, m, plist_xfer)
            call read_3d_field(rid, 'm_slag',  slag%m_sl, m, plist_xfer)
            call read_3d_field(rid, 'E_slag',  slag%E_sl, m, plist_xfer)
            do c = 1, N_SLAG_COMP
                call read_3d_field(rid, trim(XNAME(c)), slag%m_X(:,:,:,c), m, plist_xfer)
            end do
            call read_3d_field(rid, 'mu_t', sh%mu_t, m, plist_xfer)
            call update_properties(liq, gas, sh, m, cfg)
            call h5lexists_f(rid, 'rho_gas', ex, error)
            if (ex) then
                call read_3d_field(rid, 'rho_gas',       gas%rho,    m, plist_xfer)
                call read_3d_field(rid, 'mu_eff_liquid', liq%mu_eff, m, plist_xfer)
            else if (rank == 0) then
                print '(A)', ' [RESTART] AVISO: snapshot sin rho_gas/mu_eff_liquid; recalculadas de T'
            end if

            adims(1) = 1
            call read_attr_real(rid, 'dt', cfg%dt, adims)
            ne = size(elec)
            allocate(rv(ne), iv(ne))
            adims(1) = ne
            call read_attr_real_arr(rid, 'elec_z_tip', rv, adims)
            do e = 1, ne; elec(e)%z_tip = rv(e); end do
            call read_attr_real_arr(rid, 'elec_arc_length', rv, adims)
            do e = 1, ne; elec(e)%arc_length = rv(e); end do
            call read_attr_real_arr(rid, 'elec_arc_R', rv, adims)
            do e = 1, ne; elec(e)%arc_R = rv(e); end do
            call read_attr_real_arr(rid, 'elec_arc_power', rv, adims)
            do e = 1, ne; elec(e)%arc_power = rv(e); end do
            call read_attr_int_arr(rid, 'elec_bore_in_done', iv, adims)
            do e = 1, ne; elec(e)%bore_in_done = (iv(e) /= 0); end do
            deallocate(rv, iv)
            call h5gclose_f(rid, error)
        else
            ! Snapshot anterior al grupo /restart: reconstruccion aproximada
            if (rank == 0) then
                print '(A)', ' [RESTART] AVISO: snapshot sin grupo /restart; se reconstruyen'
                print '(A)', '           E_s (de T_s), m_C (carbon_frac*m_s), layer_id=0,'
                print '(A)', '           escoria (de alpha_sl/T_sl), mu_t=0, dt del config,'
                print '(A)', '           electrodos (trayectoria de bore-in desde el tiempo).'
            end if
            where (sol%m_s > 0.0_dp)
                sol%m_C = cfg%carbon_frac * sol%m_s
            elsewhere
                sol%m_C = 0.0_dp
            end where
            call reconstruct_solid_energy(sol, cfg)
            sol%layer_id = 0
            slag%m_sl = slag%alpha_sl * cfg%rho_slag * m%vol
            slag%E_sl = slag%m_sl * cfg%cp_slag * slag%T_sl
            allocate(xdiag, mold=slag%m_sl)
            do c = 1, N_SLAG_COMP
                call h5lexists_f(gid, trim(XFRAC(c)), ex, error)
                if (ex) then
                    call read_3d_field(gid, trim(XFRAC(c)), xdiag, m, plist_xfer)
                    slag%m_X(:,:,:,c) = xdiag * slag%m_sl
                else
                    slag%m_X(:,:,:,c) = 0.0_dp
                end if
            end do
            deallocate(xdiag)
            sh%mu_t = 0.0_dp
            call update_properties(liq, gas, sh, m, cfg)
        end if
        call h5gclose_f(gid, error)

        !--- /metadata: time, step ---------------------------------------------
        call h5gopen_f(file_id, '/metadata', gid, error)
        call check_h5(error, 'h5gopen_f: /metadata', rank)
        adims(1) = 1
        call read_attr_real(gid, 'time', time, adims)
        call read_attr_int(gid, 'step', step, adims)
        call h5gclose_f(gid, error)

        call h5pclose_f(plist_xfer, error)
        call h5fclose_f(file_id, error)
        call check_h5(error, 'h5fclose_f: '//trim(filename), rank)
        call h5close_f(error)

        !--- halos y campos derivados -----------------------------------------
        sh%pp = 0.0_dp
        sol%mdot = 0.0_dp
        call phase_exchange_halos(liq, m)
        call phase_exchange_halos(gas, m)
        call solid_exchange_halos(sol, m)
        call slag_exchange_halos(slag, m)
        if (m%is_parallel) then
            call mpi_exchange_halos_3d(sol%m_C, m%topo)
            call mpi_exchange_halos_3d_int(sol%layer_id, m%topo)
            call mpi_exchange_halos_3d(sh%p,    m%topo)
            call mpi_exchange_halos_3d(sh%tke,  m%topo)
            call mpi_exchange_halos_3d(sh%eps,  m%topo)
            call mpi_exchange_halos_3d(sh%mu_t, m%topo)
            call mpi_exchange_halos_3d(sh%Y_O2, m%topo)
            call mpi_exchange_halos_3d(sh%Y_CO, m%topo)
            call mpi_exchange_halos_3d(sh%Y_CO2, m%topo)
        else
            call fill_periodic_theta(sol%m_C, m%ntheta)
            call fill_periodic_theta_int(sol%layer_id, m%ntheta)
            call fill_periodic_theta(sh%p,    m%ntheta)
            call fill_periodic_theta(sh%tke,  m%ntheta)
            call fill_periodic_theta(sh%eps,  m%ntheta)
            call fill_periodic_theta(sh%mu_t, m%ntheta)
            call fill_periodic_theta(sh%Y_O2, m%ntheta)
            call fill_periodic_theta(sh%Y_CO, m%ntheta)
            call fill_periodic_theta(sh%Y_CO2, m%ntheta)
        end if

        ! Electrodos sin estado guardado: posicion consistente con la chatarra
        ! (necesita alpha_s YA leida y con halos)
        if (.not. has_restart) call reconstruct_electrodes(elec, sol, m, cfg, time)

        if (rank == 0) then
            print '(A,A)', ' [RESTART] Estado leido de ', trim(filename)
            print '(A,I0,A,F10.3,A,ES10.3)', '           paso ', step, '  t = ', time, &
                  ' s  dt = ', cfg%dt
            if (has_restart) then
                print '(A)', '           grupo /restart presente: reinicio completo'
            end if
        end if
    end subroutine restart_read

    !---------------------------------------------------------------------------
    ! E_s desde T_s con la entalpia unica del solido (mod_melting_3d)
    !---------------------------------------------------------------------------
    subroutine reconstruct_solid_energy(sol, cfg)
        type(solid_t), intent(inout) :: sol
        type(config_t), intent(in)   :: cfg
        integer :: i, j, k

        do k = lbound(sol%m_s, 3), ubound(sol%m_s, 3)
            do j = lbound(sol%m_s, 2), ubound(sol%m_s, 2)
                do i = lbound(sol%m_s, 1), ubound(sol%m_s, 1)
                    if (sol%m_s(i,j,k) > 0.0_dp) then
                        sol%E_s(i,j,k) = sol%m_s(i,j,k) * solid_enthalpy(sol%T_s(i,j,k), cfg)
                    else
                        sol%E_s(i,j,k) = 0.0_dp
                    end if
                end do
            end do
        end do
    end subroutine reconstruct_solid_energy

    !---------------------------------------------------------------------------
    ! Electrodos sin estado guardado: punta a ARC_LENGTH_SET sobre la cima de
    ! la chatarra bajo cada electrodo (misma busqueda que update_electrodes,
    ! reduccion global), bore-in dado por hecho, arc_R inicial.
    !---------------------------------------------------------------------------
    subroutine reconstruct_electrodes(elec, sol, m, cfg, time)
        type(electrode_t), intent(inout) :: elec(:)
        type(solid_t), intent(in)        :: sol
        type(mesh_t), intent(in)         :: m
        type(config_t), intent(in)       :: cfg
        real(dp), intent(in)             :: time

        integer :: e, i, j, k
        real(dp) :: x_e, y_e, x_c, y_c, dist, z_top, z_glob, z_desc

        do e = 1, size(elec)
            x_e = cfg%R_pcd * cos(elec(e)%theta_pos)
            y_e = cfg%R_pcd * sin(elec(e)%theta_pos)
            z_top = 0.0_dp
            do k = 1, m%nz
                do j = 1, m%ntheta
                    do i = 1, m%nr
                        x_c = m%r(i) * cos(m%theta(j))
                        y_c = m%r(i) * sin(m%theta(j))
                        dist = sqrt((x_c - x_e)**2 + (y_c - y_e)**2)
                        if (dist <= cfg%R_elec * 2.0_dp .and. &
                            sol%alpha_s(i,j,k) > 0.01_dp) z_top = max(z_top, m%zf(k))
                    end do
                end do
            end do
            if (m%is_parallel) then
                call mpi_allreduce_max(z_top, z_glob, m%topo)
                z_top = z_glob
            end if
            ! Descenso de bore-in desde el arranque (update_electrodes)
            z_desc = cfg%H_total - 0.1_dp - BORE_IN_SPEED * time
            if (z_desc > z_top .and. z_desc > cfg%H_bowl + 0.1_dp) then
                elec(e)%bore_in_done = .false.
                elec(e)%z_tip = max(z_desc, cfg%H_bowl + 0.05_dp)
            else
                elec(e)%bore_in_done = .true.
                elec(e)%z_tip = min(max(z_top + ARC_LENGTH_SET, cfg%H_bowl + 0.05_dp), &
                                    cfg%H_total - 0.1_dp)
            end if
            elec(e)%arc_length = 0.05_dp     ! se recalcula de V en cada paso
            elec(e)%arc_R = 1.0e-3_dp
            elec(e)%arc_power = 0.0_dp
        end do
    end subroutine reconstruct_electrodes

    !---------------------------------------------------------------------------
    ! La malla del snapshot debe ser la del config
    !---------------------------------------------------------------------------
    subroutine check_dims(gid, name, m, rank)
        integer(HID_T), intent(in)   :: gid
        character(len=*), intent(in) :: name
        type(mesh_t), intent(in)     :: m
        integer, intent(in)          :: rank

        integer(HID_T) :: dset_id, fspace
        integer(HSIZE_T) :: dims(3), maxdims(3)
        integer :: error, ng(3)

        call h5dopen_f(gid, name, dset_id, error)
        call check_h5(error, 'h5dopen_f: '//name, rank)
        call h5dget_space_f(dset_id, fspace, error)
        call h5sget_simple_extent_dims_f(fspace, dims, maxdims, error)
        call h5sclose_f(fspace, error)
        call h5dclose_f(dset_id, error)
        if (m%is_parallel) then
            ng = [m%topo%nr_global, m%topo%nth_global, m%topo%nz_global]
        else
            ng = [m%nr, m%ntheta, m%nz]
        end if
        if (any(int(dims) /= ng)) then
            if (rank == 0) print '(A,3I5,A,3I5)', &
                ' [RESTART] ERROR: malla del snapshot ', int(dims), &
                ' distinta de la del config ', ng
            call MPI_Abort(MPI_COMM_WORLD, 1, error)
        end if
    end subroutine check_dims

    !---------------------------------------------------------------------------
    ! Lectura de un campo 3D por hyperslab propio (espejo de write_3d_field)
    !---------------------------------------------------------------------------
    subroutine read_3d_field(gid, name, field, m, plist_xfer)
        integer(HID_T), intent(in)   :: gid, plist_xfer
        character(len=*), intent(in) :: name
        real(dp), intent(inout)      :: field(-1:,-1:,-1:)
        type(mesh_t), intent(in)     :: m

        integer(HID_T) :: dset_id, fspace, mspace
        integer(HSIZE_T) :: dims_local(3), offset(3)
        integer :: error, rank
        real(dp), allocatable :: buf(:,:,:)

        rank = 0
        if (m%is_parallel) rank = m%topo%rank
        call h5dopen_f(gid, name, dset_id, error)
        call check_h5(error, 'h5dopen_f: '//name, rank)
        if (m%is_parallel) then
            dims_local = [m%topo%iloc, m%topo%jloc, m%topo%kloc]
            offset = [m%topo%iglobal_start - 1, m%topo%jglobal_start - 1, &
                      m%topo%kglobal_start - 1]
            allocate(buf(dims_local(1), dims_local(2), dims_local(3)))
            call h5dget_space_f(dset_id, fspace, error)
            call h5sselect_hyperslab_f(fspace, H5S_SELECT_SET_F, offset, dims_local, error)
            call h5screate_simple_f(3, dims_local, mspace, error)
            call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, buf, dims_local, error, &
                           mem_space_id=mspace, file_space_id=fspace, xfer_prp=plist_xfer)
            call check_h5(error, 'h5dread_f: '//name, rank)
            field(m%topo%istart:m%topo%iend, m%topo%jstart:m%topo%jend, &
                  m%topo%kstart:m%topo%kend) = buf
            call h5sclose_f(mspace, error)
            call h5sclose_f(fspace, error)
        else
            dims_local = [m%nr, m%ntheta, m%nz]
            allocate(buf(m%nr, m%ntheta, m%nz))
            call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, buf, dims_local, error)
            call check_h5(error, 'h5dread_f: '//name, rank)
            field(1:m%nr, 1:m%ntheta, 1:m%nz) = buf
        end if
        call h5dclose_f(dset_id, error)
        deallocate(buf)
    end subroutine read_3d_field

    subroutine read_3d_field_int(gid, name, field, m, plist_xfer)
        integer(HID_T), intent(in)   :: gid, plist_xfer
        character(len=*), intent(in) :: name
        integer, intent(inout)       :: field(-1:,-1:,-1:)
        type(mesh_t), intent(in)     :: m

        integer(HID_T) :: dset_id, fspace, mspace
        integer(HSIZE_T) :: dims_local(3), offset(3)
        integer :: error, rank
        integer, allocatable :: buf(:,:,:)

        rank = 0
        if (m%is_parallel) rank = m%topo%rank
        call h5dopen_f(gid, name, dset_id, error)
        call check_h5(error, 'h5dopen_f: '//name, rank)
        if (m%is_parallel) then
            dims_local = [m%topo%iloc, m%topo%jloc, m%topo%kloc]
            offset = [m%topo%iglobal_start - 1, m%topo%jglobal_start - 1, &
                      m%topo%kglobal_start - 1]
            allocate(buf(dims_local(1), dims_local(2), dims_local(3)))
            call h5dget_space_f(dset_id, fspace, error)
            call h5sselect_hyperslab_f(fspace, H5S_SELECT_SET_F, offset, dims_local, error)
            call h5screate_simple_f(3, dims_local, mspace, error)
            call h5dread_f(dset_id, H5T_NATIVE_INTEGER, buf, dims_local, error, &
                           mem_space_id=mspace, file_space_id=fspace, xfer_prp=plist_xfer)
            call check_h5(error, 'h5dread_f: '//name, rank)
            field(m%topo%istart:m%topo%iend, m%topo%jstart:m%topo%jend, &
                  m%topo%kstart:m%topo%kend) = buf
            call h5sclose_f(mspace, error)
            call h5sclose_f(fspace, error)
        else
            dims_local = [m%nr, m%ntheta, m%nz]
            allocate(buf(m%nr, m%ntheta, m%nz))
            call h5dread_f(dset_id, H5T_NATIVE_INTEGER, buf, dims_local, error)
            call check_h5(error, 'h5dread_f: '//name, rank)
            field(1:m%nr, 1:m%ntheta, 1:m%nz) = buf
        end if
        call h5dclose_f(dset_id, error)
        deallocate(buf)
    end subroutine read_3d_field_int

    !---------------------------------------------------------------------------
    ! Atributos (metadatos: los leen todos los ranks)
    !---------------------------------------------------------------------------
    subroutine read_attr_real(loc, name, val, adims)
        integer(HID_T), intent(in)   :: loc
        character(len=*), intent(in) :: name
        real(dp), intent(out)        :: val
        integer(HSIZE_T), intent(in) :: adims(1)
        integer(HID_T) :: attr_id
        integer :: error
        call h5aopen_f(loc, name, attr_id, error)
        call check_h5(error, 'h5aopen_f: '//name, 0)
        call h5aread_f(attr_id, H5T_NATIVE_DOUBLE, val, adims, error)
        call h5aclose_f(attr_id, error)
    end subroutine read_attr_real

    subroutine read_attr_int(loc, name, val, adims)
        integer(HID_T), intent(in)   :: loc
        character(len=*), intent(in) :: name
        integer, intent(out)         :: val
        integer(HSIZE_T), intent(in) :: adims(1)
        integer(HID_T) :: attr_id
        integer :: error
        call h5aopen_f(loc, name, attr_id, error)
        call check_h5(error, 'h5aopen_f: '//name, 0)
        call h5aread_f(attr_id, H5T_NATIVE_INTEGER, val, adims, error)
        call h5aclose_f(attr_id, error)
    end subroutine read_attr_int

    subroutine read_attr_real_arr(loc, name, vals, adims)
        integer(HID_T), intent(in)   :: loc
        character(len=*), intent(in) :: name
        real(dp), intent(out)        :: vals(:)
        integer(HSIZE_T), intent(in) :: adims(1)
        integer(HID_T) :: attr_id
        integer :: error
        call h5aopen_f(loc, name, attr_id, error)
        call check_h5(error, 'h5aopen_f: '//name, 0)
        call h5aread_f(attr_id, H5T_NATIVE_DOUBLE, vals, adims, error)
        call h5aclose_f(attr_id, error)
    end subroutine read_attr_real_arr

    subroutine read_attr_int_arr(loc, name, vals, adims)
        integer(HID_T), intent(in)   :: loc
        character(len=*), intent(in) :: name
        integer, intent(out)         :: vals(:)
        integer(HSIZE_T), intent(in) :: adims(1)
        integer(HID_T) :: attr_id
        integer :: error
        call h5aopen_f(loc, name, attr_id, error)
        call check_h5(error, 'h5aopen_f: '//name, 0)
        call h5aread_f(attr_id, H5T_NATIVE_INTEGER, vals, adims, error)
        call h5aclose_f(attr_id, error)
    end subroutine read_attr_int_arr

    subroutine fill_periodic_theta_int(field, nth)
        integer, intent(inout) :: field(-1:,-1:,-1:)
        integer, intent(in)    :: nth
        field(:, -1,    :) = field(:, nth-1, :)
        field(:,  0,    :) = field(:, nth,   :)
        field(:, nth+1, :) = field(:, 1,     :)
        field(:, nth+2, :) = field(:, 2,     :)
    end subroutine fill_periodic_theta_int

    subroutine check_h5(error, context, rank)
        integer, intent(in) :: error
        character(len=*), intent(in) :: context
        integer, intent(in) :: rank
        integer :: abort_err
        if (error < 0) then
            write(*,'(A,A,A,I0,A,I0)') '[RESTART] ERROR HDF5 en ', trim(context), &
                  ', code=', error, ', rank=', rank
            call MPI_Abort(MPI_COMM_WORLD, 1, abort_err)
        end if
    end subroutine check_h5

end module mod_restart
