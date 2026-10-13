# Auditoría estricta 2 — 13-oct-2026 (golden v71, commit 86080c3)

Segunda auditoría completa, antes de re-juzgar B1 desde t = 0. Siete revisiones
paralelas de solo lectura (acople P-V; α y lazo multifase; energía, fusión y
escoria; arco, radiación, química y k-ε; infraestructura, MPI, E/S y reinicio;
contabilidad y arnés de pruebas; modelo de mezcla y revisión transversal de
gravedad, EOS, fronteras de bloque, `mold=`, igualdades reales y divisiones).
Cada hallazgo C/A y los M de mayor impacto se **verificaron contra el código**
(columna V: ✔ verificado aquí; R = reportado con evidencia de código, se
re-verifica al corregir). Severidad: C crítico, A alto, M medio, B bajo.

Lo que sale limpio (verificado por las revisiones): fronteras de bloque en
todo `src/` tras 4a79146 (tabla completa, ninguna incorrecta); `mold=` (~80
sitios, todos inicializados); EOS única `gas_eos` en todo el código (salvo N-B9);
PHDF5 colectivo; halos MPI y descomposición; química (estequiometría, signos,
masas molares); presupuesto del arco; simetría de la matriz de presión;
exportación conservativa `ws_Fc`/`ws_Fg`; consistencia predictor/Rhie–Chow de la
fuerza balanceada; volúmenes de `eafutil` con eje real.

## Críticos

| id | V | Hallazgo | Dónde |
|---|---|---|---|
| N-C1 | ✔ | **La fuerza balanceada (d2d9f22) retiene el líquido en el lecho.** `liq_continuous` declara continuo al líquido del lecho desde α_l ≥ 0.01; con `liq_balanced_force` líquido y gas ven el mismo gradiente reducido y ninguna lleva peso propio, así que la flotación relativa líquido–gas desaparece: en una columna de lecho uniforme `u_l = u_g = 0` es punto fijo (debería percolar ~0.1 m/s). Salto en el umbral α_l = 0.01 (debajo, el disperso percola). Lo mismo para burbujas en el baño. Ningún banco lo cubre (`bed_flood` corre con Plan D, que apaga la forma nueva). Encontrado por dos revisiones independientes | `mod_momentum_3d` (`cell_w`, `lbf_m`), `mod_pressure_3d` (`cell_wp`), `mod_constants::liq_continuous` |
| N-C2 | ✔ | **La congelación destruye energía.** Con el transitorio αⁿ el balance exacto es Mⁿ(e′ − eⁿ) = dm(e′ − e_entry); el código usa eⁿ (T_old) en el latente → pierde dm·(e′ − eⁿ) por paso, y el líquido no alcanza e_lb en el paso (la palanca no se cumple en un paso). El hook reproduce el mismo término. **`bath_freeze` pierde 1.83e9 J sin fuentes (err 1.000)** | `mod_energy_3d.f90:292-306, 509-517` |
| N-C3 | ✔ | **El gate de energía está ciego.** (a) `check_audit` no se corre en 13 de las 26 corridas de la matriz (bath_freeze fallaría hoy con err 1.0; ECS, escoria, química con flujo nunca se gatean); (b) la escala `max(|dE|, |E_in|, Σ|E_melt|)` deja pasar errores de 6e8–4e9 J en casos con fusión cuyo arco total es 4e6–2e8 J | `tests/run_tests.sh`, `check_audit.py:84-86` |

### Hallazgos nuevos durante la resolución

| id | V | Hallazgo | Dónde |
|---|---|---|---|
| N-C4 | ✔ | **Sin transporte de α de dos fluidos (ramas de una sola fase y solo energía) el ṁ de fusión/congelación no se aplicaba al líquido**: el sólido ganaba la masa congelada sin que el líquido la perdiera (bath_freeze sin flujo: +18 t de acero y +1.4e10 J por paso). Usan `solve_flow = false` chem_test, slag_chem_test, ecs_test, noflow_energy y dos configs de input | `main_3d.f90`, `mod_solid_phase.f90` |
| N-A7 | ✔ | RESUELTO: no era fuga. Desglose por fases con columnas nuevas (`E_conv_liq`, `E_conv_gas`, `E_abs_gas_hook`): sólido y líquido cierran a ±400 J/paso; la identidad sumaba el «defecto» convectivo del LÍQUIDO, que con el transitorio αⁿ y los flujos exactos del transporte de α es transporte de masa ya contado en el inventario. Ahora solo el del gas. Más: el libro del gas usa la α_g con la que absorbió el calor (antes de la flotación de la escoria, 14 % de error en el encendido de slag_chem_flow), y bed_drain con max_outer 10 | `check_audit.py`, `mod_audit` |
| N-C5 | ✔ | **El residual de energía se normaliza con la temperatura ABSOLUTA** (Σ\|aP T\|): un desfase de 0.7 K sobre 1550 K pasa `tol_energy = 1e-3` y el lazo externo se corta con 2.8 % de las fuentes del paso sin aplicar (bath_freeze sin flujo: −7e7 J por paso, igual con max_outer = 60) | `mod_solver_3d.f90:388-401`, `mod_config_3d.f90:51` |

