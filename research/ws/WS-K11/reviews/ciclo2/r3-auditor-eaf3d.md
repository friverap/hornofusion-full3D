# WS-K11, panel de cierre, ronda 1: revisión del auditor-eaf3d

**Veredicto: RECHAZA.** Quedan dos hallazgos MEDIO sin resolver, los dos en la regla `.claude/rules/transporte-energia.md` (staged) y en el reporte. No hay defectos en el código de medida.

## Alcance

- El diff staged no toca `src/` ni `tests/`. `diff_sha` = e3b0c442…b855, que es el sha256 de un diff vacío y coincide con `ledger.py` (`git diff --cached` de `src/` y `tests/`).
- El código revisado:
  - los scripts nuevos `research/ws/WS-K11/scripts/duracion.py` y `pares.py`;
  - `h22.py` (ya commiteado en 8b2d95b), que decide C-265 y C-266;
  - el texto nuevo de la regla de transporte;
  - las entradas C-265, C-266 y C-267 del registro.
- No leí las revisiones de otros revisores.

## Hallazgos

### MEDIO

**M1. N/B no es un par de una sola clave; «f28 lo da en fh 290 s» no está medido; la cita C-257 está mal.**

- **Dónde:**
  - `.claude/rules/transporte-energia.md:363-366`
  - `research/ws/WS-K11/report.md:12-16` y `:451-457`
  - `research/ledger.jsonl`, C-265 y C-266
- **Defecto:** `diff campaigns/b1/k11_n_dt025_fh290_off/config.dat campaigns/b1/k11_b_dt025_fh290_on/config.dat` muestra que N y B difieren en `pc_transport_f28` **y** en `pc_outlet_total_pressure`. Sin embargo:
  - la regla dice que *encender f28* da la firma en fh 290 s;
  - el titular llama a N «control de una sola clave»;
  - C-266 cuenta 290 s entre los «5 de 6 estados» donde f28 la da.
- **La cita C-257 no sirve para lo que se afirma:**
  - C-257 (H21, brazo H) prueba que la presión total no es *suficiente*.
  - Que no es *necesaria* lo prueba C-249 (F), y solo en 280 s.
  - Tampoco hay control sin cambio para el estado de 280.06 s (G).
- **Escenario de fallo:** una sesión futura toma la regla como prueba de que f28 sola dispara la firma en 290 s. Ese brazo no se ha corrido, y en jb 280 s la presión total separa u_gas_max hasta un 12 % en la ventana (`pares.py` C/E).
- **Arreglo, una de dos:**
  - Corregir la redacción en la regla, el titular y la sección 13, y añadir una entrada de corrección de C-265/C-266 al registro: «en 290 s, con las dos claves (B); f28 sola no probada»; la no necesidad de la presión total se apoya en C-249 (280 s).
  - O pre-registrar el brazo fh 290 s con solo f28 encendida.

**M2. La regla generaliza la persistencia del régimen ≥ 100 kPa tras el cambio.**

- **Dónde:** `.claude/rules/transporte-energia.md:386-388` y `report.md:67`, `:222`, `:779`.
- **Defecto:** se afirma que «con 0.25 ms el régimen tras el cambio se mantiene ≥ 100 kPa en los 60 ms». Recalculé los pasos con p_max ≥ 100 kPa por cuartos, sin el paso 1:

  | brazo | pasos ≥ 100 kPa por cuartos | ¿se mantiene? |
  |---|---|---|
  | G | 27, 0, 0, 0 | no: cae tras el primer cuarto |
  | I | 59, 6, 22, 55 | no: bajón en el segundo cuarto |
  | P | 0, 0, 0, 0 | no: cambio sin régimen |
  | k10b_dt025 / F, B, J | — | sí |

- **Escenario de fallo:** quien diseñe un banco con cambio de f28 supondrá que la ventana entera queda contaminada, o que el régimen siempre persiste. G lo contradice.
- **Arreglo:** acotar la frase a k10b_dt025/F (120/235), B (235/235) y J (219/239), y citar las excepciones G, I y P.

### BAJO

**B1.** En la regla (`.claude/rules/transporte-energia.md:376`), «jb 295 s … toca 300 m/s 3 pasos» es inexacto. Los valores de 295002-295004 son 300.0, 299.8 y 245.3 m/s: un paso en U_GAS_MAX y tres ≥ 200 m/s. El reporte lo dice bien en el paso 12. Basta con corregir la redacción.

