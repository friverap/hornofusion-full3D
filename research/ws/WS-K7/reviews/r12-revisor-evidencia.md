Ronda 1 de WS-K7 (7.º lanzamiento): **apruebo**. El reporte dice «sin decidir», que es lo que da la letra de {C-144}. Recalculé las cifras principales desde los datos y todas coinciden con el redondeo mostrado. Quedan 5 objeciones menores, ninguna bloqueante.

Revisión de solo lectura. Usé python3 con csv y h5py sobre archivos existentes, `tests/integration/check_audit.py` (sin escrituras), `research/ws/WS-K7/scripts/{nogas_vecinas,rho_uz_nogas}.py` (solo lectura) y git en modo lectura. No leí `reviews/`.

## Criterio pre-registrado frente al veredicto

- **{C-144}** (ts 13:01:46, sin enmienda posterior) fija la regla:
  - SOPORTADA si `rem_abs_all/abs_multi ≤ 0.3` **y** `|Σe_multi − Σerr_liq_all| ≤ 0.3|Σe_multi|`.
  - REFUTADA si el cociente es ≥ 0.7.
  - En otro caso, SIN DECIDIR.
- **Valores recalculados** en `campaigns/b1/k7v5_mo20/audit.csv` (59 filas, step > 280000):
  - cociente 5.2108e-3 / 1.6356e-2 = **0.3186**
  - neto |−8.5549e-4 − 4.8809e-4| / 8.5549e-4 = **1.5705**
- **Veredicto:** sin decidir, el mismo que dan {C-145} y el reporte. El reporte no aprueba H ni reinterpreta el criterio.
- **Expectativa (i):** el reporte declara que su 3.ª cláusula NO se cumple («en base mayor»: 8.73e-6 < 2.16e-5). Corrige el texto de C-145 vía {C-162}, como corresponde.
- **Prerrequisitos de C-144:**
  - `mass_gas_rewrites` PASS en k7v5_mo20, base y 1k (restos −6.15e-14, −7.08e-14 y −5.41e-14) y en los 78 bancos de `tests/out` (0 FAIL, resto máximo 3.97e-12).
  - `liq_skip` = `e2_skip` = 0.
  - Identidad lk + unl: resto 1.2e-20.
  - k7v4 frente a k7v5: 105 de 110 columnas idénticas en los 60 renglones. Solo difieren las 5 que dependen de E2, y las 11 columnas exigidas son bit a bit iguales.
  - Tests OK (ver O4).
