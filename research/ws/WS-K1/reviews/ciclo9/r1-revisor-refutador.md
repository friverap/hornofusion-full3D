# WS-K1, ciclo 9, ronda 1: revisor-refutador

Revisión ciega: no leí `reviews/`. Fue solo lectura; usé python únicamente para leer los h5 y los audit.csv que ya existen.

## 1. Conclusiones del reporte y su mejor alternativa

**C1. «G1 no cumplida: H1 y H1b refutadas»**
- Alternativa: las dos refutaciones se apoyan en criterios mal planteados (|p| < 20 kPa, C-031; grad_hid ≤ 3) o en un margen de un paso en una sola trayectoria, así que lo correcto sería «sin decidir».
- Lo que las separa: si k1b elimina el ciclo en la sonda o lo reproduce.
- Está en disco y va **en contra de la alternativa**:
  - En 342520–342537, k1b reproduce el ciclo de la base: |d2p| > 1000 Pa en el 100 % de los puntos en las dos, con mediana 40.7 frente a 48.1 kPa y p75 55.2 frente a 52.6 kPa.
  - El pico de k1b es de 410.0 kPa en 342534; el de la base, 413.4 kPa en 342535.
  - Los pasos con p > 100 kPa de k1b (342534–342537) son ese mismo pico.
- La conclusión se sostiene, y con más fuerza de la que el reporte le reconoce (ver O1).

**C2. «No adoptado» fue una decisión, no una refutación del beneficio en B1**
- Alternativa: la bajada de p > 100 kPa de K es un traslado del problema (más líquido en el lecho, más fusión).
- Lo comprobé:
  - dm_liq en [340, 345.3) s: 398.6–400.6 kg en K frente a 392.4–392.6 kg en la base.
  - p > 100 kPa: 2.2–4.6 % en K frente a 10.3–12.2 % en la base.
- El reporte ya lo deja ABIERTO y nombra la serie temporal que lo decidiría. No hay objeción.

**C3. La holgura (sin A2) quita el ciclo (C-039)**
- Alternativa: es una diferencia entre dos trayectorias sueltas.
- Lo comprobé: k1 ≡ k1pa (|Δp| ≤ 17 Pa) y k1b ≡ k1pb (≤ 96 Pa), así que es 1 contra 1.
- A favor del mecanismo: la separación es determinista y empieza en 342506, el mismo paso en que arranca el ciclo de la base. Ver O3.

**C4. «No reintentar el conjunto activo con tope exacto» (lectura estructural)**
- El reporte dice que esta directiva «es más fuerte que los datos», porque «en la sonda el tope exacto mejora a la base».
- Ver O1: esa mejora está entera **después** del pico (342538–342560: 14 % frente a 100 %), en una trayectoria. Dentro del ciclo, k1b ≈ base.
- Los datos apoyan la lectura estructural, no la salvedad del reporte.

**C5. Brazo K del juez = v2 sin A2, solo declarado**
- El reporte lo deja abierto y nombra la prueba bit a bit que lo decidiría. No hay objeción.

## 2. Repeticiones de fracasos registrados

- **D2.2 (limitador en el Poisson):** está tratada. El reporte, punto (iv) de Incertidumbre, y PLAN_K §2 dicen en qué difiere: el conjunto activo se converge en el mismo solve, frente al `ws_lim` viejo de D2.2. También dicen que la diferencia es una conjetura y que D2.2 es condicional (bed_flood, 7-oct).
- **`n_pc_max`:** PLAN_K §2 lo distingue.
- **Reglas de clasificación D/E/F/G:** las recoge reevaluacion.md (líneas 19, 50 y 79). Con tope exacto, el dato de k1b (C1) muestra que el conjunto activo dentro del paso se comporta como otra regla con retraso entre pasos. Es la lección del congelado de F2.31 y la entrada la conserva como lectura estructural.
- **Guía contra repeticiones:** el diff staged la quita de la regla permanente (O2).

## 3. Objeciones

- **O1 (bloqueante).** «Amplitud 3.4× menor» y «el tope exacto mejora a la base en la sonda (47 frente a 85 %)» salen de la elección de ventana: un arranque 5–8 pasos más tarde y el tramo posterior al pico. Dentro del ciclo, k1b ≈ base, como ya dice C-028 («RECUPERA el ciclo»). Hay que reescribir con los datos segmentados por tramo:
  - punto 4, línea 110;
  - Incertidumbre, líneas 280–294 y 322–334.
  - Datos: p[1,59,9] de diag_p342b, k1b_342 y k1_342.
  - Tramos: 342500–342537, 342520–342537 y 342538–342560.
- **O2 (no bloqueante).** La entrada staged quita «juez B1 ≥ 3 trayectorias, no la ventana corta (k1pa la pasó y falló C-041)» y «en qué difiere de 4547861/D2.4/A20-2».
  - La lista «Se retiraron» no lo menciona.
  - Las viñetas de los ciclos 3 y 6 quedan desfasadas.
  - El reporte de WS-K2 (HEAD, líneas 272–287) cita acople-pv.md:659–666, que queda colgada.
  - Arreglo: volver a poner una línea en la entrada o declararlo y marcar esas viñetas como superadas.
- **O3 (no bloqueante).** C-039 es 1 trayectoria contra 1; las supuestas «dos variantes» son la misma. Hay que decirlo, junto con que la separación empieza en 342506. Lo decidirían P-a y P-b a 14/15 ranks, que no existen.

## Verificado (solo lectura)

- Series de la sonda en las cinco corridas de 342 s: identidades por pareja y separación en 342506.
- Métricas por tramo (342500–342560, 342500–342537, 342520–342537 y 342538–342560).
- dm_liq y p > 100 kPa en 340–345.3 s en las siete trayectorias.
- La entrada staged frente a HEAD.
- C-025, C-028, C-039, C-040, C-041, C-065 y C-309 a C-313.

VEREDICTO: rechaza
