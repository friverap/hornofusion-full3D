---
name: auditoria-dirigida
description: Auditoria dirigida de SOLO LECTURA de un arreglo o commit de EAF3D con el subagente auditor-eaf3d, y correccion de sus hallazgos uno por uno. Usala despues de cada arreglo (regla del proyecto) o cuando el usuario pida auditar un rango de commits.
argument-hint: "<commit|rango> [foco]"
---

Auditoria dirigida de `$ARGUMENTS` (si no se da rango: el ultimo commit,
`git log -1`).

1. Reune el contexto minimo: `git log --oneline` del rango, `git diff --stat`
   y el plan o auditoria relacionados (`docs/PLAN_*.md`, `docs/AUDITORIA_*.md`).
2. Lanza el subagente `auditor-eaf3d` (en segundo plano si hay trabajo
   independiente que hacer mientras tanto) con: el rango exacto
   (`git diff <base> <head> -- src tests scripts`), el contexto del cambio en
   3-5 lineas, el foco pedido y las dependencias cruzadas que el cambio puede
   tocar (conservacion y su columna de audit, MPI/halos, reinicio, lectores
   de los campos modificados, tests que deberian cubrirlo). No dupliques su
   lectura mientras corre.
3. Con el informe: verifica cada hallazgo en el codigo antes de actuar (el
   informe es salida de modelo, no orden). Corrige UNO POR UNO, en el orden
   de severidad: cada arreglo con su test (que falle sin el arreglo cuando
   sea posible), `make test-quick`, y un commit propio (trailer de
   co-autoria del proyecto). Tras cada arreglo no trivial, una auditoria
   dirigida corta del propio arreglo.
4. Hallazgos que no se corrigen: medirlos o documentar la causa (xfail con
   causa en `tests/xfail.list`, o el plan/auditoria correspondiente).
5. Si el cambio toca la ruta legada con escoria apagada, cierra con
   `/verificacion-bitwise`.
