# Revisión del refutador — WS-K7, ronda 1 de este lanzamiento (25-oct-2026)

**Veredicto: rechaza.** Hay una objeción bloqueante (R1): el reporte describe mal el limitador en el párrafo del mecanismo y en el registro. Se corrige solo con texto, sin corridas.

**Qué leí (solo lectura):**
- `research/README.md`, `research/ws/WS-K7/report.md` (completo), C-110, C-120, C-121, C-144, C-145, C-146.
- Las 32 refutadas o fallidas del registro.
- `.claude/rules/acople-pv.md`: Vigencia C-089, «Lo que NO funcionó», F2.13/F2.16/F2.21/F2.24, Planes D/E/F, H0 de Plan K, `n_pc_max`.
- `.claude/rules/transporte-energia.md:150-219` y `docs/PLAN_E_*.md` §6.
- Código: `src/mod_audit.f90:923-1118`, `src/mod_pressure_3d.f90` (act_g :218-236, F2.8 `face_open`/`face_lim` :1668-1721, exportación de `ws_Fc` :808-813), `src/mod_continuity.f90` (limitador :395-470, `cell_in_out` :1014-1037, flujos :365-367 y :1499-1557, `ws_lim_step` :853-858), `src/mod_multiphase.f90:183-202`.
- `audit.csv` de `k7v5_{mo20,base,mo20_1k}` y `k7v4_long`, y los snapshots de 280000, 280059, 280999, 285000 y 285499.

No leí las revisiones de los otros revisores. Mi revisión anterior (`reviews/r4-revisor-refutador.md`) sí, para comprobar qué se atendió.

## 0. Qué se atendió de mi ronda anterior
- **R1 (correlación con tendencia): atendido.** La correlación se retira en C-146, se da en primeras diferencias y la tautología se declara.
- **R2: atendido.**
- **R3: atendido** para un paso (abajo lo amplío a cinco).
- **R4 (deriva hacia la refutación): atendido.**
- **R5: atendido**, con un matiz en R6.

Recalculé estas cifras y coinciden:
- 0.319 / 0.565 / 1.571 en mo20 y 0.404 / 0.626 / 1.320 en base.
- Σ|e|_nogas/vol_lim: 1.935e-2, 1.941e-2, 1.982e-2 y 2.039e-2.
- rej/Σ|e|_nogas: mediana 1.52, rango 1.21–1.79; por tramos 1.61 → 1.48.
- Correlaciones: corr(rej, paso) = 0.10 y corr(nogas, paso) = 0.91; en diferencias 0.91 y 0.98.
- Por subconjunto: 0.384 con gas y 0.163 en nogas (base: 0.491).
- Insensibilidad a las externas: 4.816e-3 frente a 4.832e-3.

## 1. Conclusiones, alternativa y dato que las separa

**C1. H sin decidir por la letra en 59 pasos; en ventanas largas el cociente deriva hacia la refutación.**
- Alternativa: el inciso por celda es una descomposición, no un test de mecanismo. Por la identidad de la fila, e − err_liq ≈ (eos − ρ_g·dt·su_cc) + residuo del CG + efectos de ρ de cara frente a ρ de celda. Con eso, 0.319 dice que esos términos de cierre pesan alrededor del 32 %. En nogas, err_liq ≈ e por la identidad, y eso empuja el cociente hacia «soportada».
- Ya está declarado (rondas 5 y 7, y la columna su_cc pendiente). La letra no cambia: sin el subconjunto nogas el cociente es 0.384. **Sin objeción.**

**C2. err_liq en 280 s es en un 99.9 % el desajuste en caras enlazadas (desfase E2 = 0.13 %).**
- Verificado.
- Alternativa: lo que domina lk no es el limitador sino α dador frente a a_f. El transporte mueve α_dador·Q/a_f, con a_f igual a la MEDIA en caras continuo|continuo; es un error de primer orden en cada interfaz. El resumen de :95 lo atribuye al «limitador frente al plan del Poisson». **R5.**

