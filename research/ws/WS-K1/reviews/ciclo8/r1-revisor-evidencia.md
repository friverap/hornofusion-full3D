# WS-K1, ronda 1. Revisor de evidencia

Revisión ciega: no leí `research/ws/WS-K1/reviews/`. Solo lectura. Recalculé cada número con `cell_series.py`, `regime2.py`, `plank_conv.py`, `submerged_bed.py`, python (h5py/csv) sobre los `audit.csv`, los snapshots y los npz existentes, más `git show`/`grep`/`sed`.

## Veredicto frente al criterio pre-registrado

- **C-025 (H1b):** no tiene enmiendas en el registro. Con el criterio literal:
  - (b) falla: `grad_hid_max` 70.57 > 3.
  - (c) falla: p>100k 5.4 % > 3.2 %.
  - Conclusión: refutada {C-028}. Correcto.
- **Precisión del inciso (c):** sin redondear, cent_pg = 3/111 = 2.703 % > 2.7 %, igual que la base. Por la letra, (c) también falla por cent_pg. El veredicto no cambia (O5).
- **Comparación justa:** mismo reinicio (`diag_p342a/eaf3d_00342450.h5`), 12 ranks 2×3×2, misma ventana y misma `config.dat` salvo `pc_ai_tol` y la ventana de sonda de k1_342. Lo que no es verificable es el binario (O7).
- **«G1 no cumplida»** se sostiene por la letra de C-012 y C-028. Las lecturas post hoc están marcadas como tales.

## Tabla

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| k1_342 sin converger, tol 1e-6 / 1e-3 | 205/205; 0/205 | 205/205 (it 8.00); 0/205 | ok |
| k1_342 \|p\| máx y paso; valor en 342540 | 69967.7 (342539); 69.1 k | 69967.7 (342539); 69103.1 | ok |
| \|p\| ≥ 20 kPa en 342518–342560 | sí | mín 20967 | ok |
| osc2 base → k1 | 51.8 k → 342 | 51835 → 342.3 | ok |
| k1b: osc2 / grad_hid_max | 885.7 / 70.57 | 885.7 / 70.57 | ok |
| k1b sin converger, tol 1e-3 | 0.9 % | 5/550 = 0.9 % | ok |
| vol_lim medio base / K | 2.481e-3 / 2.460e-3 (−0.8 %) | 2.4807e-3 / 2.4596–2.4600e-3 | ok |
| vol_unlinked medio | 2.057e-3 | 2.0569–2.0573e-3 | ok |
| \|d2p\| > 1000: base / k1 / k1b / k1pa / k1pb | 85 / 22 / 47 / 22 / 47 % | 50, 13, 28, 13, 28 de 59 | ok |
| p75 / máx de \|d2p\| | 112.0k/333.8k; 730/3729; 14559/218858; 721/3728; 14565/218864 | idénticos | ok |
| regime2 p>100k, ventana 342.45–342.56 | base 6.3; k1b y k1pb 5.4; k1 y k1pa 1.8 | idem; n 111 | ok |
| Pasos > 1e5 en audit | base 7; k1b y k1pb 6; k1 y k1pa 2 | mismos pasos | ok |
| 342451 / 342452 | 8.045e5 y 8.030e5; 1.6401–1.6404e5 | 8.045e5, 8.030e5; 1.64006–1.64035e5 | ok |
| Pasos permitidos 3.55 / 3.49; 4/109 = 3.7 % | — | 3.552 / 3.488; 3.67 % | ok |
| Ventana 342510–342533 | k1b 6874/0.01500; k1pb 6876; k1 y k1pa 209.5/0.01834; base 23362 | idem | ok |
| Razón de amplitud base/k1b | 3.4× | 3.40 | ok |
| k1b liso en 342538–342560 | 27.4–36.5 kPa | 27411.7 (342544) – 36507.4 (342539) | ok |
| dense_340_n14, celda (1,59,9) | 74.5/94.0/42.6/108.0/42.9/636.0; 48.8 | idem | ok |
| Firma vol_lim en 342451: k1pa / k1b − k1 | +1.3e-9 / −4.48e-7 | +1.348e-9 / −4.484e-7 | ok |
| Rango k1b y k1pb, 342451–342460 | −3.8e-8 a −4.5e-6 | −3.84e-8 a −4.48e-6 | ok |
| vol_unlinked de k1b en 342455 / 342458 | −6.3e-8 / −1.45e-7 | −6.29e-8 / −1.451e-7 | ok |
| vol_unlinked de k1pa «positivo» | positivo hasta +1.5e-8 | −2.3e-11 en 342451, luego hasta +1.51e-8 | objeción menor (O6) |
| k1pa_340_n12 − k1_340 | +7.1e-9; +7e-9 a +3.8e-7; vol_unl −4.1e-9 en 340007 | idem | ok |
| n14 y n15 frente a n12 | 3e-17 a 2e-14 | 2.9e-17 a 1.78e-14 | ok |
| base_340 frente a judge | ≤ 5e-15 | máx 5.30e-15 | objeción menor (O6) |
| p_max k1 frente a k1pa | < 1.4 Pa | máx 1.31 Pa | ok |
| regime2 340–345.5 s (cent_pg y p>100k, 7 corridas) | todas | coinciden | ok |
| regime2 344–345.3 s | base 25.1/20.8/35.2; K 6.4/6.6/9.0/15.1 | idem | ok |
| dm_liq / dE_liq en [340, 345.3) | 392.4–392.6 / 398.6–400.6 kg; 4.523–4.524 / 4.561–4.573e8 | idem | ok |
| k1_340, pmax en 344–346 s | 4.51e5 | 4.51e5 | ok |
| n15: pasos ≥ 1 MPa / en 2 MPa | 183 / 122 | 183 / 122 | ok |
| diag_k15_k_off | 1.551e5, luego 2.0e6 → 1.797e6, 10 filas | idem | ok |
| C-030 | 242/45/73 | 242/45/73 | ok |
| Afirmaciones raíz | 16: 4 / 9 / 3 | idem | ok |
| Commits de src desde 1bc9832; `git apply --check` | 7; falla en :733 | 7; falla en :733 | ok |
| Índices de blob; cmp de parches | 412cfd5/3c1948e/c01f606; idénticos | idem | ok |
| Recuentos PROBE en run.log | 0/550/550/550; 410 frente a 1650; 3211 frente a 2971; 37 frente a 34 | idem | ok |
| D2.2 / D2.2c en dev-history | 15.2/8.1, 11.2/4.7; 17.1/15.1 frente a 4.9/4.4 | idem | ok |
| Holgura medida «en k1_342 y k1pa_342», corregida en el §6 del plan | corregida | PLAN_K:101 dice «medida solo en k1pa_342» | **objeción O1** |
| Diff staged | acople-pv 42, PLAN_K 6 | 64 / 12 | objeción (O2) |
| grep D2.2 en .claude/rules | 0 | 9 en el árbol; 0 en HEAD | objeción (O2) |
| k1_340 «~0.4 % de holgura» | sin fuente | no medida en k1_340; k1_342 da 0.33 pp | objeción (O3) |
| «k1pa_342 pasó esa ventana» | pasó | grad_hid_max 10.52 > 3: falla (b) de C-025 | objeción (O4) |

