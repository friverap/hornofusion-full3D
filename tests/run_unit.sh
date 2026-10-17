#!/bin/bash
#===============================================================================
# run_unit.sh - Ejecuta los unit tests Fortran compilados en tests/bin/
# Cada binario corre como proceso MPI singleton (sin mpirun).
# XFAIL: ids "unit:<nombre>" en tests/xfail.list.
#===============================================================================
set -u
cd "$(dirname "$0")/.."

XFAIL_LIST=tests/xfail.list
FAILURES=0

is_xfail() { grep -qx "unit:$1" "$XFAIL_LIST" 2>/dev/null; }

for t in tests/bin/*; do
    [ -x "$t" ] || continue
    name=$(basename "$t")
    # (auditoria dirigida 16, B2) tope de tiempo: un cuelgue (A15-1) falla el
    # gate en vez de colgarlo. (auditoria 18) con SIGKILL desde un vigilante:
    # el SIGALRM de perl lo ignoraba el binario MPI singleton (Open MPI instala
    # sus manejadores; test_mesh_seam colgo 50 min en el rebaseline v123)
    "$t" > "tests/bin/$name.log" 2>&1 &
    tpid=$!
    # el vigilante no hereda la salida y mata a su propio sleep al terminar
    # (dirigida de bajos A18, B2: un sleep huerfano por test retenia el stdout
    # y una tuberia 'make test-unit | tee' no cerraba hasta 300 s despues)
    ( exec >/dev/null 2>&1
      sleep "${UNIT_TIMEOUT:-300}" & sp=$!
      trap 'kill $sp 2>/dev/null; exit 0' TERM
      wait $sp && kill -9 "$tpid" 2>/dev/null ) &
    wpid=$!
    wait "$tpid"; trc=$?
    kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
    if [ "$trc" -eq 137 ]; then
        echo "TIMEOUT unit:$name (> ${UNIT_TIMEOUT:-300} s, matado con SIGKILL)" >> "tests/bin/$name.log"
    fi
    if [ "$trc" -eq 0 ]; then
        if is_xfail "$name"; then
            echo "XPASS unit:$name (quitar de tests/xfail.list)"
        else
            grep -h '^ PASS' "tests/bin/$name.log" || echo "PASS unit:$name"
        fi
    else
        if is_xfail "$name"; then
            echo "XFAIL unit:$name (fallo esperado hasta su fix)"
        else
            echo "FAIL unit:$name"
            cat "tests/bin/$name.log"
            FAILURES=$((FAILURES + 1))
        fi
    fi
done

echo "------------------------------------------------------------"
if [ "$FAILURES" -eq 0 ]; then
    echo "UNIT TESTS: OK"
else
    echo "UNIT TESTS: $FAILURES fallo(s)"
    exit 1
fi
