# WS-K11 — Diagnóstico de la centinela U_GAS_MAX del banco de 0.25 ms

Pregunta, del panel de WS-K10 ({C-222}): ¿por qué el banco `k10b_dt025` dispara la
centinela U_GAS_MAX (300 m/s, 461 kPa) a los 3 pasos de reiniciar desde
`judge_otp_280/eaf3d_00280000.h5` con dt acotado a 0.25 ms? Es diagnóstico:
sin cambios en `src/` ni `tests/`. La regla del proyecto exige diagnosticar
toda centinela que se dispare. Este cierre diagnostica el pico de
`k10b_dt025`; quedan SIN diagnosticar la de L (jb 295 s, {C-261}), los
450 kPa de `k11_dt025_s290` ({C-237}) y P_HYDRO_CAP en I y J ({C-277}).

**Resultado en una línea.** En los primeros 60 ms tras reiniciar con
0.25 ms, ENCENDER `pc_transport_f28` sobre un estado escrito sin ella es
NECESARIO, en los estados probados, para la firma (≥ 1 paso con celdas
multifase sin cara enlazada, nolink, y ≥ 20 pasos con p_max ≥ 100 kPa en
60 ms), pero NO suficiente ({C-265}, {C-266}, alcance en {C-268} y
{C-269}). Todos los estados probados con cambio son de la trayectoria
`judge_fh_275`. La firma NO es exclusiva de ese reinicio: a 1 ms,
`k7v4_long` la da 4.67 s después del cambio, junto a la parada de B1 de
284.3 s, pero con un patrón de celdas distinto ({C-275}; abajo).
- **Necesario, con ese alcance:** ninguno de los 12 brazos de 0.25 ms sin
  cambio de f28 tiene la firma: los controles con las claves apagadas en
  fh 280, 285, 290 y 295 s (A, H, M, N, O) y los estados jb/otp con sus
  claves. Entre los brazos con f28 encendida (15 de los 20 de 0.25 ms,
  contando `k11_dt025_tgfix`), «sin cambio» y «f28 establecida ≥ 5 s» van
  siempre juntos (mínimo probado: jb 280 s); A, H, M, N y O no tienen
  cambio y nunca llevan f28. Un reinicio es casi una continuación
  determinista (≤ 2.2e-12 relativo, {C-236}), así que «quién escribió el
  snapshot» no es una variable del estado: lo abierto es qué propiedad
  del estado, formada con la dinámica sin f28 y erosionada con f28
  encendida, hace falta para la firma. «Cuenta la edad del cambio» es una
  HIPÓTESIS no probada y sin escala de decaimiento ({C-268}, {C-269}).
  Se RETIRA, para F, que su final con celdas nolink la haga plausible:
  `k11_dt025_tgfix`, casi gemelo de F, termina la ventana sin nolink y en
  42-104 kPa ({C-273}). B, que no tiene gemelo, termina con nolink (4
  celdas, 109-150 kPa); de los 6 brazos con cambio y firma, B y F acaban
  con nolink y G, I, J y tgfix sin él ({C-277}; paso 13 e Incertidumbre).
- **La firma fuera de los bancos de 60 ms** ({C-269}). `k7v4_long` (1 ms,
  config de `k7v4_base`, que es la de `judge_otp_280` con 5 externas,
  desde `judge_otp_280/eaf3d_00280000.h5`, es decir, con el cambio de f28
  en 280 s; binario `eaf3d_k7v4_opt`, {C-135}; coincide con `judge_otp_280` en
  280002 y es otra trayectoria antes de 281 s) tiene nolink > 0 en 146 pasos
  entre los pasos 284669 y 285379 (t = 284.670-285.380 s; hasta 360
  celdas) y ninguno antes. En los 60 pasos desde 284669: 59 con nolink, 45
  con p_max ≥ 100 kPa, 30 con u_gas_max ≥ 299 m/s y p_max hasta 153 kPa.
  Su primera fila de nivel centinela de B1 es anterior y sin nolink (300
  m/s en el paso 284340, t = 284.341 s; {C-272} corrige el paso de
  {C-269}), y 86 de sus 96 filas de nivel centinela llevan nolink
  ({C-274}). Lo único común con los reinicios de 0.25 ms es el indicador
  binario nolink > 0; el patrón es distinto ({C-275}):
  - **tamaño:** `k7v4_long` tiene exactamente 360 celdas en 144 de sus
    146 pasos nolink (12 tramos), un bloque fijo que se enciende y se
    apaga; los reinicios, 1-16 celdas que fluctúan (máximo 6 en F, 11 en
    G, 16 en I, 13 en J);
  - **orden:** en `k7v4_long` el episodio empieza por u_gas (300 m/s en
    284340) sin nolink; en los 328 pasos siguientes p_max queda en
    35.9-85.3 kPa y no hay nolink ({C-277}), y nolink entra de 0 a 360 en 284669, el
    paso de su primer p_max ≥ 100 kPa; en los reinicios, nolink está
    desde el paso 2;
  - **relación con p** (mixta): pasos con p_max ≥ 100 kPa que llevan
    nolink, 94/96 en `k7v4_long` y 27/27 en G, pero 71/120 en F, 56/142
    en I y 70/219 en J.
  Hipótesis de trabajo: NO es el mismo conjunto de celdas. Quedan dos
  lecturas sin discriminar: (i) un artefacto propio del cambio; (ii) el
  cambio con 0.25 ms dispara antes el mecanismo de las paradas de B1;
  estos datos no apoyan (ii). Tampoco la refutan: la comparación cruza la
  convergencia del Poisson y el binario. `k7v4_long` (CG 20, 5 externas)
  acumula ≥ 27001 resoluciones de CG sin converger de unas 27500, frente
  a 0 avisos en los bancos de 0.25 ms (CG 1000), y la clase nolink
  depende de los enlaces del último Poisson; su binario es del 25-oct,
  anterior a `4d8570a` ({C-277}; Incertidumbre).
  > [fuente: python3 research/ws/WS-K11/scripts/nolink.py]
- **No suficiente:** encender f28 da la firma en fh 280, 285 y 295 s
  (pares de una clave A/F, M/I y O/J) y en el estado de 280.06 s escrito
  por el binario actual (G, sin control sin cambio), y no en fh 300 s (P).
  En fh 290 s la firma se midió encendiendo las dos claves (N/B): f28 sola
  en 290 s no se probó.
- **La firma** se definió tras ver los primeros 14 brazos. Fuera de esa
  muestra, H22 era una predicción de BAJO riesgo: nunca se había visto
  nolink con f28 apagada, y la columna con f28 apagada solo existe en
  ventanas de 60 ms (A, H, M, N, O). La única prueba exigente fuera de
  muestra fue H23, y quedó refutada (la suficiencia). Si «nolink ⇒ f28
  encendida» vale en B1 lo decidiría una corrida larga sin f28 con la
  columna (no corrida; Incertidumbre).
- **Solo un sentido del cambio.** Todos los reinicios con cambio encienden
  f28 sobre un estado escrito sin ella; ninguno la apaga sobre un estado
  escrito con ella. El titular no cubre ese sentido (Incertidumbre).
- **La centinela U_GAS_MAX sola no identifica el cambio:** en jb 295 s,
  con las claves de su escritor, acotar dt da 300.0 m/s en 1 paso
  (295002; 3 pasos ≥ 200 m/s) y se apaga, sin nolink (H20 REFUTADA por ese
  brazo; {C-259}).
- **`pc_outlet_total_pressure`** no es necesaria en fh 280 s (F, {C-249})
  ni suficiente en fh 280 s (H, {C-257}) ni en jb 280 s (E, {C-248}).

Nueve predicciones pre-registradas, una trayectoria por brazo y todos los
brazos con 0.25 ms:
- **H15** ({C-238}, SOPORTADA en {C-239}; alcance en {C-240}): encender las
  dos claves es NECESARIO para el pico. Desde el snapshot de 280 s con las
  claves APAGADAS no hay pico (15 kPa, 69 m/s); desde el de 290 s de
  `judge_fh_275`, escrito sin ellas, encendiéndolas sí (300 m/s). El brazo A
  solo difiere de `k10b_dt025` en las dos claves: el snapshot de 280 s y el
  código que lo escribió no bastan, cosa que H13 ({C-227}) no aislaba
  ({C-236}).
- **H16** ({C-244}, SOPORTADA en {C-245}): tener f28 encendida no basta.
  Desde el estado de 280 s de `judge_jb_275`, con sus mismas claves (f28
  desde 275 s, sin la de presión total), no hay pico: 51 m/s y 117 kPa como
  máximo.
- **H17** ({C-246}, REFUTADA en {C-248}): encender SOLO la presión total
  sobre ese mismo estado tampoco da pico. Reproduce el brazo de H16 a
  ≤ 7.9e-9 relativo en u_gas_max y p_max en los pasos 0-10.
- **H18** ({C-247}, REFUTADA en {C-249}): encender SOLO f28 sobre el estado
  de 280 s escrito sin las claves BASTA. Da el pico entero de `k10b_dt025`
  (300 m/s, 461 kPa, 592 kPa en 280161) y lo reproduce a ≤ 1.1e-9 relativo
  en los pasos 0-10.
- **H19** ({C-252}, SOPORTADA en {C-255}): el binario que escribió el estado
  no es el confusor. Encender f28 sobre el estado de A en 280.06 s, escrito
  por el binario actual con las claves apagadas y sin acotar dt, da pico
  (216 m/s y 361 kPa en los pasos 2-10; 895 kPa en la ventana).
- **H20** ({C-253}, REFUTADA en {C-256}): encender f28 sobre fh en 285 y
  295 s da pico, hasta P_HYDRO_CAP (2 MPa); jb 285 s con sus claves no lo
  da; jb 295 s con sus claves SÍ, por la letra: 300.0 y 299.8 m/s en
  295002-295003 y 245.3 m/s en 295004 (3 pasos ≥ 200 m/s, 1 en U_GAS_MAX)
  y después ≤ 113 m/s, sin celdas nolink {C-259}.
- **H21** ({C-254}, SOPORTADA en {C-257}): encender solo la presión total
  sobre fh 280 s no da pico (15 kPa, 69 m/s, como A).
- **H22** ({C-263}, SOPORTADA en {C-265}): fh 285, 290 y 295 s con las
  claves apagadas no dan la firma (15-20 kPa, sin nolink): el estado fh
  tardío con 0.25 ms no basta.
- **H23** ({C-264}, REFUTADA en {C-266}): encender f28 sobre fh 300 s no da
  la firma (máximo 96 kPa, alternancia que decae, sin nolink); jb 300 s
  con sus claves tampoco, como se predijo.

El «cambio» se define operativamente: un estado escrito por un linaje sin
f28 (judge_fh_275) frente a uno escrito con ella (judge_jb_275). Los dos
linajes parten del MISMO estado de 275 s (sus `eaf3d_00275000.h5` son
idénticos) y sus configs solo difieren en f28, pero en 5 s los estados
divergen mucho; los escribieron binarios distintos, confusor que H19
descarta. Más hallazgos:
- **Tras el cambio, la persistencia ≥ 100 kPa no es general** {C-268}.
  Ocupa los 60 ms en F y `k10b_dt025` (120/235 pasos), B (235/235) y J
  (219/239), y con medias que bajan en `k11_dt025_tgfix` (103/235: 31, 27,
  26, 19; nolink solo en 280002-280023); en G cae a 0 tras el primer
  cuarto (27, 0, 0, 0), en I baja a 6 en el segundo (59, 6, 22, 55) y en P
  no aparece. No es un transitorio de 2-3 pasos. En B la media de p_max
  por cuartos cae un 44 % (244 → 138 kPa), en `k10b_dt025` la de |Δp| va
  de 73 a 31 kPa y en `k11_dt025_tgfix` la de p_max de 138 a 84 kPa y la
  de |Δp| de 74 a 18 kPa ({C-273}). Si decae después de 60 ms, sin decidir
  {C-239}{C-240}{C-250}.
- **Con 0.25 ms, sin cambio de claves, los brazos jb/otp no son
  tranquilos; los fh apagados sí.** Los brazos jb/otp con f28 establecida
  alternan: C y E pasan de 28 kPa a 76-80 kPa de media por cuartos, K
  66-71, L 31-42, Q 34-52, con |Δp| de 8-27 kPa. Los fh con las claves
  apagadas (A, H, M, N, O) quedan planos en 14-18 kPa con |Δp| ≤ 0.1 kPa.
  f28 y linaje van juntos (no hay brazo jb/otp con f28 apagada ni fh sin
  cambio con f28 encendida), así que no se separa si ese nivel lo pone f28
  o el estado (Resultado). El contraste de H16 (C sin pico) vale para el
  pico de los pasos 2-10 con el umbral pre-registrado, no para el nivel
  del régimen {C-250}.
- **Huella con 0.25 ms: celdas multifase sin cara enlazada** (columna
  `m_gas_cells_nolink`) desde el paso 2 tras encender f28: 105/235 pasos en
  `k10b_dt025` y en F, 235/235 en el brazo B. Ninguna en los bancos de
  60 ms con 0.5 y 1 ms (`k10b_dt05`, `k10b_mo20`) ni en los 1000 pasos de
  `k7v5_mo20_1k`, ni con las claves apagadas o f28 ya establecida (A, C,
  D, E y `k11_dt025_s290`) {C-240}{C-245}{C-248}. Pero sí con 1 ms en
  `k7v4_long`, desde el paso 284669 (t = 284.670 s; arriba, {C-269},
  {C-272}), con un bloque de 360 celdas en lugar de 1-16 ({C-275}):
  el indicador nolink no es exclusivo de 0.25 ms ni del reinicio. En los 20
  brazos de 0.25 ms (los 19 de `h22.py --todos` y `k11_dt025_tgfix`, que
  el script omite; paso 13), nolink > 0 implica cambio de f28 en los 60
  ms, pero el cambio no implica nolink (P). Como la firma incluye nolink por definición, que
  nolink «separe la firma» es circular; lo que se lee es la implicación
  anterior, lectura no pre-registrada en su origen ({C-260}, {C-269};
  paso 12 e Incertidumbre).
