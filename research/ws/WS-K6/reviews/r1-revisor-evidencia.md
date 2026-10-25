# Revisión r1 — revisor-evidencia — WS-K6

Recalculé cada número desde los datos. Solo leí archivos; las únicas herramientas fueron `check_audit.py` sobre directorios existentes (no escribe nada) y python/csv propio. Archivos fuente:

- `campaigns/b1/{k5,k6,sonda_gc}_{mo20,base}/audit.csv`
- `research/ws/WS-K6/logs/*.txt`
- `research/ws/WS-K5/logs/test_full.txt`
- registro: C-116, C-117, C-118 y C-119

## Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| (1) p_max, m_gas, E_liq, E_gas y u_gas_max de k6 iguales bit a bit a sonda_gc_* | 60 renglones | idénticos en 60 renglones (280000-280059), en mo20 y en base | ok |
| (1) solo difiere m_gas_volfix | 15/60, \|Δ\| ≤ 5.3e-23 | 15/60, máx 5.294e-23 | ok |
| (1) misma config | configs de k5 | diff = solo output_dir; reinicio judge_otp_280/280000; 15 ranks | ok |
| (2) cierre en k6 | -6.1e-14 / -7.1e-14 kg | -6.140e-14 / -7.094e-14 | ok |
| (2) bloques [audit] / sin flujo / cierres | 76 / 9 / 64 (49 + 15) | 76 / 9 / 64; 61 − 9 − 3 = 49 base + 15 reinicios | ok |
| (2) los 64 dentro de la tolerancia de C-117(2) | sí | sí, peor \|cierre\|/tol = 0.29 | ok |
| (2) 3 sin balance | bath_fill_mix_n4, bath_mix_n4, oneflow_test_n4 | los mismos | ok |
| (3) mass_gas_vf_cells | 64 PASS, «diferencia 0.0» | 64 PASS; dif = 0 solo en 53/64, máx \|dif\| 3.33e-15 (k6: 0.0) | **objeción O1** (no bloqueante) |
| (4) cold_bucket2_slag_n1 | multi -0.0173, EOS 0.0177 (antes -1.739) | -0.01732 / 0.01773, cociente 0.98 ≤ 2; K5: -1.739 | ok |
| (4) cold_bucket2_n4 | +0.0626, EOS 0.756 (antes -10.40) | 0.06263 / 0.7561, cociente 0.083; K5: -10.40 | ok |
| (5) multifase k6_mo20 | -8.554925e-4 | -8.5549254e-4 | ok |
| (5) multifase k5 exacta | -8.685537e-4 | -8.6855367e-4 | ok |
| (5) diferencia contra el valor exacto de k5 | 1.306e-5 | 1.30611e-5 | ok |
| (5) diferencia contra -8.686e-4 | 1.3108e-5, exceso 7.5e-9 | 1.310746e-5, exceso 7.46e-9 | ok |
| (5) volfix total / en celdas libres | 1.310e-5 / 4.1e-8 | 1.3102e-5 / 4.09e-8 | ok |
| (5) columna libre | 2.1794e-5 → 2.1835e-5 | 2.17937e-5 → 2.18346e-5 | ok |
| (5) volfix / columna | 1.5 % | 1.53 % | ok |
| FAIL previos en k6_base | energy_balance 2.24, regime_gas 215 | 2.243 y 215.0, idénticos en sonda_gc_base; k6_mo20 sin FAIL | ok |
| (6) tests con golden v131 | OK | UNIT / quick / full OK; metrics_v131.json, rtol 1e-12 | ok |
| Pre-registro antes de compilar | C-117 18:03:05 | src/ editado 18:03:31-18:03:51; corridas k6 18:05-18:06; src/ intacto desde entonces | ok |

## Veredicto de la predicción contra el criterio literal

C-117(5) pide |multifase − (−8.686e-4)| ≤ 1.31e-5 kg. El valor obtenido es 1.310746e-5, que no cumple. El reporte y C-118 declaran la predicción **refutada en la letra** sin enmendar el criterio. No hay ninguna `enmienda` registrada y el texto no reinterpreta el resultado. La frase «la lectura de B1 no cambia» es una interpretación física aparte y no toca el veredicto.

Los incisos (1), (2), (3), (4) y (6) se cumplen, y los verifiqué de forma independiente. El veredicto registrado respeta el criterio pre-registrado.

## Justicia de la comparación

- Mismo punto de reinicio (judge_otp_280, paso 280000).
- Misma ventana: 59 pasos, 280.001-280.06 s.
- Mismas configs.
- Mismo código salvo el diagnóstico: el diff de src/ solo agrega `audit_volfix_cell` en las 6 rutas y la resta en `audit_gas_cells`.
- La base es la correcta: k5 para la columna y sonda_gc para la numérica.

La muestra de 59 pasos es corta, y el reporte lo declara en «Incertidumbre». Para un cambio solo de diagnóstico con identidad bit a bit basta.

## Objeciones

1. **O1 (no bloqueante).** `research/ws/WS-K6/logs/test_full.txt`: mass_gas_vf_cells tiene dif = 0.00e+00 en 53/64 evaluaciones; las otras 11 llegan hasta 3.33e-15 kg. El reporte (inciso 3) y C-118 dicen «diferencia 0.0». Todas pasan la tolerancia de C-117(3). Para levantarla: corregir el texto a «0.0 en k6_* y en 53/64; resto ≤ 3.3e-15 kg».
2. **O2 (no bloqueante).** Las notas de procedencia de (1), (4) y (5) no dan un comando ejecutable, solo describen la operación. Los números se reproducen con python/csv (`rows[1:]`, suma por columna). Para levantarla: añadir un one-liner o la invocación de `check_audit.py --config`.

Ninguna de las dos cambia un veredicto ni un número de los que depende el criterio.

VEREDICTO: aprueba