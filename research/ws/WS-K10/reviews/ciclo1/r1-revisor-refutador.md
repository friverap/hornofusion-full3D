# WS-K10, ronda 1: revisor-refutador

Leí: `research/README.md`, el reporte, C-196/197 y C-202..209 (`ledger.py show`), `ledger.py open`, `.claude/rules/acople-pv.md` (convenciones, «Lo que NO funcionó», 22-oct y Oct-2026), el diff staged de `src/mod_pressure_3d.f90`, `src/mod_audit.f90` (piezas, `gface`), `gas_adv` y las llamadas que le pasan el caudal, y los `audit.csv`/`run.log` de `campaigns/b1/k10_*`. Solo leí; los análisis son python sobre datos que ya existían. No leí las revisiones de los otros revisores.

## 1. Conclusiones, alternativas y dato que las separa

| Conclusión del reporte | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| El 0.93 de C-197 era el transitorio del reinicio | Sigue habiendo transitorio después del paso 1 | e sin el paso 1 y sin los pasos 1-2; mitades de la ventana | Sí. Sin el paso 1 da 0.315 y sin los pasos 1-2, 0.321. Las mitades son estables (e de 0.5 ms: −4.73e-6 / −4.42e-6). Las dos ventanas cubren el mismo tiempo físico (59 ms). D sigue en 0.380. **Se sostiene.** |
| El error «escala como una TASA» | Error de truncamiento temporal, O(dt^~0.7) por unidad de tiempo, que converge, más quizá una tasa residual | Un tercer dt | No. e(0.5)/e(1) = 0.315 ± ~0.02 (dt^1.67 por paso), fuera de la banda «tasa» [0.35, 0.65] de C-194/C-202. Br2/Bgr: 0.18 (dt^2.46). Una tasa pura (0.5) queda excluida con ~9 desviaciones estándar. **No se sostiene tal como está escrita.** |
| Bgq domina e con los dos dt | Bgq es un desplazamiento casi constante que err_liq compensa en parte, y su talla depende de la contabilidad de gadv (err_cc resta ρ_f dt gadv y Bgr + Bgq lo suman) | Magnitudes brutas dt Σ ρ_it gadv y dt Σ gq; coincidencia espacial con err_liq | En parte. Bgq: sd/|media| 0.06-0.07; corr(Bgq, e) por paso 0.07 / −0.03; corr(Bgq, err_liq) +0.08 / −0.48 / −0.37 (1 ms, 0.5 ms, base). Las magnitudes brutas no se exportan. |
| Bgq = ensamblaje frente a corregido + caras de ALPHA_CUTOFF; lo siguiente es partir por la guardia | La parte de ensamblaje es A8 con el caudal PREDICHO (`af·u_f·A`) frente al corregido (`Fg + ag·Δpp`). Es ∝ pp del último outer: residuo del lazo externo estancado (C-184) | Bgq frente al número de externas; término (q*−q)(ρ_N−ρ_P) por cara | En parte: 5 externas −3.79e-5 frente a 20 externas −2.25e-5 (×1.68). La correlación con los residuos globales de [STEP] es débil. |
| Br + Bgr neto = 0.012 e: la densidad posterior pesa ~0 | La cancelación es algebraica: Br2 + Bgr = (ρ_pre−ρ_f)(X − dt gadv) − …; err_liq, err_cc y A también llevan ρ_f | Reevaluar err_liq, err_cc y A con ρ_it | No. |

## 2. Repeticiones de fracasos registrados

- El workstream es un diagnóstico sin cambio numérico. **No repite** ningún fracaso. Además encaja con C-117, C-106 y C-108, ya refutadas (volfix y reescritura de la EOS): Br neto ~0.
- **Riesgo en el paso siguiente.** La guardia ALPHA_CUTOFF de `gas_adv` existe por M6-1 (−3.6e4 veces el volumen en slag_chem_flow) y por M7-5 (caudal fantasma). Quitarla o relajarla repetiría esos fallos. Linealizar gadv en pp dentro de la fila queda cerca de Plan D.

## 3. Objeciones

