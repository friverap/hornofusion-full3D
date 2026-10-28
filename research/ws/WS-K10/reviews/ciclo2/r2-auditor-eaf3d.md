# WS-K10, ronda 1: auditor-eaf3d (código del diff staged)

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Quedan dos BAJO que no bloquean.

Fuera de alcance: no compilé ni corrí nada. Solo ejecuté `check_audit.py`, `compare_audit.py`, `cmp_comunes.py` y `h14.py` sobre salidas que ya existían, todas de solo lectura.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B-1. `tests/integration/check_audit.py:537-541`: `mass_gas_eos_end` da PASS vacuo cuando la escala es 0.**
- En 8 de los 43 bancos de `tests/out` con la descomposición evaluada, `m_gas_eosend_scale` suma 0. Son bath_test_n1/n4/n12, bath_test_stretch_n4, bed_bath_rest_n1/n4, cold_flow_noenergy_n4 y pocket_rise_n4.
- El checker imprime `PASS ... = 0.00e+00 (max 1e-13 x 0.00e+00 + 1e-20; valida el reparto Br1/Br2)`. Ahí Br2 ≡ 0, así que el resultado no es falso, pero tampoco valida nada.
- Escenario de fallo: si una regresión dejara la escala en 0 (por ejemplo, el gancho de `mg_eos` movido después de `update_properties`), el check seguiría en PASS.
- Arreglo: imprimir INFO n/a cuando la escala sea 0. En el reporte, decir que el reparto se valida en 35 bancos.

**B-2. Los arrays nuevos se reservan y se ponen a cero aunque el audit esté apagado.**
- Dónde: `src/mod_pressure_3d.f90:221-222` (puesta a cero en cada Poisson) y `src/mod_workspace.f90:546-550` (reserva siempre).
- `ws_Fgv_*` se escriben también siempre (`ws_Fg = gmass(ws_Fgv)`). El coste es despreciable y el resultado es idéntico.
- El problema es de redacción: `.claude/rules/transporte-energia.md:349-350` dice «exporta … solo con `audit_freq > 0`». Solo son condicionales el intercambio de halos, la copia `ws_rho_g_used` y `ws_pc_res`.
- Arreglo: corregir la redacción y, si se quiere, proteger la puesta a cero con `audit_freq > 0`.

## 2. Verificado como correcto (no re-auditar)

- **Identidad algebraica.** Partí de D = ee − elf − ecc − eart. Con `pa`, `br1`, `br2`, `bgr`, `bgq` y `bx` tal como están en `mod_audit.f90:1226-1255`, resulta:
  - D − Σpiezas = (residuo por celda de la identidad K7: dm − comp − eos − volfix) + ρ_it·dt·`rvv`.
  - Por tanto el cierre en masa equivale a K7 más la fila en volumen.
  - Parecería que ρ_it se cancela, pero no queda sin validar. El cierre exige −fl = dt Σ ρ_dador q_out, y eso solo se cumple si `ws_rho_g_used` coincide con la densidad que usó `gmass` en las celdas dadoras.
  - `gface` usa el mismo dador que `gmass` (la celda − si q ≥ 0) y sale con q = 0, igual que gmass, que en ese caso da 0. Así no lee halos de frontera física.
- **Bgq.** `gadv` (`mod_pressure_3d.f90:1096-1112`) es Σ_in q*(ρ_N − ρ_P)/ρ_P, con la guardia ALPHA_CUTOFF. Entonces Bgq = dt Σ_in (ρ_N − ρ_P)(q* − q), más las caras de la guardia y las caras que cambian de sentido. Coincide con lo que dice el reporte.
- **`ws_rho_g_used`.**
  - Es una copia de `gas%rho` justo después del bucle de `gmass`.
  - `solve_pressure_correction` no escribe `gas%rho`: los únicos escritores son `mod_properties_3d:42` y la inicialización.
  - `correct_velocities` va después y no toca rho.
- **`ws_rho_g_pre` y la marca de la EOS.**
  - Se toman en `main_3d.f90:798-804`, después de `audit_accumulate` y justo antes de la única `update_properties` final (807). El modo 1 llega en 812.
  - Entre el último Poisson y la marca solo cambia rho la EOS del mismo outer (`mod_multiphase.f90:579`). Br1 está bien etiquetado.
