# WS-K10, ronda 1: revisión del refutador

Revisión de solo lectura. Leí `research/README.md`, el reporte, C-184, C-197, C-202, C-204, C-206, C-210, C-226, C-227 y C-230 a C-233, las refutadas del registro, `.claude/rules/acople-pv.md` y la entrada WS-K10 de `.claude/rules/transporte-energia.md`. Todos los números propios salen de los `audit.csv` de `campaigns/b1/k11_*_s290`, `k10b_*` y `judge_otp_280`, leídos con python.

## 1. Conclusiones, hipótesis alternativa y dato que las separa

**1. «La premisa C-197 era un artefacto del paso 1».**
- Alternativa: el paso 1 solo es grande por el cambio de claves.
- Dato que separa: el paso 290001 con dt acotado y las claves ya activas. Está en los datos (C-230): e = −1.735e-3 kg. El artefacto existe sin cambio de claves.
- Se sostiene.

**2. «Desde 280 s los cocientes entre dt están confundidos».**
- Lo aceptan el propio reporte y C-227/C-230. No hay objeción.

**3. «H14(a): desde 290 s el error multifase es MAYORMENTE una TASA».**
- Alternativa: no hay piso y la caída es una ley de potencia lenta (r ∝ dt^p con p pequeño).
- Lo que la separa es la curvatura de los tres puntos. Está en los datos, pero el reporte no la da. Con bootstrap circular:
  - r(0.5)/r(1) = 0.877 (IC90 0.860-0.894);
  - r(0.25)/r(0.5) = 0.949 (IC90 0.925-0.972).
- Los IC no se solapan: la caída se frena y hay piso. El ajuste da c/r1 = 0.81 (IC90 0.73-0.84). La conclusión se sostiene.
- Pero el criterio pre-registrado tenía poca potencia (O3). Y la frase «con 3 dt no se cuantifica la parte que converge» es falsa con estos datos.

**4. «H14(b): err_liq_lk = a·dt + k, SOPORTADA».**
- Alternativa: no hay pieza por paso (k = 0) y err_liq_lk es una tasa que crece levemente al bajar dt.
- Lo que la separa es el cociente de incrementos de r entre los tres dt. El modelo con k predice 2.0; el medido es 0.71 (IC90 0.39-1.18).
- La interpolación con k = 0 da 7.020e-6, más cerca de lo medido (6.996e-6) que la predicción (6.92e-6).
- **La conclusión implícita es falsa**: la letra se cumple, pero el modelo queda refutado por la forma de los datos (O1).

**5. «Bgq es la tasa dominante / la pieza que la pone».**
- Alternativa: es un artefacto del reparto de gadv entre err_cc, Bgr y Bgq, o una diferencia de dos términos brutos grandes, o el residuo del lazo externo estancado (C-184).
- Lo que la separaría son columnas que no existen (términos brutos de Bgq, Bgq en celdas con err_liq ≠ 0) y un barrido de externas desde 290 s. No está en los datos (O5).

**6. «Br + Bgr < 2 % de e».**
- Depende también de la contabilidad (C-210). Ya está declarado. No hay objeción nueva.

**7. «Sin cambio numérico».**
- La procedencia de la base es asunto del revisor de evidencia.
- Verifiqué la salvedad de binario de C-226: k11_base_s290 coincide con judge_otp_280 a ≤3e-14 en el paso 1, y la diferencia crece por redondeo hasta 1e-11 (12 frente a 15 ranks). No hay transitorio de binario y esa salvedad puede cerrarse.

**8. Confusor de régimen en 290 s.**
- Al bajar dt, p_max medio sube (30.8, 35.2, 45.1 kPa) y u_gas_max medio baja (98.9, 78.1, 69.3 m/s).
- El banco de 0.25 ms relaja durante unos 12-24 ms: r(0.25)/r(0.5) pasa de 0.949 a 0.984 si se excluye t ≤ 290.03 s.
- La parte que depende de dt no es truncamiento puro (O4).

## 2. Repeticiones de fracasos registrados

- **H14(b), una pieza por paso en err_liq_lk**, revive la «operación una vez por paso» de C-197, que retiraron C-206 y C-210.
  - El reporte explica la diferencia: es una pieza y no e entero, y se mide sin el paso 1.
  - Pero los tres puntos la contradicen, y el reporte no lo dice (O1).
- **«Partir Bgq»**, como paso siguiente, toca la guardia ALPHA_CUTOFF (M6-1), `ws_qin_cap` (M7-5) y el acople implícito de Plan D (C-008, D2.2).
  - Está declarado.
  - No hay arreglo en este workstream, así que no hay repetición efectiva.
- No hay limitador en el Poisson, ni reglas D/E/F/G, ni n_pc_max (C-007).

## 3. Objeciones

- **O1 (bloqueante).** (b) es SOPORTADA por la letra pero no discrimina, y los tres puntos refutan k constante. Datos:
  - cociente de incrementos 0.71 (IC90 0.39-1.18), frente a 2.0;
  - k por par: 3.4e-7 frente a 1.2e-7;
  - interpolación con k = 0: 7.020e-6.

  Hay que corregir las líneas 49 y 490-513, que están caducadas, y registrar un resultado que refiera C-232.
- **O2 (bloqueante).** Sitio:
  - H14 solo está medida con 20 externas y CG 1000.
  - En la config de B1, el gas libre suma −2.2e-5 kg/paso (err_cc_free −1.9e-5, store_free +7.6e-5), más Bx.
  - El reporte contradice C-233 en las líneas 323-324, 741-750 y 748-750.

  Hay que acotar el titular y la regla. Para extender la conclusión a B1, banco nuevo: config de B1 con 0.5 ms desde eaf3d_00290000.h5, comparado con k11_base_s290.
- **O3.** El criterio (a) tenía poca potencia: con los extremos ya vistos, cualquier r monótono da un cociente en [0.833, 1.00]. Hay que apoyar la conclusión en la curvatura (0.877 frente a 0.949, IC90 sin solape) y en c/r1 = 0.81 (0.73-0.84).
- **O4.** El régimen cambia con dt también en 290 s (p_max medio, u_gas_max medio, relajación inicial con 0.25 ms). Hay que declararlo en la sección H14.
- **O5.** Falta «en esta contabilidad» en el titular de Bgq y en la regla. Lo resolverían los términos brutos de Bgq, Bgq restringida a celdas con err_liq ≠ 0 y un barrido de externas desde 290 s.
- **O6.** La regla dice que desde 290 s «no hay transitorio». Debe añadir que el paso 1 con dt acotado se excluye siempre (C-230).

VEREDICTO: rechaza
