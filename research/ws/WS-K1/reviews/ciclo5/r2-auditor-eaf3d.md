# WS-K1, panel de cierre, ronda 2: auditor-eaf3d

**Veredicto: RECHAZA.** Hay un hallazgo MEDIO sin resolver (MEDIO-1).

Alcance: `git diff --cached`, que toca `.claude/rules/acople-pv.md`, `docs/PLAN_K_limitador_en_poisson.md`, `status.json`, el reporte y las revisiones archivadas. Contrasté el diff con `research/ws/WS-K1/report.md` en disco, que trae cambios sin stagear propios de esta ronda. No hay cambios en `src/` ni en `tests/`.

## Hallazgos

### MEDIO

**MEDIO-1: falta D2.2/D2.2c en la lista de lo ya rechazado de la entrada «Plan K CERRADO»** (`.claude/rules/acople-pv.md`:661-670, staged)
- **Defecto.** La viñeta «Si se retoma con un margen o barrera continua…» pide decir «en qué difiere de lo ya rechazado» y enumera solo 4547861, D2.4/C-091 y A20-2.
- **Qué falta.** D2.2/D2.2c (Plan D, `pc_limiter_faces`), el precedente más cercano. Era un cierre gradual de caras en el Poisson con el momento congelado, dentro del paso y sin estado entre pasos, y empeoró en toda combinación:
  - D2.2: p>100k 15.2 frente a 8.1 %, centinela 11.2 frente a 4.7 %.
  - D2.2c: 17.1/15.1 frente a 4.9/4.4 %.
  - Fuente: `docs/dev-history/2026-10-07_plan_d_acople_implicito.md`:71-78 y 159-166.
- **Contradicción con el reporte.** El reporte habla de «cuatro fracasos» (report.md:277) y retira su argumento del «cierre gradual» precisamente por D2.2. En report.md:392-405 declara que la entrada «necesita» O1 (D2.2), O2, O3 y O5, y siguen pendientes: `acople-pv.md` no tiene cambios fuera del staged.
- **Ningún archivo de reglas lo cubre.** Ni `.claude/rules` ni `CLAUDE.md` mencionan D2.2 o `pc_limiter_faces` (grep: 0 coincidencias).
- **Escenario de fallo.** Una sesión futura carga la regla, diseña una barrera continua bajo el tope en el Poisson, la contrasta con las tres entradas, no encuentra D2.2 y repite su mecanismo: la celda donante se vuelve un callejón sin salida y la columna se sella de abajo arriba. Además, el registro permanente contradice al reporte que lo cierra (tres precedentes frente a cuatro).
- **Arreglo.** Añadir a esa lista: «D2.2/D2.2c (Plan D, 7-oct: cierre continuo o binario de caras en el Poisson con el momento congelado, perjudicial; banco `bed_flood` previo a las auditorías 3-21, condicional)». Recomendado, en una línea (O5): «la decisión del 23-oct se apoyó en C-041 y en C-064, hoy fallida (C-294)». Después, quitar el bloque «Pendiente para el coordinador» del reporte.

### BAJO

**BAJO-1 (se mantiene de la ronda 1): el reporte atribuye a este diff cosas que ya están en HEAD**
- report.md:17-19 dice «El diff compartido del cierre sí añade {C-312}/{C-313}».
- report.md:51-52 y 348-357 dicen «corrigió en este cierre» y «añadido … en este cierre».
- Todo eso ya está en HEAD desde e250687: `git log -S` sobre `ledger.jsonl` y sobre `acople-pv.md` devuelve e250687. Ni `ledger.jsonl` ni `research.md` están en el staged.
- **Arreglo.** Redactar «ya en HEAD (e250687)».

**BAJO-2 (se mantiene de la ronda 1): el default de tolerancia se cita del parche equivocado**
- report.md:35-36 dice «el default del parche es 1e-6», pero ese valor sale de `plan_k_v2.patch`, y k1_342 corrió v1, cuyo parche no está archivado.
- **Arreglo.** Redactar «default de v2; el de v1 no está archivado».

**BAJO-3: base incompleta de la decisión del 23-oct**
- report.md:9-11 dice que la decisión se apoyó en C-064, y llama «motivo de C-065» a una cita que está en su ENUNCIADO.
- Ese enunciado da dos bases: C-041 (sigue refutada) y C-064.
- **Escenario.** El lector infiere que la decisión perdió toda su base con C-294.
- **Arreglo.** Citar ambas bases.

**BAJO-4: `unl_on` no depende solo de `pc_drift_source`**
- report.md:154-155 dice que con `pc_drift_source = true` «unl_on sí estaba activo».
- En `plan_k_v2.patch`:155, `unl_on` exige además `ws_pc_unl_valid` y `ws_pc_unl_id` igual al paso actual.
- En 1bc9832, `mod_continuity.f90`:863-866 solo lo valida tras un transporte del mismo paso; la línea 277 lo invalida en la ruta `solve_alpha_bounded_implicit`.
- En consecuencia, `unl_on` está activo como mucho en los outers 2-5. La conclusión (P-a cambia dos cosas) se sostiene; la frase es más fuerte que el código.

## Verificado como correcto

- **`diff_sha`.** Vale e3b0c442…, que es el sha256 de la cadena vacía. Es correcto: el staged no toca rutas GATED (README:106-123, `ledger.py`:371 y 396).
- **Sin código Fortran en el diff.** Halos, `mold`, dummies, audit y snapshot no aplican en esta ronda.
- **Parches.** `pa_sin_A2.patch`:7-23 pone el factor de `acc_face` a 1 y `unl_on = .false.`. En `plan_k_v2.patch`:212-220 y 310-325, la fórmula de `s_nw` y `acc_face` son coherentes con la inferencia de signo del reporte (marcada como inferencia).
- **Configuración y logs.** `pc_drift_source = true` en las cinco `config.dat`. Hay 0 líneas PROBE-LIM/`ws_pc_unl` en los `run.log` de k1*_342.
- **Sonda (10,60,2), 342500-342560, recalculada con h5py:**

  | corrida | osc2 (Pa) | fracción \|d2p\| > 1000 | p75 (Pa) | máximo (Pa) |
  |---|---|---|---|---|
  | k1b | 885.7 | 0.475 | 14 559 | 218 858 |
  | k1pb | 889.7 | 0.475 | 14 565 | 218 864 |
  | base | 51 835 | 0.847 | 111 994 | 333 796 |
  | k1pa | 342 | 0.22 | 721 | 3 728 |

  Coincide con lo que dice O3: k1b y k1pb son en la práctica una sola trayectoria.
- **Cifras de D2.2/D2.2c y «sin estado entre pasos».** Confirmadas en el dev-history de Plan D.
- **Registro.** C-064 dice «Existe con y sin Plan K» y C-294 la cierra como fallida. C-040 declara el brazo K = v2 + pa_sin_A2. C-312/C-313 están en estado `propuesta`.
- **Plan K §2 y §6 (staged).** §2 ya distingue a Plan K de D2.2. §6 es coherente con el reporte en P-a (dos ingredientes), la holgura medida solo en k1pa_342 y el binario no identificado.

## Orden de corrección

1. MEDIO-1: añadir D2.2/D2.2c, y opcionalmente O5, a `acople-pv.md`. Stagear y quitar el bloque «Pendiente para el coordinador» del reporte.
2. BAJO-3: base de la decisión.
3. BAJO-1: procedencia en HEAD.
4. BAJO-2 y BAJO-4: precisiones de redacción.
