# EAF3D — Simulador Multifísica 3D de Horno Eléctrico de Arco

Implementación computacional del modelo de Ugarte et al. (2024) *Materials* **17**(21), 5139.  
Simulación CFD 3D de fusión de chatarra/HBI en un horno eléctrico de arco (EAF) de 130 t AC.

---

## Características

| Módulo | Método |
|--------|--------|
| Flujo multifase | Euler–Euler (gas + líquido + sólido dual-cell) |
| Acoplamiento P-V | SIMPLE implícito |
| Turbulencia | k-ε estándar |
| Arco eléctrico | Cassie–Mayr + MC radiación + Lorentz |
| Radiación | Ordenadas Discretas (DO, 6 direcciones) |
| Fusión/Solidificación | Entalpía efectiva + Ergun drag |
| Química | Maahs (C→CO) + combustión secundaria (CO→CO₂) |
| Transporte de especies | Convección-difusión CO / CO₂ |
| Escoria | Pseudo-fase con flotabilidad |
| Buoyancy | Boussinesq (β = 1.2×10⁻⁴ K⁻¹) |
| Paralelización | MPI-3D domain decomposition + halo exchange |
| Salida | HDF5 paralelo (PHDF5 con MPI-IO) |

---

## Requisitos

| Herramienta | Versión mínima | macOS (Homebrew) |
|-------------|---------------|------------------|
| GFortran/mpif90 | GCC 11+ | `brew install open-mpi` |
| HDF5 (Fortran + MPI) | 1.12+ | `brew install hdf5-mpi` |
| GNU Make | 4.0+ | incluido en Xcode CLT |
| Python 3 (post-proceso) | 3.9+ | `brew install python` |

```bash
# Verificar instalación
mpif90 --version
h5fc --version
```

---

## Compilación

```bash
git clone <repo>
cd hornofusion/full3D

# Build de producción (optimizado)
make clean && make

# Build de depuración (bounds check + backtrack)
make debug

# Build con máxima optimización (-O3 -march=native)
make opt
```

El binario se genera en `bin/eaf3d_mpi`.

---

## Ejecución rápida

### Test de regresión (10 pasos, 15,552 celdas)

```bash
mpirun -n 8 ./bin/eaf3d_mpi input/config_10step_full_physics.dat
```

Salida esperada: 10 pasos estables, archivos `output/eaf3d_0000000{1..10}.h5`.  
Tiempo real: ~30 s en MacBook M4 Pro.

### Corrida de producción (604,800 celdas, física completa)

```bash
mkdir -p output_prod
mpirun -n 12 ./bin/eaf3d_mpi input/config_production_full.dat
```

Tiempo simulado: 5040 s (tap-to-tap completo).  
Salida: ~50 snapshots HDF5 ≈ 6 GB en `output_prod/`.

---

## Estructura del repositorio

