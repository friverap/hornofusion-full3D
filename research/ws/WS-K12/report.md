# WS-K12 — Cierre de las afirmaciones abiertas del registro

**Meta:** G3 (higiene del registro; abarca afirmaciones de WS-K2, WS-K3,
WS-K7, WS-K8, WS-K9, WS-K10 y WS-K11). **Sin cambio numérico** y sin cambios
en `src/` ni `tests/`. Pedido del usuario el 28-oct-2026: cerrar las
afirmaciones abiertas, sin cerrar nada que el panel no apruebe.

**Qué se somete al panel.** Para cada afirmación del alcance, el evento de
cierre PROPUESTO con su texto literal. Ningún evento está registrado todavía.
El coordinador los registra con `ledger.py add` tal como aparecen aquí, y
solo si el panel aprueba por unanimidad. Para el **grupo E** el usuario
decidió el 28-oct-2026 añadir a `ledger.py` el estado cerrado `sin_decidir`.
Es el único cambio de herramienta de este WS y va en el diff staged (ver
«Cambio de herramienta»).

Forma común de todos los eventos: `python3 scripts/research/ledger.py add
--tipo resultado --autor coordinador --ws <WS de la afirmación> --ref <C-nnn>
--estado <estado> --enunciado "<texto literal>" [--ruta ... --cmd "..."]`. El
texto empieza por «Cierre WS-K12 (panel):».

## Alcance (regla declarada)

Entra en este cierre:

1. Las afirmaciones raíz cuyo estado vigente está fuera de CERRADOS: 18 de 64
   según `ledger.py open`.
   > [fuente: python3 scripts/research/ledger.py open | head -1]
2. Toda predicción o hipótesis no raíz cuyo estado vigente no está cerrado,
   siguiendo los veredictos registrados sobre sus enmiendas y sobre sus
   predicciones hijas:
   - sin decidir: C-126, C-130, C-135, C-144, C-170 y C-202, y C-212;
   - hipótesis de WS-K11 sin experimento: C-237 y C-261.
3. Los resultados no raíz que están en en_disputa y que ningún evento cerrado
   posterior corrige: C-154 y C-168.

Barrido: 101 eventos no raíz con `current_state` fuera de CERRADOS.
> [fuente: python3 -c "import json,sys; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); print(sum(1 for e in ev if e.get('ref') and L.current_state(e['id'],ev) not in L.CERRADOS))"]

De esos 101, entran 11 (puntos 2 y 3). Los otros 90 quedan fuera por estos
motivos:

- **61 resultados en «propuesta»**: C-094, C-103, C-113, C-141, C-142,
  C-183, C-185 a C-188, C-190, C-192, C-197, C-200, C-201, C-205 a C-211,
  C-214 a C-223, C-228 a C-230, C-233 a C-236, C-240 a C-243, C-250, C-251,
  C-258 a C-260, C-262 y C-267 a C-278. Son lecturas, correcciones o
  precisiones de otro evento. Ninguno lleva `refuta_si` ni criterio (0 de 61),
  así que no hay nada que decidir; valen lo que vale el evento al que se
  refieren.
- **C-193** (resultado, propuesta): es una lectura. Su «pre-registrada» viene
  de su predicción hija C-194, que se juzgó soportada a través de C-195 →
  C-196.
- **C-146, C-162 y C-181** (resultados soportados): ya están cerrados.
  `current_state` toma el estado de un evento posterior que los cita.
- **20 veredictos**. Catorce tienen estado propio cerrado: C-093, C-102,
  C-112, C-184, C-196, C-225, C-227, C-232, C-239, C-245, C-249, C-256, C-265
  y C-266. Los otros seis están en en_disputa y siguen a su predicción del
  grupo E: C-127, C-131, C-139, C-174, C-204 y C-213.
- **Enmiendas C-122, C-172 y C-203**: siguen a su predicción (C-121, C-170 y
  C-202, todas del grupo E).
- **C-169 y C-194**: ya se juzgaron a través de su enmienda (C-171 → C-173
  refutada; C-195 → C-196 soportada). No necesitan evento nuevo.

`current_state` (`scripts/research/ledger.py:158-164` con el diff staged;
`:144-150` en HEAD) solo mira los eventos
con `ref` directa. Por eso una predicción juzgada a través de su enmienda
aparece como «enmendada», y una madre cuya hija se juzgó aparece como
«pre-registrada».

Los miembros no raíz del grupo E no aparecen en `open` por esa misma
limitación; su cierre se registra igual, con `--ref` a cada uno.

## Regla de cierre aplicada

- **soportada / refutada «en la letra de C-yyy»** (grupo A). Se usa cuando
  una predicción pre-registrada hija tiene ese veredicto y prueba el
  enunciado de la madre. Si el `refuta_si` de la madre no coincide con el
  veredicto, el texto del cierre lo dice con cifras.
- **fallida (no concluyente)**. Se usa cuando la predicción hija probó una
  afirmación que la madre no enuncia, o cuando su criterio no tiene una
  cláusula que decida la madre. En ese caso el veredicto de la hija no se
  propaga (C-057, C-079, C-085, C-089).
- **soportada / refutada por relectura** (grupo B). Se usa solo cuando la
  relectura de la salida guardada del propio check de la afirmación,
  ejecutada hoy, decide su enunciado literal. En C-047 es su propio comando.
  En C-198 su comando lee `tests/out`, que no es estable (ver B1); se usan
  los logs versionados de WS-K9 con la salida del mismo check
  (`check_audit.py`, mismas líneas `mass_gas` y `mass_gas_flux_closure`),
  más la lectura del código para la causa y el registro del ejecutable. El texto dice qué binario produjo
  esa salida y cita la lectura del `src/` actual que muestra que esa ruta de
  código no cambió. No es un criterio previo, y por eso el texto lo llama
  «relectura». Solo C-198 (soportada) y C-047 (refutada) cumplen esa
  condición.
- **Relectura que decide solo una parte** (C-044, C-154, C-199): **fallida
  (no concluyente)**, con lo verificado como lectura en el texto del cierre.
  Es el mismo trato que reciben en el grupo A las madres cuya hija prueba
  solo una parte (decisión del usuario, ciclo 2).
- **fallida (cerrada sin verificar)**: la línea no sigue y no hay prueba
  (precedente: C-065 a C-073).
- **«sin decidir» por la letra de su criterio**: NO se cierra como fallida
  (grupo E). En sus criterios, «fallida» queda reservado a los prerrequisitos
  que no se cumplen (C-121, C-172, C-202), y C-218 dejó escrito para C-204
  «la etiqueta sigue SIN DECIDIR y no fallida».

## Grupo A — veredicto ya emitido sobre la predicción hija

| Afirmación | Predicción → veredicto | Cierre propuesto |
|---|---|---|
| C-057 [WS-K2] (hipótesis) | C-058 → C-061 refutada | **fallida (no concluyente)**: C-058, leída por nombre de cara, sí quedó refutada (E y N fijadas, `:269`), pero esas caras son salidas de la celda saltada y el `refuta_si` de C-057 habla de caras de entrada: la hija probó otra afirmación |
| C-074 [WS-K3] (hipótesis) | C-075 → C-076 fallida; C-077 → C-078 refutada | **refutada** en la letra de C-077; su `refuta_si` no se cumplió |
| C-079 [WS-K3] (resultado) | C-080 → C-081 refutada | **fallida (no concluyente)**: C-080 probó otra afirmación |
| C-082 [WS-K3] (hipótesis) | C-083 → C-084 soportada | **soportada**, con el alcance «estado girado = material + atributos de los electrodos» |
| C-085 [WS-K3] (hipótesis) | C-086 → C-087 refutada | **fallida (no concluyente)**: C-086 juzgó el paso 341706 y C-085 enuncia el 341705 |
| C-089 [WS-K3] (resultado) | C-090 → C-091 soportada (banco) | **fallida (no concluyente)**: C-090 no tiene cláusula que decida la tesis |

Cifras de los datos crudos:

- C-078 (n14): 31 eventos, 19 con precursor (61.3 %); control 453/4919
  (9.2 %).
  > [fuente: campaigns/b1/dense_340_n14/c077.out | tail -1 campaigns/b1/dense_340_n14/c077.out]
- C-081 (n15): 26 eventos, 18 con precursor (69.2 %); control 457/4837
  (9.4 %). Celdas: (1,59,9) 22, (1,58,9) 2, (1,0,9) 1, (1,58,8) 1.
  > [fuente: campaigns/b1/dense_340_n15/c080.out | tail -1 campaigns/b1/dense_340_n15/c080.out; grep '^ *evento paso' campaigns/b1/dense_340_n15/c080.out | grep -oE '\(1, [0-9]+, [0-9]+\)' | sort | uniq -c]
- C-084 (estado girado): 21 eventos, 17 con precursor (81.0 %); control
  480/4948 (9.7 %). Celdas: (1,19,9) 18, (1,20,9) 3.
  > [fuente: campaigns/b1/dense_rot_n15/c083.out | tail -1 campaigns/b1/dense_rot_n15/c083.out; grep '^ *evento paso' campaigns/b1/dense_rot_n15/c083.out | grep -oE '\(1, [0-9]+, [0-9]+\)' | sort | uniq -c]
- C-087 y C-088, valores de Su l/g/c:
  - 341706, 1.ª externa: −2.20e-2 / −2.21e-1 / −2.51e-4; cuota del gas
    0.908.
  - 341705, 1.ª externa: +1.26e-2 / +2.18e-3 / −1.27e-3; cuota del líquido
    1.26e-2/(1.26e-2 + 2.18e-3 + 1.27e-3) = 0.785.
  - 341705, externas 2 a 5: act TF, Su_gas = Su_comp = 0; cuota del líquido
    1.0.
  > [fuente: campaigns/b1/diag_p417/c086.out | grep -E '^34170[56] o[1-5]' campaigns/b1/diag_p417/c086.out]

Los `--cmd` de C-084 y C-087 (phantom_scan.py en modo HDF5 y probe_p.py) ya
no reproducen lo registrado. En `dense_rot_n15` solo quedan 13 snapshots, y
la versión actual de `probe_p.py` imprime otra tabla. Por eso los cierres
citan como comando la LECTURA de la salida guardada (`c083.out`, `c086.out`).

**Eventos literales del grupo A:**

- **A1** — `--ws WS-K2 --ref C-057 --estado fallida --ruta campaigns/b1/diag_c058 --ruta research/ws/WS-K1/patches/v2_completo_sobre_HEAD.patch --cmd "grep -nE 'PROBE-(S|P)\] paso +345318' campaigns/b1/diag_c058/run.log; sed -n '195p;201p;229p;269p;329,344p' research/ws/WS-K1/patches/v2_completo_sobre_HEAD.patch"`
  > Cierre WS-K12 (panel): fallida (no concluyente). Lectura unica de C-058: por NOMBRE de cara, como la enuncia su criterio. Con esa lectura la clausula de refutacion de C-058 SI se cumplio y C-061 (refutada) es literal: E y N quedan candidatas (cx=1 en E en las it 2-6 y en N en las it 1-6 de la 2a externa de 345318) y las candidatas se fijan en el CG siguiente (v2_completo_sobre_HEAD.patch:269, fx = cx). Ese veredicto no se propaga a C-057 porque C-058 probo otra afirmacion: enumero T, E y N por nombre dando por hecho que seguian siendo ENTRADAS de (9,1,2), como en la 1a externa (C-054), mientras que el refuta_si de C-057 habla de caras de ENTRADA. Por construccion del parche (lectura de codigo): s_nw = 1 por defecto (:195), la celda se salta si act_g = F (:201) y las candidatas son caras que entran a una celda con s < 1 (:229; fix_face, :329-344). Con (9,1,2) saltada (s = 1), las E y N fijadas son SALIDAS de (9,1,2), fijadas por la vecina receptora, y ninguna cara de entrada puede fijarse. Confirmado en la sonda: SALTADA (act_g=F) en las it 1-6, y la cara T (68 % de la entrada, C-054) nunca es candidata. Lectura de C-063 (refutada, arreglo A1): con la celda dentro del bucle s = 1 y p(9,1,2) sigue en 2.0e6 Pa; salir del conjunto activo no es la causa, lo es la fila incompresible al apagarse el gas. Plan K no se adopto.
