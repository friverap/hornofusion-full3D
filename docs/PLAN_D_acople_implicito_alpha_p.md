# Plan D — Acople implícito fracción de volumen ↔ presión

Fecha: 7-oct-2026. Estado del árbol: `fb06a44` (F2.30/F2.31 + fixes del
parser). Antecedentes: `docs/dev-history/2026-09-29_colapso_al_perforar_el_lecho.md`
(mecanismos 1–4, F2.22–F2.34) y paper §6.2 "The long heat".

## 1. Objetivo y criterio de éxito

**Objetivo.** Que la colada B1 (malla media 30×60×42) cruce el régimen de
lecho inundado (t ≈ 320 s) y llegue a refinación, para cerrar la comparación
con Ugarte et al. (2024): curva de fusión completa y ratio sólido/líquido
32.5/67.5.

**Criterio de éxito (gate final).** Juez estadístico desde
`campaigns/b1_v35_f229_5040s/eaf3d_00150000.h5` (300 s) hasta 345 s, tres
descomposiciones (5/6/7 ranks), dt 2 ms adaptativo: en la ventana 320–345 s,
% de pasos con |p| > 20 kPa **< 5 %** y **cero** centinelas (`P_HYDRO_CAP`,
`U_GAS_MAX`, `U_LIQ_MAX`) en las tres trayectorias. Referencia actual:
78–89 % y 37–66 % (paper, Tabla 3). Después, la colada completa.

**Lo que NO es éxito.** Mover el inicio del colapso unos segundos; bajar una
columna del audit subiendo otra (F2.32: presión ↓, líquido en cota ↑);
cualquier resultado medido en una sola trayectoria pasados los 280 s.

## 2. Diagnóstico: por qué el algoritmo segregado no sostiene este régimen

El lazo externo (`mod_multiphase::multiphase_iteration`, `main_3d` l.366)
hace, por iteración: momento(l) → momento(g) → PEA → **presión** →
corrección de u → **transporte de α** → energía. Tres desfases:

1. **α rezagada en la ecuación de presión.** Los coeficientes `α_f (αV/aP)_f`
   y la fuente `−Σ α_f u_f A` del Poisson de volumen se arman con la α de la
   iteración externa anterior; el transporte de α corre DESPUÉS, con los
   flujos ya corregidos. En el freeboard y en el baño libre el desfase es
   inocuo (α cambia poco por iteración). En el poro casi lleno (vacío fluido
   < 5 %) una variación de α de 1e-3 es el 100 % del gas de la celda.

2. **El limitador de hueco actúa fuera del Poisson.** `solve_volume_fraction`
   escala la entrada de líquido a cada celda a lo que cabe (`ws_lim`, barridos
   Jacobi hasta convergencia) y derrama el exceso hacia arriba (`m_spill`).
   El Poisson acaba de pedir un flujo por una cara que el limitador cierra un
   instante después: la continuidad de volumen que el CG resolvió no es la que
   se aplica. La diferencia se re-emite como fuente en la iteración siguiente
   → presión del signo que haga falta para forzar el flujo por otra cara →
   es el *water packing* de RELAP5 §3.4.6 / TRACE cap. 2, literal.

3. **El líquido disperso mueve volumen que el Poisson no ve.** El drift
   (`ws_ud_*`, percolación en el lecho) es un flujo de volumen que desplaza
   gas; el Poisson de mezcla no lo incluye ni como fuente conocida. Donde llega
   (el lecho) aparece volumen de líquido "de la nada" para la ecuación de
   presión, que lo compensa pidiendo gas al paso siguiente.

Cuatro reglas locales sobre el campo α (F2.28, F2.29, F2.33, F2.34) y la
salvaguarda numérica (F2.32) no repararon ninguno de los tres, porque los
tres están en el ORDEN del algoritmo, no en ninguna celda.

**Qué hacen los códigos que sí sostienen este régimen.**
- NEPTUNE_CFD (Guelfi et al. 2007, NSE 156:281; Méchitoua et al. NURETH-10
  2003): paso "alpha–pressure–energy" con lazo interno que itera fracciones
  de volumen y presión hasta que Σα = 1 dentro de tolerancia; el momento va
  rezagado (fractional step).
- Liles & Reed 1978 (TRAC/TRACE/RELAP5): semi-implícito; la restricción de
  volumen se linealiza con Newton y las fracciones quedan implícitas en la
  ecuación de presión.
- OpenFOAM `multiphaseEulerFoam` (PIMPLE): `nOuterCorrectors` ×
  (`alphaEqns` con MULES → momento → `nCorrectors` de presión), con los flujos
  de fase `alphaPhi` recomputados en cada corrector y `nAlphaCorr` sub-lazos
  de α; `faceMomentum` para la consistencia de flujos de cara.
- Darwish & Moukalled 2001 (GCBA, ya adoptado en Plan C F2): en su forma
  completa el algoritmo itera α y p en el mismo corrector.

