# Revisión del refutador — WS-K7, ronda 1 (panel de cierre, 25-oct-2026)

Solo lectura: `research/README.md`, `research/ws/WS-K7/report.md`, registro (C-089, C-110, C-121, C-134, C-135, C-139, C-140, C-143, C-144, C-145 y las 37 refutadas/fallidas), `.claude/rules/acople-pv.md` (Vigencia C-089, «Lo que NO funcionó», Plan D/E/F, corrector `n_pc_max`, H0 de Plan K), `docs/PLAN_E_*.md`, `docs/PLAN_K_*.md`, `.claude/rules/transporte-energia.md` (párrafo WS-K7), `src/mod_audit.f90` (~:923-931, :1040-1118), `src/mod_pressure_3d.f90` (:222-256, :1214-1246, :1726-1736), y los `audit.csv` de `campaigns/b1/k7v5_{mo20,base,mo20_1k}` y `k7v4_long`. No se leyeron las revisiones de otros revisores.

## 1. Conclusiones del reporte, alternativa y dato que las separa

**C1. H (C-110) queda SIN DECIDIR por celda (0.319 sin filtro, 0.565 con filtro) y el inciso del neto falla (1.571).**
- Recalculado de `k7v5_mo20/audit.csv`: 0.319 / 0.565 / 1.571; base 0.404 / 0.626 / 1.320. Por subconjunto: con gas 0.384 (base 0.491), nogas 0.163.
- Alternativa: el 0.319 lo acerca al umbral el subconjunto nogas, donde err_liq ≈ e es la identidad de volumen del Poisson (no H). El reporte ya lo declara (ronda 7, R5). Quitando nogas el cociente es 0.384: sigue en banda. Sin objeción al veredicto por la letra.
- Lo que el reporte no dice con claridad (R4): la deriva en TODAS las ventanas largas va hacia la refutación (20 ext.: 0.314 → 0.349 en 1 s; 5 ext.: 0.43 → 0.57 en 5.5 s; con filtro, 53 % de los pasos de k7v4_long ≥ 0.7).

**C2. err_liq en 280 s es en un 99.9 % el desajuste en caras enlazadas; el desfase E2 pesa 0.13 % de Σ|e|.**
- Verificado: unl_abs 2.158e-5 / 1.636e-2 = 0.0013; `mass_gas_err_liq_split` PASS (1.2e-20).
- Alternativa: el goteo no enlazado es GRANDE (vol_unlinked 0.207 m³ frente a vol_lim 0.249 m³ en 59 pasos) y aparece en V_pois (E2 aceptada) y en V_eff, cancelándose; que unl sea pequeño mide que E2 converge entre el último Poisson y el transporte, no que el goteo no genere error. Es compatible con la lectura del reporte (con E2 convergida el Poisson exporta gas por la fuente, así que no hay «complemento sin flujo»); no hay dato que la contradiga. Sin objeción.

**C3. El 29 % de Σ|e| en celdas sin gas es la válvula ficticia de Plan E (E1) por el conducto de la α media del gas (F2.24); la MAGNITUD la fija el volumen que el limitador rechaza (corr 0.97).**
- Conducto: verificado en código (`af = 0.5(aef(P)+aef(nb))`, :1220; act_g por alcance :235-237; Plan F apagado).
- Alternativa 1 (residuo del CG, ≥ 85 % de los Poisson sin converger en mo20): la separa la insensibilidad del término nogas a las externas, y los datos la DESCARTAN: Σ|e|_nogas 4.816e-3 (mo20) frente a 4.832e-3 (base), rej 7.655e-3 frente a 7.705e-3, vpois 4.078e-3 frente a 4.086e-3, mientras el subconjunto con gas cambia un 15 %. El reporte no cita este dato; debería (apoya su lectura).
- Alternativa 2 (tendencia común): la correlación 0.97 en k7v4_long es entre dos series monótonas (corr con el paso 0.965 y 0.992); en primeras diferencias 0.46; por tramos de 500 pasos 0.05–0.90. En k7v5_mo20_1k la medida LOCAL del rechazo (`rej_nogas`) NO deriva (corr con paso 0.10) mientras Σ|e|_nogas sí (0.91): rej/Σ|e| cae 1.61 → 1.48; lo que sigue a Σ|e|_nogas es `vpois_abs_nogas` (0.97 crudo, 0.98 diferencias, cociente 0.83–0.85), que es la identidad de volumen de la fila. **Objeción R1 (bloqueante).**
- Alternativa 3 (tautología): V_eff = 0 en nogas es forzado (α_g = 0 en ambos extremos ⇔ celda llena ⇔ room = 0 ⇔ entrada neta real 0). La expectativa (iii) de C-144 no podía fallar. **R2.**
- Alternativa 4 (qué celdas son): `gas_cell_class` 2 incluye chatarra con α_s ≥ 1e-2 sin líquido; «celda de baño» no está medido. **R3.**
- Contexto de escala: Σ|e|_nogas/vol_lim ≈ 2e-2 kg/m³ es ~ρ_g/10: solo ~6–10 % del rechazo global aparece como error nogas. **R5.**

