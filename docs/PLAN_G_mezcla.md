# Plan G — Modelo de MEZCLA con deslizamiento y acople α–p implícito (12-oct-2026)

Clave `mixture_model` (default `false`), módulo `src/mod_mixture_3d.f90`.
Motivo: los Planes D, E y F atacaron con reglas locales la pérdida de
hiperbolicidad del modelo de dos fluidos cuando una fase desaparece en el
lecho inundado de B1 (~320 s) y los tres fallaron en el juez. En el modelo de
mezcla no hay fase que desaparezca dentro del acople P–V: una velocidad, una
presión, y α_l transportada con el flujo de la mezcla más un deslizamiento que
la presión no ve.

## 1. Formulación (forma volumétrica, como el Poisson de Plan C F2)

- `eps = 1 − α_s − α_sl` (porosidad fluida), `s = α_l/eps`.
- `v` = velocidad VOLUMÉTRICA intersticial de la mezcla,
  `eps v = α_l u_l + α_g u_g`; se reconstruye de las velocidades de fase
  guardadas, así que no hay estado nuevo de velocidad.
- Continuidad de volumen: `div(eps v)` = compresibilidad del gas (la fusión es
  neutra, ρ_l = ρ_s).
- Momento de la mezcla con fuerzas de cara BALANCEADAS (presión + gravedad en
  la cara, la fuerza de celda es la media de sus caras; Francois 2006,
  interFoam). El Boussinesq del líquido va en la densidad de cara.
- Velocidad de celda RECONSTRUIDA desde los flujos conservativos (como
  `fvc::reconstruct`): el corrector clásico solo cancelaba la mitad de un salto
  de fuerza concentrado en una cara (gas a 300 m/s sobre el baño).
- Transporte de α_l: `j_l = f·Q + eps s (1 − s) W` con Godunov acotado
  (saturación del dador de arriba × hueco de gas del receptor de abajo).
- Velocidades de fase para energía, especies y salida a partir de `v`, `f` y
  `W` (identidad `α_l u_l + α_g u_g = eps v` exacta).

### Lecho (α_s ≥ 1e-2): Darcy bifásico (Buckley–Leverett con gravedad)

Movilidades `λ_q = α_q²/K_q` con el Ergun de cada fase (Bug 21). El modelo
homogéneo (Ergun de la mezcla, peso ρ_m g, inercia ρ_m, fracción convectiva s)
trataba gas y acero como si se movieran juntos: la columna con más gas flotaba
como un airlift y la mezcla circulaba por el lecho saturado. En el lecho:

| término | homogéneo | Darcy bifásico |
|---|---|---|
| arrastre | Ergun(ρ_m) | `K = eps²/λ_T` |
| peso | ρ_m | `ρ_λ = (λ_l ρ_l + λ_g ρ_g)/λ_T` |
| inercia | ρ_m (masa vieja) | ρ_λ (fase móvil) |
| fracción convectiva | s | flujo fraccional `λ_l/λ_T` |
| deslizamiento | — | `λ_l λ_g/λ_T Δρ g`, acotado por la burbuja de Harmathy |

La fracción convectiva se evalúa con la α de cada sub-paso (con la α congelada
al inicio de la iteración el transporte vaciaba celdas por debajo de cero y el
recorte creaba líquido: 274 t → 1220 t en `bath_test`).

### Fuera del lecho

Gota terminal (`settling_velocity`) o burbuja de Harmathy
(1.53 (σ g Δρ/ρ_l²)^¼ ≈ 0.34 m/s) mezcladas con la logística AIAD; la película
sobre el lecho gotea a la velocidad de percolación (F2.14).

## 2. Piezas físicas que faltaban en el código y el modelo de mezcla expone

- **Intercambio de calor gas–líquido** (no existía): burbujas (logística AIAD
  sobre α_g), Nu = 2, paso partido exacto de dos nodos, auditado en las
  columnas de interfase. Sin él, el gas dentro del baño recibía su parte del
  arco, llegaba a 3000 K y su expansión hinchaba el baño. Solo burbujas: con
  área de gota o de superficie, el gas frío sobre el baño de `bath_test` se
  calentaba de 300 a 1230 K en dos pasos.
- **Referencia de la fuente de compresibilidad** = T del gas al final del
  SIMPLE del paso anterior (`sh%Tg_end`, persiste en el reinicio), no la T de
  inicio de paso. Los operadores partidos de después del SIMPLE (interfase con
  el sólido) enfrían el gas sin pasar por el Poisson y el gas vuelve dentro del
  paso a su equilibrio con el líquido: medida contra T_old esa ida y vuelta era
  una EXPANSIÓN neta cada paso que integraba presión en filas de conductancia
  mínima (lecho denso inundado de `bed_flood`: +35 K por paso, 45 → 2000 kPa).
  Es el mecanismo por el que existe F2.13 en el modelo de dos fluidos.
