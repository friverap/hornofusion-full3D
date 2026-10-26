# Revision r1 — auditor-eaf3d — WS-K7 (diff staged)

Alcance: codigo del diff staged (`src/mod_audit.f90`, `src/mod_continuity.f90`, `src/mod_properties_3d.f90`, `Makefile`, `tests/integration/check_audit.py`, `scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md`, `.claude/rules/transporte-energia.md`) contra `research/ws/WS-K7/report.md` y el ledger C-120..C-143. Solo lectura; no lei `reviews/` de otros revisores.

Veredicto: **RECHAZA** (una objecion MEDIO sin resolver, M-1).

## Hallazgos

### MEDIO (bloqueante)

**M-1. `m_gas_err_liq` usa la E2 del transporte posterior al ultimo Poisson y, por construccion, cancela el termino de caras no enlazadas.**
- `src/mod_audit.f90:1037-1043` (staged): `vp = dt*(sum ws_Fc enlazadas) + dt*ws_pc_unl` (si `pc_drift_source .and. ws_pc_unl_valid .and. lk_any`); `ve = dt*(sum ws_Fr)/rho_l`; `el = rho_g (vp - ve)`.
- `ws_pc_unl` lo escribe el FINAL de `solve_volume_fraction` (`src/mod_continuity.f90:864-867`) y en cada iteracion externa el orden es Poisson (`src/mod_multiphase.f90:478`) -> transporte (`:510`). En el modo 1 del audit (fin de paso) `ws_pc_unl` es la E2 del transporte N; el Poisson N uso la del transporte N-1, y en la iteracion externa 1 NINGUNA (`src/mod_pressure_3d.f90:642-643` exige `ws_pc_unl_id == probe_current_step()`; el id es del paso anterior).
- Peor: `unl_vol` (`src/mod_continuity.f90:496-504`) se construye con los MISMOS `Fw..Ft` que acumulan `ws_Fr/Fth/Fz` (`:506-508`), tomando solo las caras con `ws_Fc_lk = 0`. Con `pc_spill_source = false` (default, `mod_config_3d.f90:109`): `dt*ws_pc_unl(N) = parte no enlazada de ve` exactamente. Luego `vp - ve = dt*sum_enlazadas(F_c - F_r/rho_l) + derrame`: el termino de goteo por caras no enlazadas (uno de los tres mecanismos que la regla y el glosario atribuyen a err_liq) se cancela identicamente, para cualquier valor de E2.
- Escenario concreto: `max_outer = 1`, `pc_drift_source = true` (default). El Poisson nunca acepta E2. Una celda multifase con alguna cara enlazada pero alimentada solo por goteo no enlazado: V_pois real = 0, V_eff = unl, bajo H `e = -rho_g*unl`. El audit calcula `vp = unl`, `ve = unl`, `err_liq = 0`, `rem_abs += |e|`: reporta que H no explica justo donde H es exacta. En k7v4 (max_outer 5/20) el sesgo por celda es `rho_g*dt*(E2(N-1) - E2(N))`, que nadie midio (R-4 declara Poisson sin converger en parte de los pasos). El veredicto C-139 (0.319 / 0.57) y las lecturas por subconjunto (58-84 %, >= 71 %) dependen de columnas que no miden lo enunciado.
- Afecta: `m_gas_err_liq`, `_all`, `_rem_abs`, `_rem_abs_all`, `_vpois_abs`, `m_gas_e2_nolink` (`:1030`, mismo valor desfasado), la regla, el glosario y `docs/AUDIT_COLUMNS.md` ("E2 ... where the Poisson accepted it").
- Arreglo: en `solve_pressure_correction`, al sumar `ws_pc_unl` a `Su` (`:649`) guardar `ws_pc_unl_used(i,j,k) = ws_pc_unl(i,j,k)` (0 en el resto, puesto a 0 al inicio de cada Poisson, con flag/id); `audit_gas_cells` usa `ws_pc_unl_used` en `vp` y en `m_gas_e2_nolink` (el proxy `lk_any` queda solo para la clase nolink). Re-medir k7v4_* con el binario corregido y reescribir la descripcion del instrumento: con la E2 del transporte N se reduce al desajuste en caras enlazadas + derrame.

