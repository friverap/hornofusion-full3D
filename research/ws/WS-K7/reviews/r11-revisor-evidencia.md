## Revisión de evidencia: WS-K7, ronda 2 (mismo revisor que la ronda 1)

Revisé `research/ws/WS-K7/report.md` (diff de trabajo frente al staged: ronda 18) contra los datos y contra `ledger.py show` de C-144, C-145 y C-162..C-165. Solo lectura: python sobre CSV y HDF5, `nogas_vecinas.py` (no escribe) y `check_audit.py`.

### 1. Tabla

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| rem_all/abs, k7v5_mo20 (decide) | 0.319 | 5.2108e-3/1.6356e-2 = 0.3186 | ok |
| Mediana y rango por paso | 0.317; 0.302–0.381 | 0.3171; 0.3023–0.3814 | ok |
| Neto \|e_multi − err_liq_all\|/\|e_multi\| | 1.571 | 1.5705 | ok |
| Veredicto C-145 frente al criterio de C-144 | sin decidir | 0.3 < 0.319 < 0.7 y neto > 0.3 → sin decidir | ok |
| Prerrequisitos: skip, split, rewrites, bit a bit con k7v4 | cumplidos | 0 / ≤ 3.3e-20 / PASS (−6.15e-14, −7.08e-14, −5.41e-14) / 0 columnas distintas | ok |
| lk, unl, Σ\|unl\|/Σ\|e\| | +4.977e-4, −9.6e-6, 0.13 % | +4.9768e-4, −9.583e-6, 0.132 % | ok |
| Expectativa (i), «en base mayor» | NO cumplida (8.73e-6 frente a 2.16e-5) | 8.734e-6 frente a 2.158e-5 | ok |
| 0.3836 × 0.7055 + 0.1629 × 0.2945 | 0.319 | 0.3186 | ok |
| Base con gas / nogas | 0.491 / 0.165 | 0.4906 / 0.1648 | ok |
| e_gas, cota superior (:308, :393) | −3.53e-3 | −3.5248e-3 | objeción E1 (no corregida) |
| Ronda 18, O1: rem_all/abs en tests/out | 0.620, 0.134, 0.830, 0.868, 1.000, 0.541, 1.007, 0.964 | idénticos | ok |
| Cociente con gas / peso nogas | 0.160–1.010 / 0.000–0.182 | 0.160–1.010 / 0.000–0.182 | ok |
| Bandas de los 8 bancos | 5 ≥ 0.7, 2 sin decidir, 1 < 0.3 | 5 / 2 / 1 | ok |
| Brechas nogas (CG convergido) | 0.101 … 0.000; excepciones 0.494 y 0.512 | idénticas, 0 AVISO | ok |
| O2: nogas sobre poro seco en los bancos de test | 0 % (0/664 … 0/208) | idéntico; además 0 en TODOS los snapshots | ok |
| O2: B1 a 280000 | 96.6 % (393/407); 43.0 % (527/1226) | idéntico | ok |
| O3: ALPHA_PORE_GAS | 0.015, `src/mod_constants.f90:88`; pore_floor :438 | 1.5e-2 en :88; fórmula en :438; pore_floor_on = true por defecto | ok |
| O3: nogas que son baño | 407/407; 564/564 | idéntico | ok |
| O3: a 320 s | 80.5 % (454/564); 3.2 % (51/1612) | idéntico | ok |
| k7v5_mo20_1k por tramos de 200 pasos | 0.314→0.349; 0.568→0.605; nogas 0.30–0.31 | idéntico | ok |
| k7v4_long, deriva | «0.43 → 0.57 en 5000 pasos» y «… en 5.5 s» | tramos de 500: 0.427 → 0.570 (tramo 10) → 0.529 (último); C-163 dice 0.53 | objeción E6 |
| k7v4_long, % de pasos ≥ 0.7 con filtro | 53 % | 52.9 % | ok |
| check_audit de los bancos k7v5 (:283) | solo mo20 pasa; base FAIL energy 2.243 y regime 215; 1k FAIL regime 209 | idéntico | ok |

### 2. Juicio contra el criterio pre-registrado

El criterio de C-144 (13:01:46, antes del binario y de las corridas) es SOPORTADA si el cociente ≤ 0.3 y el neto ≤ 0.3; REFUTADA si el cociente ≥ 0.7; en otro caso, sin decidir. Con 0.3186 y 1.5705 la letra da «sin decidir», que es lo que dicen C-145 y el reporte. No hay enmienda posterior al veredicto.

La ronda 18 solo retira o restringe: el contrafactual 0.279, «no es solo un artefacto del CG» y la diferencia de población con Plan E pasa a ser «por definición». No amplía ninguna conclusión. Todas sus cifras se reproducen. La afirmación «0 % sobre poro seco» la comprobé en todos los snapshots de los 11 bancos, no solo en el final.

La comparación es justa: mismo reinicio (`judge_otp_280/eaf3d_00280000.h5`), misma ventana de 59 pasos, mismo binario y columnas invariantes bit a bit con k7v4. El reporte declara que 59 pasos tras el reinicio no representan el régimen y que las ventanas largas derivan hacia la refutación.

### 3. Objeciones (ninguna bloqueante)

1. **E1** (de la ronda 1, sin corregir). `report.md:308` y `:393` dicen −3.53e-3; el valor es −3.5248e-3. Para levantarla: escribir −3.52e-3.
2. **E2** (se mantiene). El registro no está commiteado: HEAD llega a C-121, el índice a C-162 y el archivo de trabajo a C-165. Está declarado y el veredicto es nulo.
3. **E3** (se mantiene). Los tests del prerrequisito se acreditan con logs posteriores al veredicto. Está declarado.
4. **E4** (se mantiene y la ronda 18 la refuerza). El banco no está convergido como exige el «convergida» de C-121, y el «sin decidir» no resiste a la refutación. Pendiente: max_inner_pres 200, pre-registrado.
5. **E5** (se mantiene). Hay cifras históricas no reproducibles, rotuladas y fuera del veredicto.
6. **E6** (nueva). La deriva de `k7v4_long` aparece como «0.43 → 0.57 en 5.5 s» en `report.md:364` y como «0.43 → 0.53» en C-163. El 0.57 es el tramo 10 y el último tramo vale 0.529. Para levantarla: unificar las cifras.
7. **E7** (nueva). `status.json` registra revisor-evidencia = rechaza en la ronda 1, frente al «aprueba» que me pasaron como mi veredicto de la ronda 1. Lo debe conciliar el coordinador; no es verificable sin leer reviews/.
8. **E8** (nueva, observación). `.claude/rules/transporte-energia.md:182-185` conserva el 0.279 retirado y `:211-213` no tiene el matiz de C-165. Está declarado como trabajo del coordinador.

VEREDICTO: aprueba