- **Sub-relajación local**: `α_eff = α_u + (1 − α_u)·f`, f = fracción de aP
  que es arrastre. En una celda dominada por Darcy la relajación explícita era
  memoria que el corrector (d minúsculo) no podía borrar.

## 3. Acople α–p implícito

El transporte de α corre dentro de cada iteración externa con los flujos
conservativos de esa iteración, y `check_convergence` exige además
`max|Δα|` entre iteraciones < `tol_alpha_mix` (Picard sobre v, p y α). Con
`max_outer` acotado (B1: 5) la convergencia la limita el tope.

## 4. Bancos (n4)

| banco | métrica | dos fluidos | mezcla |
|---|---|---|---|
| `bath_test` (baño en reposo, 1 s) | hidrostática / corriente fantasma | 0.9 % / 0.17 m/s | 1e-15 / 2e-14 m/s |
| `bath_fill` (baño + fusión + arco, 0.5 s) | p_max / u_gas_max | 83 kPa / 163 m/s | 62 kPa / 85 m/s |
| `bath_fill` sin arco ni fusión, con radiación | p_max | — | 52 kPa, estable |
| `bed_flood` plano (12 s) | p > 100 kPa / cent | 8.1 / 4.7 % | 70.6 / 79.3 % |

Balances (masa del acero, entrega de fusión, energía, presupuesto del arco)
cerrados en todos. Reinicio bit a bit en modo mezcla (`bath_fill` desde el paso
20, 0.0 a 1e-12). Clave apagada: `make test-quick` bit a bit.

`bed_flood` falla desde ~3.3 s: el arco funde el lecho bajo el electrodo y la
columna del arco (gas a 2500–3000 K con 17 % de gotas de acero) sube a
60 m/s; en el modelo de mezcla las gotas, con tiempo de relajación ~4 s,
quedan obligadas a seguir al gas que se expande, y acelerar esa mezcla pesada
cuesta ~1 MPa. El banco NO predice B1 (cuatro veces en Planes D–F): el juez
decide.

### Probado y negativo
- Gotas con velocidad propia (deriva relajada de Bug 15 + arrastre con el gas)
  dentro de la mezcla: con interruptor en α_l = 0.3 la celda pasaba de inercia
  y peso de mezcla a los del gas (0.7 MPa); con la logística suave,
  `bath_fill` 0.52 MPa y gas en la cota. Queda apagado (`MIX_DROPLETS`).

## 5. Juez B1 (reinicio desde 300 s): NEGATIVO

`judge_g_n12` (= `judge_base_n12` + `mixture_model`): p_max 0.75 MPa a los 25
pasos y `P_HYDRO_CAP` antes de 300.3 s; se detuvo a los 484 pasos por
protocolo. La referencia limpia del modelo de dos fluidos está limpia hasta
318 s. Diagnóstico con reinicios cortos y densos (`g_b1d`, `g_b1e`, 30 pasos,
snapshot cada 5):

| variante | p_max (kPa) por paso | dónde |
|---|---|---|
| mezcla | 856 → 2000 (pasos 2–6) → ~750 sostenido | piso del lecho, k = 3, α_s 0.87–0.95 saturado |
| + equilibrio térmico de burbujas al reanudar | igual | idem, −700 a −790 kPa |
| + piso de porosidad 0.3 en la permeabilidad (`mix_eps_perm_min`) | 1.2–2.0 MPa | celdas α_s 0.985 (gas de poro) y el baño encima, ±1.1–1.5 MPa |

Lectura. El estado de B1 a 300 s tiene 762 celdas con α_s > 0.9 (porosidad
< 10 %; 165 densas y medio saturadas): chatarra compactada por el colapso hasta
el tope 1 − `ALPHA_PORE_GAS`. Con Ergun su permeabilidad es ~1e6 veces menor
que la de un lecho real, así que cualquier fuente de volumen en ellas (gas que
se calienta o se enfría unos kelvin) cuesta MPa en CUALQUIER acople
incompresible/low-Mach: el modelo de mezcla no lo cambia. Es el mismo sitio y
la misma familia que las ráfagas del modelo de dos fluidos (Plan F §1) y que
los fallos de D, E y F. Además, reanudar desde un estado del modelo de dos
fluidos es una perturbación grande para otro modelo (gas a temperatura de arco
dentro del baño, sin intercambio gas–líquido); un juicio justo del modelo de
mezcla requiere que construya él mismo el lecho y el baño desde antes de la
inundación (reinicio desde ~200 s, ~12 h de máquina) o desde t = 0.

Lo que queda (opt-in, default apagado, bit a bit con la clave apagada,
reinicio bit a bit en modo mezcla): el modelo de mezcla completo, el
intercambio gas–líquido de burbujas, la referencia `Tg_end` (persistida), la
clave de diagnóstico `mix_eps_perm_min`.
