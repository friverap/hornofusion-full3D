# WS-K13: pendientes de herramienta que dejó el panel de WS-K12

**Meta:** G3 (herramienta del harness). **Sin cambio numérico:** no toca
`src/` ni el simulador; toca `scripts/research/ledger.py`, el hook
`.claude/hooks/guard_cierre.sh`, sus tests (`tests/research/`),
`research/README.md` y una línea de `CLAUDE.md`.

## Origen

El auditor del panel que aprobó WS-K12 (commit 61e4d25) dejó tres BAJO: L1,
L5 y L6 (`research/ws/WS-K12/reviews/ciclo2/r2-auditor-eaf3d.md:3`). L6 (hacer
stage del `report.md` vigente) quedó resuelto en el propio 61e4d25, que incluye
la tabla «Ciclo 2, ronda 1 del panel» del reporte. Este workstream ataca L1 y
L5, y un tercer punto que NO es un BAJO del panel sino un límite que declaró el
propio reporte de WS-K12:

- **L1** (`research/ws/WS-K12/reviews/ciclo2/r2-auditor-eaf3d.md`, «BAJO»):
  `open` armaba la lista «cerradas sin decidir» con el estado PROPIO de cada
  evento `sin_decidir`, no con el estado vigente de su `ref`. Si una de esas
  afirmaciones (p. ej. {C-110}) se retoma con una predicción nueva, como manda
  el README, salía a la vez en «abiertas» y en «cerradas sin decidir»; un
  segundo `sin_decidir` la repetía en la lista.
- **L5** (mismo archivo): `staged_sha` y `guard_cierre.sh` cubrían solo
  `src/` y `tests/`. El `diff_sha` de WS-K12 fue el de un diff vacío
  (e3b0c442…): el cambio de `ledger.py` de WS-K12 no quedó atado al panel.
- **Límite de `current_state`** (`research/ws/WS-K12/report.md`, «Cambio de
  herramienta» y «Fuera de este cierre»): no seguía las enmiendas juzgadas. Por
  eso {C-169} (refutada vía {C-171} → {C-173}) y {C-194} (soportada vía
  {C-195} → {C-196}) aparecían «enmendada» y `validate` aún aceptaba un
  `sin_decidir` sobre ellas.

Dos pendientes del panel de WS-K12 que no son de herramienta quedan FUERA de
este workstream:

- **O8** (revisor-evidencia, no bloqueante,
  `research/ws/WS-K12/reviews/ciclo2/r2-revisor-evidencia.md:49`): el texto de
  la precisión P2 sobre {C-049} (`61e4d25:research/ws/WS-K12/report.md:604`, y
  el evento {C-309}) sigue diciendo «la misma lectura que B4 refuta» y no dice
  si el veredicto de {C-049} se sostiene por su letra. Es errata de texto; {C-309}
  es inmutable, así que se corrige con un evento de precisión nuevo sobre
  {C-049}, a decidir por el coordinador.
- **R3** (revisor-refutador, no bloqueante,
  `research/ws/WS-K12/reviews/ciclo2/r2-revisor-refutador.md:48`): en A4 el
  material y `elec_z_tip` quedan confundidos. Exige una corrida (girar el
  material sin permutar z_tip, o solo z_tip, con el criterio de {C-083}),
  pre-registrada; este workstream no corre nada.

## Ciclos del panel

Este reporte va por el ciclo 8. En cada ciclo se lanza de nuevo el panel y la
ronda vuelve a contar desde 1. Al lanzar, `status.json` queda con `ronda=0` y
los tres revisores en `pendiente`.

- **Dónde está cada dato.** Los `diff_sha` de los ciclos 1 a 6 están en
  `research/ws/WS-K13/diff_sha_ciclos.txt`. Cada parche es `git diff --cached
  HEAD -- <archivo>` del staged que revisó su ciclo.
