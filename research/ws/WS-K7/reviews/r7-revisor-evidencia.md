El veredicto de WS-K7 es correcto: con el criterio pre-registrado de {C-144}, k7v5_mo20 queda **sin decidir**. Recalculé desde los datos todas las cifras que sostienen ese veredicto y coinciden dentro del redondeo. Hay 8 objeciones, ninguna bloqueante: son textos desactualizados, un intervalo incompleto, una afirmación que los datos no sostienen y dos cifras sin comando.

Lo verifiqué sin compilar ni correr nada: repetí los cálculos con python3 y csv/h5py sobre los `audit.csv` y los `.h5` existentes, y ejecuté `check_audit.py` y `nogas_vecinas.py`, que son de solo lectura.

## 1. Tabla

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| **{C-145}** k7v5_mo20: cociente por celda (rem_all/abs_multi) | 0.319; por paso mediana 0.317, rango 0.302–0.381 | 0.3186; 0.3171; 0.3023–0.3814 | ok |
| **{C-145}** inciso del neto | 1.571 | 1.5705 | ok |
| Criterio de {C-144}: ≤ 0.3 en ambos incisos soporta, ≥ 0.7 refuta, en otro caso sin decidir | «sin decidir» | entre 0.3 y 0.7, así que sin decidir (literal) | ok |
| k7v5_base: cociente; neto; rango por paso | 0.404; 1.320; 0.377–0.457 | 0.4038; 1.3196; 0.3774–0.4567 | ok |
| Reparto err_liq_all = lk + unl (mo20) | +4.881e-4 = +4.977e-4 − 9.58e-6 | igual; resto 1.2e-20 | ok |
| Σ\|unl\| como fracción de Σ\|e\|; cota con Σ\|err_liq_all\|; fracción del neto | 0.13 %; ≤ 0.19 %; −2.0 % | 0.132 %; 0.194 %; −1.96 % | ok |
| Celdas sin gas: Σ\|ρV_pois\|, Σ\|ρV_eff\|, rej, rej/Σ\|e\|, rej/V_pois | 4.078e-3; 1.1e-16; 7.655e-3; 1.59; 1.88 | 4.0782e-3; 1.087e-16; 7.6547e-3; 1.589; 1.877 | ok |
| Prerrequisitos de C-144: mass_gas_rewrites (mo20/base/1k) y barrido de tests/out | PASS; 78 bancos, 0 FAIL, máx. 4.0e-12 | −6.15e-14 / −7.08e-14 / −5.41e-14; 78/78 PASS, máx. 3.97e-12 | ok |
| Prerrequisitos: liq_skip, e2_skip y bit a bit con k7v4 | 0, 0; sí | 0, 0; 105 columnas idénticas, difieren solo las 5 que dependen de E2 | ok |
| Tablas k7_mo20 / k7_base (e_multi, err_liq, Σ\|e\|, rem, nogas, V_pois, V_eff, 0.566, 2.456, 0.626, 0.856) | ver tabla del reporte | todas coinciden; reproducción con k7v3/k7v4 ≤ 2.42e-16 | ok |
| Tabla k7v3 (4.977e-4, 3.454e-3, 7.85e-4, 84 %, 5.225e-3, 0.319, 1.582, comp_abs, eos_abs) | ver tabla del reporte | todas coinciden | ok |
| Cotas por subconjunto (e_nogas, 0.29, [0.81, 1.29], e_gas, [0.16, 0.42], 58–84 %) | ver reporte | coinciden | ok |
| Cociente de amplitudes y fórmula de la correlación | 7.9e-7 / 3.35e-6 = 0.24; 0.972 | desviaciones poblacionales 7.908e-7 / 3.3496e-6; 0.97173 | ok |
| Tabla k7v4 (1.38, 1.08, 4.0e-4, 2.8e-4, 1.95, 1.93, 51×, correlaciones) | ver tabla del reporte | coinciden | ok |
| k7v4_long: FAIL, tolerancias, nolink, cocientes, correlaciones, tercios, deriva ×1.85, 53 % ≥ 0.7 | ver reporte | todo coincide (6 FAIL; 3.26e-10; 51845 celdas-paso; 0.504/0.712; etc.) | ok |
| Tramos de 500 pasos (k7v4_long) y de 200 pasos (1k) | ver tablas | las 11 + 5 filas coinciden | ok |
| R1: identidad de fila, rej, cociente con vol_lim, insensibilidad a las externas | ver reporte | coinciden (corr(rej, paso) 0.0996) | ok |
| ρ_g medio, masa reconstruida, mediana nogas, tamaños 6.4 / 8.5 / 10.1 / 13.5 % | ver reporte | 0.30428; 52.9735; 0.2275; mismos % | ok (E5: falta comando) |
| Composición y dirección (5 snapshots, tolerancias 1e-6 / 1e-3 / 5e-3) | ver reporte | coinciden con `nogas_vecinas.py` | ok, salvo E3 |
| «7.1–8.1 % con la clase estricta» | 7.1–8.1 % | 7.1–17.0 % (280000 da 17.0 %) | objeción E3 |
| u_z del líquido en nogas (p10 / mediana / p90) | −0.28 / 0.01 / +0.76 | −0.283 / 0.0107 / 0.757 | ok (E5) |
| C-151: cotas y porcentajes | 0.1165; ≥ 48 %; ≥ 24 %; no muerde | 0.11653; 48.06 %; 24.05 %; 1.54e-3 y 3.64e-2 | ok |
| Bancos sin líquido: Σ\|e\|, e_multi y Σ\|e\|/Σ\|eos\| | ver reporte | coinciden | ok |
| outer_conv_n8 como «piso estructural» | ~1e-3/paso, «piso» | decae de +1.2e-3 a −3.1e-5 en 10 pasos | objeción E4 |
| CG: avisos de no convergencia; k7_base | ≥ 1001 (3.2e-2); un aviso | 1001 con res 3.245e-2; un aviso | ok |
| Logs de tests y conteos en test_full | OK; 67 / 64; máx. 3.97e-12 | OK; 67 / 64; 3.97e-12 / 3.985e-12 | ok |
| Identidad del binario | sha 28a31905… | shasum coincide; sha del diff staged igual al del log | ok |
| mtimes «hoy 13:04:15» | 13:04:15 | 16:57:25 / 18:14:49 | objeción E1 |

