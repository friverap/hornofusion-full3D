**Resultado:** apruebo el cierre de WS-K1. La conclusión central se sostiene por la letra de los criterios: G1 no se cumplió y el estado propuesto es `fallido`. Dejo seis objeciones, ninguna bloqueante (R1–R6). Solo leí datos; no corrí nada.

# Revisión WS-K1, ronda 1: refutador

Reporte revisado: `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K1/report.md`.

## 1. Conclusiones, alternativas y dato que las separa

### C1. H1 refutada {C-011 → C-012}
- **Alternativa:** H1 no refuta el mecanismo; refuta un criterio con dos defectos.
  - La convergencia del 0 % la produce la tolerancia 1e-6. Según P-b {C-038}, v2 también queda 99.8 % sin converger con esa tolerancia.
  - El umbral |p| < 20 kPa estaba mal planteado: los 69 kPa son la media del ciclo frenando un chorro {C-031}.
  - El vol_lim de la celda no se midió.
  - Mientras tanto, la oscilación sí desapareció: osc2 bajó de 51.8 kPa a 342 Pa.
- **Dato que las separa:** ya está en el registro (C-038 y C-031).
- **Cómo queda:** la refutación es literal y válida. La «Incertidumbre» lo reconoce («se refutaron los criterios»), pero el punto 1 no lo dice (R3).

### C2. H1b refutada {C-025 → C-028}, por el inciso (c)
- **Alternativa:** (c) mide el pico que produce F2.31, no el limitador.
- **Dato que las separa:** el recuento de `act_l/g=TF` por paso en la celda sonda (10,60,2), en los `run.log`. Lo revisé:

| Corrida | Pasos con TF (outers con TF) | Lectura |
|---|---|---|
| k1b_342 | 342534 (1), 342535 (3), 342536 (4), 342537 (4), 342538 (4) | Coinciden con los pasos > 1e5: 342534 410 kPa, 342535 342 kPa, 342536 144 kPa, 342537 122 kPa |
| k1pb_342 | mismo patrón, 342534–342540 | — |
| Base: diag_p342p, diag_p342q, diag_h0lim | 342535–342537 | Mismo mecanismo que C-088 y que la sección del 22-oct |
| k1_342 y k1pa_342 | 0 | p_max plano, de unos 69 kPa |

- **Cómo queda:** (c) falla por la cadena ciclo → exclusión F2.31 → pico, idéntica a la de la base y un paso antes. Esto no tumba el veredicto.
  - Además, es un marcador NO circular de que k1b reproduce la cadena de la base. Es más sólido que la métrica de C-036, que se calibró con k1b, y el reporte no lo usa.
  - Pero también muestra que el Plan K dejó F2.31 intacto por diseño (§3.3), y que `pc_ai_fsat`, la subclave pensada para esa interacción, nunca se probó (R1).

### C3. «Ganó la holgura» {C-039}
- **Alternativas:** el ingrediente es `unl_on=.false.` y no el factor de A2; o los binarios no son los que se declaran.
- **Cómo queda:** el reporte ya concede las dos y nombra el dato (hash del binario o recompilación). No añado nada.

### C4. Plan K no adoptado; el juez de 3 trayectorias refutado {C-041}
- **Alternativa:** la holgura funciona, y la refutación sale de un estado al que llegó k1pa_340_n15 y que la base también sostendría.
- **Dato que las separa:** la base corrida desde un snapshot de k1pa_340_n15 anterior a 345.25 s. No está en disco.
- **Lo que ya dicen los datos (C-312/C-313):**
  - Hasta 345.318 s, las 3 trayectorias K quedan unas 10 veces por debajo de la base.
  - Desde el mismo estado, el brazo sin K también queda ≥ 1e6 Pa.
- **Cómo queda:** el reporte WS-K1 no cita C-312/C-313 y usa «k1pa falló el juez» como argumento contra la holgura (R2).

