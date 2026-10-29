El diff staged de WS-K1 no cambia código, pero lo rechazo: hay dos defectos MEDIO en el texto, uno en la regla permanente y otro en el propio reporte.

# Revisión WS-K1, ronda 1, auditor-eaf3d

**Veredicto: RECHAZA** (2 hallazgos MEDIO, bloqueantes).

**Alcance:** el diff con compuerta (src, tests, scripts/research, .claude/{hooks,workflows,agents,settings.json}) está vacío. Su SHA-256 es `e3b0c442…`, el de una entrada vacía, y coincide con el `diff_sha` de `status.json`. Lo staged es solo documentación:
- la entrada «Plan K CERRADO» de `.claude/rules/acople-pv.md`;
- el §6 de `docs/PLAN_K_limitador_en_poisson.md`;
- `report.md`, las revisiones y `status.json`.

Revisé ese texto contra el registro, el código de HEAD y los datos de `campaigns/b1`, solo en lectura.

## Hallazgos

### MEDIO

**MEDIO-1: la regla contradice a C-041.**
- **Dónde:** `.claude/rules/acople-pv.md:629-631` (staged) y `research/ws/WS-K1/report.md:15-16`.
- **Defecto:** el texto dice «No adoptarlo fue una DECISIÓN, no una refutación del beneficio en B1».
  - C-040 pre-registró que Plan K mejora a la base en B1, y C-041 la dio por REFUTADA. La misma viñeta cita C-041 dos líneas antes.
  - La entrada declara que «solo recoge veredictos del registro», y esta frase no es un veredicto del registro.
- **Escenario de fallo:** una sesión que edita `mod_pressure` carga esta regla. Lee que el beneficio en B1 no está refutado y repite el juez con la misma variante, o informa ese estado al usuario en contra del registro.
- **Arreglo:** «No adoptarlo fue una DECISIÓN del usuario (C-065). C-041 refutó la mejora pre-registrada en B1 (C-040); que 2 de 3 trayectorias K mejoraran a la base en 344–345.5 s es una lectura post hoc sin veredicto.»

**MEDIO-2: el reporte describe un diff staged que ya no existe.**
- **Dónde:** `research/ws/WS-K1/report.md:531-637`.
- **Defecto:** la reducción del ciclo 9 (líneas 681-706) es correcta, pero las viñetas de los ciclos 5-8 siguen afirmando en presente cosas que ya no son ciertas:
  - **567-570:** «el diff staged trae lo de los ciclos 6-8». Esa parte se retiró en el ciclo 9.
  - **575-578 y 627-632:** «§6 staged, línea 101, dice "medida solo en k1pa_342"». Hoy dice «medida en k1_342 (v1) y en k1pa_342».
  - **590-592:** la viñeta «no reintentar» llevaría la salvedad de una sola trayectoria (47 frente a 85 %). La entrada staged no la lleva.
  - **595:** «la entrada y el reporte cuentan los mismos cuatro precedentes». La entrada solo nombra D2.2/D2.2c.
  - **608:** stat de «64/12 líneas». El real es 75/35 (numstat 26+49 y 17+18).
  - **617-622 y 635-637:** «la regla permanente lleva la versión nueva» (la identificación por la firma del audit). La regla dice «solo declarado en C-040».
  - **582, 626 y 632:** remiten a «Pendiente del coordinador», una sección que no existe.
- **Escenario de fallo:** el reporte de cierre se archiva como registro. Quien lo consulte para saber qué dice la regla permanente obtiene la respuesta equivocada. Además ve como pendiente la corrección del §6:101, que ya está hecha, y puede volver a editarla.
- **Arreglo:**
  - marcar las viñetas de los ciclos 5-8 como historial superado por el ciclo 9, o borrarlas;
  - quitar las afirmaciones en presente sobre el contenido staged;
  - actualizar el stat;
  - hacer que las remisiones a «Pendiente del coordinador» apunten a «Experimentos que este reporte nombra y que no existen».

### BAJO (no bloqueantes)

