# WS-K8 — El plan del Poisson frente a lo realizado, con el CG convergido

Continúa WS-K7 ({C-168}). Pregunta: ¿el error de masa del gas por celda es el
desajuste entre lo que planeó el último Poisson (líquido, compresibilidad y
almacenamiento de la fila) y lo que realizaron el transporte del líquido y la
EOS? ¿Y cambia el veredicto de la hipótesis del complemento (C-110) cuando el
CG converge? Cambio solo de diagnóstico: la numérica queda idéntica bit a bit
en las columnas físicas.

Ronda 2 (27-oct, coordinador, tras la ronda 1 del panel: el auditor aprueba;
evidencia y refutador rechazan; el redactor corrigió este reporte y registró
{C-177} y {C-178}): el párrafo de WS-K8 de `.claude/rules/transporte-energia.md`
se reescribe con las lecturas corregidas (rem2 mide el cierre de la fila y no
contrasta la EOS; el neto multifase es un desfase constante de −2.17e-5 kg por
paso independiente del CG, lectura que superaron {C-181} y {C-187}; la igualdad de sumas con la entrada por las celdas
de salida se retira como origen; «con 20 externas» en vez de «en B1»;
`alpha_p` cae en err_cc, no en rem2). El coordinador verificó por separado las
mismas cifras y las registró en {C-179} y {C-180}, que duplican a {C-177} y
{C-178} (el registro es append-only: no se borran). Sin cambios en `src/` ni
`tests/`.

Corrección tras el revisor-refutador (O1–O3, 27-oct) {C-181}: (O1) el neto
multifase NO es independiente de la configuración: no depende del CG con 20
externas, pero sí del número de externas (−3.28e-5 kg/paso con 5 externas
frente a −2.17e-5 con 20; −3.60e-5 frente a −2.11e-5 ya en el paso 1, desde
el mismo estado); se retira «vive en un sesgo de la identidad de fila, no en
el CG» como atribución y se nombra el truncamiento del lazo externo como
origen candidato. (O2) se retira corr(e_multi, plan) = 0.93 como evidencia
(sale de la construcción). (O3) «el 0.863 del gas libre es un piso de
conversión» pasa a hipótesis. El párrafo WS-K8 de
`.claude/rules/transporte-energia.md` contenía las tres lecturas retiradas
(«no en el CG», el 0.93 y el «piso de conversión»); el coordinador lo
reescribió en la ronda 3.

Ronda 3 (27-oct, coordinador, tras la ronda 2; párrafo con cifras de B1
corregidas en el ciclo 2: auditor y evidencia aprueban;
el refutador rechaza con O1 bloqueante). Se hizo lo que pedía O1: barrido de
`max_outer` pre-registrado en {C-182} (commit `34be842`, antes de correr) con
el CG convergido desde el mismo reinicio. **Veredicto {C-184}: SOPORTADA, el
desfase neto multifase de rem2 es estructural respecto al lazo externo a
partir de ~20 externas** (−2.105e-5, −2.078e-5 y −2.085e-5 kg en el paso 1
con 20, 40 y 80 externas). Con 5 externas el desfase es mayor que la
meseta: 1.99 veces en el paso 1 y 1.76 de media con CG 1000, y 1.71 y 1.51
con CG 20, que es la config de B1 ({C-183}, corregido por {C-187}). Es una
lectura de bancos que no decidían y no es un reparto aditivo.
El lazo externo no declara convergencia en ningún paso de ningún banco: la
meseta es la del iterado estancado. {C-183} se registró antes del veredicto
con ref a sí mismo; lo corrige {C-185}. Cocientes del barrido en {C-186}.
Sin cambios en `src/` ni `tests/`.

Ciclo 2, ronda 1 (27-oct, coordinador). La ronda 3 del ciclo 1 terminó
`sin_terminar` con tres rechazos (revisiones en `reviews/r3-*`); el usuario
pidió abrir un segundo ciclo. Correcciones: (auditor M1) (1 − fsat)·gadv, el
acarreo y el tope se cancelan en rem2 con `su_cc` y en el gas libre fsat ≡ 1;
se retiran como candidatos de rem2 y se nombran los que sobreviven {C-188},
que corrige {C-181}; (evidencia O1, refutador O1) «con 5 externas, la config
de B1, el doble; la mitad es truncamiento» era falso: B1 corre con CG 20, y
en esa config el desfase vale 1.71 / 1.51 veces la meseta, no es aditivo y
sale de bancos que no decidían {C-187}, que corrige {C-183}. Lo mismo en el
párrafo WS-K8 de `.claude/rules/transporte-energia.md`.

Además, tras una revisión previa al panel: erratas de la ronda 3 corregidas
(desfase de `k8_mo20` −2.167e-5, tramo −3.04e-3, cociente de la salida,
trayectoria de `k7v5_mo20_1k`, fuentes de las pruebas de humo, de los FAIL y
de los residuos, cita `mod_audit.f90:1102-1103`); «de segundo orden» se
precisa en {C-190}; enganche de fase descartado con N = 21 y 41
pre-registrado ({C-189}, veredicto {C-191}); correlación de D con el residuo
y extrapolación en {C-192}. Sin cambios en `src/` ni `tests/`.

## Proceso

1. **Punto de partida.** K7 dejó la hipótesis del complemento sin decidir por
   celda (0.319, {C-145}), frágil frente al residuo del CG en ambas
   direcciones ({C-163}), y el piso neto sin medir: vive en el cambio de masa
   del conjunto multifase y en el flujo por su frontera ({C-150}). Quedaba sin
   medir la «alternativa del lado de la EOS»: la demanda de compresibilidad
   del Poisson frente a lo que la EOS realiza ({C-133}).