## Altos

| id | V | Hallazgo | Dónde |
|---|---|---|---|
| N-A1 | ✔ | **No existe intercambio de calor gas–líquido en dos fluidos** (solo gas–sólido y líquido–sólido; el de la mezcla no se usa). En `bath_test` el gas a 300 K sobre acero a 1850 K queda a 300 K. El gas sobre el baño y la columna del arco no pueden ceder calor al baño | `mod_interphase_ht.f90` |
| N-A2 | ✔ | **El arco que pega en el baño calienta al gas.** `S_arc` se reparte por fracción de volumen (`w_src`), no por absorción como la radiación (`w_rad`): en una celda de superficie con α_l 0.3–0.5, 50–70 % del haz del MC va al gas (que no puede cederlo: N-A1). Además, sin chatarra P_rad directo (0.25 P_arc ≈ 7 MW/electrodo) va a la columna de gas kg_tip±3 (incluso dentro del grafito) y P_elec tras el bore-in se reparte por volumen en toda la columna bajo la punta (~20 % al gas) | `mod_energy_3d.f90:236-245`; `mod_arc_cassie_mayr.f90:208-313, 356-372` |
| N-A3 | ✔ | **Lorentz: B_φ ∝ 1/r_loc junto al eje del electrodo.** `1 − cos θ` se calcula con ρ regularizado y no se anula en el eje: 0.29 T a 1 cm (físico 5e-4 T), fuerza 10³–10⁴ N/m³ en la celda más cercana al eje de cada electrodo. `test_lorentz` caso 2 es tautológico (misma fórmula) | `mod_lorentz_3d.f90:93-98` |
| N-A4 | ✔ | RESUELTO: n9 (1×3×3, corta z en la superficie del baño) y n12 (2×3×2, corta r a través del baño) para bath_test, bath_freeze y slag_chem_test; tolerancias ~100× lo medido (cold 1e-10, ecs 1e-12, baño 1e-8, congelación 1e-5, escoria 1e-4, reinicio n8→n4 1e-10; antes 1e-3) y escala por familia de campo. Destapó una regresión del propio N-C1 (corregida: ver CLAUDE.md, flotación del lecho solo del líquido y con W̄). **Cobertura de descomposición insuficiente.** Ninguna frontera de bloque en z o r cruza baño, escoria o sólido (n4/n8 parten z en k = 8; las fases viven en k ≤ 5; n12 solo en casos sin líquido). `compare_decomposition` usa 1e-3 relativo al máximo de cada campo (medido 1e-12–1e-5). Sin comparación: melt_forced, bed_flood, bath_fill, chem, slag_chem_flow, cold_bucket2, arc_noscrap, mezcla | `run_tests.sh`, `compare_decomposition.py` |
| N-A5 | ✔ | **Reinicio no bit a bit con transición disperso→continuo:** `ws_liq_cont_prev` se lee solo en celdas propias y sus halos quedan en `.true.` (no se intercambian); `reset_new_continuous` los lee. Y la cobertura de reinicio casi no ejerce estado de `/restart` (m_C, escoria, espuma, ECS, Tg_end, cesta 2; sin reinicio con r partido; `/restart` no se compara) | `mod_restart.f90:161-169, 245-269` |
| N-A6 | R | **Gates vacuos o laxos:** `outer_conv` con `tol_cont = tol_mom = 1` y sin cota inferior (una regresión de Bug 20 pasa); `check_bath` 1e-2 frente a 2e-11 medido; `check_chem` 5 % y ventana estequiométrica mal definida; simetría con energía, radiación, líquido y Lorentz apagados; quick sin caso de baño ni balance activo | `configs/outer_conv.dat`, `check_*.py` |

## Medios

