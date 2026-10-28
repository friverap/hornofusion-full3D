# WS-K9 — Venteo de gas sin energía y binario en run.log

Pieza de código pequeña que cierra dos objeciones no bloqueantes del panel
del ciclo 2 de WS-K8 (`research/ws/WS-K8/reviews/r1-*.md`): la del auditor
(B1) sobre `m_gas_out` y la de evidencia (O4) sobre qué binario corrió cada
banco. Sin cambio numérico: el `test-full` con el arreglo reproduce las
métricas del golden v131 (anterior al arreglo) con error relativo 0 en los
60 bancos comunes. Además, los `audit.csv` de esos 60 bancos escritos por el
rebaseline son idénticos en todas las columnas a una copia previa
{C-199}{C-200}. No hay predicción pre-registrada porque no hay cambio
numérico que decidir.

## Proceso

1. **El defecto** {C-198}. `audit_accumulate` acumulaba la masa neta que
   entra a las celdas de salida (`AUD_GAS_OUT`, columna `m_gas_out`) solo
   dentro de `if (gas_energy_on ...)`, con gas_energy_on = solve_energy
   .and. solve_flow .and. solve_multiphase (`src/mod_audit.f90`, bloque
   del venteo del techo). Pero `audit_gas_cells` y el check
   `mass_gas_flux_closure` (flux_multi + flux_free + m_gas_out = 0 por
   paso) solo exigen flujo de dos fluidos. Con solve_energy = false la
   columna quedaba en 0 y el cierre daba una falsa alarma.
2. **Reproducción con el binario previo** {C-198}: `cold_10step` con
   `solve_energy`, `solve_melting`, `solve_radiation` y `solve_arc` en
   false, 4 ranks, `campaigns/bin/eaf3d_k8b_opt`: `m_gas_out` = 0 y FAIL
   `mass_gas_flux_closure` con max|resto| 3.41e-6 kg; `mass_gas` pasaba
   comparando dm_gas 7.08e-6 kg con un venteo de 0. El `run.log` de esa
   corrida no tiene la línea `Ejecutable:`, así que el binario es anterior
   al arreglo. Procedencia del ejecutable {C-201}: su sha256 actual
   (`bbe3e11c…81ad3`) es el que registró WS-K8 para el `bin/eaf3d_mpi`
   compilado a las 14:27 (`research/ws/WS-K8/logs/opt_identidad.txt`). El
   diff de `src/` de ese build frente a HEAD (`4aa8363`) tiene sha256
   `78797d1c…2ef`, el mismo que `git diff 79dc27b~1 79dc27b -- src`, y
   `src/` no cambia entre `4aa8363` y `79dc27b~1`. Por tanto, su `src/` es
   el de `79dc27b`. El mtime del archivo (14:44:15) es el del build k8c, no
   el del k8b (14:28). El contenido, sin embargo, es el del hash registrado
   del build de las 14:27.
   La config es `tests/integration/configs/cold_flow_noenergy.dat`, sin las
   tres líneas de comentario de cabecera y con
   `output_dir = <scratchpad>/coldnoE_old` (`<scratchpad>` se define en «Resultado»; efímero; el `diff` se verificó y
   solo difieren esas líneas). Su `run.log` y la salida del check están
   copiados en `research/ws/WS-K9/logs/`.
   > [fuente: research/ws/WS-K9/logs/coldnoE_binario_previo_run.txt, research/ws/WS-K9/logs/coldnoE_binario_previo_check.txt, research/ws/WS-K8/logs/opt_identidad.txt | comando de la reproducción: mpirun -n 4 campaigns/bin/eaf3d_k8b_opt <scratchpad>/coldnoE_old/config.dat; python3 tests/integration/check_audit.py <scratchpad>/coldnoE_old --config <scratchpad>/coldnoE_old/config.dat. Procedencia: shasum -a 256 campaigns/bin/eaf3d_k8b_opt; git diff 79dc27b~1 79dc27b -- src | shasum -a 256; git diff 4aa8363 79dc27b~1 -- src | wc -l (0)]
