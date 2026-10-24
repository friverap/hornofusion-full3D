# Revision r1 — auditor-eaf3d — WS-K5 (columnas de masa del gas por celda)

**Veredicto: aprueba.** No hay hallazgos ALTO ni MEDIO. Quedan cuatro BAJO no bloqueantes.

Alcance: el codigo staged de `src/mod_audit.f90`, `src/main_3d.f90`, `tests/integration/check_audit.py` y `tests/unit/test_gas_cell_class.f90`, mas la documentacion asociada. Hice solo lectura y reproduje con `python3 check_audit.py` sobre salidas que ya existian. No compile ni corri nada.

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO
1. **Falso residuo de cierre con la energia apagada.**
   - Donde: `src/mod_audit.f90` (~L705, `if (gas_energy_on .and. k == m%nz ...)`).
   - Defecto: `m_gas_out` solo se acumula si `solve_energy` esta activo. `audit_gas_cells` acumula `m_gas_err_out` sin esa condicion.
   - Escenario: flujo y multifase activos con `solve_energy=F`. El INFO de cierre imprime un residuo del orden del venteo, que no es real.
   - Alcance: ningun banco actual lo dispara (los tres configs con energia apagada tienen `solve_flow=F`). Solo afecta el INFO.
   - Arreglo: imprimir el cierre solo con la energia del gas activa, o desacoplar `AUD_GAS_OUT` de `gas_energy_on`.
2. **Evidencia de test-full anterior a la ultima edicion.**
   - `logs/test_full.txt` es de las 17:36:59. `mod_audit.f90` y `check_audit.py` cambiaron a las 17:44:41.
   - El reinicio bit a bit y el golden de test-full son del build previo. Con el build actual solo hay test-quick.
   - La cabecera de columnas es identica en `campaigns/bin/eaf3d_k5col_opt` y en `bin/eaf3d_mpi`. Que el cambio sea solo de comentarios es plausible, pero no lo verifique.
3. **Signo en un comentario.** El comentario de `AUD_MG_ERR_OUT` dice «su e es el venteo». En realidad es aproximadamente −venteo: en k5_mo20, out vale +9.244e-4 y el venteo −9.461e-4.
4. **El cierre no esta protegido por ningun test.** La identidad de cierre es solo INFO. Conviene un `chk.report` con una tolerancia de redondeo en los bancos sin pasos omitidos, para que una regresion de consistencia haga fallar un test.

## Verificado como correcto
- **Patron MPI.** `acc` se reduce con `mpi_allreduce_sum` en todas las columnas (`mod_audit.f90` ~L544). `m_gas_cells_skip` solo lo suma el rank 0, asi que cuenta una vez por paso. La condicion de omision (`mg_ini_ok`, `ws_Fg_valid`, cfg) es la misma en todos los ranks, porque `ws_Fg_valid` lo fija la parte colectiva del Poisson.
- **Halos y Bug 22.**
  - `mg_ini` (con `mold`) y `mg_cls0` solo se leen y escriben en celdas propias, y heredan las cotas `(-1:)` de `gas%alpha`.
  - Las caras `i-1`, `j-1` y `k-1` leen `ws_Fg_*` y `ws_Fg_lk_*`. Esos arrays se inicializan a 0 al reservarse (`mod_workspace.f90:496-499`) y en cada Poisson (`mod_pressure_3d.f90:209-210`), y su halo se intercambia tras calcularlos.
- **Snapshot.** `mg_ini` y `mg_cls0` se recapturan en el modo 0 de cada paso, asi que no son estado entre pasos. `ws_Fg_valid` se apaga al empezar cada paso (`main_3d.f90:577`). El reinicio no depende de ellos.
- **Orden en `main_3d`.**
  - El modo 0 corre al empezar el paso, antes de la segunda cesta, el ECS y cualquier volfix, de modo que el volfix queda dentro de e, como se documenta.
  - El modo 1 corre despues del `update_properties` final y del intercambio de halos, antes de `audit_write_step`. Usa la misma rho con la que se escribe `m_gas`.
  - El paso que cierra por tiempo de reloj o por NaN no pierde la acumulacion.
- **Escoria (K5-M1).** `slag_vol` lee `alpha_sl` con la guarda `allocated`. La clase no depende de si `liq%alpha` esta o no en la vista condensada. La clase libre exige que la celda lo sea al inicio y al final del paso (`c==1 .and. mg_cls0==2 -> 2`). La celda outlet es invariante.
- **Outlet.** Usa la misma definicion que `m_gas_out` (`k==nz`, `at_zmax`, `is_electrode`) y el mismo producto `ws_Fg * lk`.
- **Signos en `check_audit.py`.** `clos = resid - ef - em - eo - m_out + m_fix` es coherente con «EOS − celdas = venteo − volfix». El gate de `mass_gas` no cambia.
- **Cifras del reporte, reproducidas con `check_audit.py`:**

  | Banco | Cierre (kg) | Libre | Multifase | Outlet | Nota |
  |---|---|---|---|---|---|
  | k5_mo20 | −6.14e-14 | +2.179e-5 | −8.686e-4 | +9.244e-4 | volfix −1.310e-5 |
  | k5_base | −7.09e-14 | −9.896e-4 | −1.585e-3 | +1.284e-3 | |
  | cold_bucket2_slag_n1 | — | — | −1.739 | — | volfix −1.722; sale el AVISO |
  | arc_slag_n4 | — | — | −1.067 | — | EOS −1.097 |
  | bath_mix_n4 | — | — | — | — | «sin balance en 100 de 100» |

- **Logs.**
  - `test_full.txt`: 64 renglones con balance; el peor |cierre| es 3.985e-12 kg; 18 de 64 tienen |volfix| > 10 % de |multifase|.
  - Sin FAIL; solo XFAIL preexistentes; «TESTS (full): OK».
  - `test_unit`: PASS de `test_gas_cell_class`. `test_quick`, con el build actual, muestra el AVISO.
- **Prueba unitaria.** Cubre outlet, libre, los bordes en `ALPHA_FLOW_CUTOFF` y tres casos con escoria.
- **Documentacion.** El reporte, `AUDIT_COLUMNS.md` y la regla de transporte-energia ya dicen que e incluye el volfix y marcan C-110 como hipotesis. Ninguna conclusion se apoya en `m_gas_err_multi` como medida del piso.

## Orden sugerido de correccion
1. A-K5-2: confirmar que la edicion de las 17:44 es solo de comentarios, o volver a correr test-full.
2. A-K5-1: proteger el INFO de cierre cuando la energia del gas esta apagada.
3. A-K5-4: convertir el cierre en un `chk.report` con tolerancia de redondeo.
4. A-K5-3: corregir el comentario del signo de outlet.
