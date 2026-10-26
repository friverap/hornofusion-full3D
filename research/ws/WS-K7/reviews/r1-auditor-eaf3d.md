# Revision r1 (auditor-eaf3d) — WS-K7, diff staged

Alcance: `git diff --cached` de `src/mod_audit.f90`, `src/mod_continuity.f90`, `src/mod_properties_3d.f90`, `Makefile`, `tests/integration/check_audit.py`, `scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md`, `.claude/rules/transporte-energia.md`, contra `research/ws/WS-K7/report.md` y los eventos C-122..C-131 del ledger. Solo lectura; no lei `reviews/` de otros revisores. Cifras recomputadas con python3 sobre los `audit.csv` existentes.

## Veredicto: RECHAZA (un hallazgo MEDIO sin resolver)

## Hallazgos

### MEDIO

**M1 — El instrumento suma la fuente E2 (`ws_pc_unl`) donde el Poisson la descarta.**
`/Users/frariv/Horno/hornofusion-full3D/src/mod_audit.f90`, modo 1, `case default`:
```fortran
if (cfg%pc_drift_source .and. ws_pc_unl_valid) vp = vp + cfg%dt * ws_pc_unl(i,j,k)
```
se evalua en TODAS las celdas multifase. El Poisson, en cambio, solo la anade en celdas activas (`mod_pressure_3d.f90:647`: `if (.not. (act_l .or. act_g)) cycle`) y ademas pone `Su = 0` en inactivas y filas selladas (`:663-667`). En una celda inactiva todas las caras tienen `lk = 0` (`link` exige vecino activo, `:1733`), `ws_Fc = 0`, y `unl_vol` (`mod_continuity.f90:497-504`, las 6 caras no enlazadas) es la entrada neta TOTAL = `V_eff` salvo los terminos de derrame (`:673/678`). Resultado: `err_liq = rho_g (dt*ws_pc_unl - V_eff) ~ 0` por construccion.

- Escenario: celda de lecho con gas atrapado (F2.31 no ventea) o gas < 1e-2 sin alcance, con liquido que gotea por caras no enlazadas. El complemento destruye gas, `F_g = 0`, `e = comp + eos != 0`; el instrumento registra `err_liq ~ 0` («no explicado») cuando el Poisson no balanceo NADA ahi (V_pois = 0 segun la definicion documentada) y H predice `e ~ -rho_g V_eff`. Ademas infla `m_gas_vpois_abs` (la cota 3.9) con volumen que el Poisson nunca vio.
- El texto del glosario / `docs/AUDIT_COLUMNS.md` («the liquid volume the Poisson balanced (ws_Fc on linked faces + E2 source)») es falso en esas celdas.
- Efecto sobre el veredicto: NINGUNO en la letra (el inciso del neto falla 1.58/2.46 >> 0.3 con cualquier definicion; quitar E2 en inactivas solo puede bajar `rem`, lejos de 0.7). Pero el instrumento es permanente y no puede atribuir a H justo en la clase de celdas donde H actua. Magnitud no cuantificable desde `audit.csv`.
- Arreglo: (a) sumar `dt*ws_pc_unl` solo si la celda tiene alguna cara enlazada (`ws_Fc_lk_*` o `ws_Fg_lk_*` == 1 en una de las 6), que es exactamente la condicion «no sellada» del Poisson (`aW+...+aT > 0`), y re-medir en `k7v4_*` con bit a bit; o (b) sin tocar numeros: declarar el sesgo en glosario, `AUDIT_COLUMNS.md`, regla e Incertidumbre del reporte, evento en el ledger con `--ref C-131`, y columna futura `sum|e|` sobre multifase sin cara enlazada (coordinador).

### BAJO

**B1 — Tolerancia de `mass_gas_rewrites` escala con los netos, no con el churn.** `/Users/frariv/Horno/hornofusion-full3D/tests/integration/check_audit.py:380-386`: `1e-9 x (sum|m_gas_comp| + sum|m_gas_eos| + sum|volfix|)` usa los netos por paso (4.1e-5 y 5.5e-5 kg en 59 pasos) mientras el redondeo de los productos por celda escala con `m_gas_eos_abs` (0.43 kg, 200x). En los 67 bancos (<= ~200 pasos) el resto maximo es 4.0e-12 y lo sostiene el piso `1e-14 max|m_gas| + 1e-12`. PLAUSIBLE en campanas B1 largas (no reproducido). Arreglo: usar `m_gas_comp_abs + m_gas_eos_abs + |volfix|` (ya estan en el CSV).

