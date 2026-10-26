# WS-K7, ronda 2: revisión del refutador

**Veredicto: aprueba.** Las cuatro objeciones de la ronda 1 quedan resueltas por texto y registro. Queda una objeción nueva, no bloqueante, que corresponde al coordinador.

Revisión de solo lectura. Lo que comprobé:
- Las sumas de `tests/out/*/audit.csv`.
- `report.md`.
- Los eventos C-163, C-164 y C-165 del registro, y `ledger.py check`.
- `.claude/rules/transporte-energia.md`.

## 1. Conclusiones, hipótesis alternativa y dato que las separa

| Conclusión (estado tras la ronda 18) | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| Veredicto de {C-145}: «sin decidir» por la letra (0.319; neto 1.57) | Con el CG convergido, el inciso por celda cruza 0.7 y H queda refutada | k7v5_mo20 con `max_inner_pres` 200 | No. El reporte declara ahora que el «sin decidir» **no resiste a la refutación** y que los bancos convergidos abarcan las tres bandas (0.134–1.007). Lo recalculé y coincide. |
| El término nogas existe con el CG convergido | Artefacto del CG truncado en la población de B1 (baño sobre poro seco) | Identidad de fila con el CG convergido en esa población | No. El reporte restringe la conclusión a «otra población» ({C-164}): 0 % de las nogas sobre poro seco en los bancos, frente al 96.6 % en B1. La alternativa queda declarada como intacta. |
| La población no es la de Plan E | La válvula actúa en el subconjunto con gas, que las nogas excluyen por definición | Columnas por clase dentro del subconjunto con gas | No. El reporte lo declara ({C-165}, :384). El confusor temporal 280/320 s está descartado con datos (80.5 % sobre poro seco a 320 s). |
| K7 aporta un instrumento y no propone remedio | — | — | No hace afirmación de mecanismo que refutar. |

## 2. Repeticiones de fracasos registrados

No hay repeticiones. K7 es un diagnóstico y no propone remedio. Los remedios que sugeriría H ya figuran como negativos y el reporte los lista:
- E1b `pc_sat_gas_off`.
- Plan K G1/G2 (limitador en el Poisson; D2.2 en Plan D).
- `n_pc_max = 3`.
- F2.31.

El reporte añade la salvedad de vigencia {C-089}.

## 3. Objeciones

- **O1 (resuelta).** El contrafactual 0.279/0.300 queda retirado y se declara que el inciso por celda es frágil en ambas direcciones ({C-163}). Recalculé las cifras desde audit.csv: rem_all/abs 0.620, 0.134, 0.830, 0.868, 1.000, 0.541, 1.007 y 0.964; peso 0.000–0.182; brecha ≤ 0.101. Coinciden.
- **O2 (resuelta).** Se retira «no es solo un artefacto del CG truncado». La conclusión queda restringida a otra población, con la alternativa declarada ({C-164}).
- **O3 (resuelta).** Se declara la exclusión por definición de la válvula ({C-165}).
- **O4 (resuelta).** {C-164} lleva ref C-158. `ledger.py check`: OK, 165 eventos.
- **O5 (nueva, no bloqueante, coordinador).** `.claude/rules/transporte-energia.md` sigue con las dos frases retiradas:
  - :184 cita todavía el contrafactual «0.279 si bajara…».
  - :212 dice «su población es otra» sin el matiz de definición.

  Quien consulte la regla leerá lo que el reporte ya retiró. **Resolución:** que el coordinador edite :182-185 y :211-213 para alinearlos con {C-163} y {C-165} antes de cerrar WS-K7.

## Pendientes para decidir H (no bloquean el cierre del reporte tal como queda redactado)

Siguen sin medirse; el reporte las declara como pendientes, no como resueltas:
- k7v5_mo20 con `max_inner_pres` 200, pre-registrado.
- Un banco con baño sobre poro seco y el CG convergido.
- Columnas por clase de poro saturado.

VEREDICTO: aprueba
