# Revisión de evidencia: WS-K7, ronda 1 (lanzamiento posterior a la ronda 10)

Revisor: revisor-evidencia. Solo lectura: no ejecuté make, corridas ni binarios. Raíz: `/Users/frariv/Horno/hornofusion-full3D`.
Predicción vigente (status.json): {C-144} → veredicto {C-145}. `ledger.py check`: OK (149 eventos). No hay enmiendas a {C-144}.

## Criterio pre-registrado frente al veredicto

El criterio de {C-144}, literalmente, se juzga sobre k7v5_mo20 con las 59 filas de step > 280000:
- **Soportada** si rem_all/abs_multi ≤ 0.3 **y** |Σe_multi − Σerr_liq_all| ≤ 0.3·|Σe_multi|.
- **Refutada** si rem_all/abs_multi ≥ 0.7.
- **Sin decidir** en cualquier otro caso.

Valores recalculados:
- rem_all/abs_multi = 5.2108e-3 / 1.63557e-2 = **0.3186**.
- Neto = |−8.5549e-4 − 4.8809e-4| / 8.5549e-4 = **1.5705**.

Resultado: **sin decidir**, que es lo que dicen el reporte y {C-145} (estado `en_disputa`). No hay reinterpretación. La deriva hacia la refutación en las ventanas largas se declara como límite del alcance y no cambia el veredicto. {C-135} tampoco se reinterpreta para aprobar: el reporte registra su inciso de correlación tal como está escrito y declara que el umbral se fijó después de conocer el dato (O5 de la ronda 5).

Prerrequisitos de {C-144}, todos verificados:
- `mass_gas_rewrites` PASS con tolerancia 1e-11: −6.15e-14, −7.08e-14 y −5.41e-14 en los tres bancos k7v5, y 78 bancos de tests/out con 0 FAIL y resto máximo 3.97e-12.
- liq_skip = e2_skip = 0 en los tres bancos k7v5.
- Identidad lk + unl: residuo de 1.2e-20, 2.4e-20 y 6.5e-19.
- Las 11 columnas exigidas son bit a bit iguales a k7v4 (105 de las 110 columnas comunes). Solo cambian las 5 que {C-144} anticipó.
- Logs: test-unit, test-quick y test-full OK con v131 y 0 FAIL.

