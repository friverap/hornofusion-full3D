# WS-K7, panel de cierre, ronda 1: auditor-eaf3d (revisión del código del diff staged)

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO en el código. Quedan tres hallazgos BAJO, ninguno bloqueante.

Alcance: `git diff --cached` de `src/` (mod_audit, mod_continuity, mod_pressure_3d, mod_properties_3d, mod_workspace), del Makefile, de `tests/integration/check_audit.py`, del glosario (`scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md`) y de la regla. Todo lo hice en solo lectura: grep, git show y python sobre `tests/out/**/audit.csv` y `campaigns/b1/k7v5_*`. No compilé ni ejecuté nada.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO
- **B1. Orden de `SRCS` (Makefile:23 frente a :29).** `mod_audit.f90` va antes que `mod_probe.f90` aunque ahora lo usa, lo que incumple la convención de CLAUDE.md. Compila gracias a la regla explícita de Makefile:101, y ningún script compila siguiendo `SRCS`. No hay escenario de fallo hoy. Está declarado en el reporte (:388) para un commit aparte.
- **B2. `m_gas_e2_skip` vale 0 por construcción** (`src/mod_audit.f90:1019-1023`), igual que el AVISO de `check_audit`. La rama por celda exige `ws_Fg_valid`, que se anula en `main_3d.f90:577` y se fija en `mod_pressure_3d.f90:851`. Antes de eso, en la misma llamada, el Poisson ya puso `ws_pc_unl_used_valid = .true.` con id = paso (:753-754), y no hay `return` entre :213 y :851. Por eso esa columna en 0 no verifica nada de forma independiente.
  - Arreglo: declararlo así en el glosario y en el comentario, o retirar la columna más adelante.
- **B3. Citas desfasadas en el reporte.**
  - `check_audit.py:373-374` (report :100, :395, :399): en el staged la rama n/a está en :385-389.
  - `:434-456` (report :362): en el staged el bloque está en :448-473.
  - El encabezado de :362 sigue diciendo «1e-9 Σ|.|» como vigente; la tolerancia actual es 1e-11.

## 2. Verificado como correcto (no re-auditar)

1. **Identidad `mass_gas_rewrites`: cobertura completa de las reescrituras.**
   - Toda escritura de `gas%alpha` y `gas%rho` en `src/` lleva gancho o está fuera de la ventana:
     - complemento: `mod_continuity.f90:812, 1240, 1691`;
     - EOS: `mod_properties_3d.f90:45`;
     - volfix: `ecs_feed:281`, `fields:778`, `slag_3d:660/868`, `slag_chemistry:353`, `solid_phase:119`;
     - solo de inicialización: `fields_initialize_all`, `init_heel`, `slag_initialize`, `fields:429`;
     - celdas `cell_type 0`, que el modo 1 no suma.
   - La ventana va del modo 0 (`main_3d.f90:337`) al modo 1 (`:795`) y contiene todas las llamadas a `update_properties` (646/658/790). No hay ningún `exit` entre ambos modos.
   - La descomposición es exacta: el complemento cambia α con ρ fija y la EOS cambia ρ con α fija.
   - Barrido de `check_audit` sobre los 78 `audit.csv` de `tests/out`: **78/78 PASS**, resto máximo 3.97e-12 kg (arc_slag_n1). El peor cociente frente a la tolerancia es 0.44 (bed_bath_rest_n1).
2. **Halos y MPI.**
   - Los ganchos solo escriben celdas propias.
   - `mg_comp/eos/_abs` se anulan enteros en el modo 0; `mg_ag0` solo se lee en celdas propias.
   - `ws_pc_unl_used` se asigna con `mold` y se inicializa a 0. No hay copias de arrays `mold` escritos solo en celdas propias (Bug 22), ni dummies nuevos de tipo array.
   - Las caras i-1 se leen de halos intercambiados:
     - `ws_Fc` y `ws_Fc_lk`: `pressure:817-823`;
     - `ws_Fg` y su lk: `:846-851`;
     - `ws_Fr/Fth`: `continuity:549-550`;
     - `ws_Fz`: `:743`, después del derrame.
   - Las caras de frontera física quedan en 0.
   - Invariancia a la descomposición de las 24 columnas nuevas en 10 pares (n1 frente a n4/n8/n9/n12): rel ≤ 2e-6 y recuentos idénticos. La única excepción es `rej_nogas`, con 1.4e-4 sobre 1e-13 kg, que es ruido.
