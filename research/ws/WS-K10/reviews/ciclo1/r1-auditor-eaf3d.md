# WS-K10, ronda 1: revisión del código staged (auditor-eaf3d)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Quedan cuatro BAJO, ninguno bloqueante.

El diff solo añade diagnóstico. No cambia la numérica: en los 61 bancos de la suite y en los 3 de campaña, las columnas comunes del audit son idénticas antes y después, y el golden v132 pasa. La descomposición cierra a redondeo en todos los bancos donde se evalúa.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B1. Algunos PASS de `mass_gas_eos_end` son vacíos** (`tests/integration/check_audit.py:528`)
- **Defecto:** cuando la EOS final no cambia la densidad, el check compara 0 con 0 y da PASS. Pasa en 8 de los 41 PASS de `test_full.txt`:
  - `bath_test_n1/n4/n12` y `bath_test_stretch_n4`;
  - `bed_bath_rest_n1/n4`;
  - `cold_flow_noenergy_n4` y `pocket_rise_n4`.
- **Efecto:** el reparto Br1/Br2 se valida de verdad en 33 bancos, no en 41.
- **Arreglo:** dar INFO n/a cuando la escala `eos_s` valga 0.

**B2. Falso FAIL con un audit.csv sin columnas de escala** (`check_audit.py:522-523`)
- **Escenario:** el binario intermedio `eaf3d_k10_opt` escribió las columnas de cierre pero no las de escala. El checker lee la escala ausente como 0.
- **Comprobado:** `python3 tests/integration/check_audit.py campaigns/b1/k10_mo20` da FAIL `mass_gas_decomp` con un resto de 2.91e-14 frente a una escala 0. El comando de evidencia de C-204 sobre `k10_*` ya no se reproduce.
- **Alcance:** el reporte usa `k10b_*`, donde el check pasa, así que la conclusión no cambia.
- **Arreglo:** dar INFO n/a si falta la columna de escala.

**B3. Coste y memoria con el audit apagado** (`src/mod_pressure_3d.f90:221-222`, `891-904`; `src/mod_workspace.f90:547-549`)
- **Defecto:** aunque el audit esté apagado, cada Poisson pone a cero 5 arrays completos y escribe `ws_Fgv_*`, y se reservan 6 arrays 3D.
- **Con el audit encendido:** se añaden 3 intercambios de halos, una copia y el lazo del residuo por Poisson y por externa.
- **Sin medir:** los TIMERS no aíslan el sobrecoste. También suben bloques que el diff no toca (radiación DO, ×2 en dt05), así que la diferencia es ruido de la máquina.
- **Arreglo:** meter el reset y `ws_Fgv` dentro de la guarda `audit_freq > 0`, o medir el sobrecoste con el audit encendido y apagado.

**B4. «Por paso» significa «por fila»** (`check_audit.py:531`, `piezas.py`)
- **Defecto:** con `audit_freq > 1` una fila agrega varios pasos, y la media rotulada «por paso» sale inflada.
- **Alcance:** en los bancos de K10 `audit_freq = 1` (verificado), así que los números del reporte son correctos.

## 2. Verificado como correcto (no re-auditar)

**Procedencia**
- El sha256 del diff staged de `src/` coincide con el binario `eaf3d_k10b_opt` (`opt_identidad.txt`).
- `tests/out` es posterior a la última edición de `src/`.
- La base del scratchpad coincide con el manifiesto. Las 61 audit.csv son idénticas en sus 137 columnas comunes.
- En test-full el golden `metrics_v132` compara con rtol 1e-12 y no da diferencias.

**Bancos de campaña**
- Las columnas comunes de `k8s_*`/`k8_base` frente a `k10_*` son idénticas.
- `k10_*` frente a `k10b_*`: solo cambia `m_gas_rv_scale`, por el cambio de definición.
- Los tres checks pasan en los tres `k10b_*`.
- `[CG] AVISO`: 0, 0 y 1, como dice el reporte.

**Números del reporte**
- `piezas.py`, con y sin `--sin-paso1`, reproduce la tabla, el veredicto SIN DECIDIR y Br + Bgr = −1.70e-7.
- El paso 280001 de `k10_dt05` pone el 66 % de la suma de e.

**Identidad de la fila**
- El residuo r = Su − A pp usa la misma matriz (después de las BC) y el mismo orden que `matvec`; `pp` trae los halos del CG.
- Las filas triviales, selladas y de salida dan r = 0 exacto: `pp` se queda en 0 y el residuo inicial es 0.

**Gas**
- `ws_Fg = gmass(ws_Fgv)`: el dador de `gface` coincide con el de `gmass`.
- Las caras sin enlace valen 0: se reinician en cada Poisson y se intercambian por halo.
- La costura periódica en θ y la frontera de bloque son coherentes.

**Densidad**
- Solo `update_properties` (y la inicialización) escribe `gas%rho`.
- Por tanto Br1 es solo la EOS de la misma externa, y Br2 es solo la EOS final. Esta última está validada por `eos_end` en los bancos no triviales.

**MPI, reinicio y memoria**
- Los intercambios nuevos tienen una guarda global, así que no hay deadlock.
- No hay estado nuevo que deba entrar al snapshot: todo se valida con `*_id == paso`.
- No hay Bug 22: las copias completas salen de arrays inicializados también en los halos.
- No hay dummies de array nuevos.

**CSV y predicados**
- La cabecera y el orden de escritura de las 24 columnas coinciden: 161 campos, dentro del límite de 200 del formato.
- El predicado `pc_fs_*` coincide con `fs_on`.
- `err_liq_all` y `ELF_FREE` usan el mismo `el` que el cierre por celda.

**Checkers**
- `mass_gas_row_volume` y `mass_gas_decomp` detectan errores reales: el residuo y los caudales se calculan por caminos independientes, y `fl` usa la masa de `ws_Fg` frente a la ρ del dador de `ws_rho_g_used`.
- La tolerancia es de unos 9e-11 kg sobre 59 pasos, frente a piezas de 1e-5 kg por paso.

## 3. Orden sugerido de corrección (uno por uno, ninguno bloquea el cierre)
1. B2: n/a si falta la columna de escala.
2. B1: n/a si la escala de `eos_end` es 0; citar 33 no triviales.
3. B4: rotular «por fila» o dividir por pasos.
4. B3: guardar el reset y `ws_Fgv` bajo `audit_freq > 0`, o medir el sobrecoste.
