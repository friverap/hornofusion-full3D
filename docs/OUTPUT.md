# Formato de Salida — EAF3D

Descripción completa de los archivos de salida: HDF5 paralelo y monitor ASCII.

---

## Tabla de contenidos

1. [Archivos generados](#1-archivos-generados)
2. [Estructura del archivo HDF5](#2-estructura-del-archivo-hdf5)
3. [Campos disponibles en /fields](#3-campos-disponibles-en-fields)
4. [Coordenadas de malla en /mesh](#4-coordenadas-de-malla-en-mesh)
5. [Metadatos en /metadata](#5-metadatos-en-metadata)
6. [Monitor de convergencia](#6-monitor-de-convergencia)
7. [Lectura con Python/h5py](#7-lectura-con-pythonh5py)
8. [Visualización con ParaView](#8-visualización-con-paraview)
9. [Estimación de tamaño de salida](#9-estimación-de-tamaño-de-salida)

---

## 1. Archivos generados

El simulador produce dos tipos de salida:

### Snapshots HDF5 (binario, paralelo)

```
output_dir/eaf3d_XXXXXXXX.h5
```

Donde `XXXXXXXX` es el número de paso con 8 dígitos (p. ej. `eaf3d_00000200.h5`).

**Frecuencia:** controlada por `output_freq` en el config.  
Con `output_freq = 200` y `dt = 0.5 s` → snapshot cada 100 s simulados.

**Nota:** el último paso siempre se escribe, independientemente de `output_freq`.

### Monitor de convergencia ASCII

```
output_dir/monitor.log
```

Una línea por paso monitorizado. Controlado por `monitor_freq`.

---

## 2. Estructura del archivo HDF5

```
eaf3d_00000200.h5
├── /mesh                          Coordenadas de la malla (arrays 1D)
│   ├── r        float64[nr]       Centros de celda radiales [m]
│   ├── theta    float64[nth]      Centros de celda azimutales [rad]
│   └── z        float64[nz]      Centros de celda axiales [m]
│
├── /fields                        Campos físicos (arrays 3D)
│   └── ... (ver sección 3)
│
└── /metadata                      Atributos escalares
    ├── time     float64            Tiempo simulado [s]
    ├── step     int32              Número de paso
    └── nprocs   int32              Número de procesos MPI usados
```

### Orden de ejes en los arrays 3D

Los datasets 3D tienen dimensiones `(nz, nth, nr)` en el orden C/HDF5  
(el índice más lento varía primero: z es el más lento, r es el más rápido):

```python
field.shape == (nz, nth, nr)
```

Para visualizar un plano radial-azimutal a altura k:

```python
field[k, :, :]    # slice en z fija → plano (nth, nr)
```

Para visualizar un plano radial-axial a ángulo j:

```python
field[:, j, :]    # slice en theta fija → plano (nz, nr)
```

---

## 3. Campos disponibles en /fields

### Fase líquida (acero fundido)

| Dataset | Símbolo | Unidades | Descripción |
|---------|---------|----------|-------------|
| `T_liquid` | T_l | K | Temperatura del líquido |
| `alpha_liquid` | α_l | — | Fracción de volumen [0, 1] |
| `velocity_r_liquid` | u_r | m/s | Velocidad radial |
| `velocity_th_liquid` | u_θ | m/s | Velocidad azimutal |
| `velocity_z_liquid` | u_z | m/s | Velocidad axial |

### Fase gaseosa

| Dataset | Símbolo | Unidades | Descripción |
|---------|---------|----------|-------------|
| `T_gas` | T_g | K | Temperatura del gas |
| `alpha_gas` | α_g | — | Fracción de volumen [0, 1] |
| `velocity_r_gas` | u_r | m/s | Velocidad radial |
| `velocity_th_gas` | u_θ | m/s | Velocidad azimutal |
| `velocity_z_gas` | u_z | m/s | Velocidad axial |

### Fase sólida (chatarra/HBI)

| Dataset | Símbolo | Unidades | Descripción |
|---------|---------|----------|-------------|
| `alpha_solid` | α_s | — | Fracción de volumen sólido [0, 1] |
| `T_solid` | T_s | K | Temperatura del sólido |
| `mass_solid` | m_s | kg | Masa sólida por celda |

### Escoria

| Dataset | Símbolo | Unidades | Descripción |
|---------|---------|----------|-------------|
| `alpha_slag` | α_sl | — | Fracción de volumen de escoria |
| `T_slag` | T_sl | K | Temperatura de la escoria |

### Campos compartidos — Flujo y turbulencia

| Dataset | Símbolo | Unidades | Descripción |
|---------|---------|----------|-------------|
| `pressure` | p | Pa | Presión estática |
| `tke` | k | m²/s² | Energía cinética turbulenta |
| `epsilon` | ε | m²/s³ | Tasa de disipación turbulenta |

### Campos compartidos — Arco y electromagnetismo

| Dataset | Símbolo | Unidades | Descripción |
|---------|---------|----------|-------------|
| `S_arc` | S_arc | W/m³ | Fuente volumétrica de calor del arco |
| `F_lorentz_r` | F_r | N/m³ | Fuerza de Lorentz radial |
| `F_lorentz_th` | F_θ | N/m³ | Fuerza de Lorentz azimutal |

### Campos compartidos — Química y especies

| Dataset | Símbolo | Unidades | Descripción |
|---------|---------|----------|-------------|
| `S_chem` | S_chem | W/m³ | Calor total de reacciones químicas |
| `S_CO_src` | ṁ_CO | kg/(m³·s) | Fuente neta de CO (producción - consumo) |
| `Y_CO` | Y_CO | — | Fracción másica de CO [0, 1] |
| `Y_CO2` | Y_CO₂ | — | Fracción másica de CO₂ [0, 1] |

**Total: 25 campos 3D** por snapshot.

---

## 4. Coordenadas de malla en /mesh

Los arrays `r`, `theta`, `z` contienen las posiciones de los **centros de celda**  
(no las caras). Son 1D; las 3 dimensiones del dominio son independientes en coordenadas cilíndricas.

```python
with h5py.File('eaf3d_00000200.h5', 'r') as f:
    r     = f['mesh/r'][:]       # shape (nr,) en metros
    theta = f['mesh/theta'][:]   # shape (nth,) en radianes
    z     = f['mesh/z'][:]       # shape (nz,) en metros
```

Para construir una malla meshgrid completa:

```python
R, TH, Z = np.meshgrid(r, theta, z, indexing='ij')  # shape (nr, nth, nz)
```

---

## 5. Metadatos en /metadata

```python
with h5py.File('eaf3d_00000200.h5', 'r') as f:
    t      = f['/metadata'].attrs['time']    # tiempo simulado [s]
    step   = f['/metadata'].attrs['step']    # número de paso
    nprocs = f['/metadata'].attrs['nprocs']  # MPI processes
```

---

## 6. Monitor de convergencia

El archivo `monitor.log` tiene una línea de cabecera y una línea por paso monitorizado.

### Formato

```
# step  time[s]  m_s[kg]  res_cont  res_ur  res_energy  n_outer
      20     10.00  1.31E+05  1.2E-05  0.0E+00  2.1E-02    5
      40     20.00  1.31E+05  1.1E-05  0.0E+00  2.0E-02    5
```

### Columnas

| Columna | Descripción |
|---------|-------------|
| `step` | Número de paso temporal |
| `time[s]` | Tiempo simulado acumulado |
| `m_s[kg]` | Masa total de sólido en el dominio |
| `res_cont` | Residual de continuidad (global MPI L2) |
| `res_ur` | Residual de velocidad radial |
| `res_energy` | Residual de energía |
| `n_outer` | Iteraciones SIMPLE usadas |

### Lectura con pandas

```python
import pandas as pd
df = pd.read_csv('output_prod/monitor.log', comment='#', sep=r'\s+',
                 names=['step','time','m_s','res_cont','res_ur','res_energy','n_outer'])

# Evolución de masa sólida
df.plot(x='time', y='m_s', title='Masa sólida vs tiempo')

# Convergencia energía
df['res_energy'].plot(logy=True, title='Residual de energía')
```

---

## 7. Lectura con Python/h5py

### Instalación

```bash
pip install h5py numpy matplotlib
```

### Script completo de post-proceso

```python
import h5py
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

def load_snapshot(filepath):
    """Carga un snapshot HDF5 y retorna dict con todos los campos."""
    data = {}
    with h5py.File(filepath, 'r') as f:
        # Metadatos
        data['time']   = f['/metadata'].attrs['time']
        data['step']   = f['/metadata'].attrs['step']
        data['nprocs'] = f['/metadata'].attrs['nprocs']

        # Malla
        data['r']     = f['mesh/r'][:]
        data['theta'] = f['mesh/theta'][:]
        data['z']     = f['mesh/z'][:]

        # Campos (nz, nth, nr)
        for name in f['fields']:
            data[name] = f[f'fields/{name}'][:]
    return data

# Cargar snapshot
snap = load_snapshot('output_prod/eaf3d_00000200.h5')
print(f"t = {snap['time']:.1f} s   (step {snap['step']})")
print(f"Malla: {snap['T_liquid'].shape}  (nz, nth, nr)")

# Temperatura máxima del gas
print(f"max(T_gas)  = {snap['T_gas'].max():.1f} K")
print(f"max(Y_CO)   = {snap['Y_CO'].max():.4f}")
print(f"max(S_arc)  = {snap['S_arc'].max():.2e} W/m³")

# ── Gráfica: plano radial-axial a theta=0 (j=0) ──
fig, axes = plt.subplots(2, 2, figsize=(12, 10))
fig.suptitle(f'EAF3D  t = {snap["time"]:.0f} s', fontsize=14)

r = snap['r']
z = snap['z']

fields_to_plot = [
    ('T_liquid', 'Temperatura líquido [K]', 'hot'),
    ('alpha_solid', 'Fracción sólida [-]', 'Blues'),
    ('Y_CO', 'Fracción másica CO [-]', 'Greens'),
    ('S_arc', 'Fuente calor arco [W/m³]', 'Reds'),
]

for ax, (field_name, title, cmap) in zip(axes.flat, fields_to_plot):
    # slice en theta=0
    data_2d = snap[field_name][:, 0, :]   # (nz, nr)
    im = ax.pcolormesh(r, z, data_2d, cmap=cmap, shading='auto')
    plt.colorbar(im, ax=ax)
    ax.set_xlabel('r [m]')
    ax.set_ylabel('z [m]')
    ax.set_title(title)
    ax.set_aspect('equal')

plt.tight_layout()
plt.savefig('eaf3d_snapshot.png', dpi=150)
plt.show()
```

### Evolución temporal (serie de snapshots)

```python
import glob, re

def load_time_series(output_dir, field_name):
    """Carga la evolución temporal de max(field) sobre todos los snapshots."""
    files = sorted(glob.glob(f'{output_dir}/eaf3d_*.h5'))
    times, values = [], []
    for f in files:
        with h5py.File(f, 'r') as hf:
            t = hf['/metadata'].attrs['time']
            v = hf[f'fields/{field_name}'][:].max()
            times.append(t)
            values.append(v)
    return np.array(times), np.array(values)

t, T_max = load_time_series('output_prod', 'T_liquid')
plt.plot(t, T_max)
plt.xlabel('Tiempo [s]')
plt.ylabel('max(T_liquid) [K]')
plt.title('Temperatura máxima del acero líquido')
plt.axhline(1809, ls='--', label='T_liquidus')
plt.legend()
plt.savefig('T_max_evolution.png', dpi=150)
```

### Calcular masa sólida total (verificación)

```python
with h5py.File('output_prod/eaf3d_00001000.h5', 'r') as f:
    r     = f['mesh/r'][:]
    theta = f['mesh/theta'][:]
    z     = f['mesh/z'][:]
    alpha_s = f['fields/alpha_solid'][:]   # (nz, nth, nr)

# Volúmenes de celda en cilíndricas: dV = r dr dθ dz
dr     = np.gradient(r)
dtheta = np.gradient(theta)
dz     = np.gradient(z)

# Meshgrid en orden (nz, nth, nr)
R, TH, Z = np.meshgrid(r, theta, z, indexing='ij')  # (nr, nth, nz)
R, TH, Z = R.T, TH.T, Z.T                            # → (nz, nth, nr)

dR = np.gradient(r)[np.newaxis, np.newaxis, :]       # broadcast
dTH = np.gradient(theta)[np.newaxis, :, np.newaxis]
dZ  = np.gradient(z)[:, np.newaxis, np.newaxis]

vol = R * dR * dTH * dZ    # (nz, nth, nr)

rho_steel = 7500.0
m_solid = (alpha_s * rho_steel * vol).sum()
print(f"Masa sólida total: {m_solid/1000:.1f} t")
```

---

## 8. Visualización con ParaView

ParaView puede leer HDF5 directamente como XDMF. Generar el archivo descriptor:

```python
def write_xdmf(h5_files, output_file='output.xdmf'):
    """Genera descriptor XDMF para serie temporal en ParaView."""
    with h5py.File(h5_files[0], 'r') as f:
        nz, nth, nr = f['fields/T_liquid'].shape

    with open(output_file, 'w') as xf:
        xf.write('<?xml version="1.0" ?>\n')
        xf.write('<!DOCTYPE Xdmf SYSTEM "Xdmf.dtd" []>\n')
        xf.write('<Xdmf Version="2.0"><Domain><Grid Name="TimeSeries" '
                 'GridType="Collection" CollectionType="Temporal">\n')

        for h5file in h5_files:
            with h5py.File(h5file, 'r') as f:
                t = f['/metadata'].attrs['time']

            xf.write(f'  <Grid Name="t={t:.1f}"><Time Value="{t}"/>\n')
            xf.write(f'  <Topology Type="3DSMesh" NumberOfElements="{nz} {nth} {nr}"/>\n')
            # ... (extender según necesidad)
            xf.write('  </Grid>\n')

        xf.write('</Grid></Domain></Xdmf>\n')
```

Alternativamente, usar el plugin **HDF5 Reader** de ParaView directamente con:
- Formato: `HDF Image`
- Dataset: `/fields/T_liquid`

---

## 9. Estimación de tamaño de salida

| Config | Malla | Campos | Por snapshot | output_freq | Snapshots | Total |
|--------|-------|--------|-------------|-------------|-----------|-------|
| Test regresión | 18×36×24 | 25 | ~1 MB | 1 | 10 | ~10 MB |
| Bore-in 300 s | 18×36×24 | 25 | ~1 MB | 5 | 12 | ~12 MB |
| Producción | 60×120×84 | 25 | ~121 MB | 200 | ~51 | ~6 GB |

### Fórmula

```
Tamaño ≈ n_cells × n_campos × 8 bytes
        = 604,800 × 25 × 8 = 120 MB/snapshot

Snapshots = t_final / (output_freq × dt) = 5040 / (200 × 0.5) ≈ 50
```

### Compresión HDF5 (opcional)

Para reducir el tamaño de salida, añadir compresión gzip a `h5dcreate_f`:

```fortran
call h5pcreate_f(H5P_DATASET_CREATE_F, dcpl_id, error)
call h5pset_chunk_f(dcpl_id, 3, chunk_dims, error)
call h5pset_deflate_f(dcpl_id, 6, error)   ! nivel 6: buen balance velocidad/compresión
call h5dcreate_f(group_id, name, H5T_NATIVE_DOUBLE, dspace_id, dset_id, error, dcpl_id=dcpl_id)
```

Con gzip nivel 6, los campos de temperatura y fracción de volumen se comprimen típicamente 3–5×.
