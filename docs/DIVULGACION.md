# ¿Qué hace este simulador? — Guía de divulgación

Una explicación sin jerga técnica sobre qué es, para qué sirve y cómo funciona **EAF3D**.

---

## El problema que resuelve

Cada vez que compramos un coche, una lavadora o un edificio, gran parte del acero que lo compone
pasó por un **horno de arco eléctrico** (en inglés, *Electric Arc Furnace* o EAF).
Es una cuba cilíndrica del tamaño de una habitación, hecha de acero refractario, en la que se
funden chatarra y materias primas para producir acero nuevo.

El proceso es extraordinariamente intenso: tres electrodos de grafito del grosor de un árbol
adulto bajan desde el techo y generan un **arco eléctrico** — básicamente un rayo permanente —
a 55 000 amperios y 500 voltios. La temperatura en el núcleo del arco supera los **10 000 K**
(diecisiete veces más caliente que la superficie del Sol).

En unos 40–90 minutos, decenas de toneladas de chatarra a temperatura ambiente se convierten
en acero líquido a 1 600 °C.

---

## Por qué es difícil de diseñar y optimizar

El interior del horno durante la fusión es prácticamente inaccesible:
- Las temperaturas destruyen cualquier sensor en segundos.
- El arco emite luz ultravioleta, vapores metálicos y polvo que ciegan las cámaras.
- La chatarra sólida, el acero líquido, los gases y la escoria coexisten al mismo tiempo,
  chocando, fundiéndose y reaccionando entre sí.

Como resultado, los ingenieros han diseñado hornos durante décadas guiándose principalmente
por **experiencia y ensayo-error**, con escasa visibilidad de lo que ocurre dentro.

---

## Qué es este simulador

**EAF3D** es un programa de computadora que recrea virtualmente el interior de un horno de
arco eléctrico, en tres dimensiones y a lo largo del tiempo.

En lugar de encender un horno real, el simulador resuelve las ecuaciones físicas que describen
lo que ocurre dentro:

| ¿Qué modela? | En términos cotidianos |
|---|---|
| **Flujo de fluidos** | Cómo se mueven el acero líquido y los gases calientes |
| **Transferencia de calor** | Cómo fluye la energía del arco al sólido, al líquido y al gas |
| **Fusión y solidificación** | Cuándo y dónde la chatarra sólida pasa a ser acero líquido |
| **Reacciones químicas** | El carbono de la chatarra reacciona con el oxígeno formando CO y CO₂ |
| **Radiación** | Cómo los "rayos de calor" del arco viajan por el interior y calientan la chatarra |
| **Campo electromagnético** | Cómo la corriente eléctrica gigantesca agita el baño de acero |
| **Escoria** | La capa flotante de óxidos que protege el acero del gas |

Todo esto ocurre **al mismo tiempo** y **se afecta mutuamente**. El simulador actualiza todos
estos fenómenos cada medio segundo de tiempo simulado, repitiendo el cálculo miles de veces
para cubrir el ciclo completo del horno.

---

## Una analogía: el horno como una olla a presión muy complicada

Imagina que quieres saber exactamente qué ocurre dentro de una olla a presión mientras cocinas:
dónde hierve primero el agua, cómo circula el vapor, cómo se distribuye el calor en la comida.
Podrías abrir la olla para mirar, pero eso cambia el experimento.

Un simulador hace exactamente eso: en lugar de abrir la olla, resuelve las ecuaciones de la
física para predecir qué ocurre en cada punto del interior, en cada momento.

En el caso del horno de arco, la "olla" tiene un radio de casi 4 metros, pesa cientos de
toneladas y opera a temperaturas que derriten cualquier metal conocido. Un simulador es la
única forma práctica de "ver" su interior.

---

## Cómo funciona por dentro (sin ecuaciones)

### 1. El dominio: una rodaja de pastel de 360°

El horno es cilíndrico, así que el simulador lo divide en una cuadrícula tridimensional con
coordenadas **radiales** (del centro al borde), **angulares** (la vuelta completa) y
**verticales** (del suelo al techo).

Con la configuración de producción, esa cuadrícula tiene **600 000 celdas** — pequeños
cubitos de volumen donde el simulador calcula temperatura, velocidad, composición, etc.

### 2. El algoritmo SIMPLE

El corazón del simulador es un método llamado **SIMPLE** (*Semi-Implicit Method for
Pressure-Linked Equations*). En cada instante de tiempo, hace lo siguiente:

1. Calcula cómo se moverán los fluidos dado el campo de presiones actual.
2. Comprueba si ese movimiento viola la conservación de masa (si "sobra" o "falta" fluido).
3. Corrige la presión para que todo encaje.
4. Repite hasta que la solución es consistente.

