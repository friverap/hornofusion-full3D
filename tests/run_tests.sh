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

# run_case_restart_from <config_name> <nprocs> <snapshot>: como run_case pero
# reanudando desde un estado construido (auditoria 6, pocket_rise)
run_case_restart_from() {
    local name=$1 np=$2 snap=$3
    local dir=$OUT/${name}_n${np}
    rm -rf "$dir" && mkdir -p "$dir"
    cp "$CFG/$name.dat" "$dir/config.dat"
    printf '\noutput_dir = %s\nrestart_file = %s\n' "$dir" "$snap" >> "$dir/config.dat"
    echo "== corrida $name -n $np (desde $snap)"
    if ! mpirun -n "$np" "$BIN" "$dir/config.dat" > "$dir/run.log" 2>&1; then
        echo "FAIL: la corrida $name -n $np terminó con error (ver $dir/run.log)"
        tail -5 "$dir/run.log"; note_fail; return 1
    fi
    if grep -q '\[CONFIG\] WARNING\|\[CG\] AVISO\|\[ALPHA\] AVISO\|\[DO\] AVISO\|\[CHARGE\] WARNING\|\[ECS\] AVISO\|\[SLAG\] AVISO\|\[RESTART\] AVISO\|\[CONFIG\] AVISO\|\[INPUT\] AVISO' "$dir/run.log"; then
        echo "FAIL: aviso en $name -n $np:"; grep 'WARNING\|AVISO' "$dir/run.log" | head -3
        note_fail; return 1
    fi
    if ! ls "$dir"/eaf3d_*.h5 > /dev/null 2>&1; then
        echo "FAIL: $name -n $np no produjo snapshots"; note_fail; return 1
    fi
}

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
    # (auditoria 3, M3-8) un CG sin converger o un fallback implicito del
    # transporte de alpha son fallos del caso, no ruido de stdout:
    # slag_chem_flow corria con res 2.3e-2 (tol 1e-8) y nadie lo veia
    # (M4-20) tambien la DO sin converger, carga/ECS sin espacio y avisos
    # del reinicio
    if grep -q '\[CG\] AVISO\|\[ALPHA\] AVISO\|\[DO\] AVISO\|\[CHARGE\] WARNING\|\[ECS\] AVISO\|\[SLAG\] AVISO\|\[RESTART\] AVISO\|\[CONFIG\] AVISO\|\[INPUT\] AVISO' "$dir/run.log"; then
        echo "FAIL: aviso del solver/carga en $name -n $np:"
        grep '\[CG\] AVISO\|\[ALPHA\] AVISO\|\[DO\] AVISO\|\[CHARGE\] WARNING\|\[ECS\] AVISO\|\[SLAG\] AVISO\|\[RESTART\] AVISO\|\[CONFIG\] AVISO\|\[INPUT\] AVISO' "$dir/run.log" | head -3
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
#   la tolerancia es la de la invarianza de descomposición (1e-10; medido
#   8.5e-13). (auditoria 4, B4-19) ademas invariantes, audit del tramo y
#   audit.csv BIT A BIT contra la continua (compare_audit). Vive en
#   tests/out/restart/ (fuera del golden).
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
    # (auditoria 5, B5-18) los MISMOS filtros que run_case (M4-20 a medias)
    if grep -q '\[CONFIG\] WARNING' "$dir/run.log"; then
        echo "FAIL: clave de config desconocida en el reinicio $base (¿typo?):"
        grep '\[CONFIG\] WARNING' "$dir/run.log" | head -3
        note_fail
        return 1
    fi
    if grep -q '\[CG\] AVISO\|\[ALPHA\] AVISO\|\[DO\] AVISO\|\[CHARGE\] WARNING\|\[ECS\] AVISO\|\[SLAG\] AVISO\|\[RESTART\] AVISO\|\[CONFIG\] AVISO\|\[INPUT\] AVISO' "$dir/run.log"; then
        echo "FAIL: aviso en el reinicio $base n$np:"
        grep '\[CG\] AVISO\|\[ALPHA\] AVISO\|\[DO\] AVISO\|\[CHARGE\] WARNING\|\[ECS\] AVISO\|\[SLAG\] AVISO\|\[RESTART\] AVISO\|\[CONFIG\] AVISO\|\[INPUT\] AVISO' "$dir/run.log" | head -3
        note_fail
        return 1
    fi
    # (auditoria 21, B21-P3) con el mismo n de ranks BIT A BIT (rtol 0;
    # medido 0.0 en todos) y tambien el estado entre pasos de /restart
    local rtol=0
    [ "$np" = "$npb" ] || rtol=1e-10   # (medido 3.9e-14; antes 1e-3)
    run_script "restart_${base}_n${npb}_to_n${np}" \
        $PY $INT/compare_decomposition.py "$dir" "$src" --rtol $rtol --with-restart
    # (auditoria 4, B4-19) el tramo reanudado pasa los mismos gates que una
    # corrida y su audit.csv coincide con el de la continua
    check_invariants_case "$dir" "$base"
    # xfail propios del TRAMO (audit_restart_<base>): la identidad acumulada
    # sobre una ventana corta no tiene el S_gas de los primeros pasos
    check_audit_if_present "$dir" "audit_restart_${base}" "$(audit_extra_args "$base")" "$base"
    run_script "restart_audit_${base}_n${npb}_to_n${np}" \
        $PY $INT/compare_audit.py "$dir" "$src" --from-step "$st" --rtol $rtol $( [ "$np" = "$npb" ] || echo --decomp )
}

