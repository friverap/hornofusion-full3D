# WS-K3: cierre de la meta G3 (verificación del Plan K) y de sus diagnósticos

**Meta G3** (`research/QUESTION.md`): los bancos (bed_bath_rest, bed_drain,
pocket_rise y bath_freeze), MPI con n1/n4, y la prueba bitwise con la clave
apagada. Terminado cuando test-full y `/verificacion-bitwise` no muestren
regresión.

**Conclusión: G3 (verificación del Plan K) quedó SIN OBJETO.** La meta era
verificar el Plan K antes de adoptarlo. El Plan K no se adoptó (WS-K1,
{C-065}) y `src/` no lo contiene, así que no hay cambio que verificar.
Nunca se corrieron ni los bancos, ni MPI n1/n4, ni la prueba bitwise con el
Plan K.

Mientras estuvo abierto, WS-K3 alojó otro trabajo: el diagnóstico del
régimen marginal de B1 con el código BASE (sin Plan K), con 15 afirmaciones,
todas ya cerradas.

Estado propuesto: `fallido`, con `cierre` = «G3 (verificación del Plan K)
sin objeto: Plan K no adoptado; 15 afirmaciones de diagnóstico cerradas».
El cierre no toca código ni registra eventos nuevos. El `fallido` es solo
el de esta verificación: WS-K4 a WS-K13 llevan la etiqueta G3 y están en
`aprobado` (K4-K8 numéricos, con sus commits de `src/` posteriores a
1bc9832 y su propia compuerta); este cierre no los toca.
> [fuente: research/ws/WS-K{4..13}/status.json (meta G3, estado aprobado;
> numerico=true en K4-K8); git log --oneline 1bc9832..HEAD -- src (7 commits)]

**Cómo se cierra** (`research/README.md`, «Estados de un workstream»): si el
panel aprueba este reporte por unanimidad, el coordinador fija
`ledger.py ws-set WS-K3 estado=fallido cierre=<motivo>`; `ledger.py check`
exige para `fallido` la clave `cierre` y los tres «aprueba» de la ronda
vigente. Un `fallido` no abre la compuerta de commit.

## Proceso: lo que se hizo en WS-K3

1. **Velocidad fantasma como precursor de los picos de la base** {C-074}:
   - Primera prueba: no concluyente {C-075} → C-076.
   - Segunda: refutada {C-077} → {C-078}. Hubo precursor en 19 de 31 eventos
     (61.3 % < 70 %).
   - WS-K12 cerró C-074 como refutada (C-280).
   > [fuente: ledger.py show C-074 (cadena C-075..C-078, C-280)]
2. **Punto caliente:**
   - Los picos de la base están en una esquina del piso junto a la costura
     theta. C-079 es una observación, cerrada como no concluyente (C-281).
   - Lo fija el estado del material bajo el electrodo 1 {C-082}, con el
     soporte del giro de 120 grados {C-083} → {C-084}: 21 de 21 eventos
     siguieron al estado girado.
   - Alcance según C-282: el giro movió juntos el material y z_tip.
   > [fuente: ledger.py show C-082 (cadena C-083, C-084, C-282)]
3. **Primer pico (paso 341705):**
   - C-085 lo atribuye a la fuente del líquido; su prueba quedó refutada en
     la letra {C-086} → C-087, y WS-K12 cerró C-085 como no concluyente.
   - La observación {C-088} quedó cerrada sin verificar.
   > [fuente: ledger.py show C-085 | show C-088]
4. **Revalidación de los Planes D, E y F con el código actual:**
   - Base es la regla de vigencia del usuario {C-089}.
   - Banco del primer pico {C-090} → {C-091}: pasan d26k, e1 y bed_flood.
   - Juez denso de 340–345.5 s {C-092}: d26k y e1 refutadas {C-093} por el
     inciso (d), que falla por DOS checks en las 4 corridas:
     - sentinel_gas en FAIL: pasos con u_gas >= 300 (n15/n14) d26k 23/77,
       e1 2/1.
     - energy_balance gap/permitido d26k 2.32/2.31 y e1 1.79/1.84 frente a
       1.717 de base (C-284: el 2.31 de d26k_n14 es errata; check_audit da
       2.334).
     - La base también falla ambos (201/131 pasos; 1.717). Frente a ella,
       d26k y e1 mejoran picos y centinela de gas y EMPEORAN la energía
       (C-094, C-284). La caída no se reduce al residuo de la
       sub-relajación que la base comparte (C-105 e): sentinel_gas también
       falla en las 4.
   - {C-308} precisa que dos de sus picos son la fila del paso truncado; el
     veredicto no cambia.
   > [fuente: ledger.py show C-090 | show C-092 (cadena C-093, C-094, C-308)]
