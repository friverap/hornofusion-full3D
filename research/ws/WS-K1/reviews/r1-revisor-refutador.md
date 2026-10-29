# WS-K1, ronda 1: revisión del refutador

Revisé solo leyendo: el reporte, el registro (show/open), `acople-pv.md` y `PLAN_K` staged, h5/audit/run.log ya existentes. No ejecuté corridas.

## Veredicto

La conclusión resiste: G1 no se cumplió y el estado que corresponde es `fallido`. Ninguna hipótesis alternativa la vuelve falsa:
- H1 falla por la letra. El propio reporte reconoce que sus criterios son débiles.
- H1b falla en (c) y, lo que pesa más, en lo que afirma. Dentro de 342520–342537, k1b reproduce el ciclo de la base: |d2p| > 1 kPa en el 100 % de los puntos y el mismo pico. Lo recomprobé.
- No adoptar el Plan K fue decisión del usuario (C-065).

Mis tres objeciones no son bloqueantes. Afinan lo que queda ABIERTO en el registro permanente.

## 1. Conclusiones, su mejor alternativa y el dato que las separa

**G1 no cumplida (H1 refutada).**
- Alternativa: H1 no se juzgó de verdad. Su tolerancia no es verificable y el criterio |p| está mal planteado (C-031). Sería «no juzgable», no refutada.
- Por qué no cambia nada: G1 cae igual por H1b. El reporte ya lo dice («criterios débiles»).

**H1b refutada.**
- Alternativa A: el exceso de (c) es ruido de una sola trayectoria, porque falla por un paso.
- Dato que las separa: la serie de la sonda. Ya está en disco. Los 4 pasos de exceso (342534–342537) son el pico de la base reproducido. En 342520–342537, k1b tiene la mediana de |d2p| en 37–41 kPa, frente a 48 kPa en la base. Lo verifiqué. k1pb no es una réplica independiente; el reporte lo admite.
- Alternativa B: la implementación quedó inerte en la celda.
- Por qué se descarta: [PROBE-AI] muestra un conjunto activo vivo, con 34 a 69 caras fijas, y k1b se separa de k1 en 342506. La celda sí está afectada.

**Ganó la holgura (C-039), que queda ABIERTO en el registro.**
- Alternativa: la holgura solo mantiene a (10,60,2) bajo el tope en esa ventana; el retraso entre pasos de H0 sigue en todo el dominio.
- Dato: ya está en disco y apoya la alternativa (O1).
  - El conjunto activo alterna de un paso al siguiente en k1pa: fracción 0.96–1.0, unas ±10 caras sobre 66–71.
  - El vol_lim global alterna por paso con fracción 0.98 en todas las variantes K, frente a 0.74 en la base.
  - Tras el pico, k1pa alterna en la sonda con una amplitud de 0.6 a 3.7 kPa, más que k1b (≈ 0.75 kPa) (O2).

**La bajada de p>100k en B1 podría ser un traslado del problema.** El reporte ya plantea la alternativa (más líquido en el lecho y +6–8 kg de fusión) y nombra el dato que la decidiría: una serie temporal, que no existe. No tengo nada que añadir.

## 2. Repeticiones de fracasos registrados

- **D2.2/D2.2c** (Plan D): el reporte los trata como el precedente más cercano, con su salvedad de banco y de vigencia, y la guía de retoma los incluye. Bien.
- **n_pc_max = 3** (acople-pv.md, entrada del corrector interno): PLAN_K §2 sí lo distingue. La guía de retoma del registro no lo nombra (O3).
- No encontré clasificaciones locales D/E/F/G disfrazadas.

## 3. Objeciones

- **O1 (no bloqueante).** La holgura de C-039 se midió en una sola celda. El conjunto activo y el vol_lim global siguen alternando por paso en la variante con holgura, así que la «lectura alternativa» del punto 4 ya tiene un dato a nivel de conjunto activo.
  - Resolución: una línea en el punto 7, en «Qué hacer si se retoma» y en la viñeta ABIERTO de «Plan K CERRADO».
  - Datos: `campaigns/b1/{k1b_342,k1pb_342,k1pa_342}/run.log` ([PROBE-AI]) y `audit.csv`.
- **O2 (no bloqueante).** «Liso» frente a «cicla» después del pico depende del umbral de 1 kPa. Si se analiza k1pa por tramos, igual que k1b, la comparación entre holgura y tope exacto se invierte después del pico.
  - Resolución: una frase en el punto 4 y en la viñeta de C-033.
  - Datos: `p[1,59,9]` de los h5, 342538–342560.
- **O3 (no bloqueante).** Añadir n_pc_max a la lista de la guía de retoma. Una barrera en el Poisson con el momento congelado sigue siendo un esquema segregado. Es solo texto.

VEREDICTO: aprueba
