## WS-K12, revisión del refutador (ciclo 2, ronda 1)

Rechazo por una objeción bloqueante (R1, en A6). R2 a R5 no bloquean.

La revisión es ciega y de solo lectura. No lancé corridas ni make. Usé python solo para leer audit.csv, HDF5, los npz de phantom/ y el registro. El script auxiliar está en el scratchpad (`matched.py`).

### 1. Conclusiones, mejor alternativa y dato que las separa

| Cierre | Mejor alternativa | Dato que la separa | ¿Está en los datos? |
|---|---|---|---|
| **A2: C-074 refutada; «su refuta_si no se cumplió» (61–81 % frente a 9.2–9.7 %)** | El «precursor» es una tendencia común: la u_ph local crece de forma monótona junto con los picos (ya lo dice C-079), y el control no está emparejado por ubicación | El control evaluado en la celda caliente, por tramos de tiempo | **Sí.** `phantom_scan.py:116-120` evalúa los quietos en la celda de su PROPIO max\|p\|. Con `phantom/*.npz`, el control emparejado en la celda caliente da 11.4 % (n14), 10.5 % (n15) y 11.5 % (rot). Por tramos, en n14: antes de 343.3 s, 0/12 eventos con precursor frente a 0.4 % de los quietos; después, 19/19 frente a 30.6 %. Las cifras de n15 (0.0 / 31.4 %) y rot (1.4 / 29.7 %) son parecidas. El refuta_si no se cumple en conjunto y «refutada» se mantiene, pero el contraste citado exagera la asociación (R2) |
| **A4: C-082 soportada; «no sigue a la costura ni a la descomposición MPI»** | (a) Es un artefacto de rank; (b) la costura o la frontera MPI CREARON el estado anómalo en 0–340 s | (a) ¿Dónde caen las fronteras de rank? (b) Correr desde un tiempo temprano con los electrodos lejos de la costura | (a) **Sí, y la descarta.** `factorize_3d` da, con 15 ranks, 1×5×3 (bloques de 12 en j): la costura j=59\|0 es frontera y j=19/20 queda dentro del bloque 12–23. Además `cell_type` es invariante ante cualquier giro en j (0 diferencias). (b) **No.** A 340 s, en α_s, k=1, i=8–9: 0.10–0.62 bajo el electrodo 1, frente a 0.25–0.92 y 0.34–0.96 bajo el 2 y el 3. La costura j=0 es frontera de rank en todas las rejillas usadas (12 ranks: 2×3×2; 14: 1×2×7; 15: 1×5×3) (R3) |
| **A6: C-089 fallida (no concluyente); «el modo de fallo cambió a centinela de gas, energía o masa»** | d26k y e1 MEJORAN frente a la base en presión y en centinela de gas. Solo empeoran la energía (340 s, sin descontar la sub-relajación) y la reescritura EOS en 280 s, en checks que la base ya falla | Cada check frente a la base | **Sí.** C-092: la base da FAIL en sentinel_p, sentinel_gas, energy_balance (1.717) y regime_*. C-093: pasos a 300 m/s 23/77 (d26k) y 2/1 (e1) frente a 201/131 de la base; mi recuento en audit.csv da 22/71, 2/1 y 182/119. C-105: la base truncada también falla mass_gas (0.552) y la energía de e1 pasa descontado el residuo (R1) |
| C1/B3: el pico de 805 kPa de C-015 es contaminación del reinicio | Lo causa otro binario, otra config u otros ranks en diag_p342b | Config y ranks frente a judge_otp_280 | **Sí, y la descarta.** La config.dat de diag_p342b solo difiere de judge_otp_280 en output_dir, restart, t_final y output_freq. Los dos corrieron con 12 ranks (2×3×2) el mismo día. diag_p342a 342450: dt 1.186e-9, p_max 9.52e4; diag_p342b 342451: 8.05e5, luego 1.64e5 y 8.48e4; judge_otp_280 en 342450–342452: 2.4–3.2e4 |
| B4: C-047 refutada | El audit mide otro iterado | max\|p\| del snapshot frente al audit | Ya lo verifiqué en la ronda anterior (395/395); sin cambios |
| Grupo E (`sin_decidir`) | C-121 podría estar en la zona de refutación (≥ 0.7) | Σ\|e\| en 0 < α_g < 1e-2 | **No existe.** El texto declara que el valor no está determinado (≥ 0.565) y cita la letra de C-124. Aceptable |
| E8: C-212 sin decidir | El banco no podía decidir y además no es limpio | IC90 y centinela | **Sí**, en C-216, C-219 y C-222, pero E8 no los cita (R5) |
| F1/F2 | — | — | Correcto. La lista de pendientes omite P_HYDRO_CAP de I y J (R4) |

