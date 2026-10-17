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
input=$(cat)
exec python3 - "$input" <<'PY'
import json, re, shlex, subprocess, sys

data = json.loads(sys.argv[1] or "{}")
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
is_bin = lambda p: bool(re.search(r'(^|/)bin(/|$)', p)) and "campaigns/bin" not in p and "tests/bin" not in p

# --- herramientas de archivo ------------------------------------------------
if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    fp = ti.get("file_path", "") or ti.get("notebook_path", "")
    if fp.endswith("tests/run_tests.sh") and running("tests/run_tests\\.sh"):
        deny(SUITE_MSG)
    if is_bin(fp):
        r = running("eaf3d")
        if r:
            deny(RUN_MSG.format(r))
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)
cmd = ti.get("command", "") or ""
if not cmd:
    sys.exit(0)

# --- 3. suite en curso (sin escape) ----------------------------------------
if running("tests/run_tests\\.sh"):
    writes_rt = ("run_tests.sh" in cmd and (
        re.search(r'>\s*\S*run_tests\.sh', cmd) or re.search(r"open\([^)]*run_tests\.sh[^)]*['\"][wa]", cmd)
        or re.search(r'(sed|perl)\s+-i[^;&|]*run_tests\.sh', cmd)
        or re.search(r'(^|[;&|\s])(cp|mv|tee|install)\s[^;&|]*run_tests\.sh', cmd)))
    git_tree = re.search(r'(^|[;&|(\s])git\s+(checkout|switch|stash|reset|rebase|cherry-pick|apply|restore|pull|merge|am)\b', cmd) \
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
    while tok and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tok[0]):
        tok = tok[1:]
    if not tok:
        continue
    exe = tok[0].split('/')[-1]
    if exe in ("make", "gmake", "mpirun", "mpiexec"):
        hit = True; break
    if exe in ("cp", "mv", "install", "ln") and len(tok) > 1 and re.match(r'^(\./)?bin(/|$)', tok[-1]):
        hit = True; break
    if exe == "rm" and any(re.match(r'^(\./)?bin(/|$)', t) for t in tok[1:]):
        hit = True; break
if hit:
    r = running("eaf3d")
    if r:
        deny(RUN_MSG.format(r))
sys.exit(0)
PY
