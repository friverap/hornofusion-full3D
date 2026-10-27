## Revisión WS-K8: auditor-eaf3d (código del diff staged)

**Veredicto: APRUEBA.** No encontré ningún defecto ALTO ni MEDIO en el código. El instrumento es solo de diagnóstico y no altera la numérica: lo comprobé con los datos. Quedan cinco hallazgos BAJO no bloqueantes: uno latente en un checker y el resto de redacción.

**Contexto.** La tarea dice «ronda 1», pero el reporte se presenta como ronda 2 y `research/ws/WS-K8/reviews/r1-auditor-eaf3d.md` ya está staged. Si esta revisión se guarda en esa ruta, sobrescribe la anterior.

### Hallazgos

**BAJO**

- **B1 (latente) – `tests/integration/check_audit.py` (`mass_gas_flux_closure`) y `src/mod_audit.f90:806-807, 857, 899`.**
  - **Defecto:** `m_gas_out` solo se acumula si `gas_energy_on` (`solve_energy .and. solve_flow .and. solve_multiphase`). `flux_multi` y `flux_free` se acumulan sin esa condición.
  - **Escenario:** `solve_energy=false` con flujo y multifase activos y venteo por las salidas. Resultado: `m_gas_out=0` y FAIL espurio del check. Hoy ningún banco tiene esa combinación.
  - **Arreglo:** acumular el `fl` de la clase 0 en `audit_gas_cells`, o condicionar el check.
- **B2 – descripción de `mass_gas_flux_closure`** (reporte §4, rules, comentario del check, glosario).
  - **Defecto:** se presenta como «NO tautológico, otro camino de código». Pero `m_gas_out` (`mod_audit.f90:873-878, 899`) y `flux_*` (`1085-1087`) suman los mismos `ws_Fg·ws_Fg_lk`.
  - **Consecuencia:** es un cierre telescópico. Solo detecta flujo en caras de frontera física o hacia `cell_type 0`, o una máscara de salidas que no coincide. No es evidencia independiente del reparto.
  - **Arreglo:** describirlo así.
- **B3 (PLAUSIBLE en magnitud) – `src/mod_pressure_3d.f90:1055-1061`.**
  - **Defecto:** la conversión volumen→masa del plan usa `gadv`, que hereda las guardas físicas: solo caudal entrante de ensamblaje, `alpha_g >= 1e-6` en las dos celdas y solo con `gas_compressibility`.
  - **Escenario:** en caras de gas enlazadas con una celda evanescente, `ws_Fg` lleva la densidad del dador sin término de conversión, y ese término cae en rem2.
  - **Por qué importa:** no figura en Incertidumbre y es candidato a explicar parte del desfase constante del neto.
  - **Arreglo:** añadirlo a Incertidumbre. Al partir los corchetes, calcular la conversión desde el flujo corregido y `ws_Fg`, sin guardas.
- **B4 (errata del reporte).** «Σ flux_multi = 95.3 % de −Σ m_gas_out» está invertido.
  - Medido: Σflux_multi/(−Σm_gas_out) = 1.050 (`k8_cg1000`), 1.072 (`k8_mo20`) y 0.864 (`k8_base`).
- **B5 (rules) – `.claude/rules/transporte-energia.md`.**
  - El cociente «+1.39 a −143 en 999 pasos» es Σe_multi/Σm_gas_out, no el flujo que entra al multifase: `k7v5_mo20_1k` no tiene la columna `m_gas_flux_multi`.
  - «Vive en un sesgo sistemático de la identidad de fila en masa» omite el paréntesis de C-179. Así parece atribuir el neto solo a la fila del Poisson, en contra de «origen no medido».

### Lo verificado como correcto (no hace falta re-auditarlo)

- **Identidad del código probado:**
  - El sha256 del diff staged de `src/` coincide con el de `opt_identidad.txt`.
  - Los `audit.csv` de `k8_cg1000` y `k8_mo20` son idénticos con `cmp` a los de `*_r2`.
  - `k8_mo20` frente a `k7v5_mo20` es idéntico en las 117 columnas comunes, salvo las `m_gas_err_*` (≤1.1e-19 kg).
- **`mod_pressure_3d`:**
  - Los arrays nuevos se ponen a cero de forma incondicional en cada Poisson y se anulan en las filas triviales, selladas y con Su==0.
  - No hay `return` entre el ensamblaje y el CG.
  - En las salidas pp es exactamente 0: fila identidad, x0=0 y enlaces plegados.
  - `store_art` se calcula antes del plegado de las BC, que es lo correcto.
  - La división real/artificial de D2.4 es correcta.
- **`mod_workspace`:**
  - `allocate(mold=)` con todo a cero, halos incluidos (Bug 22 OK).
  - El estado vale solo dentro del paso, con id; no hay nada que deba ir al snapshot.
- **`mod_audit`:**
  - La cabecera y el `write` coinciden en orden en las 20 columnas.
  - `acc` se reduce con allreduce_sum y `cc_skip` lo cuenta solo el rank 0.
  - Los filtros `liq_ok` y `cc_ok` son coherentes entre numerador y denominador; en las cuatro corridas los skips valen 0.
- **Cifras recalculadas desde los `audit.csv`:**
  - Tabla de resultados: cocientes, netos, desfase −2.169e-5 ± 0.13e-5 (59/59), corr 0.93, C-110 0.3156 y err_art.
  - Estadísticas por paso y por tramos de 200 pasos: los cinco cocientes de `k7v5_mo20_1k` coinciden.
  - Recuentos de [CG] AVISO.
  - Salidas de `check_audit` sobre `k8_*`.
- **Tests y supuestos:**
  - Los logs de unit, quick y full terminan en OK.
  - `alpha_g_comp_min` vale 0 por defecto.
  - La salida silenciosa del CG con |pq|<SMALL confirma el hueco que el reporte ya declara.

### Orden sugerido de corrección (uno por uno)

1. B4: errata del 95.3 %.
2. B5: dos frases de las rules.
3. B2: descripción del cierre telescópico.
4. B3: añadir a Incertidumbre y al pre-registro del split de corchetes.
5. B1: guarda del check (código de test; puede esperar al próximo WS).