## Objeciones

1. **O1 (bloqueante).** `docs/PLAN_K_limitador_en_poisson.md:101` (staged) dice «medida solo en k1pa_342».
   - El reporte (líneas 548–562 y 516–517) dice que esto se corrigió en acople-pv.md **y** en el §6 del plan. Solo se corrigió en acople-pv.md.
   - Los datos lo contradicen: k1_342 da ag_min 0.01834 y osc2 209.5 en 342510–342533.
   - Para levantarla: corregir esa línea en el diff staged, o retirar del reporte la afirmación de que está corregida.
2. **O2.** Procedencia desactualizada en `report.md:547`.
   - `git diff --cached --stat` da 64/12, no 42/6.
   - El grep de D2.2 da 9, no 0.
   - Las líneas 509–511 no mencionan lo de los ciclos 7 y 8, que también está en el diff.
   - Para levantarla: volver a correr los comandos y poner sus valores.
3. **O3.** `report.md:286`: «k1_340 (~0.4 % de holgura)».
   - No lleva {C-nnn} y contradice las líneas 225–226 (no hay sonda en las corridas de 340 s).
   - El valor medido en k1_342 da 0.33 puntos.
   - Para levantarla: atribuir la cifra a k1_342 y citar C-032, o quitarla.
4. **O4.** `report.md:340-341`: «k1pa_342 pasó esa ventana».
   - Por la letra de C-025 falla (b): `cell_series k1pa_342 --steps 342500,342560` da grad_hid_max 10.52.
   - Para levantarla: acotar la frase a la métrica de ciclo de C-035 y a p>100k.
5. **O5.** Inciso (c): cent_pg sin redondear es 2.703 % > 2.7 %.
   - Hay que declarar con qué precisión se juzgó. No cambia el veredicto.
6. **O6.** Erratas numéricas menores.
   - El máximo base frente a judge es 5.30e-15, no ≤ 5e-15.
   - vol_unlinked de k1pa vale −2.3e-11 en 342451 (no es positivo en todos los pasos).
   - Las referencias de línea de H0 son 613–618 y las de J-B 561–568.
7. **O7 (no verificable).** No se puede comprobar el binario de k1b_342 que exige C-025, ni el del brazo K del juez: no hay ejecutable ni commit en los run.log. Falta la recompilación con comparación bit a bit. El reporte ya lo declara; no cambia la conclusión.

Todos los demás números del reporte se reproducen dentro del redondeo mostrado. La única objeción que bloquea el cierre es O1: una afirmación falsa que el diff llevaría a la documentación permanente, y que el reporte da por corregida.

VEREDICTO: rechaza