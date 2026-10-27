# Revisión r1, refutador: WS-K8

Revisión de solo lectura. Leí el reporte, C-110, C-133, C-137, C-145, C-150, C-154, C-163 y C-168..C-176, `ledger.py open`, `.claude/rules/acople-pv.md` (secciones de oct y 22-oct), `src/mod_audit.f90:1075-1200`, `src/mod_pressure_3d.f90:600-900` y `src/mod_solver_3d.f90:225-275`. Recalculé con csv.DictReader los `audit.csv` de k8_{cg1000,cg200,mo20,base} y de k7v5_mo20_1k, k7v4_long y k7v5_base.

## 1. Conclusiones, alternativas y dato que las separa

**C1. C-169/H8 queda REFUTADA por la letra (gas libre 0,863).** El veredicto formal es correcto. La alternativa es que el 0,863 no significa que al plan le falte un término, sino que e_libre está en el piso de conversión de la fila. Σ|cc|_libre = 0,374 kg = 4070×Σ|e|_libre, y rem2_libre/Σ|cc|_libre vale 2,0e-4 con CG 200 y 2,1e-4 con CG 1000: es una meseta, no el CG. Este dato ya está y apoya la alternativa (O4).

**C2. «El plan explica el ~80 % del error por celda multifase».** La alternativa es que se trata de una identidad. En el código, rem2 = ee − el − ecc − eart, y ecc = mg_eos + cc − rx. Por la identidad de K7, la EOS y rx se cancelan exactamente: rem2 = comp − fl − el − cc − eart. El inciso por celda comprueba que el complemento sigue al líquido realizado y que la fila del Poisson cierra en masa; **no depende de lo que realice la EOS**. Σ|cc|_multi = 0,058 = 3,6×Σ|e|, así que el 0,197 es un cierre al 5,5 % de términos grandes. El dato que lo separaría es Σ|err_cc| por clase, que no está (O4).

**C3. Con el CG convergido, C-110 sigue sin decidir y no se mueve.** El dato lo confirma también por tramos (0,320/0,314/0,313 con CG 1000 frente a 0,323/0,317/0,316 con CG 20). La alternativa es que las dos trayectorias son casi idénticas, así que esto no prueba nada sobre la deriva larga de C-163 (O7, no bloqueante).

**C4. «El residuo del CG explica el error del gas libre en B1».** Con 20 externas el dato lo apoya: en el paso 1, con el mismo estado inicial, 9,8e-6 frente a 7,5e-7. Pero B1 corre con 5 externas (`max_outer 5`, la config de k8_base), donde Σ|e|_libre = 9,2e-3 y el aporte del CG no está medido (O5).

**C5. «Origen del flujo neto multifase = celdas de salida (95,3 %)» y expectativa (iii) cumplida.** La alternativa es que el neto multifase es un déficit estacionario por paso, independiente del outlet. La igualdad de las sumas en 59 pasos es una coincidencia de la ventana. Los datos están y apoyan la alternativa:
- **m_gas_out por paso.** Media -1,65e-5, sd 6,3e-5; sale en 34 de 59 pasos.
- **e_multi por paso.** Negativo en 59/59, con media -1,45e-5 y sd 3,4e-6.
- **Correlaciones por paso.** corr(e_multi, m_out) = 0,09; corr(flux_multi, -m_out) = 0,23; corr(e_multi, -flux_multi) = 0,10. flux_multi y comp+eos fluctúan con sd 3,2e-5 y se cancelan entre sí.
- **k7v5_mo20_1k, tramos de 200 pasos.** Σe_multi = -3,0e-3..-3,55e-3 (997/999 pasos negativos), mientras Σm_out = -2,19e-3, +2,5e-5, -1,76e-3, +4,3e-4 y -5,33e-3 (cocientes 1,39, -143, 1,91, -7,8 y 0,67). En 200-400 el outlet no aporta y el déficit es igual.

Esto contradice también la frase de C-110 «neto ≈ −la entrada por el outlet», que el reporte reutiliza (O1).

**C6. El neto está en el residuo (no lo dice el reporte).** rem2 neto = -2,169e-5 ± 0,13e-5 kg/paso (59/59 negativos) en cg1000, y -2,167e-5 ± 0,10e-5 en mo20. Eso es e_multi = plan + desfase constante (corr(e, plan) = 0,93), y el CG no lo mueve. El piso neto es, por tanto, un sesgo sistemático de [comp + ρV_eff] o de [fl + ρV_pois + cc + eart], no residuo del CG (O2). Concuerda con C-150: outer_conv_n8 deja ~1e-3 kg/paso sin líquido ni complemento.

**C7. «Almacenamiento artificial despreciable; el piso no está en compliance, D2.4 ni acústico».** La parte de D2.4 no se probó: `alpha_g_comp_min` vale 0 en estas configs (O6).

**C8. alpha_p (Incertidumbre, C-176(4)).** El reporte dice que la parte de store_gas no realizada por la EOS cae en rem2. No es así: cae en err_cc. ws_Fg se corrige con el pp completo (`mod_pressure_3d.f90:853-858`), solo p avanza alpha_p·pp (:898) y la EOS se cancela en rem2 (O3).

## 2. Repeticiones de lo ya registrado
- **Inciso por celda de H8.** Repite el diseño que C-154 objetó en C-145 («peso de dos términos de una descomposición exacta, no contrasta H con su alternativa»). El reporte no dice en qué difiere.
- **«Neto ≈ entrada por el outlet».** Repite C-110 (el reporte lo reconoce), pero k7v5_mo20_1k, que ya existía, lo contradice.
- **Arreglos numéricos.** El cambio es solo de diagnóstico, así que no repite los fracasos de D2.2, D/E/F/G, F2.31 por paso ni n_pc_max.

## 3. Objeciones
1. **O1 (bloqueante).** «Origen = celdas de salida» y la expectativa (iii) son igualdades de sumas en una sola ventana, sin relación por paso. Resolución: reportar la estadística por paso y los tramos de 1k, y corregir C-176(1) y (iii). Para el reparto, pre-registrar flux/comp+eos por tramos en 999 pasos o más con el binario K8.
2. **O2 (bloqueante).** El neto multifase es un desfase constante de rem2 (-2,17e-5 kg/paso) que no depende del CG. Resolución: decirlo y pre-registrar la separación de rem2 en sus dos corchetes, con neto y valor absoluto por clase y por paso.
3. **O3 (bloqueante).** El efecto de alpha_p cae en err_cc, no en rem2. Resolución: corregir el texto y C-176(4).
4. **O4 (bloqueante).** «Explica el 80 %» es el cierre de una identidad que no depende de la EOS (repite C-154). Resolución: reformular y añadir Σ|err_cc| por clase, pre-registrado.
5. **O5 (bloqueante).** «En B1» no está medido: B1 usa 5 externas. Resolución: cambiar a «con 20 externas» o correr k8_base con CG 1000, pre-registrado.
6. **O6 (no bloqueante).** D2.4 está inactivo (alpha_g_comp_min = 0). Resolución: acotar el texto.
7. **O7 (no bloqueante).** «El CG no mueve C-110» vale solo para 59 pasos con trayectorias casi idénticas, no para la deriva larga.

VEREDICTO: rechaza
