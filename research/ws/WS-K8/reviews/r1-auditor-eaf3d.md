# WS-K8: revisión ciega del código del diff staged (auditor-eaf3d, r1)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Hay un BAJO, que no bloquea.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO
- **B1. `mass_gas_flux_closure` depende de que la energía esté activa.** Ver `tests/integration/check_audit.py:416-422` y `src/mod_audit.f90:806` y `:857-901`.
  - **Defecto:** `m_gas_out` (AUD_GAS_OUT) solo se acumula dentro del bloque `gas_energy_on = solve_energy .and. solve_flow .and. solve_multiphase`. En cambio, `audit_gas_cells` llena `m_gas_flux_*` sin mirar la energía.
  - **Escenario:** un banco de flujo frío (`solve_energy=false`, flujo y multifase activos) da `m_gas_out = 0`. El resto del check vale la entrada neta a las celdas de salida y sale FAIL aunque la contabilidad sea correcta. Es una falsa alarma, no un falso PASS. Ningún banco de la suite tiene esa configuración (revisé todos los `config.dat` de `tests/out`), y no afecta a `k8_*` ni a B1.
  - **Arreglo:** acumular la masa de `m_gas_out` fuera del bloque de energía, con la misma máscara de outlet y `ws_Fg`, o saltar el check cuando `solve_energy` esté apagado.

## 2. Verificado como correcto (no hace falta re-auditarlo)

**Identidad del código probado**
- El sha256 de `git diff HEAD -- src/` y el de `git diff --cached -- src/` coinciden: `78797d1c…32ef`. Es el mismo valor que registra `research/ws/WS-K8/logs/opt_identidad.txt` antes de `make opt` y de los tests. El código staged es el que se probó.
- `test_full.txt` termina en `TESTS (full): OK`. Los 6 «FAIL» del log son XFAIL ya existentes. `mass_gas_class_split` y `mass_gas_flux_closure` dan PASS en los 64 bancos del log.

**Instrumento en `src/mod_pressure_3d.f90`**
- Al empezar cada Poisson se anulan `ws_su_cc_used`, `ws_gadv_used`, `ws_store_gas` y `ws_store_art`, y se pone `valid=.false.` (l. 216-218). La rutina no tiene `return` temprano, así que los valores son siempre los del último Poisson del paso. `id = probe_current_step()` impide leer datos de otro paso.
- `ws_su_cc_used = dcl` es exactamente lo que se suma a `Su`, con fsat, acarreo, reacciones y tope (l. 627-631). `ws_gadv_used` es la `gadv` de ensamblaje, normalizada por `max(ρ_P, SMALL)` (l. 1066-1067). Se anulan en las filas triviales o selladas (l. 680-681) y donde `Su == 0` tras las BC, que son las de salida y `cell_type 0` (l. 770-777). Las celdas que el bloque de compresibilidad salta (`¬act_g` o `α_g < ALPHA_CUTOFF`, y las de electrodo del techo) se quedan en 0. Esto es coherente con el candidato (ii) del reporte.
- `store_art + store_gas` coincide con `aP − Σa_nb` calculado **antes** de `apply_pressure_bc`:
  - el plegado Dirichlet hacia las celdas de salida conserva el enlace en `aP`, pero ese enlace es flujo por cara (`ws_Fg` y `ws_Fc` con `pp_out = 0`), no almacenamiento, y no entra en `store`;
  - el piso D2.4 se resta bien: `ag_c·… − store_gas`, que da 0 exacto cuando `ag_c = α_g`;
  - el término acústico del líquido se suma igual que en `aP`;
  - `α_g` está recortado a ≥ 0 (`src/mod_continuity.f90:810,1689`), así que no hay desajuste entre `act_g` y `ag_c > 0`.
- `ws_store_* · sh%pp` tras el CG: `sh%pp` y `ws_*` comparten límites `(-1:n+2)` y los halos de `store` valen 0. En las filas de salida `pp` queda exactamente en 0 (`pp = 0` inicial, fila desacoplada y simétrica). Nada modifica `pp` entre el CG y la corrección de `ws_Fg` (l. 866-871). `sh%p` avanza `alpha_p·pp` (l. 898), como dice el reporte.

