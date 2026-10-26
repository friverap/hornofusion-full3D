# Revisión ronda 1, auditor-eaf3d (WS-K7, código del diff staged)

**Veredicto: RECHAZA.** El código de `src/` y `tests/` es correcto. No encontré defectos ALTOS ni MEDIOS en Fortran ni en el checker. Rechazo por un solo hallazgo MEDIO: la regla `.claude/rules/transporte-energia.md`, que va en el mismo diff, contradice el registro y el propio código. Se arregla editando texto, sin código ni corridas.

Diff revisado: `git diff --cached -- src tests` sha256 efa2d14…a6c599fe, igual al `diff_sha` de status.json. El diff de `src/` da 0503d1f6…, igual al de `logs/opt_identidad.txt`.

## Hallazgos

### MEDIO

**M1. La regla conserva una lectura retirada y una descripción falsa del checker** (bloqueante).

- **Lectura retirada.** `.claude/rules/transporte-energia.md:175-177` dice: «el neto multifase −8.55e-4 es el ~20 % residual de esa cancelación, dentro de los sesgos del estimador (~30 % por subconjunto)».
  - {C-150} R3 y el reporte la retiran: report.md:179 «NO es el residuo de una cancelación a resolver con más precisión»; report.md:264 «no es 'el residuo de esa cancelación'».
  - La misma regla dice lo contrario en :204-207 (la exportación se cancela por construcción y el piso vive en Δm_multi y en la frontera).
  - Sobre sus propias cifras también es falsa: +3.45e-3 − 2.96e-3 = +4.9e-4, de signo opuesto a −8.55e-4.
- **Descripción falsa del checker.** `:216-218` dice «sin líquido en movimiento `check_audit` imprime n/a».
  - El código, `tests/integration/check_audit.py:374-383`, imprime «H explica 0.000». Lo comprobé ejecutándolo sobre `tests/out/cold_10step_n4`.
  - La propia regla lo dice bien en :243-244.
- **Por qué importa.** El reporte (ronda 11) dice que la regla quedó limpia de formas retiradas, y eso no se cumple. Una sesión futura que edite mod_audit o mod_continuity carga esta regla y hereda la lectura retirada.
- **Arreglo.** Reescribir las dos frases con la forma de C-150 y comprobar con grep.

### BAJO

- **B1.** `tests/integration/check_audit.py:358-362`: el comentario dice que sin líquido «los cocientes no se imprimen (antes daban ... '0.000' sobre ceros)». El código de :374-383 imprime 0.000, que es lo correcto según C-150. Solo hay que alinear el comentario.
- **B2.** En el orden de `SRCS` del Makefile, mod_audit y mod_properties_3d van antes que mod_probe. Ya está declarado y diferido (ronda 8 B-1). Compila gracias a las reglas .o explícitas (:101, :110). No encontré escenario de fallo. Va en un commit aparte.
- **B3 (PLAUSIBLE).** `compare_audit.py` no tiene piso de redondeo para las columnas nuevas que en régimen son puro ruido: `m_gas_veff_abs_nogas` ≈ 1e-16, `m_gas_err_liq_unl` con la E2 convergida y `m_gas_cells_nolink`.
  - Un reinicio `--decomp` multifase fallaría en esas columnas. Hoy solo hay reinicios `--decomp` fríos, sin líquido.
  - No está reproducido; falta un banco multifase con `--decomp`.

## Verificado correcto (no re-auditar)

1. **Numérica intacta.**
   - Fuera de mod_audit, el diff solo escribe variables locales (`ag_pre`, `rho_old`) y `ws_pc_unl_used`. Según grep, ese array solo lo lee `src/mod_audit.f90`.
   - En `logs/test_full.txt`, el golden v131 da error relativo 0.
   - `make opt` produce el mismo sha256 que `campaigns/bin/eaf3d_k7v5_opt`, según el log.
   - El sha del diff de src coincide con el de ese log.
   - Los tests corrieron después de la última edición de src/tests (src 16:57, check_audit 18:14:49; tests 18:19 y 18:33).
2. **La identidad `mass_gas_rewrites` está completa.**
   - Reescrituras de α_g dentro del paso:
     - los tres complementos de mod_continuity (:808, :1237, :1687) llevan gancho;
     - ECS, charge_scrap, solid_phase, slag_chemistry, slag_buoyancy y slag_condensed_sort pasan por volfix con `audit_volfix_cell`;
     - las de mod_slag_3d:134-171 y mod_fields_3d:399-510 son de la inicialización;
     - en cell_type 0, α_g = 0 queda fuera de m_gas y fuera de la suma.
   - Reescrituras de ρ_g: solo `update_properties`. Las llamadas de restart e init ocurren antes del primer modo 0, cuando mg_eos aún no está asignado.
   - El producto telescopa exacto, porque cada ruta cambia solo α o solo ρ.
   - Entre el modo 1 (main:795) y el modo 0 del paso siguiente (main:337) nada toca el gas.
   - m_gas y los ganchos suman el mismo conjunto de celdas: propias con cell_type ≠ 0.
   - Comprobado ejecutando el checker: arc_melt_slag_n4 da resto −5.7e-13 con escoria condensada; cold_10step_n4 da −5.7e-13.
