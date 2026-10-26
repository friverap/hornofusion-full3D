El veredicto es **rechaza**, por un solo hallazgo MEDIO de documentación (M1). En el código Fortran del diff no encontré defectos ALTO ni MEDIO.

# Revisión r1, auditor-eaf3d: WS-K7, panel de cierre, ronda 1

**Veredicto: RECHAZA** (M1 es bloqueante).

Alcance: revisé el diff staged de `src/`, `tests/integration/check_audit.py`, `Makefile`, `docs/AUDIT_COLUMNS.md`, `scripts/make_audit_glossary.py` y `.claude/rules/transporte-energia.md` contra `research/ws/WS-K7/report.md` y el registro (C-149). Solo lectura, sin compilar. No leí `reviews/`.

## 1. Hallazgos

### MEDIO

**M1. La regla y el glosario conservan afirmaciones que el reporte ya retiró** (bloqueante)

**Regla, `/Users/frariv/Horno/hornofusion-full3D/.claude/rules/transporte-energia.md:221-224`**
- Dice «err_liq es en un 99.9 % el desajuste en caras ENLAZADAS». Esa cifra se retiró en la ronda 9 (E2, {C-147}); el valor vigente es «≤ 0.2 % de Σ|err_liq_all|, 2 % del neto».
- Dice «la entrada enlazada rechazada por el limitador (`m_gas_rej_nogas`) es 1.6× Σ|e| ahí». Esa lectura se retiró en la ronda 9 (R1, {C-148}): rej es un estimador bruto y no se interpreta.
- Contradice la línea 187 de la misma regla, que dice «su 1.59 no se interpreta».

**Glosario, `/Users/frariv/Horno/hornofusion-full3D/docs/AUDIT_COLUMNS.md:121` y `/Users/frariv/Horno/hornofusion-full3D/scripts/make_audit_glossary.py:255-257`**
- El script regenera `paper/tables/audit_glossary.tex:126`.
- La entrada de `m_gas_veff_abs_nogas` dice «veff/vpois << 1 there means ... limiter rejection, the Plan E valve».
- Eso se retiró en la ronda 8 (R2) y la ronda 9 (R1/R2), {C-146}{C-148}: en las nogas el cociente es ≈ 0 por construcción y no se mide si la celda es ciega o de paso.
- Contradice además el INFO de `check_audit` («0 por construccion en celdas llenas»).

**Secundario: `m_gas_err_rem_abs`**
- Se describe como «what hypothesis C-110 does NOT explain» (AUDIT_COLUMNS.md:104, make_audit_glossary.py:207-208, regla:160).
- El reporte declara que 1 − rem/abs no es atribución de mecanismo.

**Escenario de fallo**
- La regla se carga sola al tocar continuity o audit. Una sesión posterior tomaría «99.9 %» y «el limitador rechaza 1.6×» como hechos y planificaría sobre la válvula de Plan E o E1b, que es lo que {C-148} prohíbe.
- El glosario del artículo publicaría la lectura retirada.
- La ronda 10 del reporte afirma que la regla quedó «reescrita con la lectura de {C-147}{C-148}», y no es del todo así.

**Arreglo**
- Sustituir las tres frases por su forma vigente.
- Regenerar el glosario.
- Comprobar con grep que no quedan «99.9», «rechazada por el limitador» ni «Plan E valve».

### BAJO

**B1. Citas de línea que no corresponden al diff staged.** El reporte dice «en el diff en revisión del 25-oct», pero los números no coinciden. Comprobé por grep que el contenido citado existe en ambos casos.

| Archivo | Cita del reporte | Línea real en el diff staged |
|---|---|---|
| `mod_audit.f90` | :872-888 | :899-915 |
| `mod_audit.f90` | :967-968 | :995-996 |
| `mod_audit.f90` | :998 | :1036 |
| `mod_audit.f90` | :1005-1047 | :1045-1112 |
| `mod_audit.f90` | :1015 | :1053 |
| `mod_pressure_3d.f90` | :209 | :210 |
| `mod_pressure_3d.f90` | :813-835 | :832-849 |
| `mod_pressure_3d.f90` | :649 | :652 |
| `mod_pressure_3d.f90` | :663-667 | :664-672 |
| `mod_pressure_3d.f90` | :1220 | :1237 (cara oeste :1203) |
| `mod_pressure_3d.f90` | :1243 | :1260 |
| `mod_pressure_3d.f90` | :767 | :784 |
| `mod_pressure_3d.f90` | :231-233 | :235-237 |
| `mod_pressure_3d.f90` | :1730-1734 | :1747-1751 |

En `mod_pressure_3d.f90` el reporte usa la numeración de HEAD, con un desfase de +17. Arreglo: actualizar las citas o declararlas como numeración de HEAD.

