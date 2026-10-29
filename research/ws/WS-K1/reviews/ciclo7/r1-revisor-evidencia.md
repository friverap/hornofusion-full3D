## Revisión de evidencia: WS-K1, ronda 1

Revisé `research/ws/WS-K1/report.md` contra el registro (`ledger.py show/open/check`) y contra los datos de `campaigns/b1/`. Todo fue de solo lectura: no corrí simulaciones ni compilé. No leí las revisiones de otros revisores.

### Pre-registro y veredicto

- **C-011 (H1).** El criterio está en `docs/PLAN_K_limitador_en_poisson.md` §4, commit c298555 (16:48:17). Es anterior a `k1_342/config.dat` (16:52:37), así que el pre-registro vale. El veredicto C-012 es «refutada». Aunque la tolerancia de v1 no se pueda verificar, el inciso «|p| sonda < 20 kPa» falla con cualquier lectura: |p| ≥ 20 kPa en todos los pasos de 342518 a 342560.
- **C-025 (H1b).** Se registró a las 17:32:08 (commit fecc672), antes de `k1b_342/config.dat` (17:58:19). No tiene enmiendas. Comparé el criterio literalmente con lo medido en k1b_342:

| Inciso | Umbral | Medido | Resultado |
|---|---|---|---|
| (a) osc2 | ≤ 1000 | 885.7 | pasa |
| (b) grad_hid_max | ≤ 3 | 70.57 | **falla** |
| (c) cent_pg | ≤ 2.7 | 2.7 | pasa |
| (c) p>100k | ≤ 3.2 % | 5.4 % | **falla** |
| (d) sin converger | ≤ 5 % | 0.9 % | pasa |
| (e) vol_lim | ≤ 2.605e-3 | 2.4596e-3 | pasa |

  El veredicto C-028 «refutada» respeta la letra del criterio. El reporte no lo reinterpreta: las lecturas post hoc van marcadas como «sin valor de veredicto».
- **Comparación justa.** Base diag_p342b y los cuatro brazos K:
  - Mismo reinicio: `diag_p342a/eaf3d_00342450.h5`.
  - Misma ventana: 111 filas.
  - Mismo número de procesos: 12 (2×3×2).
  - `config.dat` idéntico salvo `output_dir` y las claves de Plan K. Entre k1pa y k1pb solo difiere `pc_ai_tol`.
  - El binario no es verificable (O7).
  - Muestra corta, con 2 pasos de artefacto de reinicio. El reporte lo declara, y aun sin esos pasos (c) falla: 4/109 frente a 3.49 permitidos.
- **Registro.** `ledger.py check` da OK (313 eventos). `open` da 0 abiertas. Hay 16 raíces de WS-K1: 4 refutadas, 9 fallidas y 3 soportadas (reproducido con el comando del reporte).

### Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| plank_conv k1_342 (tol por defecto) | 205/205, it 8.00 | 205/205 (100 %), it 8.00 | ok |
| plank_conv k1_342 --tol 1e-3 | 0/205 | 0/205 | ok |
| p_max sonda k1_342, 342500–560 | 69 967.7 en 342539 | 69 967.7 en 342539 | ok |
| p sonda en 342540 (C-012) | 69.1 kPa | 69 103 Pa | ok |
| \|p\| ≥ 20 kPa desde | 342518 | 342518 | ok |
| osc2 k1_342 / base | 342 / 51.8 k | 342.3 / 51 835.2 | ok |
| k1b osc2 / grad_hid_max | 885.7 / 70.57 | 885.7 / 70.57 | ok |
| k1b, 342510–533: osc2 / ag_min | 6874 / 0.01500 | 6874.3 / 0.01500 | ok |
| k1pa, 342510–533: osc2 / ag_min | 209.5 / 0.01834 | 209.5 / 0.01834 | ok |
| k1pb osc2 (510–533 / 500–560) | 6876 / 889.7 | 6876.0 / 889.7 | ok |
| base, 342510–533: osc2 | 23 362 | 23 362.5 | ok |
| \|d2p\|>1000: base / k1 / k1b / k1pa / k1pb | 85 / 22 / 47 / 22 / 47 % | 0.847 / 0.220 / 0.475 / 0.220 / 0.475 (50/13/28/13/28 de 59) | ok |
| p75 de \|d2p\| | 112.0k / 730 / 14559 / 721 / 14565 | 111 994 / 730 / 14 559 / 721 / 14 565 | ok |
| máx de \|d2p\| | 333.8k / 3729 / 218858 / 3728 / 218864 | 333 796 / 3729 / 218 858 / 3728 / 218 864 | ok |
| regime2 342.45–56, p>100k: base / k1 / k1b / k1pa / k1pb | 6.3 / – / 5.4 / 1.8 / 5.4 | 6.3 / 1.8 / 5.4 / 1.8 / 5.4; pmax 8.03e5 | ok |
| pasos con p_max > 1e5 (audit.csv) | base 7, k1b/k1pb 6, k1/k1pa 2 | 7 / 6 / 6 / 2 / 2, con los pasos listados | ok |
| paso 342450 | 9.52e4 | 95 224.7 | ok |
| p_max en 342451 / 342452 | 8.045e5 base, 8.030e5 K / 1.6401–1.6404e5 | 8.0451e5, 8.0298e5 / 1.64006–1.64035e5 | ok |
| k1b sin conger. (tol 1e-3) / k1pb (tol 1e-6) | 0.9 % / 99.8 % (C-038) | 5/550 / 549/550 | ok |
| vol_lim medio base / K | 2.481e-3 / 2.460e-3 (−0.8 %) | 2.4807e-3 / 2.4596–2.4600e-3 (−0.84 a −0.85 %) | objeción O4 |
| vol_unlinked medio | 2.057e-3 en todas | 2.057e-3 en las cinco | ok |
| dense_340_n14, (1,59,9) | 74.5, 94.0, 42.6, 108.0, 42.9, 636.0 kPa; 342530 = 48.8 en otra celda | 74.46, 94.03, 42.65, 107.96, 42.88, 635.97; 342530 = 48.84 en (1,19,7) | ok |
| reinicio de dense_340_n14 | judge_otp_280/…340000 | igual | ok |
| k1b, 342538–560: mín / máx | 27 411.7 (342544) / 36 507.4 (342539) | igual, 23 pasos | ok |
| pico de la sonda k1b | 410 kPa en 342.534 s | 409 994.6 en 342534 | ok |
| amplitud base / k1b | 3.4× | 3.40 | ok |
| C-030: celdas sumergidas | 242 / 45 / 73 | 242 / 45 / 73 (submerged_bed.py) | ok |
| regime2 340–345.5, cent_pg | k1_340 0.5/1.1/0.7; n12 0.4/0.3/0.1; n14 0.2/0.2/0.3; n15 0.1/0.2/12.8 | igual | ok |
| p>100k base (3 ventanas) | 2.3/4.1/2.2; 10.3/9.8/7.2; 23.9/20.2/31.5 | igual | ok |
| p>100k K (3 ventanas) | 0.1×4; 1.6/1.4/1.6/2.4; 6.7/6.5/8.5/26.4 | igual | ok |
| p>100k en 344–345.3 s | base 25.1/20.8/35.2; K 6.4/6.6/9.0/15.1 | igual | ok |
| C-310/C-311: pasos ≥ 1e6 | base 1/4/19; n15 183 (122 en 2e6) | 1/4/19; 0/0/183 (122) | ok |
| diag_k15_k_off | 1.551e5 → 2.0e6 → 1.797e6; 10 filas ≥ 1e6 | igual | ok |
| recuentos [PROBE-*] (MOM/loc/P/AI/pmax) | según el reporte | 205/2214/410 (k1); 550/5940/1650 (k1b/k1pa/k1pb); AI 2971/3211, pmax 571/1056 | ok |
| «pp tras conjunto activo» | 0/550/550/550 | 0/550/550/550 | ok |
| caras fijas en 342451: k1b / k1pa | 34 / 37 | 34 / 37 | ok |
| `index` del parche frente a blobs de 1bc9832 | 412cfd5, 3c1948e, c01f606 | coinciden | ok |
| v2_completo frente a plan_k_v2 | idénticos | cmp: idénticos | ok |
| commits de src desde 1bc9832 / 79dc27b en mod_pressure | 7 / 32 líneas | 7 / 32 | ok |
| `git apply --check` | falla en mod_pressure_3d.f90:733 | igual | ok |
| archivos de src con `pc_alpha_implicit` | 0 | 0 | ok |
| D2.2 / D2.2c (dev-history) | 15.2/8.1, 11.2/4.7; 17.1/15.1 frente a 4.9/4.4 | igual | ok |
| diff staged de acople-pv.md | 42 líneas | 48 (39+/9−) | objeción O1 |
| grep D2.2 en .claude/rules | 0 | 8 líneas | objeción O2 |
| holgura de k1_340 | ~0.4 % | sin dato; 0.33 puntos medidos en k1_342/k1pa_342 | objeción O3 |

### Objeciones (ninguna bloqueante)

1. **O1.** `report.md:467` dice `acople-pv.md 42 líneas`; `git diff --cached --numstat` da 39+/9− = 48. **Para levantarla:** corregir la cifra.
2. **O2.** `report.md:467` dice que el grep `D2.2\|pc_limiter_faces` devuelve 0; en disco devuelve 8 líneas (acople-pv.md:673–690, del diff staged). **Para levantarla:** retirar el grep o fecharlo en HEAD.
3. **O3.** `report.md:248` da «~0.4 % de holgura» para k1_340 sin procedencia. Lo medido son 0.33 puntos, y en k1_342/k1pa_342, no en k1_340. **Para levantarla:** citar el ag_min medido o quitar la cifra.
4. **O4.** `report.md:280` da vol_lim −0.8 %. Recalculado: −0.84 % (k1) a −0.853 % (k1b). **Para levantarla:** escribir «−0.8 a −0.9 %».
5. **O5.** `report.md:323–325` atribuye a Plan D que sus «resultados» no se transfieren a B1. La fuente (dev-history:424–425) solo lo dice de las mejoras D2.2b y D2.4–D2.6. **Para levantarla:** usar la redacción de la entrada staged de acople-pv.md.
6. **O6.** `report.md:296`: «k1pa_342 pasó esa ventana» no dice con qué criterio. Pasó P-a (C-037); con C-025 fallaría el inciso (b) (grad_hid_max 10.52 > 3). **Para levantarla:** nombrar el criterio.
7. **O7.** No verificable que k1b_342 y k1pa_342 usen los binarios que exigen C-025 y C-035; el reporte lo declara. **Para levantarla:** hash del binario o recompilación bit a bit sobre 1bc9832. No bloquea, porque `fallido` (G1 no cumplida) se sostiene también por H1 (C-012).

### Conclusión

Todos los números de los que depende el cierre se reproducen dentro del redondeo mostrado. Las refutaciones de C-011 y C-025 siguen la letra de criterios registrados antes de las corridas, y las lecturas post hoc van marcadas como tales. El estado propuesto, `fallido`, es coherente con la meta G1 de `research/QUESTION.md`. Las objeciones son erratas de procedencia o de precisión que no cambian ninguna conclusión.

VEREDICTO: aprueba