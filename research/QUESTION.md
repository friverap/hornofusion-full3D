# Pregunta de investigación

**Aprobada por el usuario:** 22-oct-2026, al aprobar el plan del harness
co-investigador («Plan K como piloto»).

## Pregunta

¿El limitador de hueco dentro del Poisson (Plan K, `pc_alpha_implicit`,
`docs/PLAN_K_limitador_en_poisson.md`) elimina la familia «piso de poro con un
paso de retraso» que detiene B1 a 284.3, 294.1 y 342.5 s, sin crear presiones
no físicas ni empeorar otras ventanas de B1, los bancos o los gates?

## Metas

| Meta | Workstream | Entregable | Terminado cuando |
|---|---|---|---|
| G1 | WS-K1 | Los 9 hallazgos de la auditoría dirigida del Plan K resueltos o documentados, y H1 en la ventana 342.45–342.56 s | Predicción H1b juzgada; panel unánime; test-quick; commit por la compuerta |
| G2 | WS-K2 | Ventanas B1 284.3, 294.1 y 340–346 s (y más largas si G1 pasa) | Predicciones por ventana juzgadas contra la base `judge_otp_280` |
| G3 | WS-K3 | Bancos (bed_bath_rest, bed_drain, pocket_rise, bath_freeze), MPI n1/n4, bitwise con la clave off | test-full y `/verificacion-bitwise` sin regresión |

## Fuera de alcance

Cambiar el default de `pc_alpha_implicit` (solo tras G1–G3 y un juez largo);
el pico de 805 kPa de 342.45–342.53 s (otro mecanismo, hipótesis abierta);
M3 (gas aspirado), Plan I.