**Comparación justa:** los tres bancos k7v5 arrancan del mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`), con 15 ranks y el mismo binario. Las configs solo difieren en `max_outer` (y en t_final/output_freq para el de 1000 pasos). Orden temporal: C-144 13:01:46 < binario 13:06:13 < audit 13:07:00 < C-145 13:38:13.

**Muestra:** 59 pasos tras el reinicio, con transitorio (p_max 9.5e4–9.96e4 en los pasos 2–3 frente a una mediana de 4.22e4). El reporte lo declara y limita el «sin decidir» a esa ventana. Los bancos `_1k` y `k7v4_long` no pasan check_audit y se reportan sin decidir.

## Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| rem_all/abs_multi, k7v5_mo20 (mediana por paso, rango) | 0.319 (0.317; 0.302–0.381) | 0.3186 (0.3171; 0.3023–0.3814) | ok |
| Inciso del neto, mo20 / base | 1.571 / 1.320 | 1.5705 / 1.3196 | ok |
| rem_all/abs_multi, base | 0.404 (0.401; 0.377–0.457) | 0.4038 (0.4010; 0.3774–0.4567) | ok |
| Con filtro, mo20 / base | 0.565 / 0.626 | 0.5651 / 0.6263 | ok |
| err_liq_all = lk + unl, mo20 | 4.881e-4 = 4.977e-4 − 9.58e-6; resto 1.2e-20 | 4.8809e-4 = 4.9768e-4 − 9.583e-6; 1.19e-20 | ok |
| Ídem, base | 5.022e-4 = 5.021e-4 + 1.64e-7; resto 2.4e-20 | 5.0224e-4 = 5.0207e-4 + 1.643e-7; 2.37e-20 | ok |
| Σ\|unl\|/Σ\|e\|; cota sobre Σ\|err_liq_all\|; neto unl | 0.0013 (base 0.0005); ≤ 0.19 %; −2.0 % | 0.00132 (0.00048); 0.194 %; −1.96 % | ok |
| Celdas sin gas: Σ\|ρV_pois\|, Σ\|ρV_eff\| | 4.078e-3, 1.1e-16 (base 4.086e-3) | 4.0782e-3, 1.087e-16 (4.0862e-3, 1.07e-16) | ok |
| rej/Σ\|e\|_nogas; rej/V_pois; V_pois/Σ\|e\|_nogas | 1.59; 1.88; 0.85 | 1.589 (base 1.595); 1.877; 0.847 | ok |
| m_spill; vol_lim | 1.3e-12; 0.249 | 1.27e-12; 0.2489 | ok |
| Correlaciones mo20 / base | +0.233, +0.970, 0/59 / −0.428, +0.993, 0/59 | idénticas | ok |
| Identidad de fila en celdas sin gas | 0.163 (base 0.165; 1k 0.162–0.177) | 0.1629; 0.1648; 0.162–0.177 | ok |
| Σ\|e\|_nogas/vol_lim en los 4 bancos | 1.94e-2, 1.94e-2, 1.98e-2, 2.04e-2 | 1.935e-2, 1.941e-2, 1.982e-2, 2.039e-2 | ok |
| Subconjunto con gas: Σ\|e\|; rem/abs | 1.154e-2 / 1.331e-2; 0.38 / 0.49 | 1.1539e-2 / 1.3308e-2; 0.384 / 0.491 | ok |
| 1k, totales | 0.333; 0.590; 1.49; Σ\|unl\| 9.1e-4 (0.3 %); 2e-14; 1.53 | 0.3333; 0.5896; 1.488; 9.148e-4 (0.32 %); 2.4e-14; 1.528 | ok |
| 1k por tramos de 200 (50 cifras) | tabla | todas coinciden | ok |
| 1k, rej/nogas por paso y correlaciones | mediana 1.52 (1.21–1.79); 1.61→1.48; 0.10/0.91; diferencias 0.91; V_pois/nogas 0.83–0.85, diferencias 0.98 | 1.521 (1.214–1.789); 1.609→1.480; 0.100/0.909; 0.911; 0.829–0.847; 0.984 | ok |
| 1k frente a mo20: primeras 59 filas | iguales salvo la 280059 | 1 fila difiere (280059) | ok |
| FAIL de k7v5_base y 1k | energy 2.243, regime 215.0; regime 209.0 | ídem | ok |
| Celdas sin gas por instantánea | 407/406/412/488/482 | ídem | ok |
| «Baño»: α_s < 5e-3, α_l ≥ 0.995, suma 1 | todas | todas: max α_s 4.99e-3, min α_l 0.99500, \|α_l+α_s−1\| = 0 (con mi script; nogas_vecinas.py no lo comprueba) | ok |
| Sobre poro seco | 393 (96.6 %) … 457 (94.8 %) | ídem | ok |
| Caras en 280059 | 1214: 521/340/247/86/20 | ídem | ok |
| Rangos en el resto de instantáneas | 42.8–43.0; 28.2–30.3; 10.2–20.3; 7.1–8.1 (17.0) | ídem | ok |
| Igualdad exacta α_g == 0.015 | pierde 88 de 391 | 88 de 391 | ok |
| Poro saturado con tolerancia 1e-3 / 5e-3 | 11.8–17.6 / 16.4–18.9 % | 11.6–17.2 / 16.2–18.6 % | **O3** |
| ρ_g medio; masa reconstruida | 0.304; 52.97 frente a 52.94 | 0.3043; 52.974 con caras exteriores a medio paso (52.922 si se recortan a R/H) frente a m_gas 52.937 | ok |
| ρ_g en celdas sin gas; fracción del volumen rechazado | mediana 0.228 (0.138–0.341); 6.4 % / 8.5 % | 0.2275 (0.1375–0.3410); 6.36 % / 8.50 % | ok |
| Tabla k7_mo20/k7_base (10 filas × 2) | — | todas coinciden (p. ej. 0.566/0.626; 2.456/0.856; 29 %/27 %) | ok |
| Por paso 0.574 (0.539–0.612); V_pois/V_eff 3.87 (mediana 3.91, 3.29–4.53; base 3.90) | — | ídem | ok |
| corr(err_liq, V_pois) 0.976; corr(err_liq, vol_lim) −0.853/−0.890; k7v3 +0.517/+0.708 | — | ídem | ok |
| resto/err_liq −0.707, sd 0.081, −0.95..−0.46; corr −0.850; base −0.46/0.10/−0.70..−0.27/−0.39 | — | ídem | ok |
| check_audit de k7_base / k7_mo20 | 2.243 (−4.688e3/2.090e3), 215.0; 0.050, 163.5 | ídem | ok |
| k7 frente a k7v3; sonda_gc_* | ≤ 2.4e-16; bit a bit en 60 filas | 2.42e-16; bit a bit | ok |
| Proceso 7 (datos actuales) | −3.97e-3; 4.440e-3; 0.271 | ídem | ok |
| Tabla k7v3 (9 filas × 2) | — | todas coinciden | ok |
| Σ\|eos\|: 26.4/26.5×; 8e3×; 127× de 3.42e-3 | — | 26.4/26.5; 7.8e3; 126.5 de 3.418e-3 | ok |
| sd 7.9e-7 / 3.35e-6; r 0.236; fórmula 0.9717 con mínimo en ρ = r | — | sd poblacional 7.91e-7/3.349e-6; 0.236; 0.9717; mínimo analítico en ρ = r | ok |
| Cotas por subconjunto | [2.67, 4.24]e-3; 0.29; [0.81, 1.29]; [−5.09, −3.53]e-3; [0.16, 0.42]; 71 %; 58–84 % | ídem | ok |
| e_out y tercios | 9.24e-4; −0.09/0.00/−0.004; +6.96/+9.52/+6.90e-2; +1.36/+2.25/−2.67e-2 | ídem | ok |
| Tabla k7v4 (11 filas × 2) y 51× | — | ídem (1.38/1.08; 4.0e-4/2.8e-4; 1.95/1.93; 51.4) | ok |
| k7v4 frente a k7v3 | bit a bit salvo las columnas redefinidas | solo difieren comp_abs y eos_abs | ok |
| k7v4_long: pasos, ranks, duración | 5499, 15 ranks, 34 min | ídem (11:08:47 → 11:42:54) | ok |
| k7v4_long: rewrites y tolerancia antigua | −3.23e-14; 78.35; 3.26e-10 | ídem | ok |
| k7v4_long: 6 FAIL | 1.878 (284736); 2.42; 0.547; 300; 5.02e5 | ídem | ok |
| k7v4_long: clase nolink y correlaciones | 51 845; 7.47e-3 (0.36 %); 1.1e-14; 0.504/0.712; −0.234/0.999/726; 0.235 (4.2e-4); 78.1 (38×) | ídem | ok |
| Fila 280059, base frente a long | dt 9.9999971e-4 frente a 1.0e-3; −2.61196e-5 frente a −2.61190e-5 | ídem (base primero en ambos) | ok |
| e/paso por tramos de 1000; ×1.85 | — | ídem; 1.845 | ok |
| Tabla por tramos de 500 (66 cifras) | 4501–5000: err_liq_all 6.08e-3 | 6.07499e-3 | **O4** |
| 53 % de pasos ≥ 0.7; rem_all/abs en 0.377–0.698 | — | 52.9 %; ídem | ok |
| corr(nogas, vol_lim) 0.97; 0.965/0.992; diferencias 0.46; por tramos | — | 0.971; ídem; 0.464; ídem | ok |
| CG: ≥ 1001 de 1180 (84.8 %), res 3.2e-2 | — | ídem en los logs | ok |
| CG: «aviso solo en el caso 1 y el 1001» | — | uno de cada 1000 | **O5** |
| clip, rx, volfix, m_melted | 1.3e-12 (máx. 4.7e-14); 5.4e-6; −1.3e-5; 2.04 | ídem | ok |
| Transitorio; tercios de la ventana corta | 1.0e5 frente a 4.2e4; 0.323/0.318/0.318 | ídem (k7v3/k7v4 con 20/20/19; en k7v5: 0.323/0.317/0.316) | ok |
| Logs de tests; grep -c | OK, v131, 0 FAIL; 67/64 | ídem | ok |
| Barrido de tests/out | 78, 0 FAIL, 4.0e-12; 66; 32 con datos / 34 n/a (22 + 12) | 78, 0, 3.97e-12; 66 (3.99e-12); 32/34 (22 + 12) | ok |
| HEAD | 6579277 hasta C-121 | ídem | ok |
| Líneas de src (mapa de la ronda 8, rondas 9–10) | — | mod_pressure_3d, mod_audit, mod_continuity, mod_multiphase y mod_config coinciden | ok |
| Línea de check_audit.py | :434 | :443 | **O2** |
| Binario de la ronda 10 idéntico a k7v5_opt | cmp idéntico | no verificable (exige make) | **O1** |

## Objeciones (ninguna bloqueante)

1. **O1, no verificable.** {C-149} afirma que `make clean && make opt` da un binario idéntico a `campaigns/bin/eaf3d_k7v5_opt`. No puedo comprobarlo:
   - `bin/eaf3d_mpi` es hoy la compilación de desarrollo de los tests (16:58:53, 2.3 MB, sha 8d39276b), no la -O3 (`eaf3d_k7v5_opt`, 13:06:13, 1.25 MB, sha 28a31905).
   - Después del binario solo cambió `src/mod_audit.f90` (16:57:25), y no queda versión previa: lo staged coincide con el árbol de trabajo.
   - Corroboración parcial: las líneas 899–1086 del mapa de la ronda 8 no se desplazaron, y `obj/mod_audit.o` (16:58:22) es posterior a la edición.
   - Se levanta guardando en `logs/` la salida fechada de cmp y los sha256 de ambos binarios, o repitiendo la comprobación en la compuerta.
2. **O2.** `tests/integration/check_audit.py:434` → hoy es `:443`.
3. **O3.** Las cifras de sensibilidad a la tolerancia (11.8–17.6 % y 16.4–18.9 %) no llevan comando y no se reproducen: obtengo 11.6–17.2 % y 16.2–18.6 %. La conclusión («minoría») no cambia. Hay que añadir la tolerancia como argumento a `nogas_vecinas.py` y citar sus cifras.
4. **O4.** `k7v4_long`, tramo 4501–5000: err_liq_all es 6.075e-3, que con 3 cifras se escribe 6.07e-3 (el reporte pone 6.08e-3). Cosmético.
5. **O5.** El aviso del CG se imprime en el caso 1 y uno de cada 1000 (`src/mod_solver_3d.f90:271-274`; `k7v5_mo20_1k/run.log` muestra 2001…9001). Las cifras de los 59 pasos no cambian.
6. **O6.** Quedan «pendientes» que la ronda 10 ya resolvió:
   - los comentarios de `src/mod_audit.f90:222-224` y `:1050-1052`;
   - SKIP/«n/a» en check_audit;
   - la conciliación de N1.

   Hay que marcarlos como resueltos en {C-149}.
7. **O7.** `.claude/rules/transporte-energia.md:220-224` conserva dos frases que el reporte retira: «99.9 %» (retirada en la ronda 9, E2) y «rechazada por el limitador … 1.6×» (el reporte declara que rej no se interpreta). Aun así, el reporte afirma que la regla se reescribió. Hay que corregir la regla (lo hace el coordinador) o cualificar la afirmación del reporte.
8. **O8.** «Ninguna cifra de este reporte sale ya de la primera corrida» contradice Proceso 7, que cita cifras históricas rotuladas como no reproducibles. Hay que acotar la frase a Resultado e Incertidumbre.

Ninguna objeción afecta al veredicto formal: el criterio de {C-144} da «sin decidir» con los valores recalculados, y todos los prerrequisitos se cumplen.

VEREDICTO: aprueba