El reporte de cierre de WS-K1 está bien respaldado: apruebo. El diff no toca código y todas las afirmaciones que revisé contra el registro son correctas. Quedan 3 observaciones menores que no bloquean.

# Revisión WS-K1, ronda 1 (auditor-eaf3d)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO.

## Alcance del diff
- `git diff --cached` de WS-K1 solo trae `research/ws/WS-K1/report.md` (nuevo) y `status.json` (pasa a `en_revision` y llena `diff_sha`).
- Las rutas que la compuerta vigila (src, tests, scripts/research, .claude/*) no tienen nada staged: `git diff --cached -- src tests scripts/research .claude | wc -c` da 0.
- `diff_sha` = `e3b0c442...b855`, que es el sha256 de la cadena vacía. Cuadra con un cierre sin código.
- Por eso no aplican los temas de Fortran (halos, `mold`, dummies `(-1:,-1:,-1:)`, snapshot, columna de audit).
- El diff staged también incluye WS-K2 y WS-K3. Quedan fuera de esta revisión.

## Hallazgos
### ALTO
Ninguno.
### MEDIO
Ninguno.
### BAJO (no bloqueantes)
- **B-1. Ronda mal etiquetada.**
  - `research/ws/WS-K1/status.json` tiene `ronda: 0` y el panel es la ronda 1.
  - `cmd_ws_set` (`scripts/research/ledger.py`, aprox. líneas 375-377) guarda cada veredicto con la ronda que tenga `status.json` en ese momento.
  - Escenario: si no se hace `ws-set ronda=1` antes, los tres «aprueba» quedan como ronda 0. `check` pasa igual porque compara contra la misma ronda, pero el registro queda con la ronda equivocada.
  - Arreglo: fijar `ronda=1` antes de registrar los veredictos.
- **B-2. Matiz de C-029 en la tabla.**
  - La tabla cuenta C-029 como refutada, igual que el registro.
  - Pero C-032 solo refuta la mitad act_g; la mitad gsum quedó sin medir.
  - El texto lo matiza; la tabla no. Basta una nota al pie.
- **B-3. Falta decir qué son los 7 commits.**
  - Los 7 commits en src desde 1bc9832 son: 1de144e, 2b65e11, 79dc27b, 4d8570a, e3397d4, 50d1d97 y c80dff6.
  - Todos son de auditoría o diagnóstico, y sus mensajes los declaran bit a bit.
  - Los diffs que leí de mod_continuity y mod_pressure_3d solo añaden `audit_comp_cell` y escrituras en arrays `ws_*`.
  - El reporte no lo dice, y eso decide si el Plan K sigue «vigente» según C-089.
  - Yo no verifiqué el bit a bit.

## Verificado como correcto
- **Estado de las afirmaciones.** El comando del reporte da `16 {'refutada': 4, 'fallida': 9, 'soportada': 3}`.
  - Raíces: C-011, C-013, C-016..C-024, C-025, C-029, C-030, C-033, C-034.
  - `ledger.py open` no muestra nada abierto de WS-K1.
  - `ledger.py check` da OK (309 eventos).
- **H1 y H1b.**
  - C-012 refuta C-011: convergencia 0 %, |p| = 69.1 kPa > 20, osc2 baja de 51.8 kPa a 342 Pa.
  - C-028 refuta C-025: (b) 70.6 > 3; (c) 5.4 % > 3.2 %; recupera el ciclo y el pico de 410 kPa en 342.534 s.
- **La «sobrepresión no física».** C-031 refuta C-013: es la media del ciclo de la base y frena el chorro.
  - La lección está en `.claude/rules/research.md:15` («Pensar la escala física antes»).
- **Hipótesis de la holgura.**
  - C-032 refuta la mitad act_g de C-029.
  - C-039 soporta C-034. P-a da osc2 209.5 Pa (C-037). P-b da osc2 6876 Pa, 99.8 % sin converger (C-038).
- **Cierre de los 9 hallazgos.** C-065..C-073 están `fallida` con motivo «Plan K no adoptado; usuario aprobo el cierre 2026-10-23».
  - C-018 (A3) estaba PENDIENTE, como dice el reporte.
- **Juez y estallido.**
  - C-041 refuta C-040 por (i) en 344-345.5 s y por (iii) en n15 (2.0e6 Pa); 2 de 3 trayectorias K salen mejores.
  - C-064 está cerrado como fallida por C-294 (WS-K12), como dice el reporte.
- **Código archivado.**
  - `grep -l pc_alpha_implicit src/*.f90 | wc -l` da 0.
  - `git apply --check research/ws/WS-K1/plan_k_v2.patch` falla en `src/mod_pressure_3d.f90:733`, como dice el reporte.
  - `git rev-list --count 1bc9832..HEAD -- src` da 7.
- **Archivos citados.** Existen `research/ws/WS-K1/plan_k_v2.patch`, `patches/pa_sin_A2.patch`, `patches/v2_completo_sobre_HEAD.patch`, `reevaluacion.md` y `reviews/r1-revisor-refutador-reevaluacion.md`.
- **Ruta de cierre.**
  - `ledger.py check` exige para `fallido` la clave `cierre` y los 3 «aprueba» en la ronda vigente (líneas 328-335). Coincide con lo que dice el reporte y con `research/README.md:129-136`.
  - Un `fallido` no pasa `gate_errors`, que exige `aprobado`. Es correcto que no abra la compuerta.
- **Meta G1.** El texto de G1 en `research/QUESTION.md:17` coincide con lo que se cita.

## Orden sugerido
1. B-1: fijar `ronda=1` antes de registrar los veredictos.
2. B-2: nota en la tabla sobre C-029.
3. B-3: una línea sobre la naturaleza de los 7 commits.

Todos se pueden hacer sin código.