## 2. Objeciones (ninguna bloqueante)

1. **E1 — fechas desactualizadas.** `report.md:205` dice «hoy mtime 13:04:15» para `src/mod_audit.f90` y `tests/integration/check_audit.py`; hoy son 16:57:25 y 18:14:49. `report.md:214` dice que el binario se compiló «tras la última edición de src/ 13:04:15», pero `mod_audit.f90` se editó después (solo comentarios).
   - La correspondencia del binario con el código sí está probada por hash (ver tabla).
   - **Para levantarla:** poner las fechas actuales y citar `logs/opt_identidad.txt`.
2. **E2 — predicción equivocada en el texto.** `report.md:301` dice que la predicción del cierre es {C-135} con veredicto {C-139}. `status.json` dice `prediccion: C-144`, y la cabecera del propio reporte (:91-92) también da C-144/C-145.
   - **Para levantarla:** escribir C-144/C-145.
3. **E3 — intervalo incompleto.** En `report.md:154` (Dirección), «7.1–8.1 %» deja fuera el snapshot 280000, que da 17.0 % (208 de 1226 caras).
   - **Para levantarla:** escribir 7.1–17.0 %.
4. **E4 — afirmación que los datos no sostienen.** `report.md:295` llama «piso multifase estructural» a lo que deja `outer_conv_n8`.
   - En `tests/out/outer_conv_n8/audit.csv`, `m_gas_err_multi` por paso vale +1.16e-3, −1.38e-3, +1.07e-3, +1.20e-3, +1.09e-3, +9.6e-4, +7.4e-4, +5.4e-4, +1.9e-4, −3.1e-5.
   - Es un transitorio que decae y cambia de signo; 10 pasos en frío no bastan para llamarlo piso.
   - **Para levantarla:** reformularlo como transitorio, o medirlo en un banco más largo.
5. **E5 — cifras sin comando.** ρ_g medio 0.304 y la masa reconstruida 52.97 kg (`report.md:154`), la mediana 0.228 en nogas, y los percentiles de u_z (`report.md:253`) citan la ruta pero solo describen el cálculo en prosa.
   - Las reproduje y son correctas.
   - **Para levantarla:** añadir el comando o un script.
6. **E6 — pre-registro sin commit.** {C-144} no está commiteado (desviación ya declarada en :293): HEAD 6579277 solo llega a C-121.
   - El orden sí se comprueba: C-144 13:01:46 < binario 13:06:13 < `k7v5_mo20/audit.csv` 13:07:00 < C-145 13:38:13, y `ledger.py check` da OK.
   - **Para levantarla:** el coordinador commitea el registro antes de la próxima corrida pre-registrada.
7. **E7 — líneas sin rótulo.** `report.md:292` cita `src/mod_pressure_3d.f90:1668-1686` y `:808-813` sin rótulo. Son líneas del diff staged (en HEAD, `face_open` está en :1651-1669), en contra de la convención de :289 («sin rótulo = HEAD»).
   - **Para levantarla:** rotularlas como «diff staged».
8. **E8 — no verificable, ya declarado.** No pude verificar:
   - las cifras de la primera corrida (Proceso 7 y {C-123});
   - el «PASS con tolerancia 1e-9» de :157/:159;
   - los tests y el rebuild, salvo por sus logs (no puedo ejecutar `make`).

   Ninguna de estas cifras sostiene el veredicto. **Para levantarla:** mantenerlas rotuladas como históricas, como ya están.

## 3. Juicio

- **Veredicto contra el criterio:** «sin decidir» es la lectura literal del criterio de {C-144}. El reporte no lo reinterpreta: el umbral de correlación de {C-135}, fijado después de ver el dato, está declarado (O5), y las expectativas (i)–(iii) se informan como lo que son, sin decidir nada.
- **Prerrequisitos:** se cumplen todos.
- **Equidad de la comparación:** mismo reinicio, mismas configs salvo la clave probada, y la numérica es idéntica bit a bit a k7v4.
- **Límite de la muestra:** está declarado. Son 59 pasos con transitorio inicial, y las ventanas largas derivan hacia la refutación; el reporte dice que el veredicto vale para esos 59 pasos, no para el régimen.
- **Sesgos y fallos de banco:** están declarados con su cifra. `k7v5_base` y el banco de 1000 pasos no pasan `check_audit`.

VEREDICTO: aprueba