## Revisión WS-K11, ronda 1 (auditor-eaf3d)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Quedan cuatro objeciones BAJO, ninguna bloqueante; B1 conviene corregirla antes del commit.

**Datos sensibles:** ninguno. Solo campos de simulación y rutas del repo.

**Alcance del diff staged:**
- No toca `src/` ni `tests/`.
  - `diff_sha` es el sha256 de la cadena vacía, coherente con `numerico: false`.
- Lo staged es:
  - `.claude/rules/transporte-energia.md`
  - la entrada C-239 de `research/ledger.jsonl`
  - `report.md`
  - `status.json`
  - copias de revisiones del ciclo 1 (no leídas, porque la revisión es ciega)
- Los scripts de medida (`research/ws/WS-K11/scripts/h15.py` y `medir_centinela.py`) no cambiaron desde el commit de pre-registro `424a70d`.
  - `git status` los da limpios.
  - Por eso la medida de H15 es la pre-registrada.

### Hallazgos

**ALTO:** ninguno.

**MEDIO:** ninguno.

**BAJO**

1. **B1. Cuartos de k10b_dt025 mal copiados** (`research/ledger.jsonl`, C-239; `research/ws/WS-K11/report.md` §9 «Lectura»).
   - Ambos dicen 31, 21, 32 y 33. Con `h15.py` sale 31, 21, 32 y 36, tanto con el corte n//4 como con 58/58/58/61.
   - Esos cuartos suman 120, que es el 120/235 del propio Resultado; 31+21+32+33 suman 117.
   - El reporte se contradice en sí mismo (§9 frente a Resultado).
   - El veredicto no cambia: es una lectura, fuera del criterio de C-238.
   - **Arreglo:** cambiar 33 por 36. La línea del ledger aún no tiene commit, así que se puede corregir ahí mismo.

2. **B2. «Casi todos» exagera para el snapshot de 280 s** (`.claude/rules/transporte-energia.md`, bloque OJO).
   - Desde `judge_otp_280/eaf3d_00280000.h5` con 0.25 ms son 120/235 pasos (51 %).
   - Solo el brazo B, que parte de otro snapshot, tiene 235/235.
   - **Escenario:** un agente que lea la regla esperaría que casi todos los pasos estuvieran altos en un banco desde 280 s.
   - **Arreglo:** dar las dos cifras.

3. **B3. Las claves no «pasaron» a ON: nacieron en ON** (`report.md` §6).
   - `2f0529b` y `8f568fc` crean las claves ya en ON: en `src/mod_config_3d.f90` solo hay líneas `+`.
   - `scrfh_b` usó `pc_transport_f28` el 20-oct, antes de que existiera en git. Eso refuerza la salvedad del reporte sobre su binario.
   - **Arreglo:** corregir la frase.

4. **B4. Disparador identificado, mecanismo no** (observación; ya consta en C-237 (b) y (c)).
   - No se sabe por qué a 0.25 ms el régimen alto no decae, cuando a 1 ms se asienta en unos 20 ms.
   - Tampoco qué clave pesa a 0.25 ms, ni de dónde vienen los 450 kPa con las claves ya establecidas.
   - El reporte lo declara abierto, así que no bloquea.

### Verificado como correcto (no re-auditar)

**Configuración de los brazos**
- El `diff` de config de A frente a `k10b_dt025` solo cambia las dos claves (de true a false) y `output_dir`.
- El de B frente a `k10b_dt025` solo cambia `restart_file` (`judge_fh_275/eaf3d_00290000.h5`), `t_final` (290.06) y `output_dir`.
- Los tres corren con el ejecutable `campaigns/bin/eaf3d_k10b_opt`, según el run.log.

**Medida de H15**
- Ejecuté `h15.py`: brazo A sin pico (69.4 m/s, 15 kPa, 0 pasos altos); brazo B con pico (300.0 m/s, 342 kPa en 2-10; 365 kPa en 290020; cuartos 58, 59, 59 y 59). Resultado: SOPORTADA, con 0 `[CG] AVISO` en los dos brazos.
- `check_audit`:
  - A no tiene ningún FAIL.
  - B falla sentinel_gas y regime_gas.
  - k10b_dt025 falla sentinel_gas, regime_p (591.6 kPa) y regime_gas.
- Las identidades de masa del gas (`mass_gas*`, `flux_closure`, `class_split`, `decomp`, `eos_end`) pasan en los dos brazos.
- Los tres audit.csv (A, B y k10b_dt025) tienen 236 filas contiguas, sin huecos. Por tanto `r[1:]` excluye exactamente el paso 1.

**Aislamiento**
- El contraste limpio es A frente a `k10b_dt025`: mismo snapshot, mismo binario y misma config salvo las claves.
- El snapshot de B, el de 280 s y el reescrito por `judge_otp_280` tienen el mismo conjunto de datasets HDF5. No falta ningún `/restart` que el lector actual tuviera que inventar, así que B no lleva ese confusor.
- Las claves no tienen estado persistente fuera del snapshot:
  - f28 congela el hueco en `liq_old%alpha` (`src/mod_multiphase.f90:139-147`).
  - La presión total de salida actúa sobre `sh%p`, que se guarda en `fields/pressure` (`src/mod_pressure_3d.f90:1001`).
- `judge_fh_275` (20-oct) corrió sin las claves porque aún no existían en git.

**Tablas del reporte**
- §7: `m203_280` y `m21f1_280` reproducen a `judge_otp_280` con 4.83e-6; `k10_base` con 6.1e-12 en 11 pasos. Los valores 126.5/50.3 y 215.0/83.5 coinciden, igual que `scrfh_b` (160.0/65.3, 189.8/62.0) y `scrfh_base` (71.9/14.8).
- Resultado:
  - `k11_dt025_s290` llega a 450.0 kPa en 290093 (128.6 m/s) y a 344.3 kPa en 290074, con 5/235 pasos altos.
  - `k11_dt05_s290` llega a 70.6 kPa y `k11_mo20_s290` a 70.0 kPa.
  - `k11_base_s290` da u_gas_max 106.9 m/s y p_max 27.1 kPa, tiene 1 `[CG] AVISO` y falla `energy_balance`.
- Los u_gas_max ≥ 200 m/s de `k10b_dt025` están en 280003, 280004, 280007, 280011, 280041 y 280137.
- «Con 1 ms dura ~20-25 pasos» es razonable: en `k10b_mo20` y `judge_otp_280`, p_max baja a unos 25 kPa hacia el paso 20-22. Queda luego una alternancia de periodo 2 por encima de la línea base sin claves.

### Orden sugerido de corrección

1. B1: corregir el número en C-239 y en report.md antes del commit.
2. B2: dar las dos cifras en la regla.
3. B3: corregir la frase de §6.
4. B4: abrir un WS de seguimiento para C-237 (b) y (c), con un brazo de solo f28 a 0.25 ms desde 280 s.
