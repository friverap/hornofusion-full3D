# WS-K7 — Revisión auditor-eaf3d (ronda 1 del quinto lanzamiento, diff staged del 25-oct, {C-144}/{C-145})

Alcance: SOLO LECTURA sobre `git diff --cached` (src/mod_audit.f90, mod_continuity.f90, mod_pressure_3d.f90, mod_properties_3d.f90, mod_workspace.f90, Makefile, tests/integration/check_audit.py, regla, glosario) contra `research/ws/WS-K7/report.md` y el ledger (C-144, C-145). No leí `reviews/` de otros revisores. Verifiqué cada punto en el código o recomputando desde los `audit.csv` existentes (python3 sin escribir).

## Veredicto: APRUEBA

No encuentro ningún defecto ALTO ni MEDIO en el código del diff. Tres observaciones BAJAS (no bloqueantes), todas de etiquetado/convención, abajo.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B-1 — `Makefile`: `SRCS` fuera de orden topológico.** `mod_audit.f90` (SRCS línea 23) y `mod_properties_3d.f90` (línea 28) preceden a `mod_probe.f90` (línea 29), pero mod_audit ahora `use mod_probe` y mod_properties_3d `use mod_audit`. Compila porque las reglas explícitas (`Makefile:101`, `:110`) fuerzan el orden (verificado: compilación limpia 13:06 y tests OK). Contradice la convención de CLAUDE.md. Arreglo: subir `mod_probe.f90` por encima de `mod_audit.f90` en `SRCS`.

**B-2 — Etiqueta de `m_gas_err_liq_lk` solo vale con `pc_drift_source = true`.** En `src/mod_audit.f90` (modo 1) `e2_ok` exige `cfg%pc_drift_source`; con la guarda apagada `el_unl = 0` y toda la entrada por caras NO enlazadas de `ws_Fr` cae en `el_lk`, contra el glosario («Part ... on LINKED faces»). Escenario: banco con `pc_drift_source = false` (el default es true, `mod_config_3d.f90:108`; k7v5_* y la batería no lo sufren). Columna de diagnóstico. Arreglo: anotarlo en glosario/AUDIT_COLUMNS o calcular `el_unl = −ρ_g·dt·ws_pc_unl(N)` también en ese caso (es el reparto exacto cuando el Poisson no acepta E2).

**B-3 — `m_gas_rej_nogas` es un estimador.** `ws_lim_step = in_ok/in_tot` es la fracción admitida de la entrada TOTAL del transporte explícito (todas las caras, `mod_continuity.f90:854-858`); el instrumento la aplica a la entrada ENLAZADA del Poisson (`ws_Fc`), que difiere de `ws_Fr`. En las nogas de k7v5 `lim_step = 0` y la columna es Σmax(Fc_in,0) (coincide con «bruta por caras entrantes» del reporte); con 0 < lim_step < 1 la frase del glosario sobreafirma. Arreglo: una palabra («estimador») en glosario y AUDIT_COLUMNS.

## 2. Verificado como correcto