2. **Derivación.** Por celda, e = comp + eos − fl − rx (el volfix se cancela,
   identidad de K7). La fila del Poisson es un balance de VOLUMEN de la
   mezcla: el gas sale lo que pide su compresibilidad (`su_cc`), más el
   líquido planeado (V_pois), menos lo que la fila almacena en su diagonal.
   Pasado a masa con el flujo de gas `ws_Fg`, que ya lleva la densidad del
   dador, el plan es:
   - err_liq_all = ρ_g (V_pois − V_eff) (K7);
   - err_cc = eos + ρ_g dt (su_cc − gadv − store_gas) − rx, con `gadv` el
     término advectivo sin pesar (A8) y `store_gas` la compresión acústica
     REAL del gas, α_g/(P0 + p)·V/dt·pp (con el pp COMPLETO, como `ws_Fg`;
     la EOS solo ve p avanzado en alpha_p·pp, así que una parte no la
     realiza la EOS y cae en err_cc, no en el residuo: ver Incertidumbre,
     {C-177}). Ojo: `su_cc` no es «demanda térmica + gadv»: es
     clamp(fsat·(−src + gadv) + acarreo/dt + S_rx/ρ_g)
     (`src/mod_pressure_3d.f90:625-632`), y el plan resta `gadv` completo
     (`src/mod_audit.f90:1102-1103`). El plan usa la MISMA `su_cc` que la
     fila sumó a `Su` (`ws_su_cc_used` = `dcl`, ya con fsat, acarreo y
     tope) y la fila la realiza en flujos: por la identidad de la fila,
     `su_cc` aparece igual en fl + ρ_g V_pois que en cc y se cancela en
     rem2. Lo que fsat, el acarreo o el tope hagan dentro de `su_cc` solo
     sobrevive en rem2 multiplicado por (ρ_final − ρ_iterado)/ρ, es decir,
     es de orden (Δρ/ρ)·Σ|cc|. No es despreciable en el gas libre, donde
     Σ|cc|_libre = 0.374 kg = 4070 Σ|e|_libre: basta Δρ/ρ ≈ 2e-4 para dar
     todo rem2_libre (7.94e-5 kg) {C-190}. Ese producto es el candidato (i)
     de abajo, no un término aparte de fsat, el acarreo o el tope, que como
     tales pertenecen a err_cc frente a la EOS. En el gas libre fsat ≡ 1:
     `fsat_cell` (`src/mod_pressure_3d.f90:1019-1028`) solo baja de 1 con
     `ws_bed` > 0, que exige α_s ≥ `ALPHA_BED` = 1e-2, y la clase libre
     exige α_s < 1e-2 al inicio y al final del paso
     (`src/mod_audit.f90:981`). Esto corrige la lectura de {C-181} que daba
     (1 − fsat)·gadv como término que la fila no pidió {C-188};
   - err_art = −ρ_g dt store_art, el almacenamiento ARTIFICIAL de la fila
     (compliance `PP_COMPLIANCE`, piso `alpha_g_comp_min` de D2.4 y acústico
     del líquido), que ninguna fase realiza. En `k8_*` el piso D2.4 está
     INACTIVO: `alpha_g_comp_min` no aparece en `config.dat` y vale 0 por
     defecto (`src/mod_config_3d.f90:94`) {C-177}.
   - El residuo rem2 = e − plan = comp − fl − err_liq_all − ρ_g dt (su_cc −
     gadv − store_gas) − err_art NO contiene la EOS ni rx: se cancelan
     (`ecc = mg_eos + cc − rx`, `src/mod_audit.f90:1106`). Se puede escribir
     rem2 = [comp + ρ_g V_eff] − [fl + ρ_g V_pois + ρ_g dt (su_cc − gadv −
     store_gas) + err_art]: el primer corchete es la identidad de K7 (el
     complemento sigue al líquido realizado) y el segundo, el cierre en masa
     de la fila del Poisson. Por eso el inciso por celda mide el cierre de
     esas dos identidades, no lo que realizó la EOS frente al plan {C-178}.
   Y sobre cada conjunto, sin aproximación: e_conjunto = comp + eos − flux −
   rx, con flux el flujo neto de gas que ENTRA por su frontera (las caras
   internas se cancelan).
3. **Corrección antes del pre-registro.** La prueba de humo en bancos de test
   (que no deciden) dio un plan peor que nada en el gas libre: se había usado
   ρ·dt·su_cc, que cuenta dos veces el término advectivo porque `ws_Fg` ya
   lleva la densidad del dador. Con su_cc − gadv, y añadiendo después el
   almacenamiento de la fila, el plan explicaba 0.77–1.00 del gas libre y
   0.73–0.76 del multifase en `arc_melt_n4` y `cold_10step_n8`, y 0.11 del
   multifase en `bed_bath_rest_n4`. Todo esto antes de pre-registrar.
   > [fuente: tests/out/{arc_melt_n4,cold_10step_n8,bed_bath_rest_n4}/audit.csv | for d in tests/out/arc_melt_n4 tests/out/cold_10step_n8 tests/out/bed_bath_rest_n4; do python3 tests/integration/check_audit.py $d | grep mass_gas_cells_cc; done]
4. **Instrumento** (`src/mod_workspace.f90`, `src/mod_pressure_3d.f90`,
   `src/mod_audit.f90`): el Poisson guarda la demanda de compresibilidad que
   sumó a `Su` (`ws_su_cc_used`), su término advectivo (`ws_gadv_used`) y el
   almacenamiento de la fila partido en real y artificial (`ws_store_gas`,
   `ws_store_art`, convertidos a caudal con `pp` tras el CG), con el mismo
   patrón que `ws_pc_unl_used` de K7 (anulados al empezar cada Poisson y en
   las filas triviales y de salida). El audit añade 20 columnas
   (`m_gas_{comp,eos,flux,rx}_{multi,free}`, `m_gas_err_cc_*`,
   `m_gas_err_art_*`, `m_gas_rem2_abs_*`, `m_gas_err_abs_free`,
   `m_gas_cc_abs_*`, `m_gas_art_abs_*`, `m_gas_cc_skip`).
   `tests/integration/check_audit.py`: check nuevo `mass_gas_class_split`
   (PASS/FAIL; es `mass_gas_rewrites` restringido a cada clase: compara el
   inventario con los ganchos de complemento, EOS y volfix, pero es
   tautológico en el flujo y en rx, que entran igual en e y en flux), check
   nuevo `mass_gas_flux_closure` (flux_multi + flux_free + m_gas_out = 0 por
   paso; NO tautológico, m_gas_out sale de otro camino de código; añadido
   tras la verificación previa al panel, {C-176}) e INFO `mass_gas_cells_cc`.
5. **Pre-registro commiteado antes de compilar el binario de banco**
   (`8dcb6e5`): {C-169} (H8, el plan del Poisson explica el error por celda)
   y {C-170} (C-110 por celda con el CG convergido). Decidía `k8_cg200`
   (`max_inner_pres` 200), con `k8_cg1000` previsto si el CG no convergía.
