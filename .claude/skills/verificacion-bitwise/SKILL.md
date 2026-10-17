---
name: verificacion-bitwise
description: Verifica que un cambio deja BIT A BIT intacta la ruta legada (B1 corto y produccion corta, audit por columnas comunes y snapshot final a rtol 0) contra un binario de referencia de un commit dado. Usala cuando un cambio solo debe actuar con una clave nueva activa o con escoria.
argument-hint: "[commit_ref]"
---

Gate bit a bit contra el commit de referencia `$0` (si no se da: `main`).

1. Comprueba que no haya una simulacion en curso (`pgrep -fl eaf3d`); el hook
   `guard_corridas` bloquea `make`/`mpirun` si la hay.
2. Binario de referencia: si no existe ya uno del mismo commit en el
   scratchpad, constrúyelo en un worktree temporal fuera de `bin/`:
   `git worktree add <scratch>/ref_<sha> <commit>`, `make -C <scratch>/ref_<sha> -j8`
   y copia su `bin/eaf3d_mpi` a `<scratch>/bitref/eaf3d_<sha>`; luego
   `git worktree remove <scratch>/ref_<sha>`.
3. Compila el arbol actual (`make -j8`) y copia `bin/eaf3d_mpi` al scratchpad.
4. `bash scripts/bitwise_check.sh <ref> <nuevo> <scratch>/bit_<etiqueta>`
   (12 ranks; B1 corto 30 pasos y produccion corta). Exige `BITWISE: OK`.
   Columnas de audit nuevas se informan y no cuentan como diferencia.
5. Si falla: diagnostica con `compare_decomposition.py --rtol 0` el primer
   campo que difiere y busca la rama legada que el cambio altero (las
   expresiones del legado deben quedar textualmente iguales, no "equivalentes").