Nada de esto exige un sistema monolítico α–p–u: basta un **corrector
interno α↔p iterado a convergencia** dentro de cada iteración externa, con el
limitador DENTRO del corrector.

## 3. Diseño

### D2 (núcleo) — corrector interno α ↔ p

Nuevo lazo en `multiphase_iteration`, en el lugar de las llamadas actuales a
`solve_pressure_correction` + `solve_volume_fraction`:

```
u*, flujos F* (del momento + PEA, SIN relajar)        ← ya existe
do ic = 1, n_pc_max
    (a) ensamblar Poisson con α^{(ic)}  (coeficientes α_f d_f, fuente −Σ α_f u_f A,
        compresibilidad del gas, acústico, compliance)         ← existe
    (b) FUENTE NUEVA: ventanas cerradas por el limitador de la pasada anterior:
        cara con ws_lim < 1 hacia una celda llena → coeficiente de la fase
        líquida en esa cara × ws_lim (cara parcialmente cerrada)  → NUEVO
    (c) FUENTE NUEVA: flujo de volumen del líquido DISPERSO (drift),
        explícito y conocido: Su -= Σ_f (α_l u_drift A)_f en caras dispersas  → NUEVO
    (d) CG → pp; corregir u y exportar F = F* + a_nb Δpp               ← existe
    (e) transportar α DESDE α_old con F (sub-pasos CFL + limitador + derrame) ← existe
    (f) Δα = max |α^{(ic+1)} − α^{(ic)}| global; si Δα < tol_alpha_pc: exit
    (g) p ← p + α_p·pp SOLO en la última pasada (las intermedias corrigen
        u y F, no acumulan p)
end do
```

Decisiones de diseño:
- **α NO se relaja** (es conservativa y nace de α_old en cada pasada). Lo
  que converge es la pareja (F, ws_lim).
- **El limitador entra al Poisson por los coeficientes de cara (b)**, no por
  una fuente: así la presión "ve" la pared parcial y busca otro camino en la
  misma iteración. Es el tratamiento implícito del *water packing*: la celda
  llena deja de ser "numerical dead end" porque el sistema lo sabe antes de
  resolver. Con `ws_lim = 0` la cara se cierra del todo y la celda cae en
  F2.29 (sellada → Neumann) si no le queda ninguna.
- **El drift del disperso (c)** es fuente conocida (explícita en el
  corrector, implícita en el paso porque se recalcula por pasada). Es el
  término de drift-flux de la continuidad de mezcla (Manninen 1996, ec. de
  continuidad de la mezcla con `∇·(α_l u_drift)`).
- **Costo**: cada pasada = un CG + un transporte de α (explícito, barato).
  `n_pc_max` = 4; en régimen sano Δα cae bajo tolerancia en la pasada 1–2
  (medirlo en D1 antes de fijar `tol_alpha_pc`). Estimación: +30–60 % de
  tiempo de paso en bore-in, ×2–3 en el régimen inundado.
- **Residual de continuidad** del lazo externo: sigue siendo Σ|Su|/Σ|F*| del
  iterado entrante (Bug 20); se añade `dalpha_pc` (Δα de la última pasada)
  como columna del audit y criterio de salida del externo.
- Claves nuevas: `n_pc_max` (4), `tol_alpha_pc` (1e-6), `pc_limiter_faces`
  (true), `pc_drift_source` (true) — las dos últimas para apagar (b) y (c) por
  separado en el juez.

### D3 — consistencia del gas de poro con el corrector

Con (b), una celda cuyo poro se llena pierde todas sus caras de líquido; su
gas queda con el acústico y la compresibilidad. Verificar que F2.13/F2.16/
F2.31 (gas de poro, percolación, venteo) se evalúen con la α de la última
pasada, no con la de entrada al externo; si no, el mismo desfase vuelve por
el gas. Toca `gas_percolation_mask` (mover dentro del corrector o
recomputar en (a) cuando Δα > tol).

### D4 — reinicio y auditoría

Todo estado nuevo que persista (ninguno previsto: `ws_lim`, `pp` y los
flujos son del paso) → confirmar con `restart_*` bit a bit. Columnas nuevas
del audit: `n_pc` (pasadas usadas), `dalpha_pc`, `m_lim_faces` (masa
redirigida por caras cerradas). Glosario del paper (Apéndice B) se regenera.

## 4. Fases, entregables y gates

