#!/bin/bash
# PreToolUse (Bash, Edit, Write, MultiEdit): COMPUERTA DE CIERRE del harness
# co-investigador (research/README.md; AI co-mathematician, arXiv 2605.06651
# §3.3-3.4: el trabajo no se marca terminado hasta que pasan los tests y TODOS
# los revisores aprueban).
#   1. `git commit` cuyo staged toque src/, tests/ (salvo tests/golden y
#      tests/research), scripts/research/, .claude/hooks/, .claude/workflows/,
#      .claude/agents/ o .claude/settings.json (la herramienta del registro y el
#      panel, WS-K13) exige
#      `scripts/research/ledger.py gate` OK para ESE diff (GATED en ledger.py):
#      workstream aprobado por los tres revisores en la misma ronda,
#      test_quick=ok, diff_sha del staged y, si es numerico, prediccion
#      pre-registrada juzgada.
#   2. `git commit -a/--all/-i/-o` o con pathspec: denegado (se saltan el
#      staged que la compuerta verifica); usar `git add` explicito.
#   3. research/ledger.jsonl es append-only: solo `ledger.py add` lo escribe.
# Escape SOLO con autorizacion explicita del usuario: "# cierre-sin-compuerta"
# en el comando (queda anotado en el registro).
tmp=$(mktemp -t guard_cierre.XXXXXX) || exit 0
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"
python3 - "$tmp" <<'PY'
import json, os, re, shlex, subprocess, sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
tool = data.get("tool_name", "")
ti = data.get("tool_input", {}) or {}

def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                      "permissionDecision": "deny", "permissionDecisionReason": reason}}))
    sys.exit(0)

LEDGER_MSG = ("research/ledger.jsonl es append-only: se escribe SOLO con "
              "'python3 scripts/research/ledger.py add ...' (una correccion es un evento nuevo con --ref).")

# --- 3. registro append-only ------------------------------------------------
if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    fp = (ti.get("file_path", "") or ti.get("notebook_path", "")).replace("\\", "/")
    if fp.endswith("research/ledger.jsonl"):
        deny(LEDGER_MSG)
    sys.exit(0)
if tool != "Bash":
    sys.exit(0)
cmd = ti.get("command", "") or ""
if not cmd:
    sys.exit(0)
if "ledger.jsonl" in cmd and (re.search(r'>\s*\S*ledger\.jsonl', cmd)
        or re.search(r'(sed|perl)\s+-i[^;&|]*ledger\.jsonl', cmd)
        or re.search(r'(^|[;&|\s])(cp|mv|tee|install|rm|truncate)\s[^;&|]*ledger\.jsonl', cmd)
        or re.search(r'git\s+(checkout|restore)\b[^;&|]*ledger\.jsonl', cmd)):
    deny(LEDGER_MSG)

if not re.search(r'\bgit\b', cmd) or "commit" not in cmd:
    sys.exit(0)

PROJ = os.environ.get("CLAUDE_PROJECT_DIR", "") or data.get("cwd", "")
REPO0 = PROJ if os.path.isfile(os.path.join(PROJ, "Makefile")) else os.path.join(PROJ, "hornofusion-full3D")

def segments(c):
    try:
        lex = shlex.shlex(c, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = '#'
        toks = list(lex)
    except ValueError:
        return None
    seg, out = [], []
    for t in toks:
        if t and set(t) <= set(';&|()\n'):
            if seg: out.append(seg)
            seg = []
        else:
            seg.append(t)
    if seg: out.append(seg)
    return out

segs = segments(cmd)
if segs is None:
    deny("guard_cierre: no se pudo analizar el comando con git commit (comillas sin cerrar).")

GIT_GLOBAL_VAL = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
cwd = data.get("cwd") or REPO0
commits = []   # (repo_dir, args)
for tok in segs:
    while tok and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tok[0]):
        tok = tok[1:]
    if not tok:
        continue
    exe = tok[0].split('/')[-1]
    if exe == "cd" and len(tok) > 1:
        cwd = tok[1] if os.path.isabs(tok[1]) else os.path.join(cwd, tok[1])
        continue
    if exe != "git":
        continue
    i, rdir = 1, cwd
    while i < len(tok) and tok[i].startswith("-"):
        if tok[i] in GIT_GLOBAL_VAL and i + 1 < len(tok):
            if tok[i] == "-C":
                rdir = tok[i + 1] if os.path.isabs(tok[i + 1]) else os.path.join(rdir, tok[i + 1])
            i += 2
        else:
            i += 1
    if i < len(tok) and tok[i] == "commit":
        commits.append((rdir, tok[i + 1:]))