6. **Enmiendas antes del banco que decide** {C-171}{C-172}, commiteadas
   (`4aa8363`): en `k8_cg200` el CG no convergió (2 «[CG] AVISO»: ≥ 1001
   Poisson con residuo reducido ~2e-5 frente a tol 1e-8), así que decide
   `k8_cg1000`, y si tampoco convergía la predicción quedaba fallida. Y el
   prerrequisito bit a bit se limitó a las columnas físicas: las
   `m_gas_err_*` se recalculan en el lazo de diagnóstico modificado y
   difieren a ~1e-20 kg (relativo ≤ 4e-12). Constancia: esta segunda
   enmienda relaja el prerrequisito bit a bit de {C-169} DESPUÉS de ver que
   `k8_mo20` lo incumplía literalmente en `m_gas_err_multi` y
   `m_gas_err_abs_multi`; se registró antes del banco que decide (`4aa8363`,
   13:59:32; `k8_cg1000` arranca a las 13:59:38) y de cualquier veredicto, y
   `k8_cg200` da el mismo veredicto (0.847), así que no cambia el resultado.
7. **Corridas** en rutas propias, una a la vez, binario
   `campaigns/bin/eaf3d_k8_opt`, 59 pasos 280001–280059 desde
   `judge_otp_280/eaf3d_00280000.h5`, 15 ranks: `k8_mo20` (20 externas,
   `max_inner_pres` 20 como B1), `k8_base` (5 externas), `k8_cg200` y
   `k8_cg1000` (20 externas, CG 200 y 1000).

8. **Verificación independiente previa al panel** (agente `auditor-eaf3d`, solo
   lectura) {C-176}: corrigió la lectura del neto multifase (atribuyó el
   flujo neto a las celdas de salida; el panel lo retiró como mecanismo:
   es una igualdad de sumas en la ventana, {C-177}), señaló que
   `mass_gas_class_split` es tautológico en el flujo (se añade
   `mass_gas_flux_closure`) y que `store_gas` usa el `pp` completo; además,
   erratas. Solo se cambiaron COMENTARIOS en `src/`: el ejecutable optimizado
   difiere del de banco en 270 bytes, todos en las cadenas de error con número
   de línea que incrusta gfortran; `k8_cg1000` y `k8_mo20` repetidos con el
   binario del código actual (`campaigns/bin/eaf3d_k8b_opt`, rutas
   `k8_cg1000_r2`, `k8_mo20_r2`) dan `audit.csv` idénticos en las 137 columnas
   y 60 filas (`research/ws/WS-K8/logs/opt_identidad.txt`).

## Resultado

Tabla {C-173}{C-176}{C-178}:

| Cantidad (59 pasos) | k8_cg1000 (decide) | k8_cg200 | k8_mo20 | k8_base |
|---|---|---|---|---|
| «[CG] AVISO» en `run.log` | **0** | 2 | 2 | 1 |
| Gas libre: Σ\|e\| | 9.20e-5 kg | 8.99e-5 | 1.03e-3 | 9.20e-3 |
| Gas libre: Σ\|e − plan\| / Σ\|e\| | **0.863** | 0.847 | 1.004 | 0.918 |
| Multifase: Σ\|e\| | 1.632e-2 kg | 1.632e-2 | 1.636e-2 | 1.814e-2 |
| Multifase: Σ\|e − plan\| / Σ\|e\| | **0.197** | 0.197 | 0.203 | 0.339 |
| Multifase: neto e frente al neto del plan | **−8.55e-4 / +4.25e-4 (1.50)** | −8.58e-4 / +4.25e-4 | −8.55e-4 / +4.23e-4 | −1.57e-3 / +3.65e-4 |
| Multifase: desfase e − plan por paso, media ± sd (pasos < 0) | −2.169e-5 ± 0.13e-5 (59/59) | −2.173e-5 ± 0.13e-5 (59/59) | −2.167e-5 ± 0.10e-5 (59/59) | −3.28e-5 ± 0.45e-5 (59/59) |
| Desfase por paso: sd / \|media\| | 0.060 | 0.059 | 0.047 | 0.136 |
| Desfase en el PASO 1 (mismo estado inicial) | −2.105e-5 | −2.105e-5 | −2.110e-5 | −3.602e-5 |
| C-110: rem_all / abs_multi; neto | **0.3156; 1.571** | 0.3155; 1.569 | 0.3186; 1.571 | 0.4038; 1.320 |
| Σ\|err_art\| / (Σ\|e\|_multi + Σ\|e\|_libre) | 3.0e-6 | 2.9e-6 | 5.2e-6 | 4.8e-5 |
| `mass_gas_class_split` (resto) | PASS (−1.6e-17) | PASS | PASS | PASS |
| `mass_gas_rewrites` (resto) | PASS (1.8e-14) | PASS | PASS (−6.2e-14) | PASS |

> [fuente: campaigns/b1/k8_{cg1000,cg200,mo20,base}/audit.csv y run.log | python3 -c "import csv,statistics as s
> for n in ('k8_cg1000','k8_cg200','k8_mo20','k8_base'):
>  r=[x for x in csv.DictReader(open('campaigns/b1/%s/audit.csv'%n)) if int(x['step'])>280000];V=lambda c:[float(x[c]) for x in r];S=lambda c:sum(V(c));e=V('m_gas_err_multi');p=[a+b+c for a,b,c in zip(V('m_gas_err_liq_all'),V('m_gas_err_cc_multi'),V('m_gas_err_art_multi'))];d=[a-b for a,b in zip(e,p)];print(n,S('m_gas_err_abs_free'),S('m_gas_rem2_abs_free')/S('m_gas_err_abs_free'),S('m_gas_err_abs_multi'),S('m_gas_rem2_abs_multi')/S('m_gas_err_abs_multi'),sum(e),sum(p),s.mean(d),s.stdev(d),sum(x<0 for x in d),s.correlation(e,p),S('m_gas_err_rem_abs_all')/S('m_gas_err_abs_multi'),abs(sum(e)-S('m_gas_err_liq_all'))/abs(sum(e)),(S('m_gas_art_abs_multi')+S('m_gas_art_abs_free'))/(S('m_gas_err_abs_multi')+S('m_gas_err_abs_free'))))"; python3 tests/integration/check_audit.py DIR | grep -E 'mass_gas_class_split|mass_gas_rewrites'; grep -c '\[CG\] AVISO' DIR/run.log]

