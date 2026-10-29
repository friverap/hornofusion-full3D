## Revisión del refutador: WS-K13, ciclo 7, ronda 1

**Alcance.** WS-K13 es solo de herramienta (G3): no cambia `src/` ni la numérica. Las preguntas de banco frente a B1 y de ventana corta no aplican. Aquí el «sitio que importa» son dos: el registro real (309 eventos) y la ruta real de commit (el hook).

**Qué verifiqué (solo lectura).** El diff staged de `ledger.py`, el hook, `run_tests.sh`, el README y CLAUDE.md. Además:
- `ledger.py open`: 0 abiertas y 10 cerradas sin decidir. `ledger.py check`: OK con 309 eventos.
- El estado vigente de C-168..C-196. C-169 queda refutada vía C-171 y C-173; C-194 queda soportada vía C-195 y C-196.
- Los dos sha (`f1b8e6ba…` = `diff_sha_gated`; `e9e5211c…` = `diff_sha`). No hay cambios sin stage en archivos versionados, así que disco = índice.
- Una sonda en memoria con `validate`/`current_state` del staged, sin escribir nada (6 escenarios).
- Los tests de L1, de la hija y de rutas no ASCII, leídos.

### 1. Conclusiones, alternativas y el dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| L1: «cerradas sin decidir» usa el estado vigente | El `open` real sale idéntico porque las ramas nuevas nunca se ejecutan en el registro real; el arreglo no se probaría | Que el test de L1 falle con HEAD | Sí, por lectura. `test_open_sin_decidir_por_estado_vigente` hace `assertNotIn("cerradas sin decidir")` tras la retoma. HEAD arma `sind` con todos los eventos `sin_decidir`, así que falla. Discrimina. |
| `current_state` sigue las enmiendas juzgadas; solo cambian C-169 y C-194 | «24 → 0 veredictos» es tautológico: el veredicto devuelve su propio estado por construcción | Que ningún consumidor de `current_state(veredicto)` cambie de decisión | Sí. `check` pasa, `open` es idéntico, y la regla de cosas permanentes mira la raíz, no el veredicto. Las 41 citas a veredictos son la práctica del registro (31 propuesta, 8 soportada, 2 en_disputa). Sin efecto colateral. |
| M1/B1 del ciclo 6 arreglados | Los tests pasan con aserciones débiles | Contrafactual con los parches del ciclo 6 | Lo declara el reporte (fallan exactamente 2). Por lectura, `test_hija_no_juzga_a_una_prediccion` solo pasa si P sigue `en_disputa`. Sonda E: una hipótesis hija refutada no cambia P (`pre-registrada`). |
| B5: rutas no ASCII | — | `-z` frente a `quotepath` | Sí: el test usa `src/año.f90`. Sin `-z` la ruta sale entrecomillada y no empieza por `src/`. |
| L5: `diff_sha` ata la herramienta; la decide el `ledger.py` de HEAD | HEAD puede cambiar sin compuerta, así que «HEAD = aprobada» es falso | Cobertura del hook sobre los comandos que crean commits | Sí, y en contra en parte: ver R1 (`guard_cierre.sh:57`; rama `choi-intento` con un commit de `src/` fuera de HEAD). |
| Las reglas nuevas no rompen el flujo real | Las skills y los workflows mandan registrar patrones que ahora se rechazan | grep de `--ref`/`--estado` en skills, workflows y agents | Solo `preregistro` queda desfasada (R3). `auditoria-dirigida` registra resultado propuesta → resultado soportada, que sigue permitido. |

**¿Mueve el problema de sitio?** Muy poco. La duplicación de C-110 que señalaba L1 desaparece. Pero en la ruta vía cierre, la misma pregunta figura como cerrada (la madre) y como abierta (su retoma) a la vez; con la ruta directa no pasa (R2). El costo sube a O(n²), con 0.3 s declarados.

### 2. Repeticiones de fracasos registrados

No hay. El cambio no es numérico, así que no aplica nada de «Lo que NO funcionó» de `acople-pv.md` ni de los `PLAN_D..K` (limitador en el Poisson, D2.2, reglas D/E/F/G, `n_pc_max`). En el registro no hay afirmaciones refutadas sobre la herramienta (busqué ledger.py, compuerta, hook y `current_state`). Dentro del propio WS, el ciclo 7 no reintroduce lo que rechazaron los ciclos 1 a 6: la herramienta del staged ya no se certifica a sí misma, y borrarla o renombrarla está cubierto con tests. El hook que se certifica a sí mismo sigue declarado como límite.

### 3. Objeciones

- **R1 (no bloqueante).** El hook solo cubre comandos con «commit»; merge, cherry-pick, revert, rebase y am cambian HEAD sin compuerta. Eso debilita la premisa «el `ledger.py` de HEAD es la herramienta aprobada», que este WS introduce. La rama `choi-intento` tiene un commit de `src/` fuera de HEAD. **Lo resuelve:** un test de deny para merge o cherry-pick, o declararlo en «Incertidumbre» y en el «Límite» del README.
- **R2 (no bloqueante).** Hay dos rutas de retoma para una hipótesis o un resultado `sin_decidir`, y `open` las lista distinto. El ejemplo del README (C-110 vía C-304) es justo la ruta que no reabre. **Lo resuelve:** fijar en el README cuál es la ruta canónica, o que `open` marque «retomada vía C-nnn».
- **R3 (no bloqueante).** La skill `preregistro` sigue mandando la enmienda y el veredicto con `--ref` a la predicción, contra la cadena lineal. Falla cerrada. **Lo resuelve:** actualizar la línea o declararlo.

Ninguna objeción invalida las conclusiones del reporte dentro de su alcance (L1, L5, el límite de `current_state` y M1, B1, B5 y B6 del ciclo 6). Las tres son de alcance o de documentación, no de corrección.

VEREDICTO: aprueba