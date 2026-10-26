# WS-K7, revisión de evidencia (ronda 1)

**Resultado: apruebo.** Recalculé desde los datos todas las cifras del veredicto y sus prerrequisitos, y todas coinciden con el reporte. El veredicto «sin decidir» sale tal cual de la letra del criterio de C-144. Dejo 4 objeciones, ninguna bloqueante: un endpoint mal citado (O1), una lectura «en ambas direcciones» que se apoya en un banco con claves no por defecto (O2), el pre-registro sin commit (O3) y una muestra corta (O4).

Alcance: solo lectura. Usé `ledger.py show/check`, python con csv y h5py sobre archivos existentes, `check_audit.py` (que no escribe; grep sin `open(...,'w')`), `nogas_vecinas.py`, `rho_uz_nogas.py`, `grep`, `sed` y `git diff --cached | shasum`. No ejecuté `make`, `mpirun` ni binarios.

## Criterio frente al veredicto

El criterio de C-144 (13:01:46, sin enmienda) se evalúa sobre k7v5_mo20, en los 59 pasos con step > 280000:
- **Soportada** exige rem_all/abs ≤ 0.3 **y** |e_multi − err_liq_all| ≤ 0.3·|e_multi|.
- **Refutada** si rem_all/abs ≥ 0.7.
- En otro caso, **sin decidir (en_disputa)**.

Valores recalculados: rem_all/abs = 5.2108e-3 / 1.63557e-2 = **0.3186**, y el neto da **1.5705**. Por la letra, el resultado es **sin decidir**. Coincide con C-145 (estado en_disputa) y con el reporte. El reporte no aprueba nada que el criterio no apruebe:
- La expectativa (i) queda corregida como fallida en su tercera cláusula (C-162): Σ|unl| en base es 8.734e-6, menor que 2.158e-5.
- La (iii) se declara «por construcción, no informativa».

`ledger.py check`: OK (168 eventos).

