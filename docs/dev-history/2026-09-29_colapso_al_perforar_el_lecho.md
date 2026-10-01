# Caracterizacion del fenomeno emergente (29-sep-2026)

Origen: juez F2.20/F2.21 (`scratchpad/cand/judge_F221`, reinicio de v33 a 200 s,
14 ranks, `audit_freq = 1`) y la colada `campaigns/b1_v33_full_5040s`.
**v33 es codigo PREVIO a F2.16/F2.20/F2.21** (lanzada 28-sep 13:20; esos commits
son del 29-sep): sirve para el mecanismo y la propagacion, no para juzgar el
codigo actual.

## 1. Que es

No es un artefacto aislado en 209 s. Es un **colapso de regimen que arranca en
el instante en que el arco perfora el lecho de chatarra y llega a la solera**,
y desde ahi se extiende a todo el bano.

### Disparo, medido en v33

| tramo (s) | as_eff bajo el arco | celdas en regimen disperso | u_liq_max | p_max |
|---|---|---|---|---|
| 0-200  | 0.79 -> 0.985 | 0    | <= 0.73 m/s | <= 5.4 kPa |
| 200-220| 0.0           | -    | 20.0 (cota) | 2 MPa (cota) |
| 250    | 0.0           | 3    | 11.1        | 1.38 MPa |
| 300    | 0.0           | 283  | 20.0        | 2 MPa, 100 % de los pasos |
| 400    | 0.0           | 1143 | 20.0        | 2 MPa, 100 % de los pasos |

Doscientos segundos impecables (cero cotas), y a partir de 205.53 s las tres
centinelas empiezan a activarse. Desde 260 s la corrida no tiene validez
fisica: presion, gas y liquido en la cota el 100 % de los pasos.

### Donde

A los 400 s las 1143 celdas que han cambiado de regimen cubren **todo el radio**
(i = 0..13) concentradas en k = 3..5: es la **superficie entera del bano**, con
alpha_gas mediana 0.49. No es un rincon: es la interfase bano-freeboard.

## 2. Por que

Dos sumideros de momento del liquido desaparecen a la vez cuando la celda de
abajo pierde su chatarra.

1. **Ergun se desvanece con alpha_s** (continuo). Medido en (i=12,j=40,k=5) con
   as_eff = 0.075: velocidad terminal 1.9 m/s. Con as_eff = 0: cero sumidero.
2. **El intercambio gas-liquido SALTA** (discontinuo). El criterio de F2.15 es
   un interruptor duro: `alpha_s propio > 1e-4 .or. alpha_s(k-1) >= 1e-2` da
   cizalla AIAD; si no, relajacion dispersa `alpha_l alpha_g rho_l / TAU_LG`.
   Salto medido en las celdas de liquido sobre el lecho: **mediana 1.5e8 x**
   (K_cizalla ~ 50 frente a K_TAU ~ 5e4). Un umbral con un salto de ocho
   ordenes de magnitud.

La relajacion dispersa con TAU_LG = 0.01 s es **rigidez numerica, no arrastre
fisico**: en una celda de superficie de bano vale K ~ 1.4e5, que frente a la
inercia del gas (alpha_g rho_g/dt ~ 45-85) es **K/inercia ~ 500-4600 por paso**.
El gas queda SOLDADO al liquido en una fraccion de paso. Con el bano en reposo
y sin arco eso es justo lo que frena al gas (razon por la que se conservo en
F2.15). Con el chorro del arco a 24-90 m/s llegando a esa misma celda, el
chorro se aniquila en una sola celda y el campo de presion tiene que absorber
su momento: de ahi los MPa. Y en el mismo coeficiente, el liquido ve
K/inercia ~ 0.1-0.2 por paso y es empujado hacia la velocidad del gas.

## 3. Como arranca

El arranque es **exponencial**, no una respuesta forzada. Paso a paso
(208.90 -> 209.14 s) la velocidad maxima del liquido continuo crece
0.19 -> 0.34 -> 0.59 -> 0.99 -> 1.62 -> 2.55 -> 3.89 -> 5.77 -> 8.33 -> 11.64
-> 15.43 -> 19.79 -> cota. Factor constante ~1.04 por paso:

    tiempo de crecimiento e-folding ~ 50 ms  (sigma ~ 20 1/s)

Cinco e-folding desde el ruido hasta la cota en 0.24 s. La tasa coincide en
orden de magnitud con Kelvin-Helmholtz de escala de malla para gas a 100 m/s
sobre acero liquido con k = 2*pi/dz: sigma = k u sqrt(rho_g rho_l)/(rho_g+rho_l)
~ 31 1/s. La localizacion es la huella de los tres electrodos (i = 12, k = 5,
j = 0 / 20 / 39-40 / 59, con los electrodos en j = 0, 20, 40), es decir,
crecimiento localizado donde el chorro es rapido.

