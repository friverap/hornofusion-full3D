Ronda 2. Apruebo el WS-K9: recalculé desde los datos todas las cifras del reporte y coinciden. Las 4 objeciones de la ronda 1 quedan resueltas; dos de ellas dejan un residuo declarado que no bloquea. Encontré una objeción nueva, menor (O5).

Revisor de evidencia del WS-K9, ronda 2. Todo lo revisé en modo de solo lectura.

## 1. Cifras del reporte frente a lo recalculado

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| m_gas_out con el arreglo (cold_flow_noenergy_n4) | −7.1206e-6 kg | suma de audit.csv = −7.120643e-6 | ok |
| mass_gas_flux_closure con el arreglo | PASS, 1.69e-21 | PASS, 1.69e-21 (check_audit y test_full.txt:2138+) | ok |
| mass_gas con el arreglo | dm 7.0818e-6 frente a 7.1206e-6 | igual | ok |
| run.log: Ejecutable y Compilador | presentes, GCC 16.1.0 | `./bin/eaf3d_mpi`, GCC version 16.1.0 | ok |
| Binario previo: m_gas_out / closure | 0 / FAIL 3.41e-6 | 0 / FAIL 3.41e-06 (coldnoE_binario_previo_check.txt) | ok |
| Binario previo: mass_gas | dm 7.08e-6 frente a 0 | 7.0818e-06 frente a 0 | ok |
| sha256 de eaf3d_k8b_opt | bbe3e11c…81ad3 | bbe3e11c…81ad3, igual a opt_identidad.txt (14:27) | ok |
| sha del diff de src/ | 78797d1c…2ef | igual a `git diff 79dc27b~1 79dc27b -- src` | ok |
| src/ entre 4aa8363 y 79dc27b~1 | sin cambios | 0 líneas; el reflog confirma HEAD = 4aa8363 a las 14:27 | ok |
| mtime de k8b_opt | 14:44:15 | 14:44:15 | ok |
| Config de la reproducción | cold_flow_noenergy menos 3 líneas de cabecera, más output_dir | diff: exactamente eso | ok |
| Log de la reproducción: 4 procesos, sin Ejecutable | sí | sí | ok |
| Golden: 60 PASS con err rel 0 | 60 | 60 (líneas 5087-5149) | ok |
| Único FAIL del test-full | el banco nuevo, no está en el golden | solo la línea 5127 (más el resumen) | ok |
| v132 = v131 + banco nuevo | sí | {cold_flow_noenergy_n4}, 0 métricas distintas | ok |
| v131 anterior al arreglo | 529e96e, 2026-10-22 | ok; sin cambios frente a HEAD | ok |
| test-unit / rebaseline | OK / OK | OK / OK | ok |
| Comparación celda a celda | 60 idénticos, 0 distintos | 60 / 0 / faltan [] | ok |
| Manifiesto de k9_base | d0367a43…81cad | igual en la base y en tests/out | ok |
| tests/out: mtimes y Ejecutable | 19:01:04-19:12:15; 61 run.log | igual | ok |
| Copia de la base frente al binario nuevo | 18:45:28-29 frente a 18:46:16 | igual | ok |
| Banco "casi en reposo" | u_gas_max 0.0 m/s | máximo 7.47e-5 m/s (audit.csv); 0.0 es el redondeo de check_audit | objeción O5 |

No hay predicción pre-registrada. El cambio no toca la solución: solo afecta a la columna de auditoría m_gas_out cuando solve_energy = false. Los 60 bancos existentes no cambian (err 0 frente a v131). La ausencia de predicción es coherente con la regla 3 del README.

## 2. Objeciones

1. **O1 (resuelta).** C-200 corrige C-199. El reporte separa ahora dos evidencias:
   - el golden, para la salida del test-full: `research/ws/WS-K9/logs/test_full.txt:5087-5149`, 60 PASS con err 0;
   - la comparación celda a celda, que se hizo contra la salida del rebaseline.
2. **O2 (resuelta como declaración).** La ruta de la base y su manifiesto ya están citados y los verifiqué. La procedencia queda como declaración del operador. Residuo: `<scratchpad>/k9_base` es efímero. Si se quiere un respaldo persistente, el coordinador puede copiar el manifiesto a `research/ws/WS-K9/logs`; no es obligatorio.
3. **O3 (resuelta).** La cadena hash del ejecutable → `research/ws/WS-K8/logs/opt_identidad.txt` → diff de src/ = 79dc27b se cumple completa. El reflog confirma que HEAD era 4aa8363 a las 14:27.
4. **O4 (resuelta, con residuo declarado).** Las rutas están en la evidencia de C-200. El comando mpirun aparece en C-201, pero no en un archivo. Opcional: guardarlo en `research/ws/WS-K9/logs/coldnoE_binario_previo_cmd.txt`.
5. **O5 (nueva, no bloqueante).** En Incertidumbre, `u_gas_max 0.0 m/s` no lleva fuente. En `tests/out/cold_flow_noenergy_n4/audit.csv`, la columna u_gas_max llega a 7.47e-5 m/s. Corrección propuesta: escribir "u_gas_max ≤ 7.5e-5 m/s" y citar ese audit.csv.

Nota para el coordinador, fuera de la evidencia: `report.md` y `ledger.jsonl` tienen cambios sin pasar a staged (estados MM y AM), así que el `diff_sha` de `status.json` está desactualizado. Hay que volver a pasarlos a staged y recalcular el `diff_sha` antes de `test_quick` y del gate.

VEREDICTO: aprueba