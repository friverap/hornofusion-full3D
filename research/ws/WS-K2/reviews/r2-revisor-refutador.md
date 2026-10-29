# WS-K2, ronda 2: revisión del refutador

Revisión de solo lectura. No se lanzó ninguna corrida; usé python solo para leer los audit.csv existentes.

## Estado de mis objeciones de la ronda 1

| Id | Estado | Comprobación |
|---|---|---|
| O1 (bloqueante) | Resuelta | La regla de aborto y «refutado como mecanismo» pasan a ser lectura sin valor de veredicto. Se citan C-028 (a) con 886 Pa, C-033 y la lectura J-B/H0. Coincide con acople-pv.md:622-642 y con PLAN_K §6 (líneas 94-103). |
| O2 (bloqueante) | Resuelta | Juez de 3 o más trayectorias en 340-345.5 s desde judge_otp_280/eaf3d_00340000.h5. Se excluye diag_p342a por C-290. Remite a 4547861, D2.4 (C-091) y A20-2. Coincide con acople-pv.md:660-666. |
| O3 | Resuelta | Para la variante juzgada en B1, el motivo efectivo es solo C-041. La evidencia del binario queda marcada como circunstancial. |
| O4 | Resuelta | Se nombra diag_k15c/eaf3d_00345150.h5, se verifica el linaje y se añaden la advertencia de C-309 y el brazo k_on de control como propuesta. |
| O5 | Resuelta | f231_340 citado como evidencia parcial. Recalculé las cifras y coinciden: en 340-345.5 s, 345 pasos ≥ 1e6, 51 en la centinela (el primero en 344873) y racha de 82 (345394-345475); en 340-346 s, 482 / 66 / 108 (345481-345588). |

También recalculé el cent_pg partido en 345.318 s. Coincide con la tabla: K 0.15 / 0.08 / 0.76 y 0.0 / 2.2 / 100.0; base 7.21 / 7.89 / 10.24 y 2.7 / 2.2 / 3.8. En 344-345.5 s da K 0.133 / 0.333 / 12.858 frente a base 6.667 / 7.195 / 9.46.

## 1. Conclusiones, explicación alternativa y dato que las separa

- **G2 no se cumplió (estado `fallido`).** C-040 está refutada por la letra (C-041). La alternativa es que el fallo venga de un solo evento de n15 sin causalidad probada. El reporte ya lo dice. El dato que las separa es la base desde diag_k15c/eaf3d_00345150.h5 con un brazo k_on de control; no está en disco. Esto no cambia `fallido`, porque el criterio se aplicó tal como se pre-registró.
- **284.3 y 294.1 s quedan «sin objeto».** El motivo es solo que el Plan K se archivó, no una señal medida. Así queda escrito; nada que objetar.
- **«Alcanzar el tope no separa a K de la base».** La alternativa es que lo propio de K sea quedarse pegado al tope. El reporte la deja sin decidir y usa f231_340 como evidencia parcial en contra. Es correcto.
- **«No hay indicios de que el Plan K mueva el defecto a otra métrica del audit».** La frase va más allá de lo medido; ver O6. En [340, 345.3) las 3 trayectorias K se separan de las 3 base en m_melted (+1.4 % a +1.9 %, sistemático desde los primeros 500 pasos) y en E_gas_volfix: con K hay de 2 a 3 pasos por encima de 5 J y la parte positiva suma de 68 a 81 J; en la base hay 0 pasos y entre 1.1 y 6.5 J. A favor de K, u_gas_max ≥ 300 se da en 10-17 pasos frente a 115-175. Alternativa sin separar: el binario, y no el Plan K, explica la diferencia de m_melted.

## 2. Repeticiones de fracasos registrados

El reporte no propone ningún experimento nuevo que repita un fracaso. Descarta explícitamente combinar K con D2.6 (C-093). Para un margen o barrera continua exige decir antes en qué difiere de 4547861, D2.4 (C-091) y A20-2. No hay repetición sin declarar.

## 3. Objeciones

- **O6 (no bloqueante).** Acotar «otra métrica del audit» a las 4 que se examinaron y mencionar m_melted (K 425.6-427.7 kg frente a base 419.6-419.7 kg) y E_gas_volfix (pasos > 5 J: K 2-3 frente a base 0). **Cómo se resuelve:** el dato ya está en los 6 audit.csv de C-041 con 340 ≤ time < 345.3. Para separar K del binario haría falta una corrida con el binario K y `pc_alpha_implicit=false`, que no existe.

## Archivos

- /Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K2/report.md
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/{k1pa_340_n12,k1pa_340_n14,k1pa_340_n15,judge_otp_280,base_340_n14,base_340_n15,f231_340}/audit.csv
- /Users/frariv/Horno/hornofusion-full3D/.claude/rules/acople-pv.md (618-668)
- /Users/frariv/Horno/hornofusion-full3D/docs/PLAN_K_limitador_en_poisson.md (§6)

VEREDICTO: aprueba