- **La comparación es justa:**
  - Mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`).
  - Las configs mo20 y base difieren solo en `max_outer`; mo20 y 1k solo en `t_final` y `output_freq`; k7v4 y k7v5 solo en `output_dir`.
  - El binario corresponde al diff staged: sha 0503d1f6… y opt idéntico byte a byte.
- **Muestra:** 59 pasos tras el reinicio, con transitorio (p_max 9.5e4–1.0e5 en los pasos 2–3) y ≥ 1001 de 1180 Poisson sin converger. El reporte limita el «sin decidir» a esa ventana y declara que no representa el régimen ni resiste a la refutación. Correcto.

## Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| rem_all/abs k7v5_mo20; mediana; rango | 0.319; 0.317; 0.302–0.381 | 0.3186; 0.3171; 0.3023–0.3814 | ok |
| neto k7v5_mo20 / base | 1.571 / 1.320 | 1.5705 / 1.3196 | ok |
| rem_all/abs base; mediana; rango | 0.404; 0.401; 0.377–0.457 | 0.4038; 0.4010; 0.3774–0.4567 | ok |
| filtro mo20/base | 0.565 / 0.626 | 0.5651 / 0.6263 | ok |
| lk + unl mo20 | 4.977e-4 + (−9.58e-6) = 4.881e-4 | 4.9768e-4 − 9.583e-6 = 4.8809e-4 | ok |
| lk + unl base | 5.021e-4 + 1.64e-7 | 5.0207e-4 + 1.643e-7 | ok |
| Σ\|unl\|/Σ\|e\| mo20/base | 0.0013 / 0.0005 | 0.00132 / 0.00048 | ok |
| ≤ 0.19 % de Σ\|err_liq_all\|; −2.0 % del neto | — | 0.194 %; −1.96 % | ok |
| nogas: V_pois, V_eff, rej, rej/Σ\|e\| | 4.078e-3, 1.1e-16, 7.655e-3, 1.59 | 4.0782e-3, 1.087e-16, 7.6547e-3, 1.589 | ok |
| rej/V_pois; V_pois/Σ\|e\| nogas | 1.88; 0.85 | 1.877; 0.847 | ok |
| m_spill; vol_lim | 1.3e-12; 0.249 | 1.27e-12; 0.2489 | ok |
| corr mo20 / base | +0.233, +0.970, 0/59 / −0.428, +0.993, 0/59 | idénticos | ok |
| subconjuntos mo20 | 0.3836·0.7055 + 0.1629·0.2945 | 0.3836, 0.7055, 0.1629, 0.2945 | ok |
| subconjuntos base | 0.491 / 0.165 | 0.4906 / 0.1648 | ok |
| k7v4 → k7v5 | 4.977e-4 → 4.881e-4; 5.225e-3 → 5.211e-3; 1.582 → 1.571 | idénticos | ok |
| 1k: total; filtro; neto | 0.333; 0.590; 1.49 | 0.3333; 0.5895; 1.4878 | ok |
| 1k: Σ\|unl\|; unl; lk | 9.1e-4 (0.3 %); −6.0e-4; +8.8e-3 | 9.148e-4 (0.32 %); −5.99e-4; 8.81e-3 | ok |
| tabla de tramos de 200 de 1k (5 filas × 9 columnas) | — | todas coinciden | ok |
| tramos 1k: con gas 0.380 → 0.426; nogas 0.162–0.177 | — | idénticos | ok |
| rej/Σ\|e\| nogas por paso: mediana; rango | 1.52; 1.21–1.79 | idénticos | ok |
| corr(rej, paso); corr(Σ\|e\| nogas, paso); corr(rej/Σ\|e\| nogas, paso); 1as dif. | 0.10; 0.91; −0.49; 0.91 | idénticos | ok |
| Σ\|e\|_nogas/vol_lim en 4 bancos | 1.94/1.94/1.98/2.04e-2 | 1.935/1.941/1.982/2.039e-2 | ok |
| k7v4_long: corr; tendencias; 1as dif.; por tramos | 0.97; 0.965/0.992; 0.46; 0.94…0.40 | 0.971; idénticos | ok |
| tabla k7_mo20/base (10 filas) | — | todas coinciden (k7_* = k7v3_*) | ok |
| rem/abs k7_mo20 por paso | med 0.574, 0.539–0.612 | 0.5740, 0.5391–0.6120 | ok |
| V_pois/V_eff | 3.87; med 3.91; 3.29–4.53; base 3.90 | idénticos | ok |
| tabla k7v3 (sd, medias, correlaciones, comp_abs, eos_abs) | — | coinciden | ok |
| 26.4×; 26.5×; 51×; 8e3×; 127× | — | 26.4; 26.46; 51.4; 7833; 126.5 | ok |
| tabla k7v4 (comp_abs 1.38/1.08, nogas 4.0e-4/2.8e-4, eos 1.95/1.93) | — | coinciden | ok |
| e_nogas ∈ [2.67e-3, 4.24e-3]; ≤ 0.29; [0.81, 1.29] | — | coinciden | ok |
| e_gas ∈ [−5.09e-3, −3.53e-3] | −3.53e-3 | −3.5248e-3 | objeción O1 |
| k7v4_long: rem_all 0.504; filtro 0.712; corr −0.234/0.999; 726 | — | coinciden | ok |
| k7v4_long: nolink; e2_nolink | 51 845; 7.47e-3 (0.36 %); 1.1e-14 | coinciden | ok |
| k7v4_long: 53 % ≥ 0.7; e/paso −2.96e-5 → −5.46e-5 | — | 0.529; coinciden | ok |
| tabla de tramos de 500 de k7v4_long (11 filas) | — | coincide | ok |
| «0.43 → 0.57 en 5.5 s» | 0.57 | máximo 0.570; final 0.528 | objeción O2 |
| k7v4_long FAIL | 1.878 (paso 284736); 2.42; 0.547; 300; 5.02e5 | idénticos | ok |
| tolerancias k7v4_long | 3.26e-10; resto −3.23e-14 | idénticos | ok |
| cota C-151/152 | 0.1165/−0.2244 (48 %); 24 %; 1.54e-3; 3.64e-2 | coinciden | ok |
| cota C-151/152 (cont.) | ≥ 31.8 %; 0.32…0.61; 0.43; 1.91–2.44; 4340; 4669 | coinciden | ok |
| e_out por tercios | +6.96e-2/+9.52e-2/+6.90e-2; sumas; corr | coinciden | ok |
| snapshots (nogas_vecinas.py): nogas; sobre poro seco | 407/406/412/488/482; 96.6…94.8 % | idénticos | ok |
| snapshots: caras; tolerancias 1e-3 y 5e-3 | 1214; 521/340/247/86/20 | idénticos | ok |
| snapshots: dirección; 320000 | 80.5 %, 3.2 % | idénticos | ok |
| celdas con 0 < α_g < 1e-2 (cmd de C-157) | 85/95/90/91/89; medianas 0.99/0.006 | idénticos | ok |
| ρ_g 0.304; masa 52.97/52.94; mediana 0.2275 (0.1375–0.341) | — | idénticos | ok |
| u_z −0.283/0.0107/0.757; 6.4 %; 8.5 % | — | idénticos | ok |
| bancos con CG convergido: identidad 0.101…0.000; peso 0.000–0.182 | — | coinciden | ok |
| bancos con CG convergido: rem_all/abs 0.134–1.007 (5 de 8 ≥ 0.7); con gas 0.160–1.010 | — | coinciden | ok |
| V_eff/V_pois nogas en esos bancos | ≤ 7e-10 | 7.2e-10 | objeción O5 |
| bancos fríos: EOS −18.71; ratios; e_multi por paso | 3.0e-4/3.9e-4/3.5e-3 | coinciden | ok |
| bancos fríos: Σ\|e\|/Σ\|eos\|; max_inner_pres 200; 0 avisos de CG | 2.1e-4/3.1e-4/3.0e-3 vs 1.94e-2 | coinciden | ok |
| barrido del checker (rewrites) | 78 PASS; 4.0e-12 | 78, 0 FAIL, 3.97e-12 | ok |
| barrido del checker (EOS) | 66 ≤ 4.0e-12 | 66, 3.985e-12 | ok |
| barrido del checker: líneas | 30/12/24 (22 + 2) | 30/12/22 + 2 | ok |
| avisos de CG (k7v5_mo20) | ≥ 1001/1180 | casos 1 y 1001 | ok |
| citas de código (pressure :210, :234-236, :652, :667-672, :1237, :1260, :1747-1751) | — | coinciden | ok |
| citas de código (continuity :418-421, :467; constants :88; solver :271-278; check_audit :470) | — | coinciden | ok |
| greps vacíos de la regla y del glosario | — | vacíos | ok |
| ledger.py check | OK | OK (167 eventos) | ok |

## Objeciones (todas no bloqueantes)

1. **O1, e_gas** (`research/ws/WS-K7/report.md:330` y `:415`): la cota superior dice −3.53e-3, pero el dato da −3.5248e-3, es decir −3.52e-3. Las cotas 0.16–0.42 y 58–84 % no cambian. Para levantarla: escribir −3.52e-3.
2. **O2, deriva de k7v4_long** (`research/ws/WS-K7/report.md:386`): «0.43 → 0.57 en 5.5 s» toma el máximo (tramo 4501–5000) como si fuera el final. El último tramo da 0.528, y {C-163} dice 0.53. Para levantarla: «0.43 → 0.53 al final (máximo 0.57)».
3. **O3, pre-registro no commiteado** (`.claude/rules/research.md`): HEAD solo llega a C-121. Está declarado (:444), y el orden de ts y mtime es correcto (C-144 13:01:46 < fuente 13:04:15 < binario 13:06:13 < audit 13:07:00 < C-145 13:38:13). Para levantarla: el coordinador commitea el registro antes de la próxima corrida pre-registrada.
4. **O4, logs de tests posteriores al veredicto** (`research/ws/WS-K7/logs/test_*.txt`, 20:12–20:30): src/ es el mismo y el binario es idéntico, pero el checker se editó después. Está declarado (:465). Para el cierre falta `test_quick=ok` sobre el diff_sha final.
5. **O5, «≤ 7e-10»** (`research/ws/WS-K7/report.md:454`): en `tests/out/bed_bath_rest_n4` el dato es 7.2e-10. Para levantarla: escribir ≤ 7.2e-10.

VEREDICTO: aprueba