- **No es el salto de densidad** heredado de `Tg_end` ({C-225}, refutada).
- **Con las claves ya establecidas** (snapshots de 290 y 300 s de
  `judge_otp_280`) no hay ese pico. Pero desde 290 s, con 0.25 ms, quedan
  excursiones aisladas de presión de hasta 450 kPa (paso 290093), sin
  diagnosticar ({C-236}) y no repetidas desde 300 s ({C-245}). El snapshot
  de 290 s cae en la fase tranquila de 290-293 s de ese juez
  {C-241}{C-242}.
- **Con 1 ms el pico no se asienta en un estado tranquilo** sino en un ciclo
  de 2 pasos; con f28 encendida ese régimen alto y alternante ocupa los
  15-20 s medidos en los dos jueces que la llevan, también en `judge_otp_280`, el juez de B1
  después de 280 s {C-241}. Eso es con media de p_max y |Δp|. Con la
  métrica de las paradas de B1 (u_gas ≥ 299 m/s o p_max ≥ 300 kPa), en
  280-295 s el linaje con solo f28 es el más tranquilo (1 fila, frente a 15
  del linaje apagado y 26 del juez de B1): los datos no sostienen que ese
  régimen explique las paradas de B1 {C-251}.

## Proceso

1. **Datos del banco** {C-222}. En `k10b_dt025` hay tres pasos anómalos tras
   el reinicio:

   | paso | u_gas_max [m/s] | p_max [kPa] |
   |---|---|---|
   | 280002 | 198.6 | 281 |
   | 280003 | 300.0 | 461 |
   | 280004 | 200.8 | 199 |

   `check_audit` da FAIL en `sentinel_gas` (paso 280003), `regime_gas` y
   `regime_p`. El de `regime_p` (591.6 kPa) NO es de este pico: está en el
   paso 280161, 40 ms después del reinicio ({C-236}). Cero `[CG] AVISO`.
   > [fuente: python3 research/ws/WS-K10/scripts/centinela.py campaigns/b1/k10b_mo20 campaigns/b1/k10b_dt05 campaigns/b1/k10b_dt025; python3 tests/integration/check_audit.py campaigns/b1/k10b_dt025 | grep FAIL]
2. **Descartado sin corrida: el acarreo de compresibilidad** {C-228}. `comp_carry`
   del snapshot vale 0 en todas las celdas.
   > [fuente: python3 -c "import h5py,numpy as np; c=np.array(h5py.File('campaigns/b1/judge_otp_280/eaf3d_00280000.h5','r')['restart/comp_carry']); print(abs(c).sum())"]
3. **Descartado sin corrida: la densidad del snapshot** {C-228}{C-236}.
   Coincide con la EOS de su T_gas y su p (`gas_eos`,
   `src/mod_constants.f90:594-599`, rho_gas = 1.2): |Δρ/ρ| ≤ 4.4e-16 en las
   68232 celdas con gas, es decir, redondeo. En cambio, `Tg_end` difiere de
   T_gas en unas pocas celdas: |T_gas/Tg_end − 1| llega a 17.7 % (p99 0.2 %)
   en esas mismas 68232 celdas.
   > [fuente, solo lectura: python3 -c "import h5py,numpy as np; f=h5py.File('campaigns/b1/judge_otp_280/eaf3d_00280000.h5','r'); r,T,p,a=(np.array(f[k]) for k in ('restart/rho_gas','fields/T_gas','fields/pressure','fields/alpha_gas')); m=a>1e-6; e=r[m]*np.maximum(T[m],100.)*101325./np.maximum(101325.+p[m],0.05*101325.)/300.; print(m.sum(), np.abs(e/1.2-1).max())". Salto de Tg_end, solo lectura: python3 -c "import h5py,numpy as np; f=h5py.File('campaigns/b1/judge_otp_280/eaf3d_00280000.h5','r'); T,G,a=(np.array(f[k]) for k in ('fields/T_gas','restart/Tg_end','fields/alpha_gas')); m=a>1e-6; e=np.abs(T[m]/G[m]-1); print(m.sum(), e.max(), np.percentile(e,99))". La copia corregida de H12 la ESCRIBE python3 research/ws/WS-K11/scripts/snap_tgfix.py ORIGEN DESTINO.]
4. **H12** {C-224}, pre-registrada en el commit `096b1ba` antes de correr.
   - **Hipótesis:** el salto heredado de `Tg_end` es el disparador. La fuente
     de compresibilidad lo ventea dividido por el dt nuevo
     (`src/mod_multiphase.f90:473-477`, `src/mod_pressure_3d.f90:598-601`).
   - **Prueba:** una copia del snapshot con `Tg_end` = `T_gas`.
   - **Veredicto: REFUTADA** {C-225}. La serie de los pasos 280001-280005
     coincide con la de `k10b_dt025` a 2-3 cifras: p_max del paso 280001
     difiere un 0.45 % (69.37 frente a 69.06 kPa); en 280002-280005, ≤ 3.4e-4
     relativo en p_max y u_gas_max. La centinela salta igual en el paso
     280003.
   > [fuente: python3 research/ws/WS-K11/scripts/medir_centinela.py campaigns/b1/k10b_dt025 campaigns/b1/k11_dt025_tgfix]
5. **Descartado con datos existentes: una demanda de volumen que crezca como
   1/dt** {C-228}. Por unidad de tiempo, la masa que reescribe la EOS final vale
   2.922, 2.882 y 2.865 kg/s con 1, 0.5 y 0.25 ms. El calentamiento posterior
   al SIMPLE escala con dt; no es un salto fijo por paso.
   > [fuente: python3 -c "import csv,statistics as s; [print(n, s.mean(float(x['m_gas_eosend_scale'])/2 for x in list(csv.DictReader(open('campaigns/b1/'+n+'/audit.csv')))[2:])/dt) for n,dt in (('k10b_mo20',1e-3),('k10b_dt05',5e-4),('k10b_dt025',2.5e-4))]"]
6. **El cambio de claves** {C-226}{C-236}, señalado por la revisión previa
   del panel de WS-K10. `diff` entre las configs de `judge_fh_275` y `judge_otp_280`:
   `judge_otp_280` añade `pc_transport_f28 = true` y
   `pc_outlet_total_pressure = true`. Las dos claves se introdujeron con
   valor por defecto ON en `2f0529b` (21-oct, 10:13:58) y `8f568fc` (22-oct,
   02:56:49); antes no existían en `src/`. El run.log de `judge_otp_280` nació
   43 s después del segundo (02:57:32). El pico de los pasos 2-3 tras el reinicio en
   280 s aparece con todos los dt y crece al bajar dt: 99.6 kPa (280003) y
   163.5 m/s (280002) con 1 ms, 191.4 kPa (280003) con 0.5 ms, 461 kPa y
   300 m/s (280003) con 0.25 ms.
   > [fuente: diff campaigns/b1/judge_fh_275/config.dat campaigns/b1/judge_otp_280/config.dat; git log -1 --date=iso 2f0529b; git log -1 --date=iso 8f568fc; git log -S pc_transport_f28 -- src; git log -S pc_outlet_total_pressure -- src; stat -f '%SB' -t '%F %T' campaigns/b1/judge_otp_280/run.log; python3 research/ws/WS-K11/scripts/medir_centinela.py campaigns/b1/k10b_mo20 campaigns/b1/k10b_dt05]
7. **Datos existentes a 1 ms** {C-236}, no citados en la primera versión.
   Todos reinician de `judge_fh_275/eaf3d_00280000.h5` con la config de B1
   (5 externas, CG 20) y dt 1 ms. Valores de u_gas_max [m/s] / p_max [kPa]:

   | banco | claves encendidas | arranque | 280001 | 280002 |
   |---|---|---|---|---|
   | `scrfh_base` | ninguna | 20-oct 17:14 | 71.9 / 14.8 | 71.7 / 14.8 |
   | `scrfh_b` | solo f28 | 20-oct 21:29 | 160.0 / 65.3 | 189.8 / 62.0 |
   | `m203_280`, `m21f1_280` | solo f28 | 21-oct | 126.5 / 50.3 | 215.0 / 83.5 |
   | `judge_otp_280`, `k10_base` | f28 y outlet | 22-oct y 27-oct | 126.5 / 50.3 | 215.0 / 83.5 |

   - Con las claves apagadas el reinicio es liso; al encender f28 aparece el
     pico. En la config, `scrfh_b` solo difiere de `scrfh_base` en
     `pc_transport_f28`. Sin embargo, su run.log se creó en el mismo segundo
     que `campaigns/bin/eaf3d_cand_f28_opt` (21:29:42), posterior a
     `3c4bf52`: su binario probablemente no es el de `scrfh_base`. Los logs
     no registran el binario.
   - `m203_280` y `m21f1_280` (solo f28) reproducen a `judge_otp_280`
     (f28 y outlet) en 280001-280011 con menos de 5e-6 de diferencia relativa:
     a 1 ms, `pc_outlet_total_pressure` no añade nada visible.
   - Los cuatro bancos tienen `[CG] AVISO` (CG 20): no son bancos limpios.
   > [fuente: python3 research/ws/WS-K11/scripts/medir_centinela.py campaigns/b1/scrfh_base campaigns/b1/scrfh_b campaigns/b1/m203_280 campaigns/b1/judge_otp_280; diff campaigns/b1/scrfh_base/config.dat campaigns/b1/scrfh_b/config.dat; stat -f '%SB %N' campaigns/b1/scrfh_base/run.log campaigns/b1/scrfh_b/run.log campaigns/bin/eaf3d_cand_f28_opt]
8. **H13** {C-226}, pre-registrada en el commit `d4c07b7` antes de correr.
   - **Hipótesis:** la centinela es el transitorio de cambiar las claves,
     amplificado al bajar dt. (Enunciado tal como se pre-registró. La lectura
     «el mismo transitorio, amplificado» no se sostiene: con 0.25 ms aparecen
     celdas sin cara enlazada que no hay con 0.5 ni 1 ms, y el régimen se
     mantiene ≥ 100 kPa en la ventana; ver paso 9 y {C-240}.)
   - **Prueba:** el mismo banco de 0.25 ms desde
     `judge_otp_280/eaf3d_00290000.h5`, que escribió `judge_otp_280` ya con
     las claves activas.
   - **Control:** 1 ms desde el mismo snapshot.
   - **Veredicto: SOPORTADA por la letra** {C-227}. La prueba sostiene que el
     pico es propio del snapshot de 280 s, pero no aísla las claves
     ({C-236}; ver Incertidumbre).

