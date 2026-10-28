# WS-K11, panel de cierre, ronda 1: auditor-eaf3d

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO.

## Alcance del diff staged

- **Sin código del simulador.** El diff no toca `src/` ni `tests/`. El `diff_sha` de `status.json` (e3b0c442...) es el SHA-256 del diff vacío de `src/`+`tests/`, que es lo que calcula `ledger.py:244-270`. Es coherente con `numerico: false`.
- **Lo que sí cambia:**
  - Tres scripts de medida de solo lectura: `research/ws/WS-K11/scripts/duracion.py`, `nolink.py` y `pares.py`.
  - El hunk WS-K11 de `.claude/rules/transporte-energia.md`.
  - El reporte, `status.json` y 12 eventos nuevos del registro (+12/-0, solo añadidos).
- **Método.** Ejecuté los tres scripts y `h22.py` solo leyendo los `audit.csv` existentes, y comparé cada cifra con el reporte y la regla.

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO (no bloqueantes)

- **B1. `duracion.py:2-4` usa un nombre equivocado para su umbral.**
  - **Defecto:** el docstring llama «nivel centinela» a u >= 200 m/s o p >= 300 kPa. El reporte (report.md:460-468) reserva ese nombre para u >= 299 m/s o p >= 300 kPa.
  - **Escenario:** si alguien cita la salida como filas de nivel centinela, obtiene L 3 en vez de 2, F 8 en vez de 6 y B 18 en vez de 9.
  - **Arreglo:** renombrarlo a «criterio de pico (H15)».
- **B2. report.md:326 cita una fuente que no prueba lo que dice.**
  - **Defecto:** afirma que F tiene nolink «en los mismos pasos que k10b_dt025» y cita `pares.py`, que solo cuenta pasos (105 y 105).
  - **Estado del dato:** comprobé por separado que los conjuntos son idénticos, así que la afirmación es cierta; solo falla la fuente.
  - **Arreglo:** que `pares.py` imprima `set(A) == set(B)`.
- **B3. La regla se contradice al hablar de `k7v4_long`.**
  - **Defecto:** el texto dice «a 1 ms y sin reiniciar, k7v4_long (desde judge_otp_280/eaf3d_00280000.h5)», pero `k7v4_long` es un reinicio en 280 s.
  - **Arreglo:** «a 1 ms, 4.67 s después de reiniciar con el cambio de f28».
- **B4. Falta un confusor en la comparación de tamaño (PLAUSIBLE).**
  - **Defecto:** la comparación de 360 celdas frente a 1-16 ({C-275}) también cruza binarios, y el reporte solo nombra la config como posible causa.
  - **Fechas:** `eaf3d_k7v4_opt` se compiló el 25-oct a las 10:48 desde un árbol sin commit, antes de 4d8570a, 79dc27b, 2b65e11 y 1de144e. `eaf3d_k10b_opt` es del 27-oct.
  - **Riesgo:** bajo. Según git, desde entonces el código que FIJA `ws_F*_lk` no cambió (solo cambió cómo se usa), pero no se puede confirmar.
  - **Arreglo:** añadir el binario a la lista de confusores de Incertidumbre.
- **B5. Error de uno en report.md:51-52.**
  - **Defecto:** «en los 329 pasos siguientes, 36-87 kPa» incluye el propio paso 284340, y los 87.0 kPa son de ese paso.
  - **Valor correcto:** los pasos estrictamente siguientes son 328, con 35.9-85.3 kPa. Ninguna conclusión cambia.
- **B6. `nolink.py:20` no acepta rutas completas.**
  - **Defecto:** antepone `campaigns/b1/` a sus argumentos, mientras que `duracion.py` y `pares.py` reciben rutas completas.
  - **Escenario:** `nolink.py campaigns/b1/k7v4_long` da FileNotFoundError.

## Verificado como correcto (no re-auditar)

- **Estado del commit.**
  - Registro: solo se añadieron eventos (C-265..C-276).
  - `diff_sha`: es el del diff vacío de `src/`+`tests/`.
- **`nolink.py` reproduce {C-275} entero:**
  - k7v4_long: 146 pasos, 12 tramos, 360 celdas en 144 de ellos.
  - Máximo de celdas: F 6, G 11, I 16, J 13.
  - Pasos con p >= 100 kPa que llevan nolink: 94/96, 27/27, 71/120, 56/142 y 70/219.
  - 86 de las 96 filas centinela llevan nolink.
  - Orden: primera centinela en 284340 (t = 284.341 s), primer nolink en 284669 (t = 284.670 s).
- **`k7v4_long`:** una fila por paso. En los 60 pasos desde 284669 hay 59 con nolink, 45 con p >= 100 kPa y 30 con u >= 299, con p_max de 152.7 kPa. No hay nolink en 280001-280031.
- **`duracion.py`:**
  - Reproduce la tabla del paso 12.
  - Uniones del criterio de pico: G 11, F 8, B 18, I 101, J 187, L 3, s290 2.
  - Uniones del nivel centinela: 7, 6, 9, 73, 120, 2, 2.
- **`pares.py`:**
  - C/E: <= 7.9e-9 en u y 1.5e-9 en p.
  - k10b/F: 1.1e-9 y 3.5e-10.
  - m_gas: 2.5-2.6e-7.
  - Ventana: E frente a C hasta 12 % en u.
- **tgfix:** el conjunto de pasos nolink de F es igual al de k10b. tgfix tiene nolink solo en 280002-280023 y se separa de k10b desde 280027.
- **`h22.py`:** implementa el criterio pre-registrado de {C-264} tal cual. Al ejecutarlo da H22 SOPORTADA y H23 REFUTADA.
- **Checkers que podrían pasar por la razón equivocada (descartado):**
  - Los ceros de `[CG] AVISO` son reales: los run.log están completos y la cadena existe en `mod_solver_3d.f90:276` (k11_base_s290 registra 1).
  - El nolink = 0 de los controles no viene de un skip del audit: las cinco columnas `m_gas_*_skip` valen 0 en A, H, M, N, O, C, P y k10b.
  - La clase nolink (`mod_audit.f90:1318-1335`) no depende de `pc_transport_f28`: esa clave no aparece en `mod_pressure_3d.f90`.
- **Configs de los pares:** cambian solo lo declarado.
  - A/F, M/I y O/J: solo f28.
  - N/B: f28 + presión total.
  - A/H y C/E: solo la presión total.
  - k10b/F: solo la presión total.
  - k10b/tgfix: solo el restart.
  - A/G: restart + f28.
- **Presión total:** la descripción coincide con `mod_pressure_3d.f90:1001-1027` y `2000-2012`.
- **Conteos por cuartos:** coinciden en G, I, J, B, k10b, tgfix y C. Hay 15 brazos con f28 encendida de 20.

## Orden sugerido de corrección (uno por uno)

1. **B3:** la regla se carga como convención, así que es lo que más se propaga.
2. **B1:** el nombre del umbral en `duracion.py`.
3. **B2:** la fuente de «mismos pasos» en el reporte.
4. **B4:** añadir el binario a los confusores.
5. **B5:** el error de uno en el texto.
6. **B6:** la interfaz de `nolink.py`.
