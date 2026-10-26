# Revisión del refutador: WS-K7, ronda 1 de este lanzamiento (ronda 10 del reporte), 25-oct-2026

**Veredicto: rechaza.** Hay una objeción bloqueante (R1): el cambio de la ronda 10 en `check_audit.py` convierte en «n/a» una lectura correcta que va en contra de H, y el reporte y C-149 la describen como «sobre ceros», lo cual es falso. El resto de las objeciones no bloquea.

**Qué leí (solo lectura):**
- `research/README.md`, `report.md` completo, `status.json`.
- Del registro: C-109, C-110, C-120 a C-149, `ledger.py open` y las 32 refutadas o fallidas.
- `.claude/rules/acople-pv.md`: Vigencia, «Lo que NO funcionó», F2.13/16/20/21/24, Planes D/E/F/G, secciones del 22-oct.
- El plan aprobado `iterative-foraging-newell.md`.
- Mi revisión anterior `reviews/r5-revisor-refutador.md`. No leí las de los otros revisores.
- Código: `src/mod_pressure_3d.f90`, `mod_multiphase.f90`, `mod_continuity.f90`, `mod_audit.f90`, `tests/integration/check_audit.py`.
- Datos: `audit.csv` de k7v5_*, k7v4_long y `tests/out`; snapshots 280000, 280059, 280999, 285000 y 285499.

**Qué se atendió de mi ronda anterior:** R1 a R6 y N1 están atendidos en el texto (rondas 9 y 10).

## 1. Conclusiones, alternativa y dato que las separa

**C1. H queda sin decidir por la letra (0.319; neto 1.571) y deriva hacia la refutación en ventanas largas.**
- Verificado: 0.3186 y 1.5705; por subconjunto, nogas 0.163 y con gas 0.384.
- Alternativa: el cociente por celda lo dominan pares internos antisimétricos (la exportación de las nogas y sus receptoras), y err_liq los iguala por la identidad de la fila. El cociente no dice nada del piso.
- Está declarado. Lo afino en R3.

**C2. err_liq es el desajuste en caras enlazadas (desfase E2 = 0.13 % de Σ|e|).**
- Verificado.
- Alternativa: domina α del dador frente a a_f, no el limitador. Ya está declarado como componente no separada. Sin objeción.

**C3. El 29 % de Σ|e| está en nogas.** El reporte lo lee así: es el plan neto del Poisson en celdas llenas (identidad de la fila salvo 16-18 %), por el conducto de la α media más el alcance; tiene el mismo balance de fila que Plan E en otra población; pesa 6-8.5 % de ρ_g·vol_lim y es insensible a las externas.
- **Alternativa A (causa).** El flujo fantasma lo empuja la velocidad atada de F2.20 sobre una cara con α media; la «entrada planeada» es consecuencia de la fila, no su causa. La premisa de F2.21 («charco quieto ⇒ u ≈ 0») falla porque el baño del piso se mueve: u_z del líquido en las nogas, p10 −0.28 m/s y p90 +0.76 m/s. La separa el signo de Fs frente a ws_Fc y ΣF_g por dirección; no está en los datos (Incertidumbre R3 lo declara a medias).
- **Alternativa B (población):** ver R2.
- **Alternativa C (tamaño):** ver R4.
- **Relevancia para el piso:** nula por construcción (R3).

**C4. Composición: todas las nogas son baño en k = 1-3 y el 94-97 % está sobre poro seco.** Verificado: re-ejecuté `nogas_vecinas.py` en 280000 y 280059. Lectura alternativa en R2.

**C5. Sobre el piso neto el WS no concluye.** Hay dos alternativas con datos que el reporte no usa.
- Bancos secos con comp = 0 y e_multi distinto de 0, también con el lazo convergido (R1).
- Una cota del complemento neto: al menos el 48 % del piso de 5.5 s no es complemento (R5).

**C6. Instrumento permanente: identidad de reescrituras, numérica idéntica bit a bit, tests y checker.**
- La alternativa es que el checker esconda contraevidencia: lo hace (R1).
- La identidad byte a byte del binario no es verificable en solo lectura (N1).

## 2. Repeticiones de fracasos registrados

