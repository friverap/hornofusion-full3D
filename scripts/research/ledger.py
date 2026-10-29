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
ESTADOS = ("propuesta", "pre-registrada", "soportada", "refutada", "en_disputa", "fallida", "enmendada",
           "sin_decidir")
# sin_decidir: cierre de una afirmacion cuyo criterio dio la banda intermedia
# («sin decidir» por la letra), o de un resultado que solo registra ese «sin
# decidir» de otra prediccion; no es soporte, refutacion ni prueba fallida (WS-K12)
CERRADOS = ("soportada", "refutada", "fallida", "sin_decidir")
ESTADOS_VEREDICTO = ("soportada", "refutada", "fallida", "en_disputa")
# refutada y fallida son ABSORBENTES en una afirmacion (hipotesis, prediccion o
# resultado): ningun evento posterior la cita con --ref; quien retome la
# pregunta registra una afirmacion nueva que la cita en el enunciado (WS-K13)
PERMANENTES = ("refutada", "fallida")
# un cambio numerico solo pasa la compuerta con su prediccion JUZGADA en firme:
# en_disputa (y el sin_decidir que la cierra) o fallida no deciden (WS-K14)
FIRMES = ("soportada", "refutada")
AFIRMACIONES = ("hipotesis", "prediccion", "resultado")
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
    if t == "hipotesis" and e.get("estado") != "propuesta":
        err.append("una hipotesis nace 'propuesta': se juzga despues, con un resultado o una prediccion (WS-K13)")
    if t in ("veredicto", "enmienda"):
        ref = ids.get(e.get("ref"))
        if ref is None:
            err.append(f"'{t}' exige 'ref' a un evento previo (ref={e.get('ref')})")
    # la cadena de enmiendas es LINEAL: se enmienda y se juzga su punta (el criterio vigente)
    if t in ("veredicto", "enmienda") and e.get("ref") in ids and tiene_enmienda(e["ref"], ev):
        err.append(f"{e['ref']} ya tiene una enmienda: el {t} va sobre la ULTIMA enmienda de la cadena")
    if t == "veredicto":
        ref = ids.get(e.get("ref"))
        if ref is not None:
            raiz = raiz_enmienda(ref["id"], ids)
            if raiz.get("tipo") != "prediccion":
                err.append("un veredicto juzga una PREDICCION (o su enmienda)")
            elif juzgada(raiz["id"], ev):
                err.append(f"{raiz['id']} ya tiene veredicto: un segundo juicio va en una prediccion nueva")
        if e.get("estado") not in ESTADOS_VEREDICTO:
            err.append("un veredicto termina en soportada|refutada|fallida|en_disputa")
    if t == "enmienda":
        if not e.get("motivo"):
            err.append("una enmienda exige 'motivo'")
        ref = ids.get(e.get("ref"))
        if ref is not None and raiz_enmienda(ref["id"], ids).get("tipo") == "prediccion" and not e.get("criterio"):
            err.append("la enmienda de una prediccion trae el criterio NUEVO")
        raiz = raiz_enmienda(e.get("ref"), ids)
        if raiz.get("id") and raiz.get("tipo") != "prediccion":
            err.append("una enmienda cambia el criterio de una PREDICCION (o de su ultima enmienda)")
        elif raiz.get("id") and (juzgada(raiz["id"], ev) or current_state(raiz["id"], ev) in CERRADOS):
            err.append("no se enmienda una afirmacion ya juzgada o cerrada: registrar una prediccion nueva")
    # un CIERRE (resultado refutada, fallida o sin_decidir con --ref) es el sitio de las precisiones y
    # retomas: no reabre a la afirmacion que cierra, asi que solo admite una nota o una retoma (WS-K13)
    ref0 = ids.get(e.get("ref"), {})
    if ref0.get("tipo") == "resultado" and ref0.get("ref") and ref0.get("estado") in PERMANENTES + ("sin_decidir",):
        if not (t in ("prediccion", "hipotesis") or (t == "resultado" and e.get("estado") == "propuesta")):
            err.append(f"{ref0['id']} es un cierre: solo admite una nota (resultado propuesta) o una retoma")
        base = {}
    else:
        # lo que cita una enmienda cita a su prediccion: las reglas miran la raiz de la cadena
        base = raiz_enmienda(e.get("ref"), ids) if e.get("ref") in ids else {}
    if base.get("tipo") in AFIRMACIONES and current_state(base["id"], ev) in PERMANENTES:
        err.append(f"{base['id']} esta {current_state(base['id'], ev)} (permanente): nada la cita con --ref "
                   "(ni a sus enmiendas); la retoma va sin --ref o con --ref a su VEREDICTO")
    elif base.get("tipo") == "prediccion" and (current_state(base["id"], ev) in CERRADOS or any(
            v["estado"] != "en_disputa" for v in veredictos(base["id"], ev))):
        err.append(f"{base['id']} es una prediccion cerrada ({current_state(base['id'], ev)}): es definitiva; "
                   "una precision o una retoma van con --ref a su veredicto o a su cierre")
    elif base.get("id") and current_state(base["id"], ev) == "sin_decidir" and t != "prediccion":
        err.append(f"{base['id']} esta cerrada sin_decidir: solo la retoma una PREDICCION nueva "
                   "(una nota va con --ref a su cierre)")
    if t == "resultado" and base.get("tipo") == "prediccion":
        if e.get("estado") not in ("propuesta", "sin_decidir"):
            err.append("una prediccion se juzga con un VEREDICTO: un resultado sobre ella (o su enmienda) es una "
                       "nota (propuesta) o un cierre sin_decidir")
        elif e.get("estado") == "propuesta" and juzgada(base["id"], ev):
            err.append(f"{base['id']} ya tiene veredicto: una nota va con --ref al VEREDICTO")
    if e.get("estado") == "sin_decidir":
        ref = ids.get(e.get("ref"))
        if t != "resultado" or ref is None:
            err.append("'sin_decidir' solo cierra con un resultado cuya --ref es un evento previo")
        elif ref.get("tipo") in ("veredicto", "enmienda"):
            err.append("'sin_decidir' cierra la afirmacion (hipotesis, prediccion o resultado), "
                       "no un veredicto ni una enmienda")
        elif current_state(ref["id"], ev) in CERRADOS:
            err.append(f"'sin_decidir': {ref['id']} ya esta cerrada ({current_state(ref['id'], ev)})")
        elif any(v["estado"] != "en_disputa" for v in veredictos(ref["id"], ev)):
            err.append(f"'sin_decidir': {ref['id']} tiene un veredicto de cierre; solo cabe tras uno en_disputa")
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
    """Estado vigente: el del ultimo veredicto/resultado/enmienda que lo referencia.

    Una enmienda ya juzgada cede al estado de su juicio: la prediccion juzgada a
    traves de su enmienda toma el estado de ese veredicto (WS-K13). El veredicto
    de una prediccion HIJA no se propaga a la madre: la madre se cierra con un
    resultado propio (regla de WS-K12).
    """
    yo = next(x for x in ev if x["id"] == eid)
    if yo["tipo"] == "veredicto":
        return yo["estado"]   # un veredicto es un juicio: las notas que lo citan no lo cambian (WS-K13)
    st, cadena = yo["estado"], cadena_enmiendas(eid, ev)
    for x in ev:   # en el orden del registro: cada juicio cuenta en SU posicion
        if x.get("ref") == eid and yo["tipo"] == "prediccion" and (
                x["tipo"] in ("prediccion", "hipotesis") or (x["tipo"] == "resultado" and x["estado"] == "propuesta")):
            continue   # ni una hija ni una nota cambian el estado de una PREDICCION: la juzga su veredicto (WS-K13)
        if x.get("ref") == eid:
            st = "enmendada" if x["tipo"] == "enmienda" else x["estado"]
        elif x.get("tipo") == "veredicto" and x.get("ref") in cadena:
            st = x["estado"]   # veredicto sobre una enmienda de la cadena (WS-K13)
    return st


