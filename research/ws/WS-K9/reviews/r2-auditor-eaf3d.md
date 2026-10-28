# Revisión WS-K9, ronda 2 (auditor-eaf3d)

**Veredicto: aprueba.** El código staged no cambia desde la ronda 1: `src/mod_audit.f90`, `src/main_3d.f90`, `tests/run_tests.sh`, el config nuevo, el glosario y el golden v132. No encontré defectos ALTOS ni MEDIOS. Mi objeción B5 de la ronda 1 queda resuelta con un dato (C-201). Las B1 a B4 siguen abiertas, todas BAJAS y no bloqueantes.

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO (siguen abiertos, no bloqueantes)
- **K9-A1-B1**: `research/ws/WS-K9/report.md:15` todavía atribuye la acumulación a `audit_write_step`. Está en `audit_accumulate`, en el bloque del venteo (`src/mod_audit.f90:862-910`).
- **K9-A1-B2**: en `cold_flow_noenergy` el check `mass_gas` pasa también con el binario previo (venteo 0, EOS 3.36e-6 rel; `research/ws/WS-K9/logs/coldnoE_binario_previo_check.txt`). El único check que discrimina es `mass_gas_flux_closure` (resto 3.41e-6 contra 1.69e-21). El reporte (línea 64) sigue citando `mass_gas` como evidencia sin aclararlo.
- **K9-A1-B3**: los comentarios de `tests/integration/configs/cold_flow_noenergy.dat` están heredados de cold_10step: «física de flujo completa», u_gas~5 m/s y energy_balance 0.97. No describen este banco.
- **K9-A1-B4**: `Ejecutable:` es solo la ruta, no identifica el build, y `get_command_argument` se llama sin status (ruta de más de 1024 caracteres truncada sin aviso). Ya está declarado en Incertidumbre.

## Resuelto desde la ronda 1
- **K9-A1-B5 (procedencia del binario previo)**: verificado. `shasum -a 256 campaigns/bin/eaf3d_k8b_opt` da `bbe3e11c…81ad3`, el mismo hash que registra `research/ws/WS-K8/logs/opt_identidad.txt` para el `bin/eaf3d_mpi` de las 14:27. El sha256 del diff de `src/` de ese build (`78797d1c…3e32ef`) coincide con `git diff 79dc27b~1 79dc27b -- src | shasum -a 256`, y `git diff 4aa8363 79dc27b~1 -- src` está vacío. El diff de git incluye los hashes de blob, así que la igualdad implica el mismo contenido: ese binario se compiló con el `src/` de 79dc27b.

## Verificado como correcto (no re-auditar)
- `gas_mass_on = solve_flow .and. solve_multiphase` gobierna el bloque del venteo (`mod_audit.f90:812, 862`). La entalpía (`srcacc(17)`) sigue condicionada a `gas_energy_on` (líneas 889-904) y AUD_GAS_OUT se acumula fuera de esa condición. Con energía activa, el camino es idéntico al anterior.
- `ws_Fg_valid` lo pone `mod_pressure_3d.f90:881`, que no depende de la energía, y se apaga por paso en `main_3d.f90:586`. Sin energía, el venteo usa los mismos flujos conservativos que el cierre: resto 1.69e-21 en `test_full.txt:2138+`.
- Ningún banco previo combina energía apagada con flujo de dos fluidos: chem_test, ecs_test y slag_chem_test tienen `solve_flow = false` y `solve_multiphase = false`. Es coherente con el error relativo 0 en las métricas.
- Golden: `test_full.txt` 5087-5149 compara contra v131 (commit 529e96e, 22-oct) y da 60 PASS con err rel 0.000e+00. El único FAIL es el banco nuevo. En v132 frente a v131: añadido solo `cold_flow_noenergy_n4`, ningún banco común cambia y no se quita ninguno.
- `test_unit.txt`: UNIT TESTS OK. `test_rebaseline.txt`: OK, incluido el audit-restart de cold_10step con 0 de diferencia.
- Reproducción con el binario previo (`coldnoE_binario_previo_*.txt`): 4 procesos, sin línea `Ejecutable:`, m_gas_out 0 y FAIL del cierre con resto 3.41e-6.
- `main_3d.f90`: el bloque de impresión está dentro de la rama del rank 0 y `compiler_version` viene de `iso_fortran_env`. No toca halos, estado ni reinicio.
- No hay estado persistente nuevo (nada que añadir al snapshot) ni ruta de masa o energía nueva sin auditar: el cambio solo activa una columna que ya existía.

## Orden sugerido de corrección (uno por uno, ninguno bloquea el cierre)
1. B1 y B2: dos frases en `report.md`.
2. B3: comentarios del config del banco nuevo.
3. B4: opcional, identificador del build en run.log, en otro WS.
