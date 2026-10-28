## Revisión r1, auditor-eaf3d (WS-K11, panel de cierre, ronda 1)

**Veredicto: APRUEBA.** No hay hallazgos ALTO ni MEDIO. Quedan tres objeciones BAJO no bloqueantes.

El diff staged no toca `src/` ni `tests/` (`diff_sha` es el SHA del diff vacío). Lo que se puede revisar como código son tres scripts de solo lectura: `nolink.py`, `pares.py` y `duracion.py`. El resto son el reporte, la regla `.claude/rules/transporte-energia.md` y el ledger (C-277, C-278). He reproducido con lecturas sobre los datos existentes todas las cifras nuevas que introduce el diff.

### 1. Hallazgos

**ALTO:** ninguno. **MEDIO:** ninguno.

**BAJO**

- **B1. La frase «según git» no vale para el binario de k7v4_long.**
  - Dónde: `research/ws/WS-K11/report.md`, ~l.1041-1045, y C-277(3).
  - Lo que es cierto: las asignaciones de `ws_Fc_lk_*` y `ws_Fg_lk_*` en `src/mod_pressure_3d.f90` y `src/mod_workspace.f90` son del 23-sep al 13-oct (git blame).
  - El defecto: `campaigns/bin/eaf3d_k7v4_opt` (25-oct 10:51) se compiló desde un árbol sin commitear. La cabecera de `campaigns/b1/k7v4_long/audit.csv` tiene 110 columnas y termina en `m_gas_e2_nolink`, y ningún commit tiene esa cabecera (antes de 4d8570a acaba en `m_gas_vf_cells`; en 4d8570a, en `m_gas_e2_skip`). Git no puede atestiguar el código del binario, ni siquiera el clasificador `lk_any` (`src/mod_audit.f90:1320-1325`).
  - Escenario de fallo: alguien lee la frase como garantía de que las 360 celdas usan la misma definición de nolink que los reinicios.
  - Arreglo: decir que la fuente del binario no está en git (código del WS-K7 en curso, C-135). Esto refuerza al binario como confusor.
- **B2. «6 brazos con cambio y firma» (`report.md:35-36` y C-277(2)).**
  - `h22.py --todos` da FIRMA en 7 brazos con cambio: k10b_dt025, B, F, G, I, J y tgfix.
  - k10b_dt025 también acaba con nolink (4 celdas, último en 280236).
  - El 6 solo cuadra agrupando F/k10b_dt025, como hace «Un solo linaje», pero esta frase no lo dice.
  - Arreglo: añadir «(F y k10b_dt025 como uno)» o escribir «7, 3 con nolink al final».
- **B3. `research/ws/WS-K11/status.json` (staged).**
  - `test_quick` queda como la cadena `"null"`, no como JSON null.
  - Al reabrir se conservan los tres «aprueba» con `ronda: 1`, que es también la ronda actual. Como `diff_sha` es el SHA del diff vacío (constante para cualquier diff solo de `research/`), no distingue ciclos.
  - Escenario de fallo: si un revisor no registra su veredicto, `/estado` muestra la unanimidad heredada del cierre e5f45e7. `ledger.py gate` falla cerrada (exige `estado=aprobado` y `test_quick=ok`), así que no hay cierre falso por esa vía.
  - Arreglo: subir la ronda o vaciar `revisores` al reabrir.

**Nota informativa, no es defecto:** el bloque fijo de k7v4_long tiene 360 = 6 × 60 celdas, y la malla de B1 tiene `ntheta = 60`. Eso apunta a anillos azimutales completos, es decir, a una clase estructural (pared o fila sellada) más que a un evento localizado. Encaja con la hipótesis «no es el mismo conjunto de celdas» y es una pista barata para PROBE-P.

### 2. Verificado como correcto (no re-auditar)

**Scripts**
- **Filtro de pasos (`nolink.py`, `pares.py`):** `step > p0+1` quita P0 (fila del estado reiniciado, t = 280.001) y el paso 1. Deja 235/239 filas, como el reporte.
- **`nolink.py`:** la ruta acepta un nombre bajo `campaigns/b1` o una ruta completa. Reproduce C-275 completo: k7v4_long con 146 pasos nolink, distribución {1:1, 4:1, 360:144}, 12 tramos, 94/96 y 86/96, y también F, G, I y J.
- **`pares.py`:**
  - F frente a k10b_dt025: 105 = 105 pasos nolink, «mismos pasos nolink: True» (lo cita la tabla).
  - F frente a tgfix: False.
- **`duracion.py`:** solo cambia el docstring; el umbral u ≥ 200 m/s o p ≥ 300 kPa es el de H15.

**C-277**
- **(1) `liq_cont_prev`:** sumas 1620 (rampbelow 255 s), 1707 (A 280.06 s) y 1708-1755 (fh).
- **(1) Config de `judge_e2_275`:** equivale a la de fh; solo cambian el orden y un `audit_freq = 5` duplicado.
- **(2) Final de los brazos:**
  - B: 4 celdas nolink y 109.4-150.1 kPa en sus 20 últimas filas.
  - tgfix: sin nolink desde 280024 y 42.3-104.3 kPa.
  - Medias del último cuarto: 83.9 kPa (tgfix) y 106.8 kPa (k10b).
- **(3) Ventana 284341-284668:** 328 pasos, p entre 35.9 y 85.3 kPa, 7 filas con u ≥ 299 m/s y 0 nolink.
- **(3) Avisos de CG:**
  - El último aviso de k7v4_long acumula 27001 casos.
  - `n_cg_unconv` (`src/mod_solver_3d.f90:273`) cuenta solves.
  - `n_pc_max = 1` por defecto, así que hay un CG por externa y unas 27500 resoluciones en total.
  - Los bancos de 0.25 ms tienen 0 avisos (`k11_base_s290` es de 1 ms).
- **(3) Binario:** fechado el 25-oct, anterior a 4d8570a (26-oct).

**C-278 y otras afirmaciones del diff**
- **C-278:** los 11 recuentos de chatarra sumergida se reproducen exactamente (212, 212, 191, 189, 155, 43, 217, 140, 130, 189, 52). `ALPHA_BED = 1e-2` (`src/mod_constants.f90:75`).
- **G y A:** `dt_min = dt_max = 0.25 ms`, así que G no tiene salto de dt.
- **M-Q:** 0 nolink y 0 pasos con p ≥ 100 kPa también en sus primeras 235 filas.
- **Ledger:** append-only (0 líneas borradas), ids únicos, C-277/C-278 bien formados. C-278 está marcada como «no pre-registrada».
- **Regla de transporte:** 4.67 s = 284.670 − 280.0. Que los 450 kPa de s290 sigan sin diagnosticar está cubierto por C-237(c) y C-245.

### 3. Orden sugerido de corrección

1. **B1:** reformular la frase de git sobre el binario (cambia lo que se infiere).
2. **B2:** precisar el recuento de brazos (6 con F/k10b como uno, o 7).
3. **B3:** higiene de `status.json` al reabrir (ronda o revisores, y null real).