| id | V | Hallazgo | Dónde |
|---|---|---|---|
| N-M1 | ✔ | Eje real (M31) incompleto: u_r del primer anillo sigue con fila de relleno u_r = 0 (simetría de pared) y el corrector la salta; el Rhie–Chow de la cara 1–2 promedia con 0 y la energía/especies (flujo reconstruido) ven la mitad del caudal | `mod_boundary_3d.f90:123-136`, `mod_pressure_3d.f90:1526,1565`, `mod_mixture_3d.f90:1023` |
| N-M2 | ✔ | El corrector salta la componente normal en coraza, piso y techo (`skip_r/skip_z`) aunque el momento SÍ la resuelve (solo el eje tenía fila de relleno); celdas de salida por los agujeros de electrodo con u_z sin corregir | `mod_pressure_3d.f90:1526-1568` |
| N-M3 | R | M24 parcial: energía y especies del gas siguen con `face_mass_fluxes` (α simétrica, fantasma ½α_Pρu) mientras el momento usa `ws_Fg`; las especies con flujo no conservan C/O y ningún gate lo mide | `mod_energy_3d.f90:181-183`, `mod_species_transport.f90:102` |
| N-M4 | R | El transitorio (αρ)ⁿ del momento del gas supone continuidad de masa del gas exacta; no lo es (tope `COMP_SRC_CAP`, EOS sin recorte, Poisson de volumen de la suma) | `mod_momentum_3d.f90:230-238` |
| N-M5 | R | Energía del gas sin trabajo de presión (compresión isoterma en el Poisson): con p ~ P0 en el lecho inundado la justificación "orden p/P0" no vale (ΔT/T ≈ 0.2 adiabático de 1 a 2 atm) | `mod_energy_3d`, `mod_pressure_3d.f90:546` |
| N-M6 | R | `K_disp` en el lecho usa la velocidad de percolación (respecto del sólido) como deslizamiento respecto al gas: el gas recibe además el peso del líquido que el sólido ya carga | `mod_multiphase.f90:209-217` |
| N-M7 | R | El transporte de α mueve α_dador·u_f·A, no el Q del Poisson (α_f aritmética): masa conservada pero divergencia de volumen ≠ 0 en caras con α distinta | `mod_continuity.f90:930-976` |
| N-M8 | R | `update_properties` no intercambia halos: las especies del paso siguiente leen `gas%rho` rancio en fronteras de rank (sin escoria no hay intercambio intermedio) | `mod_properties_3d.f90`, `main_3d.f90:400` |
| N-M9 | R | Celdas cuña del eje: el CFL θ del transporte de α es ~38× el que usa el dt global (`dth_len = max(rdθ, dr)`); con cfl_max ≳ 3 o deriva de 50 m/s, fallback implícito no conservativo en todo el dominio | `mod_continuity.f90:172-235`, `mod_convergence_3d.f90:239` |
| N-M10 | R | `slag_energy` lee `liq%T` del halo antes de la interfase (sin intercambio tras `compute_interphase_heat`): dependencia de la descomposición en z | `mod_slag_3d.f90:488-494` |
| N-M11 | R | DO: tazón/piso "re-radiantes" devuelven B de la celda vecina, no la intensidad incidente (no adiabáticos fuera del equilibrio); el MC trata esas celdas como pérdida | `mod_radiation_do.f90:362-373` |
| N-M12 | R | k-ε en la superficie libre: S² con la superficie como pared, G_b con T rancia de la celda de gas, convección con el flujo fantasma (F2.24) | `mod_turbulence_3d.f90:79-201` |
| N-M13 | R | A17 incompleta en el corrector del gas (máscara de acople final ≠ `ws_pv_active` del predictor); el gas atrapado/fuera del acople no se comprime (contradice la doc de M25); posible alternancia F2.31 con la fuente (p^k − pⁿ) | `mod_pressure_3d.f90:363, 690` |
| N-M14 | R | La hidrostática inicial no es el punto fijo de W_f con dz no uniforme (producción usa stretch 1.5; toda la matriz usa 1.0); la init cuenta el líquido disperso y W_f no | `mod_fields_3d.f90:748-777` |
| N-M15 | R | La rama de flujo de una sola fase con energía pierde arco/química/radiación del gas (pasa `gas%alpha` como `alpha_other`); latente | `main_3d.f90:495-498` |
| N-M17 | ✔ | RESUELTO con N-A7 (misma identidad). Modelo de mezcla (opt-in): la energía no cerraba con la identidad estricta (`bath_fill_mix`: gap ≈ 0.5–0.7 del defecto convectivo del hook por paso, 1.6e7 J en 50 pasos); xfail `audit_fillmix` con causa | `mod_mixture_3d` (energía con Q_l y Q − Q_l) |
| N-M16 | R | Documentación desactualizada: ARCHITECTURE §6 (orden del paso, Cassie–Mayr), CONFIGURATION (44 claves sin documentar, incluida `liq_balanced_force`; §9-10 al revés), OUTPUT (/restart, /fields) | docs |