**Observación, sin defecto confirmado.** `status.json` staged trae `prediccion: "C-264"` aunque el ciclo tiene dos (C-263 y C-264). Como `numerico` es false, no afecta al guard.

## Verificado como correcto (no re-auditar)

- **`h22.py`**
  - P0 (primera fila de `audit.csv`) es la fila del reinicio en los 19 brazos. Lo comprobé con step y time: el linaje fh/jb tiene un desfase de +1 ms en el time del snapshot; el de G, P y Q es coherente.
  - El filtro `step > P0+1`, los conteos de nolink y de p_max ≥ 100 kPa y el criterio de firma son correctos.
  - La cadena `[CG] AVISO` coincide con `src/mod_solver_3d.f90:276`.
  - Reproduce M/N/O (15, 18 y 20 kPa; nolink 0) y P/Q (96 y 95 kPa; nolink 0). Resultado: H22 SOPORTADA y H23 REFUTADA.
  - Ningún `audit.csv` tiene filas duplicadas (241 o 237 filas por corrida).
- **`check_audit.py`** (solo lectura): 0 FAIL y 23 PASS en M, N, O, P y Q.
- **Configs:** M/I y O/J difieren solo en f28. P/F y Q/C difieren solo en `restart_file` y `t_final`. N/B difiere en dos claves (ver M1).
- **`pares.py`**
  - E frente a C: 7.9e-9 en u_gas_max, 1.5e-9 en p_max y 2.6e-7 en m_gas.
  - F frente a k10b_dt025: 1.1e-9, 3.5e-10 y 2.5e-7.
  - nolink: 105/105 en el par F/k10b_dt025 y 0/0 en el par C/E.
  - «Pasos 0-10» equivale a `r[:11]` desde P0; es correcto.
- **`duracion.py`:** G 9/7, último paso 27; I 99/55, 232; J 187/74, 226; L 3/0, 4.
- **Tablas del paso 12, recalculadas:**
  - Unión u ≥ 200 o p ≥ 300 kPa: G 11, F 8, B 18, I 101, J 187, L 3, s290 2.
  - Nivel centinela de B1: G 7, F 6, B 9, I 73, J 120, L 2, s290 2.
  - Pasos con nolink y p < 100 kPa: F 34, G 8, B 0, I 1, J 2.
  - Máximo de p_max sin nolink: F 380, G 91, I 634, J 2000 kPa.
- **Filas de nivel centinela B1 en 280-295 s:** fh 15, jb 1, otp 26.
- **Medias de P por cuartos:** 43.8, 35.4, 33.5 y 26.4 kPa; alternancia 86/54 kPa. `judge_fh_275` sube de 56 a 112 m/s en 299.9-300.0 s.
- **`m_gas_cells_nolink`**
  - `lk_any` lee las banderas de cara de las seis caras (`src/mod_audit.f90:1318-1335`).
  - El halo de esas banderas se intercambia tras el Poisson (`src/mod_pressure_3d.f90:876-878` y `:912-914`): la frontera de bloque no fabrica celdas nolink falsas.
  - El acumulador se reduce con `mpi_allreduce_sum` (`mod_audit.f90:751`): es un conteo global.
- **Snapshot final `eaf3d_00299999.h5`:** lo escribe la misma `write_hdf5_parallel` (`main_3d.f90:937`), con el mismo grupo `/restart` (18 datasets, entre ellos `liq_cont_prev`, `Tg_end` y `comp_carry`) y dt nominal. P no está confundido por el tipo de snapshot.
- **Presión total:** solo actúa en celdas de salida con gas y `ws_Fg_valid`; con u_in ≤ 0 el objetivo es p0 (`mod_pressure_3d.f90:1001-1010` y `:2000-2012`).
- **Citas de código del reporte, correctas:**
  - `gas_eos` (`mod_constants.f90:594-599`), cuyas constantes (100 K, 300 K, 0.05·P0) usa la comprobación de C-228;
  - `mod_multiphase.f90:473-477`: `Tg_ref` queda asignado entero por `where`/`elsewhere`, sin riesgo de Bug 22;
  - `mod_pressure_3d.f90:598-601`;
  - `mod_config_3d.f90:110`.

## Orden de corrección sugerido (uno por uno)

1. M1: redacción en la regla, el titular y la sección 13, más la entrada de corrección de C-265/C-266 en el registro; o el brazo fh 290 s con solo f28.
2. M2: acotar la persistencia del régimen en la regla y en el reporte, con G, I y P como excepciones.
3. B1: redacción de L en la regla.
