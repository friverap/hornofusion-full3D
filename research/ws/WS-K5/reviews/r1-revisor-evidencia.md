## Revisión de evidencia de WS-K5, ronda 1 (revisor-evidencia)

**Veredicto: aprueba.** Saco cada número del reporte de los datos y cumple el criterio pre-registrado de C-114. Ojo: esa aprobación solo prueba que el código es consistente; no localiza dónde la EOS reescribe la masa.

Todo fue solo lectura: check_audit sobre los directorios, python sobre audit.csv, test_full.txt y los GCELL de la sonda, y git diff --cached.

### 1. Afirmación por afirmación

| Afirmación | Reporte | Recalculado | |
|---|---|---|---|
| Masa que reescribe la EOS, e1 / base (280–285.5 s) | 0.615 / 0.552 | C-105: 0.615 / 0.552 | ok |
| Residuo con 5 / 10 / 20 externas | −13.3 / −5.3 / −4.5 e-3 | C-109: −13.34 / −5.33 / −4.46 e-3 | ok |
| Deriva de la base | ~−5e-5 kg/paso | C-107: 4.46e-5 | ok (redondeo) |
| Lecho con 5 externas | −2.78e-3 → −3.69e-3 | C-110 | ok |
| \|e\| y neto, sonda mo20 | 1.7e-2 / −8.5e-4 | sonda_gc_mo20 GCELL: 1.739e-2 / −8.47e-4 | ok (cita imprecisa, E5) |
| Cierre k5_mo20 / k5_base | −6.1e-14 / −7.1e-14 | −6.140e-14 / −7.094e-14 | ok |
| mo20: libre / multi / outlet | +2.179e-5 / −8.686e-4 / +9.244e-4 | iguales | ok |
| mo20: EOS / venteo / volfix | −8.554e-4 / −9.461e-4 / −1.310e-5 | iguales | ok |
| base: libre / multi / outlet | −9.896e-4 / −1.585e-3 / +1.284e-3 | iguales | ok |
| base: EOS / venteo / volfix | −2.580e-3 / −1.302e-3 / −1.312e-5 | iguales | ok |
| outlet − \|venteo\| en mo20 | −2.17e-5 | −2.17e-5 | ok |
| multi / \|volfix\| en mo20; contaminación | ~66; ≤1.5 % | 66.3; 1.51 % | ok |
| Numérica igual bit a bit a sonda_gc_* en 60 renglones | sí | 60/60 renglones; las 87 columnas comunes son idénticas (no solo las 5 citadas) | ok |
| Mismo reinicio, mismos ranks, misma config | judge_otp_280, 15 ranks | run.log: restart_file judge_otp_280/eaf3d_00280000.h5, 15 procesos; la config solo difiere en output_dir y en las claves probe_* | ok |
| Bancos de test-full con balance | 64 | 64 (bancos distintos) | ok |
| \|cierre\| máximo | ≤ 4.0e-12 | 3.985e-12 (arc_slag_n1) | ok |
| Bancos con \|volfix\| > 10 % de \|multi\| | 18 de 64 | 18 | ok |
| cold_bucket2_slag_n1 (:1822) | multi −1.739 / volfix −1.722 / EOS −1.773e-2 | iguales | ok |
| cold_bucket2_n4 (:1790) | −10.40 / −10.47 / −0.756 | −10.40 / −10.47 / −0.7561 | ok |
| bath_freeze_n1 (:1202) | −0.260 / −3.833 / +3.942 | −0.2604 / −3.833 / +3.942 | ok |
| AVISO del check_audit actual | sale en cold_bucket2_slag_n1; no en k5_mo20 ni arc_slag_n4 | confirmado | ok |
| arc_slag_n4 | multi −1.067, EOS 1.097 (antes −9.7e-18) | multi −1.067, EOS −1.097; el valor anterior solo está en C-113 | ok (E4) |
| Bancos sin balance | bath_fill_mix_n4, bath_mix_n4, oneflow_test_n4 | :1109 / :1289 / :2147, 'N de N pasos' | ok |
| Tests | unit, quick y full OK con golden v131 | test_unit:390 PASS test_gas_cell_class; quick y full 'OK'; metrics_v131; solo XFAIL ya conocidos | ok (E1) |
| Prueba unitaria: 3 casos con escoria | 3 | 3 (solo escoria, borde de escoria, outlet con escoria) | ok |

### 2. Criterio pre-registrado de C-114, comparado al pie de la letra

C-114 se registró a las 17:18:53, antes de las corridas k5 (audit.csv a las 17:20) y de test-full (17:36). El veredicto C-115 es de las 17:37.

- (1) \|cierre\| ≤ 1e-8 y numérica igual bit a bit: **cumple**.
- (2) En los 64 bancos, \|cierre\| ≤ 1e-6·(\|abs\| + \|out\| + \|EOS\|) + 1e-12: **cumple**, ninguno falla. La tolerancia más estricta es la de slag_rest_n4_to_n4_s50 (1.0e-12, cierre 1.9e-15), no la de bath_test como dice C-115. Este detalle está en el registro, no en el reporte.
- (3) \|multi\| ≥ 0.1\|EOS\| en arc_slag_n4: **cumple** (1.067 frente a 0.11).
- (4) Los bancos con mezcla avisan que omitieron pasos: **cumple**.
- (5) quick y full OK con golden v131: **cumple**.

El signo del venteo se corrigió en check_audit antes de evaluar. Esa corrección deja el código igual a la identidad pre-registrada (EOS − celdas = venteo − volfix) y no toca el criterio. Es aceptable.

El reporte no aprueba nada que el criterio no apruebe. Además, retira de forma explícita las lecturas de localización (K5-R1..R4).

### 3. Objeciones (ninguna bloqueante)

1. **E1.** research/ws/WS-K5/logs/test_full.txt es de las 17:36:59 y src/mod_audit.f90 y check_audit.py son de las 17:44:41. No se volvió a correr test-full con el árbol final. **Se levanta** volviendo a correr test-full, o mostrando que ese cambio fue solo de comentarios.
2. **E2.** status.json:prediccion=C-111. Debería decir C-114.
3. **E3.** Los criterios (2) y (3) de C-114 son débiles: la identidad se cumple por construcción. La conclusión se limita a consistencia, y así lo reconoce el reporte.
4. **E4.** arc_slag_n4 'antes −9.7e-18' solo puede comprobarse en C-113.
5. **E5.** Proceso 3: |e| 1.7e-2 y neto −8.5e-4 vienen de campaigns/b1/sonda_gc_mo20/run.log, no del texto de C-110; hay que citar esa ruta. El comentario de mod_audit.f90 dice '|e| 1.6e-2' y lo medido es 1.739e-2.

VEREDICTO: aprueba