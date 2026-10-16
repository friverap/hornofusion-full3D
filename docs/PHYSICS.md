# Modelos Físicos — EAF3D

Documentación completa de todos los modelos físicos implementados en el simulador 3D de horno eléctrico de arco.

---

## Tabla de contenidos

1. [Coordenadas y malla](#1-coordenadas-y-malla)
2. [Flujo multifase Euler-Euler](#2-flujo-multifase-euler-euler)
3. [Algoritmo SIMPLE](#3-algoritmo-simple)
4. [Turbulencia k-ε](#4-turbulencia-k-ε)
5. [Transferencia de calor y energía](#5-transferencia-de-calor-y-energía)
6. [Arco eléctrico](#6-arco-eléctrico)
7. [Radiación Monte Carlo del arco](#7-radiación-monte-carlo-del-arco)
8. [Radiación Ordenadas Discretas (DO)](#8-radiación-ordenadas-discretas-do)
9. [Fuerza de Lorentz](#9-fuerza-de-lorentz)
10. [Arrastre Ergun (lecho poroso)](#10-arrastre-ergun-lecho-poroso)
11. [Fusión y solidificación](#11-fusión-y-solidificación)
12. [Química del carbono](#12-química-del-carbono)
13. [Transporte de especies O₂ / CO / CO₂](#13-transporte-de-especies-o₂--co--co₂)
14. [Escoria](#14-escoria)
15. [Transferencia de calor interfase](#15-transferencia-de-calor-interfase)
16. [Buoyancy de Boussinesq](#16-buoyancy-de-boussinesq)
17. [Constantes físicas](#17-constantes-físicas)

---

## 1. Coordenadas y malla

### Sistema de coordenadas

Coordenadas cilíndricas `(r, θ, z)`:

- **r**: dirección radial, 0 ≤ r ≤ R_shell
- **θ**: dirección azimutal, 0 ≤ θ < 2π (periódico)
- **z**: dirección axial, 0 ≤ z ≤ H_total

El origen z = 0 es el fondo del cuenco (bowl). El techo está en z = H_total.

### Malla FVM con estiramiento

Distribución no uniforme tipo hiperbólica con factor de estiramiento `stretch_r` y `stretch_z`.  
Las celdas son más densas cerca del eje y del fondo del cuenco.

Malla de producción: **60 × 120 × 84 = 604,800 celdas**

### Halos MPI

Todas las matrices se asignan con halos: índices `(-1:nr+2, -1:nth+2, -1:nz+2)`.  
Las celdas físicas son `(1:nr, 1:nth, 1:nz)`.  
Los halos permiten acceso a celdas vecinas entre ranks MPI sin sincronización adicional dentro del bucle de actualización.

---

## 2. Flujo multifase Euler-Euler

### Fases presentes

| Fase | Variable | Descripción |
|------|----------|-------------|
| Gas | `gas` | Mezcla CO/CO₂/aire caliente |
| Líquido | `liq` | Acero fundido |
| Sólido | `sol` | Chatarra/HBI (dual-cell, sin N-S) |
| Escoria | `slag` | Pseudo-fase por flotabilidad |

### Restricción de fracción de volumen

```
α_gas + α_liquid + α_solid + α_slag = 1
```

### Ecuaciones de momentum (por fase fluida q ∈ {gas, liq})

```
∂(αq ρq uq)/∂t + ∇·(αq ρq uq ⊗ uq) = -αq ∇p + ∇·(αq τq) + αq ρq g + Sq
```

donde `Sq` incluye:
- Arrastre Ergun (interacción fluido-sólido)
- Fuentes de arco: S_arc_mom (impingement)
- Fuerza de Lorentz: F_lorentz_r, F_lorentz_th (solo líquido)
- Buoyancy de Boussinesq (solo uz, líquido)

### Ecuación de continuidad multifase

```
∂αq/∂t + ∇·(αq uq) = 0
```

Discretizada con FVM implícito, resuelta con SIMPLE.

### Propiedades del gas

Gas ideal con compresión física (auditoría M25, `gas_eos` en `mod_constants`):

```
ρ_gas = ρ_ref · (300 K / T) · (P0 + p) / P0     ρ_ref = 1.2 kg/m³, P0 = 101325 Pa
μ_gas = 5×10⁻⁵ Pa·s
k_gas = 0.5 W/(m·K)
```

`p` es la presión manométrica del código (cero en la bóveda); la absoluta tiene
un piso de 0.05·P0. La continuidad de volumen del gas en el Poisson lleva
`(α_g/ρ_g) Dρ_g/Dt`: la parte temporal contra ρ(P0 + pⁿ, Tⁿ) (contiene el
término `(p^k − pⁿ)/(P0 + p)`, que no se anula al converger), su linealización
de Newton `α_g/(P0 + p) V/Δt` en la diagonal, y la advectiva upwind de A8. Un
bolsillo de gas atrapado se comprime como un resorte real. La energía del gas no
lleva el trabajo de compresión (orden p/P0 frente al calor sensible). El modelo
de mezcla (opt-in, Plan G) sigue en ρ(P0, T): con la compresión física su baño
en reposo es inestable (el gas es el complemento de la mezcla, sin masa propia).

---

## 3. Algoritmo SIMPLE

### Estructura del bucle externo

```
for each timestep:
    1. Actualizar arco, radiación, química
    2. for outer = 1..max_outer:
        a. Calcular drag Ergun
        b. Resolver momentum (u*, v*, w*)
        c. Resolver corrección de presión (p')
        d. Corregir velocidades y presión
        e. Resolver energía
        f. Resolver turbulencia k-ε
        g. Verificar convergencia
    3. Actualizar fase sólida (fusión, collapse)
    4. Actualizar escoria
    5. Actualizar dt adaptativo
```

### Relajación sub-relajación

```
φ_new = α_φ · φ* + (1 - α_φ) · φ_old
```

| Variable | Factor α | Config |
|----------|----------|--------|
| Velocidad u | 0.3 | `alpha_u` |
| Presión p | 0.7 | `alpha_p` |
| Temperatura T | 0.7 | `alpha_T` |
| k turbulento | 0.5 | `alpha_k` |
| ε turbulento | 0.5 | `alpha_eps` |
| Fracción vol. α | 0.3 | `alpha_alpha` |
| Especies Y | — (sin relajación: una solución por paso) | — |

### dt adaptativo

```
dt_new = dt_old × factor(residual)
dt = clamp(dt_new, dt_min, dt_max)
```

---

## 4. Turbulencia k-ε

### Ecuaciones de transporte

**Energía cinética turbulenta k:**
```
∂(ρk)/∂t + ∇·(ρu k) = ∇·((μ + μt/σk)∇k) + Pk - ρε
```

**Tasa de disipación ε:**
```
∂(ρε)/∂t + ∇·(ρu ε) = ∇·((μ + μt/σε)∇ε) + C1ε (ε/k) Pk - C2ε ρ ε²/k
```

### Viscosidad turbulenta

```
μt = min(Cμ ρ k²/ε, 10⁵ μ)        (tope de la razón de viscosidad)
```

Solo en líquido **continuo**. Producción de flotabilidad
`G_b = max(0, −β g (μt/Prt) ∂T/∂z)` (caliente abajo = inestable; signo
corregido en M8). En la celda junto a una pared, función de pared de alto
Reynolds (Launder–Spalding): `ε = Cμ^¾ k^{3/2}/(κ y_P)`, κ = 0.41, y_P la
media celda normal a la pared (el eje es simetría).

### Constantes del modelo k-ε estándar

| Constante | Valor |
|-----------|-------|
| Cμ | 0.09 |
| C1ε | 1.44 |
| C2ε | 1.92 |
| σk | 1.0 |
| σε | 1.3 |
| Prt | 0.85 |

### Viscosidad efectiva

```
μ_eff = μ_molecular + μ_t
```

Usada en momentum, energía, y transporte de especies.

---

## 5. Transferencia de calor y energía

### Ecuación de energía (por fase fluida q)

```
∂(αq ρq cp,q T)/∂t + ∇·(αq ρq cp,q u T) = ∇·(αq k_eff ∇T) + Sq
```

donde `Sq` incluye:
- `S_arc`: calor del arco eléctrico
- `S_rad`: fuente/sumidero de radiación DO
- `S_chem`: calor de reacciones química (C→CO y CO→CO₂)
- Transferencia de calor interfase gas↔sólido, líquido↔sólido

### Conductividad efectiva

```
k_eff = k_molecular + μt · cp / Prt     con Prt = 0.85
```

### Discretización temporal

Euler implícito: `∂(ρcp T)/∂t ≈ ρcp (T - T_old)/dt`

Convección: upwind de primer orden  
Difusión: diferencias centrales

---

## 6. Arco eléctrico

> Revisado tras la auditoría del 12-oct-2026 (C2, A9, A10, B4–B8). La EDO de
> Cassie–Mayr que esta sección describía se retiró: su R no se usaba y su
> término P_rad·R no era dimensionalmente coherente.

### Estado eléctrico

V e I por electrodo vienen del perfil medido (`electrode_profile_file`, por
defecto `input/electrode_profile.dat`; `''` = constante `elec_V_const` /
`elec_I_const`; un archivo configurado que no abre es error):

```
P_arc = |V · I|                    potencia del arco por electrodo
l_a   = max((|V| − 40 V) / 1150 V/m, 0.01 m)   longitud de arco (gradiente de columna)
R_arc = |V| / |I|                  diagnóstico
```

**Corriente alterna sin desfase (decisión de diseño, auditoría bajos).** Los
tres electrodos usan el mismo V/I **eficaz** del perfil, sin el desfase de
120° de la trifásica. Es coherente con un modelo promediado en el ciclo de
50/60 Hz (Δt ≫ 20 ms): potencia (V·I) y fuerza de Lorentz (∝ I²) son
cantidades cuadráticas cuyo promedio no depende de la fase. Lo que se pierde
es la interacción magnética instantánea entre arcos (deflexión de arco), que
este modelo no resuelve.

### Distribución del calor del arco

| Fracción | Destino |
|----------|---------|
| `frac_rad` × `MC_RAD_SHARE` (0.5) | Monte Carlo (§7) |
| `frac_rad` × (1 − `MC_RAD_SHARE`) | depósito directo en la superficie de la chatarra bajo el electrodo; **sin chatarra, también al MC** (`mc_share` = 1) |
| `frac_conv` | columna de gas entre la punta y la superficie de chatarra; **sin chatarra, la capa de la superficie del baño** (chorro de plasma que impacta). La superficie (chatarra o baño) se decide en UN solo barrido por contenido ponderado con la gaussiana del arco hasta 4σ (primera capa en la que la chatarra, medida por su fracción del volumen ponderado de la capa con umbral `ARC_SURF_FRAC_S` = 5 %, y el baño, medido por su espesor equivalente con umbral `ARC_SURF_H` = 0.014 m, suman 1 en unidades de sus umbrales; si el baño pasa su umbral, chatarra si Σwα_s ≥ Σwα_l y la chatarra pasa el suyo; si no, el material más cercano a su umbral, auditoría 8 M8-1. Auditoría 6 M6-5: con el 5 % del volumen también para el baño, en la malla de producción bastaban ~13 kg de líquido para recibir P_elec. Auditoría 7 M7-1: con el espesor también para la chatarra, un cráter a medio fundir, con α_s < 0.22–0.37, dejaba de ser superficie; auditoría 4 M4-7, auditoría 5 A5-1: con la regla antigua del baño, una celda con α_l ≥ 0.3 a < 2σ, un electrodo mandaba 5.5 MW de P_elec a una celda casi vacía mientras los otros dos usaban la capa de contenido) |
| `frac_elec` | tras el bore-in, SOLO las celdas de baño (α_l ≥ `ALPHA_LIQ_CONT`) de la capa de superficie del baño elegida por contenido (gaussiana hasta 4σ, peso α_l V; auditoría 3 A3-4: antes una gota con α_l > 1e-6 en la columna recibía todo P_elec; A5-1: misma capa que P_conv); con chatarra como superficie o sin baño, con `frac_conv`; antes del bore-in, con `frac_conv` |

(Auditoría 2, N-A2: con baño plano el líquido recibía el 6.9 % del arco
absorbido; ahora 71 %, el resto es la atenuación del gas en el camino del MC.)

En una celda con chatarra el depósito se reparte por **absorción**
(κ_s α_s frente a κ_g α_g, F2.30), y lo que queda en `S_arc` se reparte entre
líquido y gas también por absorción (κ_l α_l frente a κ_g α_g, el mismo peso
que la radiación de la DO); la parte del sólido entra a `E_s` con un
tope de **estado** (T_s ≤ T_liq + 100 K, `solid_arc_room`) y el exceso va a
`S_arc`. La escoria intercepta su parte de `S_arc` también por absorción
(κ_sl α_sl + κ_foam α_foam frente a κ_l α_l + κ_g α_g).

### Regulación de electrodos

```
z_target = z_superficie + l_a          superficie = tope de chatarra (α_s > 0.05) o de baño (α_l ≥ 0.3)
bore-in:     dz = clamp(z_target − z_tip, −BORE_IN_SPEED dt, +ELEC_SPEED_MAX dt)
regulación:  dz = clamp((z_target − z_tip) min(1, dt/TAU_REG), ±ELEC_SPEED_MAX dt)
```

El bore-in termina cuando el material superior bajo el electrodo es baño.
Una recarga de cesta retrae los electrodos y reinicia el bore-in.

---

## 7. Radiación Monte Carlo del arco

1. Emisión isótropa desde puntos repartidos a lo largo de la **columna** del
   arco (de la punta al pie z_tip − l_a), `n_beams` rayos por electrodo.
2. Paso `0.5 × min(dr)`; en cada celda el gas absorbe por Beer–Lambert
   `dP = P (1 − exp(−κ_g α_g ds))` y lo deposita en esa celda.
3. Impacto: chatarra (α_s > `ALPHA_SCRAP_SURF` = 0.05) o superficie del baño
   (α_l ≥ `ALPHA_LIQ_CONT`).
4. El rayo que entra en un electrodo (sombra) o sale del dominio se audita como
   `E_mc_lost`. El trazado es cartesiano: el rayo cruza el eje sin obstáculo
   (eje real, auditoría M31).
5. Depósito por absorción sólido/fluido como el depósito directo (§6).

Semilla por paso, la misma en todos los ranks (aritmética de 64 bits); los
rayos se reparten round-robin y el depósito se reduce con `MPI_SUM`.

---

## 8. Radiación Ordenadas Discretas (DO)

Cuadratura de simetría de nivel S4/S6/S8 (`do_quadrature`: 24/48/80
direcciones), barridos TDMA iterados hasta `RTE_SWEEP_TOL` (aviso si no
converge). Proyecciones de cara integradas exactas en cilíndricas.

```
s · ∇I = κ (B − I),   κ = κ_g α_g + κ_l α_l + κ_s α_s + κ_foam α_foam
κ_g = 0.3, κ_l = 100, κ_s = 10, κ_foam = 30 1/m   (una sola definición, mod_constants)
S_rad,q = (κ_q α_q / Σκα) κ_f (G − 4σT_q⁴)        reparto por absorción (A11)
```

Sin limitador de `S_rad`: la radiación es implícita (linearización de Newton
alrededor del iterado). Paredes: la coraza y el techo son frías; el tazón, el
piso y el eje re-irradian (`Bmix` de la celda). La DO no es invariante a
rotaciones de 120° (efecto de rayos de S4). **El reparto por fase lo fija la
DO** (auditoría 5, M5-1): `sh%w_rad_l` = κ_l α_l/κ_f con la α del momento de
la llamada (αⁿ; una fase bajo `ALPHA_CUTOFF` no emite ni absorbe, B4-13) y la
energía lo usa tal cual para absorción y emisión. Con α^{n+1} del SIMPLE en la
energía la absorción cerraba (Σw = 1) pero la emisión no: κ_f 4σ[(w^{n+1} −
wⁿ) T⁴] V dt de energía creada en cada paso con fusión (el 1 % radiativo de
`melt_forced`: −1.2e5 J → +51 J). El arco (`S_arc`) conserva el reparto por
α^{n+1} (`rad_weight`): su presupuesto cierra por construcción.

---

## 9. Fuerza de Lorentz

Fuente puntual de corriente en un conductor semi-infinito (Shercliff 1970;
Sozou 1971; auditoría M11). La corriente entra al baño en el punto P más bajo
entre el pie del arco y el tope del baño bajo el electrodo, y se reparte
radialmente en el hemisferio inferior:

```
J = I / (2π ρ²),   B_φ = μ₀ I (1 − cos θ) / (2π r_loc),   ρ² ← ρ² + R_elec²,   cos θ = √(dz² + R_elec²)/ρ  (fuente a profundidad efectiva: B → 0 en el eje del electrodo; auditoría 2, N-A3)
F = −J B θ̂,   θ̂ = cos θ ê_h + sin θ ẑ    (hacia el eje y hacia abajo)
```

Rotacional no nulo: impulsa el chorro descendente bajo el electrodo. Solo en
líquido **continuo** (α_l ≥ 0.3) y solo en la ecuación del líquido.
Magnitud típica 10²–10³ N/m³ cerca del electrodo.

---

## 10. Arrastre Ergun (lecho poroso)

```
A_E = 150 μ (1 − ε)² / (d_p² ε³),   B_E = 1.75 ρ (1 − ε) / (d_p ε³)
coef = ε² A_E + ε³ B_E |u|          (forma de Gidaspow para velocidad intersticial, A6)
```

ε = 1 − α_s para el líquido; para el gas del lecho, ε = 1 − α_s − α_l (el
líquido retenido es obstáculo: Sáez & Carbonell 1985, M29). Única definición:
`mod_constants::ergun_coefficients`. El Ergun efectivo del lecho sobre una
celda de líquido se desvanece con su α_l (F2.28).

---

## 11. Fusión y solidificación

Entalpía única del sólido (C1.8), con el latente en la zona mushy:

```
e_s(T) = c_s T                                T ≤ T_sol
       = c_s T_sol + c_m (T − T_sol)          T_sol < T ≤ T_liq,   c_m = c_s + L/(T_liq − T_sol)
       = e_lb + c_l (T − T_liq)               T > T_liq,           e_lb = c_s T_liq + L
e_l(T) = c_l T + C0,   C0 = (c_s − c_l) T_liq + L   (mismo dato: e_l = e_s sobre T_liq)
```

**Regla de la palanca (auditoría M9):** fusión y congelación son estados, no
tasas por paso.

```
sólido con e > e_sol:  f = (e − e_sol)/(e_lb − e_sol),  dm = f m_s sale a e_lb (T_liq),
                       el resto queda en e_sol;  con e ≥ e_lb la parcela entera sale con su e
líquido con T < T_liq: dm = M (e_lb − e_l)/(e_lb − e_entry),  e_entry = min(e_sol, e_l),
                       acotado por RESOLID_LIMITER M (positividad del transporte de α)
```

La fusión por paso resulta Q/(e_lb − e_sol): la condición de Stefan con el
calor recibido. `compute_melting` devuelve la T de entrada del fundido
(`ws_Tsrc`). El remanente bajo `ALPHA_SOLID_RESID` se cierra (masa y entalpía
al líquido) solo si ya alcanzó el solidus (M10).

### Colapso de chatarra

La chatarra sobre un hueco cae conservando su **empaquetamiento** (α del
trozo), sin superar el hueco libre de líquido y escoria; lo que no cabe se
apila hacia arriba (A4). Una celda de baño no es hueco.

---

## 12. Química del carbono

**Primaria (superficie de la chatarra), C + ½O₂ → CO:** cinética de Maahs
con `P_O₂ = P0 · x_O₂` (fracción molar con la masa molar real de la mezcla
O₂/CO/CO₂/N₂), limitada por el carbono del inventario `m_C` y por el O₂ de la
celda en el paso (en la práctica siempre por el O₂). El carbono oxidado
**sale del acero** (`m_s`, `E_s`; columna `m_C_oxid`, M15) y su entalpía
pasa al gas; el calor de reacción (110.5 kJ/mol) va al sólido.

**Secundaria (fase gas), CO + ½O₂ → CO₂:** segundo orden en densidades
parciales, `r = A ρ_CO ρ_O₂ exp(−E/RT_g)`, limitada por el CO y el O₂ del
paso; el calor (283 kJ/mol) va **solo al gas**.

---

## 13. Transporte de especies O₂ / CO / CO₂

```
α_g ρ_g DY_k/Dt = div(Γ_f ∇Y_k) + S_k − Y_k S_gas,    S_gas = Σ S_k
```

La masa del gas la fija la ecuación de estado; la masa que aportan las
reacciones entra al Poisson como fuente de volumen `S_gas/ρ_g` y en las
especies como dilución `−Y_k S_gas` (M14; columnas `m_dil_*`): ΣY ≤ 1.
Difusión de cara armónica `Γ_f` de α μ_eff/Sc_t, nula hacia celdas sin gas;
sin convección entrante desde celdas sin gas (M16). Sin sub-relajación (se
resuelven una vez por paso; A2). `solve_chemistry` exige `solve_species`.

---

## 14. Escoria

Pseudo-fase sin momento propio. Flotación por **columna global** (gather +
mismo barrido en todos los ranks): la escoria asciende hasta el tope del baño
o desciende cuando el material de abajo desaparece, nunca entra a celdas
llenas de chatarra, y `α_sl = m_sl/(ρ_sl V)` (A14); el gas que crea o destruye al reescribir
α_g se audita en masa y energía de inventario (`m_gas_volfix`,
`E_gas_volfix`; auditoría 4, M4-13), **y el gas creado no trae especies** (Y
diluida por α_old/α_new como en el volfix; auditoría 5, M5-5: antes creaba O
y C de la nada). Lo mismo valen la carga de cesta y el ECS, que destruyen gas
al cargar chatarra (M5-4: `cold_bucket2` atribuía a la EOS 10.4 de 12.5 kg).
Las especies que salen con el gas destruido van a `m_vf_O2/CO/CO2`, y con
ellas y `m_dil_*` el balance elemental de O y C cierra con escoria
(`check_chem --slag`, 1e-11 en `slag_chem_test`; la identidad usa la ρ_g del
código, `/restart/rho_gas`). El CO de una reducción nacida en una celda de
escoria sin gas (el solver de especies descartaría la fuente) sube hasta la
primera celda con gas (pasadas Jacobi con halos; no se activa en los bancos).
Intercambio escoria–fluido exacto de dos
nodos (exponencial), en dos pasadas. **Con el gas, consistente con su
inventario logarítmico** (M4-13): la energía del gas ideal a p fija es
C_g ln(T/T_ref) con C_g = α ρ_ref T_ref c_p V (P0 + p)/P0 (la masa la fija la
EOS, ρ ∝ 1/T), así que el equilibrio se resuelve en la forma no lineal
C_s (T_s − T_eq) = C_g ln(T_eq/T_g), el gas avanza la fracción f hacia T_eq en
ln T y la escoria recibe exactamente lo que perdió el inventario del gas. El
"poke" lineal T −= Q/(αρc_pV) perdía el 30 % de Q con gas a 300 K contra
escoria a 1800 K. Química FeO/C con conservación elemental (E2). Piso
T_sl ≥ 300 K con E_sl coherente y la energía inyectada auditada
(`E_slag_tclip`).

---

## 15. Transferencia de calor interfase

**Gas–líquido en dos fluidos (auditoría 2, N-A1; auditoría 4, M4-9/M4-10)**:
`compute_gas_liquid_heat`, implícito exacto de dos nodos tras el SIMPLE. Tres
contribuciones: (i) **película del lecho** (α_s ≥ 1e-2, rampa `fbed` entre 1e-2
y 2e-2 hacia el régimen libre; se apaga al saturar el poro con `fsat`),
a_i = 6α_s/d_p · min(1, α_l/(1−α_s)), h de Ranz–Marshall; (ii) **gotas** en el
gas continuo, 6 α_l/d_gota con f_disp (logística AIAD; 0 en líquido continuo),
Nu = 2 + 0.6 Re^½ Pr^⅓; (iii) **superficie libre resuelta por CARAS
verticales**: en cada cara k|k+1 el nodo líquido es la celda con más α_l y el
gas la otra, área |Δα_l|·A_z, h = k(2/dz + 0.664 Re_L^½ Pr^⅓/L) con
L = max(R_shell, dz) — la conducción 2k/dz deja intercambiar a un gas en
reposo y L largo quita la dependencia h ∝ dz^-½ de la placa de longitud dz;
se omite si alguna de las dos celdas tiene chatarra (α_s ≥ 2e-2). Con
interfase nítida ninguna celda tiene las dos fases, por eso el acople es de
cara y no de celda (antes: |∇α_l| central, que pulsaba con la posición del
nivel). Antes de N-A1 no existía: el gas a 300 K sobre el baño a 1850 K
quedaba a 300 K. Banco: `bath_test_cold`. **El lazo de caras va en dos
barridos por paridad de la cara global con halos de T frescos antes de cada
uno** (auditoría 5, M5-2): así los dos ranks de una frontera de bloque en z
evalúan la misma q (el lazo por celda y un Gauss–Seidel en k dejaban halos
rancios: `melt_forced` n1 frente a n7 difería 3.3e-8 en α_s; ahora 6e-11) y
dentro de un barrido ninguna celda toca dos caras (dos nodos exactos). El nodo
líquido de la cara es continuo por `ws_liq_cont` (B5-1: la celda de superficie
con α_l < 0.3 quedaba sin intercambio) y el área lleva la rampa (1 − fbed) de
la celda con más chatarra (B5-2), nunca un corte duro. **Todo intercambio con
el gas es en forma LOG (B5-3)**: una sola definición de dos nodos
(`gas_log_exchange`, mod_audit): el gas se relaja EXACTAMENTE con su capacidad
C_g/T hacia la T nueva T* del otro nodo, 1 − T*/T = (1 − T*/T_g) e^{−G T* dt/C_g}
(tasa inicial hA(T_g − T*), acotada, equilibrio exacto a dt → ∞), entrega
Q = C_g ln(T_g/T_g′) y T* cumple el balance C_o(T* − T_o) = Q (+ el nodo
líquido lineal implícito en la interfase gas–sólido), por bisección monótona.
Vale para el lazo por celda, el de caras, la escoria y la interfase gas–sólido.
Aplicar la fracción lineal en ln T (primer intento) daba 1.7× el calor físico
a dt pequeño: la tasa es física, el inventario decide ΔT. `noflow_energy`
cierra a 2e-5 J (antes 96 J). El libro del gas del audit
(`E_gas_abs`) se parte por lo mismo en la parte de la ECUACIÓN (medida de
estado lineal entre T_old y `Tg_end`) y los pokes exactos: con un solo libro
lineal un poke log perdía O(dT²) (arc_melt −4.7e3 → +3.2e5 J).

```
gas–sólido:      h_gs = (k_mol/d)(2 + 1.1 Pr^⅓ Re^0.6) [Wakao], k_mol = μ c_p / 0.7;
                 sobre 1373 K, max(Wakao, correlación radiativa de alta T) (A12, M39)
líquido–sólido:  h_ls = (k_l/d)(2 + 0.6 Re^½ Pr^⅓) [Ranz–Marshall con |u_l|] (M39)
área:            6 α_s/d repartida entre gas y líquido por fracción de poro (M7)
```

Paso **implícito exacto de tres nodos** (M6): con b_q = a_q C_q/(C_q + a_q),
a_q = G_q dt,

```
T_s' = (C_s T_s + b_g T_g + b_l T_l) / (C_s + b_g + b_l),   Q_q dt = b_q (T_q − T_s')
```

Sin rebase del equilibrio con ningún dt. Gas–líquido (modelo de mezcla):
intercambio de burbuja (AIAD) exacto de dos nodos.

---

## 16. Buoyancy de Boussinesq

Aplicada solo a la componente `uz` del líquido:

```
src_extra += α_liquid × ρ_liquid × β × g × (T - T_ref_boussinesq)    (T_ref_boussinesq = T_liquidus por defecto, A7)

β = 1.2×10⁻⁴ K⁻¹    (coeficiente de expansión térmica del acero)
g = -9.81 m/s²       (hacia abajo, z negativo)
```

---

## 17. Constantes físicas

| Símbolo | Valor | Unidades | Descripción |
|---------|-------|----------|-------------|
| σ (Stefan-Boltzmann) | 5.6704×10⁻⁸ | W/(m²·K⁴) | Radiación cuerpo negro |
| R_gas | 8.3145 | J/(mol·K) | Constante de gas ideal |
| g | 9.81 | m/s² | Gravedad |
| μ₀ | 1.2566×10⁻⁶ | H/m | Permeabilidad magnética vacío |
| ρ_steel | 7500 | kg/m³ | Densidad acero |
| T_solidus | 1600 | K | Temperatura de solidus |
| T_liquidus | 1809 | K | Temperatura de liquidus |
| cp_solid | 400 | J/(kg·K) | Calor específico sólido |
| cp_liquid | 696.4 | J/(kg·K) | Calor específico líquido |
| L_fusion | 247,000 | J/kg | Calor latente de fusión |
| k_solid | 35 | W/(m·K) | Conductividad térmica sólido |
| k_liquid | 30 | W/(m·K) | Conductividad térmica líquido |
| μ_liquid | 6×10⁻³ | Pa·s | Viscosidad dinámica acero |
| ρ_gas | 1.2 | kg/m³ | Densidad del gas a 300 K y P0 (EOS ρ = 1.2·(300/T)·(P0 + p)/P0) |
| cp_gas | 1000 | J/(kg·K) | Calor específico gas |
| k_gas | 0.5 | W/(m·K) | Conductividad EFECTIVA de la difusión del gas (la interfase usa μc_p/0.7) |
| μ_gas | 5×10⁻⁵ | Pa·s | Viscosidad dinámica gas |
| ε (emissivity) | 0.7 | — | (sin efecto en el modelo: la DO usa κ) |
| β | 1.2×10⁻⁴ | K⁻¹ | Expansión térmica acero |
| d_particle | 0.10 | m | Tamaño chatarra (Ergun) |
| ARC_LENGTH_GRAD | 1150 | V/m | Gradiente de la columna del arco |
| MW_C | 0.012 | kg/mol | Masa molar carbono |
| MW_CO | 0.028 | kg/mol | Masa molar monóxido de carbono |
| MW_CO₂ | 0.044 | kg/mol | Masa molar dióxido de carbono |
| ΔH_C→CO | −110.5 | kJ/mol | Entalpía oxidación parcial |
| ΔH_CO→CO₂ | −283.0 | kJ/mol | Entalpía combustión CO |

---

*Referencia base: Ugarte et al. (2024), Materials 17(21), 5139*

## Líquido disperso: drift-flux con relajación de partícula (sep-2026)

Fuera del lecho el líquido es fase **continua** (momento propio, Poisson) sólo con α_l ≥ `ALPHA_LIQ_CONT` = 0.3; en el lecho (α_s ≥ 0.01) rige el umbral hidrodinámico ordinario. Por debajo es fase **dispersa** (gotas, salpicaduras, niebla): no tiene ecuación de momento propia, no entra al Poisson, y su velocidad se relaja hacia la de la fase portadora más el deslizamiento terminal (modelo de mezcla con inercia de partícula; Manninen, Taivassalo & Kallio, VTT 1996):

    objetivo:  u* = u_g − u_t ẑ            (freeboard)
               u* = −min(u_t, √(2 g d_p)) ẑ (en el lecho: percolación por la chatarra)
    relajación: u_l^{n+1} = u_l^n + (Δt g / u_t) (u* − u_l^n),   τ_p = u_t / g
    u_t: Schiller–Naumann (punto fijo en Re), acotada a 50 m/s;  d = d_droplet (2 mm)

El acople de momento con el gas es el arrastre físico de la gota, exacto en el punto de operación: `K = α_l (ρ_l − ρ_g) g / u_t`, implícito en ambas fases. A deslizamiento u_t equivale al peso de las gotas; durante los transitorios del gas el deslizamiento crece y el gas siente la inercia de la niebla (100× la suya a α_l = 0.5 %). El deslizamiento algebraico puro (ajuste instantáneo) no es válido aquí: τ_p ≈ 3.5 s ≫ Δt, y sin la relajación el gas queda libre bajo la niebla. Cuando una celda pasa a continua, su velocidad se inicializa con el promedio de las vecinas continuas. Para acero en gas a 1800 K u_t ≈ 35 m/s; la niebla salpicada por el arco vuelve al baño en ~1 s y el resultado es insensible a d en 1–5 mm.

## Acople α–p del líquido continuo y superficie libre (Plan C F1, sep-2026)

- **Transporte de α_l con los flujos del Poisson.** El transporte explícito donor-cell del líquido continuo usa la velocidad de cara de Rhie–Chow corregida, `u_f A = [F* + a_nb(pp_P − pp_nb)]/(αρ)_f`, exportada por la corrección de presión. Su divergencia por celda es el residuo del Poisson (más el almacenamiento de compliance y acústico), así que el transporte no llena ni drena celdas que el Poisson dejó en balance. La reconstrucción simétrica desde velocidades de centro queda para el líquido disperso (drift-flux). La energía convecta el líquido con los mismos flujos efectivos.
- **Superficie libre.** Una celda con α_l ≥ 10⁻² sobre una celda de baño (α_l ≥ 0.3) es película superficial: fase continua, con ecuación de momento y enlazada al Poisson. En caras mixtas (continuo | disperso) el flujo lo fija el dador: el líquido que sale del baño va a la velocidad del baño; las gotas que caen, a su velocidad de drift; convergentes, la media; divergentes, cero.
- **Presión del gas sobre el baño.** Con una sola presión por celda, el gas de la celda sobre una celda de baño ve `p_g = p + ρ_l g_eff Δz (½ − α_l)`: la línea hidrostática del líquido evaluada en su tope (líquido estratificado en el fondo de la celda). Sin esta corrección el gas leía media carga de líquido en la p de centro y se aceleraba a 50–200 m/s sobre un baño en reposo.
- **Colapso de chatarra.** Una celda de baño no es hueco: la chatarra descansa sobre el líquido y la consume la fusión.
- **Fuerza vertical balanceada por caras (oct-2026, `liq_balanced_force`).** Las fases continuas ven la presión reducida de la mezcla, media de caras de (p_N − p_P)/δz + W_f, con W_f = g (α_l ρ_l(1 − β(T − T_ref))|cont + α_g ρ_g)/(α_l + α_g) promediado en la cara; el peso no entra como fuerza de celda. El baño en reposo es punto fijo discreto (antes: corriente par–impar de 0.2 m/s, ARCHITECTURE F1b). No hay flotación relativa entre líquido continuo y gas (interfase grande); el líquido disperso conserva su sedimentación. **En el lecho** (α_s ≥ 1e-2) cada fase recupera la forma clásica −α∇p − αρ_q g sumando a cada cara B_f = bed_f (w_q,f − W_f) (auditoría 3, A3-1/M3-1; misma expresión en el Rhie–Chow); el gas solo donde es la fase continua del poro (`ws_bed_gas`: percola y α_g entre 1× y 2× `ALPHA_PORE_GAS` pesa 0 → 1), de modo que el líquido drena con todo su peso contra Ergun y el gas residual del poro saturado no bombea. La misma B_f, con máscara de cara = mínimo de las dos celdas, da la flotación de las **burbujas** dentro del baño (A3-5, `ws_bub`: celda de líquido continuo sin lecho, con gas del acople y baño continuo encima); la superficie libre no la lleva.
- **Intercambio de calor gas–líquido (auditoría 2 N-A1; morfología A3-2).** Implícito exacto de dos nodos por celda con G = h·a_i·V. Lecho (α_s ≥ 1e-2): a_i = 6α_s/d_p · min(1, α_l/(1−α_s)), h de Ranz–Marshall con d_p. Fuera del lecho: G = f_disp·h_gota·6α_l/d + (1−f_disp)·h_placa(dz)·|∇α_l|, con f_disp la logística AIAD en α_l (centro 0.3, pendiente 50); la celda de superficie del baño (continua por la regla de superficie libre) usa f_disp = 0.
- **Referencia de la compresibilidad del gas (A3-3).** La fuente de volumen del Poisson mide ρ(p, T_it) contra ρ(pⁿ, T_end), con T_end la T del gas al final del SIMPLE anterior (`sh%Tg_end`, estado del reinicio): así la expansión del calor que recibe el gas después del Poisson (interfase gas–sólido, intercambio gas–líquido) entra al acople en el paso siguiente en vez de reescribirse en la masa por la EOS.

## Ecuación de presión de volumen y superficie libre (Plan C F2, sep-2026)

- **Ecuación de presión.** Suma de las continuidades de fase divididas por su densidad (GCBA de Darwish–Moukalled; `multiphaseEulerFoam`): `Σ_q[∂α_q/∂t + div(α_q u_q)] = −(α_g/ρ_g)Dρ_g/Dt`. Los coeficientes de cara son `α_f (α V/aP)_f A/δ` por fase y la fuente `−Σ_f α_f u_f A` (flujo volumétrico de Rhie–Chow). La fusión y la re-solidificación (ρ_l = ρ_s) son exactamente neutras sin fuente alguna; el líquido que entra a una celda desplaza igual **volumen** de gas. La forma de masa de la mezcla (que el código tuvo hasta F1) exigía gas de igual masa, 7500× su volumen: era el origen de las presiones de MPa al formarse el baño.
- **Corrección de velocidad** `u' = −(α V/aP)∇p'` y `d_f = (αV/aP)_f` en el Rhie–Chow: consistentes con el predictor `−α∇p`.
- **Burbujas en el baño (auditoría 4, B4-25).** En las celdas de burbuja (`ws_bub`: líquido continuo sin lecho, gas que puede deslizar y baño continuo encima) el cierre de interfase resuelta `α_l α_g ρ_mez/TAU_LG` cede, con el peso de `ws_bub`, al arrastre físico de burbuja `K = α_g α_l (ρ_l − ρ_g) g / U_BUBBLE` (con α_l porque la flotación que el gas ve en la forma balanceada es la relativa α_g(ρ_mez − ρ_g)g; auditoría 5, B5-10: sin α_l el deslizamiento efectivo era α_l·U_BUBBLE), con `U_BUBBLE` = 0.23 m/s (Clift, Grace & Weber 1978: burbujas elipsoidales de 3–10 mm en líquidos de baja viscosidad; el estado estacionario del momento de la fase dispersa, Bug 17). `TAU_LG` fijaba el deslizamiento en g τ ≈ 0.1 m/s sin depender de nada. La celda de superficie (`ws_bub` = 0) conserva `TAU_LG`.
- **Acople del arrastre.** Eliminación parcial (Spalding; Karema & Lo) por celda tras los solves de momento, con las soluciones sin relajar: `u_l' = (aP_g H_l + KV H_g)/det`, `u_g' = (aP_l H_g + KV H_l)/det`. Necesaria donde `K` es grande (celdas de superficie, `TAU_LG`).
- **Superficie libre.** Con una sola presión por celda, la celda de superficie está sobre la línea hidrostática de la mezcla; el gas contiguo no debe sentir ese salto como fuerza (sería la flotación de la fase ligera en la mezcla, física para burbujas pero espuria en una interfase grande). En las caras verticales el gas usa `∇p_f + (α_lρ_l)_f g_eff` con α_l sólo del líquido **continuo**; el disperso (niebla) conserva el gradiente de mezcla, cuya flotación compensa el arrastre de las gotas.
- **Estado inicial.** Presión hidrostática de la mezcla por integración de columna desde el techo (patrón gather global).

## Régimen del líquido en el lecho y cierre del acople (Plan C F2.13–F2.15, sep-2026)

Tres reglas fijan **qué régimen** tiene el líquido en cada celda, y con él su velocidad y su intercambio de momento. Sin ellas el acople de presión seguía produciendo excursiones de decenas a cientos de kPa aunque la ecuación de presión ya fuera correcta.

- **Goteo en contacto con el lecho (F2.14).** Una celda con chatarra propia (α_s > `ALPHA_SOLID_RESID`) o que descansa sobre una celda del lecho (α_s ≥ 10⁻² debajo) está en régimen de goteo: el líquido disperso percola a `percolation_velocity` con el α_s efectivo `max(propio, de abajo)`, nunca a la velocidad del gas. Es lo que hacen los modelos de lecho empacado: en el de cuatro fluidos del alto horno (Austin, Nogami y Yagi, ISIJ Int. 37 (1997) 458) el arrastre sólido–líquido se construye para que la velocidad del líquido tienda a la del sólido cuando su holdup se anula, y en los modelos de dos fluidos de lechos de goteo el arrastre líquido–sólido es Ergun dividido por el holdup al cuadrado. Sin esta regla, la celda recién fundida bajo el arco (α_s 0.003–0.01, por debajo del umbral de «lecho») llovía al lecho a la velocidad del chorro.

- **Morfología del intercambio gas–líquido (F2.15).** En esas mismas celdas el intercambio es la **cizalla de superficie libre** `K = C_FS_SHEAR ρ_g |u_g − u_l| |∇α_l|` (AIAD: la densidad de área interfacial es el gradiente de fracción), no la relajación de régimen disperso `α_l α_g ρ_l/TAU_LG`. AIAD reserva el arrastre de gota a α_l < 0.3 dentro de gas continuo; entre 0.3 y 0.7 la morfología es superficie libre y la cizalla **no iguala velocidades**. Fuera del lecho el charco libre conserva el acople disperso: es lo único que frena al gas sobre un baño en reposo. Además el líquido lleva Ergun con el α_s efectivo del lecho al que drena, porque una celda de charco sin chatarra propia se queda si no **sin ningún sumidero de momento** y cae en caída libre.

- **Gas residual de poro (F2.13).** El gas que F2.7 deja en el lecho para que la celda no se selle existe para la contabilidad de volumen, no para llevar presión. Una celda casi sólida, sin líquido continuo y con α_g en ese piso no es fluido del acople P–V: es pared para los gradientes, su corrección es cero y recibe el Neumann de sus vecinas. Si se la deja dentro, su compresibilidad integra `p ≈ P₀ (T/T₀ − 1)` al calentarse — la termodinámica de un poro sellado a volumen constante.

**Estado del acople (B1 v32, malla media, 120 s desde t = 0, con arco, fusión, colapso y química).** Cero episodios de presión, máximo 5.35 kPa en toda la corrida — y ocurre a t = 0.12 s, en el transitorio de encendido —, gas 168 m/s, líquido 0.84 m/s, clip 0. `P_HYDRO_CAP`, `U_GAS_MAX` y `U_LIQ_MAX` son **centinelas**: no se activan en régimen sano, y su activación señala que el acople volvió a romperse. Queda abierto el modo par-impar del esquema colocado (velocidades de centro de ~0.2 m/s con flujos de cara nulos), acotado y de otra familia.

