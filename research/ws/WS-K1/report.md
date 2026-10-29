# WS-K1: cierre de la meta G1 (Plan K, limitador de hueco en el Poisson)

**Meta G1** (`research/QUESTION.md`): los 9 hallazgos de la auditoría
dirigida del Plan K resueltos o documentados, y H1 en la ventana
342.45–342.56 s. Terminado cuando H1b esté juzgada, con panel unánime,
test-quick y commit por la compuerta.

**Conclusión: G1 NO se cumplió.** H1 y H1b quedaron refutadas, y el usuario
aprobó no adoptar el Plan K el 23-oct-2026. Esa decisión se tomó
apoyada en dos bases que da el ENUNCIADO de C-065 (su `motivo` solo dice
«Plan K no adoptado; usuario aprobo el cierre 2026-10-23»): {C-041}
refutada en 344–345.5 s, que sigue vigente como refutación del juez
pre-registrado {C-040}, y {C-064} («estallido de 345.3 s por velocidad
fantasma que Plan K destapa»), hoy fallida ({C-294}). Además, la base
también supera 1 MPa sin Plan K ({C-310}/{C-312}/{C-313}). No adoptarlo
fue una DECISIÓN del usuario ({C-065}). {C-041} refutó la mejora
pre-registrada en B1 ({C-040}); que 2 de 3 trayectorias del brazo K dieran
cent_pg 0.1/0.3 % frente a 6.7–9.5 % de la base en 344–345.5 s es una
lectura post hoc sin veredicto (ver Incertidumbre). Estado propuesto para el
workstream: `fallido`, con `cierre` = «G1 no cumplida: H1 y H1b refutadas;
Plan K no adoptado». Este cierre no toca código ni registra eventos.
{C-312}/{C-313} (de WS-K2) y la entrada «Plan K CERRADO» de `acople-pv.md`
ya están en HEAD desde e250687 (cierre de WS-K2); el diff de este cierre
reduce esa entrada y el §6 del plan a los veredictos del registro (ver
Incertidumbre, «El registro permanente del Plan K»).
Todas las afirmaciones del workstream ya están cerradas (ver «Estado de las
afirmaciones»).
> [fuente: ledger.py show C-065 (enunciado: «C-041 refutada en 344-345.5 s; C-064 estallido de 345.3 s …»; motivo) | git log -S'"C-312"' -- research/ledger.jsonl (e250687) | git log -S'Plan K CERRADO' -- .claude/rules/acople-pv.md (e250687) | ledger.py show C-294 (C-064 fallida) | ledger.py show C-310 | ledger.py show C-313 | regime2 de k1pa_340_n12/n14/n15 en 344–345.5 s, ver Incertidumbre («Qué se refutó»)]

**Cómo se cierra** (`research/README.md`, «Estados de un workstream»): si el
panel aprueba este reporte por unanimidad, el coordinador fija
`ledger.py ws-set WS-K1 estado=fallido cierre=<motivo>`; `ledger.py check`
exige para `fallido` la clave `cierre` y los tres «aprueba» de la ronda
vigente. Un `fallido` no abre la compuerta de commit.

## Proceso

1. **H1 tal como se escribió en el plan** {C-011}
   (`docs/PLAN_K_limitador_en_poisson.md` §4) quedó refutada {C-012}.
   - Con la versión previa a la auditoría (k1_342), la convergencia fue 0 %
     (tol 1e-6 supuesta: `k1_342/config.dat` no fija `pc_ai_tol`; 1e-6 es el
     default de v2 (`plan_k_v2.patch`), y el parche v1 no está archivado,
     así que el default de v1 no es verificable; 205/205 solves al tope de
     8 iteraciones).
     Con tol 1e-3 los mismos 205 solves contarían como convergidos (0 % sin
     converger), pero el veredicto no cambia: el inciso de |p| también falla.
     |p| en la sonda (10,60,2) es ≥ 20 kPa en todos los pasos de 342518 a
     342560, con un máximo de 70.0 kPa (69 967.7 Pa) en el paso 342539. El
     69.1 kPa de C-012 es el valor del paso 342540, no el máximo.
   - La oscilación sí desapareció: osc2 bajó de 51.8 kPa a 342 Pa.
   > [fuente: python3 scripts/research/ledger.py show C-011 | ledger.py show C-012 | python3 scripts/diag/plank_conv.py campaigns/b1/k1_342/run.log (205/205 sin converger, it_medio 8.00) | idem --tol 1e-3 (0/205) | grep -n "pc_ai_tol = 1.0e-6\|pc_ai_max_it = 8" research/ws/WS-K1/plan_k_v2.patch | python3 scripts/diag/cell_series.py campaigns/b1/k1_342 --cell 10,60,2 --steps 342500,342560 (p_max=69967.7, osc2=342.3)]
2. **La «sobrepresión no física»** que el coordinador dedujo de esos 69 kPa
   {C-013} quedó refutada {C-031}. Son la media del ciclo de la base y frenan
   un chorro de líquido que cae sobre una celda de esquina. El criterio
   «|p| < 20 kPa» estaba mal planteado para una celda en deceleración. La
   lección quedó en `.claude/rules/research.md` («pensar la escala física
   antes»). La línea decía que el criterio «ignoraba la hidrostática de ~70
   kPa del fondo», que era una errata: la columna de encima equivale a ~6 kPa
   {C-013} y los ~69 kPa son dinámica, la media del ciclo frenando un chorro
   {C-031}. La errata ya está corregida en HEAD desde e250687 (cierre de
   WS-K2); este diff no toca `research.md`.
   > [fuente: ledger.py show C-013 (vigente refutada por C-031) | sed -n 15,18p .claude/rules/research.md | git log --oneline -1 -- .claude/rules/research.md (e250687)]
3. **Auditoría dirigida del Plan K:** dejó 9 hallazgos, {C-016} a {C-024}.
   - Ninguno se verificó.
   - Los 9 se cerraron como «fallida (cerrada sin verificar)», {C-065} a
     {C-073}, cuando el usuario aprobó no adoptar el Plan K («Plan K no
     adoptado; usuario aprobo el cierre 2026-10-23», campo `motivo` de C-065).
   - La primera parte de G1 («resueltos o documentados») se cumple, como
     mucho, como «documentados», y solo en el registro: el enunciado de una
     línea de cada hallazgo y su cierre «sin verificar». Ninguno quedó
     resuelto en `src/`. La entrada «Plan K CERRADO» del registro
     permanente de reglas no los cita uno por uno: solo recoge los
     veredictos (ver Incertidumbre, «El registro permanente del Plan K»).
   > [fuente: ledger.py show C-065 (motivo y evidencia research/ws/WS-K1/plan_k_v2.patch)]
