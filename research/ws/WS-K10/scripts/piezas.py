#!/usr/bin/env python3
"""Medida pre-registrada de WS-K10 (H10): media por paso, en el conjunto
multifase y en el gas libre, del error e y de cada pieza de su
descomposicion exacta
    e = err_liq + err_cc + err_art + A + Br1 + Br2 + Bgr + Bgq + Bx
(Br = Br1 + Br2 = densidad que cambia despues del ultimo Poisson), sobre las
filas step > 280000. Con dos bancos (dt 1 ms y dt 0.5 ms) imprime el cociente
de cada pieza con e y el cociente entre dt, y evalua el criterio de H10.

Uso: python3 research/ws/WS-K10/scripts/piezas.py [--sin-paso1] DIR_1MS DIR_05MS [DIR_LECTURA ...]

--sin-paso1 descarta la primera fila (paso 280001) de cada banco: con dt
0.5 ms es el transitorio del reinicio (el dt del snapshot se acota; C-206).
El veredicto pre-registrado de C-202 se juzga SIN esta opcion.
"""
import csv
import statistics as st
import sys

PIEZAS = [("err_liq", None), ("err_cc", "m_gas_err_cc_{c}"), ("err_art", "m_gas_err_art_{c}"),
          ("A", "m_gas_pa_{c}"), ("Br1", "m_gas_brho_it_{c}"), ("Br2", "m_gas_brho_end_{c}"),
          ("Bgr", "m_gas_bg_rho_{c}"), ("Bgq", "m_gas_bg_q_{c}"), ("Bx", "m_gas_bx_{c}")]


SALTO = 0


def medias(d, c):
    r = [x for x in csv.DictReader(open(f"{d}/audit.csv")) if int(x["step"]) > 280000][SALTO:]
    f = lambda col: st.mean(float(x[col]) for x in r)
    out = {"e": f(f"m_gas_err_{c}")}
    for nm, col in PIEZAS:
        if nm == "err_liq":
            out[nm] = f("m_gas_err_liq_all" if c == "multi" else "m_gas_err_liq_free")
        else:
            out[nm] = f(col.format(c=c))
    out["Br"] = out["Br1"] + out["Br2"]
    out["suma"] = sum(out[nm] for nm, _ in PIEZAS)
    out["store"] = f(f"m_gas_store_{c}")
    out["skip"] = sum(float(x["m_gas_dec_skip"]) for x in r)
    out["n"] = len(r)
    out["dt"] = st.mean(float(x["dt"]) for x in r)
    return out


def tabla(dirs, c):
    M = {d: medias(d, c) for d in dirs}
    nombres = ["e"] + [nm for nm, _ in PIEZAS] + ["Br", "suma", "store"]
    print(f"\n== {'multifase' if c == 'multi' else 'gas libre'}: media por paso [kg]")
    print("pieza    " + "".join(f"{d.split('/')[-1]:>14s}" for d in dirs)
          + "".join(f"{'/e ' + d.split('/')[-1]:>16s}" for d in dirs[:2]) + f"{'0.5ms/1ms':>12s}")
    for nm in nombres:
        fila = "".join(f"{M[d][nm]:+14.4e}" for d in dirs)
        rel = "".join(f"{M[d][nm] / M[d]['e']:+16.3f}" if M[d]["e"] else f"{'-':>16s}" for d in dirs[:2])
        q = M[dirs[1]][nm] / M[dirs[0]][nm] if M[dirs[0]][nm] else float("nan")
        print(f"{nm:8s}{fila}{rel}{q:+12.3f}")
    for d in dirs:
        print(f"  {d}: {M[d]['n']} filas, dt medio {M[d]['dt']:.4e}, pasos sin descomposicion {M[d]['skip']:.0f}")
    return M


if __name__ == "__main__":
    dirs = sys.argv[1:]
    if dirs and dirs[0] == "--sin-paso1":
        SALTO = 1
        dirs = dirs[1:]
        print("(sin el paso 280001 en cada banco)")
    Mm = tabla(dirs, "multi")
    tabla(dirs, "free")
    a, b = Mm[dirs[0]], Mm[dirs[1]]
    r1, r05 = a["Br"] / a["e"], b["Br"] / b["e"]
    q = b["Br"] / a["Br"] if a["Br"] else float("nan")
    print(f"\nH10 (C-pre): Br/e = {r1:.3f} (1 ms), {r05:.3f} (0.5 ms); Br(0.5)/Br(1) = {q:.3f}")
    sop = 0.5 <= r1 <= 1.5 and 0.5 <= r05 <= 1.5 and 0.75 <= q <= 1.33
    ref = (abs(a["Br"]) < 0.2 * abs(a["e"]) and abs(b["Br"]) < 0.2 * abs(b["e"])) or 0.35 <= q <= 0.65
    etiqueta = "lectura con --sin-paso1 (NO es el veredicto de C-202)" if SALTO else "veredicto por la letra"
    print(f"{etiqueta}:", "SOPORTADA" if sop else ("REFUTADA" if ref else "SIN DECIDIR"))