def raiz_enmienda(eid, ids):
    """Sube por la cadena de enmiendas hasta el evento enmendado (la prediccion)."""
    x = ids.get(eid, {})
    while x.get("tipo") == "enmienda":
        x = ids.get(x.get("ref"), {})
    return x


def tiene_enmienda(eid, ev):
    return any(x.get("tipo") == "enmienda" and x.get("ref") == eid for x in ev)


def cadena_enmiendas(pid, ev):
    """Ids de las enmiendas de `pid`, enmiendas de enmiendas incluidas (sin `pid`)."""
    cadena, front = set(), {pid}
    while front:
        front = {x["id"] for x in ev if x.get("tipo") == "enmienda" and x.get("ref") in front} - cadena
        cadena |= front
    return cadena


def veredictos(pid, ev):
    """Veredictos sobre la prediccion `pid` o sobre CUALQUIER enmienda de su cadena."""
    cadena = cadena_enmiendas(pid, ev) | {pid}
    return [x for x in ev if x.get("tipo") == "veredicto" and x.get("ref") in cadena]


def juzgada(pid, ev):
    """La prediccion `pid` tiene veredicto, directo o sobre una enmienda de su cadena."""
    return bool(veredictos(pid, ev))


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
        hijas = [y["id"] for y in ev if y.get("ref") == x["id"] and y["tipo"] == "prediccion"
                 and current_state(y["id"], ev) in CERRADOS]
        nota = f" (hija juzgada: {', '.join(hijas)}; cerrar la madre con un resultado)" if hijas else ""
        print(f"  {x['id']} [{x['ws']}] {s:14s} {x['enunciado'][:90]}{nota}")
    hijas_ab = [x["id"] for x in ev if x.get("ref") and x["tipo"] in ("prediccion", "hipotesis")
                and current_state(x["id"], ev) not in CERRADOS]
    if hijas_ab:
        print(f"predicciones/hipotesis NO raiz abiertas: {len(hijas_ab)}: " + ", ".join(hijas_ab))
    refut = [x for x in raices if current_state(x["id"], ev) in ("refutada", "fallida")]
    if refut:
        print(f"refutadas/fallidas (permanentes): {len(refut)}; ultimas:")
        for x in refut[-5:]:
            print(f"  {x['id']} [{x['ws']}] {x['enunciado'][:90]}")
    # por el estado VIGENTE de la ref: una retomada con una prediccion nueva ya no cuenta (WS-K13)
    sind = list(dict.fromkeys(x["ref"] for x in ev if x.get("estado") == "sin_decidir"
                              and current_state(x["ref"], ev) == "sin_decidir"))
    if sind:
        print(f"cerradas sin decidir: {len(sind)}: " + ", ".join(sind))
    for ws in all_ws():
        st = ws_status(ws) or {}
        cierre = f"; {st['cierre']}" if st.get("cierre") else ""
        print(f"workstream {ws}: {st.get('estado', '?')} (meta {st.get('meta', '?')}, ronda {st.get('ronda', 0)}{cierre})")


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
        if st and st.get("estado") == "fallido":
            # fallido = cierre APROBADO por el panel con la meta no cumplida (WS-K13)
            if not str(st.get("cierre") or "").strip():
                err.append(f"{ws}: fallido sin la clave 'cierre' (motivo en una linea)")
            for r in REVISORES:
                v = (st.get("revisores") or {}).get(r)
                if not v or v.get("veredicto") != "aprueba" or v.get("ronda") != st.get("ronda"):
                    err.append(f"{ws}: fallido sin la aprobacion de {r} en la ronda {st.get('ronda')}")
    if err:
        print("\n".join(err))
        sys.exit(1)
    print(f"ledger OK ({len(ev)} eventos, {len(all_ws())} workstreams)")