- **Reproducción por sha.** Para los ciclos 3 a 6, los tres parches
  concatenados (hook, ledger y tests) reproducen un sha de
  `diff_sha_ciclos.txt`: el `diff_sha` en los ciclos 3 y 4, y el sha sobre
  todas las rutas de `GATED` en los ciclos 5 y 6 (su `diff_sha` usó la
  fórmula de HEAD, solo `src` y `tests`; en el ciclo 6 es el
  `diff_sha_gated`). Para los ciclos 1 y 2 no se guardaron los tests, así que
  no se pueden reproducir.
  > [fuente: D=research/ws/WS-K13; cat $D/hook_ciclo3.patch $D/ledger_ciclo3.patch $D/tests_ciclo3.patch | shasum -a 256 (302baba4…); cat $D/hook_ciclo4.patch $D/ledger_ciclo4.patch $D/tests_ciclo4.patch | shasum -a 256 (d86e3085…); cat $D/hook_ciclo5.patch $D/ledger_ciclo5.patch $D/tests_ciclo5.patch | shasum -a 256 (571806d2…); cat $D/hook_ciclo6.patch $D/ledger_ciclo6.patch $D/tests_ciclo6.patch | shasum -a 256 (b0cd7c65…)]

| Ciclo | Revisiones | Parches |
|---|---|---|
| 1 | `reviews/ciclo1/`: rechazan los tres | `ledger_ciclo1.patch` |
| 2 | `reviews/ciclo2/`: rechazan los tres | `ledger_ciclo2.patch`, `hook_ciclo2.patch` |
| 3 | `reviews/ciclo3/`: rechazan los tres | `{ledger,hook,tests}_ciclo3.patch` |
| 4 | `reviews/ciclo4/`: aprueba evidencia | `{ledger,hook,tests}_ciclo4.patch` |
| 5 | `reviews/ciclo5/`: rechazan los tres | `{ledger,hook,tests}_ciclo5.patch` |
| 6 | `reviews/ciclo6/`: aprueban evidencia y refutador; rechaza el auditor | `{ledger,hook,tests}_ciclo6.patch` |
| 7 | `reviews/ciclo7/`: aprueban evidencia y refutador; rechaza el auditor | `{ledger,hook,tests}_ciclo7.patch` |
| 8 | este ciclo | el diff staged, con `diff_sha_gated` en `status.json` |

Lo que atendió cada ciclo:

- **1:** la cadena de enmiendas, la nota que juzgaba una enmienda, las hijas
  de una refutada y `fallido` sin verificar.
- **2:**
  - la cadena no lineal;
  - el segundo veredicto;
  - las notas que reabrían refutadas;
  - `sin_decidir` tras un veredicto de cierre;
  - los veredictos que cambiaban por notas;
  - el hook fuera de `diff_sha`.
- **3:**
  - el juicio que contaba en la posición de la enmienda;
  - el segundo juicio por `resultado`;
  - las refutadas alcanzadas a través de una enmienda;
  - las retomas vía veredicto;
  - `settings.json` y `agents/` fuera de la compuerta;
  - el hook que leía el `ledger.py` del disco.
- **4:**
  - el `ledger.py` staged que se certificaba a sí mismo;
  - el nuevo juicio de una predicción cerrada sin veredicto;
  - la compuerta apagada al borrar la herramienta;
  - el respaldo al disco;
  - la nota que reabría una `sin_decidir`;
  - el resultado de cierre sobre una enmienda.
- **5:**
  - **M1:** el `git mv` hacia fuera apagaba la compuerta.
  - **O1, M2 y E1:** el commit de arranque no ataba con un sha el cambio de
    la herramienta.
  - **O2 y B1:** las precisiones sobre un cierre `sin_decidir` no tenían
    camino.
  - **O3 y B2:** la retoma de una predicción `sin_decidir`.
  - **O5:** las enmiendas de hipótesis.
  - **O6 y B3:** una nota que cambiaba un veredicto `en_disputa`.
  - **O4 y B4:** un hook que se certifica a sí mismo (declarado como límite).
  - **B5:** `test-quick` no corría `tests/research`.
  - **E2 y E3:** erratas.
- **6:** M1 y B1 (las hijas de una predicción), B5 (rutas no ASCII) y B6 (log
  ignorado), arreglados; B2–B4, declarados en «Incertidumbre».
- **7:** M1 (criterio en las enmiendas encadenadas), B1 (una nota cambiaba
  una predicción enmendada) y B2 (repos temporales de los tests), arreglados.

## Cambios

En `scripts/research/ledger.py` (líneas del `ledger.py` staged del ciclo 7):

