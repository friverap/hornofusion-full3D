#!/bin/bash
# PreToolUse (Bash, Edit, Write, MultiEdit): reglas operativas de EAF3D que
# antes dependian de la memoria del agente:
#   1. corridas SOLO SECUENCIALES (una simulacion a la vez: compiten por los
#      18 nucleos y los tiempos/juicios dejan de ser comparables);
#   2. NUNCA tocar bin/ mientras corre una simulacion (make reescribe el
#      binario que usa la corrida activa);
#   3. NUNCA modificar tests/run_tests.sh (ni reescribir el arbol con git)
#      mientras corre la suite: bash lee el script de forma INCREMENTAL
#      (rebaseline v121: error de sintaxis al final y golden contaminado).
# Escape explicito para 1-2 (no para 3): "# permitir-concurrente" en el comando.
# (auditoria 19, M19-2) el JSON va por un archivo temporal, no por argv (un
# Write de mas de ~1 MB superaba ARG_MAX y el hook dejaba pasar todo)
tmp=$(mktemp -t guard_corridas.XXXXXX) || exit 0
cat > "$tmp"
python3 - "$tmp" <<'PY'
import json, os, re, shlex, subprocess, sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
tool = data.get("tool_name", "")
ti = data.get("tool_input", {}) or {}

def running(pattern):
    try:
        out = subprocess.run(["pgrep", "-fl", pattern], capture_output=True, text=True).stdout
    except Exception:
        return ""
    lines = [l for l in out.splitlines() if "pgrep" not in l and "guard_corridas" not in l]
    return "; ".join(lines[:3])

def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                      "permissionDecision": "deny", "permissionDecisionReason": reason}}))
    sys.exit(0)

SUITE_MSG = ("tests/run_tests.sh se esta ejecutando (suite de tests): bash lo lee de forma "
             "incremental y modificarlo o reescribir el arbol con git ahora corrompe la corrida. "
             "Espera a que termine la suite.")
RUN_MSG = ("Hay una simulacion EAF3D en curso ({}). Regla del proyecto: corridas SOLO "
           "secuenciales y nunca tocar bin/ mientras corre una simulacion. Espera a que termine "
           "(o detenla si es tuya y ya no sirve). Escape explicito: anade '# permitir-concurrente' "
           "al comando solo si de verdad no compite (p.ej. make -n).")
PROJ = os.environ.get("CLAUDE_PROJECT_DIR", "")
REPO = PROJ if os.path.isfile(os.path.join(PROJ, "Makefile")) else os.path.join(PROJ, "hornofusion-full3D")
def is_bin(p):
    # bin/ del repo con ruta relativa o ABSOLUTA (los subagentes usan absolutas)
    p = p.replace("\\", "/")
    if "campaigns/bin" in p or "tests/bin" in p:
        return False
    if os.path.isabs(p):
        return p.startswith(os.path.join(REPO, "bin") + "/") or p == os.path.join(REPO, "bin")
    return bool(re.match(r'^(\./)?bin(/|$)', p))
# corridas EAF3D reales (binario de desarrollo o de campana), no cualquier
# proceso con 'eaf3d' en la linea (h5dump eaf3d_*.h5 bloqueaba make)
SIM_PAT = r'bin/eaf3d'
SUITE_PAT = r'(bash|sh) +([^ ]*/)?tests/run_tests\.sh'

# --- herramientas de archivo ------------------------------------------------
if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    fp = ti.get("file_path", "") or ti.get("notebook_path", "")
    if fp.endswith("tests/run_tests.sh") and running(SUITE_PAT):
        deny(SUITE_MSG)
    if is_bin(fp):
        r = running(SIM_PAT)
        if r:
            deny(RUN_MSG.format(r))
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)
cmd = ti.get("command", "") or ""
if not cmd:
    sys.exit(0)

# --- 3. suite en curso (sin escape) ----------------------------------------
if running(SUITE_PAT):
    writes_rt = ("run_tests.sh" in cmd and (
        re.search(r'>\s*\S*run_tests\.sh', cmd) or re.search(r"open\([^)]*run_tests\.sh[^)]*['\"][wa]", cmd)
        or re.search(r'(sed|perl)\s+-i[^;&|]*run_tests\.sh', cmd)
        or re.search(r'(^|[;&|\s])(cp|mv|tee|install)\s[^;&|]*run_tests\.sh', cmd)))
    git_tree = re.search(r'(^|[;&|(\s])git(\s+-C\s+\S+)?\s+(checkout|switch|stash|reset|rebase|cherry-pick|apply|restore|pull|merge|am)\b', cmd) \
               or re.search(r'(^|[;&|(\s])patch\s', cmd)
    if writes_rt or git_tree:
        deny(SUITE_MSG)

if "# permitir-concurrente" in cmd:
    sys.exit(0)

# --- 1-2. simulacion en curso ----------------------------------------------
hit = False
for seg in re.split(r'&&|\|\||[;&|()\n]', cmd):
    seg = seg.strip()
    if not seg:
        continue
    if re.search(r'(^|[^0-9&])>\s*(\./)?bin/', seg):
        hit = True; break
    try:
        tok = shlex.split(seg, comments=True)
    except ValueError:
        tok = seg.split()
    # (M19-2) quitar asignaciones VAR=x y prefijos que lanzan otro comando
    PREFIX = {"nohup", "nice", "time", "env", "caffeinate", "timeout", "exec", "command", "sudo"}
    while tok:
        t0 = tok[0].split('/')[-1]
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tok[0]):
            tok = tok[1:]; continue
        if t0 in PREFIX:
            tok = tok[1:]
            # opciones del prefijo y sus valores (nice -n 5, timeout 10s, env -i)
            while tok and (tok[0].startswith('-') or re.match(r'^[+-]?[0-9.]+[smhd]?$', tok[0])):
                tok = tok[1:]
            continue
        break
    if not tok:
        continue
    exe = tok[0].split('/')[-1]
    args = tok[1:]
    if exe in ("make", "gmake", "mpirun", "mpiexec"):
        hit = True; break
    # lanzadores de corridas del repo (runner de campanas, suite, bit a bit)
    if exe in ("python", "python3", "bash", "sh", "zsh") and args and \
       re.search(r'(run_campaign\.py|run_tests\.sh|bitwise_check\.sh)$', args[0]):
        hit = True; break
    if re.search(r'(run_campaign\.py|run_tests\.sh|bitwise_check\.sh)$', exe):
        hit = True; break
    if exe in ("cp", "mv", "install", "ln") and len(tok) > 1 and is_bin(tok[-1]):
        hit = True; break
    if exe == "rm" and any(is_bin(t) for t in tok[1:]):
        hit = True; break
if hit:
    r = running(SIM_PAT)
    if r:
        deny(RUN_MSG.format(r))
sys.exit(0)
PY
rm -f "$tmp"
