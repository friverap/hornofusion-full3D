# Revisión de evidencia: WS-K12, ronda 1 (revisor-evidencia)

El panel rechaza el cierre: hay 5 objeciones bloqueantes y 6 no bloqueantes. Casi todas las cifras se reproducen. El problema es que cinco cierres no respetan lo que dice el registro: estados que el criterio pre-registrado no asigna, una lectura ya retirada y una cifra retirada que hoy no se reproduce.

Reporte: `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K12/report.md`. Registro: `research/ledger.jsonl` (278 eventos, `ledger.py check` OK). Todo fue de solo lectura; los scripts que reejecuté (`bench_metric.py`, `probe_p.py`, `piezas.py`, `check_audit.py`) solo leen datos existentes.

## 1. Tabla de cifras

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Afirmaciones raíz abiertas | 18 de 64 | 18 de 64 | ok |
| Predicciones juzgadas a través de su enmienda (5 cadenas) | C-169→C-173 refutada, C-170→C-174, C-194→C-196, C-202→C-204, C-121→C-123 | coinciden; `current_state` está en `ledger.py:144` | ok |
| C-078 | 31 eventos / 19 con precursor (61.3 %) / control 453 de 4919 (9.2 %) | igual (`c077.out`) | ok |
| C-081 | 26 / 18 (69.2 %) / 457 de 4837 (9.4 %); 17/26 (65.4 %) | igual; ALPHA_BED = 1e-2 | ok |
| C-084 | 21 eventos en j = 19 o 20 | 18 en (1,19,9) + 3 en (1,20,9) | ok |
| C-087 | Su −2.20e-2 / −2.21e-1 / −2.51e-4; cuota del gas 0.908 | 0.9085 | ok |
| C-091 | base0 3.706e5 / 3.706e5 / 17; d26k, e1 y combo | `bench_metric.py` reejecutado: idéntico | ok |
| C-061 (base de C-057) | E y N con cx = 1 en la 2.ª externa | `diag_c058/run.log:560-576` | ok |
| C-198 | max\|resto\| 1.69e-21; sum m_gas_out −7.1206e-6 | igual | ok (ver O8) |
| C-199 | v132 − v131 = {cold_flow_noenergy_n4} | igual; `test_full.txt` con 60 PASS err rel 0 | ok (ver O9) |
| Fecha del audit.csv frente a commits | 00:43 / 1de144e 01:05 | igual | ok |
| Plan K fuera de `src/` | grep vacío; el patch existe | igual | ok |
| C-123 | por celda 0.270; neto 3.135 «sacados de su audit.csv» | **0.5660 / 2.456** (audit reescrito a las 20:02, después del veredicto) | **objeción O5** |
| C-174 | 0.3156; neto 1.571 | 0.3156; 1.571 | ok |
| C-204 | Br/e −0.683 y −0.135; cociente 0.184 | igual (`piezas.py`) | ok |
| Reparto de C-175 | −8.55e-4 kg | −8.550e-4 kg | cifra ok; la lectura es la objeción O3 |
| C-079 «refutada» | — | su refuta_si no se cumplió | **objeción O1** |
| C-089 «soportada» | — | C-090 no define soporte global; C-093 lo contradice | **objeción O4** |
| Grupo E «fallida» | — | los criterios dicen «sin decidir» | **objeción O2** |

## 2. Objeciones

### Bloqueantes

**O1. C-079 no puede cerrarse como «refutada» tal como está propuesto.**
- Su refuta_si («otra trayectoria o ventana tiene picos en celdas distintas») no se cumplió: en n15 los 26 de 26 eventos caen en la misma esquina (`campaigns/b1/dense_340_n15/c080.out`).
- El reporte atribuye a C-079 una «parte de mecanismo (lecho casi vacío)» que su enunciado no contiene. Esa condición la introdujo el criterio de C-080.
- **Para levantarla:** que el cierre diga que se refuta solo la operacionalización de C-080 y que el refuta_si propio no se cumplió, o elegir otro estado (en_disputa o «cerrada sin verificar»). Corregir también la descripción de C-079 en el reporte.

**O2. Grupo E: «fallida (no concluyente)» cambia lo que dicen los criterios pre-registrados.**
- Para la banda intermedia, los tres criterios dicen «sin decidir»:
  - `C-121.criterio`: «SIN DECIDIR (se registra así)»;
  - `C-172.criterio`: «sin decidir»;
  - `C-202.criterio`: «Otro caso: sin decidir».
