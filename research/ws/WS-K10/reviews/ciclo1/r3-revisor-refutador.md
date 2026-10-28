El veredicto es **rechaza**, por dos objeciones bloqueantes que se resuelven con texto y datos que ya existen, sin corridas nuevas:
- el banco de 0.25 ms dispara la centinela de gas, y el reporte no lo dice;
- el titular «0.32, por debajo de la banda de tasa» no resiste el propio confusor de régimen del reporte.

# WS-K10 (ciclo 2), ronda 1: revisor refutador

**Qué leí.** `research/README.md`, el reporte actual, C-196..C-221 (`ledger.jsonl`), `ledger.py open` con las refutadas y fallidas, `.claude/rules/acople-pv.md` (centinelas, régimen y «Lo que NO funcionó»), la entrada WS-K10 de `transporte-energia.md`, la corrección en `research/ws/WS-K8/report.md` y mi revisión anterior del refutador. No leí las revisiones de los otros revisores.

**Cómo trabajé.** Solo lectura: python sobre `campaigns/b1/k10*/audit.csv` y `run.log`, más `check_audit.py` y `cmp_comunes.py`, que solo leen. No hay un `docs/PLAN_*` específico del tema.

## 1. Conclusiones, alternativas y dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| Instrumento exacto y sin cambio numérico | El cierre lo fuerza la tolerancia | Restos frente a tolerancia; columnas comunes | Sí, y la confirma: decomp 2.9e-14 a 1.2e-13 kg frente a tolerancias ≥ 1.4e-11; row_volume 2.2e-14 m³; `cmp_comunes` da 61 idénticos; test-full OK (solo XFAIL conocidos). |
| El 66 % del error con 0.5 ms está en el paso de reinicio con dt acotado | Cualquier reinicio produce ese pico, no el acotado | e en el paso 1 con 1 ms, que no se acota | Sí, y la confirma: con 1 ms el paso 1 vale −1.37e-5, igual a la media (−1.45e-5). Con 0.5 ms vale −1.06e-3 y con 0.25 ms −1.59e-3. |
| Sin ese paso, e baja más que linealmente (0.32, por debajo de la banda [0.35, 0.65]) | Es una tasa y el 0.32 lo producen el 9 % de pasos con p ≥ 100 kPa, donde e > 0 | e condicionado a p_max < 100 kPa | **Sí, y la debilita.** En los pasos tranquilos el cociente por paso es 0.352 (por unidad de tiempo 0.705, IC90 0.65-0.78 con bloques móviles y 0.66-0.82 sin solapar): en el borde de la banda. De 0.5 a 0.25 ms el cociente por paso es 0.41, dentro de la banda. → **O2** |
| C-212 sin decidir; tres dt no separan tasa de truncamiento | La comparación ni siquiera es de la misma física: con 0.25 ms el acople sale del régimen sano | Centinelas y régimen en check_audit | **Sí, y el reporte lo omite.** k10b_dt025 da FAIL en sentinel_gas (u_gas 300 m/s en el paso 280003, p_max 461 kPa), en regime_p (592 kPa) y en regime_gas. Ese paso tiene e/dt +8.55e-2 kg/s; sin él, r(0.25)/r(0.5) = 0.855. → **O1** |
| err_liq + A crece por unidad de tiempo al bajar dt | El crecimiento es efecto del régimen | La misma pieza con p < 100 kPa | En parte. Crece igual, pero menos: 1.021 y 1.070 (IC90 1.03-1.10) frente a 1.038 y 1.114. La k de err_liq_lk baja a la mitad. → O3 |
| Bgq domina la media; apenas cambia con el régimen | Es contabilidad del reparto de gadv | Las magnitudes brutas de sus dos términos | No exportadas; el reporte ya lo declara. Bgq 0.25/0.5: IC90 0.915-0.990 sin solapar (se sostiene). |
| k10_base: el gas libre pesa 0.66 del multifase | — | — | Es lectura. Falta decir que k10_base/k10b_base dan FAIL en energy_balance y regime_gas, heredados de k8_base. |

## 2. Repeticiones de fracasos registrados

