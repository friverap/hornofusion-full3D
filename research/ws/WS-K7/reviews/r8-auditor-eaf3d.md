# WS-K7, panel de cierre, ronda 1: revisión del código (auditor-eaf3d)

**Veredicto: RECHAZA**, por un hallazgo MEDIO pendiente (M1). Es un defecto de documentación del glosario y de la regla, no de numérica. El arreglo es corto.

Revisión ciega: no leí `research/ws/WS-K7/reviews/`. Fue solo lectura. Lo único que ejecuté fue `check_audit.py` y `ledger.py show` sobre archivos ya existentes, sin escribir nada.

## 1. Hallazgos

### MEDIO

**M1. El glosario y la regla confunden `m_gas_err_liq` (con filtro) con `m_gas_err_liq_all` (sin filtro).**

- **Dónde:**
  - `scripts/make_audit_glossary.py:198-203`, que se propaga a `docs/AUDIT_COLUMNS.md:102` y a `paper/tables/audit_glossary.tex`. Dice: «m_gas_err_liq … Reduced form: m_gas_err_liq_lk + m_gas_err_liq_unl».
  - `.claude/rules/transporte-energia.md:160-166`. Dice: «se mide como `m_gas_err_liq` = ρ_g (V_pois,in − V_eff,in) en celdas multifase … err_liq = `m_gas_err_liq_lk` + `m_gas_err_liq_unl`».
- **Qué hace el código:** en `src/mod_audit.f90:1088-1092`, `el_lk` y `el_unl` se acumulan en TODAS las multifase con `liq_ok`, el mismo conjunto que `m_gas_err_liq_all`. `m_gas_err_liq` solo suma dentro de `if (has_gas)` (`:1093-1094`).
- **Fallo concreto:** con el checker actual sobre `campaigns/b1/k7v5_mo20`, m_gas_err_liq = −2.966e-3 kg, mientras que lk + unl = 4.977e-4 − 9.58e-6 = **+4.881e-4** kg, que es err_liq_all. Tiene signo contrario y es 6 veces menor.
- **Por qué importa:** la diferencia entre los dos conjuntos es lo que separa el 0.566 (C-127) del 0.319 (C-145). El reporte la distingue bien (:163, :282), pero la regla, que se carga en sesiones futuras, y la tabla del paper la pierden.
- **Arreglo:**
  - Glosario: «m_gas_err_liq_all = lk + unl; m_gas_err_liq = restricción a α_g > 0 al inicio o al final».
  - Regla: nombrar `m_gas_err_liq_all` para todas las multifase y dejar `m_gas_err_liq` para el conjunto con gas.
  - Regenerar `docs/AUDIT_COLUMNS.md` y el .tex. El ejecutable no cambia.

### BAJO

- **B1. El checker imprime ceros falsos con CSV viejos.**
  - Dónde: `tests/integration/check_audit.py:391-393,424`. S() devuelve 0.0 para las columnas ausentes.
  - Caso: sobre `campaigns/b1/k7_mo20`, la fuente que el reporte cita con este comando, imprime «C-121 sin filtro … = 0.000 de sum|e|», «corr(e − err_liq_all, e) +1.000», «sum|comp| por llamada 0.000e+00» y «0 celdas-paso sin cara enlazada». Nada de eso se midió en ese CSV.
  - Arreglo: condicionar cada bloque a `col in last` e imprimir «no medido» si falta.
- **B2. La regla dice F_g = 0 sin matizar.**
  - Dónde: `.claude/rules/transporte-energia.md:211-212`: «0 < α_g < ALPHA_FLOW_CUTOFF … con F_g = 0».
  - Contradice lo que el propio WS mide: con la celda en `act_g` por alcance, F_g ≠ 0 por la α de cara media (`src/mod_pressure_3d.f90:1237`, `Fg_r` en :1260). El reporte (:297) limita F_g = 0 al caso «sin alcance».
  - Arreglo: decir que F_g = 0 solo sin alcance.
- **B3. La regla describe mal cuándo sale «n/a».**
  - Dónde: `.claude/rules/transporte-energia.md:209-210` dice «n/a SOLO sin filas con err_liq evaluado».
  - El código (`check_audit.py:373`) también da n/a cuando Σ|e| multifase = 0.
- **B4. Citas de línea del reporte que no corresponden al staged.**
  - Las de `mod_pressure_3d` (:1186/:1220/:1243/…, :649, :663-667, :209, :813-835) son de HEAD. En el staged hay que sumar 17, salvo las anteriores a :212. En el mismo párrafo, `link` :1747-1751 sí es del staged.
  - Las de `mod_audit` :872-888, :967-968 y :998 no coinciden con HEAD ni con el staged. En el staged son :899-915, :993-996 y :1036.
