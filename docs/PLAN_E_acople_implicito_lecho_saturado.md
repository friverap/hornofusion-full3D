# Plan E — Acople α–p implícito: lecho saturado incompresible + corrector interno

Fecha: 10-oct-2026. Árbol: `d293b92` (Plan D consolidado, claves `pc_*` en
false, golden v35). Antecedentes: `PLAN_D_acople_implicito_alpha_p.md` §2
(tres desfases), dev-history `2026-10-07_plan_d_acople_implicito.md` (D1:
Spearman `vol_lim` 0.94, `vol_unlinked` 0.93; D2.2: mecanismo de la celda que
cae a g/2 sobre un poro sellado; D5/D6: ninguna regla local cruza el juez).
Decisión del usuario (10-oct): "vamos por la correcta, el acople α–p
implícito".

## 1. Objetivo y criterio

Igual que Plan D §1: juez estadístico v35@300 → 345 s, tres descomposiciones,
ventana 320–345 s con **< 5 %** de pasos con |p| > 20 kPa y **cero**
centinelas en las tres trayectorias. Después, la colada B1 completa.
Lección de Plan D que gobierna este plan: **el banco de 4 celdas no predice
B1**; ninguna pieza toca un default sin pasar por el juez.

## 2. Diagnóstico de raíz (lectura del código, 10-oct)

1. **El lecho saturado es una PARED para la presión.** `face_open` (F2.8,
   `mod_pressure_3d`) cierra toda cara de líquido hacia una celda del lecho
   sin hueco de poro (`ws_liq_room ≤ 1e-4`). Una celda con el poro lleno queda
   sin caras de líquido; F2.29 la declara sellada y su `p` es la media de sus
   vecinas (Neumann), no la continuación hidrostática de la columna. La celda
   de baño de encima diferencia a través de ella (gradiente centrado, o
   unilateral con D2.2b) y lee ½ g (D2.2, sonda `[PROBE-MOM]`): cae a
   −1.3 m/s contra un piso incompresible. Parar 1.3 m/s de acero en un paso de
   2 ms cuesta ρ u Δx/Δt ≈ 5e5 Pa: los MPa son el golpe de ariete de una
   columna que NUNCA debió caer. Físicamente un lecho saturado es un medio
   poroso incompresible: la presión se propaga por él y el líquido lo
   atraviesa a la velocidad de Darcy (Ergun: 1 cm/s cuesta 3.5 kPa/m con
   d_p = 0.1 m, ε = 0.15), la columna de encima está en reposo hidrostático y
   lo que gotea desde arriba hace subir la superficie EN OTRO SITIO a través
   del lecho, por la presión. F2.8 se introdujo (v22, sep-2026) cuando el
   Poisson "seguía empujando líquido que el limitador rechazaba": la respuesta
   correcta no era cerrar la cara, sino quitar el almacenamiento de la fila
   (celda llena ⇒ div(α_l u_l) = 0 con las caras ABIERTAS).

2. **Lo que el Poisson no sabe se lo cobra la presión** (desfases 2 y 3 de
   Plan D, medidos en D1): el limitador bloquea entradas que el Poisson pidió
   (`vol_lim`) y el goteo disperso entra por caras que el Poisson no enlaza
   (`vol_unlinked`). Ambos son del mismo tamaño y crecen juntos; el 1
   (α rezagada en los coeficientes) es 100× menor.

3. **La presión se relaja (`alpha_p` = 0.7) y la velocidad no**: en la fila
   rígida la corrección alterna de signo por iteración externa (sonda
   `[PROBE-P]`: pp ±3e5 con signo alternante, p 27 → 378 kPa en 3 pasos). Es
   la convergencia lenta de SIMPLE en una región incompresible cerrada; se
   mide y se trata al final (E3), no antes de quitar 1 y 2.

## 3. Diseño

### E1 — Poro saturado = celda incompresible transmisiva (clave `pc_sat_open`)

- `face_open` deja de cerrar las caras **líquido|líquido** (ambas celdas con
  líquido continuo activo). Una celda en cap tiene fila con sus caras de
  líquido abiertas y sin término de almacenamiento: `Σ_f a_f (pp_nb − pp_P) =
  −Σ_f α_f u*_f A`, es decir div(α_l u_l) = 0 — incompresible.
