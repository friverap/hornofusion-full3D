# WS-K5 — Balance de masa del gas por celda en el audit

Paso 1 de la propuesta posterior al diagnóstico de mass_gas en B1, aprobado
por el usuario el 24-oct-2026 («sí»). El objetivo era hacer visible dónde
reescribe masa la EOS, como WS-K4 hizo con el residuo de la sub-relajación de
T. Es un cambio solo de diagnóstico y no altera la numérica.

> **Corrección tras la ronda 1 del refutador (K5-R1, K5-R3):** las columnas
> por celda **no aíslan la EOS**. Por construcción suman
> libre + multi + outlet = EOS − venteo + volfix: el volfix por celda queda
> dentro de la clase donde actúa y el venteo dentro del outlet. Mientras el
> volfix no se separe por clase, `m_gas_err_free` y `m_gas_err_multi` miden
> «reescritura de la EOS + volfix» en esa clase, no la EOS sola. Los
> comentarios de `src/mod_audit.f90`, `docs/AUDIT_COLUMNS.md` y la regla
> `.claude/rules/transporte-energia.md`, que atribuyen la columna a la EOS
> o al complemento, ya están **corregidos** (ronda 3, coordinador): dicen que
> e incluye el volfix por celda sin separar por clase, y que `m_gas_err_multi`
> solo se lee como masa reescrita donde |volfix| << |multi|. `check_audit`
> imprime `AVISO volfix ... >= 10 % de multifase` cuando no es así; en
> cold_bucket2_slag_n1 sale el aviso (volfix −1.722 kg frente a multi
> −1.739), y en k5_mo20 y arc_slag_n4 no.
> [fuente: python3 tests/integration/check_audit.py campaigns/b1/k5_mo20 | tests/out/cold_bucket2_slag_n1 | tests/out/arc_slag_n4]
> Pendiente, como pieza aparte: separar el volfix por clase. Exige tocar
> las 6 rutas de volfix (mod_fields_3d, mod_ecs_feed, mod_slag_3d ×2,
> mod_slag_chemistry, mod_solid_phase).

## Proceso

1. El juez de e1 en 280–285.5 s se refutó solo por mass_gas: la EOS reescribe 0.615 relativo, con la base en 0.552 {C-105}.
2. El residuo es una deriva continua de unos −5e-5 kg/paso.
   - El lazo externo truncado explica cerca del 60 %: con max_outer 5, 10 y 20 el residuo da −13.3, −5.3 y −4.5 e-3 kg {C-107}{C-109}.
   - Queda un piso de alrededor de 1/3 que no depende de las externas ni de alpha_T {C-109}.
3. Sondas temporales, no commiteadas {C-110}:
   - **Hecho medido:** el inventario del gas solo cambia por la EOS y por el complemento α_g = 1 − Σ. El flujo del outlet nunca entra al inventario.
   - El balance por celda e = Δ(α ρ V) − dt Σ ws_Fg − rxn reparte el residuo: el lazo truncado cae en las celdas de gas libre y en el lecho; el piso, en las celdas multifase. Ese e incluye también el volfix por celda (K5-R1); en la ventana de la sonda no se midió aparte.
   - **Hipótesis, no probada** (C-110 sigue en «propuesta»): el piso sería el complemento, que crea gas donde el líquido se retira y lo destruye donde entra, sin flujo de gas.
   - **Alternativa abierta:** transporte por caras no enlazadas (ws_Fg_lk = 0), que se cancela en la suma. Cuadra con |e| = 1.7e-2 kg frente a un neto de −8.5e-4 kg.
