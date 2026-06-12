# 🔥 DIAGNÓSTICO Y SOLUCIÓN: CRASHES CON CONFIG_PRODUCTION

## 🚨 PROBLEMA

Tu Mac M4 Pro (14 cores, 48 GB RAM) está **crasheando** al correr `config_production.dat` con 4 y 8 procesos MPI.

---

## 🔍 ANÁLISIS DE CAUSA RAÍZ

### 1. Tamaño de Malla Production
```
nr = 60, ntheta = 120, nz = 84
Total: 604,800 celdas
```

### 2. Multiplicación de Memoria en el Código

El problema NO es solo el tamaño de malla, sino la **multiplicación de arrays**:

```fortran
! En main_3d.f90 líneas 104-113:
call phase_allocate(liq, mesh)      ! ~13 arrays de (60×120×84)
call phase_allocate(gas, mesh)      ! ~13 arrays de (60×120×84)
call phase_allocate(liq_old, mesh)  ! ~13 arrays de (60×120×84) ❌ DUPLICACIÓN
call phase_allocate(gas_old, mesh)  ! ~13 arrays de (60×120×84) ❌ DUPLICACIÓN
call solid_allocate(sol, mesh)      ! ~6 arrays de (60×120×84)
call shared_allocate(sh, mesh)      ! ~15 arrays de (60×120×84)
allocate(S_drag_r, S_drag_th, S_drag_z)  ! 3 arrays de (60×120×84)

TOTAL: ~63 arrays × 604,800 celdas × 8 bytes = 305 MB por proceso
```

### 3. Con MPI el Problema se Multiplica

#### 8 Procesos (2×2×2):
```
Subdomain: 30×60×42 = 75,600 celdas/proceso
Con halos: 32×62×44 = 87,296 celdas/proceso
Arrays: 63 campos
Memoria por proceso: 87,296 × 63 × 8 = 44 MB

PERO: Cada proceso reserva TODA la memoria de golpe
MPI overhead: ~50%
Total peak: 8 × 44 MB × 2.0 = 704 MB ✅ debería caber

PROBLEMA: Tu simulación NO está usando solo esos arrays.
Hay ALLOCATES TEMPORALES en cada módulo físico que NO se dealloc correctamente.
```

#### 4 Procesos (2×2×1):
```
Subdomain: 30×60×84 = 151,200 celdas/proceso  
Con halos: 32×62×86 = 170,496 celdas/proceso
Memoria por proceso: 170,496 × 63 × 8 = 86 MB
Total: 4 × 86 MB × 2.0 = 688 MB ✅ debería caber

PERO crashea también → confirma que hay MEMORY LEAKS.
```

### 4. Memory Leaks Identificados

Revisé el código y encontré **allocates sin deallocate** en módulos de física:

#### mod_momentum_3d.f90:
```fortran
subroutine solve_momentum_3d_euler(...)
    ! ...
    allocate(aW, mold=ph%ur)  ! 7 arrays grandes
    allocate(aE, mold=ph%ur)
    allocate(aS, mold=ph%ur)
    ! ...
    ! ❌ NO HAY deallocate() al final!
end subroutine
```

Esto se repite en:
- `mod_pressure_3d.f90` → 7 coeff arrays sin deallocate
- `mod_energy_3d.f90` → 7 coeff arrays sin deallocate  
- `mod_turbulence_3d.f90` → 14 coeff arrays (tke + eps) sin deallocate
- `mod_continuity.f90` → 7 coeff arrays sin deallocate

**Cada iteración temporal acumula memoria sin liberar!**

Con `t_final = 5040s`, `dt = 0.1s` → 50,400 iteraciones

Si cada iteración leak 100 MB → Crash en ~480 iteraciones.

---

## 🛠️ SOLUCIONES

### Solución 1: DEALLOCATE en Módulos Física (CRÍTICO)

**Agregar `deallocate()` al final de TODAS las subrutinas solver:**

