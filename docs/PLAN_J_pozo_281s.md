# Plan J — El pozo de presión de B1 281 s (cara cerrada por F2.8 que el transporte rellenaba)

Estado (21-oct-2026): **J-B en commit y ON por defecto** (`pc_transport_f28`,
2f0529b; golden v128 en 8b50511, que además lleva I1/I2 del Plan I —ver
`PLAN_I_escoria_columna.md`). J-1 rechazado con datos. Pendientes en
`AUDITORIA_20_2026-10-21.md`, todos cerrados (ver abajo).

## Causa (medida, B1 281 s, −82 kPa)
Celda de poro saturado del lecho: F2.8 cerraba en el Poisson las caras del
líquido hacia vecinas sin hueco de poro (`face_open`, `ws_Fc_lk = 0`), de modo
que su fila cuadraba «sale líquido por la única cara abierta = entra gas de
piso por las otras cinco». Pero el transporte de α (`face_fluxes_noalpha_all`,
rama "resto") reconstruía el flujo de esas caras continuo|continuo
desenlazadas con la velocidad de CENTRO y el limitador las rellenaba. La fila
de presión pedía un volumen que el transporte no respetaba; el defecto se
cerraba con un pozo de presión (rastreo del agente, 20-oct; sonda `[PROBE-P]`,
`scripts/diag/probe_p.py`).

## Opciones
- **J-1 (gas de piso unilateral en `face_lim`, clave `pc_floor_gas`)**:
  RECHAZADA. `bed_bath_rest` con gas a 83 m/s (7.2 con E1). Parche archivado en
  `campaigns/b1/planJ_floor_gas.patch`, sin commit.
- **J-B (F2.8 también en el transporte)**: ADOPTADA. Con `ws_Fc_valid`, una cara
  continuo|continuo con `ws_Fc_lk = 0` y vecina dentro del dominio lleva G = 0
  en r, θ y z (`mod_continuity.f90`, `face_fluxes_noalpha_all`, argumento
  `f28`). Conservativa (la cara deja de transportar en ambos sentidos) y
  coherente con la energía (`ws_Fr/Fth/Fz` salen del mismo G).

## El ciclo entre iteraciones externas (y su arreglo)
Primera versión: `bed_drain` energy_balance_step ×8.9 (gap ~2.5e4 J/paso).
Causa: `ws_liq_room` se recalculaba en cada outer con la α del iterado → la
cara se cerraba, la receptora no se llenaba, se reabría en el outer siguiente;
`vol_dalpha_outer` sube (bed_drain n1: 2.5e-2 m³ sin el congelado frente a
1.45e-4 con él; sin J-B el nivel era ~3e-6). Arreglo: con `pc_transport_f28` el
hueco de poro se CONGELA en α^n al inicio del paso (`mod_multiphase.f90`) y no
se actualiza dentro del bucle `n_pc_max > 1`. En la vista condensada (Plan H)
`liq_old%alpha` ya incluye la escoria: no sumar `ws_sp_asl` (hallazgo ALTO de
la dirigida, corregido antes del commit).

## Medido
| juez | ventana | centinela | p > 50 kPa | p_max |
|---|---|---|---|---|
| base (rampa+histéresis+E2) | B1 280–281.6 s | 2.6 % | 11.8 % | 90 kPa |
| J-B + hueco congelado | B1 280–281.6 s | 0 % | 0.8 % | 94 kPa |

Juez B1 275→300 s (`campaigns/b1/judge_jb_275`) por ventana de 5 s, % de filas
con centinela de p, gas o líquido (`scripts/diag/regime2.py`):

| ventana | jfh (histéresis) | je2 (+E2) | **J-B (+E2)** |
|---|---|---|---|
| 275–280 | 0.0 | 0.0 | 0.1 |
| 280–285 | 1.0 | 2.3 | **0.0** |
| 285–290 | 0.2 | 1.6 | 0.1 |
| 290–295 | 0.2 | 33.3 | **0.0** |
| 295–300 | 0.0 | 41.5 | **0.0** |

Con J-B el centinela de líquido de E2 (33–41 % a 290–300 s) desaparece y el
gas toca la cota en 2 filas de 5001 (277.5 y 288.7 s); presión y líquido nunca.

## Tests
`test_transport_f28` (casos 1–6: cierre en z, B off transporta, cara lateral
continuo|disperso intacta, cara enlazada no se corta, inerte sin
`ws_Fc_valid`, caras r y θ). Mutaciones verificadas.

## Límite conocido (B20-8)
J-B solo actúa en caras continuo|continuo. Una cara continuo|disperso hacia
una celda llena (la auditoría 20 lo señaló con α_s > 0.975, donde la receptora
no entra en la máscara de continuidad) no se corta: su entrada la sigue
acotando el limitador de α con `liq_cap`, como antes de J-B.

## Cerrados (auditoría 20)
- M20-2: separar el hueco congelado (`face_open`, J-B) del del iterado (fsat,
  F2.31, `fs_full`): PROBADO Y NO ADOPTADO, empeora el pozo de 281 s.
- M20-3: el enlace cambia entre correcciones en ~1 % de las caras, sin
  relación con las ráfagas: medido sin acción.
- M20-5: caso 6 (r, θ) de `test_transport_f28` y gates `bed_drain_outer` /
  `bed_drain_unlinked` en `check_drain.py`; `n_pc_max > 1` sin cubrir (no es
  default).
