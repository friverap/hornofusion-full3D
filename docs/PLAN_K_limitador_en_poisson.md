# Plan K — Limitador de hueco dentro del Poisson (conjunto activo)

Fecha: 22-oct-2026. Árbol: rama `pore-ramp`, HEAD `3008a26`, golden v131.
Antecedentes: `.claude/rules/acople-pv.md` (sección 22-oct), Planes D (D2.2),
E (E2, lazo interno) y J.

## 1. Problema

Las tres paradas de B1 con el modelo actual (284.3 s, 294.1 s, 342.5 s) son
una familia: celdas con chatarra (piso de poro, `liq_cap`) donde el tope de
líquido actúa UN PASO después de la presión.

Sonda H0 (`campaigns/b1/diag_h0lim`, celda (10,60,2), 342.500–342.537 s):

| paso | entrada pedida | hueco | s del limitador | α_l |
|---|---|---|---|---|
| par (342508…514) | 91 → 107 | ~27 | 0.60 → 0.49 | 0.8963–0.8969 |
| impar | 0 (cara cerrada, celda en su tope) | 0.6 | 1 | 0.8991–0.8996 |

La decisión es idéntica en los 5 outers del paso (hueco congelado en αⁿ,
J-B) y solo cambia entre pasos; la demanda del Poisson crece paso a paso.
Es una complementariedad (α_l ≤ cap ⊥ flujo de entrada) tratada con retraso.

## 2. Por qué no es D2.2 ni `n_pc_max`

- D2.2 (Plan D) escalaba los coeficientes de cara con el `ws_lim` de la
  pasada ANTERIOR: la presión veía un limitador viejo. Perjudicial.
- `n_pc_max` (Plan E / 22-oct) re-transporta α con flujos de una presión sin
  converger y corrige u por pasada. Mucho peor en B1.
- Plan K converge el conjunto activo DENTRO del mismo solve de presión (lazo
  primal-dual, Hintermüller–Ito–Kunisch 2002; aparición/desaparición de fases
  como complementariedad: Lauser et al. 2011, Ben Gharbia–Jaffré 2014), con
  el momento congelado, y corrige u y p UNA vez.
- En la forma de volumen ∂α/∂p se cancela (Σα = 1): añadir esa diagonal no
  aporta; la no linealidad que rompe el acople es el limitador.

## 3. Diseño (clave `pc_alpha_implicit`, default false)

En `solve_pressure_correction`, tras el ensamblaje actual (F2.31,
compresibilidad, E2, compliancia), guardando aP0…/Su0:

1. Lazo `ias = 1..pc_ai_max_it` alrededor de BC + CG:
   a. flujos de líquido de prueba F = F* + a_f Δpp (forma del export);
   b. limitador de un paso como función pura compartida con el transporte:
      s_i = min(1, (room_i ρV/dt + out_i − ṁ_i)/in_i), room en αⁿ;
   c. conjunto activo A = {s_i < 1}: cada cara de líquido que ENTRA a i ∈ A
      pasa a flujo fijo Q_f = s_i F_f (coeficiente fuera de aP y del vecino,
      ±Q_f a Su de ambas celdas; matriz simétrica, sigue el CG);
   d. liberación: la cara vuelve a abrirse si con el pp nuevo llevaría < Q_f;
   e. convergencia: A sin cambios en todo el dominio (allreduce) y |Δs| < tol;
      si no converge, se queda la unión (conservador) y se cuenta.
2. Export: en caras fijas ws_Fc = Q_f, enlazadas; el transporte debería ver
   s ≈ 1 (`vol_lim`, `vol_unlinked` miden la consistencia).
3. Piso de poro solo vía `liq_cap` en room; el gas de piso conserva su
   conductancia (no repetir E1b). F2.8 y F2.31 sin cambios (F2.31 con el
   hueco predicho: subclave `pc_ai_fsat`, aparte).

Claves: `pc_alpha_implicit` (false), `pc_ai_max_it` (8), `pc_ai_tol` (1e-6),
`pc_ai_fsat` (false); incompatible con `n_pc_max > 1`.

## 4. Pruebas e hitos

- Unit `test_alpha_implicit.f90` (columna de 5 celdas): hueco 0.005 vs
  demanda 0.02 converge en ≤ 3 iteraciones con entrada = room·V/dt;
  liberación al invertir el flujo; simetría; Σ flujos fijos = 0; off ⇒
  matrices idénticas.
- Bitwise con la clave off; bancos bed_bath_rest, bed_drain, pocket_rise,
  bath_freeze, MPI n1/n4.
- **H1 (abortar si falla):** ventana 342.45–342.56 s desde
  `diag_p342a/eaf3d_00342450.h5`: el lazo converge en ≥ 95 % de los outers,
  `vol_lim + vol_unl` de la celda sonda ≥ 10× menor, |p| sonda < 20 kPa,
  centinela ≤ 3.7 %. Si converge pero la presión sigue ciclando, el
  mecanismo no es el limitador: parar.
- Juez 340–346 s desde `judge_otp_280/eaf3d_00340000.h5` (base 0.3/2.5/6.7 %
  centinela) y ventanas 284.3 y 294.1 s (`diag_g284a`, `diag_g294a`).

Esfuerzo estimado 7–8 días; H0 cumplido (22-oct).

## 5. Riesgos

Ciclado del conjunto activo (matriz no M) → tope + unión; invarianza MPI
(Jacobi, halos de A y s, convergencia global); energía del líquido sigue
ws_Fc (vigilar `energy_balance_step`); coste ×1.3–2 de CG por outer;
residuo por los sub-pasos del transporte (medido con `vol_lim`).

## 6. Cierre (23-oct-2026; registrado en WS-K1/WS-K2, 29-oct-2026)

**Refutado y no adoptado.** La clave `pc_alpha_implicit` nunca llegó a
`src/` (0 archivos). El código quedó archivado en
`research/ws/WS-K1/plan_k_v2.patch` y `research/ws/WS-K1/patches/`, que ya
no aplican sobre HEAD.

- H1 (§4) refutada: C-011 → C-012.
- H1b (post-auditoría, tope exacto) refutada por sus incisos (b) y (c):
  C-025 → C-028. Su inciso de ciclo (a) pasa solo en la mediana.
- Juez de 3 trayectorias en 340–345.5 s refutado: C-040 → C-041.
  - La base también pasa de 1 MPa (C-310/C-311).
  - Que el pegado al tope de una trayectoria K sea propio de K no está
    probado (C-312/C-313).
- Abierto, sin veredicto:
  - la holgura de la variante sin A2 (C-039), medida en k1_342 (v1) y en
    k1pa_342;
  - si el brazo K del juez fue esa variante (solo declarado en C-040);
  - si la bajada de p>100k en B1 es una mejora o un traslado de líquido al
    lecho.

Detalle y salvedades: `research/ws/WS-K1/report.md`,
`research/ws/WS-K2/report.md` y «Plan K CERRADO» en
`.claude/rules/acople-pv.md`.
