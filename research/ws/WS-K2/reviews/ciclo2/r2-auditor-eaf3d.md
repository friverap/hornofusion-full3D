## Revisión WS-K2, ronda 2 (auditor-eaf3d)

**Veredicto: rechaza.** Hay una objeción MEDIO bloqueante, M-1, en el diff staged de `.claude/rules/acople-pv.md`.

### Alcance
- Diff staged: `.claude/rules/acople-pv.md`, `.claude/rules/research.md`, `docs/PLAN_K_limitador_en_poisson.md`, `status.json` y los reportes y revisiones de WS-K1/K2.
- No toca `src/` ni `tests/`. El `diff_sha` es el del diff vacío, lo correcto en un cierre sin código.
- Reporte de la ronda 2: `research/ws/WS-K2/report.md`, copia de trabajo (estado AM). C-312 está en `research/ledger.jsonl` sin stagear.

### Hallazgos

**MEDIO**

- **M-1 (bloqueante).** `.claude/rules/acople-pv.md:629-632`, entrada staged «Plan K CERRADO».
  - (a) Dice «pegado a la centinela de 2 MPa 183 pasos seguidos». Los 183 pasos son >= 1 MPa; en 2 MPa hay 122 (C-311). Es B-1 de la ronda 1, sin corregir.
  - (b) Dice «lo que separa a K es quedarse pegado al tope». C-312 lo contradice: desde el mismo estado, el brazo sin K sigue >= 1 MPa en sus 10 pasos (345311-345320). El reporte lo admite («Pendiente del coordinador»), pero el diff staged no lo cambia.
  - Qué puede fallar: la regla duradera atribuye al Plan K un pegado que el registro no le atribuye, y un agente descarta la idea de holgura o barrera por ese motivo.
  - Arreglo: corregir (a) y (b) en el staged según C-311/C-312 y añadir la salvedad de B-5.

**BAJO** (no bloqueantes)

- **B-1:** absorbida en M-1 (a).
- **B-2:** «desde diag_p342a, que no existe» (`acople-pv.md:637-638`; ahora también en `report.md:206-207`). El reinicio `diag_p342a/eaf3d_00342450.h5` sí existe; lo que falta es la corrida.
- **B-3 (a):** el reporte aún lista restart, t_final y output_freq como diferencias de config.dat. Solo difieren `output_dir` y las claves `pc_alpha_implicit`/`pc_ai_tol`. La parte (b) quedó resuelta.
- **B-4:** informativa, sin cambio (la media de K en 342-344 s es 0.267, no 0.23).
- **B-5:** la regla y PLAN_K §6 dan el brazo K por «v2 sin A2», y el binario no es verificable. Falta la salvedad.
- **B-6 (nueva):** «el brazo SIN Plan K se pega MÁS» depende de la ventana elegida.
  - La ventana 345310-345320 da a k_off 10 pasos tras su arranque y a k_on solo 3.
  - Alineados por el arranque, los dos siguen >= 1 MPa en todos los pasos medidos y decaen parecido.
  - El salto de k_off en el primer paso es el transitorio de cambiar de operador sobre un estado de K (C-294/C-309).
  - Con 10 pasos no se mide un pegado de 183. La conclusión «sin prueba de que sea propio de K» se sostiene; «se pega más» no.
- **B-7 (nueva):** «D2.6 PEOR en picos» es del Plan D, que según la regla de vigencia (`acople-pv.md:269`) no vale para el código actual. El dato vigente C-093 da 0 eventos > 3e5. El motivo válido es el inciso (d).
- **B-8 (nueva, proceso):** el índice tiene el reporte de la ronda 1 y no tiene C-312, y `diff_sha` (solo rutas GATED) no lo detecta. Hacer `git add` antes del commit.
- **B-9 (nueva):** la suma de m_spill de base_340_n14 es 1.0449e-10, que redondea a 1.04, no 1.05.

### Verificado como correcto
- C-312, brazos: k_off 10 pasos >= 1e6 (2 en 2e6), cent_pg 90.9 %; k_on 3 pasos (1 en 2e6), 27.3 %. k_on es idéntico fila a fila a k1pa_340_n15.
- C-312, cent_pg en [344, 345.318): K 0.15/0.08/0.76, base 7.21/7.89/10.24. En [345.318, 345.5]: K 0/2.19/100, base 2.75/2.19/3.83.
- C-312, medias y sumas en [340, 345.3): vol_lim, vol_unlinked, m_spill (salvo B-9) y m_alpha_clip, como dice el reporte.
- [PLAN-K]: 5 líneas por run.log, 104/143/114 sin converger de 25000 (0.42-0.57 %), 0 «unknown key».
- research.md: 69 kPa = media del ciclo que frena un chorro; ~6 kPa hidrostáticos (C-013/C-031).
- PLAN_K §6: coherente con C-012, C-028, C-037, C-039 y C-041.

### Orden sugerido de corrección
1. M-1, junto con B-1 y B-5 (una sola edición de la entrada «Plan K CERRADO»).
2. B-6 (frase «se pega MÁS» en report.md y en C-312).
3. B-2 (regla y reporte).
4. B-3 (a).
5. B-7.
6. B-9.
7. B-8 (stagear reporte y ledger antes del commit).
