## Revisión de cierre WS-K1, ronda 1 (auditor-eaf3d)

**Veredicto: aprueba.** Sin hallazgos ALTO ni MEDIO. Quedan 3 hallazgos BAJO, todos de redacción y ninguno bloqueante.

Alcance. El diff staged no tiene código: no toca `src/`, `tests/`, `scripts/research` ni los hooks. Solo cambia `.claude/rules/acople-pv.md`, `docs/PLAN_K_limitador_en_poisson.md`, `research/ws/WS-K1/status.json`, el reporte y las revisiones. Conforme a la regla de revisión ciega, no leí las revisiones. Lo que audité fue cada afirmación sobre código y datos de los dos textos staged, contra el código, los parches archivados y los CSV/HDF5 en disco. Todo fue de solo lectura: no compilé ni corrí nada.

### Hallazgos

**ALTO:** ninguno.

**MEDIO:** ninguno.

**BAJO**

1. **B-1. El §6 del plan contradice la entrada de reglas.**
   - Dónde: `/Users/frariv/Horno/hornofusion-full3D/docs/PLAN_K_limitador_en_poisson.md:100-101`.
   - Defecto: dice «medida solo en k1pa_342». La entrada staged de `acople-pv.md` dice «MEDIDA en k1_342 (v1 …) y en k1pa_342».
   - El reporte agrava la confusión: su bullet «ciclo 8» dice que esa corrección y las de D2.2b/D2.2c entraron «en la entrada … y en el §6». El §6 no tiene ninguna de las dos.
   - Escenario: quien lea solo el plan cree que la desaparición del ciclo descansa en una sola corrida.
   - Recomprobado: k1_342 y k1pa_342 dan las mismas métricas en la sonda (osc2 209.5, ag_min 0.01834, alternancia_dp 0.000).
   - Arreglo: corregir el §6, o acotar el bullet del reporte a lo que el §6 contiene.

2. **B-2. «sin entrada no enlazada» describe `unl_on` a medias.**
   - Dónde: `acople-pv.md` (entrada staged) y `PLAN_K:102`.
   - En el código (`research/ws/WS-K1/plan_k_v2.patch:212-217`), `unl_on` lleva `ws_pc_unl > 0` a `qin` y `ws_pc_unl < 0` a `qout`.
   - Escenario: si la fuente neta es negativa, P-a quita crédito de salida, así que s baja y hay MENOS holgura. La inferencia del punto 5 del reporte solo trata el caso > 0.
   - Arreglo: «sin la fuente no enlazada (entrada si > 0, salida si < 0)».

3. **B-3. El §6 atribuye «v2» a la firma del audit, que no lo distingue.**
   - Dónde: `PLAN_K:107-108`.
   - La firma excluye A2, pero no excluye v1 con otra `pc_ai_tol`. k1_340 no fija la tolerancia y k1pa_340_* fija 1e-3.
   - Lo único que separa a k1pa de v1 es [PROBE-P] «pp tras conjunto activo», y eso solo existe a 342 s. La parte «v2» viene de la declaración de C-040.
   - La entrada de reglas lo redacta bien («variante con HOLGURA»), y la conclusión operativa no cambia.
   - Arreglo: aclararlo en el §6.

### Verificado como correcto (no re-auditar)

**Compuerta**
- `diff_sha` = e3b0c442…b855 es el SHA-256 del diff vacío. Es coherente: no hay nada staged en `GATED` (`scripts/research/ledger.py:343-350`).
- `estado = en_revision` es un estado válido (`ledger.py:40`).

**Configuración y código actual**
- `src/mod_config_3d.f90`, defaults: `pc_limiter_faces` false en :91, `pc_liq_sealed_wall` false en :92, `pc_transport_f28` true en :110.
- La incompatibilidad B21-F1 está en :603-607, y `require` termina en `stop 1` (:625-627). bench_d22c salió con exit 1, así que «aborta en la configuración» es correcto.
- `src/mod_pressure_3d.f90:1769-1795`, `face_lim`: en HEAD solo existe el cierre BINARIO D2.2c. El escalado continuo D2.2 ya no está.

