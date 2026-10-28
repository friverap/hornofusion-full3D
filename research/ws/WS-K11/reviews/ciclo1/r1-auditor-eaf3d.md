## Revisión WS-K11, ronda 1 (auditor-eaf3d)

**Veredicto: RECHAZA.** Hay dos hallazgos MEDIO sin resolver.

### Qué se revisó
El diff staged no toca código: solo `research/ws/WS-K11/report.md` y `status.json`. `diff_sha` es el sha256 de la cadena vacía, coherente con `numerico=false`. Revisé las afirmaciones del reporte contra los datos y el código, con lectura únicamente: scripts ya commiteados, `check_audit.py`, `audit.csv`, snapshots HDF5 y fuente.

### Hallazgos

**MEDIO-1. La causa "cambio de claves" no está aislada.**
- **Qué compara la prueba.** H13 solo separa el snapshot de 280 s del de 290 s.
- **Quién escribió el de 280 s.** Lo escribió judge_fh_275 (20-oct, 13:24-16:38) con las claves apagadas. Por la cronología de commits, también fue con código anterior a varios cambios:
  - `3c4bf52`: histéresis de la película, que entra en `ws_liq_cont_prev`, estado del snapshot. Su commit dice que arregla un **gas a 300 m/s en 282.73 s**, en esta misma ventana.
  - `f57e950` (B20-1), `eccca75`, `28cccdf` y `36f7d17`.
- **Dónde se afirma la causa.** En el titular, en C-227 y en la regla ya commiteada (`.claude/rules/transporte-energia.md:359-366`).
- **Escenario de fallo.** Alguien reinicia desde 280 s con las claves apagadas para que coincidan, y el transitorio puede persistir.
- **Estado: PLAUSIBLE.** La alternativa no está probada, pero el diseño no la descarta.
- **Arreglo.** Correr un control de 10-20 pasos con dt 0.25 ms desde 280 s y las dos claves en `false`. Si no se corre, reformular como "cambio de modelo al reiniciar, sin aislar".

**MEDIO-2. La ventana 2-10 oculta picos que acotan la conclusión.**
- **(a) Picos de k10b_dt025 fuera del transitorio.**
  - El FAIL de `regime_p` (592 kPa) está en el **paso 280161**, no en el transitorio, y el reporte lo cuenta entre sus síntomas.
  - Hay 282.8 m/s en el 280011 y 252.8 m/s en el 280041. No es un transitorio de "2-3 pasos" como dice la regla.
- **(b) Picos de k11_dt025_s290, sin cambio de claves.**
  - Llega a **450 kPa en el paso 290093** y a 344 kPa en el 290074; `check_audit` marca regime_p 4.5e5 frente a un límite de 5e5.
  - Desde el mismo snapshot, 0.5 ms y 1 ms no pasan de 71 kPa.
  - Hay entonces excursiones de presión propias de dt 0.25 ms que no se diagnostican. Este banco se usa como referencia limpia en H14/C-232.
- **Arreglo.**
  - Poner en la tabla el máximo de toda la ventana, con su paso.
  - Quitar `regime_p` y "2-3 pasos" de lo que se atribuye al transitorio.
  - Matizar C-227 ("no un efecto de dt por sí solo") y la regla.
  - Abrir en el ledger el diagnóstico de esos picos.

**BAJO-1. La incertidumbre del binario ya se puede cerrar con datos existentes.** `k10_base` reproduce `judge_otp_280` en 280001-280005, y `k11_base_s290` lo reproduce en 290001-290005. Las columnas `u_gas_max`, `p_max` y `m_gas` coinciden hasta ~1e-12 relativo. El binario que lee no influye; lo que queda abierto es el código que escribió (MEDIO-1).

**BAJO-2.** El `run.log` de `k11_base_s290` tiene 1 `[CG] AVISO` que la lectura C-233 no menciona.

**BAJO-3.** El archivo `judge_otp_280/eaf3d_00280000.h5` tiene fecha del 22-oct, porque lo reescribió judge_otp_280. `/restart` y los campos primarios son idénticos a los de `judge_fh_275/eaf3d_00280000.h5`; solo difieren 8 campos diagnósticos. Precisar la redacción.

### Verificado como correcto
- H12 se refutó con una prueba efectiva, no nula:
  - `Tg_end` se lee en el reinicio (`mod_restart.f90:165-170`) y lo usa `mod_multiphase.f90:473`.
  - La copia tgfix tiene salto 0 y el banco la cargó (`run.log:28`).
  - `m_gas` difiere en 2e-3 kg en el paso 280001.
- Las cifras del reporte se reproducen con `medir_centinela.py`: 300.0 m/s y 461 kPa; 120/235, 5/235 y 0/58; 71.6 m/s y 79 kPa; 124 m/s y 55 kPa.
- `check_audit`:
  - k10b_dt025: FAIL en `sentinel_gas`, `regime_p` y `regime_gas`.
  - Bancos s290: sin FAIL; `mass_gas_row_volume`, `mass_gas_decomp` y `mass_gas_eos_end` dan PASS.
  - k11_base_s290: solo falla `energy_balance` (106.9 m/s, 27 kPa).
- `comp_carry` es 0 en el snapshot de 280 s y vale 1.35e-7 en el de 290 s.
- Tasas EOS final: 2.922, 2.882 y 2.865 kg/s. La columna es Σ|deos|+|peos| (`mod_audit.f90:1262`).
- El diff de configs entre fh_275 y otp_280 solo añade las dos claves.
- Los dos snapshots tienen la misma estructura de datasets, y el aviso de acotar dt aparece igual en ambos bancos.

### Orden sugerido de corrección
1. MEDIO-2: tabla con la ventana completa y atribución de `regime_p` corregida. Es solo redacción y ledger.
2. MEDIO-1: banco de control desde 280 s con las claves apagadas, o reformular titular, C-227 y regla.
3. BAJO-1, BAJO-2 y BAJO-3.
