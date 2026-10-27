# WS-K8, ronda 1: revisión de código (auditor-eaf3d)

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Quedan 4 hallazgos BAJO, ninguno bloqueante.

El alcance fue el diff staged: `src/mod_pressure_3d.f90`, `src/mod_audit.f90`, `src/mod_workspace.f90`, `tests/integration/check_audit.py`, el glosario y las reglas, todo contrastado con `research/ws/WS-K8/report.md`. Trabajé en solo lectura, sin compilar ni correr nada.

## 1. Hallazgos

### BAJO

**K8-A1. Falso FAIL latente en `mass_gas_flux_closure`**
- **Dónde:** `tests/integration/check_audit.py:456-473` y `src/mod_audit.f90:806,857,899`.
- **Defecto:** `m_gas_out` solo se acumula con `gas_energy_on` (requiere `solve_energy`). En cambio, `flux_multi` y `flux_free` solo exigen `solve_flow`, `solve_multiphase` y `ws_Fg_valid` (`mod_audit.f90:1058`).
- **Escenario de fallo:** una config con flujo y multifase activos, `solve_energy=false` y audit activo da `m_gas_out = 0` y `flux_multi + flux_free != 0`, así que el check da FAIL sin que haya defecto.
- **Alcance:** hoy ningún banco de `tests/out` tiene esa combinación (lo verifiqué), así que no afecta a WS-K8.
- **Arreglo:** condicionar el check, o acumular la masa de `AUD_GAS_OUT` fuera de `gas_energy_on`.

**K8-A2. La justificación de "no tautológico" del checker es imprecisa**
- **Dónde:** el comentario de `check_audit.py:452-456` y el reporte.
- **Defecto:** el reporte y el comentario dicen que `m_gas_out` "sale de otro camino de código". En realidad es la misma expresión `ws_Fg*ws_Fg_lk` sobre las mismas celdas de salida (`mod_audit.f90:873-900` frente a `1090`; la función `outlet` declara la misma definición).
- **Lo que el check verifica de verdad:** el telescopio de los flujos de cara. Es decir, la coherencia de `ws_Fg` y `ws_Fg_lk` en las costuras entre ranks y en la periódica de theta, y que no hay flujo enlazado en la frontera física (`cell_type` vale 0 en los halos físicos, `mod_mesh` 248-251). Ese contenido es real, y la conclusión del 95.3 % se sostiene.
- **Arreglo:** cambiar la redacción del comentario y del reporte.

**K8-A3 (PLAUSIBLE). La conversión volumen→masa del plan es incompleta**
- **Dónde:** `mod_pressure_3d.f90:631` (`ws_gadv_used = gadv`).
- **Defecto:** `gadv` no es la conversión exacta del flujo realizado `gmass` (`mod_pressure_3d.f90:1032-1039`):
  - (i) usa los Q* del ensamblaje y no el Q corregido. Esto está declarado en el reporte.
  - (ii) omite las caras en las que alguna celda tiene `alpha_g < ALPHA_CUTOFF` (guarda M6-1, `mod_pressure_3d.f90:1061`), aunque `gmass` sí use allí la ρ del dador. No está declarado.
  - (iii) vale 0, y rx no entra en `su_cc`, en las celdas `act_g` que el lazo de compresibilidad salta, mientras `err_cc` sigue restando rx. No está declarado.
- **Escenario de fallo:** entra gas desde un canal F2.17 con `alpha_g` casi 0 y una ρ rancia. La diferencia (ρ_N − ρ_P)·Q termina en rem2 como "no explicado".
- **Lo que falta:** no medí la magnitud. El veredicto "refutada por la letra" se sostiene con el instrumento pre-registrado.
- **Arreglo:** declarar (ii) y (iii) en Incertidumbre. Para atribuir el residuo, guardar la conversión exacta en un WS posterior.

**K8-A4. `m_gas_cc_skip` no es un control independiente**
- **Defecto:** la columna vale 0 por construcción mientras corre la rama por celda. La razón es que `ws_Fg_valid` se pone a falso en cada paso (`main_3d.f90:577`) y solo lo vuelve a poner a verdadero el mismo Poisson que validó `ws_su_cc_used` con el id del paso (`mod_pressure_3d.f90:780,881`).
- **Consecuencia:** el AVISO de la INFO `mass_gas_cells_cc` nunca se dispara.
- **Arreglo:** añadir en el glosario la misma advertencia que ya tiene `m_gas_e2_skip`.

