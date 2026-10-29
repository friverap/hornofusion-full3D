# Revisión del refutador: WS-K1, panel de cierre, ronda 2

Fue una revisión de solo lectura. No leí las revisiones de los otros revisores.

## 1. Conclusiones y alternativas

**C1. «G1 no se cumplió; H1, H1b y C-040 refutadas.»**
- **Alternativa:** se refutó la implementación (la exportación al transporte) y no el concepto.
- **Qué la distinguiría:** `vol_lim` y `vol_unl` por celda en (10,60,2).
- **Estado:** no hay datos. El reporte lo declara en Incertidumbre. No objeto la conclusión, porque se limita a los criterios.

**C2. «Plan K no adoptado» es una decisión, no una refutación del beneficio en B1.**
- Ahora está en la Conclusión.
- Verifiqué el motivo de C-065: cita a C-064 «que Plan K destapa». C-294 deja a C-064 como fallida.
- **Alternativa:** el pegado de n15 es propio de la base. Lo apoyan C-312/C-313 y que C-064 diga «Existe con y sin Plan K».
- **Qué la distinguiría:** la base desde un snapshot de n15 anterior a 345.25 s. No existe.

**C3. «Ganó la holgura» (C-039, k1pa_342).**
- **Alternativa:** el efecto viene de quitar la entrada no enlazada (`unl_on = .false.`) y no del factor.
- **Estado:** el reporte lo declara. Verifiqué que `pc_drift_source = true` en las cinco config.dat, así que P-a sí cambia las dos cosas.
- **Qué la distinguiría:** una corrida de factor 1 con `unl_on` activo. No existe.

**C4. Si se retoma, el experimento decisivo es un juez B1 de ≥ 3 trayectorias en 340–345.5 s.**
- Se mide en el sitio correcto. Ya no se apoya en una ventana corta ni en un banco.
- Ahora nombra a D2.2 como precedente más cercano y retira la frase «única razón».

## 2. Repeticiones de fracasos registrados

- **D2.2/D2.2c (Plan D, 7-oct).** Fue un cierre gradual o binario de las caras del líquido en el Poisson, con el momento congelado.
  - Verifiqué las cifras en `docs/dev-history/2026-10-07_plan_d_acople_implicito.md`:
    - D2.2: p>100k 15.2 frente a 8.1 %; centinela 11.2 frente a 4.7 %.
    - D2.2c: 17.1/15.1 frente a 4.9/4.4 %.
  - En report.md está bien tratado: marca la diferencia como conjetura y lo declara condicional.
  - **Falta en `.claude/rules/acople-pv.md`.** `grep -n D2.2` no devuelve nada en todo el archivo. La entrada «Plan K CERRADO» (líneas 668–672) sigue listando solo 4547861, D2.4 y A20-2.
- **El «mecanismo que faltaba» / Bug 16** y el estallido de C-064. Están en el reporte (punto 7), pero no en acople-pv.md.

## 3. Objeciones

1. **O1 (bloqueante, residual).**
   - **Problema:** acople-pv.md va en el diff del cierre (está staged) y sigue sin D2.2/D2.2c en la lista «en qué difiere de lo ya rechazado». Es el archivo que guía el trabajo futuro. Cerrar así deja abierta la repetición que este panel debe impedir. El reporte lo marca como «pendiente para el coordinador», pero lo pendiente no está verificado.
   - **Cómo se resuelve:** el coordinador edita las líneas 668–672. Añade D2.2/D2.2c con sus cifras, la lección de la celda donante y la marca de condicional (bed_flood, 7-oct). Se comprueba con `grep -n 'D2.2' .claude/rules/acople-pv.md`.
2. **O2 (no bloqueante).**
   - **Problema:** acople-pv.md no remite C-064 al «mecanismo que faltaba» de Plan D.
   - **Cómo se resuelve:** una línea de remisión. La causalidad solo la decide un snapshot de n15 anterior a 345.25 s, que no existe.
3. **O3 (no bloqueante).**
   - **Problema:** la frase «no reintentar con tope exacto» de acople-pv.md no dice que k1b y k1pb son una sola trayectoria que en la sonda mejora a la base.
   - **Cómo se resuelve:** añadir esas cifras (885.7 frente a 889.7 Pa; 47 frente a 85 %) o hacer ≥ 3 trayectorias de v2 completo.
4. **O4 (no bloqueante).**
   - **Problema:** P-a confunde el factor con `unl_on`. Ya está declarado en el reporte.
   - **Cómo se resuelve:** una corrida de factor 1 con `unl_on` activo.
5. **O5 (no bloqueante).**
   - **Problema:** acople-pv.md no dice que el «no adoptado» se apoyó en C-064, hoy fallida.
   - **Cómo se resuelve:** una frase en la entrada.

## Verificado

- report.md: D2.2 como (iv), la frase retirada, las cifras de D2.2/D2.2c contra el dev-history y la cita de §2 del plan («la presión veía un limitador viejo»).
- C-064 contiene «Existe con y sin Plan K». El motivo de C-065 cita a C-064. C-294 es fallida.
- `pc_drift_source = true` en k1_342, k1b_342, k1pa_342, k1pb_342 y diag_p342b.
- acople-pv.md, líneas 618–674: no está modificada respecto a la ronda 1 en lo que pedí; no hay ninguna mención de D2.2.
- El §6 del plan no tiene lista de precedentes, así que O1 solo afecta a acople-pv.md.

El reporte en sí resuelve mis objeciones. El rechazo se debe únicamente a que el registro permanente de reglas, que se cierra en el mismo diff, sigue omitiendo el precedente que más se parece a la vía de retoma que el propio cierre recomienda.

VEREDICTO: rechaza