# r1 — revisor-refutador sobre reevaluacion.md — VEREDICTO: rechaza

Resumen fiel del informe (salida de modelo; afirmaciones verificadas por el
coordinador marcadas ✓):

1. ✓ Punto 6 contradicho: media del ciclo de la base = k1_342 paso a paso;
   u_l,z igual en base y k1 (frenado inercial ~7 g); alpha_g de k1 nunca baja
   del piso (min 0.0183). La celda tiene pared abajo y en i+1, gas encima
   (alpha_g 0.6-0.8 en k=3): modo local de impacto, no columna.
2. ✓ C-029 (A1/F2.31): act_l/g=TT durante el ciclo en k1b_342; F2.31 solo en
   el pico. Alternativa: A2/tolerancia → tope exacto → la celda toca el piso.
3. Punto 7 prematuro: k1_340 es el mejor 340-346 s registrado; la falla de
   340-342 s es de una trayectoria (juez estadistico).
4. Opcion B = sexta regla local de clasificacion (D2.x, E1/E1b, A20-2, F2.31
   por paso, Plan F). Legitima solo con cierre continuo, bibliografia,
   prediccion en B1 multi-trayectoria y explicacion frente al fallo de Plan F.
5. Opcion C contradice k1_340 (llega a 346 s con menos p>100k que la base).
6. Opcion D (nueva): separar conjunto activo de holgura con dos ventanas
   cortas (v2 sin A2; v2 con tol 1e-6) + k1_340 multi-trayectoria.
