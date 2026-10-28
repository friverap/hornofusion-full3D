# WS-K11, ronda 1: revisor refutador

Solo lectura. Hice comprobaciones con python sobre los audit.csv, las config.dat y los .h5 existentes; no lancé ninguna corrida.

## 1. Conclusiones, mejor alternativa y dato que las separa

| # | Conclusión del reporte | Mejor alternativa | Dato que separa | ¿Está en los datos? |
|---|---|---|---|---|
| 1 | Encender f28 sobre un estado escrito sin ella es NECESARIO para la firma (0.25 ms, 60 ms, estados probados) | Lo necesario es un estado de la TRAYECTORIA fh (propiedad X), no el cambio: los 7 brazos con f28 encendida sin cambio son jb/otp, con \|Δα_s\| hasta 0.77 frente a fh | f28 encendida/apagada desde `judge_e2_275` 280 s; f28 apagada desde jb 280 s | No. El reporte lo reconoce como «propiedad X», pero el titular sigue hablando del «cambio» (R3) |
| 2 | No suficiente (P, fh 300 s) | El snapshot 299999 es un volcado final distinto | Estructura de los .h5 | Sí: 295000 y 299999 tienen los mismos 60 datasets; descartado |
| 3 | La firma no es exclusiva del reinicio; comparte marcador con el episodio de 284 s de B1; (i)/(ii) sin separar y «a favor de (ii) pesan» 86/96 | Coinciden en el indicador binario, pero son fenómenos distintos | Número de celdas, orden temporal y relación nolink/p | **Sí, y va contra (ii)**: k7v4_long tiene 360 celdas exactas en 144/146 pasos (bloque fijo; 360 = 6×60), frente a 1-16 celdas en los reinicios. En B1 el episodio empieza 0.33 s antes sin nolink (284340, u = 300 m/s, p de 62-87 kPa) y nolink entra de golpe de 0 a 360 en 284669. En k7v4_long, 94/96 pasos con p ≥ 100 kPa llevan nolink; en J 70/219 y en I 56/142. Filas centinela con nolink: J 42/120, I 50/73 (R1) |
| 4 | La presión total no es necesaria ni suficiente | — | — | Aceptado (pares de una clave en 280 s) |
| 5 | La cifra de adopción de f28 no la contamina el arranque | — | — | Aceptado, con la salvedad ya declarada de una trayectoria |
| 6 | M20-2: «la prohibición sigue apoyada» fuera del arranque | Dispersión entre trayectorias | p_max máximo de los bancos hermanos tras el paso 280031 | **Sí**: hermanos con f28 entre 48.3 y 62.6 kPa (otp2_280 62.6), m202_280 66.1; filas 1 frente a 0; scrfh_b llega a 287.7 m/s. Queda dentro de la dispersión (R2) |
| 7 | El régimen tras el cambio decae (tgfix) | Dispersión entre trayectorias | Réplicas | El reporte ya lo declara |
| 8 | Recomienda reiniciar desde un snapshot escrito con las mismas claves | Desplaza el problema (L 300 m/s y s290 450 kPa sin cambio) | — | El reporte ya lo declara |

## 2. Repeticiones de fracasos registrados

Es un workstream de diagnóstico y no cambia `src/`, así que no repite D2.2 (limitador en el Poisson), las reglas locales D/E/F/G ni `n_pc_max`. La prueba que sugiere para P con `comp_carry` = 0 repite el método de H12, ya refutado; el reporte lo señala y le da prior bajo. Correcto.

## 3. Objeciones

**R1 (bloqueante).** El «marcador compartido» entre el reinicio de 0.25 ms y el episodio de 284 s de B1 se reduce a que nolink > 0 en los dos.
- Tamaño: en k7v4_long son 360 celdas constantes, un bloque fijo que se enciende y apaga en 12 tramos; en los reinicios, 1-16 celdas que fluctúan.
- Orden: en B1 el episodio arranca por u_gas sin nolink y con p < 90 kPa, y nolink aparece 0.33 s después con el salto a ≥ 100 kPa.
- Relación con p: en B1, nolink va con casi todo p ≥ 100 kPa (94/96); en I y J, con una minoría.

El reporte omite estos datos y cuenta 86/96 «a favor de (ii)».
*Resolución:* incluir la distribución de `m_gas_cells_nolink` por corrida, el orden temporal y las coincidencias de I y J, y retirar o justificar «a favor de (ii)». Para decidir (i)/(ii): PROBE-P o volcado por celda desde `k7v4_long/eaf3d_00285000.h5` (285051-285064) frente a F en 280002-280004.

**R2 (bloqueante).** Para M20-2, el reporte da «66.1 frente a 51.3 kPa y 1 fila frente a 0» como apoyo de la prohibición. Ese valor queda dentro de la dispersión de los hermanos (48.3-62.6 kPa, scrfh_b a 287.7 m/s). Para f28, el reporte juzga «1 frente a 15 con una trayectoria» como ni apoyo ni contradicción: mismo tipo de dato, criterio distinto.
*Resolución:* reescribir como «ni apoya ni refuta fuera del arranque»; decidirlo con un juez estadístico de m202 frente a m203 desde un estado sin cambio de claves.

**R3 (no bloqueante).** «Necesario» está confundido con el linaje: no hay brazo jb/otp con f28 apagada ni brazo fh sin cambio con f28 encendida.
*Resolución:* reinicios de 0.25 ms desde `judge_e2_275/eaf3d_00280000.h5` (f28 encendida y apagada) y desde jb 280 s con f28 apagada. Mientras no se corran, el titular debería decir «estados de la trayectoria `judge_fh_275`».

**R4 (no bloqueante).** La clase nolink depende de los enlaces del último Poisson (`src/mod_audit.f90:1319-1324`), y k7v4_long usa CG 20 y 5 externas frente a CG 1000 y 20 externas en los brazos de 0.25 ms.
*Resolución:* el mismo reinicio desde `k7v4_long/eaf3d_00285000.h5` con 20 externas y CG 1000, comprobando si se mantienen las 360 celdas.

## Comprobado por mí

- Recuento de nolink y de filas centinela en los 51 audit.csv que tienen la columna. Ninguna corrida fuera de los brazos de K11 y de k7v4_long tiene nolink; k7v5_mo20_1k da 0.
- k7v4_long: primera fila centinela en 284340 sin nolink; 10 de sus 96 filas centinela sin nolink; 360 celdas en 144/146 pasos; tramos 284669-285379.
- Malla 30×60×42 en las dos configs (k7v4_long y k10b_dt025); `diff` entre ellas: CG, externas, dt y salida.
- Bancos M20-2 fuera de 280001-280031: máximos de p_max y número de filas.
- `fh 295000` y `fh 299999` tienen el mismo conjunto de 60 datasets.
- El contador nolink no depende de `pc_transport_f28` en el código del audit, así que «nolink ⇒ f28» no es tautológico.

VEREDICTO: rechaza