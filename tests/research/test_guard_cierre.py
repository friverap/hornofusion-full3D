"""Tests del hook .claude/hooks/guard_cierre.sh con JSON simulado.

python3 -m unittest discover -s tests/research
"""
import json, os, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
HOOK = os.path.join(REPO, ".claude", "hooks", "guard_cierre.sh")
LEDGER = os.path.join(REPO, "scripts", "research", "ledger.py")


class GuardCierreTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        g = lambda *a: subprocess.run(["git", "-C", self.d, *a], check=True, capture_output=True)
        subprocess.run(["git", "init", "-q", self.d], check=True)
        g("config", "user.email", "t@t"); g("config", "user.name", "t")
        os.makedirs(os.path.join(self.d, "scripts", "research"))
        shutil.copy(LEDGER, os.path.join(self.d, "scripts", "research", "ledger.py"))
        open(os.path.join(self.d, "Makefile"), "w").write("all:\n")
        for sub in ("src", "docs", "campaigns"):
            os.makedirs(os.path.join(self.d, sub))
        open(os.path.join(self.d, "campaigns", "a.csv"), "w").write("x\n")
        self.g = g

    def hook(self, tool, ti):
        data = {"tool_name": tool, "tool_input": ti, "cwd": self.d}
        env = dict(os.environ, CLAUDE_PROJECT_DIR=self.d)
        r = subprocess.run(["bash", HOOK], input=json.dumps(data), capture_output=True, text=True, env=env)
        if not r.stdout.strip():
            return "allow", ""
        o = json.loads(r.stdout)["hookSpecificOutput"]
        return o["permissionDecision"], o["permissionDecisionReason"]

    def ledger(self, *a):
        env = dict(os.environ, RESEARCH_ROOT=self.d)
        return subprocess.run([sys.executable, os.path.join(self.d, "scripts", "research", "ledger.py"), *a],
                              capture_output=True, text=True, env=env, cwd=self.d, check=True).stdout.strip()

    def stage(self, path, txt):
        open(os.path.join(self.d, path), "w").write(txt)
        self.g("add", path)

    def commit(self, extra=""):
        return self.hook("Bash", {"command": f"cd {self.d} && git commit -m 'x'{extra}"})

    def test_src_sin_workstream_deny(self):
        self.stage("src/a.f90", "x=1\n")
        dec, why = self.commit()
        self.assertEqual(dec, "deny"); self.assertIn("compuerta", why)

    def test_docs_allow(self):
        self.stage("docs/a.md", "x\n")
        self.assertEqual(self.commit()[0], "allow")

    def test_flags_que_saltan_staged(self):
        for c in ("git commit -am 'x'", "git commit -a -m x", "git commit --all -m x",
                  "git commit -m x src/a.f90", "git commit -m x -- src", "git -C . commit -qam x"):
            dec, why = self.hook("Bash", {"command": f"cd {self.d} && {c}"})
            self.assertEqual(dec, "deny", c)
        # -m con valor que parece pathspec no es pathspec
        self.stage("docs/b.md", "y\n")
        self.assertEqual(self.hook("Bash", {"command": f"cd {self.d} && git commit -q -m 'src/a.f90 arreglo'"})[0], "allow")

    def test_compuerta_completa_y_diff_cambiado(self):
        self.ledger("ws-init", "WS-T", "--meta", "G1")
        self.stage("src/a.f90", "x=1\n")
        self.ledger("ws-set", "WS-T", "ronda=1", "estado=aprobado", "diff_sha=auto", "test_quick=ok",
                    "revisor.auditor-eaf3d=aprueba", "revisor.revisor-evidencia=aprueba",
                    "revisor.revisor-refutador=aprueba")
        self.assertEqual(self.commit()[0], "allow")
        self.stage("src/a.f90", "x=2\n")
        dec, why = self.commit()
        self.assertEqual(dec, "deny"); self.assertIn("diff_sha", why)

    def test_escape_queda_en_registro(self):
        self.stage("src/a.f90", "x=1\n")
        self.assertEqual(self.commit(" # cierre-sin-compuerta")[0], "allow")
        self.assertIn("SIN compuerta", open(os.path.join(self.d, "research", "ledger.jsonl")).read())

    def test_ledger_append_only(self):
        self.assertEqual(self.hook("Write", {"file_path": f"{self.d}/research/ledger.jsonl", "content": ""})[0], "deny")
        self.assertEqual(self.hook("Bash", {"command": "echo '{}' >> research/ledger.jsonl"})[0], "deny")
        self.assertEqual(self.hook("Bash", {"command": "sed -i '' 's/a/b/' research/ledger.jsonl"})[0], "deny")
        self.assertEqual(self.hook("Bash", {"command": "python3 scripts/research/ledger.py open"})[0], "allow")
        self.assertEqual(self.hook("Bash", {"command": "wc -l research/ledger.jsonl"})[0], "allow")

    def test_otros_comandos_no_tocados(self):
        self.stage("src/a.f90", "x=1\n")
        for c in ("git status", "git log --oneline -3", "grep -n commit src/a.f90", "git diff --cached"):
            self.assertEqual(self.hook("Bash", {"command": f"cd {self.d} && {c}"})[0], "allow", c)


if __name__ == "__main__":
    unittest.main()
