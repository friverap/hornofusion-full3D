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

---

# LA RAFAGA DE LOS 281 s, caracterizada (1-oct)

Reinicio desde el snapshot de 280 s con salida cada 50 ms (`rafaga281`) y sonda
de la FILA DE PRESION de una celda (`[PROBE-P]`, nueva en `mod_pressure_3d`:
Su por fase, los seis coeficientes de cara, aP, pp y las diagonales de momento
de la celda y sus vecinas, por iteracion externa).

## Donde y que

Los cinco pulsos (280.95, 281.35, 281.50, 281.75, 281.85 s; 20-52 kPa; 80 ms
cada uno) caen en **celdas de liquido PURO en reposo exacto** (alpha_l = 1.000,
u = 0, T = 1825 K), en `i = 9, k = 3`, rotando por los tres sectores de
electrodo (j = 59/0 -> 39/40 -> 19/20). Cada una descansa sobre lecho denso
(alpha_s = 0.985 con gas de poro 0.015 ATRAPADO, movilidad 1e-5: pared para
el Poisson) y tiene tres caras abiertas: dos laterales a liquido puro y la de
arriba a la celda de superficie (alpha_l ~ 0.5).

Lo que NO es: no hay fusion en la celda ni en sus vecinas (dm_s = 0 en toda la
columna); el arco es estable (potencia y posicion sin salto); las celdas ya
estaban llenas >= 100 ms antes de pulsar (no es el instante de sellado); y la
bolsa no esta sellada geometricamente (dos celdas puras con cuatro salidas).

## El orden causal (snapshots de 50 ms, columna i=9 j=59)

| t | p(k=3) | alpha_l(k=4) | uz_l(k=4) | uz_g(k=5) |
|---|---|---|---|---|
| 280.80 | 1.6 kPa | 0.596 | -1.79 | -63.9 |
| 280.90 | 3.4 kPa | 0.552 | -2.08 | -47.7 |
| 280.95 | 10.9 kPa | 0.526 | -1.96 | +13.5 |
| 281.00 | **35.3 kPa** | 0.492 | -0.38 | **+89.5** |
| 281.05 | 7.7 kPa | 0.458 | -0.07 | +3.5 |

El chorro del arco (gas a -64 m/s) empuja la celda de superficie hacia abajo a
2 m/s, dentro de la celda llena. Esta no tiene a donde ponerlo: la presion
salta, invierte el gas a +90 m/s hacia arriba y frena la entrada. Un golpe de
ariete sobre una celda empacada.

## La fila de presion de la celda del pico (sonda, cada 4 ms)

| paso | t | aW (hacia el bano) | aT (superficie) | aP | p | aPuz propia |
|---|---|---|---|---|---|---|
| 140440 | 280.880 | 8.2e-6 | 1.0e-7 | 8.3e-6 | 2.7 kPa | 1.3e5 |
| 140470 | 280.940 | 2.1e-6 | 1.2e-7 | 2.3e-6 | 7.8 kPa | 1.2e5 |
| 140490 | 280.980 | 2.9e-7 | 1.3e-7 | 4.2e-7 | 34 kPa | 2.0e5 |
| 140496 | 280.992 | 1.4e-7 | 1.4e-7 | 2.8e-7 | **58 kPa** | 2.5e5 |
| 140530 | 281.060 | 4.2e-9 | 1.8e-7 | 1.8e-7 | 7.5 kPa | 8.1e4 |

aE = aS = aB = 0 (paredes). Dos hechos:

1. **La celda es hidraulicamente rigida.** Su diagonal de momento vale
   1.3e5, 25 veces su inercia (alpha rho V/dt = 4.7e3). Es el **Ergun
   EFECTIVO del lecho de abajo** (F2.15, `compute_ergun_drag(on_bed=.true.)`:
   alpha_s_eff = 0.985, epsilon acotado a 0.01, A = 8.7e7, A·V = 1.1e5). Con
   d = alpha V/aP minusculo, sus coeficientes en el Poisson son 1e-6..1e-7, y
   la cara hacia la superficie — por donde entra el volumen — pesa 80 veces
   menos que la cara hacia el bano.