> [fuente de las filas «sd / |media|» y «paso 1», y de las correlaciones de O2 {C-181}: la misma lectura, imprimiendo d[0], s.stdev(d)/abs(s.mean(d)), s.stdev(e), s.stdev(V('m_gas_eos_multi')) y s.correlation(A,B) con A = comp_multi − flux_multi y B = err_liq_all + (err_cc_multi − eos_multi + rx_multi) + err_art_multi; comando completo en el registro de C-181; diff campaigns/b1/k8_base/config.dat campaigns/b1/k8_mo20/config.dat]

«plan» = err_liq_all + err_cc + err_art por celda; «desfase» = e − plan
sumado sobre el multifase en cada paso (es el neto de rem2). `k8_base` y
`k8_mo20` solo difieren en `max_outer` (5 frente a 20) y en la ruta de
salida (`diff` de sus `config.dat`; `alpha_T` = 0.7 en ambas). Se retiró la fila corr(e_multi, plan) (0.93 / 0.93 / 0.96 /
0.68): no es evidencia, ver «Neto multifase» {C-181}.

- **Veredicto de {C-169} (enmendada por {C-171}): REFUTADA por la letra** {C-173}.
  En `k8_cg1000`, con el CG convergido, el cociente del gas libre es 0.863 ≥
  0.7. El resto del criterio: el multifase por celda cumple (0.197 ≤ 0.3) y
  el inciso del neto falla (1.497 > 0.3). Lectura acotada {C-178}: el 0.197
  del multifase NO es evidencia de que el plan del Poisson sea el
  mecanismo del error por celda. Como la EOS y rx se cancelan en rem2
  (Derivación), el inciso por celda solo comprueba que el complemento sigue
  al líquido realizado y que la fila del Poisson cierra en masa: no
  contrasta lo que realizó la EOS con ninguna alternativa y, en lo
  esencial, repite el diseño que {C-154} criticó en {C-145}. Escala:
  Σ|cc|_multi = 5.82e-2 kg = 3.6 Σ|e|_multi, así que rem2_multi (3.21e-3) es
  un cierre al 5.5 % de Σ|cc|. En el gas libre, Σ|cc|_libre = 0.374 kg =
  4070 Σ|e|_libre y rem2_libre / Σ|cc|_libre = 2.0e-4 (CG 200) y 2.1e-4
  (CG 1000). Esa meseta solo prueba que el 0.863 no es residuo del CG.
  HIPÓTESIS, no medida {C-181}: que sea un piso de conversión volumen→masa
  del cierre y no un término que le falte al plan. Candidatos que sí
  sobreviven a la cancelación de `su_cc` en rem2 {C-188}: (i) (ρ_final −
  ρ_iterado)·dt·(su_cc + E2 + líquido neto − store); (ii) `gadv` de
  ensamblaje frente a Σ Q_in,corregido·(ρ_N − ρ_P), incluidas las caras
  que `gas_adv` excluye por la guardia `ALPHA_CUTOFF`
  (`src/mod_pressure_3d.f90:1061`) y las que cambian de sentido tras la
  corrección; (iii) el residuo del CG, ya descartado. (1 − fsat)·gadv, el
  acarreo y el tope NO son candidatos de rem2 (ver Derivación). El plan no reproduce el NETO multifase
  (signo contrario); ver «Neto multifase».
- **Veredicto de {C-170} (enmendada por {C-172}): SIN DECIDIR** {C-174}: 0.3156
  entre 0.3 y 0.7; neto 1.571 > 0.3. **En esta ventana, converger el CG no
  mueve el cociente** {C-178}: 0.3186 (CG 20; en `k8_mo20` consta ≥ 1001
  Poisson sin converger: avisos en el caso 1 y en el 1001 de `run.log`; el
  «≥ 85 %» de {C-168} se midió en `k7_mo20`) → 0.3155 (CG 200) → 0.3156
  (CG 1000, convergido); por tramos de 20 pasos, 0.320/0.314/0.313 con CG
  1000 frente a 0.323/0.317/0.316 con CG 20. Las trayectorias son casi
  idénticas, así que esto NO prueba lo que {C-163} planteaba entre
  regímenes ni frente a la deriva en ventanas largas (0.314 → 0.349 por
  tramos de 200 pasos en `k7v5_mo20_1k`, CG 20, {C-154}); solo que, en estos 59 pasos, el «sin decidir» de K7 no
  era un artefacto del CG truncado.
- **Con 20 externas, el residuo del CG explica el error del gas libre**
  {C-173}{C-178} (`k8_mo20` frente a `k8_cg1000`, ambas con 20 externas):
  con CG 20 Σ|e|_libre = 1.027e-3 kg y el plan no explica nada (1.004); con
  el CG convergido baja 11 veces, a 9.198e-5 kg; ya en el paso 1, desde el
  mismo estado, 9.8e-6 frente a 7.5e-7 kg. En el multifase el CG apenas
  importa (Σ|e| 1.636e-2 → 1.632e-2). Con 5 externas, la configuración de
  B1, solo hay lectura no pre-registrada {C-186}: `k8_base` (CG 20) tiene
  Σ|e|_libre = 9.203e-3, nueve veces el de `k8_mo20`, y `k8s_mo5` (CG 1000)
  3.627e-3, así que el CG truncado aporta ~60 % del error del gas libre; en
  el paso 1, 1.71e-4 frente a 5.80e-5 kg. El multifase casi no cambia
  (1.814e-2 → 1.797e-2). Ver Incertidumbre.
