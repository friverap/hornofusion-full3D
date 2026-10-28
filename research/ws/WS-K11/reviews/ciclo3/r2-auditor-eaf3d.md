# WS-K11, panel de cierre ronda 1: auditor-eaf3d

**Veredicto: RECHAZA.** Hay un hallazgo MEDIO (M1) y es de una sola frase: la regla persistente atribuye a f28 un efecto que el propio reporte declara confundido con el linaje. Lo demás que se puede comprobar con los datos coincide con el reporte.

Alcance del diff staged: no toca `src/` ni `tests/`. Por eso `status.json` lleva `diff_sha` = sha256 vacío (e3b0c442…), lo que concuerda con `ledger.py:269` (hash del staged de src/ y tests/), y `numerico = false`. El código revisado son dos scripts nuevos (`pares.py`, `duracion.py`), el párrafo WS-K10/WS-K11 de `.claude/rules/transporte-energia.md`, los eventos C-265..C-271 del registro y el reporte. Todo lo ejecutado fue lectura: los scripts con python3 sobre audit.csv y HDF5 existentes, sin escribir nada. No leí `reviews/`.

## Hallazgos

### MEDIO

**M1. La regla atribuye a f28 lo que no se separa del linaje** (`.claude/rules/transporte-energia.md:399-401`)

> Sin cambio, f28 con 0.25 ms tampoco es tranquila: jb 280 s sube de 28 a ~80 kPa alternando; sin f28 queda plano en 14.5 kPa.

Medido por cuartos, sin el paso 1 (media de p_max / |dp|, en kPa):

- **f28 apagada, todos del linaje fh:**
  - A 14.5-14.4 / 0.0
  - H 14.5-14.4 / 0.0
  - M 14.4-14.1 / 0.0
  - N 17.1-14.6 / 0.0
  - O 17.6-14.8 / ≤ 0.1
- **f28 establecida, todos jb/otp:**
  - C 76-80 / 11-18
  - K 66-71 / 16-21
  - L 31-42 / 8-9
  - Q 34-52 / 20-27
  - k11_dt025_s290 y D (tabla del reporte) también alternan

f28 y linaje coinciden por completo. El reporte lo reconoce (`report.md:566-567`), pero la regla no.

- **Escenario de fallo:** un workstream posterior toma de la regla que «f28 sube el nivel con 0.25 ms» y decide sobre esa base.
- **Arreglo:** escribir el contraste con su confusor, sin corrida nueva (texto propuesto en la objeción M1).

### BAJO

- **B1** (`transporte-energia.md:382-384`; `report.md:20-21` y `815-816`). «"Sin cambio" y "f28 establecida ≥ 5 s" van juntos en los 19 brazos» es falso tal como está escrito: A, H, M, N y O no tienen cambio y tampoco tienen f28. Hay que restringirlo a los brazos con f28 encendida.
- **B2** (`transporte-energia.md:390-391`; `report.md:372-374`). «Solo actúa con reflujo» no es exacto. `src/mod_pressure_3d.f90:1001-1027` relaja toda abertura con electrodo y gas hacia p0 = rho_g·g·(zf−z) aunque u_in ≤ 0 (`outlet_total_pressure`, 2008-2016). El objetivo sigue a rho_g sin que haya reflujo, así que no está medido que el ~2.5e-7 de m_gas venga del reflujo.
- **B3** (C-269). La primera fila de nivel centinela de `k7v4_long` es el paso 284340 (t = 284.341 s), no el «284341». Además, «desde 284.669 s» es un número de paso: su tiempo es 284.670 s. El desfase es de 1 ms; basta un evento de corrección.
- **B4** (`report.md:110-111`). «A, el único con f28 apagada» quedó desactualizado: H, M, N y O también la tienen apagada y también quedan planos.
- **B5** (`transporte-energia.md:422-425`). El paréntesis de los bancos de 1599 filas queda dentro de «que reinician de judge_otp_280/…». En realidad reinician de `judge_fh_275/eaf3d_00280000.h5`.

## Verificado como correcto (no re-auditar)

