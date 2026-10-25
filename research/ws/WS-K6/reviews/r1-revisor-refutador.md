## Revisión refutadora: WS-K6, ronda 1

Revisión de solo lectura. Leí el reporte, C-110 y C-116 a C-119, el diff de `src/`, el diff de `check_audit.py`, `research/ws/WS-K6/logs/test_full.txt` y los `audit.csv` de `campaigns/b1/k5_*`, `k6_*` y `sonda_gc_*`. No leí las revisiones de los otros revisores.

### 1. Conclusiones, hipótesis alternativas y dato que las separa

**(1) «La numérica es idéntica; el cambio es solo de diagnóstico.»**
- **Alternativa:** la referencia sonda_gc_* salió de binarios de sonda temporales (C-110). Si la sonda hubiera alterado algo, la igualdad contra ella no probaría igualdad contra la línea base commiteada (k5).
- **Dato que las separa:** comparar k6 con k5 en todas las columnas. **Ya está en los datos.**
  - k5_mo20 y sonda_gc_mo20 son idénticos en las columnas comunes.
  - k6 frente a k5 solo cambia en m_gas_err_free, m_gas_err_multi y m_gas_err_abs (59 filas, cambio esperado) y en el último bit de m_gas_volfix (15 filas, |Δ| ≤ 5e-23 kg; la suma de las 60 filas es idéntica).
  - La conclusión se sostiene. La explicación del último bit (orden de suma con -O3) no está verificada (K6-R2).

**(2) y (3) «El cierre EOS − celdas − venteo da redondeo y el volfix por celda está completo.»**
- **Alternativa A:** el check es una identidad, porque los dos acumuladores reciben el mismo dm. Pasaría aunque una ruta no se ejerciera nunca.
- **Alternativa B:** se registran índices globales en vez de locales, o celdas fantasma. Eso deja bien la suma y reparte mal por celda.
- **Dato que las separa:**
  - Para B: las columnas por celda deben ser invariantes a la descomposición. **Está en los datos:** cold_bucket2_slag n1 = n9, ecs_slag n1 = n9 = n12 y cold_10step n1 = n4 = n8 = n12 coinciden a 4 cifras. B queda descartada.
  - Para A: hace falta saber qué ruta aporta en qué caso. **No está.** Hay casos donde el check es vacuo: volfix 0.0, −2.1e-15 en slag_rest y −3.0e-14 en el reinicio cold_bucket2_slag_s15. Ver K6-R1.

**(4) «El volfix salió de la columna multifase.»**
- **Alternativa:** que el cambio en multifase venga de otra cosa, como el reparto de clases.
- **Dato que las separa:** Δmultifase debe ser igual al volfix. **Lo es:**
  - cold_bucket2_slag_n1: −1.739 − (−1.722) = −0.017, frente a −0.0173 medido;
  - cold_bucket2_n4: −10.40 − (−10.466) = +0.066, frente a +0.0626 medido.
- **Salvedad:** en cold_bucket2_n4 el gas libre (−0.653 kg) y el outlet (−17.26 kg) siguen siendo grandes frente a la EOS (0.756 kg). Multifase sola no es «el piso» en las cargas de cesta (K6-R3).

**(5) «En B1, el volfix es el 1.5 % de la columna y la lectura no cambia.»**
- **Alternativa:** que el término que falta sea grande en otro sitio.
- **Dato que las separa:** sumas de k5/k6_mo20. **Verificado:**
  - multifase pasa de −8.685537e-4 a −8.554925e-4;
  - libre pasa de 2.17937e-5 a 2.18346e-5;
  - m_gas_vf_cells = m_gas_volfix = −1.3102e-5;
  - outlet no cambia.
- El inciso (5) de C-117 queda refutado en la letra, sin enmienda posterior. Eso es correcto y no afecta la lectura.
- Otros términos que siguen en e, como m_gas_ccdrop (8.3e-6) y m_alpha_clip (1e-12), son del orden del 1 % o menos.

### 2. Repeticiones de fracasos registrados

Ninguna. Es instrumentación de auditoría y no cambia la física. No toca el acople p-v (D2.2 / Plan K), ni la clasificación D/E/F/G, ni n_pc_max. Tampoco mueve el problema de sitio: los campos, los inventarios, p_max y u_gas_max son idénticos bit a bit.

### 3. Objeciones (ninguna bloqueante)

- **K6-R1. Cobertura por ruta no demostrada.**
  - El check `mass_gas_vf_cells` solo detecta una ruta que no registra su celda si esa ruta se ejerce.
  - **Lo que lo resuelve:** una tabla de qué caso de test-full ejerce cada una de las 6 rutas con volfix no nulo. Si alguna no se ejerce en ninguno, reformular la frase «falla si una ruta no registra su celda».
- **K6-R2. El último bit de m_gas_volfix se atribuye a -O3 con un «probablemente».**
  - **Lo que lo resuelve:** verificarlo (ensamblador o -O0, fuera de esta revisión) o declararlo no verificado.
- **K6-R3. El inciso (4) solo cita multifase.**
  - **Lo que lo resuelve:** citar también las columnas libre y outlet de cold_bucket2_n4 y cold_bucket2_slag_n1, que ya están en el log. Así se evita que una lectura posterior tome multifase como el piso en las cargas de cesta.

### Archivos
- /Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K6/report.md
- /Users/frariv/Horno/hornofusion-full3D/src/mod_audit.f90 (audit_volfix_cell, audit_gas_cells)
- /Users/frariv/Horno/hornofusion-full3D/tests/integration/check_audit.py
- /Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K6/logs/test_full.txt
- /Users/frariv/Horno/hornofusion-full3D/campaigns/b1/k6_mo20/audit.csv y k5_mo20/audit.csv

VEREDICTO: aprueba