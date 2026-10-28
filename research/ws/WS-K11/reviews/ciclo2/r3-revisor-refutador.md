## Revisión del refutador, WS-K11, ronda 1

Revisión de solo lectura: python se usó únicamente para leer audit.csv y h5 ya existentes.

### Verificado con los datos
- `h22.py --todos` reproduce la tabla de firma de los 19 brazos: 12 sin cambio de f28 sin firma; F, G, B, I y J con firma; P y Q sin firma.
- Los 19 brazos usan el mismo binario (`campaigns/bin/eaf3d_k10b_opt`) y 15 ranks (1×5×3), según el run.log.
- P y N difieren de A solo en el reinicio, f28 y t_final. k10b_mo20, dt05 y dt025 difieren solo en dt.
- C-263 y C-264 se registraron en el commit 8b2d95b (10:42:49). El run.log de M nació a las 10:42:55, después.
- nolink vale 0 en el paso P0+1 en todos los brazos, así que excluir el paso 1 no oculta nada.
- `m_gas_cells_nolink` no depende de cfg%pc_transport_f28 (`src/mod_audit.f90:1318-1335`).

### 1. Conclusiones y alternativas
| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| Encender f28 sobre un estado escrito sin ella es NECESARIO para la firma | Lo que importa es la **edad** del cambio, no quién escribió el estado | Reiniciar desde un snapshot escrito con f28 en el transitorio (B o F, eaf3d_*0236) | Indirectamente, sí. B y F acaban con nolink 4 y p_max 110-150 kPa en las últimas 20 filas. El reinicio reproduce la corrida continua a 2e-12 (k11_base_s290 frente a judge_otp_280). Se predice firma en un brazo «sin cambio» → **R1** |
| NO suficiente (P, fh 300 s) | (a) P arranca de un snapshot de fin de corrida (00299999), el único fh con comp_carry de 2.26e-5; (b) efecto de dosis | Repetir P con comp_carry = 0, o con otro estado fh | En parte. Las celdas del lecho justo en su tope bajan de forma monótona en fh: 300, 128, 108, 87, 66 → **R2** |
| Lo que distingue «escrito sin f28» | Celdas del lecho exactamente en su tope (f28 las congela con hueco 0) | Proporción de celdas en tope sobre cercanas al tope | Sí. fh ≈ 0.97-1.0; jb/otp ≈ 0.5-0.6; F y B a los 59 ms ≈ 0.5 con nolink aún activo → **R3** |
| La presión total no es necesaria ni suficiente | Que no sea suficiente solo está probado en 280 s | Un brazo con solo la presión total en 285-295 s | No → **R4** |
| U_GAS_MAX sola no identifica el cambio | — | L | Sí, sostenido |
| El régimen de f28 no explica las paradas de B1 | — | Una trayectoria por linaje; lo dice el propio reporte | Sostenido como enunciado negativo |
| El pico de k10b_dt025 lo causa f28 y no el acotado de dt (L muestra que acotar dt solo ya da un transitorio) | — | A (fh 280 s, dt acotado, sin f28): 69 m/s | Sí, A lo separa |

### 2. Repeticiones de fracasos registrados
El workstream es de diagnóstico, sin cambios en `src/`. No repite D2.2, ni las reglas locales D/E/F/G, ni n_pc_max = 3, ni M20-2 (separar el hueco congelado). La recomendación de reiniciar con las mismas claves no es un arreglo numérico. Queda como contexto, que el reporte ya señala: la adopción de f28 (2f0529b, ventana 280-281.6 s) se midió con un reinicio que la encendía, es decir, con el mismo artefacto.

### 3. Objeciones
- **R1 (bloqueante).** La necesidad y la recomendación de «reiniciar desde un snapshot escrito con las mismas claves» solo están probadas con f28 establecida ≥ 5 s. Un snapshot escrito en los primeros 60 ms tras el cambio (por ejemplo k10b_dt025/eaf3d_00280236.h5, con las claves de su escritor) arrastraría la firma por continuidad: última fila de B y F con nolink 4 y p_max de 110-150 kPa; reinicio determinista a 2e-12. **Resolución:** acotar el texto a «f28 establecida ≥ 5 s (mínimo probado)» citando esas filas. Opcional: 60 ms desde k11_b…/eaf3d_00290236.h5, o la prolongación de ≥ 300 ms ya propuesta.
- **R2.** La no suficiencia depende de P, el único brazo con snapshot de fin de corrida y comp_carry ≠ 0, y el mínimo de celdas en tope. **Resolución:** anotarlo en Incertidumbre; para separarlo, P con comp_carry puesto a 0, u otro estado fh.
- **R3.** R4 solo descarta poros sobrellenados (room < 0, que no aparecen en ningún snapshot). Sí hay una huella de linaje: celdas del lecho exactamente en su tope (fh 300/305 … 66/66 frente a jb/otp 149/276 … 39/62). Esa huella se borra a los 59 ms con f28 (F 138/287, B 57/102) mientras nolink sigue. **Resolución:** citarla como variable candidata y, con PROBE-P, comprobar si las primeras celdas nolink son vecinas de celdas exactamente en su tope.
- **R4.** Indicar en el titular dónde se probó la presión total («no suficiente en 280 s»).
- **R5.** Añadir que la firma (nolink) es propia de 0.25 ms; con 1 ms, el dt de B1, no aparece.

Cálculo de R2 y R3, solo lectura sobre los h5. room = max(1 − α_s − α_sl − pore_floor(α_s), 0) − α_l; lecho: α_s ≥ 0.01; líquido continuo: α_l ≥ 0.01; «en el tope»: room ≤ 1e-6; «cercana al tope»: room ≤ 1e-3. Snapshots: judge_otp_280/00280000, judge_fh_275/00285000-00299999, judge_jb_275/00280000-00299999, judge_otp_280/00290000 y 00300000, y k11_f/k11_b/k10b_dt025 *_0236.

VEREDICTO: rechaza