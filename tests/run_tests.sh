#!/bin/bash
#===============================================================================
# run_tests.sh - Driver de tests de integración EAF3D
#
# Uso:  bash tests/run_tests.sh quick|full|rebaseline
#   quick      : cold_10step -n 8 + invariantes + audit + métricas   (~1 min)
#   full       : matriz completa {configs} x {ranks} + todos los checks
#   rebaseline : corre la matriz completa y regenera el golden de métricas
#                (STAGE=v1 bash tests/run_tests.sh rebaseline para nombrarlo)
#
# XFAIL: los ids listados en tests/xfail.list son fallos esperados hasta que
# aterrice su fix (no bloquean); un XPASS avisa de que hay que quitar el id.
#===============================================================================
set -u
cd "$(dirname "$0")/.."

MODE=${1:-quick}
BIN=./bin/eaf3d_mpi
OUT=tests/out
CFG=tests/integration/configs
INT=tests/integration
PY=python3
XFAIL_LIST=tests/xfail.list
FAILURES=0

[ -x "$BIN" ] || { echo "ERROR: falta $BIN (correr 'make' primero)"; exit 2; }

is_xfail()  { grep -qx "$1" "$XFAIL_LIST" 2>/dev/null; }
xfail_ids() { grep "^$1:" "$XFAIL_LIST" 2>/dev/null | cut -d: -f2- | paste -sd, -; }
note_fail() { FAILURES=$((FAILURES + 1)); }

#------------------------------------------------------------------------------
# run_case <config_name> <nprocs>  -> corrida en tests/out/<name>_n<np>
#------------------------------------------------------------------------------
run_case() {
    local name=$1 np=$2
    local dir=$OUT/${name}_n${np}
    rm -rf "$dir" && mkdir -p "$dir"
    local tmpcfg=$dir/config.dat
    cp "$CFG/$name.dat" "$tmpcfg"
    printf '\noutput_dir = %s\n' "$dir" >> "$tmpcfg"
    echo "== corrida $name -n $np"
    if ! mpirun -n "$np" "$BIN" "$tmpcfg" > "$dir/run.log" 2>&1; then
        echo "FAIL: la corrida $name -n $np terminó con error (ver $dir/run.log)"
        tail -5 "$dir/run.log"
        note_fail
        return 1
    fi
    if grep -q '\[CONFIG\] WARNING' "$dir/run.log"; then
        echo "FAIL: clave de config desconocida en $name (¿typo?):"
        grep '\[CONFIG\] WARNING' "$dir/run.log" | head -3
        note_fail
        return 1
    fi
    if ! ls "$dir"/eaf3d_*.h5 > /dev/null 2>&1; then
        echo "FAIL: $name -n $np no produjo snapshots"
        note_fail
        return 1
    fi
}

#------------------------------------------------------------------------------
# run_restart_case <base> <np_base> <np> <step>
#   Reanuda <base> desde tests/out/<base>_n<np_base>/eaf3d_<step>.h5 con <np>
#   ranks hasta el mismo t_final y compara el snapshot final con la corrida
#   continua (compare_decomposition): el reinicio debe ser un estado
#   COMPLETO — BIT A BIT (1e-12) con el mismo nº de ranks; con distinto nº
#   la tolerancia es la de la invarianza de descomposición (1e-3; medido
#   4e-9 tras 5 pasos). Vive en tests/out/restart/ (fuera del golden).
#------------------------------------------------------------------------------
run_restart_case() {
    local base=$1 npb=$2 np=$3 st=$4
    local src=$OUT/${base}_n${npb}
    local dir=$OUT/restart/${base}_n${npb}_to_n${np}_s${st}
    local snap
    snap=$(printf '%s/eaf3d_%08d.h5' "$src" "$st")
    [ -f "$snap" ] || { echo "FAIL: falta el snapshot $snap"; note_fail; return 1; }
    rm -rf "$dir" && mkdir -p "$dir"
    local tmpcfg=$dir/config.dat
    cp "$CFG/$base.dat" "$tmpcfg"
    printf '\noutput_dir = %s\nrestart_file = %s\n' "$dir" "$snap" >> "$tmpcfg"
    echo "== reinicio $base desde paso $st (n$npb -> n$np)"
    if ! mpirun -n "$np" "$BIN" "$tmpcfg" > "$dir/run.log" 2>&1; then
        echo "FAIL: el reinicio $base n$np terminó con error (ver $dir/run.log)"
        tail -5 "$dir/run.log"
        note_fail
        return 1
    fi
    local rtol=1e-12
    [ "$np" = "$npb" ] || rtol=1e-10   # (medido 8.5e-13; antes 1e-3)
    run_script "restart_${base}_n${npb}_to_n${np}" \
        $PY $INT/compare_decomposition.py "$dir" "$src" --rtol $rtol
}

