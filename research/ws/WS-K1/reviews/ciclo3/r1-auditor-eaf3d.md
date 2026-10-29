## Revisión: auditor-eaf3d, WS-K1, ronda 1

**Veredicto: RECHAZA.** Hay dos hallazgos MEDIO, los dos en el texto permanente: la entrada de `.claude/rules/acople-pv.md` y el §6 del plan.

**Alcance.** El diff staged no toca código ni ninguna ruta con compuerta: no hay `src`, `tests`, `scripts/research` ni `.claude/hooks`. `diff_sha` es el sha256 de la salida vacía, como corresponde. Los cambios son de reglas, plan, reporte y status. Por eso revisé las afirmaciones del reporte y las del texto permanente contra el código, los parches, los `audit.csv` y el registro.

### Hallazgos

**MEDIO, M1: el inciso (a) de C-025 no prueba que el ciclo desapareciera, y se usa como si lo probara.**
- Dónde: `research/ws/WS-K1/report.md`, punto 4 e Incertidumbre; `.claude/rules/acople-pv.md`, en «Plan K CERRADO» («Su inciso de ciclo (a) PASÓ»); `docs/PLAN_K_limitador_en_poisson.md` §6.
- Defecto: osc2 es una mediana (`scripts/diag/cell_series.py:46`), así que no ve un ciclo que ocupe menos de la mitad de la ventana. El veredicto C-028 lo advierte con la frase «cumple solo en la mediana». Los tres textos omiten esa salvedad y presentan (a) como contrapeso de «sigue ciclando».
- Lo medido en k1b_342, sonda (10,60,2), pasos 342500–342560:

| Brazo | Puntos con \|d2p\| > 1000 Pa | p75 | Máximo | Mediana |
|---|---|---|---|---|
| k1b_342 | 47 % | 14.6 kPa | 219 kPa | 885.8 Pa |
| k1_342 / k1pa_342 | 22 % | ≈ 0.7 kPa | ≈ 3.7 kPa | ≈ 342 Pa |

- Escenario de fallo: quien retome el Plan K y lea la regla concluye que el tope exacto pasó su criterio de ciclo, cuando lo pasó por 3 puntos de fracción y con una métrica que no ve ese ciclo.
- Arreglo: añadir en los tres sitios «pasa por la letra, solo en la mediana (C-028); 47 % de los pasos > 1000 Pa frente a 22 % de k1 y k1pa». Dejar de usarlo como contrapeso.

**MEDIO, M2: la regla repite una afirmación que el registro ya retiró.**
- Dónde: `.claude/rules/acople-pv.md`, entrada «Plan K CERRADO», viñeta del juez C-041.
- Defecto (i): dice «pegado a la centinela de 2 MPa 183 pasos seguidos». Son 183 pasos seguidos con p_max ≥ 1 MPa, y solo 122 en 2.0e6 (C-311; lo reconté).
- Defecto (ii): dice «Lo que separa a K es quedarse pegado al tope». C-312, con la errata C-313, concluye que «no hay prueba de que el pegado sea propio de K». Lo verifiqué: desde el mismo estado `diag_k15d/eaf3d_00345310.h5`, el brazo sin K (`diag_k15_k_off`, `pc_alpha_implicit = false`) queda ≥ 1e6 en los 10 pasos medidos (345311–345320, de 2.0e6 a 1.80e6).
- Escenario de fallo: un juez futuro toma «pegarse al tope» como la firma de K.
- Arreglo: escribir «183 pasos seguidos ≥ 1 MPa (122 en 2 MPa)» y sustituir la frase por la lectura de C-312/C-313: el pegado no está probado como propio de K y ninguno de los dos brazos es un control limpio.

**BAJO, B1.** La fuente de Incertidumbre dice «(solo k1_340 llega a 346 s)». Es falso al pie de la letra: `f231_340` y `npc3_340` también llegan a 346000. Basta con escribir «entre las variantes de Plan K».

**BAJO, B2.** `patches/pa_sin_A2.patch` es incremental sobre v2 y no tiene cabeceras de git. Además, `v2_completo_sobre_HEAD.patch` es idéntico a `plan_k_v2.patch` y su base es 1bc9832, no HEAD. Conviene una línea en el reporte con la receta: plan_k_v2 sobre 1bc9832 y luego pa_sin_A2.

**Nota, fuera de WS-K1:** `research/ws/WS-K2/report.md` está como AM, es decir, la versión staged no es la del working tree. Cuidado si se commitea antes del panel de WS-K2.

### Verificado como correcto
- `src/` no contiene `pc_alpha_implicit`: 0 archivos.
- Los parches v2 tienen como base los blobs de 1bc9832 y `git apply --check` falla en `mod_pressure_3d.f90:733`.
- Hay 7 commits de `src` desde 1bc9832. Sus mensajes declaran numérica bit a bit o golden v131/v132. Revisé los diffs de 4d8570a en `mod_continuity`, `mod_pressure_3d` y `mod_properties_3d`: son solo de audit o diagnóstico (`audit_comp_cell`, `audit_eos_cell`, `ws_pc_unl_used`).
- P-a cambia dos cosas, factor 1 en `acc_face` y `unl_on = .false.`, como dice el punto 5.
- Pasos con p_max > 1e5 en la ventana de regime2: base 7, k1 2, k1b 6, k1pa 2 y k1pb 6. El paso 342450 tiene 9.52e4, y los valores de 342451 y 342452 coinciden con los citados.
- `vol_lim`: 2.481e-3 en la base frente a 2.460e-3 en los brazos K; `vol_unlinked`: 2.057e-3 en todos.
- `cell_series` y `regime2` reproducen las cifras citadas: 885.7, 70.57, 6874.3, 209.5, 23362.5, 6.3 y 5.4.
- `dense_340_n14`: la celda (10,60,2) aparece en los pasos y con las presiones citadas, y el reinicio es `judge_otp_280` a 340 s.
- `regime2` de las corridas de 340 s coincide con el reporte.
- WS-K1 tiene 16 registros raíz (4 refutadas, 9 fallidas, 3 soportadas), y C-065 a C-073 cierran C-016 a C-024.
- Las referencias de líneas en `acople-pv.md`, en el plan (§4, 72–73) y en `reevaluacion.md` son correctas, igual que los recuentos de `[PROBE-*]` y las configuraciones.

### Orden de corrección
1. M2: quitar de la regla permanente la afirmación que el registro retiró.
2. M1: añadir la salvedad de la mediana en la regla, en el §6 del plan y en el reporte.
3. B1 y B2, de redacción.