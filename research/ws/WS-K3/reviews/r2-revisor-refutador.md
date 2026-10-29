## Revisión del refutador, ronda 2 (WS-K3)

### 1. Conclusiones, alternativas y el dato que las separa

**C1. G3 (verificación del Plan K) quedó sin objeto porque el Plan K no se adoptó y `src/` no lo contiene.**
- *Alternativa:* que parte del Plan K haya llegado a `src/` y, entonces, sí haya algo que verificar.
- *Dato que las separa:* las claves del diseño en `docs/PLAN_K_limitador_en_poisson.md` §3 (`pc_alpha_implicit` y `pc_ai_*`).
- *Qué dicen los datos:* `grep -rn 'pc_alpha_implicit|pc_ai_' src` no devuelve nada. C-065 dice que el código se archivó en `research/ws/WS-K1/plan_k_v2.patch` y que `src` volvió a 1bc9832. La alternativa queda descartada.

**C2. Las 15 afirmaciones raíz de diagnóstico están cerradas: 7 refutadas, 4 fallidas, 3 soportadas y 1 sin decidir.**
- *Alternativa:* que alguna siga abierta a través de una hija.
- *Dato:* volví a correr el conteo citado y da `15 {'refutada': 7, 'fallida': 4, 'soportada': 3, 'sin_decidir': 1}`. `ledger.py open` da 0 abiertas de 64 y `ledger.py check` da OK (309 eventos).

**C3 (punto 4). d26k y e1 quedan refutadas en B1 con el código actual.**
- *Alternativa:* que la refutación sea solo un artefacto de la letra del inciso (d), porque la base también falla esos checks.
- *Cómo queda en el reporte:* tal como se pidió en la ronda 1, ahora dice que la base falla los dos checks y que, frente a ella, d26k y e1 mejoran los picos y la centinela de gas pero empeoran la energía (C-094 y C-284). Además, sentinel_gas falla en las 4 corridas, así que no basta con el residuo de la sub-relajación. Esto coincide con C-093 y C-284.

### 2. Repeticiones de fracasos ya registrados
Este cierre no propone ningún cambio numérico, así que no repite ningún fracaso. La relación entre el Plan K y D2.2 (`pc_limiter_faces`) está declarada en Incertidumbre: D2.2 no se puede evaluar con el código actual (C-091), y E1 no tiene corrida en 320-325 s (C-284).

### 3. Objeciones
- **O1, resuelta.** El inciso (d) de C-093 aparece completo, con sentinel_gas y energy_balance.
- **O2, resuelta.** El juez de la combinación bed_flood está declarado como compromiso pendiente. Comprobado: `judge_combo*` no existe y `bench_combo` sí.
- **O3, resuelta, con una errata que no bloquea.** El reporte dice que hay «dos [corridas de E1] del 20-oct en 275–300 s», pero en `campaigns/b1` hay seis:
  - judge_fhe1_275
  - scrfh_e1
  - scr2908_E1
  - scr2908_E12
  - scr291_E1
  - scr291_E1b

  Las cuatro `scr29*` van de 290800 a 290999. Ninguna cae en 320-325 s ni es posterior a C-089, así que la conclusión no cambia. Corregirla es opcional.
- **O4, resuelta.** El cierre queda acotado a «G3 (verificación del Plan K)». Comprobado: 7 commits de src en 1bc9832..HEAD, y WS-K4 a WS-K13 en aprobado.

No encontré ninguna explicación alternativa nueva que invalide el cierre. Lo que el reporte deja pendiente está declarado como tal en Incertidumbre.

VEREDICTO: aprueba