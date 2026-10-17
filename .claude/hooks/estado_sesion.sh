#!/bin/bash
# SessionStart: estado operativo del repo para que la sesion no arranque a
# ciegas (antes se reconstruia leyendo la memoria y el git log a mano).
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -d hornofusion-full3D ] && cd hornofusion-full3D
[ -f Makefile ] || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
head=$(git log --oneline -1 2>/dev/null)
dirty=$(git status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')
golden=$(ls tests/golden/metrics_v*.json 2>/dev/null | sed 's/.*metrics_v\([0-9]*\)\.json/\1/' | sort -n | tail -1)
running=$(pgrep -fl 'eaf3d' 2>/dev/null | grep -v -e pgrep -e estado_sesion | head -3)
[ -z "$running" ] && running="ninguna"
ctx="EAF3D (estado al iniciar): rama ${branch}, HEAD ${head}; ${dirty} archivo(s) versionado(s) modificado(s); golden vigente v${golden}. Corridas EAF3D activas: ${running//$'\n'/; }. El hook guard_corridas bloquea make/mpirun y escrituras en bin/ mientras haya una corrida activa (corridas solo secuenciales)."
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
exit 0
