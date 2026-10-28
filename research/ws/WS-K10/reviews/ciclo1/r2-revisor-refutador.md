El veredicto es **rechaza**. La lectura del tercer dt (C-214 y C-215) no sobrevive a dos cosas que ya están en los datos: los intervalos de confianza y el régimen de presión de cada banco.

# WS-K10, ronda 1: revisor refutador

**Qué leí.** `research/README.md`, el reporte actual y las afirmaciones C-196/197 y C-202..215 (`ledger.py show`). También `ledger.py open` y la lista completa de afirmaciones refutadas y fallidas, `.claude/rules/acople-pv.md` (búsquedas por la guardia ALPHA_CUTOFF, M6-1, M7-5 y «por paso»), la sección de WS-K10 de `.claude/rules/transporte-energia.md` y mi propia revisión anterior. Leí además, sin modificarlos, `research/ws/WS-K10/scripts/tasa.py` y los `audit.csv`/`run.log` de `campaigns/b1/k10b_{mo20,dt05,dt025}`, `k8s_mo20` y `judge_otp_280`.

**Cómo trabajé.** Solo lectura: no ejecuté make, mpirun ni corridas; todo es python sobre datos existentes. No leí las revisiones de los otros revisores.

## 1. Conclusiones, alternativas y dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| El paso 280001 es un transitorio; sin él, e(0.5)/e(1) = 0.315 | El transitorio del reinicio dura más de un paso | p_max y e en los primeros pasos | **En parte.** El 0.315 aguanta (con 2 pasos descartados da 0.321). Pero en presión el transitorio sigue después del paso 1: con 0.25 ms, p_max vale 281k, 461k y 199k en los pasos 3-5 y 454k en el paso 12. Con 0.5 ms vale 191k en el paso 4 y 175k en el paso 10. |
| C-214: el error mezcla un 46 % que no depende de dt y una parte que converge como dt^1.6 | El cociente refleja un cambio de RÉGIMEN de presión que depende de dt, no truncamiento | e condicionado a p_max; IC del ajuste | **Sí, y contradice la conclusión.** IC90 de r(0.25)/r(0.5) = 0.71-0.97, de c/r1 = 0.25-0.61 y de p = 0.87-3.9 (bootstrap de bloques 10/20/40; igual con 5/10/20 y 20/40/80). Pasos con p_max ≥ 100 kPa: 0/58, 11/117 y 120/235. e/dt con p_max < 100 kPa: −1.45e-2, −1.02e-2 y **−1.73e-2** kg/s. Con p_max ≥ 100 kPa: +1.3e-3 y +2.0e-3. corr(e, p_max) = 0.15, 0.32 y 0.52. En los pasos tranquilos no hay convergencia. |
| C-214: la caída de r con 0.25 ms es real | Ruido de err_cc concentrado en el primer tercio de la ventana | e/dt por tramos | **Sí.** Con 0.25 ms, e/dt por sextos de ventana vale −3.9e-3, −4.5e-3, −8.5e-3, −9.1e-3, −9.3e-3 y −8.8e-3. Los últimos 2/3 coinciden con el valor de 0.5 ms (≈ −9.0e-3). Lo que mueve el primer tercio es err_cc (+1.55e-3 y +1.21e-3, luego ≈ −2.5e-3), con medias de 8 pasos que oscilan entre +1.5e-2 y −9.6e-3. |
| C-215: Bgq + err_cc y err_liq + A son tasas de signo contrario | err_liq + A contiene una pieza POR PASO, porque crece al bajar dt | Cocientes con IC; ajuste a·dt + k | **Sí.** err_liq + A: 1.038 (IC90 1.004-1.072) y 1.114 (1.072-1.147); crece, y cada vez más. err_liq_lk sigue a·dt + k con k = +2.75e-7 kg/paso: predice 2.316e-6 frente a 2.349e-6 observado con 0.25 ms. Del cambio de r(e) entre 0.5 y 0.25 ms, el 63 % lo aporta err_liq + A. Bgq + err_cc da 0.967 (0.92-1.04): esa parte sí es compatible con tasa. |
| Bgq es una tasa con piso | Pieza de contabilidad (reparto de gadv) que no cambia con el régimen | Brutos de Bgq; Bgq por régimen | En parte: Bgq/dt vale −1.66e-2 con p < 100 kPa y −1.69e-2 con p ≥ 100 kPa (0.25 ms). Es estable; los brutos no están exportados. |
| Br + Bgr < 2 % de e | Cancelación algebraica de la contabilidad | Reevaluar con ρ_it | No; el reporte ya la presenta como condicionada a la contabilidad. Sin objeción nueva. |

## 2. Repeticiones de fracasos registrados

- El workstream es un diagnóstico sin cambio numérico y **no repite** ningún fracaso refutado: ni C-006/007/008/009/010 ni C-106/108/117.
- **Ojo con O2.** Si se adopta que err_liq_lk y A llevan una pieza por paso, se reabre, en otra pieza y con el signo contrario, la idea de C-197 («operación de una vez por paso»), que C-206 y C-211 retiraron. El reporte tendría que decir en qué difiere: aquella era sobre e completo y estaba contaminada por el paso de reinicio; esta es sobre err_liq_lk sin ese paso.
- **Riesgo en el paso siguiente.** Tocar la guardia ALPHA_CUTOFF repetiría M6-1 y M7-5; linealizar gadv en pp se acerca a Plan D. El reporte ya lo señala.

