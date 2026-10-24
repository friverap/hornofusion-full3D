## Revisión del refutador WS-K5, ronda 1 (relectura del reporte corregido)

### Qué verifiqué (solo lectura; python únicamente para leer datos que ya existían)
- Corrí `check_audit.py` sobre `campaigns/b1/k5_mo20`, `campaigns/b1/k5_base`, `tests/out/cold_bucket2_slag_n1` y `tests/out/arc_slag_n4`. Coinciden todas las cifras del reporte:
  - libre, multi y outlet;
  - EOS, venteo y volfix;
  - cierre −6.14e-14 y −7.09e-14 kg;
  - el AVISO sale en cold_bucket2_slag_n1 y no sale en k5_mo20 ni en arc_slag_n4;
  - arc_slag_n4 da multi −1.067 frente a EOS −1.097.
- Bit a bit: las 87 columnas comunes de `audit.csv` son idénticas entre k5_mo20 y sonda_gc_mo20, y entre k5_base y sonda_gc_base, en los 60 renglones. `m_gas_cells_skip` vale 0 en las dos.
- En test_full.txt hay 3 bancos con «sin balance por celda en N de N» (líneas 1109, 1289 y 2147).
- Corrí el check_audit actual sobre los 60 directorios de tests/out: ningún traceback y 14 AVISO.
- `docs/AUDIT_COLUMNS.md` y `.claude/rules/transporte-energia.md` ya dicen que e incluye el volfix y que multi solo se lee como masa reescrita donde |volfix| << |multi|.

### 1. Conclusiones y sus alternativas

**C1. El cambio es solo de diagnóstico y no altera la numérica.**
- Alternativa: las llamadas nuevas (inicio de paso y después del `update_properties` final) cambian el estado.
- Qué las separa: comparar todas las columnas del audit con una corrida sin el cambio.
- Está en los datos: 87 columnas idénticas frente a sonda_gc_* y test-full OK con golden v131.
- Limitación: sonda_gc es a su vez un binario de sonda. El golden v131 cubre la referencia sin sonda en los bancos de test.
- Resultado: se sostiene.

**C2. Identidad de cierre EOS − celdas − venteo + volfix = 0 al redondeo.**
- Alternativa: el cierre es algebraico y no prueba que la medida sea correcta.
- El reporte ya lo admite (K5-R3) y no apoya ninguna conclusión física en la identidad.
- Resultado: se sostiene como prueba de consistencia, que es lo único que afirma.

**C3. La escoria ya entra en la clase multifase.**
- Alternativa: el valor de arc_slag cambió por otra razón.
- Qué las separa: comparar antes y después en el mismo banco. Antes daba −9.7e-18 en multi; ahora da −1.067 frente a EOS −1.097, con libre −1.1e-2.
- Hay un test unitario con 3 casos de escoria.
- Resultado: se sostiene.

**C4 (ya no se afirma). El piso está en el complemento α_g.**
- El reporte lo deja como hipótesis abierta junto con la alternativa de las caras con lk = 0.
- Retira «libre conserva» y declara que ninguna conclusión numérica se apoya en `m_gas_err_multi`.
- Ese era el punto bloqueante de K5-R1 a K5-R4, y queda resuelto en el texto.

### 2. Repeticiones de fracasos registrados
No hay ninguna. El cambio es instrumentación pura: no toca el limitador del Poisson (D2.2), ni las reglas D/E/F/G, ni n_pc_max. No mueve el problema de sitio porque la numérica es idéntica.

### 3. Sitio de medida
B1 se mide con una sola ventana de 59 pasos en 280 s. El reporte lo declara y exige reportar el volfix en una ventana de 340 s. Para una herramienta de diagnóstico eso basta. No serviría como prueba de mecanismo, y el reporte no lo usa como tal.

### 4. Objeciones (ninguna bloqueante)
- **K5-R5.** El comentario de `src/mod_audit.f90` (~175-180) sigue afirmando el mecanismo como hecho («ahi solo queda la convergencia del lazo externo»; «el complemento crea gas...») y omite la escoria en la definición de libre. Contradice la retirada de K5-R2. Se resuelve reescribiéndolo en condicional, sin corrida.
- **K5-R6.** test_full.txt es anterior al AVISO de check_audit. El reporte dice 18/64 y el script actual da 14/60 directorios. Ya comprobé que el script no falla en ningún directorio. Falta explicar la diferencia de cuentas o regenerar el log en el próximo test-full.
- **K5-R7.** La regla presenta como «Hecho medido» lo que sale de una sonda no commiteada (C-110, en propuesta). Hay que citarlo como exploratorio.

Rechacé la versión anterior del reporte por K5-R1 a K5-R4. El texto corregido ya no afirma más de lo que miden los datos. Las objeciones que quedan son de redacción en comentarios y de trazabilidad de una cuenta.

VEREDICTO: aprueba