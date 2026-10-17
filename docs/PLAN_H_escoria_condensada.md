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

## Estado P4 (2026-10-16)
Cableado completo. Gate arc_slag 10 s condensado: u_liq max 0.087 m/s,
vol_lim max 2.4e-7, u_gas 95 -> 5 m/s, p_max 95 kPa estable, acero sobre la
escoria ~1e-10, gas bajo la escoria 0, masas a 1e-10, energia gap 7.3e3 J
(4e-3 del permitido), volfix -2.8e-5 kg. Legado bit a bit (bitwise_check).
Hallazgos cerrados en P4: (1) trazas de escoria con E/m absurda (cancelacion
de masa a 1e-110 kg con E en el redondeo) -> paso 580 a -2 MPa; equilibrio
termico de la traza con el bano, auditado (E_slag_tclip). (2) E_sl y m_X con
valores especificos de inicio de paso: la escoria que cruzaba una celda vacia
dentro del paso viajaba sin energia y el reescalado final creaba energia sin
auditar (1.3e6 J); ahora viajan con asl en cada movimiento (slq_adv).
(3) gas bajo la escoria -> compactacion en el reordenamiento. (4) hidrostatica
inicial con el peso de la escoria condensada (paso 1 de slag_rest: 4e-4 ->
2e-10 m/s). Reposo (slag_rest): CORREGIDO en la auditoria 18 (A18-2): el
"transitorio del gas" era la conveccion del gas a 300 K (el banco no fijaba
T_ambient); en equilibrio termico el reposo condensado queda en u_liq ~1e-11
y u_gas <= 4e-6 m/s (legado: 5e-4 / 8.8 m/s, el gas fantasma de M17-PV1).
Gate automatizado: check_slag_bed --umax-liq 1e-8 --umax-gas 1e-4.

## Estado P5 (2026-10-16)
Fuentes de escoria (quimica E2.3/E2.4, adiciones) al VOLUMEN DE SU MASA en
slag_condensed_sort: alpha_sl = m_sl/(rho_sl V) donde difiere del redondeo y,
si el condensado no cabe, el segmento se extiende hacia arriba sobre el gas
de la columna; el gas desplazado se audita como el volfix (misma convencion
que la fusion: sin fuente en el Poisson, NOTA de mod_pressure_3d). El sort se
llama tambien al fijar el estado de inicio de paso (tras la quimica), con el
delta del remapeo aplicado a liq_old. slag_chem_flow condensado: slag_mass
err 7e-12 (antes 0.95: la masa de las fuentes se perdia), fe_element 6e-11,
volfix -1.0e-4 kg auditado. PENDIENTE P7: `activity` del banco (Fe oxidado
0.99 kg frente a 2.7 kg legado, umbral 1 kg): el estencil de oxidacion pide
O2 en la celda de escoria y bano en la de abajo; con la capa compactada la
celda inferior no tiene gas (la capa resuelta aisla el metal). Decidir en P7
(estencil por columna o umbral del banco) antes de P9.

## Estado P6–P7 (2026-10-16)
P6: m_slag_clip / E_slag_clip (recorte del condensado partido acero/escoria,
acotado alpha_sl <= alpha_c; por paso). Auditoria dirigida de P4 cerrada:
A1 (tclip por paso), A2 (= P5), M1 (= P6), M2 (vol_dalpha condensado), M3
(fallback implicito), M4/M5 (compactacion solo en la interfaz de escoria
resuelta y nunca por encima del hueco), bajos (ws_sp_* en drivers, rho_l
constante documentada). P7: arc_slag 10 s condensado tras M4/M5: u_liq 0.087,
vol_lim 2.9e-7, u_gas 6, p 95 kPa, energia 1.6e-3 del permitido, orden y masa
de la capa exactos. arc_melt_slag y arc_melt_slag_heel condensados: todos los
checks de check_slag_bed y del audit PASS (regimen comparable al legado).
slag_chem_test no tiene flujo (la clave no aplica). slag_chem_flow: activity
con umbral 0.5 kg (la capa condensada aisla el metal del O2: 0.99 kg frente a
2.7 kg legado; el check vigila que la quimica corra). slag_rest en la matriz
de test-full; golden v116.

## Estado P8 (2026-10-16)
arc_slag condensado 0.3 s: n1/n4/n9 a <= 1.2e-12 (redondeo del MC). Reinicio
misma descomposicion BIT A BIT (campos y audit); n4 -> n9: campos 6e-13 y
columnas de audit de redondeo puro (m_slag_clip ~1e-33 kg, m_spill ~1e-26 kg)
que cambian de signo: m_slag_clip/E_slag_clip entran en las columnas de
redondeo de compare_audit (piso 1e-15 del inventario de escoria, solo con
--decomp); m_spill NO (M7-2). sNaN (snanfill + -O0 -ffpe-trap=invalid) en
slag_rest y arc_slag condensados: limpio. Reinicio de slag_rest en la matriz.

## Estado P9 (2026-10-16) — PLAN H CERRADO
slag_in_volume = true por defecto (sin error de configuracion donde no
aplica: slag_condensed_on la apaga). Produccion y B1 bit a bit (sin escoria).
Hallazgo del rebaseline: traza de escoria (alpha_sl 4e-14 < ASL_QMIN) con
Sigma X = 1.04 en slag_chem_flow (cede volumen sin extensivas): composicion
de la traza acotada a su masa. Golden v117 (arc_slag, arc_melt_slag[_heel],
slag_chem_flow pasan a condensado). Docs: CLAUDE.md (M17-PV1 cerrado),
CONFIGURATION.md, PHYSICS.md §14.x.