9. **H15** {C-238}, pre-registrada en el commit `424a70d` antes de correr.
   Responde al panel, ronda 1: H13 no aislaba las claves.
   - **Brazo A.** `k11_a_dt025_s280_off`: config de `k10b_dt025` (0.25 ms,
     20 externas, CG 1000) desde `judge_otp_280/eaf3d_00280000.h5`, con
     `pc_transport_f28` y `pc_outlet_total_pressure` en false. Mismo estado
     y mismo escritor que `k10b_dt025`, pero sin cambio de claves.
   - **Brazo B.** `k11_b_dt025_fh290_on`: el mismo banco desde
     `judge_fh_275/eaf3d_00290000.h5`, escrito con las claves apagadas, con
     las dos en true. Hay cambio de claves, con otro estado.
   - **Criterio.** Hay «pico» si en los pasos 2-10 u_gas_max ≥ 200 m/s o
     p_max ≥ 300 kPa. SOPORTADA si A no tiene pico y B sí.

   | brazo | pasos 2-10: u_gas_max / p_max | ventana: max p_max | pasos ≥ 100 kPa por cuartos | FAIL |
   |---|---|---|---|---|
   | A (280 s, claves off) | 69.4 m/s / 15 kPa | 15 kPa | 0, 0, 0, 0 | ninguno |
   | B (fh 290 s, claves on) | **300.0 m/s** / 342 kPa | 365 kPa (290020) | 58, 59, 59, 59 | sentinel_gas, regime_gas |

   > [fuente: python3 research/ws/WS-K11/scripts/h15.py campaigns/b1/k11_a_dt025_s280_off 280000 campaigns/b1/k11_b_dt025_fh290_on 290000; python3 tests/integration/check_audit.py campaigns/b1/<brazo> | grep FAIL]

   - **Veredicto: SOPORTADA por la letra** {C-239}. Cero `[CG] AVISO` en
     los dos brazos.
   - **Alcance** {C-240}. El par brazo A / `k10b_dt025` solo cambia las dos
     claves (mismo snapshot, mismo binario `eaf3d_k10b_opt`, misma config
     salvo las claves): demuestra que encenderlas es NECESARIO. No dice nada
     de su historial: la alternativa «con las claves encendidas y 0.25 ms ese
     estado ya da el pico, haya o no cambio» predice el mismo patrón A sin
     pico / B con pico. El único estado con las claves ya establecidas era
     `k11_dt025_s290`, un solo snapshot del mismo linaje fh tras encender
     las claves en 280 s (`judge_otp_280` reinicia de `judge_fh_275`), en
     una fase tranquila {C-241}. H15 sola no separaba el cambio de la presencia; lo separan
     H16 (paso 10) para f28, y H17 y H18 (paso 11) clave por clave.
   - **Lectura de la ventana.** Con 0.25 ms, en `k10b_dt025` y B el
     régimen tras encender las claves se mantiene ≥ 100 kPa en toda la
     ventana, con medias que bajan (Resultado); no en todos los brazos con
     cambio (paso 13, {C-268}). En `k10b_dt025` los pasos ≥ 100 kPa
     por cuartos son 31, 21, 32 y 36 (120/235); {C-239} registró por error
     33 en el último cuarto, corregido en {C-240}. En el brazo B son 58, 59,
     59 y 59.
     > [fuente: python3 -c "import csv; r=[x for x in csv.DictReader(open('campaigns/b1/k10b_dt025/audit.csv')) if int(x['step'])>280001]; n=len(r); print([sum(float(x['p_max'])>=1e5 for x in r[i*n//4:(i+1)*n//4]) for i in range(4)])"]
   - **Huella: celdas sin cara enlazada** {C-240}. La columna
     `m_gas_cells_nolink` cuenta las celdas multifase sin ninguna cara
     enlazada (líquido ni gas) en el último Poisson (clase de {C-132},
     `src/mod_audit.f90:1318-1335`).

     | banco | dt | claves | pasos con nolink > 0 | coincide con p_max ≥ 100 kPa |
     |---|---|---|---|---|
     | `k11_a_dt025_s280_off` | 0.25 ms | off (280 s) | 0/235 | — |
     | `k11_dt025_s290` | 0.25 ms | on, establecidas (290 s) | 0/235 (también en 290093, 450 kPa) | — |
     | `k10b_dt05` | 0.5 ms | encendidas en 280 s | 0/117 | — |
     | `k10b_mo20` | 1 ms | encendidas en 280 s | 0/58 | — |
     | `k10b_dt025` | 0.25 ms | encendidas en 280 s | 105/235: 280002-280023, 280135-280141 y 280161-280236 (2 celdas en 280002, máx. 6) | 71 de 120 |
     | `k11_b_dt025_fh290_on` | 0.25 ms | encendidas en 290 s | 235/235, 4-9 celdas hasta el último paso (290236) | 235 de 235 |
     | `k11_c_dt025_jb280` (H16) | 0.25 ms | f28 sin cambio (jb 280 s) | 0/235 | — |
     | `k11_d_dt025_s300` (H16) | 0.25 ms | on, establecidas (300 s) | 0/235 | — |
     | `k11_e_dt025_jb280_otp` (H17) | 0.25 ms | f28 sin cambio, presión total encendida (jb 280 s) | 0/235 | — |
     | `k11_f_dt025_fh280_f28` (H18) | 0.25 ms | solo f28 encendida en 280 s | 105/235, en los mismos pasos que `k10b_dt025` (`pares.py`: «mismos pasos nolink: True») | 71 de 120 |

     El máximo de `regime_p` de `k10b_dt025` (591.6 kPa, paso 280161) abre su
     último tramo con celdas nolink. Con 1 ms el pico (163.5 m/s en
     `k10b_mo20`, 215 m/s en `judge_otp_280`, que no tiene esa columna)
     existe sin ninguna celda nolink (tampoco en los pasos 280001-280031 de
     `k7v4_long`). Con 0.25 ms entra, pues, en el arranque un ingrediente
     que no aparece en el arranque con 0.5 ni con 1 ms; con 1 ms sí aparece
     más tarde, en `k7v4_long` desde el paso 284669 (284.670 s; {C-269}, {C-272}),
     con 360 celdas fijas frente a 1-16 ({C-275}). En B las celdas nolink siguen hasta
     el último paso, pero la media de p_max baja un 44 % en la ventana: si
     es un estado trabado o un transitorio lento, sin decidir (Resultado).
     Dónde están esas celdas no
     se ha medido (Incertidumbre).
     > [fuente: python3 -c "import csv; [print(d, sum(float(x['m_gas_cells_nolink'])>0 for x in r), sum(float(x['m_gas_cells_nolink'])>0 and float(x['p_max'])>=1e5 for x in r), sum(float(x['p_max'])>=1e5 for x in r)) for d,p0 in (('k10b_dt025',280001),('k11_b_dt025_fh290_on',290001),('k11_a_dt025_s280_off',280001),('k11_dt025_s290',290001),('k10b_dt05',280001),('k10b_mo20',280001),('k11_c_dt025_jb280',280001),('k11_d_dt025_s300',300001),('k11_e_dt025_jb280_otp',280001),('k11_f_dt025_fh280_f28',280001)) for r in [[x for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])>p0]]]"]
   - **Con 1 ms** {C-241}. Criterio de «asentado»: primer paso desde el que
     la serie queda, hasta el paso 58, dentro de ±10 % de la media de su
     paridad (pasos pares o impares) en los pasos 31-58. En `judge_otp_280`,
     p_max se asienta en el paso 24 y u_gas_max en el 17; en `k10b_mo20`, en
     el 31 y el 13. Es decir, 13-31 pasos, no «20-25». Y no se asienta en un
     estado tranquilo, sino en un ciclo de 2 pasos: p_max 23/43 kPa en
     `judge_otp_280` y 28/49 kPa en `k10b_mo20` (ver Resultado).
     > [fuente: python3 -c "import csv,statistics as s; [print(d,c,next(k for k in range(280001,280059) if all(abs(float(r[j][c])/m[j%2]-1)<=0.1 for j in range(k,280059)))) for d in ('k10b_mo20','judge_otp_280') for r in [{int(x['step']):x for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if 280000<int(x['step'])<=280058}] for c in ('p_max','u_gas_max') for m in [{q:s.mean(float(r[k][c]) for k in range(280031,280059) if k%2==q) for q in (0,1)}]]"]

10. **H16** {C-244}, pre-registrada en el commit `aa93539` antes de correr
    (panel ronda 2, refutador O1).
    - **Brazo C (decide).** `k11_c_dt025_jb280`: config de `k10b_dt025`
      desde `judge_jb_275/eaf3d_00280000.h5`, con las mismas claves que su
      escritor (`pc_transport_f28` = true, `pc_outlet_total_pressure` =
      false). Mismo instante de 280 s, sin cambio de claves.
    - **Brazo D (lectura).** `k11_d_dt025_s300`: desde
      `judge_otp_280/eaf3d_00300000.h5`, con las claves establecidas 20 s.

    | brazo | pasos 2-10: u_gas_max / p_max | ventana: max p_max | pasos ≥ 100 kPa por cuartos | FAIL |
    |---|---|---|---|---|
    | C (jb 280 s, mismas claves) | 51.2 m/s / 117 kPa | 117 kPa (280004) | 1, 0, 0, 0 | ninguno |
    | D (otp 300 s, claves establecidas) | 77.0 m/s / 56 kPa | 56 kPa (300002) | 0, 0, 0, 0 | ninguno |

    > [fuente: python3 research/ws/WS-K11/scripts/h15.py campaigns/b1/k11_c_dt025_jb280 280000 campaigns/b1/k11_d_dt025_s300 300000 (líneas de cada brazo; la línea combinada «H15» no aplica a H16); python3 tests/integration/check_audit.py campaigns/b1/<brazo> | grep FAIL]

    - **Veredicto: SOPORTADA por la letra** {C-245}. El brazo C no tiene
      pico, con cero `[CG] AVISO`. Tener f28 encendida con 0.25 ms en un
      estado de 280 s no basta.
    - **Nivel con 0.25 ms sin cambio de claves** {C-250}. El brazo C sí
      reacciona: p_max pasa de 28.0 kPa (280000) a 116.5 kPa (280004) y
      alterna con periodo 2; los pasos pares pasan por 99.2, 90.7 y 86.5 kPa
      (280006-280010) y se estabilizan en ~87 kPa (impares ~75 kPa) hasta
      el último paso. No es un transitorio que decae: la media de p_max por
      cuartos es 76, 79, 79 y 80 kPa y la de |Δp| 18, 11, 11 y 11 kPa,
      frente a 33.9 / 11.7 kPa del juez jb a 1 ms en 280-281 s (Resultado).
      El pico de los pasos 2-10 es el 39 % del umbral de 300 kPa, una sola
      trayectoria, sin celdas nolink (0/235). El brazo D alterna entre
      unos 30 y 51-56 kPa en los primeros pasos (300001-300006) y entre
      23 y 31 kPa al final (300229-300236); su media por cuartos baja de
      37.8 a 28.2 kPa, también sin celdas nolink. Por eso H16 se lee como contraste
      del PICO de los pasos 2-10, no del nivel: con 0.25 ms todos los brazos
      con f28 encendida suben de nivel y alternan, y A (f28 apagada) no.
      > [fuente: python3 -c "import csv; [print(d, [round(float(x['p_max'])/1e3,1) for x in r[:11]], [round(float(x['p_max'])/1e3,1) for x in r[-8:]]) for d in ('k11_c_dt025_jb280','k11_d_dt025_s300') for r in [list(csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')))]]"; medias por cuartos: ver la tabla de Resultado]
    - **Lectura del brazo D.** Los picos aislados de 450 kPa de
      `k11_dt025_s290` (paso 290093) no se repiten desde 300 s. Siguen sin
      diagnosticar y pueden ser propios de esa fase.

11. **H17 y H18** ({C-246}, {C-247}), pre-registradas en el commit
    `650d712` antes de correr (panel, ciclo 1, ronda 3: evidencia O2 y
    refutador R2). Cada brazo cambia UNA clave frente a un banco ya medido:
    - **Brazo E (H17).** `k11_e_dt025_jb280_otp`: el brazo C con
      `pc_outlet_total_pressure` = true. Solo cambia la presión total.
      Predicción: pico.
    - **Brazo F (H18).** `k11_f_dt025_fh280_f28`: el brazo A con
      `pc_transport_f28` = true, es decir, `k10b_dt025` con
      `pc_outlet_total_pressure` = false. Solo cambia f28. Predicción: sin
      pico.

    | brazo | pasos 2-10: u_gas_max / p_max | ventana: max p_max | pasos ≥ 100 kPa por cuartos | nolink | FAIL |
    |---|---|---|---|---|---|
    | E (jb 280 s, cambia la presión total) | 51.2 m/s / 117 kPa | 117 kPa (280004) | 1, 0, 0, 0 | 0/235 | ninguno |
    | F (fh 280 s, cambia f28) | **300.0 m/s** / 461 kPa | 592 kPa (280161) | 31, 21, 32, 36 | 105/235 | sentinel_gas, regime_p, regime_gas |

    > [fuente: python3 research/ws/WS-K11/scripts/h17.py campaigns/b1/k11_e_dt025_jb280_otp campaigns/b1/k11_f_dt025_fh280_f28; python3 tests/integration/check_audit.py campaigns/b1/<brazo> | grep FAIL]

    - **Veredictos: H17 REFUTADA {C-248} y H18 REFUTADA {C-249}**, por la
      letra. Cero `[CG] AVISO` en los dos brazos. Mis dos predicciones
      (pre-registradas con prior débil) fallaron en el mismo sentido: la
      clave que importa es f28, no la presión total.
    - **Cada par reproduce su banco gemelo.** En los pasos 0-10, E difiere
      de C en ≤ 7.9e-9 relativo en u_gas_max y ≤ 1.5e-9 en p_max; F difiere
      de `k10b_dt025` en ≤ 1.1e-9 y ≤ 3.5e-10. m_gas difiere en ~2.5e-7: la
      presión total sí actúa. Lo hace en toda abertura del techo con
      electrodo y gas (alpha_g ≥ ALPHA_FLOW_CUTOFF), relajando p hacia
      p0 − ½ ρ_g u_in², con u_in > 0 solo si hay reflujo; sin reflujo
      relaja hacia la columna de gas p0 = ρ_g g (zf − z), que se mueve con
      ρ_g (`src/mod_pressure_3d.f90:1001-1027` y `2000-2012`). Así que la
      diferencia de m_gas no se puede atribuir al reflujo sin medirlo (no
      medido). Su efecto en el arranque es despreciable. Más
      adelante en la ventana las series se separan (u_gas_max hasta 12 % en
      E frente a C), como cabe esperar de una dinámica caótica.
      > [fuente: python3 research/ws/WS-K11/scripts/pares.py campaigns/b1/k11_c_dt025_jb280 campaigns/b1/k11_e_dt025_jb280_otp campaigns/b1/k10b_dt025 campaigns/b1/k11_f_dt025_fh280_f28]
    - **Coherente con 1 ms** ({C-236}, paso 7): allí encender solo f28 ya
      reproducía a `judge_otp_280` y la presión total no añadía nada
      visible.

