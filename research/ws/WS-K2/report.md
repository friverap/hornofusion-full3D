# WS-K2: cierre de la meta G2 (ventanas de B1 con el Plan K)

**Meta G2** (`research/QUESTION.md`): las ventanas de B1 en 284.3 s, 294.1 s y
340–346 s, y otras más largas si G1 pasa. Terminado cuando las predicciones
por ventana estén juzgadas contra la base `judge_otp_280`.

**Conclusión: G2 NO se cumplió.**
- La ventana 340–346 s se juzgó dos veces y las dos predicciones quedaron
  refutadas.
- Las ventanas de 284.3 y 294.1 s solo se MIDIERON, con ventanas cortas y sin
  predicción pre-registrada.
- No hubo ventanas largas: la predicción de G1 para el Plan K post-auditoría
  con «A2 parcial» (tope exacto) quedó refutada {C-025} {C-028}. WS-K1 sigue `en_revision`, así que
  G1 no tiene cierre formal. Matiz: la variante que declara C-040 (v2 sin A2)
  sí quitó el ciclo de 342.5 s en la sonda {C-037}, por una holgura que puede
  ser accidental y que sigue abierta {C-039}. Si el brazo K de C-040 fue esa
  variante, el fracaso de G1 no es del mismo binario que se juzgó en
  340–345.5 s; eso no se puede verificar en disco (el binario K no distingue
  v2 con o sin A2; ver «Binarios» en Incertidumbre).
  > [fuente: ledger.py show C-025 | show C-037 | show C-039; research/ws/WS-K1/status.json (estado en_revision)]
- Las ventanas de 284.3 y 294.1 s quedan **sin objeto**, no pendientes. El
  Plan K se archivó sin commit y `src` volvió a HEAD (C-065..C-073: «Plan K no
  se adopta»; {C-279}: «Plan K no se adopto»), así que ya no hay candidato que
  juzgar en ellas. «Sin objeto» descansa SOLO en ese archivo, no en que la
  señal de C-014 falle: C-014 se midió con la v1, y la variante declarada en
  C-040 (v2 sin A2) tiene la misma holgura y es «idéntica a v1 en la sonda»
  {C-037} {C-039}.
- **Motivos del archivo del Plan K.** Los cierres registrados (C-065..C-073)
  dan dos: {C-041} (juez de 340–345.5 s refutado) y C-064 («velocidad
  fantasma que Plan K destapa»). El segundo ya no vale, porque C-064 quedó
  cerrada como fallida sin verificar {C-294}. Para la variante que se juzgó
  en B1 (el brazo K de C-040, declarado v2 sin A2), el motivo efectivo es
  SOLO C-041, y su incumplimiento sale de un único evento al final de
  k1pa_340_n15 cuya causalidad queda sin decidir (ver Incertidumbre). Eso no
  cambia el estado `fallido`: C-040 está refutada por la letra.

  *Lectura del redactor, sin valor de veredicto; no son motivos registrados
  del archivo:*
  - {C-028} juzga k1b (v2 con «A2 parcial», tope exacto), no la variante del
    juez de B1. La refuta por sus incisos (b) y (c); el inciso de ciclo (a)
    pasa por la letra, «solo en la mediana» (osc2 886 Pa ≤ 1000). El ciclo
    de 2 pasos reaparece en la sonda solo en 342517–342533 {C-033}. Si eso
    dispara la regla de aborto del plan (§4, líneas 72–73, sin umbral) es
    lectura del coordinador, no un veredicto, como dicen
    `.claude/rules/acople-pv.md` (entrada «Plan K CERRADO») y el §6 del plan.
  - {C-039} es una lectura de mecanismo soportada, no una refutación: lo que
    quita el ciclo en la sonda es la holgura bajo el tope.
  > [fuente: ledger.py show C-028 | show C-033 | show C-037 | show C-039 | show C-065 (C-066..C-073 con el mismo enunciado) | show C-294; sed -n 626,634p .claude/rules/acople-pv.md; sed -n 94,99p docs/PLAN_K_limitador_en_poisson.md]

