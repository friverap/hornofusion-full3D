# Revisión del refutador — WS-K7, ronda 1 (panel de cierre, 25-oct-2026)

Solo lectura. Datos leídos: `campaigns/b1/k7v4_{mo20,base,long}/audit.csv`, `k7v3_mo20/audit.csv`; código: `src/mod_audit.f90:990-1002`, `src/mod_pressure_3d.f90:1142-1246`; registro: C-109/110/120-124/126-128/130/131/134-143 y `ledger.py open`; `.claude/rules/acople-pv.md` (Plan D/E/F, F2.24, 22-oct, vigencia C-089); plan `~/.claude/plans/iterative-foraging-newell.md`.

## 1. Conclusiones del reporte y alternativas

| # | Conclusión | Mejor alternativa | Dato que las separa | ¿Está? Qué dice |
|---|---|---|---|---|
| C1 | H (C-110) **sin decidir** por la letra (0.319 sin filtro / 0.566 con filtro; neto 1.58 / 2.46) {C-139} | El instrumento no puede decidir H: Σ\|e\| multifase cuenta dos veces el flujo fantasma de cada cara interna (nogas +3.45e-3, espejo con gas ≈ −3.5e-3) y err_liq lo reproduce por identidad en ambos lados | e_gas y e_nogas netos por paso y su correlación; Σ\|ρ_g V_pois\|, Σ\|ρ_g V_eff\| en nogas | No está. Lo que hay: Σ\|e\|_nogas/Σ\|e\| = 0.294; en el conjunto con gas Σ\|ρV_eff\|/Σ\|ρV_pois\| = 0.26 (no es identidad pura ahí). Recalculé 0.3194/0.5660/1.5817/2.4557 (mo20) y 0.4036/0.6261/1.3195/0.8556 (base): coinciden |
| C2 | Identidad Δm_gas = comp + eos + volfix cierra a 1e-13 en todas las ventanas | — (instrumento permanente, no mecanismo) | — | Verificado por el auditor/evidencia; sin objeción |
| C3 | El 29 % en nogas es «caudal fantasma por α de cara MEDIA en el Poisson (F2.24), defecto del ensamblaje, no del complemento» (R6) | La magnitud la fija el volumen de líquido que el limitador rechaza (válvula ficticia de Plan E); la α media es solo el conducto | corr(Σ\|e\|_nogas, vol_lim) por paso en ventana larga; V_eff/V_pois en nogas | **Sí está y apoya la alternativa**: k7v4_long corr = 0.97 (pasos 1-4500), 0.94 (1-2000), 0.88 (1-500), Σ\|e\|_nogas/vol_lim ≈ 2.0e-2 kg/m³ constante por tramos; en 59 pasos vol_lim varía ±1 % y la correlación es 0.22-0.35 (no informativa). Signo verificado: e_nogas > 0 = salida neta planeada de gas = entrada de líquido planeada y rechazada |
| C4 | No hay churn oculto: Σ\|comp\| por llamada 1.38× neto, Σ\|eos\| 1.95× | — | — | Medido; sin objeción |
| C5 | Σ\|eos\| 38-51× Σ\|e\|: «un desajuste su_cc–EOS podría explicar TODO Σ\|e\|» | No puede: en nogas α_g = 0, comp por llamada 1.9e-6 ⇒ eos = su_cc = 0 ahí; ni en su espejo | — | Está en los datos del reporte: cota ≤ 71 % (≤ ~50 % sin el espejo) |
| C6 | e_multi depende de las externas (×1.84); e/paso no estacionario en ventana larga | Además el **cociente por celda** deriva (no solo e/paso) y cruza 0.7 con filtro | Tabla por tramos de k7v4_long | **Sí está**: sin filtro 0.43→0.57, con filtro 0.65→0.77 por tramos de 500; 53 % de los pasos con rem/abs ≥ 0.7; rem_all/abs nunca ≤ 0.3 ni ≥ 0.7 |
| C7 | «e_out ≈ −e_multi» hecho medido sin mecanismo | Coincidencia de sumas | corr por paso | **Sí está**: corr(e_multi, e_out) = −0.09 / 0.00 / −0.004; e_out cambia de signo por tercios (−3.5e-5, −1.5e-5, +1.0e-4) con e_multi estacionario |
| C8 | Sesgo M1 de peso cero en 280 s | — | m_gas_cells_nolink | Verificado: 0 en 59 pasos; 51 845 celdas-paso solo en la cola 4501-5499 (u_gas 300, p 5e5) |
| C9 | Retiro de «el piso neto vive en e − err_liq» (fórmula de amplitudes) | — | — | Fórmula recomputada: r = 0.236, ρ = 0.229 ⇒ 0.972. Correcto |

