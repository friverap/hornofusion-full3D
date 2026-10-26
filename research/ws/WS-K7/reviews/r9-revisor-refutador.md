# WS-K7, ronda 1: revisor-refutador

Reporte revisado: `/Users/frariv/Horno/hornofusion-full3D/research/ws/WS-K7/report.md`. Revisión de solo lectura: python solo sobre datos existentes; sin make, mpirun ni corridas. No leí `reviews/`.

## Lo que verifiqué

- **Numérica idéntica.** k7v5_mo20 coincide bit a bit con k6_mo20 (binario de la etapa K6 = numérica de HEAD), con k7v4, k7v3, k7, sonda_gc y sonda_gm. Columnas comparadas, en los 60 renglones: p_max, m_gas, E_liq, E_gas, u_gas_max, dt, m_liq, u_liq_max, vol_lim y m_gas_err_multi. Hay 0 diferencias.
- **El binario corresponde al código en revisión.** El sha256 del diff staged de `src/` es hoy 0503d1f6…, igual que en `logs/opt_identidad.txt`, y no hay cambios sin indexar en `src/`. En `test_full.txt`: 0 FAIL, `TESTS (full): OK` y golden con err rel 0. El diff de `src/` fuera de `mod_audit` solo añade escrituras: ganchos, `ws_pc_unl_used` y la anulación tras las BC.
- **Prerrequisitos de C-144.**
  - Entre k7v5_mo20 y k7v4_mo20 difieren exactamente las 5 columnas que dependen de E2, de 110 comunes.
  - liq_skip = e2_skip = 0 en los tres bancos k7v5.
  - `mass_gas_rewrites` da PASS en los 78 `audit.csv` de `tests/out` y en k7v5_mo20 (resto −6.15e-14).
- **Veredicto.** rem_all/abs = 0.3186 y neto = 1.5705; en base, 0.4038 y 1.3196. La descomposición es 0.3836 (con gas, peso 0.7055) más 0.1629 (nogas, peso 0.2945), y da 0.3186.
- **Celdas sin gas (nogas).**
  - Σ|e| = 4.816e-3, Σ|ρV_pois| = 4.078e-3 (0.847 de Σ|e|) y Σ|ρV_eff| = 1.1e-16.
  - Insensible a las externas: 4.816e-3 con 20 frente a 4.832e-3 con 5.
- **El desfase de E2 no es vacuo.** `vol_unlinked` suma 0.207 m³ en 59 pasos (del orden de 6e-2 kg con ρ_g medio), frente a Σ|err_liq_unl| = 2.16e-5 kg.
- **Código.** Para el gas, `aef = gas%alpha` (`mod_pressure_3d.f90:246`) y `af = ½(aef_P + aef_vecina)`. `act_g` incluye por alcance celdas con α_g < 1e-2 (:234-236). Entre dos celdas con α_g = 0, F_g = 0, así que la cancelación interna en e_multi es consistente.
- **Tabla de {C-158}.** La reproduje con el cmd del reporte. bed_flood_n4 corre con claves de Plan D/E que no son las de defecto (`config.dat`).

## 1. Conclusiones, mejor alternativa y dato que las separa

