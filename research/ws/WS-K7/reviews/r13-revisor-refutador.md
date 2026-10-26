# WS-K7, panel de cierre, ronda 1: revisor refutador

Solo lectura. Leí el reporte (secciones de rondas, Proceso, Resultado, Antecedentes y extractos de Incertidumbre), `ledger.py show` de C-110, C-120, C-125, C-137, C-140, C-145, C-150…C-154, C-157, C-163, C-167 y C-168, `ledger.py open`, la regla `.claude/rules/transporte-energia.md:128-240` y el código staged de `src/mod_pressure_3d.f90` (act_g, ag_eff, ensamblaje de caras, face_lim). No leí `reviews/`.

## Qué cambia en esta ronda

La única objeción bloqueante de la ronda anterior (O1: la cadena C-121…C-167 no referenciaba C-110) queda atendida. C-168 (`ref C-110`, en_disputa) resume el resultado contra la hipótesis que prueba. `ledger.py show C-110` lista ahora C-120, C-151, C-152 y C-168, y `ledger.py open` muestra **C-110 en_disputa**, ya no «propuesta» sin corregir. El párrafo WS-K5 de la regla (:140-145) remite a C-168 y ya no llama «alternativa abierta» a ws_Fg_lk = 0.

## 1. Conclusiones, alternativas y dato que las separa

**(1) Veredicto SIN DECIDIR (C-145, en_disputa): 0.319 y neto 1.571.**
- Recalculado de `campaigns/b1/k7v5_mo20/audit.csv`: 0.31859 y 1.57054. En k7v5_base: 0.404 y 1.320.
- Alternativa: H estaría en realidad refutada en el régimen, porque las ventanas largas derivan hacia ≥ 0.5 y los bancos con el CG convergido caen 5 de 8 en la banda de refutación.
- Dato que las separa: k7v5_mo20 con `max_inner_pres` 200, pre-registrado. Ese dato no existe.
- El reporte lo declara: el «sin decidir» vale para los 59 pasos, es frágil frente al CG en ambas direcciones y solo protege contra «soportada» (C-163). No sobreafirma.

**(2) En las nogas la masa es flujo exportado por el último Poisson, no creación por el complemento.**
- Alternativa A: el complemento crea y destruye gas dentro del paso, entre externas. Queda descartada por medida: Σ|dm| por llamada en las nogas es 1.908e-6 kg frente a Σ|e| = 4.816e-3 kg (recalculado; k7v4 y k7v5 idénticos).
- Alternativa B: el conducto no es la α de cara media sino un piso de la α efectiva del gas. Verificado en el código staged: `ag_eff = gas%alpha` (:246) sin piso posterior; `af = 0.5*(aef(P)+aef(N))` (:1203/:1237/…); `face_lim` devuelve 1 para el gas (:1701); `pc_gas_spring` = false por defecto y ausente en la config del banco, así que la celda solo entra en act_g por alcance (:234-236).
- Sin medir y declarado: el reparto por cara, quién conduce, y si la celda es ciega o de paso.
- La identificación con «la parte α_g = 0 del +5.11e-3 creada» de C-110 es cualitativa: e_nogas con signo solo está acotado en [2.7e-3, 4.2e-3] (C-140). Así está escrita.

**(3) «Convergido» no está medido.**
- Correcto en sustancia. La cifra está un poco inflada (ver N1).

**(4) e_multi depende de las externas (×1.84 en 59 pasos; 43 % en 999).**
- Recalculado: 1.837 y 0.4307.
- Alternativa: divergencia de trayectorias, no lazo truncado.
- Dato que las separa, y ya está en los datos: en el paso 280001, con el mismo estado inicial, e_multi vale −2.79e-5 con 5 externas frente a −1.36e-5 con 20. La diferencia ×2 aparece desde el primer paso, así que es el lazo y no la divergencia. Esto refuerza (4).

**(5) La alternativa ws_Fg_lk = 0 es nula (C-120).**
- Consistente con el código staged: ws_Fg se anula en cada Poisson y solo se escribe con lk = 1.

**(6) La identidad `mass_gas_rewrites` es permanente.**
- Coherente con el barrido de 78 bancos (reporte :373/:414) y con 67 PASS en `logs/test_full.txt`.

**Numérica idéntica.**
- Comprobado: k7v5_mo20 frente a k7v4_mo20 y frente a sonda_gc_mo20, 60 filas y 8 columnas de estado (p_max, m_gas, E_liq, E_gas, u_gas_max, dt, m_liq, vol_lim). Cero diferencias.

## 2. Repeticiones de fracasos registrados

- El WS no propone ningún remedio.
- La sección «Antecedentes» declara los remedios que la lectura sugeriría y ya están registrados como negativos:
  - α del dador para el gas o sacar el baño del alcance: chocan con F2.17–F2.21 y F2.24.
  - E1b `pc_sat_gas_off`.
  - Limitador en el Poisson (Plan K, D2.2).
  - `n_pc_max`.
  - F2.31.
- También declara la vigencia condicional de esos fracasos (C-089).
- La identidad de fila no se presenta como la válvula de Plan E: la clase nogas excluye ese poro por definición (C-165).
- No hay repetición sin declarar.

## 3. Objeciones (ninguna bloqueante)

- **N1.** C-168 (3): «≥ 85 %» debe ser ≥ 84.8 % (1001/1180; un solo CG por externa, `src/mod_pressure_3d.f90:784`, n_pc_max = 1). Se corrige con un evento que lleve ref C-168.
- **N2.** La regla dice que la u_z del líquido en las nogas «refuta la premisa de F2.21». La premisa es condicional («charco quieto») y la variable medida no es la u_f del gas en la cara. Debe decir «no se cumple en B1». La cifra sí reproduce: `rho_uz_nogas.py` da −0.283 / 0.0107 / 0.757.
- **N3.** «El piso neto vive en Δm_multi y en el flujo por la frontera» es una identidad por suma, no una localización. Hay que rotularla como identidad.
- **N4.** Resultado :299 mezcla 1.582 (k7v4) con el 1.571 vigente (k7v5). Hay que rotular el ciclo.

## Juicio

Con las cifras que comprobé, ninguna conclusión vigente es más fuerte que su dato. Las alternativas que quedan abiertas (CG truncado, ciega o de paso, quién conduce, piso neto) están declaradas con el experimento que las resolvería. El defecto que motivó el rechazo anterior está corregido en el registro.

VEREDICTO: aprueba