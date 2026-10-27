# Revisión del refutador: WS-K8, ciclo 2, ronda 1

Revisión de solo lectura: no corrí make, mpirun ni simulaciones; usé python solo sobre los `audit.csv` y `run.log` que ya existían. No leí las revisiones de otros revisores, solo mi r3 del ciclo 1.

## Qué verifiqué

**Cifras de C-184 y C-191** (con `barrido_outer.py` sobre k8s_mo20, mo21, mo40 y mo41):
- D1: −2.1053e-5, −2.0429e-5, −2.0777e-5 y −2.0771e-5 kg.
- Dm: −2.1694e-5, −2.1207e-5, −2.1463e-5 y −2.0981e-5 kg.
- Cero `[CG] AVISO` en los cuatro.
- 57/59 pasos no convergidos con 41 externas.

**Cifras de C-192** (con `desfase_residuo.py`):
- corr(D, res_u) y corr(D, res_cont): coinciden con el reporte.
- Extrapolación de D1 a res_cont → 0: −2.065e-5 kg, y −2.000e-5 si se incluye N = 5.
- res_u y res_cont medios: coinciden.

**Orden del pre-registro de C-189.** El commit `d0fc6d9` es de las 16:08:00. `config.dat` de k8s_mo21 y mo41 se creó a las 16:08:06 y `run.log` de mo21 a las 16:08:11. El pre-registro es anterior a las corridas.

**Tabla principal** (k8_cg1000, k8_cg200, k8_mo20 y k8_base):
- Σ|e|_libre y su cociente: 0.863, 0.847, 1.004 y 0.918.
- Cociente del multifase: 0.197, 0.197, 0.203 y 0.339.
- C-110 (rem_all/abs): 0.3156, 0.3155, 0.3186 y 0.4038.
- Por tramos de 20 pasos: 0.320/0.314/0.313 con CG 1000 y 0.323/0.317/0.316 con CG 20. Todo coincide.

**`check_audit`:**
- Fallan `energy_balance` y `regime_gas` solo en k8s_mo5 (2.23 y 214.9 m/s) y en k8_base (2.24 y 215.0 m/s).
- Pasan k8s_mo10, mo20, mo21, mo40, mo41 y mo80, y k8_cg1000.

**Fechas de código y tests.** `src/` y `tests/` no cambian desde las 14:27. Los logs de tests son de 14:29 a 14:43.

## Estado de mis objeciones del ciclo 1 (r3)

| Objeción | Estado | Cómo se resolvió |
|---|---|---|
| O1 (B1 mal atribuido) | Resuelta | C-187: 1.71/1.51 veces con CG 20, sin reparto aditivo |
| O2 (enganche de fase) | Resuelta | Pre-registro C-189 y veredicto C-191, con N = 21 y 41 |
| O3 (relación con C-107/C-109/C-125) | Resuelta en lo formal | Sección «Relación con WS-K4». Ver O1 de esta ronda |
| O4 (dato de la salvedad) | Resuelta | C-192 |

## 1. Conclusiones, mejor alternativa y dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? Qué dice |
|---|---|---|---|
| C-169 refutada por la letra; el 0.197 del multifase no es evidencia de mecanismo | — (el reporte ya acota la lectura) | — | Sí, coincide |
| C-170 sin decidir; converger el CG no mueve el cociente en 59 pasos | La deriva larga (0.314 → 0.349) podría separar CG 20 de CG 1000 | Ventana de 999 pasos con CG 1000 | No existe. El reporte lo declara |
| Con 20 externas, el residuo del CG explica el error del gas libre | El hueco de salida silenciosa del CG | Registrar n_iter y residuo final de cada Poisson | No existe. Declarado. La caída de 11 veces ya en el paso 1, desde el mismo estado, la apoya |
| D es estructural respecto al lazo externo desde 20 externas (C-184, C-191) | (a) Meseta del iterado estancado. (b) La meseta es el error real de masa del gas (piso de C-109) y no un sesgo de la fila | (a) D en pasos donde el lazo sí converge. (b) Separar e del plan por N | (a) Sí: en los 2 pasos convergidos de k8s_mo41, D = −2.18e-5 y −2.16e-5, dentro de la meseta. Apoya la lectura del reporte, que no lo cita (O2). (b) Sí: el plan apenas varía con N (≈ +7.2e-6 kg/paso de 20 a 41 externas; +5.75e-6 a +7.7e-6 en los demás bancos). D(N) es casi entero e_multi(N), y la meseta coincide con C-109 (O1) |
| Con 5 externas, D vale 1.71/1.51 veces la meseta (lectura, no B1) | La meseta podría no ser la misma con 5 externas | Barrido pre-registrado con 5 externas y CG 20 | No existe. El reporte lo declara |
| El almacenamiento artificial es despreciable | — | — | Sí |