**Bit a bit y estado persistente**
- El diff solo escribe en los `ws_*` nuevos y en `acc`. No toca coeficientes, `Su`, `pp`, campos ni flujos.
- Comparé `k8_mo20` con `k7v5_mo20` (60 filas). Solo difieren `m_gas_err_*`, que se recalculan en el lazo modificado. Todas las columnas físicas son idénticas.
- No hay estado nuevo que tenga que entrar en el snapshot de reinicio: todo vale dentro del paso, por id.
- Los `allocate(..., mold=ws_aW)` se inicializan a 0, así que no se repite el Bug 22. `ensure_workspace` hace la asignación una sola vez (`if allocated(ws_aP) return`).

**Audit en `src/mod_audit.f90`**
- `N_AUD` sube de 91 a 111 (+20 columnas). La reducción MPI recorre `1..N_AUD`. El orden de la cabecera coincide con el de la escritura, y `audit.csv` tiene 137 columnas. `m_gas_cc_skip` solo lo suma el rank 0. El glosario cubre todas las columnas (`make_audit_glossary.py` falla si falta alguna).
- Fórmulas en l. 1100-1117 y 1144-1240:
  - `cc = ρ dt (su_cc − gadv − store_gas)`, `eart = −ρ dt store_art`, `ecc = eos + cc − rx`;
  - `elf` usa la misma expresión que `el`;
  - `rem2` solo se acumula con `cc_ok` y `liq_ok`, y `liq_ok` excluye `slag_condensed_on`. `liq%rho` vale `rho_steel` fuera de la vista condensada. No aparece ningún NaN ni Inf en las columnas nuevas de `tests/out/**`.
- La clase libre exige `α_s < 1e-2` al inicio y al final del paso. `ws_bed = (α_s ≥ ALPHA_BED = 1e-2)` (`src/mod_multiphase.f90:114`). Por tanto fsat ≡ 1 en gas libre, como afirma C-188.
- Derivación de la cancelación de `su_cc` en rem2: la fila da `vol_out = dcl + E2 − store·pp`, y la masa del gas que sale es `ρ_P(vol_out) − ρ_P·gadv`. Lo único que sobrevive es `(ρ_final − ρ_iter)·su_cc`. Restar `gadv` completo es correcto aunque fsat < 1.

**Citas del reporte**
- Comprobadas: `mod_pressure_3d.f90:625-632`, `:1019-1028`, `:1061`, `:866-871`, `:898`; `mod_audit.f90:981`, `:1102-1103`, `:1106`; `mod_solver_3d.f90:245` y `:271-279`; `mod_config_3d.f90:94`.
- El hueco de «cero [CG] AVISO»: el primer caso no convergido siempre se imprime (`mod(n,1000) == 1`), así que cero avisos significa cero agotamientos de `max_iter`, salvo la salida silenciosa con `|pq| < SMALL`, que el reporte ya declara.

**Checkers**
- `mass_gas_flux_closure` pasa por la razón correcta: en `k8_cg1000` el resto es 9.1e-19 kg frente a una escala de 2.1e-4, y en `tests/out` hay bancos con flujos de 1e-3 kg y restos de 1e-18.
- `mass_gas_class_split` es tautológico en `flux` y `rx`, y el reporte lo dice.

**Cifras recalculadas desde `campaigns/b1/*/audit.csv`**
- Tabla principal, `k8_cg1000`: 9.198e-5; 0.863; 1.6316e-2; 0.197; −8.550e-4 / +4.249e-4; −2.1694e-5 ± 1.31e-6 (59/59); 0.3156; err_art 2.96e-6; D1 −2.1053e-5.
- Mismas magnitudes para `k8_mo20` (0 avisos `[CG] AVISO`… en el banco convergido; 2 en `k8_mo20`) y `k8_base`.
- Barrido `k8s_mo{5,10,20,21,40,41,80}` (D1, medias, sd, 59/59 no convergidos y 57/59 con 41 externas): coincide con el reporte.
- C-169 a C-192 están en `research/ledger.jsonl`.

## 3. Orden sugerido de corrección
1. B1, que no bloquea y puede ir en otra pieza: sacar la acumulación de masa de `m_gas_out` del bloque `gas_energy_on`, o saltar el check sin `solve_energy`. Validarlo con un banco de flujo frío, cuando no haya otra corrida en curso.
