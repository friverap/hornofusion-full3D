# Revisión del refutador: WS-K1, ronda 1 (ciclo 7)

Revisión de solo lectura, ciega a las demás revisiones. Python se usó solo para leer `audit.csv` existentes (scripts en el scratchpad).

## 1. Conclusiones, alternativas y dato que las separa

**C1. G1 no se cumplió (H1 y H1b refutadas por la letra).**
- **Alternativa:** los criterios estaban mal planteados (|p| < 20 kPa, C-031) y el fallo de (c) en H1b es ruido de trayectoria: 6 pasos frente a 3.55 permitidos, o 4/109 sin los pasos del reinicio.
- **Qué la separaría:** ≥ 3 trayectorias de v2 completo en 342.45–342.56 s. No existen. k1pb no es independiente: comparte con k1b los mismos 6 pasos por encima de 1e5.
- **Juicio:** el reporte lo reconoce. Por las reglas del registro, el veredicto por la letra se mantiene y «no cumplida» se sostiene.
- **Nota a favor de H1:** la convergencia del 0 % no depende de la tolerancia supuesta. Las 205 resoluciones llegan al tope de 8 iteraciones, así que el propio binario declaró que no convergió.

**C2. «Plan K no adoptado» es una DECISIÓN, no una refutación del beneficio en B1.** De acuerdo; no hay alternativa que objetar.

**C3. La holgura quita el ciclo en la sonda (C-039).**
- **Alternativa del propio reporte:** el efecto viene de `unl_on = .false.` y no del factor 1.
- **Qué la separaría:** una corrida con factor 1 y `unl_on` activo, o `ws_pc_unl` por celda. No están en disco. Bien declarado.

**C4. El brazo K de C-041 tiene un binario «no verificable», así que «si era v2 con A2, la holgura nunca se juzgó en B1 y no está refutada».**
- **Alternativa:** el brazo era v2 sin A2, como declara C-040, y la holgura SÍ se juzgó.
- **El dato ya está en disco** (ver O1):
  - n12, n14 y n15 son el mismo binario: diferencias de vol_lim entre 1e-17 y 1e-15, el mismo nivel que entre las trayectorias de la base.
  - Frente a k1_340 (v1, mismo reinicio y misma descomposición 2x3x2), k1pa_340_n12 da vol_lim +7.1e-9 en 340001 y vol_unlinked positivo, entre +5e-10 y +2.5e-8.
  - Calibración en 342.45 s contra k1_342: sin A2 (k1pa) da +1.3e-9 y vol_unlinked positivo; con A2 (k1b/k1pb) da −4.48e-7 y vol_unlinked negativo y creciente.
  - **Lectura:** la firma de k1pa_340_* es la de la variante sin A2.
- **Juicio:** la vía de escape «no está refutada» no la sostienen los datos.

**C5. La directiva «no reintentar el tope exacto» es más fuerte que los datos.** El reporte lo admite, sin más objeción.

**C6. Plan K bajó p>100k en B1 sin trasladar el defecto (C-312/C-313).**
- **Alternativa:** el problema se movió a otra columna.
- **Dato:** las 4 trayectorias K funden de +6 a +8 t más que la base en 340–345.3 s (dm_liq 398.6–400.6 t frente a 392.4–392.6 t; dispersión de la base 0.2 t) y tienen dE_liq ~1 % mayor.
- **Juicio:** no prueba un defecto, pero la frase «sin indicio en otra métrica» solo cubre cuatro columnas (O3).

## 2. Repeticiones de fracasos registrados

- **Plan K frente a D2.2 y `n_pc_max`:** PLAN_K §2 dice de antemano en qué difiere (conjunto activo convergido dentro del solve, no el `ws_lim` viejo; no re-transporta α). Correcto.
- **El «margen continuo» propuesto para retomar frente a D2.2, 4547861, D2.4/C-091 y A20-2:** el reporte lo trata como conjetura y retira la frase anterior. Aceptable.
- **Repetición NUEVA latente:** si el brazo K era sin A2 (O1), proponer «un juez B1 de ≥ 3 trayectorias» para la holgura es repetir C-040/C-041. El reporte debe decir que ese experimento muy probablemente ya se hizo, y que solo un diseño distinto (barrera o margen, no la holgura accidental de A2 = 1) justifica otro juez.

## 3. Objeciones

**O1 (bloqueante).** La identificación del binario del brazo K sí se puede resolver con los audit.csv que hay en disco, y apunta a v2 sin A2.
- **Cifras:** n14/n15 frente a n12, entre 1e-17 y 1e-15. k1pa_340 frente a k1_340 en vol_lim: +7.1e-9, +2.4e-8, +1.4e-8, +9.6e-8… Calibración en 342: sin A2, +1.3e-9; con A2, −4.48e-7.
- **Qué corregir:** el punto 7, «Qué hacer si se retoma», «Tampoco está refutada la holgura…» y la viñeta de la entrada staged de `.claude/rules/acople-pv.md`. Deben decir que lo más probable es que la holgura se juzgara en B1 (C-041) y que no es «no verificable».
- **Prueba fuerte:** recompilar P-a y P-b con la receta del propio reporte y correr 10 pasos desde judge_otp_280/eaf3d_00340000.h5 a 12 ranks, comparando bit a bit con el audit de k1pa_340_n12.

**O2 (no bloqueante).** «La holgura solo está MEDIDA en k1pa_342» omite a k1_342 (v1).
- k1_342 tiene ag_min 0.01834 y osc2 209 Pa (calibración de C-035/C-036; C-037 «idéntico a v1 en la sonda»), y p_max idéntico a k1pa_342 en menos de 1.4 Pa en los primeros pasos.
- La familia con holgura suma 4 trayectorias en B1 (k1_340 más las tres k1pa_340).
- **Qué corregir:** la frase en el reporte y en acople-pv.md.

**O3 (no bloqueante).** El «sin traslado del defecto» de C-312 se limita a vol_lim, vol_unlinked, m_spill y m_alpha_clip, y K funde de un 1.5 a un 2.1 % más en 340–345.3 s.
- **Qué corregir:** acotar la frase o anotar el exceso de fusión, a partir de los audit.csv de las 7 trayectorias más k1_340.

## 4. Archivos

- /Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K1/report.md
- /Users/frariv/Horno/hornofusion-full3D/.claude/rules/acople-pv.md (entrada «Plan K CERRADO», línea 618 en adelante, staged)
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/{k1_340,k1pa_340_n12,k1pa_340_n14,k1pa_340_n15,k1_342,k1pa_342,k1b_342,k1pb_342,judge_otp_280,base_340_n14,base_340_n15}/audit.csv

VEREDICTO: rechaza