- **A2** — `--ws WS-K3 --ref C-074 --estado refutada --ruta campaigns/b1/dense_340_n14/c077.out --ruta campaigns/b1/dense_340_n15/c080.out --ruta campaigns/b1/dense_rot_n15/c083.out --cmd "tail -1 campaigns/b1/dense_340_n14/c077.out; tail -1 campaigns/b1/dense_340_n15/c080.out; tail -1 campaigns/b1/dense_rot_n15/c083.out; for f in dense_340_n14/c077.out dense_340_n15/c080.out dense_rot_n15/c083.out; do grep '^ *evento paso' campaigns/b1/\$f | awk '{print \$3, \$NF}' | tr '\\n' ' '; echo; done"`
  > Cierre WS-K12 (panel): refutada en la letra de C-077 (veredicto C-078: 31 eventos, 19 con precursor = 61.3 % < 70 %; control 9.2 %); C-075 fue no concluyente (C-076). El refuta_si propio de C-074 ('sin precursor, o igual de frecuente en instantes quietos') NO se cumplio: precursor 61.3 % (n14, C-078), 69.2 % (n15, C-081, descriptivo) y 81.0 % (estado girado, C-084, descriptivo) frente a un control de 9.2-9.7 %. Lo que se refuta es el 'van precedidos' universal con umbral de 70 %: los 12 primeros eventos de n14 (341.83-343.06 s) no tienen precursor. Lectura descriptiva, sin valor de prueba (corte post hoc): el patron se repite en las tres trayectorias. Los primeros eventos de cada una no tienen precursor (0/19: n14 los 12 hasta 343062, n15 los 4 hasta 343291, estado girado los 3 hasta 342959); despues, n14 19/19, n15 18/22 y girado 17/18. La alternativa 'dos regimenes' separaria los picos tempranos, del mecanismo de fuente de liquido/F2.31 (C-085/C-088), de los tardios, con velocidad fantasma; el cierre refutado no dice que la velocidad fantasma no importe.
- **A3** — `--ws WS-K3 --ref C-079 --estado fallida`
  > Cierre WS-K12 (panel): fallida (no concluyente). La prediccion hija C-080 probo una afirmacion distinta (alpha_s del lecho, ALPHA_BED <= alpha_s <= 0.05) que C-079 no enuncia; su veredicto C-081 (refutada, 17/26 = 65.4 %) no juzga C-079. Su refuta_si ('otra trayectoria (n15) tiene picos en celdas distintas') no se decide aqui: en n15 los 26 eventos de C-081 estan en la misma esquina, (1,59,9) 22, (1,58,9) 2, (1,0,9) 1 y (1,58,8) 1, y (1,58,8) no esta entre las celdas que lista C-079 ((1,59,9), (1,0,9), (1,58,9)); que eso cumpla el refuta_si depende de leer 'celdas distintas' como celda o como esquina. La ubicacion queda decidida por C-082/C-084. El crecimiento de u_ph con los picos (Spearman 0.53) no se probo.
- **A4** — `--ws WS-K3 --ref C-082 --estado soportada --ruta campaigns/b1/dense_rot_n15/c083.out --cmd "tail -1 campaigns/b1/dense_rot_n15/c083.out; grep '^ *evento paso' campaigns/b1/dense_rot_n15/c083.out | grep -oE '\(1, [0-9]+, [0-9]+\)' | sort | uniq -c"`
  > Cierre WS-K12 (panel): soportada en la letra de C-083 (veredicto C-084): con el estado de 340 s girado 120 grados, 21/21 eventos > 3e5 Pa en j 16..22 ((1,19,9) 18, (1,20,9) 3) y 0 en la costura. Alcance: el punto caliente sigue al estado girado, que incluye el material Y los atributos de los electrodos (z_tip permutado [1.628, 1.613, 1.657] -> [1.657, 1.628, 1.613]); no sigue a la costura theta ni a la descomposicion MPI. No separa material de atributos del electrodo: esa corrida (girar el material sin permutar z_tip, o permutar solo z_tip) no existe. El giro movio juntos el material y elec_z_tip, que es la unica asimetria de los electrodos (C-082: posiciones 0/120/240 grados, sin fase AC, potencias iguales). Dato parcial en contra de que lo explique z_tip, sin valor de prueba: el punto caliente original esta bajo el electrodo 1 (theta = 0), el de z_tip INTERMEDIO (1.628), no bajo el mas bajo (1.613). La alternativa MPI si queda excluida: con 15 ranks la rejilla es 1x5x3 (run.log), con fronteras theta en j = 0, 12, 24, 36 y 48, y el punto caliente girado (j 19-20) cae dentro de un bloque. El comando es la lectura de la salida guardada: el directorio conserva solo 13 snapshots y phantom_scan.py en modo HDF5 ya no da los 21 eventos.
- **A5** — `--ws WS-K3 --ref C-085 --estado fallida --ruta campaigns/b1/diag_p417/c086.out --cmd "grep -E '^34170[56] o[1-5]' campaigns/b1/diag_p417/c086.out"`
  > Cierre WS-K12 (panel): fallida (no concluyente). C-085 enuncia el paso 341705; la regla pre-registrada de C-086 eligio P = 341706, que es la RELAJACION del pico (p_in 3.71e5 ya entra; salvedad de C-087), y ahi la cuota del gas es 0.908 (Su l/g/c -2.20e-2 / -2.21e-1 / -2.51e-4). Ese veredicto (C-087, refutada) prueba un paso que la madre no enuncia y no se propaga. En 341705, sin prueba pre-registrada: en la 1a externa la cuota del liquido es 1.26e-2/(1.26e-2 + 2.18e-3 + 1.27e-3) = 0.785 (en la direccion de C-085; con el umbral de C-086 seria >= 0.6), y en las externas 2-5 vale 1.0 pero esta confundida, porque act_g=F saca el gas de la fila (act TF, Su_gas = Su_comp = 0). Lectura de C-088, sin valor de prueba: F2.31 apaga el gas en la 2a externa, aP cae 68x y la fuente del liquido se resuelve solo contra el liquido (pp 3.37e5). El refuta_si de C-085 no se cumple en 341705. Lo que separa las dos lecturas es el refuta_si de C-088 (mantener el gas en la fila durante todo 341705), que no se corrio (D1).
- **A6** — `--ws WS-K3 --ref C-089 --estado fallida --ruta campaigns/b1/judge_d26k_n15 --ruta campaigns/b1/judge_d26k_n14 --ruta campaigns/b1/judge_e1_n15 --ruta campaigns/b1/judge_e1_n14 --cmd "for n in judge_d26k_n15 judge_d26k_n14 judge_e1_n15 judge_e1_n14; do python3 tests/integration/check_audit.py campaigns/b1/\$n | grep -E 'energy_balance +dE'; done"`
  > Cierre WS-K12 (panel): fallida (no concluyente). El criterio de C-090 solo juzga cada variante en un banco nuevo (primer pico, 341.5-341.72 s) y no tiene clausula que decida la tesis de C-089 (los fracasos viejos son condicionales al codigo de su fecha); el 'soportada' de C-091 no se propaga. Los fracasos viejos fueron en B1, no en el banco: D2.6 'peor en picos y gas' en 320-345 s (docs/PLAN_D_acople_implicito_alpha_p.md, seccion 7) y E1 con 7x mas picos > 100 kPa en 320-325 s (.claude/rules/acople-pv.md). Con el codigo actual, los jueces B1 refutan d26k y e1 por la letra de su inciso (d), que exige PASS en checks que la base ya falla: la base de C-092 da FAIL en sentinel_p, sentinel_gas, energy_balance (1.717) y regime_*. Frente a la base, d26k y e1 MEJORAN los picos (0 eventos > 3e5 frente a 31/26; pico 1.5e5-2.0e5 frente a 2.0e6) y la centinela de gas (pasos con u_gas >= 300 en 340001-345500, n15/n14: d26k 23/77, e1 2/1, base 201/131 en C-093; recuento de hoy con umbral 299.999: base 200/131) y EMPEORAN la energia (gap/permitido n15/n14: d26k 2.32/2.31 y e1 1.79/1.84 frente a 1.717 en C-093; check_audit.py de hoy da d26k 2.321/2.334 y e1 1.793/1.839, y el de 6127dd7, el vigente a la hora de C-093, da lo mismo en d26k: el 2.31 de d26k_n14 en C-093 es una errata, no un cambio del checker). En 280-285.5 s (C-105), e1 mejora picos y centinela de gas (0 pasos u_gas >= 300 frente a 100 de la base) y empeora la reescritura EOS del gas (0.615 frente a 0.552 de la base truncada; FAIL mass_gas, que la base tambien falla); su falla de energia es el residuo de la sub-relajacion (C-105 e). No hay corrida de E1 con el codigo actual en 320-325 s, la ventana del fracaso viejo. Siguen refutadas con el codigo actual: d22b, d24, d26fs, e1b y f (banco, C-091), y d26k y e1 (B1, por la letra de (d), C-093; e1 tambien C-105); d22c no es evaluable (C-091). Nota: el pico de d26k_n14 (2.001e5) y el de e1_n14 (1.474e5) en C-093 son la fila del paso final truncado (C-044); sin ella son 1.240e5 y 1.455e5. Este cierre es el del enunciado de C-089 como afirmacion contrastable, no el de la regla: la regla de metodo (un fracaso viejo se repite en el banco actual antes de descartar) sigue vigente como metodo (.claude/rules/acople-pv.md:266-273).

## Grupo B — relectura de salidas existentes

| Afirmación | Cierre propuesto | Relectura |
|---|---|---|
| C-198 [WS-K9] | **soportada** | Antes del arreglo: FAIL. Con el arreglo: PASS. Las cifras son las de C-198 (logs versionados del mismo check). La causa y el registro del ejecutable, por lectura del código (2b65e11) |
| C-199 [WS-K9] | **fallida (no concluyente)**; lo verificado (golden) queda como lectura | 60 PASS con err rel 0 frente a v131; v132 = v131 + `cold_flow_noenergy_n4`. La comparación celda a celda no se sostiene tal como se enunció (C-200) |
| C-044 [WS-K2] | **fallida (no concluyente)**; la subida de p_max en el paso truncado, la ruta de código y el contraste C-043/C-046 quedan como lectura | Paso final truncado (dt 1.19e-9 a 1.27e-9) en 22 corridas, sube p_max en 19, entre ellas tres del binario e5d331e; la ruta sigue en `src/main_3d.f90:335-340`. «Contamina reinicios»: contraste directo ya registrado en C-043/C-046 (reinicio desde snapshot truncado frente a snapshot de paso completo, 345.15 s): 0/180 frente a 180/180 filas idénticas a la original |
| C-047 [WS-K2] | **refutada** | p_max del audit = max\|p\| del campo en 395/395 snapshots de 6 corridas. Las cifras de C-047 para el campo eran el máximo CON SIGNO, y su cifra de audit en 345.28 s es errónea |
| C-154 [WS-K7] (resultado) | **fallida (no concluyente)**; sus cifras quedan como lectura | Su propio comando reproduce hoy exactas 0.384/0.163, 0.491/0.165 y las derivas 0.380→0.426 y de 0.521 a un máximo de 0.682 (último tramo 0.639); la interpretación queda como lectura (antes en el grupo E) |

Datos:

- **C-198.** Antes del arreglo (binario previo eaf3d_k8b_opt según C-198; el
  log no registra el ejecutable), en `coldnoE_binario_previo_check.txt`: FAIL `mass_gas_flux_closure`, con
  max|resto| 3.41e-06 y sum m_gas_out 0. Con el arreglo, en el test-full de
  WS-K9: PASS, con max|resto| 1.69e-21 y sum m_gas_out −7.1206e-6 kg. Las dos
  rutas están versionadas.

  El cierre se apoya SOLO en esos dos logs versionados. `tests/out` no entra:
  está ignorado por git (`.gitignore:20`), `make test-*` lo sobrescribe, y su
  `audit.csv` actual lo produjo un binario con el instrumento de 1de144e sin
  commitear (tiene las columnas `m_gas_bx_multi` y `m_gas_bx_free`, 149-150,
  que no existen en `2b65e11:src/mod_audit.f90` y que introduce 1de144e). La
  versión anterior de este reporte le atribuía «código de 2b65e11..1de144e~1»:
  era falso y se retira.
  > [fuente: research/ws/WS-K9/logs/coldnoE_binario_previo_check.txt, research/ws/WS-K9/logs/test_full.txt | grep -E 'mass_gas |mass_gas_flux_closure' research/ws/WS-K9/logs/coldnoE_binario_previo_check.txt; sed -n 2138,2175p research/ws/WS-K9/logs/test_full.txt | grep -E 'mass_gas |mass_gas_flux_closure'; head -1 tests/out/cold_flow_noenergy_n4/audit.csv | tr ',' '\n' | grep -n m_gas_bx (149, 150); git show 2b65e11:src/mod_audit.f90 | grep -c m_gas_bx (0); git show 1de144e:src/mod_audit.f90 | grep -c m_gas_bx (1)]
