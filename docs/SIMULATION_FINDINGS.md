# Hallazgos de la Simulación de Producción — EAF 3D

**Corrida:** `input/config_production_full.dat`
**Malla:** 60 × 120 × 84 = 604 800 celdas
**Duración simulada:** 100 s → 5 040 s (84 min) · 51 snapshots
**Procesadores MPI:** 12
**Generado:** 2026-03-02

---

## 1. Resumen ejecutivo

La simulación captura correctamente la **fase de calentamiento** de la chatarra (scrap) con fisicos multifásicos completos. La temperatura máxima del sólido alcanza **1 509 K** a los 84 min, quedando **302 K por debajo del punto de fusión** del hierro (1 811 K). La extrapolación lineal sitúa el inicio del melting en **≈ 105 min** de tiempo simulado. La física del gas (arco, CO/CO₂) funciona correctamente pero presenta valores de T_gas no físicos que deben corregirse antes de análisis cuantitativos del gas.

---

## 2. Progresión térmica

### 2.1 Calentamiento del sólido

| Tiempo [min] | T_solid max [K] | T_solid media (chatarra) [K] | T_solid p90 [K] |
|---|---|---|---|
| 1.7  | 324  | 312 | 321 |
| 16.7 | 635  | 521 | 608 |
| 35.0 | 779  | 619 | 743 |
| 35.0 + Δ | **848** (tras 2º cubo) | **478** | 750 |
| 50.0 | 1 044 | 676 | 984 |
| 67.0 | 1 308 | 907 | 1 244 |
| 84.0 | **1 509** | **1 083** | **1 443** |

- **Tasa de calentamiento (última mitad de la corrida):** 864 K/hr = 0.24 K/s (lineal)
- **Brecha hasta T_melt:** 302 K → a esta tasa, ~21 min adicionales
- **Tiempo total estimado hasta el primer melting:** **≈ 105 min**

### 2.2 Evento del segundo cubo de chatarra (t ≈ 2 100 s / 35 min)

A t = 2 100 s la fracción volumétrica de sólido salta de **α_s = 0.095 → 0.176**
(segundo `charge_scrap` activado por `cfg%t_bucket2_charge`).

Efectos inmediatos:
- T_solid media cae de 619 K → 478 K (chatarra fría diluye la temperatura)
- La química CO se activa simultáneamente (T_s ya supera 800 K en algunas celdas)
- S_chem pasa de 0 → 1.1×10⁵ W/m³ y crece exponencialmente (cinética Arrhenius)

---

## 3. Por qué no se alcanzó la fase de melting

### 3.1 Razón principal — tiempo de corrida insuficiente

La corrida cubrió 84 min; la fusión requiere ≈ 105 min a la tasa de calentamiento observada. Es la razón **más directa**: simplemente se necesitan ~21 min más.

```
T_melt - T_max(final) = 1811 - 1509 = 302 K
dt_restante = 302 K / 0.24 K/s ≈ 1258 s ≈ 21 min
```

Para producir melting, re-ejecutar con `t_final = 7 200` (120 min) o mayor.

### 3.2 Razón estructural — ruta del calor del arco no llega directamente al sólido

Este es el **cuello de botella físico** más importante del modelo actual.

**Cadena de energía implementada:**
```
Arc power (P_arc)
    ↓  distribute_arc_heat()
sh%S_arc  →  Gas energy equation (solve_energy_3d)
    ↓  interphase HT (mod_interphase_ht.f90)
sol%T_s (temperatura del sólido)
```

`sh%S_arc` se aplica **únicamente en la ecuación de energía del gas** (`mod_energy_3d.f90`, línea 145). El sólido recibe calor solo a través de la transferencia de calor interfásica gas→sólido, que está limitada por el coeficiente convectivo `h_gs`.

**En el régimen de baja velocidad** (Nu de Nusselt en reposo, T_g ≤ 1 373 K):
```
h_gs = (k_g / d_s) × (2 + 1.1 × Pr^0.33 × Re^0.6)
     ≈ 2 × k_g / d_s    cuando vmag_g → 0
     ≈ 2 × 0.06 / 0.05 ≈ 2.4  W/m²/K   (muy bajo)
```