1. **(BLOQUEANTE) «TASA».** e da 0.315 por paso: dt^1.67, y 0.63 por unidad de tiempo. Br2/Bgr da 0.18. Ambos quedan fuera de la banda que el propio proyecto llama «tasa». Con dos dt no se separa una tasa de un error de truncamiento que converge; con un ajuste lineal, la parte que no depende de dt sería ~26 % del valor con 1 ms. La etiqueta ya está en `.claude/rules/transporte-energia.md` y en el reporte de WS-K8, y orienta el trabajo siguiente.
   *Resolución:* un tercer dt (0.25 ms), con un snapshot de ese dt o descartando el paso del acotado en el pre-registro. Hasta entonces, un evento que corrija C-206 y C-207 y reescribir la frase en los tres sitios: «decrece con dt más rápido que lineal por paso; no se distingue tasa de truncamiento».
2. **Bgq «domina» la media, no la explica.** Es casi constante y no se correlaciona por paso con e, cuya variación lleva err_cc. err_liq compensa el 57 % y el 94 % de Bgq. Además, su talla depende de cómo se repartió gadv entre err_cc y Bg*.
   *Resolución:* exportar dt Σ ρ_it gadv_used y dt Σ gq por clase, añadir una columna de Bgq en las celdas con err_liq ≠ 0 y matizar la frase.
3. **La parte de ensamblaje de Bgq es ∝ pp del último outer** (A8 explícito en pp). Ya hay una señal con las externas (×1.68 de 20 a 5).
   *Resolución:* que el pre-registro siguiente parta Bgq en tres: caras de la guardia, (q*−q)(ρ_N−ρ_P) y cambios de sentido. Correrlo con 20, 40 y 80 externas.
4. **Repetición potencial de M6-1 y M7-5** si el arreglo toca la guardia.
   *Resolución:* el pre-registro dice en qué difiere, con slag_chem_flow y bath_fill como prerrequisito.
5. **Sitio.** La lectura es de 280 s, 59 ms, una trayectoria y 20 externas. En la config de B1 (k10_base) el gas libre pesa 0.63-0.66 del multifase y lo dominan err_cc_free y store_free. No hay vínculo medido con los ciclos de 342 s. La tabla usa «sin el paso 1» y el texto del gas libre usa todos los pasos (−1.68e-5 frente a −1.756e-5).
   *Resolución:* un banco k10b con la config de B1 en 340-345 s y una sola convención de pasos.
6. **«Br + Bgr = efecto neto de la densidad posterior»** depende de la contabilidad.
   *Resolución:* presentar la cancelación como algebraica y condicionada, o reevaluar con ρ_it.

## Comprobado por mí

- La tabla `piezas.py --sin-paso1` se reproduce: e 0.315, Bgq 0.388, Br2 0.182; veredicto por la letra SIN DECIDIR (Br/e −0.683 / −0.135; cociente 0.184).
- Ventanas: k10_mo20 tiene 58 filas a 1 ms y k10_dt05 117 filas a 0.5 ms; las dos terminan en t = 280.06 s.
- Quitar también el paso 2 deja e en 0.321. D(0.5)/D(1) = 0.380 con y sin el paso 1.
- Error estándar efectivo de las medias (con la autocorrelación de retardo 1): e 2.7 % (1 ms) y 6.2 % (0.5 ms). Bgq: sd/|media| 0.057 y 0.069.
- corr(Bgq, e) por paso: 0.068 (1 ms), −0.027 (0.5 ms), 0.54 (base). corr(Bgq, err_liq): 0.08, −0.48, −0.37.
- Código: `gas_adv` recibe el caudal predicho `af·u_f·A` (mod_pressure_3d.f90:1291-1495); el corregido es `Fg + ag·Δpp` (:893-905); Bgq y Bgr salen de mod_audit.f90:1250-1251; err_cc resta ρ_f dt gadv_used (:1208).
- Los intercambios de halos nuevos del Poisson solo tocan arrays de diagnóstico (`ws_Fgv_*`), con la guarda `audit_freq > 0`.

VEREDICTO: rechaza