- **B5. Orden de `SRCS` en el Makefile.**
  - mod_audit (línea 23) va antes que mod_probe (línea 29), aunque ahora lo usa.
  - No hay fallo: la regla explícita en `Makefile:101` fija el orden y ningún otro script compila según `SRCS`. El reporte ya lo declara para un commit aparte.

## 2. Verificado como correcto (no re-auditar)

- **Completitud de la identidad `mass_gas_rewrites`.** Toda reescritura de `gas%alpha` o `gas%rho` dentro de la ventana modo 0 → modo 1 cae en una de tres rutas:
  - Ganchos del complemento en los 3 sitios: `mod_continuity.f90:808/1237/1687`.
  - Gancho de EOS: `update_properties` es la única EOS en tiempo de corrida (`mod_fields_3d:429` solo actúa en el arranque).
  - Volfix registrado por celda: `mod_solid_phase:119`, `mod_slag_3d:660/868`, `mod_slag_chemistry:353`, `mod_ecs_feed:281`, `mod_fields_3d:778`.
  - Las rutas que solo actúan en el arranque (`mod_fields_3d:399/403/510`, `mod_slag_3d:134-171`, `restart_read`) van antes de `audit_init` (`main_3d.f90:267` → :297).
  - `cell_type` es estático, y las celdas con `cell_type` 0 quedan fuera tanto del inventario como de las sumas.
- **Exactitud de los ganchos.** comp = ρVΔα y eos = αVΔρ cambian un solo factor cada vez, así que la suma por llamada es exacta y el neto por paso cuadra. El transporte siempre parte de `alpha_old` (`mod_continuity.f90:322`). Las columnas abs son por llamada a propósito.
- **Orden dentro del paso:** modo 0 (`main:337`) → premelt, sort y SIMPLE → `update_properties` final (:790) → modo 1 (:795) → `audit_write_step`. Nada toca el gas entre el modo 1 y la escritura de la fila.
- **`ws_pc_unl_used`:**
  - Se anula en cada Poisson (`mod_pressure_3d.f90:213`) y solo se escribe donde se sumó la E2 (:652).
  - Se pone a 0 en celdas inactivas o selladas (:672) y donde Su = 0 tras las BC: las salidas, porque `apply_pressure_bc` fija Su = 0.
  - El Poisson no tiene `return` temprano ni escribe Su después de :754.
  - Su único lector es mod_audit. Como lleva id de paso, no es estado de reinicio.
- **Halos y caras:**
  - ws_Fc, ws_Fc_lk y ws_Fg se intercambian tras escribirse (:817-823, :843-849).
  - ws_Fr, ws_Fth y ws_Fz se intercambian en `mod_continuity.f90:549-551`, y ws_Fz otra vez después del derrame (:743).
  - Las caras de frontera física se anulan al inicio.
  - El audit solo lee celdas propias. `mg_ag0` (allocate con `mold=`) se escribe y se lee solo en celdas propias, así que no hay Bug 22.
  - No hay dummies de array nuevos.
- **MPI:**
  - LIQ_SKIP y E2_SKIP solo los suma el rank 0.
  - `acc` se reduce de 1 a N_AUD (`mod_audit.f90:640-641`).
  - `ws_*_valid` se invalida por paso (`main:576-578`), y el fallback implícito se decide con `cfl_glob` global.
- **Derrame:** siempre entra en ws_Fz, y en `unl_vol` solo con `pc_spill_source`. La entrada del glosario sobre `_lk` es correcta.
- **CSV:** encabezado y datos tienen 117 campos en k7v5_mo20. `200(...)` alcanza.
- **Makefile:** las dependencias explícitas nuevas (audit → probe y properties → audit) no forman ciclo.
- **Checker:**
  - `mass_gas_rewrites` está bajo `flow_on`, y dm_g = last − first es coherente con `steps`.
  - 67 PASS. El peor cociente resto/tolerancia es 0.44 (5.9e-13 frente a 1.34e-12), así que el check no pasa por holgura.
  - Las ramas n/a / 0.000 / principal corresponden al código.
- **Cifras del reporte que reproduje:** reejecuté el checker sobre k7v5_mo20 y salen 0.319, neto 1.571, desfase 0.13 %, rej 1.589·Σ|e|_nogas y resto −6.15e-14, como en el reporte.
- **Tests e identidad del binario:** `test_unit`, `test_quick` y `test_full` se corrieron después de la última edición de código (19:04 → 19:07-19:21). No hay cambios fuera del staged. `opt_identidad.txt` registra la identidad byte a byte del binario.

## 3. Orden sugerido de corrección (uno por uno)

1. M1: glosario y regla, regenerar los docs, y comprobar en k7v5_mo20 que S(lk) + S(unl) = S(err_liq_all) ≠ S(err_liq).
2. B1: guardas en `check_audit.py` y reejecutar sobre k7_mo20.
3. B2 y B3: redacción de la regla.
4. B4: citas de línea del reporte.
5. B5: orden de `SRCS`, en el commit aparte que ya está declarado.
