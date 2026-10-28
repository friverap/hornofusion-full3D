# WS-K11, ronda 1: revisor refutador

Solo lectura: abrí audit.csv, config.dat, run.log y los snapshots HDF5 con python; no compilé ni corrí nada. No leí `reviews/`.

## 1. Conclusiones, alternativas y dato que las separa

| Conclusión del reporte | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| Encender f28 sobre un estado escrito sin ella es NECESARIO para la firma (0.25 ms, 60 ms) | Hace falta f28 encendida más una propiedad X de los estados fh; el «cambio» es solo cómo se llega a esa combinación | Una corrida larga sin f28 con la columna nolink; apagar f28 sobre un estado jb u otp; otro linaje sin f28 (e2, fhe1, rampbelow 280-299.999) | No. Las únicas corridas con f28 apagada que tienen la columna son A, H, M, N y O, todas de 60 ms. No hay reinicio que apague f28 sobre un estado escrito con ella |
| NO suficiente (P, fh 300 s) | El snapshot final de la corrida es distinto (último paso truncado) | restart/dt del snapshot 299999 | Sí: dt = 1e-3, igual que en los demás. Descarto esta alternativa |
| Régimen ≥ 100 kPa tras el cambio: trabado o transitorio, «sin decidir; solo lo decide ≥ 300 ms» | Transitorio que decae, y F/k10b frente a G no se distinguen por el estado: es dispersión entre trayectorias | Otra trayectoria del mismo estado fh 280 s con el cambio | **Sí: `k11_dt025_tgfix`**. Nolink solo en 280002-280023. Medias por cuartos de 138.0, 105.1, 99.5 y 83.9 kPa y |Δp| de 73.7 a 17.8, hacia el nivel de C/E. Sin los 483 y 592 kPa. Apoya la lectura (b) |
| «Edad del cambio» plausible porque B y F acaban con nolink | El nolink final depende de la trayectoria | El gemelo de F | tgfix acaba sin nolink, con 42-104 kPa |
| La firma es común con el episodio de 284 s de B1; (i) y (ii) sin separar | (ii), o bien que la familia de 284 s existe sin cambio y el nolink es solo un marcador | Lugar y clase de las celdas nolink en los dos casos; filas de nivel centinela en trayectorias sin f28 | En parte. 86 de las 96 filas de nivel centinela de `k7v4_long` llevan nolink. `judge_e2_275` (sin f28) tiene 29 filas en 282-287 s. jb, tras su cambio en 275 s a 1 ms, solo 0-1 filas en 275-280 s. `k7v4_long/eaf3d_00285000.h5` está dentro del episodio, con nolink 51 pasos después |
| comp_carry como candidata para la no respuesta de P | Es un marcador genérico de p ≠ EOS al escribir | comp_carry en estados que sí responden o que están en régimen de firma | Sí: 4.2e-6 en el final de F, 4.1e-7 en el final de B, 1e-8 a 1.5e-7 en jb y otp. No distingue |
| M20-2 se decidió sobre el transitorio | M20-2 empeora de verdad la respuesta a una perturbación | La ventana sin arranque | Sí: 66.1 frente a 51.3 kPa y 1 fila frente a 0, sigue peor. El commit cita además 255-258 s (neutra) |

## 2. Repeticiones de fracasos registrados

No hay cambio numérico, así que no es una repetición de D2.2, de Plan D/K ni de `n_pc_max`. La prueba propuesta para P (copia con comp_carry = 0) reutiliza el método de H12 (C-225, refutada para Tg_end). Es otra variable, pero el reporte debe decir por qué esperaría otro resultado (R6).

## 3. Objeciones

- **R1 (bloqueante).** Falta `k11_dt025_tgfix`, el brazo número 20 con cambio a 0.25 ms. Rebate la plausibilidad de la «edad del cambio» (el gemelo de F acaba sin nolink) y aporta un dato a favor de que el régimen decae. Explica también F frente a G como dispersión de trayectorias, y muestra que los 592 kPa de `regime_p` dependen de la trayectoria. *Resolución:* incluirlo en `h22.py --todos` y en las tablas, y reescribir los párrafos «si el régimen decae» y «edad del cambio».
- **R2.** La dicotomía «edad» frente a «escritor» está mal planteada, porque el reinicio es una continuación. *Resolución:* plantearla como una propiedad X del estado y proponer una prueba que la manipule.
- **R3.** El discriminador (i)/(ii) puede hacerse con un reinicio corto desde `k7v4_long/eaf3d_00285000.h5` más PROBE-P en 285051-285064. Faltan además los datos de e2 y de jb tras su cambio. *Resolución:* citarlos y proponer ese reinicio.
- **R4.** H22 era una predicción de bajo riesgo: nunca se ha medido nolink con f28 apagada fuera de 60 ms. *Resolución:* decirlo; la única prueba exigente fue H23.
- **R5.** El cambio solo se probó en un sentido. *Resolución:* reiniciar con f28 apagada desde jb 280 u otp 290, o acotar el titular.
- **R6.** comp_carry ≠ 0 es habitual. *Resolución:* citar los valores y fijar un prior bajo.
- **R7.** M20-2: los datos no piden reabrirla. *Resolución:* añadir que fuera del arranque m202 sigue peor y la ventana 255-258 s.

VEREDICTO: rechaza