**En el régimen radiativo** (T_g > 1 373 K):
```
h_gs = A_rad × f_ω × vmag_g^0.9 × T_g^0.3 / d_s^0.75
```
Si el gas está en reposo (vmag_g → 0), `h_gs → 0` independientemente de T_gas.

**Consecuencia:**
El gas en la columna del arco se calienta a temperaturas absurdas (hasta 10¹⁰ K) porque su capacidad calorífica volumétrica es tiny (α_gas × ρ_gas × cp_gas ≈ 1 J/m³/K), mientras que el sólido se calienta lentamente porque `h_gs` es bajo cuando la velocidad del gas es pequeña.

**Estimación analítica del calentamiento máximo del sólido por paso de tiempo:**
```
ΔT_solid_max/step = (α_g × ρ_g × cp_g) / (α_s × ρ_s × cp_s) × |T_g - T_s|
                  = (0.8 × 1 × 1000) / (0.2 × 7800 × 600) × 1500 K
                  ≈ 1.3 K/step → 2.6 K/s
```
Pero la tasa observada es solo **0.24 K/s**, porque la mayoría de las celdas tienen velocidades bajas y la trayectoria gas→sólido es ineficiente.

**Comparación con física real del EAF:**
| Fracción de potencia | Física real | Implementado |
|---|---|---|
| P_rad (50%) | Radiación directa al sólido | → gas (indirecto) |
| P_conv (30%) | Gas caliente sobre el sólido | → gas (correcto) |
| P_elec (20%) | Flujo de electrones/plasma | → gas (indirecto) |

En el EAF real, `frac_rad` debería depositarse directamente en `sol%E_s` (energía del sólido), no en `sh%S_arc` que alimenta al gas. El calor de arco que llega al sólido está subestimado.

### 3.3 Razón secundaria — inyección de chatarra fría (segundo cubo)

La inyección del segundo cubo a t = 35 min:
- Añade chatarra a 300 K
- Incrementa α_s de 0.095 → 0.176 (+85% de masa)
- Reduce la temperatura media de 619 → 478 K
- Reinicia el calentamiento de una fracción importante del dominio

Esto retrasa el primer melting en **~10-15 min** adicionales respecto a una corrida con un solo cubo.

### 3.4 Razón secundaria — S_chem no alimenta al sólido

Desde t = 2 100 s, `S_chem` (calor de la reacción C→CO→CO₂) crece exponencialmente hasta **5.7×10¹⁰ W/m³** (media del dominio al final). Este calor enorme también va íntegramente a la ecuación de energía del gas (misma línea 145 en `solve_energy_3d`), exacerbando el sobredimensionamiento de T_gas pero sin contribuir directamente al calentamiento del sólido.

### 3.5 Razón secundaria — baja conductividad térmica interna del sólido

El módulo de sólido no resuelve una ecuación de difusión dentro del scrap; la temperatura se actualiza por balance de energía (`T_s = E_s / (m_s × cp_s)`) sin difusión interna. Por tanto, la temperatura del sólido en una celda solo se actualiza por lo que le transfiere el gas vecino, sin propagación lateral entre celdas de sólido. Esto limita el calentamiento a lo que cada celda individualmente puede absorber por interacción con el gas.

---

## 4. Química CO/CO₂

### Observaciones

- **Y_CO_max = 1.0 desde t = 2 100 s** → celdas con CO puro en la superficie del scrap (correcto: toda la atmósfera local es CO)
- **Y_CO₂_max ≈ 0.07** → combustión secundaria activa, confinada a regiones T_gas > 600 K
- **S_chem crece exponencialmente** (5 órdenes de magnitud entre t=2100–5040 s): la cinética de Arrhenius se dispara al aumentar T_solid. Esto es físicamente plausible pero el acoplamiento con la energía del sólido está roto (ver 3.2).

### Implicación energética

La reacción C + ½O₂ → CO libera 110.5 kJ/mol_C. Con la tasa de Maahs activa sobre toda la superficie de chatarra a T > 800 K, el calor de reacción que se deposita en el gas es enorme. Sin embargo, este calor no retorna al sólido eficientemente.

---

## 5. Potencia del arco

| Snapshot | S_arc media [MW/m³] | S_arc total estimado [MW] |
|---|---|---|
| t=100 s | 27.8 | ~180 |
| t=2100 s | 23.6 | ~155 |
| t=5040 s | 21.6 | ~140 |