1. **Estado vigente.** `current_state` (`:199-219`) usa `cadena_enmiendas`
   (`:234-240`).
   - Recorre el registro en orden y se queda con lo último que aplique, cada
     cosa en su posición: un evento con `--ref` a la afirmación (una
     enmienda la deja «enmendada») o un veredicto sobre una enmienda de su
     cadena.
   - Un veredicto conserva su propio estado. Con HEAD, 24 veredictos tenían
     un estado vigente distinto del suyo; ahora ninguno.
   > [fuente: S=$(mktemp -d); git show HEAD:scripts/research/ledger.py > $S/lh.py; python3 -c "import sys,importlib.util; sys.path.insert(0,'scripts/research'); import ledger as N; s=importlib.util.spec_from_file_location('O','$S/lh.py'); O=importlib.util.module_from_spec(s); s.loader.exec_module(O); ev=N.load(); f=lambda M: sum(1 for e in ev if e['tipo']=='veredicto' and M.current_state(e['id'],ev)!=e['estado']); print(f(O), f(N))" (24 0)]
2. **Cadena lineal y un solo veredicto** (`:103-113`). La enmienda y el
   veredicto van siempre sobre la ÚLTIMA enmienda, y cada predicción admite
   un solo veredicto en toda su cadena. `juzgada` (`:249-251`) se reutiliza
   en `gate_errors` (`:408`).
   - **Hijas de una predicción (M1 y B1 del ciclo 6, arreglados en el ciclo
     7).** Una hipótesis nace `propuesta` (`validate`), así que no puede
     llegar con un estado de cierre. Además, en `current_state`, una hija
     (predicción o hipótesis) con `--ref` a una PREDICCIÓN no cambia su estado
     vigente: P con veredicto `en_disputa` sigue `en_disputa` aunque se le
     cuelgue una hija (`test_hija_no_juzga_a_una_prediccion`). En el registro
     real hay 0 hijas de predicciones y las 10 hipótesis son `propuesta`.
     > [fuente: python3 -c "import sys,collections; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); ids={e['id']:e for e in ev}; print(collections.Counter(e['estado'] for e in ev if e['tipo']=='hipotesis'), [e['id'] for e in ev if e['tipo'] in ('prediccion','hipotesis') and ids.get(e.get('ref'),{}).get('tipo')=='prediccion'])" (Counter({'propuesta': 10}) [])]
3. **Enmiendas** (`:116-126`). Solo cambian el criterio de una PREDICCIÓN
   (O5). Una afirmación ya juzgada o cerrada no admite enmiendas.
   - **Criterio en las enmiendas encadenadas (M1 del ciclo 7, arreglado en
     el ciclo 8).** El criterio NUEVO se exige cuando la raíz de la cadena
     es una predicción, sea la `ref` la predicción o su última enmienda
     (`raiz_enmienda`, `:120`). `test_cadena_de_enmiendas_juzgada` exige
     ahora el rechazo de E2 sin `--criterio`. En el registro real las 5
     enmiendas traen criterio y ninguna cita otra enmienda.
4. **Qué puede citar a una afirmación cerrada** (`:127-152`). La regla mira
   la RAÍZ de la cadena de `--ref` (`raiz_enmienda`, `:221-226`).
   - **Refutadas y fallidas** son absorbentes: nada las cita a ellas ni a sus
     enmiendas.
   - **Una predicción cerrada** (con veredicto de cierre o estado vigente
     cerrado) es definitiva: nada la cita, ni siquiera otro veredicto.
   - **Una hipótesis o un resultado `sin_decidir`** solo admite una
     predicción hija: la retoma.
   - **Un `resultado` sobre una predicción** solo puede ser una nota o un
     cierre `sin_decidir`. Si la predicción ya tiene veredicto, aunque sea
     `en_disputa`, la nota va al veredicto (O6/B3).
   - **Un CIERRE** es un `resultado` refutada, fallida o `sin_decidir` con
     `--ref` (`:127-133`). Es el sitio de las precisiones y retomas: admite
     una nota o una predicción/hipótesis hija, nada más, y no reabre lo que
     cierra (O2/B1). Así se precisa o se retoma una predicción definitiva
     (vía C-296) o un resultado `sin_decidir` sin veredicto, como {C-110}
     vía C-304. Los resultados soportados no son cierres: siguen admitiendo
     su cadena de resultados (C-124 → C-128 …).