```
full3D/
├── src/                          Código fuente Fortran
│   ├── main_3d.f90               Programa principal, bucle temporal
│   ├── mod_constants.f90         Constantes físicas y numéricas
│   ├── mod_types_3d.f90          Tipos derivados (config_t, mesh_t, phase_t, …)
│   ├── mod_config_3d.f90         Lector de configuración
│   ├── mod_mesh_3d.f90           Generación de malla cilíndrica con halo
│   ├── mod_fields_3d.f90         Alloc/init/exchange/destroy de todos los campos
│   ├── mod_mpi_topology.f90      Topología MPI cartesiana 3-D
│   ├── mod_parallel_utils.f90    Utilidades MPI (bounds, reduce, halo)
│   ├── mod_solver_3d.f90         TDMA, SOR, residuales (MPI-aware)
│   ├── mod_boundary_3d.f90       Condiciones de borde escalares y vectoriales
│   ├── mod_momentum_3d.f90       Ecuaciones de momentum (SIMPLE)
│   ├── mod_pressure_3d.f90       Corrección de presión (SIMPLE)
│   ├── mod_energy_3d.f90         Ecuación de energía
│   ├── mod_species_transport.f90 Transporte de CO / CO₂
│   ├── mod_properties_3d.f90     Propiedades termofísicas
│   ├── mod_turbulence_3d.f90     Modelo k-ε
│   ├── mod_radiation_do.f90      Radiación DO (Ordenadas Discretas)
│   ├── mod_chemistry_carbon.f90  C→CO (Maahs) + CO→CO₂ combustión
│   ├── mod_multiphase.f90        Iteración SIMPLE multifase
│   ├── mod_melting_3d.f90        Fusión/solidificación (entalpía)
│   ├── mod_solid_phase.f90       Actualización fase sólida
│   ├── mod_scrap_collapse.f90    Colapso de chatarra fundida
│   ├── mod_interphase_ht.f90     Transferencia de calor interfase (clamped)
│   ├── mod_drag_ergun.f90        Arrastre Ergun (lecho poroso)
│   ├── mod_continuity.f90        Ecuación de continuidad multifase
│   ├── mod_arc_cassie_mayr.f90   Modelo arco Cassie-Mayr + distribución calor
│   ├── mod_arc_radiation_mc.f90  Radiación MC del arco
│   ├── mod_arc_impingement.f90   Momentum de impingement del arco
│   ├── mod_lorentz_3d.f90        Fuerza de Lorentz (J×B electromagnética)
│   ├── mod_electrode_3d.f90      Control y posicionamiento de electrodos
│   ├── mod_slag_3d.f90           Capa de escoria (flotabilidad + energía)
│   ├── mod_convergence_3d.f90    Chequeo de convergencia SIMPLE
│   ├── mod_input_profiles.f90    Perfil V/I electrodos + receta de carga
│   └── mod_output_hdf5.f90       Salida HDF5 paralela (PHDF5)
├── input/
│   ├── config_production_full.dat  Corrida de producción (toda la física)
│   ├── config_10step_full_physics.dat  Test de regresión
│   ├── config_300s_borein.dat      Calibración bore-in (300 s)
│   ├── config_medium.dat           Malla media (~90k celdas)
│   ├── electrode_profile.dat       Perfil V/I tap-to-tap
│   └── charge_recipe.dat           Receta de carga (cubo 1 y 2)
├── docs/
│   ├── PHYSICS.md                  Modelos físicos y ecuaciones
│   ├── ARCHITECTURE.md             Estructura del código y tipos
│   ├── CONFIGURATION.md            Referencia completa de parámetros
│   └── OUTPUT.md                   Formato HDF5 y post-proceso
├── Makefile
└── README.md
```

---

## Configuraciones disponibles

| Archivo | Malla | Tiempo | Física | Uso |
|---------|-------|--------|--------|-----|
| `config_10step_full_physics.dat` | 18×36×24 | 5 s | Completa | Regresión / CI |
| `config_300s_borein.dat` | 18×36×24 | 300 s | Completa | Calibración bore-in |
| `config_medium.dat` | 35×70×50 | 100 s | Casi completa | Pruebas intermedias |
| `config_production_full.dat` | 60×120×84 | 5040 s | **Completa** | **Producción** |

---

## Verificación rápida de la salida

```python
import h5py, numpy as np

with h5py.File('output/eaf3d_00000001.h5', 'r') as f:
    print(list(f['fields'].keys()))          # lista de campos
    Y_CO = f['fields/Y_CO'][:]               # fracción másica CO
    T_gas = f['fields/T_gas'][:]             # temperatura del gas [K]
    print(f"max(Y_CO)  = {Y_CO.max():.4f}")
    print(f"max(T_gas) = {T_gas.max():.1f} K")
```

---

## Referencias

- Ugarte et al. (2024) *Materials* **17**(21), 5139 — modelo base  
- Cassie (1950), Mayr (1943) — modelo de arco  
- Maahs (1986) — tasa de oxidación de carbono  
- Ergun (1952) — arrastre en lecho poroso  

---

## Documentación detallada

| Documento | Contenido |
|-----------|-----------|
| [`docs/PHYSICS.md`](docs/PHYSICS.md) | Ecuaciones gobernantes, todos los modelos físicos |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Estructura del código, tipos derivados, flujo de datos |
| [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) | Referencia completa de todos los parámetros de config |
| [`docs/OUTPUT.md`](docs/OUTPUT.md) | Formato HDF5, campos disponibles, post-proceso Python |
