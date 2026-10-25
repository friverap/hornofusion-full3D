# WS-K6 — Volfix por celda en el balance de masa del gas

Pendiente 1 de WS-K5. El usuario aprobó el plan el 24-oct-2026
(`/Users/frariv/.claude/plans/iterative-foraging-newell.md`). Es un cambio
solo de diagnóstico.

## Proceso

1. En WS-K5 (commit 50d1d97), el balance por celda e = Δ(αρV) − dt Σ ws_Fg − rxn incluía el volfix de cada celda: el gas que desplazan la carga, el ECS, la fusión y la escoria. Por eso `m_gas_err_multi` no aislaba la masa reescrita: en cold_bucket2_slag daba −1.739 kg, de los que −1.722 eran volfix (C-116; ronda 2 del panel de WS-K5).
2. Las 6 rutas que suman `AUD_GAS_VOLFIX` calculan su dmg por celda con índices locales:
   - `charge_scrap` (mod_fields_3d);
   - `ecs_feed` (mod_ecs_feed);
   - `enforce_volume_constraint` (mod_solid_phase);
   - `slag_condensed_sort` y `slag_buoyancy` (mod_slag_3d);
   - `compute_slag_chemistry` (mod_slag_chemistry).

   Todas corren dentro del paso, entre `audit_gas_cells(0)` y `audit_gas_cells(1)`.
3. Cambio:
   - **`src/mod_audit.f90`:**
     - `audit_volfix_cell(i,j,k,dm)` acumula en `mg_vf`, que se anula en el modo 0. Antes de asignarse no hace nada, lo que cubre la carga de la cesta 1 y la flotación inicial.
     - `audit_gas_cells(1)` resta `mg_vf` de e.
     - Columna nueva `m_gas_vf_cells` (Σ `mg_vf`).
     - `mg_vf` no es estado entre pasos.
   - **Las 6 rutas:** una llamada a `audit_volfix_cell` con el mismo dm que ya sumaban. Ninguna cuenta física cambia.
   - **`tests/integration/check_audit.py`:**
     - el cierre pasa a ser EOS − (libre + multi + outlet) − venteo;
     - check nuevo `mass_gas_vf_cells` (PASS/FAIL): Σ por celda = m_gas_volfix con 1e-9 relativo. Una ruta futura de volfix sin `audit_volfix_cell` lo hace fallar;
     - se quita el AVISO de volfix de WS-K5.
   - **Documentación:** glosario, `docs/AUDIT_COLUMNS.md` y la regla de transporte y energía.
   - **No se agregó test unitario de `audit_volfix_cell`**, que solo suma en un array. Lo cubre el check de integración `mass_gas_vf_cells` en los 64 casos de test-full: falla si una ruta no registra su celda.

## Resultado

Predicción pre-registrada antes de compilar el binario de banco: {C-117}. Veredicto: **refutada en la letra por el inciso (5)**, con el resto cumplido {C-118}.

- **(1) Numérica idéntica.** En k6_mo20 y k6_base, p_max, m_gas, E_liq, E_gas y u_gas_max son iguales bit a bit a sonda_gc_* en 60 renglones {C-118}.
  > [fuente: campaigns/b1/k6_mo20, campaigns/b1/k6_base, campaigns/b1/sonda_gc_* | comparación csv]
  Comparé TODAS las columnas comunes de audit.csv (k6 frente a sonda_gc_*). Solo difiere `m_gas_volfix`, en el último bit: 15 de 60 renglones, con |Δ| ≤ 5.3e-23 kg. Es el acumulador diagnóstico de las rutas de volfix; probablemente la llamada nueva dentro del lazo cambia el orden de suma que elige el compilador con -O3. Los campos, los inventarios (m_gas, E_*) y p_max son idénticos bit a bit.
  > [fuente: campaigns/b1/k6_*/audit.csv frente a campaigns/b1/sonda_gc_*/audit.csv | comparación de todas las columnas comunes]
- **(2) Cierre.** EOS − celdas − venteo da −6.1e-14 y −7.1e-14 kg en k6, y queda dentro de tolerancia en los 64 cierres de test-full (49 corridas base y 15 reinicios) {C-118, corregido en C-119: C-118 decía «58 bancos»}. De los 76 bloques `[audit]` del log, 9 no tienen flujo (`solve_flow = false`) y 3 no tienen balance por celda: 2 de mezcla (bath_fill_mix_n4, bath_mix_n4) y 1 sin multifase (oneflow_test_n4).
  > [fuente: research/ws/WS-K6/logs/test_full.txt | grep -c '\[audit\]' = 76; grep -c 'solve_flow = false' = 9; grep mass_gas_cells | grep -c 'cierre EOS' = 64]
- **(3) Volfix completo.** `mass_gas_vf_cells` PASS en las 64 evaluaciones de test-full y en k6, con diferencia 0.0 {C-118}.
  > [fuente: research/ws/WS-K6/logs/test_full.txt | grep -c mass_gas_vf_cells = 64]
- **(4) Volfix fuera de la columna** {C-118}:
  - cold_bucket2_slag_n1: multifase −0.0173 kg con EOS 0.0177 (antes −1.739);
  - cold_bucket2_n4: multifase +0.0626 kg con EOS 0.756 (antes −10.40).
  > [fuente: «ahora»: research/ws/WS-K6/logs/test_full.txt | grep mass_gas_cells; «antes»: research/ws/WS-K5/logs/test_full.txt | grep mass_gas_cells (C-116)]
- **(5) B1** {C-118}:
  - k6_mo20 da multifase −8.554925e-4 kg; frente al valor exacto de k5 (−8.685537e-4) cambia 1.306e-5, que es el volfix de las celdas multifase (el total, 1.310e-5, incluye 4.1e-8 en celdas libres, que movieron la columna libre de 2.1794e-5 a 2.1835e-5);
  - el criterio citaba el valor redondeado −8.686e-4, contra el que la diferencia es 1.3108e-5, por encima del 1.31e-5 por 7.5e-9;
  - no se enmienda después de ver el dato;
  - la lectura de B1 no cambia: el volfix es el 1.5 % de la columna.
  > [fuente: campaigns/b1/k5_mo20/audit.csv y campaigns/b1/k6_mo20/audit.csv | suma de m_gas_err_multi, m_gas_err_free, m_gas_volfix y m_gas_vf_cells]
- **(6) Tests.** `make test-unit`, `make test-quick` y `make test-full` OK, con golden v131.
  > [fuente: research/ws/WS-K6/logs/test_unit.txt, test_quick.txt, test_full.txt]

## Incertidumbre

- **El mecanismo del piso multifase sigue siendo hipótesis** (C-110), igual que en WS-K5. Ahora la columna ya no mezcla volfix, así que la prueba que distinga el complemento de las caras no enlazadas puede usarla directamente.
- **Un cambio de α_g que no pase por `AUD_GAS_VOLFIX`** no se captura, pero tampoco entra a m_gas_volfix: sigue apareciendo como parte de e, igual que antes.
- **FAIL previos de check_audit en k6_base:** `energy_balance` (gap/permitido 2.24) y `regime_gas` (u_gas_max 215 m/s). Son idénticos en sonda_gc_base, así que son estado previo de B1 (fuga C-094), no cambian con WS-K6 y quedan fuera del criterio C-117. k6_mo20 no da FAIL.
- **La verificación en B1** es un solo banco de 59 pasos (280 s, 15 ranks).