La potencia total calculada integrando S_arc × vol_celda da ~1 182 MW, que es fisicamente irreal para un EAF (esperado: 30–100 MW). Esto sugiere que `sh%S_arc` está siendo sobreintegrado al multiplicar por el volumen total del dominio cuando en realidad solo está concentrado en las zonas de arco. El campo S_arc tiene la distribución espacial correcta, pero los números absolutos deben verificarse contra el perfil de entrada de electrodos.

---

## 6. Campos electromagnéticos (Lorentz)

La fuerza de Lorentz (F_r, F_θ) presenta la distribución espacial correcta:
- Concentrada bajo los electrodos en el radio PCD (R_pcd = 0.85 m)
- σ_J = 3 × R_elec = 0.90 m de anchura Gaussiana
- Efecto de agitación del baño metálico: aunque α_liquid = 0 en esta corrida, la fuerza está correctamente calculada y se activará en cuanto aparezca fase líquida

---

## 7. Recomendaciones para runs futuros

### Corto plazo — obtener melting
```ini
# config_production_full.dat
t_final = 7200    # 2 horas (en lugar de 5040 s = 84 min)
```
Con la tasa de calentamiento observada (0.24 K/s), la fusión debería iniciarse alrededor de t ≈ 6 300 s (105 min).

### ✅ CORREGIDO — P_rad ahora va directamente al sólido
`mod_arc_cassie_mayr.f90` y `main_3d.f90` fueron modificados. El depósito de P_rad ahora actualiza `sol%E_s` y `sol%T_s` directamente:
```fortran
if (sol%m_s(i,j,k) > SMALL) then
    sol%E_s(i,j,k) = sol%E_s(i,j,k) + &
        P_rad_arc * gw / total_gw_vol_rad * m%vol(i,j,k) * cfg%dt
    sol%T_s(i,j,k) = sol%E_s(i,j,k) / (sol%m_s(i,j,k) * cfg%cp_s)
end if
```
El fallback (sin chatarra bajo el electrodo) sigue usando `sh%S_arc`.
`distribute_arc_heat` ahora recibe `sol` como argumento adicional.

### Verificar S_chem → sólido
El calor de la reacción C→CO (en `mod_chemistry_carbon.f90`) también debería tener una fracción que vaya directamente al sólido (la reacción ocurre en la superficie del scrap), no solo al gas.

### Diagnóstico de T_gas
Los valores de T_gas ≥ 10⁶ K son fisicamente absurdos. Origen probable:
- `S_chem` (hasta 10¹² W/m³) deposita energía en celdas con muy poca masa gaseosa (α_gas pequeño en zonas de scrap denso)
- El gas se sobrecalienta porque no tiene a dónde transferir ese calor eficientemente
- Posible solución: añadir un cap a `S_chem` cuando T_gas supere T_plasma_max (e.g. 20 000 K)

---

## 8. Archivos de salida

| Archivo | Contenido |
|---|---|
| `plots/01_scrap_evolution.png` | T_solid max/media + α_solid vs tiempo |
| `plots/02_arc_power.png` | S_arc vs tiempo (log) |
| `plots/03_co_chemistry.png` | Y_CO, Y_CO₂, S_chem vs tiempo |
| `plots/04_spatial_Tsolid.png` | T_solid y α_solid en plano r-z (último snapshot) |
| `plots/05_spatial_YCO.png` | Y_CO y Y_CO₂ en plano r-z |
| `plots/06_spatial_Sarc.png` | S_arc y S_chem en plano r-z (log) |
| `plots/07_rtheta_Tsolid.png` | Vista superior polar T_solid con electrodos |
| `plots/08_electrode_heatmap.png` | S_arc al nivel de los electrodos (r-θ, log) |
| `plots/09_lorentz_force.png` | Magnitud de fuerza Lorentz en r-z |
| `plots/3d_temperature_isosurfaces.mp4` | Video 3D: isosuperficies T_solid + corte r-z + líneas de corriente |
| `output_prod/eaf3d_*.h5` | 51 snapshots HDF5 paralelos (60×120×84) |

---

*Generado automáticamente por los scripts `postprocess/plot_insights.py` y `postprocess/render_3d_video.py`.*