3. **`ws_pc_unl_used`.**
   - Se anula al empezar cada Poisson (:212).
   - Se escribe donde la E2 entra a Su (:653).
   - Vale 0 en celdas selladas o inactivas (:672) y donde Su = 0 tras las condiciones de borde (salida y cell_type 0, `apply_pressure_bc`).
   - Lleva `_valid` e id de paso; `probe_set_step` se llama en cada paso (main:566), antes del SIMPLE.
   - Con una sola externa la E2 no se acepta (el id es del paso anterior), así que `el_unl = −ρ dt unl(N)`, como documenta el glosario.
4. **«Sin cara enlazada» implica fila sellada o inactiva, y por tanto E2 usada = 0.** lk solo se marca cuando se suma a_nb > 0: pasada del líquido con export, pasada del gas con isg, y caras de superficie libre.
5. **Halos y frontera de bloque.**
   - Arrays de cara:
     - `ws_Fc*`/`ws_Fc_lk*` y `ws_Fg*`/`ws_Fg_lk*` se anulan en cada Poisson e intercambian halos (pressure :816-821 y :845-850);
     - `ws_Fr/Fth/Fz` se ponen a 0 en cada transporte (continuity:339) y se intercambian en :549-551 y :743;
     - en la frontera física las caras de halo valen 0.
   - Arrays por celda del audit:
     - `mg_*` se asignan con mold; comp, eos y sus _abs se anulan enteros;
     - `mg_ag0` solo se escribe y se lee en celdas propias (sin riesgo del Bug 22);
     - ninguno es un dummy de array.
6. **Sin estado persistente.**
   - Todo vale dentro del paso, controlado por id.
   - Los 16 `[audit-restart]` de test_full comparan las 117 columnas bit a bit.
7. **Unidades y derrame.**
   - Unidades: ws_Fc es volumétrico; ws_Fr es masa y se divide por el ρ_l de la celda, igual que en el transporte.
   - Derrame: entra en ws_Fz siempre y en unl_vol solo con `pc_spill_source`, lo que cuadra con el glosario de `_lk`.
   - Con `pc_drift_source = false` el reparto no se hace, y el glosario lo declara.
8. **Evaluación y formato.**
   - `liq_ok` se apaga con escoria condensada.
   - Los contadores LIQ_SKIP y E2_SKIP solo los suma el rank 0.
   - Cabecera y fila escriben 117 columnas, con formato `200(...)`.
   - El glosario cubre las 117 columnas.
9. **check_audit.**
   - La familia err_liq solo usa filas con `m_gas_liq_skip` = 0.
   - Imprime n/a sin filas evaluadas, por ejemplo arc_melt_slag_n4.
   - Las divisiones están protegidas contra cero.
   - La tolerancia escala con Σ|dm| por llamada.
   - El bloque de rewrites está dentro de la rama con `m_gas_out`, donde `dm_g` y `m_fix` están definidos.
10. **Cifras recalculadas desde los CSV de k7v5.**
    - mo20: rem_all/abs 0.3186; con filtro 0.5651; neto 1.5705; lk +4.977e-4; unl −9.58e-6; unl_abs/abs 0.0013; V_pois nogas 4.078e-3; V_eff nogas 1.09e-16; rej 7.655e-3; nogas 4.816e-3; resto de rewrites −6.15e-14.
    - base: 0.4038, 0.6263, 1.3196 y −7.08e-14.
11. **Líneas y script.**
    - Las líneas citadas en report.md:289 coinciden: pressure :210/:652/:671-672/:784/:1203…:1405/:1260/:1747; audit :899/:909/:1036/:1045/:1053/:1078/:1086; check_audit :451; continuity :418-421 y :1014-1037.
    - `nogas_vecinas.py` es coherente con `gas_cell_class` (el recuento es un superconjunto, como se declara).

## Orden sugerido de corrección

1. M1: reescribir la regla en :175-177 y :216-218, y verificar con grep.
2. B1: alinear el comentario de check_audit.py:358-362, sin cambiar el comportamiento.
3. B2: commit aparte del Makefile tras cerrar el WS.
4. B3: solo si se añade un reinicio `--decomp` multifase.
