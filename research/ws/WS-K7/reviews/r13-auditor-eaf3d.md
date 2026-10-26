# WS-K7, ronda 1: revisión de código (auditor-eaf3d)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Hay cuatro BAJO no bloqueantes.

**Alcance.** Revisé el diff staged de `src/` (mod_audit, mod_continuity, mod_pressure_3d, mod_properties_3d, mod_workspace), `Makefile`, `tests/integration/check_audit.py`, `scripts/make_audit_glossary.py` y `docs/AUDIT_COLUMNS.md`, contra el reporte y C-144. Fue revisión ciega: no leí `reviews/`. No compilé ni ejecuté nada.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO (no bloqueantes)

- **B1. Orden de SRCS.** `Makefile:23` y `:29`.
  - **Defecto:** `mod_audit` va antes que `mod_probe`, aunque ahora lo usa (`src/mod_audit.f90:37`).
  - **Por qué no rompe:** la regla `.o` explícita (`Makefile:101`) fija el orden de compilación.
  - **Escenario de fallo:** solo una compilación que siga SRCS sin las reglas `.o`; hoy ningún objetivo de make lo hace.
  - **Arreglo:** mover `mod_probe` antes de `mod_audit`. El reporte ya lo declara para un commit aparte.
- **B2. Marca de la E2 por `Su == 0`.** `src/mod_pressure_3d.f90:744-750`.
  - **Defecto:** la marca detecta bien las celdas de salida, pero el comentario «en ningún caso» es demasiado fuerte.
  - **Escenario de fallo:** en una celda activa con E2 distinta de 0 y Su anulado por cancelación exacta, la E2 sí entró a la ecuación y la marca la borra. V_pois queda sesgado. La probabilidad es prácticamente nula y la numérica no cambia.
  - **Arreglo:** usar la máscara de salida (`is_electrode` en k = nz) o rebajar el comentario.
- **B3 (PLAUSIBLE). `compare_audit --decomp`.** `tests/integration/compare_audit.py:88`.
  - **Defecto:** las columnas nuevas de cancelación (`_unl`, `_lk`, `err_liq`) no tienen piso de redondeo.
  - **Lo que falta:** solo se probó cold_10step n8→n4, sin líquido, donde valen 0.
  - **Escenario de fallo:** un banco con líquido reiniciado con otro número de ranks podría fallar rtol 1e-10 por el orden de la suma MPI, sin defecto real. El riesgo ya existía con `m_gas_err_multi`.
  - **Arreglo:** correr un `--decomp` con líquido, o añadir esas columnas a `ROUNDOFF_COLS`.
- **B4. Cobertura del fallback implícito.** `src/mod_continuity.f90:1691`.
  - **Situación:** el gancho del complemento en el fallback está verificado solo leyendo el código; ningún banco de los logs ejercita el fallback.
  - **Por qué no bloquea:** `mass_gas_rewrites` lo detectaría en cuanto un banco entre al fallback.

**Nota de proceso, no de código.** `reviews/r1-auditor-eaf3d.md` ya está staged con la revisión de un lanzamiento anterior. Guardar esta revisión en esa ruta la sobrescribe.

## 2. Verificado como correcto (no re-auditar)

**Identidad `d m_gas = comp + eos + volfix`**
- Cada sitio que escribe `gas%alpha` o `gas%rho` dentro del paso tiene gancho. Lo comprobé con `grep` de todas las escrituras:
  - complemento en `mod_continuity` :812, :1240 y :1691, con `ag_pre` capturado justo antes;
  - EOS en `mod_properties_3d:45`, con `rho_old`;
  - volfix: `ecs_feed:281`, `fields_3d:778`, `solid_phase:119`, `slag_3d:660/868`, `slag_chemistry:353`.
- Las escrituras de inicialización (heel, `slag_initialize`) y de cell_type 0 quedan fuera del inventario.
- La descomposición secuencial (α a ρ fijo, luego ρ a α fijo) es exacta por celda.
- Orden en `main_3d`: modo 0 justo tras `step+1` (:337), modo 1 tras el último `update_properties` (:795), y entre el modo 1 de un paso y el modo 0 del siguiente no hay escrituras de α_g ni ρ_g. `restart_read` llama a `update_properties` antes de que existan `mg_*`, así que no hace nada.
- **El check no pasa por la razón equivocada:** en test-full hay bancos con comp de hasta 3.89 kg y resto 2.5e-14. Un gancho que faltara se vería. En los logs no hay ningún FAIL fuera de los XFAIL.

