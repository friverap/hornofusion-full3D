# WS-K12, ronda 1: revisión del refutador

Revisión de solo lectura. No se lanzó ninguna corrida; python se usó únicamente para leer audit.csv, HDF5 y el registro que ya existen.

## 1. Conclusiones, hipótesis alternativa y dato que las separa

| Conclusión del reporte | Mejor alternativa | Dato que separa | ¿Está en los datos? |
|---|---|---|---|
| C-047 se cierra «sin verificar» | La discrepancia nunca existió: es max p con signo frente a max\|p\| | Comparar p_max del audit con max\|p\| del snapshot del mismo paso | **Sí.** Sin diferencias en diag_k15d (181/181), diag_k15b (181/181), dense_340_n15 (12/12), judge_e1_n15 (12/12), judge_otp_280 (7/7) y k10_mo20 (2/2). En 345250 y 345280 de diag_k15d: max p = 9.27e4 y 2.56e5, min p = −5.865e5 y −3.279e5; el audit marca 5.865e5 y 3.279e5. Coincide con acople-pv.md:158 |
| C-044 «no reproducida con el código actual» | Sí se reproduce | Última fila de audit.csv frente a la penúltima en corridas de e5d331e | **Sí.** 22 corridas con dt ≈ 1.2e-9 al final; dense_340_n15 pasa de 5.75e4 a 2.04e5. El pico de d26k_n14 en C-093 (2.001e5) es ese paso; sin él queda en 1.24e5 |
| C-015 «fuera de alcance, sin verificar» | El pico de 805 kPa es la contaminación del reinicio que describe C-044 | Origen del reinicio de diag_p342b y comparación con corridas continuas | **Sí.** diag_p342b reinicia desde diag_p342a/eaf3d_00342450.h5, escrito tras un paso truncado (dt 1.19e-9). El pico de 805 kPa aparece en el 1.er paso (342451), en una celda de líquido puro (2,51,8) con alpha_s = alpha_g = 0, y en dos pasos baja a 164 y 85 kPa. En 342.45–342.53 s las corridas continuas no pasan de 91, 81 y 131 kPa (judge_otp_280, base_340_n14, base_340_n15) |
| C-079 refutada | Lo que C-079 afirma, la ubicación, se sostiene; C-080 probó otra cosa (alpha_s ≤ 0.05) | El refuta_si de C-079 en n15 | **Sí.** 26/26 eventos en la misma esquina (C-081). El refuta_si no se cumple |
| C-085 refutada | La fuente del líquido sí arma el pico; la regla eligió el paso de relajación | Cuotas en 341705 | **Sí**, en c086.out. 341705, 1.ª externa: cuota del líquido 0.79; externas 2 a 5: 1.0 con act_g = F |
| C-074 refutada | El mecanismo es frecuente pero no universal; falla el umbral del 70 %, no el refuta_si de la hipótesis | Precursor antes de los eventos frente al control | **Sí.** 61.3 %, 69.2 % y 81 % frente a 9.2–9.7 % (C-078, C-081, C-084) |
| C-089 soportada (por C-091) | El banco no distingue, porque E1 y D2.6 ya pasaban los bancos antes; el fracaso viejo fue en B1 | Repetir la opción en B1 con el código actual | **En parte.** C-093 y C-105, en ventanas distintas (340–345.5 y 280–285.5 s, frente a los 320–325 s del fracaso viejo): los picos cambian mucho, pero las opciones vuelven a fallar el juez |
| C-082 soportada | Sigue a los atributos permutados de los electrodos, no al material | Girar el material sin permutar z_tip | No existe esa corrida. La conclusión frente a «costura» se mantiene |
| C-057 refutada | E y N quedaron fijadas por la celda vecina (receptora) o no se fijaron | Signo del caudal en las caras E y N en la 2.ª externa de 345318 | No (la sonda no registra el signo). Es la salvedad de C-061 |
| Grupo E: fallida (no concluyente) | — | — | Sin objeción de fondo. C-175(2) y C-204 apuntan en contra de las hipótesis, y «fallida» no lo oculta si se cita como lectura (con C-208 en el caso de C-202) |
| C-198 y C-199 soportadas | — | — | C-198 se sostiene con un binario anterior a 1de144e. C-199 solo vale en la versión de C-200 |

## 2. Repeticiones de fracasos ya registrados

No hay cambios numéricos, así que no se repite ningún intento (ni D2.2, ni reglas locales D/E/F/G, ni n_pc_max). Hay un riesgo indirecto: un «soportada» de C-089 apoyado solo en el banco puede leerse como permiso para reintentar reglas locales sobre alpha, cosa que acople-pv.md (Plan D, E1) prohíbe y que C-093 y C-105 confirman con el código actual (ver O4).

## 3. Objeciones

1. **O1 (bloqueante). C-047 la refutan los datos existentes.** p_max del audit es igual a max\|p\| en todos los snapshots comparados; las cifras de C-047 son el máximo con signo. Resolución: citar esa comparación en el cierre y quitar el punto de «Incertidumbre».
2. **O2 (bloqueante). C-044 se reproduce y explica C-015.** Hay 22 corridas con el último paso truncado; el artefacto entra en los picos de C-093 (d26k_n14, e1_n14), y el pico de 805 kPa de C-015 aparece justo en el primer paso tras reiniciar desde un snapshot truncado. Resolución: cerrar C-044 con la regla del grupo B (ruta y comando) y anotar en C-015 la cadena diag_p342a -> diag_p342b.
3. **O3 (bloqueante). La propagación mecánica contradice el refuta_si de la madre** en C-079, C-085 y C-074. Resolución: cerrarlas como «fallida (no concluyente)», o como «refutada en la letra de C-0xx» con la constancia explícita de que el refuta_si de la madre no se cumplió y sus cifras.
4. **O4 (bloqueante). C-089 se mide en el sitio equivocado.** Resolución: apoyar el cierre en C-093 y C-105 (B1), declarar la diferencia de ventana y decir que las opciones siguen refutadas con el código actual.
5. O5. Recoger en C-057 la salvedad de C-061 (candidata ≠ fijada; sin signo del caudal).
6. O6. Redactar C-082 como «sigue al estado girado (material y electrodos)».
7. O7. Limitar C-199 a la versión de C-200 (golden) y cambiar «código actual» por el rango de commits en el grupo B.
8. O8. Citar C-208, C-210 y C-211 si el cierre de C-202 menciona el signo de Br.

Todas las objeciones se resuelven cambiando el estado propuesto o el texto de los eventos de cierre con datos que ya están en `campaigns/b1/`. No hace falta ninguna corrida nueva.

VEREDICTO: rechaza