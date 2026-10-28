# WS-K11: revisión del refutador, ronda 1

**Veredicto: aprueba. Tengo 6 objeciones y ninguna es bloqueante.** He intentado refutar el reporte y no encuentro ninguna conclusión que los datos falseen.

Lo que responde el reporte está bien aislado. A y F parten del mismo snapshot, con el mismo binario y la misma config salvo `pc_transport_f28`, y son deterministas: F dispara la centinela y A no. H descarta la presión total. Las generalizaciones (que el cambio sea necesario y no suficiente, la edad del cambio, la relación con B1) están acotadas a «estados probados, 0.25 ms, 60 ms» o marcadas como hipótesis.

Las objeciones corrigen razonamientos o añaden datos que ya existen. Las dejo para que el coordinador las incorpore.

Todo ha sido solo lectura: audit.csv, run.log y snapshots `.h5` con python. No he corrido nada.

## 1. Conclusiones, hipótesis alternativa y dato que las separa

### C1. Encender f28 sobre un estado escrito sin ella es la causa de la centinela de `k10b_dt025`

- **Alternativa:** que la causa sea el binario que escribió el estado, o el acotado de dt.
- **Dato que las separa:** A frente a F (una sola clave distinta) y G, que fue escrito por el binario actual y no acota dt.
- **Qué dice:** el dato ya está y descarta la alternativa.
- **Mi lectura:** se sostiene.

### C2. El cambio es necesario para la firma en los estados probados

- **Alternativa:** lo que importa no es el cambio sino una propiedad X del estado, sumada a la antigüedad. Todos los brazos con f28 encendida y sin cambio son jb/otp, con f28 establecida al menos 5 s. Todos los brazos con cambio son fh.
- **Dato que las separa:** un reinicio con las mismas claves desde un snapshot escrito poco después del cambio. El propio reporte predice que el final de B arrastraría nolink 4.
- **Qué dice:** no se ha corrido. El reporte ya lo trata como hipótesis.
- **Mi lectura:** es cierto en la muestra, pero la recomendación necesita la edad mínima (R3).

### C3. El cambio no es suficiente (P, fh 300 s)

- **Alternativa:** la respuesta necesita además chatarra residual sumergida. En los estados fh que responden hay 212, 212, 191, 189 y 155 celdas; en fh 299.999 s solo 43.
- **Dato que las separa:** reiniciar con f28 encendida desde e2 295 (126 celdas) y e2 299.999 (55), y fhe1 299.999 (101).
- **Qué dice:** está medido por mí, solo lectura. Sigue confundido con el tiempo.
- **Mi lectura:** abierto; véase R2.

### C4. La firma no es exclusiva del reinicio (`k7v4_long`)

- **Alternativa:** el bloque de 360 celdas de `k7v4_long` es un efecto de que el Poisson no converge con CG 20.
- **Dato que las separa:** reiniciar desde `k7v4_long/eaf3d_00285000.h5` con CG 1000.
- **Qué dice:** en `k7v4_long` hay unas 27000 resoluciones sin converger en 27500. No está corrido.
- **Mi lectura:** véase R4.

### C5. La lectura (b), un transitorio que decae, tiene un dato a favor (tgfix)

- **Alternativa:** que coincida con 80 kPa es casualidad entre estados distintos.
- **Dato que las separa:** prolongar tgfix o `k10b_dt025`.
- **Qué dice:** no se ha corrido.
- **Mi lectura:** rebajar a «compatible» (R5).

### C6. La presión total no es necesaria ni suficiente

- **Alternativa:** ninguna que los datos dejen abierta.
- **Dato que las separa:** F, H y E.
- **Qué dice:** ya está.
- **Mi lectura:** se sostiene.

### C7. El conteo de filas de B1 (1, 15 y 26) no explica las paradas

- **Alternativa:** el cambio reciente añade paradas.
- **Dato que las separa:** e2 (sin f28 y sin cambio) tiene 28 filas en 282-287 s.
- **Qué dice:** ya está. El reporte dice «ni apoya ni contradice».
- **Mi lectura:** se sostiene con ese alcance.

## 2. Repeticiones de fracasos registrados

No hay ninguna. WS-K11 es un diagnóstico sin cambios en `src/` y no propone ningún arreglo de la familia D/E/F/G, ni D2.2, ni `n_pc_max`.

