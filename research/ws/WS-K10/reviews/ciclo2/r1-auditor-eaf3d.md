Revisión del panel de cierre de WS-K10 (ronda 1, auditor-eaf3d)

**Veredicto: APRUEBA.** No encontré ningún hallazgo ALTO ni MEDIO en el código del diff staged. Quedan tres hallazgos BAJO, ninguno bloqueante.

Alcance: el diff staged de `src/main_3d.f90`, `src/mod_audit.f90`, `src/mod_pressure_3d.f90`, `src/mod_workspace.f90`, `tests/integration/check_audit.py`, `tests/integration/compare_audit.py`, `scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md` y los scripts de `research/ws/WS-K10/scripts/`, contrastado con `research/ws/WS-K10/report.md`. No leí las revisiones de otros revisores.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B-1. Comentario engañoso sobre la coherencia de halos** (`src/mod_pressure_3d.f90:916`)
- **Defecto:** el comentario dice «gas%rho tiene halos coherentes aqui (la evaluo gmass)». Que gmass lea un halo no lo vuelve coherente.
- **Escenario de fallo:** si en alguna config gas%rho llega al Poisson con el halo de bloque rancio, el rank A forma `ws_Fg` con su halo y el rank B, en `gface`, usa su rho propia. `mass_gas_decomp` daría FAIL en esa frontera de bloque.
- **Gravedad:** el fallo sería visible, no silencioso, y no hay error numérico. Hoy no ocurre: hay PASS con n1, n4, n8, n12 y en los reinicios n8->n4 y n8->n12.
- **Arreglo:** reescribir el comentario. La coherencia la da el `phase_exchange_halos(gas)` posterior a la EOS, y la verifica el cierre.

**B-2. Resets sin guardia con el audit apagado** (`src/mod_pressure_3d.f90:221-222`)
- **Defecto:** `ws_Fgv_*`, `ws_rho_g_used` y `ws_pc_res` se ponen a cero en cada Poisson aunque `audit_freq = 0`. Son 5 escrituras de arrays completos por iteración externa.
- **Gravedad:** no cambia la numérica y el coste es despreciable frente al CG. El reporte dice que la copia, los halos y el residuo solo se hacen con el audit activo, y eso es cierto.
- **Arreglo:** poner los resets de `ws_rho_g_used`, `ws_pc_res` y `ws_Fgv_valid` bajo `audit_freq > 0`.

**B-3. Bootstrap del script `centinela.py` sobre una serie filtrada** (`research/ws/WS-K10/scripts/centinela.py:38-50`)
- **Defecto:** el bootstrap de «pasos tranquilos» arma bloques de 10/20 valores de una serie ya filtrada por p_max < 100 kPa. Esos valores no son contiguos en el tiempo, así que los bloques no son de 10 ms como dice el docstring. Además se descarta el resto que no completa un bloque (con 58 valores entran 50).
- **Escenario de fallo:** el IC90 de C-223 (0.33-0.40) puede quedar subestimado. Es una lectura y no afecta a los veredictos de C-202 ni de C-212.
- **Arreglo:** hacer el bootstrap sobre la serie temporal completa y filtrar dentro de cada réplica, o marcar ese IC90 como orientativo.

**Observación, no defecto.** `mass_gas_decomp` es algebraicamente igual a ρ_it·dt·(cierre de la fila en volumen) más la identidad de inventario de WS-K7, celda por celda. Lo derivé de las definiciones de `pa`, `br1`, `br2`, `bgr`, `bgq` y `bx`. Por tanto valida la consistencia de la fila, de los ganchos y de ρ_it como densidad dadora, pero no el significado del reparto entre Bgq y err_cc. El reporte ya lo declara en la sección «La contabilidad no es única».

## 2. Verificado como correcto (no re-auditar)

**Identidad y piezas**
- Derivé la identidad de forma algebraica: D − (A + Br1 + Br2 + Bgr + Bgq + Bx) = ρ_it·dt·rvv, más el resto de la identidad de inventario de WS-K7.
- Los signos son coherentes: `r = Su − A·pp` (que es `ws_pc_res`), `Bx = −ρ_it dt r`, y `rvv` incluye `+r`.
- `gface` usa el mismo dador que `gmass` (la celda − si q ≥ 0), con orientación `sgn` correcta en las 6 caras.
- `q == 0` evita leer el halo de la frontera física, y las caras no enlazadas quedan a 0 por el reset de cada llamada.