5. **`sin_decidir`** (`:153-163`). No cabe sobre una afirmación cerrada ni
   tras un veredicto de cierre. Tras un veredicto `en_disputa` sí cabe; así
   se cerraron 8 de las 10, por ejemplo {C-170}.
   > [fuente: python3 -c "import sys; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); [print(e['ref'], [v['estado'] for v in L.veredictos(e['ref'], ev[:i])]) for i,e in enumerate(ev) if e.get('estado')=='sin_decidir']" (8 con ['en_disputa'], 2 con [])]
6. **`open`.**
   - Lista las predicciones e hipótesis NO raíz abiertas (`:291-294`).
   - «Cerradas sin decidir» (`:300-304`) se calcula por estado vigente. Una
     predicción `sin_decidir` retomada vía su cierre sigue en esa lista,
     porque es definitiva, y su retoma sale como hija abierta (O3/B2; el
     README lo explica).
   - Avisa «hija juzgada» (`:287-289`) y muestra la clave `cierre` (`:307`).
7. **`check`** (`:327-334`). Un workstream `fallido` sin `cierre`, o sin los
   tres «aprueba» de su ronda, da error.
8. **`GATED`** (`:342-343`). Cubre `src`, `tests`, `scripts/research`,
   `.claude/hooks`, `.claude/workflows`, `.claude/agents` y
   `.claude/settings.json`.

En `.claude/hooks/guard_cierre.sh`:

- La lista de rutas vigiladas usa `git diff --cached --name-only
  --no-renames -z` (`:161-167`). Un `git mv` de una ruta vigilada lista la ruta
  vieja y la nueva (M1 del ciclo 5).
- La compuerta la decide el `ledger.py` de HEAD. Si HEAD no lo tiene, usa el
  del índice; si tampoco, el del disco (`:154-160`, `:171-177`). Así, ni un
  `ledger.py` permisivo, ni su borrado, ni su renombre apagan la compuerta.

**`tests/run_tests.sh`.** `make test-quick` corre ahora
`tests/research` (B5).

**Commit de arranque (este).** La compuerta de HEAD calcula `diff_sha` solo
sobre `src` y `tests`, así que el `diff_sha` y el `test_quick` de WS-K13 se
fijan con el `ledger.py` de HEAD (O1/M2/E1).
- Para atar el resto, `status.json` lleva `diff_sha_gated`: el sha256 de
  `git diff --cached` sobre TODAS las rutas de `GATED` (ledger, hook, tests,
  `run_tests.sh`).
- Justo antes del commit, el coordinador comprueba que el staged lo
  reproduce, y anota la salida en el mensaje del commit.
- README y CLAUDE.md quedan fuera de `GATED`, como antes; sus cambios están
  en el diff que revisa el panel.
> [fuente: git diff --cached -- src tests scripts/research .claude/hooks .claude/workflows .claude/agents .claude/settings.json | shasum -a 256 (= diff_sha_gated de research/ws/WS-K13/status.json); git diff --cached -- src tests | shasum -a 256 (= diff_sha)]

**Decisión que NO cambia:** el veredicto de una hija no se propaga a la madre
(regla de WS-K12); `open` lo avisa.

## Evidencia

- **Tests.** Pasan los 42 de 42. Con la herramienta de HEAD fallan 28 y pasan
  14. Con los parches del ciclo 7 fallan 2:
  - `test_cadena_de_enmiendas_juzgada`: M1 del ciclo 7, E2 sin criterio.
  - `test_nota_no_cambia_a_una_prediccion_enmendada`: B1 del ciclo 7.

  Con los parches del ciclo 6 fallaban `test_hija_no_juzga_a_una_prediccion`
  y `test_ruta_no_ascii_deny`.

  La salida completa de la suite está en
  `research/ws/WS-K13/tests_research.txt`. Está versionada; el `.log` del
  ciclo 6 lo ignoraba `.gitignore` (B6).
  > [fuente: python3 -m unittest discover -s tests/research -v 2> research/ws/WS-K13/tests_research.txt (Ran 42, OK)]
  > [fuente: T=$(mktemp -d); mkdir -p $T/scripts/research $T/tests/research $T/.claude/hooks; git show HEAD:scripts/research/ledger.py > $T/scripts/research/ledger.py; git show HEAD:.claude/hooks/guard_cierre.sh > $T/.claude/hooks/guard_cierre.sh; cp tests/research/test_*.py $T/tests/research/; (cd $T && python3 -m unittest discover -s tests/research) (FAILED failures=28)]
  > [fuente: el mismo comando más patch -s -p1 -d $T < research/ws/WS-K13/ledger_ciclo7.patch; patch -s -p1 -d $T < research/ws/WS-K13/hook_ciclo7.patch (FAILED failures=2, los 2 citados)]
