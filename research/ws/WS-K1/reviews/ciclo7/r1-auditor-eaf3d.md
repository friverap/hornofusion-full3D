## Revisión de WS-K1, ronda 1: auditor-eaf3d

**Veredicto: RECHAZA.** Hay un hallazgo MEDIO sin resolver en el texto staged de las reglas.

Alcance: el diff staged (`git diff --cached`) solo trae documentación (`.claude/rules/acople-pv.md`, `docs/PLAN_K_limitador_en_poisson.md`), el reporte, revisiones previas y `status.json`. No hay cambio en `src/` ni en ninguna ruta GATED. Por eso la auditoría de código se centró en las afirmaciones sobre el código que hace el texto nuevo. No leí las revisiones de otros revisores.

### Hallazgos

**MEDIO (bloqueante): «D2.2b, hoy F2.8» es falso**
- `.claude/rules/acople-pv.md:678-679` (texto nuevo): «frente a 4.9/4.4 % de la pared sola (D2.2b, hoy F2.8)».
- **D2.2b** es la clave `pc_liq_sealed_wall`:
  - Default `.false.` en `src/mod_config_3d.f90:92` («cerrado negativo 10-oct-2026»).
  - Refutada en el banco B1 con el código actual (C-091, d22b).
- **F2.8** es otra cosa:
  - Es el cierre binario de caras de líquido hacia una receptora sin hueco (`ws_liq_room`, `src/mod_workspace.f90:292`, `src/mod_pressure_3d.f90:1737`).
  - Es anterior a D2.2b (dev-history Plan D, línea 48) y hoy está activo.
  - La etiqueta de la tabla de Plan D «D2.2b sola (F2.8 binario)» quiere decir «sobre F2.8», no que se haya renombrado.
- El mismo archivo se contradice: en la línea 444 `pc_liq_sealed_wall` aparece con default false, y en la 684 D2.2b «no se transfiere a B1».
- **Escenario de fallo:** acople-pv.md se carga en toda sesión que toque pressure, momentum o multiphase (CLAUDE.md:103). Quien lo lea:
  - creerá que la pared sellada de D2.2b ya está activa en HEAD;
  - leerá mal la base de B1;
  - dará por probada en B1 una clave que en realidad está refutada en el banco.
- **Arreglo:** escribir «(D2.2b, clave `pc_liq_sealed_wall`, hoy default false; refutada en el banco B1, C-091)» o «(D2.2b sobre F2.8)».

**BAJO (no bloqueante): falta un dato en «D2.2 en B1 no se ha corrido»**
- `acople-pv.md:690-691` y `report.md` (iv): la frase es cierta, pero omite dos cosas.
  - **El intento del 23-oct.** D2.2c se intentó en el banco B1 (C-090, `campaigns/b1/bench_d22c`) y C-091 la dejó como FALLIDA no evaluable. La configuración la rechaza porque `pc_limiter_faces` es incompatible con `pc_transport_f28`, activo por defecto (`src/mod_config_3d.f90:603-607`, B21-F1).
  - **Qué hay en HEAD.** Solo existe el cierre binario D2.2c (`face_lim`, `src/mod_pressure_3d.f90:1769-1795`); el escalado continuo D2.2 ya no está en el código.
- **Escenario:** quien retome y lance «D2.2 en B1» verá la corrida abortar en la configuración. Si apaga `pc_transport_f28` para que corra, el resultado queda confundido con J-B y con el ciclo entre outers de B21-F1.
- **Arreglo:** una frase que cite C-091 y la incompatibilidad.

### Verificado como correcto (no re-auditar)
- **Rutas GATED:** el diff sobre ellas tiene 0 bytes, y `diff_sha` e3b0c442… es el sha256 del diff vacío (`staged_sha`, `ledger.py:347`).
- **Sin Fortran:** al no tocar código, no hay efecto sobre conservación, halos, snapshot, `liq%alpha` ni checkers.
- **Parche P-a** (`patches/pa_sin_A2.patch`): cambia exactamente dos cosas, `unl_on = .false.` y el factor de `acc_face` a 1. Es correcto que ninguna corrida las separa.
- **cell_series en k1pa_342** (10,60,2), pasos 342510–342533: alternancia_dp 0.000, osc2 209.5, ag_min 0.01834.
- **Mediana de |d2p|** en 342500–342560:
  - k1b 885.7 / k1pb 889.7 / base 51835 Pa.
  - Fracción de pasos > 1000 Pa: 0.475 / 0.475 / 0.847; k1pa 0.22.
  - Respalda tanto «UNA sola trayectoria» como «47 frente a 85 %».
- **regime2:**
  - 342–344 s: p>100k de K 1.4–2.4 % frente a 7.2–10.3 % de la base.
  - 344–345.5 s: cent_pg de K 0.1/0.3 (n12/n14) frente a 6.7–9.5 % de la base; n15 12.8.
- **Cifras de Plan D:** 15.2/8.1, 11.2/4.7, 17.1/15.1 frente a 4.9/4.4; clave `pc_limiter_faces`; cita «NO se transfieren a B1» (líneas 424–425); bed_flood de 12×24×16 y 12 s.
- **Commits:** hay 7 commits de src después de 1bc9832, y 4547861 es la rampa sobre ALPHA_BED.
- **Registro:** C-040 declara «v2 sin A2»; los textos de C-065 coinciden con lo citado; `ledger open` da 0 abiertas.

### Orden de corrección
1. A1: corregir «(D2.2b, hoy F2.8)» en acople-pv.md:678-679. Es una línea.
2. B1 (opcional): añadir el intento de C-091 y la incompatibilidad con `pc_transport_f28` en la viñeta D2.2/D2.2c y en el punto (iv) del reporte.