- En esos mismos criterios, «fallida» significa que falló un prerrequisito (C-171/C-172, C-202) o que la prueba es inválida (C-121).
- C-218 lo dejó escrito para C-204: «la etiqueta sigue SIN DECIDIR y no fallida».
- El precedente C-076 no aplica: allí el criterio de C-075 definía expresamente «FALLIDA (no concluyente)».
- **Para levantarla:** mantener en_disputa y documentarlo, o que el usuario decida un estado cerrado «sin_decidir» en `ledger.py`, sin reetiquetar los veredictos.

**O3. C-110: el reporte se apoya en una lectura ya retirada.**
- Cita C-175 (2) como algo que «apunta EN CONTRA de la parte neta de C-110».
- C-176 retiró exactamente esa lectura: «no es evidencia contra C-110… el complemento neto 4e-5 no dice nada del ±5e-3».
- Errores menores en el mismo párrafo: C-110 es de tipo resultado, no hipótesis, y C-168/C-175 son resultados, no veredictos.
- **Para levantarla:** quitar la frase o sustituirla por la cota de C-151, y corregir los tipos.

**O4. C-089 «soportada» no sale de la letra del criterio.**
- `C-090.criterio` solo define la validez del banco y si cada variante pasa o queda refutada en el banco. No dice cuándo queda soportado C-089.
- El motivo «el fracaso viejo era condicional» omite C-093 (refutada): d26k y e1 fallan el juez de B1 con el código actual (inciso d, sentinel_gas FAIL en las 4 corridas).
- **Para levantarla:** no cerrar C-089 como soportada, o registrar un criterio global; en cualquier caso, citar C-093.

**O5. Las cifras de C-123 no se reproducen y están retiradas.**
- Sobre `campaigns/b1/k7_mo20/audit.csv` actual salen **0.5660** (por celda) y **2.456** (neto), no 0.270 y 3.135. El archivo se reescribió el 24-oct a las 20:02 (re-medida C-126/C-127), después del veredicto de las 19:37.
- C-124 (soportada) ya había retirado el 0.270.
- La conclusión «sin decidir» no cambia, porque 0.566 sigue entre 0.3 y 0.7.
- **Para levantarla:** citar las cifras vigentes con su comando, o las de C-124.

### No bloqueantes

- **O6. C-085:** el texto del cierre debe llevar la salvedad de C-087. En 341705 o1, donde se construye el pico, la cuota del líquido es 0.785 (`c086.out`). Sin esa salvedad, la refutación se leería como «el gas arma el pico».
- **O7. Comandos de los veredictos:** ya no reproducen lo registrado. En `dense_rot_n15` quedan solo 13 snapshots, así que `phantom_scan.py` no puede dar los 21 eventos de C-084. Y `probe_p.py` actual imprime otra tabla, sin cuotas. Para el cierre soportado de C-082, usar como comando la lectura de `c083.out`.
- **O8. C-198:** `tests/out/` se sobrescribe en cada corrida de tests. Añadir `research/ws/WS-K9/logs/coldnoE_binario_previo_check.txt` como ruta estable: ahí está la mitad anterior al arreglo (FAIL, 3.41e-06), que verifiqué. Aclarar que la verificación es una relectura de una salida existente, no un build de HEAD.
- **O9. C-199:** limitar el cierre a lo verificable, el golden (60 PASS con err rel 0, v132 = v131 + 1). Según C-200, la procedencia de la base celda a celda es una declaración, no un dato.
- **O10. C-015:** el motivo dice que su refuta_si «nunca se probó» y que C-076 es «coherente con ella». Pero hay datos que apuntan a su refuta_si:
  - el evento 342535 de `c077.out` está en la celda de lecho del fondo (1,59,9);
  - `.claude/rules/acople-pv.md:580-586` describe, a 342.5 s, celdas de lecho del fondo con α_g en el piso que ciclan en 2 pasos.

  El motivo debería mencionarlo en lugar de decir «coherente».
- **O11. Veredictos sin panel previo y eventos sin especificar:**
  - C-061, C-078, C-081, C-084, C-087 y C-091 vienen de workstreams en ronda 0: este panel es su primera revisión. Recalculé sus cifras y coinciden.
  - El reporte solo especifica la forma exacta del evento para el grupo A. Para los grupos B-E falta fijar tipo, ref, estado y motivo de cada cierre.

VEREDICTO: rechaza