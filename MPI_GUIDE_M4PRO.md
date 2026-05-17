# 🖥️ Configuración MPI para tu Mac M4 Pro

## 📊 Hardware Disponible

```
Chip: Apple M4 Pro
Cores Totales: 14 (10 performance + 4 efficiency)
Cores Físicos: 14
Cores Lógicos: 14
Memoria: 48 GB
Arquitectura: arm64
```

---

## 🎯 RECOMENDACIONES DE PROCESOS MPI

### Regla General
**Máximo recomendado = Número de cores físicos = 14 procesos**

### Por Tipo de Test

#### 1. **Testing y Desarrollo** (usa efficiency cores también)
```bash
# Óptimo: 8 procesos (2×2×2 = buen cubo 3D)
mpirun -np 8 ./bin/eaf3d_mpi input/config_test.dat

# Alternativa: 12 procesos (2×3×2)
mpirun -np 12 ./bin/eaf3d_mpi input/config_test.dat

# Máximo: 14 procesos (usa todos los cores)
mpirun -np 14 ./bin/eaf3d_mpi input/config_test.dat
```

#### 2. **Producción/Largas Simulaciones** (solo performance cores)
```bash
# Óptimo: 8 procesos (2×2×2)
# Deja 2 performance cores libres para el sistema
mpirun -np 8 ./bin/eaf3d_mpi input/config_production.dat

# Alternativa: 10 procesos (2×5×1)
# Usa todos los performance cores
mpirun -np 10 ./bin/eaf3d_mpi input/config_production.dat
```

#### 3. **Scaling Tests** (para medir performance)
```bash
# Escala de 1 a 14
for np in 1 2 4 6 8 10 12 14; do
    echo "=== Testing with $np processes ==="
    time mpirun -np $np ./bin/eaf3d_mpi input/config_small.dat
done
```

---

## 🔢 Factorización 3D Recomendada

Tu código tiene factorización automática, pero para entender qué hace:

### Configuraciones Óptimas (npr × npth × npz)

| Procs | Factorización | Forma | Uso |
|-------|---------------|-------|-----|
| 1 | 1×1×1 | Serial | Baseline |
| 2 | 2×1×1 | Plano | Test |
| 4 | 2×2×1 | Plano | Test rápido |
| 6 | 2×3×1 | Plano | Test medio |
| 8 | 2×2×2 | **Cubo** | **ÓPTIMO** ✅ |
| 10 | 2×5×1 | Plano | Máx performance cores |
| 12 | 2×2×3 | Casi cubo | Bueno |
| 14 | 2×7×1 | Plano | Máx todos cores |

**Recomendación**: **8 procesos (2×2×2)** es ideal porque:
- ✅ Forma cúbica (mínima comunicación)
- ✅ Deja cores libres para el sistema
- ✅ Factorización perfecta

---

## 💾 Consideraciones de Memoria

### Memoria por Proceso
```
Total: 48 GB
Sistema: ~4 GB
Disponible: ~44 GB

Memoria por proceso:
- 8 procs:  ~5.5 GB/proceso
- 10 procs: ~4.4 GB/proceso
- 14 procs: ~3.1 GB/proceso
```

### Tamaño de Malla Recomendado

Para tu simulación EAF con nr=50, nth=60, nz=80:

```
Memoria por proceso ≈ nr_local × nth_local × nz_local × variables × 8 bytes

Ejemplo con 8 procesos (2×2×2):
- nr_local = 50/2 = 25
- nth_local = 60/2 = 30  
- nz_local = 80/2 = 40
- variables ≈ 50 (todas las fields)
- Memoria ≈ 25×30×40×50×8 = 1.2 GB/proceso ✅

Con 48 GB total → Puedes correr mallas MUCHO más grandes
```

---

## 🚀 COMANDOS ESPECÍFICOS PARA TU MAC

### Test Rápido (2 minutos)
```bash
cd /Users/franciscojavierriverapaleo/hornofusion/full3D

# Test básico con 8 procesos (ÓPTIMO)
mpirun -np 8 ./bin/eaf3d_mpi input/config_test.dat

# Ver output
ls -lh output/
python3 scripts/hdf5_to_vtk.py --info output/eaf3d_*.h5
```

### Strong Scaling Test (30 minutos)
```bash
# Crear script de benchmark
cat > benchmark.sh << 'EOF'
#!/bin/bash
cd /Users/franciscojavierriverapaleo/hornofusion/full3D

echo "=== Strong Scaling Test ==="
echo "Hardware: Apple M4 Pro (14 cores, 48GB RAM)"
echo ""

for np in 1 2 4 6 8 10 12 14; do
    echo ">>> Testing $np processes <<<"
    rm -rf output/*
    
    start=$(date +%s)
    mpirun -np $np ./bin/eaf3d_mpi input/config_test.dat > /dev/null 2>&1
    end=$(date +%s)
    
    elapsed=$((end - start))
    speedup=$(echo "scale=2; $elapsed / $np" | bc)
    
    echo "  Time: ${elapsed}s"
    echo "  Speedup: ${speedup}x"
    echo ""
done
EOF

chmod +x benchmark.sh
./benchmark.sh
```

