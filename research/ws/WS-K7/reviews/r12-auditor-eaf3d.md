# WS-K7, panel de cierre ronda 1: auditor-eaf3d (revision del codigo del diff staged)

**Veredicto: APRUEBA.** No encontre defectos ALTO ni MEDIO en el codigo. Quedan tres BAJO no bloqueantes.

Alcance: el codigo del diff staged (`git diff --cached`) contrastado con `research/ws/WS-K7/report.md`. Archivos revisados: `src/mod_audit.f90`, `src/mod_continuity.f90`, `src/mod_pressure_3d.f90`, `src/mod_properties_3d.f90`, `src/mod_workspace.f90`, `Makefile`, `tests/integration/check_audit.py`, `scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md` y los scripts de `research/ws/WS-K7/scripts/`. No lei las revisiones de otros revisores. No compile ni ejecute nada; solo lei archivos y corri python3 sobre CSV y logs que ya existian.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B1. Orden de `SRCS` en el Makefile (`Makefile:23` y `Makefile:29`).**
- Defecto: `mod_audit.f90` aparece antes que `mod_probe.f90`, y mod_audit ahora usa mod_probe (`src/mod_audit.f90:37`). Esto viola la convencion de CLAUDE.md de mantener `SRCS` en orden topologico.
- Escenario de fallo: hoy no hay ninguno, porque la regla explicita `Makefile:101` (`mod_audit.o: ... mod_probe.o`) fuerza el orden correcto. Si un cambio futuro quitara esa dependencia, una compilacion desde cero fallaria al no encontrar `mod_probe.mod`.
- Arreglo: mover `mod_probe.f90` antes de `mod_audit.f90`. mod_probe solo depende de constants, types, parallel_utils y mpi_topology, asi que no hay ciclo.

**B2. Comentario de `m_gas_e2_nolink` (`src/mod_audit.f90:259-262`).**
- Defecto: el comentario dice «cuanta fuente E2 descarto ahi el Poisson … el peso real del sesgo M1». El codigo (`:1067-1069`) usa la E2 del transporte N, pero el Poisson vio la del N-1.
- Consecuencia: el glosario ya la marca como aproximacion y el comentario del codigo no, asi que quien lea solo el codigo la tomara como exacta.
- Arreglo: alinear el comentario con el glosario.

**B3. Marca `Su == 0` en `src/mod_pressure_3d.f90:743-750`.**
- Defecto: el codigo da por hecho que Su = 0 implica que la E2 no entro. Si la E2 se acepto y cancela exactamente al resto de Su, la celda se marca como descartada y `err_liq_unl` cambia de rama.
- Impacto: el caso tiene medida nula y no afecta a la numerica; solo es imprecisa la frase del comentario «no evacua nada en ningun caso».
- Arreglo: precisar el comentario o marcar el descarte dentro de `apply_pressure_bc`.

## 2. Verificado como correcto (no re-auditar)

- **La numerica no cambia (bit a bit).**
  - Las cinco comparaciones `[metrics]` contra `metrics_v131.json` (rtol 1e-12) dan `err rel 0.000e+00` en todos los bancos de los logs quick y full.
  - El golden no cambia desde el 22 de octubre.
  - Los cambios en `src/` solo escriben arrays del audit. `ws_pc_unl_used` no lo lee ningun solver.
  - No hay diff sin stage en src, tests ni scripts, y el sha256 del diff staged de `src/` es `0503d1f6…`, el mismo de `logs/opt_identidad.txt`.
- **La identidad `mass_gas_rewrites` cubre todas las escrituras de alpha_g y rho_g dentro del paso.**
  - Hice grep de todas las asignaciones a `gas%alpha` y `gas%rho` en `src/`. Dentro de la ventana entre el modo 0 (`main_3d.f90:337`) y el modo 1 (`:795`), cada escritura en celdas propias con `cell_type /= 0` lleva su gancho:
    - complemento: `mod_continuity.f90:812`, `:1240` y `:1691`;
    - EOS: `mod_properties_3d.f90:45`;
    - volfix: ECS, `charge_scrap`, `solid_phase`, `slag_3d:660/868` y `slag_chemistry:353`.
  - Las escrituras sin gancho quedan todas fuera del balance, por una de estas razones:
    - son de inicializacion antes del lazo (`slag_initialize`, `init_heel`, `fields_initialize_all`);
    - fuerzan alpha = 0 en celdas `cell_type 0`, que el inventario (`mod_audit.f90:592`) y la suma (`:992`) excluyen por igual;
    - son intercambios de halo.
  - No existe ninguna copia completa ni rollback del tipo `gas`.
  - Entre el modo 1 de un paso y el modo 0 del siguiente nada reescribe alpha ni rho.
  - La identidad es exacta: el complemento cambia alpha con rho fija y la EOS cambia rho con alpha fija.
- **Residuos de la identidad recalculados** desde los `audit.csv` existentes:
  - k7v5_mo20: −6.1e-14 kg;
  - k7v5_base: −7.1e-14 kg;
  - k7v4_long (5499 pasos): −3.2e-14 kg, que coincide con la cifra de la regla;
  - test_full: 67 lineas PASS en 67 directorios con columna de audit, entre ellos los bancos con escoria, ECS, mezcla, carga de cesta y reinicio.