### C5. El ciclo no es un artefacto del reinicio
- **Dato:** dense_340_n14 (reinicio desde judge_otp_280/eaf3d_00340000.h5, sin `pc_alpha_implicit`). Lo verifiqué y los valores coinciden con el reporte:
  - pmax en [k,j,i] = (1,59,9): 74.5, 94.0, 42.6, 108.0, 42.9 y 636.0 kPa en 342529 y 342531–342535;
  - en 342530 el máximo está en otra celda (48.8 kPa).

### C6. ¿Mueve el problema de sitio?
- En la ventana, vol_lim baja un 0.8 % y vol_unlinked no cambia.
- En 340–345.3 s, C-312 no muestra desplazamiento a vol_lim, vol_unlinked, m_spill ni m_alpha_clip.
- **Cómo queda:** no hay indicio de que el Plan K mueva el defecto.

## 2. Repeticiones de fracasos registrados

- **El Plan K frente a D2.2 y n_pc_max:** el §2 del plan explica la diferencia (conjunto activo dentro del mismo solve frente a ws_lim de la pasada anterior o re-transporte). Es aceptable.
- **El «margen continuo bajo el tope» que el reporte propone para retomar:**
  - Lo compara con 4547861, D2.4 y A20-2.
  - Omite D2.2 y D2.2c (`pc_limiter_faces`), sus parientes más cercanos.
  - Omite también la lección de la «quinta regla local» tras el F2.31 por paso: «no se cura clasificando» (R4).
- **La lectura estructural (H0 + J-B):** es razonamiento sin dato.
  - k1 y k1pa, que también resuelven el conjunto activo dentro del paso con el hueco en αⁿ, sí quitaron el ciclo en la sonda.
  - El «por construcción» solo vale con tope exacto.
  - k1b no tiene una traza por celda del limitador que lo verifique.

## 3. Objeciones (ninguna bloqueante)

1. **R1.** La falla de (c) coincide con la exclusión F2.31, y `pc_ai_fsat` nunca se corrió.
   - **Para resolverla:** documentarlo en el reporte y en la entrada de acople-pv.md.
   - **Experimento:** k1b con `pc_ai_fsat=true`, o con `pc_f231_step_freeze`, en 342.45–342.56 s.
2. **R2.** Faltan C-312/C-313.
   - **Para resolverla:** citarlas en «Incertidumbre» y en «Qué hacer si se retoma».
   - En acople-pv.md, cambiar «Lo que separa a K…» por «lo que separa a k1pa_340_n15; sin prueba de que sea propio de K (C-313)».
3. **R3.** H1 se refuta solo por defectos del criterio.
   - **Para resolverla:** una línea en el punto 1 que remita a C-038.
4. **R4.** Falta decir en qué difiere el margen continuo de D2.2c y de pc_f231_step_freeze, y por qué no sería la sexta regla local.
5. **R5.** La premisa «retraso de un paso» nunca se contrastó con el dt en 342 s.
   - **Experimento:** la base desde diag_p342a con dt 0.5 y 0.25 ms; ver si el periodo se mide en pasos o en segundos. No está en disco; basta con anotarlo como abierto.
6. **R6.** `fallido` frente a `aprobado`: G1 dice «terminado cuando H1b esté juzgada», y lo está.
   - **Para resolverla:** declarar la lectura «H1 cumplida» y el precedente de WS-K3.

## 4. Valoración

La conclusión del cierre es «G1 no cumplida» y el estado `fallido`. Es cierta por la letra de los criterios pre-registrados, y ninguna alternativa la invierte:
- H1 falla en convergencia;
- H1b falla en (c) con 4 de 109 pasos sin los dos pasos del reinicio, frente a 3.49 permitidos;
- la causa de (c) es la misma cadena que en la base.

Las alternativas que encontré afectan a la guía para retomar (qué se refutó del mecanismo y qué falta probar). No afectan al cierre, y el reporte ya rotula esa guía como lectura sin veredicto.

VEREDICTO: aprueba