- **Neto multifase: un desfase casi constante del residuo, que depende del
  lazo externo y cuyo origen no está medido**
  {C-175}{C-176}{C-177}{C-178}{C-181} (`k8_cg1000`). El reparto exacto por conjunto
  es e_multi = comp (+4.06e-5) + eos (+1.288e-4) − flujo entrante por la
  frontera (+1.019e-3) − rx (+5.4e-6) = −8.55e-4 kg, y por paso cierra
  flux_multi + flux_free + m_gas_out = 0 a ≤ 9.1e-19 kg
  (`mass_gas_flux_closure`). Pero ese reparto no da un mecanismo:
  - Por paso, e_multi = −1.449e-5 ± 0.341e-5 kg (negativo en 59/59), casi
    constante, mientras m_gas_out = −1.645e-5 ± 6.39e-5 (el gas entra por
    las celdas de salida en 25/59 pasos y sale en 34);
    corr(e_multi, m_gas_out) = 0.09, corr(flux_multi, −m_gas_out) = 0.23 y
    corr(e_multi, −flux_multi) = 0.10. flux_multi (sd 3.26e-5) y comp + eos
    (sd 3.24e-5) se cancelan en cada paso. Que −Σ m_gas_out equivalga al
    95.3 % de Σ flux_multi (93.3 % en `k8_mo20`, 115.7 % en `k8_base`; el
    cociente inverso, Σ flux_multi / −Σ m_gas_out, es 1.050 / 1.072 / 0.864)
    es una
    IGUALDAD DE SUMAS en esta ventana, no una relación por paso {C-177}.
  - En `k7v5_mo20_1k` (mismo reinicio, 20 externas, 999 pasos; idéntico a
    `k8_mo20` en m_liq, m_gas, E_liq, E_gas, p_max y dt hasta el paso
    280058; la fila 280059 difiere porque en `k8_mo20` el último dt se
    recortó a t_final, 9.9999971e-4 frente a 1e-3), por tramos de 200 pasos Σ e_multi =
    −3.04e-3, −3.52e-3, −3.38e-3, −3.35e-3, −3.55e-3 kg, mientras Σ m_gas_out
    = −2.19e-3, +2.5e-5, −1.76e-3, +4.3e-4, −5.33e-3: en el tramo 200–400 el
    outlet no aporta nada y el déficit es el mismo. Se RETIRA la lectura
    «el flujo neto que entra al multifase es la entrada por las celdas de
    salida» de {C-176}(1), y con ella la coincidencia «neto ≈ −la entrada por
    el outlet» de {C-110} fuera de esta ventana {C-177}.
  - El neto entero es el desfase del residuo del plan: e − plan sumado
    sobre el multifase vale −2.169e-5 ± 0.13e-5 kg por paso con CG 1000 y
    −2.167e-5 ± 0.10e-5 con CG 20, ambas con 20 externas (negativo en
    59/59; cambia un 0.1 % al converger el CG), y suma −1.28e-3 frente a un
    neto de e de −8.55e-4 y un plan de +4.25e-4. Con 20 externas, el neto no
    depende del CG {C-178}. Su sd por paso es el 6 % de su media.
  - **Sí depende del lazo externo** {C-181}: con 5 externas (`k8_base`,
    misma config salvo `max_outer`) vale −3.28e-5 ± 0.45e-5 kg por paso
    (59/59 negativo, sd del 14 % de la media). En el PASO 1, desde el mismo
    estado y con CG 20 en ambas, −3.60e-5 (5 externas) frente a −2.11e-5
    (20 externas): el número de externas mueve el desfase un 70 % antes de
    que la trayectoria diverja. Orígenes candidatos, ninguno medido: (a) un
    sesgo estructural de la identidad de fila en masa (el corchete del
    complemento frente a V_eff o el de la conversión volumen→masa); (b)
    residuo del lazo externo truncado: el plan usa la `su_cc`, la `gadv` y
    el `pp` del ÚLTIMO Poisson, y con 20 externas el lazo externo no está
    necesariamente convergido ({C-125}, {C-109}, {C-152}); que el desfase no
    cambie entre CG 20 y CG 1000 no dice nada de (b). Se RETIRA «vive en un
    sesgo sistemático de la identidad de fila en masa, no en el CG»
    (de {C-179}(2)) como atribución. El barrido de `max_outer` (abajo,
    {C-184}) mostró después que desde 20 externas queda una meseta que no
    es (b) mientras el lazo no converja. Que (b) explique la diferencia
    entre 5 y 20 externas es lectura no pre-registrada de N = 5 y 10, y con
    5 externas el CG también mueve D (+16 %) sin sumarse {C-187}.
  - Se RETIRA corr(e_multi, plan) = 0.93 (0.96 con CG 20) como apoyo
    {C-181}: la EOS y rx entran por igual en e y en el plan (sd de eos_multi
    por paso 3.24e-5, diez veces la de e_multi, 3.41e-6), y las partes no
    compartidas, comp − flux_multi frente a err_liq_all + ρ_g dt (su_cc −
    gadv − store_gas) + err_art, correlacionan 0.9992 por la identidad de
    fila. El 0.93 solo reexpresa que sd(rem2 neto) (1.31e-6) es pequeña
    frente a sd(e_multi); es el defecto que {C-154} y {C-180} señalaron para
    el inciso por celda.
  - Como el inventario del gas nunca recibe `ws_Fg` (identidad de K7),
    «comp + eos (+1.7e-4) no realizan el flujo» no es evidencia contra
    {C-110}: el complemento neto (4e-5) no dice nada de los +5.1e-3 / −6.0e-3
    kg que se compensan entre celdas (sondas de {C-110}).
