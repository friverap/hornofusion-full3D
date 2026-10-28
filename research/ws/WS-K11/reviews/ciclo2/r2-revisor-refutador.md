## Revisión del refutador: WS-K11, ronda 1

Solo leí archivos: el reporte, el ledger (C-222 a C-257), research/README.md, `.claude/rules/acople-pv.md` y docs/PLAN_J. Calculé con Python sobre los `audit.csv` y los snapshots existentes, sin correr nada. No leí las revisiones de otros revisores.

### 1. Conclusiones, mejor alternativa y dato que las separa

**C1. La centinela de `k10b_dt025` la causa encender f28 sobre el estado fh de 280 s; la presión total no influye.**
- **Alternativas:**
  - Acotar dt de 1 a 0.25 ms.
  - El binario que escribió el estado.
  - El estado en sí.
- **Qué las separa, y qué dicen los datos:**
  - A (f28 apagada, mismo estado, mismo binario y mismo acotado de dt) da 69 m/s y 15 kPa.
  - F reproduce `k10b_dt025` con una diferencia de 1e-9.
  - H (solo la presión total encendida) es igual a A.
  - G no acota dt y su estado lo escribió el binario actual, y da pico.
  - Lo recalculé con h19.py y duracion.py y coincide.
- **Veredicto:** se sostiene. Es la respuesta a la pregunta del workstream.

**C2. El fenómeno «pasa en los cinco estados» y «sin cambio de f28 no aparece ese régimen».**
- **Alternativa:** el estado fh de 285, 290 o 295 s, con 0.25 ms, da el régimen con f28 o sin ella.
- **Qué la separaría:** correr fh 285, 290 y 295 s con f28 apagada a 0.25 ms. No existe ninguno de esos brazos.
- **Lo que sí está en los datos:**
  - fh 280 s, el único control, es el estado más tranquilo del linaje (|Δp| de 0.0 a 1 ms).
  - Con f28 apagada a 1 ms, fh tiene 300 m/s en 281.47 s y 578 kPa en 284.39 s; I arranca 0.6 s después de ese evento.
  - fh 295.0 s muestra un repunte de 95 m/s y 31 kPa.
  - L prueba que acotar dt, sin cambiar claves, basta para tocar U_GAS_MAX.
- **Veredicto:** no verificado. Ver R1.

**C3. La huella nolink distingue el cambio de los demás casos.**
- **Alternativas:**
  - Las celdas nolink serían un síntoma de presión alta.
  - O un sobrellenado heredado.
- **Lo que dicen los datos:**
  - Hay 34 pasos con nolink y p < 100 kPa en `k10b_dt025`.
  - Hay 450 kPa sin nolink en s290, y 300 m/s sin nolink en L.
  - No hay ningún hueco de poro negativo en los snapshots.
  - Las celdas saturadas no separan fh de jb (fh285 908 frente a jb285 931).
- **Veredicto:** la separación existe en los datos, pero es post hoc (R2) y su mecanismo está abierto (R3, R4).

**C4. El régimen de f28 no explica las paradas de B1.**
- **Comprobación:** 15 filas de nivel centinela en fh frente a 1 en jb.
- **Veredicto:** es prudente y está bien acotada. El matiz «apoya f28» va más allá de lo que da una sola trayectoria (R7).

### 2. Repeticiones de fracasos registrados

No hay. El workstream es diagnóstico y no cambia `src/`. No repite D2.2, las reglas D/E/F/G, `n_pc_max` ni M20-2 (el hueco congelado separado). H12 (Tg_end, C-225) quedó refutada y no se vuelve a usar.

### 3. Objeciones

- **R1 (bloqueante).** Falta el control con f28 apagada en fh 285, 290 y 295 s. Se resuelve de una de dos formas:
  - correr esos tres brazos con la config de A y una predicción pre-registrada;
  - o limitar la causa a 280 s en el resumen.
- **R2 (bloqueante).** La firma de régimen y nolink se definió tras refutarse H20. Se resuelve de una de dos formas:
  - pre-registrarla y probarla fuera de muestra con `judge_fh_275/eaf3d_00299999.h5` (f28 encendida) y `judge_jb_275/eaf3d_00299999.h5` (sus mismas claves);
  - o declarar explícitamente en el resumen que no está pre-registrada.
- **R3.** Citar el cruce entre nolink y p_max, que en parte descarta que nolink sea solo un síntoma de presión alta.
- **R4.** Localizar las celdas nolink y cruzarlas con las celdas de lecho saturadas. Hay una pista: f28 drena unas 126 en 60 ms (F280236 frente a A280236).
- **R5.** L y los 450 kPa de s290 son centinelas sin diagnosticar. Hay que registrarlas como pendiente y matizar la recomendación de bancos para 0.25 ms.
- **R6.** Evaluar, con los `audit.csv` existentes, el impacto sobre K5-K8 y K10 quitando los pasos 280001-280031.
- **R7.** Retirar «apoya f28» o respaldarlo con un juez de varias trayectorias.

VEREDICTO: rechaza