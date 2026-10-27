# Revisión del refutador, WS-K8 (ronda indicada por el harness: 1; el reporte ya trae la corrección de la ronda 2)

Revisión de solo lectura. Leí lo siguiente:
- el reporte, C-110, C-125, C-133, C-145, C-150, C-154, C-163 y C-168..C-180;
- `.claude/rules/acople-pv.md` (Plan D/E, D2.4) y el párrafo WS-K8 de `.claude/rules/transporte-energia.md`;
- `src/mod_audit.f90:1088-1110`, `src/mod_pressure_3d.f90:540-640` y `:860-900`, y `src/mod_solver_3d.f90:238-280`.

Recalculé con csv los `audit.csv` de k8_{cg1000,cg200,mo20,base} y revisé `run.log` y `opt_identidad.txt`. Mis objeciones r1 (O1 a O7) están incorporadas (C-177 a C-180) y las verifiqué en los datos.

## 1. Conclusiones, alternativa y dato que las separa

| Conclusión | Mejor alternativa | Dato que separa | ¿Está? Qué dice |
|---|---|---|---|
| C-169 REFUTADA por la letra (gas libre 0.863) | — (veredicto formal correcto) | — | Sí |
| «El 0.863 es un piso de conversión, no un término que falte» | Al plan le falta un término real: su_cc lleva fsat·gadv y el plan resta gadv entero (`mod_pressure_3d.f90:625-632` frente a `mod_audit.f90:1100`); además ρ del iterado frente a la final y el acarreo | rem2_libre partido por fuente | No. La meseta 2.0e-4 / 2.1e-4 solo descarta el CG (O3) |
| Inciso por celda 0.197 = cierre de identidades | — (ya acotado, C-178/C-180) | — | Sí |
| C-110 no se mueve con el CG (0.3186 → 0.3156) | Trayectorias casi idénticas: no dice nada de la deriva larga | 999 pasos con CG 1000 | No; el reporte lo acota bien |
| Con 20 externas, el CG explica el error del gas libre | — | paso 1: 9.8e-6 frente a 7.5e-7 | Sí. Con 5 externas el paso 1 da 1.73e-4: allí domina el lazo externo (consistente con «no medido en B1») |
| **Neto multifase = desfase constante de rem2, independiente del CG, «sesgo de la identidad de fila»** | **Truncamiento del lazo externo**: el desfase depende de las externas | barrido de max_outer con CG 1000 | **En parte sí, y contradice la atribución.** Media −3.28e-5 (5 externas) frente a −2.17e-5 (20). Paso 1, mismo estado y CG 20 en ambas: −3.60e-5 frente a −2.11e-5 (O1) |
| corr(e, plan) = 0.93 «el plan sigue a e» | Es por construcción: eos − rx compartido (sd 3.24e-5, diez veces la de e) y las partes no compartidas correlacionan 0.999 por la identidad de fila | ya está | Sí: el 0.93 no es evidencia (O2) |
| Almacenamiento artificial despreciable | — | — | Sí (PP_COMPLIANCE = 1e-6 activo; D2.4 inactivo, ya declarado) |
| Neto ≈ entrada por el outlet: retirado | — | — | Sí (k7v5_mo20_1k) |

Además: m_gas_ccdrop vale ~1.4e-7 kg/paso (0.6 % del desfase), así que el acarreo descartado no es el origen.

## 2. Repeticiones de lo ya registrado
- El inciso por celda repite el diseño criticado en C-154. Ya está reconocido (C-178/C-180).
- La correlación por paso de 0.93 vuelve a caer en ese mismo defecto, ahora como correlación (O2).
- Ningún arreglo numérico (cambio solo de diagnóstico): no repite D2.2, D/E/F/G, F2.31 ni n_pc_max.

## 3. Objeciones
1. **O1 (bloqueante).** El desfase neto depende del lazo externo.
   - Datos: −3.28e-5 ± 0.45e-5 con 5 externas frente a −2.17e-5 con 20; en el paso 1, desde el mismo estado, −3.60e-5 frente a −2.11e-5.
   - Lo que el texto no puede sostener: «no depende del CG / vive en un sesgo sistemático de la identidad de fila». El siguiente paso propuesto (partir los corchetes con 20 externas) tampoco separa un sesgo estructural del truncamiento externo, y B1 corre con 5 externas.
   - Resolución:
     - declarar la dependencia (el dato ya existe) y retirar la atribución en la regla;
     - pre-registrar un barrido de max_outer 5 / 20 / 40 con CG 1000 desde judge_otp_280, con el residuo externo registrado;
     - una meseta entre 20 y 40 indica sesgo estructural; si sigue bajando, es truncamiento;
     - la partición de rem2 debe correr en ese barrido.
2. **O2 (no bloqueante).** Hay que retirar corr(e, plan) = 0.93 como evidencia y dejar el hecho sustantivo: la sd de rem2 es el 6 % de su media.
3. **O3 (no bloqueante).** «Piso de conversión, no término que falte» es una hipótesis. El código muestra un término que el plan omite, (1 − fsat)·gadv. Hay que redactarlo como hipótesis en el reporte y en la regla y, para decidirlo, medir rem2 por fuente (columnas pre-registradas).

VEREDICTO: rechaza