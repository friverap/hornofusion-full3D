#!/bin/bash
#===============================================================================
# bitwise_check.sh <bin_ref> <bin_new> [outdir]   (Plan H, P0)
#   Corre con los dos binarios un corto de B1 (malla media, plantilla de
#   campanas con los parametros de B1, 30 pasos) y un corto de produccion
#   (config_production_full, 5 pasos) y exige audit.csv IDENTICO byte a byte y
#   el snapshot final igual a 0 (compare_decomposition --rtol 0). Es el gate
#   de "con solve_slag false / slag_in_volume false nada cambia".
#===============================================================================
set -u
REF=$1; NEW=$2; OUT=${3:-/tmp/bitwise_check}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
FAIL=0
run() {  # <bin> <tag> <case>
    local bin=$1 tag=$2 case=$3 d=$OUT/$3_$2
    rm -rf "$d"; mkdir -p "$d"
    case $case in
      b1)   cp input/config_300s_borein.dat "$d/config.dat"
            printf '\nnr = 30\nntheta = 60\nnz = 42\ndt = 0.002\ndt_min = 0.001\ndt_max = 0.01\ncfl_max = 1.0\nadaptive_dt = true\nsolve_slag = false\nsolve_species = true\naudit_freq = 1\nt_final = 0.03\noutput_freq = 1000000\nmonitor_freq = 1000\n' >> "$d/config.dat"; np=12 ;;
      prod) cp input/config_production_full.dat "$d/config.dat"
            printf '\nt_final = 0.005\naudit_freq = 1\noutput_freq = 1000000\nmonitor_freq = 1000\n' >> "$d/config.dat"; np=12 ;;
    esac
    printf 'output_dir = %s\n' "$d" >> "$d/config.dat"
    mpirun -n $np "$bin" "$d/config.dat" > "$d/run.log" 2>&1 || { echo "FAIL: $case/$tag termino con error"; FAIL=1; }
}
for c in b1 prod; do
    run "$REF" ref $c; run "$NEW" new $c
    if cmp -s "$OUT/${c}_ref/audit.csv" "$OUT/${c}_new/audit.csv"; then
        echo "  PASS  $c audit.csv identico"
    else
        echo "  FAIL  $c audit.csv distinto"; FAIL=1
    fi
    python3 tests/integration/compare_decomposition.py "$OUT/${c}_new" "$OUT/${c}_ref" --rtol 0 | tail -1
    python3 tests/integration/compare_decomposition.py "$OUT/${c}_new" "$OUT/${c}_ref" --rtol 0 > /dev/null || FAIL=1
done
[ $FAIL -eq 0 ] && echo "BITWISE: OK" || { echo "BITWISE: FALLO"; exit 1; }