if not commits:
    sys.exit(0)

ESCAPE = "# cierre-sin-compuerta" in cmd
VAL_LONG = {"--message", "--file", "--reuse-message", "--reedit-message", "--fixup", "--squash",
            "--author", "--date", "--cleanup", "--template", "--trailer", "--gpg-sign", "--pathspec-from-file"}
for rdir, args in commits:
    # --- 2. commits que se saltan el staged --------------------------------
    j, bypass = 0, None
    while j < len(args):
        a = args[j]
        if a == "--":
            bypass = "pathspec tras --"; break
        if a.startswith("--"):
            name = a.split("=", 1)[0]
            if name in ("--all", "--include", "--only", "--interactive", "--patch"):
                bypass = name; break
            if name in VAL_LONG and "=" not in a:
                j += 1
        elif a.startswith("-") and len(a) > 1:
            for k, ch in enumerate(a[1:]):
                if ch in "aiop":
                    bypass = "-" + ch; break
                if ch in "mFcCtS":
                    if k == len(a) - 2:
                        j += 1
                    break
            if bypass: break
        else:
            bypass = f"pathspec '{a}'"; break
        j += 1
    if bypass and not ESCAPE:
        deny(f"guard_cierre: 'git commit' con {bypass} se salta el staged que verifica la compuerta. "
             "Usa 'git add <archivos>' explicito y 'git commit -m ...'.")

    # --- 1. compuerta --------------------------------------------------------
    try:
        top = subprocess.run(["git", "-C", rdir, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        continue
    LP = "scripts/research/ledger.py"
    def git_show(rev):
        return subprocess.run(["git", "-C", top, "show", f"{rev}:{LP}"], capture_output=True, text=True).stdout
    # la compuerta la decide la herramienta YA APROBADA (HEAD); la del indice solo si HEAD no la tiene,
    # y la del disco solo si tampoco el indice (repo nuevo). Borrarla o renombrarla no la apaga (WS-K13)
    tool = git_show("HEAD") or git_show("")
    if not tool and os.path.isfile(os.path.join(top, LP)):
        tool = open(os.path.join(top, LP)).read()
    if not tool:
        continue   # otro repo
    # --no-renames: un `git mv` de una ruta vigilada lista la ruta vieja Y la nueva (WS-K13)
    staged = [f for f in subprocess.run(["git", "-C", top, "diff", "--cached", "--name-only", "--no-renames", "-z"],
                                        capture_output=True, text=True).stdout.split("\0") if f]
    gated = [f for f in staged if f.startswith(("src/", "tests/", "scripts/research/", ".claude/hooks/",
                                                 ".claude/workflows/", ".claude/agents/",
                                                 ".claude/settings.json"))
             and not f.startswith("tests/golden/") and not f.startswith("tests/research/")]
    if not gated:
        continue
    env = dict(os.environ, RESEARCH_ROOT=top)
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as tf:
        tf.write(tool)
    try:
        r = subprocess.run([sys.executable, tf.name, "gate"], capture_output=True, text=True, cwd=top, env=env)
    finally:
        os.unlink(tf.name)
    if r.returncode == 0:
        continue
    if ESCAPE:
        subprocess.run([sys.executable, os.path.join(top, "scripts", "research", "ledger.py"), "add",
                        "--tipo", "resultado", "--ws", "ESCAPE", "--autor", "guard_cierre",
                        "--enunciado", "commit SIN compuerta (escape autorizado por el usuario) de: "
                        + ", ".join(gated[:8])], cwd=top, env=env, capture_output=True)
        continue
    deny("guard_cierre: commit de " + ", ".join(gated[:6]) + (" ..." if len(gated) > 6 else "")
         + " sin compuerta de cierre.\n" + (r.stdout + r.stderr).strip()
         + "\nCiclo: research/README.md (panel de 3 revisores + test-quick + diff_sha). "
           "Escape '# cierre-sin-compuerta' SOLO con autorizacion explicita del usuario.")
sys.exit(0)
PY