- **BAJO-1** (`acople-pv.md:642-643`):
  - **Defecto:** la regla mantiene «No reintentar el conjunto activo con tope exacto…». El propio reporte (322-334) dice que esa directiva es más fuerte que los datos: hay una sola trayectoria (k1b≈k1pb), y en la sonda el tope exacto mejora a la base.
  - **Arreglo:** añadir esa salvedad, o convertir la frase en condición («antes de reintentar, justificar…»).
- **BAJO-2** (`acople-pv.md:638-639`):
  - **Defecto:** la regla asocia D2.2/D2.2c con `pc_limiter_faces`. En HEAD esa clave solo activa el cierre binario D2.2c (`src/mod_pressure_3d.f90:1780`). La configuración la rechaza junto con `pc_transport_f28`, que está activa por defecto (`src/mod_config_3d.f90:606-607`).
  - **Escenario:** quien intente «D2.2 en B1» activando esa clave aborta en la configuración, igual que bench_d22c (C-091).
  - **Arreglo:** anotarlo en la viñeta.
- **BAJO-3:**
  - **Defecto:** el diff quita de la regla permanente dos indicaciones, que ahora solo están en `report.md:356-371`:
    - el experimento decisivo es un juez B1 de 3 o más trayectorias, no la ventana 342.45-342.56 s;
    - antes hay que decir en qué difiere de 4547861, D2.4 y A20-2.

    La regla general de CLAUDE.md (juez estadístico) lo cubre en parte.
  - **Arreglo:** una línea en la entrada que remita a «Qué hacer si se retoma» del reporte.

## Verificado como correcto

- **Diff con compuerta:**
  - está vacío; su SHA es el de una entrada vacía e igual al `diff_sha`;
  - `git diff HEAD` está vacío en src, tests y scripts;
  - `ledger.jsonl` no se modificó, así que «no registra eventos» es cierto.
- **Plan K fuera de src:** 0 archivos con `pc_alpha_implicit`.
- **Commits posteriores:** hay 7 commits de src desde 1bc9832.
- **El parche no aplica sobre HEAD:** el contexto del hunk `mod_pressure_3d.f90 @@ -733` no aparece en el src actual (comprobado sin escribir).
- **Cadena del registro:** coincide con el texto staged.
  - C-012 refutada.
  - C-028 refutada por (b) y (c); (a) pasa solo en la mediana.
  - C-041 refuta C-040.
  - C-294 deja C-064 fallida.
  - C-065 recoge la decisión del 23-oct.
  - C-309 a C-313 son coherentes con el texto.
- **Afirmaciones raíz de WS-K1:** 16 (4 refutadas, 9 fallidas, 3 soportadas), ninguna abierta.
- **p>100k recalculado** con regime2 en las 7 corridas:

  | Ventana | K | Base |
  |---|---|---|
  | 340-342 s | 0.1 % | 2.2-4.1 % |
  | 342-344 s | 1.4-2.4 % | 7.2-10.3 % |
  | 344-345.3 s | 6.4/6.6/9.0/15.1 % | 20.8-35.2 % |

- **Snapshots 345500 recalculados con h5py:**

  | Métrica | K | Base |
  |---|---|---|
  | Líquido en el lecho | 0.1575-0.1589 m³ | 0.1540-0.1547 m³ |
  | Líquido total | 1.0741-1.0747 m³ | 1.0732 m³ |
  | Celdas de lecho con ag < 0.016 y al > 0.05 | 133/130/142 | 117/121 |

- **Historial y referencias:** e250687 introdujo la entrada «Plan K CERRADO» y el §6. Las referencias de línea anteriores a la 615 de acople-pv no se desplazan con este diff.
- **§6 del plan:** dice ya «medida en k1_342 (v1) y en k1pa_342» (la corrección está hecha).

## Orden sugerido de corrección

1. **MEDIO-1:** corregir la frase en acople-pv.md:629-631 y en report.md:15-16.
2. **MEDIO-2:** dejar la sección «registro permanente» del reporte igual al diff real.
3. **BAJO-2, luego BAJO-1, luego BAJO-3:** de una sola línea cada uno; opcionales.