Estado propuesto: `fallido`, con `cierre` = «G2 no cumplida: juez 340–345.5 s
refutado (C-041, precisado en C-310/C-311/C-312/C-313); 284.3/294.1 s sin objeto: solo
medidas con v1 (C-014) y Plan K archivado por C-041 y C-064 (C-065..C-073,
C-279; C-064 cerrado sin verificar, C-294)». El
cierre no toca código. Registra cuatro notas: C-310, su errata C-311, C-312 y
su errata C-313. C-310 y C-311 precisan C-041, C-312 precisa C-310 y C-313
corrige C-312 (ver «Incertidumbre»).

**Cómo se cierra** (`research/README.md`, «Estados de un workstream»): si el
panel aprueba este reporte por unanimidad, el coordinador fija
`ledger.py ws-set WS-K2 estado=fallido cierre=<motivo>`; `ledger.py check`
exige para `fallido` la clave `cierre` y los tres «aprueba» de la ronda
vigente. Un `fallido` no abre la compuerta de commit.

## Proceso

1. **La familia:** las paradas de B1 en 284.3, 294.1 y 342.5 s son el tope de
   líquido del piso de poro actuando un paso después de la presión {C-001}.
   Esa hipótesis quedó soportada {C-005} por tres lecturas a posteriori
   {C-002}, {C-003} y {C-004}.
   > [fuente: ledger.py show C-001 (cadena C-005)]
2. **Ventanas cortas con la versión 1** {C-014}, medidas sin pre-registro:
   - 284.33–284.37 s: centinela 9.8 % → 0 %.
   - 294.04–294.07 s: centinela 6.7 % → 0 %, pero el gas sigue en 300 m/s.
   - Son 30–41 pasos con el ciclo en marcha (41 filas de audit en
     284.33–284.37 s y 30 en 294.04–294.07 s; C-014 dice «30-40»). El propio
     C-014 las da como «señal temprana, no veredicto».
   > [fuente: ledger.py show C-014; columna n de su cmd: regime2.py campaigns/b1/k1_284 --w 284.33,284.37 (41) y campaigns/b1/k1_294 --w 294.04,294.07 (30)]
3. **Ventana 340–346 s, primer juez** {C-026}, una sola trayectoria (k1_340):
   quedó refutada {C-027}. En 340–342 s el cent_pg fue 0.5 %, por encima del
   0.3 % de la base. En 342–346 s mejoró mucho.
   > [fuente: ledger.py show C-026 | ledger.py show C-027]
4. **Ventana 340–345.5 s, juez estadístico** {C-040}, 3 trayectorias por
   brazo con el Plan K v2 sin A2 según C-040 (el binario K solo se verifica
   como «Plan K que converge», sin distinguir v2 con o sin A2; ver
   «Binarios» en Incertidumbre): quedó refutada {C-041}.
   - Inciso (i), 344–345.5 s: media del cent_pg con K 4.42 (0.133/0.333/12.8),
     por encima de la mitad de la base, 3.89 (6.667/7.2/9.467). C-041 da 4.40 y
     3.90 porque promedia valores ya redondeados a 1 decimal. El veredicto no
     cambia {C-310}.
   - Inciso (iii): k1pa_340_n15 llega a la centinela de 2.00e6 Pa en
     345–345.5 s.
   > [fuente: ledger.py show C-040 | show C-041 | show C-310 (cmd: cent_pg por trayectoria sin redondeo desde audit.csv, misma definición que scripts/diag/regime2.py --w 344,345.5; promedio de las tres trayectorias por brazo)]