- **Barrido de `max_outer` con el CG convergido** {C-182}{C-183}{C-184}{C-186}
  (`campaigns/b1/k8s_mo{5,10,20,40,80}`: config de `k8_cg1000` con
  `max_outer` = N y `monitor_freq` = 1, binario
  `campaigns/bin/eaf3d_k8b_opt`, 15 ranks, secuenciales). Prerrequisitos
  cumplidos: cero `[CG] AVISO` en los cinco; `k8s_mo20` idéntico a
  `k8_cg1000` en las 137 columnas de `audit.csv` (60 filas, ninguna
  distinta). D = desfase neto multifase de rem2 por paso; D1 = el del paso
  280001, desde el mismo estado en todos.

  | max_outer | 5 | 10 | 20 | 40 | 80 |
  |---|---|---|---|---|---|
  | D1 [kg] | −4.179e-5 | −2.308e-5 | **−2.105e-5** | **−2.078e-5** | **−2.085e-5** |
  | media D ± sd [kg/paso] (59/59 negativos) | −3.82e-5 ± 0.30e-5 | −2.29e-5 ± 0.14e-5 | −2.17e-5 ± 0.13e-5 | −2.15e-5 ± 0.11e-5 | −2.23e-5 ± 0.10e-5 |
  | externas usadas (todas = max_outer) | 59/59 | 59/59 | 59/59 | 59/59 | 59/59 |
  | res_u / res_cont medios del lazo | 7.1e-3 / 6.4e-4 | 2.5e-3 / 1.9e-4 | 2.8e-4 / 6.1e-5 | 1.9e-4 / 4.7e-5 | 1.9e-4 / 5.2e-5 |
  | gas libre: Σ\|e\| [kg]; rem2/abs | 3.63e-3; 0.401 | 5.10e-4; 0.725 | 9.20e-5; 0.863 | 6.48e-5; 0.915 | 9.24e-5; 0.955 |
  | multifase: Σ\|e\| [kg]; rem2/abs | 1.797e-2; 0.318 | 1.649e-2; 0.220 | 1.632e-2; 0.197 | 1.632e-2; 0.196 | 1.630e-2; 0.196 |
  | C-110: rem_all / abs_multi | 0.3913 | 0.3284 | 0.3156 | 0.3154 | 0.3145 |

  > [fuente: campaigns/b1/k8s_mo{5,10,20,40,80}/{audit.csv,run.log} | python3 research/ws/WS-K8/scripts/barrido_outer.py campaigns/b1/k8s_mo{5,10,20,40,80}; medias de res_u y res_cont: python3 research/ws/WS-K8/scripts/desfase_residuo.py campaigns/b1/k8s_mo{5,10,20,40,80}; python3 research/ws/WS-K8/scripts/barrido_outer.py --identidad campaigns/b1/k8_cg1000 campaigns/b1/k8s_mo20; las filas de Σ|e| y cocientes con el comando de {C-186}]

  - **Veredicto de {C-182}: SOPORTADA por la letra** {C-184}:
    |D1(40) − D1(20)|/|D1(20)| = 0.013 y |D1(80) − D1(40)|/|D1(40)| =
    0.0033, ambos ≤ 0.10; para la media, 0.011 y 0.037 ≤ 0.15. La
    refutación (|D1(80)| ≤ 0.5 |D1(20)|) no se cumple: el cociente es 0.99.
  - **Salvedad del veredicto.** El lazo externo no declara convergencia en
    ningún paso de ningún banco, y sus residuos se estancan entre 20 y 80
    externas. «Estructural» significa aquí que iterar más el lazo, tal como
    está, no lo quita; no está probado contra un lazo que sí converja.
    Lectura que la acota, no veredicto {C-192}: D no sigue al residuo paso
    a paso (corr(D, res_u) entre −0.33 y +0.30 y corr(D, res_cont) entre
    −0.13 y +0.21 con 10/20/40/80 externas), y el ajuste lineal de D1 frente
    a res_cont del paso 1 extrapola a res_cont → 0 en −2.065e-5 kg
    (−2.000e-5 incluyendo N = 5), dentro de la meseta.
    > [fuente: python3 research/ws/WS-K8/scripts/desfase_residuo.py campaigns/b1/k8s_mo{10,20,40,80}; ídem con k8s_mo{5,10,20,40,80}]
  - **Enganche de fase descartado** {C-189}{C-191}. Los N que decidieron
    {C-182} son múltiplos de 20 (refutador, ronda 3, O2). Pre-registrado
    en {C-189} (commit `d0fc6d9`, antes de correr), con N = 21 y 41:

    | max_outer | 20 | 21 | 40 | 41 |
    |---|---|---|---|---|
    | D1 [kg] | −2.1053e-5 | −2.0429e-5 | −2.0777e-5 | −2.0771e-5 |
    | media D [kg/paso] | −2.1694e-5 | −2.1207e-5 | −2.1463e-5 | −2.0981e-5 |
    | pasos con externas = max_outer | 59/59 | 59/59 | 59/59 | 57/59 |

    > [fuente: python3 research/ws/WS-K8/scripts/barrido_outer.py campaigns/b1/k8s_mo20 campaigns/b1/k8s_mo21 campaigns/b1/k8s_mo40 campaigns/b1/k8s_mo41]

    Diferencias relativas de D1: 0.030 (21 frente a 20) y 0.0003 (41
    frente a 40), ≤ 0.10; de la media, 0.022 y 0.022, ≤ 0.15: SOPORTADA.
    Cero `[CG] AVISO`; las tres identidades de masa del gas pasan. Con 41
    externas el lazo declara convergencia en 2 pasos (280022 y 280058, con
    33 y 32 externas): los únicos pasos convergidos de todo el barrido.
  - **Relación con WS-K4** {C-192}: {C-107}/{C-109} vieron que la masa que
    reescribe la EOS en 280.0–280.3 s se satura en un piso al pasar de 5 a
    10 y 20 externas. K8 lo repite con el CG convergido, otra métrica (rem2
    neto multifase), hasta 80 externas y con los residuos registrados, y es
    coherente. La salvedad de {C-125} (convergencia del lazo no medida) ya
    está medida: el lazo no converge.
  - **Con 5 externas D es mayor que la meseta, y cuánto depende del CG**
    {C-183}, corregido por {C-187}. Frente a la meseta de 20 externas
    (`k8s_mo20`: D1 −2.1053e-5, media −2.1694e-5):

    | 5 externas | D1 [kg] | media D [kg/paso] | D1 / meseta | media / meseta | exceso D1; media |
    |---|---|---|---|---|---|
    | CG 1000 (`k8s_mo5`) | −4.1794e-5 | −3.8161e-5 | 1.99 | 1.76 | 50 %; 43 % |
    | CG 20, config de B1 (`k8_base`) | −3.6017e-5 | −3.2822e-5 | 1.71 | 1.51 | 42 %; 34 % |

    > [fuente: python3 research/ws/WS-K8/scripts/barrido_outer.py campaigns/b1/k8s_mo5 campaigns/b1/k8_base campaigns/b1/k8s_mo20; exceso = 1 − meseta/D]

    Los dos truncamientos no se suman: con 5 externas, converger el CG SUBE
    |D1| un 16 % y a la vez baja el error del gas libre un 60 %; con 20
    externas el CG movía D1 un 0.2 %. Todo esto sale de bancos que, según
    {C-182}, se reportan y no deciden; el reparto entre truncamiento y
    meseta supone que la meseta es la misma con 5 externas, cosa que no se
    probó. Afirmar algo de B1 exige un banco de 5 externas con CG 20 dentro
    de un barrido que habría que pre-registrar.
  - **Gas libre con 5 externas** {C-186}: el CG convergido baja Σ|e| de
    9.20e-3 (`k8_base`) a 3.63e-3 kg, así que en esa config el CG truncado
    aporta ~60 % del error del gas libre. De 5 a 20 externas el resto baja
    ~40 veces más. El multifase y el cociente de C-110 casi no cambian de 20
    a 80 externas.
  - `k8s_mo5` tiene FAIL en `energy_balance` (2.23) y en `regime_gas` (u_gas
    214.9 m/s), igual que `k8_base` (2.24 y 215.0); no lo introduce el CG
    convergido. Las tres identidades de masa del gas pasan en los cinco
    bancos.
    > [fuente: for d in campaigns/b1/k8s_mo{5,10,20,40,80} campaigns/b1/k8_base; do python3 tests/integration/check_audit.py $d | grep -E 'FAIL|mass_gas_rewrites|mass_gas_class_split|mass_gas_flux_closure'; done]