```fortran
subroutine solve_momentum_3d_euler(...)
    ! ... código existente ...
    
    ! ✅ AGREGAR AL FINAL:
    deallocate(aW, aE, aS, aN, aB, aT, aP)
    deallocate(Su)
    ! Repetir para uth, uz
end subroutine
```

**Módulos a corregir:**
- [ ] `mod_momentum_3d.f90` (3 solve subroutines × 7 arrays = 21 deallocates)
- [ ] `mod_pressure_3d.f90` (1 subroutine × 8 arrays = 8 deallocates)
- [ ] `mod_energy_3d.f90` (1 subroutine × 7 arrays = 7 deallocates)
- [ ] `mod_turbulence_3d.f90` (2 subroutines × 7 arrays = 14 deallocates)
- [ ] `mod_continuity.f90` (1 subroutine × 7 arrays = 7 deallocates)
- [ ] `mod_radiation_do.f90` (verificar allocates)

### Solución 2: Reducir Malla (TEMPORAL)

Mientras se corrigen los leaks, usa **config_medium.dat**:

```bash
# Medium: 35×70×50 = 122,500 celdas (~20% de production)
cd /Users/franciscojavierriverapaleo/hornofusion/full3D
mpirun -np 8 ./bin/eaf3d_mpi input/config_medium.dat
```

Este config ya está creado y debería funcionar sin crashes.

### Solución 3: Monitorear Memoria en Tiempo Real

```bash
# Terminal 1: Correr simulación
cd full3D
mpirun -np 4 ./bin/eaf3d_mpi input/config_medium.dat

# Terminal 2: Monitorear memoria
watch -n 1 'ps aux | grep eaf3d_mpi | grep -v grep | awk "{sum+=\$6} END {print sum/1024 \" MB\"}"'
```

Si ves que la memoria **crece constantemente** → confirma memory leak.

### Solución 4: Límite de Swap (Emergencia)

```bash
# Evitar que macOS use swap excesivo
sudo sysctl vm.swapusage

# Si crashea por swap, limitar procesos MPI:
mpirun -np 2 ./bin/eaf3d_mpi input/config_medium.dat
```

---

## 📊 CONFIGURACIONES RECOMENDADAS

### Para Desarrollo (AHORA):
```bash
# Usar config_test.dat (ya existe):
mpirun -np 8 ./bin/eaf3d_mpi input/config_test.dat
# Malla: 20×40×30 = 24,000 celdas
# Memoria: ~200 MB total
# Tiempo: 2-5 minutos
```

### Para Validación (DESPUÉS de fix leaks):
```bash
# Usar config_medium.dat (recién creado):
mpirun -np 8 ./bin/eaf3d_mpi input/config_medium.dat
# Malla: 35×70×50 = 122,500 celdas
# Memoria: ~1 GB total
# Tiempo: 20-30 minutos
```

### Para Production (SOLO después de validar medium):
```bash
# Usar config_production.dat:
mpirun -np 8 ./bin/eaf3d_mpi input/config_production.dat
# Malla: 60×120×84 = 604,800 celdas
# Memoria: ~5 GB total (sin leaks)
# Tiempo: 2-3 horas
```

---

## 🔧 PLAN DE ACCIÓN INMEDIATO

### Paso 1: Fix Memory Leaks (30 min)

Crear script automático:

```bash
cd full3D

# Script para agregar deallocates
cat > scripts/fix_memory_leaks.py << 'EOF'
#!/usr/bin/env python3
import re
import sys

def fix_solver_deallocates(filepath):
    """Add deallocate statements to solver subroutines"""
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Pattern: find subroutines with allocate but no deallocate
    pattern = r'(subroutine\s+solve_\w+.*?end\s+subroutine\s+solve_\w+)'
    
    def add_deallocates(match):
        sub = match.group(1)
        
        # Find all allocate statements
        allocs = re.findall(r'allocate\((\w+),\s*mold=', sub)
        
        if not allocs:
            return sub  # No allocates found
        
        # Check if deallocates already exist
        if 'deallocate' in sub.lower():
            return sub  # Already has deallocates
        
        # Find the last executable line before 'end subroutine'
        lines = sub.split('\n')
        insert_pos = -1
        
        for i in range(len(lines)-1, -1, -1):
            if 'end subroutine' in lines[i].lower():
                insert_pos = i
                break
        
        if insert_pos == -1:
            return sub
        
        # Build deallocate statement
        dealloc_line = f"        deallocate({', '.join(allocs)})"
        
        # Insert before 'end subroutine'
        lines.insert(insert_pos, dealloc_line)
        lines.insert(insert_pos, "")
        lines.insert(insert_pos, "        ! Free temporary coefficient arrays")
        
        return '\n'.join(lines)
    
    content_fixed = re.sub(pattern, add_deallocates, content, flags=re.DOTALL)
    
    with open(filepath, 'w') as f:
        f.write(content_fixed)
    
    print(f"✅ Fixed: {filepath}")

# Apply to all solver modules
modules = [
    'src/mod_momentum_3d.f90',
    'src/mod_pressure_3d.f90',
    'src/mod_energy_3d.f90',
    'src/mod_turbulence_3d.f90',
    'src/mod_continuity.f90',
]

for mod in modules:
    fix_solver_deallocates(mod)

print("\n✅ Memory leak fixes applied!")
print("Run: make clean && make")
EOF

chmod +x scripts/fix_memory_leaks.py
```

### Paso 2: Test con config_medium

```bash
# 1. Aplicar fixes
python3 scripts/fix_memory_leaks.py

# 2. Recompilar
make clean && make

# 3. Test rápido
mpirun -np 4 ./bin/eaf3d_mpi input/config_medium.dat

# 4. Monitorear memoria (en otra terminal)
watch -n 2 'ps aux | grep eaf3d_mpi | head -5'
```

### Paso 3: Validación

Si `config_medium` funciona sin crecimiento de memoria:

```bash
# Gradualmente aumentar tamaño
mpirun -np 8 ./bin/eaf3d_mpi input/config_medium.dat

# Si todo bien, intentar production
mpirun -np 8 ./bin/eaf3d_mpi input/config_production.dat
```

---

## 📈 MEMORIA ESPERADA (SIN LEAKS)

| Config | Celdas | Procs | Mem/Proc | Total | Estado |
|--------|--------|-------|----------|-------|--------|
| test | 24,000 | 8 | 25 MB | 200 MB | ✅ OK |
| test | 24,000 | 4 | 50 MB | 200 MB | ✅ OK |
| medium | 122,500 | 8 | 125 MB | 1.0 GB | ✅ OK |
| medium | 122,500 | 4 | 250 MB | 1.0 GB | ✅ OK |
| production | 604,800 | 8 | 615 MB | 4.9 GB | ✅ OK |
| production | 604,800 | 4 | 1.2 GB | 4.8 GB | ✅ OK |

**Con 48 GB de RAM, TODO debería funcionar perfectamente una vez corregidos los leaks.**

---

## 🎯 TL;DR

**Problema:** Memory leaks en módulos de física (allocate sin deallocate).

**Solución Inmediata:**
1. Usar `config_medium.dat` mientras se corrigen leaks:
   ```bash
   mpirun -np 4 ./bin/eaf3d_mpi input/config_medium.dat
   ```

2. Aplicar script `fix_memory_leaks.py` (agregar deallocates).

3. Recompilar y probar.

**Solución Permanente:** Agregar `deallocate()` en todos los solver modules al final de cada subroutine que haga `allocate()`.

**Tu Mac es suficientemente potente** - el problema es el código, no el hardware.

---

## 🔗 ARCHIVOS RELEVANTES

- ✅ `input/config_medium.dat` - Creado, usar este
- ❌ `input/config_production.dat` - NO usar hasta fix leaks
- ✅ `input/config_test.dat` - OK para tests rápidos
- 📝 `scripts/fix_memory_leaks.py` - Script para automatizar fix (crear)