3. **Arreglo** (`src/mod_audit.f90`): la nueva bandera gas_mass_on =
   solve_flow .and. solve_multiphase gobierna el bloque del venteo; dentro,
   la entalpía (`srcacc(17)`, que usa T y cp del gas) sigue exigiendo
   gas_energy_on y la masa (`AUD_GAS_OUT`) no. Con energía activa el código
   hace exactamente lo mismo que antes.
4. **Binario en run.log** (`src/main_3d.f90`): el rank 0 imprime al
   arrancar `Ejecutable:` (`get_command_argument(0)`) y `Compilador:`
   (`compiler_version()`).
5. **Test**: banco nuevo `cold_flow_noenergy` en `make test-full` (4 ranks,
   `tests/integration/configs/cold_flow_noenergy.dat`); pasa invariantes
   y audit por el bucle general de `tests/run_tests.sh`. Golden v132 =
   v131 más ese banco. Glosario de `m_gas_out`
   (`scripts/make_audit_glossary.py` → `docs/AUDIT_COLUMNS.md`),
   `tests/README.md` y la regla `.claude/rules/transporte-energia.md`
   actualizados.

## Resultado

- **Con el arreglo** {C-198}: en `cold_flow_noenergy_n4`, `m_gas_out` =
  −7.1206e-6 kg, `mass_gas_flux_closure` PASS con max|resto| 1.69e-21 kg,
  y `mass_gas` compara dm_gas 7.0818e-6 con un venteo de 7.1206e-6 kg.
  `run.log` muestra la línea `Ejecutable:` con la ruta del binario y
  `Compilador: GCC version 16.1.0`. Las mismas cifras de `mass_gas` y
  `mass_gas_flux_closure` aparecen en la salida del `test-full`
  (`test_full.txt`, bloque `[audit] tests/out/cold_flow_noenergy_n4`). La
  carpeta `tests/out` actual es la que escribió el rebaseline.
  > [fuente: research/ws/WS-K9/logs/test_full.txt (líneas 2138 y siguientes) | python3 tests/integration/check_audit.py tests/out/cold_flow_noenergy_n4 --config tests/integration/configs/cold_flow_noenergy.dat | grep -E 'mass_gas |mass_gas_flux_closure'; grep -E 'Ejecutable|Compilador' tests/out/cold_flow_noenergy_n4/run.log]
- **Sin cambio numérico** {C-199}{C-200}. La evidencia verificable es la
  comparación con el golden versionado. El `test-full` con el arreglo
  (`test_full.txt`, 19:00) compara contra `tests/golden/metrics_v131.json`
  (commit `529e96e`, 2026-10-22, anterior al arreglo) a rtol 1e-12: en
  los 60 bancos comunes da PASS con «peor métrica err rel 0.000e+00», y el
  único FAIL es el banco nuevo, que no está en el golden. El rebaseline da
  v132 = v131 más ese banco, sin ninguna métrica común distinta.
  > [fuente: research/ws/WS-K9/logs/test_full.txt (líneas 5087-5149), research/ws/WS-K9/logs/test_rebaseline.txt, tests/golden/metrics_v131.json, tests/golden/metrics_v132.json | sed -n '5087,5149p' research/ws/WS-K9/logs/test_full.txt | grep PASS | grep -c 'err rel 0.000e+00' (60)]
- **Comparación celda a celda (complementaria)** {C-200}. NO se hizo
  contra la salida del `test-full`, que el rebaseline sobrescribió. Se hizo
  contra los `tests/out/*/audit.csv` que escribió el rebaseline (mtimes
  19:01:04-19:12:15; binario `./bin/eaf3d_mpi` con el arreglo, línea
  `Ejecutable:` en los 61 `run.log`). La ejecución única de
  `cmp_audit.py`, a las 19:14:53, da 60 idénticos y 0 distintos. La base es
  `<scratchpad>/k9_base`: 60 carpetas con solo `audit.csv`, copiadas a las
  18:45:28-29, antes del primer `bin/eaf3d_mpi` con el arreglo (18:46:16).
  Está en el scratchpad efímero de la sesión: `<scratchpad>` =
  `/private/tmp/claude-502/-Users-frariv-Horno/68c200c2-efa4-46c5-a9ff-3c767a24d56a/scratchpad`.
  Su manifiesto (sha256 de la lista
  ordenada de los sha256 de sus 60 `audit.csv`) es `d0367a43…81cad`, igual
  al de los 60 `audit.csv` homónimos de `tests/out`.
  > [fuente: research/ws/WS-K9/logs/cmp_audit.txt | python3 research/ws/WS-K9/scripts/cmp_audit.py <scratchpad>/k9_base tests/out; (cd <scratchpad>/k9_base && shasum -a 256 */audit.csv | sort -k2) | shasum -a 256]