- **Almacenamiento artificial de la fila: despreciable** {C-173}: Σ|err_art|
  = 4.9e-8 kg (`m_gas_art_abs_multi` + `m_gas_art_abs_free`, `k8_cg1000`)
  frente a Σ|e| = 1.64e-2. Con el `pp` del último Poisson, el error no está
  en la compliance `PP_COMPLIANCE` ni en el acústico del líquido; D2.4
  estaba inactivo (`alpha_g_comp_min` = 0) y no se probó {C-177}.
- **Expectativas de {C-169}** (no decidían) {C-173}{C-176}{C-177}: (i)
  err_art ≤ 1 % de Σ|e|: cumplida (3.0e-6, con denominador Σ|e|_multi +
  Σ|e|_libre); (ii) cociente rem2/abs menor con el CG convergido (métrica
  pre-registrada: `k8_cg200` frente a `k8_mo20`): cumplida en el gas libre
  (1.004 → 0.847; 0.863 con CG 1000) y marginal en el multifase (0.203 →
  0.197); (iii) el neto lo lleva el flujo de frontera más que el
  complemento: cumplida SOLO por la letra de las sumas en esta ventana
  (1.02e-3 frente a 4.1e-5); por paso no hay relación (corr(e_multi,
  −flux_multi) = 0.10), así que no se lee como mecanismo.
- **Numérica bit a bit** {C-171}{C-173}: `k8_mo20` frente a `k7v5_mo20` es
  idéntico en `p_max`, `m_gas`, `E_liq`, `E_gas`, `u_gas_max` y
  `m_gas_err_liq_all` en las 60 filas; las `m_gas_err_*` difieren a ≤
  1.1e-19 kg (relativo ≤ 4e-12), por debajo de 1e-10.
- **Tests** {C-173}{C-176} (27-oct, 14:27–14:43, compilación limpia del diff final de WS-K8): `make test-unit`, `make test-quick` y `make test-full` OK (`TESTS (full): OK`, golden v131, 0 FAIL). Barrido sobre `tests/out/**/audit.csv`: `mass_gas_rewrites` en 78 bancos y `mass_gas_class_split` y `mass_gas_flux_closure` en 66, 0 FAIL, restos máximos 4.0e-12 kg y, en `mass_gas_class_split`, 8.5e-15 (multifase) y 3.7e-14 (gas libre, `arc_melt_slag_heel_n1`).
  > [fuente: research/ws/WS-K8/logs/test_unit.txt, test_quick.txt, test_full.txt | for d in $(dirname tests/out/**/audit.csv); do python3 tests/integration/check_audit.py $d | grep -E 'mass_gas_rewrites|mass_gas_class_split|mass_gas_flux_closure'; done]
- **Contra la hipótesis original** {C-175}, corregido por {C-176}{C-177}{C-178} (`--ref C-110`): con el CG convergido el inciso por celda de C-110 sigue sin decidir y no se mueve en esta ventana. El neto multifase es un desfase casi constante del residuo del plan, que no depende del CG con 20 externas pero sí del número de externas (−3.28e-5 frente a −2.17e-5 kg/paso con 5 y 20) y que el barrido de `max_outer` {C-184} separa en una meseta estructural de ~−2.1e-5 kg/paso a partir de 20 externas y que con 5 externas es mayor (1.71 veces en el paso 1 y 1.51 de media en la config de B1, con CG 20; lectura no pre-registrada, {C-187}); el origen de la meseta no está medido; la equivalencia de sumas con la entrada por las celdas de salida no se sostiene por paso ni por tramos en 999 pasos. Que el complemento y la EOS no realicen el flujo no es evidencia contra C-110. Se retiran «medido por primera vez», «no gas creado o destruido por el complemento» y «el origen del flujo está medido».