- Se mantiene cerrada la cara hacia una celda en cap desde una celda SIN
  líquido continuo (no hay cara de líquido que abrir) y la lógica F2.29
  para celdas realmente sin caras.
- El limitador de hueco del transporte sigue como guardia: con flujos
  consistentes su bloqueo debe caer a ~0 (`vol_lim` del audit es el juez).
- Test nuevo en `test_poisson_bath`: columna de baño sobre tres celdas de
  lecho saturado (α_s 0.85, poro lleno) ⇒ p hidrostática a través del lecho
  a 1e-9 y u = 0.

### E2 — Corrector interno α↔p con fuentes consistentes (claves `n_pc_max`, `tol_alpha_pc`)

En `multiphase_iteration`, en lugar de `solve_pressure_correction` +
`solve_volume_fraction` una vez:

```
S_store = 0; S_unl = 0                       (outer 1; después: del outer anterior, mismo paso)
do ic = 1, n_pc_max
    Poisson con α^{(ic)}, fuente extra por celda  Su += S_unl − S_store      (NUEVO)
    CG → pp; corregir u; exportar F = F* + a_nb Δpp                           (existe)
    transporte de α desde α_old con F (sub-pasos, limitador, derrame)        (existe)
    medir por celda (NUEVO, en solve_volume_fraction):
        S_unl   = Σ_f flujo de líquido por caras NO enlazadas (drift, dador) [m³/s]
        S_store = (α_l^{(ic+1)} − α_old) V/Δt   SOLO si el gas de la celda no
                  está en el acople (poro con gas atrapado o residual): el
                  hueco absorbe sin presión hasta llenarse
    Δα = max |α^{(ic+1)} − α^{(ic)}|; si Δα < tol_alpha_pc: exit
end do
p += alpha_p·pp  solo en la última pasada (las intermedias corrigen u y F)
```

- `S_unl` es el término de drift-flux de la continuidad de mezcla (Manninen
  1996): el líquido que entra por goteo desplaza gas (celda con gas acoplado)
  o líquido (celda saturada) **en la misma iteración**, por la presión.
- `S_store` es la capacidad del hueco no acoplado: mientras cabe, el Poisson
  no exige nada; cuando el limitador deja Δα = 0, la fila es incompresible.
  Es el tratamiento implícito del water packing en forma de FUENTE (D2.2 lo
  hizo en forma de cierre de cara y empeoró: cerrar la cara mueve el problema
  a la donante; la fuente deja la cara abierta y reparte por presión).
- Sin estado entre pasos (`ws_*` del paso): reinicio bit a bit intacto.
- Columnas del audit: `n_pc` (pasadas), `dalpha_pc` (Δα de salida);
  `vol_lim`/`vol_unlinked` existentes deben caer.
- Costo: cada pasada = un CG + un transporte explícito. En régimen sano la
  pasada 2 debe salir por tolerancia.

### E3 — Corrector de presión no relajado en la fila rígida (solo si E1+E2 lo dejan visible)

