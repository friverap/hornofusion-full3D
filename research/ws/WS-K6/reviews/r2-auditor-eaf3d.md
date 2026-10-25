# WS-K6, ronda 2: revisión del auditor EAF3D

**Veredicto: aprueba.** No encontré hallazgos ALTO ni MEDIO en el código staged. Quedan dos observaciones BAJO que no bloquean; una de ellas es de redacción y sigue sin corregirse desde la ronda 1.

## 1. Hallazgos

### ALTO / MEDIO
Ninguno.

### BAJO

**K6-A1-B1 (redacción, sigue abierto)**
- Dónde: `research/ws/WS-K6/report.md`, inciso (3), y C-118.
- Problema: dicen "diferencia 0.0" para las 64 evaluaciones de test-full. El log (`research/ws/WS-K6/logs/test_full.txt`) muestra:
  - 53 evaluaciones con `dif 0.00e+00`;
  - 11 evaluaciones con diferencias de redondeo; la mayor es `3.33e-15` kg, en cold_bucket2_slag_n1.
- Además, 15 de las 64 evaluaciones tienen volfix 0 y pasan de forma trivial.
- Arreglo: cambiar la frase a "dif <= 3.3e-15 kg (53 de 64 exactamente 0; 15 con volfix nulo)".

**K6-A1-B2 (cobertura, se mantiene)**
- Dónde: `tests/integration/check_audit.py`. El check `mass_gas_vf_cells` solo corre cuando `nskip == 0`.
- Problema: en bancos de mezcla, una ruta futura de volfix sin `audit_volfix_cell` pasaría sin detectarse. No da un PASS engañoso, porque en esos casos las columnas ya se declaran incompletas.
- El cierre EOS - celdas - venteo sigue siendo INFO, sin umbral.
- Arreglo opcional: convertir el cierre en `chk.report` con la tolerancia del inciso (2) de C-117.

## 2. Verificado como correcto (no hace falta re-auditar)

**`audit_volfix_cell` y `mg_vf` (`src/mod_audit.f90`)**
- `mg_vf` se crea con `allocate(mg_vf, mold=gas%alpha)`, igual que `mg_ini`, así que conserva los límites `(-1:...)`.
- Se pone a cero ENTERA (halos incluidos) en cada `audit_gas_cells(0)`. No hay basura de `mold` en los halos (Bug 22).
- `mg_vf` no es estado entre pasos, así que no hace falta que entre al snapshot de reinicio.
- La suma `AUD_MG_VF_CELLS` usa el mismo bucle de celdas propias y el mismo `cell_type /= 0` que el balance por celda.

**Orden de llamadas en `src/main_3d.f90`**
- Las 6 rutas de volfix corren entre `audit_gas_cells(0)` (línea 337) y `audit_gas_cells(1)` (línea 795):
  - `charge_scrap` (bucket 2), línea 365;
  - `ecs_feed`, línea 383;
  - `compute_slag_chemistry`, línea 467;
  - `enforce_volume_constraint`, línea 484;
  - `slag_condensed_sort`, línea 598;
  - las llamadas internas de `mod_slag_3d`.
- La carga de la cesta 1 (línea 235) y la flotación inicial (línea 251) ocurren antes de que exista `mg_vf`, así que no hacen nada.
- Al reiniciar, la flotación inicial no se ejecuta.

**Mismo dm que `AUD_GAS_VOLFIX`**
- En cada ruta, `audit_volfix_cell` recibe el mismo dm que ya se sumaba a `AUD_GAS_VOLFIX`.
- La expresión se evalúa antes de actualizar `gas%alpha`, en el mismo orden que la suma original:
  - `mod_slag_3d`, líneas 657 y 864;
  - `mod_solid_phase`, línea 116;
  - `mod_slag_chemistry`, línea 350, con el mismo `ag_old = max(alpha, 0)`;
  - `mod_fields_3d`, línea 775;
  - `mod_ecs_feed`, línea 278.
- Todos los índices son locales.

**Columna nueva y check**
- La columna se agrega al final del CSV, con encabezado y escritura en el mismo orden. `N_AUD` pasa a 67.
- Check en test-full: 64 PASS, 0 FAIL, incluidos casos multi-rank con volfix grande:
  - cold_bucket2_n4: -10.46599 kg contra -10.46599 kg;
  - ecs_test_n12;
  - ecs_slag_n12.
- Con eso queda cubierto que ninguna ruta registre celdas de halo, ni que lo haga dos veces.

**Datos de B1, recalculados desde `campaigns/b1/*/audit.csv`**
- Multifase: k5_mo20 = -8.6855367e-4 kg, k6_mo20 = -8.5549254e-4 kg. La diferencia es 1.3061e-5.
- Libre: pasa de 2.17937e-5 a 2.18346e-5 kg (+4.09e-8).
- La suma de ambos cambios es 1.3102e-5, igual a `m_gas_volfix`, que a su vez es igual a `m_gas_vf_cells`. Esto coincide con el inciso (5) y con C-119.
- Inciso (1): p_max, m_gas, E_liq, E_gas y u_gas_max son idénticos bit a bit entre k6_{mo20,base} y sonda_gc_* en los 60 renglones (0 diferencias).

**Física**
- La física no cambia: el único efecto es restar `mg_vf` en el diagnóstico.
- Se quitó el aviso de WS-K5 y se corrigió la identidad de cierre (ahora EOS - celdas = venteo) en los comentarios, el glosario y check_audit.

## 3. Orden sugerido de corrección
1. K6-A1-B1: un cambio de una línea en el reporte y una nota en el ledger.
2. K6-A1-B2: opcional; convertir el cierre en PASS/FAIL en un workstream posterior.
