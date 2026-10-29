# Revisión de evidencia: WS-K2, ronda 2 (revisor-evidencia)

**Resultado: apruebo.** Los números del reporte se reproducen desde los datos y el veredicto sobre C-040 aplica a la letra el criterio que se registró antes del experimento. Las seis objeciones de la ronda 1 están resueltas. Quedan tres erratas nuevas, ninguna bloqueante.

Alcance: solo lectura. Usé `ledger.py show|check`, `regime2.py`, python (csv/h5py) sobre los audit.csv y snapshots que ya existen, `cmp`, `diff`, `ls` y `sed`. `ledger.py check`: OK (313 eventos).

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| Inciso (i) 344–345.5 s, cent_pg por trayectoria con K | 0.133/0.333/12.8, media 4.42 | 0.133/0.333/12.8, media 4.422 | ok |
| Inciso (i), mitad de la media de la base | 3.89 (6.667/7.2/9.467) | 3.889 | ok (falla también max K 12.8 > 9.467) |
| cent_pg [344,345.318) | K 0.15/0.08/0.76; base 7.21/7.89/10.24 | 0.152/0.076/0.759; 7.208/7.891/10.243 | ok (post hoc, rotulada) |
| cent_pg [345.318,345.5] | K 0.0/2.2/100.0; base 2.7/2.2/3.8 | 0.0/2.186/100.0; 2.747/2.186/3.825 | ok |
| Pasos con p_max ≥ 1e6 en judge_otp_280 | 1 (1.056e6 en 345266) | 1 (1.0563e6 en 345266) | ok |
| Pasos con p_max ≥ 1e6 en base_340_n14 | 4, tope desde 344641 | 4, 2e6 en 344641 | ok |
| Pasos con p_max ≥ 1e6 en base_340_n15 | 19, tope desde 344797, racha 2 | 19, 344797, racha 2 | ok |
| k1pa_340_n12 y _n14 | 0 (máx. 3.30e5 en 340026) | 0, 3.303e5 en 340026 | ok |
| k1pa_340_n15 | 183 seguidos 345318–345500, 122 en el tope | 183 (345318–345500), 122 | ok |
| vol_lim medio [340,345.3) | K 2.524–2.530e-3; base 2.541–2.548e-3 | 2.5245–2.5298e-3; 2.5413–2.5479e-3 | ok |
| vol_unlinked medio | K 2.097–2.104e-3; base 2.071–2.086e-3 | 2.0968–2.1041e-3; 2.0708–2.0861e-3 | ok |
| Suma de m_spill | K 2.3–7.1e-11; base 1.04–1.22e-10 | 2.28–7.13e-11; 1.0449/1.0909/1.2220e-10 | ok |
| Suma de m_alpha_clip | K 5.1–8.3e-11; base 5.6–7.8e-11 | 5.08–8.31e-11; 5.62–7.75e-11 | ok |
| diag_k15_k_off | salto 345311; 1.797e6 en 345320; 10 pasos ≥ 1e6 | igual (11 filas, 345310–345320) | ok |
| diag_k15_k_on | salto 345318; 1.812e6 en 345320 (fin del brazo) | igual | ok |
| k1pa_340_n15 tras el salto | 1.734e6 en 345325; 2.0e6 en 345326 | igual | ok |
| C-309, max\|p\| en h5 de k_off | 2.000e6 (345311, 345312), 1.851e6 (345318), índices (1,56,7-8); 6.07e5 con signo | 2e6/2e6/1.851e6; (1,56,8) y luego (1,56,7); max con signo 6.072e5 | ok |
| f231_340, 340–345.5 s | 345 / 51 / primero 344873 / racha 82 (345394–345475) | igual | ok |
| f231_340, 340–346 s | 482 / 66 / 108 (345481–345588) | igual | ok |
| diff de config base_340_n14 vs f231_340 | 117c117, 119c119, 121a122 | igual | ok |
| Linaje diag_k15c | 5151 filas idénticas | 5151/5151 | ok |
| Linaje diag_k15d | 181 filas con p_max y m_gas; 180 completas; la 345150 difiere «solo en E_src_*» | 181 y 180 sí; la 345150 difiere en 43 columnas | **objeción O7** |
| dt del paso 345150 de n15 | 1.0e-3 | 1.0e-3 | ok |
| C-014, filas | 41 y 30 | 41 y 30 | ok |
| C-014, cent_pg | 9.8→0 y 6.7→0, gas 300 | igual (regime2) | ok |
| C-027 | 340–342: 0.5 > 0.3 | 0.5 frente a 0.3 | ok |
| Afirmaciones raíz de WS-K2 | 22: 7 soportadas, 7 refutadas, 8 fallidas | igual, mismos ids | ok |
| cmp base_340_n1{4,5} = dense_340_n1{4,5}, run.sh → eaf3d_head_e5d331e_opt | sí | sí | ok |
| eaf3d_k1pa_opt ausente; sin run.sh en k1pa_340_* ni en judge_otp_280 | sí | sí | ok |
| diff de config base vs k1pa | 117c117, 121a122,123 | igual | ok |
| Líneas [PLAN-K] | 5; 104/143/114 sin converger de 25000 | igual | ok |
| «difieren desde la primera fila» | primera fila | la fila 340000 es idéntica; difieren desde la 340001 | **objeción O8** |
| Marcas de tiempo de los config.dat k1pa_340_* / k1pa_342/audit.csv | 18:15:48 / 18:14:03 | igual | ok |
| Referencia a la lectura de WS-K1 | report.md:208–221 | ahora en 228–242 | **objeción O9** |
| acople-pv.md:626–642 y 659–666; PLAN_K 72–73 y 94–99 | citas | coinciden | ok |
| Enunciados citados del registro (C-025, C-028, C-033, C-037, C-039, C-065..C-073, C-076, C-078, C-093, C-279, C-287, C-290, C-294) | citas | coinciden | ok |