#------------------------------------------------------------------------------
# run_script <xfail_id> <cmd...>  -> maneja XFAIL/XPASS de scripts completos
#------------------------------------------------------------------------------
run_script() {
    local id=$1
    shift
    if "$@"; then
        if is_xfail "script:$id"; then
            echo ">> XPASS script:$id (quitar de tests/xfail.list)"
        fi
    else
        if is_xfail "script:$id"; then
            echo ">> XFAIL script:$id (fallo esperado hasta su fix)"
        else
            echo ">> FAIL script:$id"
            note_fail
        fi
    fi
}

check_invariants() {  # <rundir> <config_name>
    if ! $PY $INT/check_invariants.py "$1" --config "$CFG/$2.dat" \
            --xfail "$(xfail_ids invariants)"; then
        echo ">> FAIL invariantes en $1"
        note_fail
    fi
}

check_audit_if_present() {  # <rundir> [prefijo_xfail_extra] [args extra]
    local extra="" more="${3:-}"
    [ -n "${2:-}" ] && extra=",$(xfail_ids "$2")"
    # config del caso (nombre del directorio sin _nN): solve_energy = false
    # => el balance de energia no aplica (auditoria 2, N-C3)
    local base cfgarg=""
    base=$(basename "$1"); base=${base%_n*}
    [ -f "$CFG/$base.dat" ] && cfgarg="--config $CFG/$base.dat"
    if [ -f "$1/audit.csv" ]; then
        if ! $PY $INT/check_audit.py "$1" $cfgarg $more --xfail "$(xfail_ids audit)$extra"; then
            echo ">> FAIL auditoría en $1"
            note_fail
        fi
    fi
}

#------------------------------------------------------------------------------
case "$MODE" in
quick)
    mkdir -p "$OUT"
    run_case cold_10step 8 && {
        check_invariants "$OUT/cold_10step_n8" cold_10step
        check_audit_if_present "$OUT/cold_10step_n8" audit_cold
        if ! $PY $INT/metrics_snapshot.py "$OUT" --mode check \
                --only cold_10step_n8; then
            echo ">> FAIL métricas golden"
            note_fail
        fi
        # Reinicio desde el snapshot intermedio (paso 5): estado completo
        run_restart_case cold_10step 8 8 5
        # Baño en reposo en el gate por commit (auditoria 2, N-A6; ~10 s):
        # fuerza balanceada, intercambio gas-liquido y balance de energia
        run_case bath_test 4 && {
            check_invariants "$OUT/bath_test_n4" bath_test
            check_audit_if_present "$OUT/bath_test_n4"
            run_script "bath_test" \
                $PY $INT/check_bath.py "$OUT/bath_test_n4" --config "$CFG/bath_test.dat" \
                --xfail "$(xfail_ids bath)"
            if ! $PY $INT/metrics_snapshot.py "$OUT" --mode check \
                    --only bath_test_n4; then
                echo ">> FAIL métricas golden (bath_test)"
                note_fail
            fi
        }
    }
    ;;

