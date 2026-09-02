!===============================================================================
! test_slag_additions.f90 - Adiciones a la escoria (E2.2)
!
! Capa sintética de escoria con masas desiguales; N pasos de adición de
! cal (CaO+MgO) y carbón. Verifica:
!   - conservación: dm_sl total == (mdot_cal + mdot_c) * t a 1e-12
!   - especiación: sum m_CaO == mdot_cal*frac_cao*t; ídem MgO y C
!   - proporcionalidad: cada celda recibe ~ m_sl_cell/m_sl_tot
!   - energía: dE_sl == dm * cp_slag * T_ambient
!===============================================================================
program test_slag_additions
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_fields_3d
    use mod_slag_3d, only: slag_additions
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    type(slag_t)   :: slag
    real(dp), parameter :: MCAL = 2.5_dp, MC = 0.8_dp, DT = 1.0_dp
    real(dp) :: m0, m1, e0, e1, dm, err, w_ref, w_got
    integer :: n, k0
    logical :: ok

    call config_set_defaults(cfg)
    cfg%nr = 8; cfg%ntheta = 8; cfg%nz = 8
    cfg%cal_frac_cao = 0.7_dp
    cfg%cal_frac_mgo = 0.25_dp

    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call slag_allocate(slag, mesh)

    ! capa sintética: nivel k0 con masas desiguales
    k0 = 6
    slag%m_sl(2:7, 1:8, k0) = 10.0_dp
    slag%m_sl(4,   3,   k0) = 50.0_dp    ! celda "pesada"
    slag%alpha_sl(2:7, 1:8, k0) = 0.5_dp
    slag%T_sl(2:7, 1:8, k0) = 1800.0_dp
    slag%E_sl = slag%m_sl * cfg%cp_slag * 1800.0_dp

    ok = .true.
    m0 = sum(slag%m_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    e0 = sum(slag%E_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    w_ref = 50.0_dp / m0     ! peso de la celda pesada

    do n = 1, 10
        call slag_additions(slag, mesh, cfg, MCAL, MC, DT)
    end do

    m1 = sum(slag%m_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    e1 = sum(slag%E_sl(1:mesh%nr, 1:mesh%ntheta, 1:mesh%nz))
    dm = 10.0_dp * (MCAL + MC) * DT

    err = abs((m1 - m0) - dm) / dm
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL conservacion masa, err = ', err
        ok = .false.
    end if

    err = abs(sum(slag%m_X(1:mesh%nr,1:mesh%ntheta,1:mesh%nz,SL_CAO)) &
              - 10.0_dp * MCAL * DT * cfg%cal_frac_cao) / dm
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL CaO, err = ', err; ok = .false.
    end if
    err = abs(sum(slag%m_X(1:mesh%nr,1:mesh%ntheta,1:mesh%nz,SL_MGO)) &
              - 10.0_dp * MCAL * DT * cfg%cal_frac_mgo) / dm
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL MgO, err = ', err; ok = .false.
    end if
    err = abs(sum(slag%m_X(1:mesh%nr,1:mesh%ntheta,1:mesh%nz,SL_C)) &
              - 10.0_dp * MC * DT) / dm
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL C, err = ', err; ok = .false.
    end if

    err = abs((e1 - e0) - (m1 - m0) * cfg%cp_slag * cfg%T_ambient) / (e1 - e0)
    if (err > 1.0e-12_dp) then
        print '(A,ES10.3)', '   FAIL energia, err = ', err; ok = .false.
    end if

    ! proporcionalidad (primer paso domina; usar cota laxa tras 10 pasos
    ! porque los pesos se re-derivan cada paso con la masa creciente)
    w_got = (slag%m_sl(4,3,k0) - 50.0_dp) / (m1 - m0)
    if (abs(w_got - w_ref) / w_ref > 0.05_dp) then
        print '(A,2F8.4)', '   FAIL proporcionalidad: w_ref, w_got = ', &
            w_ref, w_got
        ok = .false.
    end if

    if (ok) then
        print '(A,F8.2,A)', ' PASS test_slag_additions (', m1 - m0, ' kg)'
    else
        print '(A)', ' FAIL test_slag_additions'
        stop 1
    end if
end program test_slag_additions
