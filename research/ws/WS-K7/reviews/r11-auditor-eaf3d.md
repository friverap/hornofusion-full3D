## Revisión del auditor EAF3D, WS-K7, panel ronda 2

**Veredicto: RECHAZA.** Hay una objeción bloqueante (M1). Afecta a un documento del diff staged, no al código. El código en sí no tiene defectos nuevos.

### Hallazgos

**MEDIO**

- **M1. La regla conserva el contrafactual que esta ronda retiró.**
  - Dónde: `.claude/rules/transporte-energia.md:182-185`. La regla sigue diciendo «queda a ±0.02 del umbral según cuánto de la brecha sin gas sea CG truncado (0.279 si bajara al ≤ 0.028 de los bancos convergidos; C-162)».
  - Por qué es un defecto: C-163 (ronda 18, O1) RETIRA ese 0.279 como estimación. Según C-163, el inciso por celda es frágil frente al CG en ambas direcciones: en los bancos convergidos rem_all/abs va de 0.134 a 1.007, y 5 de 8 caen en la banda de refutación. El reporte (l.231-233) y C-163 lo reconocen, pero lo dejan «al coordinador».
  - Escenario de fallo: la regla se carga sola al tocar transporte y energía. Una sesión futura la lee, toma H como «a ±0.02 de soportada» y planifica la corrida con `max_inner_pres` 200 dando por sentado que está cerca del umbral. El registro vigente dice que puede caer en refutación.
  - Matiz menor en :211-213: «su población es otra» hereda el «por definición» de C-165 (las celdas de la válvula de Plan E tienen α_g = 0.015 > 0 y nunca son nogas).
  - Arreglo: editar la regla antes del commit y comprobar con `grep -n "0.279\|±0.02" .claude/rules/` que ya no queda nada. El binario no cambia.

**BAJO** (se mantienen de la ronda 1; el staged no cambió)

- **B1.** `Makefile:23/28/29`: en SRCS, `mod_audit` y `mod_properties_3d` van antes que `mod_probe`. Compila gracias a las reglas `.o` explícitas. Está declarado (l.423) para un commit aparte.
- **B2.** `src/mod_audit.f90:260-262` dice «cuánta E2 descartó ahí el Poisson». El código (:1067-1069) suma `ws_pc_unl` del transporte N, pero el último Poisson descartó la E2 del N-1. El reporte repite la forma exacta en l.338 («la E2 que el Poisson descartó ahí es 1.1e-14 kg») y `check_audit` imprime «con E2 descartada». El glosario sí dice «approximately». Con 1.1e-14 kg no cambia ninguna conclusión.
- **B3.** `src/mod_pressure_3d.f90:743-749`: marcar con `Su == 0` falla si la E2 cancela exactamente el resto de la fila, y el comentario afirma lo contrario. Es un caso de medida casi nula, sin efecto en la numérica.

### Verificado como correcto (no hace falta re-auditarlo)

- **Binario:** el hash de `git diff --cached -- src/` coincide con `logs/opt_identidad.txt` (0503d1f6…), así que el binario de banco corresponde al código en revisión.
- **Ganchos:**
  - Están en los 3 sitios del complemento (`mod_continuity.f90:808/1237/1687`) y en la EOS (`mod_properties_3d.f90:42`).
  - El resto de escrituras de α_g y ρ_g son volfix ya auditado, celdas `cell_type` 0, o la inicialización y el reinicio.
  - El orden en el bucle principal es: modo 0 en `main_3d:337`, último `update_properties` en :790, modo 1 en :795. No hay rollback de gas.
- **`ws_pc_unl_used`:**
  - Se asigna inicializado a 0 y se anula al empezar cada Poisson; la rutina no tiene returns tempranos.
  - Se pone a 0 en celdas inactivas o selladas (:672) y con `Su == 0` tras las BC.
  - valid/id se fijan en :751-752 y el audit solo lee celdas propias.
- **Halos e invalidación:**
  - `ws_Fc*` y `ws_Fc_lk*` se intercambian (:817-822) y `ws_Fr` también (`continuity:549`).
  - `ws_Fg_valid` se resetea en cada paso (`main:577`), así que `m_gas_e2_skip` = 0 por construcción es cierto.
- **CSV y MPI:**
  - La cabecera tiene 117 columnas, igual que las filas, y las 24 columnas nuevas van en el mismo orden que el `write`.
  - Todas las N_AUD se reducen por suma MPI y los contadores solo los suma el rank 0.
- **Arrays y reinicio:**
  - `mg_comp`, `mg_eos` y sus `_abs` se anulan enteros en el modo 0, sin el problema del Bug 22.
  - De `mg_ag0` solo se leen celdas propias.
  - No hay estado entre pasos, así que el reinicio no se ve afectado.
- **Checker:**
  - `mass_gas_rewrites` está dentro de la rama `flow_on`; `test_full.txt` tiene 67 PASS y «TESTS OK».
  - La lógica de n/a frente a 0.000 y la precedencia de la expresión son correctas, y la columna `m_slag` existe.
- **Citas de línea del reporte (l.418):** coinciden con el staged.

### Orden sugerido de corrección (uno por uno)

1. M1: corregir los párrafos :182-185 y :211-213 de la regla con la forma de C-163 y C-165; comprobar con grep.
2. B2: comentario de `mod_audit.f90:260-262` y frase del reporte l.338.
3. B3: máscara de salida explícita o corrección del comentario en `mod_pressure_3d.f90:743-745`.
4. B1: commit aparte, solo del Makefile, para el orden de SRCS.
