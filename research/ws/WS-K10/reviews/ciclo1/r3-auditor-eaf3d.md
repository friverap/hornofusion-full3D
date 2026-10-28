# WS-K10, ronda 1: auditoría del código (auditor-eaf3d)

**Veredicto: RECHAZA.** No encontré defectos ALTO ni MEDIO en el código del diff staged. Sí hay un hallazgo MEDIO en la evidencia del reporte: la centinela U_GAS_MAX se dispara en k10b_dt025 y el reporte no lo dice. Es bloqueante por la regla del panel.

Revisé el diff staged de `src/` (sha256 del diff `74a5e2a…`, idéntico al registrado para `campaigns/bin/eaf3d_k10b_opt` en `research/ws/WS-K10/logs/opt_identidad.txt`) y el de `tests/integration/check_audit.py`, `compare_audit.py`, `scripts/make_audit_glossary.py`, los scripts de `research/ws/WS-K10/scripts/` y la regla `.claude/rules/transporte-energia.md`. Por revisión ciega no leí `reviews/`.

## 1. Hallazgos

### MEDIO

**M1. La centinela U_GAS_MAX se dispara en `campaigns/b1/k10b_dt025` y el reporte no lo menciona (bloqueante).**
- **Qué pasa:** en el paso 280003, u_gas_max = 300.0 m/s (el tope) con p_max de 461 kPa. `python3 tests/integration/check_audit.py campaigns/b1/k10b_dt025` da:
  - FAIL `sentinel_gas`;
  - FAIL `regime_gas`: 6 filas con u_gas_max ≥ 200 m/s;
  - FAIL `regime_p`: 592 kPa.

  Los comandos de fuente del reporte filtran con `grep -E 'mass_gas_…'`, así que estos FAIL no se ven. En k10b_mo20 y k10b_dt05 el máximo es de 164 y 188 m/s, sin FAIL.
- **Efecto en las cifras:** el cociente pre-registrado depende de esos pasos.

  | pasos excluidos | e: r(0.25)/r(0.5) | Bgq + err_cc | err_liq + A |
  |---|---|---|---|
  | solo el 280001 (reporte) | 0.812 | 0.967 | 1.114 |
  | hasta el 280003 | 0.888 | 1.003 | 1.114 |
  | hasta el 280004 | 0.842 | 0.982 | 1.117 |

  - El cociente de e queda muy cerca del umbral de refutación de 0.90.
  - err_liq + A es robusto: el ×1.114 se sostiene.
  - El reporte da la sensibilidad a descartar pasos solo en c (−7.0e-3 y −7.2e-3), no en el cociente.
- **Escenario de fallo:** el cuarto dt (0.125 ms) o el reparto de Bgq se pre-registran tomando dt025 como referencia limpia, sin saber que el tope de velocidad del gas estuvo activo en la ventana. CLAUDE.md exige diagnosticar cualquier centinela que se dispare.
- **Arreglo:** declararlo en «Tercer dt» y en «Incertidumbre» con la tabla de arriba, y registrar el diagnóstico (o dejarlo como pendiente explícito del coordinador) en el ledger. El SIN DECIDIR no cambia.

### BAJO (no bloqueantes)

- **B1. Coste fijo con el audit apagado.**
  - `src/mod_workspace.f90:547-550` reserva siempre 6 arrays 3D.
  - `src/mod_pressure_3d.f90:221-222` pone a cero 5 de ellos en cada Poisson aunque `audit_freq = 0`.
  - En `:894-905`, `ws_Fgv` se escribe siempre.

  El impacto es del orden del 1 % del Poisson y no cambia resultados. Arreglo opcional: condicionar a cero `ws_rho_g_used` y `ws_pc_res`.
- **B2. Rama de compatibilidad del checker.** La rama C-221 de `tests/integration/check_audit.py` (CSV sin `m_gas_dec_scale_*`) usa una tolerancia unas 1e2-1e3 veces más laxa. Hoy solo la usan los `k10_*`, con restos de 2.9e-14 kg frente a una tolerancia de 1.4e-11 kg. Conviene comentar en el código que es solo para esos CSV, o retirarla cuando dejen de citarse.
- **B3. FAIL de k10_base sin mencionar y glosario impreciso.**
  - k10_base y k10b_base dan FAIL `energy_balance` (2.24×) y `regime_gas` (215 m/s), sin mención en el reporte. No es regresión: k8_base da los mismos FAIL, idénticos.
  - El glosario de `m_gas_eosend_abs` dice «sum over cells», pero el código solo suma celdas con c ≠ 0 en pasos con `dec_ok`.

## 2. Verificado como correcto (no re-auditar)

