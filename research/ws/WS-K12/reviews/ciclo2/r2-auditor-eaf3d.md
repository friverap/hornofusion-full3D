# WS-K12, ciclo 2, ronda 2: auditor-eaf3d

**Veredicto: aprueba.** No hay hallazgos ALTO ni MEDIO. Quedan dos BAJO de la ronda anterior (L1 y L5) y uno nuevo de proceso (L6), ninguno bloqueante.

Alcance de la revisión: el diff staged de `scripts/research/ledger.py`, `research/README.md` y `research/ws/WS-K12/status.json`, contra la versión de `research/ws/WS-K12/report.md` que está en el árbol de trabajo (18:11). Todo se hizo en modo de solo lectura y sin escribir en `research/ledger.jsonl`. No había ninguna corrida de `eaf3d` activa (`ps` vacío).

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**L1 (sigue abierta; el código no cambió).** `scripts/research/ledger.py:207-209` arma «cerradas sin decidir» con el estado propio de cada evento, no con `current_state` de la ref.
- **Cómo falla (reproducido en memoria).** Se registra `sin_decidir` con ref C-110 y después una predicción nueva con `--ref C-110`, que es la forma que da el README para retomar la pregunta. Entonces `open` muestra C-110 en «afirmaciones abiertas» (pre-registrada) y también en «cerradas sin decidir: 1: C-110». Un segundo `sin_decidir` se acepta y C-110 aparece dos veces en esa lista.
- **Alcance.** Solo afecta la salida de `open`.
- **Arreglo.** Filtrar con `current_state(x['ref'], ev) == 'sin_decidir'` y sin repetir refs.

**L5 (anterior a este diff; sigue igual).** `staged_sha` (`ledger.py:237-240`) y `guard_cierre.sh` cubren solo `src/` y `tests/`.
- El `diff_sha` de status.json es e3b0c442…, que es el sha256 de un diff vacío. El cambio de la herramienta del registro no queda atado al panel.
- status.json sigue con `ronda: 0` y con los veredictos del ciclo 1.
- **Arreglo.** Pendiente del coordinador.

**L6 (nueva, de proceso).** El `report.md` staged (2b2397b) es una versión anterior.
- Le faltan:
  - P2;
  - el `--ruta`/`--cmd` de A6;
  - la regla del grupo B con los logs de WS-K9;
  - la simulación en línea;
  - la tabla «Ciclo 2, ronda 1».
- **Cómo falla.** `guard_cierre` prohíbe `commit -a`. Un `git commit` hecho tal como está guardaría un reporte distinto del aprobado, mientras que los eventos se registrarían desde el texto del árbol.
- **Arreglo.** `git add research/ws/WS-K12/report.md` (y el status.json final) antes del commit.

### Objeciones de la ronda 1 que quedan resueltas

- **L2.** Ahora «Fuera de este cierre» deja como único pendiente de la herramienta la limitación de `current_state` (C-169 y C-194).
- **L3.** La simulación va en el reporte y se puede reproducir desde el repo. La corrí: 31 eventos (C-279 a C-309), todos aceptados, y 0 abiertas de 64.
- **L4.** El reporte ya apoya la reproducción en las cifras y no solo en el código de salida. Con `--run`, B4 imprime 181/181/12/12/7/2 snapshots (395 en total) con 0 diferencias, y las filas 345250-345283 salen 5.865e5, 3.491e5, 3.279e5 y 3.082e5. El bucle de B4 sigue sin `set -e`, pero eso es cosmético.

## Lo verificado como correcto (no hace falta volver a auditarlo)

- **ESTADOS, CERRADOS y veredictos** (`ledger.py:27-33`).
  - `sin_decidir` está en ESTADOS y en CERRADOS.
  - `ESTADOS_VEREDICTO` conserva los cuatro estados de antes, así que un veredicto con `sin_decidir` se rechaza (comprobado).
  - En HEAD, `CERRADOS` estaba en `:28` y `current_state` en `:144-150`. Las citas del reporte son correctas.
- **`validate` en `:114-122`** (probado en memoria sobre el registro real):
  - se rechaza una ref inexistente (C-999);
  - se rechazan las refs a un veredicto (C-061) y a una enmienda (C-122);
  - se rechaza una ref ya cerrada (C-001 soportada);
  - se rechaza `sin_decidir` en un veredicto;
  - C-169 y C-194 pasan, como dice el reporte, porque `current_state` no sigue enmiendas.
- **`check` sigue igual.** Revalida cada evento contra los anteriores, así que los cierres históricos no se invalidan con eventos posteriores. `ledger check` da OK con 278 eventos.
- **Otros consumidores.** Ningún otro script lee `CERRADOS` ni los estados: `workstream.js`, los hooks y los skills solo llaman a `open`/`check`. `estado_sesion.sh` hace `open | head -14`, y la línea nueva no le cambia nada importante.
- **README.** Es coherente con el código: el alcance de `sin_decidir`, que solo lo puede llevar un `resultado` con ref, y cómo se consulta.
- **Simulación del cierre** con el texto actual: 31 eventos aceptados; los 10 refs del grupo E están en estado no cerrado antes del cierre; quedan 0 abiertas de 64.
- **`--run`.** Los `--cmd` de A1, A2, A4-A6, B1-B5, P1 y P2 terminan en 0 y reproducen las cifras del texto. Algunos ejemplos:
  - A2: 61.3 / 69.2 / 81.0 %;
  - A4: 18 (1,19,9) y 3 (1,20,9);
  - B2: 60 y `{'cold_flow_noenergy_n4'}`;
  - B3: 22/19;
  - B5: de 0.521 a 0.682, último 0.639;
  - P1: 2.001e5 → 1.240e5 y 1.474e5 → 1.455e5;
  - P2: min p = −2.0e6 desde 345311.

  Ninguno de esos comandos escribe archivos (`check_audit.py` no tiene ningún `open(...,'w')`).

## Orden sugerido de corrección (uno por uno)

1. L6: hacer stage del `report.md` vigente y del status.json final antes del commit.
2. L1: filtrar «cerradas sin decidir» por estado vigente.
3. L5: decidir si `scripts/research` entra en la compuerta (pendiente del coordinador, fuera de este WS).