**Parches archivados y 1bc9832**
- `plan_k_v2.patch:155`: condición de `unl_on`.
- `plan_k_v2.patch:310-325`: `acc_face`. El factor incluye α_nb/a_f y ρ̄/ρ_i.
- `plan_k_v2.patch:220`: s = min(1, max(0, cap + qout)/qin).
- `pa_sin_A2.patch`: cambia exactamente dos cosas, el factor a 1 y `unl_on = .false.`.
- `git show 1bc9832:src/mod_continuity.f90`: la fuente E2 se invalida tras `solve_alpha_bounded_implicit` (:277) y solo se valida con `ws_Fc_valid` (:863-868).

**Firma del audit (recalculada con csv)**
- k1b_342 y k1pb_342 frente a k1_342: Δvol_lim −4.484e-7 en 342451, y entre −3e-7 y −4e-6 en 342451-342456.
- k1pa_342 frente a k1_342: +1.35e-9 en 342451, y Δvol_unlinked positivo desde 342452.
- k1pa_340_n12, n14 y n15 frente a k1_340: idénticos entre sí. Δvol_lim de +7.13e-9 a +9.6e-8 en 340001-340006, y Δvol_unlinked > 0 en esos pasos.
- base_340_n14 frente a judge_otp_280: diferencias ≤ 3e-16.

**Métricas regime2 (p>100k)**
- 342-344 s: K 1.4-2.4 % frente a 7.2-10.3 % de la base.
- 344-345.3 s: K 6.4/6.6/9.0/15.1 % frente a 20.8-35.2 % de la base.

**Sonda (10,60,2)**
- osc2 885.7 (k1b) frente a 889.7 (k1pb).
- Fracción de pasos con |d2p| > 1000 Pa: 0.847 en la base, 0.475 en k1b y k1pb, 0.22 en k1 y k1pa.
- ag_min: 0.01500 con tope exacto, 0.01834 con holgura.

**Plan D (dev-history 2026-10-07)**
- D2.2: 15.2/8.1 % y 11.2/4.7 %.
- D2.2c: 17.1/15.1 % frente a 4.9/4.4 %.
- La malla 12×24×16 y la conclusión «NO se transfieren a B1» (:424-425) coinciden con lo citado.

**Registro (ledger)**
- C-031 (k1 min 0.0183), C-037, C-039, C-040 (declara el binario v2 + pa_sin_A2), C-041, C-091 (d22b/d24 refutadas, d22c FALLIDA) y C-294 (C-064 fallida) coinciden con lo que cita la entrada.

**Vigencia**
- Hay 7 commits en `src` desde 1bc9832.
- Verifiqué por lectura de código que 79dc27b, que el reporte marca como «no reverificado», solo escribe arrays de diagnóstico en `mod_pressure_3d`; no cambia aP, Su ni coeficientes. Los arrays nuevos se alocan con `mold` y se inicializan a 0.
- 4d8570a y 1de144e también son solo diagnóstico en `mod_continuity`, `mod_pressure_3d` y `mod_properties_3d`. 1de144e solo evalúa la misma expresión en un temporal.
- Con esto, la etiqueta VIGENTE de la ruta base se sostiene.
- `pc_alpha_implicit`: 0 archivos en `src/`.
- `git apply --check` falla en `mod_pressure_3d.f90:733`.

**Referencias**
- Las líneas citadas de `acople-pv.md` (266-274, 536-546, 560-566 y 611-617) son correctas en la versión staged.

### Orden sugerido de corrección (uno por uno, no bloqueantes)
1. B-1: alinear el §6 del plan con la entrada de reglas, o corregir el bullet del reporte.
2. B-2: redactar `unl_on` como fuente no enlazada de los dos signos.
3. B-3: en el §6, separar «sin A2 (firma)» de «v2 (declarado en C-040)».