2. **Su unica conexion real se cierra durante la rampa**: aW cae de 8.2e-6 a
   4e-9 (2000 veces) mientras p sube. Con sum(a_nb) ~ 1e-7, un desbalance de
   volumen de 1e-4 m3/s — Su_liq +1.27e-2 y Su_gas -1.27e-2, que se cancelan
   solo aproximadamente: el gas entra por la cara de ALCANCE de F2.21 y el
   liquido sale soldado al chorro — exige miles de Pa por iteracion.

## Cuan general es

| t (s) | celdas de bano | sobre lecho | puras sobre lecho | p max en esas | p max resto |
|---|---|---|---|---|---|
| 200 | 64 | 64 | 0 | — | — |
| 250 | 142 | 142 | 29 | 3.95 kPa | 0 |
| 281 | 206 | **204** | 17 | **35.3 kPa** | 3.4 kPa |

**Practicamente todo el bano descansa sobre lecho**, porque el bano se forma
fundiendo hacia abajo: su capa inferior siempre esta sobre chatarra. La regla
del Ergun efectivo no es una excepcion, rigidiza TODA la base del bano. Y el
maximo de presion de la corrida vive exactamente en las celdas puras de esa
capa.

## Lectura

F2.15 anadio el Ergun efectivo para un CHARCO PARCIAL (alpha_l ~ 0.3) sin
chatarra propia que, sin ningun sumidero, caia libremente hasta U_LIQ_MAX. Una
celda LLENA no puede caer a ninguna parte — su fila del Poisson se lo prohibe —
y lo que necesita como sumidero es la presion, no un arrastre de 25 veces su
inercia que la vuelve incapaz de ceder volumen. El candidato de arreglo es que
el Ergun efectivo del lecho se desvanezca con el hueco de la celda (sin poro
abierto no hay percolacion), de modo que la celda empacada recupere una
diagonal normal y el Poisson pueda absorber el desbalance con 25 veces menos
presion. Pendiente de la literatura y de la sonda ampliada (aP radial y
azimutal) antes de implementar.

## Sonda ampliada y literatura: cierre del diagnostico

Las tres diagonales de momento de la celda del pico son iguales: aP_ur =
aP_uth = aP_uz = 1.3e5 (inercia 4.7e3). Es el Ergun efectivo, isotropo.

La literatura lo tiene nombre y manual: **water packing**. RELAP5 Vol. I
§3.4.6: "a liquid full cell and large liquid influx momentum [...] Because the
liquid is nearly incompressible, this large influx of liquid momentum will
cause a large increase in pressure". TRACE §2: "the boundary of a mesh cell
behaves like the dead end of a pipe in a water hammer event [...] a numerical
dead end for the liquid [...] push the liquid on through the cell face with an
abrupt increase in pressure", y TRACE iguala el coeficiente del vapor al del
liquido en esa cara "to prevent excessively large vapor velocities" — nuestro
gas a +90..+117 m/s. Lo que convierte a la celda en callejon aqui es el Ergun
efectivo del lecho (d minusculo), no la incompresibilidad sola; por eso el
remedio es de la familia "level tracking" (evitar el callejon) y no el parche
reactivo de RELAP5: **F2.28**, el Ergun efectivo se desvanece con
`1 - alpha_l`.

## F2.28, juez del pulso (280.5-282.2 s) y re-juez del caso de F2.15

| | base F2.24 | F2.28 |
|---|---|---|
| episodios p > 20 kPa | 5 | 3 |
| tiempo por encima de 20 kPa | 0.222 s | **0.058 s** |
| picos | 71-88 kPa | 59-69 kPa |
| u_gas max | 237 | 218 |
| u_liq max | 2.37 | 3.36 |

La rafaga baja a la cuarta parte en tiempo pero NO desaparece: quedan tres
pulsos de 16-26 ms a ~65 kPa. Restaurar el camino del liquido no quita el
ingrediente que queda: la celda de superficie, soldada al chorro, sigue
empujando liquido a 2 m/s dentro de una celda llena, y la presion tiene que
frenarlo dentro del paso.

