## Revisión del refutador: WS-K7, ronda 1 (sexto lanzamiento)

Revisión ciega: no se leyó `research/ws/WS-K7/reviews/`. Solo lectura: sin make, sin mpirun ni corridas; Python solo para leer los `audit.csv` y los `.h5` que ya existen.

### 1. Conclusiones del reporte: alternativa y dato que las separa

| # | Conclusión vigente | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|---|
| C1 | {C-145}: H **sin decidir** (rem_all/abs 0.319; neto 1.571) | El inciso por celda reparte el peso entre dos términos de una descomposición exacta, no contrasta H con su alternativa. En las nogas la coincidencia es la identidad de fila; en las celdas con gas, e − err_liq ≈ (EOS − su_cc) + residuo del CG + variación de ρ | Σ\|dt·su_cc\| por celda y subconjunto; CG con más iteraciones | En parte. Recalculado por subconjunto: con gas 0.384, nogas 0.163 (k7v5_mo20); base 0.491/0.165. El veredicto no cambia (el neto falla 5×), pero el 0.319 **no** apoya a H (R7) |
| C2 | Desfase E2 ≤ 0.2 % ⇒ err_liq es el desajuste en caras enlazadas | Sería trivial si el flujo no enlazado fuera pequeño | `vol_unlinked` | **Sí, se sostiene**: vol_unlinked = 0.207 m³ en 59 pasos (ρ_g·V ≈ 0.063 kg ≈ 4 Σ\|e\|); el desfase pequeño tiene contenido |
| C3 | Nogas (29 %): conducto = α de cara media (verificado), magnitud = plan neto del Poisson, «mismo balance de fila que Plan E»; además «el recuento sin dirección subestimaba la población de Plan E» | La celda nogas como **conducto de paso** del gas fantasma (½α_vecina·u·A, u atada al líquido, F2.20/F2.21/F2.24) entre el lecho con gas de encima y el baño o lecho con gas laterales. El neto sería residuo de un flujo bruto mayor y la población de Plan E no conduciría | ws_Fg bruto por dirección y clase de vecina | **Indicio aproximado en snapshots, en contra del reporte** (R3). El conducto sí está verificado: `af = 0.5*(aef(P)+aef(nb))`, `ag_eff = gas%alpha` (src/mod_pressure_3d.f90:1203/1237/:246); `face_lim` devuelve 1 para el gas (:1701) |
| C4 | La exportación de las nogas se cancela por construcción en e_multi | Ninguna razonable (ws_Fg conservativo, receptoras multifase 1213/1214) | — | Se sostiene. Consecuencia: el 29 % no informa del piso neto |
| C5 | Bancos sin líquido: «piso multifase **estructural**» sin H | Residuo relativo del solver sobre una EOS enorme de arranque en frío | outer_conv_n8 con max_iter del CG mayor | En parte: EOS −18.7 kg en 10 pasos, e_multi 5.55e-3 (3e-4); converger el lazo externo baja solo 24 % (R4) |
| C6 | {C-151}: ≥ 48 % del piso no es complemento neto; «matiza C-110» | Lazo truncado de 5 externas más régimen de centinela | Misma cota con 20 externas en el mismo intervalo | **Sí, y favorece la alternativa** (R2) |

### 2. Repeticiones de fracasos registrados

- **H ≡ válvula ficticia de Plan E E1** (`.claude/rules/acople-pv.md:456-481`) **≡ desfase 2 de Plan D** (`vol_lim`). El reporte lo declara («Antecedentes»), no propone remedio y lo que añade es un instrumento por celda. No es repetición de un remedio refutado; lo acepto. Mi dato C3 sugiere además que la población de Plan E casi no conduce, y eso debilita incluso la analogía de población.
- **«Remedio latente»** (α del dador para el gas en el Poisson, o sacar del alcance las celdas de baño) = F2.17–F2.21 (cuatro intentos, `acople-pv.md:366-382`) y la familia de reglas locales D/E/F/G/F2.31 (`:442-455`, `:587-594`). El reporte NO lo propone. Pero argumenta que «la premisa de F2.21 no se cumple aquí». Si alguien lo usa, debe decir en qué difiere de F2.17–F2.19 y pasar el juez estadístico tras revalidar ({C-089}). La reconstrucción de R3 indica que el flujo fantasma viene del lecho con gas de encima, es decir del canal de alcance F2.21, que es justo lo que esos intentos tocaron.
- **Cinco redefiniciones del conjunto** sobre la misma ventana de 59 pasos (C-122 → C-126 → C-130 → C-135 → C-144). Están declaradas, igual que el umbral de correlación fijado tras ver el dato (O5). Sin más objeción.
- `n_pc_max` y el limitador dentro del Poisson: no aplican (diagnóstico, numérica idéntica; golden v131 con rtol 1e-12 y sha256 del binario de banco = `make opt`, `research/ws/WS-K7/logs/opt_identidad.txt`).

### 3. Objeciones

