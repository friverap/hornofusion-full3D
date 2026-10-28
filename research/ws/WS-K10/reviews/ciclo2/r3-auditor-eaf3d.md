# Revisión de código WS-K10, ronda 1 (auditor-eaf3d)

Alcance: el diff staged de `src/`, `tests/integration/` y `scripts/make_audit_glossary.py`, contrastado con `research/ws/WS-K10/report.md`. Además revisé por encima los scripts de `research/ws/WS-K10/scripts/`. Todo fue de solo lectura: no compilé ni corrí nada. Sí ejecuté `check_audit.py` y `compare_audit.py` sobre salidas que ya existían en `tests/out`.

**Veredicto: APRUEBA.** No encontré ningún hallazgo ALTO ni MEDIO. Quedan tres BAJO que no bloquean.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

- **B-1. `tests/integration/check_audit.py:590-594`: `mass_gas_eos_end` pasa sin medir nada.**
  - **Defecto:** cuando `m_gas_eosend_scale` vale 0, la condición queda en `0 <= 1e-20` y el check da PASS.
  - **Cuándo ocurre:** en las corridas sin EOS final, porque la condición de `main_3d.f90:806` (`solve_flow .and. solve_multiphase .and. solve_energy`) es falsa.
  - **Medido sobre `tests/out`:** 8 de los 43 PASS imprimen «max 1e-13 x 0.00e+00»: bath_test_n1/n4/n12, bath_test_stretch_n4, bed_bath_rest_n1/n4, cold_flow_noenergy_n4 y pocket_rise_n4.
  - **Alcance:** ahí Br2 vale 0 por construcción, así que no se acepta ningún estado incorrecto. El problema es que el reporte cuenta los 43 PASS como si fueran 43 evaluaciones reales, y la cobertura efectiva es de 35.
  - **Arreglo:** con `eos_s == 0`, imprimir `INFO n/a (sin EOS final)` en lugar de PASS.

- **B-2. `check_audit.py:560-565`: el «n/a» de `mass_gas_decomp` no separa causas legítimas de una regresión.**
  - **Escenario de fallo:** si un cambio futuro deja `dec_ok` siempre falso (por ejemplo, copiar `ws_rho_g_pre` antes de `probe_set_step(step)` en `main_3d.f90:575`), los tres cierres pasan a «n/a» en toda la suite y nadie se entera.
  - **Estado actual:** verifiqué las filas con `cells_skip = liq_skip = cc_skip = 0` y `dec_skip > 0`. Solo aparece `bed_flood_n4`, y ahí es legítimo: su config activa `pc_fs_liquid_face` y `pc_fs_liquid_gradient`.
  - **Arreglo:** que el checker dé FAIL en ese caso cuando la config no tiene las dos claves `pc_fs_*`.

- **B-3. `src/mod_audit.f90:1039-1040`: comentario fuera de sitio.** El comentario de `audit_eos_cell` quedó encima de la cabecera de `audit_mark_eos_pre`. Es solo de forma.

## 2. Verificado como correcto (no hace falta re-auditarlo)

- **La identidad es exacta.** Rehíce el álgebra a mano:
  - Partiendo de e = comp + eos − fl − rx, la fila del Poisson tras el CG (aP pp − Σ a_nb pp_nb = Su − r, con aP − Σ a_nb = store_gas + store_art) y `gmass` con el dador «celda − si q ≥ 0», se obtiene D = A + (ρ_it − ρ_f) X + ρ_f dt gadv + dt Σ(ρ_d − ρ_it) q_out − ρ_it dt r.
  - Eso es lo mismo que A + Br1 + Br2 + Bgr + Bgq + Bx con las definiciones de `mod_audit.f90:1223-1245`.
  - `gface` usa el mismo dador y la misma orientación que `gmass` (`mod_pressure_3d.f90:1076-1084`).
- **La aritmética del Poisson no cambia.** `ws_Fg = gmass(ws_Fgv)` aplica la misma expresión que antes, solo que guardada en una variable intermedia.
  - `ws_Fgv_*`, `ws_rho_g_used` y `ws_pc_res` se ponen a cero en cada Poisson (`mod_pressure_3d.f90:432`).
  - La copia de densidades, los tres intercambios de halos y el residuo solo se hacen con `audit_freq > 0`. Los intercambios son colectivos porque `cfg` es igual en todos los ranks.
  - `mod_pressure_3d.f90` es el único sitio que escribe `ws_Fg` y `ws_Fg_valid`.
