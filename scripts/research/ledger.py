#!/usr/bin/env python3
"""Registro de afirmaciones del harness co-investigador (research/ledger.jsonl).

Replica el seguimiento de incertidumbre de *AI co-mathematician* (Zheng et
al. 2026, arXiv 2605.06651, §2): cada hipotesis, prediccion, resultado y
veredicto es un evento append-only con evidencia reproducible; los fracasos
nunca se borran. Anadido propio: PRE-REGISTRO (una prediccion lleva un
criterio numerico congelado; el veredicto se juzga contra ese texto y
cambiarlo exige una enmienda explicita con motivo).

Uso:
  ledger.py add --tipo T --ws WS --enunciado TXT --autor A [--estado E]
                [--criterio TXT] [--ref C-nnn] [--motivo TXT]
                [--ruta P ...] [--cmd TXT] [--refuta-si TXT]
  ledger.py show C-nnn          historia de una afirmacion
  ledger.py open                afirmaciones abiertas + workstreams
  ledger.py check               reglas del registro (exit 1 si falla)
  ledger.py ws-init WS --meta G [--numerico]
  ledger.py ws-set WS clave=valor ...   (diff_sha=auto calcula el del staged)
  ledger.py gate [WS]           compuerta de cierre del diff STAGED (exit 1 si falla)

Raiz: $RESEARCH_ROOT o la raiz del repo git.
"""
import argparse, datetime, glob, hashlib, json, os, subprocess, sys

TIPOS = ("hipotesis", "prediccion", "resultado", "veredicto", "enmienda")
ESTADOS = ("propuesta", "pre-registrada", "soportada", "refutada", "en_disputa", "fallida", "enmendada")
CERRADOS = ("soportada", "refutada", "fallida")
REVISORES = ("auditor-eaf3d", "revisor-evidencia", "revisor-refutador")
WS_ESTADOS = ("abierto", "en_revision", "aprobado", "sin_terminar", "fallido")


def root():
    r = os.environ.get("RESEARCH_ROOT")
    if r:
        return r
    try:
        return subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                              text=True, check=True).stdout.strip()
    except Exception:
        return os.getcwd()


def lpath():
    return os.path.join(root(), "research", "ledger.jsonl")


def load():
    p = lpath()
    if not os.path.exists(p):
        return []
    ev = []
    with open(p) as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                ev.append(json.loads(line))
            except json.JSONDecodeError as e:
                sys.exit(f"ledger.jsonl linea {n}: JSON invalido ({e})")
    return ev


def next_id(ev):
    n = max([int(e["id"][2:]) for e in ev if str(e.get("id", "")).startswith("C-")] + [0])
    return f"C-{n + 1:03d}"


def validate(e, ev):
    """Errores de UN evento contra el registro previo `ev`."""
    err = []
    for k in ("id", "ts", "tipo", "ws", "enunciado", "estado", "autor"):
        if not e.get(k):
            err.append(f"falta '{k}'")
    if e.get("tipo") not in TIPOS:
        err.append(f"tipo '{e.get('tipo')}' no es uno de {TIPOS}")
    if e.get("estado") not in ESTADOS:
        err.append(f"estado '{e.get('estado')}' no es uno de {ESTADOS}")
    ids = {x["id"]: x for x in ev}
    t = e.get("tipo")
    if t == "prediccion":
        if not e.get("criterio"):
            err.append("una prediccion exige 'criterio' (numerico, congelado)")
        if e.get("estado") != "pre-registrada":
            err.append("una prediccion nace 'pre-registrada'")
    if t in ("veredicto", "enmienda"):
        ref = ids.get(e.get("ref"))
        if ref is None:
            err.append(f"'{t}' exige 'ref' a un evento previo (ref={e.get('ref')})")
    if t == "veredicto":
        ref = ids.get(e.get("ref"))
        if ref is not None:
            raiz = ref
            while raiz.get("tipo") == "enmienda":
                raiz = ids.get(raiz.get("ref"), {})
            if raiz.get("tipo") != "prediccion":
                err.append("un veredicto juzga una PREDICCION (o su enmienda)")
        if e.get("estado") not in CERRADOS + ("en_disputa",):
            err.append("un veredicto termina en soportada|refutada|fallida|en_disputa")
    if t == "enmienda":
        if not e.get("motivo"):
            err.append("una enmienda exige 'motivo'")
        ref = ids.get(e.get("ref"))
        if ref is not None and ref.get("tipo") == "prediccion" and not e.get("criterio"):
            err.append("la enmienda de una prediccion trae el criterio NUEVO")
        if any(x.get("tipo") == "veredicto" and x.get("ref") == e.get("ref") for x in ev):
            err.append("no se enmienda una prediccion ya juzgada: registrar una prediccion nueva")
    if e.get("estado") == "soportada":
        evd = e.get("evidencia") or {}
        if not evd.get("rutas") or not evd.get("cmd"):
            err.append("'soportada' exige evidencia con rutas y comando de reproduccion")
    return err