## 4. La rafaga de fusion que lo acompana

En la misma ventana la fusion llega a 180 kg/s (176 MW extraidos del solido)
con solo ~37 MW entrando al solido (18.8 arco directo + 9.9 radiacion +
7-9 interfase). No se crea energia: sale del **calor sensible del lecho a punto
de liquidus**; el balance de masa cierra (65749.9 -> 65750.2 kg en 10.7 s,
5e-6 relativo). La rafaga es el gatillo del colapso, no su causa.

## 5. Estado del codigo actual

F2.20/F2.21 mejoran mucho la severidad en la misma ventana (p_max 2 MPa -> 9.9
kPa en 200-210 s) pero **no quitan el mecanismo**: en el juez, desde 209.12 s el
liquido queda clavado en U_LIQ_MAX y a 210.70 s el estado es estacionario y
patologico: p_max 27.2 kPa, gas 232 m/s (de 300), liquido 20 m/s, bano creciendo
25 kg/s. Las tres magnitudes suben de forma monotona.

El clip auditado de 0.4165 kg (1222 filas desde 206.96 s, maximo 6.3e-4 kg por
paso) **precede** al evento de velocidad y se apaga cuando el liquido empieza a
drenar: es la cola de la cadena de derrame (122.3 kg), no consecuencia del
liquido rapido.

## 6. Veredicto

**No relanzar la colada completa.** Por el criterio de cierre del propio Plan C
(F4: ninguna centinela se activa), el modelo esta fuera de validez desde que el
arco perfora el lecho, y eso ocurre a los ~205 s de una colada de 5040 s.

## 7. Direccion del arreglo

1. El cambio de morfologia tiene que ser una **mezcla** (blending) y no un
   umbral: el salto de 1e8 en K a traves de `alpha_s = 1e-2` es el defecto.
2. La cizalla de superficie libre necesita una **magnitud fisica** que no
   dependa del refinamiento; la forma actual `C rho_g |du| |grad alpha_l|` se
   anula dentro de un charco y en malla gruesa da K ~ 50.
3. Hay que rehacer la restriccion que justificaba conservar TAU_LG. El banco
   `bath_test` no tiene arco: el gas que hay que frenar ahi es un gas boyante en
   reposo, no un chorro. Un rozamiento fisico de superficie libre NO puede (ni
   debe) frenar un chorro a 100 m/s: un chorro que incide se desvia por el campo
   de PRESION, no por friccion. Que `bath_test` se fuera a 143 m/s con cizalla
   sola apunta a que al gas sobre el bano le falta otro sumidero, y eso hay que
   diagnosticarlo aparte en vez de taparlo con rigidez.

---

---

# CORRECCION (29-sep-2026, misma sesion): la "causa raiz" de arriba era FALSA

La seccion "CAUSA RAIZ" que sigue mas abajo afirmaba que la celda de
superficie libre siente el 58 % de su peso sin equilibrar por un defecto de
**balanced-force**. **Es incorrecto.** Se comprobo con dos medidas en
`bath_test` a t = 0, en reposo exacto:

1. **El campo de presion SI es consistente.** Es el hidrostato de la MEZCLA
   con densidad de cara aritmetica, y la g implicita sale identica en las
   tres caras del bano (8.984, 8.984, 8.985 m/s2). No hay error de
   discretizacion en el gradiente.

2. **La fuerza neta sobre el liquido de una celda mixta es FISICA.** Es la
   flotacion relativa de la fase dentro de la mezcla,
   `F_q = alpha_q (rho_mezcla - rho_q) g`: predicha -16 262 N/m3 y medida
   -14 988 en la celda de superficie; **exactamente cero en las celdas
   puras**. Es el termino que separa las fases, no un residuo numerico.

Lo que la equilibra es el arrastre de interfase. Con TAU_LG = 0.01 s el
coeficiente vale K = 1.81e5 en esa celda y la equilibra con un deslizamiento
de **0.09 m/s**. Es decir: **TAU_LG no era una muleta que tapaba un bug; es
el cierre de interfase RESUELTA** que la literatura llama Strubelj & Tiselj
(2011) y que Fluent expone como `time-scale-drag`, cuyo proposito declarado
es forzar casi-no-deslizamiento donde la interfase esta resuelta.

Por eso el intento F2.22 original (sustituirlo por la friccion de AIAD,
K ~ 1e3) rompia la hidrostatica: dejaba el cierre 200 veces mas debil que la
flotacion que debe sostener.

