## Revisión WS-K11, ronda 1: auditor-eaf3d

**Veredicto: RECHAZA.** Hay dos hallazgos MEDIO sin resolver.

Alcance: es un diff de diagnóstico, sin `src/` ni `tests/`. Revisé el texto que guía al código (`.claude/rules/transporte-energia.md`), `research/ledger.jsonl` (C-245), `research/ws/WS-K11/status.json` y `research/ws/WS-K11/report.md`. Además rehíce, en solo lectura, las medidas de C-245 sobre los `audit.csv` existentes.

### Hallazgos

**MEDIO (O1): la regla contradice C-240 y C-241**
- **Dónde:** `.claude/rules/transporte-energia.md:367-369` (versión staged).
- **Defecto:**
  - Dice «Con 1 ms dura ~20-25 pasos». C-241 mide 13-31 pasos hasta asentarse, y no en un estado tranquilo: en un ciclo de 2 pasos (23/43 y 28/49 kPa). Ese régimen alto dura los 15-20 s medidos.
  - Dice que con 0.25 ms los pasos con p_max >= 100 kPa son «casi todos». En `k10b_dt025` son 120 de 235 (recontado). Solo el brazo B llega a 235 de 235.
  - Falta la huella `m_gas_cells_nolink`, que solo aparece con 0.25 ms (C-240).
  - El propio `report.md:419-427` da estos tres puntos como pendientes.
- **Escenario de fallo:** alguien compara config a 1 ms desde `judge_otp_280/eaf3d_00280000.h5` y descarta unos 25 pasos. Sigue dentro del régimen alternante (30-57 kPa, frente a 15 kPa del linaje apagado) y atribuye la diferencia a la config.
- **Arreglo:** reescribir esas líneas con C-240/C-241 y añadir la huella nolink.

**MEDIO (O2): el informe se contradice tras H16**
- **Dónde y qué:**
  - `report.md:327-341` sigue diciendo «Cambio de claves frente a claves encendidas: sin separar» y propone como pendientes los brazos C y D, que ya decidieron C-245.
  - `report.md:413-427` pide corregir la regla en 360-366, pero esas líneas ya cambiaron en este diff: un punto quedó resuelto y dos siguen mal (O1).
  - `report.md:383-386` habla en futuro de un experimento ya corrido.
- **Escenario de fallo:** quien lea la sección de incertidumbre concluye que la pregunta central sigue abierta, o da la regla por corregida.
- **Arreglo:** actualizar la incertidumbre al estado posterior a C-245. Queda abierto:
  - si la clave outlet pesa a 0.25 ms;
  - el brazo B sin control propio;
  - dónde están las celdas nolink;
  - los 450 kPa del paso 290093.

**BAJO (O3, no bloquea): el plural «claves» generaliza de más**
- **Dónde:** regla, líneas 366-367, y `report.md:27`: «la causa es el CAMBIO, no la sola presencia de las claves».
- **Defecto:** el brazo C solo conserva f28. Frente a `k10b_dt025` cambia a la vez la historia de f28 y `pc_outlet_total_pressure`: comparé las configs y solo difieren en esa clave y en `restart_file`. Que tener outlet encendida con 0.25 ms a 280 s baste no lo excluye C; solo lo excluyen s290 y D, a 290 y 300 s.
- **Arreglo:** precisar el texto, o correr 0.25 ms desde `judge_jb_275` a 280 s con outlet=true.
- Nota: el brazo C sube a 117 kPa en 280004, unas 8 veces el brazo A (15 kPa). Queda bajo el umbral pre-registrado y el informe lo dice; no es objeción.

### Verificado como correcto
- No hay cambios en `src/` ni en `tests/`, ni staged ni sin stagear. `diff_sha` es el sha256 de la cadena vacía, coherente.
- `h15.py` se commiteó en 424a70d, antes de la corrida. Usa la ventana 2-10 pre-registrada y cuenta los AVISO sobre todo el `run.log`, más estricto que lo pre-registrado.
- C-245 se reproduce exacto:
  - **Brazo C:** 51.2 m/s / 117 kPa en los pasos 2-10; máximo de la ventana 117 kPa (280004); 86.1 m/s; cuartos [1,0,0,0]; 0 AVISO.
  - **Brazo D:** 77.0 m/s / 56 kPa; cuartos [0,0,0,0]; 0 AVISO.
  - `check_audit` no da FAIL en ninguno de los dos.
- Diff de configs:
  - `k10b_dt025` frente al brazo C: solo outlet y `restart_file`.
  - `k10b_dt025` frente al brazo D: solo `restart_file` y `t_final`.
  - `k10b_dt025` frente al brazo A: solo las dos claves.
  - `judge_jb_275` frente al brazo C: mismas claves físicas.
- El brazo C corrió con `eaf3d_k10b_opt` a 15 ranks y leyó el snapshot de `judge_jb_275` (según su `run.log`).
- `judge_otp_280` es continuo desde `judge_fh_275` a 280 s con las dos claves: el snapshot de 300 s lleva 20 s con ellas.
- Recuentos recalculados: `k10b_dt025` da 120/235 pasos >= 100 kPa y 105 pasos con nolink; el brazo B, 235/235 en ambos; el brazo C, 1 y 0.

### Orden sugerido
1. O1: corregir las líneas 367-369 de la regla.
2. O2: actualizar la incertidumbre del informe.
3. O3: precisar el texto sobre el alcance de la clave outlet.