## 2. Verificado como correcto

**Workspace y Poisson**
- Arrays nuevos de `mod_workspace` (`ws_su_cc_used`, `ws_gadv_used`, `ws_store_gas`, `ws_store_art`):
  - se crean con `mold=ws_aW` y se ponen a 0 en el array entero, halos incluidos, sin riesgo de Bug 22;
  - se reinician al empezar cada Poisson;
  - no son estado entre pasos: la validez va por id de paso, así que no hacen falta en el snapshot;
  - no los lee ningún módulo numérico, solo `mod_audit`.
- Anulación de `ws_su_cc_used` y `ws_gadv_used`: en las filas triviales o selladas, y en las de `Su == 0` tras `apply_pressure_bc` (salidas y `cell_type` 0).
- `ws_store_art`:
  - suma la compliance Σa_nb·`PP_COMPLIANCE`, más (piso D2.4 − parte real), más el acústico del líquido;
  - se calcula ANTES de `apply_pressure_bc`, lo cual es correcto: el plegado Dirichlet hacia una salida es flujo real, no almacenamiento;
  - los ceros de pared de `apply_pressure_bc` no alteran nada, porque `link()` ya da 0 contra los halos físicos.
- `ws_store_gas`:
  - coincide con el término que entra en aP, porque `ag_c >= gas%alpha` en `act_g`;
  - la resta en `store_art` es exacta (las mismas operaciones).
- La conversión a caudal con `sh%pp` justo después del CG es correcta: `pp` no se modifica hasta la corrección, y en las salidas pp = 0.
- Signos del plan: de la fila del Poisson se obtiene e ≈ comp + eos + ρdt(su_cc − gadv − store) + ρdt·liq − rx, coherente con `err_cc` y `err_art`. Restar el `gadv` sin pesar (aunque `su_cc` lleve `fsat·gadv`) es correcto.

**Audit**
- El orden del encabezado coincide con el orden de escritura en las 20 columnas nuevas.
- `N_AUD = 111`, y la reducción suma todas las entradas.
- El contador `CC_SKIP` solo lo incrementa el rank 0.
- `elf` (gas libre) usa la misma fórmula que `el` (multifase).
- `rem2` se acumula en el mismo conjunto de celdas que el `err_abs` de su clase cuando `liq_ok` y `cc_ok` son verdaderos.
- Filtros de `check_audit`: `cs` y `lq` (sin `liq_skip`, sin `cc_skip`, sin escoria).
- `mass_gas_class_split` es tautológico en el flujo y en rx, tal como se declara.

**Números del reporte, recalculados desde `campaigns/b1/k8_*/audit.csv`**
- Cocientes: 0.863 / 0.197 / 1.497 / 0.3156 / 1.571; 0.847 y 1.004; 0.339 y 0.918.
- Reparto del neto: comp, eos, flux, rx y m_gas_out; porcentajes 95.3 / 93.3 / 115.7 %.
- `err_art`: 2.96e-6.
- Los skips valen 0 en las 59 filas.

**Convergencia del CG**
- Cero `[CG] AVISO` en `k8_cg1000`. El aviso sale en el caso 1 y cada 1000 (`mod_solver_3d.f90:271-279`), así que 0 avisos implica que ningún Poisson agotó las iteraciones.
- El hueco por |p·q| < SMALL (línea 245) está declarado en el reporte.

**Identidad bit a bit y tests**
- Bit a bit: `k8_mo20` frente a `k7v5_mo20` coincide en 117 columnas comunes. Solo difieren las `m_gas_err_*`, en ≤ 1.1e-19.
- El sha256 del diff staged de `src/` coincide con el de `logs/opt_identidad.txt` (78797d1c…).
- Barrido de `tests/out`: `mass_gas_rewrites` 78 PASS; `class_split` y `flux_closure` 66 PASS; 0 FAIL.
- Logs: unit, quick y full en OK, golden v131. Los XFAIL son los conocidos.

## 3. Orden sugerido de corrección (ninguno bloquea el cierre)
1. K8-A2: redacción del checker y del reporte.
2. K8-A4: advertencia en el glosario.
3. K8-A1: condicionar el check o mover la acumulación de `m_gas_out`, con un banco corto `solve_energy=false`.
4. K8-A3: declarar (ii) y (iii). Si se quiere atribuir el residuo del gas libre, conversión exacta en un WS pre-registrado.
