# WS-K2, ronda 2: revisión del refutador

Revisé research/ws/WS-K2/report.md, C-310/C-311/C-312, C-028, C-037, C-039, C-065, C-093 y C-294, `ledger.py open` (0 abiertas) y la entrada «Plan K CERRADO» de .claude/rules/acople-pv.md (líneas 618-640). Recalculé las cifras nuevas directamente desde los audit.csv, en modo solo lectura.

## 1. Conclusiones y sus hipótesis alternativas

**C1. G2 no se cumplió y el juez C-040 queda refutado (C-041).**
- **Alternativa:** el fallo se debe a un solo evento de n15 que también podría darse en la base, no a un defecto general de K.
- **Dato que las separa:** cent_pg por subventana y comportamiento desde el mismo estado.
- **Qué dicen los datos (recalculado):**
  - En 344-345.318 s, K tiene 0.15/0.08/0.76 % y la base 7.21/7.89/10.24 %.
  - En 345.318-345.5 s, K tiene 0.0/2.19/100.0 % y la base 2.75/2.19/3.83 %.
  - En 345310-345320, sin K hay 10 de 11 pasos >= 1e6 (2 en 2e6, cent 90.9 %); con K hay 3 de 11 (1 en 2e6, cent 27.3 %).
- **Valoración:** el reporte recoge todo esto ahora (C-312) y dice explícitamente que la alternativa sigue en pie. El veredicto «refutada» es una aplicación literal del criterio pre-registrado, y el reporte no lo vende como prueba de que K sea dañino. Es correcto.

**C2. Las ventanas de 284.3 y 294.1 s quedan sin objeto.**
- **Alternativa:** que la señal de C-014 sí se transfiera.
- **Valoración:** el reporte ya dice que «sin objeto» descansa SOLO en el archivo del Plan K. También reconoce que la variante juzgada es idéntica a v1 en la sonda (C-037, C-039). Es coherente.

**C3. El archivo del Plan K se apoya en C-028, C-039 y C-041.** El reporte reconoce que el motivo C-064 ya no vale (C-294). Es correcto.

**C4. ¿Mueve el problema de sitio?** Verifiqué las cifras en 340-345.3 s:

| Métrica | K | Base |
|---|---|---|
| Media de vol_lim | 2.524-2.530e-3 | 2.541-2.548e-3 |
| Media de vol_unlinked | 2.097-2.104e-3 | 2.071-2.086e-3 |
| Suma de m_spill | 2.3-7.1e-11 | 1.04-1.22e-10 |
| Suma de m_alpha_clip | 5.08-8.31e-11 | 5.6-7.75e-11 |

No hay desplazamiento del defecto. La energía por paso no aplica: el reporte no presenta ninguna mejora de K.

## 2. Repeticiones de fracasos registrados

- El reporte ya no propone K+D2.6. Dice que el limitador dentro del Poisson está refutado como mecanismo (C-028, regla de aborto §4) y que la mejora venía de la holgura (C-039).
- Recuerda C-093: D2.6 tuvo sentinel_gas en FAIL y un gap de energía de 2.32/2.31 frente a 1.717.
- Alinea el siguiente paso con acople-pv:636-639: margen continuo sin Poisson implícito, desde diag_p342a.

No queda ninguna repetición sin justificar.

## 3. Estado de mis objeciones de la ronda 1

| Objeción | Estado |
|---|---|
| O1 (bloqueante) | Resuelta. Párrafo reescrito y propuesta retirada. |
| O2 (bloqueante) | Resuelta en el reporte. Tabla k_off/k_on verificada (10/2/90.9 frente a 3/1/27.3). Queda pendiente la frase de acople-pv.md:631-632, que es del coordinador (ver objeción O2-pendiente). |
| O3 | Resuelta. |
| O4 | Resuelta. |
| O5 | Resuelta. Cifras verificadas. |
| O6 | Resuelta. Ahora dice «prueba PARCIAL», con 5 líneas [PLAN-K] y 0.42-0.57 % sin converger. |

## 4. Objeciones nuevas o residuales (no bloqueantes)

- **O2-pendiente.** acople-pv.md:631-632 sigue diciendo «lo que separa a K es quedarse pegado al tope». C-312 lo contradice. El coordinador debe matizarlo al hacer el ws-set de cierre. No hace falta ningún experimento.
- **E1.** La suma de m_spill de base_340_n14 es 1.0449e-10, así que el rango de la base empieza en 1.04e-10, no en 1.05e-10. Es una errata menor que no cambia nada.

La cuestión de fondo (si n15 se pega por K o por el estado) sigue sin decidir. El reporte lo declara y nombra el control que lo resolvería: la base desde un snapshot de k1pa_340_n15 anterior a 345.25 s, o trayectorias base más largas. No es una objeción al cierre como `fallido`.

VEREDICTO: aprueba