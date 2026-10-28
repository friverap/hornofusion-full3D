# WS-K10, ronda 1: revisor-refutador

**Veredicto: aprueba.** No encontré ninguna alternativa que haga falsa una conclusión tal como está escrita. Todas las objeciones son no bloqueantes y aclaran cómo leer los resultados.

Fue de solo lectura: python solo para leer `audit.csv`, `run.log` y el registro, más `check_audit.py`, `cmp_comunes.py` y `h14.py`.

## Lo que verifiqué con los datos

- **H14 (`h14.py`).** r(e) vale −4.934e-2, −4.328e-2 y −4.108e-2 kg/s. Los cocientes 0.877 y 0.833 reproducen el reporte. err_liq_lk vale 6.996e-6 kg por paso.
- **Curvatura.** Reproduje el IC90 con bootstrap circular 10/20/40, semilla 1: r05/r1 = 0.877 (0.860-0.894), r025/r05 = 0.949 (0.925-0.972) y c/r1 = 0.81 (0.73-0.84). Hay ajuste en las 4000 réplicas.
- **Checks de `k11_dt05_s290`.** `mass_gas_row_volume`, `mass_gas_decomp` y `mass_gas_eos_end` dan PASS: 2.28e-14 m³, 5.73e-14 kg y 2.30e-18 kg.
- **Sin cambio numérico en los bancos.** `cmp_comunes --par` da 137 columnas comunes y «distintas: []» en los tres pares: k8s_mo20 frente a k10_mo20, k8s_dt05 frente a k10_dt05 y k8_base frente a k10_base.
- **Paso del reinicio.** En k8s_dt05, el paso 280001 vale −1.056e-3 kg, el 66.4 % de la suma de la ventana. En el paso 290001, e vale −1.735e-3 kg con 0.25 ms, −1.167e-3 con 0.5 ms y −5.06e-5 con 1 ms.
- **Bgq no es un resto.** En `mod_audit.f90:1251` Bgq se calcula de forma independiente, así que `mass_gas_decomp` no es tautológico.
- **B1 corre con dt fijo de 1 ms.** En `judge_otp_280` hay 65528 filas entre 280 y 345.5 s, todas con dt de 1 ms y ningún cambio de dt. El artefacto del paso 1 no ocurre en B1.

## 1. Conclusiones, alternativas y dato que las separa

| Conclusión | Mejor alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| La premisa «por paso» (C-197) era el paso del reinicio con dt acotado | Que sea un defecto activo siempre que cambia el dt | Ver si dt cambia en B1 | Sí: B1 nunca cambia de dt. Alternativa descartada |
| C-202 SIN DECIDIR; Br + Bgr pesa < 2 % de e | Que la cancelación Br2/Bgr la cause la contabilidad elegida | Una contabilidad con ρ_it por celda | No. El reporte ya lo declara |
| Desde 290 s el error es «mayormente tasa» (c/r ≈ 0.8) | (a) La tasa es el iterado estancado del lazo externo y no un sesgo de flujo | Barrido de externas desde 290 s con cada dt | Parcial. Los residuos de [STEP] escalan casi como dt (res_u 5.06e-4, 2.46e-4 y 1.67e-4), así que el estancamiento también daría «tasa». Pero corr(e, res) por paso es ≈ 0, y C-193 muestra 2 pasos convergidos en la meseta (O1) |
| La parte que depende de dt es el 12-19 % y la curvatura excluye c = 0 | (b) Esa parte es régimen y no truncamiento | r(e) en los pasos tranquilos | Sí. Con p_max < 35 kPa los cocientes son 0.98 y 1.00. Con 40 kPa no es monótono (O3) |
| La curvatura tiene IC90 sin solape | (c) Varianza entre trayectorias que el bootstrap no ve | Réplicas de trayectoria | Solo un proxy: k8s_mo20/21/40/41/80 dan sd ≈ 2.3 %, comparable a la brecha del 5 % (O2) |
| Bgq es la pieza dominante «en esta contabilidad» | Bgq es la diferencia de dos términos grandes | Los términos brutos de Bgq | No están exportados. El reporte ya lo declara |
| Store ×77 es propio de la config de B1 | Que lo cause el CG 20 o las 5 externas por separado | Un banco con 5 externas y CG 1000 | No. El reporte dice «config», no «externas» |
| Las cifras de 280 s están confundidas con el cambio de claves | Que la diferencia con 290 s sea el estado de la ventana y no el transitorio | Una tercera ventana con las mismas claves | No hay corrida, pero existe el snapshot `eaf3d_00300000.h5`. El reporte no adopta ninguna de las dos lecturas |

## 2. Repeticiones de fracasos registrados

- **No hay repetición de nada refutado.** WS-K10 es diagnóstico y no propone ningún arreglo.
- **H10 (Br) ya estaba propuesto.** Es el candidato (i) de C-188, y Bgq es su candidato (ii). C-188 no está refutada, pero el reporte no lo cita (O5).
- **«Tasa» no contradice lo refutado en C-106 ni en C-108**, que decían que el lazo truncado dominaba. Concuerda con el piso estructural de C-109, que no depende de las externas.
- **Los riesgos de un arreglo futuro ya están señalados:** M6-1 y M7-5 (guardias ALPHA_CUTOFF y `ws_qin_cap`), y la cercanía al acople implícito de Plan D si se linealiza gadv en pp.
- **La regla `transporte-energia.md` está bien acotada:** 20 externas, CG 1000, 290 s, «en esta contabilidad».

## 3. Objeciones (ninguna bloqueante)

- **O1.** Como los residuos del lazo escalan casi como dt, H14 no separa «sesgo de flujo» de «iterado estancado». Se resuelve con un barrido de externas 20/40/80 desde 290 s con 1 y 0.5 ms, o al menos declarándolo y citando los residuos y C-193.
- **O2.** Los IC90 de la curvatura son de una sola trayectoria. La dispersión entre bancos perturbados (sd ≈ 2.3 %) es comparable a la brecha 0.949 frente a 0.877. Se resuelve con réplicas de 12/14/16 ranks con 0.5 y 0.25 ms, o citando la dispersión de k8s_mo*.
- **O3.** En los pasos tranquilos r(e) no depende de dt, así que la parte del 12-19 % puede ser régimen en su totalidad, y el c/r(1 ms) = 0.81 no describe el truncamiento. Se resuelve con snapshots asentados con cada dt, o añadiendo esta lectura como sensibilidad no pre-registrada.
- **O4.** Sitio: H14 no se transfiere a la config de B1. Hacen falta un banco con la config de B1 y 0.5 ms desde 290 s y otro en 340-345 s; el snapshot `eaf3d_00340000.h5` ya existe.
- **O5.** El reporte debe citar C-188, C-109, C-110 y C-193.
- **O6.** No se puede verificar la procedencia de la base de la suite (el reporte lo declara), y test_quick está pendiente. Se resuelve regenerando la base desde 934c2d4 con log y sha, y corriendo test-quick sobre el diff 660ee6ac….

Rutas:
- `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K10/report.md`
- `/Users/frariv/Horno/hornofusion-full3D/campaigns/b1/k11_{mo20,dt05,dt025,base}_s290/`
- `/Users/frariv/Horno/hornofusion-full3D/campaigns/b1/k8s_mo{20,21,40,41,80}/audit.csv`
- `/Users/frariv/Horno/hornofusion-full3D/campaigns/b1/judge_otp_280/audit.csv`

VEREDICTO: aprueba