**B2 — `rem_abs` incompleto cuando `liq_ok` es falso.** `src/mod_audit.f90` modo 1: la rama `else` (|e| de las nogas a `rem_abs` y `nogas`) esta dentro de `if (liq_ok)`; en un paso con fallback implicito `m_gas_err_rem_abs` no recorre «TODAS las multifase» como dice el glosario. Hoy solo lo delata el AVISO de `m_gas_liq_skip` (0 en k7). Arreglo: sacar esa acumulacion del `if (liq_ok)` o anotarlo en el glosario.

**B3 — Deriva de la regla.** El diff de `.claude/rules/transporte-energia.md` solo lleva C-123/C-124/C-126 (0.57) y dice que «la pieza siguiente debe definirlo por caras del gas enlazadas»; el reporte (Proceso 9, C-130/C-131) ya midio la definicion sin filtro (0.319), tiene cuatro columnas nuevas (`_all`, `_abs`) ausentes de la regla y declara que esa definicion NO se adopta. Incertidumbre «Documentacion (O1)» dice que la regla lleva los numeros de C-127, no de C-131. Arreglo: un parrafo.

## Verificado como correcto (no re-auditar)

- Ganchos del complemento en los 3 sitios (`mod_continuity.f90:808-813, 1236-1240, 1686-1691`) y de la EOS (`mod_properties_3d.f90:41-45`); `dm = factor no modificado x delta`: identidad discreta exacta.
- Todas las demas asignaciones a `gas%alpha`/`gas%rho` estan cubiertas: `cell_type == 0` (continuity 754/1670; excluidas del inventario, linea 549, y de las sumas), volfix con `audit_volfix_cell` (solid_phase 119/138, slag_chemistry 353/363, slag_3d 660/674 y 868/887, ecs_feed 281/266, fields 778/761 con bucket > 1), o solo en inicializacion antes de la fila 0 y de asignar `mg_*` (fields 399/403/429/510 `init_heel`; slag_3d 134-171 `slag_initialize`; main 246-252 fuera del lazo).
- Orden del paso: modo 0 en `main_3d.f90:337` antes de toda reescritura; `update_properties` final en `:790`, modo 1 en `:795`, `audit_write_step` en `:819`; nada reescribe entre ellos. Dentro de la externa el Poisson (`mod_multiphase.f90:478`) precede al transporte (`:510`).
- MPI: `ws_Fc_*`, `ws_Fc_lk_*`, `ws_Fr/Fth/Fz`, `ws_pc_unl` con intercambio de halos; `mg_comp`/`mg_eos` a cero enteros (sin Bug 22); `mg_ag0` solo se lee en celdas propias; `liq_ok` identico entre ranks (`n_sub` sale de `cfl_glob`; `ws_Fc_valid` se fija en el Poisson colectivo); `acc(1:N_AUD)` se reduce de forma generica.
- CSV: 106 nombres = 106 valores en el `write`; `200(...)` cubre. `check_audit`: `dm_g`, `m_fix`, `em` en ambito; `mass_gas_rewrites` no depende de `ws_Fg`.
- Numerica identica: 300/300 valores iguales (p_max, m_gas, E_liq, E_gas, u_gas_max, 60 filas) entre `k7v3_*`/`k7_*`/`k7_*_v2` y `sonda_gc_*`.
- Cifras del reporte recomputadas (59 filas step > 280000): k7_mo20 0.566 / 2.456 / nogas 4.816e-3 / vp 8.80e-3 / ve 2.28e-3 / skip 0 / resto -6.15e-14; k7_base 0.626 / 0.856 / -7.08e-14; k7v3_mo20 0.319 / 1.582 / comp_abs 2.271e-3 / eos_abs 0.4324; k7v3_base 0.404 / 1.319; `m_slag = 0`. `k7_mo20` y `k7_mo20_v2` son identicos (el reporte cita uno y C-129 el otro: mismas cifras).
- Logs: 67 PASS `mass_gas_rewrites` (resto max 3.97e-12) en test_full, 5 en test_quick; los XFAIL vistos son los conocidos (no contrastados con `tests/xfail.list`).
- Makefile: dependencia `mod_properties_3d.o -> mod_audit.o` correcta y sin ciclo. `ve` no divide por cero (`liq%rho = rho_steel` en toda celda `cell_type /= 0`). `ws_Fr` es promedio temporal de sub-pasos. `paper/tables/audit_glossary.tex` esta fuera del repo por diseno.

## Orden sugerido de correccion (uno por uno)

1. M1: filtro por cara enlazada en `vp` (o declaracion del sesgo + ledger si no se re-mide).
2. B2: acumulacion de |e| nogas fuera de `if (liq_ok)`.
3. B3: parrafo de la regla con C-130/C-131.
4. B1: tolerancia con las columnas `_abs`.