5. **Diagnóstico del estallido de 345.3 s en k1pa_340_n15:**
   - C-042 sobre la familia: fallida por el prerrequisito {C-043}. Fue un
     error de protocolo: el paso final truncado de 1.25e-9 s.
   - Repetición {C-045}: refutada {C-046}. No es la familia del piso de poro.
   - En la celda (9,1,2), el Plan K es necesario para el salto de un paso
     {C-048}, soportada {C-049}. La necesidad vale SOLO para esa celda
     {C-309}. Sin Plan K (diag_k15_k_off) el campo también llega al tope:
     max|p| = 2.000e6 en 345311 y 345312 y 1.851e6 en 345318, en otra celda
     (índices numpy [k,j,i] (1,56,7-8)). El 6.07e5 de C-049 es el máximo con
     signo. Además, ese brazo arranca de diag_k15d/eaf3d_00345310.h5, un estado
     con Plan K, así que no es un control limpio del código base {C-309}
     {C-294}.
     > [fuente: ledger.py show C-309 (cmd h5py: max, min y max|p| de fields/pressure por snapshot en campaigns/b1/diag_k15_k_off)]
   - El salto de Su_liq entra por caras que el Plan K abre {C-052}, soportada
     {C-054}.
   - El flujo de esas caras es la velocidad media de las celdas, no
     Rhie-Chow {C-053}: refutada {C-055}.
   - C-057: fallida (no concluyente) en WS-K12 (C-279).
   - Tope B, Plan K + pc_sat_open {C-059}: refutada {C-062}.
   - Tope C, arreglo A1 {C-060}: refutada {C-063}.
   - Diagnóstico final: golpe de ariete de una velocidad fantasma {C-064}.
     WS-K12 lo cerró sin verificar (C-294), por ser un solo evento.
   > [fuente: ledger.py show C-042 | show C-045 | show C-048 | show C-052 | show C-053 | show C-059 | show C-060 | show C-064]
6. **Hallazgos laterales que WS-K12 cerró:**
   - El paso final truncado sube p_max (C-044, fallida no concluyente; la
     lectura verificada es 19 de 22 corridas).
   - El p_max del audit es max|p| del campo {C-288}, la refutación de C-047,
     que afirmaba lo contrario.
   - El pico de 805 kPa {C-015} quedó cerrado sin verificar.
   > [fuente: ledger.py show C-044 | show C-288 | show C-015]

## Estado de las afirmaciones

Hay 22 afirmaciones raíz en WS-K2, ninguna abierta:

| Estado | Cuántas | Cuáles |
|---|---|---|
| soportada | 7 | {C-001}, {C-002}, {C-003}, {C-004}, {C-014}, {C-048}, {C-052} |
| refutada | 7 | {C-026}, {C-040}, {C-045}, {C-047}, {C-053}, {C-059}, {C-060} |
| fallida | 8 | {C-015}, {C-042}, {C-044}, {C-050}, {C-051}, {C-056}, {C-057}, {C-064} |

> [fuente: python3 -c "import sys,collections; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); r=[x for x in ev if x['ws']=='WS-K2' and not x.get('ref')]; print(len(r), dict(collections.Counter(L.current_state(x['id'],ev) for x in r)))" (22 {'soportada': 7, 'fallida': 8, 'refutada': 7})]

## Incertidumbre

- **Ventanas de 284.3 y 294.1 s:** nunca tuvieron un juez pre-registrado con
  el Plan K. Lo único que hay es la señal temprana de C-014, de la versión
  previa a la auditoría. Esa versión es idéntica en la sonda a la variante
  juzgada en C-040 {C-037}.
- **El fallo del juez C-040 sale de un solo evento al final de n15** {C-312}.
  *Lectura descriptiva post hoc, sin valor de veredicto.* El corte en
  345.318 s se eligió DESPUÉS de ver el resultado, justo al inicio del
  evento de n15: a K le quita su evento y a la base le deja los suyos
  (base_340_n14 toca 2e6 en 344641 y base_340_n15 en 344797, antes del
  corte). Con ese corte, hasta 345.318 s las TRES trayectorias con Plan K
  están unas 10 veces por debajo de las tres de la base en cent_pg:

  | cent_pg (%) | K n12 / n14 / n15 | base otp_280 / n14 / n15 |
  |---|---|---|
  | 344–345.318 s | 0.15 / 0.08 / 0.76 | 7.21 / 7.89 / 10.24 |
  | 345.318–345.5 s | 0.0 / 2.2 / 100.0 | 2.7 / 2.2 / 3.8 |

  La refutación sale entera de los últimos 0.18 s de k1pa_340_n15. Ese evento
  arrastra la media del inciso (i) y es lo único que rompe el inciso (iii).
  No hay indicios de que el Plan K mueva el defecto a otra métrica del audit.
  En 340–345.3 s quedan en el mismo orden que la base:
  - media de vol_lim: K 2.524–2.530e-3, base 2.541–2.548e-3;
  - media de vol_unlinked: K 2.097–2.104e-3, base 2.071–2.086e-3;
  - suma de m_spill: K 2.3–7.1e-11, base 1.04–1.22e-10 (C-312 dice 1.05;
    errata en {C-313}: base_340_n14 da 1.0449e-10);
  - suma de m_alpha_clip: K 5.1–8.3e-11, base 5.6–7.8e-11.

  En esta ventana elegida a posteriori el resultado no se ve como «K mixto
  en general». Es una descripción, no matiza el veredicto de C-041 («la
  mejora no es robusta entre trayectorias»).
  > [fuente: ledger.py show C-312 (cent_pg con la definición de C-310 en [344,345.318) y [345.318,345.5]; medias y sumas en [340,345.3) de los 6 audit.csv de C-041) | show C-313 (m_spill: judge_otp_280 1.222e-10, base_340_n14 1.0449e-10, base_340_n15 1.0909e-10)]