## Juicio frente al criterio pre-registrado (C-040)

- **El veredicto se aplica a la letra.** El inciso (i) en 344–345.5 s falla por la media (4.422 > 3.889) y por el máximo (12.8 > 9.467). El inciso (iii) falla porque k1pa_340_n15 llega a 2.0e6. El reporte no reinterpreta el criterio: las lecturas descriptivas (corte en 345.318 s, comparación con la base, f231_340) están rotuladas sin valor de veredicto.
- **La comparación es justa.** Los seis brazos y f231_340 reinician desde judge_otp_280/eaf3d_00340000.h5 y llegan a 345.5 s (f231_340 a 346.0). Los brazos k_on y k_off salen ambos de diag_k15d/eaf3d_00345310.h5.
- **Límites de los datos, declarados por el reporte.** No se pueden verificar los binarios de judge_otp_280 ni del brazo K. Los brazos de unos 10 pasos son demasiado cortos para medir la persistencia de n15. Ninguno de los dos brazos sirve de control limpio.
- **El estado `fallido` se sostiene** con C-041 y C-064, como dicen C-065..C-073.

## 2. Objeciones

**Resueltas de la ronda 1:** O1, O2, O3, O4, O5 y O6, comprobadas contra el texto actual y contra las fuentes.

**Nuevas (no bloqueantes):**

- **O7.** `campaigns/b1/diag_k15d/audit.csv`, paso 345150. El reporte dice que difiere de n15 «solo en las columnas E_src_*». En realidad difiere en 43 columnas: todos los acumuladores por paso (E_src_*, E_arc_direct_sol, E_mc_deposit, m_melted, m_alpha_clip, m_spill, vol_lim, vol_unlinked, m_gas_out, m_vf_*…). p_max y m_gas sí coinciden, así que el linaje no cambia.
  - Para levantarla: escribir «difiere solo en acumuladores por paso, no en p_max ni m_gas».
- **O8.** `campaigns/b1/k1pa_340_n1{4,5}/audit.csv` frente a `base_340_n1{4,5}/audit.csv`. No difieren «desde la primera fila»: la fila del paso 340000 es idéntica, y `cmp` da la primera diferencia en la línea 3 (paso 340001).
  - Para levantarla: escribir «desde el paso 340001».
- **O9.** La referencia `research/ws/WS-K1/report.md:208–221` (y la fuente `sed -n 201,221p`) quedó obsoleta: ese reporte se editó a las 01:39:56. La lectura del redactor sobre 4547861/D2.4/A20-2 está ahora en las líneas 228–242.
  - Para levantarla: actualizar las líneas o citar el bloque por su título.

Ninguna de las tres cambia una cifra que sostenga la conclusión ni el veredicto.

VEREDICTO: aprueba