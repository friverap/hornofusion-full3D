## Panel de cierre WS-K1, ronda 1: auditor de código EAF3D

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Hay dos BAJO, ninguno bloqueante.

### Alcance

El diff staged no toca código: solo cambia `.claude/rules/acople-pv.md`, `.claude/rules/research.md` y `docs/PLAN_K_limitador_en_poisson.md`, añade reportes y revisiones del ciclo 1 de WS-K1/WS-K2 y actualiza `status.json`.

- El sha256 de `git diff --cached` sobre las rutas con compuerta (GATED) es el del diff vacío (`e3b0c442...`). Coincide con `diff_sha` en ambos `status.json`.
- Por eso no aplican aquí las comprobaciones de conservación, columnas de audit, halos/MPI, `mold` (Bug 22) ni snapshot de reinicio.
- Sí revisé lo que el cierre afirma sobre el código: que Plan K no está en `src/`, que los parches ya no aplican y que la numérica no cambió desde 1bc9832.

### Hallazgos

**ALTO:** ninguno.

**MEDIO:** ninguno.

**BAJO**

- **B-1.** `.claude/rules/acople-pv.md:618-640`, entrada staged «Plan K CERRADO».
  - **Defecto:** dice «k1pa_340_n15 pegado a la centinela de 2 MPa 183 pasos seguidos desde 345.318 s».
  - **Qué muestra audit.csv:** los 183 pasos seguidos (345318-345500) son con p_max ≥ 1 MPa. En 2 MPa exactos hay 122 pasos, no seguidos; la racha más larga en la centinela es de 31 pasos, desde 345398. Es la errata que ya registraron C-310/C-311.
  - **Escenario:** quien lea la regla permanente cree que n15 estuvo 183 pasos seguidos en 2 MPa. La conclusión (lo que separa a K de la base es quedarse pegado al tope) no cambia.
  - **Arreglo:** «por encima de 1 MPa 183 pasos seguidos desde 345.318 s (122 de ellos en la centinela de 2 MPa; C-310/C-311)».
- **B-2.** Cita de línea desfasada.
  - **Defecto:** el reporte (Incertidumbre, Vigencia) cita `acople-pv.md` líneas 266-273. Con la línea que añade este diff, el bloque VIGENCIA ocupa ahora 266-274.
  - **Escenario:** `sed -n 266,273p` corta la última línea («con esta salvedad.»).
  - **Arreglo:** citar 266-274.

**Nota de proceso (no es un defecto):** `status.json` de WS-K1 sigue en `ronda: 0` y este panel es la ronda 1. Para que `ledger.py check` acepte `fallido`, el coordinador debe fijar la ronda antes de registrar los tres «aprueba» en esa misma ronda.

### Verificado como correcto (no re-auditar)

**Código y compuerta**

- **Plan K fuera de `src/`:** 0 coincidencias de `pc_alpha_implicit` y `pc_ai_tol` en `src/` y `tests/`.
- **Parches archivados:**
  - `git apply --check plan_k_v2.patch` falla en `src/mod_pressure_3d.f90:733`.
  - La base del parche es 1bc9832 (blob `3c1948e`).
  - `plan_k_v2.patch` y `patches/v2_completo_sobre_HEAD.patch` son idénticos.
- **Commits posteriores a 1bc9832:** 7 en `src/` (c80dff6, 50d1d97, e3397d4, 4d8570a, 79dc27b, 2b65e11, 1de144e). Sus mensajes dicen lo que cita el reporte.
- **Numérica sin cambios:** leí el diff de `src/` desde 1bc9832 fuera de `mod_audit`.
  - Todo es diagnóstico. `audit_gas_cells`, `audit_comp_cell`, `audit_eos_cell` y `audit_volfix_cell` reciben todos sus argumentos con `intent(in)`.
  - Los `ws_*` nuevos solo se escriben.
  - `ws_Fgv` es una variable intermedia antes de `gmass` y da el mismo valor IEEE.
  - Esto respalda la vigencia de H1/H1b para la ruta de la base, que el reporte había tomado solo de los mensajes de commit.

**Corridas**

- **Sonda k1_342 (10,60,2):**
  - |p| ≥ 20 kPa en 342518-342560.
  - Máximo 69 967.7 Pa en el paso 342539; el paso 342540 da 69 103.1 Pa.
  - osc2 = 342.3 Pa.
- **Sondas k1pa_342, k1b_342 y k1pb_342 (342510-342533):** osc2 de 209.5, 6874.3 y 6876.0 Pa; ag_min de 0.01834, 0.01500 y 0.01500.
- **Convergencia (`plank_conv`):**
  - k1_342: 205/205 sin converger con tol 1e-6.
  - k1pa, k1b y k1pb: 0.9 % sin converger con tol 1e-3; k1pb, 99.8 % con tol 1e-6.
  - k1pa no es el binario de v1: tiene 550 solves frente a 205 e it_medio 5.84 frente a 8.00, aunque la sonda coincida a menos de 1 Pa (C-037).
- **Pasos con p_max > 1e5 en 342.45-342.56 s:**
  - Base: 7 pasos (342451, 342452, 342535-342537, 342539, 342541).
  - k1b: 6 pasos (342451, 342452, 342534-342537).
  - `regime2` usa 111 filas (`t0 <= t < t1`), así que 6/111 = 5.4 %, 4/109 = 3.7 % y 3.2 % de 111 = 3.55 cuadran.
- **C-310/C-311 en audit.csv (340-345.5 s):**
  - judge_otp_280: 1 paso ≥ 1 MPa (máximo 1.056e6).
  - base_340_n14: 4 pasos ≥ 1 MPa, 1 en 2 MPa.
  - base_340_n15: 19 pasos ≥ 1 MPa, 3 en 2 MPa.
  - k1pa n12 y n14: máximo 3.30e5.
  - k1pa n15: 183 pasos seguidos ≥ 1 MPa, 122 en 2 MPa.
- **Binarios:** ningún `run.log` de k1*_342 tiene la línea `Ejecutable:` (se añadió después, en 2b65e11) y no hay binarios k1 en `campaigns/bin`. Las `config.dat` coinciden salvo `pc_ai_tol`.

**Registro y documentos**

- **Afirmaciones raíz de WS-K1:** 16 (refutada 4, fallida 9, soportada 3). `ledger.py open` da 0 abiertas y no muestra Plan K; `ledger.py check` da OK.
- **Cadenas del registro:** C-012, C-013→C-031, C-028, C-035 a C-039, C-041, C-064 (cerrada por C-294), C-065 a C-073 (con su motivo), C-284, C-290 y C-309 coinciden con lo que dice el reporte.
- **Citas de documentos:**
  - Regla de aborto en `PLAN_K_limitador_en_poisson.md`, líneas 72-73.
  - `reevaluacion.md`, líneas 82-85.
  - En el parche P-a: `unl_on = .false.` y factor 1 en `acc_face`.

### Orden de corrección sugerido

1. B-1: corregir la frase sobre n15 en la regla permanente.
2. B-2: cambiar la cita de líneas en el reporte.

Ninguno de los dos cambia una conclusión. Siguiendo la regla de erratas no bloqueantes, pueden quedar registradas aquí sin abrir un nuevo pase.
