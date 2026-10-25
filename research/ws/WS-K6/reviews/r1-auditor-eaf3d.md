# Revisión r1 (auditor EAF3D) de WS-K6: volfix por celda en el balance de masa del gas

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO en el código staged. Quedan 3 hallazgos BAJO, ninguno bloqueante: dos de redacción y alcance de la evidencia y uno de un comentario desactualizado.

Revisión ciega: no leí `research/ws/WS-K6/reviews/`. Solo lectura: no compilé ni ejecuté nada. Usé solo `git diff --cached`, `grep`, `sed` y `python3` sobre los CSV y logs que ya existían.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

- **K6-A1-B1. «Diferencia 0.0» en el inciso (3) del reporte y en C-118.**
  - **Dato real:** en `research/ws/WS-K6/logs/test_full.txt` la diferencia de `mass_gas_vf_cells` es `0.00e+00` en 53 de 64 evaluaciones. Las otras 11 tienen diferencias de redondeo, de 6.3e-30 a 3.33e-15 kg, todas dentro de la tolerancia 1e-9·Σ|volfix| + 1e-12.
  - **Arreglo:** corregir la cifra en el reporte o con una nota en el ledger.

- **K6-A1-B2. La cobertura del check se exagera.**
  - El reporte dice que el check «lo cubre en los 64 casos». Pero en 15 de ellos el volfix registrado es exactamente 0 y el PASS es vacuo: arc_noscrap n1/n4, bath_test_cold, bath_test n1/n4/n12/stretch, bed_bath_rest n1/n4, pocket_rise, symmetry_3elec y los 4 reinicios de cold_10step.
  - Además, el check compara solo Σ por celda contra `m_gas_volfix`. Detecta una ruta que no llama a `audit_volfix_cell`, pero no una que la llama con índices o con un dm equivocados que suman lo mismo.
  - Hoy la atribución a la celda correcta se apoya en la lectura del código (abajo la verifiqué ruta por ruta).
  - **Arreglo:** decir «49 evaluaciones con volfix distinto de 0» y anotar ese límite.

- **K6-A1-B3. Comentario desactualizado en `src/mod_audit.f90:180-181`.**
  - Sigue citando «multifase -8.7e-4 kg» para B1, que es el valor de WS-K5 con el volfix dentro. En k6_mo20 la columna vale -8.555e-4.

## 2. Verificado como correcto (no re-auditar)

- **Las 6 rutas son todas las que hay.** Hay exactamente 6 sitios con `audit_add(AUD_GAS_VOLFIX, …)` en `src/`: `mod_fields_3d.f90:777`, `mod_ecs_feed.f90:280`, `mod_solid_phase.f90:142`, `mod_slag_3d.f90:679` y `:891`, `mod_slag_chemistry.f90:351`. Cada uno tiene su `audit_volfix_cell` y no hay otra ruta de volfix.
- **Mismo dm, misma celda, antes de sobrescribir `gas%alpha`.**
  - `charge_scrap` y `ecs_feed` reutilizan el mismo `dmg`.
  - `enforce_volume_constraint`, `slag_condensed_sort` y `slag_buoyancy` repiten la expresión `(ag_new - gas%alpha)·ρ·V` antes de la asignación `gas%alpha = ag_new`.
  - `compute_slag_chemistry` usa el mismo `ag_old = max(alpha, 0)`.
  - Los índices son locales y de celdas propias: `global_to_local(..., owned)` con `cycle` si no es propia, o lazos locales sobre el dominio propio. No se escriben halos.
- **Ventana del paso.** `audit_gas_cells(0)` está en `main_3d.f90:337` y `(1)` en `:795`. Todas las llamadas por paso quedan dentro: carga de la cesta 2 (`:365`), ECS (`:383`), química de escoria (`:467`), `enforce_volume_constraint` (por `update_solid_premelt` y `apply_mass_source_noflow`), sort de inicio de paso (`:598`) y `update_slag` (sort y flotación).
  - Ninguna ruta de volfix corre dentro del lazo de iteraciones externas, así que el registro es por PASO.
  - La carga de la cesta 1 (`bucket > 1` no audita) y la flotación inicial (`:251`) van antes del lazo, con `mg_vf` aún sin asignar, y `audit_init` reinicia `acc` después.
- **`mg_vf`.**
  - Se asigna con `mold=gas%alpha` y se anula ENTERO en el modo 0, halos incluidos, así que no repite el Bug 22.
  - No es estado entre pasos y no hace falta en el snapshot.
  - Con `audit_freq = 0` nunca se asigna y la llamada no hace nada.
- **Suma en `audit_gas_cells(1)`.**
  - Recorre las mismas celdas que las rutas: excluye `cell_type == 0` y las rutas tampoco las tocan.
  - Suma `AUD_MG_VF_CELLS` antes del `cycle` de outlet, así que entra también el volfix de las celdas outlet.
  - En los pasos sin balance (mezcla o sin multifase) no suma, y `check_audit` solo evalúa el check si nskip = 0.
- **Reducción MPI y CSV.** `AUD_MG_VF_CELLS` = 67 entra a la `mpi_allreduce_sum` de `1..N_AUD`. Encabezado y write quedan alineados: 93 columnas en k6_mo20, menos que el `100(...)` del formato. La columna va al final, así que los lectores por nombre no se rompen.
- **Datos B1 recalculados con python sobre los CSV.**
  - k5_mo20: multi -8.6855367e-4.
  - k6_mo20: multi -8.5549254e-4, libre 2.1834595e-5 (antes 2.1793717e-5), outlet sin cambio (9.2438284e-4), `m_gas_vf_cells` = `m_gas_volfix` = -1.3102000e-5. El signo es coherente con `e -= mg_vf`.
  - k6 frente a sonda_gc_* (87 columnas comunes, 60 renglones, mo20 y base): solo difiere `m_gas_volfix`, en 15 renglones, con |Δ| ≤ 5.29e-23. Coincide con el reporte.
- **Cierre EOS − celdas − venteo en test-full.** Las 64 líneas dan |cierre| ≤ 3.99e-12 kg, el peor con |EOS| 1.097.
- **`check_audit.py`.** El nuevo `clos` quita el `+ m_fix`, coherente con el cambio en Fortran. El check `mass_gas_vf_cells` solo corre si la columna existe y con nskip = 0. No encontré un PASS por la razón equivocada, salvo los casos vacuos de B2.
- **Ledger.** C-117, C-118 y C-119 son coherentes con el reporte. La refutación en la letra del inciso (5) se debe al valor de k5 redondeado en el criterio, y la confirmé con los números de arriba.

## 3. Orden sugerido de corrección (uno por uno)
1. K6-A1-B1: corregir «diferencia 0.0» en el reporte o el ledger.
2. K6-A1-B2: precisar 49 evaluaciones no vacuas y el límite «suma, no celda».
3. K6-A1-B3: actualizar la cifra de B1 en el comentario de `mod_audit.f90`.
