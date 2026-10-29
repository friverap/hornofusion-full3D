## Revisión r1, auditor-eaf3d (WS-K12, ronda 1)

**Veredicto: rechaza.** Hay una objeción MEDIO bloqueante (M1). No hay hallazgos ALTO. Todo lo que revisé es de solo lectura: las simulaciones de eventos se hicieron en memoria y no se escribió nada en `research/ledger.jsonl`.

### 1. Hallazgos

**MEDIO**

- **M1. Los comandos de B3, B4 y P1 son marcadores, no comandos ejecutables.**
  - **Dónde:** `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K12/report.md:221, 223, 374`.
  - **Defecto:** el `--cmd` de esos tres eventos dice, por ejemplo, `"<comando python3 -c de C-044 en research/ws/WS-K12/report.md>"`. Como el texto no está vacío, `validate` lo acepta (`scripts/research/ledger.py:115-118`).
  - **Escenario de fallo:** se registra el cierre de C-044 «tal como aparece» y alguien ejecuta su cmd. El shell lee `<comando` como una redirección desde un archivo inexistente y falla.
  - **Además:** el comando real de la fuente (`report.md:189`) solo recorre 4 corridas, así que no reproduce la cifra principal del cierre B3 («22 corridas, en 19 sube p_max»). Yo verifiqué 22/19 con un script propio y es correcta. Aun así, el cierre de una soportada quedaría sin un comando que reproduzca esa cifra.
  - **Arreglo:** poner el comando literal y escapado. En B3, el barrido de `campaigns/b1/*/audit.csv` con último dt < 1e-6 (última fila frente a la penúltima) más `grep e5d331e campaigns/b1/dense_340_n15/run.sh`. En B4, el bucle con `$d` escapado. En P1, el comando de C-044.

**BAJO**

- **B1. `scripts/research/ledger.py:113-114`: la regla de `sin_decidir` no comprueba la ref.**
  - Exige que haya ref, pero no que exista ni de qué tipo es el evento referido.
  - Lo comprobé en memoria: se aceptan `ref=C-999` (no existe) y `ref=C-099` (refutada permanente). En el segundo caso, C-099 sale de la lista de refutadas permanentes de `open`.
  - Escenario: una errata al teclear la ref cierra otro evento, y el registro es append-only (no se puede borrar).
  - Arreglo: con `sin_decidir`, exigir que la ref esté en `ids`, que el tipo sea hipotesis, prediccion o resultado, y que el evento referido no esté ya soportado ni refutado.
- **B2. Referencias del reporte desfasadas por el propio diff.**
  - `report.md:63` cita `ledger.py:144-150`; current_state ahora está en las líneas 150-156.
  - `report.md:313-314` afirma que no existe un estado cerrado «sin decidir» y cita `:28`. Tras el diff, CERRADOS está en la línea 31 e incluye `sin_decidir`.
  - Arreglo: actualizar las líneas y escribir esa frase en pasado.
- **B3. El texto C1 omite el signo del pico de C-015.** El «pico de 805 kPa» es p = −8.045e5 Pa, una succión: es max|p| en (2,51,8) (comprobado en `campaigns/b1/diag_p342b/eaf3d_00342451.h5`). Conviene decirlo, dado que el cierre B4 establece que p_max = max|p|.
- **B4. Las raíces cerradas como `sin_decidir` desaparecen de `open`.**
  - `open` (`ledger.py:194`) solo muestra como permanentes las refutadas y fallidas. C-110 y C-121, al cerrarse con `sin_decidir`, ya no aparecerían en su salida.
  - `research/README.md:36` no menciona el estado nuevo.
  - Consecuencia: /pregunta consulta `open` antes de proponer y no vería que esa línea de prueba no sigue con este instrumento.
  - Arreglo: listarlas en `open` o documentar en el README cómo consultarlas.

### 2. Verificado como correcto (no re-auditar)

- **Cambio en ledger.py:**
  - Lo staged coincide con el árbol de trabajo.
  - `ESTADOS_VEREDICTO` es el mismo conjunto que el antiguo `CERRADOS + ("en_disputa",)`, así que los veredictos no cambian.
  - `check` da OK con 278 eventos, y ninguno usa `sin_decidir`.
- **Validador:** `sin_decidir` se rechaza en veredicto, hipotesis, enmienda y en un resultado sin ref, y se acepta en un resultado con ref. Coincide con lo que dice el reporte.
- **Simulación en memoria de A1–F2 y P1:**
  - Todos los eventos pasan `validate`.
  - Las rutas de las soportadas existen.
  - El `--ws` coincide con el ws de cada ref.
  - `open` pasa de 18 a 0 abiertas.
  - C-093 ya estaba en «propuesta» por C-094, así que P1 no cambia nada.
- **Barrido:** 101 eventos no raíz = 62 resultados en propuesta (los 61 de la lista + C-193, ninguno con refuta_si ni criterio) + 20 veredictos (la lista coincide) + C-122/C-172/C-203 + C-146/C-162/C-181 + C-169/C-194 + los 11 del alcance.
- **C-044:**
  - 22 corridas con paso final truncado, y en 19 sube p_max.
  - Los binarios e5d331e están confirmados (`run.sh` de dense_340_n15 y la letra de C-092).
  - La ruta del paso corto sigue vigente en `src/main_3d.f90:334-341`.
  - 1de144e es el único commit de `src` desde 2b65e11.
- **C-047:**
  - 0 diferencias entre audit y campo en diag_k15d (181 snapshots), judge_otp_280 (7) y k10_mo20 (2).
  - En 345250 el campo va de −5.865e5 a 9.27e4; en 345280, de −3.279e5 a 2.564e5.
  - `mod_audit.f90:704` calcula max|sh%p| sobre las celdas activas propias; `main_3d.f90:836` y `:900` y `mod_output_hdf5.f90:230` confirman que audit y snapshot escriben el mismo `sh%p`.
- **C-198/C-199:**
  - En los logs de WS-K9: FAIL con max|resto| 3.41e-06 antes del arreglo y PASS con 1.69e-21 después; sum m_gas_out −7.1206e-6.
  - 60 PASS con err rel 0.
  - v132 = v131 + cold_flow_noenergy_n4, sin ninguna métrica común distinta.
  - Horas: binario a las 00:40 y audit.csv a las 00:43, ambos antes de 1de144e (01:05).
- **Grupo E:** k7_mo20 da 0.5660 y 2.456 (archivo del 24-oct, 20:02); k8_cg1000 da 0.3156 y 1.571 con las columnas `_all`.
- **C-015:**
  - El `restart_file` de diag_p342b apunta a diag_p342a/eaf3d_00342450.h5.
  - El pico está en (2,51,8) con alpha_s = alpha_g = 0.
  - Las corridas continuas dan 91, 81 y 131 kPa en esa ventana.
  - Plan K no está en `src`, y `research/ws/WS-K1/plan_k_v2.patch` existe.
- **status.json:** `diff_sha` es el sha256 del diff vacío de src/tests, coherente con un WS sin cambio numérico.

### 3. Orden sugerido de corrección (uno por uno)

1. M1: comandos literales en B3, B4 y P1, incluido el barrido 22/19 en B3.
2. B1: comprobar en `validate` que la ref de `sin_decidir` existe y es de un tipo válido.
3. B3: el signo del pico en C1.
4. B2: las referencias de línea y la frase de `report.md:313-314`.
5. B4: que `open` o el README muestren las `sin_decidir`.
