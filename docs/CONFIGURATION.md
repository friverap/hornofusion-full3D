# Referencia de Configuración — EAF3D

Documentación completa de todos los parámetros del archivo de configuración `.dat`.  
El archivo se lee por `mod_config_3d.f90` con sintaxis `clave = valor` (un parámetro por línea, `#` para comentarios).

---

## Formato del archivo

```ini
# Líneas que comienzan con # o ! son comentarios
# Espacios alrededor del = son ignorados
nr     = 60
ntheta = 120
nz     = 84
solve_flow = true
```

Los valores booleanos aceptan: `true`, `false`, `.true.`, `.false.`  
Claves desconocidas se ignoran silenciosamente.

---

## Índice de secciones

1. [Geometría del horno](#1-geometría-del-horno)
2. [Malla](#2-malla)
3. [Integración temporal](#3-integración-temporal)
4. [Algoritmo SIMPLE](#4-algoritmo-simple)
5. [Tolerancias de convergencia](#5-tolerancias-de-convergencia)
6. [Propiedades del acero](#6-propiedades-del-acero)
7. [Propiedades del gas](#7-propiedades-del-gas)
8. [Condiciones de borde](#8-condiciones-de-borde)
9. [Flags de física](#9-flags-de-física)
10. [Modelo de arco eléctrico](#10-modelo-de-arco-eléctrico)
11. [Escoria](#11-escoria)
12. [Transporte de especies](#12-transporte-de-especies)
13. [Carga del horno](#13-carga-del-horno)
14. [Salida](#14-salida)

---

## 1. Geometría del horno

| Parámetro | Tipo | Default | Unidades | Descripción |
|-----------|------|---------|----------|-------------|
| `R_shell` | real | 3.80 | m | Radio interior de la carcasa del horno |
| `H_total` | real | 4.50 | m | Altura total (fondo cuenco → techo) |
| `H_bowl` | real | 0.60 | m | Profundidad del cuenco (bowl) |
| `R_bowl` | real | 2.50 | m | Radio del cuenco en la base |
| `R_pcd` | real | 0.85 | m | Radio del círculo de electrodos (pitch circle diameter / 2) |
| `R_elec` | real | 0.30 | m | Radio de cada electrodo |
| `R_outlet` | real | 0.35 | m | Radio de la zona de salida en el techo |

### Notas

- Los 3 electrodos se distribuyen a θ = 0, 2π/3, 4π/3 sobre el círculo de radio `R_pcd`.
- El cuenco inferior tiene geometría semi-esférica definida por `H_bowl` y `R_bowl`.
- La geometría corresponde a un EAF AC trifásico de 130 toneladas (Ugarte et al. 2024).

---

## 2. Malla

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `nr` | int | 60 | Número de celdas en dirección radial |
| `ntheta` | int | 120 | Número de celdas en dirección azimutal |
| `nz` | int | 84 | Número de celdas en dirección axial |
| `stretch_r` | real | 1.5 | Factor de estiramiento radial (concentra celdas en centro) |
| `stretch_z` | real | 1.5 | Factor de estiramiento axial (concentra celdas en cuenco) |

### Descomposición MPI

El dominio se descompone en **θ × z** (r no se descompone).  
`ntheta` y `nz` deben ser exactamente divisibles por los factores de la descomposición.

| NPROCS | Descomp. | ntheta/proc | nz/proc |
|--------|----------|-------------|---------|
| 8 | 1×4×2 | 30 | 42 |
| 12 | 2×3×2 | 40 | 42 |
| 16 | 1×4×4 | 30 | 21 |

### Configuraciones de malla predefinidas

| Config | nr × ntheta × nz | Celdas | Uso |
|--------|-----------------|--------|-----|
| Mínima | 12×24×16 | 4,608 | Prueba MPI |
| Test | 18×36×24 | 15,552 | Regresión (8 procs) |
| Media | 35×70×50 | 122,500 | Validación intermedia |
| **Producción** | **60×120×84** | **604,800** | **Paper Ugarte 2024** |

---

## 3. Integración temporal

| Parámetro | Tipo | Default | Unidades | Descripción |
|-----------|------|---------|----------|-------------|
| `dt` | real | 0.1 | s | Paso temporal inicial |
| `dt_min` | real | 1.0e-3 | s | Paso mínimo (dt adaptativo) |
| `dt_max` | real | 1.0 | s | Paso máximo (dt adaptativo) |
| `t_final` | real | 5040.0 | s | Tiempo de simulación total (tap-to-tap) |
| `adaptive_dt` | bool | true | — | Habilitar ajuste automático de dt |

### Recomendaciones

- **Test regresión:** `dt = 0.5`, `t_final = 5.0`, `adaptive_dt = false`
- **Bore-in:** `dt = 5.0`, `t_final = 300.0` (electrodos tardan ~200 s en bajar)
- **Producción:** `dt = 0.5`, `dt_max = 2.0`, `t_final = 5040.0`, `adaptive_dt = true`

El tiempo de bore-in es `(H_total - H_bowl) / BORE_IN_SPEED = (4.5 - 0.6) / 0.01 ≈ 390 s`.  
El cubo 2 se carga en `t = t_bucket2_charge = 2100 s`.

---

## 4. Algoritmo SIMPLE

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `max_outer` | int | 20 | Máximo de iteraciones externas SIMPLE por paso temporal |
| `max_inner_mom` | int | 5 | Iteraciones internas del solver TDMA para momentum y escalares |
| `max_inner_pres` | int | 50 | Iteraciones internas del solver para corrección de presión |
| `alpha_u` | real | 0.3 | Sub-relajación de velocidad |
| `alpha_p` | real | 0.7 | Sub-relajación de presión |
| `alpha_T` | real | 0.7 | Sub-relajación de temperatura |
| `alpha_k` | real | 0.5 | Sub-relajación de k turbulento |
| `alpha_eps` | real | 0.5 | Sub-relajación de ε turbulento |

### Recomendaciones

- Valores de `alpha_u = 0.3`, `alpha_p = 0.7` son estándar para flujos con gradientes fuertes.
- Para arrancar desde cero (frío): `max_outer = 10`, `max_inner_mom = 3`.
- Para corridas de producción en régimen: `max_outer = 20`, `max_inner_pres = 50`.

---

## 5. Tolerancias de convergencia

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `tol_cont` | real | 1.0e-4 | Tolerancia de residual de continuidad |
| `tol_mom` | real | 1.0e-4 | Tolerancia de residual de momentum |
| `tol_energy` | real | 1.0e-3 | Tolerancia de residual de energía |
| `tol_turb` | real | 1.0e-4 | Tolerancia de residual de turbulencia |

Los residuales son normas L2 globales (reducción MPI). El SIMPLE itera hasta que todos los residuales activos caen por debajo de su tolerancia, o hasta `max_outer`.

---

## 6. Propiedades del acero

| Parámetro | Tipo | Default | Unidades | Descripción |
|-----------|------|---------|----------|-------------|
| `rho_steel` | real | 7500.0 | kg/m³ | Densidad del acero (sólido y líquido) |
| `T_solidus` | real | 1600.0 | K | Temperatura de solidus |
| `T_liquidus` | real | 1809.0 | K | Temperatura de liquidus |
| `cp_s` | real | 400.0 | J/(kg·K) | Calor específico sólido |
| `cp_l` | real | 696.4 | J/(kg·K) | Calor específico líquido |
| `h_fusion` | real | 247000.0 | J/kg | Calor latente de fusión |
| `k_s` | real | 35.0 | W/(m·K) | Conductividad térmica sólido |
| `k_l` | real | 30.0 | W/(m·K) | Conductividad térmica líquido |

Fuente: Ugarte et al. (2024), Tabla 2.

---

## 7. Propiedades del gas

Las propiedades del gas son constantes de referencia (modelo de gas ideal simplificado):

| Constante (no configurable) | Valor | Unidades |
|-----------------------------|-------|----------|
| `rho_gas` | 1.2 | kg/m³ |
| `cp_gas` | 1000.0 | J/(kg·K) |
| `k_gas` | 0.5 | W/(m·K) |
| `mu_gas` | 5×10⁻⁵ | Pa·s |

> Las propiedades del gas no son actualmente configurables desde el archivo `.dat`.  
> Modificar `mod_constants.f90` para cambiarlas.

---

## 8. Condiciones de borde

| Parámetro | Tipo | Default | Unidades | Descripción |
|-----------|------|---------|----------|-------------|
| `T_ambient` | real | 300.0 | K | Temperatura ambiente (BC en paredes y techo) |
| `T_initial` | real | 300.0 | K | Temperatura inicial de todos los campos |

- Las velocidades son cero en todas las paredes (no-slip).
- Temperatura: Dirichlet `T = T_ambient` en paredes y techo.
- Presión: Neumann en paredes, valor fijo en salida.
- Especies CO/CO₂: Neumann (gradiente cero) en todas las paredes.
- Dirección θ: periódica para todos los campos.

---

## 9. Flags de física

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `solve_flow` | bool | true | Resolver ecuaciones de momentum (N-S) |
| `solve_energy` | bool | true | Resolver ecuación de energía |
| `solve_melting` | bool | true | Resolver fusión/solidificación |
| `solve_turb` | bool | true | Resolver modelo k-ε |
| `solve_radiation` | bool | true | Resolver radiación DO |
| `solve_chemistry` | bool | false | Resolver química de carbono (C→CO, CO→CO₂) |
| `solve_arc` | bool | true | Resolver modelo de arco (Cassie-Mayr + MC + Lorentz) |
| `solve_multiphase` | bool | true | SIMPLE multifase (gas + líquido acoplados) |
| `solve_slag` | bool | false | Resolver capa de escoria |
| `solve_species` | bool | false | Resolver transporte CO/CO₂ |

### Dependencias entre flags

```
solve_species = true  →  requiere solve_chemistry = true
                          (para generar S_CO_src y S_CO2_src ≠ 0)

solve_slag    = true  →  independiente de los demás flags

solve_arc     = true  →  activa simultáneamente:
                          - Cassie-Mayr (update_arc_resistance)
                          - Distribución de calor (distribute_arc_heat)
                          - MC radiation (distribute_arc_radiation_mc)
                          - Impingement (compute_arc_impingement)
                          - Lorentz (compute_lorentz_force)
```

---

## 10. Modelo de arco eléctrico

| Parámetro | Tipo | Default | Unidades | Descripción |
|-----------|------|---------|----------|-------------|
| `frac_rad` | real | 0.50 | — | Fracción radiativa del calor del arco (→ superficie scrap) |
| `frac_conv` | real | 0.30 | — | Fracción convectiva (→ columna de gas) |
| `frac_elec` | real | 0.20 | — | Fracción resistiva (→ punta del electrodo) |
| `arc_w` | real | 30.0 | W | Potencia de enfriamiento del arco (Cassie-Mayr ARC_W) |

> **Invariante:** `frac_rad + frac_conv + frac_elec = 1.0` (no se verifica automáticamente).

### Calibración de `arc_w`

```
R_eq = ARC_W × R² / P_arc
Con I=55 kA, V=500 V → P_arc=27.5 MW:
  ARC_W = 30 W  →  R_eq ≈ 9 mΩ  →  P_arc ≈ 27.5 MW  ✓
```

### Perfil de electrodos

Las curvas V(t) e I(t) se leen de `input/electrode_profile.dat`:

```
# time[s]  voltage[V]  current[A]
0.0        500.0        55000.0
300.0      520.0        55000.0
...
5040.0     440.0        42000.0
```

Si el archivo no existe, se usa un perfil constante: 500 V, 50 kA.

---

## 11. Escoria

| Parámetro | Tipo | Default | Unidades | Descripción |
|-----------|------|---------|----------|-------------|
| `solve_slag` | bool | false | — | Habilitar modelo de escoria |
| `rho_slag` | real | 2800.0 | kg/m³ | Densidad de la escoria |
| `cp_slag` | real | 1200.0 | J/(kg·K) | Calor específico de la escoria |
| `k_slag` | real | 1.5 | W/(m·K) | Conductividad térmica de la escoria |
| `h_contact_sl` | real | 1000.0 | W/(m²·K) | Coeficiente de contacto escoria-acero |
| `m_slag_init` | real | 3300.0 | kg | Masa inicial de escoria en el horno |

La escoria se inicializa 3 niveles k por encima de la superficie del scrap,  
escalada a exactamente `m_slag_init` kilogramos.

---

## 12. Transporte de especies

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `solve_species` | bool | false | Habilitar transporte CO/CO₂ |
| `Sc_t_species` | real | 0.7 | Número de Schmidt turbulento (D_eff = μ_eff/(ρ Sc_t)) |
| `alpha_Y_species` | real | 0.5 | Factor de sub-relajación de la fracción másica Y |

Las fracciones másicas `Y_CO` y `Y_CO₂` se inicializan en 0.0 al inicio de la simulación.  
Las fuentes son generadas por `compute_carbon_oxidation` cuando `solve_chemistry = true`.

---

## 13. Carga del horno

| Parámetro | Tipo | Default | Unidades | Descripción |
|-----------|------|---------|----------|-------------|
| `t_bucket2_charge` | real | 2100.0 | s | Tiempo de carga del segundo cubo |

La receta de carga se lee de `input/charge_recipe.dat`:

```
# bucket  mass[kg]  solid_fraction
1   4692.9   0.52      # Capa 1 del cubo 1
1   4692.9   0.48      # Capa 2 del cubo 1
...
2   5092.3   0.50      # Capa 1 del cubo 2
```

Si el archivo no existe, se usa la receta por defecto:
- Cubo 1: 14 capas × 4693 kg, α_s = 0.50 → total 65.7 t
- Cubo 2: 13 capas × 5092 kg, α_s = 0.50 → total 66.2 t

---

## 14. Salida

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `output_freq` | int | 100 | Cada cuántos pasos escribir un snapshot HDF5 |
| `monitor_freq` | int | 10 | Cada cuántos pasos escribir una línea en monitor.log |
| `output_dir` | string | 'output' | Directorio de salida (se crea con `mkdir -p`) |

> El directorio de salida se crea automáticamente solo por el rank 0.  
> Con `mpirun`, verificar que el directorio exista antes de lanzar si hay problemas de permisos.

### Frecuencias recomendadas por caso

| Caso | output_freq | monitor_freq | Snapshots | Monitor lines |
|------|-------------|-------------|-----------|---------------|
| Test (10 pasos) | 1 | 1 | 10 | 10 |
| Bore-in (60 pasos) | 5 | 1 | 12 | 60 |
| Producción (10080 pasos) | 200 | 20 | ~50 | ~504 |

---

## Ejemplo completo: config de producción

```ini
# config_production_full.dat
# ============================================================
# MALLA
# ============================================================
nr      = 60
ntheta  = 120
nz      = 84
stretch_r = 1.5
stretch_z = 1.5

# ============================================================
# GEOMETRÍA
# ============================================================
R_shell  = 3.80
H_total  = 4.50
H_bowl   = 0.60
R_bowl   = 2.50
R_pcd    = 0.85
R_elec   = 0.30

# ============================================================
# TIEMPO
# ============================================================
dt           = 0.5
dt_min       = 0.01
dt_max       = 2.0
t_final      = 5040.0
adaptive_dt  = true

# ============================================================
# SIMPLE
# ============================================================
max_outer     = 10
max_inner_mom = 5
max_inner_pres= 50
alpha_u = 0.3;  alpha_p = 0.7;  alpha_T = 0.7
alpha_k = 0.5;  alpha_eps = 0.5

# ============================================================
# MATERIAL
# ============================================================
rho_steel = 7500.0;  T_solidus = 1600.0;  T_liquidus = 1809.0
cp_s = 400.0;  cp_l = 696.4;  h_fusion = 247000.0
k_s = 35.0;  k_l = 30.0
T_initial = 300.0;  T_ambient = 300.0

# ============================================================
# FÍSICA
# ============================================================
solve_flow = true;  solve_energy = true;  solve_melting = true
solve_turb = true;  solve_radiation = true;  solve_chemistry = true
solve_arc = true;  solve_multiphase = true

# ============================================================
# ARCO
# ============================================================
frac_rad = 0.50;  frac_conv = 0.30;  frac_elec = 0.20
arc_w = 30.0

# ============================================================
# ESCORIA
# ============================================================
solve_slag = true
rho_slag = 2800.0;  cp_slag = 1200.0;  k_slag = 1.5
h_contact_sl = 1000.0;  m_slag_init = 3300.0

# ============================================================
# ESPECIES
# ============================================================
solve_species = true
Sc_t_species = 0.7;  alpha_Y_species = 0.5

# ============================================================
# CARGA
# ============================================================
t_bucket2_charge = 2100.0

# ============================================================
# SALIDA
# ============================================================
output_freq = 200;  monitor_freq = 20;  output_dir = output_prod
```