3. **Reinicio.** No hay estado persistente nuevo (todo es válido dentro del paso por id). El `audit-restart` compara 117 columnas y la diferencia es 0.
4. **Numérica idéntica bit a bit.**
   - Golden v131: err rel 0 en todos los bancos.
   - El sha256 del diff staged de `src/` (0503d1f6…) coincide con `logs/opt_identidad.txt`, y el binario es idéntico a `eaf3d_k7v5_opt`.
   - No hay cambios sin stage.
   - Los logs (20:15-20:29) son posteriores al último cambio de `check_audit.py` (20:12).
5. **Semántica de la E2 aceptada.**
   - Se anula en :213 y se fija en :653 solo donde `Su += E2`.
   - Se pone a 0 en celdas inactivas o selladas (:672) y donde `Su == 0` tras las BC. `apply_pressure_bc` solo pone `Su = 0` en celdas de salida y en `cell_type 0` (`mod_boundary_3d.f90:203-232`).
   - Entre :751 y el CG nada modifica `Su`.
   - Salvedad: el comentario «en ningún caso» de :745-747 solo falla con cancelación exacta, un caso de medida nula.
6. **Orden y reparto lk/unl.**
   - En cada iteración externa va primero el Poisson y luego el transporte (`multiphase:478` y luego `507/510`).
   - `unl_vol` usa los mismos `Fw..Ft` que `ws_Fr`, y ρ_l es constante (`cfg%rho_steel`), así que lo no enlazado se cancela.
   - Con `pc_spill_source`, el derrame entra en `unl_vol` y en `ws_Fz` con la misma magnitud.
7. **CSV.** El encabezado tiene 117 columnas, igual que las filas. El orden del encabezado coincide con el de `write`. El formato admite 200 grupos, de sobra para 114. La reducción recorre `N_AUD`.
8. **Ramas de `check_audit`.** Reproduje: 30 bancos con líquido, 12 con «0.000» y 24 con «n/a» (22 por escoria condensada y 2 por escoria legada). La columna `m_slag` existe, no hay tracebacks y el checker es de solo lectura. No se aflojó ningún check existente.
9. **Glosario.** Las 24 columnas nuevas tienen entrada en `DEFS`, y las filas del `.md` coinciden con la transformación del generador. El `.tex` está en `.gitignore`.
10. **Cifras de {C-145}**, recalculadas desde `campaigns/b1/k7v5_{mo20,base}/audit.csv` (step > 280000):

    | Banco | rem_all/abs | Neto |
    |---|---|---|
    | k7v5_mo20 | 0.319 | 1.571 |
    | k7v5_base | 0.404 | 1.320 |

    En k7v5_mo20: lk +4.977e-4, unl −9.58e-6, err_liq −2.966e-3, nolink 0, liq_skip 0. La config tiene `solve_slag = false`, así que `liq_ok` es válido.
11. **Dependencias de módulos.** `mod_audit` → `mod_probe` y `mod_properties_3d` → `mod_audit` no forman ciclos, y las reglas `.o` están actualizadas.

Fuera del alcance de esta revisión de código: las lecturas físicas de B1 más allá de {C-145}. Las cubre revisor-evidencia.

## 3. Orden sugerido de corrección (uno por uno, ninguno bloquea el cierre)
1. B3: corregir las citas del reporte (redactor).
2. B2: declarar o retirar `m_gas_e2_skip` (coordinador, commit posterior).
3. B1: orden de `SRCS` en un commit aparte, solo del Makefile, con test-quick.