full | rebaseline)
    rm -rf "$OUT" && mkdir -p "$OUT"
    run_case cold_10step 1
    run_case cold_10step 4
    run_case cold_10step 8
    # 12 ranks = 2x3x2: la UNICA corrida de la matriz que parte r (las
    # fronteras de bloque en r se trataban como pared en 5 sitios, oct-2026)
    run_case cold_10step 12
    run_case melt_forced 8
    run_case noflow_energy 1
    run_case symmetry_3elec 6
    run_case outer_conv 8
    run_case chem_test 4
    run_case ecs_test 1
    run_case ecs_test 8
    run_case slag_chem_test 1
    run_case slag_chem_test 8
    # (auditoria 2, N-A4) descomposiciones cuyas fronteras CRUZAN las fases:
    # n9 = 1x3x3 corta z en la superficie del baño (k 5|6), n12 = 2x3x2 corta
    # r a traves del baño (n4/n8 cortan z en k = 8, sobre las fases)
    run_case slag_chem_test 9
    run_case slag_chem_flow 4
    # Bug 19 (Plan C, F0): bancos del bano de liquido puro — reposo (n1/n4)
    # y llenado por fusion (n4). Sus checks propios (bath:*) llevan xfail
    # con causa hasta F1/F2; los invariantes duros (nan/bounds) NO.
    run_case bath_test 1
    run_case bath_test 4
    run_case bath_test 12
    run_case bath_fill 4
    run_case bath_mix 4
    run_case bath_fill_mix 4
    run_case bath_freeze 4
    # Descomposicion del lecho inundado/congelado (auditoria M22: celdas
    # selladas en la frontera entre ranks; antes 9.7 % en alpha_l n1 vs n4)
    run_case bath_freeze 1
    run_case bath_freeze 9
    # Lecho INUNDADO (Plan D D0): poros llenos bajo chatarra que funde y drena;
    # reproduce el regimen de B1 a ~320 s. Su check bed_flood:bath_pv_bounded
    # lleva xfail con causa.
    run_case bed_flood 4
    # Arco sin chatarra (auditoria 12-oct, C1): respaldo de P_rad
    run_case arc_noscrap 4
    # Cesta 2 durante la corrida (auditoria A5): carga aditiva y auditada
    run_case cold_bucket2 4
    # Drenaje del lecho con la fuerza balanceada (auditoria 2, N-C1)
    run_case bed_drain 4

    for d in "$OUT"/cold_10step_n*; do
        check_invariants "$d" cold_10step
    done
    # melt_forced: régimen violento aún inestable (gated en C3.4) ->
    # sus invariantes duros (nan/bounds) llevan xfail PROPIO por corrida
    if ! $PY $INT/check_invariants.py "$OUT/melt_forced_n8" \
            --config "$CFG/melt_forced.dat" \
            --xfail "$(xfail_ids invariants),$(xfail_ids invariants_melt)"; then
        echo ">> FAIL invariantes en melt_forced_n8"
        note_fail
    fi
    check_invariants "$OUT/noflow_energy_n1" noflow_energy
    check_invariants "$OUT/symmetry_3elec_n6" symmetry_3elec

    run_script "decomposition_cold_n1" \
        $PY $INT/compare_decomposition.py "$OUT/cold_10step_n1" "$OUT/cold_10step_n8" --rtol 1e-10
    run_script "decomposition_cold_n4" \
        $PY $INT/compare_decomposition.py "$OUT/cold_10step_n4" "$OUT/cold_10step_n8" --rtol 1e-10
    run_script "decomposition_cold_r" \
        $PY $INT/compare_decomposition.py "$OUT/cold_10step_n1" "$OUT/cold_10step_n12" --rtol 1e-10
    run_script "symmetry" \
        $PY $INT/check_symmetry.py "$OUT/symmetry_3elec_n6"
    run_script "melt" \
        $PY $INT/check_melt.py "$OUT/melt_forced_n8" --config "$CFG/melt_forced.dat"
    run_script "outer_convergence" \
        $PY $INT/check_outer.py "$OUT/outer_conv_n8" --max-outer 30
    run_script "chem" \
        $PY $INT/check_chem.py "$OUT/chem_test_n4" --config "$CFG/chem_test.dat"
    run_script "ecs" \
        $PY $INT/check_ecs.py "$OUT/ecs_test_n8" --config "$CFG/ecs_test.dat"
    run_script "decomposition_ecs" \
        $PY $INT/compare_decomposition.py "$OUT/ecs_test_n1" "$OUT/ecs_test_n8" --rtol 1e-12
    run_script "slag_chem" \
        $PY $INT/check_slag_chem.py "$OUT/slag_chem_test_n8" --config "$CFG/slag_chem_test.dat"
    run_script "slag_chem_flow" \
        $PY $INT/check_slag_chem.py "$OUT/slag_chem_flow_n4" --config "$CFG/slag_chem_flow.dat"
    # escoria por columna global (auditoria A14): invariante a la descomposicion
    # ECS con r DESCOMPUESTO (12 ranks -> 2x3x2): antes de la auditoria M38
    # la carga no se depositaba (indice radial local tomado como global)
    run_case ecs_test 12 && run_script "decomposition_ecs_r" \
        $PY $INT/compare_decomposition.py "$OUT/ecs_test_n12" "$OUT/ecs_test_n1" --rtol 1e-12
    run_script "decomposition_slag" \
        $PY $INT/compare_decomposition.py "$OUT/slag_chem_test_n1" "$OUT/slag_chem_test_n8" --rtol 1e-4
    for d in "$OUT"/bath_test_n*; do
        check_invariants "$d" bath_test
        run_script "bath_test" \
            $PY $INT/check_bath.py "$d" --config "$CFG/bath_test.dat" \
            --xfail "$(xfail_ids bath)"
    done
    check_invariants "$OUT/bath_fill_n4" bath_fill
    run_script "bath_fill" \
        $PY $INT/check_bath.py "$OUT/bath_fill_n4" --config "$CFG/bath_fill.dat" --fill \
        --xfail "$(xfail_ids bath_fill)"
    # Modelo de MEZCLA (Plan G): baño en reposo y llenado con fusion y arco
    check_invariants "$OUT/bath_mix_n4" bath_mix
    run_script "bath_mix" \
        $PY $INT/check_bath.py "$OUT/bath_mix_n4" --config "$CFG/bath_mix.dat" \
        --xfail "$(xfail_ids bath_mix)"
    check_invariants "$OUT/bath_fill_mix_n4" bath_fill_mix
    run_script "bath_fill_mix" \
        $PY $INT/check_bath.py "$OUT/bath_fill_mix_n4" --config "$CFG/bath_fill_mix.dat" --fill \
        --xfail "$(xfail_ids bath_fill_mix)"
    check_invariants "$OUT/bath_freeze_n4" bath_freeze
    run_script "bath_freeze" \
        $PY $INT/check_bath.py "$OUT/bath_freeze_n4" --config "$CFG/bath_freeze.dat" --fill \
        --xfail "$(xfail_ids bath_freeze)"
    check_invariants "$OUT/bed_flood_n4" bed_flood
    check_invariants "$OUT/arc_noscrap_n4" arc_noscrap
    check_invariants "$OUT/cold_bucket2_n4" cold_bucket2
    run_script "bed_flood" \
        $PY $INT/check_bath.py "$OUT/bed_flood_n4" --config "$CFG/bed_flood.dat" --fill \
        --xfail "$(xfail_ids bed_flood)"
    check_invariants "$OUT/bed_drain_n4" bed_drain
    run_script "bed_drain" \
        $PY $INT/check_drain.py "$OUT/bed_drain_n4" --xfail "$(xfail_ids bed_drain)"
    # Auditoria de energia/masa/arco en TODA corrida de la matriz (auditoria
    # 2, N-C3: antes 13 de 26 no se auditaban; bath_freeze fallaba con err 1)
    for d in "$OUT"/*_n*; do
        more=""
        case $(basename "$d") in
            arc_noscrap_*)   more="--min-liq-arc 0.6" ;;
            outer_conv_*)    more="--etol 1e-4" ;;   # lazo convergido (N-A6)
        esac
        case $(basename "$d") in
            cold_10step_*)   x=audit_cold ;;
            arc_noscrap_*)   x=audit_arcnoscrap ;;
            noflow_energy_*) x=audit_noflow ;;
            *)               x="" ;;
        esac
        check_audit_if_present "$d" "$x" "$more"
    done
    run_script "decomposition_bath" \
        $PY $INT/compare_decomposition.py "$OUT/bath_test_n1" "$OUT/bath_test_n4" --rtol 1e-8
    run_script "decomposition_bath_r" \
        $PY $INT/compare_decomposition.py "$OUT/bath_test_n1" "$OUT/bath_test_n12" --rtol 1e-8
    run_script "decomposition_freeze_z" \
        $PY $INT/compare_decomposition.py "$OUT/bath_freeze_n1" "$OUT/bath_freeze_n9" --rtol 1e-5
    run_script "decomposition_slag_z" \
        $PY $INT/compare_decomposition.py "$OUT/slag_chem_test_n1" "$OUT/slag_chem_test_n9" --rtol 1e-4
    run_script "decomposition_freeze" \
        $PY $INT/compare_decomposition.py "$OUT/bath_freeze_n1" "$OUT/bath_freeze_n4" --rtol 1e-5
    # Reinicio desde snapshot: mismo numero de ranks y distinto (lectura por
    # hyperslab), y sobre el regimen de fusion (melt_forced, paso 6 de 11)
    run_restart_case cold_10step 8 8 5
    run_restart_case cold_10step 8 4 5
    run_restart_case melt_forced 8 8 6
    # (auditoria 2, N-A5) reinicios que ejercen el estado del lecho y la
    # mascara liq_cont_prev (transiciones disperso->continuo), la
    # congelacion y la descomposicion que parte r
    run_restart_case bed_drain 4 4 150
    run_restart_case bath_freeze 4 4 50
    run_restart_case cold_10step 12 12 5

    if [ "$MODE" = "rebaseline" ]; then
        $PY $INT/metrics_snapshot.py "$OUT" --mode rebaseline \
            ${STAGE:+--stage "$STAGE"} || note_fail
    else
        if ! $PY $INT/metrics_snapshot.py "$OUT" --mode check; then
            echo ">> FAIL métricas golden"
            note_fail
        fi
    fi
    ;;

*)
    echo "Uso: $0 quick|full|rebaseline"
    exit 2
    ;;
esac

echo "------------------------------------------------------------"
if [ "$FAILURES" -eq 0 ]; then
    echo "TESTS ($MODE): OK"
else
    echo "TESTS ($MODE): $FAILURES fallo(s)"
    exit 1
fi