## Bajos

N-B1 recorte de α sin columna de energía (bath_fill_mix: 268 kg y −2.6e8 J en el
paso 1) · N-B2 volumen de gas creado por ECS y flotación de escoria sin
`AUD_GAS_VOLFIX` · N-B3 pérdidas silenciosas en `distribute_arc_heat` con suma de
pesos ≤ SMALL; `AUD_ARC_DISCARD` muerta · N-B4 Diagonal de Newton de M25 sin
ρⁿ/ρ y sumada con el tope activo · N-B5 demanda de compresibilidad perdida en
filas selladas (contradice el acarreo M26) · N-B6 corrector con operador central
≠ media de caras del predictor en malla estirada · N-B7 W_f con líquido disperso
divide el peso del gas por α_l + α_g · N-B8 ρ_l sin Boussinesq en
sedimentación/percolación/K_disp · N-B9 P_O₂ con P0 + p también en la mezcla
(low-Mach) · N-B10 `T_ref_boussinesq` no sigue a `T_liquidus` del config ·
N-B11 Makefile: dependencias faltantes (`mod_parallel_utils` en convergence y
solver; `mod_slag_chemistry` en main) y SRCS no topológico · N-B12 escritura
final sin la protección M4 (reanudar con t_final ≤ time trunca el snapshot de
origen) · N-B13 `n_outer` sin asignar sin física activa · N-B14 `check_dims` no
compara geometría; dt del snapshot sin acotar · N-B15 halos de gas/sólido a cero
en el paso 1 de un arranque en frío · N-B16 `[MESH]` impreso por todos los ranks;
contador de intercambios int32 · N-B17 validaciones faltantes (cfl_max > 0,
d_particle > 0, …) · N-B18 receta de carga ignora `layer_bucket`; tiempos de
perfiles sin validar monótonos · N-B19 química de escoria solo lee la celda de
abajo; `rho_co` con 101 325 Pa · N-B20 MC sin atenuación por líquido disperso;
escoria densa fuera de la DO · N-B21 `wall_shear` aplica no deslizamiento en las
aberturas de salida · N-B22 `god_bl` con σ = 1.8 a mano · N-B23 `exchange_gas_liquid`
(mezcla) con k efectiva · N-B24 comentarios rancios (cabecera de momento con
signos invertidos, energía "ρ(T)", F2.22/TAU_LG "flotación relativa",
ws_pcorr_g, √(2 g d_p), slag "3 pasadas", interphase "regímenes disjuntos") ·
N-B25 golden solo min/max/media; `eafutil.read_config` no quita comentarios en
línea; `run_unit.sh` corre binarios huérfanos.

## Pruebas que faltan (prioridad)

1. `check_audit` en TODA corrida con energía, con dos identidades separadas
   (traspaso fusión/congelación a 1e-8; balance global escalado con las fuentes
   sin traspaso) y columna `E_alpha_clip`.
2. Unitario de congelación con latente: ΔE_liq + ΔE_sol = 0 a 1e-12 (N-C2).
3. Banco de drenaje de lecho (goteo 1D) con y sin `liq_balanced_force` (N-C1).
4. Descomposición con fronteras a través de las fases (n12 de baño, congelación,
   escoria; o forzar npr/npth/npz) y `compare_decomposition` con piso por familia
   de campo y tolerancia por caso; comparar `/restart`.
5. `outer_conv` con tolerancias reales y cota inferior de iteraciones.
6. Reinicios de escoria, química con flujo, ECS, mezcla, bed_flood a mitad, y
   n8 → n12.
7. Identidades nuevas: masa de sólido, cierre de interfase, cierre radiativo,
   centinelas en todas las corridas.
8. Corrida de integración con malla estirada (stretch 1.5).
9. Unitarios: EOS de compresión (cavidad cerrada), telescopía de `ws_Fg`,
   conservación geométrica con eje real, Lorentz contra la fórmula sin
   regularizar, fuerza balanceada con superficie libre.
10. Simetría con energía, líquido y Lorentz; caso de baño en el gate quick.
