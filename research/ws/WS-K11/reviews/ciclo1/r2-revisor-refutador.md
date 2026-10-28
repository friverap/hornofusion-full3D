## WS-K11, ronda 1: revisión del refutador

Revisión en modo solo lectura. Volví a correr `h15.py`, `check_audit.py` y lecturas en Python de audit.csv, config.dat y run.log.

### Qué verifiqué
- **Brazo A frente a `k10b_dt025`:** las configs solo difieren en `pc_transport_f28` y `pc_outlet_total_pressure`. Usan el mismo binario (`eaf3d_k10b_opt`) y el mismo snapshot.
- **Brazo B frente a `k10b_dt025`:** solo cambian el restart y el t_final.
- **`h15.py`:** reproduce A (69.4 m/s / 15 kPa; cuartos 0, 0, 0, 0) y B (300 m/s / 342 kPa; máximo 365 kPa en 290020; cuartos 58, 59, 59, 59).
- **Avisos y FAIL:** cero `[CG] AVISO` en los dos brazos. El FAIL de sentinel_gas y regime_gas aparece solo en B.

### 1. Conclusiones, alternativa y dato que las separa

**C1. «La centinela la causa ENCENDER las claves sobre un estado escrito sin ellas» (C-239).**
- **Alternativa:** basta con tener las claves encendidas con 0.25 ms en ese estado, sea o no un cambio. El par A / k10b solo prueba que las claves son necesarias. Con la alternativa, el resultado de H15 (A sin pico, B con pico) sería el mismo.
- **Qué la separa:** un estado en 280 s con las claves YA establecidas.
- **Datos actuales:** solo hay un estado así, `k11_dt025_s290` (de otro linaje), y se tomó en una fase tranquila. judge_otp_280 tiene en 290.0 s un |Δp| consecutivo de 3.7 kPa, frente a 15-22 kPa en 280.2-283 s. Aun así da 450 kPa en el paso 290093.
- **Dato que falta y es barato:** existe `judge_jb_275/eaf3d_00280000.h5` (f28 activa desde 275 s). Ver O1.

**C2. «Con 0.25 ms el régimen alto no decae; si es transitorio largo o persistente, sin decidir».**
- **El dato ya existe.** `m_gas_cells_nolink` vale 0 en A, s290, dt05 y mo20. En k10b_dt025 aparece en el paso 2 con 2 celdas (105/235 pasos, hasta 280236). En B aparece con 4 celdas en 235/235 pasos, y p ≥ 100 kPa en esos mismos 235.
- Es un estado trabado de celdas multifase sin ninguna cara enlazada, exclusivo de 0.25 ms. Con 1 ms el pico existe sin celdas nolink.
- Por tanto «el mismo transitorio amplificado al bajar dt» (C-226) es dudoso: hay un segundo mecanismo, propio del dt.

**C3. «No es el salto de Tg_end» (C-225).** Es sólido: la serie es idéntica a 3 cifras.

**C4. «Con las claves establecidas no hay ese pico».**
- Descansa en un solo snapshot en fase tranquila.
- **Alternativa:** el pico depende de la fase del régimen con las claves encendidas, que con 1 ms tiene un ciclo de 2 pasos de 15-22 kPa. Ver O1 y O3.

**C5. «Con 1 ms dura ~20-25 pasos» y «No afecta a B1».**
- El pico decae en ~20 pasos, pero hacia un ciclo de 2 pasos (24 frente a 42-49 kPa) que sigue segundos después. En 281 y 283 s la media de p_max es de 32-34 kPa y el |Δp| de 14-16 kPa. El linaje con las claves apagadas, judge_fh_275, se queda en 15 kPa con |Δp| de 0.1 kPa.
- judge_jb_275 (f28 desde 275 s) muestra el mismo régimen en 280-295 s.
- El juez de B1 posterior a 280 s ES judge_otp_280, un reinicio con cambio de claves. Ver O3.

### 2. Repeticiones de fracasos registrados
El workstream es diagnóstico y no prueba ningún remedio, así que no repite nada registrado. Una advertencia: el mecanismo que asoma, celdas sin cara enlazada por F2.8/J-B, es la familia de reglas locales de clasificación (D, E, F, G; F2.31 por paso; M20-2 «no repetir»; acople-pv.md, 22-oct). Un remedio que reclasifique caras sería una repetición.

### 3. Objeciones

**O1 (bloqueante).** «Cambio de claves» frente a «claves encendidas con 0.25 ms».
- **Resolución:** 0.25 ms desde `judge_jb_275/eaf3d_00280000.h5` con f28 = true y outlet = false, más una réplica desde `judge_otp_280/eaf3d_00300000.h5`. Si no se corren, reformular el titular.

**O2.** El reporte no incluye la huella `m_gas_cells_nolink`, que está en los datos.
- **Resolución:** reportarla y retirar o matizar «amplificado al bajar dt».

**O3.** El alcance sobre B1 y los «20-25 pasos» con 1 ms.
- **Resolución:** tabla de la media de p_max y el |Δp| por ventanas de 0.1 s en 280-295 s para judge_otp_280, judge_jb_275 y judge_fh_275.

**O4.** El brazo B no tiene control con las claves apagadas.
- **Resolución:** 0.25 ms desde fh 290 s con las claves en false, o declararlo.

**O5.** No se sabe qué clave actúa con 0.25 ms.
- **Resolución:** desde jb_275 en 280 s, con outlet = true.

**O6.** C-239 dice cuartos 31, 21, 32 y 33. Los datos y el Resultado dan 31, 21, 32 y 36.
- **Resolución:** evento de corrección con ref C-239.

VEREDICTO: rechaza