# run_wallstop_case <base> <np>  (auditoria 16, M16-I2)
#   Corre <base> con wall_time_max diminuto: debe parar tras el primer paso
#   con [WALL] y escribir un snapshot reanudable; el reinicio desde el hasta
#   t_final debe ser BIT A BIT con la continua tests/out/<base>_n<np>
#   (campos y audit.csv). Es la receta por segmentos de produccion.
run_wallstop_case() {
    local base=$1 np=$2
    local src=$OUT/${base}_n${np}
    local d1=$OUT/restart/${base}_wallstop_n${np}
    local d2=$OUT/restart/${base}_wallresume_n${np}
    rm -rf "$d1" "$d2" && mkdir -p "$d1" "$d2"
    cp "$CFG/$base.dat" "$d1/config.dat"
    printf '\noutput_dir = %s\nwall_time_max = 1.0e-9\n' "$d1" >> "$d1/config.dat"
    echo "== parada por reloj $base -n $np"
    if ! mpirun -n "$np" "$BIN" "$d1/config.dat" > "$d1/run.log" 2>&1 \
       || ! grep -q '\[WALL\]' "$d1/run.log"; then
        echo "FAIL: wall_time_max no detuvo $base (ver $d1/run.log)"
        tail -5 "$d1/run.log"; note_fail; return 1
    fi
    local snap
    snap=$(printf '%s/eaf3d_%08d.h5' "$d1" 1)
    [ -f "$snap" ] || { echo "FAIL: la parada por reloj no escribio $snap"; note_fail; return 1; }
    cp "$CFG/$base.dat" "$d2/config.dat"
    printf '\noutput_dir = %s\nrestart_file = %s\n' "$d2" "$snap" >> "$d2/config.dat"
    if ! mpirun -n "$np" "$BIN" "$d2/config.dat" > "$d2/run.log" 2>&1; then
        echo "FAIL: la reanudacion tras la parada por reloj fallo (ver $d2/run.log)"
        tail -5 "$d2/run.log"; note_fail; return 1
    fi
    run_script "wallstop_${base}_n${np}" \
        $PY $INT/compare_decomposition.py "$d2" "$src" --rtol 1e-12
    run_script "wallstop_audit_${base}_n${np}" \
        $PY $INT/compare_audit.py "$d2" "$src" --from-step 1 --rtol 1e-12
}

