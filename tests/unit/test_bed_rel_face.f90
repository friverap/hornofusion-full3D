!===============================================================================
! test_bed_rel_face.f90 - Flotacion relativa del lecho por caras: la definicion
! UNICA que usan momento (bed_rel_f) y Poisson (bed_rel_fp) (auditoria 6; el
! pendiente de la auditoria 4 era un unitario que las comparara: ahora ambas
! son envolturas de mod_workspace::bed_rel_face y mix_cell_weight, y el
! Rhie-Chow cancela la flotacion solo si son identicas).
!   1. Ceros EXACTOS: sin fuerza balanceada, sin mascaras validas, sin liquido
!      en la cara (corridas frias bit a bit) o con mascara nula.
!   2. Valor a mano: liquido con ws_bedl_f = 0.7 y gas con max(min(ws_bed_gas),
!      ws_bub_f), peso propio ponderado por alpha (B4-10).
!   3. Cara de columna UNIFORME con W = peso de mezcla por volumen de fluido y
!      mascara comun: sum_q alpha_q B_q = 0 (la flotacion relativa no empuja a
!      la mezcla; A4-1) a 1e-14 relativo.
!   4. mix_cell_weight: sin continuidad solo cuenta el gas; sin fluido, 0;
!      liq_cont_fallback coincide con el umbral del Poisson (1e-2).
!===============================================================================
program test_bed_rel_face
    use mod_constants
    use mod_types_3d
    use mod_mpi_topology
    use mod_config_3d, only: config_set_defaults
    use mod_mesh_3d, only: mesh_generate_parallel
    use mod_workspace
    implicit none

    type(config_t) :: cfg
    type(mesh_t)   :: mesh
    real(dp) :: al, ag, rl, rg, Tl, wl, wg, W, Bl, Bg, hand
    logical  :: ok

    call config_set_defaults(cfg)
    cfg%nr = 4; cfg%ntheta = 4; cfg%nz = 6
    call mpi_init_topology(cfg%nr, cfg%ntheta, cfg%nz, mesh%topo)
    call mesh_generate_parallel(mesh, cfg)
    call ensure_workspace(mesh)
    ok = .true.

    al = 0.3_dp; ag = 0.2_dp; rl = 7000.0_dp; rg = 0.3_dp; Tl = 1900.0_dp
    wl = liq_own_weight(rl, Tl, cfg%beta_expansion, cfg%T_ref_boussinesq)
    wg = GRAVITY * rg
    W  = mix_cell_weight(al, wl, ag, rg, .true., .true.)

    ! --- 1. ceros exactos ---
    ws_bed_valid = .true.
    ws_bedl_f = 0.7_dp; ws_bed_gas = 0.5_dp; ws_bub_f = 0.0_dp
    call zero(bed_rel_face(.false., 2, 2, 3, 4, al, al, al, al, wl, wl, W, .false.), 'sin fuerza balanceada')
    ws_bed_valid = .false.
    call zero(bed_rel_face(.false., 2, 2, 3, 4, al, al, al, al, wl, wl, W, .true.), 'mascaras no validas')
    ws_bed_valid = .true.
    call zero(bed_rel_face(.true., 2, 2, 3, 4, 0.0_dp, 5.0e-7_dp, ag, ag, wg, wg, W, .true.), 'sin liquido (gas)')
    call zero(bed_rel_face(.false., 2, 2, 3, 4, 0.0_dp, 5.0e-7_dp, 0.0_dp, 5.0e-7_dp, wl, wl, W, .true.), 'sin liquido (liq)')
    ws_bedl_f = 0.0_dp
    call zero(bed_rel_face(.false., 2, 2, 3, 4, al, al, al, al, wl, wl, W, .true.), 'mascara nula')

    ! --- 2. valores a mano ---
    ws_bedl_f = 0.0_dp; ws_bedl_f(2,2,3) = 0.7_dp      ! cara (3|4) usa min(ka,kb) = 3
    hand = 0.7_dp * ((0.3_dp * wl + 0.1_dp * 0.9_dp * wl) / (0.3_dp + 0.1_dp) - W)
    call near(bed_rel_face(.false., 2, 2, 3, 4, 0.3_dp, 0.1_dp, 0.3_dp, 0.1_dp, wl, 0.9_dp * wl, W, .true.), &
              hand, 'liquido a mano')
    ws_bed_gas = 0.0_dp; ws_bed_gas(2,2,3) = 0.8_dp; ws_bed_gas(2,2,4) = 0.4_dp
    ws_bub_f = 0.0_dp; ws_bub_f(2,2,3) = 0.6_dp
    hand = 0.6_dp * (wg - W)                             ! max(min(0.8,0.4), 0.6)
    call near(bed_rel_face(.true., 2, 2, 3, 4, al, al, ag, ag, wg, wg, W, .true.), hand, 'gas a mano (ws_bub_f gana)')
    ws_bub_f(2,2,3) = 0.1_dp
    hand = 0.4_dp * (wg - W)                             ! max(min(0.8,0.4), 0.1)
    call near(bed_rel_face(.true., 2, 2, 3, 4, al, al, ag, ag, wg, wg, W, .true.), hand, 'gas a mano (minimo de celdas)')

    ! --- 3. sum alpha_q B_q = 0 en columna uniforme con mascara comun ---
    ws_bedl_f = 0.6_dp; ws_bed_gas = 0.6_dp; ws_bub_f = 0.0_dp
    Bl = bed_rel_face(.false., 2, 2, 3, 4, al, al, al, al, wl, wl, W, .true.)
    Bg = bed_rel_face(.true.,  2, 2, 3, 4, al, al, ag, ag, wg, wg, W, .true.)
    if (abs(al * Bl + ag * Bg) > 1.0e-14_dp * (al * abs(Bl) + ag * abs(Bg))) &
        call fail('sum alpha_q B_q /= 0 (relativo)', (al * Bl + ag * Bg) / (al * abs(Bl) + ag * abs(Bg)))
    ! B_f se SUMA al gradiente reducido (fuerza -alpha (g_f + B_f)): el liquido,
    ! mas pesado que la mezcla, lleva B > 0 (empuje hacia abajo) y el gas B < 0
    if (.not. (Bl > 0.0_dp .and. Bg < 0.0_dp)) call fail('signos: el liquido no se hunde o el gas no sube', Bl)

    ! --- 4. mix_cell_weight y respaldo de continuidad ---
    call near(mix_cell_weight(al, wl, ag, rg, .false., .true.), GRAVITY * ag * rg / (al + ag), 'sin continuidad: solo gas')
    call zero(mix_cell_weight(0.0_dp, wl, 0.0_dp, rg, .true., .true.), 'sin fluido')
    call near(mix_cell_weight(al, wl, ag, rg, .true., .false.), al * wl, 'sin fuerza balanceada: alpha_l w_l')
    if (liq_cont_fallback(0.009_dp) .or. .not. liq_cont_fallback(0.011_dp)) &
        call fail('liq_cont_fallback no es el umbral del Poisson (1e-2)', 0.0_dp)

    if (ok) then
        print '(A)', ' PASS test_bed_rel_face (ceros exactos, valores a mano, sum alpha B = 0, peso de mezcla)'
    else
        print '(A)', ' FAIL test_bed_rel_face'
        stop 1
    end if
    call mpi_finalize_topology(mesh%topo)

contains
    subroutine zero(v, msg)
        real(dp), intent(in) :: v
        character(len=*), intent(in) :: msg
        if (v /= 0.0_dp) call fail(msg // ': no es 0 exacto', v)
    end subroutine zero
    subroutine near(v, ref, msg)
        real(dp), intent(in) :: v, ref
        character(len=*), intent(in) :: msg
        if (abs(v - ref) > 1.0e-13_dp * max(abs(ref), 1.0_dp)) call fail(msg, v - ref)
    end subroutine near
    subroutine fail(msg, v)
        character(len=*), intent(in) :: msg
        real(dp), intent(in) :: v
        print '(3A,ES12.4)', '   FAIL ', msg, ': ', v
        ok = .false.
    end subroutine fail
end program test_bed_rel_face