## 3. Objeciones

1. **(BLOQUEANTE) C-214 no se sostiene.**
   - El IC90 de r(0.25)/r(0.5) es 0.71-0.97: cruza las dos bandas de C-212.
   - El IC90 de c/r(1 ms) es 0.25-0.61 y el de p, 0.87-3.9.
   - Además está confundido con el régimen de presión: la fracción de pasos con p_max ≥ 100 kPa pasa de 0 % a 9 % y a 51 %, y en los pasos tranquilos e/dt NO baja (−1.45e-2, −1.02e-2, −1.73e-2).
   - La lectura «~46 % que no depende de dt» ya está copiada como hecho en `.claude/rules/transporte-energia.md`.
   - *Resolución:* retirar o rebajar C-214 en el registro y en las reglas, con los IC por bootstrap de bloques. Dar r condicionado al régimen. Para separar tasa y truncamiento, pre-registrar un experimento con snapshots asentados con cada dt.
2. **(BLOQUEANTE) C-215: err_liq + A no es una tasa.**
   - Crece al bajar dt: 1.038 y luego 1.114, los dos con IC90 por encima de 1.
   - err_liq_lk se explica con exactitud como a·dt + k, con k = +2.75e-7 kg/paso.
   - El 63 % de la caída de r(e) entre 0.5 y 0.25 ms viene de este grupo, no de la convergencia de Bgq + err_cc.
   - *Resolución:* reescribir C-215 y la copia en las reglas. Probar el modelo por paso: un cuarto dt de 0.125 ms, pre-registrado, donde ese modelo predice err_liq_lk/dt ≈ 1.04e-2 kg/s. Partir err_liq_lk entre el limitador y el recorte o derrame; vol_lim baja con dt: 4.2e-3, 2.1e-3 y 1.05e-3.
3. **(BLOQUEANTE) Los tres dt no recorren la misma trayectoria.**
   - p_max medio por décimo de ventana: 32-81 kPa (1 ms), 42-111 kPa (0.5 ms) y 91-175 kPa (0.25 ms).
   - Con 0.25 ms hay picos de 461 kPa en el paso 280004 y de 454 kPa en el 280012.
   - El reporte lo menciona en genérico («cambia la trayectoria») sin medirlo, y los cocientes entre dt se leen como si fueran de la misma física.
   - *Resolución:* añadir la serie de p_max por dt y la fracción de pasos por encima de 100 y de 300 kPa, y declarar el confusor. El veredicto limpio exige snapshots asentados.
   - Lateral: que los picos de presión crezcan al bajar dt es relevante para B1 y merece su propio registro.
4. **(no bloqueante) Las reglas dicen «Siguiente: partir Bgq» sin las condiciones del propio reporte.**
   - Faltan los brutos de Bgq y la condición del sitio: un banco k10b con la config de B1 en 340-345 s, donde el gas libre pesa 0.66 del multifase.
   - Bgq, además, no cambia con el régimen; lo que se mueve es err_cc.
   - *Resolución:* copiar esas condiciones en `.claude/rules/transporte-energia.md`.

## Comprobado por mí

- `tasa.py` (normal y `--grupos`) reproduce la tabla del tercer dt: r(e) −1.4505e-2, −9.145e-3 y −7.424e-3; cociente 0.812; p 1.64; c −6.61e-3; grupos 0.792/0.967 y 1.038/1.114.
- Bootstrap de bloques (semillas 1 y 2; 3000-4000 réplicas):
  - r(0.25)/r(0.5): IC90 0.71-0.97.
  - c/r1: 0.25-0.61.
  - p: 0.87-3.91.
  - err_liq + A: 1.004-1.072 y 1.072-1.147.
  - Bgq + err_cc: 0.763-0.828 y 0.919-1.040.
- Medias por sextos de ventana y medias móviles de 8 pasos de e y err_cc con 0.25 ms (ver tabla de la sección 1).
- e, err_cc, err_liq y Bgq condicionados a p_max < 100 kPa o ≥ 100 kPa en los tres bancos; correlaciones por paso con p_max.
- p_max de los primeros 40 pasos: k10b_mo20 coincide con k8s_mo20 y se parece a judge_otp_280 (alternancia de periodo 2 entre ~24k y ~42k). k10b_dt05 y k10b_dt025 muestran picos de 191k y 461k.
- Ajuste a·dt + k por pieza: err_liq_lk predice 2.316e-6 frente a 2.349e-6; A, 2.80e-7 frente a 3.22e-7.
- `run.log` de k10b_dt025: un único `[RESTART] AVISO ... se acota` (1e-3 → 2.5e-4).
- El reporte de WS-K8 y las reglas ya recogen la retirada de «TASA» (C-210/C-211); esa objeción de mi revisión anterior está resuelta.

VEREDICTO: rechaza