# Revision r2 (auditor-eaf3d) — WS-K7, diff staged (ronda 5 del panel)

Alcance: `git diff --cached` de `src/mod_audit.f90`, `src/mod_continuity.f90`, `src/mod_properties_3d.f90`, `Makefile`, `tests/integration/check_audit.py`, `scripts/make_audit_glossary.py`, `docs/AUDIT_COLUMNS.md`, `.claude/rules/transporte-energia.md`, contra `research/ws/WS-K7/report.md` (arbol de trabajo, version ronda 5) y `research/ledger.jsonl` (C-122..C-141). Solo lectura; no lei `reviews/` de otros revisores. Cifras recomputadas con python3 sobre los `audit.csv` existentes. La ronda 5 fue «solo reporte y registro»: el codigo es el mismo que revise en mi ronda anterior, asi que mis objeciones B-1..B-3 se mantienen (ninguna resuelta por el reporte ni por los datos) y anado tres BAJO nuevos.

## Veredicto: APRUEBA (sin hallazgos ALTO ni MEDIO)

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B-1 (se mantiene) — V_pois suma la E2 del transporte posterior al ultimo Poisson.** `/Users/frariv/Horno/hornofusion-full3D/src/mod_audit.f90`, modo 1:
```fortran
if (cfg%pc_drift_source .and. ws_pc_unl_valid .and. lk_any) vp = vp + cfg%dt * ws_pc_unl(i,j,k)
```
El Poisson solo acepta E2 si `ws_pc_unl_id == probe_current_step()` (`src/mod_pressure_3d.f90:642-643`); el id lo fija el transporte (`src/mod_continuity.f90:867`), asi que en la externa 1 nunca la acepta y el ultimo Poisson vio la E2 de la externa k-1, no la k que suma el instrumento. Escenario: `max_outer = 1` -> ningun Poisson acepto E2 y `m_gas_err_liq` la suma en toda multifase con cara enlazada; `m_gas_e2_nolink = 0` no lo delata; el glosario («only where the Poisson accepted it») es falso en el tiempo. Arreglo: snapshot `ws_pc_unl_seen` copiado en el Poisson al aceptar, o anotar que la columna exige max_outer >= 2. No bloqueante (k7v4 corre con 5/20 externas).

**B-2 (se mantiene) — `mass_gas_rewrites` no se evalua sin flujo.** `/Users/frariv/Horno/hornofusion-full3D/tests/integration/check_audit.py:311-313, :399`: el bloque vive dentro de `elif \"m_gas_out\" in last:` (solo `solve_flow = true`). Con `solve_flow = false` y `solve_energy = true` la EOS sigue reescribiendo rho_g (`src/main_3d.f90:658`) y la identidad vale con comp = 0, pero nadie la comprueba. Arreglo: sacar el bloque de la rama flow_on o PASS «no aplica» explicito.

**B-3 (se mantiene) — tolerancia 1e-9·Σ|dm| cuatro-seis ordenes mas holgada que lo medido.** `check_audit.py:415`. Recomputado: k7v4_long resto -3.23e-14 kg con Σ|dm| 78.35 kg (4e-16 relativo) frente a tolerancia 7.8e-8. Arreglo: factor 1e-12 y re-barrido (0 FAIL esperado).

**B-4 (nuevo) — la regla staged lleva tres frases que el reporte retira.** `/Users/frariv/Horno/hornofusion-full3D/.claude/rules/transporte-energia.md` (hunk +147): «H no explica el piso neto ...; el piso neto vive en e − err_liq» (retirado R1/R2), «F2.21» como causa del 29 % en nogas (el reporte lo corrige a la alpha de cara MEDIA del gas en el ensamblaje del Poisson, verificado en `src/mod_pressure_3d.f90:1186/1220/1243`) y «un desajuste del 2 % ... explicaria todo Σ|e|» (retirado R5). El reporte lo declara como pendiente del coordinador. No es codigo, pero la regla es la memoria que cargan los agentes al editar continuity/audit. Arreglo: reescribir las tres frases antes del commit de cierre.

