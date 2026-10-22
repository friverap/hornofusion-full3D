---
name: preregistro
description: Pre-registra en research/ledger.jsonl una predicción con criterio numérico CONGELADO antes de lanzar un experimento o una corrida de EAF3D (harness co-investigador). También registra enmiendas (con motivo, solo antes del veredicto) y veredictos contra el criterio. Úsala antes de toda corrida que vaya a decidir algo.
argument-hint: "<WS> \"<predicción>\" \"<criterio numérico>\" | veredicto <C-nnn> | enmienda <C-nnn>"
---

Pre-registro para `$ARGUMENTS`.

**Predicción (antes de correr).**
1. El criterio debe ser numérico, medible con un comando concreto y
   físicamente razonado ANTES de ver datos: magnitud, ventana temporal, base
   de comparación (ruta de la corrida base) y tolerancia. Piensa en la escala
   física (p. ej. hidrostática local ρ g h antes de pedir «|p| < X»).
2. Escribe también `--refuta-si` (qué resultado tumbaría la hipótesis) y el
   comando que lo medirá.
3. `python3 scripts/research/ledger.py add --tipo prediccion --ws <WS> --autor coordinador --enunciado "..." --criterio "..." --refuta-si "..."`
   y, si el workstream es numérico, `ledger.py ws-set <WS> prediccion=C-nnn`.
4. Commitea `research/` antes de lanzar la corrida (el timestamp del commit
   prueba que el criterio es previo al dato).

**Veredicto (después).** Ejecuta el comando registrado, compara LITERALMENTE
con el criterio y registra `--tipo veredicto --ref C-nnn --estado
soportada|refutada|en_disputa --ruta <datos> --cmd "<comando>"`. Un resultado
que no cumple el criterio es `refutada` aunque «se vea bien»: dilo así al
usuario. Lo que sugiera el dato va a una predicción NUEVA.

**Enmienda.** Solo si el criterio estaba mal planteado y AÚN no hay
veredicto: `--tipo enmienda --ref C-nnn --motivo "..." --criterio "<nuevo>"
--estado pre-registrada`, y avisa al usuario de la enmienda y su motivo.
