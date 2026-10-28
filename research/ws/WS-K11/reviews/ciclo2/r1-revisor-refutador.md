# WS-K11, ronda 1: revisión del refutador

Revisión en solo lectura. He leído el reporte, C-222 y C-236 a C-249, `ledger.py open`, acople-pv (secciones de oct-2026 y del 22-oct), el párrafo de transporte-energia sobre WS-K10/K11 y `src/mod_multiphase.f90:125-150` (f28). Toda la información aquí es interna y confidencial.

## 1. Conclusiones, hipótesis alternativa y dato que las separa

**C1. Con 0.25 ms, el pico lo dispara encender f28 sobre fh280; la presión total no influye.**
- Lo que verifiqué: los config.dat difieren en una sola clave entre A y F, entre F y k10b, y entre C y E. Las series coinciden con su gemelo a ≤ 1e-9. Para fh280 la conclusión es sólida.
- Alternativa 1: el binario viejo que escribió el estado, combinado con f28 (R5). El brazo A no lo separa. Discriminador ya disponible: reiniciar con f28 encendida desde `k11_a_dt025_s280_off/eaf3d_00280236.h5`, un estado escrito por el binario nuevo con f28 apagada.
- Alternativa 2: la presión total también basta sobre fh280. No está probado: la suficiencia solo se midió en jb (R6).

**C2. Lo que importa es el cambio, no la mera presencia de f28 (H16).**
- El propio reporte lo plantea como «propiedad del estado fh». Pero dice que no hay un estado del linaje fh con f28 establecida, y eso es falso. fh275 y jb275 son idénticos (Δα = 0), así que jb y otp son ambos linaje fh con f28 encendida. Eso da dos pares en el mismo instante: F frente a C a 280 s, y B frente a s290 a 290 s. Refuerzan la conclusión (R4).
- Para replicarlo hay snapshots fh/jb de 285 y 295 s (R7).

**C3. «Con 0.25 ms el régimen alto no decae en 60 ms».**
- Alternativa: es un transitorio que decae hacia el nivel de f28 establecida.
- Los datos existentes la apoyan en parte:

  | brazo | media de p_max por cuartos | media \|Δp\| por cuartos |
  |---|---|---|
  | B | 244 / 191 / 148 / 138 kPa | — |
  | k10b_dt025 | — | 73 / 52 / 55 / 31 kPa |

- «No decae» sale solo del conteo de pasos ≥ 100 kPa. **Bloqueante (R1).**

**C4. Con f28 establecida y 0.25 ms no hay pico, solo un «transitorio menor» en C.**
- El brazo C sube de 28 a ~80 kPa y se queda ahí todo el tramo (76/79/79/80 kPa, |Δp| 11 kPa). El brazo A sigue plano en 14.5 kPa.
- Con 0.25 ms, f28 encendida sube la presión y la deja alternando en todos los brazos; el cambio de claves la amplifica.
- H16 se cumple por la letra (umbral de 300 kPa), pero la descripción del régimen está mal. **Bloqueante (R2).**

**C5. «Sí afecta a B1»: el régimen con f28 dura 15-20 s, «jb muestra lo mismo y el linaje apagado no».**
- Filas al nivel de la centinela (u ≥ 299 m/s o p ≥ 300 kPa), cadencia de 5 pasos, 280-295 s:

  | linaje | filas |
  |---|---|
  | fh, claves apagadas | 15 |
  | jb, solo f28 | 1 |
  | otp, juez de B1 | 26 |

- fh tiene 578 kPa a 284.39 s, junto a la parada de B1 de 284.3 s.
- Alternativa: la parada de 284 s es física del estado y no depende de la clave. **Bloqueante (R3).**

**C6. Las celdas nolink aparecen solo con el cambio y con 0.25 ms.** Verificado: 105/235 en k10b y en F, 235/235 en B, 0 en el resto. El mecanismo sigue abierto, como reconoce el reporte.

## 2. Repeticiones de fracasos registrados

Ninguna. Es un diagnóstico sin cambios en `src/`. Lo único: la oscilación de periodo 2 que f28 sostiene con 0.25 ms es de la misma familia que el ciclo α–p del poro (acople-pv 22-oct, Plan K). Conviene citarlo, pero no es una repetición.

## 3. Objeciones

Cada una con el dato o experimento que la resuelve.

- **R1 (bloqueante).** Rehacer la frase «no decae» con las medias por cuartos, que ya están en los audit.csv. Para decidirlo, prolongar B o k10b a ≥ 300 ms desde su `eaf3d_*0236.h5`.
- **R2 (bloqueante).** Describir C/E como un régimen sostenido de ~80 kPa, no como un transitorio. Limitar H16 al pico de los pasos 2-10.
- **R3 (bloqueante).** Añadir los conteos 15 / 1 / 26 y los eventos de fh a 281.47 y 284.39 s. Matizar «Sí afecta a B1» y el texto de la regla.
- **R4.** Corregir «no hay estado fh con f28 establecida» (fh275 = jb275) y usar los dos pares del mismo instante.
- **R5.** Confusor del binario escritor: reiniciar con f28 encendida desde `k11_a…/eaf3d_00280236.h5`.
- **R6.** Presión total sobre fh280: correr un brazo G o reescribir el alcance.
- **R7.** Réplicas desde fh/jb a 285 y 295 s, cuyos snapshots ya existen.
- **R8.** Alcance de la consecuencia: k5, k6, k7, k8s, bench_w280, sonda_* y judge_e1w280 también arrancan del mismo snapshot.
- **R9.** f28 se adoptó con un reinicio que cambiaba claves y una ventana de 1.6 s. Registrar la evidencia de 275-300 s de R3.

VEREDICTO: rechaza