- **Alcanzar el tope no separa a K de la base** {C-310} {C-311}. Hay que contar
  los pasos con p_max >= 1e6 Pa en audit.csv, en 340.0–345.5 s:

  | Trayectoria | Pasos >= 1e6 | Tope 2.0e6 |
  |---|---|---|
  | judge_otp_280 (base) | 1 | no (máx. 1.056e6 en 345266) |
  | base_340_n14 | 4 | sí, desde el paso 344641 |
  | base_340_n15 | 19 | sí, desde el paso 344797 (racha máx. 2) |
  | k1pa_340_n12 / _n14 | 0 | no (máx. 3.30e5 en 340026) |
  | k1pa_340_n15 | 183 seguidos, de 345318 a 345500 | sí, 122 pasos |

  El inciso (iii) solo se aplica a K y el criterio pre-registrado se aplicó a
  la letra. Pero ninguna trayectoria de la base lo cumpliría, y 2 de 3 tocan
  la centinela antes que k1pa_340_n15. En esas 6 trayectorias, lo que
  diferencia a n15 es que se queda pegado al tope ({C-046}: p cerca de
  -1.7e6 hasta 345330; {C-063}: fila incompresible con el gas apagado). Pero
  NO hay prueba de que eso sea propio del Plan K {C-312} {C-313}. Desde el
  mismo estado (diag_k15d/eaf3d_00345310.h5), el brazo sin K también queda
  >= 1e6 Pa en los 10 pasos medidos. Alineados por el paso en que cada brazo
  salta al tope, los dos decaen parecido:

  | Brazo | Salto a 2.0e6 | p_max en los pasos siguientes |
  |---|---|---|
  | diag_k15_k_off (sin K) | 345311 | 1.797e6 en 345320 (10 pasos >= 1e6) |
  | diag_k15_k_on (con K) | 345318 | 1.812e6 en 345320 (fin del brazo) |
  | k1pa_340_n15 (= k_on fila a fila) | 345318 | 1.734e6 en 345325; vuelve a 2.0e6 en 345326 |

  Los brazos son demasiado cortos para medir persistencia: con unos 10 pasos
  no se puede medir un pegado de 183. El salto de k_off de 1.551e5 a 2.0e6
  en su primer paso es el transitorio de cambiar de operador sobre un estado
  de K (C-294/C-309). La versión anterior de este reporte (y C-312) decía
  que el brazo sin K «se pega MÁS»; eso dependía de la ventana 345310–345320,
  que da 10 pasos tras el salto a k_off y solo 3 a k_on, y se RETIRA {C-313}.

  La hipótesis alternativa queda en pie. n15 llegó a un estado que se queda
  sobre 1 MPa con cualquiera de los dos operadores en los pasos medidos, y
  las 3 trayectorias base no lo visitaron en 5.5 s. Los dos brazos arrancan
  de un estado de Plan K, así que ninguno es un control limpio {C-309}
  {C-294}.

  *Evidencia parcial, sin valor de veredicto:* f231_340 sale del mismo
  judge_otp_280/eaf3d_00340000.h5 sin Plan K, con F2.31 decidido por paso
  (`pc_f231_step_freeze = true`). No es la base: su config difiere del de
  base_340_n14 en `output_dir`, `t_final` (346.0) y esa clave, y su binario
  no se verifica en disco. En 340–345.5 s tiene 345 pasos con p_max >= 1e6,
  51 en la centinela de 2e6 (el primero en 344873) y una racha máxima de 82
  pasos seguidos >= 1e6 (345394–345475); en 340–346 s, 482, 66 y 108
  (345481–345588). Un operador segregado sin K, en esta familia de
  trayectorias, también se queda sobre 1 MPa más de 80 pasos seguidos. Eso
  debilita la lectura de que solo K se pega; no decide nada sobre la base.
  > [fuente: diff campaigns/b1/base_340_n14/config.dat campaigns/b1/f231_340/config.dat (117c117, 119c119, 121a122); recuento de p_max >= 1e6 y >= 1.9999e6 y racha máxima de pasos consecutivos >= 1e6 en campaigns/b1/f231_340/audit.csv con 340.0 <= time <= 345.5 y <= 346.0]

  El cierre NO prueba que el Plan K cree presiones no físicas que la base no
  tenga, ni que la base no se quede pegada al tope. Las dos cosas quedan sin
  decidir. Para decidirlas haría falta una de estas dos corridas, y ninguna
  está en disco:
  - la base desde un snapshot de k1pa_340_n15 anterior a 345.25 s. El
    reinicio SÍ está en disco: campaigns/b1/diag_k15c/eaf3d_00345150.h5. Es
    del linaje de n15: el audit de diag_k15c es idéntico fila a fila al de
    k1pa_340_n15 en 340000–345150 (5151 filas), y el de diag_k15d, que
    arranca de ese snapshot, coincide con n15 en p_max y m_gas en sus 181
    filas (345150–345330; 180 filas idénticas completas, la de 345150 difiere
    solo en las columnas E_src_*). El paso 345150 es completo (dt 1.0e-3),
    no truncado como el de diag_p342a (C-290). Advertencia: cambiar de
    operador sobre un estado de K hizo saltar max|p| de 1.551e5 a 2.0e6 en
    el primer paso {C-309}; un brazo base desde 345150 puede tener el mismo
    transitorio y confundir el resultado. Propuesta para el pre-registro
    (la fija el coordinador): el brazo base solo vale si sus primeros pasos
    no saltan al tope, o se compara con un brazo k_on desde el mismo
    snapshot;
  - trayectorias base más largas que lleguen a ese estado.
  > [fuente: ledger.py show C-312 | show C-313 (p_max por paso en campaigns/b1/diag_k15_k_off/audit.csv, diag_k15_k_on/audit.csv y k1pa_340_n15/audit.csv, pasos 345310-345328)]
  > [fuente: comparación fila a fila por `step` de campaigns/b1/diag_k15c/audit.csv y diag_k15d/audit.csv contra k1pa_340_n15/audit.csv (todas las columnas; y solo p_max y m_gas); ls campaigns/b1/diag_k15c (eaf3d_00340000.h5, eaf3d_00345150.h5); columna dt de k1pa_340_n15/audit.csv en el paso 345150]
  > [fuente: ledger.py show C-310 (cmd: recuento de p_max >= 1e6 y = 2e6 por trayectoria en audit.csv) | show C-311 (122 pasos en el tope, no 123)]
