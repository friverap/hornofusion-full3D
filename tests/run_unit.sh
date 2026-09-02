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
    if "$t" > "tests/bin/$name.log" 2>&1; then
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
