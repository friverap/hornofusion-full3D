# Reevaluación del Plan K (22-oct-2026)

Pedida por el usuario tras dos predicciones refutadas. Borrador del
coordinador para el refutador; todo número lleva su afirmación del registro.

## Lo que está establecido

1. **La familia existe.** Las paradas de B1 a 284.3, 294.1 y 342.5 s son el
   tope de líquido del piso de poro actuando un paso después de la presión
   {C-001} {C-002} {C-003} {C-004} {C-005}.
2. **La población es real y pequeña.** 45–242 celdas de lecho sumergidas,
   chatarra escasa (mediana α_s 0.03–0.07), casi todas con el gas en el piso
   {C-030}.
3. **Fracasos previos sobre el mismo terreno:** reglas de clasificación y
   corrector segregado {C-006} {C-007} {C-008} {C-009} {C-010}; el Plan F
   (quitar el piso de gas en TODO el lecho) fue catastrófico
   (docs/PLAN_F_gas_resorte.md §5) y el modelo de mezcla (Plan G) negativo.

## Lo que mostró el Plan K

4. **Versión 1** (sin los arreglos de la auditoría): quitó la oscilación de la
   celda del ciclo (osc2 51.8 kPa → 0.34 kPa) pero dejó una sobrepresión
   estática de 10.5 veces el gradiente hidrostático {C-012} {C-013}. Ventanas:
   284 s limpia, 294 s parcial {C-014}; 340–346 s mucho mejor en 342–346 s
   pero peor en 340–342 s, criterio refutado {C-027}. Nunca convergió a 1e-6.
5. **Versión 2** (con A1, A2 parcial, M1–M3, B1): converge (0.9 % sin
   converger) pero el ciclo y el pico de 410 kPa vuelven; criterio refutado
   {C-028}. Hipótesis sin verificar: A1 excluye la celda porque F2.31 saca su
   gas del acople dentro del paso {C-029}.

## Interpretación (lo que el refutador debe atacar)

6. El Plan K no cambia la física del problema, solo dónde se paga: con la
   restricción α_l ≤ cap impuesta dentro del Poisson, el volumen que el
   líquido no puede ocupar exige EXPULSAR el gas del piso (≈1.5–2 % del
   volumen) por una conductancia de gas minúscula → sobrepresión estática
   (versión 1); si la celda se excluye (versión 2), vuelve el ciclo. Ambos
   síntomas salen de lo mismo: un residuo de gas ARTIFICIAL forzado a existir
   y a moverse en celdas que físicamente son baño con trozos de chatarra.
7. Por tanto, aun arreglando la elegibilidad (C-029), lo mejor que puede dar
   el Plan K es convertir el ciclo en una sobrepresión estática no física. Su
   valor esperado es bajo.
8. La causa raíz sería el modelo del piso de poro en celdas sumergidas de
   chatarra escasa. PERO la regla del proyecto prohíbe reintentar reglas
   locales de clasificación por α (lección D/E/F/G), y el Plan F mostró que
   quitar el piso en todo el lecho es peor. Cualquier cambio del piso exige
   antes una justificación física y bibliográfica, no otra regla local.

## Opciones

- **A. Seguir con el Plan K**: sonda de elegibilidad (15 min) y, si C-029 se
  confirma, ajustar A1. Riesgo: por (6) solo traslada el problema.
- **B. Cerrar el Plan K como refutado** y abrir una pregunta nueva
  (/pregunta) sobre el modelo físico de una celda sumergida con chatarra
  escasa, empezando por literatura verificada y una medición, sin código.
- **C. Aceptar el límite del modelo**: B1 no pasa de ~342 s con el modelo de
  lecho actual; reportar B1 hasta ahí con esa limitación documentada.

Recomendación del coordinador: B, con C como respaldo documentado.