4. **H1b**, el Plan K después de la auditoría {C-025}, quedó refutada {C-028}.
   - Según la letra de C-025 fallaron dos incisos: (b) grad_hid_max 70.57 > 3
     y (c) p > 100 kPa en el 5.4 % de los pasos, por encima del 3.2 %. Los
     otros tres cumplen por la letra: (a) osc2(10,60,2; 342500–342560) =
     885.7 Pa ≤ 1000, (d) 0.9 % sin converger ≤ 5 % y (e) vol_lim 2.46e-3 ≤
     2.605e-3.
   - Precisión de (c): cent_pg se juzgó a la precisión que imprime regime2
     (2.7 %). Sin redondear es 3/111 = 2.703 % en k1b_342, idéntico a la
     base y a k1pa_342; leído literalmente, (c) también falla por cent_pg.
     El veredicto (refutada) no cambia; C-028 («cent_pg 2.7 % cumple») no
     dice qué precisión aplicó.
   - **El inciso (a) no es prueba de que el ciclo no volvió.** C-028 lo dice:
     «cumple solo en la mediana». osc2 es la MEDIANA de |d2p| =
     |p_n − (p_{n−1}+p_{n+1})/2| (`scripts/diag/cell_series.py`:46,
     `np.median`), así que no ve un ciclo que ocupe menos de la mitad de la
     ventana. En k1b_342, 342500–342560, |d2p| > 1000 Pa en 28 de 59 puntos
     interiores (47 %), con p75 14.6 kPa y máximo 219 kPa; la mediana (885.7
     Pa) pasa por 3 puntos de fracción. En k1_342 y k1pa_342 la fracción es
     22 % (13 de 59; p75 0.73 y 0.72 kPa) y en la base diag_p342b 85 % (50
     de 59). El inciso (a) no sirve como contrapeso de «sigue ciclando».
   - *Lectura fuera del criterio, sin valor de veredicto:* el inciso (b) usa
     el mismo patrón de «líquido en reposo» que C-031 declaró mal planteado
     para una celda en deceleración (el defecto del criterio de H1, punto 2).
     El veredicto no depende de esa lectura: (c) falla por sí solo.
   - El margen de (c) es pequeño: 6 de 111 pasos frente a 3.55 permitidos
     (la base tiene 7). La ventana de regime2 es 342.45 ≤ t < 342.56 s,
     pasos 342450–342560; el 342450 tiene p_max 9.52e4 < 1e5. Los pasos
     342451 y 342452, los dos primeros tras el reinicio, comunes a todos
     los brazos ({C-290}, fallida, los lee como probable contaminación del
     reinicio; lectura sin valor de veredicto), están presentes (> 1e5) en
     todos; no son iguales (342451: 8.045e5 en la base y 8.030e5 en k1,
     k1b, k1pa y k1pb; 342452: 1.6401e5–1.6404e5). Sin esos dos pasos, k1b
     tiene 4 de 109 (3.7 %) frente a 3.49 permitidos, y la base 5 de 109.
     Esos 4 pasos de k1b (342534–342537) no son un exceso marginal por
     ruido: son el pico de la base (342535–342537, 342539, 342541)
     reproducido un paso antes (siguiente viñeta).
   - *Ciclo, lectura post hoc sin valor de veredicto* (sonda (10,60,2), una
     sola trayectoria; k1pb_342 es casi idéntica): la versión corregida
     recupera la alternancia de 2 pasos de la base y el pico (410.0 kPa en
     342534; la base, 413.4 kPa en 342535), como dice C-028 («RECUPERA el
     ciclo de 2 pasos de la base»). Por tramos de |d2p| (puntos interiores
     de cada tramo; revisor-refutador, recomprobado aquí):
     - Dentro del ciclo, 342520–342537 (16 puntos), k1b reproduce la base:
       |d2p| > 1000 Pa en el 100 % de los puntos en las dos, mediana 40.7
       frente a 48.1 kPa y p75 55.2 frente a 52.6 kPa.
     - El ciclo de k1b arranca 4–5 pasos más tarde: el primer |d2p| > 1, 5,
       10 y 20 kPa cae en 342513, 342519, 342522 y 342525 en k1b, y en
       342509, 342515, 342518 y 342520 en la base.
     - Tras el pico, 342538–342560 (21 puntos), k1b queda liso: 14 %
       frente a 100 % de la base {C-033}.

     **Se retira** la «amplitud 3.4 veces menor» que daba antes este
     reporte (osc2 6874 frente a 23362 Pa en 342510–342533): es la mediana
     de una ventana que corta el ciclo de k1b en su arranque tardío, no una
     amplitud menor del ciclo. Igual, el 47 frente a 85 % de 342500–342560
     (viñeta anterior) sale casi entero del tramo posterior al pico. En la
     métrica de C-036, k1b da PRESENTE (osc2 6874 Pa, ag_min 0.01500), pero
     esos umbrales se fijaron después y con la propia k1b como ejemplo de
     PRESENTE (6874 Pa/0.01500 está en la lista de calibración de C-036):
     para k1b ese resultado es circular; los tramos de arriba no dependen de
     esa métrica. El único criterio de ciclo pre-registrado, el inciso (a),
     no decide nada aquí: pasa solo en la mediana.
   - El ciclo no viene del reinicio desde `diag_p342a` (que {C-290},
     fallida, lee sin veredicto como probable contaminación): la corrida
     continua `dense_340_n14` (desde
     `judge_otp_280/eaf3d_00340000.h5`, sin pasar por ese reinicio) tiene
     max|p| en [k,j,i] = (1,59,9), la celda (10,60,2), en 342529 y
     342531–342535: 74.5, 94.0, 42.6, 108.0, 42.9 y 636.0 kPa (alternancia
     de 2 pasos desde 342531; en 342530 el máximo está en otra celda, 48.8
     kPa).
   - **Regla de aborto del plan** (`docs/PLAN_K_limitador_en_poisson.md`
     §4, líneas 72–73: «Si converge pero la presión sigue ciclando, el
     mecanismo no es el limitador: parar»). No tiene umbral numérico. *A
     juicio del coordinador*, no por la letra, se disparó con k1b: converge
     (inciso (d)) y el ciclo vuelve. Es una lectura sin valor de veredicto,
     porque la regla no tiene umbral. El «sigue ciclando» ya no descansa
     solo en la métrica circular de C-036: por tramos de |d2p| (viñeta
     anterior), k1b reproduce la base en 342520–342537, pero en una sola
     trayectoria; el inciso (a) no lo confirma ni lo descarta (pasa solo en
     la mediana). Además, la conclusión de la regla («el
     mecanismo no es el limitador») choca con C-039, que este reporte
     acepta: con el tope exacto la celda toca el piso y el limitador
     conmuta.
   - *Lectura alternativa (revisor-refutador, sin corrida que la decida):*
     H0 mostró que la decisión del limitador es idéntica en los 5 outers y
     alterna entre pasos (`.claude/rules/acople-pv.md`:611–617,
     `diag_h0lim`), y el hueco de poro se congela en α^n durante el paso
     (J-B, acople-pv.md:560–566). Un conjunto activo dentro del paso no
     puede quitar un retraso entre pasos, y con tope exacto ese retraso se
     reproduce por construcción. Sería una limitación estructural del diseño,
     conocida antes de H1, no una refutación de «limitador en el Poisson».
   - No se paró. Se siguió con la opción D de `reevaluacion.md` (P-a/P-b).
   > [fuente: ledger.py show C-025 | ledger.py show C-028 | python3 scripts/diag/cell_series.py campaigns/b1/k1b_342 --cell 10,60,2 --steps 342500,342560 --quiet (osc2=885.7, grad_hid_max=70.57) | idem --steps 342510,342533 (osc2=6874.3, ag_min=0.01500) | python3 -c "import glob,os,h5py,numpy as np; [(lambda p: print(r, np.mean(np.abs(p[1:-1]-0.5*(p[:-2]+p[2:]))>1000), np.percentile(np.abs(p[1:-1]-0.5*(p[:-2]+p[2:])),75), np.abs(p[1:-1]-0.5*(p[:-2]+p[2:])).max()))(np.array([h5py.File(f,'r')['fields/pressure'][1,59,9] for f in sorted(glob.glob(f'campaigns/b1/{r}/eaf3d_*.h5')) if 342500<=int(os.path.basename(f)[6:-3])<=342560])) for r in ['diag_p342b','k1_342','k1b_342','k1pa_342']]" (frac>1000: 0.847 / 0.220 / 0.475 / 0.220; p75 112.0k / 730 / 14559 / 721; max 333.8k / 3729 / 218858 / 3728; 59 puntos interiores) | ledger.py show C-036 (lista de calibración) | python3 scripts/diag/regime2.py campaigns/b1/diag_p342b campaigns/b1/k1b_342 --w 342.45,342.56 (n 111; p>100k 6.3 / 5.4) | conteo |p_max|>1e5 en campaigns/b1/{diag_p342b,k1_342,k1b_342,k1pa_342,k1pb_342}/audit.csv con 342.45<=t<342.56 (python3 csv.DictReader, columnas time y p_max): base 7 (342451, 342452, 342535-342537, 342539, 342541), k1b y k1pb 6 (342451, 342452, 342534-342537), k1 y k1pa 2 (342451, 342452) | python3 -c "import numpy as np; [print(s, float(np.load(f'campaigns/b1/dense_340_n14/phantom/00{s}.npz')['pmax']), np.load(f'campaigns/b1/dense_340_n14/phantom/00{s}.npz')['kp']) for s in range(342525,342540)]" | grep restart_file campaigns/b1/dense_340_n14/config.dat | python3 (h5py, p[1,59,9] de campaigns/b1/{diag_p342b,k1b_342,k1pb_342}/eaf3d_*.h5; |d2p| en los puntos interiores de 342520–342537 y 342538–342560) → 342520–342537: base frac 1.000, mediana 48142, p75 52619; k1b 1.000, 40716, 55160; 342538–342560: base 1.000; k1b 0.143; pico de p: base 413369 Pa en 342535, k1b 409995 Pa en 342534; primer |d2p| > 1/5/10/20 kPa en 342500–342560: base 342509/342515/342518/342520, k1b 342513/342519/342522/342525 | ledger.py show C-290 (fallida; «Lecturas sin valor de veredicto»)]