## Tabla de verificación

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| rem_all/abs k7v5_mo20 (mediana; rango por paso) | 0.319 (0.317; 0.302–0.381) | 0.3186 (0.3171; 0.3023–0.3814) | ok |
| Neto k7v5_mo20 | 1.571 | 1.5705 | ok |
| k7v5_base: cociente / neto (mediana; rango) | 0.404 / 1.320 (0.401; 0.377–0.457) | 0.4038 / 1.3196 (0.4010; 0.3774–0.4567) | ok |
| Con filtro: mo20 / base | 0.565 / 0.626 | 0.5651 / 0.6263 | ok |
| err_liq_all = lk + unl (mo20) | +4.881e-4 = +4.977e-4 − 9.58e-6 | 4.8809e-4 = 4.9768e-4 − 9.583e-6; resto 1.2e-20 | ok |
| err_liq_all = lk + unl (base) | +5.022e-4 = 5.021e-4 + 1.64e-7 | 5.0224e-4 = 5.0207e-4 + 1.643e-7; resto 2.4e-20 | ok |
| Σ\|unl\|/Σ\|e\|: mo20 / base | 0.0013 / 0.0005 | 0.00132 / 0.00048 | ok |
| Σ\|unl\| / (Σ\|e\| − rem_all) | ≤ 0.19 % | 0.194 % | ok |
| unl/err_liq_all | −2.0 % | −1.96 % | ok |
| Celdas sin gas: Vpois, Veff, rej, rej/Σ\|e\|nogas | 4.078e-3, 1.1e-16, 7.655e-3, 1.59 | 4.0782e-3, 1.087e-16, 7.6547e-3, 1.589 | ok |
| rej/Vpois; Vpois/Σ\|e\|nogas | 1.88; 0.85 | 1.877; 0.847 | ok |
| m_spill; vol_lim | 1.3e-12; 0.249 | 1.27e-12; 0.2489 | ok |
| corr por paso mo20; base | +0.233, +0.970, 0/59; −0.428, +0.993 | +0.2333, +0.9702, 0; −0.4285, +0.9931 | ok |
| Columnas comunes con k7v4 que coinciden | 105 de 110; difieren 5 que dependen de E2 | 110 comunes; difieren exactamente las 5 citadas (mo20 y base) | ok |
| v4 → v5: err_liq_all, rem_all, neto, err_liq | 4.977e-4→4.881e-4; 5.225e-3→5.211e-3; 1.582→1.571; −2.956e-3→−2.966e-3 | igual | ok |
| mass_gas_rewrites (tol 1e-11) en k7v5 mo20 / base / 1k | −6.15e-14 / −7.08e-14 / −5.41e-14 (Σ\|dm\| 14.4) | igual (check_audit), PASS | ok |
| liq_skip, e2_skip, nolink en k7v5_* | 0 | 0 | ok |
| Barrido tests/out: rewrites; cierre EOS | 78 bancos, 0 FAIL, máx 4.0e-12; 66 evaluaciones | 78 PASS, máx 3.97e-12; 66 evaluaciones, máx 3.99e-12 | ok |
| Familia err_liq en tests/out: evaluada / 0.000 / n/a | 30 / 12 / 24 (22 + 2) | 30 / 12 / 24 (22 + 2) | ok |
| Tests: unit, quick, full | OK, golden v131 | logs: UNIT / quick / full OK, metrics_v131; los FAIL que aparecen son 6 XFAIL | ok |
| Identidad del binario | sha 28a31905…, diff staged de src/ 0503d1f6… | `git diff --cached -- src/` actual = 0503d1f6…; src/ y tests/ sin cambios después de los logs | ok |
| 1k: cociente, filtro, neto, Σ\|unl\|/Σ\|e\| | 0.333, 0.590, 1.49, 0.3 % | 0.3333, 0.5895, 1.4878, 0.32 % | ok |
| 1k: Veff/Vpois nogas; rej/Σ\|e\|nogas | 2e-14; 1.53 | 2.4e-14; 1.528 | ok |
| Tabla por tramos de 200 de 1k (las 10 columnas) | — | coinciden en las 5 filas | ok |
| 1k: rej/nogas por paso; corr con paso; primeras diferencias | mediana 1.52 (1.21–1.79); corr 0.10 / 0.91 / −0.49; 0.91 y 0.98 | 1.521 (1.214–1.789); 0.0996 / 0.909 / −0.488; 0.911 y 0.984 | ok |
| Brecha nogas mo20 / base; tramos 1k | 0.163 / 0.165; 0.162–0.177 | 0.1629 / 0.1648; 0.162–0.177 | ok |
| Media ponderada | 0.3836 × 0.7055 + 0.1629 × 0.2945 | 0.38357, peso 0.29448; da 0.31859 | ok |
| Cociente con gas por tramos (1k; k7v4_long) | 0.380→0.426; 0.521→0.682 | igual | ok |
| Tabla k7_mo20 / k7_base (filtro) | 0.566 / 2.456; 0.626 / 0.856; vp/ve 3.87 | 0.566 / 2.456; 0.626 / 0.856; 3.867 | ok |
| Tabla k7v3: nogas err_liq, rem nogas, 84 % | 3.454e-3; 7.85e-4; 84 % | 3.4540e-3; 7.847e-4; 83.7 % | ok |
| Cotas por subconjunto | e_nogas [2.67e-3, 4.24e-3]; e_gas [−5.09e-3, −3.53e-3]; 0.16–0.42 | igual | ok |
| sd por paso, media de e | 7.9e-7 / 3.35e-6 = 0.236; media −1.45e-5; 59/59 negativos | 7.908e-7 / 3.350e-6 = 0.2361; −1.450e-5; 59 | ok |
| k7v4 comp_abs, eos_abs (cocientes) | 1.38, 1.08; 1.95, 1.93; 26.4×; 51× | 1.376, 1.076; 1.946, 1.934; 26.44; 51.4 | ok |
| Ventana larga | 0.504, 0.712; corr −0.234 / 0.999; 726 pasos; nolink 51 845, 7.47e-3; 38× | 0.5037, 0.7125; −0.2342 / 0.9992; 726; 51 845, 7.467e-3; 38.1 | ok |
| Tabla de la ventana larga por tramos de 500 (11 filas) | — | coinciden todas | ok |
| Ventana larga, tramo final | «0.43 → 0.57 en 5.5 s» (línea 401) | 0.427 → 0.528 (máximo 0.570 en 4501–5000) | **O1** |
| e/paso por tramos de 1000 en la ventana larga | −2.96e-5 … −5.46e-5 | −2.959e-5 … −5.460e-5 | ok |
| Cota del complemento | 0.1165 / −0.2244 (48 %); 24 %; 31.8 %; 43.1 %; 1.91–2.44; bloques 0.32–0.61; pasos 4340 / 4669; 0.43 | igual | ok |
| e_out por tercios; corr | +6.96e-2, +9.52e-2, +6.90e-2; −0.09 / 0.00 / −0.004 | igual | ok |
| Composición de las celdas sin gas (5 snapshots y el de 320 s) | 407/406/412/488/482; 96.6 %…; 1214 caras … | salida idéntica de nogas_vecinas.py | ok |
| Celdas con 0 < α_g < 1e-2 | 85/95/90/91/89, baño en k = 1–3 | 85/95/90/91/89 | ok |
| ρ_g medio, masa de gas, u_z | 0.30428, 52.9735 kg (m_gas 52.94), u_z p10/med/p90 −0.283/0.0107/0.757 | igual (m_gas en 280059 = 52.937) | ok |
| Bancos convergidos (C-163): rem_all/abs | 0.620, 0.134, 0.830, 0.868, 1.000, 0.541, 1.007, 0.964 | igual; 0 avisos de CG en los 11 directorios | ok |
| «Ambas direcciones»: el banco bajo 0.3 | 0.134 cuenta como lado «cumplido» | ese banco corre con claves de Plan D/E no por defecto | **O2** |
| Bancos fríos | 1.331e-2 / 1.196e-1 / 8.771e-3; EOS −18.71; 3.0e-4 / 3.9e-4 / 3.5e-3 | igual; serie por paso de outer_conv igual; 0 avisos de CG | ok |
| Avisos de CG | ≥ 1001 de 1180 en mo20; 1 aviso en base | 2 avisos (1 y 1001) / 1 aviso | ok |
| Líneas de código citadas | mod_audit :1078 y :1086; mod_pressure :210, :652, :671-672, :1237, :1260, :1747; mod_constants :88; mod_config :96, :100, :111; mod_continuity :418-421, :467; check_audit :470 | el contenido coincide | ok |