### BAJO

**B-1.** `src/mod_audit.f90:1032-1052`: con escoria condensada `ws_Fr` es el flujo del acero (`mod_continuity.f90:1260`) y el complemento sigue al condensado; el glosario lo declara invalido pero el codigo calcula e imprime "err_liq explica X". Sugerido: `liq_ok = liq_ok .and. .not. slag_condensed_on(cfg)` (cuenta en `m_gas_liq_skip`).

**B-2.** `tests/integration/check_audit.py:416`: tolerancia `1e-9*sum|dm|` (~1.6e-7 kg en los bancos) frente a restos medidos <= 4e-12 kg: una ruta sin gancho que mueva < 1e-7 kg por ventana pasa. Sugerido `1e-11*sum|dm|`.

## Verificado como correcto (no re-auditar)

- Identidad `d m_gas = comp + eos + volfix`: los 3 ganchos de complemento (`mod_continuity.f90:812, 1240, 1691`) y el de EOS (`mod_properties_3d.f90:45`) cubren todas las reescrituras de `gas%alpha`/`gas%rho`; el resto (solid_phase:119, ecs_feed:281, fields:778, slag_3d:660/868, slag_chemistry:353) ya tienen `audit_volfix_cell`. `gas%alpha = 0` en `cell_type 0` queda fuera de `m_gas` (write_step y modo 1 excluyen cell_type 0). Secuencialidad exacta de los dm; resto <= 4e-12 kg en 60+ bancos de los logs.
- Orden del paso: modo 0 (`main_3d.f90:337`) precede a toda reescritura; EOS 646/658/579/790 y complementos entre modo 0 y modo 1 (795); entre `audit_write_step` y el modo 0 siguiente no hay estado del gas que cambie. `charge_scrap`/`ecs_feed` (365/383) dentro del paso.
- Halos/MPI: arrays del audit puestos a 0 ENTEROS y sumados solo en celdas propias (sin Bug 22); `mg_ag0` solo se lee donde se escribio; `ws_Fc*`, `ws_Fc_lk*` (pressure 800-805) y `ws_Fr/Fth/Fz` (continuity 549-551) con exchange: la cara `i-1` en frontera de bloque es la propia del vecino. `LIQ_SKIP` solo rank 0; `CELLS_NOLINK` por celda, reducido bien.
- Convencion de caras igual a la del balance del gas; `ws_Fc` volumetrico, `ws_Fr` masa, `liq%rho = rho_steel` fuera de la vista condensada (restituida antes del audit).
- C-120: `ws_Fg = 0` en caras no enlazadas (pressure 210, 819-823). Correcto.
- Proxy `lk_any` para el CONJUNTO donde el Poisson acepta E2: mascaras puestas a 1 exactamente donde se suma coeficiente (pressure 1228-1262, 1319-1342, 1406-1429, 1553-1591); `sealed` = act con suma de coeficientes <= 0 (655-668). Correcto (el VALOR de E2 es M-1).
- Sin estado persistente nuevo; flags intra-paso ya se invalidan en `main 576-578`. Numerica bit a bit (solo arrays del audit). Makefile con la dependencia nueva, sin ciclo. Formato `200(...)`, encabezado, glosario y docs consistentes; `dm_g/m_fix/em/rows` definidos en su ambito en `check_audit.py`.

## Orden sugerido de correccion

1. M-1: `ws_pc_unl_used` en el Poisson + audit que lo lea; re-medir k7v4_mo20/base; corregir regla, glosario, AUDIT_COLUMNS y reporte (forma reducida del instrumento y magnitud de `E2(N-1) - E2(N)`); auditoria dirigida.
2. B-1: guardar el paso con escoria en `m_gas_liq_skip`.
3. B-2: apretar la tolerancia de `mass_gas_rewrites`.