- **Identidad `mass_gas_rewrites`** (Δm_gas = comp + eos + volfix). Inventario de TODAS las escrituras de `gas%alpha`: `mod_continuity.f90:808/1237/1687` (gancho `audit_comp_cell`, con `ag_pre` tomado justo antes), `mod_ecs_feed.f90:266` (volfix :281), `mod_fields_3d.f90:761` (cestas > 1, volfix :778), `mod_solid_phase.f90:138` (volfix :119), `mod_slag_3d.f90:674/887` (volfix :660/:868), `mod_slag_chemistry.f90:363` (volfix :353); `mod_fields_3d.f90:399/403/510` y `mod_slag_3d.f90:134/164/171` son inicialización (antes del lazo). `mod_continuity.f90:754/1670` (`alpha_g = 0`) solo en `cell_type = 0`, excluidas del inventario `m_gas` (`mod_audit.f90:591`) y de la suma de comp/eos. `gas%rho` solo se reescribe en `update_properties` (gancho) e init. Sin ruta sin gancho.
- **Orden del paso**: modo 0 (`main_3d.f90:337`) → cargas/ECS/química/volfix/premelt → `probe_set_step` (:566) → SIMPLE (`update_properties` :646/:658) → `update_properties` :790 → modo 1 (:795) → `audit_write_step` (:819). Nada toca α_g/ρ_g entre :819 y el modo 0 siguiente. Los ids de paso (`ws_pc_unl_used_id`, `ws_pc_unl_id`, `ws_lim_step_id`) se comparan todos después de :566.
- **`ws_pc_unl_used`** (`mod_pressure_3d.f90`): anulado al inicio de cada Poisson (:213), escrito solo donde E2 entra a `Su` (:654), 0 en inactivas/selladas (:672) y donde `Su == 0` tras `apply_pressure_bc` (:744-752); `Su` no se modifica después de la marca (solo lectura en :766). Sin estado entre pasos → correcto que no entre al snapshot. Último Poisson gana.
- **Halos / frontera de bloque**: `ws_Fc_*`, `ws_Fc_lk_*`, `ws_Fg_*`, `ws_Fg_lk_*` (:817-850), `ws_Fr/Fth/Fz` (`mod_continuity.f90:549-551`, :743), `ws_lim_step` (:859), `ws_pc_unl` (:865) con exchange antes de que el modo 1 lea `i-1/j-1/k-1`. Ganchos solo en celdas propias (`get_loop_bounds`; `update_properties` 1..nr). `mg_*` con `allocate(mold)` y sin copia entera (sin Bug 22). Sin dummies 3D nuevas (los ganchos reciben escalares).
- **Signos**: `vp`, `ve`, `vin` usan la misma entrada neta `F(i-1) − F(i)` que `fl` (:1032-1034); `ws_Fc` volumétrico, `ws_Fr` masa / `liq%rho` = ρ_steel constante; `liq_ok` apagado con escoria condensada (donde `liq%rho` cambia, `mod_workspace.f90:394`).
- **CSV**: 117 nombres en el encabezado = 116 separadores + `step` en el `write`; `200(A,ES24.16E3)` cubre los 117 items (con 100 habría reversión de formato). `N_AUD = 91`, reducción MPI sobre `acc(1:N_AUD)` (:641). Contadores por paso solo en rank 0 antes de la reducción.
- **Flags**: `liq_ok = ws_Fc_valid ∧ ws_flux_valid ∧ ¬slag_condensed_on`; los `*_valid` se anulan por paso (`main_3d.f90:576-578`) y el fallback implícito invalida `ws_flux_valid`, `ws_lim_step_valid`, `ws_pc_unl_valid`; la combinación `e2_ok ∧ ¬unl_ok ∧ liq_ok` es inalcanzable.
- **`check_audit.py`**: `mass_gas_rewrites`, `mass_gas_cells_liq/e2/net` y `mass_gas_err_liq_split` están dentro del `elif 'm_gas_out' in last` (`dm_g`, `m_fix`, `em` definidos); con `solve_flow = false` no se evalúa (coherente). Logs: 0 `Traceback`, `TESTS (quick/full): OK`, 67 `mass_gas_rewrites` PASS en test_full y ninguno con comp = eos = 0 (no pasa por la razón equivocada). `mass_gas_err_liq_split` es identidad por construcción (`el_lk := el − el_unl`); vale como guardia de ediciones futuras, no como evidencia.
- **Cifras de {C-145}** recomputadas desde `campaigns/b1/k7v5_{mo20,base}/audit.csv` (59 filas > 280000): rem_all/abs 0.3186 / 0.4038; neto 1.5705 / 1.3196; con filtro 0.5651 / 0.6263; err_liq_all +4.881e-4 = lk +4.977e-4 + unl −9.58e-6 (base +5.022e-4 = +5.021e-4 + 1.64e-7); Σ|unl|/Σ|e| 0.0013 / 0.0005; nogas Σ|ρV_pois| 4.078e-3 / 4.086e-3, Σ|ρV_eff| 1.1e-16; rej/Σ|e|_nogas 1.589 / 1.595; nogas/abs 0.294 / 0.266; liq_skip = e2_skip = 0; `mass_gas_rewrites` resto −6.15e-14 PASS; split resto 1.2e-20 PASS. 14 columnas invariantes bit a bit idénticas a k7v4_* (60 filas). Todas coinciden con el reporte y con C-145.
- **Binario vs diff**: `campaigns/bin/eaf3d_k7v5_opt` 25-oct 13:06:13, posterior a la última edición de `src/` y `tests/` (13:04:15). Numérica idéntica: el único array nuevo del workspace solo lo lee el audit; golden v131 OK.
- `paper/tables/audit_glossary.tex` está en `.gitignore` (`paper/`) por diseño (`make_audit_glossary.py:7`); su ausencia del diff no es omisión.

## 3. Orden sugerido de corrección (ninguna bloquea el cierre)

1. B-1: reordenar `SRCS` (un movimiento de línea; `make clean && make` cuando no haya corrida en curso).
2. B-2: nota en glosario/AUDIT_COLUMNS (o el reparto exacto con `pc_drift_source = false`).
3. B-3: «estimador» en la descripción de `m_gas_rej_nogas`.

Las tres pueden ir en el mismo commit de documentación posterior; no exigen re-medida ni re-baseline.
