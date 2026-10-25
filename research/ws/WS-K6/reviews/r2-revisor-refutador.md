# WS-K6, ronda 2: revisión del refutador

Desde la ronda 1, el reporte solo incorporó C-119, la corrección del conteo de cierres (64 en vez de 58) que pidió el revisor de evidencia. Mis tres objeciones de la ronda 1 siguen sin atenderse. Las mantengo y ninguna es bloqueante.

## 1. Conclusiones, hipótesis alternativas y dato que las distingue

| Conclusión | Hipótesis alternativa | Dato que las distingue | ¿Está en los datos? |
|---|---|---|---|
| (1) La numérica es idéntica; ninguna cuenta física cambia | El código compilado de las rutas cambió (FMA o eliminación de subexpresiones comunes al duplicar dm) y eso puede derivar el estado | Comparar todas las columnas de audit.csv entre k5 y k6 | Sí. Solo cambian m_gas_volfix (15/60 renglones, al ULP) y m_gas_err_* (por diseño). El estado no cambia, pero el binario sí cambió (K6-R1). |
| (2) Cierre EOS − celdas − venteo en los 64 casos | Que el cierre sea una identidad algebraica y no pruebe nada | Es una identidad por construcción. Lo que sí aporta es que no aparezcan términos sin contar | Se cumple en los 64 casos. Es una prueba de consistencia, no de física. |
| (3) Volfix completo | El check suma dos veces el mismo dm, así que no detectaría una ruta sin AUD_GAS_VOLFIX | Cuántas evaluaciones tienen volfix ≠ 0 | 49/64; en las otras 15 el PASS no prueba nada (K6-R2). |
| (4) Volfix fuera de la columna | Que la reescritura de la EOS se reparta entre libre y multifase según el caso | Reparto libre/multi en cold_bucket2_n4 y en el banco grande | Sí: en esos casos domina el gas libre, al revés que en B1 (K6-R3). |
| (5) Refutada por la letra del criterio | Que la diferencia física sea real | Diferencia contra el valor exacto de k5: 1.306e-5, que es el volfix multifase | Explicada. Correcto no enmendar. |

## 2. Repeticiones de fracasos registrados

Ninguna. El cambio es solo de diagnóstico y no actúa sobre el campo.

## 3. Objeciones

- **K6-R1 (se mantiene, no bloqueante).** m_gas_volfix cambia al ULP en 15 de 60 renglones (k5 frente a k6, mo20 y base). Se resuelve de una de dos formas: el reporte lo declara, o se pasa la misma variable dm a audit_add y a audit_volfix_cell.
- **K6-R2 (se mantiene, no bloqueante).** La cobertura real es de 49 de 64 evaluaciones con volfix ≠ 0. El check mide consistencia, no completitud. El reporte debería decirlo.
- **K6-R3 (se mantiene, no bloqueante).** Sin volfix, el reparto entre libre y multifase depende del caso: en cold_bucket2_n4 queda −0.653 kg libre contra +0.063 kg multifase, y en el banco grande −13.8 contra −1.12. El reporte debería registrarlo en Incertidumbre (test_full.txt, líneas 683 y 1823) y no extrapolar C-110 fuera de B1 280 s.

Las tres son de precisión del texto. Ninguna invalida la conclusión: el volfix queda separado por celda sin tocar el estado.

VEREDICTO: aprueba