# rutas cuyo diff staged ata la aprobacion del panel (las mismas que vigila guard_cierre.sh)
GATED = ("src", "tests", "scripts/research", ".claude/hooks", ".claude/workflows", ".claude/agents",
         ".claude/settings.json")


def staged_sha():
    out = subprocess.run(["git", "diff", "--cached", "--", *GATED], capture_output=True,
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
        e.append("diff_sha no coincide con el diff staged de " + ", ".join(GATED)
                 + " (la aprobacion es de OTRO diff)")
    if st.get("test_quick") != "ok" or st.get("test_quick_sha") != sha:
        e.append("falta test_quick=ok sobre este diff")
    ronda = st.get("ronda")
    for r in REVISORES:
        v = (st.get("revisores") or {}).get(r)
        if not v or v.get("veredicto") != "aprueba" or v.get("ronda") != ronda:
            e.append(f"{r} no aprueba en la ronda {ronda}")
    if st.get("numerico"):
        pid = st.get("prediccion")
        vs = veredictos(pid, ev) if pid else []
        if not vs:
            e.append("cambio numerico sin prediccion pre-registrada juzgada")
        elif vs[-1]["estado"] not in FIRMES:
            e.append(f"la prediccion {pid} tiene veredicto '{vs[-1]['estado']}' (se exige "
                     + " o ".join(FIRMES) + ")")
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
