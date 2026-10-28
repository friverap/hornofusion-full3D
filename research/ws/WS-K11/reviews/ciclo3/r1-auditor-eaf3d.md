## Revisión WS-K11, ronda 1: auditor-eaf3d

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Dejo cuatro objeciones BAJAS que no bloquean.

### Alcance del diff staged
- No hay cambios en `src/` ni en `tests/`: `git diff --cached -- src tests` sale vacío. Por eso `status.json` tiene `diff_sha` = sha256("") (e3b0c442…), y es correcto: `ledger.py` calcula el hash solo sobre el diff staged de `src/` y `tests/`.
- Sí entran en el diff:
  - `.claude/rules/transporte-energia.md`: el párrafo WS-K10/WS-K11.
  - 4 eventos añadidos al final de `research/ledger.jsonl` (C-265..C-268), sin ninguna línea borrada.
  - `report.md`.
  - Dos scripts de solo lectura: `scripts/pares.py` y `scripts/duracion.py`.
  - `status.json` y las revisiones de los ciclos 1 y 2. Esas revisiones no las leí, porque la revisión es ciega.

### Hallazgos

**ALTO:** ninguno.

**MEDIO:** ninguno.

**BAJO**

**A1. Mecanismo de `pc_outlet_total_pressure` mal descrito**
- Dónde: `.claude/rules/transporte-energia.md`, viñeta de la clave, y `report.md:342`.
- Qué dicen: «solo actúa con reflujo».
- Qué hace el código: en `src/mod_pressure_3d.f90:1001-1027` y `2008-2016`, con la clave encendida, toda celda de abertura con electrodo y alpha_g ≥ 1e-2 se relaja en cada iteración hacia `p0 = rho_g·g·(zf−z)`, calculado con la ρ_g ACTUAL, también cuando el gas sale (u_in ≤ 0 → t = p0). Sin la clave, esa celda es Dirichlet fijo.
- Escenario de fallo: al reiniciar con la clave encendida sobre un estado escrito sin ella, el ancla se mueve sin que haya reflujo. Una verificación bitwise en un banco sin reflujo daría diferencias que se atribuirían mal.
- Lo que sigue valiendo: las cifras medidas (≤ 1e-8 en u_gas_max y p_max; 2.5e-7 en m_gas).
- Arreglo: reescribir la frase. Ver la objeción A1.

**A2. El nivel de ~80 kPa se atribuye a f28 sin separarlo del estado**
- La regla dice: «jb 280 s sube de 28 a ~80 kPa alternando; sin f28 queda plano en 14.5 kPa».
- El problema: el control sin f28 es el estado fh (A, M, N, O), no jb. `report.md:519-522` reconoce que no está separado.
- Lo medí con los audit.csv: Q (jb 300 s) da 51.7 → 34.1 kPa por cuartos y D (otp 300 s) 37.8 → 28.2 kPa. El nivel de ~80 kPa no generaliza.
- Arreglo: añadir la salvedad a la regla.

**A3. Cifra de m_gas inconsistente**
- La regla dice «m_gas ~3e-7». `pares.py` da 2.5-2.6e-7 y el reporte dice ~2.5e-7.
- Arreglo: unificar en ~2.5e-7.

**A4. Robustez de `pares.py`**
- `r[:11]` se etiqueta como «pasos 0-10», lo que solo es correcto con audit en cada paso. Además, divide sin protección contra cero.
- No afecta a las cifras del reporte: todos los bancos comparados se auditan en cada paso, con 237 pasos comunes.

### Lo verificado como correcto (no hace falta re-auditarlo)

**Ejecuté los scripts staged y recalculé desde los `audit.csv`.**
- `pares.py`, pasos 0-10:
  - C/E: 7.9e-9 en u_gas_max, 1.5e-9 en p_max, 2.6e-7 en m_gas; 12 % en u_gas_max en la ventana.
  - k10b/F: 1.1e-9, 3.5e-10 y 2.5e-7; 105 pasos con nolink en cada uno.
  - A/H: 2.0e-9 y 2.5e-7; 0 pasos con nolink.
- `duracion.py`: G 9/7, último paso 27; I 99/55, último 232; J 187/74, último 226; L 3/0, último 4; K y H en 0.
- Uniones con el umbral «u ≥ 200 o p ≥ 300 kPa»: G 11, F 8, B 18, I 101, J 187, L 3, s290 2. Con el umbral «u ≥ 299 o p ≥ 300 kPa»: 7, 6, 9, 73, 120, 2 y 2. Coinciden con el paso 12 del reporte.
- Pasos ≥ 100 kPa por cuartos: F y k10b 31/21/32/36; B 58/59/59/59; J 57/49/60/53; G 27/0/0/0; I 59/6/22/55; P 0/0/0/0. Coinciden con C-268.
- Últimas 20 filas: B y F terminan con nolink 4 y p_max de 104-156 kPa.

**H22/H23 (`h22.py`):**
- M, N y O sin firma: máx. 15, 18 y 20 kPa; 92.3, 68.9 y 61.2 m/s. P sin firma (96 kPa, 130.0 m/s). Q sin firma (95 kPa, 89.9 m/s).
- H22 SOPORTADA y H23 REFUTADA, que coincide con C-265 y C-266.
- Cero `[CG] AVISO` en los cinco brazos y 0 FAIL en `check_audit.py`.
- Los `run.log` de M a Q se crearon entre las 10:42:55 y las 11:15:45, después del commit de pre-registro `8b2d95b` (10:42:49), que ya contenía `h22.py`.

**Pares de configuración (`diff config.dat`):**
- M/I, O/J y A/F difieren solo en `pc_transport_f28`.
- N/B difiere en las dos claves, además de t_final (290.061 frente a 290.06). Eso confirma la corrección de alcance de C-268.
- A/H difiere solo en la presión total. k10b/F difiere solo en la presión total.
- P usa la config de F y Q la de C; solo cambian restart_file y t_final.
- G es A con f28 encendida, reiniciando desde su eaf3d_00280236.h5.

**Lista de bancos afectados (C-251):** todos los bancos de WS-K5 a WS-K8 y WS-K10 que reinician de `judge_otp_280/eaf3d_00280000.h5` llevan explícitamente f28 = true y outlet = true, y su audit empieza en 280000. Las únicas excepciones son los brazos k11 A, F y H, cuyas claves son intencionadas.

**Filas de nivel centinela de B1 (280-295 s, cada 5 pasos):** fh 15, jb 1 (288680), otp 26.

**Con 1 ms:** p_max se asienta en el paso 280024 (otp) y 280031 (k10b_mo20), y u_gas_max en el 280017 y el 280013. Los ciclos de 2 pasos son 23.2/43.3 y 27.6/49.0 kPa.

**Columna nolink en el código** (`src/mod_audit.f90:1318-1335`):
- Las banderas `ws_Fc_lk_*` y `ws_Fg_lk_*` se ponen a cero (`mod_pressure_3d.f90:208,214`) y se intercambian por halos (876, 912) antes de leer las caras i-1, j-1 y k-1 en la frontera de bloque.
- El contador se reduce con allreduce (`mod_audit.f90:751`).
- La firma no tiene, pues, artefactos de frontera de bloque ni de rank.

**Ledger:** los eventos se añaden al final, sin borrar nada. C-267 corrige las etiquetas y el duplicado de C-262.

### Orden sugerido de corrección (uno por uno, solo redacción)
1. A1: mecanismo de la presión total, en la regla y en `report.md:342`.
2. A2: salvedad jb frente a fh en la regla.
3. A3: unificar ~2.5e-7.
4. A4: filtro por paso en `pares.py` (opcional).