- **Plan E E1, válvula ficticia (acople-pv :456-480).** La repetición está declarada. La diferencia de población que afirma el reporte solo se sostiene contando caras sin dirección (R2).
- **F2.17-F2.21 y F2.24.** El remedio que sugiere la lectura del conducto (α del dador del gas en el Poisson, o quitar el alcance en el piso) sería la sexta regla local de la familia D/E/F/G/F2.31. Choca con cuatro intentos fallidos y con el papel estabilizador del caudal fantasma del gas (F2.24). Antecedentes no lo nombra (R6).
- No se propone ningún remedio, ni D2.2 ni n_pc_max. Correcto.

## 3. Objeciones

- **R1 (bloqueante).** `check_audit.py:359-375` imprime «n/a: sin liquido planeado ni movido» en 12 bancos fríos donde err_liq = 0 y comp_abs = 0, pero Σ|e| multifase vale entre 1.5e-3 y 1.2e-1 kg.
  - Ejemplo: cold_bucket2_n4 tiene e_multi = +6.26e-2 kg en 10 pasos.
  - La salida vieja, «explica 0.000», era cierta, así que «sobre ceros» (report :76 y C-149) es falso.
  - Con «n/a», Σ|e| multifase desaparece de la salida.
  - Esos bancos son la única medida existente de la alternativa su_cc frente a EOS. outer_conv_n8 converge en 20-23 externas y deja ~1e-3 kg/paso con comp = 0.
  - **Resolución:** dejar «n/a» solo para el reparto lk/unl; imprimir «H explica 0.000; Σ|e| multifase X con comp = 0»; registrar un evento con ref C-149; añadir una línea en Incertidumbre. Los datos están en `tests/out/{cold_10step_n4,cold_bucket2_n4,outer_conv_n8}/audit.csv`.
- **R2.** El 96-97 % de las nogas tiene una vecina con gas ENCIMA. Entre esas caras superiores, el poro casi saturado (α_g < 0.02 con líquido) es el 31-38 %.
  - El «7.1 %» incluye en el denominador las caras al poro seco, que están debajo. Que la solera esté en act_g no está verificado, y con e_nogas > 0 esas caras solo serían salida si el gas bajara.
  - **Resolución:** columna −dt·ΣF_g por clase y por dirección, pre-registrada. Mientras tanto, citar «7-19 % de todas las caras; 31-38 % de las superiores».
- **R3.** En 280059, 1213 de las 1214 caras con gas de las nogas dan a celdas multifase, así que la exportación se cancela exactamente en e_multi.
  - **Resolución:** decirlo en el Resultado y retirar la lectura «residuo de una cancelación de ±4e-3» como dato sobre el piso. Lo que se mide en el sitio del piso son el flujo de frontera y comp/eos por conjunto.
- **R4.** El 6-8.5 % usa en el numerador el plan neto, no el volumen rechazado. vol_lim es (1−s)·entrada bruta, y una celda de paso aporta 0.
  - Con el estimador homogéneo rej_nogas, la fracción es 10.1-13.5 %: «minoría» se sostiene, pero hay que reescribir el razonamiento.
- **R5.** Cota: |comp_multi| ≤ (Σ|comp| − comp_neto)/2. En k7v4_long da 0.1165 kg frente a e_multi = −0.2244 kg, así que al menos el 48 % del piso no es complemento neto.
  - En los cuatro bancos el complemento neto es positivo, de signo opuesto al piso.
  - **Resolución:** evento con ref C-110 y la columna comp por conjunto.
- **R6.** Añadir a Antecedentes el remedio implícito y su colisión con F2.17-F2.21, F2.24 y la familia D/E/F/G; exigir el juez estadístico en B1 antes de tocar valores por defecto.
- **N1.** La identidad byte a byte no se puede reproducir: `bin/` se sobrescribió a las 16:58:53. **Resolución:** sha256 de la build opt del diff en el registro, o el log de cmp.

## 4. Verificado

- Cocientes de k7v5_mo20 y k7v5_base.
- Subconjuntos, tamaño y estimador rej.
- Composición, dirección y receptoras de las caras en los snapshots.
- Cota del complemento en los cuatro bancos.
- Bancos fríos y salida «n/a».
- Código del conducto, del alcance, del limitador, de vol_lim, de unl_vol y del audit.

VEREDICTO: rechaza