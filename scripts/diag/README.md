# Detector de lecturas de memoria sin inicializar (Bug 22, oct-2026)

`snanfill.c` interpone `malloc`/`realloc` (macOS, `__interpose`) y rellena cada
bloque nuevo con NaN SEÑALIZANTE (`0x7FF4000000000001` por palabra de 8 bytes).
Con una compilación `-O0 -ffpe-trap=invalid`, la PRIMERA aritmética sobre un
real(8) sin inicializar aborta con traza; `MallocPreScribble=1` (patrón 0xAA,
≈ −4e-103) solo delata que el resultado depende del heap, no dónde.

```bash
clang -O2 -dynamiclib -o libsnanfill.dylib scripts/diag/snanfill.c
# copia del árbol con FFLAGS_DBG += -finit-real=snan -ffpe-trap=invalid, make debug
DYLD_INSERT_LIBRARIES=$PWD/libsnanfill.dylib ./bin/eaf3d_mpi config.dat   # en serie
# traza simbolizada:
lldb --batch -o "env DYLD_INSERT_LIBRARIES=$PWD/libsnanfill.dylib" -o "run config.dat" \
     -k "thread backtrace -c 25" -- ./bin/eaf3d_mpi
```

Lecturas INOFENSIVAS de halos (elementales de array completo cuyo resultado
no se usa) también disparan: hay que mirar la traza y, si es inofensiva,
inicializar el array igualmente — la regla es que ningún halo lleve basura.
Comparación determinista de dos corridas idénticas:
`tests/integration/compare_decomposition.py A B --rtol 1e-12`.

# Diagnóstico de ventanas de B1 (auditoría 20, B20-5)

- `regime2.py DIR1 DIR2 ... [--w t0,t1,...]`: régimen acotado por ventana
  desde `DIR/audit.csv` (p>100 kPa, gas>200 m/s, centinela de p o gas,
  `u_liq_max`≥20 — esta columna incluye líquido DISPERSO —, p_max, gas_max).
- `probe_p.py run.log [--cada N] [--audit audit.csv]`: tabla de las líneas
  `[PROBE-P]` (fila del Poisson de la celda sonda por iteración externa); el
  tiempo de cada paso sale del `audit.csv` vecino (`step`,`time`).
