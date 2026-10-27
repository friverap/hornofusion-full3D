# WS-K8: revisión del auditor eaf3d (ronda 1 del panel de cierre)

**Veredicto: RECHAZA.** El código del diff es correcto. Bloquea un hallazgo MEDIO de derivación que está en el reporte y en la regla staged.

## Hallazgos

### MEDIO (bloqueante)

**M1. Los candidatos de rem2 o del 0.863 del gas libre se cancelan por construcción.**
- **Dónde:** `research/ws/WS-K8/report.md:195-199`, `:368-372`, `:386-390` y `.claude/rules/transporte-energia.md:292` («candidato en el código: (1 − fsat)·gadv»).
- **Defecto:** se proponen (1 − fsat)·gadv, el acarreo y el tope `COMP_SRC_CAP` como términos que le faltan al plan en rem2.
  - Por álgebra: rem2 = comp − fl − el − cc − eart (`src/mod_audit.f90:1102-1106`). La fila del Poisson cumple: salida neta corregida (gas + líquido) = su_cc + E2 − store·pp. Por esa identidad, su_cc aparece igual en fl + ρ V_pois que en cc y se cancela. Lo que fsat, el acarreo o el tope hagan dentro de su_cc solo sobrevive multiplicado por (ρ_final − ρ_iterado)/ρ, que es de segundo orden. Esos tres términos son de err_cc frente a la EOS, como dice la propia Derivación (líneas 69-73).
  - En el gas libre fsat ≡ 1:
    - `fsat_cell` (`src/mod_pressure_3d.f90:1019-1028`) solo baja de 1 si `ws_bed > 0`.
    - Eso exige alpha_s ≥ `ALPHA_BED` = 1e-2 (`src/mod_multiphase.f90:114`).
    - La clase libre exige alpha_s < 1e-2 al inicio y al final del paso (`src/mod_audit.f90:981`, `:1084`).
- **Escenario de fallo:** la pieza siguiente («pre-registrada», línea 368) crearía columnas para partir el corchete 2 por términos que dan cero. La regla persistente orienta mal a quien edite el módulo.
- **Arreglo:**
  1. Mover esos tres términos al inciso de err_cc frente a la EOS.
  2. Nombrar como candidatos del corchete 2:
     - (i) (ρ_final − ρ_iterado)·dt·(su_cc + E2 + líquido neto − store);
     - (ii) `gadv` de ensamblaje (Q*) frente a Σ Q_in,corregido·(ρ_N − ρ_P), incluidas las caras que `gas_adv` excluye por la guardia `ALPHA_CUTOFF` (`src/mod_pressure_3d.f90:1061`) y las que cambian de sentido tras la corrección;
     - (iii) el residuo del CG, ya descartado.
  3. Registrar la corrección en el ledger con `--ref C-181`.

### BAJO (no bloqueantes)

- **B1. Dependencia oculta de `mass_gas_flux_closure`** (`tests/integration/check_audit.py:467-473`).
  - El check usa `m_gas_out`, que solo se acumula con `gas_energy_on` (`src/mod_audit.f90:806`, `:857`). El balance por celda solo exige `ws_Fg_valid`, flujo y multifase (`:1053`).
  - Escenario: con `solve_energy = false`, flujo y multifase activos, sale un FAIL espurio. Falla del lado seguro y ninguna prueba actual lo ejercita; `mass_gas` ya tenía la misma dependencia.
  - «m_gas_out sale de otro camino de código» exagera: son los mismos `ws_Fg` × lk. El check prueba el telescopado entre caras y halos y la partición de clases, no `ws_Fg`.
  - Arreglo: acumular `AUD_GAS_OUT` fuera de `gas_energy_on`, o condicionar el check a `solve_energy`, en una pieza aparte.
- **B2. Comentario inexacto en `src/mod_workspace.f90`** (declaración de `ws_store_gas` y `ws_store_art`).
  - Dice store = (aP − Σ a_nb)·pp. Tras el plegado de Dirichlet (`src/mod_boundary_3d.f90:241-246`), aP − Σ a_nb también incluye el flujo hacia la salida.
  - El código está bien (usa la suma Σa previa a las condiciones de contorno); solo hay que corregir el comentario.