- **El golpe de ariete {C-064} es un diagnóstico de un solo evento**, cerrado
  sin verificar {C-294}. C-064 afirma que la velocidad fantasma existe también
  sin el Plan K. Esa generalización al código base se probó dos veces y
  ninguna la sostiene: C-075 salió no concluyente ({C-076}: 2 eventos
  evaluables, menos de 3), y C-077 quedó refutada en la letra ({C-078}: 19 de
  31 eventos con precursor, 61.3 % < 70 %; control 9.2 %).
- **Qué se refutó del limitador dentro del Poisson en 342.5 s.** {C-028}
  refuta H1b (v2 con «A2 parcial», tope exacto) por sus incisos (b) y (c);
  su inciso de ciclo (a) pasa por la letra, «solo en la mediana» (osc2
  886 Pa). El ciclo de 2 pasos reaparece en la sonda solo en 342517–342533
  {C-033}. Que eso dispare la regla de aborto del plan (§4, sin umbral) es
  lectura del coordinador, no un veredicto. La mejora de la variante v2 sin
  A2 viene de la HOLGURA {C-039}: la celda queda bajo el tope y el limitador
  no conmuta. Ese dato apunta a la conmutación del limitador como mecanismo
  del ciclo; no la refuta. *Lectura alternativa, estructural y sin valor de
  veredicto:* el conjunto activo resuelto DENTRO del paso, con el hueco
  congelado en α^n (J-B), no puede quitar un retraso que ocurre ENTRE pasos
  (H0); lo refutado sería esa implementación, no el limitador como
  mecanismo. Que la holgura sea física o accidental sigue abierto en C-039.

  Este cierre no propone combinar el Plan K con D2.6 (`pc_liq_closed_dir`).
  En el código vigente {C-093} quedó refutada por el inciso (d):
  sentinel_gas en FAIL y gap de energía 2.32/2.31 frente a 1.717 de la base.
  No hay ningún argumento de que, combinada con K, no repita ese fallo. (El
  «PEOR en picos» del Plan D no se cita: es anterior a las auditorías 3–21 y
  no vale para el código actual según la regla de vigencia, C-089; en picos,
  C-093 da 0 eventos > 3e5 frente a 31/26 de la base.)

  El siguiente paso, si se retoma la idea, es el que ya marca
  `.claude/rules/acople-pv.md`: no reintentar el conjunto activo con tope
  exacto sin atacar el retraso entre pasos. La pregunta abierta es si basta
  un margen o barrera continua bajo el tope, SIN Poisson implícito. El
  experimento decisivo es un juez B1 de ≥ 3 trayectorias en 340–345.5 s
  desde judge_otp_280/eaf3d_00340000.h5, contra la base de {C-040}/{C-310};
  no la ventana 342.45–342.56 s, que k1pa ya pasó y aun así falló el juez.
  No se usa campaigns/b1/diag_p342a/eaf3d_00342450.h5: se escribió tras un
  paso truncado (dt 1.19e-9) y reiniciar desde él da el artefacto de 805 kPa
  en el primer paso {C-290}. Antes hay que decir en qué difiere un margen
  continuo de tres fracasos registrados: la rampa del piso de poro por
  encima de ALPHA_BED (4547861), D2.4 (`alpha_g_comp_min`, d24 refutada en
  el banco, {C-091}) y llevar el hueco de la banda al Poisson (A20-2). Esa
  diferencia, como lectura del redactor de WS-K1 sin corrida que la
  respalde, está en research/ws/WS-K1/report.md:208–221. Ninguna de estas
  corridas se ha hecho.
  > [fuente: ledger.py show C-028 | show C-033 | show C-039 | show C-093 | show C-089 | show C-290 | show C-091; sed -n 626,642p .claude/rules/acople-pv.md (lectura del coordinador; «no reintentar el conjunto / activo con tope exacto», 641–642); sed -n 659,666p .claude/rules/acople-pv.md; sed -n 201,221p research/ws/WS-K1/report.md]