Nota sobre el confusor del CG (ronda 5, R3, «no acotado»): en las nogas err_liq ≈ e exige que la fila del Poisson balancee, así que \|e − err_liq\|/\|e\| ≤ 0.29 ahí acota CONJUNTAMENTE residuo de fila + ρ_g V_eff + desajuste ρ_celda/ρ_dador. No es objeción; el reporte puede usarlo.

## 2. Repeticiones de fracasos registrados

- H es la válvula ficticia de Plan E E1 medida con `[PROBE-P]` a 320 s (acople-pv.md «Plan E E1», E1b `pc_sat_gas_off` negativo en B1). El reporte lo declara en Antecedentes y no propone remedio: correcto. Salvedad: la lectura R6 (α media del gas en el Poisson como «defecto») sugiere implícitamente el dador para el gas en el Poisson = cerrar la válvula = E1b (negativo en B1, C-089 condicional). Debe quedar explícito que R6 no es una vía a E1b sin revalidación en banco vigente.
- La «pieza siguiente» (su_cc frente a m_gas_eos por celda) no repite C-106/C-108 (sub-relajación de T, refutadas) ni C-117 (volfix por celda). No es repetición.
- No hay regla local nueva de clasificación (D/E/F/G) ni limitador en el Poisson (Plan K): no aplica.

## 3. Objeciones

**R1 (bloqueante).** Atribución del 29 % nogas a la α de cara media «no del complemento» presentada como atribución corregida sin dato que la separe del rechazo del limitador; los datos existentes (k7v4_long: corr(Σ\|e\|_nogas, vol_lim) = 0.97 en 4500 pasos, cociente constante 2.0e-2 kg/m³) apoyan que la magnitud es el volumen rechazado (válvula de Plan E), y el espejo del mismo flujo en las celdas con gas es exactamente «flujo de gas sin complemento». Resolución: reescribir como conducto verificado en código + magnitud que sigue a vol_lim + causa no separada, en Resultado y en la corrección pendiente de `transporte-energia.md:173`; dato pre-registrado: Σ\|ρ_g V_pois\| y Σ\|ρ_g V_eff\| en nogas, vol_lim restringido a caras de nogas.

**R2 (no bloqueante).** «podría explicar TODO Σ\|e\|» (su_cc–EOS) contradicho por nogas (eos = su_cc = 0 ahí): cota ≤ 71 %. Corregir en reporte y regla; la columna Σ\|dt·su_cc\| pendiente debe ir por subconjunto.

**R3 (no bloqueante).** Deriva del cociente por celda en k7v4_long (0.43→0.57; con filtro 0.65→0.77, 53 % de pasos ≥ 0.7) omitida; el reporte solo cita 0.504/0.712 y dice que no cambia el veredicto. La ventana corta además arranca con transitorio de reinicio (p_max 1.0e5 en pasos 2-3 frente a mediana 4.2e4; los tercios de la corta no muestran efecto en el cociente: 0.323/0.318/0.318). Resolución: tabla por tramos en el reporte; «sin decidir» acotado a 59 pasos tras reinicio; experimento: ≥ 1000 pasos con 20 externas y columnas por celda, pre-registrado.

**R4 (no bloqueante).** «e_out ≈ −e_multi» es de sumas, no por paso (corr −0.09/0.00/−0.004; e_out cambia de signo dentro de la ventana; en base la suma es −2.9e-4). Declararlo y no usarlo como apoyo del «espejo».

**R5 (no bloqueante).** «err_liq explica el 60-85 % del neto de cada subconjunto» (Resultado, Incertidumbre (4), regla vía C-143): en nogas y en las celdas espejo es la identidad de volumen del Poisson; reetiquetar como «compatible con la identidad; no atribución a H». Dato: V_pois/V_eff en nogas; e_gas/e_nogas netos por paso.

## 4. Veredicto

El veredicto formal «sin decidir» {C-139} se sostiene por la letra y el reporte ya retiró las lecturas de mecanismo del neto. Lo que bloquea es la única atribución mecanística nueva que queda en pie (R6, 29 % nogas = defecto del ensamblaje «no del complemento»), que va camino de la regla sin el dato que la distinga de la válvula de Plan E, cuando los datos existentes del propio WS (ventana larga, vol_lim) sostienen la alternativa con corr 0.97.

VEREDICTO: rechaza
