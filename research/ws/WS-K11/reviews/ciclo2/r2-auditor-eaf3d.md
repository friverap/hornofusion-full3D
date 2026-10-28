## Revisión WS-K11, ronda 1 (auditor-eaf3d)

**Veredicto: rechaza.** Hay 1 hallazgo MEDIO sin resolver (M1). Es un error numérico en el registro oficial y se arregla con un evento.

**Alcance.** El diff staged no toca `src/` ni `tests/` y es un diagnóstico. Contiene:
- la regla `.claude/rules/transporte-energia.md`;
- los eventos C-255..C-258 del registro;
- dos scripts de solo lectura (`duracion.py`, `pares.py`);
- `status.json` y el reporte.

No hay rutas de masa ni energía nuevas, halos, dummies ni estado de reinicio que auditar. Ejecuté los scripts del WS y `check_audit.py` sobre `audit.csv` ya existentes; ninguno escribe archivos.

### Hallazgos

**MEDIO**

- **M1. `research/ledger.jsonl`, evento C-256.**
  - Defecto: el enunciado dice que los brazos con cambio de f28 (G, I, J, F, B) tienen «p_max de 0.9-2 MPa».
  - Lo que dan los datos (máximo de p_max en la ventana): B 365 kPa (290020), F 592 kPa (280161), G 895 kPa, I y J 2000 kPa. El rango correcto es 0.37-2 MPa, como ya dice el reporte (líneas 11 y 364).
  - Ningún evento corrige C-256: no hay `ref` C-256, y C-258 solo cambia etiquetas.
  - Escenario de fallo: `/estado` o `ledger.py show C-256` (los estados al usuario salen SOLO del registro) da un rango que excluye 2 de los 5 brazos y contradice el reporte cerrado.
  - Arreglo: `ledger.py add --ref C-256` con la cifra corregida. El veredicto REFUTADA no cambia.

**BAJO**

- **B1. `.claude/rules/transporte-energia.md:345`.**
  - Defecto: la cabecera dice «WS-K11 C-222..C-249», pero el párrafo cita hasta C-257.
  - Arreglo: cambiarla a «C-222..C-257».
- **B2. Misma regla, párrafo nuevo.**
  - Defecto: dice que el efecto de la presión total en el arranque «es de 1e-8». `pares.py` da ≤7.9e-9 en u_gas_max y ≤1.5e-9 en p_max, pero **2.6e-7 en m_gas** (pasos 0-10). El reporte lo dice bien.
  - Arreglo: redactar «≤1e-8 en u_gas_max y p_max, ~3e-7 en m_gas».
- **B3 (harness, PLAUSIBLE, no afecta a este diff).**
  - Defecto: `status.json` conserva los veredictos del ciclo 2 con `ronda: 1`, el mismo número que la ronda vigente. `gate_errors` (`scripts/research/ledger.py:274-277`) solo compara el número de ronda, así que una aprobación vieja contaría si no se sobrescribe.
  - Por qué no afecta aquí: el diff de src/ y tests/ está vacío (`diff_sha` = sha256 de la cadena vacía) y el hook no exige la compuerta.
  - Arreglo, fuera de este WS: reiniciar los revisores al abrir un ciclo, o registrar el ciclo en el veredicto.

### Verificado como correcto (no re-auditar)

**H19-H21 (`h19.py`).** Da H19 SOPORTADA, H20 REFUTADA y H21 SOPORTADA. Coinciden todas las celdas de la tabla del paso 12: u/p en los pasos 2-10, máximo de la ventana y su paso, cuartos ≥100 kPa, nolink y cero `[CG] AVISO`.

**`duracion.py`.**

| brazo | pasos u ≥ 200 / p ≥ 300 kPa | último paso |
|---|---|---|
| G | 9 / 7 | 27 |
| I | 99 / 55 | 232 |
| J | 187 / 74 | 226 |
| L | 3 / 0 | 4 (y máx. 113.3 m/s desde P0+5) |
| H, K | 0 / 0 | — |

**`pares.py`.**
- E frente a C, pasos 0-10: 7.9e-9 en u_gas_max, 1.5e-9 en p_max, 2.6e-7 en m_gas; 12 % de u_gas_max en la ventana.
- F frente a `k10b_dt025`, pasos 0-10: 1.1e-9, 3.5e-10 y 2.5e-7.
- Nolink: 105/105 en F y `k10b_dt025`; 0/0 en C y E.

**Código de los dos scripts nuevos.** La lógica es correcta para los pares usados: pasos comunes contiguos desde P0 y se excluye el paso 1. No hay división por cero con estos datos.

**Configs de los brazos nuevos.** Cada brazo difiere de su banco base solo en lo pre-registrado (C-252..C-254):
- G = A + f28 + restart 280236 + t_final;
- H = A + presión total;
- I y J = F con otro restart y otro t_final;
- K y L = C con otro restart y otro t_final.

Los seis corrieron con 15 ranks.

**Snapshots.** Los 9 snapshots usados tienen los mismos 17 datasets en `/restart`, así que no falta estado persistente según el escritor. El dt del snapshot es 1e-3 en todos salvo A 280236 (2.5e-4); por eso G no acota dt, como afirma el reporte.

**`check_audit` (FAIL por brazo).**
- G: sentinel_gas, regime_p y regime_gas.
- I y J: los mismos más sentinel_p.
- L: sentinel_gas y regime_gas.
- H y K: ninguno.

**Otras cifras del reporte.**
- Medias de p_max y |Δp| por cuartos de B, `k10b_dt025`/F, C/E y A.
- Asentamiento a 1 ms: 280031/280013 en `k10b_mo20` y 280024/280017 en `judge_otp_280`.
- Filas de nivel centinela 15/1/26.
- Decaimiento con 0.5 ms: 8, 1, 2 y 0.
- Serie de L y alternancia ~160/110 m/s, 44/22 kPa de `judge_jb_275` en 295 s.

**Citas de `src/`.**
- `mod_pressure_3d.f90:1001-1010` y `2000-2012`: la presión total solo actúa en aberturas del techo con electrodo y alpha_g ≥ cutoff; con u_in ≤ 0 el objetivo es p0.
- `mod_audit.f90:1318-1335`: clase nolink.
- `mod_config_3d.f90:110`: comentario de adopción de f28.
- `mod_multiphase.f90:473-477`, `mod_pressure_3d.f90:598-601` y `mod_constants.f90:594-599`.

### Orden sugerido de corrección (uno por uno)

1. M1: evento de corrección de C-256 en el registro.
2. B2: cifra del efecto de la presión total en la regla.
3. B1: rango de claims en la cabecera de la regla.
4. B3: en el harness, en un cambio aparte, fuera de WS-K11.
