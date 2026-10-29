Revisión del revisor refutador: WS-K1, ronda 1 (panel de cierre)

## 1. Conclusiones, hipótesis alternativa y dato que las separa

**C1. «G1 no se cumplió; H1 y H1b refutadas».**
- **Alternativa:** las dos refutaciones son por la letra de criterios débiles, no por un defecto del diseño.
  - H1 (C-012) falla en convergencia con una tolerancia que no se puede verificar en v1: con 1e-3 da 0/205 sin converger.
  - H1 falla también en |p|<20 kPa, un criterio que C-031 declaró mal planteado.
  - H1b (C-028) falla en (b), que tiene el mismo defecto, y en (c) por un solo paso: 4/109 frente a 3.49 permitidos sin los pasos del reinicio, en una sola trayectoria (k1pb = k1b), con la base en 5/109.
- **Dato que las separa:** ≥3 trayectorias de v2 completo en 342.45-342.56 s. No existen.
- **Qué dicen los datos:** G1 sigue sin cumplirse por la letra, y el estado `fallido` es correcto. El reporte reconoce cada pieza por separado, pero no las reúne en un solo sitio (O2, no bloquea).

**C2. «Plan K no adoptado es una DECISIÓN, no una refutación del beneficio en B1».**
- **Alternativa:** los datos de B1 favorecen a Plan K y la decisión se apoyó en una base hoy caída (C-064 → C-294).
- **Dato que las separa:** regime2 de las 4 trayectorias K frente a las 3 de la base. Ya está en disco:

| Ventana | p>100k K | p>100k base |
|---|---|---|
| 340-342 s | 0.1 % | 2.2-4.1 % |
| 342-344 s | 1.4-2.4 % | 7.2-10.3 % |
| 344-345.5 s | 6.5-8.5 % (3 de 4); n15 26.4 % | 20.2-31.5 % |

- **¿Mueve el problema de sitio?** No se ve. C-312 no encuentra el defecto trasladado a vol_lim, m_spill ni m_alpha_clip. Lo único que sube en K es g>200 en 340-342 s (0.8-1.4 % frente a 0.4-0.9 %), y es poco.
- **Qué dicen los datos:** el reporte llama correctamente DECISIÓN a la no adopción, pero solo lo apoya en cent_pg con n = 3. La evidencia es más fuerte, porque k1_340 es una cuarta trayectoria.

**C3. «Ganó la holgura» (C-039) y «no reintentar el tope exacto».**
- **Alternativa:** P-a cambia dos cosas a la vez (el factor de `acc_face` y `unl_on`), y el tope exacto es una sola trayectoria que en la sonda mejora a la base.
- **Qué dicen los datos:** el reporte declara ambas cosas.
- **Lo que probé:** separar con los datos existentes el binario de k1pa_340_* mediante una firma de α_g en el piso en celdas de lecho sumergidas. No separa ni siquiera k1b de k1pa (55/53 frente a 51), así que no se resuelve (O4).

**C4. La lección de D2.2 «se aplica tal cual» a una barrera bajo el tope.**
- **Alternativa:** es una extrapolación de banco a B1.
  - D2.2/D2.2c se midieron solo en `bed_flood` (malla 12×24×16).
  - El Plan D concluye que sus resultados de banco «NO se transfieren a B1».
  - El único dato de B1 sobre un cierre del lado del Poisson con el momento congelado es el de Plan K, y va en sentido contrario (tabla de C2).
- **Qué dicen los datos:** la alternativa está en disco y contradice la afirmación (O1, bloquea).

## 2. Repeticiones de fracasos registrados

- **D2.2 (Plan D):** PLAN_K §2 explica en qué difiere: el conjunto activo converge dentro del solve, en lugar de usar el `ws_lim` de la pasada anterior. Los datos de B1 muestran un resultado distinto al de D2.2, así que en B1 no es una repetición en su efecto.
- **`n_pc_max`:** también lo distingue PLAN_K §2.
- **F2.31 por paso (regla local D/E/F/G):** no se aplica.
- **Conclusión:** no hay repetición sin justificar. El problema es el contrario: la entrada nueva invoca el fracaso de D2.2 como precedente vigente para B1 sin un dato de B1 que lo respalde (O1).

## 3. Objeciones

1. **O1 (bloquea).** Hay que quitar «se aplica tal cual» del punto (iv) del reporte. En la viñeta D2.2 del reporte y de `acople-pv.md` hay que añadir dos cosas:
   - que D2.2 es un resultado solo del banco `bed_flood` y que los bancos no predicen B1;
   - que en B1 Plan K, también con el momento congelado, bajó p>100k en 4 de 4 trayectorias hasta 345.3 s, con las cifras de regime2 de arriba.

   Dato: el regime2 de las 7 corridas, ya en disco. Lo que lo decidiría de verdad, D2.2 corrido en B1, no existe.
2. **O2 (no bloquea).** En «Qué se refutó», reunir en un solo sitio por qué las dos refutaciones son débiles: H1 cae por un criterio mal planteado y una tolerancia que no se puede verificar, y H1b cae por un paso de margen en una sola trayectoria. Lo resolverían ≥3 trayectorias de v2 completo.
3. **O3 (no bloquea).** Corregir dos erratas: «lo ÚNICO que trae el diff staged» (línea 400), que contradice la sección del ciclo 6, y la fuente «acople-pv.md 16 líneas» (línea 425), cuando el diff actual tiene 42.
4. **O4 (no bloquea).** El binario de k1pa_340_* no se puede identificar con los datos existentes; lo confirmé con una firma de campo. Solo lo resolvería el hash del binario o recompilar sobre 1bc9832 y comparar bit a bit.

## 4. Verificado

- **Src de los dos brazos del juez:** la base del juez (e5d331e) tiene el mismo src que 1bc9832, la base de Plan K.
- **Afirmaciones citadas:** C-011, C-012, C-025, C-028, C-039, C-040, C-041, C-064, C-065, C-294 y C-310 a C-313 coinciden con lo que dice el reporte.
- **Entrada «Plan K CERRADO»:** declara la DECISIÓN y las salvedades.

VEREDICTO: rechaza