- **C-199.**
  > [fuente: research/ws/WS-K9/logs/test_full.txt, tests/golden/metrics_v131.json, tests/golden/metrics_v132.json | sed -n 5087,5149p research/ws/WS-K9/logs/test_full.txt | grep PASS | grep -c 'err rel 0.000e+00' (60); python3 -c "import json; a=json.load(open('tests/golden/metrics_v131.json'))['runs']; b=json.load(open('tests/golden/metrics_v132.json'))['runs']; print(set(b)-set(a), [k for k in a if a[k]!=b[k]])"]
- **C-044.** Última fila de `audit.csv` frente a la penúltima:

  | Corrida | Paso final y dt | p_max: penúltima → última |
  |---|---|---|
  | diag_k15a | 345150, dt 1.25e-9 | 3.84e4 → 2.46e5 |
  | dense_340_n15 | dt 1.258e-9 | 5.75e4 → 2.04e5 |
  | judge_e1_n14 | dt 1.258e-9 | 2.75e4 → 1.47e5 |
  | judge_d26k_n14 | dt 1.258e-9 | 1.86e4 → 2.00e5 |

  - De 22 corridas de `campaigns/b1` con último dt < 1e-6, en 19 sube p_max.
    En diag_c060 baja (1.77e6 → 9.98e5), en f231_340 baja un poco (2.19e5 →
    2.10e5), y en k1pa_340_n15 queda en el tope de 2e6. El barrido es el
    `--cmd` de B3.
  - Binario e5d331e: `campaigns/b1/dense_340_n15/run.sh:4` y
    `campaigns/b1/judge_c092_chain.sh:3` (este crea judge_{d26k,e1}_n{14,15}).
  - El inciso «contamina reinicios» no lo decide el comando de C-044
    (`tail -2` de diag_k15a), pero el registro YA tiene el contraste directo
    y controlado, en 345.15 s, de la misma sesión que C-044 (las dos
    registradas a las 09:55:05):
    - C-043: diag_k15a (t_final 345.15, fuera de la malla de pasos) →
      diag_k15b, que reinicia desde `diag_k15a/eaf3d_00345150.h5`, escrito
      tras el paso truncado.
    - C-046: diag_k15c (t_final 345.150999999) → diag_k15d, que reinicia
      desde `diag_k15c/eaf3d_00345150.h5`, escrito tras un paso completo
      (dt 1e-3).
    - Las cuatro corridas usan 15 ranks y el binario de k1pa_340_n15: el
      tramo a reproduce la original en 5150 de 5151 filas (C-043) y el
      tramo c en 5151/5151 (C-046). Según C-049 ese código incluye Plan K
      (el brazo con Plan K es idéntico a diag_k15d). Las configuraciones de
      diag_k15b y diag_k15d son idénticas salvo restart_file, output_dir y
      t_final.
    - Frente a k1pa_340_n15 en 345151–345330: diag_k15d 180/180 filas de
      audit.csv idénticas; diag_k15b 0/180.
    - Primer paso tras reiniciar (345151): p_max 2.98e5 en diag_k15b frente
      a 3.81e4 en diag_k15d.
    - Filas con p_max > 3e5: diag_k15b 0 y diag_k15d 62, que llega al tope
      de 2e6 en 345318, como la original. La contaminación no dura dos
      pasos: cambia la trayectoria y suprime el estallido de 345.3 s.
    - El control de la validez de C-087 (reinicio de diag_p417 desde
      `dense_340_n15/eaf3d_00341500.h5`, snapshot de paso completo con dt
      1e-3: 220/220 filas idénticas a base_340_n15) repite el lado limpio
      con el binario e5d331e.

    Es una relectura de datos registrados, no una prueba pre-registrada de
    C-044, y el contraste se hizo con el código de su fecha (con Plan K).
    Por la regla del grupo B, B3 sigue en fallida (no concluyente) porque
    el comando de C-044 no decide este inciso, no por falta de datos.
    > [fuente: campaigns/b1/{diag_k15b,diag_k15d,k1pa_340_n15}/audit.csv, campaigns/b1/diag_p417, campaigns/b1/base_340_n15 | python3 -c "import csv;L=lambda d:{int(r['step']):r for r in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv'),skipinitialspace=True)};o=L('k1pa_340_n15');[print(d,sum(a[s]==o[s] for s in range(345151,345331)),a[345151]['p_max'],sum(float(a[s]['p_max'])>3e5 for s in range(345151,345331))) for d in ('diag_k15b','diag_k15d') for a in [L(d)]]" (diag_k15b 0 2.98e5 0; diag_k15d 180 3.81e4 62); grep -E 'restart_file|t_final' campaigns/b1/diag_k15[bd]/config.dat; python3 scripts/research/ledger.py show C-043; ... show C-046; validez de C-087: python3 -c "import csv;L=lambda d:{r['step']:r for r in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv'),skipinitialspace=True)};a=L('diag_p417');b=L('base_340_n15');k=[x for x in a if 341501<=int(x)<=341720];print(len(k),sum(a[x]==b[x] for x in k))" (220 220)]
  - La ruta sigue en el código actual. En `src/main_3d.f90:335-340` se da el
    paso corto final si `t_final − time > 1e-6·dt_step`: un hueco de 1.25e-9
    s con dt de 1 ms supera 1e-9.
  - Lo mitiga un t_final con la forma x.xxx999999 (así lo hace C-090).
  - Errata de C-044: la penúltima fila de diag_k15a da 3.84e4, no 2.7e4; el
    2.62e4 corresponde al paso 345148.
  > [fuente: campaigns/b1/{diag_k15a,dense_340_n15,judge_e1_n14,judge_d26k_n14}/audit.csv | python3 -c "import csv; [print(d,[(x['step'],float(x['dt']),float(x['p_max'])) for x in list(csv.DictReader(open('campaigns/b1/'+d+'/audit.csv'),skipinitialspace=True))[-2:]]) for d in ['diag_k15a','dense_340_n15','judge_e1_n14','judge_d26k_n14']]"; sed -n 335,341p src/main_3d.f90]
- **C-047.** Comparé p_max de `audit.csv` con max|p| de `fields/pressure` en
  cada snapshot del mismo paso, con 0 diferencias en todas las corridas:

  | Corrida | Snapshots comparados |
  |---|---|
  | diag_k15d (la corrida de C-047) | 181 |
  | diag_k15b | 181 |
  | dense_340_n15 | 12 |
  | judge_e1_n15 | 12 |
  | judge_otp_280 | 7 |
  | k10_mo20 | 2 |

  - En diag_k15d, 345250: max p = 9.27e4, min p = −5.865e5 y audit =
    max|p| = 5.865e5.
  - En diag_k15d, 345280: max p = 2.564e5, min p = −3.279e5 y audit =
    3.279e5.
  - Las cifras 9.3e4 y 2.6e5 que C-047 da para el campo son el máximo CON
    SIGNO (9.27e4 y 2.564e5).
  - La cifra de audit que C-047 da para 345.28 s (2.6e5) también es errónea:
    `diag_k15d/audit.csv` da 3.279e5 en 345280 (3.491e5 en 345277 y 3.082e5
    en 345283). La de 345.25 s (5.9e5) es correcta (5.865e5).
  - Por construcción, en el código actual p_max = max|sh%p| sobre las celdas
    propias activas (`src/mod_audit.f90:704`). Se escribe en
    `src/main_3d.f90:836`, y el snapshot del mismo paso escribe el mismo
    `sh%p` (`main_3d.f90:900`, `mod_output_hdf5.f90:230`).
  - `.claude/rules/acople-pv.md:158` ya lo documentaba («p_max del audit es
    max|p|»).
  > [fuente: campaigns/b1/{diag_k15d,diag_k15b,dense_340_n15,judge_e1_n15,judge_otp_280,k10_mo20} | for d in diag_k15d diag_k15b dense_340_n15 judge_e1_n15 judge_otp_280 k10_mo20; do python3 -c "import sys,h5py,glob,csv,numpy as np;d='campaigns/b1/'+sys.argv[1];a={int(r['step']):float(r['p_max']) for r in csv.DictReader(open(d+'/audit.csv'),skipinitialspace=True)};fs=[f for f in glob.glob(d+'/eaf3d_*.h5') if int(f[-11:-3]) in a];print(sys.argv[1],len(fs),sum(np.abs(h5py.File(f,'r')['fields/pressure'][...]).max()!=a[int(f[-11:-3])] for f in fs))" $d; done]

**Eventos literales del grupo B:**

- **B1** — `--ws WS-K9 --ref C-198 --estado soportada --ruta research/ws/WS-K9/logs/coldnoE_binario_previo_check.txt --ruta research/ws/WS-K9/logs/test_full.txt --ruta tests/integration/configs/cold_flow_noenergy.dat --ruta src/mod_audit.f90 --ruta src/main_3d.f90 --cmd "grep -E 'mass_gas |mass_gas_flux_closure' research/ws/WS-K9/logs/coldnoE_binario_previo_check.txt; sed -n 2138,2175p research/ws/WS-K9/logs/test_full.txt | grep -E 'mass_gas |mass_gas_flux_closure'; git diff --stat 79dc27b 2b65e11 -- src; git show 2b65e11 -- src/mod_audit.f90 | grep gas_mass_on; grep -n gas_mass_on src/mod_audit.f90; sed -n 146,151p src/main_3d.f90"`
  > Cierre WS-K12 (panel): soportada por relectura de dos logs versionados de WS-K9 (no por un build de HEAD). Antes del arreglo (binario previo eaf3d_k8b_opt segun C-198; el log no registra el ejecutable), coldnoE_binario_previo_check.txt: FAIL mass_gas_flux_closure, max|resto| 3.41e-06, sum m_gas_out 0. Con el arreglo (test-full de WS-K9, test_full.txt lineas 2138-2175): PASS, max|resto| 1.69e-21, sum m_gas_out -7.1206e-6 kg, las cifras de C-198; el mass_gas de esos logs da dm_gas 7.0818e-6 frente a venteo 0 (antes) y 7.1206e-6 (despues). Causa en el codigo (lectura): git diff 79dc27b 2b65e11 -- src solo toca main_3d.f90 (+9) y mod_audit.f90 (+11/-2); 2b65e11 introduce gas_mass_on = solve_flow .and. solve_multiphase como condicion del acumulador de m_gas_out (hoy src/mod_audit.f90:884 y :934; :812 y :862 en 2b65e11), y src/main_3d.f90:149-150 imprime 'Ejecutable' (get_command_argument(0)) y 'Compilador' (compiler_version()) en run.log; ningun log versionado de WS-K9 contiene esas lineas, asi que esa parte se sostiene por el codigo, no por una salida. tests/out/cold_flow_noenergy_n4 no entra en este cierre: esta ignorado por git, lo sobrescribe make test-*, y su audit.csv actual es de un binario con el instrumento de 1de144e sin commitear (columnas m_gas_bx_*). Para regenerar: make test-full.
- **B2** — `--ws WS-K9 --ref C-199 --estado fallida --ruta research/ws/WS-K9/logs/test_full.txt --ruta tests/golden/metrics_v131.json --ruta tests/golden/metrics_v132.json --cmd "sed -n 5087,5149p research/ws/WS-K9/logs/test_full.txt | grep PASS | grep -c 'err rel 0.000e+00'; python3 -c \"import json; a=json.load(open('tests/golden/metrics_v131.json'))['runs']; b=json.load(open('tests/golden/metrics_v132.json'))['runs']; print(set(b)-set(a), [k for k in a if a[k]!=b[k]])\""`
  > Cierre WS-K12 (panel): fallida (no concluyente): la relectura no decide el enunciado literal. Verificado, como lectura: (1) test_full.txt de WS-K9 da 60 PASS con 'peor metrica err rel 0.000e+00' frente a metrics_v131 (lineas 5087-5149); (2) metrics_v132 = metrics_v131 mas el banco nuevo cold_flow_noenergy_n4, sin ninguna metrica comun distinta. La afirmacion central, 'celda a celda, 60 audit.csv identicos a los del test-full con el arreglo', NO se sostiene como se enuncio (C-200): se hizo contra la salida del rebaseline, y la procedencia de la base es una declaracion, no un dato. Lo verificado cubre las metricas del golden, no todas las columnas de audit.csv.
