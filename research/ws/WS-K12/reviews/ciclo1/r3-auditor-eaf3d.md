# WS-K12 ronda 1: revisión del auditor-eaf3d

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Hay cuatro BAJO no bloqueantes; recomiendo corregir A1 y A2 antes de registrar los eventos, porque el registro es append-only.

Alcance: diff staged (`/Users/frariv/Horno/hornofusion-full3D/scripts/research/ledger.py`, `/Users/frariv/Horno/hornofusion-full3D/research/README.md`, `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K12/status.json` y `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K12/report.md`) contra el reporte. No hay cambios en `src/` ni `tests/`, así que no aplica ningún riesgo numérico, de MPI, halos ni snapshot. No leí revisiones de otros revisores. Todo lo que ejecuté fue de solo lectura: `ledger.py check/open`, `validate` y la simulación en memoria, `check_audit.py` sobre campañas existentes y lecturas de CSV/HDF5.

## 1. Hallazgos

### BAJO

**A1. El guard de `sin_decidir` no sigue las enmiendas** (`scripts/research/ledger.py:114-122`).
- **Defecto.** Solo consulta `current_state(ref)`. Una predicción refutada a través de su enmienda aparece como «enmendada» y el guard la acepta.
- **Escenario.** Con el registro actual, `validate(resultado, ref=C-169, estado=sin_decidir)` devuelve `[]`, aunque C-169 está refutada (C-171 → C-173). C-169 es el id contiguo a C-170 (E6), así que una errata de un dígito cierra como «sin decidir» una refutada permanente.
- **Por qué importa.** El reporte (`report.md:428-429`) afirma que «una ref mal tecleada a una refutada permanente ya no se acepta», y eso solo vale para raíces.
- **Arreglo.** Recorrer la cadena de enmiendas de la ref y rechazar si alguna está en CERRADOS. Lo comprobé en memoria: rechaza C-169 y acepta las 10 refs del grupo E (C-122, C-172 y C-203 están en_disputa). La otra opción es restringir la frase del reporte.
- **Efecto en este WS.** Ninguno: las refs literales de E1-E11 son correctas.

**A2. Literal de B5: «0.521 -> 0.682» no es el valor final.**
- **Defecto.** El comando del propio evento da, para k7v4_long, `[0.521, 0.56, 0.581, 0.531, 0.532, 0.618, 0.634, 0.637, 0.663, 0.682, 0.639]`. 0.682 es el máximo (tramo 10); el último tramo (499 pasos) da 0.639 y la serie no es monótona. C-154 decía «de 0.521 hasta 0.682», que sí es correcto.
- **Arreglo.** Usar «de 0.521 hasta 0.682 (máximo en el tramo 10; último 0.639)».

**A3. Texto contradictorio en `report.md:500-503`.**
- **Defecto.** Dice que la validación de la ref y la lista de `sin_decidir` en `open` quedan pendientes. Las dos están implementadas en el diff (`:114-122`, `:207-209`), y el propio reporte lo dice en `:425-431` y `:595-596`.
- **Arreglo.** Dejar como pendiente solo la limitación de `current_state`.

**A4. Efectos de `current_state` que el reporte no menciona.**
- **P1 y C-093.** P1 (resultado «propuesta», ref C-093) deja `current_state(C-093)` en «propuesta». En la simulación, el barrido de no raíz pasa de 90 a 91, con un veredicto refutado contado como no cerrado.
- **Lista de `open`.** `open` (`:207-209`) lista todo evento `sin_decidir` aunque un evento posterior con la misma ref cambie su estado vigente. Una afirmación podría salir a la vez en «abiertas» y en «cerradas sin decidir».
- **Arreglo.** Documentar lo de P1. En `open`, filtrar por `current_state(ref) == 'sin_decidir'`.

## 2. Verificado como correcto

**Herramienta (`ledger.py`)**
- `ESTADOS_VEREDICTO` es idéntico a la tupla anterior (`CERRADOS + ("en_disputa",)` en HEAD), así que la validación de veredictos no cambia.
- `sin_decidir` se rechaza en un veredicto, con ref a un veredicto o una enmienda (C-123, C-122, C-061) y con una ref inexistente.
- `current_state` no cambió (`:158-164` ahora, `:144-150` en HEAD).
- `check` sigue en OK (278 eventos; ningún evento existente usa `sin_decidir`). `diff_sha` es el sha256 del diff vacío de `src/` y `tests/`, que es lo correcto.
- Consumidores revisados: `estado_sesion.sh` (`head -14` de `open`), las skills y `workstream.js`. Ninguno depende de la tupla CERRADOS ni se rompe con la línea nueva.

**Alcance y simulación**
- 18 de 64 raíces abiertas.
- Barrido de 101 no raíz con partición exacta: 61 propuestas sin `refuta_si` ni criterio, 14 + 6 veredictos, C-193, C-146/C-162/C-181, las enmiendas, C-169/C-194 y 11 incluidos, sin faltantes ni sobrantes.
- Simulé en memoria los 30 eventos en el orden del reporte: todos pasan `validate`, las rutas de los «soportada» existen, y `open` queda en 0 abiertas de 64.

**Cifras reproducidas con sus comandos**
- c077, c080 y c083: 61.3 / 69.2 / 81.0 % y controles de 9.2 a 9.7 %. Las celdas de n15 y del estado girado coinciden.
- c086 (341705 y 341706, externas o1-o5): cuotas y act TF coinciden.
- Sonda de diag_c058, 2.ª externa de 345318: E con cx=1 en it 2-6, N en it 1-6, T nunca; celda SALTADA.
- C-044: 22/19; picos de P1 (1.240e5 y 1.455e5 sin la fila truncada).
- C-047: 0 diferencias en 395/395 snapshots, en las 6 corridas. diag_k15d da 5.865e5 / 3.491e5 / 3.279e5 / 3.082e5.
- diag_p342a/b: paso truncado con dt 1.186e-9 y p_max 2.78e4 → 9.52e4; después 8.045e5, 1.64e5 y 8.48e4. La celda (2,51,8) tiene p = −8.045e5, máximo con signo 3.19e4, y alpha_s = alpha_g = 0.
- C-121: cota 0.5647 y margen de 2.213e-3 kg.
- B5: 0.384/0.163 y 0.491/0.165.
- `check_audit.py` sobre k10_mo20 y k10_base: PASS en `mass_gas_decomp` y `mass_gas_row_volume`, con los restos y tolerancias citados.
- Logs de WS-K9: FAIL 3.41e-06 frente a PASS 1.69e-21; 60 PASS con err rel 0; v132 = v131 + `cold_flow_noenergy_n4`.

**Citas de código vigentes**
- `src/main_3d.f90:335-340` (paso corto final), `:836` (audit) y `:900` (snapshot).
- `src/mod_audit.f90:704` (p_max = max|p| sobre las celdas propias activas).
- `src/mod_output_hdf5.f90:230`.
- `tests/integration/check_audit.py:535`.

## 3. Orden sugerido (uno por uno)
1. A2: literal de B5, antes de registrarlo.
2. A1: guard con la cadena de enmiendas, o restringir la frase del reporte.
3. A3: texto de `:500-503`.
4. A4: nota sobre P1 y filtro de `open`. Puede quedar como pendiente del coordinador.
