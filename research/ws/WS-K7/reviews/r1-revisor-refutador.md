# Revisión del refutador — WS-K7, ronda 1

Solo lectura: audit.csv de `campaigns/b1/k7_{mo20,base}`, `k7v3_{mo20,base}`, `sonda_gc_*`, run.log, `src/mod_audit.f90`, `src/mod_solver_3d.f90`, registro C-089/C-109/C-110/C-120..C-131, `.claude/rules/acople-pv.md` (Plan E, vigencia C-089), plan aprobado.

## 1. Conclusiones y alternativas

| Conclusión | Alternativa | Dato que separa | ¿Está? Qué dice |
|---|---|---|---|
| Alternativa «lk = 0 transporta gas» nula {C-120} | Otro lector del flujo | Código :209, :813-835 | Verificado en C-120; acepto |
| Δm_gas = comp + eos + volfix {C-127} | Check trivial | Falló antes del arreglo (Proceso 6); PASS 67 bancos | Tiene dientes; acepto |
| H «sin decidir» por celda (0.32 / 0.57) y neto falla; «la prueba por sumas netas no discrimina» {C-131} | **El neto sí discrimina: el piso neto no es err_liq** | corr por paso de e con err_liq y con el residuo | **Está**: k7v3_mo20 corr(e − err_liq_all, e) = 0.972; corr(err_liq_all, e) = 0.229; signo opuesto 59/59; con filtro corr(err_liq, e) = −0.016. El piso neto vive en el residuo con cualquier definición |
| «Σ|comp| = 2.27e-3 del orden de err_liq; Σ|eos| = 0.43 kg por celda y llamada (reescribe y deshace)» | Las columnas son |neto por celda y paso| | Código de los ganchos | **Está**: `audit_comp_cell`/`audit_eos_cell` acumulan dm con signo (:853-867) y el abs se aplica al acumulado (:939-944). La cancelación intra-paso ya está quitada; creación/destrucción NO medidas; 0.43 kg = neto por celda de compresibilidad, 26× |e| mediana por paso |
| 29 % de Σ|e| en nogas; «gas aparece y se destruye dentro del paso» | El gas nunca apareció: el Poisson empuja F_g por celdas de baño en act_g | Σ|comp| por llamada en nogas | No está (R-1c). e = −fl exacto ahí (rx 5.4e-6, volfix −1.3e-5 despreciables) |
| Nogas: err_liq explica 84 % (predicción C-130 cumplida) | Identidad de volumen del Poisson, no mecanismo | V_eff vs V_pois en nogas | No está: vpois_abs/veff_abs solo en el conjunto con gas (R-5) |
| «err_liq sigue al limitador» corr −0.85 | Depende del conjunto | corr(err_liq_all, vol_lim) | **Está**: +0.517 (mo20), +0.708 (base) — signo opuesto al citado (R-3) |
| e_multi depende de las externas (×1.84) | k7_base sucio (FAIL energy/regime) | check_audit | Verificado: k7v3_base FAIL energy_balance (gap/permitido 2.243) y regime_gas (215 m/s); el reporte lo declara |
| k7_mo20 «decide» (lazo convergido) | CG sin converger ≥1001 veces | Σ|e| base vs mo20 | Σ|e| 1.81e-2 (CG ok) vs 1.64e-2 (CG no): el CG no genera Σ|e|; efecto en rem/abs desconocido (R-4) |

## 2. Repeticiones
- H es la válvula ficticia de Plan E (acople-pv.md, E1 `[PROBE-P]` a 320 s); el reporte lo declara (Antecedentes) y no propone remedio ni reabre E1b. Salvedad C-089 citada. No es repetición encubierta.
- El neto nogas (+3.45e-3 ± 0.8e-3) es la re-medida de «α_g < 0.02, +5.11e-3 creada» de C-110; el reporte lo enlaza. Correcto.
- La tercera redefinición del conjunto (caras enlazadas) NO se adopta: bien.

## 3. Verificado con datos
- Sumas de las 59 filas de k7v3_mo20/base y k7_mo20/base: coinciden con el reporte (e_multi −8.555e-4, err_liq −2.956e-3, abs 1.636e-2, rem 9.257e-3, nogas 4.816e-3, vpois 8.80e-3, veff 2.28e-3, err_liq_all +4.977e-4, rem_all 5.225e-3, comp_abs 2.271e-3, eos_abs 4.324e-1; cocientes 0.566 / 0.319 / 2.456 / 1.582; mediana por paso 0.318, rango 0.304–0.381; corr −0.016 / −0.853 / 0.976; base 0.583 / −0.890).
- Σ_nogas|e − err_liq| = rem_all − (rem − nogas) = 7.85e-4; err_liq nogas = +3.454e-3. Derivación válida (mismo `el` en ambas ramas del código).
- Bit a bit: p_max, m_gas, E_liq, E_gas, u_gas_max de k7v3_mo20 = k7_mo20 = sonda_gc_mo20; k7v3_base = sonda_gc_base. m_gas_err_liq y rem_abs entre k7 y k7v3 difieren ≤ 2.7e-20 (orden de suma).
- check_audit k7v3_mo20: PASS energy (0.050), PASS regime (163.5), PASS mass_gas_rewrites (resto −6.15e-14). k7v3_base: FAIL energy (2.243), FAIL regime (215.0), PASS rewrites (−7.08e-14).
- run.log k7_mo20/k7v3_mo20: avisos CG con «1 casos» y «1001 casos» (el código imprime cada 1000): ≥1001 Poisson sin converger; k7_base/k7v3_base: 1.

## 4. Objeciones
- **R-1 (bloqueante)** `m_gas_comp_abs`/`m_gas_eos_abs` son Σ|neto por celda y paso| (código :853-867, :939-944), no «por sitio»/«por llamada». Retirar la conclusión R2 («NO es 100× mayor»), la explicación del 0.43 kg y «aparece y se destruye dentro del paso», o añadir acumuladores de |dm| por llamada pre-registrados. Señalar que 0.43 kg/59 = 7.3e-3 kg/paso es 26× |e|: un 4 % de desajuste su_cc/EOS explicaría todo Σ|e| (alternativa de C-120 no descartada).
- **R-2 (bloqueante)** Añadir las correlaciones por paso (0.972 / 0.229 / 59 de 59 signo opuesto / −0.016) y concluir que H no explica el piso NETO con ninguna definición; quitar «no discrimina» (reinterpretación posterior del criterio pre-registrado).
- **R-3** Citar corr(err_liq_all, vol_lim) = +0.52/+0.71 junto al −0.85 filtrado.
- **R-4** Dar la fracción de Poisson sin converger (n_pc por paso) y el sentido de «res» (reducido); citar Σ|e| base/mo20 como cota del confusor; efecto sobre rem/abs pendiente (coordinador).
- **R-5** En nogas e = −fl exacto; el 84 % es la identidad de volumen del Poisson salvo que V_eff ≪ V_pois ahí, cosa no medida (vpois/veff solo en el conjunto con gas). Declararlo o extender las columnas.
- **R-6** Viñeta de status.json desactualizada (dice C-121/C-126; real C-130/C-131).

VEREDICTO: rechaza