# audit_xfail_prefix <base> -> prefijo de xfail del audit propio del caso
audit_xfail_prefix() {
    case $1 in
        cold_10step)   echo audit_cold ;;
        arc_noscrap)   echo audit_arcnoscrap ;;
        arc_slag)      echo audit_arcslag ;;
        noflow_energy) echo audit_noflow ;;
        bed_flood)     echo audit_bedflood ;;
        bath_fill_mix) echo audit_mix ;;
        melt_forced)   echo audit_melt ;;
        oneflow_test)  echo audit_oneflow ;;
        pocket_rise)   echo audit_pocket ;;
        *)             echo "" ;;
    esac
}
# audit_extra_args <base> -> argumentos extra de check_audit del caso
audit_extra_args() {
    case $1 in
        arc_noscrap) echo "--min-liq-arc 0.6" ;;
        outer_conv)  echo "--etol 1e-4" ;;   # lazo convergido (N-A6)
        # (auditoria 15, M15-4) techo absoluto del clip (el xfail se retiro al
        # ceder la escoria; queda como guarda: medido ~1e-11 kg)
        arc_slag)    echo "--clip-abs-max 3e-4" ;;
        arc_slag_legacy) echo "--clip-abs-max 3e-4" ;;
        *)           echo "" ;;
    esac
}
# check_audit_case <rundir> <base>
check_audit_case() {
    check_audit_if_present "$1" "$(audit_xfail_prefix "$2")" "$(audit_extra_args "$2")" "$2"
}
# check_invariants_case <rundir> <base>: melt_forced (regimen violento,
# gated en C3.4) lleva xfail propio por corrida
check_invariants_case() {
    local xf
    xf="$(xfail_ids invariants)"
    [ "$2" = "melt_forced" ] && xf="$xf,$(xfail_ids invariants_melt)"
    if ! $PY $INT/check_invariants.py "$1" --config "$CFG/$2.dat" --xfail "$xf"; then
        echo ">> FAIL invariantes en $1"
        note_fail
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

check_audit_if_present() {  # <rundir> [prefijo_xfail_extra] [args extra] [base]
    local extra="" more="${3:-}"
    [ -n "${2:-}" ] && extra=",$(xfail_ids "$2")"
    # config del caso (nombre del directorio sin _nN, o <base> explicito):
    # solve_energy = false => el balance de energia no aplica (auditoria 2,
    # N-C3)
    local base cfgarg=""
    base=${4:-}
    if [ -z "$base" ]; then base=$(basename "$1"); base=${base%_n*}; fi
    [ -f "$CFG/$base.dat" ] && cfgarg="--config $CFG/$base.dat"
    if [ -f "$1/audit.csv" ]; then
        if ! $PY $INT/check_audit.py "$1" $cfgarg $more --xfail "$(xfail_ids audit)$extra"; then
            echo ">> FAIL auditoría en $1"
            note_fail
        fi
    elif ! grep -Eq '^[[:space:]]*audit_freq[[:space:]]*=[[:space:]]*0' "$1/config.dat" 2>/dev/null; then
        # (auditoria 4, B4-22) sin audit.csv y sin audit_freq = 0 en el
        # config del caso es un fallo, no un caso 'sin audit'
        echo ">> FAIL falta audit.csv en $1 (audit_freq /= 0)"
        note_fail
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
        # Fusion progresiva bajo arco en el gate por commit (auditoria 4,
        # M4-7 segunda vuelta; ~11 s): es el unico banco del regimen de B1 y
        # tres commits pasaron test-quick con una regresion 27.8 -> 8.4 kg
        run_case arc_melt 4 && {
            check_invariants "$OUT/arc_melt_n4" arc_melt
            check_audit_if_present "$OUT/arc_melt_n4"
            run_script "arc_melt" \
                $PY $INT/check_arcmelt.py "$OUT/arc_melt_n4" --xfail "$(xfail_ids arc_melt)"
            if ! $PY $INT/metrics_snapshot.py "$OUT" --mode check \
                    --only arc_melt_n4; then
                echo ">> FAIL métricas golden (arc_melt)"
                note_fail
            fi
        }
        # Lecho inundado en reposo (auditoria 5, M5-8; ~3.5 s): el unico banco
        # que vigila la bomba de A4-1 (0.29 -> 0.069 m/s); una regresion de
        # las mascaras de flotacion pasaba el gate por commit
        run_case bed_bath_rest 4 && {
            check_invariants "$OUT/bed_bath_rest_n4" bed_bath_rest
            check_audit_if_present "$OUT/bed_bath_rest_n4"
            run_script "bed_bath_rest" \
                $PY $INT/check_bedbath.py "$OUT/bed_bath_rest_n4" --xfail "$(xfail_ids bed_bath_rest)"
            if ! $PY $INT/metrics_snapshot.py "$OUT" --mode check \
                    --only bed_bath_rest_n4; then
                echo ">> FAIL métricas golden (bed_bath_rest)"
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
    # (auditoria 18, A1) quimica con capa de escoria condensada gruesa
    run_case slag_chem_thick 4
    run_case slag_chem_thick 1
    # (auditoria 21, M21-P2) n12 = 1x2x6 corta z en 20|21 (kt|kt+1 de la capa,
    # interfaz kb 19 / kt 20) y theta: los planos de un dueno de la oxidacion
    # por columna (I1) a traves de ranks
    run_case slag_chem_thick 12
    # (Plan I, gates 6-8; auditoria 20, A20-1) ECS que desplaza una capa de
    # escoria (60 t, k0 llena) y cesta 2 que la atraviesa: n9 corta z en la
    # escoria, n12 corta r
    run_case ecs_slag 1
    run_case ecs_slag 9
    run_case ecs_slag 12
    run_case cold_bucket2_slag 1
    run_case cold_bucket2_slag 9
    # Bug 19 (Plan C, F0): bancos del bano de liquido puro — reposo (n1/n4)
    # y llenado por fusion (n4). Sus checks propios (bath:*) llevan xfail
    # con causa hasta F1/F2; los invariantes duros (nan/bounds) NO.
    run_case bath_test 1
    run_case bath_test 4
    run_case bath_test 12
    run_case bath_test_stretch 4
    run_case bath_test_cold 4
    # (auditoria 5, B5-4) rama de UNA fase (flujo sin dos fluidos): banco legado
    run_case oneflow_test 4
    run_case bath_fill 4
    run_case bath_mix 4
    run_case bath_fill_mix 4
    # (auditoria 12, M12-2) bath_fill con el control de paso adaptativo de produccion
    run_case bath_fill_adapt 4
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
    # (auditoria 12, M12-1arc) arco sobre escoria en su propia capa (malla fina)
    run_case arc_slag 4
    # invarianza MPI de la escoria CONDENSADA (Plan H, default: transporte con
    # el condensado y slag_condensed_sort; decomposition_arcslag n1 frente a
    # n4). Con slag_in_volume = false era la cesion + slag_buoyancy legada
    run_case arc_slag 1
    # (auditoria 19) descomposicion en THETA de la escoria condensada (n12 =
    # 1x2x6; r no se corta con nr = 12)
    run_case arc_slag 12
    # (auditoria 18, A18-9) el camino legado de la escoria sigue soportado
    run_case arc_slag_legacy 4
    run_case arc_slag_legacy 1
    # (Plan H, P4/P7) escoria CONDENSADA (slag_in_volume) en reposo: fase del
    # Poisson y del momento, hidrostatica con su peso, reordenamiento y masa
    run_case slag_rest 4
    # Cesta 2 durante la corrida (auditoria A5): carga aditiva y auditada
    run_case cold_bucket2 4
    # Drenaje del lecho con la fuerza balanceada (auditoria 2, N-C1)
    run_case bed_drain 4
    # (auditoria 3, M3-10) descomposicion de las rutas que no la tenian: el
    # drenaje del lecho (B_f por caras), el llenado del bano, el arco con bano
    # (kbath / P_elec / Lorentz) y la fusion forzada
    run_case bed_drain 1
    # (auditoria 21, M21-P1) n12 = 2x3x2 (la descomposicion de produccion)
    # corta r en un caso con lecho y liquido: J-B, E2 (vol_unlinked lee
    # ws_Fc_lk_r del halo) e histeresis en la cara r de bloque
    run_case bed_drain 12
    run_case bath_fill 1
    run_case arc_noscrap 1
    run_case melt_forced 1
    # (auditoria 4, A4-7) bano bajo lecho en reposo y fusion progresiva bajo
    # arco: los dos regimenes de B1 que la matriz no ejercia
    run_case bed_bath_rest 4
    run_case bed_bath_rest 1
    # (auditoria 6-7, M4-12) bolsa de gas bajo una capa saturada, desde un
    # estado construido sobre el paso 0 de bed_bath_rest_n4 (presion
    # hidrostatica y rho_gas coherentes; defaults)
    if [ -f "$OUT/bed_bath_rest_n4/eaf3d_00000000.h5" ]; then
        if $PY $INT/make_pocket_init.py "$OUT/bed_bath_rest_n4/eaf3d_00000000.h5" "$OUT/pocket_init.h5" > /dev/null; then
            run_case_restart_from pocket_rise 4 "$OUT/pocket_init.h5"
        else
            echo "FAIL: make_pocket_init.py no pudo construir el estado de pocket_rise"; note_fail
        fi
    else
        echo "FAIL: falta el snapshot inicial de bed_bath_rest_n4 para pocket_rise"; note_fail
    fi
    run_case arc_melt 4
    run_case arc_melt 1
    # (oct-2026) escoria sobre un lecho que funde: modelo termico de la
    # escoria y la escoria que cede al acero (auditorias dirigidas 17-18)
    run_case arc_melt_slag 4
    # (oct-2026) con talon de bano bajo el lecho: soporte de la escoria
    run_case arc_melt_slag_heel 4
    # (auditoria 19, MEDIO-2 MPI) escoria condensada en el lecho: contacto
    # escoria-chatarra, fundido pendiente del sort, cara superior de la escoria
    run_case arc_melt_slag_heel 1


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
    # Invariantes en TODA la matriz (auditoria 3, A3-7: chem_test y
    # slag_chem_test violaban sum_alpha (7.7e-6, 1.04e-4) sin que nadie los
    # mirara: ni chem, ni slag_chem, ni ecs, ni outer_conv, ni melt_forced)
    run_script "chem" \
        $PY $INT/check_chem.py "$OUT/chem_test_n4" --config "$CFG/chem_test.dat"
    run_script "ecs" \
        $PY $INT/check_ecs.py "$OUT/ecs_test_n8" --config "$CFG/ecs_test.dat"
    run_script "decomposition_ecs" \
        $PY $INT/compare_decomposition.py "$OUT/ecs_test_n1" "$OUT/ecs_test_n8" --rtol 1e-12
    run_script "slag_chem" \
        $PY $INT/check_slag_chem.py "$OUT/slag_chem_test_n8" --config "$CFG/slag_chem_test.dat"
    # (auditoria 5, M5-5) balance elemental de O y C CON escoria (FeO formado
    # y reducido, gas creado sin especies y destruido con ellas): solo sin
    # flujo, con la EOS reescribiendo masa (N-M4) no es una identidad
    run_script "chem_slag_elements" \
        $PY $INT/check_chem.py "$OUT/slag_chem_test_n8" --config "$CFG/slag_chem_test.dat" --slag
    run_script "slag_chem_flow" \
        $PY $INT/check_slag_chem.py "$OUT/slag_chem_flow_n4" --config "$CFG/slag_chem_flow.dat" \
        --mtol 1e-10 --min-yield 4.1
    # (Plan I, general 2 M5) slag_mass medido 6.4e-12 (flow) y 1.6e-10
    # (thick) antes de I1: --mtol con margen. (auditoria 20, M20-C1)
    # --min-yield = 0.6 x lo medido con I1 (golden v128: flow 6.832, thick
    # 2.579 kg; sin I1 0.989 y 0.626): sin la oxidacion por columna falla
    run_script "slag_chem_thick" \
        $PY $INT/check_slag_chem.py "$OUT/slag_chem_thick_n4" --config "$CFG/slag_chem_thick.dat" --min-return 0.5 \
        --min-yield 1.5 --mtol 1e-9
    # (Plan I, gates 6-8) masa/energia del ECS con escoria exactas (1e-16),
    # nada pendiente, base = k0 con escoria; orden acero|escoria y clip.
    # Descomposicion ~10x lo medido el 21-oct (velocidades: ecs n9 1.4e-6,
    # n12 6.0e-6, cesta 1.9e-6; alpha_slag 1.3e-9; masas exactas)
    run_script "ecs_slag" \
        $PY $INT/check_ecs.py "$OUT/ecs_slag_n9" --config "$CFG/ecs_slag.dat" --slag
    run_script "ecs_slag_bed" \
        $PY $INT/check_slag_bed.py "$OUT/ecs_slag_n9"
    run_script "bucket2_slag_bed" \
        $PY $INT/check_slag_bed.py "$OUT/cold_bucket2_slag_n9"
    # (auditoria 21, B21-C2) la cesta ATRAVIESA la escoria (I2): 288 de 576
    # celdas de escoria reciben chatarra; con thru = .false. 0 (mutacion)
    run_script "bucket2_slag_through" \
        $PY $INT/check_bucket2.py "$OUT/cold_bucket2_slag_n9" --pre 5 --post 15
    run_script "decomposition_ecs_slag" \
        $PY $INT/compare_decomposition.py "$OUT/ecs_slag_n1" "$OUT/ecs_slag_n9" --rtol 2e-5
    run_script "decomposition_ecs_slag_r" \
        $PY $INT/compare_decomposition.py "$OUT/ecs_slag_n1" "$OUT/ecs_slag_n12" --rtol 6e-5
    run_script "decomposition_bucket2_slag" \
        $PY $INT/compare_decomposition.py "$OUT/cold_bucket2_slag_n1" "$OUT/cold_bucket2_slag_n9" --rtol 2e-5
    # escoria por columna global (auditoria A14): invariante a la descomposicion
    # ECS con r DESCOMPUESTO (12 ranks -> 2x3x2): antes de la auditoria M38
    # la carga no se depositaba (indice radial local tomado como global)
    run_case ecs_test 12 && run_script "decomposition_ecs_r" \
        $PY $INT/compare_decomposition.py "$OUT/ecs_test_n12" "$OUT/ecs_test_n1" --rtol 1e-12
    run_script "decomposition_slag" \
        $PY $INT/compare_decomposition.py "$OUT/slag_chem_test_n1" "$OUT/slag_chem_test_n8" --rtol 1e-7
    run_script "bath_test_cold" \
        $PY $INT/check_bath.py "$OUT/bath_test_cold_n4" --config "$CFG/bath_test_cold.dat" --fill \
        --xfail "$(xfail_ids bath_test_cold)"
    run_script "oneflow_test" \
        $PY $INT/check_bath.py "$OUT/oneflow_test_n4" --config "$CFG/oneflow_test.dat" \
        --xfail "$(xfail_ids oneflow_test)"
    run_script "bath_test_stretch" \
        $PY $INT/check_bath.py "$OUT/bath_test_stretch_n4" --config "$CFG/bath_test_stretch.dat" \
        --xfail "$(xfail_ids bath)"
    for d in "$OUT"/bath_test_n*; do
        run_script "bath_test" \
            $PY $INT/check_bath.py "$d" --config "$CFG/bath_test.dat" \
            --xfail "$(xfail_ids bath)"
    done
    run_script "bath_fill" \
        $PY $INT/check_bath.py "$OUT/bath_fill_n4" --config "$CFG/bath_fill.dat" --fill \
        --xfail "$(xfail_ids bath_fill)"
    run_script "bath_fill_adapt" \
        $PY $INT/check_bath.py "$OUT/bath_fill_adapt_n4" --config "$CFG/bath_fill_adapt.dat" --fill \
        --xfail "$(xfail_ids bath_fill_adapt)"
    # Modelo de MEZCLA (Plan G): baño en reposo y llenado con fusion y arco
    run_script "bath_mix" \
        $PY $INT/check_bath.py "$OUT/bath_mix_n4" --config "$CFG/bath_mix.dat" \
        --xfail "$(xfail_ids bath_mix)"
    run_script "bath_fill_mix" \
        $PY $INT/check_bath.py "$OUT/bath_fill_mix_n4" --config "$CFG/bath_fill_mix.dat" --fill \
        --xfail "$(xfail_ids bath_fill_mix)"
    run_script "bath_freeze" \
        $PY $INT/check_bath.py "$OUT/bath_freeze_n4" --config "$CFG/bath_freeze.dat" --fill \
        --xfail "$(xfail_ids bath_freeze)"
    run_script "bed_flood" \
        $PY $INT/check_bath.py "$OUT/bed_flood_n4" --config "$CFG/bed_flood.dat" --fill \
        --xfail "$(xfail_ids bed_flood)"
    run_script "bed_drain" \
        $PY $INT/check_drain.py "$OUT/bed_drain_n4" --xfail "$(xfail_ids bed_drain)"
    run_script "bed_bath_rest" \
        $PY $INT/check_bedbath.py "$OUT/bed_bath_rest_n4" --xfail "$(xfail_ids bed_bath_rest)"
    run_script "pocket_rise" \
        $PY $INT/check_pocket.py "$OUT/pocket_rise_n4" --dt 0.005 --xfail "$(xfail_ids pocket_rise)"
    run_script "arc_melt" \
        $PY $INT/check_arcmelt.py "$OUT/arc_melt_n4" --xfail "$(xfail_ids arc_melt)"
    run_script "arc_slag_bed" \
        $PY $INT/check_slag_bed.py "$OUT/arc_slag_n4" --volfix-max 0.06 --xfail "$(xfail_ids arc_slag)"
    run_script "arc_slag_legacy" \
        $PY $INT/check_slag_bed.py "$OUT/arc_slag_legacy_n4" --volfix-max 0.06 --xfail "$(xfail_ids arc_slag_legacy)"
    run_script "slag_rest" \
        $PY $INT/check_slag_bed.py "$OUT/slag_rest_n4" --volfix-max 1e-3 \
        --umax-liq 1e-8 --umax-gas 1e-4 --xfail "$(xfail_ids slag_rest)"
    run_script "arc_melt_slag_heel" \
        $PY $INT/check_slag_bed.py "$OUT/arc_melt_slag_heel_n4" --max-jumps 0 \
        --asl-min 1e-3 --al-min 0.05 --volfix-max 0.15 --xfail "$(xfail_ids arc_melt_slag_heel)"
    run_script "arc_melt_slag" \
        $PY $INT/check_slag_bed.py "$OUT/arc_melt_slag_n4" \
        --asl-min 1e-3 --al-min 0.05 --volfix-max 0.6 --xfail "$(xfail_ids arc_melt_slag)"
    # Auditoria de energia/masa/arco en TODA corrida de la matriz (auditoria
    # 2, N-C3: antes 13 de 26 no se auditaban; bath_freeze fallaba con err 1)
    # (auditoria 4, B4-21) invariantes en TODA corrida de la matriz (antes
    # faltaban los n1/n9 nuevos: bath_freeze n1/n9, bed_drain n1, bath_fill
    # n1, arc_noscrap n1, melt_forced n1)
    for d in "$OUT"/*_n*; do
        b=$(basename "$d"); b=${b%_n*}
        check_invariants_case "$d" "$b"
        check_audit_case "$d" "$b"
    done
    run_script "decomposition_bath" \
        $PY $INT/compare_decomposition.py "$OUT/bath_test_n1" "$OUT/bath_test_n4" --rtol 1e-8
    run_script "decomposition_bath_r" \
        $PY $INT/compare_decomposition.py "$OUT/bath_test_n1" "$OUT/bath_test_n12" --rtol 1e-8
    run_script "decomposition_freeze_z" \
        $PY $INT/compare_decomposition.py "$OUT/bath_freeze_n1" "$OUT/bath_freeze_n9" --rtol 1e-5
    run_script "decomposition_slag_z" \
        $PY $INT/compare_decomposition.py "$OUT/slag_chem_test_n1" "$OUT/slag_chem_test_n9" --rtol 1e-7
    run_script "decomposition_freeze" \
        $PY $INT/compare_decomposition.py "$OUT/bath_freeze_n1" "$OUT/bath_freeze_n4" --rtol 1e-5
    # (M3-10) tolerancias ~100x lo medido entonces. Re-medido en la
    # auditoria 20 (M20-7, golden v128, HEAD d9112ef): drenaje 7.8e-5 (6.4x;
    # el 7e-6 de M3-10 ya no vale desde la rampa/J-B), llenado 6.6e-9,
    # arco con bano 6.1e-14, fusion forzada 6.2e-11
    run_script "decomposition_drain" \
        $PY $INT/compare_decomposition.py "$OUT/bed_drain_n1" "$OUT/bed_drain_n4" --rtol 5e-4
    run_script "decomposition_drain_r" \
        $PY $INT/compare_decomposition.py "$OUT/bed_drain_n1" "$OUT/bed_drain_n12" --rtol 1e-3
    # (auditoria 21, M21-T3) fill medido 6.6e-9: rtol 1e-7 (antes 1e-4, 15 000x)
    run_script "decomposition_fill" \
        $PY $INT/compare_decomposition.py "$OUT/bath_fill_n1" "$OUT/bath_fill_n4" --rtol 1e-7
    run_script "decomposition_arc_bath" \
        $PY $INT/compare_decomposition.py "$OUT/arc_noscrap_n1" "$OUT/arc_noscrap_n4" --rtol 1e-11
    run_script "decomposition_melt" \
        $PY $INT/compare_decomposition.py "$OUT/melt_forced_n1" "$OUT/melt_forced_n8" --rtol 1e-8
    # (A4-7) medido 2.4e-8 (n1 frente a n4, golden v92; 2e-9 en A4-7) y 1.4e-13 (B5-19: margen 4x, no 50x)
    run_script "decomposition_bedbath" \
        $PY $INT/compare_decomposition.py "$OUT/bed_bath_rest_n1" "$OUT/bed_bath_rest_n4" --rtol 1e-7
    # (oct-2026) medido 1.3e-10 (T_gas); Y_* solo donde hay gas. M20-7:
    # arc_slag 1.4e-13 (n4) / 1.5e-13 (n12); arc_slag_legacy 1.7e-10 (5.9x)
    run_script "decomposition_arcslag" \
        $PY $INT/compare_decomposition.py "$OUT/arc_slag_n1" "$OUT/arc_slag_n4" --rtol 1e-9
    run_script "decomposition_arcslag_legacy" \
        $PY $INT/compare_decomposition.py "$OUT/arc_slag_legacy_n1" "$OUT/arc_slag_legacy_n4" --rtol 1e-9
    run_script "decomposition_arcslag_rth" \
        $PY $INT/compare_decomposition.py "$OUT/arc_slag_n1" "$OUT/arc_slag_n12" --rtol 1e-9
    run_script "decomposition_slagbed" \
        $PY $INT/compare_decomposition.py "$OUT/arc_melt_slag_heel_n1" "$OUT/arc_melt_slag_heel_n4" --rtol 1e-7
    # M20-7: medido 4.8e-8 (T_slag, margen 2.1x): el mas justo de la matriz;
    # un cambio que lo cruce debe diagnosticarse (orden de sumas en la
    # quimica de escoria gruesa), no resolverse subiendo la tolerancia
    run_script "decomposition_slagthick" \
        $PY $INT/compare_decomposition.py "$OUT/slag_chem_thick_n1" "$OUT/slag_chem_thick_n4" --rtol 1e-7
    # (M21-P2) medido 2.2e-8 (21-oct)
    run_script "decomposition_slagthick_iface" \
        $PY $INT/compare_decomposition.py "$OUT/slag_chem_thick_n1" "$OUT/slag_chem_thick_n12" --rtol 1e-7
    run_script "decomposition_arcmelt" \
        $PY $INT/compare_decomposition.py "$OUT/arc_melt_n1" "$OUT/arc_melt_n4" --rtol 1e-11
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
    # (auditoria 20, B20-6) reinicio con PELICULA en la banda de histeresis
    # [ALPHA_FLOW_CUTOFF, 2 ALPHA_FLOW_CUTOFF) sobre el bano (20 celdas con
    # liq_cont_prev en el paso 750): sin restaurar la mascara previa del
    # snapshot el reinicio difiere 1.0 en u_z del gas (mutacion medida)
    run_restart_case bed_flood 4 4 750
    run_restart_case cold_10step 12 12 5
    # (M3-10) reinicios de ECS, escoria con flujo+quimica+especies, y n8 -> n12
    run_restart_case ecs_test 8 8 10
    run_restart_case slag_chem_flow 4 4 10
    # (Plan H, P8) reinicio BIT A BIT con la escoria condensada (estado de
    # inicio de paso ws_sp_* desde el snapshot, sin la colocacion inicial)
    run_restart_case slag_rest 4 4 50
    # (auditoria 19) reinicio con escoria condensada en el lecho que funde
    run_restart_case arc_melt_slag_heel 4 4 100
    run_restart_case cold_10step 8 12 5
    # (A4-7) reinicio a MITAD de la fusion progresiva (paso 100 de 200)
    run_restart_case arc_melt 4 4 100
    # (Plan I, gates 6/8) reinicios con escoria desplazada por el ECS y
    # cruzando la carga de la cesta 2 (paso 5) y despues (15): bit a bit
    run_restart_case ecs_slag 9 9 30
    run_restart_case cold_bucket2_slag 9 9 5
    run_restart_case cold_bucket2_slag 9 9 15
    # (auditoria 16, M16-I2) parada por tiempo de reloj + reanudacion
    run_wallstop_case cold_10step 8

    if [ "$MODE" = "rebaseline" ]; then
        # (auditoria 4, B4-23) el golden solo se regenera con la matriz LIMPIA:
        # un rebaseline con fallos convertia el fallo en referencia
        if [ "$FAILURES" -eq 0 ]; then
            $PY $INT/metrics_snapshot.py "$OUT" --mode rebaseline \
                ${STAGE:+--stage "$STAGE"} || note_fail
        else
            echo ">> golden NO regenerado: $FAILURES fallo(s) en la matriz"
        fi
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
