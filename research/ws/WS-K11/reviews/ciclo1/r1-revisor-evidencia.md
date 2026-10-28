# Revisión de evidencia: WS-K11, ronda 1

**Veredicto: rechaza.** Los números del reporte coinciden con los datos y el veredicto de H13 respeta la letra del criterio C-226. Rechazo porque el reporte deja fuera un dato de la misma corrida que contradice su lectura (O1).

Revisión ciega: no leí `research/ws/WS-K11/reviews/`. Solo hice lecturas: ejecuté medir_centinela.py, centinela.py, check_audit.py y python propio sobre los audit.csv y los .h5. No escribí ningún archivo. `ledger.py check` sale OK (235 eventos).

## 1. Tabla de verificación

| afirmación | reporte | recalculado | estado |
|---|---|---|---|
| k10b_dt025, u_gas_max en los pasos 280002/3/4 | 198.6 / 300.0 / 200.8 m/s | 198.6 / 300.0 / 200.8 | ok |
| k10b_dt025, p_max en los pasos 280002/3/4 | 281 / 461 / 199 kPa | 281.1 / 460.8 / 199.1 | ok |
| k10b_dt025, FAIL de check_audit | sentinel_gas, regime_p (592 kPa), regime_gas | los mismos; p_max 5.916e5 Pa (paso 280161) | ok |
| k10b_dt025, avisos [CG] | 0 | 0 | ok |
| comp_carry del snapshot de 280 s | 0 en todas las celdas | sum de valores absolutos = 0.0 | ok |
| ρ del snapshot frente a la EOS(T_gas, p) | máx. de abs(Δρ/ρ) = 0 | 0.0 (68232 celdas con gas) | ok, pero sin comando (O5) |
| diferencia entre Tg_end y T_gas | máx. 17.7 %, p99 0.2 % | 0.1769 y 0.00217 | ok |
| H12: k11_dt025_tgfix frente a k10b_dt025 | serie 280001-280005 igual a 3 cifras; centinela en el 280003 | igual; primera diferencia en el 280006 (109.8 frente a 109.7); 300.0 m/s y 461 kPa en el 280003 | ok |
| H12: el snapshot tgfix solo cambia Tg_end | (implícito) | solo cambia restart/Tg_end, que es igual a T_gas | ok |
| veredicto C-225 (REFUTADA) frente al criterio C-224 | REFUTADA | u = 300 m/s en el 280003 → REFUTADA por la letra; 0 avisos [CG] | ok |
| masa de la EOS final por unidad de tiempo | 2.92 / 2.88 / 2.87 kg/s | 2.9221 / 2.8824 / 2.8650 | ok |
| diff entre las configs de judge_fh_275 y judge_otp_280 | judge_otp_280 añade las 2 claves | confirmado | ok |
| default ON de las claves el 21-oct | 2f0529b y 8f568fc | 2f0529b es del 21-oct 10:13; **8f568fc es del 22-oct 02:56** | objeción O3 |
| snapshot de 280 s escrito por judge_fh_275 el 20-oct | 20-oct | estado idéntico al de judge_fh_275 (20-oct); el archivo lo reescribió judge_otp_280 el 22-oct (diagnósticos distintos) | objeción O4 |
| pico de los pasos 2-3 con 1 ms | 100 kPa y 163 m/s | 99.6 kPa (280003) y 163.5 m/s (280002) | ok, sin comando (O5) |
| pico de los pasos 2-3 con 0.5 ms | 191 kPa | 191.4 kPa (280003) | ok, sin comando (O5) |
| k11_dt025_s290, máximos en los pasos 290002-290010 | 71.6 m/s y 79 kPa | 71.6 y 79 | ok |
| k11_dt025_s290, pasos con p_max ≥ 100 kPa | 5/235 | 5/235 (290064, 290074, 290075, 290093, 290094) | ok |
| k11_dt025_s290, máximo de toda la ventana | **no se reporta** | **p_max 450.0 kPa y u 128.6 m/s en el 290093; 344 kPa en el 290074** | **objeción O1** |
| k11_dt025_s290, FAIL y avisos [CG] | ninguno; 0 | ninguno; 0 | ok |
| k11_dt025_s290, identidades de masa | pasan | row_volume, decomp y eos_end PASS | ok |
| k11_mo20_s290, control (pasos 2-10) | 124 m/s y 55 kPa; 0/58 | 124.0 y 55; 0/58 | ok |
| k10b_dt025, pasos con p_max ≥ 100 kPa | 120/235 | 120/235 | ok |
| veredicto C-227 (SOPORTADA) frente al criterio C-226 | SOPORTADA | 71.6 < 200, 79 < 300 y 0 avisos [CG] → SOPORTADA por la letra | ok |
| pre-registro antes de las corridas | 096b1ba y d4c07b7 | C-224: 23:44:20 y commit 23:44:28; primer h5 de tgfix 23:44:33. C-226: 23:49:46 y commit 23:49:56; primeros h5 a las 23:50:01 (mo20) y 23:51:12 (dt025) | ok |
| equivalencia de los bancos | misma config salvo restart_file y t_final; mismo binario; 15 ranks | diff de config confirmado; ejecutable campaigns/bin/eaf3d_k10b_opt en todos; 15 procesos | ok |
| k11_base_s290 | 107 m/s y 27 kPa; ya no falla regime_gas; sigue fallando energy_balance | 106.9 m/s y 27.07 kPa; FAIL energy_balance 2.153 | ok (O6: 1 aviso [CG] no mencionado) |
| k10_base y k8_base, 215 m/s en el 280002 | 215 | 215.0 en el 280002 | ok (lectura no pre-registrada, O6) |
| oscilación de u en el control de 1 ms | ~122 / ~77 | 116-124 / 76-80 | ok |

