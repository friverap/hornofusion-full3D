# Revisión r2 — revisor-refutador — WS-K7

Solo lectura: `audit.csv` de `campaigns/b1/k7v4_{mo20,base,long}` y `k7v3_mo20`, `src/mod_pressure_3d.f90`, `src/mod_audit.f90`, `research/ledger.jsonl` (C-109, C-110, C-120..C-141), `.claude/rules/acople-pv.md`, `.claude/rules/transporte-energia.md`, `docs/PLAN_K_limitador_en_poisson.md`, `research/README.md`.

## 0. Estado de mis objeciones de la ronda 1

| id | estado | verificación |
|---|---|---|
| R1 (correlación vacía) | resuelta | La frase «H no explica el piso neto; el piso neto vive en e − err_liq» está retirada como mecanismo en Resultado (l. 80), k7v3 (l. 126), veredicto C-139 (l. 148) e Incertidumbre (l. 168); C-140 lo registra con `--ref C-139`. Reproduje sd(err_liq_all)/sd(e) = 7.91e-7/3.35e-6 = 0.236, corr 0.229/0.972, media e −1.45e-5, 59/59 negativos. |
| R2 (subconjuntos / frontera) | resuelta, con una imprecisión numérica (R7) | Cotas reproducidas: e_nogas ∈ [2.669e-3, 4.239e-3], e_gas ∈ [−5.094e-3, −3.525e-3], |e_gas − err|/|e_gas| ∈ [0.16, 0.42], e_out +9.24e-4. La lectura «frontera ≈ entrada por el outlet» queda «compatible, no medida» y las columnas pendientes están listadas. |
| R3 (cota del confusor del CG) | resuelta | Retirada en l. 163; queda «no medido». |
| R4 (k7v4_long) | resuelta | Filas 280001–280058 idénticas a k7v4_base, 280059 distinta (76 columnas; dt 9.9999971e-4); e/paso por tramos −2.96e-5 → −5.46e-5 reproducido. |
| R5 (1.9 % / 3.8 %) | resuelta | Retirados en l. 127 y 151; «orientada, no cuantificada». |
| R6 (α de cara media) | resuelta, con un matiz (R9) | `af = 0.5*(aef(P)+aef(vecina))` en :1186/:1220/:1269/:1303/:1352/:1388; `ag_eff = gas%alpha` (:243, sin piso); `fl = dt·(entrada − salida)` en el audit (:994-996) ⇒ e_nogas > 0 es gas que SALE de celdas con α_g = 0: solo la media lo permite. |

## 1. Conclusiones del reporte, alternativa y dato que las separa

1. **Veredicto formal «sin decidir» (0.319 por celda; neto 1.58 > 0.3)** — reproducido por la letra de C-135. Alternativa: la banda 0.3–0.7 es función de la posición de la ventana, no del mecanismo. Dato: cocientes por tramo en k7v4_long. Está en los datos: sin filtro 0.44 → 0.56, con filtro 0.66 → 0.76 (≥ 0.7 desde el tramo 3001–4000). No decide (5 externas, no pre-registrado) pero el reporte solo cita los agregados (R8).
2. **El 29 % de Σ|e| en nogas es caudal fantasma por la α de cara MEDIA del gas en el Poisson (F2.24), no churn del complemento** — Alternativas: (a) `ag_eff` con piso (ALPHA_PHASE_MIN/ALPHA_PORE_GAS) en celdas sin gas; (b) entrada de gas con dador en la vecina. Dato: `ag_eff = gas%alpha` (:243, única asignación) descarta (a); el signo de fl en el audit (entrada neta) con e_nogas > 0 implica SALIDA neta de gas de celdas con α_g = 0, lo que descarta (b). Confirmado además `comp_abs_nogas` = 1.908e-6. Matiz: `face_lim` devuelve 1 para el gas (:1684); el reporte dice «tras el limitador fl» (R9).
3. **e_multi depende de las externas (−1.571e-3 con 5, −8.55e-4 con 20); la independencia de C-109 era de la EOS total** — reproducido. Alternativa: k7_base no es una corrida válida (FAIL energy 2.24×, u_gas 215). Declarado en Incertidumbre; no se generaliza.
4. **Σ|comp| por llamada 1.38× el neto, Σ|eos| 1.95×: sin churn de 100×** — reproducido (3.125e-3 / 2.271e-3; 0.841 / 0.432). Lectura acotada; no hay alternativa pendiente.
5. **M1 de peso cero en 280 s (nolink = 0) y 0.36 % en ventana larga** — reproducido (51 845 celdas-paso, 7.47e-3 de 2.048 kg, E2 descartada 1.1e-14).
6. **Identidad Δm_gas = comp + eos + volfix cierra a 1e-13 y el resto no crece** — reproducido (−6.15e-14 / −3.23e-14; Σ|dm| por llamada 0.844 / 78.35 kg).
7. **Sobre el mecanismo del piso NETO el WS no concluye; e_multi ≈ −e_out es compatible, no medido** — correcto. Dato adicional en mano (R11): en k7v4_long e_multi −0.224 frente a e_out +0.234 (0.96) y e_free −0.065 ≈ Σ eos −0.058: la relación se repite en las dos ventanas y los dos regímenes de externas; coincide con el reparto de C-110 (+5.1e-3 / −6.0e-3, neto ≈ −entrada por el outlet).

