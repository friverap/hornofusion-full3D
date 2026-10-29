"""Tests del registro del harness co-investigador (scripts/research/ledger.py).

python3 -m unittest discover -s tests/research
"""
import json, os, shutil, subprocess, sys, tempfile, unittest

LEDGER = os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "research", "ledger.py")


class LedgerTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d, True)
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
        # re-aprobado el diff nuevo, el test_quick viejo no cuenta
        self.run_l("ws-set", "WS-T", "diff_sha=auto")
        r = self.run_l("gate", "WS-T", ok=False)
        self.assertIn("test_quick", r.stdout)
        self.run_l("ws-set", "WS-T", "test_quick=ok")
        self.run_l("gate", "WS-T")
        # un cambio de la herramienta del registro tambien invalida la aprobacion (WS-K13, L5)
        os.makedirs(os.path.join(self.d, "scripts", "research"), exist_ok=True)
        open(os.path.join(self.d, "scripts", "research", "x.py"), "w").write("x = 1\n")
        subprocess.run(["git", "-C", self.d, "add", "scripts/research/x.py"], check=True)
        r = self.run_l("gate", "WS-T", ok=False)
        self.assertIn("diff_sha", r.stdout)

    def test_gate_exige_veredicto_firme(self):
        # en_disputa (aun cerrada sin_decidir) y fallida no pasan; soportada y refutada si (WS-K14)
        open(os.path.join(self.d, "src", "a.f90"), "w").write("x = 1\n")
        subprocess.run(["git", "-C", self.d, "add", "src/a.f90"], check=True)
        for est, pasa in (("en_disputa", False), ("fallida", False), ("refutada", True), ("soportada", True)):
            ws = "WS-" + est
            self.run_l("ws-init", ws, "--meta", "G1", "--numerico")
            p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
            extra = ("--ruta", "campaigns/audit.csv", "--cmd", "c") if est == "soportada" else ()
            self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", est, *extra)
            if est == "en_disputa":
                self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir")
            self.run_l("ws-set", ws, "estado=aprobado", "diff_sha=auto", "test_quick=ok", f"prediccion={p}",
                       *(f"revisor.{r}=aprueba" for r in ("auditor-eaf3d", "revisor-evidencia", "revisor-refutador")))
            r = self.run_l("gate", ws, ok=pasa)
            if not pasa:
                self.assertIn(f"veredicto '{est}'", r.stdout)
        # el veredicto sobre la enmienda vigente decide igual
        for est, pasa in (("en_disputa", False), ("refutada", True)):
            ws = "WS-enm-" + est
            self.run_l("ws-init", ws, "--meta", "G1", "--numerico")
            p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
            e = self.add("--tipo", "enmienda", "--enunciado", "e", "--ref", p, "--motivo", "m", "--criterio", "c2")
            self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", e, "--estado", est)
            self.run_l("ws-set", ws, "estado=aprobado", "diff_sha=auto", "test_quick=ok", f"prediccion={p}",
                       *(f"revisor.{r}=aprueba" for r in ("auditor-eaf3d", "revisor-evidencia", "revisor-refutador")))
            self.run_l("gate", ws, ok=pasa)

    def test_open_sin_decidir_por_estado_vigente(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "h")
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", h, "--estado", "sin_decidir")
        out = self.run_l("open").stdout
        self.assertIn(f"cerradas sin decidir: 1: {h}", out)
        self.assertIn("afirmaciones abiertas: 0 de 1", out)
        # retomada con una prediccion NUEVA: vuelve a abiertas y sale de la lista
        self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c", "--ref", h)
        out = self.run_l("open").stdout
        self.assertIn("afirmaciones abiertas: 1 de 1", out)
        self.assertNotIn("cerradas sin decidir", out)
        # un segundo sin_decidir no la repite
        self.add("--tipo", "resultado", "--enunciado", "s2", "--ref", h, "--estado", "sin_decidir")
        self.assertIn(f"cerradas sin decidir: 1: {h}\n", self.run_l("open").stdout)

    def test_prediccion_juzgada_por_su_enmienda(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        e = self.add("--tipo", "enmienda", "--enunciado", "e", "--ref", p, "--motivo", "m", "--criterio", "c2")
        self.assertIn("afirmaciones abiertas: 1 de 1", self.run_l("open").stdout)
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", e, "--estado", "refutada")
        out = self.run_l("open").stdout
        self.assertIn("afirmaciones abiertas: 0 de 1", out)
        self.assertIn("refutadas/fallidas (permanentes): 1", out)
        # ya cerrada: ni sin_decidir ni otra enmienda
        r = self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir", ok=False)
        self.assertEqual(r, "")
        self.add("--tipo", "enmienda", "--enunciado", "e2", "--ref", p, "--motivo", "m", "--criterio", "c3",
                 ok=False)

    def test_cadena_de_enmiendas_juzgada(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        e1 = self.add("--tipo", "enmienda", "--enunciado", "e1", "--ref", p, "--motivo", "m", "--criterio", "c2")
        # la enmienda encadenada tambien trae el criterio NUEVO
        self.add("--tipo", "enmienda", "--enunciado", "e2", "--ref", e1, "--motivo", "m", ok=False)
        e2 = self.add("--tipo", "enmienda", "--enunciado", "e2", "--ref", e1, "--motivo", "m", "--criterio", "c3")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", e2, "--estado", "refutada")
        self.assertIn("refutadas/fallidas (permanentes): 1", self.run_l("open").stdout)
        for ref in (p, e1, e2):   # ni sobre la prediccion ni sobre ningun eslabon
            r = self.add("--tipo", "enmienda", "--enunciado", "e3", "--ref", ref, "--motivo", "m",
                         "--criterio", "c3", ok=False)
            self.assertEqual(r, "")
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir", ok=False)

    def test_nota_sobre_enmienda_no_la_juzga(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        e1 = self.add("--tipo", "enmienda", "--enunciado", "e1", "--ref", p, "--motivo", "m", "--criterio", "c2")
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", e1)
        out = self.run_l("open").stdout
        self.assertIn("afirmaciones abiertas: 1 de 1", out)
        self.assertIn("enmendada", out)

    def test_resultado_que_cierra_impide_enmienda(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        self.add("--tipo", "resultado", "--enunciado", "cerrada", "--ref", p, "--estado", "sin_decidir")
        self.add("--tipo", "enmienda", "--enunciado", "e", "--ref", p, "--motivo", "m", "--criterio", "c2",
                 ok=False)

    def test_prediccion_solo_se_juzga_con_veredicto_y_una_vez(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        a = self.add("--tipo", "enmienda", "--enunciado", "a", "--ref", p, "--motivo", "m", "--criterio", "c2")
        # un resultado de cierre sobre la prediccion o su enmienda no la juzga: se rechaza
        for ref in (p, a):
            self.add("--tipo", "resultado", "--enunciado", "r", "--ref", ref, "--estado", "soportada",
                     "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)
            self.add("--tipo", "resultado", "--enunciado", "r", "--ref", ref, "--estado", "refutada", ok=False)
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", a, "--estado", "en_disputa")
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir")
        # cerrada sin_decidir: ni soporte por resultado, ni nota, ni otro veredicto (patron C-121)
        self.add("--tipo", "resultado", "--enunciado", "r", "--ref", p, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", p, ok=False)
        self.add("--tipo", "veredicto", "--enunciado", "v2", "--ref", a, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)
        self.assertIn(f"cerradas sin decidir: 1: {p}", self.run_l("open").stdout)

    def test_cierre_admite_nota_y_retoma(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        v = self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "en_disputa")
        # una nota directa sobre la prediccion juzgada no cambia su juicio: va al veredicto
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", p, ok=False)
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", v)
        c = self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir")
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", c)
        self.add("--tipo", "resultado", "--enunciado", "r", "--ref", c, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)
        h = self.add("--tipo", "prediccion", "--enunciado", "retoma", "--criterio", "c", "--ref", c)
        out = self.run_l("open").stdout
        # la prediccion es definitiva: sigue en cerradas sin decidir y la retoma sale como hija abierta
        self.assertIn(f"cerradas sin decidir: 1: {p}", out)
        self.assertIn(f"NO raiz abiertas: 1: {h}", out)
        # cierre de una refutada (fallida): tambien admite la nota
        h2 = self.add("--tipo", "hipotesis", "--enunciado", "h2")
        c2 = self.add("--tipo", "resultado", "--enunciado", "f", "--ref", h2, "--estado", "fallida")
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", c2)

    def test_hija_no_juzga_a_una_prediccion(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        # una hipotesis nace propuesta: no puede llegar ya refutada ni soportada
        self.add("--tipo", "hipotesis", "--enunciado", "h", "--ref", p, "--estado", "refutada", ok=False)
        self.add("--tipo", "hipotesis", "--enunciado", "h", "--ref", p, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "en_disputa")
        # una hija sobre la prediccion juzgada no le cambia el estado (sigue en_disputa)
        self.add("--tipo", "prediccion", "--enunciado", "hija", "--criterio", "c", "--ref", p)
        self.add("--tipo", "hipotesis", "--enunciado", "h2", "--ref", p)
        self.assertIn("en_disputa", self.run_l("open").stdout)
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir")

    def test_nota_no_cambia_a_una_prediccion_enmendada(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        self.add("--tipo", "enmienda", "--enunciado", "a", "--ref", p, "--motivo", "m", "--criterio", "c2")
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", p)
        self.assertIn("enmendada", self.run_l("open").stdout)

    def test_enmienda_solo_de_predicciones(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "h")
        self.add("--tipo", "enmienda", "--enunciado", "e", "--ref", h, "--motivo", "m", ok=False)

    def test_sin_decidir_sin_veredicto_no_admite_juicio(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)

    def test_sin_decidir_solo_la_retoma_una_prediccion(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "h")
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", h, "--estado", "sin_decidir")
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", h, ok=False)
        self.add("--tipo", "hipotesis", "--enunciado", "h2", "--ref", h, ok=False)
        self.add("--tipo", "prediccion", "--enunciado", "retoma", "--criterio", "c", "--ref", h)

    def test_refutada_no_admite_hijas(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "h")
        self.add("--tipo", "resultado", "--enunciado", "r", "--ref", h, "--estado", "refutada")
        r = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c", "--ref", h, ok=False)
        self.assertEqual(r, "")
        self.add("--tipo", "hipotesis", "--enunciado", "h2", "--ref", h, ok=False)
        self.add("--tipo", "prediccion", "--enunciado", f"retoma {h}", "--criterio", "c")
        self.assertIn("refutadas/fallidas (permanentes): 1", self.run_l("open").stdout)

    def test_cadena_lineal_y_un_solo_veredicto(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        e1 = self.add("--tipo", "enmienda", "--enunciado", "e1", "--ref", p, "--motivo", "m", "--criterio", "c2")
        # enmienda hermana y veredicto sobre un eslabon superado: se rechazan
        self.add("--tipo", "enmienda", "--enunciado", "e2", "--ref", p, "--motivo", "m", "--criterio", "c3",
                 ok=False)
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "refutada", ok=False)
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", e1, "--estado", "en_disputa")
        # segundo veredicto: tampoco
        self.add("--tipo", "veredicto", "--enunciado", "v2", "--ref", e1, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)
        # tras en_disputa, el cierre sin_decidir si cabe (patron de C-301)
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir")

    def test_refutada_es_absorbente(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "h")
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c", "--ref", h)
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "refutada")
        # ni nota, ni soporte, ni hija, ni sin_decidir sobre la prediccion refutada (no raiz)
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", p, ok=False)
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c", ok=False)
        self.add("--tipo", "prediccion", "--enunciado", "p2", "--criterio", "c", "--ref", p, ok=False)
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir", ok=False)
        self.assertIn(f"hija juzgada: {p}", self.run_l("open").stdout)

    def test_sin_decidir_no_tras_veredicto_de_cierre(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "soportada",
                 "--ruta", "campaigns/audit.csv", "--cmd", "c")
        # definitiva: ni nota, ni otro juicio por resultado, ni sin_decidir; la precision va al veredicto
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", p, ok=False)
        self.add("--tipo", "resultado", "--enunciado", "r", "--ref", p, "--estado", "refutada", ok=False)
        self.add("--tipo", "resultado", "--enunciado", "s", "--ref", p, "--estado", "sin_decidir", ok=False)
        self.assertIn("afirmaciones abiertas: 0 de 1", self.run_l("open").stdout)

    def test_juicio_por_enmienda_cuenta_en_su_posicion(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        a = self.add("--tipo", "enmienda", "--enunciado", "a", "--ref", p, "--motivo", "m", "--criterio", "c2")
        self.add("--tipo", "resultado", "--enunciado", "nota", "--ref", p)   # antes del juicio
        v = self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", a, "--estado", "refutada")
        out = self.run_l("open").stdout
        self.assertIn("afirmaciones abiertas: 0 de 1", out)
        self.assertIn("refutadas/fallidas (permanentes): 1", out)
        for ref in (p, a):   # nada cuelga de la refutada ni de su enmienda
            self.add("--tipo", "prediccion", "--enunciado", "h", "--criterio", "c", "--ref", ref, ok=False)
        # la retoma via el veredicto si se acepta y open la lista como hija abierta
        h = self.add("--tipo", "prediccion", "--enunciado", "retoma", "--criterio", "c", "--ref", v)
        self.assertIn(f"NO raiz abiertas: 1: {h}", self.run_l("open").stdout)

    def test_nota_sobre_veredicto_no_lo_cambia(self):
        p = self.add("--tipo", "prediccion", "--enunciado", "p", "--criterio", "c")
        v = self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "refutada")
        self.add("--tipo", "resultado", "--enunciado", "precisa", "--ref", v)
        sys.path.insert(0, os.path.dirname(LEDGER))
        import ledger
        os.environ["RESEARCH_ROOT"] = self.d
        try:
            ev = ledger.load()
        finally:
            del os.environ["RESEARCH_ROOT"]
        self.assertEqual(ledger.current_state(v, ev), "refutada")
        self.assertEqual(ledger.current_state(p, ev), "refutada")

    def test_ws_fallido_exige_cierre_y_panel(self):
        self.run_l("ws-init", "WS-T", "--meta", "G1")
        self.run_l("ws-set", "WS-T", "ronda=1", "estado=fallido")
        r = self.run_l("check", ok=False)
        self.assertIn("cierre", r.stdout)
        self.assertIn("auditor-eaf3d", r.stdout)
        self.run_l("ws-set", "WS-T", "cierre=meta no cumplida", "revisor.auditor-eaf3d=aprueba",
                   "revisor.revisor-evidencia=aprueba", "revisor.revisor-refutador=aprueba")
        self.run_l("check")
        self.assertIn("meta no cumplida", self.run_l("open").stdout)

    def test_open_avisa_madre_con_hija_juzgada(self):
        h = self.add("--tipo", "hipotesis", "--enunciado", "madre")
        p = self.add("--tipo", "prediccion", "--enunciado", "hija", "--criterio", "c", "--ref", h)
        self.add("--tipo", "veredicto", "--enunciado", "v", "--ref", p, "--estado", "refutada")
        out = self.run_l("open").stdout
        self.assertIn("afirmaciones abiertas: 1 de 1", out)   # no se propaga (WS-K12)
        self.assertIn(f"hija juzgada: {p}", out)


if __name__ == "__main__":
    unittest.main()