## 2. Objeciones

**O1 (bloqueante): falta en el reporte un dato de la misma ventana.**
- Dato: `campaigns/b1/k11_dt025_s290/audit.csv`, paso 290093: p_max = 450.0 kPa y u_gas_max = 128.6 m/s. En el paso 290074, p_max = 344 kPa.
- check_audit da regime_p con 4.500e+05 Pa, que es el 90 % del límite de 500 kPa. El dato ya está en el registro (C-230).
- Por qué importa: el reporte usa la escalera 100 → 191 → 461 kPa como firma del transitorio de cambio de claves y la tabla de Resultado solo da el máximo de los pasos 2-10. Pero el banco de 0.25 ms desde 290 s, sin cambio de claves, llega a 450 kPa a los 23 ms.
- La frase «no se acerca a la centinela» es cierta para u_gas, pero no para la presión.
- Para levantarla: reportar el máximo de toda la ventana con {C-230} y su comando, y precisar que lo que desaparece es el pico de los pasos 2-3 y la frecuencia (5/235 frente a 120/235), no los episodios de varios cientos de kPa.

**O2 (no bloqueante): factor confundido no declarado.**
- H13 cambia también el instante y el estado del reinicio (280 s frente a 290 s). La letra del criterio se cumple, pero la causa no queda aislada.
- No hay ninguna corrida desde 280 s a 0.25 ms con las dos claves apagadas.
- judge_fh_275 se audita cada 5 pasos (audit_freq 5), así que no registra los pasos 280002-280003.
- Para levantarla: declararlo en Incertidumbre y hablar de compatibilidad, o correr ese control.

**O3 (no bloqueante): fecha de 8f568fc.** El commit es del 2026-10-22 02:56:49, no del 21 de octubre.

**O4 (no bloqueante): origen del archivo de 280 s.**
- `campaigns/b1/judge_otp_280/eaf3d_00280000.h5` lo escribió judge_otp_280 el 22-oct a las 02:57:34 y su sha difiere del de judge_fh_275.
- El estado pronóstico y el grupo restart son idénticos a los de `campaigns/b1/judge_fh_275/eaf3d_00280000.h5` (20-oct).
- Solo cambian los diagnósticos F_lorentz_*, G_rad, S_*. Hay que precisar la redacción.

**O5 (no bloqueante): notas de procedencia sin comando que produzca la cifra.**
- Paso 3: «abs(Δρ/ρ) = 0» no tiene comando, y el comando citado usa `<copia>` y escribe un archivo.
- Paso 6: 100 kPa / 163 m/s / 191 kPa no salen de `diff` ni de `git log`.
- Las reproduje con mi propio python (ver la tabla). Falta un comando de solo lectura para cada una.

**O6 (no bloqueante): lectura presentada como hecho.**
- «Los 215 m/s de k10_base y k8_base eran el mismo transitorio» sale de C-233, que es una lectura no pre-registrada (estado propuesta). Debe marcarse como lectura.
- `campaigns/b1/k11_base_s290/run.log` contiene 1 `[CG] AVISO` (20 iteraciones, res 4.198E-02) que el reporte no menciona.

## 3. Juicio

Por la letra de C-224 y C-226, los veredictos de H12 (REFUTADA) y H13 (SOPORTADA) son correctos y se pre-registraron antes de las corridas. Las configs y el binario son equivalentes salvo la clave probada.

El rechazo se debe a O1: la narrativa de la presión omite un máximo de 450 kPa en la misma ventana. Para aprobar basta con añadir ese dato y matizar la conclusión.

VEREDICTO: rechaza