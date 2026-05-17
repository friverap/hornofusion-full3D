# Modelos Físicos — EAF3D

Documentación completa de todos los modelos físicos implementados en el simulador 3D de horno eléctrico de arco.

---

## Tabla de contenidos

1. [Coordenadas y malla](#1-coordenadas-y-malla)
2. [Flujo multifase Euler-Euler](#2-flujo-multifase-euler-euler)
3. [Algoritmo SIMPLE](#3-algoritmo-simple)
4. [Turbulencia k-ε](#4-turbulencia-k-ε)
5. [Transferencia de calor y energía](#5-transferencia-de-calor-y-energía)
6. [Modelo de arco eléctrico Cassie-Mayr](#6-modelo-de-arco-eléctrico-cassie-mayr)
7. [Radiación Monte Carlo del arco](#7-radiación-monte-carlo-del-arco)
8. [Radiación Ordenadas Discretas (DO)](#8-radiación-ordenadas-discretas-do)
9. [Fuerza de Lorentz electromagnética](#9-fuerza-de-lorentz-electromagnética)
10. [Arrastre Ergun (lecho poroso)](#10-arrastre-ergun-lecho-poroso)
11. [Fusión y solidificación](#11-fusión-y-solidificación)
12. [Química del carbono](#12-química-del-carbono)
13. [Transporte de especies CO / CO₂](#13-transporte-de-especies-co--co₂)
14. [Capa de escoria](#14-capa-de-escoria)
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

El gas se modela con propiedades de referencia constantes más corrección de densidad ideal:

```
ρ_gas = ρ_ref = 1.2 kg/m³  (referencia 300 K, 1 atm)
μ_gas = 5×10⁻⁵ Pa·s
k_gas = 0.5 W/(m·K)
```

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
| Especies Y | 0.5 | `alpha_Y_species` |

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
μt = Cμ ρ k²/ε
```

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

## 6. Modelo de arco eléctrico Cassie-Mayr

### ODE de Cassie-Mayr

```
dR/dt = (1/τ)(R - R_eq)
R_eq  = ARC_W · R² / P_arc
P_arc = |V · I|
```

donde:
- `τ = ARC_TAU = 3×10⁻⁴ s` (constante de tiempo del arco)
- `ARC_W = 30 W` (potencia de enfriamiento — calibrado para R_eq ≈ 9 mΩ)
- `R_eq`: resistencia de equilibrio (dinámica)

### Calibración eléctrica

Con V = 500 V, I = 55,000 A por electrodo:
```
P_arc = 500 × 55000 = 27.5 MW/electrodo
R_eq  = ARC_W × R² / P_arc ≈ 9 mΩ
P_total (3 electrodos) ≈ 82.5 MW
```

### Distribución del calor del arco

| Fracción | Valor | Destino |
|----------|-------|---------|
| `frac_rad` | 0.50 | Superficie del scrap (nivel k_scrap) |
| `frac_conv` | 0.30 | Columna de gas (k_scrap → k_tip) |
| `frac_elec` | 0.20 | Punta del electrodo |

El algoritmo `distribute_arc_heat` busca la celdas del scrap debajo de cada electrodo (búsqueda `kscrap_loop`) y deposita `P_rad` exactamente en esa superficie. Si no hay scrap, deposita en la columna de arco (pre-bore-in).

### Control de electrodos

```
Fase bore-in:    z_tip -= BORE_IN_SPEED × dt   (0.01 m/s)
Fase regulación: Δz = -K_REG × (L_arc - L_set)  (K_REG=0.02, L_set=0.20 m)
```

---

## 7. Radiación Monte Carlo del arco

### Método

Trazado de rayos estocástico desde cada punta de electrodo hacia la carga. Cada rayo:

1. Se lanza con dirección aleatoria isótropa en la semiesfera inferior
2. Se propaga con paso `step_size = 0.5 × min(dr(1:nr))`
3. Se absorbe cuando impacta scrap (α_s > 0.5) o pared (cell_type = 2)
4. El calor se deposita en la celda de impacto

### Guard de seguridad

```fortran
if (step_size < 1e-6) step_size = 0.01    ! fallback anti-loop
MAX_TRACE_STEPS = 50000                    ! límite de trazado
```

La condición de salida usa `.not. (r_pos <= R_shell)` para capturar NaN correctamente.

---

## 8. Radiación Ordenadas Discretas (DO)

### Ecuación de transporte radiativo (ERT)

Para cada dirección discretizada `s_i` (6 direcciones principales):

```
s_i · ∇I_i = κ(B - I_i)
```

donde:
- `I_i`: intensidad radiativa en dirección i
- `κ`: coeficiente de absorción (mezcla gas/sólido)
- `B = σT⁴/π`: función de Planck

### Fuente de radiación

```
S_rad = κ (G - 4σT⁴)    [W/m³]
```

donde `G = Σ_i I_i w_i` es la irradiancia integrada (suma sobre direcciones con pesos).

**Nota signo:** La fuente es positiva cuando G > 4σT⁴ (absorción neta) y negativa cuando G < 4σT⁴ (emisión neta). Esto es termodinámicamente correcto.

### Coeficiente de absorción

```
κ = κ_gas × (1 - α_s) + κ_solid × α_s     (suave, sin umbral binario)
```

### Límite de estabilidad

```
S_rad = clamp(S_rad, -S_RAD_LIMIT, +S_RAD_LIMIT)    con S_RAD_LIMIT = 1×10⁴ W/m³
```

Esto limita ΔT_gas ≤ 4.2 K/paso (dt = 0.5 s, cp_gas = 1000 J/kg·K).

### Condición de borde en paralelo

El barrido DO es local por rank. No hay comunicación MPI entre ranks para los halos de intensidad (limitación conocida). La condición de frontera de entrada usa `I_dir = σT⁴/π` (warm start) en lugar de cero para evitar enfriamiento espurio global.

---

## 9. Fuerza de Lorentz electromagnética

### Modelo analítico

Corriente vertical gaussiana alrededor de cada electrodo:

```
J_z(r,θ,z) = I/(π σ_J²) × exp(-d²/(2σ_J²))  [A/m²]
```

donde `d` = distancia horizontal al eje del electrodo, `σ_J = 3 × R_elec`.

Campo magnético (ley de Ampère, aproximación axisimétrica):

```
B_θ = μ₀/(2π r) × I_enclosed(r)
```

### Fuerza de Lorentz

```
F = J × B
F_r  = J_z × B_θ × cos(θ_offset)    [N/m³]
F_θ  = J_z × B_θ × sin(θ_offset)    [N/m³]
```

### Aplicación

- Solo donde `α_liquid > 10⁻⁴` (solo en acero fundido)
- Sumada sobre los 3 electrodos
- Almacenada en `sh%F_lorentz_r`, `sh%F_lorentz_th`
- Añadida como fuente en las ecuaciones de momentum del líquido

---

## 10. Arrastre Ergun (lecho poroso)

### Correlación de Ergun

```
S_drag = -(A + B|u|) × u

A = 150 μ (1 - α_s)² / (d_p² α_s³)    [Pa·s/m²]
B = 1.75 ρ  (1 - α_s)  / (d_p   α_s³)  [kg/m³]
```

donde `d_p = 0.10 m` (tamaño característico del fragmento de chatarra).

La fuerza de arrastre se aplica al fluido (gas o líquido) en las celdas donde `α_s > 0`.

---

## 11. Fusión y solidificación

### Enthalpía efectiva

El calor de fusión se distribuye linealmente entre T_solidus y T_liquidus:

```
H_eff(T) = cp_s × T                              T < T_solidus
H_eff(T) = cp_s × T_sol + L × f_l               T_solidus ≤ T ≤ T_liquidus
H_eff(T) = cp_l × T + L                         T > T_liquidus

f_l = (T - T_solidus)/(T_liquidus - T_solidus)   (fracción líquida local)
```

### Tasa de fusión

```
mdot = (H_eff(T_s) - H_ref) × m_s / (L × dt)    [kg/s]
```

La masa se transfiere de `sol%m_s` a `liq%alpha` cada paso temporal.

### Colapso de scrap

Cuando `α_s` local cae por debajo de un umbral, las celdas superiores de scrap colapsan gravitacionalmente para mantener coherencia física.

---

## 12. Química del carbono

### Reacción primaria: C + ½O₂ → CO

**Tasa de Maahs (superficie de chatarra):**

```
rate = A_Maahs × P_O2 × exp(-E_Maahs / R T_s)    [kg_C / (m² s)]

A_Maahs = 2.3×10⁵ kg/(m² s Pa)
E_Maahs = 1.63×10⁵ J/mol
```

Solo activa donde `α_s > 0.01` y `T_s > 800 K`.

**Área superficial específica (Ergun):**
```
A_surf = 6 α_s / d_p    [m²/m³]
```

**Fuente de calor:**
```
S_chem += (-ΔH_C→CO / MW_C) × rate × A_surf    [W/m³]
ΔH_C→CO = -110.5 kJ/mol
```

**Fuente de CO:**
```
S_CO_src += rate × A_surf × (MW_CO / MW_C)    [kg_CO / (m³ s)]
```

---

### Reacción secundaria: CO + ½O₂ → CO₂ (combustión en fase gas)

Solo donde `α_gas > 0` y `T_gas > 600 K`:

**Ley de velocidad de Arrhenius:**
```
r_CO2 = A_CO2 × Y_CO × P_O2 × exp(-E_CO2 / R T_g)    [kg_CO / (m³ s)]

A_CO2 = 1.0×10⁶ m³/(kg s Pa)
E_CO2 = 1.25×10⁵ J/mol
```

**Anti-overshooting (clamp):**
```
r_CO2 = min(r_CO2, Y_CO × ρ_g × α_g / dt)
```

**Efectos:**
```
S_CO_src  -= r_CO2                           (consume CO)
S_CO2_src += r_CO2 × (MW_CO2 / MW_CO)       (produce CO₂)
S_chem    += (-ΔH_CO→CO2 / MW_CO) × r_CO2  (calor exotérmico)
ΔH_CO→CO2 = -283.0 kJ/mol
```

---

## 13. Transporte de especies CO / CO₂

### Ecuación gobernante

Para cada fracción másica Y ∈ {Y_CO, Y_CO₂}:

```
∂(αg ρg Y)/∂t + ∇·(αg ρg u Y) = ∇·(αg ρg D_eff ∇Y) + S_net    [kg/(m³ s)]
```

### Difusividad efectiva

```
D_eff = μ_eff / (ρ_g × Sc_t)

Sc_t = 0.7    (Schmidt turbulento — configurable via Sc_t_species)
```

### Discretización

Idéntica a la ecuación de energía:
- Convección: upwind de primer orden
- Difusión: diferencias centrales
- Temporal: Euler implícito

La conductancia difusiva reemplaza `αq kth` por `αg ρg D_eff`.

### Condiciones de borde

Neumann (gradiente cero) en todas las paredes y techo: `Y_bc = 0.0`  
El CO/CO₂ sale convectado por el flujo de gas caliente ascendente.

### Post-solve

```
Y = clamp(Y, 0.0, 1.0)
Y = α_Y × Y_new + (1 - α_Y) × Y_old    (α_Y = 0.5 por defecto)
```

---

## 14. Capa de escoria

### Diseño

La escoria es una pseudo-fase sin ecuaciones N-S propias. Su fracción volumétrica `α_slag` evoluciona por flotabilidad: sube hacia las zonas de menor densidad (sobre el líquido, por debajo del gas).

### Flotabilidad (3 barridos ascendentes por paso)

```
for k = nz-1 downto 1:
    if α_gas(k+1) > threshold:
        intercambiar α_slag(k) con α_slag(k+1)    (la escoria sube)
```

El gas compensa el volumen desplazado.

### Balance de energía de la escoria

```
dT_slag/dt = Q_arc + Q_interface
```

**Intercepción del calor del arco:**
```
Q_arc = α_slag × S_arc × vol    [W]
```

**Intercambio interfacial:**
```
Q_sl = h_contact × A_contact × (T_slag - T_liquid)    con h_contact = 1000 W/(m² K)
Q_sg = h_contact × A_contact × (T_slag - T_gas)
```

Clamp anti-overshooting: `ΔT_slag ≤ |T_slag - T_fluid|` en un paso.

### Inicialización

- 3 niveles k por encima de la superficie del scrap
- Masa escalada a `m_slag_init = 3300 kg`
- Temperatura inicial = `T_initial`

---

## 15. Transferencia de calor interfase

### Gas ↔ Sólido y Líquido ↔ Sólido

```
Q_gs = h_gs × A_surf × (T_gas - T_solid)    [W/m³]
Q_ls = h_ls × A_surf × (T_liquid - T_solid)
```

El área superficial usa la misma correlación de Ergun que la química.

### Clamp de estabilidad

Para prevenir oscilaciones cuando `α_q` es pequeño:

```
Q_lim = α_q × ρ_q × cp_q × vol × |T_fluid - T_solid| / dt
Q = sign(Q) × min(|Q|, Q_lim)
```

Esto garantiza `ΔT_fluid ≤ |T_fluid - T_solid|` en un paso (sin overshooting).

---

## 16. Buoyancy de Boussinesq

Aplicada solo a la componente `uz` del líquido:

```
src_extra += α_liquid × ρ_liquid × β × g × (T - T_ambient)

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
| ρ_gas | 1.2 | kg/m³ | Densidad gas referencia |
| cp_gas | 1000 | J/(kg·K) | Calor específico gas |
| k_gas | 0.5 | W/(m·K) | Conductividad térmica gas |
| μ_gas | 5×10⁻⁵ | Pa·s | Viscosidad dinámica gas |
| ε (emissivity) | 0.7 | — | Emisividad superficial acero |
| β | 1.2×10⁻⁴ | K⁻¹ | Expansión térmica acero |
| d_particle | 0.10 | m | Tamaño chatarra (Ergun) |
| ARC_TAU | 3×10⁻⁴ | s | Constante tiempo arco |
| ARC_W | 30 | W | Potencia enfriamiento arco |
| MW_C | 0.012 | kg/mol | Masa molar carbono |
| MW_CO | 0.028 | kg/mol | Masa molar monóxido de carbono |
| MW_CO₂ | 0.044 | kg/mol | Masa molar dióxido de carbono |
| ΔH_C→CO | −110.5 | kJ/mol | Entalpía oxidación parcial |
| ΔH_CO→CO₂ | −283.0 | kJ/mol | Entalpía combustión CO |

---

*Referencia base: Ugarte et al. (2024), Materials 17(21), 5139*