### 2. Repeticiones de fracasos registrados

No hay cambio numérico. No se repite el limitador en el Poisson (D2.2 / Plan K), ni las reglas locales D/E/F/G, ni n_pc_max. El estado `sin_decidir` no tiene precedente refutado: no aparece en el registro ni en `.claude/rules/acople-pv.md`.

El riesgo de esta clase de WS es otro: dejar en el registro permanente una lectura que dé por muerta una opción vieja. Es lo que protege la regla de vigencia (`acople-pv.md:266-273`, C-089), y es justo el problema de A6 (R1).

### 3. Objeciones

1. **R1 (bloqueante, A6).** «sentinel_gas FAIL en las 4 corridas» y «el modo de fallo cambió a centinela de gas» presentan como fallo propio de d26k/e1 algo que la base falla peor: 201/131 pasos a 300 m/s frente a 23/77 y 2/1 (C-093); en mi recuento, 182/119 frente a 22/71 y 2/1. Frente a la base, solo empeoran la energía en 340 s (2.32/2.31 y 1.79/1.84 frente a 1.717, sin descontar la sub-relajación, que en 280 s explica todo el fallo de energía de e1 según C-105 e) y la EOS del gas en 280 s (0.615 frente a 0.552, las dos en FAIL).
   - **Resolución (datos ya registrados):** «refutadas por la letra de (d), que exige PASS en checks que la base ya falla; frente a la base mejoran picos y centinela de gas y empeoran la energía (y, para e1 en 280 s, la reescritura EOS)», con esas cifras.
2. **R2 (no bloqueante, A2).** El control 9.2–9.7 % no está emparejado por ubicación y está confundido por el tiempo. El emparejado y estratificado da: n14 0/12 frente a 0.4 % antes de 343.3 s y 19/19 frente a 30.6 % después; n15 0.0 / 31.4 %; rot 1.4 / 29.7 %.
   - **Resolución:** añadir esas cifras (lectura de `campaigns/b1/dense_*/phantom/*.npz`) o quitar el 9.2–9.7 % como argumento.
3. **R3 (no bloqueante, A4).** El giro decide qué FIJA la ubicación dado el estado de 340 s, no qué CREÓ ese estado. La costura j=0 es frontera de rank en todas las rejillas usadas y el electrodo 1 siempre está en ella.
   - **Resolución:** una frase en A4. El experimento que lo separa (sin corrida hoy) es correr desde un tiempo temprano con los electrodos desplazados de la costura o con npth=1.
4. **R4 (no bloqueante).** Añadir P_HYDRO_CAP de I y J (C-277 (4)) a «Lo que deja de verse en open» y a F1 o F2. Con `open` en 0 de 64, es el único rastro que queda.
5. **R5 (no bloqueante, E8).** Citar C-216 y C-219 (IC90 del cociente que cruza las dos bandas; trayectorias distintas entre dt) y C-222 (k10b_dt025 dispara la centinela; el cociente va de 0.812 a 0.896 según los pasos descartados).

### Verificado por mí (solo lectura)

- Rejilla MPI (`src/mod_mpi_topology.f90`, `factorize_3d`, con nr=30, nθ=60, nz=42): 15 ranks → 1×5×3; 14 → 1×2×7; 12 → 2×3×2.
- `mesh/cell_type` de `dense_340_n15/eaf3d_00340000.h5`: 0 diferencias ante giros de 1, 10, 20, 30 y 40 celdas.
- Estado de 340 s por sector de electrodo (α_s, α_g en k=1, i=8–9).
- Control emparejado y estratificado con `phantom/*.npz` de dense_340_n14, dense_340_n15 y dense_rot_n15.
- `c077.out`: los 12 primeros eventos no tienen precursor y la u_ph local va de 1.4 a 8.7.
- Pasos con u_gas_max ≥ 300 en judge_{d26k,e1}_n{14,15} y base_340_n{14,15}.
- diag_p342a/b frente a judge_otp_280: config, ranks y filas de audit en 342449–342453.
- Diff staged de `scripts/research/ledger.py`: validate de `sin_decidir` (ref existente, no veredicto ni enmienda, no cerrada) y `open`, que lista las cerradas sin decidir.

VEREDICTO: rechaza