- **Registro real.** `ledger.py check` pasa sobre los 309 eventos y revalida
  cada uno con todas las reglas nuevas.
  > [fuente: time python3 scripts/research/ledger.py check (ledger OK (309 eventos, 13 workstreams); 0.3 s)]
- **Estados que cambian frente a HEAD.** Aparte de los veredictos (punto 1),
  solo cambian {C-169} (enmendada → refutada) y {C-194} (enmendada →
  soportada). `ledger.py open` da la misma salida que con HEAD: el diff
  sale vacío.
  > [fuente: S=$(mktemp -d); git show HEAD:scripts/research/ledger.py > $S/lh.py; python3 -c "import sys,importlib.util; sys.path.insert(0,'scripts/research'); import ledger as N; s=importlib.util.spec_from_file_location('O','$S/lh.py'); O=importlib.util.module_from_spec(s); s.loader.exec_module(O); ev=N.load(); print([(e['id'],O.current_state(e['id'],ev),N.current_state(e['id'],ev)) for e in ev if e['tipo']!='veredicto' and O.current_state(e['id'],ev)!=N.current_state(e['id'],ev)])"; diff <(python3 $S/lh.py open) <(python3 scripts/research/ledger.py open) (vacío)]

## Incertidumbre

- **El hook se certifica a sí mismo** (O4/B4 del ciclo 5). Claude Code
  ejecuta el `guard_cierre.sh` del DISCO, así que un hook debilitado decide
  su propio commit. Hacer que `settings.json` ejecute la versión de HEAD
  cambiaría cómo se cargan todos los hooks, y queda fuera de este WS. El
  README lo declara.
- **Commit de arranque.** El `diff_sha_gated` lo comprueba el coordinador a
  mano, no la compuerta. Cada cambio futuro de la compuerta pasará por el
  mismo procedimiento.
- **Compuerta numérica con un veredicto `en_disputa`** (B2 del ciclo 4). Es
  anterior a este WS y requiere una decisión de política que este WS no
  toma.
- **Hipótesis y resultados soportados** pueden reabrirse o refutarse (C-031 →
  C-013). Es deliberado.
- **Fuera de la compuerta.** Quedan fuera `.claude/rules/`, `.claude/skills/`
  y, del bloqueo, `tests/research/`. El escape `# cierre-sin-compuerta`
  sigue disponible con autorización del usuario.
- **Ciclo 6: arreglados en el ciclo 7.**
  - **M1** (hipótesis que nacía con estado de cierre) y **B1** (una hija
    cambiaba el estado de una predicción `en_disputa`): ver el punto 2 de
    «Cambios».
  - **B5** (rutas no ASCII): el hook usa `--name-only --no-renames -z`.
- **Ciclo 6: declarados, anteriores a este WS o fuera de su alcance.**
  - **B2:** WS-K11 y WS-K12 están `aprobado` con el sha del diff vacío
    (e3b0c442…), porque sus diffs no tocaban `src` ni `tests`, y
    `gate_errors` no lo rechaza. Para el resto del registro es inocuo: un
    diff vacío no abre ningún commit vigilado. Además, el hook y `GATED`
    mantienen dos listas de rutas a mano y hay que cambiarlas juntas.
  - **B3:** el escape registra su evento con el `ledger.py` del disco y sin
    mirar el código de salida.
  - **B4:** un `resultado` refutada o fallida con `--ref` a un VEREDICTO se
    acepta. No cambia el estado del veredicto ni el de la predicción (un
    veredicto conserva su estado) y no sale en `open`. En el registro real
    no hay ninguno.
- **Ciclo 7, arreglados en el ciclo 8.**
  - **M1:** criterio en las enmiendas encadenadas (punto 3 de «Cambios»).
  - **B1:** una nota (`resultado` propuesta) con `--ref` a una PREDICCIÓN ya
    no cambia su estado vigente. `current_state` la ignora, igual que a una
    hija (`test_nota_no_cambia_a_una_prediccion_enmendada`). Sigue sin
    aceptarse una nota directa sobre una predicción con veredicto (punto 4).
  - **B2:** los `setUp` de `tests/research` borran su repo temporal con
    `addCleanup(shutil.rmtree, ...)`.