**C4. Sobre el mecanismo del piso NETO el WS no concluye.** Correcto y coherente con C-140/C-143; e_out ≈ −e_multi solo por sumas (corr por paso −0.09) declarado. Sin objeción.

**C5. Identidad `mass_gas_rewrites` permanente; numérica bit a bit; tests OK.** check_audit de k7v5_mo20 PASS en todo (resto −6.15e-14); no re-ejecuté tests (solo lectura). Sin objeción.

## 2. Repeticiones de fracasos registrados
- Válvula ficticia de Plan E E1 (C-009; acople-pv.md «Plan E E1 CERRADO NEGATIVO», sonda PROBE-P a 320 s): el reporte la DECLARA como repetición (Antecedentes) y dice en qué difiere: medida por celda con instrumento permanente, clase α_g = 0 (no poro con 0.015), conducto α media del gas en el Poisson (no visto antes). No propone remedio; cita C-089 y rechaza E1b sin revalidación. Correcto.
- «El Poisson pide lo que el limitador rechaza» = desfase 2 de Plan D (vol_lim, D1 Spearman 0.94) y H0 de Plan K: el cociente Σ|e|_nogas/vol_lim es la versión por celda de aquella correlación. No es repetición de un remedio fallido, y el reporte no reabre D2.2, n_pc_max ni Plan K.
- Aviso: «α dador para el gas en el Poisson» sería la sexta regla local de la familia D/E/F/G (lección: el ciclo α–p no se cura clasificando); el reporte no la propone. Debe seguir así hasta juez estadístico en B1.

## 3. Objeciones
- **R1 (bloqueante).** La evidencia «magnitud = limitador, corr 0.97» es tendencia común; sustituir por corr de diferencias (0.46; por tramos 0.94/0.72/0.18/0.48/0.58/0.39/0.23/0.21/0.40; en 1k corr(ΔΣ|e|_nogas, Δrej) = 0.91 y con Δvpois 0.98), por la constancia del cociente de sumas (≈ 2.0e-2 kg/m³ en 4 bancos) y declarar que rej/Σ|e| deriva 1.61 → 1.48. Reescribir la frase de mecanismo (e_nogas = entrada neta planeada por el Poisson en celdas llenas, identidad; rechazada íntegra porque la celda está llena). Corregir report.md:110, regla transporte-energia.md:181-183 y evento con `--ref C-145`. Sin corridas.
- **R2.** Expectativa (iii) de C-144 infalsable (V_eff neto = 0 forzado en celdas llenas); declararlo y apoyar la lectura en rej > 0 y en la insensibilidad a las externas.
- **R3.** Composición del conjunto nogas (baño frente a sólido) no medida; columna pre-registrada o volcado por celda del snapshot 280059.
- **R4.** Declarar que la tendencia en ventanas largas es hacia la refutación de H por celda con ambas definiciones, y que el banco que decidiría es ≥ 1000 pasos con 20 externas que pase check_audit.
- **R5.** Dar la fracción (ρ_g·vol_lim)/Σ|e|_nogas para que el 29 % no se lea como el grueso del rechazo.

## 4. Lo que verifiqué y apoya al reporte
Cocientes y restos de k7v5 (0.319/0.565/1.571; 0.404/0.626/1.320); nolink/liq_skip/e2_skip = 0; check_audit PASS; conducto α media en código; E2 desfase 0.13 %; término nogas idéntico con 5 y 20 externas (descarta el CG como causa del 29 %); pre-registros C-121/C-135/C-144 con umbrales fijos; retiros de C-140/C-143 consistentes; ningún remedio de la familia D/E/F/G/K reabierto.

VEREDICTO: rechaza
