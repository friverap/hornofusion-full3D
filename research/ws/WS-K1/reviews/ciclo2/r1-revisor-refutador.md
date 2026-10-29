# Revisión del refutador: WS-K1, ronda 1

Revisión ciega: no leí `research/ws/WS-K1/reviews/`. Solo lectura; python únicamente para leer datos que ya existen.

## 1. Conclusiones del reporte y su mejor explicación alternativa

**C1. G1 no se cumplió: H1 y H1b quedaron refutadas.**
- Alternativa: ninguna sólida. H1 (C-012) y H1b (C-028) fallan en incisos pre-registrados.
- El margen de H1b (c) es pequeño (6 de 111 pasos frente a 3.55 permitidos), pero es la letra del criterio.
- La conclusión se sostiene.
- Omisión: el reporte no dice que el inciso de ciclo (a) PASÓ. Lo comprobé: `cell_series.py campaigns/b1/k1b_342 --cell 10,60,2 --steps 342500,342560` da osc2 = 885.7 Pa, por debajo de 1000.

**C2. «Lectura más fuerte»: el tope exacto cumple la condición de aborto. En acople-pv: «No reintentar el conjunto activo con tope exacto».**
- Alternativa: la regla de aborto infiere «el mecanismo no es el limitador», y C-039 dice lo contrario (la celda toca el piso y el limitador conmuta).
- H0 (acople-pv.md:611-614) ya mostraba que la decisión es idéntica en los 5 outers y alterna entre pasos. Con el hueco congelado en α^n (J-B), un conjunto activo dentro del paso no puede quitar un retraso entre pasos. Con tope exacto ese retraso se reproduce por construcción.
- Qué separa las dos lecturas: la tabla H0 (ya existe) y que P-b sea casi idéntica a k1b (osc2 6876 frente a 6874; ag_min 0.01500 en las dos), es decir, que la convergencia no cambia nada en la celda.
- La métrica que declara PRESENTE (C-036) se calibró después y con k1b como ejemplar: es circular.

**C3. La holgura es lo que quita el ciclo (C-039).**
- Alternativa A: el ciclo es un artefacto del reinicio contaminado. Todos los brazos y H0 arrancan de `diag_p342a/eaf3d_00342450.h5`, escrito con dt 1.186e-9 (C-290). Queda DESCARTADA por los datos: en la corrida continua `dense_340_n14/phantom` la misma celda (10,60,2), [k,j,i] (1,59,9), alterna en 2 pasos desde 342525 y llega a 636 kPa en 342535.
- Alternativa B: el efecto viene de quitar `unl_on`, no del factor de A2. El reporte ya lo reconoce; no hay corrida que separe los dos ingredientes.
- k1pa coincide con k1 en la sonda hasta el 4.º dígito (p_max 68499 frente a 68502; osc2 209.5 en las dos).

**C4. No se puede verificar qué binario usó cada corrida.**
- Resuelto en parte por la estructura de los `run.log`: k1pa tiene la sonda de 5 outers como k1b (1650 líneas PROBE-P, frente a 410 en k1) y recuentos de PROBE-AI y PROBE-pmax distintos de k1b.
- Por tanto, k1pa no es el binario v1 ni el de k1b.

**C5. ¿El problema se mueve de sitio?**
- En 342.45-342.56 s, no: vol_lim, vol_unlinked, m_spill y m_alpha_clip son iguales en todos los brazos. cent_pg es 2.7 % en todos, y p>100k baja con k1/k1pa (1.8 %, frente a 6.3 % de la base).
- Pero ese mismo dato muestra que la consistencia entre Poisson y transporte del diseño nunca se logró: el vol_lim global queda a menos del 1 % de la base (2.48e-3 frente a 2.50e-3). Ver O5.
- En B1 la holgura sí se refutó (C-041); el reporte lo dice.

## 2. Repeticiones de fracasos registrados

- Plan K frente a D2.2: la diferencia está escrita en PLAN_K §2 (D2.2 usaba el limitador de la pasada anterior; Plan K converge dentro del solve). Es aceptable.
- Lo que no se dice: el fracaso del tope exacto es la restricción ya documentada en J-B y M20-2 (el hueco se congela en α^n; la celda que se llena dentro del paso queda abierta hasta el siguiente). No es un hallazgo nuevo sobre «limitador en el Poisson».
- La retoma propuesta («margen continuo bajo el tope») no dice en qué difiere de:
  - la rampa del piso de poro por encima de ALPHA_BED (4547861, juez a 2 MPa);
  - D2.4 alpha_g_comp_min (d24 refutada en el banco con el código actual, C-091);
  - llevar el hueco de la banda al Poisson (A20-2).

## 3. Objeciones

1. **(Bloqueante)** «Por la letra se disparó la regla de aborto», la «lectura más fuerte» y «No reintentar el conjunto activo con tope exacto» (acople-pv.md:621-636) reinterpretan el resultado. La regla no tiene umbral numérico. C-025 (a), pre-registrado, pasó con 885.7 Pa. La métrica PRESENTE es post hoc y se calibró con k1b. La inferencia de la regla («no es el limitador») contradice C-039. *Resolución (solo texto):* decir que (a) pasó; acotar «el ciclo vuelve» a la sonda (10,60,2), pasos 342510-342533, una trayectoria, con métrica post hoc; sustituir «No reintentar…» por la causa estructural (H0 de diag_h0lim más el hueco congelado en α^n de J-B).
2. **(Bloqueante)** El experimento decisivo propuesto (corrida de la base con margen, desde diag_p342a, en 342.45-342.56) mide en el sitio que no importa. k1pa ya pasó esa ventana y falló en B1 con 3 trayectorias (C-041). *Resolución:* fijar como experimento decisivo un juez B1 de ≥3 trayectorias en 340-345.5 s, y explicar en qué difiere el margen de 4547861, de D2.4/C-091 y de A20-2.
3. (No bloqueante) Incluir la prueba de que el ciclo no es un artefacto del reinicio: dense_340_n14, pasos 342525-342539, celda (1,59,9), 636 kPa en 342535.
4. (No bloqueante) Citar la estructura de los run.log como identificación parcial de los binarios (k1pa no es v1 ni k1b).
5. (No bloqueante) Ningún brazo verificó la consistencia entre Poisson y transporte del diseño. El vol_lim global queda a menos del 1 % de la base (2.503e-3 frente a 2.482e-3) y el vol_lim de la celda nunca se midió. La refutación es de la implementación tal como se probó. Si se retoma: medir vol_lim y vol_unl por celda en (10,60,2).

## Verificado

- Las cifras de ciclo en la sonda (cell_series), tanto en la ventana post hoc 342510-342533 como en la pre-registrada 342500-342560.
- regime2 de los cinco brazos.
- vol_lim, vol_unlinked, m_spill y m_alpha_clip en el audit.
- El reinicio común desde el snapshot truncado.
- La alternancia en la corrida continua dense_340_n14.
- Los recuentos de etiquetas de sonda en los run.log.

VEREDICTO: rechaza