# WS-K13, ciclo 8, ronda 1: revisión de evidencia

**Resultado:** cada número del reporte se reproduce con los datos. Hay cuatro objeciones, ninguna bloqueante.

**Cómo lo verifiqué:**
- El repositorio no cambió. No hay cambios sin stage y `git status` sigue igual que al empezar.
- Copias de la herramienta (HEAD y ciclos 5, 6 y 7) en el scratchpad, con `TMPDIR` apuntando ahí y `PYTHONDONTWRITEBYTECODE=1`.
- Lo nuevo de WS-K13 no es numérico (`numerico=false` y `prediccion=null`), así que no hay criterio pre-registrado que juzgar. La regla 3 del README no aplica.

## 1. Tabla de verificación

| Afirmación | Valor del reporte | Valor recalculado | Estado |
|---|---|---|---|
| `diff_sha_gated` del staged | 221d17b0… | 221d17b00c48… | ok |
| `diff_sha` (`src`, `tests`) | e10f7514… | e10f7514a73e… | ok |
| sha de los parches del ciclo 3 | 302baba4… | 302baba47975… | ok |
| sha de los parches del ciclo 4 | d86e3085… | d86e30853 1ff… | ok |
| sha de los parches del ciclo 5 | 571806d2… | 571806d2d8fa… | ok |
| sha de los parches del ciclo 6 | b0cd7c65… | b0cd7c6585fc… | ok |
| sha de los parches del ciclo 7 | (no se cita) | f1b8e6ba… = `diff_sha_gated` del ciclo 7 | objeción E2 |
| Veredictos cuyo estado vigente difiere del suyo (HEAD / staged) | 24 / 0 | 24 / 0 | ok |
| Estados que cambian frente a HEAD | C-169 enmendada→refutada; C-194 enmendada→soportada | igual, sin más cambios | ok |
| Diff de `open` entre HEAD y staged | vacío | vacío; HEAD lee el registro real (21 líneas) | ok |
| Hipótesis del registro | 10, todas `propuesta` | Counter({'propuesta': 10}) | ok |
| Hijas de predicciones en el registro | 0 | [] | ok |
| `sin_decidir` tras `en_disputa` | 8 de 10, por ejemplo C-170 | 8 con ['en_disputa'] (C-296..C-303) y 2 con [] (C-304→C-110, C-305→C-168) | ok |
| Enmiendas del registro | 5, todas con criterio y ninguna sobre otra enmienda | 5 (C-122, C-171, C-172, C-195, C-203), todas con criterio y `ref` a predicción | ok |
| `ledger.py check` | OK, 309 eventos, 13 WS, 0.3 s | OK, 309 eventos, 13 WS, 0.22 s | ok |
| Suite `tests/research` | 42/42 OK | Ran 42, OK; mismos 42 nombres que `tests_research.txt` | ok |
| Herramienta de HEAD con los tests actuales | 28 fallan, 14 pasan | FAILED (failures=28) de 42 | ok |
| Parches del ciclo 7 con los tests actuales | 2 fallan (cadena_de_enmiendas_juzgada y nota_no_cambia…) | los mismos 2 | ok |
| Ciclo 6 «fallaban hija_no_juzga y ruta_no_ascii» | 2 | con los tests del ciclo 7: esos 2 de 41 (con los actuales: 4, los 2 de más son del ciclo 8) | ok |
| N1 del ciclo 6: HEAD con los tests del ciclo 6 | 25 de 39 | 25 de 39 | ok |
| N1 del ciclo 6: parches del ciclo 5 con los tests del ciclo 6 | 3 | 3 | ok |
| B2 del ciclo 7: los tests limpian su repo temporal | addCleanup | 0 temporales tras la suite actual; con los tests del ciclo 7 quedaron 41 | ok |
| B4: resultado refutada sobre un veredicto, aceptado e invisible | aceptado; no cambia V ni P; 0 en el registro | validate=[]; cs(V)=soportada; cs(P)=soportada; 0 | ok |
| M1 del ciclo 7: E2 sin criterio rechazada | rechazada | 'la enmienda de una prediccion trae el criterio NUEVO' | ok |
| B1 del ciclo 7: una nota no cambia una predicción enmendada | enmendada | enmendada | ok |
| M1 y B1 del ciclo 6 en el staged | hipótesis no nace cerrada; P `en_disputa` se mantiene | error «nace 'propuesta'»; en_disputa con hija hipótesis o predicción | ok |
| C-169 vía C-171→C-173, C-194 vía C-195→C-196, C-110 vía C-304, C-308→C-093, C-226→C-225, C-263→C-256, C-031→C-013, C-124→C-128 | según el texto | refs y estados coinciden en `ledger.jsonl` | ok |
| Hook :154-160, :161-167, :171-177 | según el texto | coinciden con el staged | ok |
| ledger.py :103-113, :116-126, :120, :127-152, :153-163, :199-219, :234-240, :249-251, :408 | según el texto | coinciden con el staged | ok |
| ledger.py :221-226, :291-294, :300-304, :307, :327-334, :342-343 | según el texto | en el staged son :222-227, :292-295, :301-305, :308, :328-335, :343-344 (son las líneas del ciclo 7) | objeción E1 |
| `run_tests.sh` corre `tests/research` en quick | sí | sí (diff staged) | ok |
| Veredictos de cada ciclo del panel | tabla | no verificable sin leer `reviews/` | objeción N1 |

