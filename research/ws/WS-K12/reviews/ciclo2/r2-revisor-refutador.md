## Revisión del refutador: WS-K12, ciclo 2, ronda 2

**En resumen:** las seis objeciones de la ronda 1 quedan resueltas y lo comprobé en los datos. Las conclusiones aguantan las alternativas que formulé. Solo queda R3, que no bloquea.

Revisión de solo lectura: no hubo builds, `mpirun` ni corridas. Usé python únicamente para leer `audit.csv`, HDF5, `*.out` y el registro. La simulación del cierre la ejecuté en memoria y sin `--run`.

### 1. Estado de mis objeciones de la ronda 1

| Id | Estado | Qué comprobé |
|---|---|---|
| R1 | Resuelta | B3, los datos de C-044, el grupo C, C1 e Incertidumbre citan ya el contraste C-043/C-046. Ya no dicen «un caso» ni «el contraste directo no está corrido», y se retiró la lectura de C-076 sobre diag_p342b. Recalculé el barrido de pasos truncados: 22 corridas, con subida de p_max en 19. La validez de C-087 da 220/220. |
| R2 | Resuelta | P2 sobre C-049, más una frase en C3 y C4. Releí diag_k15_k_off: config con `restart_file` = diag_k15d/eaf3d_00345310.h5 y `pc_alpha_implicit = false`. El snapshot de partida tiene max\|p\| = 1.551e5. En 345311, max p = 4.560e5 y min p = −2.000e6 en (1,56,8), y el audit da 2.0e6. En 345318, max p = 6.072e5 y max\|p\| = 1.851e6. Coincide con el texto. |
| R3 | Se mantiene, no bloquea | Ver la objeción R3. El texto ya recoge el dato parcial de z_tip y la exclusión de la alternativa MPI (rejilla 1x5x3; j 19-20 cae dentro del bloque 12-23). |
| R4 | Resuelta | Releí c077/c080/c083.out. La cifra correcta para n15 es la del redactor: 18/22 después de 343291, con 4 eventos sin precursor (343808, 344026, 344036 y 345052). Mi 14/18 era erróneo. n14 da 12 sin precursor y luego 19/19; el estado girado da 3 sin precursor y luego 17/18. |
| R5 | Resuelta | En `src/main_3d.f90:146-151` está el bloque Ejecutable/Compilador. `gas_mass_on` está en :884 y :934 hoy, y en :812 y :862 en 2b65e11. `git diff --stat 79dc27b 2b65e11 -- src` da main_3d +9 y mod_audit +11/−2. |
| R6 | Resuelta | F1 queda como «fallida (no concluyente)», porque C-238 → C-239 prueba el inciso (a). La sección «Fuera de este cierre» ya no lista como pendiente lo que el diff staged implementa: `validate` en :114-122 y `open` en :207-209. Las líneas coinciden. |

### 2. Conclusiones, alternativas y dato que las separa

- **B3 (C-044, «contamina reinicios»).**
  - Alternativa: k15b diverge porque reinicia desde otra corrida, no por el paso truncado.
  - Qué las separa: k15a y k15c reproducen la original en 5150 y 5151 filas, y solo difieren en la fila truncada. Además, k15d da 180/180 filas idénticas frente a 0/180 de k15b.
  - Conclusión: la alternativa queda excluida con los datos existentes. El mecanismo concreto (p modificado o dt_old en el snapshot) no se afirma, y está bien que no se afirme.
- **C1 (C-015).**
  - Alternativa: el pico es el transitorio genérico de cualquier reinicio.
  - Qué las separa: un reinicio desde un snapshot de paso completo con el binario e5d331e (diag_p417) da 220/220 filas idénticas a la original. El reinicio limpio no genera pico.
  - Conclusión: queda como lectura sin valor de veredicto, que es lo correcto.
- **P2 (C-049).**
  - Alternativa: el tope en el primer paso del brazo sin Plan K es el transitorio de cambiar la clave sobre un estado de Plan K, el mismo patrón que C-238/C-239 aisló en WS-K11.
  - Conclusión: P2 ya dice que el brazo «no es un control limpio» y restringe la conclusión a la celda (9,1,2). No hace falta más.
- **A2 (C-074).**
  - Alternativa: dos regímenes, con picos tempranos de fuente de líquido y picos tardíos con velocidad fantasma.
  - Conclusión: el texto ya lo recoge como corte post hoc y aclara que el cierre refutado no niega el papel de la velocidad fantasma.
- **A4 (C-082).** Ver R3.

### 3. Repeticiones de fracasos registrados

No hay. WS-K12 no propone ningún cambio numérico. El único cambio de herramienta (`sin_decidir`) lo decidió el usuario y no reetiqueta veredictos.

### 4. Otras comprobaciones

- **Simulación en memoria del reporte:** 31 eventos aceptados (C-279 a C-309) y 0 abiertas de 64.
- **P1 y P2:** cambian el `current_state` de C-093 y C-049 a «propuesta», igual que ya hace C-094. No reabren ninguna raíz.
- **P1:** cifras reproducidas. d26k_n14 da 2.001e5 → 1.240e5 sin la fila truncada, y e1_n14 1.474e5 → 1.455e5. En n15 el máximo no está en la fila final.

### Objeciones

**R3 (no bloquea).** A4 deja confundidos el material y elec_z_tip. Se resuelve con una corrida que gire el material sin permutar z_tip, o que permute solo z_tip, con el criterio de C-083. Ya está listada como pendiente.

VEREDICTO: aprueba