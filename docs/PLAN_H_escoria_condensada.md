# Plan H — La escoria como fase condensada dentro del Poisson (cierra M17-PV1)

Decisión del usuario (16-oct-2026): rediseño ahora, antes de los bajos; B1 al
final. Diseño elegido: **(A) vista condensada c = acero + escoria** para
volumen y momento. Rechazadas: (B) deriva propia de la escoria en el Poisson
(patrón prohibido desde Bug 15); (C1) tercer fluido euleriano
(desproporcionado); (C2) fuente con el Δα_sl de slag_buoyancy (un paso tarde,
no local, no ataca el bloqueo del limitador).

## Causa (M17-PV1, medido)
El Poisson trata la escoria como volumen inmóvil y `slag_buoyancy` la recoloca
fuera de él. En arc_slag la escoria tapa el baño (celda de interfaz α_l 0.45,
α_sl 0.55, α_g 0); el único escape de volumen del Poisson es un gas fantasma del
canal F2.21 (2.5e-4 m³/s); el limitador bloquea la entrada y el baño se acelera
(u_liq 1.25 m/s a 10 s; 0.11 sin escoria). Ocho parches locales rechazados con
datos (CLAUDE.md, AUDITORIA_17).

## Diseño
- Interruptor: `cond = solve_slag .and. slag_in_volume .and. solve_flow .and.
  solve_multiphase .and. .not. mixture_model`. Clave nueva `slag_in_volume`
  (default false hasta P9). Sin `cond` el camino legado queda TEXTUALMENTE
  intacto (bit a bit: producción, B1, slag_chem_test sin flujo, mezcla).
- Vista condensada en `multiphase_iteration` (máscaras → antes del transporte, y
  alrededor de cada Poisson del corrector): liq%alpha ← α_l+α_sl, liq%rho ← ρ_c
  (mezcla), igual para liq_old; copias del acero en workspace, restauradas exactas.
- Explícito: peso propio del condensado `ws_wc` (Boussinesq del acero + ρ_sl g de
  la escoria); hueco `liq_cap(α_s,0) − α_c`; el momento usa el flujo condensado
  `ws_Fcm_*` (la energía sigue con el del acero).
- Transporte condensado (subrutina nueva `solve_condensed_fraction`): mismos
  flujos donor G, acero G·α_l,d y escoria G·α_sl,d; limitador sobre el condensado;
  derrame con composición del dador; m_sl/E_sl/m_X advectados desde `slag_pre`;
  con α_sl ≡ 0 debe reproducir `solve_volume_fraction` bit a bit.
- Flotación = REORDENAMIENTO neutro en volumen por segmento condensado contiguo
  de cada columna (`slag_condensed_sort`): conserva α_c por celda, acero abajo
  (remapeo con su T_l), escoria arriba (remapeo M17-arc1); no toca el gas.
- Adiciones (y química si se mide relevante) como fuente de volumen conocida en
  el Poisson y mdot de escoria en el transporte.
- t = 0: una colocación legada (auditada); después solo reordenamiento.

## Piezas y gates
| Pieza | Contenido | Gate |
|---|---|---|
| P0 | clave, línea base arc_slag 10 s, arnés bit a bit (producción y B1 corto) | golden sin cambio |
| P1 | vista condensada + peso | test_condensed_view; golden sin cambio |
| P2 | transporte condensado | test_condensed_transport (a–e); golden sin cambio |
| P3 | reordenamiento | test_condensed_sort (1–5) |
| P4 | cableado (multiphase, main, momento) | reposo baño+escoria u ≤ 1e-9; banco slag_rest; arc_slag 2 s u_liq ≤ 0.2 |
| P5 | fuentes de volumen (P5b viscosidad opcional) | slag_chem_flow: volfix ≈ 0, química cerrada |
| P6 | audit (m_slag_clip, E_slag_clip, m_slag_src) | identidades por paso |
| P7 | validación arc_slag 10 s y bancos con escoria; rebaseline | u_liq ≤ 0.2, vol_lim ≲ 1e-6, u_gas ≤ 100, masas 1e-12, película 0, volfix 0 |
| P8 | robustez: decomposition n1/n4/n9, reinicio, sNaN | 1e-9 / bit a bit |
| P9 | docs; slag_in_volume = true | — |

Riesgos y su detección: ver el informe del plan (bit a bit/FMA; lectores ocultos
de liq%alpha en la ventana; corrientes espurias en la interfaz por el salto de
ρ; superficie gas|escoria; escoria drenando en lecho frío; arco/MC/DO; química y
espuma; cesta 2/ECS; MPI; reinicio; energía auditada; rendimiento).
