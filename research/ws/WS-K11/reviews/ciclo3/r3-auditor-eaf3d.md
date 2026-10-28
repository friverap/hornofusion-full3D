# WS-K11, panel de cierre, ronda 1: auditor-eaf3d

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Hay 3 BAJO que no bloquean.

## Alcance del diff staged
- No toca `src/` ni `tests/`. `status.json` registra `diff_sha` = e3b0c442…, que es el sha256 del diff vacío de src/tests (`scripts/research/ledger.py:221-223`), así que es coherente. La compuerta `guard_cierre.sh` no aplica porque el diff no tiene rutas en src/ o tests/.
- Código revisado:
  - `research/ws/WS-K11/scripts/pares.py` y `duracion.py`: son de solo lectura y no escriben nada.
  - `.claude/rules/transporte-energia.md`: el bloque WS-K11.
  - `research/ledger.jsonl`: solo agrega las entradas C-265..C-274 y no modifica nada anterior.
- No leí las revisiones de otros revisores.

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO
1. **B1. La regla de f28 establecida ≥ 5 s es insuficiente** (`.claude/rules/transporte-energia.md`, cierre del bloque WS-K11).
   - `k7v4_long` tiene celdas nolink en los pasos 284669-285379. Su `eaf3d_00285000.h5` está 5.0 s después del cambio y cumple la regla, pero cae dentro del episodio (tramos en 285051-285064 y 285151-285168).
   - Arreglo: exigir además que el audit del escritor no muestre nolink ni filas de nivel centinela alrededor del snapshot.
2. **B2. La salvedad de M20-2 quedó en la regla equivocada.**
   - `acople-pv.md:566-568` sigue citando 156 frente a 94 kPa sin remitir a C-270/C-274. Esa regla es la que se carga al editar multiphase y pressure.
   - Arreglo: una línea de remisión en acople-pv.md.
3. **B3. Redacción contradictoria.** La regla dice «a 1 ms y sin reiniciar, k7v4_long (desde judge_otp_280/eaf3d_00280000.h5)», pero k7v4_long es un reinicio con el cambio de f28. Arreglo: escribir «4.67 s después del reinicio con el cambio».

## Verificado como correcto (recalculado desde `campaigns/b1/*/audit.csv` y los h5, solo lectura)
- **Firma por brazo con el filtro step > P0+1.** P0 es la primera fila; a 0.25 ms esa fila es el paso de 1 ms (t = 280.001).
  - Pasos con nolink: A, C, D, E, H, K, L, M, N, O, P, Q y s290 = 0; B = 235; F y k10b = 105; G = 35; I = 57; J = 72; tgfix = 22 (280002-280023).
  - Pasos con p_max ≥ 100 kPa por cuartos: F/k10b 31,21,32,36; B 58,59,59,59; J 57,49,60,53; G 27,0,0,0; I 59,6,22,55; tgfix 31,27,26,19; P 0.
  - Medias por cuartos: C 76-80, K 66-71, L 31-42, Q 34-52, A/H/M/N/O 14.1-17.6 kPa, tgfix 138.0 a 83.9 kPa.
  - Máximos de p_max y u_gas_max de M, N, O, P y Q: coinciden con C-265 y C-266.
- **Conteo de 20 brazos y 15 con f28 encendida.** «Sin cambio» y «f28 establecida ≥ 5 s» van juntos en C, D, E, K, L, Q y s290.
- **k7v4_long:**
  - 146 pasos con nolink entre 284669 y 285379, máximo 360 celdas, ninguno antes.
  - Primera fila de nivel centinela en el paso 284340 (t = 284.341 s), como corrige C-272.
  - 86 de 96 filas de nivel centinela coinciden con nolink.
  - En los 60 pasos desde 284669: 59 con nolink, 45 con p ≥ 100 kPa, 30 con u ≥ 299 m/s, p_max hasta 152.7 kPa.
- **Pico del brazo L.** u ≥ 200 m/s en 3 pasos y nivel centinela en 2.
- **Duración (`duracion.py`).**
  - Unión de u ≥ 200 m/s o p ≥ 300 kPa: G 11, F 8, B 18, I 101, J 187, L 3, s290 2.
  - Nivel centinela: 7, 6, 9, 73, 120, 2, 2.
- **s290.** 450 kPa en el paso 290093, sin nolink.
- **C-251.** Con muestreo cada 5 pasos en 280-295 s: fh 15, jb 1, otp 26.
- **C-270.**
  - scrfh_base: 42 filas en 281461-281502.
  - scrfh_b, m21f1_280 y otp_280: 0 filas.
  - m202_280: 5 filas (280003…280033); sin los pasos 280001-280031, 66.1 frente a 51.3 kPa y 1 fila frente a 0.
  - u en 280002: 215.0 / 189.8 / 136.7 m/s.
  - Los textos de `0398a99` y `acople-pv.md:566-568` concuerdan con lo citado.
- **C-241.** Asentamiento a 1 ms en 13-31 pasos, con ciclo de 23.2/43.3 y 27.6/49.0 kPa.
- **Pares (`pares.py`).** C/E 7.9e-9 en u y 1.5e-9 en p; k10b/F 1.1e-9 y 3.5e-10; m_gas 2.5-2.6e-7.
- **Snapshots y linajes.**
  - `judge_fh_275` y `judge_otp_280` en 280 s: solo difieren en campos derivados (F_lorentz, G_rad y S_*). Los campos primarios y /restart son idénticos.
  - Las configs de fh y jb solo difieren en f28.
  - comp_carry: fh 280 = 0, fh 295 = 1.46e-9, fh 299.999 = 2.26e-5, F 280236 = 4.2e-6, jb 285 = 5.2e-5.
  - judge_e2_275: 28 filas de nivel centinela en 282-287 s.
- **Bancos que reinician de judge_otp_280/eaf3d_00280000.h5.** Todos llevan f28 = true, salvo A y H. La lista del reporte cubre K5-K8, K10, bench_w280, sondas, judge_e1w280 y diag_g284a.
- **Código fuente.**
  - Lo que el texto dice de `pc_outlet_total_pressure` concuerda con `src/mod_pressure_3d.f90:1001-1027` y `2000-2012`.
  - La columna `m_gas_cells_nolink` (`src/mod_audit.f90:1318-1335`) usa los enlaces del Poisson, que se ponen en `mod_pressure_3d.f90` sin depender de `pc_transport_f28`. Por eso «nolink = 0 con f28 apagada» no es un artefacto del instrumento.
  - f28 solo congela el hueco de poro en `liq_old%alpha` (`mod_multiphase.f90:139-147`, `517-518`) y no añade estado persistente fuera del snapshot.

## Orden sugerido de corrección
1. B3 (una palabra).
2. B1 (precisar la regla de reinicio).
3. B2 (remisión en acople-pv.md).
