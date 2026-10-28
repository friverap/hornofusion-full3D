# WS-K10, ronda 1: revisión de código (auditor-eaf3d)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Hay tres BAJO no bloqueantes; conviene arreglar B1 en este mismo commit.

Alcance: el diff staged de `src/main_3d.f90`, `src/mod_audit.f90`, `src/mod_pressure_3d.f90`, `src/mod_workspace.f90`, `tests/integration/check_audit.py`, `tests/integration/compare_audit.py`, `scripts/make_audit_glossary.py` y los scripts de `research/ws/WS-K10/scripts/`, revisado contra `research/ws/WS-K10/report.md`. Todo fue de solo lectura: no compilé ni corrí binarios. Solo ejecuté scripts Python de lectura sobre `campaigns/b1/*/audit.csv`.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B1. Un check da PASS sin haber medido nada cuando faltan sus columnas** (`tests/integration/check_audit.py:514-530`)
- **Defecto.** `V = lambda c: sum(r.get(c, 0.0) ...)` toma como 0 las columnas que faltan, y la única compuerta es que exista `m_gas_dec_abs_multi`.
- **Escenario.** `python3 tests/integration/check_audit.py campaigns/b1/k10_mo20` (binario k10 previo a la revisión) da:
  - `PASS mass_gas_eos_end ... = 0.00e+00 kg (max 1e-13 x 0.00e+00 + 1e-20)`, aunque esas columnas no existen en el CSV;
  - `mass_gas_row_volume` pasa con la escala antigua (7.58 frente a 661);
  - `mass_gas_decomp` da FAIL por la escala 0.
  
  La misma causa da tres resultados distintos. Además rompe la convención de marcar «no medido» las columnas que faltan en CSV antiguos.
- **Impacto.** No afecta a la suite, que siempre tiene todas las columnas, ni al reporte, que limita eos_end a los `k10b_*`.
- **Arreglo.** Condicionar cada check a que estén sus columnas (`m_gas_eosend_*`, `m_gas_dec_scale_*` y la escala bruta de rv). Si faltan, imprimir «INFO … no medido».

**B2. La línea INFO dice «por paso» pero divide por filas** (`tests/integration/check_audit.py:536-543`)
- **Defecto.** `mass_gas_cells_pieces` divide entre el número de filas.
- **Escenario.** Con `audit_freq > 1`, cada fila acumula varios pasos y la cifra impresa es por fila.
- **Impacto.** Solo la etiqueta. Los números del reporte salen de `piezas.py` y `tasa.py`.
- **Arreglo.** Dividir entre los pasos que cubre cada fila (delta de `step`), o cambiar la etiqueta a «por fila».

**B3. Los logs de test no están atados al diff (evidencia, no código)**
- `test_unit.txt` y `test_full.txt` no registran el hash del diff de `src/`. Solo los ata el orden de mtime: src a las 22:21:15, unit a las 22:23 y full a las 22:36:55.
- `status.json` tiene `test_quick = null`.
- **Arreglo.** Correr `make test-quick` sobre el diff exacto, como exige guard_cierre, y registrar en el log el sha256 de `git diff --cached -- src/`.

## 2. Verificado como correcto (no hace falta volver a auditarlo)

**Identidad**
- Rehíce el álgebra a mano. Con:
  - Δm = comp + eos + volfix;
  - fl = −dt Σ ρ_dador q_out;
  - la fila Σ(q_g,out + q_l,out) = su_cc + E2 − store_gas − store_art − r;
  - X = dt(Σq_g,out + r);
  
  sale D − A = dt Σρ_d q_o − ρ_f X + ρ_f dt gadv, que es exactamente Br1 + Br2 + Bgr + Bgq + Bx.
- Es puro álgebra y vale también con escoria legada; ahí solo cambia cómo se interpreta A.

**Caudales y densidad del dador**
- `gface` (`mod_audit.f90:1392`) toma el mismo dador que `gmass` (`mod_pressure_3d.f90:1076`) y orienta bien los signos de las caras − y +.
- `rit` se asigna antes de llamar a `gface`.

