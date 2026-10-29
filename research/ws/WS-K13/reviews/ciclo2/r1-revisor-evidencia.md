## Revisión de WS-K13, ronda 1 (revisor de evidencia): rechaza

Rechazo el cierre por una sola objeción bloqueante (E1): el README que entra en el diff documenta una regla que el registro contradice en 8 eventos y que `check` no aplica. Todas las cifras del reporte se reproducen.

**Cómo lo verifiqué.** Solo lectura sobre el repositorio. Los tests de `tests/research/` los corrí sobre copias en el scratchpad, con la versión staged, la de HEAD y la de `ledger_ronda1.patch`; esos tests solo escriben en directorios temporales. No leí las revisiones de otros revisores de WS-K13.

**Tipo de cambio.** WS-K13 no es numérico (`numerico=false`, 0 archivos en `src/`, ningún evento WS-K13 en el registro). Por eso no hay criterio pre-registrado que juzgar.

### 1. Tabla

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Tests con el diff | 23/23 OK | Ran 23, OK | ok |
| Tests nuevos o ampliados frente a HEAD | 10 | 1 ampliado (test_gate) + 8 nuevos (test_ledger) + 1 nuevo (guard) = 10 | ok |
| Fallos con ledger.py y hook de HEAD | 9; nota_sobre_enmienda pasa | FAILED failures=9; nota_sobre_enmienda no falla | ok |
| Fallos con el patch de la ronda 1 | 5 (cadena, nota, refutada, resultado_que_cierra, ws_fallido) | los mismos 5 | ok (origen del patch: E3) |
| `ledger.py check` | OK (309 eventos, 13 workstreams) | idéntico | ok |
| Cambios de estado vigente HEAD → staged | solo C-169 y C-194 | C-169 enmendada→refutada, C-194 enmendada→soportada, ningún otro | ok |
| validate de `sin_decidir` sobre C-169 y C-194 | rechazado | «ya esta cerrada (refutada)» / «(soportada)» | ok |
| `open` HEAD frente a staged | diff vacío; 0 de 64; 10 cerradas sin decidir | diff vacío; 0 de 64; C-121, C-126, C-130, C-135, C-144, C-170, C-202, C-212, C-110, C-168 | ok |
| C-225 y C-181 | pre-registrada, propuesta | pre-registrada, propuesta (igual que en HEAD) | ok |
| diff_sha de WS-K12 | e3b0c442… (diff vacío) | e3b0c442…b855 en 61e4d25 | ok |
| diff_sha de WS-K13 (status.json) | 351c1e5f… | sha256 del staged de src, tests y scripts/research = 351c1e5f…8d2d | ok |
| Duración de `check` | 0.2 s | 0.22 s | ok |
| Resultados de precisión: citan veredictos, no raíces | afirmado | 0 eventos citan una raíz ya refutada o fallida | ok |
| C-057, C-079, C-085, C-089 no concluyentes | afirmado | fallida (no concluyente) por C-279, C-281, C-283, C-284 | ok |
| Citas de WS-K12 (L1, L5, L6; O8 :49; R3 :48; report.md:604; tabla del ciclo 2) | afirmado | todas existen y dicen lo citado | ok |
| Líneas de ledger.py | :164-176 … :357 | todas coinciden salvo check :277-285 (el bloque es :278-285) | E4 |
| README: una predicción juzgada no admite `sin_decidir` | regla documentada | C-296..C-303 son `sin_decidir` sobre predicciones juzgadas (en_disputa) y check las acepta | **objeción E1** |
| Ronda | «staged de la ronda 2», tabla «1 → 2» | status.json ronda=1, tres «rechaza» de la ronda 1 | E2 |

### 2. Objeciones

1. **E1 (bloqueante): el README contradice el registro y el código.**
   - El bloque «Estado vigente» de `research/README.md` dice que una predicción juzgada a través de cualquier eslabón de su cadena de enmiendas ya no admite «otra enmienda … ni `sin_decidir`».
   - `research/ledger.jsonl:C-296..C-303` contradice la parte de `sin_decidir`: 8 de los 10 cierres `sin_decidir` caen sobre predicciones con `juzgada()=True` en el momento del cierre. Ejemplo: C-170 ← C-172 ← C-174 (veredicto en_disputa) → C-301 sin_decidir.
   - `check` los acepta porque `validate` (`scripts/research/ledger.py:127`) solo bloquea cuando el estado vigente está en CERRADOS, y en_disputa no lo está.
   - El código es correcto (es la vía de cierre que usó WS-K12), pero el README, que dice «las verifica ledger.py check», documenta una regla falsa. Además va a guiar los cierres de WS-K1, WS-K2 y WS-K3.
   - Para levantarla: ninguna enmienda una vez juzgada o cerrada; ningún `sin_decidir` si el estado vigente es soportada, refutada, fallida o sin_decidir; un veredicto en_disputa sí admite `sin_decidir`. Acotar igual el punto 2 de «Cambios».
2. **E2 (no bloqueante): numeración de rondas.**
   - `research/ws/WS-K13/status.json:ronda=1` frente al reporte, que habla de «ronda 2».
   - Hay que hacer `ws-set ronda=2` (o declarar el esquema ciclo/ronda) antes de registrar los votos. Si no, se pisan los votos de la ronda 1 y el límite de 3 rondas queda mal contado.
3. **E3 (no bloqueante, no verificable): origen del patch.**
   - Nada prueba que `research/ws/WS-K13/ledger_ronda1.patch` sea el `ledger.py` de la ronda 1: el sha de la ronda 1 se sobrescribió en status.json.
   - Para levantarla: anotar el sha del diff o del patch de la ronda 1.
4. **E4 (no bloqueante): cita y procedencia.**
   - La cita del bloque `fallido` es `scripts/research/ledger.py:278-285`, no :277-285.
   - La nota de «Cambios de estado vigente» usa `$S` sin definirlo; hay que hacerla autocontenida.

VEREDICTO: rechaza