Caso original de F2.15 (v31, 110 -> 113.8 s, el charco de alpha_l ~ 0.3 que
caia libremente): corrida que motivo F2.15: p_max 145 kPa, gas 300, liquido en
cota 2.7 % de los pasos; **con F2.28: 3.6 kPa, gas 58, ninguna cota, clip 0**.
F2.28 no reabre el caso de F2.15.

## F2.28, juez 250-296 s: NO cierra — mueve el fallo del liquido al gas

| tramo | base F2.24 (p / gas / liq / % cota liq) | F2.28 |
|---|---|---|
| 280-290 | 68 kPa / 218 / 11.5 / 0 | 90 kPa / 251 / 11.6 / 0 |
| 290-300 | 81 kPa / 133 / **20.0 / 32.8 %** | **125 kPa / 300** / 8.8 / 0 |

El liquido deja de tocar su cota en toda la ventana (la base la tocaba el
32.8 % de los pasos de 290-300), pero la presion sube y el gas toca U_GAS_MAX
a los 292.77 s — el mismo instante en que la base capaba el liquido (292.41).
Es la tercera vez que un arreglo del lado liquido descarga la correccion en el
gas (F2.25, F2.27 y ahora F2.28), y es literalmente lo que TRACE describe para
el water packing: la correccion de presion sale por la cara con mayor alpha_g
y dispara al vapor, por lo que TRACE iguala ahi el coeficiente del vapor al
del liquido. El evento de los 292 s no se ha caracterizado todavia (solo el
de los 281); `rafaga292` reinicia desde el snapshot de 290 s de este juez.

## El evento de los 292 s: un POR0 EMPACADO con la presion congelada (F2.29)

El reinicio denso desde el snapshot de 290 s del juez F2.28 (`rafaga292`)
reproduce el disparo — en el MINIMO de presion, que es lo que el audit reporta
como `p_max` (valor absoluto). Dos hallazgos de metodo por el camino:

- **El reinicio es fiel y la dinamica es caotica**: juez y reinicio son
  identicos en el primer paso (primera diferencia a 1e-9 en 290.012 s) y
  divergen desde el redondeo (1e-4 kg en m_liq a 290.5 s, 4e-4 a 291 s) hasta
  que el mismo evento ocurre a 293.0 s en vez de a 292.8 s. La fuente del
  redondeo es el deposito Monte Carlo del arco (MPI_SUM, no bit a bit). En una
  rafaga de fusion con poros sellandose, 1e-13 se vuelve macroscopico en 2 s.
- **`p_max` del audit es max |p|**: lo que parecia una meseta de +17.7 kPa era
  una SUCCION congelada de -17.7 kPa.

La celda: (5,40,2) numpy, un poro del lecho (alpha_s 0.769) completamente
lleno de liquido (alpha_l 0.231, alpha_g 0.000), bajo una celda de bano puro.
Su presion vale -17 693 Pa, identica a cinco cifras, durante 2.5 s. A los
292.7 s la vecina (4,40,2) se empaca igual y queda congelada en **-122 kPa**:
ese es el "125 kPa / gas a 300" del juez.

Sonda `[PROBE-P]` sobre esa celda (290.00-290.08 s):
act_l = T (liquido continuo en lecho: alpha_l >= 1e-2), act_g = F;
**aW = aE = aS = aN = aB = aT = 0 exactos**, Su = 0, aP = 6e-13 (solo la
compresibilidad acustica del liquido), **pp = 0 en todas las iteraciones**,
mientras sus seis vecinas corrigen entre -83 y +400 Pa.