- **B3. Redacción y referencias del reporte.**
  - «Siguiente, pre-registrado» (`:368`) y «pre-registrado» (`:378`) se leen como ya registrados, pero no hay evento en el ledger. Cambiar a «a pre-registrar».
  - La cita `mod_audit.f90:1100-1101` debe ser `:1102-1103`.

## Lo verificado como correcto (no re-auditar)

- **Identidad del diff de `src/` con los binarios de banco:**
  - El sha256 de `git diff --cached -- src/` es 78797d1c…, el mismo que registra `logs/opt_identidad.txt`.
  - HEAD 34be842 no toca `src/`.
  - `check_audit.py`, `src/` y el glosario son anteriores a la corrida de tests de las 14:27.
- **Arrays nuevos (`ws_su_cc_used`, `ws_gadv_used`, `ws_store_*`):**
  - Solo los lee `mod_audit`.
  - Se alocan con `mold=ws_aW` y se ponen a cero completos, halos incluidos, así que no hay Bug 22.
  - Se reinician en cada Poisson y la validez va por id del paso.
  - No guardan estado entre pasos, así que no necesitan snapshot de reinicio.
  - Solo hay un llamador de `solve_pressure_correction`, que es el único que pone `ws_Fg_valid`.
- **Ensamblaje:**
  - store_gas + parte acústica de store_art = término `ag_c` de aP.
  - La compliance se calcula antes de las condiciones de contorno y el acústico del líquido está incluido.
  - En las filas selladas, triviales, de salida o con Su == 0, su_cc y gadv quedan a 0.
  - `ws_Fg` se corrige con el pp completo (`:866-871`) y `sh%p` avanza alpha_p·pp (`:898`).
  - El CG puede salir en silencio (`mod_solver_3d.f90:245`) y el AVISO está en `:271-279`.
  - `alpha_g_comp_min` vale 0 por defecto (`mod_config_3d.f90:94`) y no aparece en el `config.dat` de k8.
- **audit.csv:**
  - Las 20 columnas nuevas coinciden en orden entre el encabezado y el `write`.
  - Todos los audit.csv tienen 137 columnas y el formato admite 200 repeticiones.
  - La reducción recorre `N_AUD` y los contadores solo los suma el rank 0.
  - `liq%rho` = `rho_steel` es mayor que 0 en todas las celdas, así que `elf` no divide entre cero.
- **Checks en los 78 `tests/out`:**
  - `mass_gas_rewrites`: 78 PASS, resto máximo 3.97e-12.
  - `mass_gas_class_split`: 66 PASS, restos máximos 8.49e-15 (multifase) y 3.73e-14 (gas libre, `arc_melt_slag_heel_n1`).
  - `mass_gas_flux_closure`: 66 PASS.
  - Los FAIL de `noflow_energy` y `oneflow_test` están en `xfail.list`.
- **Números del reporte:**
  - Reproduje la tabla principal (k8_cg1000, cg200, mo20, base): cocientes, netos, D, D1, C-110, err_art y número de AVISO.
  - Con `barrido_outer.py`, D1 y Dm de k8s_mo{5,10,20,40,80}. El criterio de C-182 se cumple por la letra: 0.013, 0.0033, 0.011 y 0.037.
  - Identidad k8s_mo20 = k8_cg1000, y k8_*_r2 = k8_* en 137 columnas.
  - Bit a bit, k8_mo20 frente a k7v5_mo20: de 117 columnas comunes, 110 son idénticas y solo 7 `m_gas_err_*` difieren, con máximo 1.08e-19.
  - `liq_skip`, `cc_skip` y `cells_skip` valen 0 en todos los bancos k8 y no hay escoria, así que no hay sesgo de filtro.
  - Cocientes por tramos de 200 pasos de `k7v5_mo20_1k`: +1.39 y −142.8 (citado como −143 en la regla).

Nota: para resumir los checks guardé un archivo temporal en el scratchpad de la sesión, fuera del repo.

## Orden de corrección

1. M1: texto del reporte y de la regla, más un evento en el ledger.
2. B3: «a pre-registrar» y la cita de línea.
3. B2: comentario de `mod_workspace.f90`. Si se hace en este diff, hay que reverificar el hash.
4. B1: dependencia de `m_gas_out` en el check, en una pieza aparte con su compuerta.