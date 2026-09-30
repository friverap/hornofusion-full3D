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

# CAUSA RAIZ (encontrada el 29-sep-2026 al probar F2.22)

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

Parche completo en `docs/dev-history/2026-09-29_f222_aiad_mezcla_bloqueada.patch`.
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
