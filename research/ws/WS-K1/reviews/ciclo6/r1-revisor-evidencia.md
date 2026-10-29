# WS-K1, ronda 1: revisión de evidencia (revisor-evidencia)

**Resultado: apruebo.** Recalculé desde los datos todos los números del reporte que sostienen el veredicto, y todos coinciden. El veredicto de H1b (C-025 → C-028, `refutada`) sigue la letra del criterio pre-registrado: (b) y (c) fallan. Encontré 4 objeciones, ninguna bloqueante: tres erratas en las notas de procedencia sobre el diff staged y una advertencia de que el binario no se puede verificar, que el propio reporte ya declara.

Lo hice en solo lectura: usé los scripts de diagnóstico, h5py y csv sobre archivos existentes, `git show`/`log`/`diff --cached` y `git apply --check`, que no escribe nada.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| plank_conv k1_342 (tol 1e-6) | 205/205 sin converger, it 8.00 | 205/205, 8.00 | ok |
| plank_conv k1_342 --tol 1e-3 | 0/205 | 0 (0.0 %) | ok |
| default de v2: tol 1e-6, max_it 8 | plan_k_v2.patch | líneas 10-11 | ok |
| \|p\| sonda ≥ 20 kPa en 342518-342560 | sí | 342517 = 18.5 kPa, 342518 = 21.0 kPa en adelante | ok |
| máximo de \|p\| en k1_342 | 69 967.7 Pa (342539); 342540 = 69.1 kPa | 69 967.7 (342539); 69 103 (342540) | ok |
| osc2 base → k1 | 51.8 kPa → 342 Pa | 51 835.2 → 342.3 | ok |
| C-025 (a) osc2 k1b, 342500-342560 | 885.7 | 885.7 | ok |
| C-025 (b) grad_hid_max k1b | 70.57 > 3 | 70.57 | ok (falla) |
| C-025 (c) regime2 k1b | cent_pg 2.7, p>100k 5.4 > 3.2 | 2.7 / 5.4 (n 111) | ok (falla) |
| C-025 (d) sin converger | 0.9 % | 5/550 = 0.9 % | ok |
| C-025 (e) vol_lim medio | 2.46e-3 ≤ 2.605e-3 | 2.4596e-3 | ok |
| \|d2p\| > 1000 Pa: base / k1 / k1b / k1pa | 85 / 22 / 47 / 22 % | 50, 13, 28 y 13 de 59 | ok |
| p75 / máximo de \|d2p\| (base, k1, k1b, k1pa) | 112.0k/333.8k; 730/3729; 14559/218858; 721/3728 | idénticos | ok |
| k1pb frente a k1b: osc2, p75, máximo | 889.7 / 14565 / 218864 | idénticos | ok |
| pasos con p_max > 1e5 en audit.csv | base 7; k1b y k1pb 6; k1 y k1pa 2 | idénticos, y los mismos pasos | ok |
| 342450 / 342451 / 342452 | 9.52e4; 8.045e5 frente a 8.030e5; 1.6401-1.6404e5 | 95 225; 804 512 y 802 982-802 984; 164 006-164 035 | ok |
| sin 342451/452 | k1b 4/109 (3.7 %) frente a 3.49; base 5 | 4/109 = 3.67 %; base 5 | ok |
| osc2/ag_min en 342510-342533 | k1b 6874/0.01500; k1pb 6876; k1pa 209.5/0.01834; base 23362 | 6874.3; 6876.0; 209.5/0.01834; 23362.5 | ok |
| razón de amplitudes | 3.4× | 23362.5/6874.3 = 3.40 | ok |
| pico de k1b | 410 kPa a 342.534 s | 409 994.6 Pa en 342534 | ok |
| k1b liso, 342538-342560 | 27.4-36.5 kPa | mínimo 27 411.7 (342544), máximo 36 507.4 (342539) | ok |
| dense_340_n14, celda (1,59,9) | 74.5, 94.0, 42.6, 108.0, 42.9, 636.0 kPa; 342530 en otra celda, 48.8 | idénticos | ok |
| regime2 340/342/344-345.5 | k1_340 0.5/1.1/0.7; n12 0.4/0.3/0.1; n14 0.2/0.2/0.3; n15 0.1/0.2/12.8 | idénticos; n15 pmax 2.00e6 | ok |
| base en 344-345.5 | 6.7-9.5 % | 6.7 / 7.2 / 9.5 | ok |
| solo k1_340 llega a 346 s (con f231_340 y npc3_340, que no son Plan K) | sí | último h5 00346000 en esas tres | ok |
| C-310/C-311 | 183 pasos seguidos ≥ 1 MPa, 122 en 2 MPa; base ≥ 1 MPa | 183 (345318-345500), 122; base 1/4/19 | ok |
| diag_k15_k_off | 1.551e5, luego 2.0e6 → 1.797e6, 10 filas ≥ 1e6 | idénticos; pc_alpha_implicit=false | ok |
| C-030 | 242/45/73 | 242/45/73 | ok |
| vol_lim y vol_unlinked | 2.481e-3 frente a 2.460e-3 (−0.8 %); 2.057e-3 | 2.4807e-3 frente a 2.4596-2.4600e-3; 2.0568-2.0573e-3 | ok |
| estados del registro | 16 raíces: 4 refutadas, 9 fallidas, 3 soportadas; 0 abiertas | idénticos; `ledger.py check` OK | ok |
| recuentos PROBE por paso | MOM 5, loc 54, P 10 frente a 15, «pp tras» 0/550/550/550 | idénticos | ok |
| PROBE-AI y pmax: k1pa frente a k1b; caras en 342451 | 3211/1056 frente a 2971/571; 37 frente a 34 | idénticos | ok |
| PROBE-LIM / ws_pc_unl en el run.log de k1*_342 | 0 | 0 | ok |
| pc_drift_source en los cinco brazos | true | true | ok |
| índices de los parches = 1bc9832 | 412cfd5, 3c1948e, c01f606 | idénticos | ok |
| v2_completo_sobre_HEAD frente a plan_k_v2 | idénticos | `cmp` sin diferencias | ok |
| git apply --check | falla en mod_pressure_3d.f90:733 | idéntico | ok |
| commits de src desde 1bc9832 | 7 | 7 (los hashes citados) | ok |
| 79dc27b | mod_pressure_3d 32 líneas | 32 | ok |
| src con pc_alpha_implicit | 0 | 0 | ok |
| D2.2 / D2.2c | 15.2/8.1, 11.2/4.7; 17.1/15.1 frente a 4.9/4.4 | idénticos (dev-history 2026-10-07) | ok |
| líneas citadas de acople-pv | 539-546, 560-566, 611-617, 266-274 | el contenido coincide | ok |
| diff staged de acople-pv.md | «16 líneas» | 33+/9− = 42 | **O1** |
| alcance del diff staged | «lo ÚNICO … ciclo 5» | también trae lo del ciclo 6 | **O2** |
| grep D2.2 en .claude/rules | 0 | 4 en el árbol staged (0 solo en HEAD) | **O3** |
| binario de k1b = «src post-auditoría» (C-025) | declarado no verificable | no verificable | **O4** |