12. **H19, H20 y H21** ({C-252}, {C-253}, {C-254}), pre-registradas en el
    commit `2c03398` antes de correr (panel, ciclo 2, ronda 1: refutador R5
    y R7, y el hueco de la presión total sola sobre fh). Binario
    `eaf3d_k10b_opt`, 15 ranks, en serie; misma definición de pico, con P0
    el paso del reinicio.
    - **G (H19, predice pico).** `k11_g_dt025_a236_f28`: el estado final
      de A (`k11_a_dt025_s280_off/eaf3d_00280236.h5`, 280.06 s, escrito por
      `eaf3d_k10b_opt` con las claves apagadas; dt del snapshot 2.5e-4, sin
      acotar) con f28 encendida.
    - **H (H21, predice sin pico).** `k11_h_dt025_fh280_otp`: A con solo la
      presión total encendida.
    - **I y J (H20, predicen pico).** f28 encendida desde
      `judge_fh_275/eaf3d_00285000.h5` y `eaf3d_00295000.h5`.
    - **K y L (H20, predicen sin pico).** Las mismas claves que su escritor
      (f28 encendida, presión total apagada) desde
      `judge_jb_275/eaf3d_00285000.h5` y `eaf3d_00295000.h5`.

    | brazo | cambio de f28 | pasos 2-10: u / p | ventana: max p_max | pasos ≥ 100 kPa por cuartos | nolink | pasos u ≥ 200 / p ≥ 300 kPa; último | FAIL |
    |---|---|---|---|---|---|---|---|
    | G (A 280.06 s) | sí | **216.3 m/s / 361 kPa** | 895 kPa (280263) | 27, 0, 0, 0 | 35 | 9 / 7; paso 27 | sentinel_gas, regime_p, regime_gas |
    | H (fh 280 s, solo presión total) | no | 69.4 / 15 | 15 kPa | 0, 0, 0, 0 | 0 | 0 / 0 | ninguno |
    | I (fh 285 s) | sí | **300.0 / 2000** | 2000 kPa (285009) | 59, 6, 22, 55 | 57 | 99 / 55; paso 232 | sentinel_p, sentinel_gas, regime_p, regime_gas |
    | J (fh 295 s) | sí | **300.0 / 997** | 2000 kPa (295114) | 57, 49, 60, 53 | 72 | 187 / 74; paso 226 | sentinel_p, sentinel_gas, regime_p, regime_gas |
    | K (jb 285 s) | no | 155.3 / 128 | 128 kPa (285002) | 5, 0, 0, 0 | 0 | 0 / 0 | ninguno |
    | L (jb 295 s) | no | **300.0** / 237 | 237 kPa (295002) | 1, 0, 0, 0 | 0 | 3 / 0; paso 4 | sentinel_gas, regime_gas |

    > [fuente: python3 research/ws/WS-K11/scripts/h19.py; python3 research/ws/WS-K11/scripts/duracion.py campaigns/b1/k11_g_dt025_a236_f28 campaigns/b1/k11_h_dt025_fh280_otp campaigns/b1/k11_i_dt025_fh285_f28 campaigns/b1/k11_j_dt025_fh295_f28 campaigns/b1/k11_k_dt025_jb285 campaigns/b1/k11_l_dt025_jb295; python3 tests/integration/check_audit.py campaigns/b1/<brazo> | grep FAIL]

    - **Veredictos, por la letra:** H19 SOPORTADA {C-255}, H20 REFUTADA
      {C-256} (por L) y H21 SOPORTADA {C-257}. Cero `[CG] AVISO` en los
      seis brazos. {C-256} daba «p_max de 0.9-2 MPa» para los brazos con
      cambio de f28; lo corrige {C-259}: 0.37-2 MPa (B 365 kPa, F 592 kPa,
      G 895 kPa, I y J 2000 kPa).
    - **Dos umbrales distintos en este reporte.** «Pasos u ≥ 200 m/s o
      p ≥ 300 kPa» es el umbral del criterio de pico y de `duracion.py`
      (columna de la tabla). «Nivel centinela de B1» es u_gas_max ≥ 299 m/s
      o p_max ≥ 300 kPa, la métrica de las paradas (Resultado). Con el
      primero: G 11, F 8, B 18, I 101 y J 187 pasos; L 3 y `k11_dt025_s290` 2.
      Con el segundo: G 7, F 6, B 9, I 73 y J 120; L 2 y `k11_dt025_s290` 2.
      Con los dos hay eventos en brazos sin cambio (L y `k11_dt025_s290`),
      así que su presencia no separa; su número sí, con margen pequeño
      (≤ 3 frente a ≥ 8 con el primero; ≤ 2 frente a ≥ 6 con el segundo).
    - **G descarta los dos confusores de R5:** el binario escritor (G lo
      escribió el binario actual) y el salto de dt en el reinicio (G corre
      con dt_min = dt_max = 0.25 ms, como A, de cuyo final arranca: no
      hay salto de 1 a 0.25 ms). Su
      régimen ≥ 100 kPa ocupa el primer cuarto y luego cae, a diferencia de
      F y `k10b_dt025` (una trayectoria). La alternativa más sencilla es la
      dispersión entre trayectorias, no una propiedad del estado:
      `k11_dt025_tgfix`, el estado de F salvo `Tg_end`, se separa de
      `k10b_dt025` desde el paso 280027 y tampoco tiene sus tramos nolink de
      280135-280236 (paso 13, {C-273}).
    - **L es otra firma** (lectura NO pre-registrada, posterior a {C-256}
      y construida con los mismos brazos que separa; {C-259}{C-260}):
      300.0, 299.8 y 245.3 m/s en 295002-295004 (1 paso en U_GAS_MAX, 3
      ≥ 200 m/s), después ≤ 113 m/s, un solo paso ≥ 100 kPa y ninguna celda
      nolink. A 1 ms, `judge_jb_275` en 295 s alterna en ~160/110 m/s y
      44/22 kPa. Es un transitorio al acotar dt sin cambio de claves, sin
      diagnosticar ({C-261}). El criterio pre-registrado (máximo en los
      pasos 2-10) no separa las dos firmas, y tampoco el valor de u_gas_max
      ni el de p_max: `k11_dt025_s290`, sin cambio, llega a 450 kPa, dentro
      del rango 0.37-2 MPa de los brazos con cambio, y su último evento
      (u ≥ 200 m/s o p ≥ 300 kPa) cae en P0+93, dentro del rango P0+27 a
      P0+232 de esos brazos. Lo que separa en estos 14 brazos (la muestra
      de construcción de la firma; `k10b_dt025` y F cuentan por separado
      aunque coinciden a ≤ 1.1e-9 en los pasos 0-10) es:

      | brazo | cambio de f28 | pasos con nolink > 0 | pasos p_max ≥ 100 kPa | pasos con nolink y p_max < 100 kPa | max p_max sin nolink | max p_max |
      |---|---|---|---|---|---|---|
      | A, H | no | 0 | 0 | — | 15 kPa | 15 kPa |
      | C, E | no | 0 | 1 | — | 117 kPa | 117 kPa |
      | K | no | 0 | 5 | — | 128 kPa | 128 kPa |
      | L | no | 0 | 1 | — | 237 kPa | 237 kPa |
      | `k11_dt025_s290` | no | 0 | 5 | — | 450 kPa | 450 kPa |
      | D | no | 0 | 0 | — | 56 kPa | 56 kPa |
      | `k10b_dt025`, F | sí | 105 | 120 | 34 | 380 kPa | 592 kPa |
      | G | sí | 35 | 27 | 8 | 91 kPa | 895 kPa |
      | B | sí | 235 | 235 | 0 | — | 365 kPa |
      | I | sí | 57 | 142 | 1 | 634 kPa | 2000 kPa |
      | J | sí | 72 | 219 | 2 | 2000 kPa | 2000 kPa |

      En esta muestra nolink > 0 aparece solo en brazos con cambio; la
      persistencia ≥ 100 kPa separa con un margen pequeño (≤ 5 frente a
      ≥ 27 pasos). Con los 20 brazos (paso 13), nolink > 0 sigue
      implicando cambio, pero el cambio ya no implica nolink (P), y con
      1 ms `k7v4_long` tiene nolink 4.67 s después del cambio ({C-269}). Cruce con la presión
      (refutador R3): nolink no es un mero síntoma de p alta (450 kPa en
      `k11_dt025_s290` y 300 m/s en L sin nolink; 34 de los 105 pasos con
      nolink de F están por debajo de 100 kPa), pero p alta tampoco exige
      nolink (hasta 2 MPa sin nolink en J).
      > [fuente: ver el comando de {C-260}; python3 research/ws/WS-K11/scripts/duracion.py con los brazos de la tabla]
      > [fuente: python3 -c "import csv; r=[x for x in csv.DictReader(open('campaigns/b1/judge_jb_275/audit.csv')) if 294.9<=float(x['time'])<=295.1]; print([(x['step'],round(float(x['u_gas_max']),1),round(float(x['p_max'])/1e3,1)) for x in r])"]
    - **I y J llegan a P_HYDRO_CAP** (`sentinel_p`), más que cualquier
      brazo de 280 o 290 s.

13. **H22 y H23** ({C-263}, {C-264}), pre-registradas en el commit
    `8b2d95b` antes de correr (panel, ciclo 2, ronda 2: refutador R1 y R2,
    evidencia O1). Fijan la firma con umbral (≥ 1 paso con nolink y ≥ 20
    pasos con p_max ≥ 100 kPa, sin el paso 1; `h22.py`) y la prueban fuera
    de los 14 brazos con que se construyó.
    - **M, N, O (H22, predicen sin firma).** Config de A (claves apagadas)
      desde `judge_fh_275/eaf3d_00285000.h5`, `00290000.h5` y
      `00295000.h5`: los controles de I, B y J.
    - **P (H23, predice firma).** f28 encendida desde
      `judge_fh_275/eaf3d_00299999.h5` (300.0 s).
    - **Q (H23, predice sin firma).** Las claves de su escritor desde
      `judge_jb_275/eaf3d_00299999.h5`.

    | brazo | f28 | nolink | pasos ≥ 100 kPa | max p_max | max u_gas_max | firma |
    |---|---|---|---|---|---|---|
    | M (fh 285 s) | apagada | 0 | 0 | 15 kPa | 92.3 m/s | no |
    | N (fh 290 s) | apagada | 0 | 0 | 18 kPa | 68.9 m/s | no |
    | O (fh 295 s) | apagada | 0 | 0 | 20 kPa | 61.2 m/s | no |
    | P (fh 300 s) | se enciende | 0 | 0 | 96 kPa | 130.0 m/s | **no** |
    | Q (jb 300 s) | establecida | 0 | 0 | 95 kPa | 89.9 m/s | no |

    > [fuente: python3 research/ws/WS-K11/scripts/h22.py --todos (la opción imprime además la firma de los 14 brazos previos); python3 tests/integration/check_audit.py campaigns/b1/<brazo> | grep FAIL (ninguno)]

    - **Ventana real.** {C-263} y {C-264} fijan «t_final +0.06 s», pero las
      configs de M, N y O tienen t_final 285.061, 290.061 y 295.061 s, y P y
      Q arrancan en el paso 299999 con t_final 300.06 s: los cinco tienen
      61 ms (239 filas tras quitar el paso 1), igual que G, I, J, K y L,
      frente a 60 ms (235 filas) de A-F, H, `k10b_dt025` y `k11_dt025_s290`.
      Es una desviación del pre-registro, conservadora: M-Q dan 0 pasos
      con nolink y 0 con p_max ≥ 100 kPa en toda su ventana, y también en
      sus primeras 235 filas, así que no altera los veredictos.
      > [fuente: grep t_final campaigns/b1/k11_[mnopq]_*/config.dat; wc -l de cada audit.csv; h22.py imprime las filas]

    - **Veredictos, por la letra:** H22 SOPORTADA {C-265} y H23 REFUTADA
      {C-266}. Cero `[CG] AVISO` y ningún FAIL en los cinco brazos. H22 era
      de bajo riesgo: la columna nolink con f28 apagada solo se ha medido en
      ventanas de 60 ms (A, H, M, N, O) y nunca ha dado nolink. La prueba
      exigente fuera de muestra fue H23.
    - **`k11_dt025_tgfix` (H12), el brazo de 0.25 ms que `h22.py --todos`
      omite** ({C-273}). Config de `k10b_dt025` (las dos claves
      encendidas) desde la copia del estado fh de 280 s con `Tg_end` =
      `T_gas`: un brazo con cambio, el vigésimo de 0.25 ms. Da la firma.
      Coincide con `k10b_dt025` hasta el paso 280026 (|Δp/p| > 1 % desde
      280027).

      | brazo | nolink por cuartos | pasos ≥ 100 kPa por cuartos | media p_max por cuartos [kPa] | media \|Δp\| por cuartos [kPa] | 20 últimas filas |
      |---|---|---|---|---|---|
      | `k10b_dt025` (≈ F) | 22, 0, 24, 59 | 31, 21, 32, 36 | 137.4, 104.2, 123.6, 106.8 | 73.4, 52.1, 55.2, 30.6 | 104-156 kPa, nolink 1-4 |
      | `k11_dt025_tgfix` | 22, 0, 0, 0 (280002-280023) | 31, 27, 26, 19 | 138.0, 105.1, 99.5, 83.9 | 73.7, 50.3, 38.1, 17.8 | 42-104 kPa, nolink 0 |

      > [fuente: python3 -c "import csv,statistics as s; [print(d,[sum(float(x['m_gas_cells_nolink'])>0 for x in q) for q in Q],[sum(float(x['p_max'])>=1e5 for x in q) for q in Q],[round(s.mean(float(x['p_max']) for x in q)/1e3,1) for q in Q],[round(s.mean(abs(float(b['p_max'])-float(a['p_max'])) for a,b in zip(q,q[1:]))/1e3,1) for q in Q],round(min(float(x['p_max']) for x in r[-20:])/1e3),round(max(float(x['p_max']) for x in r[-20:])/1e3)) for d in ('k10b_dt025','k11_dt025_tgfix') for r in [[x for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])>280001]] for Q in [[r[i*len(r)//4:(i+1)*len(r)//4] for i in range(4)]]]"]

      Consecuencias: (a) con 20 brazos nolink > 0 sigue implicando cambio
      de f28; (b) la lectura «transitorio que decae hacia el nivel de f28
      establecida» (Resultado) tiene un dato COMPATIBLE en el estado fh de
      280 s: tgfix acaba en ~84 kPa de media con |Δp| de 18 kPa, cerca de C
      (80 / 11 kPa), pero compara un estado fh con uno jb y su casi gemelo
      `k10b_dt025` acaba en 106.8 kPa con nolink ({C-277}); (c) se retira,
      para F, que su final con nolink haga plausible la edad del cambio,
      porque su casi gemelo no lo tiene; B, sin gemelo, acaba con nolink
      ({C-277}); (d) F frente a tgfix, y G frente a F, se leen como
      dispersión entre trayectorias, sensibles a perturbaciones mínimas,
      no como una propiedad del estado, salvo que se pre-registre otra
      cosa; (e) el máximo de `regime_p` de `k10b_dt025` (591.6 kPa,
      280161) depende de la trayectoria: el de tgfix es 460.9 kPa, el pico
      del arranque.
    - **P:** al encender f28 en 300 s p_max alterna (86/54 kPa en los
      primeros pasos) y la media por cuartos baja de 43.8 a 26.4 kPa. Es un
      transitorio menor que decae, sin nolink. A 1 ms, `judge_fh_275` llega
      a 300 s con u_gas_max subiendo de 56 a 112 m/s en 299.9-300.0 s.
      Por qué este estado no responde como los de 280-295 s no está
      medido.
    - **Con H22**, los estados fh de 280, 285 y 295 s tienen su par de una
      sola clave (A/F, M/I y O/J): sin f28 no hay firma y con f28 sí. En
      290 s el par N/B cambia DOS claves (B enciende además la presión
      total), así que f28 sola en 290 s no está probada; que la presión
      total no es necesaria solo está medido en 280 s (F, {C-249}) {C-268}.