- La reinterpretación de M20-2 queda en «ni apoya ni refuta» y no toca la regla. Me parece correcto.
- La prueba de P con `comp_carry` puesto a 0 está marcada como repetición del método de H12, ya refutado, y con prior bajo. Me parece correcto.

## 3. Objeciones

Ninguna es bloqueante.

- **R1. Retirada sin base para B.** tgfix es casi gemelo de F, no de B. B termina con nolink 4 y p_max de 109 a 150 kPa. Lo que dicen los datos es que 2 de los 6 brazos con cambio terminan con nolink (B y F) y 4 sin él (G, I, J y tgfix). La frase debería decir «se retira para F». Afecta al titular, a Incertidumbre y a `transporte-energia.md:391-392`.

- **R2. P y la chatarra sumergida.** Conté las celdas con α_s ≥ ALPHA_BED, α_s < 0.1 y α_l > 0.5:
  - estados fh que responden: 212, 212, 191, 189 y 155;
  - P (fh 299.999 s), que no responde: 43;
  - jb/otp tienen cifras parecidas a fh, así que no es la propiedad X del cambio, pero puede ser un cofactor de la respuesta;
  - es una lectura posterior al resultado, con un solo caso negativo y confundida con el tiempo.

  Ninguna celda del lecho está sobrellenada (room < 0) en los 16 snapshots que revisé, lo que concuerda con R4 de la ronda anterior. Para discriminar: reiniciar con 0.25 ms y f28 encendida, más su control apagado, desde e2 295 y 299.999 y desde fhe1 299.999. Eso cubre además el «un solo linaje» de C-271. Hay que pre-registrarlo; corresponde al coordinador.

- **R3. Falta la edad mínima en la recomendación.** La viñeta de Consecuencia dice «mismas claves» pero no «f28 establecida ≥ 5 s», que la regla sí recoge. Por la continuidad que el propio reporte asume, un snapshot escrito con las mismas claves 60 ms después del cambio (el final de B) arrastraría la firma.

- **R4. `k7v4_long` frente a los bancos de 0.25 ms.** Con CG 20 hay unas 27000 resoluciones sin converger de unas 27500, frente a CG 1000 sin avisos en los bancos de 0.25 ms. La clase nolink depende de los enlaces del último Poisson y F2.31 depende del error de presión, así que el bloque fijo de 360 celdas puede ser un efecto de la no convergencia. Discriminador: el reinicio con CG 1000 desde `eaf3d_00285000.h5`, que ya está propuesto. Mientras no se corra, el titular debería decir que solo comparten el indicador y que la convergencia del Poisson es distinta.

- **R5. El dato de tgfix no es «a favor».** Compara un estado fh (83.9 kPa) con uno jb (80 kPa), y su casi gemelo `k10b_dt025` termina en 106.8 kPa con nolink. Que las cifras coincidan puede ser casualidad: rebajarlo a «compatible».

- **R6. Centinelas sin diagnosticar.** Siguen abiertas las de L (C-261), `k11_dt025_s290` (C-237) y P_HYDRO_CAP en I y J, cuyo mecanismo no se conoce. No invalidan el diagnóstico de `k10b_dt025`, pero el cierre no debe presentarse como «toda centinela diagnosticada».

## 4. Lo que comprobé

- **Nolink en los 20 brazos de 0.25 ms.** Los 12 brazos sin cambio dan 0 nolink. En los brazos con cambio, el primer nolink aparece en el paso 2 tras el reinicio (en G, el 280238, que es el paso 2 desde 280236); P no tiene ninguno.
- **Bancos de 1 ms y 0.5 ms.** Todos dan 0 nolink, salvo `k7v4_long`.
- **Patrón de `k7v4_long`.**
  - Primer nolink y primer p_max ≥ 100 kPa en el mismo paso: 284669, con 360 celdas.
  - El conteo es 360 en 144 pasos, 1 en un paso y 4 en otro.
  - Tiene 96 filas de nivel centinela, 86 con nolink; la primera en el paso 284340.
  - Entre 284340 y 284668, p_max va de 35.9 a 87.0 kPa sin ningún nolink.
- **Final de la ventana.** B y F terminan con nolink; G, I y J sin él.
- **P es un snapshot normal.** Es de paso completo, con dt = 1 ms y el mismo grupo `/restart` que los demás; no viene de un paso truncado.
- **Config de P.** Tiene f28 encendida por defecto y la presión total apagada.

VEREDICTO: aprueba