5. **Por qué volvió el ciclo:**
   - La hipótesis A1/F2.31 {C-029} quedó refutada en su mitad act_g {C-032}.
   - La hipótesis de la holgura {C-034} quedó soportada {C-039}, con dos
     predicciones:
     - P-a {C-035}/{C-037}: v2 sin A2 elimina el ciclo (osc2 209.5 Pa).
     - P-b {C-036}/{C-038}: v2 completo con tol 1e-6 sigue ciclando (osc2
       6876 Pa).
   - Lo que quita el ciclo es «v2 sin A2», que deja la celda por debajo del
     tope (ag_min 0.01834). Ojo: P-a cambia DOS cosas
     (`research/ws/WS-K1/patches/pa_sin_A2.patch`): el factor de `acc_face`
     pasa a 1 y además `unl_on = .false.`, que quita la entrada no enlazada.
     C-039 atribuye el efecto solo a la cuota sin el factor; no hay corrida
     que separe los dos ingredientes (factor 1 con `unl_on` activo). En las
     cinco corridas `pc_drift_source = true`, que es condición necesaria,
     no suficiente: en v2 `unl_on` exige además `ws_pc_unl_valid` y
     `ws_pc_unl_id` igual al paso actual (`plan_k_v2.patch`:155), y en
     1bc9832 la fuente solo se valida tras un transporte del mismo paso con
     `ws_Fc_valid` (`mod_continuity.f90`:863–866) y se invalida en la ruta
     `solve_alpha_bounded_implicit` (línea 277). Así que `unl_on` rige como
     mucho en los outers posteriores al primer transporte del paso (2–5).
     Aun así, P-a cambia las dos cosas en esos outers.
   - *Inferencia de lectura de código (revisor-refutador), sin dato:* en
     `acc_face` (`plan_k_v2.patch`), s = min(1, (cap + qout)/qin). Con
     fac = 1, la entrada se sobrestima cuando la donante tiene menos líquido
     que la cara (α_nb < a_f), así que s baja y aparece holgura (la salida
     también cambia de factor, con α_i/a_f, y empuja en sentido contrario
     si α_i < a_f: el signo neto del factor no es unívoco). Con
     `unl_on = .false.`, una `ws_pc_unl > 0` deja de sumarse a qin, así que
     s sube y hay MENOS holgura. Si el goteo no enlazado entra a (10,60,2),
     los dos ingredientes empujan en sentidos opuestos y la holgura medida
     (ag_min 0.01834) se habría dado a pesar de `unl_on = .false.`, lo que
     reforzaría a C-039. No es verificable con lo que hay: los `run.log` de
     k1*_342 no tienen [PROBE-LIM] ni `ws_pc_unl` por celda. Lo resolvería
     el signo y tamaño de `ws_pc_unl` en (10,60,2) durante 342510–342533, o
     una corrida de factor 1 con `unl_on` activo; ninguna existe.
   > [fuente: ledger.py show C-034 (cadena C-035..C-039) | sed -n 155p research/ws/WS-K1/plan_k_v2.patch (unl_on = cfg%pc_drift_source .and. ws_pc_unl_valid .and. ws_pc_unl_id == probe_current_step()) | git show 1bc9832:src/mod_continuity.f90 | sed -n '274,277p;863,868p' | grep -n "EXPERIMENTO P-a" research/ws/WS-K1/patches/pa_sin_A2.patch | grep -n "subroutine acc_face" -A 15 research/ws/WS-K1/plan_k_v2.patch | grep -n "s_nw(i,j,k) = min" research/ws/WS-K1/plan_k_v2.patch | grep pc_drift_source campaigns/b1/{k1_342,k1b_342,k1pa_342,k1pb_342,diag_p342b}/config.dat (true en las cinco) | grep -c "PROBE-LIM\|ws_pc_unl" campaigns/b1/k1*_342/run.log (0)]
6. **Contexto medido:**
   - La población afectada son 242, 45 y 73 celdas de lecho sumergidas (280,
     310 y 340 s) {C-030}.
   - Después del pico, k1b_342 queda liso entre 27.4 y 36.5 kPa
     (342538–342560) {C-033}.
   > [fuente: ledger.py show C-030 | ledger.py show C-033 | p[1,59,9] de campaigns/b1/k1b_342/eaf3d_*.h5 en 342538–342560 (23 pasos: mín 27411.7 Pa en 342544, máx 36507.4 Pa en 342539)]