**B-5 (nuevo, PLAUSIBLE) — `lk_any` no es la condicion «no sellada» del Poisson.** `sealed` exige aW+...+aT <= 0 (`mod_pressure_3d.f90:659-662`); el coeficiente de una cara enlazada es af·d_f·A/delta con af = 0.5(aef_P + aef_nb), `ag_eff = gas%alpha` sin piso (:244), y lk_g = 1 se fija dentro de `fl > 0` aunque af = 0. Dos celdas vecinas en alcance F2.21 con alpha_g = 0 en ambas y sin liquido continuo: cara enlazada con coeficiente 0, celda sellada (Su = 0, E2 descartada) e instrumento que si la suma; `m_gas_cells_nolink` no la cuenta. No pude confirmar la clase en k7v4 (`m_gas_ccdrop` mezcla tres fuentes: :567/626/672). Arreglo: exportar del Poisson la mascara exacta `(act_l .or. act_g) .and. .not. sealed` (:661-667) y usarla en el modo 1, o una columna que mida Σ|rho_g dt ws_pc_unl| en multifase selladas con lk_any.

**B-6 (nuevo, proceso) — el indice tiene la version ronda 4 del reporte y un ledger sin C-140/C-141.** `git status`: `report.md` AM, `ledger.jsonl` y `status.json` MM. Si el commit de cierre se hace del indice tal cual, se compromete el texto con la inferencia retirada y sin los eventos de retiro. Arreglo: `git add` de los tres antes del commit (o confirmar que el Workflow lo hace) y diff_sha coherente.

## Verificado como correcto (no re-auditar)

- Identidad dm_gas = comp + eos + volfix: ganchos en los 3 sitios del complemento (`mod_continuity.f90:807-812, 1236-1240, 1686-1691`) y la EOS (`mod_properties_3d.f90:41-45`); `mg_*` a cero enteros en el modo 0 (sin Bug 22); solo celdas propias.
- Ninguna otra escritura de `gas%alpha`/`gas%rho` sin gancho (incluidas dummies `ph` y `liq_old`): cell_type==0 excluidas del inventario y de las sumas; volfix con `audit_volfix_cell` (solid_phase 138, ecs_feed 266/281, slag_chemistry 363, slag_3d 674/887, fields 761); inicializacion fuera de `time_loop` (main_3d :267 < :311).
- Orden: modo 0 :337, EOS final :790, modo 1 :795, escritura :819; nada reescribe entre ellos. Comp/eos se suman antes de la omision por ws_Fg.
- MPI: `acc(1:N_AUD)` reducido generico (`mod_audit.f90:615-616`, N_AUD = 84); lk de liquido y gas anulados en cada Poisson (:204/:210) e intercambiados (:803-805, :829-831); banderas apagadas al inicio del paso (`main_3d.f90:576-578`); `liq_ok` identico entre ranks.
- CSV: 110 nombres = 110 valores (step+time+dt+19 s_glob+P_arc+3 mx_glob+84 a()); 109 pares caben en `200(...)`.
- `check_audit.py`: `dm_g`, `m_fix`, `em` en ambito; CSV viejos sin columnas nolink no rompen (r.get).
- Cifras recomputadas (59 filas step > 280000): k7v4_mo20 0.319 / 0.566 / neto 1.582 / 2.456 / nolink 0 / e2 0 / resto -6.15e-14 / corr 0.229, 0.972, 0/59 / comp_abs 3.125e-3 / eos_abs 0.841 / nogas 4.816e-3 / comp_abs_nogas 1.908e-6; k7v4_base 0.404 / 0.626 / 1.319 / 0.856 / -7.08e-14 / -0.429, 0.993; k7v4 = k7v3 en 13 columnas x 60 filas. k7v4_long: resto -3.23e-14, Σ|dm| 78.35, nolink 51845, err_abs_nolink 7.467e-3, e2_nolink 1.13e-14, 0.504 / 0.712, corr -0.234 / 0.999, 726/5499, medias por tramo -2.96e-5 -> -5.46e-5, fila 280059 difiere de k7v4_base (dt truncado). Todo coincide con el reporte.
- Afirmaciones de codigo del reporte: E2 solo en activas y Su = 0 en inactivas/selladas (:642-668); af media (:1186/:1220) y Fg = af·u_f·A tras `fl` (:1243); `link` (:1730-1734); alcance F2.21 (:231-233).
- Ledger staged C-122..C-139 coherente; binario `campaigns/bin/eaf3d_k7v4_opt` (10:51) anterior a los CSV (10:52, 11:42). Makefile sin ciclo. Sin estado nuevo persistente (nada que anadir al snapshot).

## Orden sugerido de correccion (uno por uno)

1. B-6: `git add` de reporte, ledger y status antes del commit de cierre.
2. B-4: tres frases de la regla.
3. B-1: snapshot `ws_pc_unl_seen` o nota max_outer >= 2 en glosario.
4. B-5: mascara exacta de aceptacion de E2 desde el Poisson.
5. B-2: bloque `mass_gas_rewrites` fuera de la rama flow_on.
6. B-3: factor 1e-12 y re-barrido.