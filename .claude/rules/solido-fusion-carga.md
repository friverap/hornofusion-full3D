---
paths:
  - "src/mod_melting_3d.f90"
  - "src/mod_solid_phase.f90"
  - "src/mod_scrap_collapse.f90"
  - "src/mod_ecs_feed.f90"
  - "src/mod_fields_3d.f90"
  - "src/mod_input_profiles.f90"
---

# Solido, fusion/congelacion, colapso de chatarra, cestas y ECS

Convenciones vigentes movidas TEXTUALMENTE desde CLAUDE.md (reestructuracion
harness, 16-oct-2026). Cada una existe por un fallo medido: no simplificar una
guarda sin leer su causa.

- **Cierre de fase evanescente (sep-2026)**: una celda con
  `0 < m_s ≤ ρ_s·V·ALPHA_SOLID_RESID` (1e-4) se CIERRA en `compute_melting`
  (masa+entalpía al líquido vía `mdot`/`T_src = liquid_entry_T(e)`, celda
  exactamente vacía). Nunca volver a la guardia `m_s > SMALL` como único
  criterio de existencia del sólido: T_s = E_s/m_s con microgramos fue el
  NaN de B1 (Bug 11 en ARCHITECTURE §10). Todo cierre nuevo de fase
  residual debe ser conservativo y auditado (`m_resid_closed`).
  **Solo remanentes que ya alcanzaron el solidus** (auditoría M10, oct-2026):
  un remanente FRÍO sigue siendo sólido — cerrarlo creaba líquido subenfriado
  que re-solidificaba y convertía en "líquido" la carga ECS de poca masa.
- **Fusión y congelación = REGLA DE LA PALANCA (auditoría M9, oct-2026)**:
  estados, no tasas por paso. Sólido con e > e_sol: f = (e−e_sol)/(e_lb−e_sol)
  sale como fundido a e_lb (T_liq), el resto queda en e_sol; líquido bajo el
  liquidus congela M(e_lb−e_l)/(e_lb−e_entry) a e_entry = min(e_sol, e_l)
  (`RESOLID_LIMITER` solo acota la fracción por paso, por positividad del
  transporte de α). La T de entrada del fundido la devuelve `compute_melting`
  en `ws_Tsrc`; NUNCA volver a usar `sol%T_s` como T_src.
- **Entalpía del sólido**: función única `solid_enthalpy`/`solid_T_from_enthalpy`
  (mod_melting_3d) para TODA conversión E↔T; el dato del líquido es
  `e_l = cp_l·T + C0`. No usar `E/(m·cp_s)` directo.
- **Colapso de chatarra**: una celda con α_l ≥ ALPHA_LIQ_CONT no es hueco.
- **Carga de la cesta 2 SOBRE el baño y la escoria (auditoría 11, A11-1)**:
  `charge_scrap` (bucket > 1) toma como cota de carga también la cara superior
  de la capa más alta con líquido + escoria ≥ ALPHA_LIQ_CONT: la chatarra solo
  desplaza GAS. Antes se metía en celdas con baño y el exceso dependía del
  derrame, que no atraviesa una capa de escoria llena: clip de toneladas en el
  paso de carga (réplica de producción: 12 t). En la capa LEGADA la cesta 2
  empieza sin contacto con el baño (como el ECS y el colapso, que apoyan la
  chatarra sobre el baño); la cesta 1 (talón) no cambia.
  `test_charge_slag`. **Con la escoria CONDENSADA (Plan I, I2) la chatarra
  ATRAVIESA la escoria** en la cesta 2 (cota = tope del ACERO), el ECS
  (capacidad min(vfrac − α_s, α_g + α_sl)) y el colapso (hueco 1 − α_l): el
  solape escoria/chatarra lo resuelve `slag_condensed_sort` al inicio del paso
  (corre después de los tres), que sube la escoria desplazada y audita el gas
  como el volfix. El ECS lleva un presupuesto por columna (gas libre desde la
  base menos el piso de poro): nunca sobrellena, lo que no cabe queda
  pendiente. Si aun asi una columna no cabe hasta el techo (cesta 2 que llega
  al techo, FeO en columna sin gas), el sort compacta con las capacidades
  escaladas por el sobrellenado, avisa `[SLAG] AVISO` (el harness falla) y
  queda Σα > 1 que el transporte recortaria: es un estado de error, no un
  régimen. Tests: casos condensados de `test_charge_slag`,
  `test_ecs_feed` y `test_scrap_collapse`.
