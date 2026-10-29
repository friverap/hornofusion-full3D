# WS-K13: revisión de código (auditor-eaf3d), ronda 1

**Veredicto: rechaza.** Hay un hallazgo MEDIO (M1) sin resolver.

Revisé el staged de `scripts/research/ledger.py`, `.claude/hooks/guard_cierre.sh`, `tests/research/*`, `research/README.md` y `CLAUDE.md`. No hay cambios sin stage en esos archivos. El staged_sha de `src tests scripts/research` es `351c1e5f…8d2d` y coincide con `diff_sha` de `research/ws/WS-K13/status.json`.

## Hallazgos

### MEDIO

**M1. La cadena de enmiendas puede no ser lineal y el veredicto puede caer sobre un eslabón superado.** Bloqueante.
`scripts/research/ledger.py:96-114` (validate de veredicto y de enmienda) y `:172-176` (`current_state`).

`current_state` toma el último evento que cita la afirmación, por orden. `juzgada` solo comprueba si existe un veredicto en la cadena. Las dos funciones divergen en dos casos que `validate` acepta. Ambos los reproduje en memoria con el `ledger.py` staged.

- **(a) Enmiendas hermanas.** Secuencia: P; E1 enmienda P; E2 enmienda P (se acepta porque P aún no tiene veredicto); V refutada sobre E1.
  - Resultado: `juzgada(P)=True` pero `current_state(P)='enmendada'`.
  - `open` muestra P como abierta y la omite de las permanentes.
  - Después, `resultado --estado sin_decidir --ref P` se acepta y P queda en «cerradas sin decidir».
  - Esto contradice la regla nueva del README («Una predicción juzgada a través de cualquier eslabón … ya no admite … `sin_decidir`») y el punto 2 de «Cambios» del reporte.
- **(b) Veredicto sobre el criterio superado.** Secuencia: P; E1 enmienda P; V1 refutada sobre E1; V2 soportada sobre P directo (criterio original). V2 se acepta y `current_state(P)` pasa a `soportada`: la refutación sale de la lista de permanentes.
  - Ya ocurría en HEAD, pero anula justo la semántica de «estado por enmienda» que introduce este WS.

**Arreglo:** exigir una cadena lineal que se juzga en su punta.
1. Rechazar una enmienda cuyo `--ref` ya tenga una enmienda (se enmienda la última).
2. Rechazar un veredicto cuyo `--ref` ya tenga una enmienda (se juzga el criterio vigente).
3. Agregar un test por escenario.

En el registro real hay 0 enmiendas hermanas y 0 veredictos sobre eslabones superados (lo verifiqué), así que `check` seguiría pasando.

### BAJO

**B1. Las refutadas no raíz se pueden reabrir.** `ledger.py:115-119` (`not ref.get("ref")`).
- Secuencia: H; P `--ref` H; V refutada sobre P; P2 predicción `--ref` P (se acepta).
- `current_state(P)` pasa de refutada a pre-registrada. Después, `sin_decidir --ref P` se acepta y P sale en «cerradas sin decidir». Además se pierde el aviso «hija juzgada» de H.
- La sección «Incertidumbre» del reporte no lo cubre.
- **Arreglo:** extender la regla a cualquier predicción, hipótesis o resultado refutado o fallido, sin incluir los veredictos, porque C-130→C-127 y otros citan veredictos. Verifiqué que ningún evento histórico la violaría. La alternativa es documentar la excepción.

**B2. Enmienda sobre una hipótesis cerrada.** `ledger.py:112-114`. `raiz_enmienda` también devuelve hipótesis y resultados.
- Ahora se rechaza enmendar una hipótesis soportada; HEAD lo aceptaba.
- El mensaje dice «prediccion ya juzgada».
- Es un cambio de comportamiento que el README no documenta. **Arreglo:** corregir el mensaje y el README.

**N1. Suite no ejecutada por mí.** No corrí la suite `tests/research` porque mi rol es de solo lectura. En su lugar reproduje en memoria los casos de los tests nuevos (ver abajo). Falta que el revisor de evidencia confirme el «Ran 23, OK».

## Verificado como correcto

- `python3 scripts/research/ledger.py check` sobre el registro real da `ledger OK (309 eventos, 13 workstreams)`.
- Ejecuté en memoria HEAD (`git show HEAD:…` cargado con `exec`) contra el staged:
  - solo cambian {C-169} (enmendada → refutada) y {C-194} (enmendada → soportada);
  - la salida de `open` es idéntica, con 0 abiertas de 64 y las mismas 10 cerradas sin decidir.
- Cadena P←E1←E2 con veredicto sobre E2: se rechazan las enmiendas sobre P, E1 y E2, y el `sin_decidir` sobre P («ya esta cerrada (refutada)»). Con esto quedan resueltos M1/E1/R1 de la ronda 1 para cadenas lineales.
- Una nota (resultado propuesta) sobre una enmienda no la juzga: P sigue en «enmendada».
- Una predicción o hipótesis con `--ref` a una raíz refutada se rechaza, con el mensaje correcto.
- `open`, lista «cerradas sin decidir»: filtra por el estado vigente de la ref y no repite refs (`dict.fromkeys`). Con esto queda resuelto L1.
- `check` de `fallido`: exige la clave `cierre` y los tres «aprueba» en la ronda vigente. `gate` sigue exigiendo `aprobado`, así que un workstream `fallido` no abre la compuerta.
- `GATED` en `staged_sha` y la lista `gated` del hook son coherentes:
  - `scripts/research/` queda bajo la compuerta;
  - `tests/research/` y `tests/golden/` quedan fuera del bloqueo, pero dentro de `diff_sha`, como antes;
  - el mensaje de `gate_errors` está actualizado.
- Los tests nuevos fallan por la razón correcta:
  - el final de `test_gate` busca «diff_sha», no el mensaje de test_quick;
  - `test_herramienta_del_registro_deny` falla con «allow» si el hook no incluye `scripts/research/`.
- `gate_errors` numérico reutiliza `juzgada`, que es transitiva.

## Orden sugerido de corrección

1. M1: cadena lineal en validate (enmienda y veredicto sobre la punta), con dos tests.
2. B1: extender la regla de permanentes a las no raíz (o documentar la excepción), con un test.
3. B2: mensaje y README.
4. N1: confirmar la ejecución de la suite sobre el staged final.