- **B3** — `--ws WS-K2 --ref C-044 --estado fallida --ruta campaigns/b1/diag_k15a --ruta campaigns/b1/dense_340_n15 --ruta campaigns/b1/judge_e1_n14 --ruta campaigns/b1/judge_d26k_n14 --ruta campaigns/b1/judge_c092_chain.sh --ruta campaigns/b1/diag_k15b --ruta campaigns/b1/diag_k15d --ruta campaigns/b1/k1pa_340_n15 --ruta src/main_3d.f90 --cmd "python3 -c \"import csv,glob;L=lambda f:list(csv.DictReader(open(f),skipinitialspace=True));T=[(f.split('/')[2],r[-2],r[-1]) for f in sorted(glob.glob('campaigns/b1/*/audit.csv')) for r in [L(f)] if len(r)>1 and float(r[-1]['dt'])<1e-6];print(len(T),sum(float(b['p_max'])>float(a['p_max']) for _,a,b in T));[print(d,a['step'],b['step'],b['dt'],a['p_max'],b['p_max']) for d,a,b in T]\"; grep -n e5d331e campaigns/b1/dense_340_n15/run.sh campaigns/b1/judge_c092_chain.sh; sed -n 335,341p src/main_3d.f90; python3 -c \"import csv;L=lambda d:{int(r['step']):r for r in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv'),skipinitialspace=True)};o=L('k1pa_340_n15');[print(d,sum(a[s]==o[s] for s in range(345151,345331)),a[345151]['p_max'],sum(float(a[s]['p_max'])>3e5 for s in range(345151,345331))) for d in ('diag_k15b','diag_k15d') for a in [L(d)]]\""`
  > Cierre WS-K12 (panel): fallida (no concluyente): el comando de C-044 decide solo una parte del enunciado. Verificado, como lectura: (1) la ultima fila de audit.csv es un paso truncado de dt 1.19e-9 a 1.27e-9 s en 22 corridas de campaigns/b1 y en 19 sube p_max (baja en diag_c060, 1.77e6 -> 9.98e5, y en f231_340, 2.19e5 -> 2.10e5; k1pa_340_n15 queda en el tope de 2e6). Ejemplos: diag_k15a 3.84e4 -> 2.46e5 (errata de C-044: la penultima es 3.84e4, no 2.7e4; 2.62e4 es la del paso 345148); con el binario e5d331e, posterior a las auditorias 3-21 (dense_340_n15/run.sh, judge_c092_chain.sh), dense_340_n15 5.75e4 -> 2.04e5, judge_e1_n14 2.75e4 -> 1.47e5 y judge_d26k_n14 1.86e4 -> 2.00e5. (2) La ruta sigue en el codigo actual (src/main_3d.f90:335-340: se da el paso corto si t_final - time > 1e-6 dt_step); lo mitiga un t_final con la forma x.xxx999999 (C-090). (3) El inciso 'contamina reinicios desde un t_final fuera de la malla de pasos' no lo decide el comando de C-044, pero el registro ya tiene el contraste directo y controlado en 345.15 s, de la misma sesion: C-043 (diag_k15a -> diag_k15b, reinicio desde el snapshot escrito tras el paso truncado) y C-046 (diag_k15c -> diag_k15d, reinicio desde un snapshot de paso completo), mismo binario (el de k1pa_340_n15, con Plan K segun C-049), 15 ranks y config identica salvo restart_file, output_dir y t_final. Frente a k1pa_340_n15 en 345151-345330: diag_k15d 180/180 filas de audit.csv identicas y diag_k15b 0/180; primer paso tras reiniciar p_max 2.98e5 (k15b) frente a 3.81e4 (k15d); filas con p_max > 3e5: k15b 0 y k15d 62 (tope de 2e6 en 345318, como la original). La contaminacion no dura dos pasos: cambia la trayectoria y suprime el estallido de 345.3 s. Es relectura de datos registrados, no prueba pre-registrada de C-044, y con el codigo de su fecha. Afecta a cifras ya registradas: C-093 (picos de d26k_n14 y e1_n14; precision P1).
- **B4** — `--ws WS-K2 --ref C-047 --estado refutada --ruta campaigns/b1/diag_k15d --cmd "for d in diag_k15d diag_k15b dense_340_n15 judge_e1_n15 judge_otp_280 k10_mo20; do python3 -c \"import sys,h5py,glob,csv,numpy as np;d='campaigns/b1/'+sys.argv[1];a={int(r['step']):float(r['p_max']) for r in csv.DictReader(open(d+'/audit.csv'),skipinitialspace=True)};fs=[f for f in glob.glob(d+'/eaf3d_*.h5') if int(f[-11:-3]) in a];print(sys.argv[1],len(fs),sum(abs(np.abs(h5py.File(f,'r')['fields/pressure'][...]).max()-a[int(f[-11:-3])])>0 for f in fs))\" \$d; done; python3 -c \"import csv;[print(r['step'],r['p_max']) for r in csv.DictReader(open('campaigns/b1/diag_k15d/audit.csv'),skipinitialspace=True) if int(r['step']) in (345250,345277,345280,345283)]\""`
  > Cierre WS-K12 (panel): refutada por relectura con su propio comando de evidencia. p_max de audit.csv es igual a max|p| de fields/pressure en el mismo paso en 395/395 snapshots, con 0 diferencias: diag_k15d 181 (la corrida de C-047), diag_k15b 181, dense_340_n15 12, judge_e1_n15 12, judge_otp_280 7 y k10_mo20 2. Las cifras 9.3e4 y 2.6e5 que C-047 da para el campo son el maximo CON SIGNO. En 345250, min p = -5.865e5 y max|p| = 5.865e5; en 345280, max p = 2.564e5, min p = -3.279e5 y max|p| = 3.279e5; en los dos pasos el audit marca max|p|. Errata adicional de C-047: la cifra de audit 2.6e5 en 345.28 s tambien es erronea; el audit da 3.279e5 en 345280 (3.491e5 en 345277 y 3.082e5 en 345283). Por construccion (src/mod_audit.f90:704; escrito en main_3d.f90:836; el snapshot escribe el mismo sh%p en main_3d.f90:900), el audit no puede superar el maximo del campo. Los criterios basados en p_max miden max|p| del campo.
- **B5** — `--ws WS-K7 --ref C-154 --estado fallida --ruta campaigns/b1/k7v5_mo20/audit.csv --ruta campaigns/b1/k7v5_base/audit.csv --ruta campaigns/b1/k7v5_mo20_1k/audit.csv --ruta campaigns/b1/k7v4_long/audit.csv --cmd "python3 -c \"import csv;L=lambda n:[x for x in csv.DictReader(open('campaigns/b1/%s/audit.csv'%n)) if int(x['step'])>280000];S=lambda r,c:sum(float(x[c]) for x in r);g=lambda r:(S(r,'m_gas_err_rem_abs')-S(r,'m_gas_err_abs_nogas'))/(S(r,'m_gas_err_abs_multi')-S(r,'m_gas_err_abs_nogas'));n=lambda r:(S(r,'m_gas_err_rem_abs_all')-S(r,'m_gas_err_rem_abs')+S(r,'m_gas_err_abs_nogas'))/S(r,'m_gas_err_abs_nogas');[print(k,g(L(k)),n(L(k))) for k in ('k7v5_mo20','k7v5_base')];a=L('k7v5_mo20_1k');b=L('k7v4_long');print([round(g(a[i:i+200]),3) for i in range(0,999,200)],[round(g(b[i:i+500]),3) for i in range(0,5499,500)])\""`
  > Cierre WS-K12 (panel): fallida (no concluyente): su comando reproduce las cifras, pero no decide la interpretacion. Cifras verificadas hoy con su propio comando, como lectura: el 0.319 de C-145 es la media ponderada de 0.384 en las celdas multifase con gas y 0.163 en las nogas (k7v5_mo20); en k7v5_base, 0.491 y 0.165; en el subconjunto con gas el cociente deriva 0.380 -> 0.426 por tramos de 200 pasos en k7v5_mo20_1k y en k7v4_long, por tramos de 500, de 0.521 a un maximo de 0.682 (serie no monotona: 0.521, 0.56, 0.581, 0.531, 0.532, 0.618, 0.634, 0.637, 0.663, 0.682, 0.639; ultimo tramo 0.639), como lo dice C-154. Comprobacion: (5.211e-3 - 7.85e-4)/(1.6356e-2 - 4.816e-3) = 0.384 y 7.85e-4/4.816e-3 = 0.163. La interpretacion (en las nogas la coincidencia es la identidad de fila del Poisson; el inciso por celda mide el peso de dos terminos de una descomposicion exacta y no contrasta H con su alternativa) queda como lectura, coherente con C-180 para H8. El veredicto formal de C-145 (sin decidir) no cambia y se cierra en E5.

## Grupo C — diagnósticos del Plan K (WS-K2), que no se adoptó

