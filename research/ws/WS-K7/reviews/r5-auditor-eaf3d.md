## Revisión r1 del auditor-eaf3d: WS-K7, diff staged (quinto ciclo)

**Veredicto: RECHAZA**, por una objeción MEDIA (M1) en el checker. El instrumento Fortran y la identidad `mass_gas_rewrites` están bien.

### Hallazgos

#### MEDIO

**M1. `mass_gas_err_liq_split` pasa siempre, y los INFO de K7 dan una lectura falsa con escoria condensada.**
- Archivos: `tests/integration/check_audit.py:356-410` (check en :394, AVISO en :386) y `src/mod_audit.f90:1013, 1086`.
- **El check no puede fallar.** En el Fortran, `el_lk = el - el_unl` y las tres columnas se acumulan con los mismos `el` y `el_unl`, así que la identidad `err_liq_all = lk + unl` se cumple por construcción. No detecta ningún defecto del reparto. Ejemplo: con `pc_spill_source = true` el derrame sale de `_lk` (se cancela entre `ws_Fz` y `unl_vol`, mod_continuity.f90:673/678) y el check sigue en PASS.
- **Está vacío en la mitad de los bancos.** Re-ejecuté check_audit sobre `tests/out`: de los 66 bancos donde pasa, en 34 las tres columnas valen 0.
  - 22 son de escoria condensada: `liq_ok` = false en todos los pasos (`m_gas_liq_skip` = número de pasos).
  - 12 no tienen líquido: cold_10step*, outer_conv_n8, cold_bucket2_n4.
- **Lectura falsa en los 22 bancos de escoria condensada.** Ejemplo: `python3 tests/integration/check_audit.py tests/out/arc_melt_slag_n4` imprime:
  - en `mass_gas_cells_liq`, «err_liq explica 1.000 por celda» y «sum|e - err_liq_all| 0.000e+00 = 0.000 de sum|e|». Según el criterio de C-121 (≤ 0.3) eso se lee como H soportada, aunque err_liq nunca se evaluó;
  - en `mass_gas_cells_net`, corr(e − err_liq_all, e) = +1.000;
  - en `mass_gas_cells_e2`, «0.000 de sum|e| sin gas».
- **El AVISO da la causa equivocada.** Dice «pasos sin flujos del liquido validos», pero los flujos son válidos: lo que pasa es que el instrumento se apaga con escoria condensada.
- **Cómo lo usan el reporte y el ledger.** El reporte («Tests» del quinto ciclo) y C-145 citan «mass_gas_err_liq_split PASS (66 bancos)» como prerrequisito cumplido. No aporta información.
- **Arreglo:**
  1. Dar SKIP o «n/a» cuando `m_gas_liq_skip` cubre todos los pasos, o filtrar las filas con `m_gas_liq_skip == 0`. Aplicarlo al split, a los cocientes y a las correlaciones.
  2. Que el AVISO nombre la escoria condensada.
  3. Para el split, una de dos: dejarlo como INFO declarado «identidad por construcción», o volverlo independiente acumulando en Fortran `el_lk` directamente por caras enlazadas, ρ_g·dt·Σ_lk(ws_Fc − F/ρ_l) + derrame.
  4. Corregir el glosario de `m_gas_liq_skip` para que incluya la escoria condensada.
  5. Registrar un evento en el ledger con `--ref C-145` y corregir el reporte: de los 66 bancos, 32 tienen datos y 34 están vacíos.
  6. Pasar `make test-quick`.

#### BAJO

**B1. El glosario de `_unl` y `_lk` está mal en dos casos.**
- Archivos: `scripts/make_audit_glossary.py:243` y la entrada de `_lk`; también `docs/AUDIT_COLUMNS.md`.
- «0 when the outer loop converges» es falso donde el Poisson descarta la E2 (celda inactiva, sellada o de salida). Ahí `ws_pc_unl_used` = 0, así que el_unl = −ρ_g·dt·unl(N) con cualquier grado de convergencia.
- «_lk … plus spill» es falso con `pc_spill_source = true`.
- Sin efecto en k7: el derrame está apagado y la clase nolink está vacía a 280 s.