Es Bug 16 en el caso que se le escapo. Bug 16 ("una celda sin fase continua
no tiene presion de fluido") impone el Neumann de las vecinas a las celdas con
`.not. act_l .and. .not. act_g`. Este poro ES act_l, pero el limitador de hueco
(F2.8, `face_open`) cierra toda cara hacia el (room <= eps), no tiene gas y
sus vecinas no le dan salida: fila activa con todas las caras cerradas. Su p
no la toca nadie y queda rancia — y las vecinas la leen como gradiente, como
describe la nota de F2.16 sobre Hilfer. Water packing DENTRO del lecho.

Censo: los poros empacados activos crecen con el bano (16 a los 100 s, 53 a
los 200, ~250 a los 290); en la serie densa 5-16 de ellos llevan la presion
congelada a 1e-3 entre snapshots. Son benignos mientras se sellan a presion
positiva pequena; el patologico es el que se sella en SUCCION.

**F2.29**: la fila activa cuyos seis coeficientes suman cero se marca
`sealed`, se vuelve trivial (aP = 1, Su = 0) y entra en el bloque de Neumann
de Bug 16 (excluyendo vecinas tambien selladas del promedio). La pared se
decide por el ESTADO hidraulico, no por la presencia de fase. Bancos: los tres
pasan; `bath_test` y `bath_fill` identicos; `bath_freeze` sube a 105 kPa
(cota 183) y gas 31 — la congelacion crea poros empacados y la pieza los toca.
Juez 250-296 con F2.28 + F2.29 en curso.

## F2.28 + F2.29, juez 250-296: tampoco cierra — y la conclusion de metodo

| tramo | base F2.24 | F2.25 | F2.27 | F2.28 | F2.28+F2.29 |
|---|---|---|---|---|---|
| 280-290 \|p\|max / gas / liq | **68 kPa / 218 / 11.5** | 84 / 237 / 5.0 | 134 / 277 / 19.9 | 90 / 251 / 11.6 | 92 / 252 / 20.0 |
| 290-300 \|p\|max / gas / liq | 81 / 133 / 20 (32.8 %) | 192 / 300 / 20 (0.3 %) | — | 125 / 300 / 8.8 (0 %) | — |
| primera centinela | liq 292.41 | gas/liq 295.6 | liq 281.31 | gas 292.77 | liq 285.05 |

Cinco candidatos, cinco instantes distintos de primera centinela, y en el
tramo 280-290 **ninguno es mas suave que la base**. Dos hechos obligan a
cambiar de metodo:

1. **La dinamica es caotica pasados los ~280 s** (medido: juez y su propio
   reinicio divergen desde 1e-9 hasta desplazar el mismo evento 0.2 s). Las
   centinelas son umbrales duros sobre un campo caotico: cual salta primero y
   cuando depende del redondeo. Juzgar por "tiempo hasta la primera centinela"
   en UNA trayectoria es leer ruido como senal.
2. Cada candidato corrigio un mecanismo REAL y medido (la pelicula en caida
   libre, el callejon del Ergun efectivo, el poro empacado congelado) y cada
   uno movio el fallo a otra variable y otro instante. El regimen 280-300 s de
   esta trayectoria es MARGINAL: varios mecanismos al limite a la vez, y
   aliviar uno carga a otro.

Lo que si es solido y queda: (a) F2.24 (caudal donor-cell) alargo la corrida
limpia de 205 a 225 s y el juez de 200-230 paso sin centinelas; (b) los tres
mecanismos estan caracterizados con sonda y literatura, y sus parches
archivados con sus medidas:
`2026-10-01_f226_f227_pelicula_sin_cerrar.patch`,
`2026-10-01_f228_ergun_efectivo_desvanece.patch`,
`2026-10-01_f229_poro_sellado_neumann_CON_sonda.patch`;
(c) las dos sondas de celda (`[PROBE-MOM]`, `[PROBE-P]`) se quedan en el
codigo, apagadas por defecto, documentadas en CONFIGURATION.

**Lo que haria falta para decidir entre candidatos**: un juez ESTADISTICO
(varias trayectorias de la misma ventana perturbando el redondeo, o una
ventana larga desde un estado limpio, 200 -> 300 s) con criterio de REGIMEN
ACOTADO (fraccion de pasos con |p| > 20 kPa, tiempo con gas > 200, con
liquido > 10) y no "tiempo hasta la primera centinela". Cuesta ~1.5 h por
trayectoria y ventana a 14 ranks. Es una decision de computo del usuario.

Arbol: codigo commiteado (30b466a) + sonda de presion + docs. test-quick en
verde, golden v32 bit a bit (las sondas estan apagadas por defecto).

---

# JUEZ ESTADISTICO (2-3 oct): F2.28 + F2.29 gana con claridad

Tres variantes x tres descomposiciones (12/14/15 ranks, que perturban el
redondeo del MPI_SUM del Monte Carlo del arco sin tocar la fisica), ventana
250-296 s desde el snapshot de 250 s de v34, audit a cada paso. Criterio de
REGIMEN ACOTADO (% de pasos), media +- desviacion entre descomposiciones:

| variante | %|p|>20 kPa | % gas>200 | % liq>10 | % alguna centinela | clip (kg) |
|---|---|---|---|---|---|
| base (F2.24) | 0.62 +- 0.01 | 0.15 +- 0.00 | 11.66 +- 0.94 | 0.47 +- 0.03 | 0 / 0.005 / 0.016 |
| F2.28 sola | 21.0 +- 9.9 | 8.3 +- 7.3 | 1.16 +- 0.94 | 1.99 +- 2.82 | 8.3 / 3.1 / 6.8 |
| **F2.28 + F2.29** | **0.43 +- 0.18** | **0.04 +- 0.01** | **0.32 +- 0.22** | **0.11 +- 0.10** | 5.3 / 3.6 / 5.7 |

Lecturas:

1. **F2.28 sola es MALA**: ablandar la base del bano sin tratar el poro
   empacado dispara la presion (21 % de los pasos sobre 20 kPa, con una
   dispersion enorme entre trayectorias: 7.6 a 31 %). Las dos piezas van
   juntas, igual que en F2.15.
2. **F2.28 + F2.29 mejora las cuatro metricas** y con separacion clara de la
   base: el liquido sobre 10 m/s cae 36 veces (11.7 % -> 0.32 %), el gas sobre
   200 m/s 4 veces, la presion sobre 20 kPa un 30 %, y los pasos con alguna
   centinela 4 veces. Los maximos instantaneos tambien bajan: |p| 190-670 kPa
   en la base frente a 82-155 kPa.
3. **La dispersion entre descomposiciones de la base es minuscula** (0.62 +-
   0.01 en presion) y sin embargo la primera centinela cae en instantes
   distintos (292.4, 293.2, ...): confirma que el "tiempo hasta la primera
   centinela" era ruido y el criterio de regimen no lo es.
4. **El coste, declarado**: el clip auditado sube de ~0 a 3.6-5.7 kg en la
   ventana (f229_n14: desde 281.37 s, maximo 2.6 g por paso, 3.61 kg en 15 s,
   el 0.17 % del bano). Coincide con la rafaga de fusion (derrame de 70-126 kg
   por 5 s) y es la contabilidad honesta del volumen que en la base se iba en
   velocidad espuria (el liquido a 20 m/s era la valvula de escape). Es
   masa auditada, no silenciosa, y hay que vigilar que no crezca en la colada
   larga.

**Decision**: se adopta F2.28 + F2.29 (golden v33). La colada se relanza con
el audit vigilando clip ademas de las centinelas.

---

# COLADA v35 (F2.28 + F2.29): se detuvo a los 411 s — dos cosas distintas

Lanzada 3-oct 16:47 (14 ranks, nice 5). Limpia hasta ~230 s; primera presion
> 20 kPa a 280.77 s; gas en cota a 281.61; liquido > 10 m/s a 293.10;
P_HYDRO_CAP (2 MPa) a 322.27; a partir de ahi 96 % de los pasos con |p| > 20
kPa y 80 % con gas en cota. El usuario la mato a los 411 s (yo no puedo:
el clasificador de permisos bloquea `pkill`).

**El juez de 250-296 era demasiado corto.** En esa ventana v35 fue un sorteo
peor que las tres corridas del juez (3.75 % de pasos > 20 kPa frente a
0.55-1.82) pero del mismo orden; el deterioro real esta en 296-322 (17 %) y
322+ (96 %), fuera de lo juzgado. La nota del audit: `u_liq_max` cuenta
cualquier celda con alpha_l >= 1e-2, dispersa incluida, asi que los 49.94 m/s
son drift de gotas (U_SETTLE_MAX), no celdas continuas saltandose la cota
(snapshots: ninguna continua > 19.5).

## Mecanismo 3 — el arco calienta el gas de poro a decenas de miles de K

Snapshots a 250/300/350/400 s, gas de PORO (alpha_s >= 0.5, alpha_g <= 0.02):

| t | n poro | T_g p90 | T_g max | n > 6000 K | S_arc en poros |
|---|---|---|---|---|---|
| 250 | 488 | 1905 | 4186 | 0 | 0.0 % |
| 300 | 933 | 1796 | 4666 | 0 | 0.0 % |
| 350 | 1475 | 1650 | 2842 | 0 | 0.0 % |
| 400 | 1231 | **8114** | **54 211** | **359** | **6.1 %** |

Coincide con el fin del bore-in: `elec_z_tip` 1.4 -> 0.9 -> 0.65 m
(`bore_in_done` = 1 entre 350 y 400). Con la punta DENTRO del lecho, los
rayos laterales del Monte Carlo entran en celdas de chatarra densa.

La cadena, en el codigo:
- `distribute_arc_radiation_mc`: el rayo deposita TODA su energia en la
  primera celda con `alpha_s > 0.1` ("hits solid") o con `z < H_bowl + 0.5`,
  como fuente volumetrica `S_arc` de la celda, sin mirar fases.
- `solve_energy_3d`: `S_arc` se reparte SOLO entre liquido y gas con
  `w = alpha_q/(alpha_l + alpha_g)`. El solido no recibe nada por esa via. En
  una celda con alpha_s 0.985, alpha_g 0.015, alpha_l 0: el gas de poro
  (atrapado, masa ~1e-3 kg) se lleva el 100 % del rayo que "choco con la
  chatarra". De ahi 50 kK con el solido de la misma celda a 1500-1800 K.
- Las vias que SI alimentan al solido tienen el patron correcto: el deposito
  directo del arco (`mod_arc_cassie_mayr`, `sol%E_s += Q_rad` con cota
  `DT_RAD_MAX = 2 K` por paso y el excedente a `S_arc`) y la radiacion DO
  (`kappa_solido*alpha_s` = 10*alpha_s contra `kappa_gas*(1-alpha_s)` =
  0.3*(1-alpha_s): en un poro, 99.95 % al solido).

**Es PREEXISTENTE**: v33 a 400 s tiene 204 celdas > 6000 K (max 11 188 K,
4.7 % del S_arc en poros) con la punta en 0.65 m. v34 se detuvo a 294, antes
del bore-in. Ningun candidato de esta semana lo toca ni lo causa.

Consecuencia hidraulica: ese gas atrapado a 8000-54000 K esta en celdas pared
(F2.16) cuya p viene del Neumann de Bug 16: a 350 s la celda del maximo
(77.8 kPa, k=1) COPIA la p de la celda de arriba y sus cuatro vecinas
laterales y la de abajo estan a 0 exacto (sin vecina con fluido, nnb = 0):
523 celdas del fondo del lecho a p = 0 y 553 con p identica a la de arriba.
Un mosaico de 0 y copias en la base del lecho.

## Mecanismo del pulso de 322 s (2 MPa): pendiente

Precede al fin del bore-in (T_g de poro aun sana a 350). Reinicio denso
300 -> 325 s en `scratchpad/cand/v35_322` en curso.

## El colapso de los 322 s de v35: SUCCION en el piso del lecho (fila CASI sellada)

Reinicio denso 300->325 (`v35_322`) lo reproduce: primera |p|>20 kPa a 302.9,
liquido en cota a 303.2, gas en cota a 321.5, P_HYDRO_CAP a 325.0. El extremo
es una SUCCION: 68 celdas a p < -100 kPa a 325 s, todas en k = 0-3 (piso del
lecho), alpha_s mediana 0.89, alpha_l 0.01, alpha_g 0.016 (piso de poro), T_g
~1000 K y subiendo. La presion PARPADEA entre snapshots (-131 kPa, luego +9 kPa,
luego -176 kPa en celdas vecinas) hasta saturar en -2 MPa.

Sonda [PROBE-P] sobre (2,52,1) Fortran (reinicio 322.5 -> 323.1, 4 ranks):

| t | aS (unica cara real) | sum a_nb | aP | Su_gas | Su_comp | p |
|---|---|---|---|---|---|---|
| 322.76 | 1.4e-6 | 1.4e-6 | 1.4e-6 | +1.1e-4 | -1.8e-4 | 7.9 kPa |
| 322.92 | 1.1e-6 | 1.1e-6 | 1.1e-6 | +1.3e-4 | -1.8e-4 | 2.3 kPa |
| **322.93** | **0** | **8e-9** | 1.7e-8 | +1.4e-4 | -1.9e-4 | **-55 kPa** |
| 323.10 | 0 | 4e-9 | 1.4e-8 | +1.8e-4 | -1.9e-4 | -139 kPa |

Su_liq = 0. En un paso la unica conexion real (aS) cae a CERO exacto (el
limitador de hueco cierra la cara al llenarse el poro de la vecina) y la fila
queda con conductancia 100-200 veces menor pero NO nula. F2.29 solo atrapa
filas con suma exactamente cero. El desbalance residual de volumen (gas que
entra por flujo frente a la fuente de compresibilidad termica, se cancelan
salvo ~7e-6) dividido por 1e-8 da pp ~ -500..-700 Pa POR ITERACION, sostenido:
la presion de la celda deriva sin cota (-55 -> -139 kPa en 0.17 s). Es
exactamente la patologia de F2.13 (gas de poro solo que integra presion por su
compresibilidad), ahora con la percolacion de F2.16 declarandolo conectado
porque su movilidad se mide con el ARRASTRE, no con la conductancia real que le
queda en el Poisson.

Literatura ya reunida que aplica: Hilfer (subfase desconectada: su presion no
pertenece al campo conectado) y la deteccion de water packing de RELAP5/TRACE
(subida de presion predicha por encima de un umbral en una celda casi cerrada).
Lo que NO esta resuelto es el criterio: "casi cerrada" exige comparar la
conductancia con una escala, y las escalas naturales (dt/rho del liquido) son
ellas mismas de 1e-9, asi que un umbral absoluto o relativo a la celda no
separa este caso del sano. Opciones: (a) umbral relativo a la conductancia
PREVIA de la propia celda (colapso de 100x en un paso -> sellada); (b) criterio
de prediccion tipo TRACE (|pp| predicho > P_SEAL con conexiones casi nulas);
(c) que la percolacion de F2.16 use la conductancia del Poisson en lugar de la
movilidad por arrastre. NO implementado: decision pendiente.

## Juez LARGO limpio (v35 a 250 s -> 420 s, F2.28 + F2.29 + F2.30 + F2.31): NaN a 370.002 s

| 250-370 s | %|p|>20k | %gas>200 | %liq>10 | %centinela | clip |
|---|---|---|---|---|---|
| v35 base (F2.28+F2.29) | 41.5 | 29.9 | 41.3 | 16.5 | 24 kg |
| + F2.30 + F2.31 | 39.3 | 13.9 | 42.7 | 3.7 | (NaN al final) |

Identico a la base hasta 280 s; el gas mejora a la mitad y las centinelas 4.5x
menos, pero **la presion NO**: el colapso del piso desde ~320 s sigue (78-100 %
de los pasos sobre 20 kPa en 320-370). Gas de poro sano en todos los snapshots
(max 5164 K, ninguna celda > 6000 K hasta 350 s): F2.30 hace lo suyo.

A 370.002 s, con la presion ya saturada, la corrida revienta por CREACION DE
MASA: m_sol -312 kg, luego -32 t, luego todo; m_liq a 1.36e6 kg y NaN en 3
pasos. El estado del solido a 350 s es sano (T_s max 1806 K, E_s/m_s max
9.7e5 J/kg, igual que v35). No caracterizado: es un desenlace terminal de un
regimen que ya estaba roto. F2.31 no cierra el mecanismo 4.

## F2.32 — salvaguarda de water packing de RELAP5/TRACE (5-oct-2026, decision del usuario)

Tras un mes de cierre pieza a pieza, el usuario elige la salvaguarda numerica
de los codigos de sistemas en lugar de seguir caracterizando cada mecanismo
(la opcion "correcta de libro", acople implicito α–p, queda diferida).

Fuentes:
- RELAP5/MOD3 Code Manual Vol. I (NUREG/CR-5535-V1, 1995) §3.4.6 "Water
  Packing Mitigation Scheme", ecs. 3.4-72 a 3.4-74 (pp. 3-170 a 3-172).
- TRACE V5.0 Theory Manual (NRC ML120060218) cap. 2 "Water Packing", ecs.
  2-56/2-57 (pp. 96-98); el cap. 7 reconoce "limited success" del esquema.
- Liles & Reed, J. Comput. Phys. 26 (1978) 390 (origen del termino);
  Abe et al., J. Nucl. Sci. Technol. 30(12) (1993) 1214; Lim et al. (KAERI
  2002) — solo resumen consultado.

Implementacion (`mod_pressure_3d`, tras el CG): celda con liquido activo,
vacio fluido α_g/(α_l+α_g) ≤ 0.1, |α_p·pp| ≥ max(7 % de la presion absoluta,
50 kPa) y una vecina activa con MAS vacio (salida): diagonal × 1e6 y se
re-resuelve el CG con los mismos coeficientes (la celda se "estira": su
correccion de presion queda practicamente congelada y el desbalance sale por
las vecinas). Imprime `[WPACK] paso N : M celdas`.
Desviacion de las fuentes: TRACE solo estira si p < p_sat − 20 K (condensacion
subita); para acero sin cambio de fase liquido-vapor la condicion no aplica y
se estira en ambos signos de Δp. Umbrales fieles a los manuales; no se
ajustaron para que la salvaguarda atrape el caso.

Tests: gates fisicos intactos (arc_budget 1.0000, melt_forced 3.7e-5,
xfails de siempre). Golden se mueve por F2.30/F2.31 (medias con signo de
campos ~0). Una activacion en todo el banco: bath_freeze paso 2 (4 celdas,
arranque del remanente de 180 t sobre chatarra fria).

Juez: `scratchpad/cand/judge_largo_F232` (v35 a 250 s -> 420 s, 14 ranks,
F2.28-F2.32). Resultado: pendiente.

### Resultado del juez de F2.32 (detenido a 335 s por decision del usuario)

[WPACK] actuo 3 veces (1 celda c/u) en 250-322 s. 290-320 s: p>20k 16.7 %
(F2.31: 8.1, v35: 10.0), liq>10 20.5 %, centinelas 10.8 %. 320-322 s: p>20k
31 % (F2.31: 81) pero el liquido en U_LIQ_MAX ~100 % desde ~318 s. Los
criterios de RELAP5/TRACE (vacio <= 0.1) casi no atrapan la succion del piso:
ese fallo NO es water packing clasico. F2.32 no se commitea en esta forma.

F2.32 retirada del codigo (bloque archivado en
`2026-10-05_f232_water_packing_relap5_trace_DESCARTADA.f90.txt`). Se commitean
F2.30 + F2.31 con golden v34. Siguiente: (a) juez de paso de tiempo 1 ms y
0.5 ms desde v35 a 300 s; (b) regla de regimen "liquido en el lecho = goteo"
(fuera del Poisson) previa revision de literatura.
