#!/bin/bash
# PreToolUse (Bash): reglas operativas de EAF3D que antes dependian de la
# memoria del agente (CLAUDE.md, memoria "Estado del proyecto"):
#   1. las corridas son SOLO SECUENCIALES (una simulacion a la vez: compiten
#      por los 18 nucleos y los tiempos/juicios dejan de ser comparables);
#   2. NUNCA tocar bin/ mientras corre una simulacion (make reescribe el
#      binario que usa la corrida activa).
# Si hay un proceso eaf3d vivo, bloquea make/mpirun/mpiexec y cualquier
# escritura o borrado en bin/. Escape explicito y visible: anadir el
# comentario "# permitir-concurrente" al comando (p.ej. un make -n).
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -z "$cmd" ] && exit 0
case "$cmd" in *"# permitir-concurrente"*) exit 0 ;; esac

# comandos que lanzan corridas, recompilan o escriben en bin/: se mira cada
# subcomando (separado por ; & | && || ( ) en posicion de comando, para no
# confundir "grep make" o "cp bin/x /tmp" (solo lee de bin/)
hit=$(python3 - "$cmd" <<'PY'
import re, shlex, sys
cmd = sys.argv[1]
for seg in re.split(r'&&|\|\||[;&|()\n]', cmd):
    seg = seg.strip()
    if not seg:
        continue
    if re.search(r'>\s*(\./)?bin/', seg):
        print("redir"); break
    try:
        tok = shlex.split(seg, comments=True)
    except ValueError:
        tok = seg.split()
    while tok and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tok[0]):   # VAR=x make
        tok = tok[1:]
    if not tok:
        continue
    exe = tok[0].split('/')[-1]
    if exe in ("make", "gmake", "mpirun", "mpiexec"):
        print(exe); break
    if exe in ("cp", "mv", "install", "ln") and len(tok) > 1 and re.match(r'^(\./)?bin(/|$)', tok[-1]):
        print(exe); break
    if exe == "rm" and any(re.match(r'^(\./)?bin(/|$)', t) for t in tok[1:]):
        print(exe); break
PY
)
[ -z "$hit" ] && exit 0

# corridas vivas (binario de desarrollo o de campana)
running=$(pgrep -fl 'eaf3d' 2>/dev/null | grep -v -e 'pgrep' -e 'guard_corridas' | head -3)
[ -z "$running" ] && exit 0

reason="Hay una simulacion EAF3D en curso (${running//$'\n'/; }). Regla del proyecto: corridas SOLO secuenciales y nunca tocar bin/ mientras corre una simulacion. Espera a que termine (o detenla si es tuya y ya no sirve). Escape explicito: anade '# permitir-concurrente' al comando solo si de verdad no compite (p.ej. make -n)."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
