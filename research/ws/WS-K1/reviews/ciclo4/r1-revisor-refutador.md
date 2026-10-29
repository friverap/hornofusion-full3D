Ninguna explicación alternativa que encontré hace verdadera la meta G1, así que apruebo el cierre como `fallido`. Dejo tres objeciones, ninguna bloqueante.

# Revisión: revisor-refutador, WS-K1, ronda 1

**Leído:** `research/ws/WS-K1/report.md`, `research/README.md`, `research/QUESTION.md` (G1), `docs/PLAN_K_limitador_en_poisson.md` (§2, §4 y §6) y `docs/PLAN_D_acople_implicito_alpha_p.md` (§3 y §7). También la entrada «Plan K CERRADO» de `.claude/rules/acople-pv.md` y, en el registro, C-011, C-012, C-025, C-028, C-031, C-034, C-036, C-038, C-039, C-041, C-065 y C-310 a C-313.

**Comprobado por mí, solo leyendo datos:**
- Los `audit.csv` de 342.45 ≤ t < 342.56 tienen 111 filas.
- Pasos con p_max > 1e5:
  - base: 342451, 342452, 342535 (413 kPa), 342536, 342537, 342539 y 342541;
  - k1 y k1pa: solo 342451 y 342452;
  - k1b y k1pb: 342451, 342452 y 342534–342537, con valores casi idénticos (409995 frente a 409991 Pa).
- Series [PROBE-P] de `run.log` en k1b_342 y k1pa_342, pasos 342506–342535.
- En `campaigns/bin` no hay binarios k1, k1b, k1pa ni k1pb.

## 1. Conclusiones, hipótesis alternativa y dato que las separa

**C1. «G1 no se cumplió; H1 refutada» (C-012).**
- *Alternativa:* el fracaso se debe al criterio |p| < 20 kPa, que estaba mal planteado (C-031).
- *Qué la descarta:* la convergencia. H1 exigía ≥ 95 % y dio 0 % (205 de 205 al tope). Eso no depende del criterio de presión, así que H1 falla por la letra igualmente.

**C2. «H1b refutada» (C-028).**
- *Alternativa 1:* el inciso (c) falla solo por el ruido de una trayectoria y por los dos pasos del reinicio.
  - *Qué la separa:* comparar brazos que comparten el reinicio.
  - *Qué dicen los datos:* k1 y k1pa tienen solo los 2 pasos del reinicio. k1b y k1pb reproducen el pico de 410 kPa de la base (base 413 kPa en 342535; k1b 410 kPa en 342534) y tres pasos más por encima de 100 kPa.
  - El fallo de (c) no es ruido. k1b no mejora a la base en picos (4 frente a 5, sin contar el reinicio), y el pico depende de la variante: las versiones con holgura no lo tienen.
- *Alternativa 2:* el ciclo de k1b es débil o es un artefacto de la métrica circular de C-036.
  - *Qué la separa:* una serie que no dependa de C-036.
  - *Qué dicen los datos:* [PROBE-P] de k1b muestra α_g al inicio del paso en el piso exacto 0.0150 un paso sí y otro no, de 342507 a 342533. pp alterna de signo y crece de ~0.8 a ~40 kPa hasta el pico de 342534.
  - En k1pa, α_g0 sube de forma monótona entre 0.0184 y 0.0194, sin alternar.
  - Es una alternancia de periodo 2, ligada al piso y que crece. Esto refuerza la conclusión (objeción O3).
- *Alternativa 3:* k1b no corrió el binario post-auditoría que exige C-025.
  - *Qué dicen los datos:* no se puede verificar. Hay un indicio: k1b ≈ k1pb paso a paso (O2).
  - Aunque fuera cierta, G1 seguiría sin cumplirse: un H1b mal juzgado no cumple la meta, y el usuario decidió no adoptar el Plan K.

**C3. «Ganó la holgura» (C-039).**
- *Alternativa:* lo que quita el ciclo es `unl_on = .false.` y no el factor de cuota.
- El reporte ya lo admite: no hay corrida que separe los dos ingredientes. No entra en el veredicto de G1.

**C4. Lectura estructural: «un conjunto activo con tope exacto reproduce por construcción el retraso entre pasos».**
- *Alternativa:* lo que la serie de k1b muestra es que la celda se llena exactamente hasta el tope en un paso y al siguiente la presión se invierte, es decir, que no hay amortiguamiento. Un retraso de diseño por sí solo no lo explica.
- *Qué la separa:* una variante con tope exacto y fracción θ < 1 del hueco por paso. No está en disco. El reporte la marca correctamente como lectura sin valor de veredicto.

**¿El problema se mueve de sitio?**
- En la ventana, vol_lim baja −0.8 % y vol_unlinked no cambia.
- En el juez, C-312 y C-313 no ven que el defecto se traslade a spill, alpha_clip ni vol_lim.

**¿Se mide en el sitio que importa?** Sí.
- La ventana empieza en 342450, antes de que arranque el ciclo (~342506).
- dense_340_n14 descarta que el ciclo sea un artefacto del reinicio.
- El reporte reconoce que la ventana no predice B1, ya que k1pa la pasó y falló el juez C-041.

## 2. Repeticiones de fracasos registrados

- El Plan K frente a D2.2 y `n_pc_max` está justificado en el §2 del plan: el limitador se resuelve dentro del paso, no con el de la pasada anterior.
- **La retoma que propone el reporte (margen continuo bajo el tope) omite D2.2/D2.2c** (PLAN_D l. 89-90 y §7). D2.2 cerraba las caras de forma gradual (coeficiente × ws_lim) y fue perjudicial. Ese precedente contradice la frase de que el cierre gradual es «la única razón para esperar un resultado distinto» (O1).

## 3. Objeciones

- **O1 (no bloqueante).** Añadir D2.2/D2.2c a la lista de precedentes del reporte y de acople-pv.md (l. 660-666), con la diferencia (limitador de la pasada anterior frente a margen dentro del paso) y la nota de que su vigencia es condicional, porque Plan D es anterior a las auditorías.
  - *Resolución:* texto de PLAN_D §3 y §7; no hace falta corrida.
- **O2 (no bloqueante).** La duda sobre qué binario se usó afecta también a C-012 y C-028, no solo a C-037, C-038 y C-039.
  - *Resolución:* citar el indicio k1b ≈ k1pb (pasos con p>1e5 idénticos, 409995 frente a 409991 Pa). Para cerrarlo del todo, recompilar con la receta del reporte (plan_k_v2.patch sobre 1bc9832) y comparar bit a bit unos pasos.
- **O3 (no bloqueante).** Citar la serie [PROBE-P] de k1b y k1pa (α_g al inicio del paso y pp antes y después del conjunto activo, 342506–342535) como evidencia no circular de la alternancia de periodo 2 en el piso que crece hasta el pico de 410 kPa. Así se evita leer «3.4× menor» como si el ciclo fuera débil.
  - *Resolución:* ya está en los `run.log`.

## 4. Juicio

Ninguna alternativa hace verdadera G1:
- H1 falla por convergencia, con independencia del criterio de presión;
- H1b falla en (c) por un pico que solo tienen las variantes con tope exacto;
- el Plan K quedó sin objeto por decisión del usuario.

El reporte separa con honestidad lo que es veredicto de lo que es lectura. Las tres objeciones mejoran el registro permanente, pero no cambian el estado `fallido`.

VEREDICTO: aprueba