- **Binarios de los brazos de C-040.** De la base solo se verifican de forma
  indirecta los de base_340_n14 y base_340_n15: sus audit.csv son idénticos
  byte a byte a los de dense_340_n14 y dense_340_n15 ({C-078}, {C-081}), cuyos
  `run.sh` lanzan `campaigns/bin/eaf3d_head_e5d331e_opt`. El binario de
  judge_otp_280 NO se verifica en disco: no tiene `run.sh`, y ni su run.log
  ni su config.dat lo identifican; «mismo src que judge_otp_280» es la
  declaración de C-040. Para el brazo K solo
  hay prueba PARCIAL. Ninguna corrida k1pa_340_* tiene `run.sh`, el run.log
  no registra el binario y `campaigns/bin/eaf3d_k1pa_opt` ya no existe. Lo que
  sí se puede verificar:
  - El config.dat de k1pa_340_n14 es igual al de base_340_n14 salvo
    `output_dir` (línea 117) y dos claves añadidas, `pc_alpha_implicit =
    true` y `pc_ai_tol = 1.0e-3` (líneas 122–123). Lo mismo entre
    base_340_n15 y k1pa_340_n15.
  - Los audit.csv difieren desde la primera fila (n14 y n15).
  - Los tres run.log tienen 5 líneas «[PLAN-K] solves … sin converger». A
    los 25000 solves quedan sin converger 104 (n12), 143 (n14) y 114 (n15),
    es decir, 0.42–0.57 %.
  - `pc_alpha_implicit` se reconoce sin el aviso «[CONFIG] WARNING: unknown
    key».

  Eso demuestra un binario con un Plan K que converge, así que no es la v1
  de C-012 (convergencia 0 %). Pero no separa la v2 con A2 de la v2 sin A2.
  Para separarlas haría falta una salida propia de `pa_sin_A2.patch` o la
  sonda (10,60,2), y estas corridas no tienen ninguna de las dos.

  Evidencia circunstancial (no prueba) de que el brazo K es la v2 sin A2:
  el binario se llamaba `eaf3d_k1pa_opt` (C-040), el mismo prefijo que la
  sonda P-a sin A2 (k1pa_342, {C-037}); los config.dat de k1pa_340_n12/_n14/
  _n15 son de las 18:15:48 del 22-oct, la misma marca de tiempo que C-040,
  y k1pa_342 había terminado a las 18:14:03 (audit.csv). Si es así, C-028
  (k1b, con A2 parcial) no juzga esa variante y el único veredicto contra
  ella en B1 es C-041.
  > [fuente: cmp campaigns/b1/base_340_n1{4,5}/audit.csv campaigns/b1/dense_340_n1{4,5}/audit.csv; cat campaigns/b1/dense_340_n1{4,5}/run.sh; ls campaigns/bin; ls campaigns/b1/judge_otp_280 (sin run.sh); ls -lT campaigns/b1/k1pa_342 campaigns/b1/k1pa_340_n1{2,4,5} (config.dat 18:15:48; k1pa_342/audit.csv 18:14:03); ledger.py show C-040 (ts 18:15:48); diff campaigns/b1/base_340_n1{4,5}/config.dat campaigns/b1/k1pa_340_n1{4,5}/config.dat (117c117 y 121a122,123); grep '\[PLAN-K\]' campaigns/b1/k1pa_340_n1{2,4,5}/run.log; src/mod_config_3d.f90:446 (aviso de clave desconocida)]
