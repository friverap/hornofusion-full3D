# WS-K9 — Revisión del refutador, ronda 2

Revisé de nuevo report.md, C-198 a C-201 y el bloque cambiado de `src/mod_audit.f90` (líneas 796-912). También comprobé el uso de `ws_Fg_valid` en src/, el `audit.csv` de `cold_flow_noenergy_n4` y lo que dicen tests/README.md y `.claude/rules/transporte-energia.md`. Fue solo lectura: no ejecuté ni compilé nada.

## 1. Conclusiones, alternativas y dato que las separa

**C1. El defecto: `m_gas_out` = 0 cuando solve_energy = false (C-198, C-201).**
- Alternativa: el FAIL del binario previo vendría de otra diferencia entre binarios o configuraciones, no de la guardia.
- Dato que las separa: C-201 fija el contenido del binario previo por hash (src de 79dc27b). La config solo difiere en el comentario y en output_dir. El código muestra que antes la acumulación de AUD_GAS_OUT estaba bajo gas_energy_on.
- Resultado: queda **descartada**.

**C2. El arreglo da el venteo correcto, no solo uno coherente con el cierre.**
- Alternativa: con la energía apagada, `ws_Fg` estaría obsoleto o sin calcular. El venteo saldría por `face_mass_fluxes`, que A4-6 declara distinto de los flujos de la ecuación, y el cierre pasaría por tautología.
- Dato que las separa: `ws_Fg_valid` se activa en `mod_pressure_3d.f90:881`, que no depende de la energía, y se apaga en `main_3d.f90:586`. Por tanto el venteo usa los flujos del Poisson.
- Contraste independiente (ya en los datos, R3): `m_gas_err_out`, el balance por celda de las celdas de salida, que sale de otro camino de código, vale −`m_gas_out` en los 10 pasos, también cuando cambia el signo (pasos 5 a 9).
- Resultado: queda **descartada**.

**C3. Sin cambio numérico con la energía activa.**
- Alternativa: el golden solo cubre un subconjunto de métricas, y una columna de audit.csv fuera del golden podría haber cambiado.
- Dato que las separa, primero el código: gas_mass_on es un superconjunto de gas_energy_on, y la entalpía (`srcacc(17)`) sigue bajo `if (gas_energy_on)`. Con la energía activa, el camino es literalmente el mismo, y `main_3d` solo añade impresiones.
- Dato que las separa, después los datos: v131 contra el test-full da 60 PASS con err rel 0. El diff de las líneas de check entre los test_full.txt de WS-K8 y WS-K9 solo difiere en el banco nuevo (R1).
- Resultado: queda **descartada**.

**C4. El registro del binario cierra la O4 de WS-K8.**
- Alternativa: una ruta relativa no identifica el contenido del ejecutable.
- Resultado: queda **en pie**. El reporte lo admite (R5).

**¿Se mide en el sitio que importa? ¿Se mueve el problema de sitio?** Es instrumentación de auditoría, no física, así que B1 no está en juego. El banco de 10 pasos casi en reposo ejerce el camino del código, no un venteo fuerte, y el reporte lo declara. No sube ninguna otra columna: `mass_gas` ahora compara contra un venteo distinto de cero, y el resto de los 60 bancos queda igual.

## 2. Repeticiones de fracasos registrados

Ninguna. El cambio no toca el limitador del Poisson (D2.2), ni las reglas de clasificación D/E/F/G, ni n_pc_max. Es una guardia de contabilidad.

## 3. Estado de las objeciones (ninguna bloqueante)

- **R1 (mitigada).** Incertidumbre ya reconoce que la comparación de los 60 audit.csv no distingue código viejo de nuevo, y apoya la conclusión en el golden. Falta citar el diff de los test_full.txt de WS-K8 y WS-K9, que es la evidencia durable para todas las líneas de check.
- **R2 (resuelta).** C-200 corrige el «contra qué» de la comparación.
- **R3 (abierta).** Falta citar `m_gas_err_out` = −`m_gas_out` como medida independiente del venteo.
- **R4 (abierta).** El paso 1 sigue diciendo `audit_write_step`; la subrutina es `audit_accumulate` (`mod_audit.f90:774`).
- **R5 (mitigada).** Falta un sha256 del ejecutable en run.log para cerrar la O4.
- **R6 (abierta).** `mass_gas` (tolerancia relativa 0.5) no detecta un venteo 0 en bancos tranquilos. La única guardia es `mass_gas_flux_closure` en `cold_flow_noenergy_n4`, que solo corre en test-full. Hay que declararlo en Incertidumbre o en tests/README.md.

Ninguna de estas objeciones invalida las conclusiones. R4 y R6 son correcciones de una línea.

VEREDICTO: aprueba