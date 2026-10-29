## Revisión WS-K1, ronda 1: auditor EAF3D

Veredicto: **RECHAZA**. Hay un hallazgo MEDIO sin resolver.

El diff staged no toca `src/`, `tests/` ni `scripts/research`: el sha del diff con compuerta es el de la cadena vacía. Por eso no hay riesgos de código Fortran (halos, `mold`, MPI, snapshot) que auditar. La revisión se centra en lo que sí cambia: el reporte, el registro permanente (`.claude/rules/acople-pv.md`, `research.md`, el §6 del plan), el ledger y los status.json. Cada cifra se verificó contra los datos en disco.

### Hallazgos

**MEDIO M1: el binario del brazo K del juez se da por identificado y no lo está.**
- **Dónde:** `research/ws/WS-K1/report.md`, punto 7 («es decir, **v2 sin A2** (la variante con holgura)») y los bullets de Incertidumbre («k1pa (v2 sin A2) es el brazo K de C-041»; «la variante k1pa, que después se refutó en B1»; «k1pa, que tenía holgura, falló el juez»). Lo mismo en `.claude/rules/acople-pv.md`, entrada «Plan K CERRADO», viñeta final: «k1pa ya pasó esa ventana y falló el juez».
- **Defecto:** se mezclan dos cosas distintas.
  - La holgura está **medida** solo en `k1pa_342`: ag_min 0.01834 y osc2 209.5.
  - Que el juez `k1pa_340_*` usara ese binario es una **declaración** de C-040. Comprobé que no se puede verificar en disco:
    - las corridas no tienen `run.sh` y el `run.log` no registra el binario;
    - `campaigns/bin/eaf3d_k1pa_opt` no existe;
    - no hay ninguna línea PROBE y solo hay 2 snapshots (340000 y 345500);
    - `pa_sin_A2.patch` no cambia ninguna salida (`[PLAN-K]` es igual en v2).
  - WS-K2/report.md:228-249, la propia entrada de acople-pv y el §6 dicen «binario no identificado: v2 con o sin A2». Es una contradicción dentro del mismo diff.
- **Escenario de fallo:** quien retome un margen o barrera bajo el tope lee en el registro permanente que «la holgura ya falló el juez B1» y la descarta. Pero si el brazo K era v2 con A2 (tope exacto), la holgura nunca se juzgó en B1. Esto contradice la regla de vigencia de los fracasos.
- **Arreglo:** decir «brazo K declarado v2 sin A2 (C-040), binario no verificable (WS-K2); la holgura se midió solo en k1pa_342», o aportar un dato que identifique el binario.

**BAJO B1.** La entrada de acople-pv y el §6 atribuyen el efecto solo a la «holgura». P-a cambia además `unl_on = .false.` (`pa_sin_A2.patch`:8), y no hay corrida que separe los dos ingredientes. «El limitador no conmuta» es una inferencia, no una medida. El reporte (punto 5) sí lo dice; el registro permanente no.

**BAJO B2.** «Este cierre no … registra eventos nuevos»: el diff compartido añade C-312 y C-313 (WS-K2), y la entrada nueva de acople-pv los cita. Conviene precisarlo.

### Verificado como correcto (no re-auditar)
- **Compuerta y ledger:**
  - el diff con compuerta está vacío (sha e3b0c44…), igual que `diff_sha` en los status.json;
  - `ledger.py check` da OK y hay 0 abiertas;
  - WS-K1 tiene 16 raíces (4 refutadas, 9 fallidas, 3 soportadas);
  - C-065..C-073 cierran C-016..C-024.
- **Sonda (10,60,2):**
  - k1: osc2 342.3, máximo 69967.7 en 342539 (69103 en 342540) y |p| ≥ 20.97 kPa desde 342518;
  - k1b: osc2 885.7 y grad_hid 70.57;
  - base: osc2 51835;
  - en 342510-342533: k1b 6874.3/0.01500, k1pa 209.5/0.01834, base 23362.5;
  - fracción |d2p| > 1000 Pa: 50, 13, 28 y 13 de 59, con p75 y máximos como en el reporte.
- **Audit 342.45-342.56:**
  - p_max > 1e5 en 7 (base), 6 (k1b, k1pb) y 2 (k1, k1pa) pasos, los listados;
  - los valores de 342451 y 342452 coinciden;
  - regime2 da 6.3 y 5.4 %;
  - vol_lim 2.481e-3 frente a 2.460e-3, y vol_unl 2.057e-3;
  - plank_conv: 0.9 % (k1b, k1pa) y 100 % (k1).
- **dense_340_n14:** el max|p| de phantom está en (1,59,9) con 74.5, 94.0, 42.6, 108.0, 42.9 y 636.0 kPa, y el reinicio sale de judge_otp_280.
- **Juez:**
  - regime2 de k1_340, de k1pa n12/n14/n15 y de la base, por ventana, coincide;
  - n15 tiene 183 pasos seguidos ≥ 1e6 (122 en 2e6);
  - la base pasa de 1 MPa en 3 de 3 trayectorias y llega a 2 MPa en 2 de 3;
  - la alineación de C-313 coincide.
- **Parches y src:**
  - las líneas index coinciden con 1bc9832, `v2_completo_sobre_HEAD` es idéntico a `plan_k_v2.patch` y `git apply --check` falla en :733;
  - desde 1bc9832 hay 7 commits de src, y los cambios en pressure y continuity son solo diagnóstico;
  - `pc_alpha_implicit` nunca estuvo en la historia de src.
- **Referencias:** las líneas citadas de acople-pv (266-274, 536-546, 560-566, 611-617), PLAN_K §4, `cell_series.py`:46 y reevaluacion.md 82-85 son correctas.

### Orden sugerido de corrección
1. M1: corregir el texto en el reporte (punto 7 e Incertidumbre) y en la viñeta final de acople-pv.
2. B1: añadir una línea sobre los dos ingredientes de P-a en acople-pv y en el §6.
3. B2: precisar «sin eventos de WS-K1».
