# Revisión del refutador: WS-K1, ronda 1

**Veredicto: rechazo.** La conclusión principal (G1 no se cumplió) se sostiene. Lo que podría ser falso es cómo se encuadra en la Incertidumbre, y el resultado de Plan K no queda en el registro permanente. Hay 2 objeciones bloqueantes (R1, R2) y 4 no bloqueantes.

## 1. Conclusiones, mejor alternativa y dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| H1 refutada (C-012) | El criterio \|p\| < 20 kPa estaba mal planteado (C-031) | El inciso de convergencia, que no depende de ese criterio | Sí: 205 de 205 solves al tope con tol 1e-6. **La refutación se sostiene.** |
| H1b refutada (C-028) | (b) es la métrica hidrostática que C-031 invalidó; (c) podría estar inflado por el artefacto del reinicio (C-290) | Recontar (c) sin los pasos 342451-342452 | Sí. Esos dos pasos son iguales en todos los brazos. Sin ellos, k1b da 4 de 109 pasos (3.7 %), por encima de 3.2 %, y además el ciclo vuelve (C-038: 6874 Pa, ag_min 0.01500). **La refutación se sostiene; (b) sobra (R4).** |
| La holgura quita el ciclo (C-039) | Ruido de trayectoria, o el ingrediente es la entrada no enlazada y no el factor | Firma mecanística en la sonda; separar las dos piezas del parche | Ruido: descartado. k1pa coincide con k1 en p_max paso a paso, k1pb con k1b, y ag_min pasa de exactamente el piso (0.0150) a 0.0183. Entrada no enlazada: **no separada** (R5). |
| «Lo refutado son criterios, no el Plan K como idea» | Lo refutado es el diseño de conjunto activo con tope exacto: converge y el ciclo vuelve. Es la regla de aborto de §4 del propio plan. El beneficio viene de la holgura, no del Poisson implícito | Una corrida de la base con un margen equivalente bajo el tope, sin conjunto activo | **No existe.** Lo que sí hay (C-038, plank_conv 0.9 % y C-039) apoya la alternativa (R1). |
| Decisión del usuario de no adoptar Plan K | Se apoyó en parte en C-064, que ahora está fallida: el brazo sin Plan K no es un control limpio (C-294) | Un brazo sin Plan K desde un estado de la base | No existe. El reporte ya lo reconoce, así que no lo objeto. |

## 2. Repeticiones de fracasos registrados

- Plan K no repite D2.2 ni n_pc_max: §2 del plan explica la diferencia (mismo solve y no pasada anterior; momento congelado).
- Sí guarda parentesco con la familia de reglas locales (acople-pv.md, 22-oct: «quinta regla local»). Si el beneficio es la holgura, eso equivale a subir localmente el piso de gas, de la familia de D2.4 alpha_g_comp_min (refutada en el banco, C-091). Esto refuerza R1.
- Riesgo de repetición futura: acople-pv.md no registra el resultado de Plan K (R2).

## 3. Objeciones

**R1 (bloqueante): el encuadre de la «idea» de Plan K.**
- La regla de aborto de §4 del plan se disparó con k1b: converge (0.9 % sin converger) y el ciclo vuelve (C-028, C-038).
- Las trayectorias «mejores» de C-041, y también k1_340 (C-027), son la variante con holgura (sin A2), no el diseño.
- reevaluacion.md:82-85 ya fijaba la consecuencia si ganaba la holgura: barrera continua en vez de tope exacto. Ganó la holgura y el reporte no lo recoge.
- **Para resolverla:** evaluar la regla de aborto en el reporte con esos datos, decir a qué variante corresponden C-041 y C-027, y trasladar la conclusión condicional. Para separar idea y holgura haría falta la corrida de la base con margen, que no existe.

**R2 (bloqueante): el resultado de Plan K no está en el registro permanente.**
- En acople-pv.md, las líneas 610-616 terminan en «⇒ Plan K» y la 272 solo lo nombra como vigente.
- docs/PLAN_K no tiene cierre.
- `ledger.py open` solo muestra las 5 últimas refutadas.
- **Para resolverla:** una entrada fechada en acople-pv.md con C-012, C-028, C-039, C-041, la regla de aborto y la salvedad de vigencia, y una nota de cierre en el PLAN_K.

**R3 (no bloqueante): research.md:16 contradice el registro.**
- Dice «hidrostática de ~70 kPa del fondo», pero C-013 midió una columna de unos 6 kPa y C-031 muestra que es un chorro frenándose.
- **Para resolverla:** corregir la línea o señalar la errata en el reporte.

**R4 (no bloqueante): el inciso (b) de H1b.**
- Es el criterio mal planteado. La refutación se apoya en (c), robusto (3.7 % sin el reinicio), y en C-038.
- **Para resolverla:** decirlo en el reporte.

**R5 (no bloqueante): P-a cambia dos cosas.**
- Pone el factor a 1 y además unl_on=.false.; C-039 se lo atribuye solo al factor.
- **Para resolverla:** una corrida con factor 1 y unl_on activo, o redactar «sin A2 (factor y entrada no enlazada)».

**R6 (no bloqueante): la cita de la regla de vigencia.**
- C-089 está fallida (C-284); la regla vive en acople-pv.md:266-273 y clasifica a Plan K como vigente.
- No se muestra si los 7 commits posteriores en src/ (de auditoría, que tocan mod_pressure_3d y mod_continuity) cambian la numérica.
- **Para resolverla:** citar la regla en acople-pv.md y aportar el bitwise o golden de esos commits, o declarar que no se verificó.

## Verificado (solo lectura)
- Recuento del registro: 16 raíz, 4 refutadas, 9 fallidas y 3 soportadas; 0 abiertas.
- C-014, C-015, C-026 y C-027 son de WS-K2.
- src/ sin `pc_alpha_implicit`; 7 commits desde 1bc9832; los dos parches fallan en mod_pressure_3d.f90:733.
- p_max > 100 kPa en los audit.csv de los 5 brazos, con y sin los pasos del reinicio.
- plank_conv con tol 1e-3 en k1, k1b, k1pa y k1pb; conjunto activo nunca vacío.
- Contenido de pa_sin_A2.patch.
- Ausencia del cierre de Plan K en acople-pv.md y en el PLAN_K.

VEREDICTO: rechaza