4. Cambio de este workstream (revisado tras la ronda 1, {C-113}):
   - `src/mod_audit.f90`:
     - `gas_cell_class(al, asl, as, is_out)` (pura): 0 outlet; 1 gas libre (α_l, α_sl y α_s < ALPHA_FLOW_CUTOFF); 2 multifase. La escoria en volumen entra porque fuera de la vista condensada liq%alpha no la incluye (K5-M1).
     - `audit_gas_cells(mode, liq, gas, sol, slag, sh, m, cfg)`:
       - el modo 0 guarda α ρ V y la clase al inicio del paso;
       - el modo 1 acumula e con la ρ final, la misma que escribe m_gas;
       - una celda solo es libre si lo es al inicio Y al final del paso (R3);
       - sin ws_Fg válido (mezcla, una fase) suma 1 a `m_gas_cells_skip` y no acumula nada, para que las columnas no queden en 0 sin aviso (K5-M2, R5).
     - Cinco columnas anexadas: `m_gas_err_free`, `m_gas_err_multi`, `m_gas_err_abs`, `m_gas_err_out` (e de las celdas outlet) y `m_gas_cells_skip`.
     - `mg_ini` y `mg_cls0` no son estado entre pasos (se recapturan al inicio de cada paso), así que no entran al snapshot.
     - Outlet tiene la misma definición que `m_gas_out`.
   - `src/main_3d.f90`: llamadas al inicio del paso y después del `update_properties` final.
   - `tests/integration/check_audit.py`: `INFO mass_gas_cells` con la **identidad de cierre** EOS − (libre + multi + outlet) − venteo + volfix = 0 al redondeo. Las caras interiores se cancelan y `m_gas_out` ya es el flujo que entra al outlet (K5-M2). Esta identidad es algebraica: se cumple por construcción y solo prueba que el código es consistente, **no** que las columnas midan la EOS ni que localicen el piso (K5-R3). Imprime también la tasa intensiva de la EOS por segundo y por kg de gas; si hay pasos sin balance, lo dice. **No** cambia el gate de mass_gas.
   - `tests/unit/test_gas_cell_class.f90`: outlet manda; libre solo sin líquido, escoria ni sólido; los bordes en ALPHA_FLOW_CUTOFF caen del lado multifase; 3 casos con escoria.
   - Glosario (tipo D, con la hipótesis, la alternativa y el aviso de skip), `docs/AUDIT_COLUMNS.md` y la regla `.claude/rules/transporte-energia.md`, donde el mecanismo queda marcado como HIPÓTESIS (R1).

## Resultado

La primera versión (C-111 → C-112) reprodujo la sonda. La ronda 1 del panel encontró tres problemas {C-113}:
- la clasificación no veía la escoria;
- la referencia «≈ volfix» del cierre estaba mal;
- en mezcla, las columnas quedaban en 0 sin aviso.

Las columnas revisadas tienen su propio pre-registro, {C-114}, con veredicto soportada {C-115}.

- **B1 (k5_mo20 y k5_base)**, 59 pasos desde judge_otp_280/eaf3d_00280000.h5, 15 ranks, binario `campaigns/bin/eaf3d_k5col_opt`:
  - el cierre da −6.1e-14 y −7.1e-14 kg {C-115} (consistencia, no localización: K5-R3);
  - mo20: libre +2.179e-5, multifase −8.686e-4, outlet +9.244e-4 kg; EOS −8.554e-4, venteo −9.461e-4, volfix −1.310e-5 kg;
  - base: libre −9.896e-4, multifase −1.585e-3, outlet +1.284e-3 kg; EOS −2.580e-3, venteo −1.302e-3, volfix −1.312e-5 kg {C-115};
  - en mo20 la columna libre (+2.18e-5 kg) es del mismo orden que |volfix| (1.31e-5 kg) y que la diferencia outlet − |venteo| (−2.17e-5 kg): **no** puede leerse como «el gas libre conserva» (K5-R2, retirado). La multifase (−8.69e-4 kg) es ~66 veces |volfix|, así que en esta ventana el volfix la contamina como máximo en ~1.5 %, pero sigue siendo EOS + volfix de esa clase.
  - la numérica es idéntica bit a bit a sonda_gc_* (p_max, m_gas, E_liq, E_gas y u_gas_max en 60 renglones) {C-115}.

  > [fuente: campaigns/b1/k5_mo20, campaigns/b1/k5_base | python3 tests/integration/check_audit.py DIR; comparación csv frente a campaigns/b1/sonda_gc_*]