- **Ids por paso.** `probe_set_step(step)` se llama cada paso, en la línea 575, antes del SIMPLE. `ws_Fgv_valid` se reinicia en cada Poisson. Los ids impiden reutilizar datos de un paso anterior.
- **Estado entre pasos.** No hay ninguno, así que no hace falta entrar al snapshot.
- **Frecuencia del audit.** Se acumula una vez por paso (modo 1), no por iteración externa.
- **Bug 22 y dummies.**
  - `mg_eos_pre` se reserva con `mold=mg_eos` y se copia entero desde un array inicializado completo.
  - `ws_rho_g_used` y `ws_rho_g_pre` son copias enteras de `gas%rho`, cuyos halos son coherentes.
  - No hay dummies de array nuevos.
- **Halos MPI.**
  - Se intercambian `ws_Fgv_*`. En serie, `mpi_exchange_halos_3d` hace la copia periódica en θ.
  - `ws_pc_res` usa `sh%pp`, cuyos halos intercambia `cg_3d_mpi` al final. Si el CG sale antes de tiempo, pp es 0 entero (línea 443).
  - El residuo se lee solo en celdas propias.
- **`ws_pc_res`.**
  - Usa la misma expresión y el mismo orden que `matvec`.
  - Las filas excluidas (cell_type 0, salidas, filas no activas y selladas) no tienen caras enlazadas.
  - `pc_fs_*`: `fs_on` exige las dos claves (línea 1255), igual que la exclusión de `dec_ok`.
- **CSV.**
  - Hay 24 columnas nuevas (de la 112 a la 135), con el mismo orden en la cabecera y en la escritura.
  - El formato admite `200(A,ES)` y se usan 158.
  - El glosario y `AUDIT_COLUMNS.md` cubren las 24.
  - `DEC_SKIP` solo lo cuenta el rank 0, y sus condiciones son globales.
- **Suite, con el `check_audit.py` staged sobre `tests/out`.** Da 43 PASS en los tres checks y 36 INFO n/a.
  - Las causas de los n/a son legítimas: sin multifase o sin flujo, mezcla, escoria condensada (`liq_skip`) o `bed_flood` (`pc_fs`).
  - En los reinicios, la fila N queda fuera (`steps = rows[1:]`).
- **Reinicio con otro número de ranks.** `compare_audit --decomp` sobre `cold_10step_n8_to_n4` y `n8_to_n12`, con rtol 1e-10, da PASS. La peor columna nueva, `m_gas_brho_it_multi`, queda en 1.2e-12.
- **Procedencia del binario y bancos.**
  - sha256 de `git diff --cached -- src/` = 74a5e2…, que es el del binario `eaf3d_k10b_opt` (5409bb…) según `opt_identidad.txt`.
  - El src no cambió entre 5999f40 y HEAD.
  - `k10b_*` y `k11_*_s290` dicen «Ejecutable: campaigns/bin/eaf3d_k10b_opt».
- **Sin cambio numérico.** `cmp_comunes.py --par` da 137 columnas comunes idénticas como cadenas en tres pares: k8s_mo20/k10b_mo20, k8s_dt05/k10b_dt05 y k8_base/k10b_base.
- **Cierres en campaña.**
  - `k10_*`: PASS con la tolerancia de la primera versión (1.41e-11 a 1.46e-11).
  - `k10b_mo20` y `k11_dt05_s290`: los tres en PASS (eos_end 1.9e-18 y 2.3e-18 kg).
  - Por fila, el cierre queda en ~5e-16 kg.
- **H14 (C-231/C-232).** `h14.py` reproduce 0.877 y 6.996e-6. El criterio del registro coincide. `k11_dt05_s290` no tiene ningún FAIL ni ningún `[CG] AVISO`.

## 3. Orden sugerido de corrección (uno por uno)

1. B-1: INFO n/a en `mass_gas_eos_end` cuando la escala es 0, y la cifra del reporte. Toca un checker de `tests/integration`.
2. B-2: la redacción de la regla y, si se quiere, la guarda de la puesta a cero.