def now():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def cmd_add(a):
    ev = load()
    e = {"id": next_id(ev), "ts": now(), "tipo": a.tipo, "ws": a.ws, "enunciado": a.enunciado,
         "autor": a.autor,
         "estado": a.estado or {"prediccion": "pre-registrada"}.get(a.tipo, "propuesta")}
    for k in ("criterio", "ref", "motivo"):
        if getattr(a, k):
            e[k] = getattr(a, k)
    if a.refuta_si:
        e["refuta_si"] = a.refuta_si
    if a.ruta or a.cmd:
        e["evidencia"] = {"rutas": a.ruta or [], "cmd": a.cmd or ""}
    err = validate(e, ev)
    if e.get("estado") == "soportada":
        err += [f"ruta inexistente: {r}" for r in e["evidencia"]["rutas"]
                if not os.path.exists(os.path.join(root(), r))]
    if err:
        sys.exit("RECHAZADO: " + "; ".join(err))
    os.makedirs(os.path.dirname(lpath()), exist_ok=True)
    with open(lpath(), "a") as f:
        f.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(e["id"])


def current_state(eid, ev):
    """Estado vigente: el del ultimo veredicto/resultado/enmienda que lo referencia."""
    st = next(x for x in ev if x["id"] == eid)["estado"]
    for x in ev:
        if x.get("ref") == eid:
            st = "enmendada" if x["tipo"] == "enmienda" else x["estado"]
    return st


def cmd_show(a):
    ev = load()
    chain, front = [], {a.id}
    for x in ev:
        if x["id"] in front or x.get("ref") in front:
            chain.append(x)
            front.add(x["id"])
    if not chain:
        sys.exit(f"{a.id} no existe")
    for x in chain:
        print(json.dumps(x, ensure_ascii=False, indent=1))


def ws_dir(ws):
    return os.path.join(root(), "research", "ws", ws)


def ws_status(ws):
    p = os.path.join(ws_dir(ws), "status.json")
    return json.load(open(p)) if os.path.exists(p) else None


def all_ws():
    return sorted(os.path.basename(d) for d in glob.glob(os.path.join(root(), "research", "ws", "*"))
                  if os.path.isdir(d))


def cmd_open(a):
    ev = load()
    raices = [x for x in ev if not x.get("ref")]
    abiertas = [(x, current_state(x["id"], ev)) for x in raices]
    abiertas = [(x, s) for x, s in abiertas if s not in CERRADOS]
    print(f"afirmaciones abiertas: {len(abiertas)} de {len(raices)}")
    for x, s in abiertas:
        print(f"  {x['id']} [{x['ws']}] {s:14s} {x['enunciado'][:90]}")
    refut = [x for x in raices if current_state(x["id"], ev) in ("refutada", "fallida")]
    if refut:
        print(f"refutadas/fallidas (permanentes): {len(refut)}; ultimas:")
        for x in refut[-5:]:
            print(f"  {x['id']} [{x['ws']}] {x['enunciado'][:90]}")
    for ws in all_ws():
        st = ws_status(ws) or {}
        print(f"workstream {ws}: {st.get('estado', '?')} (meta {st.get('meta', '?')}, ronda {st.get('ronda', 0)})")


def cmd_check(a):
    ev, prev, err = load(), [], []
    seen = set()
    for x in ev:
        if x.get("id") in seen:
            err.append(f"{x.get('id')}: id duplicado")
        seen.add(x.get("id"))
        err += [f"{x.get('id')}: {m}" for m in validate(x, prev)]
        prev.append(x)
    for i in range(1, len(ev)):
        if ev[i]["ts"] < ev[i - 1]["ts"]:
            err.append(f"{ev[i]['id']}: ts anterior al evento previo (el registro es append-only)")
    for ws in all_ws():
        st = ws_status(ws)
        if st and st.get("estado") not in WS_ESTADOS:
            err.append(f"{ws}: estado '{st.get('estado')}' invalido")
    if err:
        print("\n".join(err))
        sys.exit(1)
    print(f"ledger OK ({len(ev)} eventos, {len(all_ws())} workstreams)")


def staged_sha():
    out = subprocess.run(["git", "diff", "--cached", "--", "src", "tests"], capture_output=True,
                         cwd=root()).stdout
    return hashlib.sha256(out).hexdigest()


