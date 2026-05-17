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