**Halos y MPI**
- `ws_Fc_*` y `ws_Fc_lk_*` se intercambian (`mod_pressure_3d:815-820`); también `ws_Fg_lk` (:848) y `ws_Fr/Fth/Fz` (`mod_continuity:549`, `ws_Fz` tras el derrame :743).
- Por eso `lk_any`, `vp` y `ve` leen caras i-1, j-1 y k-1 válidas en la frontera de bloque. En la frontera física esos valores son 0 por el reset.
- `mg_comp*` y `mg_eos*` se anulan enteros. `mg_ag0` (mold) se escribe y se lee solo en celdas propias, así que no reaparece el Bug 22. `ws_pc_unl_used` se inicializa a 0 al asignarse.
- No hay dummies nuevos de array 3D.

**Sin estado nuevo entre pasos**
- `mg_*` se recaptura en cada modo 0.
- `ws_pc_unl_used` se anula en cada Poisson (:213) y lleva id de paso. `ws_lim_step` y `ws_pc_unl` también llevan id.
- No hace falta tocar el snapshot. Los reinicios con el mismo número de ranks del log son bit a bit, con 117 columnas.

**Semántica de V_pois y V_eff**
- Orden Poisson → transporte en cada pasada (`mod_multiphase:478` → `:507/510`). `ws_pc_unl_used` es exactamente lo sumado a Su:
  - se escribe junto con `Su += ws_pc_unl` (:652-653);
  - se anula en las filas inactivas o selladas (:672) y en las salidas o cell_type 0 tras las BC;
  - no hay `return` temprano en el cuerpo de `solve_pressure_correction`.
- Las validez se reinician por paso (`main_3d:576-578`). El fallback invalida `ws_flux_valid`, `ws_lim_step` y `ws_pc_unl`.
- La escoria condensada apaga `liq_ok`.
- La afirmación C-120 (`ws_Fg` = 0 donde `lk` = 0) es cierta: se resetea en :210 y se escribe solo con `lk` = 1 (:836-841).

**Sin cambio numérico**
- Ningún valor nuevo entra a la solución.
- Golden v131 con err rel 0 en test-quick y test-full.
- `opt_identidad.txt`: el sha del diff staged de `src/` (0503d1f6…) coincide con el actual, y el binario de `make opt` es idéntico byte a byte a `eaf3d_k7v5_opt`.
- `diff_sha` de `status.json` = sha de `git diff --cached -- src tests` (aac70f3a…). Los tests (20:15-20:30) son posteriores a la última edición de `check_audit.py` (20:12), y el árbol no tiene cambios fuera del staged en `src/` ni `tests/`.

**CSV, glosario y registro**
- Cabecera y escritura: 24 columnas nuevas en el mismo orden; el formato pasa a 200 repeticiones, suficiente para 114 valores.
- Contadores por paso: `LIQ_SKIP` y `E2_SKIP` solo en el rank 0; `CELLS_NOLINK` se suma entre ranks.
- Las 24 columnas tienen entrada en `DEFS` y en `docs/AUDIT_COLUMNS.md`. Las descripciones coinciden con el código: `comp_abs` y `eos_abs` son «por llamada» (`mg_*_abs += abs(dm)`).
- `ledger.jsonl` solo añade líneas (47 añadidas, 0 borradas).

**check_audit**
- `mass_gas_rewrites` está dentro de la rama `elif "m_gas_out"`, donde existen `dm_g` y `m_fix`.
- La familia err_liq solo se evalúa sin `m_gas_cells_skip` y en filas con `liq_skip` = 0. Da n/a con escoria legada o con Σ|e| multifase = 0.
- No hay divisiones por cero (`eam > 0` en la rama que divide; `_corr` tiene piso de 1e-300).

## 3. Orden sugerido (uno por uno, ninguno bloquea el cierre)
1. B1: orden de SRCS (commit aparte, sin cambio de binario).
2. B2: marca de la E2 por la máscara de salida (verificación bit a bit de la numérica y de las columnas k7v5).
3. B3: `compare_audit --decomp` en un banco con líquido.
4. B4: banco o test unitario con fallback implícito y audit.