- **Tests** {C-199}: `make test-unit` OK. `make test-full`: un único FAIL,
  «cold_flow_noenergy_n4: no está en el golden»; el banco nuevo pasa
  invariantes y audit. `STAGE=v132 make test-rebaseline` OK; v132 = v131
  más `cold_flow_noenergy_n4`, ninguna métrica común distinta.
  > [fuente: research/ws/WS-K9/logs/test_unit.txt, research/ws/WS-K9/logs/test_full.txt, research/ws/WS-K9/logs/test_rebaseline.txt | python3 -c "import json; a=json.load(open('tests/golden/metrics_v131.json'))['runs']; b=json.load(open('tests/golden/metrics_v132.json'))['runs']; print(set(b)-set(a), [k for k in a if a[k]!=b[k]])"]

## Incertidumbre

- La única configuración sin energía y con dos fluidos probada es la de
  `cold_flow_noenergy` (sin arco, sin fusión, sin radiación): 10 pasos de
  0.02 s casi en reposo (columna `u_gas_max` de
  `tests/out/cold_flow_noenergy_n4/audit.csv` ≤ 7.5e-5 m/s; check_audit lo
  redondea a 0.0). Ejerce el camino, no un
  régimen con venteo fuerte.
- `Ejecutable:` es la ruta tal como se pasó a `mpirun`; no identifica el
  contenido del binario (un mismo nombre puede apuntar a otro archivo).
  Para eso haría falta un hash del ejecutable, que no se calcula.
- No se puede verificar de qué corrida procede la base de la comparación
  celda a celda (`<scratchpad>/k9_base`). Solo guarda `audit.csv`, sin
  `run.log`, y sus mtimes son los de la copia (18:45). Que venga del
  `test-full` de WS-K8 (14:3x) y del `test-quick` de las 16:22 es lo que
  declara el operador; no es un dato. Lo único comprobable es que la copia
  es anterior al primer binario de la suite con el arreglo. Como el arreglo
  no cambia nada con energía activa, esa comparación tampoco distingue si
  la base salió del código viejo o del nuevo. Por eso el «sin cambio
  numérico» descansa en el golden v131 versionado, que solo cubre las
  métricas del golden y no todas las columnas de `audit.csv`.
- El `run.log` de la reproducción con el binario previo no registra el
  ejecutable (el binario es anterior al arreglo que añade esa línea). El
  comando `mpirun` no se guardó en un archivo: el que figura arriba es el
  declarado por el operador. Del log solo se comprueba que el binario es
  anterior al arreglo, que corrió con 4 procesos y que usó esa config.
- **Tras el cierre (`2b65e11`), objeciones no bloqueantes del panel:**
  - El PASS de `mass_gas_flux_closure` prueba que `m_gas_out` cierra el
    reparto de flujos, no que sea el venteo correcto en signo y magnitud con
    una medida independiente.
  - `mass_gas` pasa aunque el venteo sea 0 (tolerancia relativa 0.5 sobre
    max(|dm|, 1e-2·m_gas)): lo mostró la reproducción con el binario
    previo. La única guardia de este defecto es `mass_gas_flux_closure` en
    `cold_flow_noenergy_n4`, que solo corre en `test-full`.
  - Los comentarios heredados de `cold_10step` en
    `tests/integration/configs/cold_flow_noenergy.dat` («física de flujo
    completa», dt y `max_outer` justificados con la energía) no aplican a
    un banco sin energía; `get_command_argument(0, exe)` se llama sin
    `length`/`status` (una ruta de más de 1024 caracteres se truncaría sin
    aviso). Ambos tocan `tests/` o `src/` y quedan como pendiente.