5. **Fuga de energía de B1:**
   - La sub-relajación de T la localiza {C-095} → {C-096}.
   - El mecanismo propuesto {C-097} quedó refutado en la letra {C-098}.
   - El juez de alpha_T 0.85 {C-099} quedó refutado {C-100} por el inciso
     (c).
   - La columna del residuo de la sub-relajación {C-101} quedó soportada
     {C-102}. Esa línea siguió en WS-K4 (C-103).
   > [fuente: ledger.py show C-095 | show C-097 | show C-099 | show C-101]
6. **Masa del gas que reescribe la EOS:**
   - El juez de e1 en 280–285.5 s {C-104} quedó refutado {C-105}
     (mass_gas).
   - La hipótesis de la deriva continua {C-106} quedó refutada {C-107}.
   - La del resto en 280 s {C-108} quedó refutada {C-109}.
   - La localización {C-110} siguió en WS-K7/K8 (C-120, C-151, C-168, C-175)
     y WS-K12 la cerró «sin decidir» (C-304).
   > [fuente: ledger.py show C-104 | show C-106 | show C-108 | show C-110]

## Estado de las afirmaciones

Hay 15 afirmaciones raíz en WS-K3, ninguna abierta:

| Estado | Cuántas | Cuáles |
|---|---|---|
| refutada | 7 | {C-074}, {C-092}, {C-097}, {C-099}, {C-104}, {C-106}, {C-108} |
| fallida | 4 | {C-079}, {C-085}, {C-088}, {C-089} |
| soportada | 3 | {C-082}, {C-095}, {C-101} |
| sin_decidir | 1 | {C-110} |

> [fuente: python3 -c "import sys,collections; sys.path.insert(0,'scripts/research'); import ledger as L; ev=L.load(); r=[x for x in ev if x['ws']=='WS-K3' and not x.get('ref')]; print(len(r), dict(collections.Counter(L.current_state(x['id'],ev) for x in r)))" (15 {'refutada': 7, 'fallida': 4, 'soportada': 3, 'sin_decidir': 1})]

## Incertidumbre

- **G3 no se refuta: queda sin objeto.** Si el Plan K se retoma, la
  verificación de G3 (bancos, MPI n1/n4 y bitwise con la clave apagada)
  sigue pendiente completa.
- **`research/QUESTION.md` no se actualizó desde el 22-oct-2026.** Sus metas
  G1–G3 son del Plan K, pero WS-K4 a WS-K13 usan la etiqueta G3 para trabajo
  de diagnóstico y de herramienta que esa meta no describe. Este cierre no lo
  corrige: redefinir la pregunta y las metas es decisión del usuario
  (`/pregunta`).
- **El juez de la combinación de bed_flood quedó comprometido y sin
  correr.** C-092 dejó escrito que se juzgaría en B1 si ni d26k ni e1
  pasaban; C-093 refutó a las dos, así que la condición se cumplió. Ese
  juez no se corrió (no existe `campaigns/b1/judge_combo*`; sí
  `bench_combo`, que pasó el banco en C-091) y ningún evento posterior a
  C-093 registra su descarte ni su motivo. Queda pendiente: correrlo o
  descartarlo con motivo es decisión del coordinador.
- **La revalidación C-089 dejó dos huecos.** (1) D2.2 (`pc_limiter_faces`,
  limitador en caras de Plan D, antecedente del limitador en el Poisson del
  Plan K) no es evaluable con el código actual: d22c es configuración
  inválida con `pc_transport_f28` (C-091). (2) E1 no se ha corrido con el
  código actual en 320–325 s, la ventana de su fracaso viejo (C-284); las
  corridas de E1 en `campaigns/b1` son 340–345.5 s (C-093), 280–285.5 s
  (C-105) y dos del 20-oct en 275–300 s, anteriores a C-089. Quien retome
  el Plan K no tiene el dato para separarlo de D2.2.
- **La regla de vigencia {C-089} quedó «fallida (no concluyente)» como
  afirmación** (C-284). Sigue en `.claude/rules/acople-pv.md` como regla de
  método del usuario.