## Resultado

Se muestran los pasos 2-10 (el criterio de H13) y el máximo de toda la
ventana, sin el paso 1:

| banco | max u_gas_max, pasos 2-10 | max p_max, pasos 2-10 | max p_max de la ventana (paso; u_gas_max) | pasos con p_max ≥ 100 kPa | FAIL |
|---|---|---|---|---|---|
| `k11_dt025_s290` (0.25 ms, desde 290 s) | 71.6 m/s | 79 kPa | 450.0 kPa (290093; 128.6 m/s); 344.3 kPa (290074) | 5/235 | ninguno (`regime_p` PASS con 4.500e5 de 5e5) |
| `k11_dt05_s290` (0.5 ms, desde 290 s) | 80.1 m/s | 71 kPa | 70.6 kPa (290004; 80.1 m/s) | 0/117 | ninguno |
| `k11_mo20_s290` (1 ms, desde 290 s, control) | 124 m/s | 55 kPa | 70.0 kPa (290011; 121.5 m/s) | 0/58 | ninguno |
| `k10b_dt025` (0.25 ms, desde 280 s) | 300.0 m/s | 461 kPa | 591.6 kPa (280161; 113.2 m/s) | 120/235 | sentinel_gas, regime_p, regime_gas |

> [fuente: python3 research/ws/WS-K11/scripts/medir_centinela.py --inicio 290000 campaigns/b1/k11_mo20_s290 campaigns/b1/k11_dt05_s290 campaigns/b1/k11_dt025_s290; python3 tests/integration/check_audit.py campaigns/b1/k11_dt025_s290 | grep -E 'regime|sentinel'; python3 tests/integration/check_audit.py campaigns/b1/k11_dt05_s290 | grep regime_p; máximo de la ventana: python3 -c "import csv; [print(d, max(((float(x['p_max']),x['step'],float(x['u_gas_max'])) for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])>p0+1))) for d,p0 in (('k11_dt025_s290',290000),('k11_dt05_s290',290000),('k11_mo20_s290',290000),('k10b_dt025',280000))]"]

- **H13 SOPORTADA por la letra** {C-227}: menos de 200 m/s y menos de 300 kPa
  en los pasos 290002-290010, sin avisos del CG. Las tres identidades de masa
  del gas y la descomposición de WS-K10 pasan.
- **Desde 280 s, con 0.25 ms, no es un transitorio de 2-3 pasos** {C-236}.
  En `k10b_dt025`, los pasos con p_max ≥ 100 kPa por cuartos de la ventana
  son 31, 21, 32 y 36 (cuartos de 58, 59, 59 y 59 filas, los de `h15.py`;
  con 58, 58, 58 y 61 filas también da 36) {C-240}. u_gas_max también pasa
  de 200 m/s en los pasos 280007 (229.1), 280011 (282.8), 280041 (252.8) y
  280137 (229.4). Con 0.5 ms el exceso sí decae (8, 1, 2 y 0 de 29, 29, 29 y
  30 filas), y con 1 ms no aparece. Con 0.25 ms el régimen se mantiene
  ≥ 100 kPa los 58 ms de la ventana, acompañado de celdas sin cara enlazada
  que no aparecen con 0.5 ni 1 ms (paso 9).
- **Si ese régimen decae, sin decidir** {C-250}. El conteo de pasos
  ≥ 100 kPa no baja, pero las medias por cuartos (mismos cuartos que
  `h15.py`, sin el paso 1) sí, en los brazos con cambio de f28:

  | banco | f28 | p_max paso 0 [kPa] | media p_max por cuartos [kPa] | media \|Δp\| por cuartos [kPa] |
  |---|---|---|---|---|
  | B (`k11_b_dt025_fh290_on`) | cambio, fh 290 s | 15.6 | 244.3, 190.8, 148.4, 137.6 | 34.2, 30.2, 23.8, 24.3 |
  | `k10b_dt025` (F igual salvo el último decimal) | cambio, fh 280 s | 14.8 | 137.4, 104.2, 123.6, 106.8 | 73.4, 52.1, 55.2, 30.6 |
  | C (= E) | establecida, jb 280 s | 28.0 | 76.3, 79.1, 79.2, 80.3 | 17.6, 11.5, 11.4, 11.4 |
  | `k11_dt025_s290` | establecida, otp 290 s | 27.0 | 51.0, 58.7, 36.0, 35.0 | 28.8, 43.6, 16.9, 16.1 |
  | D (`k11_d_dt025_s300`) | establecida, otp 300 s | 23.9 | 37.8, 32.8, 31.0, 28.2 | 16.3, 6.4, 2.1, 5.6 |
  | A (`k11_a_dt025_s280_off`) | apagada, fh 280 s | 14.8 | 14.5, 14.5, 14.4, 14.4 | 0.0, 0.0, 0.0, 0.0 |

  > [fuente: python3 -c "import csv,statistics as s; [print(d,[round(s.mean(float(x['p_max']) for x in q)/1e3,1) for q in Q],[round(s.mean(abs(float(b['p_max'])-float(a['p_max'])) for a,b in zip(q,q[1:]))/1e3,1) for q in Q]) for d,p0 in (('k11_b_dt025_fh290_on',290001),('k10b_dt025',280001),('k11_c_dt025_jb280',280001),('k11_dt025_s290',290001),('k11_d_dt025_s300',300001),('k11_a_dt025_s280_off',280001)) for r in [[x for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])>p0]] for Q in [[r[i*len(r)//4:(i+1)*len(r)//4] for i in range(4)]]]"; F y E dan las mismas cifras que `k10b_dt025` y C salvo en el último decimal]

  Filas añadidas por el panel ({C-273}, mismos cuartos, sin el paso 1;
  K, L, Q, M, N y O con 239 filas):

  | banco | f28 | media p_max por cuartos [kPa] | media \|Δp\| por cuartos [kPa] |
  |---|---|---|---|
  | `k11_dt025_tgfix` | cambio, fh 280 s (`Tg_end` = `T_gas`) | 138.0, 105.1, 99.5, 83.9 | 73.7, 50.3, 38.1, 17.8 |
  | K (`k11_k_dt025_jb285`) | establecida, jb 285 s | 71.1, 66.1, 68.7, 69.2 | 20.4, 15.8, 20.8, 18.8 |
  | L (`k11_l_dt025_jb295`) | establecida, jb 295 s | 41.8, 31.3, 30.9, 30.7 | 9.1, 8.0, 8.9, 8.7 |
  | Q (`k11_q_dt025_jb300`) | establecida, jb 300 s | 51.7, 38.6, 36.9, 34.1 | 27.1, 22.0, 20.5, 22.0 |
  | H (`k11_h_dt025_fh280_otp`) | apagada, fh 280 s | 14.5, 14.5, 14.4, 14.4 | 0.0, 0.0, 0.0, 0.0 |
  | M (`k11_m_dt025_fh285_off`) | apagada, fh 285 s | 14.4, 14.1, 14.2, 14.1 | 0.0, 0.0, 0.0, 0.0 |
  | N (`k11_n_dt025_fh290_off`) | apagada, fh 290 s | 17.1, 15.5, 14.6, 14.6 | 0.0, 0.0, 0.0, 0.0 |
  | O (`k11_o_dt025_fh295_off`) | apagada, fh 295 s | 17.6, 15.0, 14.7, 14.8 | 0.1, 0.0, 0.0, 0.0 |

  > [fuente: el comando de la tabla anterior con estos brazos y p0 = primera fila de su audit.csv (filas con step > p0+1)]

  Dos lecturas que estos 60 ms no separan en B y `k10b_dt025`: (a) un
  régimen trabado tras el cambio; (b) un transitorio del cambio que decae,
  en decenas o cientos de ms, hacia el nivel de f28 establecida con
  0.25 ms (~80 kPa en C y E). Las dos predicen casi todo sobre 100 kPa en
  la ventana con medias que bajan. Para el estado fh de 280 s, (b) tiene
  un dato compatible: `k11_dt025_tgfix` baja a 83.9 kPa de media y
  17.8 kPa de |Δp| en el último cuarto, sin nolink desde 280024
  ({C-273}); que `k10b_dt025` acabe en 106.8 kPa con nolink se lee como
  dispersión entre trayectorias, y la cercanía al nivel de C (un estado
  jb) puede ser casual ({C-277}). En B, prolongar a ≥ 300 ms desde su `eaf3d_00290236.h5`
  seguiría decidiéndolo; no se ha corrido. La tabla muestra además que,
  con 0.25 ms, los brazos jb/otp con f28 establecida no dan un estado
  tranquilo (C y E suben de 28 a ~80 kPa y alternan ~75/87 kPa hasta el
  final; K 66-71, L 31-42, Q 34-52 kPa) y los fh con las claves apagadas
  (A, H, M, N, O) quedan planos en 14-18 kPa. f28 y linaje van juntos (no
  hay brazo jb/otp con f28 apagada), así que no se separa si ese nivel lo
  pone f28 o el estado.
- **Desde 290 s también hay picos de presión con 0.25 ms** {C-236}{C-230}.
  - Sin cambio de claves, `k11_dt025_s290` llega a 450 kPa en el paso 290093:
    el 90 % del límite de `regime_p` y del orden de los 461 kPa del paso
    280003. Con 0.5 y 1 ms, desde el mismo snapshot, no pasa de 71 kPa.
  - Desde 290 s desaparecen el pico de los pasos 2-3, u_gas = 300 m/s y la
    frecuencia del régimen alto (5/235 frente a 120/235). No desaparecen los
    episodios de presión de cientos de kPa con 0.25 ms.
  - La amplificación al bajar dt tampoco es exclusiva del snapshot de 280 s:
    desde 290 s, el máximo de p_max en los pasos 2-10 es 55, 71 y 79 kPa con
    1, 0.5 y 0.25 ms.
  - Estos picos no están diagnosticados ({C-237}).
- **Consecuencia para las comparaciones desde 280 s (K5-K8, K10)** {C-227}{C-236}. Toda comparación de config o
  de dt desde `judge_otp_280/eaf3d_00280000.h5` lleva el pico de reinicio,
  también el arranque del propio `judge_otp_280`. Para comparar, lo que queda
  en pie es reiniciar desde un snapshot escrito con las mismas claves y
  con f28 establecida ≥ 5 s (el mínimo probado sin firma, jb 280 s): por
  la continuidad del reinicio, un snapshot escrito con las mismas claves
  60 ms después del cambio, como el final de B, arrastraría la firma. Con
  las claves apagadas, H15 ({C-239}) lo muestra: el snapshot de 280 s
  (escrito el 20-oct) no da pico con el binario actual. Con f28 ya
  establecida lo respaldan `k11_dt025_s290` (fase tranquila, {C-241}), el
  brazo D (300 s) y los brazos C y E (jb 280 s, fase activa; paso 10 y
  11): cuatro snapshots, una trayectoria cada uno, no una prueba general.
  «Sin pico» no es «tranquilo»: con 0.25 ms el brazo C sube a 76-80 kPa de
  media con |Δp| de 11 kPa durante toda la ventana (tabla de arriba). Y con
  0.25 ms ningún reinicio probado da un banco limpio, tampoco sin cambio de
  claves: L (jb 295 s) toca U_GAS_MAX en 295002 y `k11_dt025_s290` llega a
  450 kPa en 290093, los dos sin diagnosticar ({C-261}, {C-237}). La
  recomendación vale para evitar el pico del cambio de f28, no para tener
  un banco de 0.25 ms sin centinelas. Y si valiera la lectura (ii) del
  titular (el cambio con 0.25 ms dispara antes el mecanismo de las
  paradas de B1, {C-269}; los datos no la apoyan, {C-275}), evitar el
  cambio quitaría el disparador de la ventana sin explicar el mecanismo.