> [fuente de las estadísticas por paso y por tramos: campaigns/b1/k8_{cg1000,mo20}/audit.csv, campaigns/b1/k7v5_mo20_1k/audit.csv | python3 -c "import csv,statistics as s
> C=lambda a,b:s.correlation(a,b)
> for n in ('k8_cg1000','k8_mo20'):
>  r=[x for x in csv.DictReader(open('campaigns/b1/%s/audit.csv'%n)) if int(x['step'])>280000];V=lambda c:[float(x[c]) for x in r];S=lambda c:sum(V(c));e=V('m_gas_err_multi');o=V('m_gas_out');f=V('m_gas_flux_multi');ce=[a+b for a,b in zip(V('m_gas_comp_multi'),V('m_gas_eos_multi'))];print(n,s.mean(e),s.stdev(e),sum(x<0 for x in e),s.mean(o),s.stdev(o),sum(x<0 for x in o),C(e,o),C(f,[-x for x in o]),C(e,[-x for x in f]),s.stdev(f),s.stdev(ce),S('m_gas_cc_abs_multi'),S('m_gas_cc_abs_free'),S('m_gas_rem2_abs_free')/S('m_gas_cc_abs_free'),float(r[0]['m_gas_err_abs_free']),[sum(float(x['m_gas_err_rem_abs_all']) for x in r[i:i+20])/sum(float(x['m_gas_err_abs_multi']) for x in r[i:i+20]) for i in (0,20,40)])
> r=[x for x in csv.DictReader(open('campaigns/b1/k7v5_mo20_1k/audit.csv')) if int(x['step'])>280000]
> print([(sum(float(x['m_gas_err_multi']) for x in r[i:i+200]),sum(float(x['m_gas_out']) for x in r[i:i+200])) for i in range(0,999,200)])"; grep -n '\[CG\] AVISO' campaigns/b1/k8_mo20/run.log]

## Incertidumbre

- Un solo estado de reinicio (`judge_otp_280`), 59 pasos y una trayectoria
  por config, 15 ranks. {C-169}/{C-170} los decide `k8_cg1000`, {C-182}
  los deciden `k8s_mo{20,40,80}` y {C-189} `k8s_mo{21,41}`. B1 por encima
  de 280 s exige juez estadístico con varias trayectorias, así que nada de
  esto es veredicto sobre B1. Con 5 externas (`k8_base`, que no pasa
  `check_audit`: FAIL `energy_balance` 2.24 y `regime_gas` 215 m/s; igual
  `k8s_mo5`: 2.23 y 214.9 m/s) los cocientes empeoran (multifase 0.339; gas
  libre 0.918, con Σ|e| 100 veces el de `k8_cg1000`).
  > [fuente: python3 tests/integration/check_audit.py campaigns/b1/k8_base; python3 tests/integration/check_audit.py campaigns/b1/k8s_mo5]
- **Con 5 externas (la configuración de B1: `max_outer` 5, `max_inner_pres`
  20 en `campaigns/b1/judge_otp_280/config.dat` y
  `campaigns/b1/b1_full_heat/config.dat`) el aporte del CG al error del gas
  libre está medido en un solo banco y sin pre-registro propio**: `k8s_mo5`
  {C-186} (CG 1000) baja Σ|e| del gas libre de 9.20e-3 a 3.63e-3 kg frente a
  `k8_base` (CG 20). Es lectura del barrido de {C-182}, que solo decidía con
  20, 40 y 80 externas. El resto de lo que se afirma del CG vale con 20
  externas ({C-125} ya limitó WS-K7 a ese régimen); con 5 externas el CG
  mueve D1 un 16 % ({C-187}), frente al 0.2 % con 20.
- **Origen de la meseta del neto multifase: no medido** {C-181}{C-184}. El
  barrido descarta que la meseta (~−2.1e-5 kg/paso desde 20 externas) sea
  truncamiento del lazo externo tal como está, pero ese lazo no converge en
  ningún banco (residuos estancados entre 20 y 80 externas): no se puede
  descartar que un lazo que sí converja la cambie. Con 5 externas el
  desfase es mayor que la meseta (1.71 / 1.51 veces con CG 20, la config de
  B1; 1.99 / 1.76 con CG 1000), en bancos que no decidían y sin reparto
  aditivo {C-187}. Siguiente pieza, por pre-registrar: partir rem2 en
  [comp + ρ_g V_eff] (cambio de α_s, ρ_l de la celda) y [fl + ρ_g V_pois +
  cc + err_art] por clase y paso en bancos de 5 y de 20 externas. En el
  segundo corchete, los candidatos que sobreviven a la cancelación de
  `su_cc` son (ρ_final − ρ_iterado)·dt·(su_cc + E2 + líquido neto − store)
  y `gadv` de ensamblaje frente al corregido, con las caras que excluye la
  guardia `ALPHA_CUTOFF` {C-188}; fsat, el acarreo y el tope no. Exige columnas nuevas en `src/` y es otra pieza. Faltan también
  una ventana de 999 pasos o más, y flux_multi y comp + eos por tramos en
  una ventana larga con el binario K8.
- **El inciso por celda no contrasta la EOS con el plan.** Para hacerlo
  hace falta Σ|err_cc| por clase frente a Σ|e| (hoy solo hay el neto
  `m_gas_err_cc_*` y Σ|cc|), a pre-registrar.
- El plan usa la ρ_g de la celda al final del paso, la `su_cc` y la `gadv`
  del último Poisson (calculada con los flujos de ensamblaje) y el `pp` de su
  CG; las diferencias entre el iterado del último Poisson y el estado final
  quedan en el residuo. Cuánto aporta cada una no está medido.
- El gas libre con el CG convergido no está explicado (0.863), pero pesa poco
  (0.56 % de Σ|e| del interior). rem2_libre es el 2e-4 de Σ|cc|_libre con
  CG 200 y con CG 1000, lo que solo descarta el CG. «Piso de conversión» es
  una HIPÓTESIS {C-181}: no está medido frente a un término que le falte al
  plan; candidatos: (ρ_final − ρ_iterado)·dt·(su_cc + E2 + líquido neto −
  store) y `gadv` de ensamblaje frente al corregido, con las caras que
  excluye la guardia `ALPHA_CUTOFF` {C-188}. En el gas libre fsat ≡ 1, y
  el acarreo y el tope se cancelan en rem2 con `su_cc`: pertenecen a err_cc
  frente a la EOS. Decidirlo exige columnas
  nuevas por clase, a pre-registrar.
- `store_gas` usa el `pp` completo, igual que `ws_Fg` (corregido con el pp
  completo, `src/mod_pressure_3d.f90:866-871`); solo `sh%p` avanza
  `alpha_p·pp` (0.7 en estas configs, `:898`). La parte de ρ dt store_gas
  que la EOS no realiza cae en err_cc, NO en rem2 (que no contiene la EOS),
  y no puede explicar el 0.863 del gas libre; esto corrige {C-176}(4)
  {C-177}. Su magnitud (Σ|ρ dt (1 − alpha_p) store_gas| por clase frente a
  err_cc) no está medida.
- «Cero [CG] AVISO ⇒ CG convergido» tiene un hueco: el CG sale en silencio si
  |p·q| < SMALL (1e-30, `src/mod_solver_3d.f90:245`) aunque el residuo no
  haya llegado a la tolerancia, y el aviso solo se emite con n_iter ≥
  max_iter (líneas 271–279). No se registró el residuo final ni n_iter de
  cada Poisson; registrarlo exige cambiar código.
- El CG no converge con 200 iteraciones en este estado (residuo reducido
  ~2e-5): con 1000 sí. B1 corre con 20 iteraciones y 5 externas; con 20
  externas, en esta ventana, el CG truncado no cambia el multifase pero sí
  el gas libre; con 5 externas, en lectura no pre-registrada {C-186}, el
  CG convergido baja el gas libre un 60 % (9.20e-3 → 3.63e-3 kg) y el
  multifase un 1 % (1.814e-2 → 1.797e-2). El número total de Poisson
  por corrida no se registra.
- «Converger el CG no mueve el cociente de C-110» vale en estos 59 pasos;
  no se ha probado frente a la deriva larga (0.314 → 0.349 por tramos de
  200 pasos en `k7v5_mo20_1k`, CG 20) sin una ventana de 999 pasos con CG 1000.
- Los bancos de test convergidos (pruebas de humo, no deciden) dan otro
  reparto: en `bed_bath_rest_n4` el plan explica solo el 11 % del multifase.
  No se generaliza a otros regímenes.