- Es un diagnóstico sin cambio numérico. **No repite** C-006/007/008/009/010 ni C-106/108/117.
- H10 (el error está en la densidad posterior al Poisson) es pariente de C-106..C-109 («la EOS reescribe»; C-109 lo dejó como estructural). No es una repetición: es la medida exacta que faltaba.
- **Repetición de método.** C-212 volvió a comparar dt desde el mismo snapshot de 1 ms, con el confusor del reinicio ya conocido por C-206, y descartó solo un paso. El reporte ya lo reconoce y pide snapshots asentados. Ojo: con 0.25 ms la presión sigue alta en toda la ventana. Es posible que no exista un estado «asentado» común a los tres dt, y el pre-registro debería contemplarlo.
- La hipótesis k de err_liq_lk ya está distinguida de C-197 (correcto).

## 3. Objeciones

1. **O1 (BLOQUEANTE).** El reporte omite que el banco de 0.25 ms dispara la centinela de gas U_GAS_MAX (paso 280003) y da FAIL en regime_p (592 kPa) y regime_gas.
   - Según acople-pv.md, que salte una centinela es la señal de que el acople se rompió.
   - Ese paso pesa: sin él, r(0.25)/r(0.5) pasa de 0.812 a 0.855.
   - Que bajar dt lleve a la centinela en 3 pasos es un dato para B1 que no está registrado.
   - *Resolución:* añadir los FAIL de check_audit de k10b_dt025 (y de k10_base/k10b_base) al reporte y al registro; dar el cociente sin el paso con centinela; registrar la observación lateral.
2. **O2 (BLOQUEANTE).** El titular «baja más que linealmente, 0.32, por debajo de la banda» se rompe al aplicarle el confusor de régimen del propio reporte.
   - En los pasos con p_max < 100 kPa da 0.352 por paso (IC90 por paso ≈ 0.33-0.39): en el borde.
   - Con el tercer dt, 0.41 por paso (dentro de la banda), y en los pasos tranquilos e/dt crece ×1.69.
   - Está copiado como hecho en transporte-energia.md y en WS-K8.
   - *Resolución:* reformularlo como «0.32 con todos los pasos, 0.35 en los tranquilos: no decidido» en el reporte, en C-210/C-211, en las reglas y en WS-K8.
3. **O3.** err_liq + A y la k de err_liq_lk dependen del régimen: 1.070 frente a 1.114, y k = 1.35e-7 frente a 2.75e-7. La predicción para 0.125 ms cambia de 1.04e-2 a ≈ 9.4e-3.
   - *Resolución:* dar las cifras condicionadas y fijar el régimen en un futuro pre-registro.
4. **O4.** C-196 («tasa» por la letra) arrastra el mismo confusor; el reporte dice que «no cambia».
   - *Resolución:* calcular D con p < 100 kPa y anotarlo.
5. **O5.** Los IC90 dependen del método: bloques móviles 0.71-0.97 frente a bloques sin solapar 0.445-1.013, con solo unos 5 bloques independientes.
   - *Resolución:* declarar el método en cada exclusión. La de Bgq se sostiene con los dos (0.915-0.990).
6. **O6.** La regla llama «sin disputa» al peso < 2 % de la densidad posterior al Poisson, que el reporte declara condicionado a la contabilidad.
   - *Resolución:* copiar la condición en la regla.

## Comprobado por mí

- `check_audit` sobre k10_{mo20,dt05,base} y k10b_dt025:
  - decomp y row_volume dan PASS (eos_end «no medido» en los k10_*);
  - k10b_dt025 da FAIL en sentinel_gas, regime_p y regime_gas;
  - k10_base, k10b_base y k8_base dan FAIL en energy_balance y regime_gas;
  - k10b_mo20, k10b_dt05, k8s_mo20 y k8s_dt05 no dan ningún FAIL.
- `[CG] AVISO` = 0 en k10_mo20, k10_dt05 y k10b_dt025.
- u_gas_max por paso: 163.5 (1 ms), 188.3 (0.5 ms) y 300.0 (0.25 ms, paso 280003; 6 pasos ≥ 200).
- e en el paso 1: −1.37e-5 (1 ms, igual que el resto), −1.06e-3 (0.5 ms) y −1.59e-3 (0.25 ms).
- Medias por régimen y desde t ≥ 280.010/020 de e, err_liq + A, err_liq_lk, Bgq, err_cc y vol_lim/dt (este último ≈ 4.2 en los tres dt: el limitador es una tasa).
- Bootstrap con bloques móviles y sin solapar, con todos los pasos y solo con los tranquilos.
- La entrada WS-K10 de las reglas ya retira C-214/C-215 y copia las condiciones (resuelve mi O4 anterior). El reporte de WS-K8 lleva la corrección de C-206/C-211 en la cabecera.

VEREDICTO: rechaza