Es como ajustar un sistema de tuberías: si cambias el caudal en un sitio, la presión cambia
en todos los demás, y hay que iterar hasta encontrar el equilibrio.

### 3. El arco eléctrico: la fuente de energía

El arco se modela de dos formas:
- **Cassie-Mayr:** una ecuación diferencial que describe la resistencia del plasma del arco
  en función de su temperatura y la corriente que lo atraviesa.
- **Monte Carlo:** miles de "rayos de calor" virtuales se lanzan desde el arco en
  direcciones aleatorias y se siguen hasta que chocan con la chatarra o la pared, depositando
  su energía donde impacten.

### 4. Las tres fases conviviendo

En cada celda del dominio pueden coexistir simultáneamente:
- **Chatarra sólida** (acero sin fundir)
- **Acero líquido** (ya fundido)
- **Gas** (mezcla de aire, CO y CO₂)

El simulador calcula qué fracción del volumen ocupa cada fase y cómo interactúan entre sí.
Cuando la temperatura del sólido supera los 1 600 K, empieza a fundirse y transfiere masa
a la fase líquida.

### 5. La química del carbono

La chatarra contiene carbono. A alta temperatura, el carbono reacciona con el oxígeno del aire:

```
C  +  ½O₂  →  CO     (primera combustión, en la superficie de la chatarra)
CO +  ½O₂  →  CO₂    (segunda combustión, en el gas caliente)
```

Ambas reacciones liberan calor adicional y el simulador las sigue en el tiempo,
calculando cuánto CO y CO₂ hay en cada punto del horno.

---

## Qué se puede aprender con este simulador

- **¿Cuánto tarda en fundirse la chatarra?** El simulador predice que el primer acero
  líquido aparece alrededor de los 105 minutos de operación para las condiciones de diseño.

- **¿Dónde llega mejor el calor del arco?** La zona directamente bajo los electrodos se
  calienta diez veces más rápido que el borde del horno. El simulador muestra el mapa completo.

- **¿Cómo agita el arco el baño metálico?** La corriente eléctrica genera fuerzas
  electromagnéticas (Lorentz) que empujan el acero líquido hacia afuera, creando una
  circulación que homogeneiza la composición química del baño.

- **¿Cuándo hay riesgo de sobrecargar el gas con CO?** El simulador rastrea la fracción
  másica de CO en todo el volumen, permitiendo detectar zonas de acumulación peligrosa.

- **¿Qué pasa cuando se añade la segunda carga de chatarra?** A los 35 minutos se vierte
  un segundo "cubo" de chatarra fría. El simulador muestra cómo cae la temperatura y cuánto
  tarda en recuperarse el ritmo de calentamiento.

---

## Por qué el cálculo es tan pesado

Resolver las ecuaciones para 600 000 celdas, 10 000 pasos de tiempo y una docena de
fenómenos físicos acoplados requiere una enorme cantidad de operaciones matemáticas.

Para hacerlo en un tiempo razonable, el simulador usa **cálculo paralelo**: divide el horno
en sectores y asigna cada sector a un procesador diferente. Con 12 procesadores, cada uno
trabaja sobre unas 50 000 celdas, reduciendo el tiempo de cómputo proporcionalmente.

La coordinación entre procesadores — intercambiar información en los bordes de cada sector —
se hace con un protocolo estándar llamado **MPI** (*Message Passing Interface*), el mismo
que usan los supercomputadores más grandes del mundo.

---

## Los resultados: lo que se puede ver

Al terminar, el simulador genera archivos con todos los campos en cada instante:

- **Temperatura del sólido, el líquido y el gas** en cada punto del horno.
- **Velocidad del acero líquido** — los vórtices que mezclan el baño.
- **Fracción de chatarra sólida** que queda — el mapa de fusión.
- **Concentración de CO y CO₂** — la "huella química" de la combustión.
- **Fuente de calor del arco** — dónde se deposita la energía del rayo eléctrico.

Estos resultados se pueden visualizar con herramientas estándar (ParaView, Python/matplotlib)
y comparar con mediciones reales del horno para validar y mejorar el modelo.

---

## En resumen

EAF3D es un **gemelo digital** del horno de arco eléctrico: una réplica virtual que permite
experimentar, optimizar y entender un proceso industrial que, de otra forma, sería demasiado
extremo, peligroso y opaco para estudiarlo directamente.

Su objetivo final es ayudar a diseñar hornos más eficientes que consuman menos energía,
produzcan menos emisiones y fabriquen acero de mayor calidad — contribuyendo a una industria
siderúrgica más sostenible.

---

*Para más detalles técnicos: [`PHYSICS.md`](PHYSICS.md) (modelos físicos), [`ARCHITECTURE.md`](ARCHITECTURE.md) (estructura del código), [`RUNNING.md`](RUNNING.md) (cómo ejecutar).*