**B2. Comentarios y regla que ya no coinciden con el código.**
- `src/mod_audit.f90:222-224` y `:1050-1052` dicen que la E2 entra a V_pois donde `lk_any`, pero el código usa `ws_pc_unl_used` (:1078). `lk_any` solo define la clase nolink.
- `.claude/rules/transporte-energia.md:196-199` conserva la frase de C-135 sobre `lk_any`, que contradice el párrafo de la «forma reducida» que viene después.

**B3. Orden de `SRCS` en el Makefile (ya declarado como B-1).** `mod_audit` va antes que `mod_probe` aunque lo usa. Compila porque las reglas `.o` explícitas fijan el orden. Queda para el commit aparte anunciado.

### Lo que verifiqué y está bien (no hace falta re-auditar)

- **Identidad `mass_gas_rewrites`.**
  - Recorrí todas las escrituras de `gas%alpha` y `gas%rho` en `src/`. Los 3 sitios del complemento llevan `audit_comp_cell` y la EOS lleva `audit_eos_cell`. Las demás reescrituras pasan por volfix con `audit_volfix_cell`: ECS, cesta > 1, `enforce_volume_constraint`, sort y flotación de escoria, `slag_chemistry`.
  - Las escrituras de inicialización corren antes del audit, y `cell_type 0` queda excluida a la vez de `m_gas` y de las sumas.
  - Orden en main_3d: modo 0 en l.337, último `update_properties` en l.790, modo 1 en l.795. No hay reescrituras entre el modo 1 y el modo 0 del paso siguiente.
  - Re-ejecución sobre `tests/out`: 78 bancos, 0 FAIL.
- **E2 aceptada (`ws_pc_unl_used`).**
  - Se anula en cada Poisson, se escribe solo donde la E2 entra a `Su`, y se pone en 0 en celdas inactivas o selladas y donde las BC dejan Su = 0 (salida y cell_type 0).
  - Nada toca `Su` entre ese barrido y el CG, y solo la lee el audit: la numérica no cambia.
  - Con `n_pc_max > 1`, `used` corresponde al último Poisson.
- **Semántica del reparto.** `liq%rho` es constante sin escoria y `unl_vol` usa los mismos Fw..Ft que `ws_Fr`. Con eso, `_lk` son las caras enlazadas más el derrame cuando `pc_spill_source` = false, y la lectura del 99.9 % en caras enlazadas es consistente con el código en k7.
- **Conducto α de cara media del gas.** `af = 0.5·(aef + aef_nb)` con `aef = gas%alpha`, y `face_lim` devuelve 1 para el gas.
- **Halos y MPI.** Las caras i-1 vienen de arrays con halo intercambiado, las sumas son de celdas propias, los contadores se cuentan en el rank 0 y se reduce con `allreduce_sum`.
- **Otros puntos.**
  - Bug 22 y dummies: correctos.
  - Snapshot de reinicio: no hay estado nuevo que deba entrar.
  - Escoria condensada: `liq_ok` la excluye.
  - CSV: encabezado y write tienen el mismo orden, con 114 datos frente a un formato de 200 repeticiones.
  - Logs: unit, quick y full OK.
  - El árbol de trabajo coincide con lo staged y el binario es posterior a las fuentes.
  - El ledger solo añade líneas.
  - En el paso 280059 no hay celdas con α_g de nivel de redondeo.

### Orden sugerido de corrección

1. **M1:** check_audit (SKIP o n/a, AVISO, split como INFO o independiente), glosario de `m_gas_liq_skip`, reporte y ledger (`--ref C-145`), y `test-quick`.
2. **B1:** textos del glosario y regenerar `AUDIT_COLUMNS.md`.
3. **B2:** comentarios de `mod_audit` y la frase de la regla.
4. **B3:** commit aparte, solo del Makefile.
