# Revisión del refutador: WS-K7, ronda 1 (lanzamiento posterior a la ronda 13 del reporte)

**Veredicto: rechaza.** Hay una objeción bloqueante, R1: la regla y C-124 atribuyen a las celdas con 0 < α_g < 1e-2 lo contrario de lo que el WS midió en las nogas. Las demás objeciones no bloquean.

**Cómo revisé.** Revisión ciega: de `reviews/` leí solo mis revisiones previas de refutador (r1 y r7), para seguir mis objeciones. Todo fue de solo lectura: sin make ni corridas, y Python solo para leer `audit.csv`, `.h5`, `run.log` y el registro.

## 1. Conclusiones, alternativa y dato que las separa

| # | Conclusión | Mejor alternativa | Dato que separa | ¿Está en los datos? Qué dice |
|---|---|---|---|---|
| C1 | {C-145}: **sin decidir** (0.319; neto 1.571), solo para 59 pasos | El «sin decidir» es un transitorio tras el reinicio y el régimen va hacia la refutación | Ventana de ≥ 1000 pasos con 20 externas que pase `check_audit` | **No existe**: `k7v5_mo20_1k` FAIL `regime_gas`. Está declarado y el veredicto se acota a 59 pasos. Lo acepto así acotado |
| C2 | err_liq es el desajuste en caras enlazadas (desfase E2 ≤ 0.2 %) | Sería trivial si lo no enlazado fuera pequeño | `vol_unlinked` | Ya se sostuvo en la ronda previa (0.207 m³). Lo acepto |
| C3 | Nogas (29 % de Σ\|e\|): e = plan neto del Poisson en celdas llenas (identidad ±16 %); el conducto es la α de cara media con la celda en el alcance; mismo balance de fila que Plan E en otra población | (a) Artefacto del CG truncado (≥ 85 % de los Poisson sin converger). (b) Celda de paso. (c) Causalidad inversa: el gas por Rhie–Chow empuja y la fila «pide» líquido | (a) El mismo término con el CG convergido. (b) `in_tot`/`in_ok`. (c) signo(Fs) frente a `ws_Fc` | **(a) Está y no se usa (R4).** En los bancos de `tests/out` con `max_inner_pres` 200 y 0 avisos del CG, la identidad por celda vale 0.003–0.101 y V_pois/e 1.00–1.09; en B1, 0.163 y 0.847. El término existe con el CG convergido, lo que favorece al reporte. (b) y (c) no están medidas y están declaradas |
| C4 | La exportación de las nogas se cancela por construcción en e_multi; el piso vive en Δm_multi y en el flujo por la frontera | — | — | Es una identidad. La acepto |
| C5 | Bancos fríos: transitorio que no es H; su CG converge | Residuo del lazo externo (`tol_cont` 1e-2) | `tol_cont` más estricto | Verificado: `max_inner_pres` = 200 y 0 «[CG] AVISO» en `outer_conv_n8`, `cold_10step_n4` y `cold_bucket2_n4`. La alternativa está declarada |
| C6 | {C-152}: la cota del complemento solo restringe con 5 externas | — | — | Verificado: e_multi en 999 pasos −2.958e-2 con 5 externas frente a −1.684e-2 con 20 |
| C7 | Regla :211-212 y {C-124}: «0 < α_g < cutoff: complemento y EOS con **F_g = 0**» | F_g ≠ 0 por el alcance (F2.21), como en las nogas | `ws_Fg` en esas celdas; el código | **En contra (R1).** `act_g` incluye el alcance con α_g < cutoff sin distinguir α_g = 0 de α_g > 0 (`src/mod_pressure_3d.f90:235`), y el alcance es geométrico (`src/mod_multiphase.f90:958`). Hay 95 celdas así en 280059 y 90 en 280999, todas baño en k = 1–3 con una vecina de α_g ≥ 1e-2: la misma población que las nogas |
| C8 | e_multi SÍ depende de las externas (Proceso 1) | — | — | Verificado: −8.555e-4 frente a −1.571e-3 (59 pasos), −1.684e-2 frente a −2.958e-2 (999). La regla no lo recoge (R2) |

## 2. Repeticiones de fracasos registrados