Plan K no está en `src/`: `pc_alpha_implicit` no aparece en ningún módulo, y
el código quedó archivado sin commit en `research/ws/WS-K1/plan_k_v2.patch`
(C-065 a C-073).
> [fuente: grep -l pc_alpha_implicit src/*.f90 (vacío); ls research/ws/WS-K1/plan_k_v2.patch]

| Afirmación | Cierre propuesto |
|---|---|
| C-015 | **fallida** (cerrada sin verificar), con lecturas |
| C-050 y C-056 (brazo con Plan K) | **fallida** (cerrada sin verificar) |
| C-051 y C-064 (también sin Plan K) | **fallida** (cerrada sin verificar), con texto propio |

Lecturas para C-015 (ninguna tiene valor de veredicto):

- **El pico de 805 kPa sale justo después de un reinicio.** Está en
  `diag_p342b`, paso 342451, el primero tras reiniciar desde
  `diag_p342a/eaf3d_00342450.h5`. Ese snapshot se escribió después de un
  paso truncado (dt 1.19e-9; p_max 2.78e4 → 9.52e4).
  - Celda del pico: [k,j,i] (2,51,8), líquido puro (alpha_s = alpha_g = 0).
    Es una presión NEGATIVA: p = −8.045e5 Pa (max|p|; el máximo con signo
    del campo es 3.19e4), como establece B4 para p_max.
  - Cae a 164 kPa y luego a 85 kPa en dos pasos.
  - En las corridas continuas no aparece. Máximo en 342.451–342.530 s:
    judge_otp_280 91 kPa, base_340_n14 81 kPa y base_340_n15 131 kPa.
  - Contraste directo de C-043/C-046 (ver B3): reiniciar desde un snapshot
    escrito tras un paso truncado cambia la trayectoria (0/180 filas
    idénticas a la original) y desde uno de paso completo no (180/180); la
    validez de C-087 (220/220) repite el lado limpio con el binario e5d331e. `diag_p342a` es
    idéntica a `judge_otp_280` en 340001–342449 y solo difiere en la fila del
    reinicio, 340000 (43 columnas de acumuladores, de energía y de masa:
    m_melted, m_resolid, m_gas_out, m_gas_volfix, m_C_oxid, entre otras), y
    en la del paso truncado 342450.
  - Lectura: el pico de C-015 es muy probablemente la contaminación del
    reinicio que describe C-044 y que contrastan C-043/C-046; el caso
    p342a → p342b no tiene su propio control en 342.450 s.
  > [fuente: campaigns/b1/diag_p342b, campaigns/b1/diag_p342a | grep restart_file campaigns/b1/diag_p342b/config.dat; tail -2 campaigns/b1/diag_p342a/audit.csv (dt, p_max); primeras filas de diag_p342b/audit.csv; argmax de |fields/pressure|, su valor con signo (−8.045e5) y alpha_solid/alpha_gas en diag_p342b/eaf3d_00342451.h5; filas distintas entre diag_p342a y judge_otp_280 (340000 y 342450); max p_max de 342451 a 342530 en judge_otp_280, base_340_n14 y base_340_n15]
- **Datos en la dirección de su `refuta_si`, para otro pico.** En
  dense_340_n14, el evento 342535 (6.36e5) está en (1,59,9), la celda de
  lecho del punto caliente (`c077.out`). Además,
  `.claude/rules/acople-pv.md:580-586` describe, a 342.5 s, celdas de lecho
  k = 1 con α_g en el piso que ciclan en 2 pasos.
- Se retira la lectura de C-076 sobre diag_p342b: esa trayectoria sale de
  un reinicio contaminado y su evento 342451 es el propio artefacto del
  reinicio, así que no aporta nada sobre el precursor.

**Eventos literales del grupo C:**

- **C1** — `--ws WS-K2 --ref C-015 --estado fallida`
  > Cierre WS-K12 (panel): fallida (cerrada sin verificar); el pico esta fuera de alcance (research/QUESTION.md) y su refuta_si no se probo con una prediccion. Lecturas sin valor de veredicto. (1) El pico de 805 kPa es el paso 342451 de diag_p342b, el PRIMERO tras reiniciar desde diag_p342a/eaf3d_00342450.h5, escrito tras un paso truncado (dt 1.19e-9, p_max 2.78e4 -> 9.52e4; C-044). Es p = -8.05e5 Pa en [k,j,i] (2,51,8) (max|p|, presion NEGATIVA; el maximo con signo del campo es 3.19e4), una celda de liquido puro (alpha_s = alpha_g = 0), y max|p| cae a 164 y 85 kPa en dos pasos. Las corridas continuas no lo tienen: en 342.451-342.530 s el maximo es 91 kPa en judge_otp_280 (identica a diag_p342a en 340001-342449), 81 kPa en base_340_n14 y 131 kPa en base_340_n15. Contraste directo ya registrado en 345.15 s (C-043/C-046, ver el cierre de C-044): reiniciar desde un snapshot escrito tras un paso truncado da 0/180 filas identicas a la original, y desde uno de paso completo 180/180. Es muy probablemente contaminacion del reinicio. (2) En la direccion de su refuta_si, pero para otro pico: el evento 342535 de dense_340_n14 (6.36e5) esta en la celda de lecho del punto caliente (1,59,9) (c077.out), y acople-pv.md:580-586 describe a 342.5 s celdas de lecho k=1 con alpha_g en el piso que ciclan en 2 pasos. La lectura de C-076 sobre diag_p342b no se usa: sale de una trayectoria contaminada y su evento 342451 es el artefacto del reinicio.
- **C2** — `--ws WS-K2 --ref <C-050 | C-056> --estado fallida`, uno por afirmación
  > Cierre WS-K12 (panel): fallida (cerrada sin verificar). Lectura de sonda de un solo evento (345.3 s) en el brazo CON Plan K v2, sin prueba pre-registrada, que ningun panel reviso; Plan K no se adopto (C-065..C-073).
- **C3** — `--ws WS-K2 --ref C-051 --estado fallida`
  > Cierre WS-K12 (panel): fallida (cerrada sin verificar). Lectura de sonda de un solo evento (345.3 s, celda (9,1,2)) que incluye el brazo SIN Plan K (diag_k15_k_off/run.log, PROBE-MOM). Ese brazo no es un control limpio del codigo base de su fecha: arranca de diag_k15d/eaf3d_00345310.h5, un estado de Plan K, y el campo toca el tope (min p = -2.0e6 Pa) en el primer paso tras el reinicio (precision P2 sobre C-049). No tiene prueba pre-registrada y ningun panel la reviso. Que Plan K no se adoptara no es el motivo del cierre. La generalizacion de la velocidad fantasma como precursor de los picos del codigo base la probaron C-075 (no concluyente, C-076) y C-077 (refutada en la letra, C-078: precursor 61.3 % < 70 %, control 9.2 %).
- **C4** — `--ws WS-K2 --ref C-064 --estado fallida`
  > Cierre WS-K12 (panel): fallida (cerrada sin verificar). Diagnostico de un solo evento (345.3 s) que afirma el mecanismo con y sin Plan K (diag_c058/eaf3d_00345317.h5, diag_k15_k_off/run.log); el brazo sin Plan K arranca de un estado de Plan K (diag_k15d/eaf3d_00345310.h5) y el campo toca el tope (min p = -2.0e6 Pa) en el primer paso tras el reinicio, asi que no es un control limpio (precision P2 sobre C-049). No tiene prueba pre-registrada propia y ningun panel lo reviso. Que Plan K no se adoptara no es el motivo del cierre. Su generalizacion al codigo base la probaron C-075 (no concluyente, C-076) y C-077 (refutada en la letra, C-078: precursor 61.3 % < 70 %, control 9.2 %); la ubicacion del punto caliente la decidieron C-083/C-084.

## Grupo D — prueba propuesta y nunca corrida

- **D1** — `--ws WS-K3 --ref C-088 --estado fallida`
  > Cierre WS-K12 (panel): fallida (cerrada sin verificar). Su refuta_si (mantener el gas en la fila todo el paso en 341705) no se corrio. Es una observacion posterior sin valor de prueba, segun su propio texto; queda citada como lectura en el cierre de C-085.

## Grupo E — «sin decidir» por la letra: cierre `sin_decidir` (decisión del usuario)

| Afirmación | Veredicto vigente | Cifras |
|---|---|---|
| C-121 [WS-K7] | C-123 en_disputa (sobre la enmienda C-122) | Por la letra, con las columnas de C-123: por celda 0.270, neto 3.135. C-124 declaró defectuoso el inciso por celda (conjuntos distintos) y retiró el 0.270. Con la definición de C-122 el cociente por celda NO se midió: queda acotado en [0.565, 0.635], dentro de la banda 0.3–0.7, con cotas que dependen de cifras de C-123 que C-128 declara no reproducibles (ver nota). El 0.566 de hoy en `k7_mo20/audit.csv` es el de C-126/C-127 (otro instrumento, alpha_g > 0 sin umbral) y no es el valor de C-121 |
| C-126 [WS-K7] | C-127 en_disputa | 0.566 (entre 0.3 y 0.7); neto 2.456 |
| C-130 [WS-K7] | C-131 en_disputa | 0.319; neto 1.582 |
| C-135 [WS-K7] | C-139 en_disputa | 0.319; neto 1.582; corr(err_liq_all, e) = +0.229 |
| C-144 [WS-K7] | C-145 en_disputa | 0.319; neto 1.571 |
| C-170 [WS-K8] | C-174 en_disputa (sobre la enmienda C-172) | 0.3156; neto 1.571 |
| C-202 [WS-K10] | C-204 en_disputa (sobre la enmienda C-203) | Br/e = −0.683 y −0.135 (fuera de [0.5, 1.5]); Br(0.5)/Br(1) = 0.184 (fuera de [0.35, 0.65]) |
| C-212 [WS-K10] | C-213 en_disputa | r(0.25)/r(0.5) = 0.812, entre 0.75 y 0.90 |
| C-110 [WS-K3] (resultado) | C-168 (WS-K7) y C-175 (WS-K8), resultados en_disputa | Ver abajo |
| C-168 [WS-K7] (resultado) | en_disputa propio | Registra sobre C-110 el veredicto SIN DECIDIR de C-145; sin criterio propio (ver Incertidumbre). C-154 pasó al grupo B (B5) |

> [fuente: campaigns/b1/k7_mo20/audit.csv, campaigns/b1/k8_cg1000/audit.csv | python3 -c "import csv;r=[x for x in csv.DictReader(open('campaigns/b1/k7_mo20/audit.csv'),skipinitialspace=True) if int(x['step'])>280000];S=lambda c:sum(float(x[c]) for x in r);print(len(r),S('m_gas_err_rem_abs')/S('m_gas_err_abs_multi'),abs(S('m_gas_err_multi')-S('m_gas_err_liq'))/abs(S('m_gas_err_multi')))" (59 0.5660 2.456); ídem k8_cg1000 con _all (0.3156 1.571); ls -l campaigns/b1/k7_mo20/audit.csv (24-oct 20:02); python3 scripts/research/ledger.py show C-124]

Notas por afirmación:

- **C-121.** Con la definición de C-122 (err_liq = 0 fuera de las celdas con
  alpha_g ≥ ALPHA_FLOW_CUTOFF = 1e-2), rem = sum|e − err_liq| sobre las
  multifase se parte en tres conjuntos disjuntos:
  - las filtradas: 4.420e-3 kg, la columna de C-123;
  - las nogas con alpha_g = 0 en los dos extremos: |e| = 4.816e-3 kg (C-127);
  - las de 0 < alpha_g < 1e-2: |e| sin columna propia.

  Cota inferior: rem/sum|e| ≥ (4.420e-3 + 4.816e-3)/1.6356e-2 = 0.565.

  Cota superior, con la desigualdad triangular de C-124 aplicada al tercer
  conjunto (|e| ≤ |e − err_liq| + |rho_g V_pois| + |rho_g V_eff| por celda,
  con el err_liq del instrumento de C-126, que sí se evalúa ahí). Cada
  término del tercer conjunto es la columna actual de k7_mo20 (instrumento
  de C-126, alpha_g > 0 sin umbral) menos la de C-123 (filtro 1e-2):
  - |e − err_liq|: (9.2565e-3 − 4.8164e-3) − 4.420e-3 = 2.0e-5 kg;
  - |rho_g V_pois|: 8.7989e-3 − 7.82e-3 = 9.79e-4 kg;
  - |rho_g V_eff|: 2.2752e-3 − 2.13e-3 = 1.45e-4 kg;
  - suma: |e| ≤ 1.14e-3 kg en el tercer conjunto, por debajo de los
    2.21e-3 kg que harían falta para llegar a 0.7.

  Cota superior: rem/sum|e| ≤ (4.420e-3 + 4.816e-3 + 1.144e-3)/1.6356e-2 =
  0.635. El cociente por celda queda en [0.565, 0.635]: el inciso por celda
  no se cumple (> 0.3) y la refutación (≥ 0.7) queda excluida, así que la
  etiqueta SIN DECIDIR sale de la letra de C-122, no solo de C-124.

  Límite de las dos cotas: ambas usan cifras de C-123 (4.420e-3, 7.82e-3,
  2.13e-3) que C-128 (soportada) declara NO reproducibles desde ningún
  archivo: el audit.csv de la primera corrida se sobrescribió. Que las
  columnas de las dos corridas sean restables supone que la trayectoria es
  la misma: las dos cumplieron P3 (p_max, m_gas, E_liq, E_gas y u_gas_max
  bit a bit iguales a sonda_gc_*; C-123 y C-127), que cubre esas cinco
  columnas y no cada celda. C-128 da un dato a favor: rem − nogas de hoy
  (4.440e-3) apenas supera el 4.420e-3 de C-123. La cota superior de C-124
  («no queda por debajo de 0.7») es anterior a las columnas de C-126; con
  ellas, la cota baja a 0.635.
  > [fuente: campaigns/b1/k7_mo20/audit.csv | python3 -c "import csv;r=[x for x in csv.DictReader(open('campaigns/b1/k7_mo20/audit.csv'),skipinitialspace=True) if int(x['step'])>280000];S=lambda c:sum(float(x[c]) for x in r);ea=S('m_gas_err_abs_multi');rem=S('m_gas_err_rem_abs');n=S('m_gas_err_abs_nogas');vp=S('m_gas_vpois_abs');ve=S('m_gas_veff_abs');t=(rem-n-4.420e-3)+(vp-7.82e-3)+(ve-2.13e-3);print(ea,rem,n,vp,ve,t,(4.420e-3+n)/ea,(4.420e-3+n+t)/ea)" (1.6356e-2 9.2565e-3 4.8164e-3 8.7989e-3 2.2752e-3 1.144e-3 0.5647 0.6347); python3 scripts/research/ledger.py show C-123 (4.420e-3, 7.82e-3, 2.13e-3); ... show C-128 (no reproducibles)]
- **C-110.** Esta versión retira la lectura de C-175 (2) («el complemento
  neto pesa 4.06e-5 frente a 8.55e-4, apunta en contra»), que C-176 RETIRÓ:
  «no es evidencia contra C-110». Lo registrado:
  - Por celda: todas las pruebas quedaron sin decidir (C-123, C-127, C-131,
    C-139, C-145, C-174). El inciso por celda no contrasta H con su
    alternativa: mide el peso de dos términos de una descomposición exacta
    (C-154, B5; C-180 para H8).
  - Parte NETA: la cláusula registrada de C-135 dio, por su letra, «H no lo
    explica» (corr(err_liq_all, e) = +0.229 < 0.3, signo opuesto en 59/59
    pasos; C-139, C-138). C-140 la retiró como inferencia de mecanismo y
    C-143 (soportada) aceptó la retirada: el umbral 0.3 se fijó conociendo el
    0.229 de C-134, así que esa parte de C-139 «queda sin valor de prueba».
  - C-151 (soportada): con 5 externas, al menos el 48 % del piso de
    k7v4_long no es complemento neto. C-152 (soportada) la RESTRINGE: retira
    «matiza el texto literal de C-110»; el ≥ 48 % es compatible con el lazo
    truncado de 5 externas y con el régimen de centinela, y con 20 externas
    (las de C-110) la cota no restringe.
  - C-120 (soportada): la alternativa «transporte por caras no enlazadas» es
    nula.
  - C-176: el origen del flujo neto es la entrada por las celdas de salida.
  - La identidad d m_gas = comp + eos + volfix queda medida.
- **C-202.** «Br tiene el signo contrario a e» es una LECTURA (C-208). El Br
  pre-registrado (Br1 + Br2) omitió Bgr: Br + Bgr = −1.69e-7 kg/paso (0.012
  e, 1 ms) y −1.8e-8 (≈ 0.001 e, 0.5 ms) (C-208), que caería en la zona del
  `refuta_si` (|Br| < 0.2 |e|); C-210 (4) advierte que esa cancelación es
  algebraica y condicionada a la contabilidad, y no prueba que la EOS final
  no importe. C-210 y C-211 corrigen la lectura de tasa. C-218 fija el
  prerrequisito y la etiqueta («sigue SIN DECIDIR y no fallida»). C-218 (27-oct 23:18) dio el PASS de
  mass_gas_decomp sobre k10_* por no reproducible con el checker de esa hora
  (FAIL de esquema: faltan las columnas m_gas_dec_scale_*) y lo sostuvo con
  k10b_* (C-209), cuyos restos y piezas son bit a bit los de k10_*. El
  `check_audit.py` versionado después en 1de144e (28-oct 01:05) tiene un modo
  para CSV sin esas columnas (`tests/integration/check_audit.py:535`) y hoy da
  PASS en los tres k10_*: mass_gas_decomp con restos multifase 2.91e-14 /
  5.81e-14 / 2.91e-14 kg y tolerancias 1.43e-11 / 1.46e-11 / 1.41e-11 kg
  (mo20 / dt05 / base), y mass_gas_row_volume PASS.
  > [fuente: for n in k10_mo20 k10_dt05 k10_base; do python3 tests/integration/check_audit.py campaigns/b1/$n | grep -E 'mass_gas_decomp|mass_gas_row_volume'; done; git log --format='%h %ci' -1 -- tests/integration/check_audit.py]

**Por qué no se cierran como fallida.** En los criterios de estas
predicciones, la banda intermedia se registra como «SIN DECIDIR» (C-121:
«se registra así»; C-172: «en otro caso SIN DECIDIR»; C-202: «Otro caso: sin
decidir»; C-212: «Otro caso: sin decidir»). «Fallida» queda reservado a los
prerrequisitos («si los hay: FALLIDA»; «si falla alguno, fallida»; «la prueba
es inválida»). El precedente de C-076 no aplica: allí el criterio de C-075
definía expresamente FALLIDA (no concluyente) con menos de 3 eventos.
Antes de este WS, `ledger.py` no tenía ningún estado cerrado que
significara «sin decidir» (en HEAD, CERRADOS = soportada, refutada, fallida;
`git show HEAD:scripts/research/ledger.py`, línea 28). El diff staged lo añade
(`scripts/research/ledger.py:32`; ver «Cambio de herramienta»).
Se RETIRA la propuesta anterior de cerrarlas como «fallida (no concluyente)».

**Decisión del usuario (28-oct-2026): estado cerrado `sin_decidir`.** Se
eligió esta opción frente a dejarlas en_disputa. Ningún veredicto se reetiqueta:
C-123, C-127, C-131, C-139, C-145, C-174, C-204 y C-213 siguen en_disputa. Lo
que se añade es un `resultado` de cierre por afirmación, con `--estado
sin_decidir` y `--ref` a la afirmación. Textos literales (todos con
`--tipo resultado --autor coordinador`):

- **E1** — `--ws WS-K7 --ref C-121 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (enmendado en C-122; veredicto C-123 en_disputa), con un instrumento declarado defectuoso. Con las columnas de C-123: por celda 0.270 y neto 3.135 > 0.3. C-124 (soportada) retiro el 0.270 (el instrumento sumaba conjuntos distintos) y dejo escrito 'sigue SIN DECIDIR por no cumplir ningun inciso y no refutarse'. Con la definicion de C-122 el cociente por celda NO se midio, pero queda acotado en [0.565, 0.635]: cota inferior (4.420e-3 + 4.816e-3)/1.6356e-2 (rem de las celdas filtradas de C-123 mas |e| de las nogas de C-127, sobre sum|e| multifase); cota superior con la desigualdad triangular de C-124 en las celdas con 0 < alpha_g < 1e-2, cuyos terminos son las columnas actuales de k7_mo20 (instrumento de C-126) menos las de C-123: |e - err_liq| 2.0e-5 + |rho V_pois| 9.79e-4 + |rho V_eff| 1.45e-4 = 1.14e-3 kg, por debajo de los 2.21e-3 kg que harian falta para llegar a 0.7. El inciso por celda no se cumple (> 0.3) y la refutacion (>= 0.7) queda excluida: SIN DECIDIR por la letra de C-122. Las dos cotas dependen de cifras de C-123 (4.420e-3, 7.82e-3, 2.13e-3) que C-128 declara no reproducibles, y de que las dos corridas sigan la misma trayectoria (ambas cumplieron P3, que cubre cinco columnas globales, no cada celda). El 0.566 de C-127 es de otro instrumento (C-126, alpha_g > 0 sin umbral) y no es el valor de C-121. No soportada ni refutada; la linea no sigue con este instrumento.
- **E2** — `--ws WS-K7 --ref C-126 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (veredicto C-127 en_disputa: por celda 0.566, entre 0.3 y 0.7; neto 2.456). No soportada ni refutada; la linea no sigue con este instrumento.
- **E3** — `--ws WS-K7 --ref C-130 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (veredicto C-131 en_disputa: por celda 0.319; neto 1.582). No soportada ni refutada; la linea no sigue con este instrumento.
- **E4** — `--ws WS-K7 --ref C-135 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (veredicto C-139 en_disputa: por celda 0.319; neto 1.582). Clausula registrada sobre el piso NETO: por su letra dio 'H no lo explica' (corr(err_liq_all, e) = +0.229 < 0.3, signo opuesto en 59/59 pasos; C-139, C-138), pero C-140 la retiro como inferencia de mecanismo y C-143 (soportada) acepto la retirada: el umbral 0.3 se fijo conociendo el 0.229 de C-134, asi que esa parte queda sin valor de prueba. No soportada ni refutada; la linea no sigue con este instrumento.
- **E5** — `--ws WS-K7 --ref C-144 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (veredicto C-145 en_disputa: por celda 0.319; neto 1.571). No soportada ni refutada; la linea no sigue con este instrumento.
- **E6** — `--ws WS-K8 --ref C-170 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (enmendado en C-172; veredicto C-174 en_disputa: por celda 0.3156 con el CG convergido; neto 1.571). No soportada ni refutada; la linea no sigue con este instrumento.
- **E7** — `--ws WS-K10 --ref C-202 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (enmendado en C-203; veredicto C-204 en_disputa: Br/e = -0.683 y -0.135, fuera de [0.5, 1.5]; Br(0.5)/Br(1) = 0.184, fuera de [0.35, 0.65]). Lectura de signo en C-208. El Br pre-registrado (Br1 + Br2) omitio Bgr: Br + Bgr = -1.69e-7 kg/paso (0.012 e, 1 ms) y -1.8e-8 (~0.001 e, 0.5 ms) (C-208), que caeria en la zona del refuta_si (|Br| < 0.2 |e|); C-210 (4): esa cancelacion es algebraica y condicionada a la contabilidad, y no prueba que la EOS final no importe. C-210/C-211 corrigen la lectura de tasa. Etiqueta fijada en C-218, que sostuvo el prerrequisito mass_gas_decomp con k10b_* (C-209), bit a bit iguales en restos y piezas, porque el checker de su hora daba FAIL de esquema en k10_*; el check_audit.py versionado en 1de144e da hoy PASS en k10_mo20, k10_dt05 y k10_base (restos 2.91e-14 / 5.81e-14 / 2.91e-14 kg, tolerancias 1.4e-11). No soportada ni refutada.
- **E8** — `--ws WS-K10 --ref C-212 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR por la letra de su criterio (veredicto C-213 en_disputa: r(0.25)/r(0.5) = 0.812, entre 0.75 y 0.90). No soportada ni refutada; la linea no sigue con este instrumento.
- **E9** — `--ws WS-K3 --ref C-110 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR. Por celda, todas las pruebas de esta hipotesis (C-121/C-122, C-126, C-130, C-135, C-144 en WS-K7; C-170/C-172 en WS-K8) quedaron sin decidir (C-168, C-175), y el inciso por celda no contrasta H con su alternativa: mide el peso de dos terminos de una descomposicion exacta (C-154; C-180 para H8). Parte NETA: la clausula registrada de C-135 dio por su letra 'H no lo explica' (corr +0.229 < 0.3, signo opuesto en 59/59; C-139/C-138), pero C-143 (soportada) la dejo sin valor de prueba (el umbral se fijo conociendo el 0.229). C-151 (al menos el 48 % del piso de k7v4_long no es complemento neto) apunta en contra con 5 externas, pero C-152 (soportada) retiro 'matiza el texto literal de C-110': es compatible con el lazo truncado y el regimen de centinela, y con 20 externas la cota no restringe. C-120 (soportada): la alternativa 'caras no enlazadas' es nula. C-176 retira la lectura de C-175 (2) como evidencia en contra. Queda medida la identidad d m_gas = comp + eos + volfix. La pregunta del error de masa del gas sigue en otra forma (error por paso de la meseta, C-197/C-211).
- **E11** — `--ws WS-K7 --ref C-168 --estado sin_decidir`
  > Cierre WS-K12 (panel): SIN DECIDIR. C-168 registra sobre C-110 el veredicto SIN DECIDIR de C-145 (por celda 0.319, neto 1.571), que se cierra en E5, y C-110 se cierra en E9; no tiene criterio propio. Sus incisos (2), (5) y (6) quedan como lecturas apoyadas en C-137/C-157, C-120 y mass_gas_rewrites; (3) en C-125 y (4) en C-152. No soportada ni refutada.

(C-154, antes E10, pasa al grupo B como B5.)

Comprobación previa del validador: un `resultado` con `--ref` y estado
`sin_decidir` se acepta; un veredicto, una hipótesis o un resultado sin
`--ref` con ese estado se rechazan. Se probó sobre un registro sintético en
el scratchpad (`RESEARCH_ROOT=<scratchpad>`), sin tocar `research/ledger.jsonl`.
> [fuente: RESEARCH_ROOT=$T python3 scripts/research/ledger.py add --tipo veredicto --ref C-001 --estado sin_decidir ... (RECHAZADO); --tipo resultado sin --ref (RECHAZADO); --tipo hipotesis --ref C-001 (RECHAZADO); --tipo resultado --ref C-001 (C-003, y `open` pasa de 1 a 0 abiertas)]

## Cambio de herramienta (decisión del usuario, grupo E)

`scripts/research/ledger.py`:
- `sin_decidir` se añade a ESTADOS y a CERRADOS (`:28-32`).
- Los veredictos conservan sus cuatro estados en `ESTADOS_VEREDICTO` (`:33`),
  sin `sin_decidir`: la banda intermedia de un criterio se sigue registrando
  como en_disputa en el veredicto.
- `validate` (`:114-122`) acepta `sin_decidir` solo en un `resultado` cuya
  `--ref` cumpla tres condiciones: que exista, que no sea un veredicto ni una
  enmienda, y que no esté ya cerrada (`current_state` fuera de CERRADOS).
  Esto resuelve B1 del auditor (ronda con `sin_decidir`) solo en parte: una
  ref mal tecleada a una afirmación cerrada por un evento con `ref` directa
  ya no se acepta. Límite: `current_state` no sigue enmiendas ni hijas, así
  que `validate` todavía acepta `sin_decidir` sobre una predicción juzgada a
  través de su enmienda. Probado en memoria, sin escribir: C-169 (refutada
  vía C-171 → C-173) y C-194 (soportada vía C-195 → C-196) tienen
  `current_state` «enmendada» y pasan la validación de `sin_decidir`.
  > [fuente: python3 -c "import sys; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); [print(r, L.current_state(r,ev), L.validate({'id':'C-999','ts':'9','tipo':'resultado','ws':'X','enunciado':'x','autor':'a','estado':'sin_decidir','ref':r},ev)) for r in ('C-169','C-194')]" (enmendada [] en las dos)]
- `open` (`:207-209`) lista las cerradas `sin_decidir` («cerradas sin
  decidir: N: refs»), también las no raíz. Esto resuelve B4 del auditor.

`research/README.md` documenta el estado y su alcance, y añade cómo se
consultan las cerradas `sin_decidir` (`open`, `show`). La definición se amplió
por decisión del coordinador (R6 del refutador): `sin_decidir` cierra también
«un resultado que solo registra ese "sin decidir" de otra predicción», que es
el caso de C-168 (E11).

Comprobaciones sobre un registro sintético en el scratchpad
(`RESEARCH_ROOT=<scratchpad>`), sin tocar `research/ledger.jsonl`:
- se rechazan las refs a un id inexistente (C-999), a un veredicto (C-002) y a
  una predicción refutada (C-003);
- se rechaza un veredicto con `sin_decidir`;
- se acepta un `resultado` con ref a una predicción en_disputa;
- se rechaza repetir ese cierre («ya esta cerrada (sin_decidir)»);
- `open` imprime «cerradas sin decidir: 1: C-001».

Ninguna de las 10 refs del grupo E está cerrada hoy. Su estado vigente es
`en_disputa`, `enmendada` o `pre-registrada`.
> [fuente: python3 -c "import sys; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); [print(c, L.current_state(c,ev)) for c in 'C-110 C-121 C-126 C-130 C-135 C-144 C-168 C-170 C-202 C-212'.split()]"]

`ledger.py check` sigue en OK con los 278 eventos actuales, y ningún evento
existente usa el estado.

## Dónde quedan los pendientes tras el cierre

Simulado EN MEMORIA, sin escribir en `research/ledger.jsonl` ni en ningún
otro archivo: el comando de abajo lee los eventos literales de este reporte
(línea `- **Xn** — \`--ws ...\`` más la línea `  > texto`), separa sus
argumentos con zsh, como lo hará el coordinador, y pasa cada evento por
`ledger.validate` (más la comprobación de rutas de `soportada`) sobre el
registro actual. Resultado de hoy: 31 eventos (C-279 a C-309; C2 son dos),
todos aceptados, y **0 abiertas de 64**. Con `--run` ejecuta además los
`--cmd` de A1, A2, A4, A5, A6, B1–B5, P1 y P2 con zsh desde la raíz del
repo: todos terminan con código 0 y reproducen las cifras del texto. La
versión anterior citaba un script en el scratchpad de otra sesión, que no
es reproducible desde el repositorio; se sustituye por este, que va
completo aquí.

```
python3 - --run <<'EOF'
import re, sys, os, subprocess
sys.path.insert(0, 'scripts/research'); import ledger as L
ev = L.load(); n0 = len(ev); cmds = []
txt = open('research/ws/WS-K12/report.md').read().split('\n')
for i, l in enumerate(txt):
    m = re.match(r'^- \*\*([A-Z]\d+)\*\* — `(--ws .*)`', l)
    if not m or not txt[i+1].startswith('  > '):
        continue
    g = m.group(2); multi = re.search(r'--ref <([^>]*)>', g)
    a = subprocess.run(['zsh', '-c', "printf '%s\\0' " + re.sub(r'--ref <[^>]*>', '--ref MULTI', g)],
                       capture_output=True, text=True).stdout.split('\0')[:-1]; o = {'ruta': []}
    for k, v in zip(a[::2], a[1::2]):
        o.setdefault(k[2:], []).append(v) if k == '--ruta' else o.__setitem__(k[2:], v)
    refs = re.findall(r'C-\d+', multi.group(1)) if multi else [o['ref']]
    for r in refs:
        e = {'id': L.next_id(ev), 'ts': '9999', 'tipo': 'resultado', 'ws': o['ws'], 'ref': r,
             'enunciado': txt[i+1][4:], 'autor': 'coordinador', 'estado': o['estado']}
        if o['ruta'] or o.get('cmd'):
            e['evidencia'] = {'rutas': o['ruta'], 'cmd': o.get('cmd', '')}
        err = L.validate(e, ev) + [f'ruta inexistente: {p}' for p in o['ruta'] if not os.path.exists(p)]
        print(m.group(1), e['id'], r, e['estado'], 'ACEPTADO' if not err else 'RECHAZADO: ' + '; '.join(err))
        ev.append(e)
        if o.get('cmd'): cmds.append((m.group(1), o['cmd']))
raices = [x for x in ev if not x.get('ref')]
print('eventos nuevos', len(ev) - n0, '; abiertas', sum(L.current_state(x['id'], ev) not in L.CERRADOS for x in raices), 'de', len(raices))
for k, c in dict(cmds).items() if '--run' in sys.argv else []:
    p = subprocess.run(['zsh', '-c', c], capture_output=True, text=True)
    print('cmd', k, 'exit', p.returncode, '|', p.stdout.strip().replace('\n', ' / ')[:300], p.stderr.strip()[:200])
EOF
```

Lo que deja de verse en `open` y sigue pendiente:
- **Cerradas con `sin_decidir`** (no aparecen en `open`): C-110, C-121, C-126,
  C-130, C-135, C-144, C-168, C-170, C-202 y C-212.
- **Centinelas sin diagnosticar de WS-K11**: las excursiones de
  k11_dt025_s290 (C-237 (c)) y la U_GAS_MAX del brazo L (C-261). Quedan en
  los cierres F1 (fallida, no concluyente) y F2 (fallida, cerrada sin
  verificar), y en C-277 (4).
- **Error de masa del gas por paso de la meseta**: C-197 y C-211 (resultados
  no raíz en «propuesta»); su predicción C-202 queda sin decidir (E7) y la
  pieza siguiente no está pre-registrada.
- **Pendientes que los propios eventos dejaron al coordinador**: columna de
  |e| para 0 < alpha_g < 1e-2 (C-124; ya no hace falta para la etiqueta de
  E1, sí para el valor exacto), comp y eos por conjunto en ventana
  ≥ 1000 pasos con 20 externas (C-152), el refuta_si de C-088 (D1) y la
  separación material/atributos del electrodo (C-082, A4).

## Grupo F — hipótesis de WS-K11 sin experimento

- **F1** — `--ws WS-K11 --ref C-237 --estado fallida`
  > Cierre WS-K12 (panel): fallida (no concluyente): su prediccion hija prueba solo una parte. Era una lista de pendientes. (a) La respondio C-238 (veredicto C-239, soportada): el pico de los pasos 2-3 lo causa el cambio de claves, no el estado ni el escritor del snapshot de 280 s. (b) El transitorio largo o el regimen alto con 0.25 ms desde 280 s, (c) las excursiones de k11_dt025_s290 (344 kPa en 290074 y 450 kPa en 290093) y (d) las replicas a 14 ranks no tienen prueba pre-registrada. C-277 (4) deja (c) como centinela sin diagnosticar al cierre de WS-K11.
- **F2** — `--ws WS-K11 --ref C-261 --estado fallida`
  > Cierre WS-K12 (panel): fallida (cerrada sin verificar). La centinela U_GAS_MAX del brazo L (k11_l_dt025_jb295: 300 m/s en 295002) no se diagnostico: la sonda PROBE-P propuesta no se corrio. C-277 (4) la deja como centinela sin diagnosticar al cierre de WS-K11.

## Precisión propuesta (sin valor de veredicto)

- **P1** — `--ws WS-K3 --ref C-093 --estado propuesta --ruta campaigns/b1/judge_d26k_n14 --ruta campaigns/b1/judge_e1_n14 --cmd "python3 -c \"import csv;L=lambda d:list(csv.DictReader(open('campaigns/b1/'+d+'/audit.csv'),skipinitialspace=True));[print(d,r[-1]['step'],r[-1]['dt'],max(float(x['p_max']) for x in r),max(float(x['p_max']) for x in r[:-1])) for d in ('judge_d26k_n14','judge_e1_n14','judge_d26k_n15','judge_e1_n15') for r in [L(d)]]\""`
  > PRECISA C-093 (WS-K12): el pico de d26k_n14 (2.001e5) y el de e1_n14 (1.474e5) son la fila del paso final truncado 345500 (dt 1.258e-9, C-044); sin ella son 1.240e5 y 1.455e5. El de d26k_n15 (2.011e5) y el de e1_n15 (1.853e5) no lo son. El veredicto no cambia: falla por el inciso (d).

- **P2** — `--ws WS-K2 --ref C-049 --estado propuesta --ruta campaigns/b1/diag_k15_k_off --cmd "grep -E 'restart_file|pc_alpha_implicit' campaigns/b1/diag_k15_k_off/config.dat; python3 -c \"import h5py,glob,csv,numpy as np;d='campaigns/b1/diag_k15_k_off';a={int(r['step']):float(r['p_max']) for r in csv.DictReader(open(d+'/audit.csv'),skipinitialspace=True)};[print(int(f[-11:-3]),p.max(),p.min(),np.unravel_index(np.argmin(p),p.shape),np.abs(p).max(),a.get(int(f[-11:-3]))) for f in sorted(glob.glob(d+'/eaf3d_*.h5')) for p in [h5py.File(f,'r')['fields/pressure'][...]]]\""`
  > PRECISA C-049 (WS-K12): el 'max de p del campo = 6.07e5 (< 1e6)' del brazo sin Plan K (diag_k15_k_off) es el maximo CON SIGNO, la misma lectura que B4 refuta en C-047; los criterios basados en p_max miden max|p|. En ese brazo el campo tiene p = -2.0e6 Pa desde el primer paso tras el reinicio: en 345311, max p = 4.56e5, min p = -2.0e6 en los indices numpy [k,j,i] (1,56,8) y audit p_max = 2.0e6; en 345318, max p = 6.07e5 (la cifra de C-049) y max|p| = 1.85e6. El brazo arranca de diag_k15d/eaf3d_00345310.h5, un estado de Plan K (max|p| 1.55e5), y toca el tope en el primer paso, asi que no es un control limpio del codigo base. Lo que C-049 mide en la celda (9,1,2) no se revisa aqui. 'Plan K es NECESARIO para el salto' queda restringido a esa celda: sin Plan K el campo tambien llega al tope, en otra celda y desde el primer paso.

## Fuera de este cierre

- Los 90 eventos no raíz excluidos (ver «Alcance»).
- Los workstreams WS-K1, WS-K2 y WS-K3 siguen abiertos (ronda 0). Este
  cierre no los cierra: es el punto 1 de la lista de pendientes. Los
  veredictos de WS-K2 y WS-K3 que este cierre cita (C-061, C-078, C-081,
  C-084, C-087 y C-091) nunca pasaron por un panel, y este es su primer
  examen. Solo C-078 (a C-074) y C-084 (a C-082) se propagan a la madre; los
  demás quedan como no concluyentes para ella (A1, A3, A5, A6).
- El único cambio de `scripts/research/ledger.py` es el estado `sin_decidir`
  con su validación de la `ref` (`:114-122`) y su listado en `open`
  (`:207-209`), los dos en el diff staged (ver «Cambio de herramienta»).
  Queda como pendiente del coordinador la limitación de `current_state`: no
  sigue enmiendas ni hijas. Por eso `validate` todavía acepta `sin_decidir`
  sobre C-169 y C-194, ya juzgadas a través de su enmienda.

## Incertidumbre

- **C-057, C-079 y C-085** (no concluyentes): la hija probó otra cosa o su
  cláusula de refutación no se observó.
  - C-057: la sonda registra candidatas, no fijación ni signo; por el
    código, con la celda saltada solo pueden ser candidatas sus salidas.
  - C-079: n15 añade la celda (1,58,8), no listada en C-079; si eso cumple
    su `refuta_si` depende de leer «celdas distintas» como celda o esquina.
  - C-085: la cuota del líquido es 0.785 en la 1.ª externa de 341705 (en su
    dirección) y 1.0 en las externas 2 a 5 (confundida por act_g=F); la
    prueba que separa las lecturas es el `refuta_si` de C-088, no corrido.
- **C-074**: se cierra «refutada en la letra» de C-077 aunque su propio
  `refuta_si` no se cumple (precursor del 61–81 % frente a un control del
  9–10 %); la discrepancia está escrita en el evento.
- **C-082**: el giro movió juntos el material y los atributos de los
  electrodos (z_tip, su única asimetría), así que la prueba no los separa.
  Dato parcial en contra de z_tip: el punto caliente original está bajo el
  electrodo de z_tip intermedio (1.628), no bajo el más bajo (1.613). La
  descomposición MPI sí queda excluida (rejilla 1x5x3; el punto girado,
  j 19-20, cae dentro del bloque j 12-23).
- **C-089**: no hay ningún juez de E1 con el código actual en la ventana del
  fracaso viejo (320–325 s).
- **C-015 y C-044 (contaminación del reinicio)**: el contraste directo y
  controlado ya está en el registro (C-043/C-046, 345.15 s: 0/180 frente a
  180/180 filas idénticas a la original; ver B3). Límites: es una relectura,
  no una prueba pre-registrada de C-044, y se hizo con el binario de su
  fecha, que incluye Plan K (C-049); con el binario e5d331e solo está el
  lado limpio (validez de C-087). B3 cierra C-044 como fallida (no
  concluyente) porque el comando de C-044 no decide ese inciso, no por falta
  de datos. El pico de C-015 (p342a → p342b) no tiene control propio en
  342.450 s.
- **C-121**: con la definición de C-122 el cociente por celda queda en
  [0.565, 0.635] (nota de C-121 y E1), así que la etiqueta SIN DECIDIR sale
  de la letra de C-122. Las dos cotas usan cifras de C-123 que C-128 declara
  no reproducibles, y suponen que la corrida de C-123 y la de hoy siguen la
  misma trayectoria celda a celda (P3 solo lo garantiza en cinco columnas
  globales). Si esas cifras no se aceptan, queda lo que dejó C-124: no se
  cumple ningún inciso y no se refuta. El valor exacto exige la columna de
  |e| en 0 < alpha_g < 1e-2 (nueva corrida).
- **Grupo E**: `sin_decidir` es un estado nuevo; ningún evento anterior lo usa.
  En C-168 (E11) se aplica a un resultado sin criterio propio que registra
  el veredicto sin decidir de C-145 sobre C-110. El coordinador amplió la
  definición para cubrir ese caso (README y comentario de `ledger.py`). C-154
  deja de usarlo (pasa a B5).
- **`tests/out`** no es una ruta estable. Los cierres del grupo B usan los
  logs versionados de WS-K9.

## Cambios de la ronda 1

| Objeción | Cambio en el reporte |
|---|---|
| M1, O1 (evid.), O3a | C-079 pasa de refutada a fallida (no concluyente), con el motivo literal de M1 |
| M2, O4 (evid.), O4 (ref.) | C-089 pasa de soportada a fallida (no concluyente); cita C-091, C-093 y C-105, la ventana distinta y la lista de opciones refutadas |
| M3, O9, O7 (ref.) | C-199: soportada solo en el golden, con texto literal |
| M4 | Regla de alcance declarada; entran C-126, C-130, C-135, C-144, C-212, C-237, C-261, C-154 y C-168; las 90 exclusiones van justificadas |
| O2 (evid.) | Se retira «fallida» en el grupo E; queda pendiente la decisión del usuario |
| O3 (evid.), B2 | Se retira la lectura de C-175 (2); se citan C-120, C-151 y C-176; tipos corregidos |
| O5 (evid.) | Las cifras de C-123 se marcan como retiradas; se dan las vigentes con su comando |
| O1 (ref.), B3 | C-047: refutada por relectura; sale de «Incertidumbre» y se retira la predicción nueva |
| O2 (ref.), B3 | C-044: soportada por relectura; lectura del reinicio en C-015; precisión P1 sobre C-093 |
| O3b, O6 (evid.), B1 | C-085: salvedad de C-087 y lectura de C-088 en el texto |
| O3c | C-074: el texto dice que su `refuta_si` no se cumplió, con cifras |
| O5 (ref.), B1 | C-057: salvedad de C-061, más C-054 y C-063 |
| O6 (ref.) | C-082: alcance «material + atributos de los electrodos» |
| O7 (evid.) | Los comandos de C-082 y C-085 pasan a ser la lectura de `c083.out` y `c086.out` |
| B4, O8 (evid.), O7 (ref.) | C-198: relectura previa a 1de144e, logs estables de WS-K9 y comando de regeneración |
| O10 | C-015: los datos en la dirección de su `refuta_si` entran en el texto |
| O8 (ref.) | C-202: cita C-208, C-210, C-211 y C-218 |
| O11 | Evento literal (tipo, ws, ref, estado, texto, ruta y cmd) para cada cierre |

## Cambios tras la escalada (coordinador)

| Objeción | Cambio |
|---|---|
| O2 (evid.), escalada | El usuario eligió el estado cerrado `sin_decidir`. Se añade a `ledger.py` y a `research/README.md`, y el grupo E pasa a tener eventos literales E1–E11 |

## Cambios del panel tras la escalada (ronda 1 con `sin_decidir`)

| Objeción | Cambio en el reporte |
|---|---|
| M1 (aud.) | `--cmd` literales en B3 (barrido de 22/19 + `grep e5d331e` + `sed`), B4 (bucle con `\$d` escapado y filas de 345250-345283) y P1. Se probaron registrando todos los eventos en una copia del registro y ejecutando cada `cmd` (sección «Dónde quedan los pendientes»). El `cmd` de B1 pierde «regenerar: make test-full», que no era un comando |
| B1, B4 (aud.); R7 (ref.) | Límites de `validate` y `open` documentados como pendientes del coordinador; sección nueva con lo que deja de verse en `open` (0 abiertas de 64 en la simulación) |
| B2 (aud.), O6 (evid.) | Líneas de `ledger.py` actualizadas (150-156, 31, 113-114, 194); la frase sobre CERRADOS pasa a pasado y cita HEAD |
| B3 (aud.) | C1 y los datos del grupo C dicen p = −8.045e5 Pa (max\|p\|, presión negativa) |
| O1 (evid.), R1 (ref.) | C-057 pasa de refutada a fallida (no concluyente), con la lectura de código del parche y la de C-063 |
| O2 (evid.), R8 (ref.) | B3: soportada SOLO en la subida de p_max del paso truncado y en la ruta de código; «contamina reinicios» queda como lectura con un caso y el control de la validez de C-087 |
| O3, O8 (evid.) | B1 sin `tests/out` (su procedencia anterior era falsa: columnas m_gas_bx_* de 1de144e); el binario eaf3d_k8b_opt se atribuye a C-198 |
| O4 (evid.) | A3: (1,58,8) no listada en C-079; el `refuta_si` no se decide |
| O5 (evid.) | C-051 y C-064 con texto propio (C3, C4) |
| O7 (evid.) | B4: errata de la cifra de audit de C-047 en 345.28 s (3.279e5, no 2.6e5) |
| O9 (evid.), R6 (ref.) | C-154 sale del grupo E: soportada SOLO en sus cifras por relectura (B5), con su comando; E11 (C-168) describe su contenido propio |
| O10 (evid.) | E7 y la nota de C-202: el checker versionado en 1de144e da hoy PASS en k10_* (la premisa de FAIL era de la hora de C-218) |
| O11 (evid.) | A6: la regla de método sigue vigente como método (`.claude/rules/acople-pv.md:266-273`) |
| R2 (ref.) | C-085 pasa de refutada a fallida (no concluyente): C-086 juzgó el paso 341706 |
| R3 (ref.) | E1 y la nota de C-121: se quita el 0.566 como valor de C-121; cota ≥ 0.565 sin cota superior < 0.7 |
| R4 (ref.) | E4 y E9: cláusula del neto de C-135 con su retirada (C-140/C-143) y C-151 con su restricción (C-152) |
| R5 (ref.) | E7: Br + Bgr de C-208 y la salvedad de C-210 (4) |

## Cambios tras la segunda escalada (coordinador)

| Objeción | Cambio |
|---|---|
| B1 (auditor) | `validate` exige que la ref de `sin_decidir` exista, no sea veredicto ni enmienda y no esté cerrada; probado en un registro sintético |
| B4 (auditor) | `open` lista las cerradas `sin_decidir`, y el README dice cómo consultarlas |
| R6 (refutador) | Se amplía la definición de `sin_decidir` a un resultado que solo registra el «sin decidir» de otra predicción (C-168, E11) |

## Ciclo 2 (decisiones del usuario y cambios del coordinador)

El ciclo 1 terminó `sin_terminar` tras 3 rondas: el auditor aprobó en la
ronda 3 y los revisores de evidencia y refutador rechazaron. Las revisiones
están en `reviews/ciclo1/`. El usuario abrió el ciclo 2 y eligió «fallida (no
concluyente)» para los cierres parciales del grupo B.

| Objeción (ciclo 1, ronda 3) | Cambio |
|---|---|
| O1 (evid.) | A1 aplica una sola lectura (por nombre): la refutación de C-058 sí se cumplió (`:269`). No se propaga a C-057 porque las caras fijadas son salidas y su `refuta_si` habla de entradas. Se retira «la cláusula de refutación no se observó» y la cita del salto pasa a `:201` |
| O2 (evid.) | B2 (C-199), B3 (C-044) y B5 (C-154) pasan a fallida (no concluyente), con lo verificado como lectura; la regla declara la variante |
| R1 (ref.) | A6 compara con la base: refutadas por la letra de (d), que exige PASS en checks que la base ya falla; mejoran picos y centinela de gas, y empeoran la energía (y la reescritura EOS de e1 en 280 s) |

## Ciclo 2, ronda 1 del panel

| Objeción | Cambio en el reporte |
|---|---|
| O1 (evid.) | Nota de C-121, E1, fila de la tabla E e Incertidumbre: el cociente por celda con la definición de C-122 queda en [0.565, 0.635] (cota superior por la desigualdad triangular de C-124 con las columnas actuales de k7_mo20 menos las de C-123), con su comando. Se retiran «sin cota superior por debajo de 0.7», «ni excluida» y «numérica bit a bit con k7_mo20 de hoy por P3»; se dice que las dos cotas usan cifras de C-123 que C-128 declara no reproducibles |
| O2 (evid.) | A6: valores de hoy (d26k 2.321/2.334, e1 1.793/1.839, n15/n14) con `--ruta` y `--cmd`; el checker de 6127dd7, vigente a la hora de C-093, da lo mismo: el 2.31 de C-093 es una errata |
| O3 (evid.), R6 (ref.) | «Cambio de herramienta»: `validate` todavía acepta `sin_decidir` sobre C-169 y C-194 (comprobado en memoria). «Fuera de este cierre»: el único pendiente de la herramienta es `current_state` |
| O4 (evid.) | B5 y tabla B: «de 0.521 a un máximo de 0.682 (último tramo 0.639)», con la serie |
| O5 (evid.) | Grupo C: la fila 340000 difiere en 43 columnas de acumuladores, de energía y de masa |
| O6 (evid.), R5 (ref.) | Regla del grupo B: relectura de la salida guardada del propio check; en C-198, logs versionados de WS-K9. B1 cita la causa en el código y el registro del ejecutable (`git diff --stat 79dc27b 2b65e11`, `gas_mass_on`, `main_3d.f90:146-151`) en `--cmd` y en el texto |
| O7 (evid.) | La simulación del cierre va completa en el reporte, en memoria y reproducible desde el repositorio (31 eventos aceptados, 0 abiertas de 64; `--cmd` con código 0) |
| R1 (ref.) | B3, datos de C-044, grupo C, C1 e Incertidumbre citan el contraste directo C-043/C-046 (0/180 frente a 180/180; primer paso 2.98e5 frente a 3.81e4; 0 frente a 62 filas > 3e5). Se retiran «un caso» y «el contraste directo no está corrido», y la lectura de C-076 sobre diag_p342b. B3 sigue en fallida (no concluyente) porque el comando de C-044 no decide el inciso |
| R2 (ref.) | Precisión P2 sobre C-049 (el 6.07e5 es el máximo con signo; max\|p\| = 2.0e6 desde 345311) y frase en C3/C4: el brazo sin Plan K arranca de un estado de Plan K y no es un control limpio |
| R3 (ref.) | A4 e Incertidumbre: z_tip es la única asimetría; el punto caliente original está bajo el z_tip intermedio; MPI excluida por la rejilla 1x5x3 |
| R4 (ref.) | A2: lectura descriptiva de los dos regímenes, con la cifra de n15 recontada (18/22, no 14/18) y el `--cmd` que la imprime |
| R6 (ref.) | F1 pasa a fallida (no concluyente): la hija C-238 → C-239 prueba el inciso (a) |