## 2. Repeticiones de fracasos registrados

- **Ningún cambio numérico.** No repite D2.2, las reglas D/E/F/G, F2.31 por paso ni n_pc_max.
- **El barrido de C-182 vuelve a medir el piso de C-109.** C-109 midió un piso «estructural, independiente de las externas» de ~1.5e-5 kg/paso; hoy e_multi + e_free vale −1.44e-5 kg/paso con 20 externas. Como el neto del plan apenas cambia con N, D(N) es casi igual a e_multi(N) más una constante.
- **Lo que difiere y es legítimo:** el CG convergido, N hasta 80, el enganche de fase descartado y los residuos registrados. Pero la sección «Relación con WS-K4» presenta rem2 como «otra métrica» cuando solo difiere de e_multi en un término casi constante (O1).
- **Bancos de pocas celdas:** no aplica. Decide el estado de B1 a 280 s, con la malla completa.
- **¿Mueve el problema de sitio?** No aplica: es solo diagnóstico.

## 3. Objeciones

1. **O1 (no bloqueante): la meseta de D es la de e_multi.**
   - El neto del plan apenas cambia con N: +7.2e-6 kg/paso de media de 20 a 41 externas, +7.7e-6 con 80 y con 5 (CG 1000), +6.2e-6 en k8_base y +5.75e-6 con 10.
   - En cambio, e_multi va de −3.09e-5 a −1.72e-5, −1.45e-5, −1.43e-5 y −1.46e-5 kg/paso con 5, 10, 20, 40 y 80 externas.
   - Por tanto, C-182 no separa «sesgo de la identidad de fila» de «error real de masa del gas que el plan no ve». Esto es el piso de C-109.
   - Resolución: el dato ya existe (medias de e, plan y D por banco). Añadirlo al reporte, a la sección «Relación con WS-K4» y al párrafo WS-K8 de `transporte-energia.md`.
2. **O2 (no bloqueante): falta el único dato de un lazo convergido, y el texto se contradice.**
   - Las líneas 351 y 461-465 dicen «no converge en ningún banco», pero la 376 dice que con 41 externas converge en 2 pasos.
   - En esos pasos (280022 y 280058), D vale −2.183e-5 y −2.163e-5 kg, dentro de la meseta.
   - Resolución: citarlo como lectura (2 pasos, sin pre-registro) y corregir la frase.
3. **O3 (no bloqueante): la extrapolación de C-192 tiene muy poco recorrido o depende de N = 5.**
   - Con N ≥ 20, res_cont solo va de 6.5e-6 a 1.27e-5.
   - Hay que precisar que no es evidencia independiente de la meseta.
4. **O4 (no bloqueante, para la siguiente pieza): ¿D es una tasa o un artefacto de una vez por paso?**
   - Con dt fijo de 1e-3 no se puede separar.
   - Resolución: banco a dt = 0.5 ms, 20 externas y CG 1000, desde judge_otp_280, pre-registrado. Si D/dt se mantiene, es una tasa (sesgo de flujo o de fila); si se mantiene D por paso, es una operación por paso fuera del lazo (candidato (i), volfix o recorte).

Ninguna objeción invalida una conclusión tal como está acotada en el reporte. Las cifras que deciden (C-184, C-191) y su orden de pre-registro están verificados, y el alcance sobre B1 queda declarado como no decidido.

VEREDICTO: aprueba