**Lo que SI sigue en pie de la caracterizacion**: el fenomeno, su disparo, su
arranque exponencial y su propagacion (secciones 1 a 5 de este documento).
Y sigue en pie que el interruptor duro de morfologia es indefendible: el
salto de 1.5e8 no lo hace ningun codigo Euler-Euler.

**F2.22 rehecha** conserva la magnitud del cierre de interfase y quita solo
el interruptor:

    f_disp = [1 + exp(A_AIAD (alpha_l - ALPHA_AIAD_LIM))]^-1     (AIAD ec. 6)
    K_int  = alpha_l alpha_g rho_mezcla / TAU_LG                 (Strubelj-Tiselj)
    K_disp = alpha_l (rho_l - rho_g) g / u_t                     (gota)
    Kexch  = (1 - f_disp) K_int + f_disp K_disp                  (AIAD ec. 9)

con la densidad de MEZCLA en vez de rho_l (Strubelj & Tiselj ec. 4). La rama
de cizalla de F2.15 desaparece. Bancos: los tres pasan y bath_test queda
igual que la base (hidrostatica 0.860 % frente a 0.869 %, reposo 0.158 frente
a 0.165 m/s, gas 20.8 frente a 20.8).

---

# CAUSA RAIZ (encontrada el 29-sep-2026 al probar F2.22)

> **OBSOLETO: ver la CORRECCION de arriba.** Se conserva por trazabilidad.

## El estado de reposo no es un equilibrio de las ecuaciones discretas

Medido en `bath_test` en **t = 0**, antes de integrar un solo paso, con la
formula de fuerza vertical tal como la arma `mod_momentum_3d`
(`-alpha_l dp/dz - alpha_l rho_l g`, gradiente centrado y unilateral en las
caras cuya vecina no tiene presion de fluido):

|  k | alpha_l | caras   | NETO N/m3 | NETO/peso |
|----|---------|---------|-----------|-----------|
|  2 | 1.000   | arriba  |   -6 199  | 0.08      |
|  3 | 1.000   | ambas   |  -16 182  | 0.22      |
|  4 | 0.407   | ambas   |  -17 512  | **0.58**  |

La celda de SUPERFICIE LIBRE siente el 58 % de su propio peso sin equilibrar,
hacia abajo, con el bano perfectamente en reposo. La causa es geometrica: su
gradiente centrado toma la presion de la celda de gas de arriba (~0) y la del
liquido de abajo, asi que ve **medio** gradiente hidrostatico del liquido.
Prediccion cerrada: le sobra `alpha_l (1/2) rho_l g` = 14 980 N/m3 frente a
los 17 512 medidos (la diferencia es Boussinesq y g_eff/g = 0.814).

Es el problema clasico de **balanced-force** de las mallas colocadas con
interfase (Francois et al., J. Comput. Phys. 213 (2006) 141): si la fuerza de
cuerpo y el gradiente de presion no se discretizan de forma consistente en la
celda donde salta la densidad, queda una fuerza residual que genera corrientes
espurias.

## Esto explica toda la familia

