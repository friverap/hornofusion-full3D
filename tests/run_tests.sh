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

check_audit_if_present() {  # <rundir>
    if [ -f "$1/audit.csv" ] && [ -f "$INT/check_audit.py" ]; then
        run_script "audit_energy" $PY $INT/check_audit.py "$1"
    fi
}

#------------------------------------------------------------------------------
case "$MODE" in
quick)
    mkdir -p "$OUT"
    run_case cold_10step 8 && {
        check_invariants "$OUT/cold_10step_n8" cold_10step
        check_audit_if_present "$OUT/cold_10step_n8"
        if ! $PY $INT/metrics_snapshot.py "$OUT" --mode check \
                --only cold_10step_n8; then
            echo ">> FAIL métricas golden"
            note_fail
        fi
    }
    ;;

full | rebaseline)
    rm -rf "$OUT" && mkdir -p "$OUT"
    run_case cold_10step 1
    run_case cold_10step 4
    run_case cold_10step 8
    run_case melt_forced 8
    run_case noflow_energy 1
    run_case symmetry_3elec 6

    for d in "$OUT"/cold_10step_n*; do
        check_invariants "$d" cold_10step
        check_audit_if_present "$d"
    done
    check_invariants "$OUT/melt_forced_n8" melt_forced
    check_audit_if_present "$OUT/melt_forced_n8"
    check_invariants "$OUT/noflow_energy_n1" noflow_energy
    check_audit_if_present "$OUT/noflow_energy_n1"
    check_invariants "$OUT/symmetry_3elec_n6" symmetry_3elec

    run_script "decomposition_cold_n1" \
        $PY $INT/compare_decomposition.py "$OUT/cold_10step_n1" "$OUT/cold_10step_n8"
    run_script "decomposition_cold_n4" \
        $PY $INT/compare_decomposition.py "$OUT/cold_10step_n4" "$OUT/cold_10step_n8"
    run_script "symmetry" \
        $PY $INT/check_symmetry.py "$OUT/symmetry_3elec_n6"
    run_script "melt" \
        $PY $INT/check_melt.py "$OUT/melt_forced_n8" --config "$CFG/melt_forced.dat"

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