## 2. Juicio contra el criterio pre-registrado

- **C-025 (H1b).** Basta con que falle un inciso, y fallan dos: (b) 70.57 > 3 y (c) p>100k 5.4 % > 3.2 %. La ventana, el reinicio (diag_p342a/eaf3d_00342450.h5), los 12 ranks, output_freq 1 y tol 1e-3 coinciden con el criterio. La base diag_p342b tiene el mismo reinicio y la misma ventana. El reporte no reinterpreta el criterio:
  - el «cumple solo en la mediana» de (a) sale de C-028;
  - todo lo post hoc va marcado «sin valor de veredicto»;
  - comprobé el artefacto del reinicio (C-290) con su propio recuento: aun sin 342451/452, (c) sigue fallando (4/109 frente a 3.49).

  `refutada` es correcto. No hay enmienda en la cadena.
- **C-011 (H1).** Falla el inciso de |p|: ≥ 20 kPa en 342518-342560 (C-012). La convergencia depende de una tolerancia no verificable en v1, y el reporte lo dice.
- **C-035 a C-038.** Las métricas cumplen los umbrales literales (AUSENTE: 209.5 ≤ 1000 y 0.01834 ≥ 0.0155; PRESENTE: 6876 ≥ 5000 y 0.01500 ≤ 0.0151). El reporte señala que la calibración con k1b es circular.
- **C-040 → C-041.** Las cifras se reproducen. La mejora en 2 de 3 trayectorias está marcada como observación fuera del criterio.
- **Tamaño de muestra.** Todo el análisis en 342 s es UNA trayectoria de 111 pasos, y el ciclo de la sonda ocupa unos 24 pasos. El reporte lo declara (k1b y k1pb son una sola trayectoria y la directiva «no reintentar» es más fuerte que los datos). No aprueba nada con esa muestra.
- **Conclusión del reporte.** «G1 no cumplida; estado `fallido`» es coherente con el registro: hay 0 afirmaciones abiertas y H1/H1b están refutadas.

## 3. Objeciones

1. **O1 (no bloqueante).** `report.md:425`, nota «acople-pv.md 16 líneas». `git diff --cached --numstat` da `.claude/rules/acople-pv.md: 33+/9−` (42). Para levantarla: citar 42 (33+/9−).
2. **O2 (no bloqueante).** `report.md:400-401` dice «lo ÚNICO que trae el diff staged … ciclo 5». El diff staged trae también lo del ciclo 6: `acople-pv.md:673-689` (D2.2/D2.2c), las «Salvedades» de k1b/k1pb y la viñeta de DECISIÓN. Contradice las líneas 410-421 del propio reporte. Para levantarla: decir que el diff trae los ciclos 5 y 6 en acople-pv y solo el ciclo 5 en PLAN_K §6.
3. **O3 (no bloqueante).** `report.md:425`, «grep -rn 'D2.2\|pc_limiter_faces' .claude/rules CLAUDE.md (0)». En el árbol staged da 4; solo en HEAD da 0. Para levantarla: decir que el 0 es de HEAD o poner 4.
4. **O4 (no bloqueante, no verificable).** C-025 exige un «binario de src post-auditoría», y ningún run.log de k1*_342 identifica el ejecutable ni el commit; `campaigns/bin` no tiene k1, k1b, k1pa ni k1pb. El reporte lo declara (Incertidumbre, 426-452). La refutación vale para lo que corrió en k1b_342. Para levantarla: el hash del binario o recompilar `plan_k_v2.patch` sobre 1bc9832 y comparar bit a bit.

Ninguna objeción toca un número que sostenga el veredicto ni la conclusión del cierre. O1-O3 describen mal el diff staged y conviene corregirlas antes del commit.

VEREDICTO: aprueba
