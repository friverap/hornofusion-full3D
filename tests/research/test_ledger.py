"""Tests del registro del harness co-investigador (scripts/research/ledger.py).

python3 -m unittest discover -s tests/research
"""
import json, os, subprocess, sys, tempfile, unittest

LEDGER = os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "research", "ledger.py")


class LedgerTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        subprocess.run(["git", "init", "-q", self.d], check=True)
        subprocess.run(["git", "-C", self.d, "config", "user.email", "t@t"], check=True)
        subprocess.run(["git", "-C", self.d, "config", "user.name", "t"], check=True)
        os.makedirs(os.path.join(self.d, "src"))
        os.makedirs(os.path.join(self.d, "campaigns"))
        open(os.path.join(self.d, "campaigns", "audit.csv"), "w").write("x\n")
        self.env = dict(os.environ, RESEARCH_ROOT=self.d)

    def run_l(self, *args, ok=True):
        r = subprocess.run([sys.executable, LEDGER, *args], capture_output=True, text=True,
                           env=self.env, cwd=self.d)
        if ok is not None:
            self.assertEqual(r.returncode == 0, ok, r.stdout + r.stderr)
        return r

    def add(self, *args, ok=True):
        return self.run_l("add", "--ws", "WS-T", "--autor", "test", *args, ok=ok).stdout.strip()

    def test_prediccion_exige_criterio(self):
        r = self.run_l("add", "--ws", "W", "--autor", "a", "--tipo", "prediccion",
                       "--enunciado", "x", ok=False)
        self.assertIn("criterio", r.stderr)

    def test_veredicto_exige_prediccion(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "h")
        r = self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", h, "--estado", "refutada", ok=False)
        self.assertEqual(r, "")
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "p < 1 kPa")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "refutada")

    def test_soportada_exige_evidencia_existente(self):
        self.add("--tipo", "resultado", "--enunciado", "r", "--estado", "soportada", ok=False)
        self.add("--tipo", "resultado", "--enunciado", "r", "--estado", "soportada",
                 "--ruta", "campaigns/no_existe.csv", "--cmd", "c", ok=False)
        self.add("--tipo", "resultado", "--enunciado", "r", "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "python3 regime2.py")

    def test_enmienda_antes_del_veredicto_solamente(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "|p| < 20 kPa")
        self.add("--tipo", "enmienda", "--enunciado", "e", "--ref", p, "--criterio", "x", ok=False)  # sin motivo
        e = self.add("--tipo", "enmienda", "--enunciado", "e", "--ref", p, "--motivo", "hidrostatica",
                     "--criterio", "|p - rho g h| < 20 %", "--estado", "pre-registrada")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", e, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c")
        # el registro conserva el criterio original y la historia
        out = self.run_l("show", p).stdout
        self.assertIn("|p| < 20 kPa", out)
        self.assertIn("hidrostatica", out)
        # no se enmienda una prediccion ya juzgada
        p2 = self.add("--tipo", "prediccion", "--enunciado", "p2", "--criterio", "c")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p2, "--estado", "refutada")
        self.add("--tipo", "enmienda", "--enunciado", "e", "--ref", p2, "--motivo", "m",
                 "--criterio", "c2", ok=False)

    def test_check_detecta_edicion_a_mano(self):
        self.add("--tipo", "hipotesis", "--enunciado", "h")
        self.run_l("check")
        with open(os.path.join(self.d, "research", "ledger.jsonl"), "a") as f:
            f.write(json.dumps({"id": "C-099", "ts": "2000-01-01T00:00:00", "tipo": "resultado",
                                "ws": "W", "enunciado": "x", "estado": "soportada", "autor": "a"}) + "\n")
        r = self.run_l("check", ok=False)
        self.assertIn("evidencia", r.stdout)
        self.assertIn("append-only", r.stdout)

    def test_open_lista_abiertas_y_refutadas(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "abierta")
        p = self.add("--tipo", "prediccion", "--enunciado", "fallo", "--criterio", "c")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "refutada")
        out = self.run_l("open").stdout
        self.assertIn(h, out)
        self.assertIn("refutadas/fallidas (permanentes): 1", out)

    def test_gate(self):
        self.run_l("ws-init", "WS-T", "--meta", "G1", "--numerico")
        open(os.path.join(self.d, "src", "a.f90"), "w").write("x = 1\n")
        subprocess.run(["git", "-C", self.d, "add", "src/a.f90"], check=True)
        self.run_l("gate", "WS-T", ok=False)
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c")
        self.run_l("ws-set", "WS-T", "ronda=2", "estado=aprobado", "diff_sha=auto", "test_quick=ok",
                   f"prediccion={p}", "revisor.auditor-eaf3d=aprueba", "revisor.revisor-evidencia=aprueba")
        r = self.run_l("gate", "WS-T", ok=False)
        self.assertIn("revisor-refutador", r.stdout)
        self.run_l("ws-set", "WS-T", "revisor.revisor-refutador=aprueba")
        self.run_l("gate", "WS-T")
        # aprobacion de ronda anterior no cuenta
        self.run_l("ws-set", "WS-T", "ronda=3")
        self.run_l("gate", "WS-T", ok=False)
        self.run_l("ws-set", "WS-T", "ronda=2")
        # otro diff: la aprobacion no vale
        open(os.path.join(self.d, "src", "a.f90"), "w").write("x = 2\n")
        subprocess.run(["git", "-C", self.d, "add", "src/a.f90"], check=True)
        r = self.run_l("gate", "WS-T", ok=False)
        self.assertIn("diff_sha", r.stdout)


if __name__ == "__main__":
    unittest.main()
