## Revisión del refutador de WS-K1 (panel de cierre, ronda 1): rechazo

Rechazo por O1, que es bloqueante: el brazo K podría estar trasladando el problema, y el dato que lo decide está en disco sin usar. «G1 no cumplida» se sostiene por la letra; lo que objeto es lo que el cierre deja escrito en las reglas permanentes sobre B1. O2 y O3 no son bloqueantes.

Todo lo hice en solo lectura: Python sobre audit.csv y h5 existentes, regime2, ledger.jsonl y git diff --cached. No leí revisiones de otros revisores.

### 1. Conclusiones, mejor alternativa y dato que las separa

**C1. «G1 no se cumplió: H1 (C-012) y H1b (C-028) refutadas».**
- **Alternativa:** los criterios estaban mal planteados (|p|<20 kPa, grad_hid) o fallan por un paso de margen (inciso (c): 4/109 frente a 3.49), así que no hay defecto de diseño.
- **Qué las separa:** ≥3 trayectorias de v2 completo en 342.45-342.56 s. No existen.
- **Valoración:** el reporte ya lo declara. Como cierre por la letra es correcto; sin objeción.

**C2. «Plan K no adoptado es una DECISIÓN apoyada en C-041 (vigente) y C-064 (hoy fallida, C-294)».**
- Comprobado en el registro: C-065 da como motivo solo la aprobación del usuario.
- Sin objeción.

**C3. «La holgura (v2 sin A2) quita el ciclo en la sonda» (C-039).**
- **Alternativa:** el efecto no viene del factor de acc_face sino de `unl_on=.false.`.
- **Qué las separa:** una corrida con factor 1 y `unl_on` activo. No existe.
- **Valoración:** el reporte ya lo declara.

**C4. «En B1 el dato de esta familia va en sentido CONTRARIO a D2.2: K baja p>100k en 4/4 trayectorias» (reporte y acople-pv.md staged).**
- Los números de regime2 son correctos (los recalculé).
- **Alternativa:** K baja la presión porque deja entrar el líquido en el lecho. El problema no desaparece: pasa a otra métrica (O1).
- **Qué las separa:** los snapshots 345500, que existen. Dicen esto:

| Métrica en 345.5 s | Base (n14 / n15) | K (n12 / n14 / n15) |
|---|---|---|
| Líquido en celdas de lecho (alpha_s>0.01) | 0.1545 / 0.1539 m³ | 0.1587 / 0.1587 / 0.1573 m³ |
| Celdas de lecho con alpha_g<0.016 y alpha_l>0.05 | 117 / 121 | 133 / 130 / 142 |
| Ídem con alpha_g<0.02 | 132 / 133 | 143 / 145 / 155 |
| Ídem con alpha_g<0.05 | 150 / 155 | 162 / 165 / 169 |
| Centroide z del líquido | 0.2257 / 0.2255 m | 0.2250 / 0.2249 / 0.2250 m |

- El líquido total casi no cambia (1.0715 frente a 1.0723-1.0729 m³), así que el exceso en el lecho es redistribución y no solo la fusión extra.
- Las columnas por paso en [340,345.3) van en el mismo sentido: m_melted +1.4-1.9 % y E_iph_sol +1.7-2.2 % en K.
- Las celdas de lecho con el gas en el piso son la población del ciclo (C-030). n15, la trayectoria que se pegó, es la que más tiene.
- **Valoración:** esto no prueba que sea un defecto; puede ser que la base expulse líquido con sus picos de presión. Pero contradice que no haya indicio de traslado y matiza «en sentido CONTRARIO».

**C5. «La firma del audit identifica el brazo K como v2 sin A2; la holgura muy probablemente ya falló el juez».**
- **Alternativa:** el signo de vol_lim no discrimina A2 en el estado de 340 s (O2).
- **Qué las separa:** la prueba bit a bit. No se ha hecho.
- **Lo que ya dicen los datos:** p_max apunta en sentido contrario (n12−k1_340 difiere hasta 70.8 Pa y −862 Pa en 10 pasos; k1pa_342−k1_342 menos de 1.4 Pa).

**C6. «No reintentar el conjunto activo con tope exacto».**
- Se apoya en una sola trayectoria (k1b y k1pb son casi idénticas). El reporte ya lo declara como salvedad; sin objeción nueva.

### 2. Repeticiones de fracasos registrados

- El cierre no propone ningún experimento nuevo.
- La «barrera continua bajo el tope» se compara de forma explícita con D2.2/D2.2c (Plan D), 4547861, D2.4/C-091 y A20-2, y se admite que la diferencia con D2.2 es conjetura. Correcto.
- Pero O1 reabre esa comparación: la lección de D2.2 («cerrar en el Poisson sin que el momento lo sepa mueve el problema») tiene ahora un indicio en B1. Hay más líquido en el lecho y más celdas en el piso del gas. El reporte afirma lo contrario sin haber mirado ese dato.

### 3. Objeciones

**O1 (bloqueante).** El reporte da por «no hecha» la comparación de snapshots, pero los 345500 están en disco y muestran más líquido en el lecho y más celdas de lecho saturadas en K, con rangos que no se solapan con ningún umbral.
- **Se resuelve** incluyendo esa tabla en el reporte y en la entrada «Plan K CERRADO», y matizando «sentido CONTRARIO», «la lección del banco no predice B1» y «sin traslado».
- **Pendiente explícito:** una serie temporal de esas métricas en base y K, que no existe, para separar «K deja entrar líquido» de «la base lo expulsa».

**O2 (no bloqueante).** La firma del audit no es discriminante a 340 s.
- El signo de A2 se calibró en otro estado, y el punto 5 del propio reporte dice que el signo neto del factor no es unívoco.
- p_max da la lectura contraria.
- **Se resuelve** recompilando P-a/P-b sobre 1bc9832 y comparando bit a bit 10 pasos desde judge_otp_280/eaf3d_00340000.h5.
- **Mientras tanto,** escribir «declarado en C-040; firma compatible, no discriminante» y quitar «muy probablemente» de la directiva de retoma.

**O3 (no bloqueante).** En el diff staged, el §6 de `docs/PLAN_K_limitador_en_poisson.md` (línea 101) dice «medida solo en k1pa_342», y acople-pv.md y el reporte dicen k1_342 y k1pa_342.
- **Se resuelve** corrigiendo esa línea.

Archivos relevantes:
- /Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K1/report.md
- /Users/frariv/Horno/hornofusion-full3D/.claude/rules/acople-pv.md (entrada «Plan K CERRADO», línea 618 en adelante)
- /Users/frariv/Horno/hornofusion-full3D/docs/PLAN_K_limitador_en_poisson.md (§6, línea 101)
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/{base_340_n14,base_340_n15,k1pa_340_n12,k1pa_340_n14,k1pa_340_n15}/eaf3d_00345500.h5

VEREDICTO: rechaza