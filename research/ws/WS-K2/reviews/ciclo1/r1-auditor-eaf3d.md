# Revisión del cierre de WS-K2, ronda 1: auditor-eaf3d

**Veredicto: aprueba.** Tengo dos observaciones de severidad BAJA. Ninguna es bloqueante.

## Alcance

El diff staged (`git diff --cached`) no contiene código: solo cambia `research/ws/WS-K{1,2,3}/report.md` y `status.json`. En WS-K2, `diff_sha` vale `e3b0c442...b855`, el sha256 de la cadena vacía, que es lo que devuelve `staged_sha()` cuando no hay cambios en las rutas GATED (`src`, `tests`, `scripts/research`, `.claude/...`).

Por eso no aplica nada de lo numérico ni de MPI: conservación con su audit, halos, arrays `mold`, dummies, snapshot de reinicio ni `liq%alpha`. La revisión se limita a comprobar el reporte contra el registro y la maquinaria de cierre.

## Hallazgos

### ALTO
Ninguno.

### MEDIO
Ninguno.

### BAJO

**B1. Paso 5 del reporte (C-048/C-309): el matiz de C-309 queda incompleto.**
- Qué dice el reporte: que C-309 solo «precisa que el máximo ... es el máximo con signo».
- Qué registra C-309 además: el brazo sin Plan K arranca de un estado de Plan K (`diag_k15d/eaf3d_00345310.h5`) y el campo llega a 2.0e6 Pa en otra celda desde el primer paso. Por eso no es un control limpio (C-293/C-294), y «Plan K es NECESARIO» vale solo para la celda (9,1,2).
- Escenario de fallo: un lector toma C-048 como prueba de que el código base no llega al tope en 345.3 s.
- Arreglo: añadir esa frase al paso 5 o a «Incertidumbre». No cambia la conclusión de G2.

**B2. Paso 6 del reporte (C-047): redacción ambigua.**
- La frase «El p_max del audit es max|p| del campo (C-047, refutada)» se puede leer como que lo refutado fue esa igualdad.
- Lo que dice el registro: C-047 afirmaba que el audit no mide el campo, y C-288 la refuta. El audit coincide con max|p| en 395 de 395 snapshots.
- Arreglo: «C-047 (el audit no mide lo mismo que el campo) quedó refutada (C-288): el p_max del audit es max|p| del campo».

## Verificado como correcto

- **El cierre no toca código ni el registro.** `ledger.jsonl` no está staged y el último evento de WS-K2 es C-309.
- **Tabla del reporte.** Las 22 afirmaciones raíz se reparten en 7 soportadas, 7 refutadas y 8 fallidas, y los ids de cada fila coinciden con `current_state()`. Reproduje el comando de la nota de procedencia.
- **Herramientas del registro.** `ledger.py open` da 0 abiertas de 64 y la única predicción hija de WS-K2, C-058, está refutada. `ledger.py check` da OK (309 eventos).
- **Cifras del reporte**, todas coinciden con el registro:
  - C-014: 9.8 %→0 % y 6.7 %→0 %, con el gas en 300 m/s.
  - C-027: 0.5 % > 0.3 % en 340–342 s.
  - C-041: media con K 4.40 > 3.90; n15 llega al tope de 2.00e6 Pa; 2 de 3 trayectorias mejores que la base.
  - C-043: paso truncado de 1.25e-9 s.
  - C-287: 19 de 22 corridas.
- **Cierres de WS-K12 bien citados:** C-279, C-288, C-290 y C-294.
- **Maquinaria de cierre.** `workstream.js` fija `ronda=N` y los `revisor.*` en una sola llamada a `ws-set`, así que la ronda 0 actual de `status.json` no es un defecto. `check` exige para `fallido` la clave `cierre` y los 3 «aprueba» de la ronda vigente. Un `fallido` no abre la compuerta. Aunque el estado pase un momento por `aprobado`, la compuerta sigue cerrada porque `test_quick` es null.
- **Conclusión.** «G2 no cumplida» corresponde a la definición de G2 en `research/QUESTION.md:18`. «G1 no pasó» es coherente con el reporte de WS-K1, aunque ese cierre todavía depende de su propio panel.

## Orden sugerido de corrección

1. B2: es solo redacción.
2. B1: una frase en «Incertidumbre».

Las dos son opcionales y no bloquean el cierre.