| Fase | Contenido | Esfuerzo | Gate |
|---|---|---|---|
| **D0** Banco | `input/bed_flood.dat`: malla 10×20×16, frío, sin arco; lecho denso en el piso (α_s 0.85, 4 celdas), charco encima drenando con `mdot` prescrito, bolsa de gas bajo el lecho. Debe REPRODUCIR el fallo (p fuera de la escala ferrostática + Ergun, centinelas) en minutos. `tests/integration/check_bath.py` extendido con `bed_pv_bounded`. | 1 día | Si el banco NO reproduce el fallo, el juez de D5 es el único instrumento (horas) y D1 se hace sobre v35@300 s con las sondas. |
| **D1** Medida del desfase | Instrumentar por iteración externa: Δα entre externas en el lecho, Σ|Su| re-emitida por el limitador, volumen de drift no visto por el Poisson. Correlacionarlos con `p_max` en 300–325 s de una trayectoria (`[PROBE-P]` en la celda de −13.6 kPa de 320.2 s: i=1, j=1–3, k=1). | ½ día | Los tres desfases del §2 deben verse en los datos antes de escribir D2. Si uno no aparece, no se implementa su pieza. |
| **D2** Corrector α↔p | §3 D2, commits separados: D2.1 lazo + Δα + claves (sin (b) ni (c): debe ser bit-idéntico con `n_pc_max = 1`); D2.2 caras del limitador (b); D2.3 drift como fuente (c). Cada uno con `test-quick`; `test_alpha_limiter`, `test_poisson_bath`, `test_dispersed_liquid`, `test_phase_appearance` como gates; invarianza MPI y simetría 120°. | 3–4 días | `bed_flood` acotado (p dentro de 2× ferrostática + Ergun, sin centinelas, masa exacta). Goldens se moverán: rebaseline v35 explicado. |
| **D3** Gas de poro | §3 D3. | 1 día | `bath_test`/`bath_fill`/`bath_freeze` sin regresión; `bed_flood` sigue acotado. |
| **D4** Reinicio + audit | §3 D4; glosario regenerado. | ½ día | `restart_*` bit a bit; `check_audit.py` cierra. |
| **D5** Juez | v35@300 → 345 s, 5/6/7 ranks, con y sin (b)/(c) (ablación). `scratchpad/cand/stat/run_all.sh` + `criterio.py`. | 2–3 días de máquina | Criterio del §1. |
| **D6** Colada | B1 5040 s a 14 ranks (lanza el usuario); vigilancia con `vigilar.py`; snapshots cada 50 s. | ~8–10 días de máquina | Llega a refinación sin centinelas sostenidas → B1 cerrado; paper §6.2 y Tabla 3 se reescriben; CLAUDE.md y memoria. |

Esfuerzo de código: ~6–7 días. Con máquina: ~3 semanas hasta el ratio de
Ugarte. Puntos de decisión: fin de D1 (¿se miden los tres desfases?), fin de
D2 (¿`bed_flood` acotado?), fin de D5 (¿criterio?). Si D2 no acota el banco
tras dos iteraciones de diseño, parar y revisar con el usuario: la siguiente
opción es el sistema acoplado α–p (Newton sobre Σα = 1, Liles & Reed) y es
otra escala de trabajo.

## 5. Riesgos

- **Convergencia del corrector interno**: el punto fijo (F, ws_lim) puede
  oscilar (una cara se cierra, la presión la reabre). Mitigación: ws_lim solo
  decrece dentro de un corrector (monótono); si oscila, sub-relajar los
  COEFICIENTES de cara, nunca α.
- **Costo**: si el régimen inundado exige `n_pc_max` ≥ 4 en cada externa, la
  colada pasa de ~8 a ~20 días. Mitigación: `n_pc` adaptativo por Δα; medir
  en D5 antes de decidir la colada.
- **Caos**: todo juicio es estadístico (3 trayectorias mínimo, media ±
  desviación, criterio de régimen acotado). Una trayectoria no decide nada.
- **Goldens**: cambio numérico intencional → rebaseline v35 UNA vez, al final
  de D2, con la explicación en el commit.
- **Lo ya aprendido (no repetir)**: nada de reglas locales sobre α; nada de
  cotas nuevas; `TAU_LG`, `ALPHA_LIQ_CONT`, `P_VENT` no se tocan; la forma
  de MASA de la mezcla no vuelve; las centinelas no se suben.

## 6. Referencias

- Guelfi A. et al. 2007, Nucl. Sci. Eng. 156, 281 (NEPTUNE_CFD).
- Méchitoua N. et al. 2003, NURETH-10, "An unstructured finite volume solver
  for two-phase water/vapour flows modelling based on an elliptic oriented
  fractional step method".
- Liles D. R., Reed W. H. 1978, J. Comput. Phys. 26, 390.
- Darwish M., Moukalled F., Sekar B. 2001, Numer. Heat Transfer B 40, 99;
  Moukalled & Darwish 2004, ibid. 45, 523 (GCBA).
- RELAP5/MOD3 Vol. I §3.4.6; TRACE V5.0 Theory Manual cap. 2 (water packing).
- Manninen M., Taivassalo V., Kallio S. 1996, VTT Publ. 288 (drift-flux).
- OpenFOAM `multiphaseEulerFoam`: `pU/pEqn.H`, `alphaEqns`, PIMPLE.