7. **Decisión:** el juez de varias trayectorias en 340–345.5 s quedó refutado
   (WS-K2: {C-040} → {C-041}). Su brazo K fue k1pa_340_n12/n14/n15, que
   C-040 **declara** como v2 sin A2 (binario `eaf3d_k1pa_opt`). El binario
   no se puede identificar DIRECTAMENTE: las corridas no tienen `run.sh`, el
   `run.log` no registra el binario ni el commit, `campaigns/bin/
   eaf3d_k1pa_opt` ya no existe y no hay sonda (10,60,2) ni salida propia de
   `pa_sin_A2.patch` (0 líneas [PROBE-*]) (WS-K2, «Binarios de los brazos de
   C-040»). La identificación como v2 sin A2 descansa en la DECLARACIÓN de
   C-040. La firma del audit es compatible con ella pero NO la discrimina
   (revisor-refutador, ciclo 8, O2; recomprobado aquí):
   - n12, n14 y n15 son el mismo binario: frente a n12, n14 y n15 difieren
     en vol_lim entre 3e-17 y 2e-14 en 340001–340010, el nivel de redondeo
     de base_340_n14/n15 frente a judge_otp_280 (≤ 5.3e-15; máximo en
     base_340_n15, paso 340010).
   - Firma de A2 desde el primer paso, calibrada en 342.45 s contra k1_342
     (v1), mismo reinicio y 12 ranks (2×3×2): con tope exacto, k1b_342 y
     k1pb_342 (tol 1e-3 y 1e-6, así que la firma no depende de la
     tolerancia) dan vol_lim −4.48e-7 en 342451 (−3.8e-8 a −4.5e-6 en
     342451–342460) y vol_unlinked negativo desde 342453 (−6.3e-8 en
     342455, −1.45e-7 en 342458). k1pa_342 da vol_lim +1.3e-9 en 342451
     (luego entre −1.8e-8 y +1.05e-7) y vol_unlinked positivo desde 342452
     (−2.3e-11 en 342451), hasta +1.5e-8.
   - k1pa_340_n12 frente a k1_340 (mismo reinicio, 12 ranks 2×3×2 en las
     dos): vol_lim +7.1e-9 en 340001 (+7e-9 a +3.8e-7 en 340001–340010) y
     vol_unlinked de +5.5e-10 a +2.5e-8 (un solo paso negativo, −4.1e-9 en
     340007). El signo de vol_lim coincide con el de k1pa_342.
   - Por qué no discrimina: (1) el signo de A2 se calibró en otro estado,
     342.45 s en ciclo activo (p_max de k1_342 entre 4.9e4 y 8.0e5 en
     342451–342460); a 340 s el estado es tranquilo (p_max de k1_340 entre
     2.1e4 y 2.9e4 en 340001–340010), y el signo neto del factor de A2 no es unívoco (punto
     5). (2) Por magnitud no se separan: n12−k1_340 da vol_lim de +7e-9 a
     +3.8e-7 en 340001–340010, y k1b−k1 da de −3.8e-8 a −4.4e-6; queda solo
     el signo. (3) p_max apunta en sentido CONTRARIO: k1pa_342−k1_342
     difiere menos de 1.4 Pa en 342451–342460, k1b−k1 de 1.8 a 57 Pa, y
     n12−k1_340 da 3–8 Pa en 340002–340006, 70.8 Pa en 340008 y −862 Pa en
     340010, el orden de k1b−k1. Además k1_340 se asume v1 porque su
     `config.dat` no fija `pc_ai_tol`, y las etiquetas de k1b/k1pa_342
     también son declaradas (ver Incertidumbre, «No es verificable qué
     binario usó cada corrida»).
   - Si la declaración de C-040 es correcta, la holgura de v2 sin A2 pasó
     por el juez de B1 y C-040 la refutó por la letra (n15). Si no lo es,
     la holgura no se juzgó en B1. Los datos no deciden entre las dos. Lo
     decidiría recompilar P-a con la receta de Incertidumbre sobre 1bc9832,
     correr 10 pasos desde `judge_otp_280/eaf3d_00340000.h5` a 12 ranks y
     comparar bit a bit con el audit de k1pa_340_n12; no se ha hecho (ver
     Incertidumbre, «Experimentos que este reporte nombra y que no
     existen», 1).
   - Aceptando la declaración de C-040, la familia con holgura tiene 4
     trayectorias en B1: k1_340 (v1; llega a 346 s con pmax 4.51e5,
     {C-027}) y k1pa_340_n12/n14/n15 (pmax 3.3e5 en n12 y n14; n15 pegada a
     2 MPa, {C-041}/{C-311}): 3 limpias y 1 pegada.
   - La holgura (ag_min 0.01834, osc2 209.5 Pa) está medida en la sonda en
     k1_342 (v1) y en k1pa_342, pero NO son réplicas: en la sonda,
     342500–342560, difieren como mucho 17 Pa (k1b_342 y k1pb_342, como
     mucho 96 Pa); en el audit, menos de 1.4 Pa en p_max en 342451–342460.
     {C-036} las calibra como «k1 209 Pa/0.01834» y {C-037} dice «idéntico
     a v1 en la sonda». Que la holgura quite el ciclo ({C-039}) es, en la
     práctica, una comparación de 1 trayectoria contra 1, y la regla «Juez
     ESTADÍSTICO» de `acople-pv.md` trata una sola trayectoria como ruido.
     *Lectura sin veredicto (revisor-refutador, recomprobada aquí):* lo que
     hace verosímil el mecanismo es que las dos parejas se separan en la
     sonda (primer |Δp| > 100 Pa entre k1_342 y k1b_342) en 342506, el mismo
     paso en que la base se separa de k1_342 y en que H0 ve arrancar la
     alternancia del limitador (342.506 s); en 30 pasos eso no parece
     divergencia caótica. Lo decidirían P-a y P-b a 14/15 ranks desde el
     mismo reinicio, que no existen. Tampoco está medida en las
     trayectorias de 340 s (k1_340, k1pa_340_*), que no tienen sonda.
   El estallido de 345.3 s se diagnosticó como
   golpe de ariete de una velocidad fantasma que el Plan K destapa {C-064},
   aunque ese diagnóstico se cerró sin verificar en WS-K12 ({C-294}). Con
   C-041 refutada y C-064 (enunciado de C-065), el usuario decidió no
   adoptar el Plan K; de esas dos bases, C-041 sigue vigente y C-064 está
   hoy fallida.
   - El mecanismo de C-064 (una columna de líquido que cae a 11–14 m/s
     contra una celda de lecho con las entradas cerradas por F2.8, frenada
     en un paso con ρuΔz/Δt del orden de MPa) es el mismo «mecanismo que
     faltaba» de Plan D: el baño cae contra una cara cerrada, variante del
     Bug 16 y del callejón sin salida de D2.2b
     (`docs/dev-history/2026-10-07_plan_d_acople_implicito.md`, «El
     mecanismo que faltaba» y la nota de D2.2c). C-064 mismo dice que
     «existe con y sin Plan K». Ese parentesco apoya la lectura de
     {C-312}/{C-313}, que no atribuye el pegado de n15 al Plan K; no lo
     decide. Lo decidiría la base desde un snapshot de n15 anterior a
     345.25 s, que no existe.
   - El código quedó archivado en `research/ws/WS-K1/plan_k_v2.patch` y
     `research/ws/WS-K1/patches/`.
   - `src/` no tiene el Plan K: 0 archivos con `pc_alpha_implicit`.
   - La reevaluación intermedia y su revisión están en
     `research/ws/WS-K1/reevaluacion.md` y
     `research/ws/WS-K1/reviews/r1-revisor-refutador-reevaluacion.md`.
   > [fuente: firma del audit: python3 (csv.DictReader de campaigns/b1/*/audit.csv por step; diferencias de vol_lim, vol_unlinked y p_max) para k1pa_340_n12 − k1_340 y k1pa_340_n14/n15 − k1pa_340_n12 en 340001–340010, base_340_n14/n15 − judge_otp_280 en 340001–340010, y k1pa_342/k1b_342/k1pb_342 − k1_342 en 342451–342460 (342451: vol_lim +1.348e-9 / −4.484e-7 / −4.484e-7; vol_unlinked k1pa_342 −2.29e-11; 340001 k1pa_340_n12 − k1_340: vol_lim +7.129e-9, vol_unlinked +5.528e-10; base_340_n15 − judge_otp_280 vol_lim máx 5.30e-15 en 340010; Δp_max n12 − k1_340 en 340001–340010: −0.5, 3.0, 5.7, −5.2, 5.1, 8.1, −2.1, 70.8, 5.1, −862.1 Pa; k1b − k1_342: 1.8, 26.9, −56.6, −43.1, −2.8, 19.2, 18.8, 17.7, 15.5, −9.2 Pa; k1pa_342 − k1_342: |Δ| ≤ 1.3 Pa) | head -30 campaigns/b1/{k1_340,k1pa_340_n12,k1_342,k1pa_342}/run.log (12 procesos, 2 x 3 x 2) | grep pc_ai_tol campaigns/b1/{k1_340,k1pa_340_n12,k1b_342,k1pb_342}/config.dat (ninguno / 1e-3 / 1e-3 / 1e-6) | python3 scripts/diag/cell_series.py campaigns/b1/k1_342 --cell 10,60,2 --steps 342510,342533 --quiet (osc2=209.5, ag_min=0.01834; idem k1pa_342) | ledger.py show C-036 (calibración) | ledger.py show C-037 | python3 (h5py, p[1,59,9] de campaigns/b1/{diag_p342b,k1_342,k1pa_342,k1b_342,k1pb_342}/eaf3d_*.h5: max|Δp| en 342500–342560 k1_342−k1pa_342 17.3 Pa, k1b_342−k1pb_342 95.8 Pa; primer paso con |Δp| > 100 Pa: k1_342−k1b_342 342506, diag_p342b−k1_342 342506) | ledger.py show C-027 (pmax 4.51e5) | grep -l pc_alpha_implicit src/*.f90 | wc -l (0) | ledger.py show C-064 («Existe con y sin Plan K») | ledger.py show C-294 | sed -n 80,93p docs/dev-history/2026-10-07_plan_d_acople_implicito.md | ledger.py show C-040 (criterio: «K = k1pa_340_n12/_n14/_n15 (eaf3d_k1pa_opt …)») | ls campaigns/b1/k1pa_340_n12 (sin run.sh) | ls campaigns/bin (sin eaf3d_k1pa_opt) | grep -c PROBE campaigns/b1/k1pa_340_n12/run.log (0) | research/ws/WS-K2/report.md, «Binarios de los brazos de C-040»]

## Estado de las afirmaciones

Hay 16 afirmaciones raíz en WS-K1, ninguna abierta:

| Estado | Cuántas | Cuáles |
|---|---|---|
| refutada | 4 | {C-011}, {C-013}, {C-025}, {C-029} |
| fallida | 9 | {C-016} a {C-024} |
| soportada | 3 | {C-030}, {C-033}, {C-034} |

> [fuente: python3 -c "import sys,collections; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); r=[x for x in ev if x['ws']=='WS-K1' and not x.get('ref')]; print(len(r), dict(collections.Counter(L.current_state(x['id'],ev) for x in r)))" (16 {'refutada': 4, 'fallida': 9, 'soportada': 3})]

## Incertidumbre

- **Qué se refutó.** Se refutaron los criterios H1, H1b y el juez C-040.
  La refutación de H1 es de criterios débiles (puntos 1 y 2); la de H1b
  tiene margen mínimo en el recuento pero no en la sustancia (punto 4): H1 cae por convergencia (que depende de una tolerancia
  no verificable en v1: con 1e-3 da 0/205 sin converger) y por |p| < 20 kPa,
  criterio mal planteado (C-031). H1b se sostiene en (c), porque (b) usa
  el mismo patrón mal planteado. (c) falla por un paso en el recuento (sin
  los pasos del reinicio, 4/109 frente a 3.49 permitidos; la base, 5/109),
  pero esos 4 pasos (342534–342537) son el pico de la base reproducido, no
  un exceso marginal por ruido. Con la única trayectoria que hay, H1b falla
  también en lo que dice su enunciado («elimina el ciclo de 342.5 s»,
  C-025), no solo por la letra: dentro del ciclo, k1b reproduce la base
  (punto 4), como ya dice C-028. Precisión: cent_pg se juzgó a la que
  imprime regime2 (2.7 %); sin redondear es 3/111 = 2.703 % en k1b_342,
  idéntico a la base y a k1pa_342, así que leído literalmente (c) falla
  también por cent_pg (punto 4); el veredicto no cambia. Lo que NO está
  decidido es si eso es una propiedad del diseño o una coincidencia de una
  trayectoria (k1pb_342 no es réplica: difiere ≤ 96 Pa en la sonda); lo
  decidirían ≥ 3 trayectorias de v2 completo en 342.45–342.56 s
  (12/14/15 ranks), que no existen.
  Que el diseño de conjunto activo con tope exacto (v2 con A2) cumpla la
  condición de aborto del plan es una lectura del coordinador sin valor de
  veredicto (punto 4): la regla no tiene umbral. El ciclo de k1b se ve por
  tramos de |d2p| sin la métrica circular de C-036, pero en una sola
  trayectoria. El inciso de ciclo pre-registrado (a) no decide en ningún
  sentido: pasa por la letra, pero solo en la mediana (C-028). Las variantes que
  quitaron el ciclo en la sonda o mejoraron 340–346 s tienen holgura bajo el
  tope:
  - k1_340 (v1) es la única variante con 340–346 s completo. Su holgura
    no está medida (no tiene sonda); la de v1 está medida en k1_342 (ag_min
    0.01834 frente al piso 0.0150: 0.33 puntos de α_g; C-032 la redondea a
    «~0.4 %»; cell_series k1_342 --steps 342510,342533). su criterio quedó refutado {C-027}. No es la mejor registrada:
    k1pa_340_n12 tiene menor cent_pg en las tres ventanas comparables (0.4,
    0.3 y 0.1 % frente a 0.5, 1.1 y 0.7 % en 340–342, 342–344 y 344–345.5 s).
  - El brazo K de C-041 es k1pa_340_*, declarado v2 sin A2 en C-040. Su
    binario no se identifica: la firma del audit en los 10 primeros pasos es
    compatible con esa declaración pero no la discrimina (signo de A2 no
    calibrado a 340 s; p_max apunta en sentido contrario; punto 7). Falta
    la prueba bit a bit.
  - **Observación post hoc fuera del criterio pre-registrado (n = 3):** en
    344–345.5 s, 2 de 3 trayectorias k1pa tuvieron cent_pg 0.1 y 0.3 %,
    frente a 6.7–9.5 % de la base. La tercera (k1pa_340_n15) llegó a 12.8 %
    y a la centinela de 2.00e6 Pa. La mejora no es robusta entre
    trayectorias {C-041}, y en el snapshot 345500 las tres trayectorias K
    tienen más líquido en el lecho que la base («Qué hacer si se retoma»,
    snapshots finales): la mejora en presión puede ser en parte un traslado.
  > [fuente: python3 scripts/diag/regime2.py campaigns/b1/k1_340 campaigns/b1/k1pa_340_n12 campaigns/b1/k1pa_340_n14 campaigns/b1/k1pa_340_n15 --w 340,342,342,344,344,345.5 (k1_340 0.5/1.1/0.7; n12 0.4/0.3/0.1; n14 0.2/0.2/0.3; n15 0.1/0.2/12.8) | ls -d campaigns/b1/*340* y último eaf3d_*.h5 de cada una (entre las variantes de Plan K, solo k1_340 llega a 346 s; f231_340 y npc3_340, que no son Plan K, también terminan en 346000)]
- **El brazo de tope exacto es UNA sola trayectoria, y dentro del ciclo
  reproduce la base.** k1pb_342 no es una réplica independiente de
  k1b_342: en la sonda (10,60,2), 342500–342560, dan osc2 885.7 frente a
  889.7 Pa, p75 de |d2p| 14 559 frente a 14 565 Pa, máximo 218 858 frente
  a 218 864 Pa, la misma fracción |d2p| > 1000 Pa (47 %) y los mismos
  pasos con p > 100 kPa (342451, 342452, 342534–342537; regime2 idéntico:
  5.4 % y p_max 8.03e5). En 342520–342537, k1b y la base tienen |d2p| >
  1000 Pa en el 100 % de los puntos (mediana 40.7 frente a 48.1 kPa; p75
  55.2 frente a 52.6 kPa) y el mismo pico (410.0 kPa en 342534 frente a
  413.4 kPa en 342535). Las cifras de toda la ventana 342500–342560 (47
  frente a 85 %, p75 14.6 frente a 112 kPa) salen casi enteras del tramo
  posterior al pico, 342538–342560 (14 frente a 100 %), y del arranque
  4–5 pasos más tardío del ciclo en k1b (punto 4). **Se retira** la
  lectura anterior de este reporte de que el tope exacto «mejora a la base
  en la sonda» y de que la directiva «no reintentar el conjunto activo con
  tope exacto» de la entrada «Plan K CERRADO» de `acople-pv.md` «es más
  fuerte que los datos». Esa única trayectoria va en el sentido de la
  directiva (con tope exacto el ciclo vuelve); lo que a la directiva le
  falta es replicación: ≥ 3 trayectorias de v2 completo en
  342.45–342.56 s (12/14/15 ranks), que no existen.
  > [fuente: python3 -c (h5py, p[1,59,9] de campaigns/b1/{k1b_342,k1pb_342,diag_p342b}/eaf3d_*.h5 en 342500–342560; mediana, fracción > 1000, p75 y máximo de |d2p|) → k1b 885.7 / 0.475 / 14559 / 218858; k1pb 889.7 / 0.475 / 14565 / 218864; base 51835 / 0.847 / 111994 / 333796; por tramos, ver la fuente del punto 4 | python3 scripts/diag/regime2.py campaigns/b1/k1b_342 campaigns/b1/k1pb_342 --w 342.45,342.56 (p>100k 5.4 / 5.4; pmax 8.03e5 / 8.03e5) | conteo de |p_max|>1e5 en audit.csv del punto 4]
- **La consistencia Poisson–transporte del diseño no se verificó en ningún
  brazo.** La propiedad central (§3.2 del plan: que el transporte vea s≈1,
  medido con `vol_lim` y `vol_unlinked`) no se midió por celda: el `vol_lim`
  de la celda sonda de H1 nunca se midió {C-012}. Los valores globales medios
  en 342.45–342.56 s apenas se mueven: `vol_lim` 2.481e-3 en la base frente a
  2.460e-3 en k1, k1b, k1pa y k1pb (−0.8 %); `vol_unlinked` 2.057e-3 en
  todos. Queda abierta la lectura de que se refutó una implementación cuya
  exportación al transporte no logró la consistencia buscada, no el
  concepto. El dato que la decidiría (vol_lim y vol_unl por celda en
  (10,60,2) y en las celdas del conjunto activo) no está en los datos.
  > [fuente: media de las columnas vol_lim y vol_unlinked de campaigns/b1/{diag_p342b,k1_342,k1b_342,k1pa_342,k1pb_342}/audit.csv con 342.45<=t<342.56 (111 filas)]
- **Qué hacer si se retoma.** `reevaluacion.md` (líneas 82–85) fijó de
  antemano esta consecuencia: «si gana la holgura, el diseño correcto es un
  tope con barrera continua consistente entre Poisson y transporte». Ganó la
  holgura en la sonda {C-039}, en una comparación de 1 trayectoria contra 1
  (k1_342 y k1pa_342 no son réplicas; punto 7). El juez B1 de
  3 trayectorias {C-041} usó k1pa_340_*, DECLARADO v2 sin A2 en C-040; la
  firma del audit es compatible pero no discriminante (punto 7). Si la
  declaración es correcta, la holgura (accidental, la de v2 sin A2) se
  juzgó en B1 y falló C-040 por la letra, por n15; si no, no se juzgó.
  Falta la prueba bit a bit (punto 7).
  - Si la declaración de C-040 es correcta, repetir un juez B1 de ≥ 3
    trayectorias con la MISMA variante (v2 sin A2) repetiría C-040/C-041
    con otro nombre; no se recomienda sin antes hacer la prueba bit a bit. Lo que no
    se ha juzgado es un diseño distinto: la barrera continua consistente
    entre Poisson y transporte de `reevaluacion.md`. Para él, el
    experimento decisivo seguiría siendo un juez B1 de varias trayectorias
    (≥ 3, 340–345.5 s, contra la base de {C-040}/{C-310}), no la ventana
    342.45–342.56 s: k1pa_342 pasó en esa ventana la métrica de ciclo de
    C-035 (osc2 209.5 Pa, ag_min 0.01834 en 342510–342533) y p>100k ≤ 3.2 %
    (1.8 %), pero no el inciso (b) de C-025 (grad_hid_max 10.52 > 3 en
    342500–342560), y la variante declarada igual (k1pa_340_*) falló el
    juez. Antes tendría que decir en qué
    difiere de la holgura ya juzgada, además de los precedentes de abajo.
    Una corrida de la base sin conjunto activo y con margen equivalente
    separaría «Poisson implícito» de «holgura», pero solo en un juez así
    decide algo. La corrida no existe.
  - *Lectura del redactor, sin corrida que la respalde:* en qué difiere un
    margen continuo bajo el tope de cuatro fracasos registrados. (i) La rampa
    del piso de poro por encima de ALPHA_BED (4547861, juez a 2 MPa,
    acople-pv.md:539–541) mueve el valor del tope según α_s; no cambia cómo
    se cierra la entrada al acercarse a él. (ii) D2.4, `alpha_g_comp_min`
    (refutada en el banco con el código actual, d24 en {C-091}), pone un
    piso de compliancia en la diagonal del Poisson; no toca la conmutación
    del limitador. (iii) Llevar el hueco de la banda al Poisson (A20-2,
    acople-pv.md:541–546) cierra caras de forma todo o nada. (iv) **D2.2, el
    precedente más cercano** (Plan D, 7-oct,
    `docs/dev-history/2026-10-07_plan_d_acople_implicito.md`, «D2.2 — caras
    del limitador en el Poisson»): escalaba coeficiente y Q* de cada cara de
    líquido hacia la receptora por `ws_lim_step`, continuo en [0,1], dentro
    del paso y sin estado entre pasos. Es decir, ya era un cierre GRADUAL en
    el Poisson con el momento congelado, y fue perjudicial en toda
    combinación (p>100k 15.2 % frente a 8.1 % de la base; centinela 11.2 %
    frente a 4.7 %). Su cierre binario, D2.2c (umbral 0.5, con pared
    sellada), también empeoró (p>100k 17.1/15.1 % en n4/n8, frente a
    4.9/4.4 % de la pared sola). La «pared» es D2.2b, clave
    `pc_liq_sealed_wall` (pared del gradiente del líquido en la celda
    sellada), aplicada SOBRE F2.8: «D2.2b sola (F2.8 binario)» en la tabla de
    Plan D significa D2.2b sobre F2.8 sin caras D2.2, no un cambio de
    nombre. Hoy `pc_liq_sealed_wall` tiene default false
    (`src/mod_config_3d.f90`:92) y está refutada en el banco del primer pico
    de B1 con el código actual (d22b en {C-091}: 2.83e5 Pa, 23 pasos). F2.8
    es otra cosa: el cierre binario de caras de líquido hacia una receptora
    sin hueco (`ws_liq_room`), anterior a D2.2b y activo en HEAD. Su lección, «cerrar la cara en el Poisson
    sin que el momento lo sepa mueve el problema a la celda donante» (la
    columna se sella de abajo arriba), se midió SOLO en el banco
    `bed_flood` (malla 12×24×16, 12 s). El propio Plan D concluye que
    «D2.2b, D2.4, D2.5 y D2.6 son mejoras locales del banco `bed_flood`
    que NO se transfieren a B1» (dev-history 2026-10-07, líneas 424–425);
    la cita trata de esas mejoras, no del empeoramiento de D2.2/D2.2c.
    Extenderla a D2.2 (que tampoco su empeoramiento predice B1) es lectura
    de este redactor, no de la fuente (pero ver los snapshots 345500,
    abajo).
    - En B1, el único dato de esta familia (cierre del lado del Poisson con
      el momento congelado, PLAN_K §2) va en sentido contrario EN p>100k
      (con la salvedad del desplazamiento de líquido, viñeta siguiente): las 4
      trayectorias de Plan K (k1_340, v1; k1pa_340_n12/n14/n15, declarado v2
      sin A2; firma de audit compatible, no discriminante, punto 7) bajaron
      p>100k frente a las 3 de
      la base en todas las ventanas hasta 345.3 s: 340–342 s, 0.1 % frente a
      2.2–4.1 %; 342–344 s, 1.4–2.4 % frente a 7.2–10.3 %; 344–345.3 s,
      6.4/6.6/9.0/15.1 % frente a 20.8–35.2 %. En 344–345.5 s, 3 de 4 quedan
      en 6.5–8.5 % frente a 20.2–31.5 % (n15, 26.4 %, entra en el rango de
      la base tras 345.3 s). C-312/C-313 tampoco ven el defecto trasladado a
      vol_lim, vol_unlinked, m_spill ni m_alpha_clip en 340–345.3 s, pero
      solo revisan esas cuatro columnas (la frase de C-312 «no hay indicio
      de que K desplace el defecto a otra métrica del audit» vale solo para
      ellas). En otra columna sí hay un cambio sistemático (revisor-
      refutador, ronda 1, O3): en [340, 345.3) s las 4 trayectorias K funden
      más, dm_liq = −dm_sol = 398.6–400.6 kg frente a 392.4–392.6 kg de la
      base (+6 a +8 kg, +1.5 a +2.1 %, con una dispersión de la base de 0.2
      kg), y dE_liq es 0.8–1.1 % mayor (4.561–4.573e8 frente a
      4.523–4.524e8). No es necesariamente un defecto, pero acompaña a la
      bajada de p>100k.
    - **Snapshots finales: K deja más líquido en el lecho** (revisor-
      refutador, ciclo 8, O1; recomprobado aquí, solo lectura). En
      345500 (k1pa_340_n12/n14/n15 frente a base_340_n14/n15; k1_340 solo
      tiene 346000 y no es comparable en tiempo):
      - Líquido (α_l·V) en celdas con α_s > ALPHA_BED (1e-2): 0.1575–0.1589
        m³ en K frente a 0.1540–0.1547 m³ en la base (+0.003 a +0.005 m³).
        El líquido total del dominio sube menos: 1.0741–1.0747 frente a
        1.0732 m³ (+0.0009 a +0.0015 m³, la fusión extra). El exceso en el
        lecho es mayor que el líquido añadido: K redistribuye líquido hacia
        el lecho. (Volúmenes con caras reconstruidas como puntos medios
        entre centros; el revisor da 0.1573–0.1587 frente a 0.1539–0.1545,
        mismo signo y orden.)
      - Centroide vertical del líquido: 0.2249–0.2250 m en K frente a
        0.2255–0.2257 m en la base (más bajo).
      - Celdas de lecho con α_g bajo el umbral y α_l > 0.05 (el piso es
        0.0150 en todas): con 0.016, 133/130/142 (n12/n14/n15) frente a
        117/121; con 0.02, 143/145/155 frente a 132/133; con 0.05,
        162/165/169 frente a 150/155. Los rangos no se solapan con ningún
        umbral. Es la población de {C-030}, y n15, la trayectoria que se
        pegó a 2 MPa, es la que más tiene. k1_340 en 346000: 135/144/153.
      - Es el patrón «presión baja, líquido en el lecho sube»: la bajada de
        p>100k de K puede ser en parte un traslado del defecto al
        contenido de líquido del lecho, que C-312/C-313 no miran. Con un
        solo snapshot por corrida no se separa «K deja entrar líquido de
        forma no física» de «la base expulsa líquido con sus picos de
        presión»; lo decidiría una serie temporal de estas métricas en base
        y K (corrida con output_freq menor), que no existe («Experimentos
        que este reporte nombra y que no existen», 2).
    > [fuente: python3 (h5py; campaigns/b1/{base_340_n14,base_340_n15,k1pa_340_n12,k1pa_340_n14,k1pa_340_n15}/eaf3d_00345500.h5 y campaigns/b1/k1_340/eaf3d_00346000.h5; V = ½(rf²₊−rf²₋)·Δθ·Δz con rf, zf puntos medios de mesh/r, mesh/z; lecho = alpha_solid > 1e-2 (ALPHA_BED, src/mod_constants.f90:75)) → V_liq lecho base 0.1547/0.1540, K 0.1589/0.1589/0.1575, k1_340 0.1541; V_liq total 1.0732/1.0732, 1.0741/1.0743/1.0747; centroide z 0.2257/0.2255, 0.2249/0.2249/0.2250; celdas (α_g<0.016, 0.02, 0.05; α_l>0.05) base 117,132,150 / 121,133,155; K 133,143,162 / 130,145,165 / 142,155,169; ag_min lecho 0.01500 en todas]
    - Esto NO prueba que la lección de D2.2 sea falsa en B1 (Plan K no
      cierra caras en el limitador como D2.2, y el juez C-040 se refutó por
      otra métrica). Tampoco se puede decir que «la lección del banco no
      predice B1»: en p>100k no hay dato de B1 que la respalde, pero el
      exceso de líquido en el lecho de los snapshots 345500 (viñeta
      anterior) es compatible con un desplazamiento del problema, que es la
      forma general de esa lección (su mecanismo concreto, la celda donante
      convertida en callejón sin salida, no se midió en B1). El
      experimento que lo decidiría, D2.2 en B1, no existe. D2.2c sí se
      intentó en el banco del primer pico de B1 el 23-oct ({C-090},
      `campaigns/b1/bench_d22c`) y quedó FALLIDA no evaluable ({C-091}):
      `pc_limiter_faces` es incompatible con `pc_transport_f28`, activo por
      defecto (`src/mod_config_3d.f90`:603–607, B21-F1: con el corte de J-B
      la cara cierra y reabre en ciclo entre outers). Además HEAD solo tiene
      el cierre BINARIO D2.2c (`face_lim`, `src/mod_pressure_3d.f90`:
      1769–1795); el escalado continuo D2.2 ya no está en el código. Lanzar
      «D2.2 en B1» con `pc_limiter_faces = true` aborta en la configuración,
      como bench_d22c; apagar `pc_transport_f28` para que corra confundiría
      el resultado con J-B y con el ciclo B21-F1.
    > [fuente: python3 scripts/diag/regime2.py campaigns/b1/{judge_otp_280,base_340_n14,base_340_n15,k1_340,k1pa_340_n12,k1pa_340_n14,k1pa_340_n15} --w 340,342,342,344,344,345.5 (p>100k base 2.3/4.1/2.2, 10.3/9.8/7.2, 23.9/20.2/31.5; K 0.1×4, 1.6/1.4/1.6/2.4, 6.7/6.5/8.5/26.4) | idem --w 344,345.3 (base 25.1/20.8/35.2; K 6.4/6.6/9.0/15.1) | sed -n 424,425p docs/dev-history/2026-10-07_plan_d_acople_implicito.md | ledger.py show C-312 | ledger.py show C-313 | python3 (csv.DictReader de campaigns/b1/{judge_otp_280,base_340_n14,base_340_n15,k1_340,k1pa_340_n12,k1pa_340_n14,k1pa_340_n15}/audit.csv, última menos primera fila con 340 <= time < 345.3; m_liq en kg, mod_audit.f90:83–114): dm_liq 392.50/392.44/392.64 y 399.48/398.56/400.17/400.64; dm_liq + dm_sol = 0.000; dE_liq 4.5241/4.5228/4.5238e8 y 4.5667/4.5608/4.5705/4.5733e8]
    - Por eso **se retira** la frase anterior de este reporte («un margen
      continuo la sustituye por un cierre gradual, que los tres anteriores
      conservan; esa es la única razón para esperar un resultado distinto»):
      el cierre gradual en el Poisson ya se probó en D2.2 (solo en el banco
      `bed_flood`; en B1 no se probó).
    - Lo único que distingue a un margen bajo el tope de D2.2, y es una
      conjetura sin dato: D2.2 copiaba en el Poisson el `ws_lim_step` de la
      pasada anterior de un limitador del transporte que SÍ llegaba al tope
      (§2 del plan: «la presión veía un limitador viejo»), mientras que un
      margen evitaría que la celda llegue a él, de modo que ninguna cara
      quedaría cerrada del todo ni la donante se convertiría en callejón sin
      salida. Por qué eso cambiaría el resultado no está demostrado: la
      barrera sigue reduciendo la entrada en el Poisson sin que el momento
      lo sepa, que es el mecanismo que hundió a D2.2 en el banco. Si ese
      mecanismo actuara en B1, un diseño que quiera evitarlo tendría que
      hacer que el momento del líquido vea el cierre (como D2.2b/D2.6), no
      solo el Poisson; los datos de Plan K en B1 (arriba) no muestran que
      actúe allí.
    - Vigencia y sitio de medida: D2.2/D2.2c se midieron en el banco
      `bed_flood` (12 s), no en B1, el 7-oct, antes de las auditorías 3–21; por C-089/C-284 son
      **condicionales** al código de su fecha, no refutaciones vigentes. Lo
      mismo vale para el argumento de (iv): es un precedente a revalidar, no
      un veto.
    - Que k1pa_340_* tuviera holgura es lo que declara C-040; la firma del
      audit (punto 7) es compatible pero no discriminante. Si la
      declaración es correcta, la holgura pasó por el juez de B1 y C-040 la
      refutó por la letra; si no, la holgura no se juzgó en B1. Lo decide
      la prueba bit a bit («Experimentos que este reporte nombra y que no
      existen», 1).
  > [fuente: python3 scripts/diag/cell_series.py campaigns/b1/k1pa_342 --cell 10,60,2 --steps 342510,342533 --quiet (osc2=209.5) | python3 scripts/diag/regime2.py campaigns/b1/k1pa_342 --w 342.45,342.56 (p>100k 1.8) | ledger.py show C-041 | ledger.py show C-090 | ledger.py show C-091 (d24 y d22b refutadas; d22c FALLIDA, config inválida) | ls -d campaigns/b1/bench_d22b campaigns/b1/bench_d22c | grep -n 'pc_liq_sealed_wall *=\|pc_limiter_faces *=\|pc_transport_f28 *=' src/mod_config_3d.f90 (91, 92, 110) | sed -n 603,607p src/mod_config_3d.f90 | sed -n 1769,1795p src/mod_pressure_3d.f90 | sed -n '95p;112,119p' docs/dev-history/2026-10-07_plan_d_acople_implicito.md | sed -n 536,546p .claude/rules/acople-pv.md | sed -n '50,54p;71,78p;112,123p;159,166p' docs/dev-history/2026-10-07_plan_d_acople_implicito.md (D2.2: 15.2/8.1 y 11.2/4.7; D2.2c: 17.1/15.1 frente a 4.9/4.4) | sed -n 24,27p docs/PLAN_K_limitador_en_poisson.md]
  - Dentro de la holgura, tampoco está separado el factor 1 de la entrada no
    enlazada (punto 5).
- **{C-039} deja abierta una pregunta que no tiene afirmación propia en el
  registro:** si la holgura es física o accidental.
- **Vigencia.** La regla de método está en `.claude/rules/acople-pv.md`, líneas
  266–274. Su enunciado como afirmación (C-089) quedó «fallida» por {C-284},
  que conserva la regla solo como método. La regla clasifica a Plan K como
  **VIGENTE** (código del 23-oct), no como condicional.
  - Hay 7 commits en `src/` desde 1bc9832: c80dff6, 50d1d97, e3397d4,
    4d8570a, 79dc27b, 2b65e11 y 1de144e. Son WS-K7 a K10 y columnas de
    audit, y tocan `mod_pressure_3d` y `mod_continuity`.
  - Seis declaran en su mensaje de commit que la numérica no cambia: «bit a
    bit» (c80dff6, 50d1d97, 4d8570a), «test-full reproduce el golden v131
    con error 0» (2b65e11), «columnas comunes … idénticas; golden v132»
    (1de144e) o «idéntica salvo el último bit del acumulador diagnóstico
    m_gas_volfix» (e3397d4). El séptimo, 79dc27b, dice algo más débil:
    «sin cambio numérico en las columnas físicas», y toca
    `mod_pressure_3d.f90` (32 líneas). Este redactor no lo reverificó; viene
    de los mensajes de commit.
  - Con eso, los fracasos de H1/H1b se leen como vigentes para la ruta de la
    base. Pero los parches ya no aplican sobre HEAD (abajo): un Plan K
    rebasado es código nuevo y tendría que volver a pasar H1b en el banco
    actual.
  > [fuente: sed -n 266,274p .claude/rules/acople-pv.md | ledger.py show C-284 | git log --format='%h %s' 1bc9832..HEAD -- src | for c in c80dff6 50d1d97 e3397d4 4d8570a 79dc27b 2b65e11 1de144e; do git show -s --format=%B $c | grep -i "bit\|error 0\|golden\|numéric\|numeric"; done | git show --stat 79dc27b -- src]
- **Los 9 hallazgos de la auditoría nunca se verificaron.** Si el Plan K se
  retoma, hay que reabrirlos. A3, el freno de presión sobre el momento del
  líquido {C-018}, estaba PENDIENTE.
- **El registro permanente del Plan K** (R2). La entrada «Plan K CERRADO:
  refutado y NO adoptado» de `.claude/rules/acople-pv.md` (justo después de
  «H0 del Plan K CONFIRMADO») y el «§6. Cierre» de
  `docs/PLAN_K_limitador_en_poisson.md` están en HEAD desde e250687
  (cierre de WS-K2). El diff staged de este cierre (ciclo 9, hecho por el
  coordinador; ciclo 10, correcciones del panel del ciclo 9) los reduce a
  los VEREDICTOS del registro: `acople-pv.md` +35/−49 líneas y el plan
  +17/−18. Lo que dicen en el índice:
  - Entrada (`acople-pv.md`:618–654):
    - H1, refutada (C-012).
    - H1b, refutada por (b) y (c); su inciso (a) pasa solo en la mediana
      (C-028).
    - El juez, refutado (C-041), con tres salvedades:
      - la base también pasa de 1 MPa (C-310/C-311);
      - el pegado de n15 no está probado como propio de K (C-312/C-313);
      - la causalidad queda sin decidir (C-309; C-064, fallida por C-294).
    - «C-041 refutó la mejora pre-registrada en B1 (C-040); que 2 de 3
      trayectorias K mejoraran a la base en 344–345.5 s es una lectura post
      hoc sin veredicto. No adoptarlo fue una DECISIÓN del usuario (C-065)».
    - ABIERTO, sin veredicto:
      - la holgura (C-039) y si el brazo K del juez fue esa variante (solo
        declarado en C-040);
      - si es mejora o traslado de líquido al lecho;
      - D2.2/D2.2c como precedente de banco. En B1 no puede correrse tal
        cual, porque `pc_limiter_faces` es incompatible con
        `pc_transport_f28` y la configuración aborta.
    - Lectura estructural, sin veredicto: «No reintentar el conjunto activo
      con tope exacto sin atacar ese retraso», ahora con «El tope exacto
      tiene UNA sola trayectoria (k1b ≈ k1pb)».
    - Guía contra repeticiones: una retoma tiene que decir en qué difiere
      de D2.2/D2.2c, 4547861, D2.4 (C-091) y A20-2, y su juez es B1 con
      ≥ 3 trayectorias contra C-040/C-310.
    - Vigencia: código de 1bc9832.
  - §6 (líneas 86–109): los mismos veredictos; la holgura, «medida en
    k1_342 (v1) y en k1pa_342».
  - `ledger.py open` sigue sin mostrar Plan K: solo lista las cinco últimas
    refutadas.
  - Respecto de HEAD, el ciclo 9 retiró de la entrada: la regla de aborto
    de §4; las cifras de la holgura (C-035–C-038); la identificación del
    brazo K por la firma del audit y el «muy probablemente YA pasó por ese
    juez»; el «BAJÓ p>100k … no predice B1»; las cifras de D2.2/D2.2c; y
    la **guía contra repeticiones** (HEAD, `acople-pv.md`:661–666): que el
    experimento decisivo es un juez B1 de ≥ 3 trayectorias en 340–345.5 s
    contra C-040/C-310, no la ventana 342.45–342.56 s (k1pa la pasó y falló
    el juez), y que antes hay que decir en qué difiere de 4547861,
    D2.4/C-091 y A20-2. En el ciclo 10 la guía se REPUSO en la entrada,
    con D2.2/D2.2c añadido (viñeta «Entrada» de arriba). El reporte de
    WS-K2, ya en HEAD, la cita por número de línea (`acople-pv.md`:659–666),
    que ya no coincide con su posición nueva; el contenido sí existe.
  - *Historial, superado por el ciclo 9:* entre los ciclos 3 y 8 el
    coordinador corrigió varias veces la entrada y el §6 (regla de aborto
    sin umbral; inciso (a) solo en la mediana; 183 pasos de n15 en ≥ 1 MPa;
    D2.2/D2.2c como precedente, con su salvedad de banco; brazo K
    identificado por la firma del audit; holgura en k1_342 y k1pa_342). Las
    de los ciclos 3 y 4 entraron en HEAD con e250687; las de los ciclos 5 a
    8 se hicieron en el índice. El ciclo 9 sustituyó todas por la reducción
    descrita arriba; de ellas, en el índice solo queda «(a) pasa solo en la
    mediana» y la holgura en k1_342 y k1pa_342 (en el §6). Las objeciones
    de cada ciclo están en `research/ws/WS-K1/reviews/ciclo*/`.
  - Las cuatro correcciones que pidió el panel del ciclo 9 (auditor
    MEDIO-1 y BAJO-1 a BAJO-3; refutador O2) están hechas en el índice para
    el ciclo 10, con la redacción de la viñeta «Entrada» de arriba. La
    referencia del reporte de WS-K2 a la guía vuelve a ser válida.
  > [fuente: git diff --cached --numstat -- .claude/rules/acople-pv.md docs/PLAN_K_limitador_en_poisson.md (35 49 / 17 18) | git show :.claude/rules/acople-pv.md | sed -n 618,654p | git show :docs/PLAN_K_limitador_en_poisson.md | sed -n 86,109p | git show HEAD:.claude/rules/acople-pv.md | grep -n "Plan K CERRADO" -A 60 (guía en 661–666) | sed -n 270,287p research/ws/WS-K2/report.md | git grep -n --cached 'D2.2\|pc_limiter_faces' -- .claude/rules CLAUDE.md (acople-pv.md, dentro de la entrada) | git show :.claude/rules/acople-pv.md | grep -n '4547861\|A20-2' (540 y 544, fuera de la entrada) | git show :.claude/rules/acople-pv.md | grep -n 'solo en la mediana\|183 pasos\|regla de aborto' (solo 624) | sed -n 1780p src/mod_pressure_3d.f90 | sed -n 607,608p src/mod_config_3d.f90 | ledger.py show C-091]
- **No es verificable qué binario usó cada corrida.** Los `run.log` de
  k1_342, k1b_342, k1pa_342 y k1pb_342 no identifican el ejecutable ni el
  commit. En `campaigns/bin` no hay binarios k1, k1b, k1pa ni k1pb.
  - Las configuraciones coinciden en reinicio, t_final y
    `pc_alpha_implicit = true`. Entre P-a y P-b la única diferencia es
    `pc_ai_tol` (1e-3 frente a 1e-6). k1_342 difiere además en la ventana
    de sonda: `probe_step_from/to` = 342500–342540 (41 pasos), frente a
    342450–342560 (110 pasos con sonda) en k1b, k1pa y k1pb; y no fija
    `pc_ai_tol` (default 1e-6).
  - Que k1pa y k1b den series distintas con la misma `config.dat` (tol 1e-3)
    indica, de forma indirecta, que usaron binarios distintos. No prueba que
    fueran `pa_sin_A2` y `eaf3d_k1b_opt`, como exige C-036.
  - La estructura de los `run.log` lo resuelve en parte. Por paso con
    sonda, los cuatro dan 5 [PROBE-MOM] y 54 [PROBE-loc] (205/41 y 2214/41
    en k1_342; 550/110 y 5940/110 en k1b, k1pa y k1pb): todos hacen 5
    outers, y eso no los distingue. Lo que separa a k1pa de v1 es [PROBE-P]:
    10 líneas por paso en k1_342 (410/41) frente a 15 en k1b, k1pa y k1pb
    (1650/110). La línea extra es «pp tras conjunto activo», 550 veces (5
    por paso) en k1b, k1pa y k1pb y 0 en k1_342: k1pa no es el binario v1.
    Sus recuentos de [PROBE-AI] y [PROBE-pmax]
    (3211 y 1056) difieren de los de k1b (2971 y 571), y ya en el paso
    342451 fija 37 caras frente a 34 de k1b; pero esos recuentos dependen de
    la trayectoria, así que solo repiten el argumento indirecto anterior.
    Sigue sin probarse que k1pa sea exactamente `pa_sin_A2`.
  - De esto dependen {C-037}/{C-038} y, por tanto, el «ganó la holgura»
    {C-039}. Lo resolvería el hash del binario o el commit en el `run.log`,
    o recompilar los parches sobre 1bc9832 y comparar bit a bit.
  > [fuente: grep -i "pc_ai\|pc_alpha\|probe_step" campaigns/b1/k1*_342/config.dat | ls campaigns/bin | grep -c "pp tras conjunto activo" campaigns/b1/{k1_342,k1b_342,k1pa_342,k1pb_342}/run.log (0/550/550/550) | for d in k1_342 k1b_342 k1pa_342 k1pb_342; do grep -o '\[PROBE-[A-Za-z0-9_]*\]' campaigns/b1/$d/run.log | sort | uniq -c; done | grep -m1 PROBE-AI campaigns/b1/{k1b_342,k1pa_342}/run.log]
- **Cómo reconstruir los binarios (receta):** P-b (`eaf3d_k1b_opt`, v2
  completo) = `plan_k_v2.patch` sobre 1bc9832 (sus líneas `index` coinciden
  con los blobs de 1bc9832 en los tres archivos). P-a = `plan_k_v2.patch`
  sobre 1bc9832 y después `patches/pa_sin_A2.patch`, que es un diff
  incremental sobre v2 con rutas de cabecera no estándar («a/src/
  mod_pressure_3d.f90 (v2)»): hay que aplicarlo con `patch -p1` sobre el
  archivo ya parcheado, no con `git apply` sobre 1bc9832.
  `patches/v2_completo_sobre_HEAD.patch` es idéntico byte a byte a
  `plan_k_v2.patch` y su base es 1bc9832, no HEAD: el nombre engaña.
  > [fuente: grep ^index research/ws/WS-K1/plan_k_v2.patch frente a git rev-parse --short=7 1bc9832:src/{mod_config_3d,mod_pressure_3d,mod_types_3d}.f90 (412cfd5, 3c1948e, c01f606) | head -2 research/ws/WS-K1/patches/pa_sin_A2.patch | cmp research/ws/WS-K1/patches/v2_completo_sobre_HEAD.patch research/ws/WS-K1/plan_k_v2.patch (idénticos)]
- **Los parches archivados ya no aplican sobre HEAD:** `git apply --check`
  falla en `src/mod_pressure_3d.f90:733`. Hay 7 commits en `src/` desde
  1bc9832.
  > [fuente: git apply --check research/ws/WS-K1/plan_k_v2.patch (error: patch failed: src/mod_pressure_3d.f90:733) | git rev-list --count 1bc9832..HEAD -- src (7)]
- **Experimentos que este reporte nombra y que no existen:**
  1. Recompilar P-a y P-b sobre 1bc9832 (receta arriba) y comparar bit a
     bit 10 pasos con los audit de k1b_342 y de k1pa_340_n12, desde sus
     reinicios.
  2. Una serie temporal, en base y en K (con output_freq menor), del
     líquido en el lecho, el centroide y las celdas en el piso, para separar
     «K deja entrar líquido» de «la base lo expulsa con sus picos».
  3. ≥ 3 trayectorias de v2 completo (tope exacto) en 342.45–342.56 s, a
     12/14/15 ranks, para separar «el ciclo vuelve por el diseño» de
     «coincidencia de una trayectoria» (punto 4; k1pb_342 no es réplica).
  4. P-a y P-b a 14/15 ranks desde el mismo reinicio, para que {C-039} no
     sea una comparación de 1 trayectoria contra 1 (punto 7).