- **Ningún remedio propuesto.** «Antecedentes» declara Plan E E1/E1b, Plan K, `n_pc_max = 3`, F2.31 por paso, F2.17–F2.24 y la familia D/E/F/G con el juez estadístico y la salvedad de vigencia {C-089}. No hay D2.2, ni reglas locales nuevas, ni corrector interno. **No es una repetición.**
- **La afirmación «H es el mecanismo de la válvula ficticia de Plan E»** (report.md:289) presenta como identidad algo que Resultado limita a «mismo balance de fila, otra población, ciega o de paso sin medir» (R3).

## 3. Objeciones

**R1 (bloqueante): una afirmación falsa en la regla y en C-124 (soportada).**
- *Qué dicen:* `.claude/rules/transporte-energia.md:211-212` afirma que las celdas con 0 < α_g < 1e-2 tienen complemento y EOS «con F_g = 0». C-124 lo da como hecho («F_g = 0 ahí, luego e = comp + eos») y las identifica con el «+5.11e-3 creada» de C-110.
- *Qué dice el código:* `act_g` incluye las celdas del alcance con α_g < cutoff (`src/mod_pressure_3d.f90:235`), y el alcance no depende de α_g (`src/mod_multiphase.f90:958`).
- *Qué midió el propio WS:* las nogas (α_g = 0, también por debajo del corte) exportan F_g justo por esa vía, con comp ≈ 0 ({C-137}).
- *Qué dicen los datos:* en 280059 hay 95 celdas multifase con 0 < α_g < 1e-2 y en 280999 hay 90. Todas son baño (α_l mediana 0.99) en k = 1–3 junto a gas con α_g ≥ 1e-2, es decir, la misma población.
- *Consecuencia:* la regla atribuye a esa clase el mecanismo contrario al medido.
- *Resolución:* corregir la frase («y, si están en el alcance, también F_g por la α de cara media») y registrar un evento con `--ref C-124`. Alternativa: una sonda de un paso de `ws_Fg_lk`/`ws_Fg` en esas celdas, o una columna Σ|dt ΣF_g| de la clase, pre-registrada.

**R2 (no bloqueante): la regla no recoge que e_multi depende de las externas.**
- El párrafo WS-K5 de la regla (:133-137) mantiene «un piso ~1/3 que no baja con más externas … vive en celdas multifase».
- K7 mide que e_multi sí baja con más externas: ×1.84 en 59 pasos y 43 % en 999, en bancos de 5 externas que no pasan `check_audit`.
- *Resolución:* añadir esa línea con su salvedad al párrafo WS-K7 de la regla.

**R3 (no bloqueante): «H es el mecanismo de la válvula ficticia» es una identidad no medida.**
- *Resolución:* escribir «mismo balance de fila que la válvula de Plan E», o medir `in_tot`/`in_ok` en las nogas y Σ dt·`ws_Fg` bruto por clase de vecina, pre-registrados.

**R4 (no bloqueante): el reporte no usa un dato que ya existe sobre la alternativa del CG.**
- En los bancos de `tests/out` con el CG convergido (0 avisos), (rem_all − rem + nogas)/nogas vale:
  - `bed_flood_n4`: 0.101;
  - `restart/bed_flood_n4_to_n4_s750`: 0.019;
  - `bath_fill_n4`: 0.008;
  - `symmetry_3elec_n6`: 0.003.
- En esos bancos vpois_nogas/nogas vale 1.003–1.086. En B1 los mismos cocientes valen 0.163 y 0.847.
- Esto muestra que el término nogas existe con el CG convergido, aunque no fija su magnitud en B1.
- *Resolución:* citarlo en Incertidumbre con su comando. Para la magnitud en B1 sigue haciendo falta `k7v5_mo20` con `max_inner_pres` mayor, pre-registrado.

## ¿Mueve el problema de sitio?

No. Es un cambio solo de diagnóstico:
- **Binario:** el sha256 de `make opt` es igual al de `campaigns/bin/eaf3d_k7v5_opt`, y no hay cambios en `src/` después de 16:57:25.
- **Costo:** el lazo SIMPLE pasa de 31.92 s (`k6_mo20`) a 32.62 s (`k7v5_mo20`), unos +2 %; en base, 17.36 s frente a 17.20 s; el número de intercambios de halo es idéntico.
- **Makefile staged:** solo cambian reglas `.o` de dependencia.

## ¿Se mide en el sitio que importa?

Está declarado que se mide en 59 pasos tras el reinicio de 280 s con 20 externas, sin una ventana larga con 20 externas que pase `check_audit`, y que no se extiende a B1. Lo acepto porque el veredicto es «sin decidir» y el reporte no saca conclusiones de régimen.

VEREDICTO: rechaza