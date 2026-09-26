# Arquitectura del código — EAF3D

Estructura interna del simulador: módulos, tipos derivados, flujo de datos y estrategia MPI.

---

## Tabla de contenidos

1. [Visión general](#1-visión-general)
2. [Mapa de módulos y dependencias](#2-mapa-de-módulos-y-dependencias)
3. [Tipos derivados principales](#3-tipos-derivados-principales)
4. [Topología MPI y descomposición de dominio](#4-topología-mpi-y-descomposición-de-dominio)
5. [Estrategia de halos](#5-estrategia-de-halos)
6. [Flujo de ejecución (bucle temporal)](#6-flujo-de-ejecución-bucle-temporal)
7. [Patrón de discretización FVM](#7-patrón-de-discretización-fvm)
8. [Solver TDMA MPI](#8-solver-tdma-mpi)
9. [Salida HDF5 paralela](#9-salida-hdf5-paralela)
10. [Bugs críticos resueltos](#10-bugs-críticos-resueltos)

---

## 1. Visión general

El simulador está escrito en **Fortran 2008** con MPI para paralelización distribuida.

```
main_3d.f90
├── Inicialización: MPI, malla, campos, electrodos, receta de carga
├── Bucle temporal  (time_loop)
│   ├── Arco: Cassie-Mayr → MC radiation → impingement → Lorentz
│   ├── Radiación DO
│   ├── Química: C→CO → combustión secundaria CO→CO₂
│   ├── Transporte de especies: Y_CO, Y_CO₂
│   └── SIMPLE (bucle externo)
│       ├── Drag Ergun
│       ├── Momentum (ur, uθ, uz) por fase
│       ├── Corrección de presión
│       ├── Energía por fase
│       └── Turbulencia k-ε
├── Actualización fase sólida (fusión, collapse, interphase HT)
├── Actualización escoria
└── Salida: HDF5, monitor.log
```

---

## 2. Mapa de módulos y dependencias

```
mod_constants
    └── mod_mpi_topology
            └── mod_types_3d
                    ├── mod_parallel_utils
                    ├── mod_config_3d
                    ├── mod_mesh_3d
                    ├── mod_solver_3d ──────────────────┐
                    │       └── mod_boundary_3d          │
                    ├── mod_energy_3d ◄──────────────────┤
                    ├── mod_species_transport ◄──────────┤
                    ├── mod_momentum_3d ◄───────────────┤
                    ├── mod_pressure_3d ◄───────────────┤
                    ├── mod_turbulence_3d ◄─────────────┤
                    ├── mod_properties_3d               │
                    ├── mod_drag_ergun                  │
                    ├── mod_continuity ◄────────────────┤
                    ├── mod_melting_3d                  │
                    ├── mod_scrap_collapse               │
                    ├── mod_interphase_ht               │
                    ├── mod_solid_phase (combina 3 arriba)
                    ├── mod_multiphase (combina momentum+presión+energía+continuidad)
                    ├── mod_arc_cassie_mayr
                    ├── mod_arc_radiation_mc
                    ├── mod_arc_impingement
                    ├── mod_lorentz_3d
                    ├── mod_electrode_3d
                    ├── mod_radiation_do
                    ├── mod_chemistry_carbon
                    ├── mod_slag_3d
                    ├── mod_convergence_3d
                    ├── mod_input_profiles
                    ├── mod_fields_3d  (alloc/init/exchange/destroy)
                    ├── mod_output_hdf5  (PHDF5)
                    └── main_3d  (usa todos los anteriores)
```

### Orden de compilación (Makefile)

Los módulos se compilan en orden topológico. El orden en `SRCS` respeta las dependencias. La regla de `make` usa `-J$(OBJDIR)` para que los `.mod` de Fortran se encuentren en `obj/`.

---

## 3. Tipos derivados principales

### `config_t` — Configuración global

```fortran
type :: config_t
    ! Geometría
    real(dp) :: R_shell, H_total, H_bowl, R_bowl, R_pcd, R_elec, R_outlet

    ! Malla
    integer  :: nr, ntheta, nz
    real(dp) :: stretch_r, stretch_z

    ! Tiempo
    real(dp) :: dt, dt_min, dt_max, t_final
    logical  :: adaptive_dt

    ! SIMPLE
    integer  :: max_outer, max_inner_mom, max_inner_pres
    real(dp) :: alpha_u, alpha_p, alpha_T, alpha_k, alpha_eps, alpha_alpha

    ! Convergencia
    real(dp) :: tol_cont, tol_mom, tol_energy, tol_turb

    ! Propiedades materiales (acero, gas)
    real(dp) :: rho_steel, T_solidus, T_liquidus, ...

    ! Flags de física
    logical  :: solve_flow, solve_energy, solve_melting
    logical  :: solve_turb, solve_radiation, solve_chemistry
    logical  :: solve_arc, solve_multiphase, solve_slag, solve_species

    ! Escoria
    real(dp) :: rho_slag, cp_slag, k_slag, h_contact_sl, m_slag_init

    ! Especies
    real(dp) :: Sc_t_species, alpha_Y_species

    ! Receta de carga (MAX_LAYERS = 30)
    integer  :: n_layers_b1, n_layers_b2, n_layers_total
    real(dp) :: layer_vfrac(30), layer_mass(30)
    integer  :: layer_bucket(30)
    real(dp) :: t_bucket2_charge
end type config_t
```

### `mesh_t` — Malla cilíndrica 3D

```fortran
type :: mesh_t
    logical          :: is_parallel
    type(mpi_topology_t) :: topo        ! topología MPI

    integer :: nr, ntheta, nz           ! dimensiones locales (sin halos)

    ! Arrays 1D de coordenadas (incluyen halos en modo paralelo)
    real(dp), allocatable :: r(:), theta(:), z(:)
    real(dp), allocatable :: rf(:), thetaf(:), zf(:)  ! caras
    real(dp), allocatable :: dr(:), dtheta(:), dz(:)

    ! Arrays 3D: volumen y áreas de cara (con halos: -1:nr+2, ...)
    real(dp), allocatable :: vol(:,:,:)
    real(dp), allocatable :: Ar(:,:,:)   ! área cara radial
    real(dp), allocatable :: Ath(:,:,:)  ! área cara azimutal
    real(dp), allocatable :: Az(:,:,:)   ! área cara axial

    integer,  allocatable :: cell_type(:,:,:)  ! 0=inactiva, 1=fluido, 2=pared

    ! Coordenadas globales (para HDF5, todos los ranks)
    real(dp), allocatable :: r_global(:), theta_global(:), z_global(:)

    ! Máscara de electrodos (N_ELECTRODES = 3)
    logical, allocatable :: is_electrode(:,:,:,:)
end type mesh_t
```

### `phase_t` — Fase fluida (gas o líquido)

```fortran
type :: phase_t
    real(dp), allocatable :: alpha(:,:,:)   ! fracción de volumen
    real(dp), allocatable :: ur(:,:,:)      ! velocidad radial
    real(dp), allocatable :: uth(:,:,:)     ! velocidad azimutal
    real(dp), allocatable :: uz(:,:,:)      ! velocidad axial
    real(dp), allocatable :: T(:,:,:)       ! temperatura [K]

    ! Propiedades termofísicas
    real(dp), allocatable :: rho(:,:,:), cp(:,:,:), kth(:,:,:)
    real(dp), allocatable :: mu(:,:,:), mu_eff(:,:,:)

    ! Coeficientes SIMPLE (aP de momentum)
    real(dp), allocatable :: aP_ur(:,:,:), aP_uth(:,:,:), aP_uz(:,:,:)
end type phase_t
```

### `solid_t` — Fase sólida (dual-cell, sin N-S)

```fortran
type :: solid_t
    real(dp), allocatable :: alpha_s(:,:,:)    ! fracción de volumen
    real(dp), allocatable :: m_s(:,:,:)        ! masa [kg]
    real(dp), allocatable :: T_s(:,:,:)        ! temperatura [K]
    real(dp), allocatable :: E_s(:,:,:)        ! energía interna [J]
    integer,  allocatable :: layer_id(:,:,:)   ! número de capa de carga
    real(dp), allocatable :: mdot(:,:,:)       ! tasa de fusión [kg/s]
end type solid_t
```

### `slag_t` — Escoria (pseudo-fase)

```fortran
type :: slag_t
    real(dp), allocatable :: alpha_sl(:,:,:)   ! fracción de volumen
    real(dp), allocatable :: m_sl(:,:,:)       ! masa [kg]
    real(dp), allocatable :: T_sl(:,:,:)       ! temperatura [K]
    real(dp), allocatable :: E_sl(:,:,:)       ! energía interna [J]
end type slag_t
```

### `shared_t` — Campos compartidos entre fases

```fortran
type :: shared_t
    ! Presión
    real(dp), allocatable :: p(:,:,:)           ! presión [Pa]
    real(dp), allocatable :: pp(:,:,:)          ! corrección de presión

    ! Turbulencia k-ε
    real(dp), allocatable :: tke(:,:,:)         ! k [m²/s²]
    real(dp), allocatable :: eps(:,:,:)         ! ε [m²/s³]
    real(dp), allocatable :: mu_t(:,:,:)        ! viscosidad turbulenta [Pa·s]

    ! Fuentes del arco
    real(dp), allocatable :: S_arc(:,:,:)       ! calor del arco [W/m³]
    real(dp), allocatable :: S_arc_mom(:,:,:)   ! momentum impingement [N/m³]

    ! Lorentz
    real(dp), allocatable :: F_lorentz_r(:,:,:)   ! fuerza radial [N/m³]
    real(dp), allocatable :: F_lorentz_th(:,:,:)  ! fuerza azimutal [N/m³]

    ! Radiación
    real(dp), allocatable :: S_rad(:,:,:)       ! fuente/sumidero DO [W/m³]

    ! Química
    real(dp), allocatable :: S_chem(:,:,:)      ! calor de reacción [W/m³]

    ! Especies CO/CO₂
    real(dp), allocatable :: Y_CO(:,:,:)        ! fracción másica CO [-]
    real(dp), allocatable :: Y_CO2(:,:,:)       ! fracción másica CO₂ [-]
    real(dp), allocatable :: S_CO_src(:,:,:)    ! fuente neta CO [kg/(m³·s)]
    real(dp), allocatable :: S_CO2_src(:,:,:)   ! fuente neta CO₂ [kg/(m³·s)]
end type shared_t
```

### `electrode_t` — Estado del electrodo

```fortran
type :: electrode_t
    real(dp) :: theta_pos       ! posición azimutal [rad]
    real(dp) :: z_tip           ! posición axial de la punta [m]
    real(dp) :: arc_length      ! longitud de arco actual [m]
    real(dp) :: arc_R           ! resistencia de arco [Ω]
    real(dp) :: arc_power       ! potencia del arco [W]
    real(dp) :: voltage, current
    logical  :: bore_in_done
end type electrode_t
```

### `mpi_topology_t` — Topología MPI

```fortran
type :: mpi_topology_t
    integer :: rank, nprocs
    integer :: comm_cart        ! comunicador cartesiano MPI
    ! Dimensiones globales
    integer :: nr_global, nth_global, nz_global
    ! Dimensiones locales
    integer :: iloc, jloc, kloc
    ! Índices globales de inicio
    integer :: iglobal_start, jglobal_start, kglobal_start
    ! Índices locales de celda activa
    integer :: istart, iend, jstart, jend, kstart, kend
    ! Vecinos MPI
    integer :: neighbor_left, neighbor_right   ! theta
    integer :: neighbor_down, neighbor_up      ! z
end type mpi_topology_t
```

---

## 4. Topología MPI y descomposición de dominio

### Estrategia de descomposición

El dominio se descompone en **theta × z** únicamente. La dirección r **no se descompone**: todos los ranks tienen el rango radial completo `1:nr`.

```
Global: nr × nth × nz
Local:  nr × (nth/p_θ) × (nz/p_z)
```

### Comunicador cartesiano 2D

```fortran
call MPI_Cart_create(MPI_COMM_WORLD, 2, [p_theta, p_z], [.true., .false.], ...)
```

- Dimensión 0 (theta): **periódica** (el fluido es azimutal)
- Dimensión 1 (z): **no periódica** (hay techo y suelo)

### Vecinos MPI por halo

Cada rank intercambia halos de 2 capas con 4 vecinos (±θ, ±z):

```
neighbor_left  ←→ rank en θ-1
neighbor_right ←→ rank en θ+1
neighbor_down  ←→ rank en z-1
neighbor_up    ←→ rank en z+1
```

### Print condicional

Solo el rank 0 imprime al stdout principal (función `should_print(mesh)`).

---

## 5. Estrategia de halos

### Asignación con halos

```fortran
! Todos los arrays 3D usan halos de 2 celdas en cada extremo:
allocate(array(-1:nr+2, -1:nth+2, -1:nz+2))
```

Los índices físicos son `1:nr`, `1:nth`, `1:nz`.  
Los índices de halo son `-1:0` (lado bajo) y `nr+1:nr+2` (lado alto).

### Regla crítica de GFortran: cotas inferiores en dummies

**Problema conocido:** cuando se pasa un array allocatable con cota inferior `-1` a un dummy `(:,:,:)`, GFortran redefine la cota inferior a `1`, causando un desplazamiento de +2 en todos los accesos a halos.

**Solución:** los dummies que acceden a halos deben declararse con cota explícita:

```fortran
! INCORRECTO — GFortran mapea lower bound a 1:
subroutine foo(arr)
    real(dp), intent(in) :: arr(:,:,:)     ! ← cota inferior = 1 ← BUG

! CORRECTO — preserva lower bound = -1:
subroutine foo(arr)
    real(dp), intent(in) :: arr(-1:,-1:,-1:)   ! ← cota inferior = -1 ✓
```

Módulos afectados (ya corregidos): `mod_energy_3d`, `mod_pressure_3d`, `mod_solver_3d`, `mod_output_hdf5`, `mod_species_transport`.

### Halo exchange

```fortran
call mpi_exchange_halos_3d(array, mesh%topo)
```

Llamado después de cada actualización de campo que necesita coherencia entre ranks:
- Fases (α, u, T) → `phase_exchange_halos`
- Sólido → `solid_exchange_halos`
- Escoria → `slag_exchange_halos`
- Especies → `mpi_exchange_halos_3d(sh%Y_CO, ...)` directamente

---

## 6. Flujo de ejecución (bucle temporal)

```fortran
time_loop: do while (time < t_final)
    step = step + 1
    time = time + dt

    ! --- Guardar campos del paso anterior ---
    liq_old = liq;  gas_old = gas

    ! --- Cubo 2 (si corresponde) ---
    if (t >= t_bucket2_charge) call charge_scrap(2)

    ! --- Perfil V/I del electrodo ---
    call interpolate_profile(elec_prof, time, V_elec, I_elec)

    ! --- ARCO ---
    if (solve_arc) then
        call update_arc_resistance(elec, V, I, cfg, dt)    ! Cassie-Mayr ODE
        call update_electrodes(elec, sol, mesh, cfg, dt)   ! bore-in / regulación
        call distribute_arc_heat(elec, sh, mesh, ...)      ! S_arc volumétrico
        call distribute_arc_radiation_mc(...)               ! MC trazado de rayos
        call compute_arc_impingement(...)                   ! S_arc_mom
        call compute_lorentz_force(...)                     ! F_lorentz_r/th
    end if

    ! --- RADIACIÓN DO ---
    if (solve_radiation) call solve_radiation_do(liq, gas, sol, sh, mesh)

    ! --- QUÍMICA ---
    if (solve_chemistry) call compute_carbon_oxidation(sol, gas, sh, mesh, cfg)

    ! --- TRANSPORTE DE ESPECIES ---
    if (solve_species) then
        Y_CO_old = sh%Y_CO;  Y_CO2_old = sh%Y_CO2
        call solve_species_3d(gas, sh%Y_CO,  Y_CO_old,  sh%S_CO_src,  ...)
        call solve_species_3d(gas, sh%Y_CO2, Y_CO2_old, sh%S_CO2_src, ...)
        call mpi_exchange_halos_3d(sh%Y_CO,  mesh%topo)
        call mpi_exchange_halos_3d(sh%Y_CO2, mesh%topo)
    end if

    ! --- SIMPLE (bucle externo) ---
    do outer = 1, max_outer
        call compute_ergun_drag(liq, sol, mesh, cfg, S_drag_r, ...)
        call multiphase_iteration(liq, gas, liq_old, gas_old, sol, sh, ...)
        ! internamente: momentum → corrección presión → energía → propiedades
        if (solve_turb) call solve_k_epsilon(liq, sh, mesh, cfg, dt)
        if (check_convergence(conv, cfg)) exit
    end do

    ! --- FASE SÓLIDA ---
    if (solve_melting) call update_solid_phase(sol, liq, gas, mesh, cfg, dt)

    ! --- ESCORIA ---
    if (solve_slag) then
        call update_slag(slag, liq, gas, sh, mesh, cfg, dt)
        call slag_exchange_halos(slag, mesh)
    end if

    ! --- DT ADAPTATIVO ---
    call adapt_timestep(cfg%dt, conv, cfg)

    ! --- SALIDA ---
    if (mod(step, output_freq) == 0)  call write_hdf5_parallel(...)
    if (mod(step, monitor_freq) == 0) call write_monitor_line(...)

end do time_loop
```

---

## 7. Patrón de discretización FVM

Todas las ecuaciones escalares (energía, especies) siguen el mismo patrón de coeficientes FVM:

```
aP φ_P = aW φ_W + aE φ_E + aS φ_S + aN φ_N + aB φ_B + aT φ_T + Su
```

**Nomenclatura de caras:**

| Coef. | Dirección | Cara |
|-------|-----------|------|
| aW | r negativo (West) | i-1/2 |
| aE | r positivo (East) | i+1/2 |
| aS | θ negativo (South) | j-1/2 |
| aN | θ positivo (North) | j+1/2 |
| aB | z negativo (Bottom) | k-1/2 |
| aT | z positivo (Top) | k+1/2 |

**Convección upwind:**
```fortran
aW(i,j,k) = D_W + max( F_W, 0.0)
aE(i,j,k) = D_E + max(-F_E, 0.0)
```

**Difusión central (energía):**
```fortran
D_W = alpha_q * kth_f * Ar(i-1,j,k) / (0.5*(dr(i) + dr(i-1)))
```

**Difusión central (especies):**
```fortran
D_W = alpha_g * rho_g * D_eff * Ar(i-1,j,k) / (0.5*(dr(i) + dr(i-1)))
```

**Guard de fase mínima:**
```fortran
if (alpha_q(i,j,k) < 1e-6) then
    aP(i,j,k) = 1.0;  Su(i,j,k) = phi_old(i,j,k);  cycle
end if
```

---

## 8. Solver TDMA MPI

### Algoritmo

Thomas Algorithm (TDMA) extendido a 3D con MPI. El barrido se realiza en la dirección z (la descompuesta en MPI) usando comunicación punto a punto para pasar los coeficientes de frontera entre ranks.

Convergencia chequeada con `compute_residual_3d_mpi`:

```
r_i    = Su_i - aP_i φ_i + Σ a_nb_i φ_nb_i           (residual local celda i)

residual = sqrt(Σ r_i²) / (sqrt(Σ (|Su_i| + |aP_i φ_i| + ε)²) + ε)
```

El denominador usa `|Su| + |aP φ|` (no solo `|Su|`) para anclar la norma a la magnitud de la solución. Con solo `|Su|`, el denominador colapsa a `ε²` cuando `Su → 0` (e.g. gas calentándose con ρ decreciente vía gas ideal), produciendo residuales falsos ≫ 1.


### Guard TDMA b(1) ≈ 0

```fortran
b1_safe = merge(b(1), SMALL, abs(b(1)) > SMALL)
```

Previene división por cero en el forward sweep si el coeficiente diagonal es muy pequeño.

---

## 9. Salida HDF5 paralela

### Regla de colectividad PHDF5

En HDF5 paralelo (PHDF5 con MPI-IO), las operaciones de **metadatos** deben ser llamadas por **todos los ranks**:

```fortran
! CORRECTO — todos los ranks crean y cierran:
call h5dcreate_f(group_id, name, H5T_NATIVE_DOUBLE, dspace_id, dset_id, error)
if (rank == 0) call h5dwrite_f(...)    ! solo rank 0 escribe arrays 1D
call h5dclose_f(dset_id, error)        ! todos los ranks cierran
```

Solo `h5dwrite_f` puede ser independiente (solo el rank propietario escribe su chunk).

### Hiperslab por rank

Cada rank escribe su subdomain local al dataset global usando selección hiperslab:

```fortran
offset(1) = iglobal_start - 1   ! offset en nr
offset(2) = jglobal_start - 1   ! offset en nth
offset(3) = kglobal_start - 1   ! offset en nz
call h5sselect_hyperslab_f(dspace_global_id, H5S_SELECT_SET_F, offset, dims_local, error)
call h5dwrite_f(..., xfer_prp=plist_xfer)   ! plist_xfer = H5FD_MPIO_COLLECTIVE_F
```

### Grupos en el archivo HDF5

```
eaf3d_XXXXXXXX.h5
├── /mesh
│   ├── r        (nr_global,)
│   ├── theta    (nth_global,)
│   └── z        (nz_global,)
├── /fields
│   ├── T_liquid          (nz, nth, nr)
│   ├── T_gas             (nz, nth, nr)
│   └── ...  (25 campos total — ver OUTPUT.md)
└── /metadata
    ├── time    (scalar)
    ├── step    (scalar)
    └── nprocs  (scalar)
```

---

## 10. Bugs críticos resueltos

### Bug 1 — MC radiation: bucle infinito

**Causa:** `step_size = minval(m%dr)` incluía celdas halo donde `dr(-1) = 0`.  
**Fix:** `step_size = minval(m%dr(1:m%nr)) * 0.5 + fallback(1e-6 → 0.01)`  
**Archivo:** `mod_arc_radiation_mc.f90`

### Bug 2 — GFortran lower bound offset (+2)

**Causa:** `T_old(:,:,:)` dummy → GFortran setea lower bound=1 en arrays con LB=-1.  
**Fix:** Cambiar a `T_old(-1:,-1:,-1:)` en todos los dummies que acceden a halos.  
**Archivos:** `mod_energy_3d.f90`, `mod_pressure_3d.f90`, `mod_solver_3d.f90`, `mod_output_hdf5.f90`, `mod_species_transport.f90`

### Bug 3 — TDMA singular (alpha_q → 0)

**Causa:** Celdas con fracción de fase casi cero → aP ≈ 0 → división por cero en TDMA.  
**Fix:** Guard `if (alpha_q < 1e-6) aP=1; Su=phi_old; cycle`  
**Archivos:** `mod_energy_3d.f90`, `mod_momentum_3d.f90`, `mod_species_transport.f90`

### Bug 4 — Cassie-Mayr: potencia del arco incorrecta

**Causa:** `arc_power = I²R` → R colapsa a R_min (equilibrio inestable) → P_arc ≈ 0.  
**Fix:** `arc_power = abs(V * I)` directamente desde el perfil del electrodo.  
**Archivo:** `mod_arc_cassie_mayr.f90`

### Bug 5 — HDF5 deadlock en h5fclose_f

**Causa:** `h5dcreate_f` llamado solo por rank 0 → barrera de metadatos desincronizada.  
**Fix:** Todas las operaciones de metadatos colectivas (todos los ranks).  
**Archivo:** `mod_output_hdf5.f90`

### Bug 6 — Interphase HT: divergencia en paso 8

**Causa:** ΔT_gas = Q_gs·dt/(α_g·ρ_g·cp_g·vol) >> |ΔT| → 1260 K/paso → inestable.  
**Fix:** Clamp `Q_lim = α·ρ·cp·vol·|T_fluid - T_solid|/dt`.  
**Archivo:** `mod_interphase_ht.f90`

### Bug 7 — DO radiation: signo y emisión incorrectos

**Causas múltiples:**
- Signo: `κ(4σT⁴-G)` → correcto: `κ(G-4σT⁴)`
- Emisión: `κσT⁴/π` → correcto: `σT⁴/π` (Planck sin kappa)
- SAVE implícito: `I_dir = 0.0` con inicializador en declaración → SAVE → persiste entre llamadas
- Row BC: warm start `I_dir = B(T_first)` en vez de 0 frío

**Archivo:** `mod_radiation_do.f90`

### Bug 8 — Colapso del denominador en `compute_residual_3d_mpi`

**Causa A (celdas triviales):** Celdas con guard de fase (aP=1, todos a_nb=0, Su=φ_old) contribuyen r_local=0 a sum_r pero SMALL² a sum_b. Con ~4500 celdas triviales: sum_b ≈ 4.5e-57 → sqrt(sum_b) ≈ 6.8e-29 → cualquier residual real se infla ~1e25.
**Fix A:** Saltear las celdas donde `aP==1 .and. todos a_nb==0` de ambas sumas.
**Causa B (Su→0 para celdas no triviales):** Al calentarse el gas, `ρ_g = ρ_ref·T_amb/T_g` (gas ideal en `mod_properties_3d`) decrece → `ρ_cp_vol_dt` decrece → `Su = ρ_cp_vol_dt·T_old` se aproxima a cero → sum_b colapsa a SMALL² → `res_energy` falso ≈ 1e63.
**Fix B:** `sum_b += (|Su| + |aP·φ| + ε)²` — ancla el denominador a la magnitud real de la solución.
**Archivo:** `mod_solver_3d.f90`

### Bug 9 — Unidades incorrectas en fuente de fusión (`mod_continuity.f90`)

**Causa:** `Su += sol%mdot * vol`. `sol%mdot` tiene unidades [kg/s] por celda; multiplicar por vol da [kg·m³/s] en vez de [kg/s]. Fuente de fusión ~88× demasiado pequeña.
**Fix:** `Su += sol%mdot` (sin multiplicar por vol).
**Archivo:** `mod_continuity.f90`

### Bug 10 — Desbocamiento térmico del sólido durante fusión (`mod_melting_3d.f90`)

**Causa:** `sol%E_s -= dm · h_fusion` no elimina el calor sensible de la masa dm que se funde. Sin esa corrección: `T_s_new = (E_s - dm·h_fus) / ((m_s - dm)·cp)` puede ser **mayor** que `T_s_old` → realimentación positiva → T_s → NaN.
**Fix:** `sol%E_s -= dm · (h_fusion + cp_eff · T_s)`, lo que garantiza `T_s_new = T_s - dm·h_fus/((m_s-dm)·cp_eff) < T_s`.
**Archivo:** `mod_melting_3d.f90`

### Bug 11 — Fase evanescente: energía huérfana en sólido residual (`mod_melting_3d.f90`)

**Síntoma:** B1 (malla media, t=471.66 s, paso 235829): `T_s` de la celda (1,1,6) salta de 3386 a 35 628 K en un paso, `T_l` → 1e26, momentum 2.5e86, NaN. Los capes de velocidad (`U_LIQ_MAX`) solo lo retrasaban.
**Causa:** la guardia `m_s > SMALL=1e-30` permitía sólidos de microgramos con temperatura propia `T_s = f(E_s/m_s)`; depósitos no proporcionales a la masa (arco, interfase con `Q_lim_sol` ∝ m_s pero `T_l` ya alta) la desbocan. Es el *vanishing phase problem* de los modelos de dos fluidos (Hérard & Hurisse 2014; `residualAlpha` en OpenFOAM, 1e-4 en COMSOL): por debajo de una fracción residual la fase no tiene variables intensivas propias.
**Fix:** cierre conservativo en `compute_melting`: si `0 < m_s ≤ ρ_s·V·ALPHA_SOLID_RESID` (1e-4) y la celda no re-solidifica, toda la masa y entalpía pasan al líquido por el camino `mdot`/`T_src` con `T_src = liquid_entry_T(e) = (e − C0)/cp_l` (conservación exacta en el dato común), y la celda queda exactamente vacía. Celdas vacías con líquido: `T_s := T_l`. Columnas de audit `m_resid_closed`/`E_resid_closed` (subconjuntos de `m_melted`/`E_melt_from_solid`, así las identidades existentes siguen cerrando). Test: `test_residual_closure`. Golden v10.

### Bug 12 — Masa fantasma en el transitorio de la energía del líquido (`mod_energy_3d.f90`)

**Síntoma:** B1 v6 (tras el cierre de fase evanescente): 9 646 kg fundidos, 9 315 kg re-solidificados, **10 kg** de baño a los 442 s con 82 MW de arco; en el snapshot t=440 s el 68 % de las celdas líquidas está bajo el solidus (mediana 740 K, mínimos negativos). Reventó en t=442.88 s (gas%T en el anillo del eje) tras un salto 10 → 5 820 → 65 310 kg de líquido en dos pasos.
**Causa:** el transitorio `α·ρ·cp·V/dt·(T−T_old)` usaba α^{n+1}. El fundido que entra a una celda sin líquido figura entonces como masa que ya existía a `T_old` (300 K, valor inicial de la celda vacía) y la fuente `mdot·cp·T_src` lo mezcla al 50 %: sale a (300+1809)/2 ≈ 1050 K < T_solidus → re-solidifica al paso siguiente → churn permanente que drena la entalpía del sólido. Además el sumidero de re-solidificación añadía `aP += |mdot|·cp` sin contraparte en `Su`: enfriamiento espurio que realimentaba la congelación.
**Fix:** forma exacta de Patankar con la continuidad discreta restada: transitorio con α^n (`alpha_old = liq_old%alpha`), la masa nueva entra solo por los `a_nb` de entrada y por `mdot·cp·T_src`; el sumidero no aporta a `aP` (se cancela algebraicamente), solo queda el latente liberado en `Su`. Guardia `aP ≤ SMALL → ecuación trivial` para fase nueva sin masa vieja ni entradas (continuidad no exacta). Hook del audit actualizado con la misma α. Solo el líquido: el gas conserva la forma T con ρ(T) a la que está calibrado `E_gas_abs`. Test `test_phase_appearance` (fase nueva sale a T_src exacta; sumidero sin latente no enfría). Golden v11.

**Segunda capa (B1 v7, mismo bug):** con el transitorio corregido el líquido subió de 740 K a ~1590 K de mediana pero seguía bajo el solidus y el churn persistía (4 556 kg fundidos / 4 490 re-solidificados / 21 kg de baño a t=187 s). El audit lo señalaba: `E_conv_defect` acumulaba −2.2 GJ (la mitad de `E_melt_from_solid`). Dos fugas hacia vecinas **sin líquido** (42 % de las caras de celdas líquidas), cuya `T_l` es un valor rancio (300 K inicial) que la guardia `α<ALPHA_CUTOFF` deja congelado: (i) la conductancia difusiva usaba `α_P` sola → conducción hacia el "líquido" inexistente de la vecina; (ii) el flujo convectivo con α interpolada simétricamente, `½(α_W ρ u_W + α_P ρ u_P)`, hacía que la vecina vacía entregara masa fantasma a 300 K. **Fix:** α de cara armónica en las conductancias (`aface`: simétrica, telescopa, nula si un lado no tiene fase) para ambas fases, y flujo donor-cell (`face_mass_fluxes_noalpha` × α upwind — el mismo del transporte de α) en la convección del líquido; el gas conserva `face_mass_fluxes`. Casos 3–4 de `test_phase_appearance`. Golden v12.

### Bug 13 — Pérdida de acero por el clip de acotamiento de α (`mod_continuity.f90`)

**Síntoma:** B1 v8 (ya con baño formándose): m_sol + m_liq cae de 65 701 a 61 294 kg en 427 s — 4.4 t de acero desaparecidas, acelerando (7 t/min al final). `m_alpha_clip` lo registraba.
**Causa:** el fundido drena por gravedad hacia celdas del fondo del lecho ya llenas (α_s ≈ 0.6 + α_l ≈ 0.4). El transporte donor-cell no conoce la restricción de volumen; el exceso se recortaba a `1−α_s−α_sl` y se descartaba. Misma familia que los bugs 11–12: una guardia no conservativa.
**Fix:** limitador de hueco en el sub-paso explícito: para cada celda `s = min(1, hueco·ρV/dt_sub + salida − mdot) / entrada`, iterado 3 veces (la salida de una celda es la entrada limitada de la vecina) con intercambio de halos; el flujo efectivo `M·s(receptora)` lo aplican ambas celdas de la cara ⇒ conservativo por construcción e invariante a la descomposición. Físicamente el fundido percola por los huecos y, si no cabe, se acumula encima. Los flujos efectivos promediados sobre los sub-pasos (`ws_Fr/ws_Fth/ws_Fz`) los reutiliza `solve_energy_3d` para el líquido: la convección de energía mueve exactamente la masa que movió la continuidad. El fallback implícito invalida esos flujos (`ws_flux_valid=.false.`) y la energía vuelve al donor-cell de las velocidades. Test `test_alpha_limiter` (celda llena con fondo bloqueado: sin sobrellenado, masa exacta, flujo efectivo nulo; columna uniforme: el limitador no actúa). Golden v13.

**Addendum (B1 v9, t≈425 s):** el limitador con 3 barridos fijos recortó 2.6 t durante un drenaje súbito del líquido encharcado en el lecho hacia el fondo de las columnas de la cavidad: el "no cabe" del fondo avanza UNA celda por barrido Jacobi, y las columnas tenían ~10 celdas. Ahora itera hasta convergencia (‖Δlim‖∞ < 1e-12, allreduce; tope 256). Además `m_alpha_clip` se auditaba en cada iteración externa (α se rehace desde α^n en cada una) — el audit contaba 13.1 t con 2.6 t perdidas, ×5 exacto; `audit_clip_step` audita diferencias telescópicas para que quede la última iteración. Formato del CSV a `ES17.9E3` (un subnormal imprimía `6.678-178` sin la E). Caso 3 de `test_alpha_limiter`. Golden v14.

**Addendum 2 (B1 v10):** los arrays de trabajo de cara `ws_Mr/Mth/Mz` se asignaban solo en celdas propias y sus halos se rellenaban por intercambio MPI — pero los halos de frontera FÍSICA (eje i=0, piso k=0) no tienen rank vecino y nadie los escribía; `cell_in_out`/`eff_flux` los leen. Con memoria sucia en el heap (dependía del estado: el mismo binario con el mismo config no lo reproducía en corridas cortas) B1 v10 creó 12 kg de líquido en el paso 5 y 143 t a los 120 s. Reproducido rellenando los arrays con 1e6 al asignar (líquido desde el paso 1) y neutralizado con el fix: los tres arrays y `ws_lim` a cero/uno COMPLETOS (halos incluidos) al inicio de cada llamada y al asignar. Regla: todo array de trabajo cuyos halos se lean debe inicializarse completo — el intercambio MPI no cubre las fronteras físicas.

**Addendum 3 (B1 v11, derrame conservativo):** con el limitador convergido y los halos limpios quedaba un goteo de clip de ~2 g por fila (0.7 kg/s a t≈480 s, 131 kg acumulados = 0.2 % de la carga; extrapolado a la colada, 3–5 t) en celdas de baño puro exactamente llenas. No es fusión en celdas llenas (ρ_l = ρ_s = 7500, sin expansión) ni chatarra cayendo al baño (snapshots sin sólido dentro del baño): es el residuo del punto fijo del limitador. En vez de recortarlo, el exceso se **derrama** a la celda de arriba con hueco (propagación dirigida, una celda por pasada, finita = profundidad del baño; la misma cantidad la aplican dador y receptor con `give` intercambiado por halos ⇒ conservativo e invariante a la descomposición); la masa derramada entra a `ws_Fz` para que la energía la transporte con la T del dador. Columna de audit `m_spill` (informativa: no es error de masa). Lo que ni así cabe (columna llena hasta el techo) sigue al clip. Diagnóstico `[LIM]` (rank 0, cada 250 pasos con derrame/clip > 1 g): iteraciones del punto fijo, `dlim` al salir, exceso máximo, derramado, recortado — para cerrar la causa del residuo en la siguiente corrida. Caso 4 de `test_alpha_limiter`. Golden v16.

### Bug 14 — Niebla de líquido suspendida bajo el umbral hidrodinámico (`mod_continuity.f90`)

**Síntoma:** B1 v11: a t = 415 s, 3 614 kg de los 10 595 kg de `m_liq` están en el freeboard con α_l exactamente igual a `ALPHA_FLOW_CUTOFF` = 0,01, repartidos en ~30 000 celdas, sin moverse. El baño real en el lecho era 6,7 t, no 10,6.
**Causa:** bajo el umbral hidrodinámico el solver de momento pone la velocidad del líquido a 0 (`mod_momentum_3d.f90`, C2.2) para no romper el acople de presión con inercias diminutas — y esa velocidad nula es la que usa el transporte de α. Las gotas que el arco salpica por encima del umbral vuelan; al diluirse por debajo (difusión numérica donor-cell) pierden la velocidad y la gravedad deja de actuar sobre ellas. En Fluent/OpenFOAM la fase dispersa siempre tiene momento (el residuo α sólo regulariza el arrastre), así que las gotas siempre caen.
**Fix (opción A, cierre de deslizamiento algebraico — Manninen, Taivassalo & Kallio 1996):** en `solve_volume_fraction` la velocidad efectiva del líquido es la del momento donde α_l ≥ 0,01 y, por debajo, la del gas más la velocidad terminal de sedimentación `−u_t(d)·ẑ` con Schiller–Naumann contra el gas local (`settling_velocity`, punto fijo en Re, cota `U_SETTLE_MAX` = 50 m/s). Entra como flujo de cara donor-cell ⇒ conservativo, pasa por el limitador de hueco y el derrame, y la energía lo transporta vía `ws_Fz`. Clave `d_droplet` (default 2 mm; 0 = comportamiento anterior). Para acero en gas a 1800 K, u_t ≈ 35 m/s (2 mm) — mayor que la caída libre de 3 m, así que la niebla llueve en < 1 s y el resultado es insensible a d en 1–5 mm. Test `test_settling` (Newton exacto; columna de niebla cae a ~u_t y llega al fondo con masa exacta; d = 0 no mueve nada). Golden v17.

### Bug 15 — Gotas en el acople presión–velocidad: blow-up del gas y "cave-in" espurio (`mod_pressure_3d.f90`, `mod_momentum_3d.f90`)

**Síntoma:** B1 v11: a t = 414–415 s la presión salta de 40 kPa a la cota `P_HYDRO_CAP` = 2 MPa en **todo** el dominio, el 70 % de las celdas tienen gas a > 100 m/s (mediana 475 m/s en gas puro, 12 km/s en el lecho, máximo 670 km/s) y el charco de 10.6 t se desploma al fondo en 10 s con 3.5 t re-solidificadas. v12 reproduce lo mismo a 450 s y además planta una columna de líquido puro (α_l = 1) colgada del techo. Ambos eventos se habían interpretado como *cave-in* físico. **La masa y la energía se conservaban**: el audit y el vigilante no lo vieron.
**Causa:** desde t ≈ 300 s había focos de presión de 40–90 kPa en celdas con α_l = 0.011–0.012 y α_s = 0 sobre el lecho: gotas que acaban de cruzar `ALPHA_FLOW_CUTOFF` y entran al Poisson con la velocidad que les dio el arrastre del gas (capada a `U_LIQ_MAX` = 20 m/s). Frenar líquido a 20 m/s exige Δp ~ ρ_l u² ~ MPa; esa punta acelera el gas puro vecino (ρ ≈ 0.3) a 400–600 m/s en un paso, que arrastra más gotas… La realimentación es lenta hasta que satura la cota en todo el dominio. Es la familia "inercia diminuta en el Poisson" por la que el cutoff subió a 1e-2, pero con gotas: subir el umbral no basta porque a 0.011 la inercia ya es 270× la del gas — el problema es que una fase dispersa **no debe** imponer restricciones de volumen al Poisson.
**Fix:** el líquido con α_l < `ALPHA_LIQ_CONT` = 0.3 fuera del lecho (α_s < 0.01) es fase **dispersa**: no resuelve su momento (drift-flux: velocidad del gas más sedimentación terminal, mismo cierre del Bug 14) y **no entra al Poisson** ni recibe corrección de velocidad (`liq_continuous`, máscara `ws_liq_cont` calculada por `multiphase_iteration`; `add_phase_contribution`/`link`/`correct_velocities` reciben la máscara por fase). En el lecho (α_s ≥ 0.01) el líquido percola con Ergun y sigue el umbral ordinario. El gas conserva su tratamiento. Columnas de audit `p_max`, `u_gas_max`, `u_liq_max` (allreduce_max) y reglas en `watch_run.py` (p > 3e5 WARN / ≥ 1.5e6 ALERT; |u_g| > 300 WARN / > 1000 ALERT). Test `test_dispersed_liquid`: predicado; la gota queda exactamente en drift-flux y el baño no; **el campo de presión con y sin gota es idéntico a 1e-9**. Golden v18. Corrige la lectura de v11/v12: la referencia física de B1 vale hasta ~300 s; los "cave-ins" eran el blow-up.

**Addendum (mismo día): cierre completo del líquido disperso.** Al introducir el drift-flux, `melt_forced` pasó de p_max 3.4 kPa a la cota 2 MPa con gas a 845 m/s en tres pasos. Se necesitaron cuatro piezas, cada una comprobada por separado sobre `melt_forced` (columnas `p_max`/`u_gas_max`):
1. **Arrastre físico gas–gota.** `Kexch = α_l α_g ρ_l/τ` (τ = 0.01 s) daba τ_gas = 0.1 ms: era el anclaje artificial de la niebla lo que "estabilizaba" v11. K = 0 dejaba al gas libre bajo 100× su masa. Ahora `K = α_l (ρ_l − ρ_g) g / u_t`: exacto en el punto de operación (arrastre = peso con deslizamiento u_t), implícito en ambas fases.
2. **Percolación en el lecho.** El líquido disperso en celdas con chatarra (α_s ≥ 0.01) no monta en el gas: percola verticalmente a √(2 g d_p) ≈ 1.4 m/s (Ergun con el sólido domina). Con la velocidad del gas horneada, la primera celda del lecho que cruzaba α_l = 0.01 entraba al Poisson a decenas de m/s → ρ_l u Δx/Δt ~ MPa (el p_max estaba siempre en esa celda).
3. **Transición disperso → continuo.** `reset_new_continuous`: la celda entra al momento y al Poisson con el promedio de sus vecinas continuas (0 si no hay), también en el ancla `liq_old`.
4. **Relajación de partícula** (la decisiva para el gas). Con el ajuste instantáneo u_l = u_g − u_t el deslizamiento es siempre u_t y el gas sólo siente el peso, nunca la inercia de la niebla: gas a 250 m/s y p 300 kPa sobre el lecho. La hipótesis del deslizamiento algebraico (τ_p ≪ escala del flujo) no se cumple: τ_p = u_t/g ≈ 3.5 s. Ahora `ws_ud = u_old + (Δt g/u_t)(objetivo − u_old)` desde `liq_old`; durante los transitorios del gas el deslizamiento crece y `K(u_l − u_g)` frena al gas con la masa de la niebla. Resultado en `melt_forced`: pico transitorio 115 kPa / 144 m/s y decaimiento a 18 kPa / 85 m/s (v17: 3 kPa / 49 m/s con el anclaje artificial). Caso 4 de `test_dispersed_liquid` (Δu del gas = arrastre implícito exacto) y caso 2 (drift relajado exacto).

**Addendum 2 (B1 v13, t = 5.5 s):** con el cierre completo, B1 reventó en la misma fila del audit del primer líquido: p 0.5 kPa → 2 MPa y gas a 7×10¹¹ m/s en 0.3 s, con 5 kg de líquido esparcidos luego por las 65 k celdas. La sonda `[PROBE]` lo delató: la presión crecía **en cada solve del Poisson de cada iteración externa** sin que el gas se moviera — el Poisson nunca cerraba la divergencia. Causa: `compute_liquid_drift` copiaba `liq%u` al inicio de la iteración también para las celdas **continuas**, y el transporte de α (que reutiliza `ws_ud`) movía el líquido con esa velocidad, una iteración atrasada respecto a la que el Poisson acababa de hacer libre de divergencia. Fix: `effective_liquid_velocity` toma la velocidad ACTUAL en las celdas continuas y el drift relajado sólo en las dispersas. Lección: el campo de velocidad con que se transporta α debe ser exactamente el corregido por el Poisson en la misma iteración; cualquier copia anterior rompe el acople. `melt_forced` (12 pasos) no lo detectó.

**Addendum 3 (B1 v13, la causa real del estallido a 5.5 s):** bisección con corridas de 5.7 s sobre el primer líquido. `fb1c7f5` (sedimentación en el transporte, `liq%u` = 0 bajo el cutoff) pasa; `84f9ca9` revienta con el primer kilogramo. Aislamiento con el código actual: `d_droplet = 0` (disperso inmóvil y sin acople) estable; sin `reset_new_continuous` revienta; K = 0 en dispersas revienta; drift = 0 con K activo estable; guardia de fase en el k-ε revienta; `liq%u` = 0 en dispersas con el transporte moviendo el drift **estable**; regla antigua en el freeboard revienta; convección del momento continuo enmascarada revienta. Conclusión: el disparador es que las celdas dispersas tengan `liq%u` ≠ 0, y el lector no es ni el k-ε ni la convección ni K. Es el **arrastre de Ergun**: `compute_ergun_drag(liq, …)` calcula el coeficiente con ρ_l = 7500 y |v_l| y se aplicaba **también al gas** ("a phase-specific coefficient would be more correct", decía el comentario). Con |v_l| ≈ 1 m/s en celdas del lecho el término de Forchheimer vale C_F ρ_l |v|/√K_perm ≈ 4×10⁸ kg/m³/s: el gas queda congelado celda a celda donde el disperso se mueve, el Poisson pierde sus caminos por el lecho y p sube en cada solve. Dormía porque bajo el cutoff u_l era 0. **Fix:** el gas usa su propio Ergun (`drag_gas` con ρ_g, μ_g, |v_g|) — lo físicamente correcto. La guardia de fase del k-ε (producción, convección y μ_t sólo en líquido continuo) se conserva: era un defecto latente independiente.

### Bug 16 — Presión congelada en celdas sin fase continua (`mod_pressure_3d.f90`, `mod_momentum_3d.f90`)

**Síntoma:** B1 v14 (con Bug 15 cerrado): a t = 42 s `p_max` salta a 6.1262×10⁵ Pa y se queda **idéntico a cinco cifras durante 20 s de simulación**, con el gas a 200–210 m/s sostenidos; el baño, que debería crecer, oscila entre 0 y 80 kg y se re-solidifica entero. La celda del máximo es (k=3, j=40, i=12) con **α_s = 1.0000 exacto, α_g = 0**, y el chorro de gas está en la **misma columna, tres celdas más arriba**.
**Causa:** una celda sin ninguna fase continua queda fuera del Poisson (`aP=1, Su=0 ⇒ pp≡0`), así que su presión **no puede volver a cambiar**: queda congelada en el valor que tuviera al sellarse. Y los vecinos la leen: (i) en `dp/dx` del momento, (ii) en los gradientes de Rhie–Chow que arma el propio Poisson. El resultado es una fuerza permanente sobre el fluido vecino. Antes de Bug 15 casi ninguna celda quedaba fuera del acople (el gas siempre estaba activo), por eso no se manifestaba; la misma patología existía —con p = 0— en las celdas de pared interna de la cuba.
**Fix:** una celda sin fase continua **no tiene presión de fluido**, así que (a) es *pared* para todo gradiente de presión — `pgrad` (en `mod_constants`) hace diferencia unilateral cuando la vecina no es válida, usado tanto en el momento como en el Rhie–Chow del Poisson, con la máscara común `ws_pv_active`; y (b) tras cada corrección se le impone el Neumann de pared (media de sus vecinas con fluido, 0 si no hay ninguna) para que no arrastre valores rancios. Test `test_sealed_cell`: una celda sellada con 6×10⁵ Pa rancios no cambia ni el campo de presión ni la velocidad del gas respecto a la misma celda con p = 0 (antes: 939 m/s de patada).

### Bug 17 — Percolación del líquido disperso 700× demasiado rápida (`mod_constants.f90`)

**Síntoma:** B1 v14 fundía 10× menos que la referencia v11 desde el principio (8 kg de baño a t = 30 s frente a 89 kg), con re-solidificado ≈ fundido.
**Causa:** al cerrar Bug 15 estimé la velocidad del líquido disperso dentro del lecho por caída libre entre trozos, √(2 g d_p) ≈ 1.4 m/s. El balance real —el estado estacionario de **su propia ecuación de momento**, con el arrastre de Ergun del lecho— es `(μ/K + C_F ρ|u|/√K)·u = α_l(ρ_l−ρ_g)g`, que con d_p = 0.1 m, ε = 0.5 y α_l = 0.01 da **≈ 2 mm/s**: 700× menos. El primer fundido abandonaba la zona caliente antes de poder acumularse y se congelaba en la chatarra fría de abajo.
**Fix:** `percolation_velocity` resuelve esa cuadrática (raíz positiva estable) y sustituye a la estimación de caída libre; la relajación de partícula se aplica sólo en el freeboard (en el lecho τ = α_lρ_l/drag ≈ 10⁻⁴ s ≪ Δt). Principio general que deja el episodio: **la velocidad de una fase dispersa es el estado estacionario de la ecuación de momento que se le está sustituyendo**, no una estimación aparte — en el freeboard eso es el arrastre del gas (velocidad terminal de gota), en el lecho el arrastre de Ergun.

### Bug 18 — Excursiones de presión en bolsas de líquido sin gas (`mod_constants.f90`, `mod_multiphase.f90`)

**Síntoma:** B1 v15 (Bugs 15–17 cerrados, comportamiento sano: baño siguiendo a la referencia, masa exacta, clip 0) presenta entre t = 34.6 y 37.7 s una ráfaga de excursiones: `p_max` llega a la cota de 2 MPa y el gas a 9.5 km/s en filas aisladas, con recuperación completa a 4 kPa / 30 m/s. Coinciden exactamente con las ráfagas de fusión (m_liq 26 → 78 kg en 0.3 s). Las celdas del máximo son del lecho, con α_s ≈ 0.6–0.79, α_l ≈ 0.21–0.28 y **α_g ≈ 0–0.12**.
**Causa:** el gas ha sido expulsado de esas celdas y el líquido que queda está hidráulicamente bloqueado — en su `aP` de momento dominan el arrastre de Ergun y el intercambio `Kexch`, así que `d = V/aP → 0` y su fila del Poisson queda con coeficientes de cara minúsculos. Cualquier desbalance de caras (las ráfagas de fusión cambian α rápidamente y el término de fusión no está en el Su del Poisson — decisión de diseño, su reintroducción da ganancia > 1) sólo puede absorberse con presiones de MPa. **No es el solver**: el residual de continuidad es 1e-6 durante todo el episodio; es la solución del sistema discreto.
**Fix:** cota de validez `U_GAS_MAX = 300 m/s` (M ≈ 0.4 a 1500 K) con `cap_gas_velocity`, aplicada tras el momento del gas y tras la corrección de presión — misma familia que `U_LIQ_MAX` y `P_HYDRO_CAP`: una solución con M = 28 está fuera del dominio de validez de la formulación low-Mach, no es física que haya que conservar. La excursión de presión sigue siendo visible en `p_max` del audit (no se esconde), pero deja de propagarse al gas. Test `test_velocity_caps` (cota exacta, dirección preservada, celdas por debajo intactas, líquido disperso exento). Mitigar la rigidez de esas bolsas (compliance del lecho poroso, `TAU_LG` en régimen no disperso) queda como pendiente del roadmap, no como tapón.

### Bug 19 — El Poisson no ve el cambio de composición: el modelo no puede sostener un baño (PENDIENTE, diagnosticado)

**Síntoma:** B1 v16, con todo lo anterior cerrado y una corrida por lo demás sana (masa exacta, clip 0, baño creciendo), escala hasta la cota de presión a partir de t ≈ 65 s y se queda allí. La correlación con el estado del horno es uno a uno: a t = 60 s no hay ninguna celda sin gas y |p| ≤ 250 Pa; a t = 65 s aparecen 8 bolsas sin gas y p_max = 77 kPa; a t = 70 s, 32 bolsas y 429 kPa; a **t = 75 s aparecen las dos primeras celdas de líquido puro (α_l = 1.000) y tienen 1.7 MPa**, con signo negativo (succión). El blow-up empieza exactamente cuando el baño se forma.

**Causa (confirmada):** el Poisson de mezcla impone `div(Σ α_q ρ_q u_q) = 0` sin el transitorio `∂ρ/∂t`. Mientras hay gas en todas las celdas, su término acústico absorbe la discrepancia; en una celda de baño que se llena o drena —sin gas y con el líquido casi incompresible— la única forma de satisfacer divergencia nula es una presión de megapascales. **Por construcción el modelo no puede simular un baño real**; ninguna corrida había llegado a formarlo (el «cave-in» de v11 era este mismo blow-up). `U_LIQ_MAX`, `U_GAS_MAX` y `P_HYDRO_CAP` acotan el daño, no la causa.

**Estado: NO resuelto.** El término correcto es el transitorio de la mezcla **fluida** menos el fundido,

    ∂(α_l ρ_l + α_g ρ_g)/∂t + div(α_l ρ_l u_l + α_g ρ_g u_g) = ṁ
    ⇒  Su −= (V/Δt)[(α_l ρ_l + α_g ρ_g) − (·)^n] − ṁ

y se implementó así (commit bd12cb7, revertido). **Tres errores encontrados al construirlo, cada uno con su síntoma medible** — la parte reutilizable de este episodio:
1. **Incluir el sólido en el transitorio.** El colapso de chatarra pasa a pedir al *fluido* que reponga `δ·ρ_s` ≈ 3750 kg/m³ cuando físicamente sólo debe entrar el gas que llena el hueco, `δ·ρ_g` ≈ 0.1 — cuatro órdenes de magnitud. El sólido no tiene flujo en el Poisson, así que tampoco transitorio.
2. **Referir la cota a la masa total.** Afloja `COMP_SRC_CAP` ~50 000× y desestabiliza hasta `cold_10step`: presión en la cota en 10 pasos. Esa cota existe porque la fuente es rígida.
3. **Restar `ṁ` en la primera iteración externa.** En ella `α_l` todavía es `α^n` (el transporte de α corre *después* de la presión en el lazo SIMPLE), así que `−ṁ` queda sin su contrapartida `∂(α_l ρ_l)/∂t`: es exactamente el «lazo con ganancia > 1, p×50/paso» que el comentario histórico de `mod_pressure_3d` advertía. Síntoma: p en la cota desde t = 5.49 s, el instante del primer fundido.

Con los tres corregidos el término sigue degradando (B1: p en la cota a t = 9 s frente a 126 Pa sin él), porque queda una inconsistencia de orden: la fuente usa la α de la iteración externa anterior mientras el Poisson corrige las velocidades que la van a cambiar, y esta fuente es lo bastante rígida como para amplificar ese desfase. **No es un parche: requiere rediseño del acople.** Hay además una segunda inconsistencia, probablemente la más fundamental: `solve_volume_fraction` reconstruye sus flujos de cara desde velocidades de centro (`face_mass_fluxes_noalpha` + donor-cell), que **no son** los flujos de Rhie–Chow que el Poisson hizo solenoidales (`arho_f·u_f·A` en `add_phase_contribution`); con p convergida, el transporte de α sigue viendo divergencia ≠ 0 y llena/drena celdas espuriamente. Plan de rediseño (Plan C en `~/.claude/plans/iterative-foraging-newell.md`): F0 banco de pruebas rápido (`bath_test`), F1 transportar α con los flujos conservativos exportados del Poisson, F2 re-añadir el transitorio de densidad ya consistente, F3 validar B1 a través del baño, F4 retirar las cotas como muletas. Hasta entonces B1 es válida hasta t ≈ 60 s.

**F0 del Plan C (2026-09-23) — banco de pruebas rápido, baseline medido con el código actual (609f9eb / golden v21):**
- `tests/unit/test_poisson_bath.f90`: columna de celdas *llenas* de líquido con p ferrostática exacta y u = 0 **sí es punto fijo** del Poisson a 1e-9 (pp ≤ 1e-9·ρgH, |u| ≤ 1e-9·g·Δt) — siempre que la p analítica lleve el Boussinesq del momento del líquido, `g_eff = g(1 − β(T_l − T_amb))` (con β = 1.2e-4 y ΔT = 1550 K es el 18.6 % de g; sin él el test «fallaba» un 48 % por un error del *test*, no del solver). Es decir: el acople admite el reposo exacto **cuando ninguna celda cambia de composición**.
- `tests/integration/configs/bath_test.dat` (12×24×16, charco de 274 t con 840 celdas α_l = 1.000, sin arco ni fusión, 1 s): el mismo charco en el ciclo completo (transporte de α incluido) **no** se queda en reposo: |u_l| llega a 0.70 m/s, Δα_l = 4.7e-2 en 1 s, la ferrostática cierra al 6 % y el gas toca `U_GAS_MAX` a t = 1 s. Masa exacta (clip 0). Es la evidencia directa de la inconsistencia (ii): con p convergida, `solve_volume_fraction` ve divergencia ≠ 0 y mueve α.
- `tests/integration/configs/bath_fill.dat` (`melt_forced` + `heel_mass` = 180 t, celdas selladas α_l + α_s = 1 sobre el charco): el limitador **satura en el primer paso** y recorta 5.4 t (2.2 % del acero) bajo las celdas selladas (derrame de 10.8 t); después clip 0. El handoff fusión→líquido cierra a 1e-9. La invarianza n1/n4 falla en ambos bancos (la velocidad del líquido «en reposo» es ruido del acople).
- Checker `tests/integration/check_bath.py` (`bath_hydrostatic` ≤ 1 %, `bath_rest`, `bath_alpha_frozen`, `bath_mass`, `bath_pv_bounded`; `--fill`: `bath_mass_steel`, `bath_melt_handoff`) en la matriz `test-full`; los fallos anteriores están en `tests/xfail.list` con causa y se retiran en F1/F2. Criterio de salida de F1: `bath_test` en reposo con Δα ≡ 0 exacto y `decomposition_bath` invariante.

**F1 del Plan C (2026-09-23) — acople α–p consistente. Cinco piezas, cada una con su síntoma en `bath_test`/`bath_fill`:**
1. **Flujos conservativos exportados del Poisson** (`ws_Fc_*`, `mod_workspace`): en `add_phase_contribution` el líquido guarda por cara + el flujo de Rhie–Chow `F* = (αρ)_f u_f A` y el coeficiente `a_nb`; tras el CG, `F = F* + a_nb(pp_P − pp_nb)`, cuya divergencia por celda es exactamente el residuo del Poisson (más compliance/acústico). `solve_volume_fraction` transporta el líquido **continuo** con `G = F·ρ_f/(αρ)_f` (donor-cell sobre la velocidad de cara solenoidal) en las caras enlazadas; la energía reutiliza los mismos `ws_F*`. La reconstrucción desde velocidades de centro queda solo para caras sin líquido continuo.
2. **Regla de superficie libre** (`liquid_continuity_mask`, `mod_continuity`): la celda con α_l ≥ `ALPHA_FLOW_CUTOFF` que descansa sobre una celda de baño (continua, α_l ≥ `ALPHA_LIQ_CONT`) es película superficial, no niebla: continua. Sin ella la celda de superficie oscilaba entre continua y dispersa al cruzar 0.3; al pasar a dispersa su cara con el baño se desenlazaba del Poisson y el drift empujaba líquido al baño sellado → succión de kPa → gas en la cota (bath_test, t = 0.8 s).
3. **Regla del dador en caras mixtas** (continuo | disperso): quien cede líquido fija la velocidad de la cara. La media simétrica aplicaba al baño la velocidad del gas de la celda casi vacía de encima (50–300 m/s): la celda de superficie se vaciaba hacia arriba en un paso. Convergentes: media (neto); divergentes: 0.
4. **Presión que ve el gas sobre el baño** (`ws_pcorr_g`): el Poisson de mezcla tiene una p por celda y el momento del líquido la pone sobre su línea hidrostática; el gas de la celda de encima leía esa p de centro (con media carga de líquido dentro) y salía disparado. Con líquido estratificado en el fondo de la celda, la p del gas en la interfase es `p + ρ_l g_eff dz(½ − α_l)`; la usan el momento del gas y su contribución al Poisson (gradientes de celda y de cara). Solo celdas de líquido continuo fuera del lecho.
5. **Colapso consciente del baño** (`apply_scrap_collapse`): una celda con α_l ≥ `ALPHA_LIQ_CONT` no es hueco (commit propio).

Además, **Bug 20** (abajo): los residuales del lazo externo no medían nada y el acople P–V se hacía en una sola iteración.

**Estado tras F1** (bath_test a valores de producción, α_p = 0.7, 10 outers): ferrostática al 0.5 %, p_max = ferrostática, u_gas ≤ 30 m/s, masa exacta, invarianza n1/n4 < 1e-3 en todo campo salvo las componentes θ (~0, ruido relativo); `bath_fill`: acero a 8e-11, handoff fusión→líquido 6e-10, p acotada. **Abierto (F1b):** corrientes fantasma del esquema colocado — velocidades de centro de 0.17 m/s con flujos de cara ≈ 0, porque el gradiente central y la fuerza de cuerpo de la celda no se balancean donde p no es lineal (superficie libre, fondo abombado) — y el Δα ≈ 2e-3/s que inducen en la capa bajo la superficie. Remedio previsto: fuerza de cuerpo balanceada por caras (Francois et al. 2006) y corrección de Choi/Majumdar al Rhie–Chow (independencia de Δt y de la relajación). El transitorio de densidad (F2) espera a que el baño en reposo sea punto fijo exacto.

**F1b, dos intentos medidos y revertidos (2026-09-23, tarde) — para no repetirlos:** la corriente fantasma es el **modo par–impar vertical** del esquema colocado: `u_z` alterna de signo entre niveles (k=2 −0.14, k=3 +0.17, k=4 −0.22 m/s, uniforme en cada nivel) con `p` en escalera (saltos de 12.7 y 24.2 kPa alrededor de los 16.8 kPa hidrostáticos); las caras ven la media de dos celdas de signo opuesto ⇒ flujo nulo, y el Poisson no lo ve. En F1 queda **acotado** en 0.17 m/s. (a) *Fuerza de cuerpo balanceada por caras* (Francois 2006) en momento y en el Rhie–Chow, con la máscara «cualquier fluido» para las caras: la celda de superficie promedia una cara con gas que su Poisson no enlaza ⇒ le falta ¼ de su peso ⇒ 3 m/s. (b) Lo mismo con gradientes, fuerzas y corrección de velocidad sobre el **dominio de la fase** (one-sided en la superficie, misma regla que `link`): consistente entre predictor, corrector y flujo, pero el gradiente one-sided de la superficie acopla las cadenas par e impar y el modo **crece** (×2 cada 10 pasos: 0.02 → 15 m/s en 1 s). El remedio de libro para un modo par–impar que el RC no amortigua es la corrección de Choi/Majumdar (el término transitorio `ρV/Δt` hace `d_f ~ Δt/ρ`: con Δt pequeño el RC pierde su amortiguamiento del tablero de ajedrez), no la fuerza de cuerpo. Pendiente; mientras, la cota 0.17 m/s de F1 es el estado de referencia y B1 v19 lo está poniendo a prueba.

**B1 v19 (checkpoint F3, binario F1): FALLA a t ≈ 65 s — y la causa cierra el diagnóstico del Bug 19 (2026-09-23, noche).** Hasta t = 64 s sana (p ≤ 220 Pa, gas ≤ 34 m/s, clip 0). A t = 65 s, en un anillo de celdas (i = 9) a k = 4: chatarra **fría** (T_s 500 K, α_s 0.62) bajo un **charco** recién fundido en k = 5 (α_s 0 → α_l 0.80, 1824 K). El líquido percola a la celda fría (α_l 0.013, justo sobre `ALPHA_FLOW_CUTOFF`) y **re-solidifica** allí (α_s 0.62 → 0.75). El Poisson, sin fuente de cambio de fase y en forma de **masa**, ve entrar masa de líquido que desaparece y exige **gas** de igual masa saliendo por la celda: dipolo +162/−123 kPa entre k = 4 y k = 5 y gas succionado a 300 m/s. Veredicto y mecanismo en `campaigns/b1_v19_f1_120s/VEREDICTO.md`.

**Conclusión (F2):** la ecuación de presión de un modelo multifluido es la de **volumen**, Σ_q[∂α_q/∂t + div(α_q u_q)] = fuentes (suma de continuidades de fase divididas por su densidad), no la continuidad de la masa de la mezcla que lleva `solve_pressure_correction` desde el origen (`(αρ)_f u_f A`). En forma de masa, el líquido que entra a una celda debe compensarse con gas de igual **masa** (7500× su volumen): imposible ⇒ MPa. Ésa es la raíz común de las celdas de líquido puro de v16 y del charco sobre chatarra fría de v19; la fusión y la re-solidificación (ρ_l = ρ_s) son neutras en volumen sin fuente alguna. Un transitorio de densidad en forma de masa sobre el transporte consistente de F1 doble-cuenta el flujo de la iteración anterior (div F_k = div F_{k−1}) y revienta hasta el baño en reposo (medido). El Poisson de volumen está implementado en la rama `planc-f2-volumen` (con presión hidrostática inicial y el banco `bath_freeze`): `bath_fill` y `bath_freeze` acotados, pero `bath_test` **inestable** en las celdas de superficie del anillo del eje (modo θ de período 4, ×300/paso): en volumen las filas con gas las domina el gas (α_g d_g ~ Δt/ρ_g), la corrección d_g∇pp sobre caras de 4 cm da 100–300 m/s y el arrastre lo pasa al líquido. Siguiente: estabilizar las filas dominadas por la fase ligera (eliminación parcial del arrastre en d_f a la manera de los códigos Euler–Euler, o tratamiento específico de las celdas de superficie) antes de volver a B1.

**F2 (2026-09-24), tras la revisión bibliográfica (memoria `literatura-acople-multifase`): cuatro piezas en la rama `planc-f2-volumen`, cada una respaldada por la literatura y medida en los bancos.**
1. **Poisson de volumen (GCBA)**: `Σ_f α_f (α V/aP)_f A/δ · Δpp = −Σ_f α_f u_f A + fuentes/ρ`; Darwish–Moukalled ("weighted pressure correction": con la forma de masa la conservación del fluido ligero es pobre), OpenFOAM `multiphaseEulerFoam` (`Σ αf·phiHbyA`, `Σ αf·alpharAUf`), Liu et al. 2024 ec. 11. Flujos exportados `ws_Fc_*` volumétricos; compresibilidad del gas `(α_g/ρ_g)Dρ_g/Dt`; acústicos `α_g/P0`, `α_l/(ρ_l c²)`.
2. **Factor α en el corrector y en el Rhie–Chow** (`d = α V/aP`, `alpharAU`): el predictor lleva `−α∇p·V`, así que la respuesta de la velocidad a la presión es `αV/aP`; con `V/aP` la corrección era 1/α veces demasiado fuerte fuera de las celdas puras (bug de consistencia, presente desde el origen).
3. **Eliminación parcial del arrastre (PEA)** en la etapa de momento, sobre las soluciones **sin relajar** (la identidad `H_k = aP_k u_k − K V u_otro,usado` sólo vale para la solución del TDMA; aplicado tras la corrección y sobre campos relajados/acotados reventaba `bath_fill` en el primer paso): por celda con ambas fases activas, `u_l' = (aP_g H_l + KV H_g)/det`, `u_g' = (aP_l H_g + KV H_l)/det`, `det = aP_l aP_g − (KV)²`. Spalding 1980, Karema & Lo 1999, Darwish–Moukalled ec. 29. Eliminó el modo θ del anillo del eje (0.02 → 15 m/s en 1 s) que era el desfase secuencial con K = 1.8e5.
4. **El gas no carga el peso del líquido CONTINUO** (`gas_pgrad_z`, `gas_gz`, `liq_weight_f`): en las caras verticales el gradiente del gas es `(p_N − p_P)/δ + (α_lρ_l)_f g_eff` con α_l sólo de celdas de líquido continuo (morfología de interfase grande, AIAD/LIM). Con una sola p por celda, la p de la celda de superficie está sobre la línea hidrostática de la mezcla y el gas de encima leía el salto de cara (0.2ρ_l g Δz) como fuerza: chorro fantasma **uniforme** de 25 m/s sobre el baño en reposo (balance ρ_g u²/L ≈ 2.2 kPa/m, medido). En una niebla el gas SÍ debe sentir el gradiente de mezcla (la flotación compensa el arrastre de las gotas: `test_dispersed_liquid` caso 4), de ahí la restricción al líquido continuo. Sustituye a `ws_pcorr_g` (que tenía el signo de la corrección al revés: suponía la línea del líquido por el centro de la celda de superficie).
Además: **presión hidrostática inicial** (`initialize_hydrostatic_pressure`, gather global) y banco `bath_freeze`.

**Resultado en los bancos (n = 4):** `bath_test`: ferrostática 0.9 %, p_max 72 kPa, gas ≤ 21 m/s, masa exacta, Δα en celdas puras 1.1e-3 en 1 s (antes 4.7e-2), corriente fantasma 0.17 m/s **acotada y no creciente** (Liu et al. 2024 documentan picos espurios del mismo tipo en interfases bruscas y los declaran no eliminables con los métodos actuales). `bath_fill`: acero 1e-9, handoff 1e-9, p 71 kPa, gas 102 m/s. `bath_freeze` (40 t congelan en 1 s): p 68 kPa, gas 14 m/s; residuos de contabilidad del limitador bajo congelación masiva de 1e-6 (acero) y 5e-6 (handoff) — pendiente menor. `test_dispersed_liquid` 3b: con el Poisson de volumen la "regla antigua" (gotas en el Poisson) ya no dispara p (ratio 1.002): el mecanismo de MPa era la forma de masa, confirmado.

**Juez de 1 h (2026-09-24):** el reproductor grueso de B1 con el binario F2 (`campaigns/b1_v20c_coarse_f2/VEREDICTO.md`) cruza la ventana 60–90 s con p_max ≤ 3.6 kPa (la F1: 43–117 kPa y gas en la cota a 88 s), gas ≤ 142 m/s, clip 0 y la misma curva de fusión (1255 vs 1256 kg fundidos). Sólo dos filas aisladas de 20–25 kPa durante ráfagas de fusión, disipadas en el snapshot siguiente. F2 pasa a `main`; el siguiente juez es B1 en malla media a 120 s.

**B1 v21 (malla media, F2) → F2.4/F2.5/F2.6/F2.7 (2026-09-24).** v21 tocó la cota a t = 34–37 s (`campaigns/b1_v21_f2_120s/VEREDICTO.md`): celdas altas del lecho frío que se **llenan** de fundido percolado desde el charco de encima hasta α_g = 0.010 → el gas deja de ser activo y la celda queda sellada por Ergun con +32 kPa (MPa entre snapshots): el "water packing" de los códigos de sistema. Se probaron y **descartaron** tres remedios, cada uno medido en bancos y reproductor grueso: **F2.4** interpolación de cara ponderada por movilidad para el líquido (d_f armónico, MWIM) y **F2.5** bolsas selladas del lecho como pared para el gradiente del gas — fusión idéntica pero picos de 49–66 kPa a 45.3 s (ráfaga de fusión) y 87 s con gas en la cota, peor que F2 (`campaigns/b1_v22c_coarse_f24`, `b1_v23c_coarse_f25`; revertidas en `cb5fc38`, `39d8576`); **F2.6** canal residual de gas en el Poisson (`residualAlpha` de OpenFOAM: el gas enlaza caras en toda celda con fluido con `max(α_g, 1e-3)` y movilidad `Δt/ρ_g`) — flujo fantasma que deja pasar líquido a celdas selladas (`bath_freeze`: 1.6 t recortadas; `bath_test`: ferrostática al 16 %). El que cierra: **F2.7, gas residual de poro por VOLUMEN** (`adf0bad`): `liq_cap = 1 − α_s − α_sl − ALPHA_PORE_GAS` (1.5e-2) en celdas con α_s ≥ 1e-2 acota la **entrada** de líquido en el limitador y dirige el derrame; el recorte final usa el hueco físico (nunca borra líquido presente); el gas de poro queda siempre activo y la celda nunca se sella. Bancos en verde (`bath_fill`: 1.46 t derramadas desde huecos inicialmente llenos, clip 0; `bath_freeze` clip 6 kg de 246 t) y reproductor grueso **pasa** (`campaigns/b1_v24c_coarse_f27/VEREDICTO.md`: fusión idéntica a F2, clip 0, p máx 26 kPa en 4 filas aisladas, gas ≤ 97, el evento de 87 s en 0.95 kPa). Golden v26. Juez siguiente: B1 v22 en malla media a 120 s (`campaigns/b1_v22_f27_120s`).

**F2.8 y mapa de la malla media (2026-09-25).** B1 v22 (F2.7) repitió el episodio de 34 s de v21 atenuado (362 kPa): las 12 celdas del lecho estaban exactamente en su cap de poro (α_g = 0.0150) — el gas residual está esclavizado al líquido por `TAU_LG` y bloqueado por Ergun, así que no ventea, y el Poisson seguía empujando líquido que el limitador rechazaba. **F2.8** (`e12a7c4`, golden v27): el Poisson del líquido cierra las caras hacia celdas del lecho sin hueco de poro (`face_open`, según el signo de u_f, simétrico) y el derrame cascada por la columna (la celda de arriba se llena hasta su hueco físico y cede en la pasada siguiente; `N_SPILL_MAX` 128). Reproductor grueso: pasa y mejora (p máx 7 kPa, ninguna fila > 20 kPa). **Malla media a 120 s (`campaigns/b1_v24_f28_120s/VEREDICTO.md`)**: el modelo **sobrevive la formación del baño** (392 kg a 120 s, fusión continua, clip 0, nunca en la cota; v19 moría a 65 s) pero con 13 episodios de 20–934 kPa (31 s de 120), todos con el mismo mecanismo: celdas en cap de poro con presión congelada (fila del Poisson casi vacía) que el charco de encima lee como gradiente. Probados y descartados: sacar esas celdas del Poisson por completo (F2.9: `bath_fill` a 1.3 MPa al fundir por dentro) y anular el arrastre gas–líquido en todo el lecho (F2.10: `bath_freeze` a 209 kPa). Pendiente: pared para vecinos sin salir del Poisson, o gas de poro con movilidad propia sólo en celdas en cap; y reinicio desde snapshot para iterar sobre el instante de 34 s en minutos.

**Reinicio desde snapshot (`mod_restart`, 2026-09-25).** `write_hdf5_parallel` añade el grupo `/restart` (E_s, m_C, layer_id, escoria por componente, mu_t, rho_gas, mu_eff_liquid; atributos dt y estado de los 3 electrodos) y `restart_file` en el config reanuda desde ese paso y tiempo con cualquier número de ranks (lectura por hyperslab). Contrato: bit a bit contra la corrida continua (`run_restart_case` en `tests/run_tests.sh`, rtol 1e-12). Hallazgo al cerrarlo: la corrida continua arranca cada paso con `rho_gas` de la última iteración externa (previa a la interfase) — recomputarla de T desviaba p un 15 % en el lecho, así que se guarda la propiedad, no se recalcula. Snapshots sin `/restart` se aceptan con reconstrucción aproximada (`docs/OUTPUT.md` §5b).

**Reproductor de 33 s y cierre del mecanismo (2026-09-25).** Con el reinicio, B1 v25 (= v24 reanudada desde el snapshot de 30 s) reprodujo el episodio (33.27–34.08 s, 248 kPa) y dejó un snapshot completo a 33.0 s (`scratchpad/b1_v25_restart30/eaf3d_00016500.h5`): el juez pasa a ser «reanudar desde ahí hasta 34.8 s» (~15 min a 12 ranks). Probados sobre ese juez y **descartados por innecesarios** (parche en `docs/dev-history/2026-09-25_f211_selladas_f24_mwim.patch`): **F2.11** celdas selladas (celda en cap sin ninguna cara de líquido abierta sale del Poisson como incógnita y recibe presión hidrostática de sus vecinas por barridos Jacobi; ojo: el bloque tiene colectivas MPI y no puede ir tras un `if (any(sealed))` por rank — deadlock medido) → 169 kPa a 33.33 s; **F2.11 + F2.4** (interpolación por movilidad re-aplicada) → 286 kPa. Ambas pasan los bancos `bath_*`, pero no tocan la causa. El diagnóstico fino con snapshots cada 0.05 s (`scratchpad/b1_v26_onset/onset.py`) llevó al **Bug 21** (§10): la corrección de Ergun sola (v29) da el mismo resultado que con las dos piezas encima (v28): pico 16–19 kPa a 33.3 s sin episodio > 20 kPa. Queda como observación: el líquido disperso toca `U_LIQ_MAX` un instante bajo el jet del arco (drift = velocidad del gas, 140 m/s); no es el acople P–V (p < 20 kPa).

**B1 v30 (malla media, Bug 21, 2026-09-25/26) y F2.13.** Con el Ergun correcto desde t = 0 (`campaigns/b1_v30_bug21_120s_r/VEREDICTO.md`): gas nunca en la cota, clip 0, tiempo con p > 20 kPa de 30.8 s (v24) a 10.6 s, peor pico de 934 a 111 kPa. Dos familias: (1) 17 episodios cortos (≤ 0.6 s, 25–84 kPa) en ráfagas de fusión bajo los arcos —la celda recién fundida deja caer su líquido disperso a 20 m/s (drift = gas del jet) sobre la celda del lecho, que llega al cap—; (2) **uno sostenido de 111 a 120 s que crece linealmente hasta 111 kPa** en celdas del fondo bajo los arcos con α_s 0.985, sin líquido y solo el gas residual de poro (α_g = 0.015, F2.7) calentándose de 657 a 1185 K: gas inmóvil, fila del Poisson sin salida, y el término de compresibilidad integra `p ≈ P0 (T/T0 − 1)` — la termodinámica de un poro sellado a volumen constante (132 celdas así a 120 s). **F2.13**: el gas residual de poro *solo* (`pore_gas_only`: α_s ≥ 1e-2, α_l < `ALPHA_FLOW_CUTOFF`, α_g ≤ 1.05·`ALPHA_PORE_GAS`) no es fase fluida del acople P–V —existe para la contabilidad de volumen de F2.7, no para llevar presión—: sale de `ws_pv_active` y de `act_g` (pared para los gradientes, pp = 0, Neumann de p, sin fuente de compresibilidad ni acústico), igual que una celda sin fluido (Bug 16). Juez de reinicio desde 110 s: tiempo > 20 kPa de 8.59 a 0.24 s, p_max de 111 a 42 kPa (lo que queda es una ráfaga); sobre la ventana de ráfagas 80–88.5 s es neutra (0.31 s frente a 0.42 s, 78 frente a 79 kPa); bancos `bath_*` y `test-full` en verde sin mover el golden (ningún config de test tiene celdas de poro solo). Probada y **descartada** en el mismo juez la regla de entrada al lecho para el flujo disperso (F2.12-B: `bed_entry_cap` a la terminal de Ergun con la α del dador; `scratchpad/cand/patch_B.py`): acumula el líquido sobre el lecho y entra de golpe por la vía continua — picos de un paso hasta 123 kPa y gas en la cota donde v30 no pasaba de 79 kPa. La familia (1) sigue abierta: ráfagas de fusión de ~100 kg en 0.5 s bajo el arco con lluvia dispersa a la velocidad del gas.

### Bug 21 — Coeficiente de Forchheimer de Ergun con unidades erróneas: el lecho era ~500–800× más resistente que Ergun (`mod_constants.f90`, `mod_drag_ergun.f90`)

**Síntoma:** toda la familia Bug 18/19 en el lecho: el líquido «percolaba» a 2–3 mm/s (`percolation_velocity`), el gas de poro no podía ventear por el lecho y cualquier celda del lecho que se llenaba de fundido respondía con kPa–MPa (B1 v16–v27). En el reproductor de reinicio (`scratchpad/b1_v25_restart30`, snapshot completo a 33.0 s de la malla media) el episodio de 33.3 s se reprodujo con F2.8 (248 kPa) y no cedió ni con las celdas selladas (F2.11: 169 kPa) ni con la interpolación por movilidad (F2.11+F2.4: 286 kPa). El diagnóstico fino (`onset.py`, snapshots cada 0.05 s) mostró el arranque: bajo cada arco una celda del lecho funde por completo en 0.3 s (m_s 9.5 → 0 kg; baño 65 → 118 kg), su líquido cae a la celda del lecho de abajo (α_s 0.65, hueco 0.24) a 1–6 m/s —primero continuo por el Poisson, luego disperso «lloviendo» al drift del gas del jet del arco—, la celda pasa de α_l 0.10 a 0.34 en 0.05 s y su gas de poro, incapaz de salir contra Ergun, responde con 46–63 kPa; después el gas revienta hacia arriba (+163 m/s) y el líquido toca `U_LIQ_MAX`.
**Causa:** el término de Forchheimer se escribía `C_F ρ |u| / √K` con `C_F = 1.75/(d_p ε³)` (unidades 1/m) en vez del adimensional de Ergun `1.75/√(150 ε³)`; el factor sobrante es `√150/(d_p ε^1.5)` ≈ 460–790 con d_p = 0.075–0.10 m y ε = 0.35–0.5. Con ello la velocidad de percolación bajo gravedad de un lecho al 65 % es 3 mm/s en lugar de ~0.1–0.2 m/s, y el gas necesita decenas de kPa por celda para atravesarlo a 1 m/s. Estaba en los dos sitios (momento de ambas fases y `percolation_velocity`) y el `test_ergun` verificaba la fórmula errónea contra sí misma.
**Fix:** `mod_constants::ergun_coefficients` como única definición, en la forma original de Ergun (1952): `A = 150 μ (1−ε)²/(d_p² ε³)`, `B = 1.75 ρ (1−ε)/(d_p ε³)`, `coef = A + B|u|`; la usan `compute_ergun_drag` y `percolation_velocity`. `test_ergun` compara contra la correlación escrita a mano con valores de referencia (d_p = 0.10, ε = 0.5: A = 180 kg/(m³·s), B = 5.25e5 kg/m⁴). Juez de reinicio (v28, desde 33.0 s): ningún episodio > 20 kPa; pico 16–19 kPa a 33.3 s que vuelve a ~300 Pa en 0.1 s; bancos `bath_test`/`bath_fill`/`bath_freeze` en verde. Lección: un test unitario que reproduce la fórmula del código no verifica nada; hay que contrastar con la correlación de la fuente y con un valor a mano.

### Bug 20 — Los residuales del lazo externo no medían el iterado (`mod_momentum_3d.f90`, `mod_pressure_3d.f90`)

**Síntoma:** en `bath_test` cada paso hacía `outer = 1` con residuales `(6.8e-17, 8.9e-6, 5.9e-17)`, mientras el líquido "en reposo" se movía a 0.7 m/s.

**Causa:** el residual de momento se evaluaba con el campo **recién resuelto** (post-TDMA): ~1e-17 siempre. El de continuidad era el residual del **CG** de la corrección de presión (≤ `SOR_TOL_PRESSURE` = 1e-5 por construcción), no el desbalance de masa de u*. Con `tol_mom = tol_cont = 1e-4`, ambos declaraban convergencia en la primera iteración y el acople P–V nunca se iteraba salvo que la energía pidiera más. La energía ya tenía la semántica correcta (residual del iterado entrante, cierre 2026); momento y continuidad se quedaron atrás.

**Fix:** momento: residual ANTES del TDMA con el iterado entrante (mismo `compute_residual_3d_mpi`). Continuidad: `Σ|Su| / Σ_caras |F*|` sobre celdas activas antes del CG (desbalance de masa normalizado por el flujo de masa total). `cold_10step` bit a bit (ya iteraba 5 outers por la energía); `melt_forced`, `outer_conv` y los bancos del baño cambian (golden v23). El test `outer_convergence` (C3) exige convergencia real: con residuales de momento reales y α_u = 0.3 el lazo tarda más — ver la nota en `tests/xfail.list`.