- **Bancos de test-full con balance (64):** |cierre| ≤ 4.0e-12 kg en todos, incluidos arc_noscrap, bath_freeze, arc_melt, bath_fill_adapt y los reinicios {C-115}.
  > [fuente: research/ws/WS-K5/logs/test_full.txt | grep mass_gas_cells]
- **El volfix domina la multifase en varios bancos (K5-R1).** En 18 de los 64 renglones con balance, |volfix| > 10 % de |multifase|. Ejemplos:
  - cold_bucket2_slag_n1 (test_full.txt:1822): multifase −1.739 kg con volfix −1.722 kg y EOS −1.773e-2 kg;
  - cold_bucket2_n4 (test_full.txt:1790): multifase −10.40 kg con volfix −10.47 kg y EOS −0.756 kg;
  - bath_freeze_n1 (test_full.txt:1202): multifase −0.260 kg con volfix −3.833 kg y EOS +3.942 kg.

  En esos bancos `m_gas_err_multi` es casi todo volfix, no EOS ni complemento.
  > [fuente: research/ws/WS-K5/logs/test_full.txt, renglón PASS mass_gas previo a cada INFO mass_gas_cells]
- **arc_slag_n4:** la multifase da −1.067 kg con un EOS de 1.097. Antes daba −9.7e-18, porque la escoria caía como gas libre {C-115}.
- **bath_fill_mix_n4, bath_mix_n4 y oneflow_test_n4:** reportan «sin balance por celda en N de N pasos» {C-115}.
- **Tests:** `make test-unit` OK (`PASS unit:test_gas_cell_class`), `make test-quick` OK y `make test-full` OK, con golden v131 y las comparaciones de audit tras reinicio en todas las columnas.
  > [fuente: research/ws/WS-K5/logs/test_unit.txt, test_quick.txt, test_full.txt]

## Incertidumbre

- **Las columnas no aíslan la EOS (K5-R1, bloqueante del panel).** Incluyen el volfix de su clase (y el outlet, el venteo). Para que `m_gas_err_free`/`m_gas_err_multi` midan la EOS hace falta separar el volfix por clase (columnas nuevas o restarlo dentro de e) y comprobar en test-full que libre + multi + outlet − volfix por clase = EOS − venteo, con cold_bucket2_slag en el orden de 1e-2 kg. Exige cambiar `src/` y `tests/`: pendiente del coordinador. Hasta entonces **ninguna conclusión numérica se apoya en `m_gas_err_multi` como medida del piso** (K5-R4).
- **No hay medida directa de la EOS por celda (K5-R3).** Falta comparar e por celda con Σ (ρ_post − ρ_pre)·α·V acumulada por clase en cada llamada a la EOS, en k5_mo20. Exige código: pendiente del coordinador.

- **El mecanismo del piso no está probado.** En B1 la columna multifase concentra el residuo (EOS + volfix de esa clase, con volfix ≤ 1.5 % allí), pero eso no distingue el complemento de las caras no enlazadas (R2) ni prueba que sea la EOS. Hace falta una prueba pre-registrada que correlacione e por celda con −Δα_l ρ_g V frente al flujo en caras con lk = 0 (K5-R4).
- **«Libre» ≈ lazo truncado es una interpretación, y «libre conserva cuando converge» queda retirada (K5-R2):** en mo20 la columna libre es del orden del volfix y del desfase outlet/venteo. Las celdas que cambian de clase dentro del paso ahora cuentan como multifase, pero `m_gas_err_multi` sigue incluyendo la parte del lazo truncado que cae en celdas con líquido, escoria o sólido: con 5 externas, el lecho pasa de −2.78e-3 a −3.69e-3 kg {C-110}. Solo con el lazo convergido se acerca a medir el piso.
- **La verificación de B1** es un solo banco de 59 pasos en la ventana de 280 s con 15 ranks. No cubre el régimen denso de 340 s, donde no se sabe cuánto vale el volfix; una ventana allí debe reportar el volfix (K5-R4).
- **Con mixture_model** no hay balance por celda: queda contado en `m_gas_cells_skip`.
