## Revision WS-K12, ronda 1: auditor-eaf3d

**Veredicto: RECHAZA.** Hay 4 hallazgos MEDIO bloqueantes y 4 BAJO.

El diff staged solo trae `research/ws/WS-K12/report.md` y `status.json`; no toca `src/` ni `tests/`. El `diff_sha` e3b0c442... es el sha256 del diff vacio de src+tests, que es lo que calcula `staged_sha()`, asi que esta bien. Lo que se juzga son los cierres propuestos para el registro.

### MEDIO (bloqueantes)

**M1. C-079 no puede cerrarse como 'refutada'.**
- C-079 solo afirma la ubicacion de los picos (todos en la esquina (1,59,9)) y el crecimiento de u_ph.
- Su refuta_si es: "otra trayectoria (n15) o ventana tiene picos en celdas distintas".
- C-081 da 26/26 eventos en la misma esquina en n15 (verificado en `campaigns/b1/dense_340_n15/c080.out`) y C-084 da 21/21 con el estado girado. El refuta_si no se cumple.
- C-080 probo otra cosa: alpha_s en [0.01, 0.05], es decir lecho casi vacio, que no aparece en el enunciado de C-079.
- Arreglo: cerrar como 'fallida (no concluyente)'. El motivo debe decir que la prediccion hija probo otra afirmacion y que la ubicacion la deciden C-082/C-084.

**M2. C-089 como 'soportada' es un non sequitur.**
- El criterio de C-090 juzga variantes una por una en un banco nuevo. No contiene ninguna condicion sobre la condicionalidad de los fracasos viejos.
- D2.6 y E1 no se cerraron en un banco, sino en B1. `docs/PLAN_D_acople_implicito_alpha_p.md:195-201` dice que todas las D2 bajan los picos del banco y fallan el juez. `docs/PLAN_E_acople_implicito_lecho_saturado.md` dice que el banco no predice B1.
- Con el codigo actual, C-093 volvio a refutar d26k y e1 en el juez B1.
- Arreglo: cerrar como 'fallida (no concluyente)', con una nota que cite C-091 y C-093/C-105.

**M3. C-199 'soportada' da por buena la frase "celda a celda" que C-200 corrigio.**
- C-200 establece que la comparacion se hizo contra el rebaseline, no contra el test-full, y que la procedencia de la base es una declaracion.
- La verificacion del Grupo B solo cubre los metrics del golden. La repeti y da `{'cold_flow_noenergy_n4'} []`.
- Arreglo: fijar un enunciado literal con el alcance restringido al golden, o separar el cierre en dos eventos.

**M4. El inventario no alcanza el pedido del usuario ("cerrar todas las abiertas").**
- El reporte cierra C-170 y C-202, que no son raiz, pero omite otras en el mismo estado:
  - predicciones en_disputa: C-126, C-130, C-135, C-144 y C-212;
  - hipotesis abiertas de WS-K11: C-237 ("ABIERTO") y C-261 ("PENDIENTE");
  - resultados: C-154 (en_disputa) y C-168/C-193 (pre-registrada).
- Un barrido con `current_state` sobre los eventos no raiz da 78 sin cerrar.
- Arreglo: declarar la regla de alcance y aplicarla a todos los casos, o justificar cada exclusion.

### BAJO (no bloqueantes)

- **B1.** Los cierres de C-085 y C-057 deben llevar sus salvedades:
  - C-085: segun C-087, P=341706 es la relajacion del pico, no su construccion; anadir tambien la lectura de C-088.
  - C-057: segun C-061, la sonda no distingue "candidata" de "fijada"; citar C-063.
- **B2.** C-110 es tipo 'resultado', no hipotesis. El cierre debe citar C-120 y C-151, que son 'soportada' parciales.
- **B3.** C-047 y C-044 se pueden acotar leyendo el codigo:
  - C-047: el audit calcula p_max como max|sh%p| sobre celdas propias activas (`src/mod_audit.f90:704`, escrito en `src/main_3d.f90:836`). El snapshot del mismo paso escribe el mismo `sh%p` (`main_3d.f90:900`, `src/mod_output_hdf5.f90:230`) y nada lo modifica en medio. Por tanto el audit no puede superar el maximo del campo, que es justo la discrepancia que reporta C-047.
  - C-044: la ruta del paso final diminuto sigue viva (`main_3d.f90:339-340`). Con dt de 1 ms, un hueco de 1.25e-9 s supera el umbral de 1e-9 y se da el paso.
- **B4.** La evidencia de C-198 esta en `tests/out/`, que git ignora (`.gitignore:20`) y que cualquier `make test-*` sobrescribe. Ademas, el `audit.csv` lo genero `./bin/eaf3d_mpi` antes del commit 1de144e, no HEAD 4f51e47. El cierre debe decirlo asi.

### Verificado como correcto
- `ledger.py open` da 18 de 64 afirmaciones raiz abiertas, y `ledger.py check` da OK con 278 eventos.
- `current_state` (`scripts/research/ledger.py:144-150`) se comporta como describe el reporte.
- `validate()` acepta los eventos 'resultado' con ref y estado de cierre. 'soportada' exige rutas existentes.
- Cifras del Grupo A, comprobadas en los datos crudos:
  - c077.out: 31 eventos, 19 con precursor, 61.3 %; control 9.2 %;
  - c080.out: 26 eventos, 17 con alpha_s en [0.01, 0.05], 18 con precursor; ALPHA_BED = 1e-2 en `src/mod_constants.f90:75`;
  - c083.out: 18 eventos en (1,19,9) y 3 en (1,20,9);
  - c086.out, fila 341706 o1: cuota del gas 0.908;
  - bench_reval_c090.out: todas las cifras citadas.
- Grupo B:
  - `check_audit.py` sobre `tests/out/cold_flow_noenergy_n4`: mass_gas PASS, mass_gas_flux_closure PASS, resto 1.69e-21, m_gas_out -7.1206e-6;
  - golden v131 frente a v132: solo se anade el banco nuevo.
- Grupo E: cifras de C-123, C-174 y C-204 contra sus veredictos, y la aritmetica de e_multi de C-175 (-8.55e-4).
- Cadenas de C-169/C-194 (ya juzgadas a traves de su enmienda), `research/QUESTION.md:24` (805 kPa fuera de alcance) y Plan K ausente de `src/`.
- Cierres de C-074, C-082 y C-088, y del Grupo C (C-015, C-050, C-051, C-056, C-064): correctos con la regla declarada.

### Orden sugerido de correccion (uno por uno)
1. M4: alcance del inventario. Define que mas entra al cierre.
2. M1: C-079.
3. M3: enunciado literal de C-199.
4. M2: C-089.
5. B1 a B4: notas de cierre y enunciados literales.