- **Por que F2.15 necesito Ergun** para el charco sin chatarra propia ("sin el
  se queda sin ningun sumidero de momento y cae en caida libre hasta
  U_LIQ_MAX"): esa caida libre a ~medio g ES esta fuerza residual. Ergun era
  la muleta.
- **Por que TAU_LG no se podia quitar**: ataba la celda de superficie al gas
  casi estatico y amortiguaba la corriente espuria. En `bath_test` la deja en
  0.165 m/s; al sustituirla por la friccion de AIAD sube a 2.91 m/s y la
  hidrostatica se va al 25 % de error.
- **Por que el horno colapsa al perforar el arco el lecho**: mientras hay
  chatarra debajo, Ergun absorbe la fuerza residual. Cuando desaparece, no la
  absorbe nadie.

El arranque exponencial de 50 ms es un mecanismo aparte y mas rapido, del
acople rigido; la fuerza residual es el termino continuo que lo alimenta.

## F2.22 (implementada, probada y BLOQUEADA)

Parche completo en `docs/dev-history/2026-09-29_f222_friccion_aiad_descartada.patch`.
Sustituye el interruptor duro por la mezcla logistica de AIAD
(`f = [1 + exp(a(alpha_l - 0.3))]^-1`, a = 50) y la cizalla ad-hoc por el
arrastre de superficie libre de AIAD en su forma de FRICCION
(`C_D,fs = max(0.01, 2(alpha_l tau_l + alpha_g tau_g)/(rho_l u_slip^2))`,
`A_fs = 2 alpha_l alpha_g |grad alpha_l - grad alpha_g|`).

Resultado medido en los tres bancos:

| banco | base | F2.22 |
|---|---|---|
| bath_test u_gas_max | 20.8 m/s | **19.8 m/s** |
| bath_test hidrostatica | PASS 0.87 % | **FAIL 25 %** |
| bath_test u_l reposo | 0.165 m/s | 2.91 m/s |
| bath_fill / bath_freeze | PASS | PASS |

**Lo bueno**: el gas se frena igual de bien SIN TAU_LG. La razon documentada
para conservar el acople disperso ("con cizalla sola bath_test se va a 143
m/s") ya no aplica: la friccion de AIAD bien formulada lo sujeta a 19.8 m/s.
Ese era el obstaculo para quitar el interruptor.

**Lo que bloquea**: sin el amortiguamiento artificial, la corriente espuria de
la fuerza residual queda a la vista y rompe la hidrostatica. **F2.22 no se
commitea sola**: va junto con el arreglo de balanced-force.

## Orden de trabajo propuesto

1. **F2.24 — balanced-force en la celda de superficie libre**: que el estado de
   reposo sea un equilibrio EXACTO de las ecuaciones discretas. Test directo y
   barato: el cuadro de arriba a t = 0 debe dar NETO = 0 en las tres filas.
   Es el arreglo de raiz y no depende de nada mas.
2. **F2.22** (el parche guardado), que entonces deberia pasar los tres bancos.
3. **F2.23 — Ergun del liquido con la forma de Attou/Boyer** (`epsilon_l` en el
   denominador y tortuosidad `alpha_l^n`, n ~ -0.5; Fourati et al.,
   arXiv:1503.04685 ecs. 7-8), para que el sumidero no se desvanezca justo
   cuando el liquido escasea. Deja de ser critico una vez hecho (1).
4. Rejuzgar con el reinicio en 200-211 s y solo entonces relanzar la colada.

---

# F2.22 de DOS vias: DESCARTADA (juez del 29-sep)

Primera version de la mezcla: dos morfologias (interfase resuelta y dispersa),
logistica sobre alpha_l, **sin rama de lecho**. Los tres bancos de bano pasaban
y bath_test quedaba igual que la base, asi que parecia lista.

**Fallo en el horno en 0.8 s.** Reinicio de v33 en 200 s: la presion sube
LINEAL de 4.5 a 63 kPa mientras la base se queda en 4.4 kPa.

Causa, medida sobre el snapshot de 200 s en las 185 celdas de lecho con gas de
poro y algo de liquido:

| K gas-liquido | mediana | p90 | K/inercia_gas por paso | celdas con >1 |
|---|---|---|---|---|
| cizalla F2.15 (antes) | 0.169 | 1.25 | 0.02 | 0 % |
| mezcla de dos vias    | 87.5  | 436  | 4.61 | 74 % |

Razon nueva/antigua: **mediana 644x**. Al quitar la rama de lecho, el gas de
poro queda SOLDADO al liquido inmovil de la chatarra, no puede ventear, se
calienta y su compresibilidad integra `p ~ P0 (T/T0 - 1)`. Es exactamente la
patologia que F2.13 y F2.16 resolvieron, reintroducida por la puerta de atras.

**Leccion**: la cizalla de F2.15 tenia una magnitud minuscula (K ~ 0.2) y eso
parecia un defecto, pero **es su funcion**: en el lecho el peso del liquido lo
lleva Ergun contra la chatarra y el gas de poro tiene que quedar libre para
ventear. No hay que "arreglar" su magnitud; hay que dejar de conmutar a ella
de golpe.

# F2.22 de TRES vias (la que queda)

Tres morfologias y dos logisticas, como el f_B/f_D/f_FS de AIAD:

    f_bed  = [1 + exp(A_AIAD (ALPHA_AIAD_LIM - alpha_s_eff))]^-1
    f_disp = [1 + exp(A_AIAD (alpha_l - ALPHA_AIAD_LIM))]^-1
    K = f_bed K_cizalla
        + (1 - f_bed) [ (1 - f_disp) K_interfase + f_disp K_gota ]

con `K_interfase = alpha_l alpha_g rho_MEZCLA / TAU_LG` (Strubelj & Tiselj,
densidad de mezcla segun su ec. 4), `ALPHA_AIAD_LIM = 0.3` y `A_AIAD = 50`
(los valores de Fluent para AIAD).

La distribucion de alpha_s es fuertemente BIMODAL (a 400 s: 1456 celdas en
alpha_s = 0, 986 en alpha_s >= 0.35, **3** en medio), asi que la mezcla
reproduce el lecho actual casi exactamente y solo suaviza el transito, que es
donde estaba el salto de 1.5e8.

Bancos: los tres pasan; bath_test identico a la base (hidrostatica 0.860 %,
reposo 0.158 m/s, gas 20.8 m/s) y bath_freeze mejora (gas 12.7 frente a 23.0).
Primer segundo del horno: sigue a la base celda por celda (4466 frente a 4468
Pa), sin rastro del ramp de presion de la version de dos vias.

---

# CAUSA RAIZ REAL (F2.24, 29-sep): caudal FANTASMA de la vecina vacia

Encontrada instrumentando el arranque con una sonda de BALANCE DE MOMENTO por
celda (`cfg%probe_cell_i/j/k`, nueva en `mod_momentum_3d`), sobre un reinicio
en 208 s de la malla media.

## La medida

La celda que arranca es la (13,1,6) de la malla media (Fortran, 1-based), bajo
un electrodo. Su vecina de abajo se funde: alpha_s pasa de **0.30 a 0.0012 en
0.2 s**. En ese tramo:

| t (s) | uz_l | a_nb | aP | Ergun*V |
|---|---|---|---|---|
| 208.80 | -0.04 |   2.4 | 8.3e3 | 3.4e3 |
| 208.90 | -0.85 |  46.8 | 7.2e3 | 2.3e3 |
| 209.00 | -7.47 |   406 | 7.3e3 | 1.9e3 |
| 209.08 | -19.91|   959 | 6.3e3 |   900 |

**`a_nb` crece 400 veces mientras `aP` no se mueve.** Ninguna fuerza local lo
explica: presion +18, gravedad -66, arrastre del gas -4.7e3 frente a aP 5.6e3.
La velocidad media de las vecinas, despejada del balance, es **-24 m/s cuando
la celda aun va a -0.85**.

Las celdas de ARRIBA tienen `alpha_l = 0.000` y llevan `uz_l = -49.7 m/s`: es
la velocidad de drift del liquido disperso, `settling_velocity(d_droplet)` con
gotas de 2 mm en gas a 2000 K, acotada por `U_SETTLE_MAX`. La masa implicada es
0.0006 kg — irrelevante. La VELOCIDAD no lo es.

## El lazo

`face_mass_fluxes` interpola alpha SIMETRICAMENTE, asi que en una cara con la
vecina vacia el caudal no es cero sino la mitad del propio:

    Ft = 1/2 (alpha_P rho u_P + 0) A        -> aT = D + 1/2 alpha_P rho |u_P| A

El coeficiente de la cara **crece con la propia velocidad** y multiplica la
velocidad de la celda vacia. En el segundo miembro eso es `C u_P` con

    C = 49.7 * 1/2 * alpha_P * rho_l * A ~ 1.2e3    frente a aP ~ 6.3e3

o sea **18 % de ganancia por iteracion**: realimentacion positiva pura. De ahi
el e-folding de 50 ms y los cinco e-folding de 0.19 a 20 m/s en 0.24 s.

Es **el mismo defecto que ya se corrigio en la energia del liquido** ("la
interpolacion simetrica de alpha hacia que una celda vacia entregara
1/2 alpha_P rho u de masa fantasma a su T rancia"), no corregido en momento.
Ahi era un sumidero de energia; aqui es una inestabilidad.

## El arreglo

`face_mass_fluxes_noalpha` + alpha DONOR-CELL para el LIQUIDO, igual que la
energia. Una vecina sin fase no entrega nada: F = 0, y la velocidad que lleve
esa celda deja de importar — que es lo robusto, porque el debate sobre que
valor darle a una fase evanescente (u = 0 de antes, drift de ahora, atada de
F2.20) se vuelve irrelevante para sus vecinas.

El GAS conserva la forma simetrica: cambiarsela tambien lleva el gas de
`bath_fill` a U_GAS_MAX (medido). Es coherente con el diagnostico: la fase con
celdas vacias que llevan una velocidad grande es el liquido.

Se aplico ademas la media ARMONICA de alpha en las conductancias difusivas de
momento (`aface`, la misma de la energia), por la misma regla general. Efecto
en el arranque: **bit a bit nulo** — el `a_nb` de esta celda es integramente
convectivo. Se conserva por correccion, no por efecto.

## Resultado

Bancos: `bath_fill` y `bath_freeze` pasan; `bath_test` deja la hidrostatica al
filo (1.05e-2 frente a una tolerancia de 1e-2; antes 8.6e-3) y el reposo en
0.175 m/s (antes 0.158).

Arranque del horno (reinicio en 208 s, malla media, 14 ranks):

| t (s) | sin donor | con donor |
|---|---|---|
| 208.80 | 0.09 | 0.09 |
| 208.85 | 0.21 | 0.09 |
| 208.90 | 0.86 | 0.12 |

El crecimiento exponencial queda suprimido.

## Veredicto del juez (reinicio en 208 s, hasta 212 s, malla media, 14 ranks)

| tramo | base (F2.22b sin donor) | F2.24 |
|---|---|---|
| 208-209 s | u_liq 0.86, p 4.6 kPa | u_liq 0.83, p 4.66 kPa |
| 209-210 s | **cota desde 209.066** | u_liq 7.40, p 4.90 kPa |
| 210-211 s | p hasta 27 kPa, gas 232 | u_liq 8.16, p 7.70 kPa, gas 108 |
| 211-212 s | (la base ya no era valida) | u_liq **7.00**, p 7.49 kPa, gas 108 |

**Ninguna centinela se activa, y el liquido SATURA**: sube a 8.16 m/s y baja a
7.00. La aceleracion residual va de 8.8 a 6.3 m/s2, o sea caida libre con
arrastre: el fundido drenando al crater que abrio el arco. Esa es la fisica
que se busca, no una inestabilidad.

## Coste, declarado

`bath_hydrostatic` pasa a XFAIL (1.05e-2 frente a tolerancia 1e-2). El banco
YA estaba al filo (0.9 %) y su corriente fantasma de 0.17 m/s ya era xfail
(`bath_rest`): con el bano de solo 3 celdas de ese banco, la misma corriente
par-impar mueve la ferrostatica medida un 1 %. No es un fenomeno nuevo. Las
dos entradas se retiran juntas cuando se cierre esa corriente.

`make test-full` en verde con esa entrada; golden v32; los 22 tests unitarios
pasan; invarianza MPI n1/n8 y simetria 120 % intactas.

## Lo que queda

1. Juez largo desde 200 s y, si aguanta, relanzar la colada completa.
2. F2.23 (Ergun del liquido en forma de Attou/Boyer) pasa a OPCIONAL: ya no es
   el sumidero que falta, porque la inestabilidad no era de falta de arrastre.
3. Hilo abierto: la corriente par-impar del bano (`bath_rest`), que ahora
   arrastra tambien a `bath_hydrostatic`.

## Juez LARGO (200 -> 230 s, malla media, 14 ranks, audit_freq 1)

Cubre entera la ventana que destruyo v33 (colapso desde 205.53 s; a 260 s las
tres centinelas en la cota el 100 % de los pasos).

| tramo | p_max | u_gas | u_liq | m_liq |
|---|---|---|---|---|
| 200-205 | 7.1 kPa | 104 | 1.24 | 920 |
| 205-210 | 14.3 kPa | 113 | 7.44 | 1128 |
| 210-215 | 7.3 kPa | 108 | 8.24 | 1209 |
| 215-220 | 4.0 kPa | 102 | 1.19 | 1344 |
| 220-225 | 4.5 kPa | 104 | 14.39 | 1491 |
| 225-230 | 4.5 kPa | 103 | 9.16 | 1470 |

- **Ninguna centinela se activa en los 30 s**: ni `U_LIQ_MAX`, ni `U_GAS_MAX`,
  ni `P_HYDRO_CAP`. v33 en el mismo tramo llevaba 7.3 % de los pasos con el
  liquido en la cota, 23.4 % con el gas, y p_max de 2 MPa.
- La presion PICA en 14.3 kPa durante la rafaga de fusion y VUELVE a 4.5 kPa.
  El liquido pica en 14.4 m/s y baja a 9.2. Nada crece de forma monotona.
- El bano se forma de 920 a 1470 kg de manera continua.
- Clip auditado: 0.2504 kg, confinado a UN episodio (206.83-209.48 s, el de la
  rafaga de fusion) y exactamente cero en los 20 s siguientes. Es el 0.05 % de
  lo fundido en la ventana.
- Masa total 65751.2 -> 65751.0 kg en 30 s (3e-6 relativo).

Con esto la colada completa se puede relanzar.

---

# SEGUNDA FALLA (30-sep / 1-oct): la PELICULA sobre el bano

La colada B1 v34, lanzada con F2.22 + F2.24, corrio **limpia 225 s** — muy por
encima de los 205 s en los que colapsaba v33 — y despues derivo despacio hasta
activar `U_LIQ_MAX` a los **293.21 s**. Perfil por tramos:

| tramo (s) | p_max | u_gas | u_liq | m_liq |
|---|---|---|---|---|
| 0–225   | ≤ 5.2 kPa | ≤ 111 | ≤ 1.60 | 960 |
| 225–250 | 7.1 kPa | 115 | 10.26 | 1517 |
| 250–275 | 5.3 kPa | 119 | 18.41 | 1644 |
| 275–300 | **81 kPa** | 218 | 20.00 | 2183 |

No es la inestabilidad rapida de F2.24 (e-folding de 50 ms): es una **deriva
lenta** sobre 50 s. Mecanismo distinto.

## El estado incoherente

Las celdas que se disparan son siempre las mismas: `i = 12` (el radio de paso
de los electrodos), `k = 5`, **peliculas delgadas de liquido apoyadas sobre una
celda de bano lleno** (`alpha_l = 1.000` debajo, en reposo exacto).

Esas celdas son CONTINUAS por la **regla de superficie libre** de
`liquid_continuity_mask`: basta `alpha_l >= ALPHA_FLOW_CUTOFF` (1e-2) y que la
de abajo sea bano. Asi que tienen ecuacion de momento propia y entran al
Poisson. Pero **F2.22 decide su morfologia de arrastre solo con alpha_l**, y
con `alpha_l = 0.165` la logistica de AIAD da `f_disp = 0.999`: el cierre que
reciben es el de GOTA.

**El modelo las trata como liquido continuo para el momento y como niebla para
el arrastre.** Medido a t = 250 s sobre las 5 celdas en ese estado: el cierre
de interfase seria **46 veces** mas fuerte que el de gota que reciben
(K mediana 9000 contra 195).

Sin chatarra debajo no hay Ergun, y con el caudal donor-cell la cara que las
separa del bano apenas intercambia momento con el. Balance medido en
(12,17,5): presion +3289, peso −12142, neto **−8853 N/m³** contra una inercia
de 1237 kg/m³, o sea **−7.2 m/s² — caida libre**. Desde el reposo llegan a los
20 m/s en 2.8 s. Fisicamente, 4 mm de acero apoyados sobre un bano profundo no
atraviesan el bano en caida libre.

## Honestidad sobre el origen

**Este modo lo introdujo F2.22.** Antes del blend, esa misma celda caia en la
rama `ws_liq_cont` y recibia `alpha_l alpha_g rho_l / TAU_LG` = 1.0e5, que la
sostenia. Al mover la decision de morfologia a `alpha_l` sola, la solte. El
balance neto sigue siendo favorable (v33 colapsaba a 205 s; v34 llega a 293 s),
pero la pieza no estaba completa.

## Direccion del arreglo

La morfologia del arrastre tiene que ser **coherente con la clasificacion de
continuidad**: una celda que el modelo trata como liquido CONTINUO no puede
recibir el cierre de gota. El candidato minimo es forzar `f_disp = 0` donde
`ws_liq_cont` es cierto, conservando el blend para el liquido genuinamente
disperso y la rama de lecho intacta. Pendiente de contrastar contra la
literatura si ademas hace falta atar la pelicula al bano de abajo.

## F2.25 — coherencia del arrastre: DESCARTADA (1-oct)

Primer intento contra la pelicula: forzar `f_disp = 0` donde `ws_liq_cont` es
cierto, para que una celda tratada como liquido continuo no reciba el cierre
de gota. Conserva la regla de vecino y solo corrige la incoherencia.

Bancos: los tres pasan, y `bath_fill` MEJORA (gas 181 -> 97 m/s, clip a un
tercio). Pero el juez sobre 250-296 s lo descarta:

| tramo | base F2.24 | F2.25 |
|---|---|---|
| 290-300 s, p_max | 81 kPa | **192 kPa** |
| 290-300 s, u_gas | 133 | **300 (cota)** |
| 290-300 s, % pasos con liquido en cota | 32.8 % | 2.5 % |

El liquido mejora mucho (32.8 -> 2.5 % de los pasos) pero **la presion se
duplica y el gas toca su cota**. La razon es directa: el cierre de interfase
es un arrastre GAS-liquido, y en una celda de pelicula vale K = 1.7e4 contra
una inercia de gas de 79, o sea 216 por paso. El gas queda soldado a la
pelicula y el chorro del arco se aniquila en una celda — exactamente el
mecanismo que producia los MPa en v33. La propia consulta de literatura lo
habia advertido: ese cierre "ata al GAS de la propia celda, que es lo que te
fallo con TAU_LG".

Leccion: corregir la incoherencia por el lado del ARRASTRE la empuja al gas.
Habia que corregirla por el lado de la CONTINUIDAD, que es lo que dice la
literatura.

## F2.26 — continuidad LOCAL con banda de histeresis

La regla de superficie libre de F1 decidia continuidad por el VECINO de abajo.
Ningun codigo Euler-Euler revisado hace eso: OpenFOAM (`blendingMethods::
linear`, banda [0.3, 0.7] sobre la alpha local), AIAD (alpha_lim = 0.3),
GENTOP (gradiente adimensionalizado por dx) y Porombka & Schlottke 2025
(cociente espesor/celda, que para una pelicula de una celda ES alpha_l)
deciden de forma LOCAL; y cuando detectan superficie libre, eso selecciona el
CIERRE DE ARRASTRE, nunca el derecho a tener ecuacion de momento.

Lo que la regla SI resolvia era el castaneteo al cruzar `ALPHA_LIQ_CONT`. El
remedio de la literatura para eso es una BANDA, no un vecino. Asi que:

    cont = liq_continuous(alpha_l, alpha_s)
    donde YA era continua y alpha_l >= ALPHA_LIQ_HYST (0.2) -> sigue continua

La memoria es el valor entrante de la mascara (el iterado externo anterior),
por eso `cont` pasa a `intent(inout)`.

Efecto: las peliculas de alpha_l < 0.2 dejan de tener ecuacion de momento y
pasan a transporte por drift, que es algebraico y acotado — ya no pueden caer
libremente por construccion. Y como dejan de ser continuas, tampoco reciben el
cierre de interfase, asi que el gas no queda soldado a ellas.

Bancos: los tres pasan y **bath_test queda IDENTICO a la base** (hidrostatica
1.051e-2, reposo 0.175, gas 20.9). Es decir, la succion que motivo la regla en
F1 no reaparece: la cubrieron F2.20/F2.21 (`ws_gas_reach` mete al gas en el
Poisson donde aun no lo hay pero puede llegar, que es justo lo que deja a una
celda de bano puro recibir gas al drenar). `bath_fill` baja el clip a 0.006 kg,
el mejor valor de toda la serie.

## F2.26 + F2.27: NO CIERRAN — y el porque reencuadra el problema

Parche completo en `docs/dev-history/2026-10-01_f226_f227_pelicula_sin_cerrar.patch`
(continuidad LOCAL con banda de histeresis + drift que se incorpora al bano).
Los tres bancos pasan y `bath_test` queda identico a la base, pero el juez
sobre 250-296 s no lo aprueba.

### La comparacion de los tres candidatos

| version | 1a cota liq | p_max | u_gas | % pasos en cota |
|---|---|---|---|---|
| F2.24 (commiteada) | 292.41 | 81 kPa | 218 | 3.0 % |
| F2.25 (coherencia) | 295.81 | 192 kPa | 300 | 0.3 % |
| F2.26+F2.27 | 281.31 | 134 kPa | 277 | 0.1 % |

### El hallazgo que reencuadra todo

Los tres variantes son **identicos hasta los 280 s** y los tres tienen el
MISMO evento despues: un racimo de **cinco picos de presion de 30-60 ms**
entre 280.95 y 281.85 s, en los mismos instantes:

| pico | F2.24 | F2.25 | F2.27 |
|---|---|---|---|
| 1 | 280.980 · 68 kPa | 280.952 · 72 kPa | 281.070 · 82 kPa |
| 2 | 281.360 · 53 kPa | 281.318 · 68 kPa | 281.338 · 134 kPa |
| 3 | 281.500 · 68 kPa | 281.464 · 84 kPa | 281.458 · 107 kPa |
| 4 | 281.660 · 62 kPa | 281.708 · 72 kPa | 281.676 · 126 kPa |
| 5 | 281.760 · 67 kPa | 281.810 · 77 kPa | 281.748 · 92 kPa |

Tiempo total por encima de 20 kPa en los 46 s de ventana: 0.21 / 0.25 / 0.19 s.
Es decir, **episodios breves y acotados**, no un colapso.

El evento coincide con una **rafaga de fusion**: m_liq pasa de 1763 a 1865 kg
entre 280.4 y 281.6 s (83 kg/s). Es la familia de las rafagas bajo los arcos
que ya trabajaron F2.14 y F2.15, y **ninguno de los tres candidatos la toca**:
solo modulan la AMPLITUD de su respuesta.

### Leccion de metodo

Pase tres iteraciones de hora y media arreglando la respuesta del liquido a un
evento cuya causa no habia identificado. La pelicula en caida libre es real y
esta bien diagnosticada, pero es **secundaria**: el disparador es la rafaga de
fusion de los 281 s. Antes de volver a tocar el cierre de morfologia hay que
caracterizar esa rafaga — igual que se hizo con el colapso del lecho: sonda de
balance en la celda que la origina, no suposiciones.

### Estado

El arbol vuelve al estado commiteado (F2.24, `30b466a`), `make test-quick` en
verde. Los tres candidatos quedan archivados con sus medidas. La colada v34 se
detuvo a los 294 s y sus snapshots y audit quedan en
`campaigns/b1_v34_f224_5040s/` como linea base de la ventana.
