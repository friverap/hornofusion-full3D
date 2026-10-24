## Revisión de la evidencia de WS-K4, ronda 1

Todo se recalculó en modo de solo lectura: `energy_gap.py`, `energy_gap.gaps()` con mi propio python, `check_audit.py` sobre los CSV que ya existían, y `ledger.py show/check`. No corrí ni compilé nada.

Las cuatro cifras de los criterios de C-101 se reproducen y los tres incisos se cumplen al pie de la letra. Las cinco objeciones son de redacción y procedencia; ninguna bloquea.

### Tabla

| Afirmación | Reporte | Recalculado | Estado |
|---|---|---|---|
| sum E_relax_liq (bench_relaxcol) | −1.0883e4 J | −1.08833e4 J | ok |
| Hueco del líquido (energy_gap) | −1.1717e4 J | −1.1717e4 J | ok |
| Diferencia relativa (C-101 crit. 1, ≤15 %, mismo signo) | 7.1 % | 7.11 %, ambos negativos | ok |
| Pearson E_relax_liq vs hueco liq (crit. 2, ≥0.9) | 0.99999918 | 0.99999918 (total vs liq+gas: 0.99999920) | ok |
| p_max idéntico, 221 renglones (crit. 3) | bit a bit | 0 renglones distintos; además ninguna columna original difiere | ok |
| energy_balance, ambos bancos | FAIL 1.456, gap −1.067e4 | FAIL 1.456, gap −1.067e4 | ok |
| INFO energy_relax: gap − residuos | −866 J | −8.661e2 J (media −3.94 J/paso) | ok |
| E_relax_gas vs hueco del gas | +1.079e3 / +1.046e3 | +1.0792e3 / +1.0465e3 | ok |
| Remanente liq: suma / mediana / std | −833 / −3.74 / 0.23 | −833.3 / −3.738 / 0.232 | ok |
| std por paso: base0 / aT1 / aT085 | 181 / 0.25 / 105 | 180.6 / 0.250 / 104.5 | ok |
| Sumas liq: aT1 / aT085 | −846 / −13 | −846.4 / −13.1 | ok |
| Mediana liq: aT1 / aT1mo10 / aT085 | −3.8 / −3.6 / (−2.1, en la regla) | −3.80 / −3.6 / −2.13 | ok |
| −58.1 → −3.8 J/paso {C-096} | ok | −58.12 / −3.80 | ok |
| «C-094: −87 J/paso en 280-340 s» | −87 | −86.98 (mediana liq de judge_otp_280, pasos 280001-345527); la cifra está en C-095, no en C-094 | objeción O2 |
| Montaje: restart 341500, 15 ranks, alpha_T 0.7, 220 pasos | ok | config igual a base0 salvo output_dir; run.log con 15 procesos; pasos 341501-341720 | ok |
| Pre-registro antes de medir | C-101 | C-101 a las 01:19:40, archivos del banco 01:21-01:22, C-102 a las 01:23:22 | ok |
| Casos del test unitario | 0 / −60 / −10 | Lectura del código: 0 / −60 / −10 | ok |
| make test-unit / test-quick OK | logs | Logs a las 01:34, después del último cambio en src (01:32:53); PASS test_relax_residual; 4 corridas con err rel 0 | ok (por log; no lo volví a correr) |
| Binario = «este diff» | sí | Binario de las 01:21, mod_audit.f90 de las 01:32:53; no hay sha | objeción O3 |
| Comentario y regla no reflejan C-098/C-103 (Incertidumbre) | «no reflejan» | El diff staged ya los refleja | objeción O1 |

### ¿La comparación es justa?

- Misma base: base0. Mismo reinicio y misma ventana: 341500 a 341720.
- Mismo config, salvo output_dir.
- Mismo número de ranks.
- Todas las columnas originales del audit son idénticas byte a byte. La única diferencia es la instrumentación.

La muestra es corta: un banco de 220 pasos, una sola trayectoria (n15) y alpha_T 0.7. Basta para lo que C-101 pre-registró y el reporte no extrapola más allá; la limitación está declarada en «Incertidumbre».

### Objeciones (ninguna bloquea)

1. **O1.** `research/ws/WS-K4/report.md`, «Incertidumbre», 2.º bullet: dice que el comentario de `src/mod_audit.f90` y `.claude/rules/transporte-energia.md` no reflejan C-098/C-103. Es texto viejo y contradice el diff staged y la sección «Respuesta a la ronda 1». Hay que actualizarlo.
2. **O2.** «C-094: −87 J/paso en 280-340 s». La cifra se reproduce: `campaigns/b1/judge_otp_280` da −86.98, mediana del líquido. Pero está en C-095, no en C-094, y esa corrida llega hasta 345.5 s. Hay que corregir la cita y la ventana, y añadir la procedencia.
3. **O3.** `campaigns/bin/eaf3d_relaxcol_opt` (01:21) es anterior a la versión final de `src/mod_audit.f90` (01:32:53). No hay sha del árbol compilado. Hay que registrarlo o mostrar que la diferencia es solo de comentarios.
4. **O4.** Referencias de línea desplazadas: `src/mod_audit.f90:517` debería ser la 522 (acc = 0), y `:730` debería ser la 736.
5. **O5.** En `research/ws/WS-K4/status.json`, test_quick = null: falta el `ws-set` sobre el diff final. Además, C-103 sigue en estado «propuesta».

### Juicio contra el criterio pre-registrado (C-101)

- (1) 7.11 % ≤ 15 %, signo negativo registrado: **cumple**.
- (2) |r| = 0.99999918 ≥ 0.9: **cumple**.
- (3) energy_balance da el mismo veredicto y p_max es idéntico, de hecho todas las columnas lo son: **cumple**.

El veredicto «soportada» de C-102 coincide con la letra del criterio, sin reinterpretación ni enmienda.

VEREDICTO: aprueba