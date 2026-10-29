El reporte no se puede aprobar todavía. Casi todos los números se reproducen desde los datos, pero el reporte atribuye a C-089 justo lo contrario de lo que esa entrada dice sobre la vigencia de las refutaciones de Plan K.

# Revisión de evidencia: WS-K1, ronda 1

**Alcance:** research/ws/WS-K1/report.md frente a research/ledger.jsonl y los datos en campaigns/b1.

**Modo:** solo lectura. Antes de ejecutar nada comprobé que no hubiera ninguna corrida eaf3d en curso: había 0 procesos. No leí reviews/ de otros revisores; solo comprobé que existe el archivo citado.

## 1. Tabla de verificación

| Afirmación | Reporte | Recalculado | Resultado |
|---|---|---|---|
| H1 (C-011): convergencia de k1_342 | 0 % | 205/205 sin converger (plank_conv.py, tol 1e-6) | ok |
| H1: \|p\| en la sonda (10,60,2) | 69.1 kPa | máximo 69 967.7 Pa (70.0 kPa) en 342539; 69 103 Pa solo en 342540 | objeción O2 (no bloqueante) |
| osc2: base frente a k1 (342500-342560) | 51.8 kPa → 342 Pa | 51 835.2 → 342.3 Pa | ok |
| Centinela de k1 | (C-012: 2.7 %) | cent_pg 2.7 % (regime2 --w 342.45,342.56) | ok |
| El criterio de H1 se escribió antes de la corrida | plan §4 | `git show c298555:docs/PLAN_K...md` §4 coincide literalmente con C-011; commit 16:48:17, k1_342 creado a las 16:53:12 | ok |
| H1b (b): grad_hid_max de k1b | 70.6 > 3 | 70.57 | ok (ver O3) |
| H1b (c): p>100k de k1b | 5.4 % > 3.2 % | 5.4 % (6 de 111 pasos); base 6.3 % | ok (ver O3) |
| H1b (a): osc2 de k1b | (C-028: 886) | 885.7 Pa ≤ 1000 | ok |
| H1b (d): pasos sin converger | (C-028: 0.9 %) | 5/550 = 0.9 % | ok |
| Pico de k1b | 410 kPa en 342.534 s | 409 994.6 Pa en 342534 | ok |
| C-025 registrado antes de k1b_342 | — | C-025 17:32:08; run.log creado a las 17:59:01 | ok |
| P-a (C-035/C-037): osc2 | 209.5 Pa | 209.5 Pa; ag_min 0.01834 → AUSENTE según el criterio | ok |
| P-b (C-036/C-038): osc2 | 6876 Pa | 6876.0 Pa; ag_min 0.01500 → PRESENTE; 549/550 sin converger | ok |
| P-a y P-b registradas antes de correr | — | C-035/036 18:12:16; config 18:12:40; k1pa 18:13:16; k1pb 18:14:03 | ok |
| Mismo reinicio y misma ventana para base, k1, k1b, k1pa y k1pb | — | restart diag_p342a/eaf3d_00342450.h5 y t_final 342.56 en las cinco; la única diferencia entre P-a y P-b es pc_ai_tol | ok (binario no verificable, O5) |
| C-030: celdas sumergidas | 242 / 45 / 73 | 242 / 45 / 73 (submerged_bed.py) | ok |
| C-033: k1b liso después del pico | 27-36 kPa | 27.4-36.5 kPa (342538-342560) | ok (redondeo) |
| C-041: cent_pg en 344-345.5 | K 0.1/0.3 frente a base 6.7-9.5 | K 0.1/0.3/12.8; base 6.7/7.2/9.5 | ok (ver O4) |
| C-064 cerrado sin verificar en WS-K12 | — | C-294: fallida, «cerrada sin verificar» | ok |
| Motivo de C-065 | «Plan K no adoptado; usuario aprobo el cierre 2026-10-23» | literal | ok |
| C-065 a C-073 cierran C-016 a C-024 como fallida | 9 | 9 | ok |
| C-018 (A3) PENDIENTE | — | literal en el enunciado | ok |
| Archivos de src con pc_alpha_implicit | 0 | 0 (src/*.f90 y búsqueda recursiva) | ok |
| `git apply --check` de plan_k_v2.patch | falla en mod_pressure_3d.f90:733 | «patch failed: src/mod_pressure_3d.f90:733» | ok |
| Commits en src desde 1bc9832 | 7 | 7 | ok |
| Afirmaciones raíz de WS-K1 | 16: refutada 4, fallida 9, soportada 3 | 16, {'refutada': 4, 'fallida': 9, 'soportada': 3}; `ledger.py open` no lista ninguna abierta de WS-K1 | ok |
| `ledger.py check` | — | «ledger OK (309 eventos, 13 workstreams)» | ok |
| Regla de vigencia {C-089}: fracasos condicionales | condicionales | C-089 lista Plan K como VIGENTE, no condicional; C-089 está fallida desde C-284 | **objeción O1 (bloqueante)** |

## 2. Veredictos frente al criterio pre-registrado

- **C-011 → C-012 (refutada):** el criterio exige convergencia ≥ 95 % y \|p\| < 20 kPa. Se obtuvo 0 % de convergencia y p ≥ 20 kPa en todos los pasos de 342518 a 342560. La refutación se mantiene por la letra, y el reporte no la reinterpreta.
- **C-025 → C-028 (refutada):** el criterio exige que se cumplan todos los incisos. Fallan (b) y (c). La refutación es correcta por la letra.
- **C-035 y C-036:** ambas se cumplen con las bandas pre-registradas, así que C-039 queda soportada. Es correcto.
- **Meta G1:** H1b está juzgada y refutada, y H1 también. Proponer `fallido` es coherente con research/README.md. Ninguna enmienda se aplicó a posteriori.

## 3. Objeciones

1. **O1 (bloqueante)** — `research/ws/WS-K1/report.md`, Incertidumbre: «Por la regla de vigencia {C-089}, estos fracasos son condicionales».
   - C-089 dice «Vigentes (codigo actual…): …, Plan K (23-oct)». `.claude/rules/acople-pv.md:266-273` repite esa clasificación.
   - El estado vigente de C-089 es fallida desde C-284, que mantiene la regla solo como método.
   - **Para levantarla:** decir que C-089 las clasificó como vigentes y que, al haber 7 commits en src desde 1bc9832, retomarlas exige repetirlas en el banco actual. Citar C-284 y el archivo de reglas.
2. **O2** — `campaigns/b1/k1_342`, celda (10,60,2): el máximo es 70.0 kPa (342539) y 69.1 kPa es solo el valor del paso 342540.
   - **Para levantarla:** decir de qué estadístico se trata.
3. **O3** — El inciso (b) de C-025 hereda el patrón hidrostático que C-031 refutó.
   - La refutación de H1b descansa en (c): 6 de 111 pasos frente a un umbral de 3.55 (la base tiene 7).
   - **Para levantarla:** señalarlo en Incertidumbre.
4. **O4** — La mejora de 2 de 3 trayectorias en C-041 es una observación post hoc y fuera de criterio. La tercera trayectoria (k1pa_340_n15) da cent_pg 12.8 % y pmax 2.00e6 Pa.
   - **Para levantarla:** etiquetarla así en el reporte.
5. **O5** — No pude verificar el binario de k1b_342, k1pa_342 ni k1pb_342: los run.log no lo identifican y no hay binarios k1* en campaigns/bin.
   - **Para levantarla:** dar el hash o la ruta del binario, o declararlo como no verificable.

## Notas no bloqueantes

- `status.json` tiene `ronda: 0` mientras esta revisión es la ronda 1. Lo debe ajustar el coordinador.
- `diff_sha` es el sha256 del diff vacío, coherente con «no toca código».

VEREDICTO: rechaza