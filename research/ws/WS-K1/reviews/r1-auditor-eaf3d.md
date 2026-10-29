## Panel de cierre de WS-K1, ronda 1: revisión del auditor del código EAF3D

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Hay dos erratas BAJO de trazabilidad documental que no bloquean.

### Alcance del diff staged
- Archivos staged (sin contar las revisiones archivadas en `reviews/ciclo*/`): `.claude/rules/acople-pv.md` (+35/−49), `docs/PLAN_K_limitador_en_poisson.md` (+17/−18), `research/ws/WS-K1/report.md` (nuevo) y `research/ws/WS-K1/status.json`.
- **El diff no toca `src/`, `tests/`, `scripts/research`, `.claude/hooks`, `.claude/workflows`, `.claude/agents` ni `settings.json`.** El `diff_sha` de status.json (e3b0c442…b855) es el SHA-256 de la cadena vacía. Eso concuerda con `staged_sha()` (`scripts/research/ledger.py`:343-350), que hashea solo las rutas GATED. Tampoco se registran eventos en `ledger.jsonl`. Por eso no hay conservación, halos, MPI, snapshots ni lectores de `liq%alpha` que auditar en este cierre.
- `python3 scripts/research/ledger.py check` da: ledger OK (313 eventos, 13 workstreams).

### Hallazgos
**ALTO:** ninguno.
**MEDIO:** ninguno.

**BAJO-1. Citas por línea de WS-K2 que quedan colgando.**
- **Defecto.** `research/ws/WS-K2/report.md`:285-287 (en HEAD) cita estas posiciones:
  - `sed -n 659,666p .claude/rules/acople-pv.md`, para la guía contra repeticiones;
  - `sed -n 626,642p`, con «no reintentar…» en 641-642;
  - `research/ws/WS-K1/report.md:208–221` y `201,221p`, para la lectura del redactor sobre en qué difiere un margen continuo.
- **Qué pasa con el índice:**
  - acople-pv.md tiene 654 líneas, así que `sed -n 659,666p` sale vacío.
  - La guía está en 648-652 y el «no reintentar» en 646-647.
  - Las líneas 641-642 ahora tratan de `pc_limiter_faces`.
  - En el reporte nuevo de WS-K1, las líneas 208-221 tratan de la identificación del binario (punto 7). La lectura del redactor está en ~413-440.
- **Contradicción en el reporte.** La línea 630 reconoce que la cita «ya no coincide», pero la viñeta final dice que «vuelve a ser válida». No menciona la cita a report.md:208-221.
- **Escenario de fallo.** Quien reproduzca la fuente de WS-K2 obtiene una salida vacía o un texto sin relación.
- **Arreglo.** Una errata con las posiciones nuevas, quitando el «vuelve a ser válida». Mejor aún: citar por ancla de texto.

**BAJO-2. Cita de la incompatibilidad desplazada una línea.**
- **Defecto.** La fuente del reporte usa `sed -n 607,608p src/mod_config_3d.f90`. El `require` ocupa 606-607 y la 608 es `if (cfg%solve_ecs)`.
- **Contexto.** El cuerpo del reporte da 603-607, que es correcto.
- **Arreglo.** Citar `603,607p`.

### Verificado como correcto (no re-auditar)
- **Referencias al código actual:**
  - `src/mod_config_3d.f90`:91, 92 y 110: defaults de `pc_limiter_faces`=false, `pc_liq_sealed_wall`=false y `pc_transport_f28`=true.
  - `src/mod_config_3d.f90`:603-607: comentario B21-F1 y `require(.not.(pc_limiter_faces .and. pc_transport_f28))`. La entrada dice «la configuración aborta», y es correcto.
  - `src/mod_pressure_3d.f90`:1769-1795: `face_lim` hace solo el cierre BINARIO D2.2c (`ws_lim_step < pc_lim_dead`) y no queda escalado continuo D2.2.
  - `src/mod_constants.f90`:75: ALPHA_BED = 1e-2.
  - `grep -l pc_alpha_implicit src/*.f90` da 0 archivos.
- **Código en 1bc9832:**
  - En `mod_continuity.f90`, `ws_pc_unl_valid` se pone a true solo con `ws_Fc_valid` (863-866) y se invalida en la ruta de la línea 277.
  - `plan_k_v2.patch`:155 define `unl_on = pc_drift_source .and. ws_pc_unl_valid .and. ws_pc_unl_id == probe_current_step()`.
- **Receta de los parches:**
  - Las líneas `index` de `plan_k_v2.patch` (412cfd5, 3c1948e, c01f606) coinciden con los blobs de 1bc9832.
  - `v2_completo_sobre_HEAD.patch` es idéntico byte a byte a `plan_k_v2.patch`.
  - `pa_sin_A2.patch` tiene cabeceras no estándar «(v2)/(v2 sin A2)».
- **Commits de `src/`:** hay 7 desde 1bc9832 (c80dff6, 50d1d97, e3397d4, 4d8570a, 79dc27b, 2b65e11, 1de144e). Esto coincide con la «Vigencia» de la entrada.
- **`scripts/diag/cell_series.py`:46:** osc2 es `np.median` de |d2p|, que respalda «(a) pasa solo en la mediana».
- **Coherencia con el registro.** La entrada nueva de acople-pv.md (618-654) y el §6 del plan (86-109) coinciden con lo que dice `ledger.py show`: C-012, C-028, C-039, C-040/C-041, C-064 (fallida por C-294), C-065 (motivo «usuario aprobo el cierre»), C-091 (d24 refutada, d22c FALLIDA por configuración inválida), C-309, C-310/C-311 y C-312/C-313.
- **Referencias internas de acople-pv.md en el índice:**
  - H0 en 611-617;
  - VIGENCIA en 266-274;
  - rampa 4547861 y A20-2 en 539-546;
  - J-B en ~560-566.
- **`status.json`:** estado `en_revision` en la ronda 0. `ledger.py check` exigirá la clave `cierre` y las tres aprobaciones para `fallido`, como describe el reporte.

### Orden sugerido de corrección
1. BAJO-1: errata de las citas por línea entre WS-K2 y WS-K1, quitando la contradicción «vuelve a ser válida».
2. BAJO-2: cita `603,607p` en la fuente.

Las dos son de redacción y no bloquean. No hay código que corregir en este cierre.