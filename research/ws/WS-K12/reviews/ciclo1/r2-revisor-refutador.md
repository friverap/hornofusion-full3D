Ronda 1 de WS-K12, revisión del refutador. Revisión ciega y de solo lectura: no lancé ninguna corrida y usé python solo para leer el registro, audit.csv, run.log y los parches archivados.

## 1. Conclusiones, alternativa y dato que las separa

| Cierre | Mejor alternativa | Dato que la separa | ¿Está en los datos? |
|---|---|---|---|
| A1: C-057 refutada | E y N quedaron fijadas como SALIDAS de (9,1,2), fijadas por la vecina; ninguna cara de entrada se fijó | Lógica de fix_face con s(9,1,2)=1 | **Sí.** `v2_completo_sobre_HEAD.patch:195` (s_nw=1; la celda saltada conserva s=1), `:329-344` (solo se fija una cara si la RECEPTORA tiene s<1) y `:269` (fx=cx: las candidatas se ensamblan). `diag_c058/run.log:560-576`: SALTADA en las it 1-6, T=0, E/N/W=1, salida por convergencia. Una celda saltada no puede tener fijada ninguna cara de entrada, así que el refuta_si de C-057 no se cumple. C-063 añade que, con la celda dentro del bucle, s=1 y p sigue en 2e6: la causa es la fila incompresible (gas apagado), no salir del conjunto |
| A5: C-085 refutada | C-085 es cierta en el paso que nombra (341705); la regla midió la relajación | Cuota en 341705 | **Sí.** c086.out: en 341705 o1 la cuota del líquido es 0.785 (≥ 0.6, saldría SOPORTADA con el umbral de C-086). En o2-o5 es 1.0, pero confundida por act_g=F (C-088). En 341706 o1, p_in ya es 3.706e5 |
| E1: C-121 «también en la banda intermedia» | Con la definición de C-122 el cociente es ≥ 0.7 (refutada) | Σ\|e\| en las celdas con 0<α_g<1e-2 | **No.** 0.566 es el instrumento de C-126 (α_g>0), no el de C-122 (α_g≥1e-2). La cota es ≥ (4.420e-3 + 4.816e-3)/1.6356e-2 = 0.565, sin cota superior por debajo de 0.7 |
| E4/E9: C-135 y C-110 «no soportada ni refutada» | La parte NETA de C-110 está contradicha por una cláusula pre-registrada | Cláusula neta de C-135 | **Sí.** C-139 da corr 0.229 < 0.3 con signo opuesto en 59/59 pasos, y C-138 (soportada) lo fija. C-151: ≥48 % del piso de k7v4_long no es complemento neto. C-154: el inciso por celda no discrimina |
| E7: C-202 sin decidir | La densidad posterior al Poisson pesa alrededor del 1 % de e (zona de refutación si se incluye Bgr) | Br+Bgr | **Sí**, en C-208: 0.012 e y ≈0.001 e. C-210(4) advierte que esa cancelación es algebraica |
| B3: C-044 soportada | El pico tras el reinicio lo causa el reinicio en sí, no el paso truncado | Reiniciar desde un snapshot de paso completo | **Sí.** Validez de C-087: 220/220 filas idénticas a base_340_n15 tras reiniciar desde 341500. Esto refuerza C-044 y C-015 y conviene citarlo |
| A2 (C-074), A3 (C-079), A4 (C-082), A6 (C-089), B1, B2, B4, C, D, F | — | — | Ya los revisé en la ronda anterior; los textos recogen las salvedades. B4 (C-047) se sostiene con 395/395 snapshots |

## 2. Repeticiones de fracasos registrados

No hay cambio numérico, así que no se repite D2.2, ni las reglas locales D/E/F/G, ni n_pc_max. El cambio de herramienta (sin_decidir) no tiene ningún precedente refutado.

Hay un problema que se mueve de sitio: tras los cierres, `open` mostrará 0 de 64, y sin_decidir no aparece en la sección de refutadas/fallidas. Los pendientes reconocidos (C-237c, C-261 y el piso del gas en C-197/C-211) dejan de verse.

## 3. Objeciones

1. **R1 (bloqueante).** A1 debe pasar a fallida (no concluyente), con las lecturas de fix_face y C-063. El texto actual se contradice: dice «'ninguna fijada' falla» y después «no se sabe si quedaron fijadas». Se resuelve con los datos ya citados (parche y run.log).
2. **R2 (bloqueante).** A5 debe pasar a fallida (no concluyente) por la regla del propio reporte (A3). El experimento que decidiría es el refuta_si de C-088 (gas en la fila durante todo 341705), que no se ha corrido.
3. **R3 (bloqueante).** E1: quitar el 0.566 como valor de C-121. Decir que, con la definición de C-122, el valor es indeterminado (≥ 0.565, sin cota < 0.7) y que el sin decidir sale de las columnas de C-123, con el instrumento defectuoso (C-124). La otra opción es cerrar como fallida (no concluyente). Lo decidiría la columna Σ\|e\| en 0<α_g<1e-2 (no existe).
4. **R4 (bloqueante).** E4 y E9 deben recoger la cláusula neta registrada (C-139/C-138), la dirección de C-151 y C-154.
5. R5. E7: añadir las cifras de C-208 y la salvedad de C-210(4).
6. R6. E10/E11: usar sin_decidir con resultados sin criterio estira la definición del README. E10 debe enunciar lo que dice C-154; sus cifras 0.384 y 0.163 se comprueban con cifras ya registradas.
7. R7. Visibilidad: que `open` cuente los sin_decidir, o que el reporte diga dónde quedan los pendientes. Comprobación: aplicar los cierres en una copia del scratchpad y ejecutar `open`.
8. R8. B3/C1: citar la validez de C-087 como control del reinicio y delimitar el soporte de B3 a lo que decide su comando.

Todas las objeciones se resuelven cambiando el estado o el texto de eventos que aún no están registrados, con datos que ya existen. La única excepción es R3: su dato decisivo no existe, y por eso exige un texto que declare la indeterminación.

VEREDICTO: rechaza
