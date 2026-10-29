El veredicto es **aprueba**: no hay hallazgos ALTO ni MEDIO. Quedan dos erratas BAJO de redacción, que no bloquean.

# Revisión auditor-eaf3d, WS-K1, ronda 1

## Alcance del diff staged

- **No hay código en el diff.** `git diff --cached -- src tests scripts/research .claude/hooks .claude/workflows .claude/agents .claude/settings.json` sale vacío.
- **El `diff_sha` está bien.** `status.json` lleva `e3b0c442…b855`, que es el SHA-256 de la cadena vacía. Coincide con `staged_sha()` (`scripts/research/ledger.py`:347-350, que solo mira las rutas GATED). No es un hash mal calculado.
- **Archivos que sí cambian:**
  - `.claude/rules/acople-pv.md`: 33 líneas añadidas y 9 quitadas.
  - `docs/PLAN_K_limitador_en_poisson.md`: 4 añadidas y 2 quitadas.
  - `research/ws/WS-K1/report.md`, el `status.json` y las revisiones de ciclos anteriores.
- **El registro no cambia.** `research/ledger.jsonl` no está staged, como dice el reporte («no registra eventos»).
- **`src/` no tiene el Plan K.** 0 archivos de `src/` contienen `pc_alpha_implicit`, y hay 7 commits de `src/` desde 1bc9832.

Como no hay código Fortran, no aplican estas comprobaciones: auditoría de masa/energía, halos, dummies `(-1:,-1:,-1:)`, Bug 22, snapshot de reinicio, vista condensada de la escoria y checkers de integración. Lo que sigue revisa los cambios a las reglas y al plan contra los datos en disco.

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B1. El reporte describe mal qué trae el diff.**
- **Dónde:** `research/ws/WS-K1/report.md`:364-366, 399-401 y la fuente de la línea 425.
- **Defecto:** el reporte dice que el diff staged «solo corrige las viñetas del ciclo 5», que eso es «lo ÚNICO» que trae, y da un stat de «acople-pv.md 16 líneas».
- **Lo que hay en realidad:** el diff también trae las correcciones del ciclo 6:
  - la lista D2.2/D2.2c (`acople-pv.md`:673-689);
  - las salvedades k1b/k1pb (637-640);
  - la viñeta «La decisión de no adoptar».

  En HEAD no hay ninguna mención de D2.2 en `acople-pv.md`. El numstat real es 33/9.
- **Escenario de fallo:** quien lea el reporte cree que la entrada D2.2 ya estaba en e250687 y no la revisa como cambio de este cierre.
- **Arreglo:** decir «ciclos 5 y 6» y poner el numstat real en la fuente.
- **Por qué no bloquea:** el contenido de esas viñetas está verificado (abajo).

**B2. «C-041 (refutada, vigente)» es ambiguo.**
- **Dónde:** `acople-pv.md`:687-689 (staged).
- **Defecto:** C-041 es el veredicto que refuta el juez C-040, no una afirmación refutada.
- **Arreglo:** escribir «el juez C-040, refutado por C-041».

## Verificado como correcto (no re-auditar)

**Variante P-a (`patches/pa_sin_A2.patch`).** Cambia dos cosas, como dicen la regla y el §6 del plan:
- `unl_on = .false.` (línea 8);
- `fac = 1` en la entrada y en la salida de `acc_face` (líneas 15-23).

**Cifras de la celda sonda (10,60,2).** Las recalculé con `cell_series.py` y con h5py sobre los HDF5 que ya existen:
- k1b_342 y k1pb_342, pasos 342500-342560: osc2 885.7 y 889.7 Pa. En ambas, el 47.5 % de los pasos supera 1000 Pa de |d2p|, con máximos de 218 858 y 218 864 Pa.
- Base diag_p342b, misma ventana: 84.7 % y máximo 333 796 Pa.
- k1pa_342, pasos 342510-342533: alternancia_dp 0.000, ag_min 0.01834, osc2 209.5 Pa.

**Cifras de Plan D** (`docs/dev-history/2026-10-07_plan_d_acople_implicito.md`, líneas 54, 75-78, 93, 116-119 y 159-165):
- D2.2: p>100k 15.2 % frente a 8.1 % de la base; centinela 11.2 % frente a 4.7 %.
- D2.2c con pared: 17.1/15.1 % (n4/n8) frente a 4.9/4.4 % de la pared sola.
- La clave es `pc_limiter_faces`, y la tabla rotula «D2.2b sola (F2.8 binario)».
- La lección de la «celda donante» y el «Bug 16 en una variante» están en el documento.

**Estado en el registro:**
- C-041 refuta C-040.
- C-064 aparece como «propuesta» en su evento raíz, y C-294 la cierra como fallida.
- C-091 (d24 refutada en el banco) y el `motivo` de C-065 coinciden con lo citado.

**Citas a `acople-pv.md`:**
- 266-274: la regla de vigencia, que declara vigente el Plan K.
- 560-566: J-B, hueco congelado en α^n.
- 611-617: H0, el limitador alterna por paso.
- 536-546: rampa 4547861 y A20-2.

**Commit e250687.** Contiene la entrada «Plan K CERRADO», el §6 del plan y C-312/C-313.

**Fuera de mi alcance.** No re-verifiqué el detalle de config.dat y de los recuentos [PROBE-*] de las líneas 426-453. No es código; le toca a revisor-evidencia.

## Orden sugerido de corrección
1. B1: alcance del diff en el reporte.
2. B2: redacción de C-040/C-041 en `acople-pv.md`.