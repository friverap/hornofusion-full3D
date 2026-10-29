El veredicto es **rechaza**, por una sola objeción bloqueante (R1). El cambio 2 cierra el hueco de la «segunda enmienda tras un veredicto» solo en el primer nivel. Con una cadena de dos enmiendas, una predicción ya refutada se puede volver a enmendar y a juzgar, y el registro lo acepta. Las demás objeciones no bloquean.

# WS-K13, ronda 1: revisor-refutador

**Alcance.** Revisé en solo lectura el diff staged (`scripts/research/ledger.py`, `.claude/hooks/guard_cierre.sh`, `tests/research/`, `research/README.md`, `CLAUDE.md`) contra `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K13/report.md` y el L1/L5 de `research/ws/WS-K12/reviews/ciclo2/r2-auditor-eaf3d.md`. Usé python solo para leer el registro y para evaluar funciones puras sobre listas sintéticas en memoria; no escribí nada en `ledger.jsonl` ni en otro archivo. No corrí make, tests ni mpirun. No leí las revisiones de los otros revisores.

## 1. Conclusiones y alternativas

| Conclusión del reporte | Mejor alternativa | Dato que las separa | Qué dicen los datos |
|---|---|---|---|
| (1) `current_state` sigue las enmiendas juzgadas, y solo cambian C-169 y C-194 | Que el cambio altere otros estados vigentes o invalide cierres históricos | Comparar `current_state` de HEAD y del diff en los 309 eventos, y correr `check` (revalida contra el prefijo) | Lo confirmé: solo C-169 (enmendada → refutada) y C-194 (enmendada → soportada). `ledger OK (309 eventos, 13 workstreams)` |
| (2) `juzgada` impide enmendar una predicción ya juzgada a través de su enmienda | Que el hueco siga abierto con una cadena de enmiendas | Caso P←E1←E2, veredicto sobre E2, luego enmienda sobre P | **Lo refuta (R1).** En memoria, `current_state(P)` da refutada, `juzgada(P)` da False, la E3 sobre P se acepta y P vuelve a «enmendada». Hoy hay 0 enmiendas de enmienda en el registro |
| (3) L1: «cerradas sin decidir» se arma por el estado vigente y sin repetir | Que la lista oculte casos o que la retomada deje rastro | Salida de `open` en HEAD y en el diff, y el test nuevo | La salida real es idéntica: las 10 mismas, C-110 una sola vez. El filtro es el que propuso el auditor |
| (4) L5: `diff_sha` y el hook cubren `scripts/research/` | Que el sha de `status.json` no corresponda al diff staged | `git diff --cached -- src tests scripts/research \| shasum -a 256` | Da 106ba79b…, igual al `diff_sha` de `status.json`. El diff ya no está vacío, así que L5 queda resuelto en lo que pedía |
| (5) El veredicto de una hija no se propaga a la madre; `open` avisa | Que la retomada mueva el problema de sitio y saque fracasos de la lista permanente | Una hija sobre una raíz refutada | **R2.** La hija se acepta y la madre pasa a pre-registrada: sale de «refutadas (permanentes)». En las raíces reales no pasa; en no-raíces sí (C-225 y C-181) |

## 2. Repeticiones de fracasos registrados

No hay. El registro no tiene afirmaciones refutadas sobre `ledger.py`, `current_state` ni `staged_sha`. El cambio no es numérico, así que las lecciones de `acople-pv.md` y Planes D/E (bancos de pocas celdas, ventanas cortas) no aplican. R1 sí es el mismo defecto que el reporte declara arreglado, solo que un nivel más abajo en la cadena de enmiendas.

## 3. Objeciones

**R1 (BLOQUEANTE): `juzgada` solo mira un nivel.**
- **El hueco.** `validate` acepta una enmienda de una enmienda (sin criterio) y también un veredicto sobre ella (el bucle while de `ledger.py:100`). Pero `juzgada` (`:176-179`) solo mira las enmiendas directas.
- **Reproducción en memoria.**
  1. Con P←E1←E2 y veredicto «refutada» sobre E2, `juzgada(P)` da False.
  2. Una enmienda E3 sobre P se acepta y P vuelve a «enmendada».
  3. A partir de ahí P se puede juzgar de nuevo.
- **Por qué importa.** Contradice la frase nueva del README («ya no admite otra enmienda»). Es la reinterpretación posterior al veredicto que el pre-registro prohíbe. `gate_errors` (`:323-325`) repite la lógica de un nivel, aunque ahí falla del lado conservador.
- **Resolución.**
  - Que `juzgada` siga la cadena de enmiendas de forma transitiva y que `gate_errors` la reutilice, o que `validate` prohíba la enmienda de una enmienda.
  - Un test con P←E1←E2, veredicto sobre E2 y luego una enmienda sobre P, que exija el rechazo.

**R2 (no bloqueante): la retomada saca refutadas de la lista permanente.**
- Una predicción hija sobre una raíz refutada se acepta, y la raíz pasa a «pre-registrada»: sale de «refutadas/fallidas (permanentes)». Es comportamiento previo al diff.
- El problema es que el README nuevo solo lo describe para las sin_decidir, y la «Incertidumbre» del reporte no lo menciona.
- En los datos reales no afecta a ninguna raíz. Sí a no-raíces: C-225 (veredicto refutada) aparece pre-registrada por C-226, y C-181 (soportada) aparece en propuesta por C-188.
- **Resolución.** Una de dos:
  - que `validate` rechace una hija sobre una raíz refutada o fallida, o que `open` liste como refutada toda raíz que haya tenido un veredicto refutado;
  - como mínimo, documentarlo en el README y en «Incertidumbre».

**R3 (no bloqueante): `fallido` no se verifica.**
- El README le da a `fallido` una semántica (unanimidad del panel y clave `cierre`) que ni `check` ni `ws-set` verifican. Ese estado se va a usar enseguida para WS-K1, WS-K2 y WS-K3.
- **Resolución.** Que `check` exija, para estado fallido, los tres «aprueba» en la ronda vigente y `cierre` no vacío, con su test. Otra opción es declarar en el README que es solo una convención.

**R4 (errata, no bloqueante): la salida de `open` es idéntica del todo.**
- No es «idéntica salvo WS-K13»: el ledger.py de HEAD también imprime WS-K13, porque lee el mismo `research/ws/`.
- **Resolución.** Corregir la frase del reporte.

## Lo verificado

- `check` pasa con 309 eventos.
- `open` da la misma salida en HEAD y en el diff.
- Solo cambian dos estados vigentes, C-169 y C-194.
- El `diff_sha` coincide con el diff staged.
- `validate` rechaza un sin_decidir sobre C-169 y sobre C-194, aunque no lo ejecuté aquí: se sigue del código (`:121`) y de los estados vigentes nuevos.
- En el registro hay 0 enmiendas de enmienda y 0 raíces refutadas reabiertas.

VEREDICTO: rechaza