| Conclusión | Alternativa | Dato que las separa | ¿Está en los datos? |
|---|---|---|---|
| Cambio solo de diagnóstico, numérica idéntica | Los ganchos alteran la optimización o el redondeo en otra configuración | Bit a bit frente a HEAD en B1 y golden en la matriz MPI | Sí, y son idénticos. Descartada. |
| C-145: sin decidir (0.319; neto 1.57) | Prueba fuera de premisa (H se planteó con convergencia; ≥ 85 % de los CG sin converger). El inciso por celda podría cruzar 0.3 con el CG convergido | k7v5_mo20 con max_inner_pres 200 | No. Aritmética con los datos: 0.279 si la brecha nogas baja a ≤ 0.028. El global sigue sin decidir por el neto (R2). |
| err_liq en 280 s = desajuste en caras enlazadas; desfase E2 ≤ 0.2 % | El desfase sale pequeño porque no hay E2 | Tamaño de E2 frente al desfase | Sí: `vol_unlinked` 0.207 m³ ≫ desfase. Descartada. |
| Nogas (29 % de Σ\|e\|): plan del Poisson en celdas llenas y exportación del gas por la α media, en `act_g` por alcance | (a) El peso del 29 % lo fija el CG truncado o el régimen de B1. (b) Conduce el flujo fantasma del gas, no la demanda de líquido | (a) B1 con el CG convergido. (b) Signo de Fs frente al de ws_Fc por cara; in_tot/in_ok | (a) Indicio a favor de la alternativa: en los bancos convergidos con claves por defecto el peso es 0–4.4 % y la brecha ≤ 0.028, frente a 29 % y 0.163 en B1. No es separable (los bancos no predicen B1). (b) No está (R1, R3). |
| «Mismo balance de fila que la válvula de Plan E» | Identidad válida en cualquier fila del Poisson | in_tot/in_ok y quién conduce | No. Los rasgos propios de Plan E están ausentes o sin medir (R3). |
| Insensible a las externas | El mismo CG residual en ambos bancos | B1 con el CG convergido | No. Declarado. |
| e_multi depende de las externas | Divergencia de trayectoria (base con FAIL `regime_gas` y `energy_balance`) | Banco de 10 externas que pase `check_audit` | No. Declarado. |
| Sobre el piso neto el WS no concluye | — | — | Coherente con los datos y con la identidad e_multi = Δm_multi − dt·F_g(∂) − rxn. |

## 2. Repeticiones de fracasos registrados

Ninguna sin declarar.

- El WS no propone remedio.
- err_liq re-mide el desfase 2 de Plan D, el `vol_lim` y la H0 de Plan K. Se declara como instrumento («Antecedentes», O4).
- El conducto de las nogas es el canal de alcance F2.21 más la α media de F2.24 en el Poisson del gas. Es diseño conocido, y el reporte mide que la premisa de F2.21 («u ≈ 0») no se cumple.
- Los remedios latentes (α del dador para el gas, sacar el baño del alcance, E1b, `n_pc_max`, F2.31, Plan K) se citan como cerrados en negativo, con la salvedad de vigencia {C-089}.

## 3. Objeciones (todas no bloqueantes)

- **R1.** bed_flood_n4 (claves de Plan D/E) fija la cota de «≤ 10 %». Con claves por defecto la brecha es ≤ 0.028, y el peso nogas es 0–4.4 % frente a 29.4 % en B1. Se resuelve con texto (los datos ya existen) y con k7v5_mo20 con max_inner_pres = 200, pre-registrado.
- **R2.** El inciso por celda queda a ±0.02 del umbral según la brecha atribuible al CG (0.279 o 0.300). El «sin decidir» global se sostiene solo por el neto. Se resuelve con el mismo banco y una frase en Resultado.
- **R3.** La etiqueta de «válvula de Plan E» carece de contenido más allá de la identidad de fila. Se resuelve con in_tot/in_ok y con signo(Fs) frente a signo(ws_Fc) por cara, pre-registrados; mientras tanto, describirlo como «flujo fantasma del gas F2.21 + F2.24».
- **R4.** Las ws_Fg de las celdas con α_g = 0 las reutilizan la energía (`mod_energy_3d.f90:183-190`) y el momento del gas (`mod_momentum_3d.f90:243, :344`). Eso choca con la regla de transporte-energía y no está medido. Se resuelve con Σ dt·|ws_Fg|·cp·T por las caras de las nogas, frente a E_conv_gas.

Ninguna conclusión vigente del reporte resulta falsa con los datos existentes. Las afirmaciones de mecanismo están retiradas o acotadas. Lo positivo (instrumento, identidad numérica, veredicto por la letra y conducto en el código) está verificado.

VEREDICTO: aprueba
