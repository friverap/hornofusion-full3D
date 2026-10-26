# Revisión de evidencia: WS-K7, ronda 1 (revisor de evidencia)

He recalculado desde los datos cada número del reporte (`research/ws/WS-K7/report.md`) y he comparado el veredicto con el criterio pre-registrado. Trabajé en solo lectura: `csv`/`h5py` sobre los `audit.csv` y `.h5` existentes, `tests/integration/check_audit.py` (no escribe archivos), los dos scripts de `research/ws/WS-K7/scripts/` (h5py en modo `'r'`), `ledger.py show|check`, `git show`/`git diff --cached` y `sed`/`grep`. No leí `reviews/` (revisión ciega).

## Veredicto pre-registrado

El criterio de {C-144} (13:01:46) dice: SOPORTADA si rem_all/abs ≤ 0.3 **y** neto ≤ 0.3; REFUTADA si ≥ 0.7; en otro caso, SIN DECIDIR.

En k7v5_mo20, rem_all/abs = 5.2108e-3 / 1.6356e-2 = **0.3186** y neto = **1.5705**. Por la letra del criterio el resultado es **SIN DECIDIR**, que es lo que dice {C-145}. El reporte no reinterpreta el criterio: retira o cualifica en prosa las lecturas de mecanismo y limita el «sin decidir» a los 59 pasos.

Prerrequisitos de {C-144}, todos cumplidos:
- `mass_gas_rewrites` PASS en los tres bancos k7v5: −6.15e-14, −7.08e-14 y −5.41e-14.
- Barrido de los 78 bancos de `tests/out`: 0 FAIL, resto máximo 3.97e-12.
- `m_gas_liq_skip` = `m_gas_e2_skip` = 0 en los tres bancos k7v5.
- Identidad lk + unl con resto 1.2e-20 (2.4e-20 en base, 6.5e-19 en 1k), muy por debajo de 1e-12.
- Las 11 columnas exigidas son bit a bit iguales a k7v4. Solo difieren las 5 que dependen de E2.
- Tests: TESTS (full) OK, golden v131, 0 FAIL (6 XFAIL listados).