## 2. Objeciones

1. **E1 (no bloqueante).**
   - **Ruta:** `research/ws/WS-K13/report.md`, sección «Cambios».
   - **Problema:** seis citas de línea apuntan al ledger.py del ciclo 7 y no al staged que se revisa (ciclo 8). Las correctas son:
     - `raiz_enmienda`: `:222-227`
     - hijas NO raíz: `:292-295`
     - «cerradas sin decidir»: `:301-305`
     - `cierre`: `:308`
     - `check` de `fallido`: `:328-335`
     - `GATED`: `:343-344`
   - **Inconsistencia:** las demás citas, incluida `:120`, ya son del ciclo 8, y el encabezado dice «ciclo 7».
   - **Para levantarla:** actualizar las citas al staged del ciclo 8 y corregir el encabezado.
2. **E2 (no bloqueante).**
   - **Ruta:** `research/ws/WS-K13/diff_sha_ciclos.txt`.
   - **Problema:** el archivo cubre los ciclos 1 a 7, no 1 a 6. La reproducción por sha omite el ciclo 7, que también se reproduce: f1b8e6ba… es el `diff_sha_gated` del ciclo 7.
   - **Para levantarla:** corregir el rango a «1 a 7» y añadir el ciclo 7 a la nota de procedencia.
3. **N1 (no bloqueante).** Por la revisión ciega no pude verificar la tabla de veredictos por ciclo ni las tablas de las rondas 6 y 7. Además, «Solo respondió el auditor-eaf3d» contradice en la redacción «aprueban evidencia y refutador».
   - **Para levantarla:** el coordinador lo comprueba contra `reviews/ciclo6` y `reviews/ciclo7` y aclara la frase.
4. **N2 (no bloqueante).**
   - **Ruta:** `research/ledger.jsonl`.
   - **Problema:** hay 0 eventos con ws=WS-K13, así que las afirmaciones propias del WS no tienen `{C-nnn}`. Todas tienen comando y ruta y todas se reproducen. Como el WS no es numérico, la compuerta no exige predicción.
   - **Para levantarla (opcional):** registrar un resultado de cierre con evidencia, o declarar en el reporte que el WS no registra afirmaciones.

## 3. Comparación justa

- **Mismo registro:** los conteos de HEAD y del staged se hicieron sobre los mismos 309 eventos.
- **Mismos tests:** los contrafactuales se corrieron con el mismo conjunto de tests sobre árboles limpios de HEAD con cada parche aplicado.
- **Shas:** el sha del staged se calculó sobre el índice actual (sin diferencias con el disco).

No hay ningún criterio pre-registrado en juego.

VEREDICTO: aprueba