- **Bancos afectados por el pico de reinicio** {C-251}. Por su
  `restart_file`, arrancan de `judge_otp_280/eaf3d_00280000.h5` con las dos
  claves encendidas (por tanto con el cambio de f28) y su `audit.csv`
  empieza en el paso 280000, así que su ventana incluye los pasos
  280001-280031 del asentamiento a 1 ms:
  - WS-K5 y WS-K6: `k5_base`, `k5_mo20`, `k6_base`, `k6_mo20` y las sondas
    `sonda_gc_*`, `sonda_gm_*`, `sonda_gs_mo20` (60 pasos, 280000-280059).
  - WS-K7: `k7_*`, `k7v3_*`, `k7v4_*`, `k7v5_*` (60 pasos), `k7v5_mo20_1k`
    (1000), `k7v4_long` (5500) y `bench_w280_*` (300).
  - WS-K8: `k8_*` y `k8s_*` (60 pasos; `k8s_dt05`, 119 con 0.5 ms).
  - WS-K10: `k10_*` y `k10b_*`.
  - Sin workstream en `research/ws/`: `judge_e1w280_n14`, `judge_e1w280_n15`
    (5500 pasos) y `diag_g284a` (4330).
  - Desde `judge_fh_275/eaf3d_00280000.h5` (campos primarios y `/restart`
    idénticos a los del archivo de `judge_otp_280`; Incertidumbre) con f28
    encendida ({C-270}): `scrfh_b`, `scrfh_bfrz`, `m202_280`, `m203_280`,
    `m21f1_280`, `m21f1fix_280` (solo f28) y `otp_280`, `otp2_280` (las
    dos claves), además del propio `judge_otp_280`. Ventanas de 1599 filas
    (280001-281599, 1 ms). u_gas_max en 280002: 215.0 m/s en seis de
    ellos, 189.8 en `scrfh_b` y 136.7 en `m202_280` (que llega a 300 m/s en
    280003). Filas con u ≥ 200 m/s o p ≥ 300 kPa en 280001-280031: 0-1 en
    siete de los ocho y 9 en `m202_280`. El asentamiento de 13-31 pasos es
    el 0.8-1.9 % de esas ventanas.
  - Decisiones registradas que se midieron en esas ventanas ({C-270}):
    - **Adopción de f28** (`2f0529b`, «centinela 2.6 % → 0 % en
      280-281.6 s»): las 42 filas de nivel centinela de `scrfh_base` (sin
      f28, 2.63 %) están en 281.461-281.502 s, lejos del arranque, y los
      bancos con f28 (`scrfh_b`, `m21f1_280`, `otp_280`) dan 0 filas,
      también en el arranque. El pico de reinicio no contamina esa cifra
      (una trayectoria por banco).
    - **M20-2** («separar fsat del hueco congelado empeora el pozo de
      281 s; no repetir», `.claude/rules/acople-pv.md:566-568`, commit
      `0398a99`, bancos `m202_*`): la comparación de 156 frente a 94 kPa
      es de p_max en el paso 280003 en los dos bancos (`m202_280` frente a
      `m203_280`/`scrfh_bfrz`), es decir, el pico del reinicio; 4 de las 5
      filas de nivel centinela de `m202_280` caen en 280003-280029 y la
      quinta en 280033. Sin los pasos 280001-280031, `m202_280` sigue
      peor: p_max llega a 66.1 frente a 51.3 kPa y queda 1 fila frente a
      0. Pero los hermanos desde el mismo estado dan 48.3-62.6 kPa
      (`otp2_280` 62.6, `otp_280` 59.5) y `scrfh_b` llega a 287.7 m/s
      ({C-276}): con una trayectoria por banco, 66.1 kPa y 1 fila quedan
      en el borde de esa dispersión, el mismo criterio con el que se juzga
      arriba «1 frente a 15» para f28. El commit cita además una segunda
      ventana, B1 255-258 s, neutra. Así que el dato fuera del arranque
      ni apoya ni refuta M20-2: la prohibición descansa en esa ventana
      neutra y en la cifra 156 frente a 94 kPa, del pico de reinicio.
      Decidirlo pide un juez estadístico de `m202` frente a `m203` desde
      un estado sin cambio de claves (fuera de WS-K11; {C-276}).
  > [fuente: cd campaigns/b1 && grep -l 'judge_fh_275/eaf3d_00280000.h5' */config.dat; grep pc_transport_f28 de cada uno; python3 -c "import csv; [print(d, [(x['step'],round(float(x['u_gas_max']),1),round(float(x['p_max'])/1e3,1)) for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])>280000 and (float(x['u_gas_max'])>=299 or float(x['p_max'])>=3e5)]) for d in ('scrfh_base','scrfh_b','m21f1_280','otp_280','m202_280','m203_280','scrfh_bfrz')]"; git show 0398a99]
  Los de 60 pasos miden sobre la ventana entera (sumas de la ventana, p. ej.
  WS-K5 «59 pasos en la ventana de 280 s», WS-K8 «igualdad de sumas en esta
  ventana»), así que más de la mitad de sus pasos cae en el asentamiento.
  Cuánto cambia eso cada conclusión no está evaluado aquí (Incertidumbre).
  > [fuente: cd campaigns/b1 && grep -l 'judge_otp_280/eaf3d_00280000.h5' */config.dat; grep -E 'pc_transport_f28|pc_outlet_total' de cada config.dat; primera y última fila de cada audit.csv; grep -l del prefijo en research/ws/*/report.md]
- **La config de B1 desde 290 s** ({C-233}, lectura no pre-registrada de
  WS-K10). `k11_base_s290`, con 5 externas y CG 20, da un u_gas_max máximo
  de 107 m/s y un p_max máximo de 27 kPa, y no falla `regime_gas`. Sigue
  fallando `energy_balance`. Su run.log tiene 1 `[CG] AVISO` (20
  iteraciones sin converger, res 4.198e-2), esperable con CG 20, pero los
  bancos limpios exigen cero. LECTURA, con el mismo alcance que H13: los
  215 m/s de `k10_base` y `k8_base` en el paso 280002 son el mismo pico de
  reinicio desde 280 s, que H15 atribuye al cambio de claves ({C-239}).
  > [fuente: python3 tests/integration/check_audit.py campaigns/b1/k11_base_s290 | grep FAIL; grep -c '\[CG\] AVISO' campaigns/b1/k11_base_s290/run.log; columnas u_gas_max y p_max de campaigns/b1/k11_base_s290/audit.csv]
- **Uso de estos bancos en WS-K10.** Los bancos desde 290 s sirvieron allí
  para la comparación limpia entre dt (H14, {C-231}{C-232}). Esa comparación
  incluye los picos de presión de 0.25 ms citados arriba.
- **El régimen de los jueces con f28 entre 275 y 295 s** {C-241}. Media de
  p_max y media de |Δp_max| entre filas consecutivas por segundo, en kPa.
  Para comparar las tres corridas se usan filas cada 5 pasos (5 ms), la
  cadencia de auditoría de `judge_jb_275` y `judge_fh_275`; en
  `judge_otp_280`, con todas sus filas, las cifras cambian poco (p. ej.
  280.0-280.1 s: 38.3 / 18.4 con todas las filas frente a 38.1 / 21.9 cada
  5 pasos).

  | s | `judge_otp_280` (f28 y outlet desde 280 s) | `judge_jb_275` (solo f28 desde 275 s) | `judge_fh_275` (claves apagadas) |
  |---|---|---|---|
  | 275-280 | — | 30.3 / 7.2 | 16.8 / 0.7 |
  | 280-281 | 34.1 / 18.9 | 33.9 / 11.7 | 14.9 / 0.0 |
  | 281-282 | 30.6 / 10.6 | 36.4 / 7.3 | 32.5 / 1.5 |
  | 282-283 | 30.8 / 9.8 | 39.1 / 16.5 | 17.1 / 1.0 |
  | 283-284 | 35.2 / 18.3 | 41.4 / 4.1 | 20.8 / 6.1 |
  | 284-285 | 55.7 / 14.7 | 45.2 / 14.8 | 25.3 / 8.6 |
  | 285-286 | 56.8 / 16.8 | 38.5 / 12.2 | 15.1 / 0.3 |
  | 286-287 | 56.8 / 18.8 | 42.8 / 11.3 | 15.2 / 0.0 |
  | 287-288 | 53.5 / 18.2 | 39.1 / 17.2 | 15.4 / 0.5 |
  | 288-289 | 49.1 / 17.2 | 47.0 / 15.0 | 15.4 / 0.8 |
  | 289-290 | 35.2 / 5.2 | 41.8 / 11.7 | 15.5 / 0.6 |
  | 290-291 | 27.7 / 7.4 | 26.7 / 7.0 | 15.2 / 0.2 |
  | 291-292 | 27.3 / 4.8 | 22.9 / 2.3 | 16.6 / 0.3 |
  | 292-293 | 24.2 / 3.3 | 22.1 / 2.2 | 16.5 / 0.9 |
  | 293-294 | 31.9 / 7.9 | 25.9 / 7.4 | 18.6 / 3.4 |
  | 294-295 | 45.1 / 19.5 | 33.0 / 16.1 | 17.0 / 0.9 |

  > [fuente: python3 -c "import csv,statistics as s; [print(d,[(round(s.mean(p for p,_ in v)/1e3,1),round(s.mean(q for _,q in v)/1e3,1)) for v in [[(b[2],abs(b[2]-a[2])) for a,b in zip(r,r[1:]) if b[0]-a[0]==5 and w<=b[1]<w+1] for w in range(275,295)] if v]) for d in ('judge_otp_280','judge_jb_275','judge_fh_275') for r in [[(int(x['step']),float(x['time']),float(x['p_max'])) for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])%5==0]]]"; `judge_jb_275` no tiene la clave outlet porque su run.log (21-oct, 10:27) es anterior a `8f568fc`. La fila 275-280 s, el tramo 280.0-280.1 s (cada 5 pasos y con todas las filas) y el |Δp| de 290.0-290.1 s con todas las filas: python3 -c "import csv,statistics as s; f=lambda d,c,a,b: [(round(s.mean(p for p,_ in v)/1e3,1),round(s.mean(q for _,q in v)/1e3,1)) for r in [[(int(x['step']),float(x['time']),float(x['p_max'])) for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])%c==0]] for v in [[(y[2],abs(y[2]-x[2])) for x,y in zip(r,r[1:]) if y[0]-x[0]==c and a<=y[1]<b]]]; print(f('judge_jb_275',5,275,280), f('judge_fh_275',5,275,280), f('judge_otp_280',5,280,280.1), f('judge_otp_280',1,280,280.1), f('judge_otp_280',1,290,290.1))" (media p_max / media |Δp|)]

  - Los dos linajes con f28 encendida están en 22-57 kPa con |Δp| de 2-20 kPa
    en los 15-20 s medidos; después no hay dato {C-242}. En 280-295 s el
    linaje apagado está en 15-19 kPa con |Δp| ≤ 1 kPa, salvo en 281-285 s
    (hasta 32.5 kPa de media y 8.6 kPa de |Δp|) y en 293-294 s (3.4 kPa).
  - `judge_jb_275`, que encendió f28 en 275 s, ya está en ese régimen entre
    275 y 280 s, antes del instante de 280 s: el régimen no es exclusivo
    del reinicio de 280 s ni de `pc_outlet_total_pressure`.
  - Los dos linajes con f28 empezaron con un cambio de claves, así que estos
    datos no distinguen un residuo largo del cambio de la física con f28
    encendida. En cualquiera de los dos casos, el régimen dura segundos, no
    20-30 pasos.
  - **Con la métrica de las paradas de B1 el orden cambia** {C-251}.
    Filas de nivel centinela de B1 (u_gas_max ≥ 299 m/s o p_max ≥ 300 kPa; no confundir con «u ≥ 200 m/s o p ≥ 300 kPa» del paso 12), cada
    5 pasos, en 280-295 s: `judge_fh_275` (claves apagadas) 15,
    `judge_jb_275` (solo f28) 1 (288.68 s) y `judge_otp_280` (juez de B1) 26.
    El linaje apagado da u_gas = 300 m/s en 281.47-281.50 s y 304 y 578 kPa
    en 284.37 y 284.39 s, junto a la parada de B1 de 284.3 s; las filas de
    `judge_otp_280` se agrupan en 284.35-285.89 s y en 294.10 s. Lectura
    alternativa que estos datos no descartan: el evento de 284 s es física
    del estado (chatarra compactada, `.claude/rules/acople-pv.md`) que
    aparece con f28 o sin ella. Por CONTEO, el régimen alto por media de
    p_max y |Δp| no explica las paradas de B1. Pero `k7v4_long` (misma
    config y mismo arranque que `judge_otp_280`, otra trayectoria, con la
    columna nolink; su primera fila de nivel centinela, paso 284340
    (284.341 s), cae junto a la de `judge_otp_280`, 284.35 s) tiene nolink
    en su episodio de 284.3-285.4 s: desde el paso 284669 (284.670 s),
    0.33 s después de su primera fila de nivel centinela, y en 86 de sus
    96 filas de nivel centinela ({C-269}, {C-272}, {C-274}). Pero el
    patrón no es el del reinicio con 0.25 ms: 360 celdas fijas frente a
    1-16, y nolink entra después de u_gas, no desde el principio
    ({C-275}).
    `judge_fh_275` y `judge_jb_275` no tienen esa columna, así que no se
    sabe si el evento del linaje apagado la lleva. Otra trayectoria con f28
    apagada, `judge_e2_275` (mismo estado de 275 s que fh, sin columna
    nolink), tiene 28 filas de nivel centinela en 282-287 s (cada 5
    pasos); y el cambio de `judge_jb_275` en 275 s a 1 ms dejó 1 fila en
    275-280 s (277.506 s) ({C-274}). Los dos datos van contra que el
    cambio contamine el juez durante segundos y a favor de que la familia
    de 284 s existe sin cambio. Que el cambio de f28 con 0.25 ms y las
    paradas de B1 sean el mismo mecanismo queda abierto, con la hipótesis
    de trabajo de que no lo son ({C-275}; Incertidumbre).
    > [fuente: python3 -c "import csv; [print(d, len(e), e) for d in ('judge_fh_275','judge_jb_275','judge_otp_280') for e in [[(x['step'],float(x['u_gas_max']),round(float(x['p_max'])/1e3,1)) for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])%5==0 and 280<=float(x['time'])<295 and (float(x['u_gas_max'])>=299 or float(x['p_max'])>=3e5)]]]"]
  - **Contexto de la adopción de f28** {C-251}. f28 se adoptó en `2f0529b`
    (comentario de `src/mod_config_3d.f90:110`, «centinela 2.6 % → 0 % en
    280-281.6 s») con un reinicio que la encendía sobre el estado fh de
    280 s y una ventana de 1.6 s: el mismo tipo de arranque que este
    reporte muestra que mete artefactos. Esa cifra concreta no la
    contamina el arranque: las 42 filas de `scrfh_base` caen en
    281.46-281.50 s y los bancos con f28 dan 0 filas, también en
    280001-280031 ({C-270}; lista de bancos arriba). La evidencia de más largo plazo
    sin cambio de claves dentro de la ventana (jb cambió en 275 s, 5 s
    antes) es la de arriba: 1 fila de nivel
    centinela de B1 en `judge_jb_275` frente a 15 en `judge_fh_275` en
    280-295 s. Con una trayectoria por linaje, y pasados ~280 s la dinámica
    es caótica (`.claude/rules/acople-pv.md`), ese conteo no contradice f28
    pero tampoco la apoya; lo decidiría un juez estadístico (varias
    trayectorias, p. ej. 12, 14 y 15 ranks desde jb y fh en 280 s), no
    corrido {C-260}.
  - El snapshot de 290 s de `judge_otp_280`, base de los bancos
    `k11_*_s290`, cae en su fase tranquila de 290-293 s (24-28 kPa y
    |Δp| de 3-7 kPa, frente a 30-57 kPa y 5-19 kPa en 280-290 s; 3.7 kPa de
    |Δp| en 290.0-290.1 s con todas las filas) {C-242}. Esos bancos no son
    representativos del régimen de 280-289 s.

## Incertidumbre

- **Disparador identificado en 280 s, mecanismo abierto** ({C-249},
  {C-255}, {C-257}). En 280 s, con control de una sola clave (A frente a
  F, H, G frente a A), encender f28 sobre un estado escrito sin ella
  dispara el pico con 0.25 ms. Por qué ese cambio produce celdas sin cara
  enlazada y un régimen que sigue ≥ 100 kPa en la ventana no está medido.
  Tampoco por qué en G cae tras el primer cuarto y en F no; la
  alternativa más sencilla es la dispersión entre trayectorias (F frente
  a `k11_dt025_tgfix`, que solo difiere en `Tg_end` y no tiene los tramos
  nolink de F tras 280023; {C-273}).
- **El transitorio de acotar dt sin cambio de claves** (L, {C-256},
  {C-259}) llega a U_GAS_MAX en un paso (300.0 m/s en 295002; 299.8 y
  245.3 m/s en 295003-295004). No está diagnosticado; cuenta como
  centinela disparada sin causa medida. Queda como pendiente en {C-261},
  junto a los 450 kPa de `k11_dt025_s290` ({C-237}); discriminador
  propuesto, sin correr: sonda PROBE-P en esos pasos.
- **Si el régimen tras el cambio decae** {C-250}. En 60 ms se mantiene
  ≥ 100 kPa, pero en B la media de p_max baja un 44 % y en `k10b_dt025` la
  de |Δp| de 73 a 31 kPa (Resultado). Un transitorio que decae en decenas o
  cientos de ms hacia ~80 kPa (nivel de C y E) es compatible con los datos,
  y en el estado fh de 280 s `k11_dt025_tgfix` ya lo muestra (83.9 kPa y
  17.8 kPa de |Δp| en el último cuarto, sin nolink desde 280024; {C-273}).
  Pendiente para B: prolongarlo a ≥ 300 ms desde `eaf3d_00290236.h5` (no
  corrido; corresponde al coordinador).
- **«Cambio de f28» frente a «linaje sin f28».** El contraste de H16/H17
  frente a H18 compara dos estados de 280 s que parten del MISMO estado de
  275 s: `judge_jb_275` es el linaje fh con f28 encendida desde 275 s (los
  dos reinician de `judge_rampbelow/eaf3d_00275000.h5`; sus
  `eaf3d_00275000.h5` son idénticos, |Δ| = 0 en α, p, T_gas y `/restart`, y
  sus configs solo difieren en f28) {C-251}. En 5 s los estados divergen
  mucho: a 280 s |Δα_s| llega a 0.77, |Δα_g| a 0.64, y la presión va de
  −0.09 a 14.8 kPa en fh y de −12.8 a 28.0 kPa en jb.
  > [fuente: python3 -c "import h5py,numpy as np; a=h5py.File('campaigns/b1/judge_otp_280/eaf3d_00280000.h5','r'); b=h5py.File('campaigns/b1/judge_jb_275/eaf3d_00280000.h5','r'); [print(k, np.abs(np.array(a['fields/'+k])-np.array(b['fields/'+k])).max()) for k in ('alpha_solid','alpha_gas','alpha_liquid')]; [print(np.array(f['fields/pressure']).min(), np.array(f['fields/pressure']).max()) for f in (a,b)]"]

  > [fuente, solo lectura: python3 -c "import h5py,numpy as np; a=h5py.File('campaigns/b1/judge_fh_275/eaf3d_00275000.h5','r'); b=h5py.File('campaigns/b1/judge_jb_275/eaf3d_00275000.h5','r'); [print(k, np.abs(np.array(a['fields/'+k])-np.array(b['fields/'+k])).max()) for k in ('alpha_solid','alpha_gas','alpha_liquid','pressure','T_gas')]"; grep restart_file campaigns/b1/judge_fh_275/config.dat campaigns/b1/judge_jb_275/config.dat; diff campaigns/b1/judge_fh_275/config.dat campaigns/b1/judge_jb_275/config.dat]

  Dentro de cada estado el contraste sí es de una sola clave (A frente a F;
  C frente a E). Y los estados con f28 establecida que no dan pico son
  TODOS del linaje fh: jb (f28 desde 275 s) y otp (f28 y presión total
  desde 280 s). Hay dos pares en el mismo instante: fh 280 s (F, pico)
  frente a jb 280 s (C, sin pico), y fh 290 s (B, pico) frente a otp 290 s
  (`k11_dt025_s290`, sin pico). Eso refuerza que el contraste lo pone la
  historia de f28 y no un estado arbitrario. Queda abierto:
  - **El binario que escribió el estado**: confusor de {C-251}, descartado
    por H19 ({C-255}). G enciende f28 sobre un estado escrito por el
    binario actual con las claves apagadas y da el pico, sin acotar dt.
  - **Instantes, y la generalidad que H20 no probó.** H20 ({C-253})
    quedó REFUTADA por L ({C-256}). La separación por firma ({C-260}) se
    construyó después con los mismos 14 brazos; H22 y H23 la pusieron a
    prueba fuera de esa muestra (paso 13). Necesidad: no contradicha por
    H22 ({C-265}), una predicción de bajo riesgo porque la columna nolink
    con f28 apagada solo se ha medido en ventanas de 60 ms; alcance de
    0.25 ms y 60 ms ({C-269}). Suficiencia: refutada en fh 300 s (H23,
    {C-266}), la única prueba exigente fuera de muestra. Queda como resultado: en los
    estados probados el cambio de f28 es necesario y no suficiente para la
    firma. Una trayectoria por brazo.
  - **Un solo linaje con cambio** ({C-271}). Todos los brazos con cambio
    que dan la firma (F/`k10b_dt025`, G, I, B, J) salen de UNA trayectoria,
    `judge_fh_275`, y G es el estado de A 60 ms después. «5 de 6 estados
    fh» es una trayectoria muestreada en el tiempo, no una tasa. Existen
    estados escritos sin f28 por otras trayectorias, sin probar con
    0.25 ms: `judge_e2_275` (misma config.dat que fh: `audit_freq` aparece dos
    veces con el mismo valor; la causa de la otra trayectoria no está en la
    config y su binario no consta en run.log, {C-277}; a
    280 s ya difiere de fh en |Δα_g| hasta 0.34 y |Δp| hasta 2.2 kPa) y
    `judge_fhe1_275` (fh con `pc_sat_open`), con snapshots de 280, 285,
    290, 295 y 299.999 s. Dato existente de no suficiencia en otro estado,
    a 1 ms: encender f28 sobre `judge_rampbelow/eaf3d_00255000.h5` (el
    ancestro de fh, 20 s antes; `m201_255`, `otp_255`, `a202_base`) no da
    pico: 50.2, 53.8 y 52.8 m/s y 14.6, 14.6 y 18.5 kPa en 255001-255003,
    frente a 50.6 m/s y 14.4 kPa en el paso 255000. Binario de esos bancos
    no registrado. Lo decidiría un reinicio de 0.25 ms con f28 encendida,
    y su control apagado, desde `judge_e2_275/eaf3d_00280000.h5`: no
    corrido (coordinador).
    > [fuente: diff campaigns/b1/judge_fh_275/config.dat campaigns/b1/judge_e2_275/config.dat; python3 -c "import h5py,numpy as np; a=h5py.File('campaigns/b1/judge_fh_275/eaf3d_00280000.h5','r'); b=h5py.File('campaigns/b1/judge_e2_275/eaf3d_00280000.h5','r'); [print(k, np.abs(np.array(a['fields/'+k])-np.array(b['fields/'+k])).max()) for k in ('alpha_gas','pressure')]"; python3 -c "import csv; [print(d,[(x['step'],round(float(x['u_gas_max']),1),round(float(x['p_max'])/1e3,1)) for x in csv.DictReader(open('campaigns/b1/'+d+'/audit.csv')) if int(x['step'])<=255003]) for d in ('m201_255','otp_255','a202_base')]"]
  - **La presión total sola sobre fh** no da pico (H21, {C-257}): no es
    necesaria ni suficiente en fh 280 s, ni suficiente en jb 280 s.
- **Los controles de B, I y J** los dio H22 ({C-265}): fh 285, 290 y
  295 s con las claves apagadas y 0.25 ms quedan en 15-20 kPa, sin nolink.
  Se retira la lectura de que 285-295 s era una asociación sin control.
  Para B el contraste es de dos claves (N/B); f28 sola en 290 s no se ha
  corrido {C-268}.
- **La edad del cambio: hipótesis abierta, no resultado** ({C-268},
  {C-269}, {C-273}). Entre los brazos con f28 encendida, «sin cambio» y
  «f28 establecida ≥ 5 s» van siempre juntos (A, H, M, N y O, sin cambio,
  nunca llevan f28). Se retira la dicotomía «edad del cambio» frente a
  «quién escribió el estado»: un reinicio es casi una continuación
  determinista (≤ 2.2e-12, {C-236}), así que el escritor del snapshot no
  es una variable del estado. La alternativa útil es una propiedad X del
  estado, medible, que se forma con la dinámica sin f28 y se erosiona con
  f28 encendida (candidatas: clase y lugar de las celdas que quedan
  nolink, o un campo del snapshot como `comp_carry`, abajo). Se retira
  también, para F, que su final con nolink haga plausible la edad: su
  casi gemelo `k11_dt025_tgfix` termina sin nolink ({C-273}). B, sin
  gemelo, termina con nolink ({C-277}).
  Además no tiene escala: `k7v4_long` da la firma 4.67 s después del
  cambio, justo por debajo del mínimo probado sin firma (5 s, jb 280 s),
  así que «edad del cambio» sin una escala de decaimiento puede absorber
  cualquier evento. Reiniciar desde
  `k11_b_dt025_fh290_on/eaf3d_00290236.h5` con las mismas claves y dt es
  casi una continuación de B: su resultado ya lo predicen las últimas
  filas de B (nolink 4), así que no es informativo salvo como prueba de
  continuidad (y no existe ningún reinicio de 0.25 ms con las mismas
  claves desde un snapshot intermedio, p. ej. A 280236 con f28 apagada,
  que la verifique). Sí serían informativos los snapshots de 1 ms
  posteriores al cambio, `judge_e1w280_n15/eaf3d_00280500.h5` y
  `00281000.h5` (0.5 y 1 s después, f28 y presión total encendidas),
  reiniciados con 0.25 ms, con una escala de edad pre-registrada; mejor
  aún, una prueba que manipule X como H12 manipuló `Tg_end`. No corrido;
  el pre-registro corresponde al coordinador.
  Sigue sin control propio el par de 300 s con f28 apagada, pero P no da la
  firma, así que no hace falta para el titular.
- **Por qué fh 300 s no responde** al encender f28 (P, {C-266}) no está
  medido. Lectura de solo lectura, NO pre-registrada y posterior al
  veredicto ({C-271}): de los `/restart` de los estados que responden
  (fh 280, 285, 290, 295 s y A 280.06 s) y de los que no (fh 299.999 s;
  `judge_rampbelow` 255 s a 1 ms), `comp_carry` (suma de |·|) vale 0, 0,
  0, 1.5e-9 (2 celdas) y 0 en los primeros, y 2.26e-5 (1 celda) y 8.1e-5
  (16 celdas) en los segundos. P arranca además del snapshot final de la
  corrida (paso 299999, no 300000). En cambio, ni el salto de `Tg_end`
  (|T_gas/Tg_end − 1| p99 0.20-0.23 % en todos los fh y 0.05 % en A
  280.06 s; máximo 6.8-44.8 %, 44.8 % en fh 295 s, que responde, y
  44.5 % en fh 300 s, que no) ni Σ`liq_cont_prev` (1620 en rampbelow
  255 s, 1707 en A 280.06 s, 1708-1755 en fh; {C-277}) separan.
  Lectura posterior (refutador del ciclo 4, R2; {C-278}): las celdas de
  chatarra sumergida (α_s ≥ ALPHA_BED, α_s < 0.1, α_l > 0.5) son 155-212
  en los estados que responden y 43 en P; en los escritos con f28 hay
  cifras parecidas (jb 280 s 217, jb 299.999 s 130, otp 300 s 52), así
  que no es la propiedad X; podría ser un cofactor, con un solo negativo y
  confundido con el tiempo. Lo discriminarían reinicios de 0.25 ms con f28
  encendida y su control desde `judge_e2_275` 295 y 299.999 s y
  `judge_fhe1_275` 299.999 s, que cubren además el linaje único; requiere
  pre-registro.
  Con dos estados que no responden, uno a otro dt, es una variable
  candidata, no un predictor, y débil: `comp_carry` ≠ 0 es habitual en
  los estados escritos con f28, también en estados en pleno régimen de
  firma: jb 280 s 9.7e-8, jb 285 s 5.2e-5, jb 295 s 2.6e-8, jb 299.999 s
  1.1e-8, otp 290 s 1.35e-7, otp 300 s 1.48e-7, final de F (280236)
  4.2e-6 y final de B (290236) 4.1e-7 ({C-274}). No hay razón medida para
  que 2.26e-5 en 1 celda importe en P si 4.2e-6 en F no impide la firma;
  solo distingue que en los fh escritos sin f28 vale 0 salvo en 300 s. Una
  prueba con P y `comp_carry` puesto a 0 (copia al estilo de
  `snap_tgfix.py`) repetiría el método de H12, ya refutado para `Tg_end`;
  si se pre-registra, con prior bajo. No corrida (coordinador). El volumen de poro saturado o sellado no se ha medido.
  Mientras tanto la firma sirve para clasificar un reinicio ya corrido,
  no para anticipar uno.
  > [fuente, solo lectura (los estados escritos con f28 de {C-274}: el mismo comando con judge_jb_275/eaf3d_00280000.h5, 00285000.h5, 00295000.h5, 00299999.h5, judge_otp_280/eaf3d_00290000.h5, 00300000.h5, k11_f_dt025_fh280_f28/eaf3d_00280236.h5 y k11_b_dt025_fh290_on/eaf3d_00290236.h5): python3 -c "import h5py,numpy as np; [print(p, np.abs(np.array(h5py.File('campaigns/b1/'+p,'r')['restart/comp_carry'])).sum(), int((np.array(h5py.File('campaigns/b1/'+p,'r')['restart/comp_carry'])!=0).sum())) for p in ('judge_fh_275/eaf3d_00280000.h5','k11_a_dt025_s280_off/eaf3d_00280236.h5','judge_fh_275/eaf3d_00285000.h5','judge_fh_275/eaf3d_00290000.h5','judge_fh_275/eaf3d_00295000.h5','judge_fh_275/eaf3d_00299999.h5','judge_rampbelow/eaf3d_00255000.h5')]"; Tg_end y liq_cont_prev con el comando del paso 3 sobre los mismos archivos]
- **Dónde están las celdas sin cara enlazada** no está medido. Los
  snapshots no guardan el indicador por celda (ningún dataset de
  `k11_b_dt025_fh290_on/eaf3d_00290236.h5` lo contiene), así que hace falta
  la sonda PROBE-P en los pasos 2-4 de B o de `k10b_dt025`: requiere corrida.
  El refutador del panel (ciclo 2, ronda 2, R4) descartó, con datos de los
  snapshots, que el estado escrito sin f28 traiga poros sobrellenados que
  el hueco congelado de f28 no deja drenar; ese cálculo es suyo, no
  repetido en este reporte. El mecanismo sigue abierto. Discriminador
  propuesto por el refutador del panel (R1, en la revisión que siguió a
  {C-268}), sin correr: comparar clase (sellada F2.29, gas excluido por F2.31, baño o
  poro) y lugar de las celdas nolink en los pasos 280002-280004 de
  `k10b_dt025`/F frente a 284669-284680 de `k7v4_long`; si coinciden
  (p. ej. fondo, chatarra sumergida), es el mismo mecanismo que el
  episodio de la familia de paradas de B1. Requiere la sonda PROBE-P o un
  volcado por celda. Discriminador más barato (refutador, {C-274}):
  reiniciar desde `k7v4_long/eaf3d_00285000.h5` con su binario
  `campaigns/bin/eaf3d_k7v4_opt` y PROBE-P en los pasos 285051-285064 (un
  tramo nolink de `k7v4_long`; otro en 285151-285168), unos 65 pasos a
  1 ms, y comparar con los pasos 280002-280004 de F; antes, comprobar que
  ese reinicio reproduce el audit de `k7v4_long`. Variante (refutador
  R4): el mismo reinicio con 20 externas y CG 1000, para ver si las 360
  celdas dependen de la config o de la no convergencia (≥ 27001 CG sin
  converger en `k7v4_long`), y con el binario actual, porque
  `eaf3d_k7v4_opt` es del 25-oct, anterior a `4d8570a` (según git, el
  código que fija los enlaces `ws_F*_lk` no cambió desde entonces; no
  verificado con una corrida; {C-277}). Hipótesis de partida: no es el mismo
  conjunto de celdas ({C-275}: 360 celdas fijas frente a 1-16, y nolink
  después de u_gas en `k7v4_long` y desde el paso 2 en los reinicios).
  Que la familia de 284 s exista sin cambio (`judge_e2_275`, f28 apagada,
  28 filas en 282-287 s; `judge_jb_275`, 1 fila en 275-280 s tras su
  cambio; Resultado) no dice nada de nolink. Complemento: una corrida larga sin cambio reciente
  (linaje jb, o fh con f28 apagada) con la columna nolink hasta 284 s;
  con f28 apagada decidiría además si «nolink ⇒ f28 encendida» vale en
  B1. Todo corresponde al coordinador ({C-269}).
- **Solo se probó un sentido del cambio.** Todos los reinicios con
  f28 = false salen del estado fh (escrito sin f28); ninguno apaga f28
  sobre un estado escrito con ella. Si el disparador fuera cualquier
  incoherencia entre la historia del snapshot y las claves (hueco
  congelado en α^n, semántica de `liq_cont_prev`), apagarla también daría
  huella; si es «f28 encendida sobre un estado fh», no. El titular no
  cubre ese sentido. Lo decidiría un reinicio de 0.25 ms con f28 = false
  desde `judge_jb_275/eaf3d_00280000.h5` o
  `judge_otp_280/eaf3d_00290000.h5`: no corrido (coordinador).
  > [fuente, solo lectura: python3 -c "import h5py; f=h5py.File('campaigns/b1/k11_b_dt025_fh290_on/eaf3d_00290236.h5','r'); f.visit(lambda n: print(n) if 'link' in n.lower() else None)" (no imprime nada)]
- **Los picos aislados de 450 kPa** de `k11_dt025_s290` (paso 290093), con
  f28 establecida, siguen sin diagnosticar ({C-236}, {C-237}); no se
  repiten desde 300 s (brazo D, {C-245}).
- **H13 no aislaba la causa; H15 aísla el snapshot de 280 s y su escritor**
  ({C-236}, {C-239}). H13 cambiaba a la vez tres cosas: la historia de
  claves, el estado físico (280 s frente a 290 s) y el código que escribió el
  snapshot. Contexto que motivó H15:
  - El estado de 280 s lo escribió `judge_fh_275` (20-oct, 13:24-16:38). Su
    binario no está registrado. Por las fechas, probablemente es
    `campaigns/bin/eaf3d_cand_filmhyst_opt` (creado a las 13:23:42, 38 s
    antes del arranque), anterior a los commits del 21-oct (`f57e950`,
    `eccca75`, `28cccdf`, `36f7d17`) y a los de J-B y de la presión total.
  - El archivo que se reinicia, `judge_otp_280/eaf3d_00280000.h5`, lo
    reescribió `judge_otp_280` al arrancar (22-oct, 02:57). Su `/restart` y
    los campos primarios son idénticos a los de
    `judge_fh_275/eaf3d_00280000.h5` (20-oct, 14:02). Difieren 8 de los 56
    datasets, todos diagnósticos y recalculados: F_lorentz_r/th/z, G_rad,
    S_arc (hasta 3.1e8), S_rad, S_chem y S_CO_src.
  - `judge_fh_275` se audita cada 5 pasos y no registra los pasos
    280002-280003.
- **El binario que LEE el snapshot no influye en el arranque** ({C-236}).
  `k10_base` (binario `eaf3d_k10_opt`, 27-oct) reproduce a `judge_otp_280` en
  280001-280005, y `k11_base_s290` lo hace en 290001-290005: u_gas_max, p_max
  y m_gas coinciden a 2.2e-12 y 5.2e-13 relativo.
- **Qué clave pesa: resuelto a 0.25 ms, con un matiz a 1 ms.** A 0.25 ms lo
  deciden H17 y H18 (paso 11). A 1 ms ({C-236}), encender solo f28
  reproduce el pico de `judge_otp_280` (`m203_280`, `m21f1_280`), lo mismo;
  pero el contraste con las claves apagadas (`scrfh_base` frente a
  `scrfh_b`) lleva probablemente un binario distinto.
- **Por qué el pico crece al bajar dt no está medido.** Se retira la lectura
  de que «el desequilibrio se corrige en un número de pasos, no en un
  tiempo»: con 0.25 ms el régimen sigue ≥ 100 kPa a los 235 pasos, aunque
  con medias que bajan (ver Resultado).
- **Una trayectoria por condición.** El arranque es determinista: los
  primeros pasos coinciden entre bancos gemelos a ≤ 2.2e-12 relativo
  ({C-236}) y a ≤ 7.9e-9 cuando difieren en la presión total (paso 11). Los
  veredictos de H15-H21 se deciden con una trayectoria por brazo; H16 con
  un brazo que llega a 117 kPa, el 39 % del umbral de 300 kPa. El
  contraste de régimen de toda la ventana (120/235 frente a 5/235, y que
  `k11_base_s290` no falle `regime_gas`) también es de una sola
  trayectoria. Pasados ~280 s la dinámica es caótica
  (`.claude/rules/acople-pv.md`). No hay réplicas ({C-237}).
- **Una oscilación en el control de 1 ms.** En `k11_mo20_s290`, u_gas_max
  alterna de un paso a otro entre ~122 y ~77 m/s. La corrida continua
  `judge_otp_280` ya alterna con periodo 2 en 289998-290009 (106.9 / 90.5
  m/s; 23.5 / 27.0 kPa), y con 20 externas la amplitud es mayor. Es el
  mismo ciclo de 2 pasos en que se asienta el pico de 280 s con 1 ms (paso
  9), y forma parte del régimen de los jueces con f28 (Resultado).
- **Qué afecta a B1, y qué no** {C-241}{C-251}. El juez de B1 posterior
  a 280 s ES `judge_otp_280`, un reinicio que enciende f28 sobre el estado
  de `judge_fh_275`. Las paradas de B1 a 284.3, 294.1 y 342.5 s ({C-001})
  caen dentro de su ventana (280-345.5 s, última fila de su audit.csv).
  Tras el pico entra en un régimen alto y alternante, medido por media de
  p_max y |Δp|, que dura segundos; `judge_jb_275` muestra lo mismo con f28
  desde 275 s, y el linaje apagado no. Pero con la métrica de las paradas
  (filas de nivel centinela, cada 5 pasos, 280-295 s) el linaje apagado da
  15, `judge_jb_275` 1 y `judge_otp_280` 26, y el apagado tiene 578 kPa en
  284.39 s, junto a la parada de 284.3 s. Por conteo, el régimen alto de
  f28 no explica las paradas de B1; el evento de 284 s aparece con f28 y
  sin ella. En `k7v4_long` el episodio de 284.3-285.4 s lleva nolink (86
  de sus 96 filas de nivel centinela; {C-269}, {C-274}), pero con otro
  patrón que el reinicio con 0.25 ms (360 celdas fijas, entra después de
  u_gas; {C-275}), y en el linaje apagado no hay columna nolink. Queda
  abierto si el reinicio con 0.25 ms es un artefacto propio del cambio o
  dispara antes el mecanismo de las paradas; los datos no apoyan lo
  segundo. Si lo fuera, el diagnóstico «artefacto del cambio de claves»
  describiría el disparador, no el mecanismo. Sí sigue en pie que el banco de 290 s no representa el
  régimen de 280-289 s, y que el arranque de `judge_otp_280` lleva el pico
  de reinicio.
- **Impacto en los workstreams que reinician de 280 s** (WS-K5 a WS-K8,
  WS-K10; lista en Resultado): sus ventanas incluyen el asentamiento del
  pico; cuánto cambia eso cada conclusión no está evaluado. Recalcular sus
  métricas sin los pasos 280001-280031 y decidir si alguna conclusión
  cerrada cambia supone reabrir workstreams cerrados; fuera de WS-K11
  (panel, ciclo 2, ronda 2, refutador R6).
- **La regla de transporte** (`.claude/rules/transporte-energia.md`, párrafo
  WS-K10/WS-K11, cabecera C-222..C-278) la corrigió el coordinador tras la
  ronda 2 del ciclo 3 con los textos que este reporte proponía: el nivel
  alternante con 0.25 ms no se separa entre f28 y linaje (auditor M1);
  «15 de 20 brazos con f28» y la edad del cambio como hipótesis sin el
  argumento de B y F, refutado por tgfix (B1, refutador R1; {C-273}); la
  presión total actúa también sin reflujo, relajando hacia p0 (B2); paso
  284669 = 284.670 s ({C-272}, B3); los bancos de 1599 filas en frase propia
  (B5); tgfix en la duración y F/tgfix/G como dispersión entre
  trayectorias ({C-273}); M20-2 con el dato fuera del arranque ({C-274});
  y un solo sentido del cambio probado. Tras la ronda 3 del ciclo 3
  (refutador R1 y R2) la corrigió de nuevo: la firma de `k7v4_long` y la
  del reinicio solo comparten el indicador nolink, con patrón distinto
  ({C-275}), y el dato de M20-2 fuera del arranque ni apoya ni refuta la
  prohibición ({C-276}). Con las objeciones no bloqueantes del ciclo 4,
  una tercera vez ({C-277}): `k7v4_long` es un reinicio en 280 s (auditor
  B3), la convergencia del CG y el binario como confusores del tamaño
  (refutador R4, auditor B4), la retirada solo para F (refutador R1) y
  las centinelas que siguen sin diagnosticar (refutador R6).