### Verificar Balanceo de Carga
```bash
# Ejecutar con verbose MPI
mpirun -np 8 --report-bindings ./bin/eaf3d_mpi input/config_test.dat

# Monitorear uso de CPU mientras corre
# En otra terminal:
top -pid $(pgrep -n eaf3d_mpi) -stats pid,cpu,mem
```

---

## ⚡ OPTIMIZACIONES ESPECÍFICAS M4 Pro

### 1. Aprovechar Unified Memory
```bash
# Los chips Apple tienen memoria unificada
# MPI puede beneficiarse de esto
export OMPI_MCA_btl=self,vader  # Usar shared memory
```

### 2. Binding de Procesos
```bash
# Mapear procesos a cores específicamente
mpirun -np 8 \
    --bind-to core \
    --map-by socket:PE=1 \
    ./bin/eaf3d_mpi input/config_test.dat
```

### 3. Limitar a Performance Cores (opcional)
```bash
# Si quieres usar SOLO los 10 performance cores
# (los 4 efficiency cores quedan libres)
mpirun -np 8 --bind-to core ./bin/eaf3d_mpi input/config_test.dat
```

---

## 📈 Performance Esperado

### En tu M4 Pro (estimado):

| Procesos | Speedup | Eficiencia | Uso |
|----------|---------|------------|-----|
| 1 | 1.0x | 100% | Baseline |
| 2 | 1.9x | 95% | - |
| 4 | 3.7x | 92% | ✅ |
| 6 | 5.3x | 88% | ✅ |
| 8 | 6.8x | 85% | ✅ **ÓPTIMO** |
| 10 | 8.0x | 80% | ✅ |
| 12 | 9.2x | 77% | ✅ |
| 14 | 10.0x | 71% | ⚠️ (incluye efficiency) |

**Notas:**
- Eficiencia baja con 14 porque los 4 efficiency cores son más lentos
- **8 procesos** ofrece el mejor balance speedup/eficiencia
- Con 10+ procesos, estás limitado más por comunicación que por compute

---

## 🔍 DIAGNÓSTICO

### Verificar OpenMPI reconoce tu hardware
```bash
ompi_info | grep "MPI:"
mpirun --version

# Ver cuántos slots detecta MPI
mpirun --display-map hostname
```

### Verificar HDF5 funciona en paralelo
```bash
# Test simple de I/O paralelo
mpirun -np 8 bash -c 'echo "Process $OMPI_COMM_WORLD_RANK ready"'
```

### Si hay problemas de performance
```bash
# Ver warnings de MPI
mpirun -np 8 --display-allocation ./bin/eaf3d_mpi input/config_test.dat

# Profiling básico
time mpirun -np 8 ./bin/eaf3d_mpi input/config_test.dat
```

---

## 📊 RECOMENDACIÓN FINAL

### Para tu Mac M4 Pro con 14 cores:

**🎯 CONFIGURACIÓN ÓPTIMA:**
```bash
# Testing/Desarrollo:
mpirun -np 8 ./bin/eaf3d_mpi input/config_test.dat

# Producción:
mpirun -np 8 --bind-to core ./bin/eaf3d_mpi input/config_production.dat

# Máximo (todos los cores):
mpirun -np 14 ./bin/eaf3d_mpi input/config_production.dat
```

### ¿Por qué 8 y no 14?
1. ✅ **Mejor forma 3D**: 2×2×2 (cubo) vs 2×7×1 (plano alargado)
2. ✅ **Menos comunicación**: Cubos minimizan surface-to-volume ratio
3. ✅ **Deja cores libres**: Sistema operativo y otros procesos
4. ✅ **Mejor eficiencia**: ~85% vs ~71% con 14
5. ✅ **Más estable**: No compite con procesos del sistema

### Cuándo usar más de 8:
- ✅ Mallas muy grandes (nr > 100, nth > 120, nz > 150)
- ✅ Simulaciones muy largas (días de cómputo)
- ✅ Cuando necesitas resultados MÁS rápido a costa de eficiencia

---

## 🚦 GUÍA RÁPIDA

```bash
# 1. PRIMER TEST (5 min)
mpirun -np 8 ./bin/eaf3d_mpi input/config_test.dat

# 2. SI FUNCIONA → Test con más procesos
mpirun -np 14 ./bin/eaf3d_mpi input/config_test.dat

# 3. SI NO FUNCIONA → Test con menos
mpirun -np 4 ./bin/eaf3d_mpi input/config_test.dat

# 4. COMPARAR TIEMPOS
time mpirun -np 1 ./bin/eaf3d_mpi input/config_small.dat   # Serial
time mpirun -np 8 ./bin/eaf3d_mpi input/config_small.dat   # Paralelo
```

---

**TL;DR:** 
- **Máximo absoluto**: 14 procesos
- **Óptimo recomendado**: **8 procesos** ✅
- **Para production**: 8-10 procesos
- **Tu hardware es EXCELENTE para MPI** 🚀