- **El residuo `ws_pc_res` sigue el mismo orden de operaciones que `matvec` de `mod_solver_3d.f90`.**
  - El CG deja los halos de `pp` intercambiados incluso cuando sale temprano por `bnorm < SMALL`, porque el primer `matvec` ya los intercambió.
  - Las filas triviales y selladas quedan con pp = 0 exacto, ya que `sh%pp = 0` antes del CG y su r y su z son 0.
  - Se excluyen las salidas con el mismo criterio que `apply_pressure_bc` y que `outlet()` del audit (`is_electrode` en k = nz con `at_zmax`).
  - Entre el CG y el corrector, nada modifica `pp`.
- **Halos y Bug 22.**
  - `ws_Fgv` se escribe en caras propias y se intercambia, así que la cara i−1 en una frontera de bloque llega por halo.
  - En una frontera física la cara no se escribe y queda en q = 0, y `gface` sale sin leer la ρ del halo.
  - Ningún array `mold` escrito solo en celdas propias se copia entero: `mg_eos` se pone a cero entero en el modo 0, y `ws_*` se inicializa en `ensure_workspace`.
  - Los dummies del CG ya tenían `(-1:,-1:,-1:)`.
- **Reparto Br1/Br2.**
  - Solo `update_properties` (`mod_properties_3d.f90:42`) reescribe `gas%rho` durante el paso, así que Br1 es exactamente la EOS posterior al último Poisson.
  - La comprobación `peos` frente a `deos` usa el mismo orden de operaciones que el gancho, y cierra a 0 o a 3e-16 kg.
- **Reinicio.** No hay estado nuevo que persista entre pasos: la validez se controla con ids por paso (`probe_current_step` se fija en `main_3d.f90:575`, antes de cualquier Poisson). `compare_audit` con `--decomp` pasa en 8→4 y en 8→12 (peor columna `m_gas_brho_it_multi`, 1.2e-12 frente a una tolerancia de 1e-10, según `test_full.txt`).
- **CSV.**
  - Las 24 columnas nuevas (112-135) salen en el mismo orden en la cabecera y en el `write`.
  - Son 161 campos, por debajo del límite de `200(A,ES)`.
  - Las corridas de `tests/out` tienen 161 campos en todas sus filas.
  - El glosario coincide con el código.
- **Checkers**, ejecutados por mí sobre `tests/out`:
  - bed_bath_rest_n4, arc_melt_n1 y cold_10step_n8 dan PASS en `row_volume`, `decomp` y `eos_end`, con restos de 1e-15 a 1e-12 frente a escalas brutas de 1e3 a 5e4.
  - Los 36 «n/a» tienen causa legítima: escoria condensada, mezcla, una fase, sin flujo, o bed_flood con `pc_fs_*`.
  - El bloque WS-K10 está fuera del `if "m_gas_comp_multi"` y usa las variables `rows`, `steps` y `last`, que existen en ese ámbito.
- **Trazabilidad del binario.** El sha256 de `git diff --cached -- src` (74a5e2…) coincide con el registrado en `logs/opt_identidad.txt` para `eaf3d_k10b_opt`. Los logs `test_full.txt` y `test_unit.txt` terminan en OK con rc = 0, y `cmp_comunes.txt` da 61 corridas idénticas.
- **Scripts de investigación.**
  - El filtro `step > 280000` más `[1:]` solo se aplicó a bancos de 280 s.
  - Los de 290 s usan `h14.py`, ya commiteado, con `> 290000` y `[1:]`, o comandos con `> 290001`. Es correcto.

## 3. Orden sugerido de corrección (uno por uno, ninguno bloquea)
1. B-1: marcar «n/a» en `eos_end` cuando la escala es 0, y precisar la cuenta del reporte (35 corridas con medida real).
2. B-2: FAIL en el checker si `dec_skip > 0` sin causa legítima.
3. B-3: recolocar el comentario de `audit_eos_cell`.