**Residuo de la fila**
- `ws_pc_res` (`mod_pressure_3d.f90:822-842`) usa el mismo orden de operaciones que `matvec`.
- El CG intercambia los halos de `pp` al salir (`mod_solver_3d.f90:298`).
- `sh%pp = 0` antes del CG (l.443). Por eso las filas triviales, selladas y de salida (aP = 1, Su = 0, sin vecinas) tienen r = 0 exacto, y excluirlas es correcto.

**Halos y MPI**
- `ws_Fgv_*`, `ws_rho_g_used` y `ws_pc_res` se ponen a cero, con halos, en cada Poisson (l.221-222).
- `ws_Fgv` intercambia halos con el audit activo y `ws_rho_g_used` copia todo `gas%rho`: no hay un `mold` escrito solo en celdas propias (Bug 22). `ws_pc_res` solo se lee en celdas propias.
- La cara con q = 0 no lee el halo de frontera física.
- La cara i−1 de otro rank llega por halo de `ws_Fgv`, así que se respeta la frontera de bloque. Los `k10b_*` a 15 ranks cierran a 1e-13.

**Reinicio**
- No hay estado nuevo entre pasos: la validez va por id de paso (`probe_set_step` en `main_3d.f90:574`) y nada entra al snapshot.
- Los 15 reinicios de la suite pasan.

**Reparto Br1/Br2**
- `gas%rho` solo se escribe en `update_properties` (`mod_properties_3d.f90:42`) y en la inicialización. Entre el último Poisson y `ws_rho_g_pre` (`main_3d.f90:801`) solo actúa `mod_multiphase.f90:579`. Por tanto Br1 es la EOS del mismo outer.
- `audit_mark_eos_pre` copia entero `mg_eos`, que el modo 0 pone a cero entero.

**Compuertas**
- `dec_ok` excluye `pc_fs_*` con las dos claves, igual que `fs_on` (`mod_pressure_3d.f90:1255`).
- La E2 sin validar no puede darse con `cc_ok` verdadero.
- `DEC_SKIP` solo lo suma el rank 0.

**CSV y glosario**
- El orden del encabezado y el de la escritura de las 24 columnas nuevas coinciden.
- Las 24 columnas están en el glosario y en `docs/AUDIT_COLUMNS.md`.

**Sin cambio numérico**
- El sha256 del diff staged de `src/` (74a5e2a4…) es igual al del binario `k10b` (`opt_identidad.txt`).
- `cmp_comunes --par`:
  - k10 frente a k10b: solo difiere `m_gas_rv_scale`, en los 3 bancos;
  - k8s_mo20 frente a k10_mo20: 0 diferencias en 137 columnas.
- `test_full.txt`: 41 PASS y 27 n/a en los tres checks; los únicos FAIL son XFAIL listados.

**Cifras del reporte (reproducidas)**
- `check_audit` sobre los `k10b_*`: restos de 2.2e-14 m3 (fila), ≤ 4.3e-13 kg (decomp) y ≤ 3e-18 kg (eos_end).
- `piezas.py --sin-paso1`: la tabla de 1 y 0.5 ms y `k10_base` coinciden.
- `tasa.py` con y sin `--grupos`:
  - r(e) = −1.4505e-2, −9.145e-3 y −7.424e-3 kg/s;
  - ajuste p = 1.64 y c = −6.61e-3 kg/s;
  - grupos 0.792 y 0.967, y 1.038 y 1.114.

**compare_audit**
- Las cotas de `ROUNDOFF_COLS` solo se aplican con `--decomp`.
- `m_gas_rv_abs` y `m_gas_eosend_abs` usan su propia escala con factor 1e-13.

## 3. Orden sugerido de corrección (uno por uno)

1. **B1**: la compuerta por columna en `check_audit.py`. Verificar que `campaigns/b1/k10_mo20` dé «no medido» y que los `k10b_*` sigan en PASS.
2. **B2**: la etiqueta o el divisor de la línea INFO.
3. **B3**: `make test-quick` sobre el diff exacto, con el hash en el log, antes del commit.
