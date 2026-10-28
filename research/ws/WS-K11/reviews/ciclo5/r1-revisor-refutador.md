## Revisión del refutador — WS-K11, ronda 1 (ciclo tras e5f45e7; C-277 y C-278 nuevos)

Revisión ciega y de solo lectura: python solo para leer audit.csv, run.log y HDF5, sin corridas.

### 1. Conclusiones, hipótesis alternativas y dato que las separa

**C1. Encender f28 sobre un estado escrito sin ella es NECESARIO para la firma (0.25 ms, 60 ms, estados probados).**
- *Alternativa:* no cuenta la historia sino f28 encendida × una propiedad X del estado del linaje fh.
- *Qué la separaría:* medir X o el sentido inverso (apagar f28 sobre un estado jb). Ninguno está corrido.
- *Qué hay en los datos:*
  - Lo he comprobado en todas las corridas de `campaigns/b1` con la columna `m_gas_cells_nolink`: solo tienen nolink > 0 k10b_dt025, F, tgfix, G, B, I, J (todas con cambio) y k7v4_long (también con cambio en 280 s). Ninguna corrida con f28 apagada pasa de 60 ms con esa columna (solo A, H, M, N, O). La implicación «nolink ⇒ cambio» se sostiene, con el alcance que declara el reporte.
  - Hay una X candidata legible en los snapshots (objeción R2): las celdas de poro parcialmente llenas, con hueco liq_cap − α_l en [1e-6, 1e-3).
    - Estados escritos sin f28: fh 280/285/290/295/299.999 s → 5/5/3/1/0; A 280.06 s → 6; e2 280/299.999 s → 2/2.
    - Estados escritos con f28: jb 280/285/295/299.999 s → 127/132/37/34; otp 290/300 s → 34/23.
    - Tras 60 ms con f28: final de F 149, tgfix 142, B 45.
    - Separa el linaje, pero no a P (fh 300 s tiene 0).
- *Sobrellenado de poros:* lo he repetido (R3). El mínimo del hueco es ≥ −1e-15 en todos los estados, así que queda descartado.

**C2. NO suficiente (P, fh 300 s).**
- *Alternativa 1: artefacto del snapshot final.* Descartada: el atributo `restart/dt` vale 1e-3, el tiempo es 300.0 y el paso 299999 sigue la cadencia normal (295000 → 295.001 s). No es un paso truncado.
- *Alternativa 2: estado con poca chatarra sumergida.* Es C-278 y he verificado sus cifras: 212/212/191/189/155 en los estados que responden y 43 en P; jb 217/140/130 y otp 189/52.
- *Discriminadores existentes, sin correr:* e2 295 s (126) y 299.999 s (55), fhe1 299.999 s (101).

**C3. El cierre diagnostica el pico de k10b_dt025: el disparador es f28.**
- El par A/F es una intervención limpia de una sola clave: f28 es necesaria.
- *Alternativa para el contacto con U_GAS_MAX en el paso 3:* el transitorio de acotar dt con f28 encendida, como en L, lo amplifica. Lo que dicen los datos (objeción R1):

  | Brazo | Cambio de f28 | Salto de dt | u_gas_max |
  |---|---|---|---|
  | G | sí | no | 216 m/s como máximo en los pasos 2-10; 300 m/s solo en P0+23 y P0+27 |
  | L | no | sí | 300 m/s en P0+2 y P0+3 |
  | F / k10b_dt025 | sí | sí | 300 m/s en P0+3 |

  A sigue plano (14.5 kPa), así que G frente a F es casi el contraste del salto de dt. La frase «G descarta el salto de dt» vale para el criterio de pico, no para la centinela que da título al WS.

**C4. La firma de k7v4_long es otro fenómeno; los datos no apoyan (ii).**
- Verificado: 146 pasos nolink, 144 de ellos con exactamente 360 celdas, el primero en 284669; en los 60 pasos desde ahí, 59/45/30 y p_max 152.7 kPa; 96 filas de nivel centinela, 86 con nolink, la primera en 284340.
- Los avisos de CG acumulados llegan a 27001 casos (último aviso del run.log).
- *Alternativa:* el bloque fijo de 360 celdas que se enciende y se apaga sugiere una clasificación global (enlaces del Poisson no convergido) más que física local. Eso refuerza la hipótesis de trabajo del reporte y no la contradice. Lo separaría la PROBE-P ya propuesta.

**C5. El régimen alto de f28 no explica las paradas de B1, por conteo.**
- Es una trayectoria por linaje y el reporte lo declara.
- La alternativa (la familia de 284 s es física del estado) está recogida, con datos de e2 (28 filas sin f28).
- No encuentro un dato nuevo que la contradiga.

### 2. Repeticiones de fracasos registrados

- No hay cambio de código. No repite D2.2 (limitador en el Poisson), ni las reglas locales D/E/F/G, ni n_pc_max, ni F2.31 por paso.
- La única prueba futura propuesta que repite un método refutado (P con comp_carry = 0, al estilo de H12) ya está marcada con prior bajo.
- M20-2 no se repite. Se cuestiona su base (pico de reinicio) sin tocar la regla, de acuerdo con la regla de vigencia de los fracasos (C-089).
- La recomendación «f28 establecida ≥ 5 s» no limpia los bancos de 0.25 ms (L y s290). El reporte lo declara, así que no traslada el problema sin decirlo.

### 3. Objeciones (ninguna bloqueante)

- **R1:** matizar «G descarta el salto de dt». Datos de G, L y F arriba. Resolución: corregir la redacción, o réplicas de G y F a 14/15 ranks.
- **R2:** la X «no medida» tiene una candidata legible en los snapshots (banda de poros parcialmente llenos). Incluirla con su alcance: separa el linaje, no a P, y es colineal con el linaje. Prueba causal: copia manipulada pre-registrada.
- **R3:** sustituir «ese cálculo es suyo» por el comando y la cifra (hueco mínimo ≥ −1e-15).
- **R4:** «refuerza que lo pone la historia» → «sistemático dentro de esas dos trayectorias». Lo resolverían los reinicios desde e2 y fhe1.

Comando de R2 y R3 (solo lectura): con h5py, para cada snapshot, `room = max(1 - a_s - pore_floor(a_s), 0) - a_l` en celdas con `a_s >= 0.01` (`pore_floor` = 0.015·clip((a_s − 0.005)/0.005, 0, 1)); contar `room < 0` y `1e-6 <= room < 1e-3`.

El titular está acotado (60 ms, 0.25 ms, estados probados, una trayectoria, un sentido del cambio, mecanismo abierto) y los números en que se apoya resisten. Ninguna alternativa encontrada lo vuelve falso dentro de ese alcance. Las cuatro objeciones son precisiones que conviene incorporar.

VEREDICTO: aprueba