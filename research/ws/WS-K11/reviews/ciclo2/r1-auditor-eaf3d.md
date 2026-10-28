# WS-K11, ronda 1: revisión del auditor-eaf3d

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Quedan tres BAJO no bloqueantes.

Alcance: el diff staged no toca `src/` ni `tests/`. `git diff --cached -- src tests` está vacío y su sha256 es `e3b0c442…b855`, igual al `diff_sha` de `status.json` y al que calcula `ledger.py`, así que es correcto. El código del diff es `research/ws/WS-K11/scripts/pares.py`. Además reviso el texto nuevo de `.claude/rules/transporte-energia.md`, los eventos C-248/C-249 y todas las citas `archivo:línea` del reporte contra `src/`.

## 1. Hallazgos

### BAJO

**A1. La regla y el reporte describen mal cuándo actúa `pc_outlet_total_pressure`.**
- **Dónde:** `.claude/rules/transporte-energia.md` (párrafo WS-K11) y `report.md:269-271`.
- **Defecto:** dicen que la clave «solo actúa con reflujo» y que su efecto en el arranque es de «1e-8».
- **Lo que hace el código:** en `src/mod_pressure_3d.f90:1001-1031` y en `outlet_total_pressure` (2008-2016), con `u_in <= 0` el objetivo es `t = p0 = rho_g*g*(zf-z)`, y se aplica `p_new = p_old + a_p*(t-p_old)`.
- **Escenario de fallo:** el Dirichlet de la abertura se re-ancla hacia p0 con la rho_g ACTUAL aunque no haya reflujo. Al arrancar con la clave desde un estado escrito sin ella, con rho_g de 0.22 a 0.30 arriba, el ancla se mueve menos de 1 Pa (media celda de unos 4 cm).
- **Magnitud omitida:** «1e-8» deja fuera m_gas, que difiere 2.6e-7 (C/E) y 2.5e-7 (k10b/F).
- **Arreglo:** corregir la redacción.

**A2. «No es necesaria ni suficiente en los dos estados» generaliza más de lo medido.**
- **Dónde:** `report.md:11-13` y C-249.
- **Defecto:** cada propiedad se probó en un solo estado. La no necesidad se vio en fh (F) y la no suficiencia en jb (E). Falta la presión total sola sobre el estado fh.
- **Por qué es improbable que cambie la conclusión:** F reproduce a k10b_dt025 a 1.1e-9.
- **Arreglo:** precisar en qué estado se probó cada propiedad, o declararlo en Incertidumbre.

**A3. Supuestos sin comprobar en `pares.py:22-25`.**
- `r[:11]` presupone que el primer paso común es el del snapshot y que la auditoría es de cada paso. Con judge_fh_275 o judge_jb_275, que auditan cada 5 pasos, la etiqueta «pasos 0-10» cubriría 50 pasos.
- La división por `abs(A)` no tiene guarda: un valor 0 provoca ZeroDivisionError.
- Lee `m_gas_cells_nolink` sin comprobar que exista: con judge_otp_280, que no tiene esa columna, termina en KeyError.
- Con las cuatro corridas que cita el reporte las cifras son correctas.
- **Arreglo:** filtrar por número de paso, proteger el denominador y comprobar la columna.

## 2. Verificado como correcto (no re-auditar)

**Pares de una sola clave**
- `diff` de config.dat:
  - C/E solo difieren en `pc_outlet_total_pressure`.
  - A/F solo difieren en `pc_transport_f28`.
  - k10b_dt025/F solo difieren en `pc_outlet_total_pressure`.
  - A/C difieren en f28 y `restart_file`.
- Todos los brazos (k10b_dt025, A-F, s290) registran `Ejecutable: campaigns/bin/eaf3d_k10b_opt`. Su sha256 empieza por 5409bbe9, como dice C-246, y su mtime (27-oct 22:37) es anterior a todas las corridas.

**Pre-registro**
- `650d712` (09:24:52) es anterior al nacimiento del run.log de E (09:24:57) y de F (09:29:27).
- `h17.py` no cambió desde ese commit.
- C-248/C-249 (09:34:29) son posteriores al final de F.
- `ledger.py check` da OK (249 eventos).

**Cifras reproducidas con los scripts, en solo lectura**
- `h17.py`:
  - E: 51.2 m/s y 117 kPa; ventana 117 kPa (280004); cuartos [1,0,0,0]; 0 AVISO; REFUTADA.
  - F: 300.0 m/s y 461 kPa; ventana 592 kPa (280161); cuartos [31,21,32,36]; 0 AVISO; REFUTADA.
- `pares.py`, pasos 0-10:
  - C/E: u 7.9e-9, p 1.5e-9, m_gas 2.6e-7; en la ventana, u hasta 12 %.
  - k10b/F: 1.1e-9, 3.5e-10, 2.5e-7.
  - nolink: 0/0 en C/E y 105/105 en k10b/F.
- `h15.py`:
  - A: 69.4 m/s y 15 kPa.
  - B: 300 m/s y 342 kPa; cuartos [58,59,59,59].
- Tabla nolink completa (los 10 bancos), incluidos 71 de 120 y 235 de 235.
- Asentamiento a 1 ms:
  - p_max: 24 y 31 pasos, con 23.2/43.3 y 27.6/49.0 kPa.
  - u_gas_max: 17 y 13 pasos.
- 0.5 ms: cuartos [8,1,2,0].
- m203/m21f1 frente a judge_otp_280: 4.8e-6.
- Máximos de la tabla Resultado: 450.0 kPa en 290093, 70.6 kPa, 70.0 kPa y 591.6 kPa en 280161.
- Tabla de régimen de los jueces 280-295 s (C-241).
- Diferencias fh/jb: |Δα_s| 0.77, |Δα_g| 0.64; presión de −0.09 a 14.8 kPa en fh y de −12.8 a 28.0 kPa en jb.

**Citas de código**
- `src/mod_constants.f90:594-599`: `gas_eos`.
- `src/mod_multiphase.f90:473-477`: Tg_ref desde Tg_end.
- `src/mod_pressure_3d.f90:598-601`: fuente de compresibilidad /dt.
- `src/mod_audit.f90:1318-1335`: clase nolink, solo en celdas multifase (case 2), con caras liq o gas.
- Commits `2f0529b` y `8f568fc`: fechas e introducción de las claves con valor ON.

**Coherencia MPI de la huella nolink**
- `ws_Fc_lk_*` y `ws_Fg_lk_*` se intercambian por halo (`mpi_exchange_halos_3d_int`, `mod_pressure_3d.f90:876-878` y `910-912`). Por eso `lk_any` en la cara `i-1` de un borde de bloque lee el valor del vecino: el conteo no depende de la descomposición.
- El cero de transporte de f28 (`mod_continuity.f90:1508-1520`) solo actúa con `ws_Fc_valid`, que corresponde al Poisson del mismo paso. No depende de estado que falte en el snapshot.

**Semántica de pasos**
- La fila `step 280000` del audit.csv es el estado del snapshot (time 280.001, igual que `metadata/time`). Las convenciones «pasos 2-10» y «sin el paso 1» son coherentes.

## 3. Orden sugerido de corrección (uno por uno, ninguno bloquea)

1. A1: redacción de la regla, que es la guía que leerán futuros cambios en `mod_pressure_3d`.
2. A2: redacción del resumen y de C-249 (como evento nuevo con `--ref`).
3. A3: robustez de `pares.py`.