**Identidad y residuo del Poisson**
- `gface` (`src/mod_audit.f90`) elige el dador igual que `gmass` (`mod_pressure_3d.f90:1076`): la celda «−» si q ≥ 0. Con q = 0 retorna, así que nunca lee la rho de un halo de frontera física.
- `ws_Fgv` se pone a cero entero (halos incluidos) en cada Poisson y solo se escribe en caras con `ws_Fg_lk = 1`, que también se ponen a cero cada Poisson. `mpi_exchange_halos_3d` no toca los halos de frontera física: verificado en `mod_mpi_topology.f90:326-351`.
- `ws_pc_res` sigue el orden de `matvec` (`mod_solver_3d.f90:318`). El CG intercambia los halos de pp al final de forma incondicional, y en el retorno temprano lo hace el primer `matvec`.
  - Filas selladas o triviales: aP = 1, Su = 0, sin enlaces. Salidas: Dirichlet con pp = 0. En ambas, r = 0 es correcto.
  - Solo se escriben celdas propias, y el audit solo lee celdas propias.
- `ws_rho_g_used = gas%rho` tiene halos coherentes: `phase_exchange_halos(gas)` en `mod_multiphase.f90:444`, antes del Poisson en :478, sin cambios de rho entre medias. Las dos formas son conformes (`-1:n+2`).
- Patrón MPI:
  - Los intercambios nuevos están bajo condiciones uniformes entre ranks (`cfg`).
  - `DEC_SKIP` lo suma solo el rank 0, como `CC_SKIP`.
  - `acc` se reduce hasta `N_AUD = 135` (`mod_audit.f90:750`).
  - No hay operaciones de columna nuevas.

**Estado y reinicio**
- Todo el estado nuevo (`ws_Fgv_*`, `ws_rho_g_used`, `ws_pc_res`, `ws_rho_g_pre`, `mg_eos_pre`) vale dentro del paso y se valida por id del paso. No hace falta en el snapshot.
- `probe_set_step(step)` se llama siempre en cada paso (`main_3d.f90:575`). No hay reintento de paso.
- `ws_Fg` solo se escribe en el Poisson, así que no hay deriva entre `fl` y `gface`.

**Detalles del código**
- No hay dummies de array nuevos (sin riesgo de Bug 22 ni de límites inferiores).
- La exclusión de `pc_fs_*` coincide con `fs_on` (`mod_pressure_3d.f90:1255`, que exige las dos claves).
- `err_liq_all`, `ELF_FREE`, `err_cc` y `err_art` se suman sobre el mismo conjunto de celdas que las piezas.
- El gancho de la EOS final (`audit_mark_eos_pre`) se marca en el mismo paso, justo antes de `update_properties`. El modo 1 corre después.

**Reproducción con el checker de este diff (`python3 tests/integration/check_audit.py`)**
- Columnas: 24 nuevas y 137 comunes con k8s_mo20 (contado).
- `k10_*` (rama C-221): PASS en `mass_gas_decomp`, con restos de 2.9e-14 / 5.8e-14 / 2.9e-14 kg frente a una tolerancia de 1.4e-11 kg.
- `k10b_*`: PASS en `row_volume`, `decomp` y `eos_end` (eos_end ≤ 3.0e-18 kg).
- Los restos de `decomp` escalan con el número de filas, porque son el redondeo de la masa de gas: unos 4.9e-16 kg por fila en el multifase. No es un sesgo.
- La tabla de piezas reproduce con `piezas.py --sin-paso1`, y el veredicto H10 da SIN DECIDIR (−0.683, −0.135; cociente 0.184).

**Sin cambio numérico**
- `research/ws/WS-K10/logs/test_full.txt` termina en «TESTS (full): OK».
- Los conteos de checks reproducen el 41 PASS / 27 INFO del reporte.
- `cmp_comunes.txt` registra 61 bancos idénticos. La procedencia de la base sigue sin verificar, como ya declara el reporte.

**Regla de transporte**
- La entrada WS-K10 de `.claude/rules/transporte-energia.md` ya no incluye las lecturas retiradas de C-214 ni C-215.

## 3. Orden sugerido de corrección (uno por uno)

1. **M1:** declarar la centinela de k10b_dt025 y la sensibilidad del cociente; registrar el diagnóstico o el pendiente en el ledger.
2. **B3:** una línea sobre los FAIL de k10_base, que son los de k8_base, y precisar el glosario de `m_gas_eosend_abs`.
3. **B2:** comentar o acotar la rama de compatibilidad del checker.
4. **B1:** condicionar la puesta a cero de los arrays de diagnóstico a `audit_freq > 0` (opcional).