- **Coste.** Las reglas son O(n²) por llamada. `check` tarda 0.3 s con 309
  eventos.

## Ciclo 6, ronda 1 del panel

Solo respondió el auditor-eaf3d. Los escenarios de M1, B1 y B4 los reproduje
en memoria con `validate` y `current_state` del `ledger.py` staged; los
conteos de N1, en copias temporales.
> [fuente: P prediccion; (A) hipotesis refutada --ref P: validate sin error de regla, current_state(P)='refutada', veredicto posterior rechazado 'esta refutada (permanente)'; (B) P + veredicto en_disputa + hipotesis soportada --ref P: aceptada, current_state(P)='soportada', sin_decidir posterior rechazado; (B1) P + veredicto en_disputa + prediccion --ref P: current_state(P)='pre-registrada'; (B4) P + veredicto soportada + resultado refutada --ref V: aceptado]
> [fuente: python3 -c "...import ledger as L; ev=L.load(); print(Counter(e['estado'] for e in ev if e['tipo']=='hipotesis'))" ({'propuesta': 10})]
> [fuente: research/ws/WS-K11/status.json y research/ws/WS-K12/status.json: estado aprobado, diff_sha e3b0c44298fc…]

| Id | Objeción | Respuesta |
|---|---|---|
| M1 (bloq.) | `hipotesis` con estado de cierre juzga una predicción sin veredicto | Confirmada. Exige cambiar `validate` (que la hipótesis nazca `propuesta`; las 10 del registro lo son) y un test con A y B. Requiere coordinador. Anotada en el punto 2 y en Incertidumbre. |
| B1 | Hija de una predicción `en_disputa` le devuelve `pre-registrada` | Confirmada. Requiere coordinador (mismo arreglo que M1, o declararla límite). En Incertidumbre. |
| B2 | Aprobaciones con el sha del diff vacío abren la compuerta | Confirmado el estado (WS-K11, WS-K12). Exige cambiar `gate_errors` y el hook. Requiere coordinador. En Incertidumbre. |
| B3 | El escape usa el `ledger.py` del disco y no mira el returncode | Confirmada por lectura (`guard_cierre.sh:181`). Requiere coordinador. En Incertidumbre. |
| B4 | `resultado` refutada o fallida sobre un veredicto, invisible | Confirmada. Requiere coordinador. En Incertidumbre. |
| B5 | `.split()` no ve rutas entrecomilladas | Confirmada por lectura. Requiere coordinador (`-z`). En Incertidumbre. |
| B6 | Log ignorado y ciclo 5 omitido | Corregido el texto: el ciclo 5 se reproduce (571806d2…) y el log se declara fuera del staged. Falta que el coordinador lo versione. |
| N1 | Conteos contrafactuales sin verificar | Vueltos a correr: HEAD da `FAILED (failures=25)` de 39; ciclo 5 da `FAILED (failures=3)` con los tres tests citados. |

## Ciclo 7, ronda 1 del panel

Solo respondió el auditor-eaf3d. M1 y B1 los reproduje en memoria con
`validate` y `current_state` del `ledger.py` staged; los conteos del registro,
con `L.load()`; el sha del ciclo 6, concatenando sus tres parches.

| Id | Objeción | Respuesta |
|---|---|---|
| M1 (bloq.) | Enmienda encadenada sin `--criterio` aceptada; el test la fija | Confirmada. Exige cambiar `ledger.py:120` (mirar la raíz) y `test_cadena_de_enmiendas_juzgada` (criterio en E2 y un caso negativo). Requiere coordinador. Anotada en el punto 3 de «Cambios» y en «Incertidumbre». |
| B1 | Una nota sobre una predicción sin juzgar le pone `propuesta` | Confirmada (anterior a WS-K13; 0 casos en el registro). Exige cambiar `current_state` o el README. Requiere coordinador. En «Incertidumbre». |
| B2 | `mkdtemp()` sin limpieza en `tests/research` | Confirmada por lectura. Exige cambiar los tests. Requiere coordinador. En «Incertidumbre». |
| B3 | Líneas del ciclo 6 y ciclo 6 omitido en la reproducción por sha | Corregido: citas de `ledger.py` y del hook actualizadas al staged del ciclo 7; el ciclo 6 se reproduce (b0cd7c65…, el `diff_sha_gated` del ciclo 6). |
