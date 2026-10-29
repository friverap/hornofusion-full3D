# Revisión WS-K3, ronda 2 (auditor-eaf3d)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO.

## Alcance
El diff staged no contiene código: `git diff --cached -- . ':!research'` sale vacío. Toca 6 archivos de `research/ws/WS-K{1,2,3}`. `diff_sha` = e3b0c442…, que es el sha256 del diff vacío de las rutas con compuerta. Por eso no aplican las comprobaciones de código (halos, Bug 22, dummies, auditoría por PASO, snapshot de reinicio, checkers). Revisé el reporte contra el registro y contra `campaigns/b1`.

## Objeciones de la ronda 1
- **B1: resuelta** en el árbol de trabajo. El inciso (d) ya aparece con sus dos checks: sentinel_gas (d26k 23/77, e1 2/1; base 201/131) y energy_balance (2.32/2.31 y 1.79/1.84 frente a 1.717). También corrige la errata (2.334, C-284). Todo coincide con C-093 y C-284.
- **N1: se mantiene como nota.** `status.json` sigue en ronda 0. Ver abajo.

## Hallazgos
### BAJO
- **B2** (`research/ws/WS-K3/report.md`, Incertidumbre, segundo hueco de C-089). El reporte dice que las corridas de E1 son «340–345.5, 280–285.5 y dos del 20-oct en 275–300 s». Los `config.dat` con `pc_sat_open = true` muestran que la lista está incompleta:
  - Faltan bench_e1 y bench_combo (banco de C-091, 341.5–341.72 s, código actual).
  - Falta diag_c059 (Plan K, 345.31–345.5 s).
  - Las del 20-oct son siete, no dos: judge_fhe1_275 (275–300 s); scrfh_e1 y scrfh_e1b (280–281.6 s); scr2908_E1 y scr2908_E12 (290.8–291 s); scr291_E1 y scr291_E1b (290.9–290.95 s).

  La conclusión (ninguna corrida en 320–325 s con el código actual) sí se sostiene. Arreglo: reformular como «ninguna corrida con pc_sat_open cubre 320–325 s» y listar las corridas completas o por grupos.

### Notas de procedimiento (no son defectos)
- **N1**: ronda=0 en `status.json`. `ws-set revisor.X` y `check` usan la misma clave (`scripts/research/ledger.py:377`, `:335`). Si se cambia la ronda después de anotar los veredictos, `check` falla.
- **N2**: `report.md` está en estado AM. El texto revisado en esta ronda está sin stage, y el índice conserva el de la ronda 1. Hay que hacer `git add` antes del commit de cierre. `diff_sha` no lo detecta porque `research/` no está en GATED.

## Verificado como correcto
- Conteo de afirmaciones raíz: 15 (7 refutada, 4 fallida, 3 soportada, 1 sin_decidir). Los IDs coinciden con la tabla.
- WS-K4..K13: meta G3, aprobado, numerico=true en K4-K8. Hay 7 commits de `src/` desde 1bc9832.
- No existe `campaigns/b1/judge_combo*`; sí existe `bench_combo`. Ningún evento posterior a C-093 registra el descarte del juez de la combinación.
- D2.2 no es evaluable: `require(.not.(pc_limiter_faces .and. pc_transport_f28))` en `src/mod_config_3d.f90:606-607`.
- La cita de C-308 (filas truncadas de n14; el veredicto no cambia) es correcta.
- `fallido` exige `cierre` y tres aprueba en la ronda vigente (`ledger.py:328-335`).

## Orden sugerido
1. N2: `git add` del reporte.
2. B2: redacción.
3. N1: fijar la ronda antes de anotar los veredictos y cerrar.
