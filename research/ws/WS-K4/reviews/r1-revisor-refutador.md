# WS-K4, ronda 1: revisión del refutador

Revisión de solo lectura. Comprobado en código y datos:
- el hook del líquido: src/mod_energy_3d.f90:479-567;
- eq_residual y audit_accumulate: src/mod_audit.f90:320, 721-739;
- scripts/diag/energy_gap.py;
- recálculo con campaigns/b1/bench_relaxcol/audit.csv y bench_base0/audit.csv.

## 1. Conclusiones, alternativas y dato que las separa

**C1. La columna E_relax_liq explica el hueco del líquido: −1.088e4 frente a −1.172e4 J, 7.1 %, r = 0.99999918.**
- Recalculado: 220 pasos, hueco del líquido −11716.6 J, sum E_relax_liq −10883.3 J. Remanente −833.3 J, mediana −3.738 J/paso, std 0.232 J. Las cifras son correctas.
- Alternativa: la concordancia es en buena parte algebraica.
  - La columna es s_abs − (fuentes del hook) y el hueco es dE_liq − ext. Ambos restan las mismas eeq(1,2..7).
  - Lo que el 7.1 % contrasta de verdad es que el inventario del hook (s_abs sobre Tk, con alpha_old) coincide con el inventario del audit, salvo términos ajenos al hook.
  - Prueba que el hueco es el residuo del enunciado discreto sobre el campo guardado. NO prueba, por sí solo, que la causa sea la relajación.
- Dato que las separa: la perturbación en alpha_T.
  - Está en los datos (C-096, C-103): con aT1 el hueco baja a −3.8 J/paso con std 0.25 J; con 0.7 la std es 181 J y con 0.85 es 105 J.
  - El remanente de relaxcol (−3.74 J/paso, std 0.23 J) es idéntico al hueco de aT1. Eso es coherente con que la parte relajada sea la columna.
  - La atribución se sostiene, pero apoyada en C-096/C-103, no en C-101(1) → R1.

**C2. E_relax_gas explica el hueco del gas.**
- Alternativa: es una identidad. Hueco del gas − E_relax_gas = −32.8 J, std 0.026 J/paso; solo difieren E_iph_gas, E_slag_gas y los pokes.
- No aporta prueba independiente → R2.

**C3. El remanente no es el TDMA.**
- Correcto por construcción: R es lineal en Tk y el hook evalúa sobre el Tk guardado con los coeficientes ensamblados, así que el residuo interno cae dentro de la columna.
- Alternativa al candidato del reporte: modificaciones de T posteriores al hook de la última iteración externa (guardas, clip). Esas también quedarían fuera de la columna.
- Dato que las separa: inventario por clase de celda con los h5 por paso de bench_relaxcol. Los datos existen; el análisis no está hecho → R4.

**C4. Sin cambio numérico.**
- Verificado: 221 renglones, 0 diferencias en p_max y en todas las columnas comunes con bench_base0.
- check_audit da FAIL 1.456 con gap −1.067e4 J e INFO energy_relax −866 J.
- No mueve el problema de sitio: la columna no entra a la identidad, así que no esconde la pérdida.
- audit_accumulate se llama en cada paso (src/main_3d.f90:785), así que con audit_freq > 1 los acumuladores siguen correctos.

**C5. alpha_T 0.85 anula el neto, no el residuo por paso.**
- Coherente con C-098, C-100 (energy_balance_step FAIL) y C-103.
- Alternativa (cancelación accidental en esta ventana): no se distingue sin el banco aT085 con el binario nuevo → R3.

## 2. Repeticiones de fracasos registrados

- Ninguna. Es un cambio diagnóstico, no un arreglo; no repite D2.2, las reglas D/E/F/G ni n_pc_max.
- La forma cuantitativa refutada (C-097 → C-098) está declarada y ya no se usa: la regla, el comentario y el glosario ya no atribuyen los −3.8 J/paso al TDMA.
- La pieza (a), alpha_T 0.85 (C-100 refutada), queda fuera del alcance.

## 3. Objeciones (ninguna bloqueante)

- **R1.** C-101(1) apenas discrimina, igual que la correlación: comparte los términos de fuente. Basta una frase que apoye la causalidad en C-096/C-103. A medio plazo, el banco aT1 con el binario nuevo (columna ≈0).
- **R2.** La concordancia del gas es casi una identidad (−33 J, std 0.026 J). Hay que reformularla como comprobación de consistencia.
- **R3.** El nombre «relax» no se ha verificado con aT1 ni aT085 usando el binario nuevo. Correr ambos bancos: aT1 debe dar columna ≈0; aT085, suma ≈ −13 J con std ≈105 J.
- **R4.** El remanente de −3.7 J/paso se puede comprobar ya con los h5 de bench_relaxcol: separar dE_liq de las celdas con alpha < ALPHA_CUTOFF y de las de T acotada.
- **R5.** Solo un banco de 220 pasos. Validar en la próxima corrida B1 larga (280-340 s, −87 J/paso en C-094).

## 4. Valoración

Las conclusiones del reporte son modestas: existe una columna diagnóstica, en este banco captura el 93 % del hueco, no altera la numérica y el remanente está declarado abierto. Resisten las alternativas. Lo que queda abierto está reconocido en «Incertidumbre» o es un ajuste de redacción sobre el valor de prueba (R1, R2). Nada invalida la pieza (b).

VEREDICTO: aprueba