**R1 (bloqueante): la regla contradice al reporte.** `/Users/frariv/Horno/hornofusion-full3D/.claude/rules/transporte-energia.md:175-177` (staged) dice «el neto multifase −8.55e-4 es el ~20 % residual de esa cancelación, dentro de los sesgos del estimador». El reporte lo retiró (R3, {C-150}; report.md:179, :264) y la propia regla lo contradice en :203-206.
*Resolución:* sustituir por la forma de C-150 y comprobar con grep regla, glosario y AUDIT_COLUMNS.

**R2 (bloqueante): C-151 no matiza C-110.**
- Mismos 999 pasos (280.001–280.999 s): con 5 externas la cota da ≥ 31.8 %, pero la diferencia de e_multi entre 5 y 20 externas es el **43.1 %** del e_multi con 5. Con 20 externas (`k7v5_mo20_1k`) la cota no restringe en ningún tramo (cota/|e| entre 1.9 y 2.4).
- En `k7v4_long` la fracción crece con el régimen: 0.32 → 0.39 → 0.48 → 0.48 → 0.56 → 0.61 por bloques de 1000 pasos, con u_gas = 300 desde el paso 4339 y |p| > 100 kPa desde el 4668; antes del centinela vale 0.43.
- C-110 define el piso con 20 externas, y el propio reporte dice que el objeto con 5 externas no es «el piso».

*Resolución:* evento con `--ref C-151` y corrección en regla :245-247 y report.md:297 («con 5 externas, compatible con el lazo truncado; con 20 la cota no restringe»), o comp/eos por conjunto en una ventana ≥ 1000 pasos con 20 externas que pase check_audit, pre-registrada.
*Comando:* sumas de `m_gas_comp_abs`, `m_gas_comp` y `m_gas_err_multi` sobre `k7v4_long[:999]` y `k7v5_mo20_1k`.

**R3 (bloqueante): «Dirección» no medida y contradicha por un indicio.** «El recuento sin dirección subestimaba la población de Plan E» (report.md:154) supone que la salida neta va por las caras superiores.

Reconstrucción aproximada:
- *Método:* q = ½·α_g,vecina·ū·A con las velocidades del gas en centro de celda, sin Rhie–Chow, estado al final del paso; el neto, 0.20 m³/s en 280059, cae dentro del e_nogas medido ≈ 0.15–0.32 m³/s.
- *Caras superiores:* son **entrada neta** en las tres variantes (−0.27, −0.34, −0.19), dominadas por el lecho con gas de encima (−0.36, −0.39, −0.47 y −1.32 m³/s en 280059, 280000, 280999 y 285000).
- *Salida neta:* lateral, hacia baño con gas (+0.29) y lecho con gas (+0.15).
- *Población de Plan E:* el poro casi saturado de encima aporta +0.001 a +0.003 (≈ 1 %).
- *Flujo bruto:* sale 0.85 y entra 0.65, más de 4 veces el neto.

*Resolución:* retirar la frase, o medir ws_Fg bruto por dirección y clase de vecina (columna pre-registrada o sonda de un paso).

**R4 (no bloqueante):** «estructural» en los bancos fríos no está establecido: e_multi es 3e-4 de la EOS y el lazo convergido solo lo baja 24 %.
*Resolución:* CG con más iteraciones en outer_conv_n8, o quitar el adjetivo.

**R5 (no bloqueante):** «Tamaño 10–13.5 %» (report.md:154, regla :194) usa el valor de `m_gas_rej_nogas`, que el reporte declara no interpretable. Que el resto de vol_lim esté en celdas con gas es una inferencia por resta.
*Resolución:* in_tot/in_ok, o vol_lim partido por subconjunto; si no, retirar la cifra.

**R6 (no bloqueante):** «Poro seco en act_g, no verificado» se resuelve con los datos existentes. `m_gas_cells_nolink` = 0 y el poro seco es de clase 2 (src/mod_audit.f90:923-933), así que tiene una cara enlazada; con α_l < 1e-6 el enlace es de gas, luego está en act_g (pv_active por percolación, src/mod_multiphase.f90:199-201). Las caras hacia la solera seca están enlazadas: ≈ +0.015 m³/s, cerca del 7 % del neto aproximado.

**R7 (no bloqueante):** el 0.319 es 0.384 (con gas) ponderado con 0.163 (nogas, identidad de fila). Hay que poner el cociente del subconjunto con gas junto al veredicto y declarar que el «sin decidir» no es evidencia a favor de H. Deriva del subconjunto con gas: 0.38 → 0.43 en 1 s con 20 externas y 0.52 → 0.68 con 5.
*Dato pendiente:* Σ|dt·su_cc| frente a eos por subconjunto, y el CG con más iteraciones.

### ¿Mueve el problema de sitio?
No aplica: cambio solo de diagnóstico. La numérica idéntica está respaldada por golden v131 (rtol 1e-12) y la identidad sha256 del binario `make opt`.

### ¿Se mide en el sitio que importa?
Está declarado que 59 pasos con 20 externas no son el piso de C-109 ni B1 (5 externas), y que no hay ninguna ventana larga que pase check_audit. R2 es justo la violación de ese acotamiento.

VEREDICTO: rechaza