- **`h22.py --todos`** reproduce el veredicto de los 19 brazos. Las firmas, nolink, pasos ≥ 100 kPa, max p_max y max u_gas_max coinciden con las tablas de los pasos 12-13 y con C-265 y C-266. Todos tienen cero `[CG] AVISO`. H22 queda SOPORTADA y H23 REFUTADA. La ventana de 239 filas de M-Q, G y I-L está declarada.
- **`pares.py`** es correcto: pasos comunes, 11 primeros = pasos 0-10, y nolink sin P0 ni P0+1. Salidas:
  - C/E: 7.9e-9, 1.5e-9 y 2.6e-7
  - k10b_dt025/F: 1.1e-9, 3.5e-10 y 2.5e-7
  - A/H: 2.0e-9, 7.4e-10 y 2.5e-7
  - Diferencia en la ventana: 12 % en u de C/E.
- **`duracion.py`** es correcto: filtro `> P0+1`, umbrales 200 m/s y 300 kPa, último paso relativo a P0. Reproduce la columna de la tabla del paso 12 (G 9/7, paso 27; I 99/55, 232; J 187/74, 226; L 3/0, 4).
- **Uniones de umbrales:** con u ≥ 200 o p ≥ 300 kPa, G 11, F 8, B 18, I 101, J 187, L 3 y s290 2. Con nivel centinela (u ≥ 299 o p ≥ 300 kPa), G 7, F 6, B 9, I 73, J 120, L 2 y s290 2.
- **Pasos ≥ 100 kPa por cuartos:** F/k10b 31,21,32,36; B 58,59,59,59; J 57,49,60,53; G 27,0,0,0; I 59,6,22,55.
- **nolink bajo 100 kPa:** 34 (F), 8 (G), 1 (I), 2 (J).
- **Max p_max sin nolink:** 380, 91, 634 y 2000 kPa.
- **Últimas 20 filas:** B nolink 4 y p 109-150 kPa; F nolink 1-4 y p 104-156 kPa.
- **Pares de configuración** (diff ordenado): A/F, M/I y O/J difieren solo en `pc_transport_f28`. N/B difiere en las dos claves y en t_final (290.061 frente a 290.06). C/E y A/H difieren solo en la presión total. P/Q difieren solo en `restart_file`.
- **`k7v4_long`:**
  - 146 pasos con nolink, entre 284669 y 285379, hasta 360 celdas, y ninguno en 280001-280031.
  - En la ventana 284669-284728: 59 pasos con nolink, 45 con p ≥ 100 kPa, 30 con u ≥ 299 m/s y p_max 152.7 kPa.
  - Su configuración es la de `judge_otp_280` salvo `restart_file`, t_final y salida.
- **C-251 y C-270:**
  - Filas de nivel centinela cada 5 pasos en 280-295 s: fh 15, jb 1, otp 26.
  - `scrfh_base`: 42 filas en 281461-281502.
  - `scrfh_b`, `m21f1_280` y `otp_280`: 0 filas.
  - `m202_280`: 5 filas (280003, 021, 025, 029, 033); u = 136.7 m/s en 280002; p = 156.0 kPa en 280003; tras 280031, max 66.1 kPa frente a 51.3.
  - u = 215.0 m/s en 280002 en seis bancos.
  - Eventos en 280001-280031: 0-1 en siete y 9 en `m202_280`.
- **C-271, `comp_carry` (suma |·| y celdas):** 0 en fh 280, 285 y 290 s y en A 280.06 s; 1.46e-9 (2 celdas) en fh 295 s; 2.26e-5 (1) en fh 299.999 s; 8.06e-5 (16) en rampbelow 255 s.
- **Registro:** 271 eventos y ningún id duplicado; JSON válido.

## Orden sugerido de corrección (uno por uno)

1. M1: una frase de la regla (bloqueante).
2. B1: misma zona de la regla y del reporte.
3. B2: redacción de la presión total en la regla y el reporte.
4. B4 y B5: limpieza de redacción.
5. B3: evento de corrección en el registro, con `--ref C-269`.