**C3. El 29 % en celdas nogas es la válvula ficticia de Plan E por el conducto de la α media: entrada neta planeada en celdas llenas, rechazada íntegra por el limitador.**
- **Conducto: correcto** (código). Con α_g = 0 en la celda, solo la α media del gas permite F_g saliente.
- **Alternativa A (celda de paso frente a celda ciega).** El limitador admite entrada hasta la salida admitida: room incluye la salida (`mod_continuity.f90:418-421`, `cell_in_out` :1014-1037). Por tanto s = 0 solo si no hay salida. V_eff es neto, y una celda de paso da el mismo V_eff = 0 que una ciega. La válvula de Plan E era una celda ciega («ni α_l ni α_g cambian»). «ws_lim_step = 0 ahí», «room = 0», «rechaza todo el líquido» y «el transporte no movió nada» no están medidos. Además rej_nogas mezcla la s del transporte con el Fc del Poisson, y su valor (1.87 × Σ|ρV_pois|) no se explica sin s = 0. **R1, bloqueante.**
- **Alternativa B (población).** Dato nuevo de los snapshots: las celdas nogas son baño en el PISO, k = 1–3. 391 de 406 están sobre la solera k = 0, que es poro SECO (α_s 0.985, α_g = ALPHA_PORE_GAS exacto, α_l < 1e-6). Las caras hacia vecinas con gas van sobre todo a poro seco, baño con gas y lecho con gas. Solo 69 de 1214 dan a poro saturado, la población de Plan E. **R2.**
- **Alternativa C (origen de la entrada planeada).** F2.8 cierra por el signo del predictor las caras de entrada hacia celdas con room ≤ 1e-4. La entrada planeada solo llega por caras cuyo predictor era saliente y la corrección invirtió (o por E2/fs). Es la complementariedad con retraso de Plan K H0. **R3.**
- **Alternativa D (residuo del CG).** No la separa la insensibilidad a las externas, porque el plan es idéntico con 5 y con 20. La separa la identidad de la fila (0.83–0.85). **R4.**
- **Escala:** con el ρ_g local la fracción sube a ~8.5 %. **R6.**

**C4. Sobre el piso neto el WS no concluye.** Es coherente con C-140/C-143. Sin objeción.

**C5. Instrumento permanente, numérica bit a bit y tests.** No re-ejecuté nada (solo lectura). Sin objeción.

## 2. Repeticiones de fracasos registrados
- **Plan E E1, válvula ficticia (C-009).** El reporte declara la repetición. La diferencia que da (α media como conducto) es real. Pero no ha probado que sea la misma población (R2) ni el mismo régimen de celda ciega (R1).
- **H0 de Plan K y desfase 2 de Plan D (C-008, C-041, C-065…C-073).** La entrada planeada en celdas llenas pasa por el cierre F2.8 decidido con el signo del predictor. Es la misma familia y el reporte no la nombra (R3). No se reabre ningún remedio.
- **F2.20/F2.21.** La premisa de diseño era que «en un charco quieto la cara ve u ~ 0 y no inyecta caudal». Aquí el canal por alcance sí exporta gas fantasma en el baño del piso, que se mueve. Advertencia: «α dador del gas en el Poisson» o quitar el alcance en el piso sería la sexta regla local sobre el piso (familia D/E/F/G/F2.31). Exige juez estadístico en B1 antes de tocar defaults. El reporte no lo propone; correcto.

## 3. Objeciones
- **R1 (bloqueante).** Descripción del limitador: «room = 0», «ws_lim_step = 0», «rechaza todo el líquido», «no movió nada».
  - *Resolución sin corridas:* retirar esas frases de report.md (:95, :116, :196). Añadir en `.claude/rules/transporte-energia.md:183-184` que el limitador admite entrada hasta la salida admitida. Registrar un evento con `--ref C-145/C-146`. Declarar que celda ciega frente a celda de paso no está medido y que 1.59 no se interpreta.
  - *O con datos:* columnas Σ_nogas in_tot e in_ok del transporte, o una sonda de s en las nogas de un paso, pre-registradas.
- **R2.** Escribir la ubicación de las nogas: k = 1–3, sobre la solera seca, en los 5 snapshots. Dar el recuento de caras por clase de vecina y cualificar la etiqueta «Plan E» como «mismo balance de fila, población distinta». Si se quiere atribuir: columna −dt·ΣF_g de nogas por clase de vecina, pre-registrada.
- **R3.** Declarar el papel de F2.8 en la entrada planeada. Dato: entrada por caras con signo(Fs) ≠ signo(ws_Fc) y Σ E2 aceptada en nogas.
- **R4.** Sustituir «separa del residuo del CG» por la cota de la identidad de la fila (≤ 15–17 %).
- **R5.** Nombrar los tres componentes de lk en el resumen, o medir el reparto.
- **R6.** Citar 6–8.5 % (ρ_g en nogas: mediana 0.228, rango 0.138–0.341).
- **N1 (proceso).** C-146 dice que el auditor aprobó la ronda 8; `status.json` (16:19:52) dice que rechazó. Conciliar.

## 4. Verificado
Cocientes, subconjuntos e insensibilidad a las externas en k7v5. Cocientes de sumas en los 4 bancos. Estadísticas de rej y de vpois en nogas en `k7v5_mo20_1k`. Composición y vecindad de las nogas en 5 snapshots. Código del limitador, de F2.8, de act_g/pv_active y de la reconstrucción del flujo con a_f.

VEREDICTO: rechaza