Medir con `[PROBE-P]` en el banco si la alternancia de signo de `pp` persiste.
Si persiste: segunda corrección tipo PISO (Issa 1986) dentro de la pasada
(`u'' = −d ∇pp₂` con Σ a_nb u'_nb en la fuente), p sin relajar en la segunda.
No se implementa antes de medir.

## 4. Fases y gates

| Fase | Entregable | Gate |
|---|---|---|
| E1 | `pc_sat_open` + test unitario hidrostático sobre lecho saturado | `test_poisson_bath` nuevo caso 1e-9; `bath_*`, `melt_forced` sin regresión; banco `bed_flood` n4: `vol_lim` ↓, p>100k ↓ respecto a d293b92 (41.7/0.9/… con claves D; base sin claves a medir) |
| E2 | lazo interno + fuentes + columnas | banco: `vol_unlinked` → ~0 en la última pasada, `dalpha_pc` < tol en ≤ 3 pasadas en régimen sano; restart bit a bit; invarianza n1/n4; simetría |
| E3 | (condicional) PISO | sonda sin alternancia |
| E4 | Juez B1 (3 trayectorias, secuencial, ~6 h c/u) | criterio §1 |
| E5 | Consolidar: defaults, golden v36, paper §b1limit reescrito, CLAUDE.md | — |

Un commit por pieza con `test-quick`; `test-full` por fase. Las claves nacen
en `true` para el desarrollo; el juez decide los defaults.

## 5. Riesgos

- E1 abre caras con `d_f` del lecho (~1e-7): matriz más rígida para el CG
  (ya coexisten 1e-7 y 1e-2). Vigilar `n_iter_cg`.
- Una celda saturada con TODAS sus vecinas de líquido también saturadas y sin
  salida real (bolsa) es incompresible de verdad: el goteo que le llega (S_unl)
  no tiene adónde ir y la presión sube hasta que el goteo se frena. Es
  físico (la bolsa está llena) y debe verse como `vol_lim` residual, no como
  MPa: el goteo disperso debe ver la presión (su drift en el lecho es la
  percolación de Ergun; si la celda de abajo está llena, el disperso de
  arriba se queda — ya es así por `ws_lim` en caras dispersas).
- `S_store` depende de qué gas está acoplado (F2.13/F2.16/F2.31): hay que
  tomarlo de la MISMA máscara `act_g` del Poisson de la pasada (exportarla).

## 6. Resultado (10-oct)

- E1 en el banco: la pieza con más efecto de Plan D+E (picos > 100 kPa 8 →
  1.4 %, líquido > 10 m/s 9 → 0 %, centinela 4.7 → 0.8 %, `vol_unlinked` 40×
  menor, consistente n2/n4/n8). E2 (fuente de goteo no enlazado) y el lazo
  interno (`n_pc_max`) sin efecto medible en el banco una vez puesta E1.
- **Juez B1 (E4): NEGATIVO.** `judge_e1_n12` detenida a 322.2 s: en 320–325 s
  p > 100 kPa en el 27.6 % de los pasos (base 4.2), gas > 200 m/s 6.3 (1.8);
  en 300–320 s no se distingue de la base. (El "100 % > 20 kPa" y el "66 %
  de centinela" del primer corte eran hidrostática y gotas dispersas:
  métrica corregida en `regime2.py`/`b1_regime_table.py`.) Detalle
  y mecanismo en dev-history `2026-10-10_plan_e_lecho_saturado.md`.
- Consolidación: `pc_sat_open` default `false` (banco `bed_flood.dat` lo
  activa), E2/lazo quedan en claves `false`, golden v37. Segunda lección de
  método, idéntica a la de Plan D: el banco de 4 celdas NO predice B1 — y
  esta vez tampoco la coincidencia en tres descomposiciones del banco.
- Lo que el fallo enseña (§5, riesgo "bolsa", confirmado): abrir la cara del
  poro saturado traslada el water packing de la celda dadora (F2.8: el baño
  cae) a la receptora (E1: el baño se estrella). Ninguna regla sobre QUÉ
  caras abre el Poisson resuelve que la presión no sabe lo que el limitador
  rechazará; el término que falta es el de E2 (`S_store`/`S_unl`) CONVERGIDO
  con la presión — pero medido en B1, no en el banco.
- **E1b (`pc_sat_gas_off`, 10-oct tarde)**: el gas residual del poro saturado
  sale del acople (máscara fijada por paso). Banco: el lecho saturado carga
  su peso (∇p = ρ_l g; la base está ~70 kPa por debajo), `vol_lim` 14× menor,
  pero aparece el water packing de la celda de baño que se llena (540 kPa) —
  antes lo absorbía la válvula ficticia. Con D2.4 (`alpha_g_comp_min = 0.01`)
  el banco queda acotado (p>100k 4 %, gas 5 %, centinela 1 %, p_max 158 kPa).
  E2 y el lazo interno no ayudan (el lazo con momento rezagado es mucho
  peor). Screening B1 (`judge_e1b_n12`, 300→325 s) en curso desde 17:55.
  Commit `95e6048`.
