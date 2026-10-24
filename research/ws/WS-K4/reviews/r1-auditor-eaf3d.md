# WS-K4, ronda 1: auditor-eaf3d (revisión de código del diff staged)

**Veredicto: APRUEBA.** No encontré hallazgos ALTO ni MEDIO. Quedan dos observaciones BAJO que no bloquean.

## 1. Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO
- **K4-R1-B1 (PLAUSIBLE): falta pasar los reinicios con otro número de ranks.**
  - Las columnas nuevas no han pasado por test-full: `cold_10step` 8->4 y 8->12, con `compare_audit --decomp` y `artol 1e-10` (`tests/run_tests.sh:154,674,695`).
  - Riesgo: `E_relax_gas` es un residuo pequeño (~1e2-1e3 J por paso) que sale de términos de ~1e6 J. Si el redondeo por descomposición supera 1e-10 de la escala de la columna, el resultado es FAIL.
  - Estimación: con `tests/out/cold_10step_n8` frente a `n12`, `E_abs_gas_hook` difiere ~6e-9 J, lo que da ~1e-11 relativo. Probablemente pasa, pero no lo he medido.
  - El gate por commit es test-quick (CLAUDE.md:61), así que no bloquea. Correr `make test-full` en la etapa.
- **K4-R1-B2: el INFO `energy_relax` no avisa con `mixture_model`.**
  - Dónde: `tests/integration/check_audit.py:270-274`.
  - Con `mixture_model` el INFO imprime el reparto líquido/gas, que el propio diff declara sin sentido en ese modo, y no lo avisa.
  - No afecta a ningún veredicto.
  - Arreglo sugerido: con `--config` y `mixture_model`, imprimir solo la suma o añadir la advertencia.

## 2. Verificado como correcto (no re-auditar)

**El residuo es el del campo que queda guardado.**
- `energy_audit_hook` (`src/mod_energy_3d.f90:479-566`) evalúa todos los términos sobre `Tk = αT·T* + (1−αT)·Tpre`. Es la misma fórmula que `relax_field` (`src/mod_parallel_utils.f90:24-36`).
- `Tpre` coincide con `p_lT`/`p_gT`: se toman en `src/mod_multiphase.f90:87-88` y no hay escrituras de `liq%T`/`gas%T` entre la línea 87 y los solves de las líneas 559/567. `phase_exchange_halos` solo toca halos.
- La relajación se aplica justo después de cada solve (líneas 562 y 570).
- Los halos de `ph%T` se intercambian antes del hook (línea 388). `Tpre` copia el arreglo completo con halos válidos. Las vecinas de otro rank cumplen la misma relación: no hay problema de frontera de bloque ni de `mold` sin inicializar, porque `Tk` y `Tpre` se asignan como arreglos completos.

**`eq_residual`.**
- Signos: `eeq(q,5)` ya llega como `-s_conv` y la pared resta, igual que en el hook (línea 565).
- `pure` que solo lee una variable de módulo: es Fortran válido.

**MPI.**
- `eeq` son sumas locales por rank. `acc(N_AUD)` se reduce con `mpi_allreduce_sum` en `audit_write_step` (líneas 506-514).
- Es el mismo patrón que la columna existente `E_abs_gas_hook`, sin doble conteo.

**Acumulado por PASO, no por iteración externa.**
- El hook sobrescribe `eeq` en cada iteración externa; queda la última, que es el campo en pie.
- `audit_accumulate` corre una vez por paso (`src/main_3d.f90:784-785`) y luego anula `eeq`.
- Con `audit_freq>1` la fila suma todos los pasos del intervalo.

**Reinicio.**
- No hay estado persistente nuevo: `acc` se anula tras cada escritura y en `audit_init`, y `eeq` se anula cada paso.
- `tests/out/restart/cold_10step_n8_to_n8_s5` da las columnas nuevas idénticas a la continua (filas 6-10).

**Encabezado y escritura.**
- 3 nombres añadidos al final del encabezado y 3 valores en el mismo orden en el `write`; `N_AUD` pasa a 61.
- `audit.csv` de test-quick tiene 87 columnas.
- No encontré lectores con índice fijo de columna: `energy_gap.py` y `check_audit` leen por nombre.

**`check_audit`.**
- Las columnas nuevas no entran en `EXT_POS`/`EXT_NEG`/`INTERNAL` ni en la identidad por paso; solo aparecen en el INFO.
- `gap`, `steps` y `last` están definidos en ese ámbito, y el bloque está protegido con `if "E_relax_liq" in last`.

**Test unitario.**
- `tests/unit/test_relax_residual.f90` entra solo por `wildcard` (Makefile:170).
- El caso 3 da 70+20+5+10−13+18 = 110, es decir, residuo −10. El caso 1 ya detecta una inversión de signo en pared o convección.

**Glosario.** El tipo «D» existe en el generador y el orden de `docs/AUDIT_COLUMNS.md` coincide con el encabezado.

**Cifras del reporte, recalculadas con python3 sobre los CSV existentes:**

| Cifra | Valor recalculado |
|---|---|
| sum E_relax_liq | −10883.3 J |
| hueco del líquido | −11716.6 J |
| diferencia | 7.11 % |
| E_relax_gas frente al hueco del gas | +1079.2 J frente a +1046.5 J |
| remanente del líquido | −833.3 J; mediana −3.738 J/paso; std 0.232 J |
| Pearson | 0.99999918 |
| std del hueco base0 / aT1 / aT085 | 180.6 / 0.250 / 104.5 J |
| gap − residuos | −866.1 J |

- Las 84 columnas comunes de `bench_relaxcol` y `bench_base0` son idénticas bit a bit en los 221 renglones, no solo `p_max`.

**Orden de la pre-inscripción.**
- C-101 (01:19:40) es anterior al binario `eaf3d_relaxcol_opt` (01:21:46) y a la corrida (01:21:51 a 01:22:59). C-102 es posterior (01:23:22).

**Límite.** No puedo comprobar que el binario del banco salga byte a byte del árbol staged. Entre rondas solo cambió un comentario, y test-unit y test-quick corrieron sobre el árbol final (logs en `research/ws/WS-K4/logs/`).

## 3. Orden sugerido

1. K4-R1-B1: `make test-full` en el gate de etapa, antes del próximo B1 con el binario nuevo.
2. K4-R1-B2: advertencia de `mixture_model` en el INFO (cosmético; puede ir junto con el siguiente cambio de `check_audit`).
