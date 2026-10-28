# WS-K11: revisión del refutador, ronda 1

**Veredicto: rechaza.** El titular («con 0.25 ms, encender f28 sobre un estado escrito sin ella es necesario y no suficiente para la firma») se sostiene tal como está acotado: reproduje todos los brazos con `h22.py --todos`. El problema es la interpretación. Los datos existentes muestran que la firma no es exclusiva del reinicio: `k7v4_long` la tiene a 1 ms, 4.67 s después del cambio y junto a la parada de B1 de 284.3 s. El reporte no separa «artefacto del cambio» de «el cambio dispara antes el mecanismo de las paradas de B1».

## 1. Conclusiones del reporte y su mejor alternativa

| Conclusión | Mejor alternativa | Qué dato las separa | ¿Está ya en los datos? |
|---|---|---|---|
| **El cambio de f28 es necesario para la firma** (12 brazos sin cambio, ninguno con firma) | La firma marca el mecanismo marginal de B1 (celdas multifase sin cara enlazada: familia F2.29/F2.31 de las paradas). El cambio con 0.25 ms solo lo dispara pronto. Sin cambio también aparece, pero más tarde que la ventana de 60 ms. | nolink en una corrida larga sin reinicio. | **Sí, contra el reporte.** `k7v4_long` (1 ms, f28 y presión total desde 280 s) tiene nolink > 0 en 146 pasos desde 284.669 s, hasta 360 celdas. En la ventana 284669-284728 cumple la firma: 59 pasos con nolink, 45 con p_max ≥ 100 kPa y 30 con u ≥ 299 m/s. «Necesario» solo vale para los primeros 60 ms tras reiniciar. |
| **No suficiente** (P, fh 300 s) | El estado de 300 s difiere en alguna variable de reinicio. | Comparar los /restart de los estados fh. | En parte: `comp_carry` vale 2.26e-5 en 299.999 s, frente a 0 en 280-290 s y 1.5e-9 en 295 s. Además es el snapshot final de la corrida. No lo decide, pero es candidata. |
| **Cuenta la edad del cambio, no quién escribió el estado** (lo dice el titular) | La firma depende del estado del linaje fh, con una sola trayectoria. | Reinicio de 0.25 ms desde un snapshot escrito 0.5-1 s después del cambio. | **No corrido.** Los snapshots existen: `judge_e1w280_n15/eaf3d_00280500.h5` y `00281000.h5`, y `k11_b.../eaf3d_00290236.h5`. `k7v4_long` muestra que la «edad» no tiene cota: firma con 4.67 s de f28. |
| **La firma separa el cambio en 5 de 6 estados fh** | Es un solo linaje (fh). G es el mismo estado 60 ms después. | Otro linaje escrito sin f28. | Existen `judge_e2_275` (misma config que fh), `judge_fhe1_275` y `judge_rampbelow`, con snapshots de 280-300 s, sin probar. A 1 ms, encender f28 sobre `judge_rampbelow` en 255 s no da pico (m201_255, otp_255, a202_base: 50 → 54 m/s y 14.6 → 18.5 kPa). Es otra no-suficiencia que el reporte no cita. |
| **El régimen de f28 no explica las paradas de B1** | Las paradas de B1 y la firma del reinicio son el mismo mecanismo con el mismo marcador. | Clase y ubicación de las celdas nolink en k10b_dt025 (pasos 2-4) frente a k7v4_long en 284.67 s. | No medido. El evento de k7v4_long en 284.67 s es el de la familia de 284.3 s (acople-pv.md:605-609). |
| **nolink separa el cambio** («con los 13 brazos») | Separa la firma, que lo incluye por definición. | Los 18 brazos. | **Sí, contra el reporte:** P tiene cambio y nolink 0. |

## 2. Repeticiones de fracasos registrados

- El workstream no cambia código y no repite D2.2, las reglas locales D/E/F/G ni `n_pc_max`.
- Aviso: si la firma resulta ser la clase F2.29/F2.31 (celdas sin ninguna cara enlazada), un arreglo «que trate las celdas nolink» sería la sexta regla local sobre la misma familia (acople-pv.md:587-594). Queda excluido de antemano.
- Contaminación posible del registro de fracasos: M20-2 («no repetir», acople-pv.md:566-568) y la adopción de f28 (2f0529b) se midieron con bancos que encienden f28 sobre `judge_fh_275/eaf3d_00280000.h5` (scrfh_b, scrfh_bfrz, otp_280, m*_280). Esos bancos arrancan con el pico de 215 m/s y faltan en la lista de bancos afectados (R4).

## 3. Objeciones

- **R1 (bloqueante).** `k7v4_long` cumple la firma a 1 ms en 284.669 s, sin reinicio y junto a la parada de 284.3 s. Lo que hay que corregir:
  - Retirar «ninguna celda nolink con 0.5 ni 1 ms» fuera de las ventanas de 60 pasos.
  - Restringir «necesario» a los primeros 60 ms tras reiniciar con 0.25 ms.
  - Separar «artefacto del cambio» de «disparo del mecanismo de las paradas de B1».

  Lo resuelve:
  - Comparar la clase y la ubicación de las celdas nolink (PROBE-P o un volcado por celda) en 280002-280004 de k10b_dt025/F y en 284669-284680 de k7v4_long.
  - Una corrida larga sin cambio reciente, con la columna nolink, a lo largo de 284 s.
- **R2.** Pasar a hipótesis la frase del titular sobre la edad del cambio, o probarla con 0.25 ms desde `judge_e1w280_n15/eaf3d_00281000.h5` (o desde `00280500.h5`, o desde `k11_b.../eaf3d_00290236.h5`). Hay que pre-registrar una escala de edad.
- **R3.** Todos los brazos con firma son de un solo linaje. Probar f28 encendida y apagada con 0.25 ms desde `judge_e2_275/eaf3d_00280000.h5`, y citar los bancos de 255 s (sin pico a 1 ms).
- **R4.** La lista de bancos afectados está incompleta. Faltan scrfh_b, scrfh_bfrz, otp_280, otp2_280, m202_280, m203_280, m21f1_280 y m21f1fix_280 (`grep restart_file` por `judge_fh_275/eaf3d_00280000.h5` con f28 encendida). Hay que marcar que M20-2 y la adopción de f28 se midieron en ventanas que empiezan con el cambio.
- **R5.** Reescribir «nolink separa limpio el cambio» con los 18 brazos: P es un cambio sin nolink, y la firma incluye nolink por definición.
- **R6.** Para «por qué 300 s no responde», comparar solo con lectura los /restart de los estados fh. El candidato inmediato es `comp_carry`: 2.26e-5 en 299.999 s frente a 0 en 280-290 s.

Rutas:
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/k7v4_long/audit.csv
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/judge_fh_275/eaf3d_00299999.h5
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/judge_e2_275/
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/m201_255/audit.csv
- /Users/frariv/Horno/hornofusion-full3D/.claude/rules/acople-pv.md (líneas 566-568 y 587-609)

VEREDICTO: rechaza