**B2. Glosario de `m_gas_e2_nolink` impreciso** (make_audit_glossary.py:237).
- Dice «E2 of the LAST transport, i.e. what would have been added».
- El último Poisson habría sumado la del transporte N−1; la columna lee la del transporte N (`mod_audit.f90:1068-1069`). El comentario del código sí lo dice bien.
- Peso nulo: la clase nolink está vacía en todas las ventanas medidas.
- Arreglo: «approximately (transport N; the Poisson saw N−1)».

**B3. Orden de SRCS en el Makefile** (ya declarado en el reporte).
- `mod_probe.f90` está después de `mod_audit.f90`, que ahora usa `mod_probe`.
- No rompe nada: la regla explícita de `mod_audit.o` cubre la dependencia y el orden del enlace no importa.
- Arreglo: commit aparte, como ya declara el reporte.

### No verificado (objeción, no bloqueante)

**U1. Identidad byte a byte de los binarios.**
- No pude comprobar «`make clean && make opt` ⇒ cmp idéntico a `campaigns/bin/eaf3d_k7v5_opt`»: no puedo compilar, y `bin/eaf3d_mpi` es hoy el build -O2 con chequeo de límites (2.31 MB frente a 1.25 MB del opt).
- Indicios compatibles:
  - El encabezado CSV del binario k7v5 coincide con el actual.
  - El único fuente modificado después de ese binario es `mod_audit.f90` (16:57:25).
  - `obj/.fflags` cambió a las 16:58:18.
- Tampoco verifiqué que `make debug` arranque.
- Lo que lo resolvería: guardar la salida del cmp o el sha256 de ambos binarios en `research/ws/WS-K7/logs/`, más un arranque de `make debug` de un paso.

## 2. Verificado como correcto (no volver a auditar)

**Identidad `mass_gas_rewrites`**
- Cobertura completa entre el modo 0 (`main_3d.f90:337`) y el modo 1 (`:795`):
  - complemento en `mod_continuity.f90:808/1237/1687`;
  - EOS en `mod_properties_3d.f90:42-45`;
  - rutas de volfix ya cubiertas.
- Las escrituras sin gancho son solo de inicialización, de reinicio (antes del lazo) o en cell_type 0, que quedan fuera del inventario y de las sumas.
- La suma es telescópica y exacta: el complemento usa el ρ vigente y la EOS el α vigente. Las columnas `_abs` son por llamada a propósito.

**MPI y halos**
- Los ganchos y el modo 1 solo tocan celdas propias.
- `mg_*` se anulan completos; `mg_ag0` y `mg_ini` se leen solo en celdas propias, así que no hay Bug 22.
- No hay dummies de arreglo nuevos.
- Los halos de `ws_Fc*`, `ws_Fc_lk*`, `ws_Fr/Fth`, `ws_Fz` (después del derrame), `ws_lim_step` y `ws_pc_unl` se intercambian.
- Los contadores de skip los suma solo el rank 0, y los flags que los deciden son colectivos.

**`ws_pc_unl_used`**
- Se anula al empezar cada Poisson, se escribe donde se suma E2 a Su, y vuelve a 0 en filas inactivas o selladas y donde Su = 0 tras las BC.
- Solo lo lee el audit, así que la numérica no cambia.

**Reparto de err_liq**
- El último Poisson se ejecuta antes del último transporte, también con el lazo `n_pc_max`.
- El reparto `el_lk = el − el_unl` es exacto, porque `unl_vol` se construye con los mismos Fw..Ft y el mismo ρ_l de la celda.
- Las fórmulas de vp, ve, vin y rej tienen el signo y las unidades correctos.

**Mecanismo de R6 en el código**
- `af = 0.5·(aef(P)+aef(vecina))` en `mod_pressure_3d.f90:1203/1237/1286…`.
- `Fg = af·u_f·A` en `:1260`.

**CSV y checker**
- Encabezado y write: 24 columnas nuevas en el mismo orden, y el formato con repetición 200 alcanza.
- `check_audit.py`: filtra las filas con `m_gas_liq_skip = 0`; las guardas n/a y las divisiones están protegidas; `mass_gas_rewrites` tiene sus variables definidas y tolerancia por llamada.

**Sin estado nuevo entre pasos y Makefile**
- No hay estado nuevo que tenga que entrar al snapshot de reinicio.
- El Makefile no tiene ciclos de dependencias.

**Gate y tests**
- El `diff_sha` de `status.json` coincide con el sha256 del diff staged de `src/` y `tests/`.
- Los logs son posteriores a la última edición del fuente: unit, quick y full OK, golden v131 con error 0, y `mass_gas_rewrites` con 67 PASS y 0 FAIL.

## 3. Orden sugerido de corrección (uno por uno)

1. **M1:** regla líneas 160 y 221-224; glosario de `m_gas_veff_abs_nogas` y `m_gas_err_rem_abs`; regenerar el glosario y verificar con grep.
2. **B2:** glosario de `m_gas_e2_nolink`, en la misma regeneración.
3. **B1:** citas de línea del reporte.
4. **U1:** guardar la evidencia del cmp y el arranque de `make debug`.
5. **B3:** orden de SRCS en un commit aparte, como ya está declarado.