- **MPI, halos y frontera de bloque.**
  - `ws_Fc_*` y `ws_Fc_lk_*` (`mod_pressure_3d.f90:817-822`), `ws_Fg_*` (`:844-849`) y `ws_Fr/Fth/Fz` (`mod_continuity.f90:549-551`, mas `ws_Fz` tras el derrame en `:743`) se intercambian por halos. Asi la cara `i-1` de la primera celda propia es la del rank vecino.
  - Lo comprobe con datos: `bed_drain` n1 frente a n4 y n12, `bath_freeze` n1 frente a n9, `bath_test` n1 frente a n4 y n12, `cold_10step` n1 frente a n8 y n12, y `arc_slag` n1 frente a n12. Todas las columnas nuevas coinciden hasta 1e-9 relativo, o hasta redondeo de trayectoria. La excepcion es `m_gas_rej_nogas`, con 1.4e-4 relativo, pero sobre 1e-13 kg absolutos y sensible a la trayectoria.
- **Bug 22 y dummies.** `mg_comp`, `mg_eos`, `mg_comp_abs`, `mg_eos_abs` y `ws_pc_unl_used` se anulan enteros. `mg_ag0` se escribe y se lee solo en celdas propias. No se agregan dummies de array.
- **Snapshot de reinicio.** Los arrays `mg_*` se recapturan en el modo 0 de cada paso, y `ws_pc_unl_used` es valido solo dentro del paso, controlado por `_id == probe_current_step()`. `probe_set_step(step)` se llama sin condicion en `main_3d.f90:566`. Las 11 comparaciones `[audit-restart]` (117 columnas, incluidas las 24 nuevas) pasan con tolerancia 1e-12 o 1e-10, entre ellas `bed_drain_s150` y `bed_flood_s750`, que tienen liquido.
- **CSV.** El encabezado y el `write` agregan las mismas 24 columnas en el mismo orden. El formato `200(...)` alcanza. `acc(1:N_AUD)` se reduce por MPI completo (`:641`). Los contadores por paso solo los suma el rank 0.
- **Validez de E2.** `ws_pc_unl_used` solo toma `ws_pc_unl` donde el Poisson lo sumo a `Su` (`:650-654`). Se anula en filas inactivas o selladas (`:672`) y en las celdas de salida o `cell_type 0`, donde `apply_pressure_bc` pone `Su = 0` (`mod_boundary_3d.f90`, lineas relativas 44 y 62). Entre `:209` y `:851` no hay `return` temprano, y `ws_Fg_valid` se fija despues de `ws_pc_unl_used_valid`. Por eso `m_gas_e2_skip = 0` se cumple por construccion, como declara el glosario.
- **Dependencias del Makefile.** `mod_properties_3d.o` ahora depende de `mod_audit.o` y `mod_audit.o` de `mod_probe.o`. No se forma ningun ciclo: `mod_audit` no usa `mod_properties` y `mod_probe` no usa `mod_audit`.
- **Checker.**
  - El bloque `mass_gas_rewrites` esta dentro de `elif "m_gas_out" in last`, donde ya existen `dm_g` y `m_fix`.
  - El bloque `mass_gas_cells_liq` solo corre si `nskip == 0`.
  - La familia err_liq se evalua solo en filas con `m_gas_liq_skip == 0`.
  - La escoria legada da n/a. Recalcule `rem_all/abs` = 0.319 y err_liq −2.966e-3 frente a `_all` +4.881e-4 = lk + unl en k7v5_mo20.
  - Los mensajes de err_liq son INFO y no pueden aprobar nada por la razon equivocada.
- **Formula err_liq.** `vp` es volumetrico (ws_Fc y la E2 en m3/s) y `ve` es masa entre `liq%rho`, que es constante (`update_properties`). `ws_Fr` es el flujo promediado en el tiempo de los subpasos (`mod_continuity.f90:506-508`). `el_lk := el − el_unl` es una identidad por construccion, como declaran el reporte y el glosario.
- **Scripts de investigacion.** La clase multifase de `nogas_vecinas.py` (cualquiera de al, asl, as >= 1e-2) coincide con `gas_cell_class` (ALPHA_FLOW_CUTOFF).
- **Tests.** Los logs `test_quick` y `test_full` terminan en OK y `test_unit` tiene 47 PASS. Los XFAIL estan listados.

Fuera de alcance: no verifique cada cifra narrativa del reporte. Eso corresponde al revisor de evidencia. Las que si recalcule coinciden.

## 3. Orden sugerido de correccion (uno por uno, ninguno bloquea)

1. B1: orden de `SRCS`. Es la unica con consecuencia posible en la compilacion.
2. B2: comentario de `m_gas_e2_nolink` en `src/mod_audit.f90:259-262`.
3. B3: comentario o marca de descarte de E2 en `src/mod_pressure_3d.f90:743-750`.