## 2. Repeticiones de fracasos registrados

- H es la válvula ficticia de Plan E (E1; `[PROBE-P]` a 320 s): declarado en Antecedentes con los remedios negativos (E1b `pc_sat_gas_off`, Plan K G1/G2, `n_pc_max = 3`, F2.31 por paso) y la salvedad C-089. El WS no propone remedio. Correcto.
- La atribución R6 (media en el Poisson del gas) sugiere «dador para el gas en el Poisson»; no está en el registro como probado ni refutado, y el Poisson exige matriz simétrica (CG) y la misma función de cara que el momento (B4-10). El reporte no lo propone: nada que exigir.
- La «pieza siguiente» (su_cc frente a EOS por celda) es la alternativa reformulada de C-120 (soportada), no una refutada.
- C-106 (lazo truncado como causa dominante) y C-117 (volfix por celda) no se repiten.
- La cancelación ±4e-3 entre nogas y con gas es la misma observación que el reparto de C-110 con otro instrumento: debería declararse como tal (R11), no es un fracaso.

## 3. Objeciones (todas no bloqueantes)

- **R7** — Cotas por subconjunto: «≤ 0.23» (l. 126) y «≥ 77 %» (l. 168) son respecto de err_liq, no de e; correcto: |e − err|/|e| ≤ 0.294 (≥ 71 %). «60–85 %» → «58–84 % con gas, ≥ 71 % nogas». Origen: mi redacción de R1 en la ronda 1. Resolución: corregir las cuatro líneas.
- **R8** — Cocientes por tramo en k7v4_long (sin filtro 0.44/0.47/0.48/0.53/0.56/0.53; con filtro 0.66/0.68/0.70/0.73/0.76/0.74): con la definición de C-126 la ventana larga de 5 externas supera 0.7 en su segunda mitad; los 59 pasos son el mínimo de los 5.5 s. Resolución: declararlo en Resultado e Incertidumbre (no decide); para 20 externas, banco largo con columnas (coordinador).
- **R9** — `face_lim` ≡ 1 para el gas (`if (isg) return`, :1684): «multiplicada por el limitador fl» es falso para el gas; las caras del gas no pasan por `face_open` ni por D2.2c. Resolución: corregir las dos frases (l. 101 y respuesta R6).
- **R10** — `.claude/rules/transporte-energia.md` está staged en el diff de cierre y aún lleva la frase retirada en negrita, la atribución a F2.21 y el 1.9 %. Resolución: editarla con C-140/C-141 antes del commit y decir en el reporte que la regla forma parte del diff.
- **R11** — Citar e_multi/e_out/e_free/eos de k7v4_long y la referencia cruzada a C-110 en la viñeta de Incertidumbre (punto 5).

## 4. Veredicto

Las seis objeciones de la ronda 1 están resueltas en el texto y verificadas contra datos y código. Lo que queda son precisiones y declaraciones (R7–R11) que no cambian el veredicto formal «sin decidir» ni dejan en el reporte ninguna inferencia de mecanismo sin soporte. La regla staged (R10) debe corregirse antes del commit de cierre.

VEREDICTO: aprueba