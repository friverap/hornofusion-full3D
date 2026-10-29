El veredicto es **aprueba**: no hay hallazgos ALTO ni MEDIO.

# WS-K2, ronda 2: revisión del auditor (auditor-eaf3d)

**Veredicto: aprueba.** Quedan objeciones BAJO, ninguna bloqueante.

Solo hubo lectura: git diff/show, grep, sed y python3 sobre los audit.csv que ya estaban en disco. No se compiló ni se ejecutó nada.

## Alcance

- **Sin código en el diff staged.** `git diff --cached --name-only` solo trae .md, .json y .jsonl. `git status -- src tests scripts Makefile` está limpio. El `diff_sha` de status.json es el sha256 de la cadena vacía. No hay código Fortran que auditar (masa, energía, halos, MPI y snapshot no aplican).
- **Qué revisé.** Las afirmaciones del reporte contra los datos en disco, y lo staged en `.claude/rules/acople-pv.md`, `.claude/rules/research.md` y `docs/PLAN_K_limitador_en_poisson.md` contra el registro.
- **Reportes con cambios sin stage.** `research/ws/WS-K2/report.md` y `research/ws/WS-K1/report.md` están en estado AM. Revisé el árbol de trabajo (ver N-3).

## Hallazgos

### ALTO / MEDIO
Ninguno.

### BAJO (no bloqueantes)

**De la ronda 1 que siguen sin resolver** (el redactor no respondió):
- **B-1** (report.md:176). «(racha máx. 2)» sigue en la columna «Tope 2.0e6». La racha en 2.0e6 es 1; la de 2 es la de >= 1e6.
- **B-3** (report.md:153, 155, 178 y la entrada «Plan K CERRADO» de acople-pv.md). Los 183/122 y el 100 % cuentan la fila 345500.
  - Verifiqué esa fila: dt 1.258e-9 y p_max 2.0e6, es el paso truncado.
  - Contando solo pasos completos son 182 y 121.
- **B-5** (report.md:268, 340-341). C-089 se cita como «regla de vigencia», pero está «fallida» (C-284).
  - C-284 dice que la regla sigue vigente como método.
  - Basta con citarla así: C-089 + C-284 + acople-pv.md:266.

**Nuevas:**
- **N-1** (report.md:230-231). «La de 345150 difiere solo en las columnas E_src_*» es falso. Difiere en 43 columnas: todas las de incremento por paso, que valen 0 en la fila de reinicio (m_spill, m_alpha_clip, vol_lim, m_melted, E_rad_sol, …). El linaje sí queda probado (ver «Verificado»).
- **N-2** (report.md:277 y acople-pv.md, viñeta «Si se retoma»). «k1pa ya pasó [342.45–342.56] y aun así falló el juez» identifica la sonda k1pa_342 con el brazo k1pa_340_*. Eso contradice las líneas 288-320 del mismo reporte, que dicen que el binario K no se identifica. La versión de trabajo de WS-K1 ya lo corrigió; hay que alinear WS-K2 y acople-pv.md con ella.
- **N-3** (report.md:285 y su fuente). `research/ws/WS-K1/report.md:208-221` solo vale para el WS-K1 staged; en el árbol de trabajo el párrafo está en 228-241. Hay que hacer stage de los dos reportes antes del commit de cierre y actualizar la referencia, o citar por sección.

### Resueltas desde la ronda 1
- **B-2.** La fuente ahora es `sed -n 626,642p` con la cita literal. «no reintentar el conjunto» está en acople-pv.md:641.
- **B-4.** El reporte da el reinicio `campaigns/b1/diag_k15c/eaf3d_00345150.h5`, con la advertencia del transitorio de C-309 y una propuesta de pre-registro. Lo verifiqué (ver abajo).

## Verificado como correcto (no re-auditar)

**Linaje del reinicio diag_k15c:**
- diag_k15c sale de judge_otp_280/eaf3d_00340000.h5 con `pc_alpha_implicit = true` y `pc_ai_tol = 1.0e-3`. Su config difiere del de k1pa_340_n15 solo en `output_dir` y `t_final`.
- Su audit.csv es idéntico fila a fila a k1pa_340_n15 en 340000-345150 (5151 filas, 0 diferencias).
- diag_k15d arranca de diag_k15c/eaf3d_00345150.h5. Sus 181 filas (345150-345330) coinciden en p_max y m_gas; 180 son idénticas en todas las columnas.
- El paso 345150 de n15 es completo (dt 1.0e-3).

**f231_340:**
- Su config difiere del de base_340_n14 en 117c117, 119c119 (t_final 346.0) y 121a122 (`pc_f231_step_freeze = true`). Mismo `restart_file` (judge_otp_280/eaf3d_00340000.h5).
- En 340-345.5 s: 345 pasos con p_max >= 1e6, 51 en 2e6 (el primero en 344873) y racha de 82 (345394-345475).
- En 340-346 s: 482, 66 y racha de 108 (345481-345588).
- Ningún «unknown key» en su run.log.
- El `ws_f231_step` de src/mod_pressure_3d.f90:392 es otra cosa: la histéresis M12-E1, que solo actúa con dt >= 2·DT_MOB_REF. No interfiere.

**Binarios:**
- judge_otp_280 no tiene run.sh; ni su run.log ni su config.dat identifican el binario.
- `campaigns/bin/eaf3d_k1pa_opt` no existe.
- Los config.dat de k1pa_340_n12/_n14/_n15 son de las 18:15:48 del 22-oct, igual que el ts de C-040. k1pa_342/audit.csv es de las 18:14:03.
- `[PLAN-K] solves 25000 sin converger` da 104/143/114, con 5 líneas por run.log.
- 0 avisos «unknown key» en los k1pa_340_*; el aviso está en src/mod_config_3d.f90:446.

**Reinicio diag_p342a:** el paso 342450 está truncado (dt 1.186e-9, p_max 2.78e4 → 9.52e4), como dice C-290.

**Registro:**
- C-028 trae «(a) osc2 886 Pa <= 1000 cumple solo en la mediana».
- C-033 restringe «recupera el ciclo» a 342517-342533.
- El «6874 frente a 23362 Pa» de acople-pv.md sale de la lista de calibración de C-036.
- C-039 está soportada y C-064 fallida.
- C-013/C-031 (staged en research.md): los ~69 kPa son la media del ciclo frenando un chorro y la hidrostática sobre esa celda es ~6 kPa. Coincide.

**Referencias de línea:** «Plan K CERRADO» en acople-pv.md:618; «no reintentar el conjunto» en 641-642; PLAN_K §4, líneas 72-73; §6, líneas 94-99; acople-pv.md:659-666.

**PLAN_K §6:** `pc_alpha_implicit` aparece en 0 archivos de src/.

## Orden sugerido de corrección (uno por uno)
1. N-3: hacer stage de los dos reportes y fijar la referencia a WS-K1.
2. N-2: alinear «k1pa ya pasó… y falló el juez» en WS-K2:277 y en acople-pv.md con la redacción corregida de WS-K1.
3. B-3: nota del paso truncado 345500, o 182/121, en el reporte y en acople-pv.md.
4. N-1: «43 columnas de incremento por paso» en lugar de «E_src_*».
5. B-1: mover «racha máx. 2» a la columna correcta.
6. B-5: citar C-089 como regla de método (con C-284).