- **El fracaso del Plan K está ahora en `.claude/rules/acople-pv.md`** (O5,
  añadido por el coordinador en el cierre de WS-K1/WS-K2): la entrada
  «Plan K CERRADO: refutado y NO adoptado» cubre C-041 por trayectoria, el
  contraste de la base (C-310/C-311), la causalidad sin decidir (C-309) y el
  diagnóstico de un evento (C-064). En `docs/PLAN_K_limitador_en_poisson.md`
  hay una sección «§6. Cierre».
  **Corregido por el coordinador en el ciclo 3** (M-1 y B-1 del auditor, ciclo 2):
  - La entrada dice ahora «183 pasos seguidos con p_max ≥ 1 MPa desde
    345.318 s (122 en la centinela de 2 MPa)» {C-311}.
  - «Lo que separa a K es quedarse pegado al tope» se sustituye por «que el
    pegado de n15 sea propio de K NO está probado». Desde el mismo estado,
    el brazo sin K también queda ≥ 1 MPa en los 10 pasos medidos, y ninguno
    de los dos brazos es un control limpio {C-312} {C-313}.
  - La entrada y el §6 del plan describen el brazo K como «binario no
    identificado: v2 con o sin A2».
  - El reporte y research/ledger.jsonl (C-310 a C-313) entran en el commit
    de cierre.
  > [fuente: grep -n "Plan K CERRADO" -A 60 .claude/rules/acople-pv.md; grep -n "## 6. Cierre" -A 25 docs/PLAN_K_limitador_en_poisson.md]
- **Los fracasos dependen del código del 23-oct-2026** (regla de vigencia,
  C-089).