**Residuo del CG**
- `ws_pc_res` usa el mismo orden de operaciones que `matvec` (`mod_solver_3d.f90:318`).
- `pp` trae halos tras el CG: el intercambio es incondicional y hace la copia periódica en theta en serial.
- `sh%pp = 0` antes del CG (línea 443). Con eso, las filas triviales (inactivas, selladas y salidas, con `aP = 1`, `Su = 0` y vecinos a 0) mantienen pp = 0 exacto bajo PCG Jacobi. Excluirlas del residuo es correcto.
- Las salidas se identifican con el mismo criterio que en las líneas 576 y 1009, y que `outlet()` del audit.

**MPI**
- Los nuevos `mpi_exchange_halos_3d` dependen solo de condiciones de config global: no hay riesgo de deadlock.
- `ws_Fgv` en el halo de bloque viene del rank dueño, igual que `ws_Fg` y `ws_Fg_lk`. Los halos de frontera física quedan a 0.
- Todas las entradas de `acc` se reducen con suma, y `DEC_SKIP` solo lo cuenta el rank 0.

**Estado, reinicio e inicialización**
- No hay estado nuevo entre pasos: todo se valida por id de paso con `probe_set_step(step)`, que es incondicional (`main_3d.f90:575`).
- `acc` no va al snapshot, así que el cambio de `N_AUD` de 111 a 135 no rompe los reinicios.
- Bug 22: `ws_rho_g_pre`, `ws_rho_g_used` y `ws_Fgv_*` se inicializan al alocarse, y `mg_eos` se pone a 0 entero en el modo 0. Las copias completas solo se leen en celdas propias, o en halos ya intercambiados.
- No hay dummies de array nuevos: `gface` recibe escalares.

**Orden del paso y checks**
- `ws_rho_g_pre` se copia justo antes de la EOS final. Entre la copia y el modo 1 solo actúan `update_properties` y los halos. `gas%rho` solo se escribe en `mod_properties_3d:42` y en `mod_fields_3d:429`.
- `eosend_ok` equivale a `dec_ok`, porque `mg_eos` siempre está alocado si `mg_ini_ok`. No hay PASS vacuo de `mass_gas_eos_end`.
- `pc_fs_*`: el gate exige las dos claves, igual que `fs_on` en `mod_pressure_3d.f90:1255`.

**Sin cambio numérico**
- Las 137 columnas comunes de `k8s_mo20`/`k10_mo20`, `k8s_dt05`/`k10_dt05` y `k8_base`/`k10_base` son idénticas. Entre `k10_*` y `k10b_*` solo cambia `m_gas_rv_scale`.
- El golden `metrics_v132` (rtol 1e-12) da 61 PASS con error 0 en `test_full.txt`.
- El sha del diff de `src/` staged (74a5e2a4…) coincide con el del binario `k10b` registrado en `opt_identidad.txt`.
- `src/` se modificó por última vez a las 22:21 y `tests/out/*/audit.csv` es de las 22:23, posterior a ese cambio.

**CSV, checker y reproducción de cifras**
- Los 61 CSV de `tests/out` tienen 161 columnas en encabezado y filas; las 24 nuevas coinciden con el glosario y con `docs/AUDIT_COLUMNS.md`.
- `check_audit.py` sobre `tests/out` da 43 PASS en cada uno de los tres checks y 36 «INFO n/a», como dice el reporte. Los PASS incluyen corridas n1 (costura periódica), n12 y los reinicios entre distinto número de ranks.
- Las cifras de C-221 se reproducen:
  - en los `k10_*`, restos de 2.91e-14, 5.81e-14 y 2.91e-14 kg con tolerancias de 1.41e-11 a 1.46e-11 kg (rama del CSV antiguo);
  - en los `k10b_*`, eos_end de 1.9e-18 a 3.0e-18 kg;
  - las piezas por paso coinciden con el reporte.
- La rama del CSV antiguo en `check_audit.py:528-532` coincide con la fórmula que enuncia C-221 y se identifica a sí misma en la salida.
- `compare_audit.py`: `ROUNDOFF_COLS` y `ROUNDOFF_FACTOR` solo actúan con `--decomp`.

## 3. Orden sugerido de corrección (uno por uno, ninguno bloquea)
1. B-3: reescribir el bootstrap o marcar el IC90 de C-223 como orientativo. Es solo reporte o script.
2. B-1: corregir el comentario. Sin cambio numérico.
3. B-2: poner los resets bajo la guardia del audit. Verificación bit a bit con `/verificacion-bitwise`.

Pendiente de proceso, no del código: `status.json` tiene `test_quick: null`. Hay que correr `make test-quick` sobre este mismo diff antes del commit.