def cmd_ws_init(a):
    d = ws_dir(a.ws)
    if os.path.exists(os.path.join(d, "status.json")):
        sys.exit(f"{a.ws} ya existe")
    os.makedirs(os.path.join(d, "reviews"), exist_ok=True)
    st = {"ws": a.ws, "meta": a.meta, "estado": "abierto", "ronda": 0, "numerico": a.numerico,
          "prediccion": None, "diff_sha": None, "test_quick": None,
          "revisores": {r: None for r in REVISORES}, "creado": now()}
    json.dump(st, open(os.path.join(d, "status.json"), "w"), indent=1, ensure_ascii=False)
    print(d)


def cmd_ws_set(a):
    st = ws_status(a.ws)
    if st is None:
        sys.exit(f"{a.ws} no existe (ws-init)")
    for kv in a.kv:
        k, _, v = kv.partition("=")
        if k == "diff_sha" and v == "auto":
            v = staged_sha()
        if k.startswith("revisor."):
            r = k.split(".", 1)[1]
            if r not in REVISORES:
                sys.exit(f"revisor desconocido {r}")
            st["revisores"][r] = {"veredicto": v, "ronda": st.get("ronda", 0)}
            continue
        if k == "test_quick":
            st["test_quick_sha"] = staged_sha()   # el ok vale solo para ESTE diff
        if k == "ronda":
            v = int(v)
        if k == "numerico":
            v = v.lower() in ("1", "true", "si")
        if k == "estado" and v not in WS_ESTADOS:
            sys.exit(f"estado {v} invalido")
        st[k] = v
    st["actualizado"] = now()
    json.dump(st, open(os.path.join(ws_dir(a.ws), "status.json"), "w"), indent=1, ensure_ascii=False)


def gate_errors(st, sha, ev):
    e = []
    if st.get("estado") != "aprobado":
        e.append(f"estado '{st.get('estado')}' (se exige 'aprobado')")
    if st.get("diff_sha") != sha:
        e.append("diff_sha no coincide con el diff staged de src/ y tests/ (la aprobacion es de OTRO diff)")
    if st.get("test_quick") != "ok" or st.get("test_quick_sha") != sha:
        e.append("falta test_quick=ok sobre este diff")
    ronda = st.get("ronda")
    for r in REVISORES:
        v = (st.get("revisores") or {}).get(r)
        if not v or v.get("veredicto") != "aprueba" or v.get("ronda") != ronda:
            e.append(f"{r} no aprueba en la ronda {ronda}")
    if st.get("numerico"):
        pid = st.get("prediccion")
        if not pid or not any(x.get("tipo") == "veredicto" and x.get("ref") in
                              {pid} | {y["id"] for y in ev if y.get("tipo") == "enmienda" and y.get("ref") == pid}
                              for x in ev):
            e.append("cambio numerico sin prediccion pre-registrada juzgada")
    return e


def cmd_gate(a):
    sha, ev = staged_sha(), load()
    cands = [a.ws] if a.ws else all_ws()
    report = []
    for ws in cands:
        st = ws_status(ws)
        if st is None:
            report.append(f"{ws}: no existe")
            continue
        e = gate_errors(st, sha, ev)
        if not e:
            print(f"compuerta OK: {ws}")
            return
        report.append(f"{ws}: " + "; ".join(e))
    print("compuerta CERRADA:\n  " + ("\n  ".join(report) if report else "ningun workstream"))
    sys.exit(1)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest="cmd", required=True)
    q = s.add_parser("add")
    q.add_argument("--tipo", required=True, choices=TIPOS)
    q.add_argument("--ws", required=True)
    q.add_argument("--enunciado", required=True)
    q.add_argument("--autor", required=True)
    q.add_argument("--estado", choices=ESTADOS)
    q.add_argument("--criterio"); q.add_argument("--ref"); q.add_argument("--motivo")
    q.add_argument("--refuta-si", dest="refuta_si")
    q.add_argument("--ruta", action="append"); q.add_argument("--cmd")
    q.set_defaults(f=cmd_add)
    q = s.add_parser("show"); q.add_argument("id"); q.set_defaults(f=cmd_show)
    s.add_parser("open").set_defaults(f=cmd_open)
    s.add_parser("check").set_defaults(f=cmd_check)
    q = s.add_parser("ws-init"); q.add_argument("ws"); q.add_argument("--meta", required=True)
    q.add_argument("--numerico", action="store_true"); q.set_defaults(f=cmd_ws_init)
    q = s.add_parser("ws-set"); q.add_argument("ws"); q.add_argument("kv", nargs="+"); q.set_defaults(f=cmd_ws_set)
    q = s.add_parser("gate"); q.add_argument("ws", nargs="?"); q.set_defaults(f=cmd_gate)
    a = p.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