## Justicia de la comparación

- Deciden un solo banco y una sola ventana, tal como se pre-registró: k7v5_mo20, 59 pasos desde judge_otp_280/eaf3d_00280000.h5.
- Base correcta: k7v5 frente a k7v4, con el mismo reinicio y las mismas configs. Solo cambian las 5 columnas que dependen de E2. El binario es idéntico byte a byte al del diff staged actual.
- k7v5_base y k7v5_mo20_1k solo se reportan, y ambos fallan check_audit:
  - base: energy_balance (2.243) y regime_gas (215);
  - 1k: regime_gas (209).
  
  El reporte lo declara.
- La muestra es corta: 59 pasos con transitorio. El reporte limita el veredicto a esa ventana (O4).

## Objeciones (ninguna bloqueante)

1. **O1.** Reporte, línea 401 (`campaigns/b1/k7v4_long/audit.csv`): «0.43 → 0.57 en 5.5 s» no es el valor final. El último tramo, 5001–5499, da 0.528; 0.57 es el máximo, en el tramo 4501–5000. **Para levantarla:** escribir «0.43 → 0.53 (máximo 0.57)», como ya dicen la línea 187 y C-163.
2. **O2.** «Frágil en AMBAS direcciones» y «1 bajo 0.3» se apoyan en un único banco, `tests/out/restart/bed_flood_n4_to_n4_s750:0.134`. Corre con claves de Plan D/E (pc_sat_open, pc_fs_liquid_face… = true; alpha_g_comp_min 0.01) y, según C-164, no sigue el camino de B1. Con claves por defecto quedan 6 bancos, entre 0.541 y 1.007, ninguno por debajo de 0.3. Además, «8 bancos distintos» cuenta el reinicio como banco distinto. **Para levantarla:** matizar la frase en el reporte y en la regla. El veredicto no cambia.
3. **O3.** El pre-registro no está commiteado (`research/ledger.jsonl`, HEAD 6579277 solo llega hasta C-121). El orden 13:01:46 < 13:06:13 < 13:07:00 sale de los ts del propio ledger y de los mtime. No es verificable de forma externa; está declarado (E9). **Para levantarla:** commitear el registro antes de la próxima corrida.
4. **O4.** La muestra es corta y la prueba poco exigente:
   - decide con 59 pasos tras el reinicio, con transitorio;
   - C-139 ya daba 0.3194, así que el resultado era casi previsible;
   - las ventanas largas derivan hacia la refutación, pero esos bancos no pasan check_audit.
   
   Está declarado. **Para levantarla:** k7v5_mo20 con max_inner_pres 200, pre-registrado, o ≥ 1000 pasos con 20 externas que pasen check_audit (coordinador).

## Nota de cierre

En `status.json` sigue `test_quick: null`. El cierre requiere además `ws-set test_quick=ok diff_sha=auto` sobre el diff exacto (README, «Cierre de un workstream»). No es una objeción de evidencia: es un paso pendiente de la compuerta.

VEREDICTO: aprueba