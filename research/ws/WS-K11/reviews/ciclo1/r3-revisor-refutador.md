## Revisión del refutador: WS-K11, ronda 1

Solo leí datos existentes: audit.csv, config.dat, run.log y los snapshots h5. No corrí nada.

### 1. Conclusiones, hipótesis alternativas y el dato que las separa

**C1. Con 0.25 ms, encender las claves sobre el snapshot de 280 s es NECESARIO para el pico (H15, C-239/C-240).**
- **Alternativa:** el pico lo pone el estado o el código que escribió el snapshot, no las claves.
- **Dato que separa:** el brazo A.
- **Lo que dicen los datos:**
  - `diff` de configs: A solo difiere de `k10b_dt025` en `pc_transport_f28` y `pc_outlet_total_pressure`, con el mismo restart.
  - A queda plano: p_max entre 14.5 y 14.6 kPa, u_gas_max 69 m/s, nolink 0/235.
  - La alternativa queda descartada. Esta conclusión se sostiene.

**C2. La centinela la causa el CAMBIO de claves, no su sola presencia (H16, C-245).**
- **Primera alternativa:** basta tener las claves encendidas con 0.25 ms en ese tipo de estado.
  - Los estados sin cambio de claves no dan pico en los pasos 2-10 y tienen nolink 0/235 (verificado): `k11_c_dt025_jb280` (f28), `k11_dt025_s290` y `k11_d_dt025_s300` (las dos claves).
  - Los estados con cambio sí dan pico: `k10b_dt025` y el brazo B.
  - Hay un punto a favor: los dos estados con cambio son tranquilos (fh: unos 15 kPa, |Δp| < 1 kPa), igual que s290 y s300. La fase no explica el contraste.
- **Segunda alternativa (sigue en pie):** con 0.25 ms pesa outlet, su cambio o su presencia en un estado activo.
  - C es el único estado activo sin cambio: alterna entre 28 y 42 kPa (verificado en el audit.csv de `judge_jb_275`, 279.9-280.05 s). Pero lleva outlet = false.
  - Los estados que llevan las dos claves ya establecidas están en fases tranquilas. Lo medí en otp: 300-301 s da 24.0 kPa con |Δp| de 2.5 kPa.
  - **Dato que separa:** 0.25 ms desde jb 280 s con outlet = true. No existe. Ver R2.
- **Tercer confusor:** «el mismo instante de 280 s» no es el mismo estado.
  - Entre fh 280 s y jb 280 s, |Δα_s| llega a 0.77, |Δα_g| a 0.64 y |Δα_l| a 0.28.
  - El campo de presión va de -0.09 a 14.8 kPa en fh y de -12.8 a 28.0 kPa en jb.
  - «Estado escrito sin claves» equivale a «linaje fh», así que en los datos no se pueden separar. Lo acepto como definición operativa del «cambio».

**C3. Con 0.25 ms el régimen alto no decae en la ventana.**
- **Alternativa:** es un transitorio largo que decae después de 60 ms.
- **Dato que separa:** una ventana más larga. No existe y el reporte lo dice.
- **Lo verificado:** en B, nolink se mantiene en 235/235 pasos hasta el último.

**C4. Hay una huella nolink con 0.25 ms.**
- **Alternativa:** es un artefacto de dt pequeño que también puede aparecer sin cambio de claves en una fase activa.
- **Lo que hay:** C (activo, sin cambio) da 0/235, a favor del reporte. Pero C no lleva outlet, y la ubicación de las celdas no está medida (R3).

**C5. Afecta a B1 porque `judge_otp_280` es un reinicio con cambio de claves.**
- La alternativa (régimen residual del cambio o física con f28 encendida) no está separada, y el reporte lo reconoce. Sin objeción nueva.

### 2. Repeticiones de fracasos registrados

- **No hay repetición.** Es un workstream de diagnóstico y no propone ningún arreglo: no repite D2.2, ni las reglas locales D/E/F/G, ni n_pc_max, ni F2.31 por paso.
- **H12 (Tg_end):** ya está refutada (C-225) y no se reintenta.
- **C-044 (snapshot de un paso truncado):** no aplica. Los snapshots de 280 s y 290 s son de pasos intermedios de jueces que siguieron corriendo.
- **C-206/C-230 (transitorio de acotar dt):** el reporte excluye el paso 1 como corresponde. Aun así, C muestra que acotar dt excita el ciclo de 2 pasos sin cambio de claves (R4).

### 3. Objeciones

- **R1 (bloqueante).** El reporte se contradice sobre su conclusión central.
  - El titular dice «CAMBIO de claves», pero las l. 152-160 dicen que el titular «no» dice «el cambio de claves».
  - La Incertidumbre (l. 327-341) mantiene «sin separar» y da como pendientes los brazos C y D, que ya se corrieron.
  - **Resolución:** reescribir esas secciones a partir de C-245, con los límites de R2 y R3.
- **R2.** H16 prueba la sola presencia de f28, no la de las dos claves en un estado activo.
  - **Resolución:** 0.25 ms desde `judge_jb_275/eaf3d_00280000.h5` con outlet = true, y 0.25 ms desde fh 280 s con solo f28.
  - Si no se corren, acotar el titular y `.claude/rules/transporte-energia.md`.
- **R3.** El mecanismo está abierto: falta saber dónde y por qué aparecen las celdas nolink solo con 0.25 ms.
  - **Resolución:** localizarlas en `k11_b_dt025_fh290_on/eaf3d_00290236.h5` y `k10b_dt025/eaf3d_00280236.h5`, o con PROBE-P.
  - Cerrar como «disparador identificado, mecanismo abierto».
- **R4.** El brazo C sí tiene un transitorio al acotar dt.
  - p_max pasa de 28 a 116.5 kPa y alterna con periodo 2, decayendo hasta 87 kPa en el paso 10.
  - **Resolución:** reportarlo; los datos ya están en `k11_c_dt025_jb280/audit.csv`.
- **R5.** Faltan C y D en la tabla de huella nolink (los dos dan 0/235, verificado). **Resolución:** añadirlos.
- **R6.** El brazo B no tiene control propio y hay una trayectoria por condición en la lectura de régimen. **Resolución:** control de B con 0.25 ms y las claves apagadas, más réplicas a 14 ranks. No bloquea.

### Verificado por mí (solo lectura)

- **Diffs de config:**
  - A frente a `k10b_dt025`: solo las dos claves.
  - B frente a `k10b_dt025`: restart y t_final.
  - C frente a `k10b_dt025`: outlet = false y restart de jb.
  - D frente a `k10b_dt025`: restart de 300 s y t_final.
- **Binario de C:** `eaf3d_k10b_opt`, según su run.log.
- **Series de los pasos 0-10 y nolink:**
  - A: 0/235.
  - B: 235/235, máximo de p_max 365.1 kPa.
  - C: 0/235, máximo de p_max 116.5 kPa en 280004, máximo de u_gas_max 86.1 m/s.
  - D: 0/235, máximo de p_max 56.0 kPa.
  - `k10b_dt025`: 105/235, máximo de p_max 591.6 kPa.
- **Avisos del CG:** cero `[CG] AVISO` en C y en D.
- **Snapshots:** fh 280 s y jb 280 s tienen los mismos 56 datasets, sin campos de reinicio exclusivos de f28. Las diferencias de estado son grandes (cifras en C2).
- **Fase de otp:** en 295-302 s, 300-301 s da 24.0 / 2.5 kPa.

VEREDICTO: rechaza