Comparación justa:
- Mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`), 15 ranks.
- Las configs de mo20 y base difieren solo en `max_outer`; `alpha_T` = 0.7 en ambas, en otra línea.
- El sha del diff staged de `src/` (0503d1f6…) coincide con el de `logs/opt_identidad.txt`, y el binario recompilado es byte a byte igual a `campaigns/bin/eaf3d_k7v5_opt`.
- La ventana corta y la deriva en las ventanas largas están declaradas.

## 1. Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| rem_all/abs k7v5_mo20 (mediana, rango por paso) | 0.319 (0.317; 0.302–0.381) | 0.3186 (0.3171; 0.3023–0.3814) | ok |
| Neto k7v5_mo20 / base | 1.571 / 1.320 | 1.5705 / 1.3196 | ok |
| k7v5_base rem_all/abs; con filtro mo20 / base | 0.404; 0.565 / 0.626 | 0.4038; 0.5651 / 0.6263 | ok |
| err_liq_all = lk + unl (mo20) | +4.881e-4 = +4.977e-4 − 9.58e-6 | idem; resto 1.19e-20 | ok |
| Σ\|unl\|: fracción de Σ\|e\|; cota sobre Σ\|err_liq_all\|; fracción del neto | 0.0013; ≤ 0.19 %; −2.0 % | 0.00132; 0.194 %; −1.96 % | ok |
| Nogas: vpois, veff, rej, rej/ng, rej/vpois | 4.078e-3, 1.1e-16, 7.655e-3, 1.59, 1.88 | 4.0782e-3, 1.087e-16, 7.6547e-3, 1.589, 1.877 | ok |
| m_spill; vol_lim | 1.3e-12; 0.249 | 1.27e-12; 0.2489 | ok |
| corr k7v5 mo20 / base | +0.233, +0.970, 0/59 / −0.428, +0.993 | idem | ok |
| Subconjuntos con gas / nogas (mo20; base) | 0.384 (70.6 %) / 0.163; 0.491 / 0.165 | 0.3836 (0.706) / 0.1629; 0.4907 / 0.1648 | ok |
| Tabla k7_mo20 / k7_base (12 cifras: e_multi … neto) | −8.555e-4 … 2.456 / −1.571e-3 … 0.856 | coinciden todas; mediana 0.574 (0.539–0.612) | ok |
| Tabla k7v3 (err_liq_all, nogas, 84 %, rem_all, comp/eos abs) | 4.977e-4, 3.454e-3, 7.85e-4, 5.225e-3, 2.271e-3, 0.4324 | idem (0.837; eos mediana 7.322e-3) | ok |
| k7v4: comp/eos por llamada, nogas | 3.125e-3 (1.38), 0.841 (1.95), 1.908e-6 (4.0e-4) | idem | ok |
| k7v5_mo20_1k: rem_all/abs, filtro, neto, unl, rej, rewrites | 0.333, 0.590, 1.49, 9.1e-4 (0.3 %), 1.53, −5.4e-14 / 14.4 kg | idem | ok |
| Tabla por tramos de 200 de 1k (45 cifras), 0.83–0.85, corr dif 0.98, rej 1.52 (1.21–1.79), corr 0.10/0.91/0.91 | — | todas coinciden | ok |
| k7v4_long: 5499 pasos, 0.504/0.712, −0.234/0.999/726, nolink 51 845 / 7.47e-3 (0.36 %) / 1.1e-14, 0.235 / 4.2e-4, 78.1 (38×) | — | idem | ok |
| k7v4_long: tolerancias 3.26e-10 / 7.8e-10 / 7.8e-8; 6 FAIL (1.878, 2.418, 0.547, 300, 5.017e5) | — | idem | ok |
| k7v4_long: medias por 1000 pasos (−2.96e-5 … −5.46e-5, ×1.85); tabla por tramos de 500 (66 cifras); 53 % ≥ 0.7; corr 0.97/0.965/0.992/0.46 y tramos | — | idem | ok |
| e_out por tercios +6.96e-2/+9.52e-2/+6.90e-2; e_multi + e_out; corr | — | idem | ok |
| Fila 280059 base ↔ long (dt, m_gas_err_multi) | 9.9999971e-4 / 1.0e-3; −2.61196e-5 / −2.61190e-5 | base / long, mismo orden | ok |
| {C-151}/{C-152}: 0.1165 frente a −0.2244 (48 %), 24 %, 31.8 %, 43.1 %, bloques 0.32…0.61, 0.43, 1.91–2.44, centinelas 4340/4669 | — | idem | ok |
| Composición: nogas 407/406/412/488/482; α_s < 5e-3; α_l ≥ 0.995; sobre poro seco 96.6…94.8 % | — | idem (h5py) | ok |
| Caras 1214 = 521/340/247/86/20; tolerancias 1e-3 y 5e-3; encima 395/391/399/467/462; casi saturado 31.2–37.9 % y 16.2–18.6 %; receptoras multifase; 88 perdidas | — | idem (`nogas_vecinas.py`) | ok |
| ρ_g 0.30428; masa 52.9735 frente a 52.937 (0.07 %); mediana 0.2275 (0.1375–0.3410); u_z −0.283/0.0107/0.757; 6.4 %/8.5 % | — | idem | ok |
| Estadísticas por paso k7_mo20/base (resto/err_liq, corr, vp/ve 3.91/3.87/3.29–4.53, 0.976/−0.853/−0.890, e_out 9.24e-4, eos/err_free de k7v4_base) | — | idem | ok |
| Envolvente por subconjuntos: e_nogas ∈ [2.67e-3, 4.24e-3], 0.294, [0.81, 1.29], e_gas ∈ [−5.09e-3, −3.53e-3], [0.16, 0.42] | — | idem | ok |
| sd(err_liq_all), sd(e) | 7.9e-7, 3.35e-6 | muestral 7.98e-7 / 3.38e-6 (poblacional 7.91e-7 / 3.35e-6) | objeción E1 |
| Tercios de la ventana corta | 0.323/0.318/0.318 | k7v5_mo20: 0.323/0.317/0.316; k7v4 (20/20/19): idem al reporte | objeción E2 |
| Bancos fríos: 1.331e-2 / 1.196e-1 / 8.771e-3; e_multi; serie de outer_conv; −18.71; 3.0e-4 / 3.9e-4 / 3.5e-3; 3.1e-4 / 3.0e-3 / 2.1e-4; −24 %; CG 200 sin avisos; tol_cont 1e-2; outer 21–24 | — | idem | ok |
| CG k7_mo20: avisos 1 y 1001 (res 3.245e-2); 1180 llamadas; 84.8 %; base, un aviso; n_pc_max = 1 | — | idem | ok |
| check_audit k7_base: FAIL 2.243 / 215.0; k7_mo20 0.050 / 163.5 | — | idem | ok |
| Logs de tests: 67 / 64, máx. 3.97e-12 / 3.985e-12; barrido 78 / 0 FAIL / 66 / 32-12-22 | — | idem | ok |
| Bit a bit k7 ↔ sonda_gc; k7 ↔ k7v3/v4 (≤ 2.4e-16); k7v4 r1 ↔ r2 | — | idem (2.42e-16; 108 columnas iguales) | ok |
| Invariantes k7v5 ↔ k7v4: «14 columnas» | 14 | 105 de 110 idénticas; difieren las 5 de E2 | objeción E5 (menor) |
| C-109: −16 %; m_melted 2.04; rx 5.4e-6; volfix −1.3e-5; clip 1.3e-12 / 4.7e-14 | — | idem | ok |
| Citas de líneas (pressure, audit, continuity, multiphase, config) | — | coinciden salvo dos | objeción E3 |
| Antecedentes: err_liq −2.956e-3 «instrumento permanente» | — | es de k7_mo20/k7v4; k7v5 −2.966e-3 | objeción E4 |
| `reviews/r4-auditor-eaf3d.md:5` | APRUEBA | no leído (revisión ciega) | objeción E6 |
| Cronología del pre-registro de {C-144} | ts + mtime | consistente; no commiteado (declarado) | objeción E7 |

## 2. Objeciones (ninguna bloqueante)

1. **E1** `report.md:167,298`: sd 7.9e-7 / 3.35e-6. Con la sd muestral salen 7.98e-7 / 3.38e-6; las cifras del reporte son poblacionales, y en el mismo texto la sd de e aparece como «3.4e-6», que es la muestral. El cociente 0.236 y el 0.9717 no cambian. *Para levantarla:* declarar pstdev y unificar la convención.
2. **E2** `report.md:322`: tercios 0.323/0.318/0.318 sin banco ni comando. En k7v5_mo20 dan 0.323/0.317/0.316. *Para levantarla:* rotular k7v4_mo20 y el corte 20/20/19, o recalcular en k7v5_mo20.
3. **E3** La tolerancia está en `tests/integration/check_audit.py:453`, no en `:451` (la edición de la ronda 13 desplazó las líneas). En HEAD, `Fs_r = af*u_f*Ar` está en `src/mod_pressure_3d.f90:1237`, no dentro de `:1232-1236`. *Para levantarla:* actualizar los números de línea.
4. **E4** `report.md:289`: el −2.956e-3 es de k7_mo20/k7v4. Con el instrumento vigente (k7v5_mo20) da −2.966e-3. *Para levantarla:* rotular el banco.
5. **E5** «14 columnas» bit a bit: la lista no está escrita. *Para levantarla:* listarlas o decir «todas las comunes salvo las 5 de E2».
6. **E6** El veredicto del auditor en la ronda 8 no es verificable bajo revisión ciega. *Para levantarla:* comprobación del coordinador.
7. **E7** El pre-registro no está commiteado (declarado como E9). Comprobé el orden con el ts del registro y los mtime: 13:01:46 < 13:06:13 < 13:07:00 < 13:38:13, y `ledger.py check` da OK. *Para levantarla:* commit del registro antes de la próxima corrida pre-registrada.

Ninguna objeción toca el veredicto «sin decidir» de {C-145} ni las cifras que lo deciden (0.3186; 1.5705), ni los prerrequisitos de {C-144}. Todas son de procedencia, convención o rótulo en cifras descriptivas.

VEREDICTO: aprueba