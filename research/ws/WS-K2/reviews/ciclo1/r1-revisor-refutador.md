El reporte acierta en que G2 no se cumplió, pero lo rechazo por una sola objeción bloqueante (O1): no se puede probar que Plan K cause el estallido que refuta el juez, y el reporte lo da por hecho.

# Revisión del refutador: WS-K2, ronda 1

Solo lectura. Datos verificados en `campaigns/b1/*/audit.csv` y en el registro.

## 1. Conclusiones, hipótesis alternativas y el dato que las separa

**C1. G2 no se cumplió: el juez 340–345.5 s quedó refutado (C-041).**
- **Alternativa:** el inciso (iii) no separa a Plan K de la base, y la media del inciso (i) depende de una sola trayectoria (régimen caótico, `acople-pv.md` «Juez ESTADÍSTICO»). Si fuera así, la refutación cumple la letra del criterio pero no prueba que Plan K sea peor.
- **Dato que las separa:** p_max por trayectoria en 344–345.5 s. **Ya está en los datos:**

  | Brazo | Trayectoria | p_max máximo (Pa) | Pasos con p_max ≥ 1e6 |
  |---|---|---|---|
  | Base | judge_otp_280 | 1.06e6 | 1 |
  | Base | base_340_n14 | 2.0e6 (tope en 344641) | 4 |
  | Base | base_340_n15 | 2.0e6 (tope en 344797) | 19 |
  | K | k1pa_340_n12 | ≤ 2.7e5 | 0 |
  | K | k1pa_340_n14 | ≤ 2.7e5 | 0 |
  | K | k1pa_340_n15 | 2.0e6 | 183, seguidos desde 345318 |

- **Lo que dicen:** la base también falla el inciso (iii) en 3 de 3 trayectorias. Lo único que distingue a K es que k1pa_340_n15 se queda pegado al tope (C-046, C-063). La conclusión «G2 no cumplida» sigue en pie, pero el reporte no cuenta este contraste.
- **No se mueve el problema de sitio:**
  - vol_lim medio 2.52–2.54e-3 y vol_unlinked 2.07–2.10e-3 en los dos brazos.
  - Centinela de gas (pasos con u_gas ≥ 299.999): K 17/15/199, base 167/131/200.

**C2. Plan K es necesario para el salto de 345.318 s (C-048, C-049).**
- **Alternativa:** el campo llega al tope también sin Plan K y solo cambia la celda donde ocurre.
- **Dato que las separa:** el brazo sin Plan K, `diag_k15_k_off`. **Ya está en los datos (C-309):** min p = -2.0e6 Pa desde el primer paso tras el reinicio; arranca de un estado de Plan K, así que no es un control limpio.
- El reporte resume C-309 solo como «máximo con signo». Omite la restricción «solo en la celda (9,1,2)».

**C3. G1 no pasó, así que no hubo ventanas largas.**
- **Alternativa:** el fracaso de G1 (C-028) es de la variante con A2. La variante juzgada en C-040 (v2 sin A2) sí eliminó el ciclo de 342.5 s (C-037, C-039, por la holgura).
- **Ya está en los datos.** WS-K1 sigue `en_revision`; hay que citar C-025/C-028, no «WS-K1».

**C4. Las ventanas de 284.3 y 294.1 s solo se midieron.**
- **Alternativa:** no están refutadas, sino sin objeto (Plan K archivado, C-065).
- C-014 sale de v1. C-034 muestra que v1 se comporta distinto en el piso, así que su señal temprana no se transfiere.

## 2. Repeticiones de fracasos registrados

- **No es una repetición de D2.2 ni de n_pc_max.** `docs/PLAN_K_limitador_en_poisson.md` §2 los distingue, y el modo de fallo medido es distinto:
  - C-056: el umbral binario ROOM_EPS de face_open.
  - C-063: la fila se vuelve incompresible cuando F2.31 apaga el gas.
- **El detonante sí coincide con un defecto registrado:** la velocidad fantasma detrás de caras cerradas (C-051/C-064; D2.6; `acople-pv.md`:233). Está en la base (C-078: 19 de 31 eventos con precursor) y d26k la reduce (C-093).
- **El fracaso de Plan K no está en `.claude/rules/acople-pv.md`.**

## 3. Objeciones

1. **O1 (bloqueante).** Hay que corregir el resumen de C-309 en el punto 5. En «Incertidumbre» hay que añadir que la base rebasa el inciso (iii) en 3 de 3 trayectorias y que lo que distingue a K es quedarse pegado al tope. La causalidad de Plan K en el campo queda sin decidir (C-309, C-294).
   *Dato:* el recuento de audit.csv de arriba, con su nota de procedencia, y el enunciado completo de C-309.
2. **O2.** Citar C-025/C-028 en lugar de «WS-K1», y añadir C-037/C-039 (la variante juzgada en C-040 sí quitó el ciclo de 342.5 s).
3. **O3.** En el motivo de cierre, poner «sin objeto» para 284.3 y 294.1 s, citando C-065 y C-034.
4. **O4.** Decir en «Incertidumbre» que la combinación Plan K + D2.6 (pc_liq_closed_dir) no se probó.
   *Experimento que la decide:* un juez C-040 con Plan K v2 sin A2 + pc_liq_closed_dir, 3 trayectorias en 340–345.5 s.
5. **O5.** Registrar el fracaso de Plan K (C-041, C-063, C-309 y el contraste de la O1) en `acople-pv.md`, o decir en el reporte que ese registro va en el cierre de WS-K1.

VEREDICTO: rechaza