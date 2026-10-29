# Revisión WS-K13, ronda 1: auditor-eaf3d

**Veredicto: RECHAZA.** Hay 1 hallazgo MEDIO sin resolver (M1).

Alcance: diff staged (`git diff --cached`) de `scripts/research/ledger.py`, `.claude/hooks/guard_cierre.sh`, `tests/research/*`, `research/README.md` y `CLAUDE.md`. No toca `src/`, así que el diff no cambia la numérica ni el MPI. Solo leí: no corrí `unittest`, `make` ni binarios. Reproduje en memoria (Python, sin escribir nada) las funciones del ledger.py staged y las de HEAD.

## Hallazgos

### MEDIO

**M1. `juzgada()` no es transitiva, pero `current_state()` sí. Una predicción refutada se puede reabrir.** Ubicación: `scripts/research/ledger.py:176-179` y `:112`.
- **Defecto:** `juzgada(pid)` solo busca veredictos sobre `pid` o sobre enmiendas que citan directamente a `pid`. En cambio, `current_state` recorre la cadena de enmiendas entera, y `validate` del veredicto (`:99-103`) acepta cadenas enmienda→enmienda de forma explícita.
- **Escenario (reproducido):** P → E1 (enmienda de P) → E2 (enmienda de E1) → V refutada con ref E2.
  - `current_state(P)='refutada'`, pero `juzgada(P)=False`.
  - Una enmienda E3 con ref P se acepta (`validate` → `[]`). P pasa a `enmendada` y vuelve a abiertas.
  - Después, `resultado sin_decidir` con ref P también se acepta.
  - Esto contradice el texto nuevo de `research/README.md:44-46`: «ya no admite otra enmienda ni `sin_decidir`».
- **Caso hermano:** con un veredicto directo sobre P, una enmienda con ref E1 se acepta, porque `:112` evalúa `juzgada(E1)` y no sube a P.
- **Ruta plausible:** la skill `/preregistro` documenta `enmienda <C-nnn>`, y ese C-nnn puede ser la última enmienda. El registro real no tiene ninguna cadena de 2 niveles (las 5 enmiendas, C-122, C-171, C-172, C-195 y C-203, citan predicciones), así que hoy el defecto está latente.
- **Arreglo:**
  - `juzgada` debe usar el cierre transitivo de enmiendas.
  - En `validate` de enmienda, subir primero a la predicción raíz (mismo bucle que `:99-101`) y llamar `juzgada(raiz)`.
  - Reusar `juzgada` en `gate_errors` (`:322-326`), que tiene la misma lógica de un nivel.
  - Agregar un test con la cadena P→E1→E2→V.

### BAJO

**B1. Asimetría entre `current_state` y `juzgada`.** Ubicación: `ledger.py:170`.
- **Defecto:** para `current_state`, cualquier evento que cite la enmienda cuenta como «juicio»; para `juzgada`, solo los veredictos.
- **Escenario (reproducido):** con P → E1 → `resultado propuesta` con ref E1, P se muestra como `propuesta` en vez de `enmendada`. Si ese resultado es `soportada` con evidencia, P queda cerrada sin veredicto y aun así admite una enmienda nueva, que la reabre.
- La variante directa sobre P ya existía en HEAD.
- **Arreglo:** contar como juicio solo veredictos y sub-enmiendas, o unificar ambas funciones en un helper.

**B2. El aviso «hija juzgada» solo ve hijas directas.** Ubicación: `ledger.py:216-218`.
- **Defecto:** una predicción que cita un resultado intermedio de la madre no genera aviso.
- Además, ya pasaba en HEAD que una hija abierta no aparece en ningún listado, porque solo se listan raíces.
- **Arreglo:** recorrer los descendientes, como hace `cmd_show`, o acotar el README a «hija directa».

**B3. `fallido` sin `cierre` pasa `check`.**
- **Defecto:** el README dice que la clave `cierre` da el motivo de un `fallido`, pero `cmd_check` no la exige.
- **Arreglo:** validarla en `check` o suavizar el README.

**Fuera de alcance (ya existía en HEAD, solo se anota):**
- El hook ejecuta el `ledger.py gate` del working tree, no la versión staged.
- `.claude/hooks/` sigue fuera de la compuerta (el reporte ya lo anota).
- El pedido del usuario incluye WS-K1, WS-K2 y WS-K3. Este diff solo documenta el estado `fallido` para cerrarlos después; esos cierres no entran en esta revisión.

## Verificado como correcto

- `diff_sha` de `status.json` (106ba79b…) es igual a `sha256(git diff --cached -- src tests scripts/research)` del staged actual. No hay cambios sin stage en archivos rastreados.
- `ledger.py check` sobre el registro real: OK (309 eventos, 13 workstreams).
- `current_state` nuevo frente al de HEAD sobre los 309 eventos: solo cambian C-169 (`enmendada`→`refutada`) y C-194 (`enmendada`→`soportada`). Las dos son hijas (ref C-168 y C-193), así que no cambian los conteos de raíces.
- La salida de `cmd_open` es idéntica a la de HEAD sobre el registro real: 0 de 64 abiertas, 46 refutadas y las mismas 10 sin decidir en el mismo orden.
- `juzgada` es True para C-169 y C-194. `validate` rechaza `sin_decidir` sobre ambas.
- **L1 arreglado:** reproduje la secuencia del test. En HEAD salía `cerradas sin decidir: 2: C-1, C-1`; con el staged sale una sola vez, y la retomada vuelve a abiertas.
- El aviso «hija juzgada» aparece con el staged y no con HEAD. El veredicto de la hija no se propaga a la madre, según la regla de WS-K12.
- Enmienda sobre una enmienda ya juzgada (un nivel): rechazada.
- **L5 en el hook:** `gated` incluye `scripts/research/` y mantiene las exclusiones `tests/golden` y `tests/research`. `scripts/research/` solo contiene `ledger.py`, así que no se bloquean por accidente scripts de análisis. El mensaje de `gate_errors` y la línea de `CLAUDE.md` coinciden con el código.
- **Por lectura, los 5 tests nuevos fallan con HEAD por la razón correcta:**
  - El hook de HEAD no ve `scripts/research/` y permite el commit.
  - `GATED` de HEAD deja igual el sha al stagear `scripts/research/x.py`.
  - En HEAD, `sin_decidir` y la segunda enmienda se aceptan.
  - HEAD no imprime el aviso de hija.
- `WS_ESTADOS` ya incluía `fallido` en HEAD. El gate sigue exigiendo `aprobado`, así que un workstream `fallido` no abre la compuerta, como dice el README.
- **No verificado por mí:** la corrida de `unittest` (18/18), porque no ejecuto tests. Le toca al revisor de evidencia.

## Orden sugerido de corrección

1. M1: `juzgada` transitiva, subida a la raíz en `validate` de enmienda, reuso en `gate_errors`, y test de cadena de 2 niveles.
2. B1: unificar el criterio de «juicio» de una enmienda.
3. B3: exigir `cierre` para `fallido` en `check`, antes de cerrar WS-K1, WS-K2 y WS-K3.
4. B2: aviso de hija sobre los descendientes, o acotar el README.
